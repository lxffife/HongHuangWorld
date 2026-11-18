package chatprojection

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"

	"github.com/nats-io/nats.go"
)

const (
	gameStream  = "HONGHUANG_GAME_EVENTS"
	gameSubject = "honghuang.game.events.v1"
)

type envelope struct {
	Version          int             `json:"version"`
	EventID          string          `json:"event_id"`
	EventType        string          `json:"event_type"`
	AggregateID      string          `json:"aggregate_id"`
	AggregateVersion int64           `json:"aggregate_version"`
	OccurredAt       time.Time       `json:"occurred_at"`
	Data             json.RawMessage `json:"data"`
}

type characterData struct {
	CharacterID string `json:"character_id"`
	AccountID   string `json:"account_id"`
	Name        string `json:"name"`
	RaceID      string `json:"race_id"`
	Level       int    `json:"level"`
	WorldID     string `json:"world_id"`
	Status      string `json:"status"`
}

type accountCharacterData struct {
	AccountID          string  `json:"account_id"`
	CurrentCharacterID *string `json:"current_character_id"`
}

type worldInstanceData struct {
	InstanceID string `json:"instance_id"`
	WorldID    string `json:"world_id"`
	NodeKey    string `json:"node_key"`
	Status     string `json:"status"`
}

type serverNodeData struct {
	NodeKey         string     `json:"node_key"`
	Status          string     `json:"status"`
	LastHeartbeatAt *time.Time `json:"last_heartbeat_at"`
}

type worldSessionData struct {
	SessionID     string     `json:"session_id"`
	CharacterID   string     `json:"character_id"`
	InstanceID    string     `json:"instance_id"`
	NodeKey       string     `json:"node_key"`
	SessionState  string     `json:"session_state"`
	DisconnectedAt *time.Time `json:"disconnected_at"`
}

// Run consumes Game domain events and maintains Chat-owned routing projections.
// It only connects to the separate Chat database supplied by the caller.
func Run(ctx context.Context, db *sql.DB, logger *slog.Logger) {
	url := strings.TrimSpace(os.Getenv("GAME_NATS_URL"))
	if url == "" {
		url = strings.TrimSpace(os.Getenv("NATS_URL"))
	}
	if url == "" {
		logger.Warn("Game projection consumer disabled: GAME_NATS_URL/NATS_URL is empty")
		return
	}
	durable := strings.TrimSpace(os.Getenv("CHAT_GAME_PROJECTION_DURABLE"))
	if durable == "" {
		durable = "CHAT_GAME_PROJECTION"
	}

	for ctx.Err() == nil {
		conn, err := nats.Connect(url,
			nats.Name("honghuang-chat-game-projection"),
			nats.Timeout(3*time.Second),
			nats.RetryOnFailedConnect(true),
			nats.MaxReconnects(-1),
			nats.ReconnectWait(2*time.Second),
		)
		if err != nil {
			logger.Warn("Game projection consumer cannot connect to NATS; will retry", "error", err)
			if !wait(ctx, 5*time.Second) {
				return
			}
			continue
		}

		js, err := conn.JetStream()
		if err == nil {
			err = ensureConsumer(js, durable)
		}
		var sub *nats.Subscription
		if err == nil {
			sub, err = js.PullSubscribe(gameSubject, durable,
				nats.BindStream(gameStream), nats.AckExplicit())
		}
		if err != nil {
			logger.Warn("Game projection JetStream setup failed; will retry", "error", err)
			conn.Close()
			if !wait(ctx, 5*time.Second) {
				return
			}
			continue
		}

		logger.Info("Chat Game projection consumer ready", "stream", gameStream, "subject", gameSubject, "consumer", durable)
		consume(ctx, sub, db, logger)
		_ = sub.Unsubscribe()
		_ = conn.FlushTimeout(time.Second)
		conn.Close()
		if ctx.Err() == nil {
			logger.Warn("Game projection consumer stopped; reconnecting")
			if !wait(ctx, 2*time.Second) {
				return
			}
		}
	}
}

func ensureConsumer(js nats.JetStreamContext, durable string) error {
	if _, err := js.ConsumerInfo(gameStream, durable); err == nil {
		return nil
	}
	_, err := js.AddConsumer(gameStream, &nats.ConsumerConfig{
		Durable: durable,
		AckPolicy: nats.AckExplicitPolicy,
		DeliverPolicy: nats.DeliverAllPolicy,
		FilterSubject: gameSubject,
		AckWait: 30 * time.Second,
		MaxAckPending: 128,
		MaxDeliver: -1,
	})
	if err == nil {
		return nil
	}
	if _, inspectErr := js.ConsumerInfo(gameStream, durable); inspectErr == nil {
		return nil
	}
	return fmt.Errorf("create or inspect Game projection consumer %s: %w", durable, err)
}

func consume(ctx context.Context, sub *nats.Subscription, db *sql.DB, logger *slog.Logger) {
	for ctx.Err() == nil {
		messages, err := sub.Fetch(32, nats.MaxWait(2*time.Second))
		if err != nil {
			if errors.Is(err, nats.ErrTimeout) {
				continue
			}
			logger.Warn("fetch Game projection events failed", "error", err)
			if !wait(ctx, time.Second) {
				return
			}
			continue
		}
		for _, msg := range messages {
			var event envelope
			if err := json.Unmarshal(msg.Data, &event); err != nil || !validEnvelope(event) {
				logger.Error("terminating invalid Game domain event", "error", err)
				if termErr := msg.Term(); termErr != nil {
					logger.Warn("terminate invalid Game domain event failed", "error", termErr)
				}
				continue
			}
			if err := applyEvent(ctx, db, event, msg.Data); err != nil {
				logger.Error("apply Game projection event failed; event will be retried",
					"event_id", event.EventID, "event_type", event.EventType, "error", err)
				if nakErr := msg.NakWithDelay(5 * time.Second); nakErr != nil {
					logger.Warn("negative acknowledge Game projection event failed", "event_id", event.EventID, "error", nakErr)
				}
				continue
			}
			if err := msg.AckSync(); err != nil {
				logger.Warn("ack Game projection event failed; event will be redelivered",
					"event_id", event.EventID, "error", err)
			}
		}
	}
}

func validEnvelope(event envelope) bool {
	if event.Version != 1 || event.EventID == "" || event.EventType == "" ||
		event.AggregateID == "" || event.AggregateVersion <= 0 ||
		event.OccurredAt.IsZero() || len(event.Data) == 0 || !json.Valid(event.Data) {
		return false
	}
	switch event.EventType {
	case "game.character.created.v1", "game.character.updated.v1",
		"game.account.current_character_changed.v1",
		"game.world_instance.upserted.v1", "game.server_node.heartbeat.v1",
		"game.world_session.opened.v1", "game.world_session.updated.v1",
		"game.world_session.closed.v1":
		return true
	default:
		return false
	}
}

func applyEvent(ctx context.Context, db *sql.DB, event envelope, raw []byte) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin projection transaction: %w", err)
	}
	defer tx.Rollback()

	result, err := tx.ExecContext(ctx, `
		INSERT INTO game_projection_inbox(event_id,event_type,aggregate_id,payload,occurred_at)
		VALUES($1::uuid,$2,$3,$4::jsonb,$5)
		ON CONFLICT(event_id) DO NOTHING
	`, event.EventID, event.EventType, event.AggregateID, string(raw), event.OccurredAt)
	if err != nil {
		return fmt.Errorf("record projection inbox event: %w", err)
	}
	inserted, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if inserted == 0 {
		return tx.Commit()
	}

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO game_projection_versions(aggregate_id,aggregate_version)
		VALUES($1,0) ON CONFLICT(aggregate_id) DO NOTHING
	`, event.AggregateID); err != nil {
		return fmt.Errorf("initialize aggregate projection version: %w", err)
	}
	var currentVersion int64
	if err := tx.QueryRowContext(ctx, `
		SELECT aggregate_version FROM game_projection_versions
		WHERE aggregate_id=$1 FOR UPDATE
	`, event.AggregateID).Scan(&currentVersion); err != nil {
		return fmt.Errorf("lock aggregate projection version: %w", err)
	}
	if event.AggregateVersion <= currentVersion {
		if _, err := tx.ExecContext(ctx, `
			UPDATE game_projection_inbox SET processed_at=now() WHERE event_id=$1::uuid
		`, event.EventID); err != nil {
			return fmt.Errorf("mark stale projection event processed: %w", err)
		}
		return tx.Commit()
	}

	if err := projectData(ctx, tx, event); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE game_projection_versions
		SET aggregate_version=$2,updated_at=now()
		WHERE aggregate_id=$1
	`, event.AggregateID, event.AggregateVersion); err != nil {
		return fmt.Errorf("advance aggregate projection version: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE game_projection_inbox SET processed_at=now() WHERE event_id=$1::uuid
	`, event.EventID); err != nil {
		return fmt.Errorf("mark projection event processed: %w", err)
	}
	return tx.Commit()
}

func projectData(ctx context.Context, tx *sql.Tx, event envelope) error {
	switch event.EventType {
	case "game.character.created.v1", "game.character.updated.v1":
		var data characterData
		if err := json.Unmarshal(event.Data, &data); err != nil {
			return err
		}
		if data.CharacterID == "" || data.AccountID == "" || data.Name == "" || data.WorldID == "" {
			return errors.New("character projection event is missing required fields")
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO chat_accounts(account_id) VALUES($1::uuid)
			ON CONFLICT(account_id) DO NOTHING
		`, data.AccountID); err != nil {
			return fmt.Errorf("ensure chat account projection: %w", err)
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO chat_characters(character_id,name,race_id,level,world_id,status,updated_at)
			VALUES($1::uuid,$2,$3,$4,$5,$6,now())
			ON CONFLICT(character_id) DO UPDATE SET
				name=EXCLUDED.name,race_id=EXCLUDED.race_id,level=EXCLUDED.level,
				world_id=EXCLUDED.world_id,status=EXCLUDED.status,updated_at=now()
		`, data.CharacterID, data.Name, data.RaceID, data.Level, data.WorldID, data.Status)
		if err != nil {
			return fmt.Errorf("upsert chat character projection: %w", err)
		}
	case "game.account.current_character_changed.v1":
		var data accountCharacterData
		if err := json.Unmarshal(event.Data, &data); err != nil {
			return err
		}
		if data.AccountID == "" {
			return errors.New("account projection event is missing account_id")
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO chat_accounts(account_id,current_character_id,updated_at)
			VALUES($1::uuid,$2::uuid,now())
			ON CONFLICT(account_id) DO UPDATE SET
				current_character_id=EXCLUDED.current_character_id,updated_at=now()
		`, data.AccountID, data.CurrentCharacterID)
		if err != nil {
			return fmt.Errorf("upsert chat account projection: %w", err)
		}
	case "game.world_instance.upserted.v1":
		var data worldInstanceData
		if err := json.Unmarshal(event.Data, &data); err != nil {
			return err
		}
		if data.InstanceID == "" || data.WorldID == "" {
			return errors.New("world instance projection event is missing required fields")
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO chat_world_instances(instance_id,world_id,node_key,status,updated_at)
			VALUES($1::uuid,$2,$3,$4,now())
			ON CONFLICT(instance_id) DO UPDATE SET
				world_id=EXCLUDED.world_id,node_key=EXCLUDED.node_key,
				status=EXCLUDED.status,updated_at=now()
		`, data.InstanceID, data.WorldID, data.NodeKey, data.Status)
		if err != nil {
			return fmt.Errorf("upsert chat world instance projection: %w", err)
		}
	case "game.server_node.heartbeat.v1":
		var data serverNodeData
		if err := json.Unmarshal(event.Data, &data); err != nil {
			return err
		}
		if data.NodeKey == "" {
			return errors.New("server node projection event is missing node_key")
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO chat_server_nodes(node_key,status,last_heartbeat_at,updated_at)
			VALUES($1,$2,$3,now())
			ON CONFLICT(node_key) DO UPDATE SET
				status=EXCLUDED.status,last_heartbeat_at=EXCLUDED.last_heartbeat_at,updated_at=now()
		`, data.NodeKey, data.Status, data.LastHeartbeatAt)
		if err != nil {
			return fmt.Errorf("upsert chat server node projection: %w", err)
		}
	case "game.world_session.opened.v1", "game.world_session.updated.v1", "game.world_session.closed.v1":
		var data worldSessionData
		if err := json.Unmarshal(event.Data, &data); err != nil {
			return err
		}
		if data.SessionID == "" || data.CharacterID == "" || data.InstanceID == "" {
			return errors.New("world session projection event is missing required fields")
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO chat_world_sessions(session_id,character_id,instance_id,node_key,session_state,disconnected_at,updated_at)
			VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6,now())
			ON CONFLICT(session_id) DO UPDATE SET
				character_id=EXCLUDED.character_id,instance_id=EXCLUDED.instance_id,
				node_key=EXCLUDED.node_key,session_state=EXCLUDED.session_state,
				disconnected_at=EXCLUDED.disconnected_at,updated_at=now()
		`, data.SessionID, data.CharacterID, data.InstanceID, data.NodeKey, data.SessionState, data.DisconnectedAt)
		if err != nil {
			return fmt.Errorf("upsert chat world session projection: %w", err)
		}
	}
	return nil
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
