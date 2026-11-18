package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
	"github.com/nats-io/nats.go"
)

const (
	chatEventSubject = "honghuang.chat.events.v1"
	chatEventStream  = "HONGHUANG_CHAT_EVENTS"
	chatEventMaxAge  = 30 * 24 * time.Hour
	chatEventQueue   = 4096
	chatEventSeenMax = 10000
)

var errInvalidChatEvent = errors.New("invalid chat event envelope")

type chatEventEnvelope struct {
	Version int          `json:"version"`
	Message chat.Message `json:"message"`
}

// chatEventBus fans persisted chat messages out to other ChatServer processes.
// Local delivery is always performed directly; NATS is never a prerequisite for
// the local ChatServer or the game simulation.
type chatEventBus struct {
	hub       *chatSocketHub
	conn      *nats.Conn
	js        nats.JetStreamContext
	sub       *nats.Subscription
	coreSub   *nats.Subscription
	logger    *slog.Logger
	publishQ  chan chatEventEnvelope
	stop      chan struct{}
	workers   sync.WaitGroup
	seenMu    sync.Mutex
	seen      map[string]struct{}
	seenOrder []string
}

func newChatEventBus(hub *chatSocketHub, logger *slog.Logger) *chatEventBus {
	bus := &chatEventBus{
		hub: hub, logger: logger, stop: make(chan struct{}),
		seen: make(map[string]struct{}),
	}
	url := strings.TrimSpace(os.Getenv("CHAT_NATS_URL"))
	if url == "" {
		url = strings.TrimSpace(os.Getenv("NATS_URL"))
	}
	if url == "" {
		logger.Warn("chat NATS is not configured; cross-instance chat fanout is disabled")
		return bus
	}

	conn, err := nats.Connect(url,
		nats.Name("honghuang-chat-server"),
		nats.NoEcho(),
		nats.RetryOnFailedConnect(true),
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2*time.Second),
		nats.ReconnectBufSize(4*1024*1024),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			logger.Warn("chat NATS disconnected; local chat remains available", "error", err)
		}),
		nats.ReconnectHandler(func(nc *nats.Conn) {
			logger.Info("chat NATS reconnected", "server", nc.ConnectedUrl())
		}),
		nats.ClosedHandler(func(nc *nats.Conn) {
			logger.Info("chat NATS connection closed", "error", nc.LastError())
		}),
	)
	if err != nil {
		logger.Error("chat NATS initialization failed; local chat remains available", "error", err)
		return bus
	}
	bus.conn = conn

	js, jsErr := conn.JetStream()
	if jsErr == nil {
		jsErr = ensureChatEventStream(js)
	}
	durable := chatEventDurableName()
	if jsErr == nil {
		jsErr = ensureChatEventConsumer(js, durable)
	}
	if jsErr == nil {
		bus.sub, jsErr = js.PullSubscribe(
			chatEventSubject, durable,
			nats.BindStream(chatEventStream),
			nats.AckExplicit(),
		)
	}
	if jsErr != nil {
		logger.Warn("chat JetStream setup failed; falling back to best-effort Core NATS", "error", jsErr)
		bus.subscribeCore()
		return bus
	}

	bus.js = js
	bus.publishQ = make(chan chatEventEnvelope, chatEventQueue)
	bus.workers.Add(2)
	go bus.consumeJetStream()
	go bus.publishJetStream()
	logger.Info("chat JetStream durable consumer ready",
		"stream", chatEventStream, "subject", chatEventSubject, "consumer", durable,
		"max_age", chatEventMaxAge.String())
	return bus
}

func ensureChatEventStream(js nats.JetStreamContext) error {
	info, err := js.StreamInfo(chatEventStream)
	if err == nil {
		for _, subject := range info.Config.Subjects {
			if subject == chatEventSubject {
				return nil
			}
		}
		return fmt.Errorf("existing stream %s does not capture subject %s", chatEventStream, chatEventSubject)
	}

	_, addErr := js.AddStream(&nats.StreamConfig{
		Name: chatEventStream, Subjects: []string{chatEventSubject},
		Retention: nats.LimitsPolicy, Storage: nats.FileStorage,
		Discard: nats.DiscardOld, MaxAge: chatEventMaxAge,
		Duplicates: 2 * time.Minute, Replicas: 1,
	})
	if addErr == nil {
		return nil
	}
	// Another ChatServer may have created the shared stream concurrently.
	info, err = js.StreamInfo(chatEventStream)
	if err == nil {
		for _, subject := range info.Config.Subjects {
			if subject == chatEventSubject {
				return nil
			}
		}
	}
	return fmt.Errorf("create or inspect chat JetStream stream: %w", addErr)
}

func ensureChatEventConsumer(js nats.JetStreamContext, durable string) error {
	if _, err := js.ConsumerInfo(chatEventStream, durable); err == nil {
		return nil
	}
	_, err := js.AddConsumer(chatEventStream, &nats.ConsumerConfig{
		Durable: durable, AckPolicy: nats.AckExplicitPolicy,
		DeliverPolicy: nats.DeliverAllPolicy, FilterSubject: chatEventSubject,
		AckWait: 30 * time.Second, MaxAckPending: 512, MaxDeliver: -1,
	})
	if err == nil {
		return nil
	}
	// Concurrent startup may have created this node's durable consumer.
	if _, inspectErr := js.ConsumerInfo(chatEventStream, durable); inspectErr == nil {
		return nil
	}
	return fmt.Errorf("create or inspect chat JetStream consumer %s: %w", durable, err)
}

func chatEventDurableName() string {
	node := strings.TrimSpace(os.Getenv("CHAT_NODE_ID"))
	if node == "" {
		node, _ = os.Hostname()
	}
	if node == "" {
		node = "default"
	}
	var b strings.Builder
	b.WriteString("CHAT_")
	for _, r := range strings.ToUpper(node) {
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
		if b.Len() >= 60 {
			break
		}
	}
	return strings.Trim(b.String(), "_-")
}

func (b *chatEventBus) subscribeCore() {
	if b == nil || b.conn == nil {
		return
	}
	sub, err := b.conn.Subscribe(chatEventSubject, func(msg *nats.Msg) {
		envelope, decodeErr := decodeChatEvent(msg.Data)
		if decodeErr != nil {
			b.logger.Warn("discarded invalid Core NATS chat event", "error", decodeErr)
			return
		}
		b.broadcastOnce(envelope.Message)
	})
	if err != nil {
		b.logger.Error("Core NATS subscription failed; local chat remains available", "error", err)
		return
	}
	b.coreSub = sub
}

func decodeChatEvent(data []byte) (chatEventEnvelope, error) {
	var envelope chatEventEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		return chatEventEnvelope{}, err
	}
	message := envelope.Message
	if envelope.Version != 1 || message.ID == "" || message.SenderCharacterID == "" ||
		strings.TrimSpace(message.Content) == "" {
		return chatEventEnvelope{}, errInvalidChatEvent
	}
	switch message.Channel {
	case "world":
		if message.WorldID == "" {
			return chatEventEnvelope{}, errInvalidChatEvent
		}
	case "cross_world":
		if message.WorldID != "" {
			return chatEventEnvelope{}, errInvalidChatEvent
		}
	default:
		return chatEventEnvelope{}, errInvalidChatEvent
	}
	return envelope, nil
}

func (b *chatEventBus) broadcastOnce(message chat.Message) {
	if b == nil || b.hub == nil {
		return
	}
	if message.ID != "" {
		b.seenMu.Lock()
		if _, exists := b.seen[message.ID]; exists {
			b.seenMu.Unlock()
			return
		}
		b.seen[message.ID] = struct{}{}
		b.seenOrder = append(b.seenOrder, message.ID)
		if len(b.seenOrder) > chatEventSeenMax {
			oldest := b.seenOrder[0]
			b.seenOrder = b.seenOrder[1:]
			delete(b.seen, oldest)
		}
		b.seenMu.Unlock()
	}
	b.hub.broadcast(message)
}

func (b *chatEventBus) publish(message chat.Message) {
	if b == nil {
		return
	}
	// The database write has already succeeded. Local delivery never waits for
	// NATS, JetStream acknowledgements, or another ChatServer.
	b.broadcastOnce(message)
	envelope := chatEventEnvelope{Version: 1, Message: message}
	if b.js != nil {
		select {
		case b.publishQ <- envelope:
		default:
			b.logger.Error("chat JetStream publish queue is full; event requires history/outbox recovery", "message_id", message.ID)
		}
		return
	}
	if b.conn == nil {
		return
	}
	payload, err := json.Marshal(envelope)
	if err != nil {
		b.logger.Error("encode chat event failed", "message_id", message.ID, "error", err)
		return
	}
	if err := b.conn.Publish(chatEventSubject, payload); err != nil {
		b.logger.Warn("publish chat event to Core NATS failed; local delivery succeeded", "message_id", message.ID, "error", err)
	}
}

func (b *chatEventBus) publishJetStream() {
	defer b.workers.Done()
	for {
		select {
		case <-b.stop:
			return
		case envelope := <-b.publishQ:
			payload, err := json.Marshal(envelope)
			if err != nil {
				b.logger.Error("encode JetStream chat event failed", "message_id", envelope.Message.ID, "error", err)
				continue
			}
			delay := time.Second
			for {
				_, err = b.js.Publish(chatEventSubject, payload, nats.MsgId(envelope.Message.ID), nats.AckWait(5*time.Second))
				if err == nil {
					break
				}
				b.logger.Warn("JetStream chat publish failed; retrying asynchronously", "message_id", envelope.Message.ID, "error", err)
				timer := time.NewTimer(delay)
				select {
				case <-b.stop:
					timer.Stop()
					return
				case <-timer.C:
				}
				if delay < 30*time.Second {
					delay *= 2
				}
			}
		}
	}
}

func (b *chatEventBus) consumeJetStream() {
	defer b.workers.Done()
	for {
		select {
		case <-b.stop:
			return
		default:
		}
		messages, err := b.sub.Fetch(32, nats.MaxWait(2*time.Second))
		if err != nil {
			if errors.Is(err, nats.ErrTimeout) {
				continue
			}
			select {
			case <-b.stop:
				return
			case <-time.After(time.Second):
			}
			b.logger.Warn("fetch JetStream chat events failed; consumer will retry", "error", err)
			continue
		}
		for _, msg := range messages {
			envelope, decodeErr := decodeChatEvent(msg.Data)
			if decodeErr != nil {
				b.logger.Warn("terminating invalid JetStream chat event", "error", decodeErr)
				if termErr := msg.Term(); termErr != nil {
					b.logger.Warn("terminate invalid JetStream chat event failed", "error", termErr)
				}
				continue
			}
			b.broadcastOnce(envelope.Message)
			if ackErr := msg.AckSync(); ackErr != nil {
				b.logger.Warn("ack JetStream chat event failed; event will be redelivered", "message_id", envelope.Message.ID, "error", ackErr)
			}
		}
	}
}

func (b *chatEventBus) close() {
	if b == nil {
		return
	}
	select {
	case <-b.stop:
	default:
		close(b.stop)
	}
	if b.sub != nil {
		_ = b.sub.Unsubscribe()
	}
	if b.coreSub != nil {
		_ = b.coreSub.Unsubscribe()
	}
	if b.conn != nil {
		b.workers.Wait()
		if err := b.conn.FlushTimeout(1 * time.Second); err != nil {
			b.logger.Warn("flush chat NATS connection during shutdown failed", "error", err)
		}
		b.conn.Close()
	}
}
