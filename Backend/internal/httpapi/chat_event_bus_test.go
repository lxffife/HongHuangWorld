package httpapi

import (
	"io"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

func TestDecodeChatEventValidatesEnvelopeAndChannelScope(t *testing.T) {
	validWorld := []byte(`{"version":1,"message":{"id":"message-1","channel":"world","world_id":"world-a","sender_character_id":"character-1","content":"hello"}}`)
	if _, err := decodeChatEvent(validWorld); err != nil {
		t.Fatalf("decode valid world event: %v", err)
	}

	validCrossWorld := []byte(`{"version":1,"message":{"id":"message-2","channel":"cross_world","sender_character_id":"character-1","content":"hello"}}`)
	if _, err := decodeChatEvent(validCrossWorld); err != nil {
		t.Fatalf("decode valid cross-world event: %v", err)
	}

	for name, payload := range map[string][]byte{
		"unsupported version": []byte(`{"version":2,"message":{"id":"1","channel":"cross_world","sender_character_id":"c","content":"x"}}`),
		"missing world scope": []byte(`{"version":1,"message":{"id":"1","channel":"world","sender_character_id":"c","content":"x"}}`),
		"cross world with world scope": []byte(`{"version":1,"message":{"id":"1","channel":"cross_world","world_id":"world-a","sender_character_id":"c","content":"x"}}`),
		"unsupported channel": []byte(`{"version":1,"message":{"id":"1","channel":"nearby","sender_character_id":"c","content":"x"}}`),
		"missing sender": []byte(`{"version":1,"message":{"id":"1","channel":"cross_world","content":"x"}}`),
		"empty content": []byte(`{"version":1,"message":{"id":"1","channel":"cross_world","sender_character_id":"c","content":" "}}`),
		"invalid json": []byte(`{"version":`),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeChatEvent(payload); err == nil {
				t.Fatal("expected invalid event to be rejected")
			}
		})
	}
}

func TestChatEventBusPublishesLocallyWithoutNATS(t *testing.T) {
	hub := newChatSocketHub()
	client := &chatSocketClient{worldID: "world-a", send: make(chan []byte, 1), done: make(chan struct{})}
	hub.add(client)
	bus := &chatEventBus{hub: hub, logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	message := chat.Message{
		ID: "message-1", Channel: "world", WorldID: "world-a",
		SenderCharacterID: "character-1", Content: "hello", CreatedAt: time.Now().UTC(),
	}
	bus.publish(message)
	bus.publish(message) // A local publish followed by JetStream redelivery must not duplicate delivery.
	if len(client.send) != 1 {
		t.Fatalf("local event count = %d, want 1", len(client.send))
	}
}

func TestChatEventDurableNameUsesStableNodeIdentity(t *testing.T) {
	t.Setenv("CHAT_NODE_ID", "asia.chat-node-02")
	if got, want := chatEventDurableName(), "CHAT_ASIA_CHAT_NODE_02"; got != want {
		t.Fatalf("durable name = %q, want %q", got, want)
	}
}

func TestChatEventDurableNameHasSafeFallback(t *testing.T) {
	t.Setenv("CHAT_NODE_ID", "node.with spaces")
	got := chatEventDurableName()
	if got == "" || strings.ContainsAny(got, ". *>/\\\\") {
		t.Fatalf("durable name contains invalid characters: %q", got)
	}
}
