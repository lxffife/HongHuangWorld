package httpapi

import (
	"encoding/json"
	"log/slog"
	"os"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
	"github.com/nats-io/nats.go"
)

const chatEventSubject = "honghuang.chat.events.v1"

type chatEventEnvelope struct {
	Version int          `json:"version"`
	Message chat.Message `json:"message"`
}

// chatEventBus fans persisted chat messages out to other ChatServer processes.
// Local delivery is always performed directly; NATS is never a prerequisite for
// the local ChatServer or the game simulation.
type chatEventBus struct {
	hub    *chatSocketHub
	conn   *nats.Conn
	logger *slog.Logger
}

func newChatEventBus(hub *chatSocketHub, logger *slog.Logger) *chatEventBus {
	bus := &chatEventBus{hub: hub, logger: logger}
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
			logger.Error("chat NATS connection closed", "error", nc.LastError())
		}),
	)
	if err != nil {
		logger.Error("chat NATS initialization failed; local chat remains available", "error", err)
		return bus
	}

	if _, err := conn.Subscribe(chatEventSubject, func(msg *nats.Msg) {
		envelope, decodeErr := decodeChatEvent(msg.Data)
		if decodeErr != nil {
			logger.Warn("discarded invalid NATS chat event", "error", decodeErr)
			return
		}
		hub.broadcast(envelope.Message)
	}); err != nil {
		logger.Error("chat NATS subscription failed; local chat remains available", "error", err)
		conn.Close()
		return bus
	}

	bus.conn = conn
	logger.Info("chat NATS event subscription configured", "subject", chatEventSubject, "connected", conn.IsConnected())
	return bus
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

func (b *chatEventBus) publish(message chat.Message) {
	if b == nil {
		return
	}
	// Deliver locally regardless of NATS health. The database write has already
	// succeeded before this method is called.
	b.hub.broadcast(message)
	if b.conn == nil {
		return
	}
	payload, err := json.Marshal(chatEventEnvelope{Version: 1, Message: message})
	if err != nil {
		b.logger.Error("encode chat event failed", "message_id", message.ID, "error", err)
		return
	}
	if err := b.conn.Publish(chatEventSubject, payload); err != nil {
		b.logger.Warn("publish chat event to NATS failed; local delivery succeeded", "message_id", message.ID, "error", err)
	}
}
