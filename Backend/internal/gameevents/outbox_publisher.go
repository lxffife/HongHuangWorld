package gameevents

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/nats-io/nats.go"
)

const (
	streamName = "HONGHUANG_GAME_EVENTS"
	subject    = "honghuang.game.events.v1"
	batchSize  = 64
)

type OutboxEvent struct {
	Sequence  int64
	ID        string
	EventType string
	Payload   []byte
	Attempts  int
}

// RunOutboxPublisher continuously drains Game's PostgreSQL outbox to JetStream.
// It is deliberately best-effort at startup: Game HTTP and simulation APIs do
// not depend on NATS being available. Unpublished rows remain durable in Postgres.
func RunOutboxPublisher(ctx context.Context, db *sql.DB, logger *slog.Logger) {
	url := strings.TrimSpace(os.Getenv("GAME_NATS_URL"))
	if url == "" {
		url = strings.TrimSpace(os.Getenv("NATS_URL"))
	}
	if url == "" {
		logger.Warn("Game event publisher disabled: GAME_NATS_URL/NATS_URL is empty")
		return
	}

	var conn *nats.Conn
	var js nats.JetStreamContext
	for {
		if ctx.Err() != nil {
			return
		}
		if conn == nil || conn.IsClosed() {
			var err error
			conn, err = nats.Connect(url,
				nats.Name("honghuang-game-event-publisher"),
				nats.Timeout(3*time.Second),
				nats.RetryOnFailedConnect(true),
				nats.MaxReconnects(-1),
				nats.ReconnectWait(2*time.Second),
			)
			if err != nil {
				logger.Warn("Game event publisher cannot connect to NATS; will retry", "error", err)
				if !wait(ctx, 5*time.Second) {
					return
				}
				continue
			}
			js, err = conn.JetStream()
			if err == nil {
				err = ensureStream(js)
			}
			if err != nil {
				logger.Error("Game JetStream setup failed; outbox will remain pending", "error", err)
				conn.Close()
				conn = nil
				js = nil
				if !wait(ctx, 5*time.Second) {
					return
				}
				continue
			}
			logger.Info("Game domain event publisher connected", "stream", streamName, "subject", subject)
		}

		events, err := claimBatch(ctx, db, publisherID(), batchSize, time.Minute)
		if err != nil {
			logger.Error("claim Game event outbox failed", "error", err)
			if !wait(ctx, 3*time.Second) {
				break
			}
			continue
		}
		if len(events) == 0 {
			if !wait(ctx, time.Second) {
				break
			}
			continue
		}

		for _, event := range events {
			if ctx.Err() != nil {
				break
			}
			_, publishErr := js.Publish(subject, event.Payload, nats.MsgId(event.ID))
			if publishErr != nil {
				retryErr := retryEvent(ctx, db, publisherID(), event, publishErr)
				logger.Warn("Game event publish failed; durable retry scheduled",
					"event_id", event.ID, "event_type", event.EventType,
					"attempts", event.Attempts, "publish_error", publishErr, "retry_error", retryErr)
				if conn.IsClosed() {
					conn = nil
					js = nil
					break
				}
				continue
			}
			if err := markPublished(ctx, db, publisherID(), event.ID); err != nil {
				// JetStream may already have accepted this event. Keep the lease;
				// retry uses the same MsgId and is deduplicated by JetStream.
				logger.Error("mark Game event published failed; lease will expire",
					"event_id", event.ID, "error", err)
			}
		}
	}
	if conn != nil {
		_ = conn.FlushTimeout(time.Second)
		conn.Close()
	}
}

func ensureStream(js nats.JetStreamContext) error {
	info, err := js.StreamInfo(streamName)
	if err == nil {
		for _, configured := range info.Config.Subjects {
			if configured == subject {
				return nil
			}
		}
		return fmt.Errorf("existing stream %s does not capture %s", streamName, subject)
	}
	_, err = js.AddStream(&nats.StreamConfig{
		Name: streamName, Subjects: []string{subject},
		Retention: nats.LimitsPolicy, Storage: nats.FileStorage,
		Discard: nats.DiscardOld, MaxAge: 30 * 24 * time.Hour,
		Duplicates: 10 * time.Minute, Replicas: 1,
	})
	if err == nil {
		return nil
	}
	info, inspectErr := js.StreamInfo(streamName)
	if inspectErr == nil {
		for _, configured := range info.Config.Subjects {
			if configured == subject {
				return nil
			}
		}
	}
	return fmt.Errorf("create or inspect stream %s: %w", streamName, err)
}

func claimBatch(ctx context.Context, db *sql.DB, worker string, limit int, lease time.Duration) ([]OutboxEvent, error) {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx, `
		WITH picked AS (
			SELECT event_sequence
			FROM game_event_outbox
			WHERE published_at IS NULL
			  AND next_attempt_at <= now()
			  AND (locked_until IS NULL OR locked_until < now())
			ORDER BY event_sequence
			LIMIT $1
			FOR UPDATE SKIP LOCKED
		)
		UPDATE game_event_outbox AS outbox
		SET locked_by=$2, locked_until=now()+$3::interval, attempts=attempts+1
		FROM picked
		WHERE outbox.event_sequence=picked.event_sequence
		RETURNING outbox.event_sequence,outbox.event_id::text,outbox.event_type,
		          outbox.payload::text,outbox.attempts
	`, limit, worker, lease.String())
	if err != nil {
		return nil, fmt.Errorf("claim rows: %w", err)
	}
	defer rows.Close()

	events := make([]OutboxEvent, 0, limit)
	for rows.Next() {
		var event OutboxEvent
		var payload string
		if err := rows.Scan(&event.Sequence, &event.ID, &event.EventType, &payload, &event.Attempts); err != nil {
			return nil, err
		}
		event.Payload = []byte(payload)
		if !json.Valid(event.Payload) {
			return nil, fmt.Errorf("outbox event %s contains invalid JSON", event.ID)
		}
		events = append(events, event)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.Slice(events, func(i, j int) bool { return events[i].Sequence < events[j].Sequence })
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return events, nil
}

func markPublished(ctx context.Context, db *sql.DB, worker, eventID string) error {
	result, err := db.ExecContext(ctx, `
		UPDATE game_event_outbox
		SET published_at=now(),locked_until=NULL,locked_by=NULL,last_error=NULL
		WHERE event_id=$1::uuid AND locked_by=$2 AND published_at IS NULL
	`, eventID, worker)
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if count != 1 {
		return errors.New("outbox lease lost before publish acknowledgement")
	}
	return nil
}

func retryEvent(ctx context.Context, db *sql.DB, worker string, event OutboxEvent, publishErr error) error {
	exponent := event.Attempts - 1
	if exponent < 0 {
		exponent = 0
	}
	if exponent > 8 {
		exponent = 8
	}
	delay := time.Duration(1<<exponent) * time.Second
	_, err := db.ExecContext(ctx, `
		UPDATE game_event_outbox
		SET next_attempt_at=now()+$3::interval,locked_until=NULL,locked_by=NULL,last_error=$4
		WHERE event_id=$1::uuid AND locked_by=$2 AND published_at IS NULL
	`, event.ID, worker, delay.String(), truncateError(publishErr.Error(), 2000))
	return err
}

func publisherID() string {
	host, _ := os.Hostname()
	if host == "" {
		host = "unknown"
	}
	return fmt.Sprintf("%s-%d", host, os.Getpid())
}

func truncateError(value string, max int) string {
	if len(value) <= max {
		return value
	}
	return value[:max]
}

func wait(ctx context.Context, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
