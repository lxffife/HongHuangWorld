package httpapi

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"testing"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

func maskedClientFrame(opcode byte, payload []byte) []byte {
	mask := [4]byte{0x12, 0x34, 0x56, 0x78}
	frame := []byte{0x80 | opcode}
	switch {
	case len(payload) < 126:
		frame = append(frame, 0x80|byte(len(payload)))
	case len(payload) <= 65535:
		frame = append(frame, 0x80|126, byte(len(payload)>>8), byte(len(payload)))
	default:
		var length [8]byte
		binary.BigEndian.PutUint64(length[:], uint64(len(payload)))
		frame = append(frame, 0x80|127)
		frame = append(frame, length[:]...)
	}
	frame = append(frame, mask[:]...)
	for i, value := range payload {
		frame = append(frame, value^mask[i&3])
	}
	return frame
}

func TestReadChatSocketFrameUnmasksText(t *testing.T) {
	want := []byte(`{"type":"ping"}`)
	reader := bufio.NewReader(bytes.NewReader(maskedClientFrame(1, want)))
	opcode, got, err := readChatSocketFrame(reader)
	if err != nil { t.Fatalf("read frame: %v", err) }
	if opcode != 1 { t.Fatalf("opcode = %d, want 1", opcode) }
	if !bytes.Equal(got, want) { t.Fatalf("payload = %q, want %q", got, want) }
}

func TestReadChatSocketFrameRejectsUnmaskedClientFrame(t *testing.T) {
	reader := bufio.NewReader(bytes.NewReader([]byte{0x81, 0x01, 'x'}))
	if _, _, err := readChatSocketFrame(reader); err == nil {
		t.Fatal("expected unmasked client frame to be rejected")
	}
}

func TestReadChatSocketFrameRejectsOversizedPayload(t *testing.T) {
	frame := []byte{0x81, 0xff, 0, 0, 0, 0, 0, 1, 0, 1}
	reader := bufio.NewReader(bytes.NewReader(frame))
	if _, _, err := readChatSocketFrame(reader); err == nil {
		t.Fatal("expected oversized client frame to be rejected")
	}
}

func TestChatSocketHubRoutesWorldAndCrossWorldMessages(t *testing.T) {
	hub := newChatSocketHub()
	worldA := &chatSocketClient{worldID: "world-a", send: make(chan []byte, 4), done: make(chan struct{})}
	worldA2 := &chatSocketClient{worldID: "world-a", send: make(chan []byte, 4), done: make(chan struct{})}
	worldB := &chatSocketClient{worldID: "world-b", send: make(chan []byte, 4), done: make(chan struct{})}
	hub.add(worldA)
	hub.add(worldA2)
	hub.add(worldB)

	hub.broadcast(chat.Message{ID: "1", Channel: "world", WorldID: "world-a", Content: "world", CreatedAt: time.Now()})
	if len(worldA.send) != 1 || len(worldA2.send) != 1 || len(worldB.send) != 0 {
		t.Fatalf("world broadcast recipients = (%d,%d,%d), want (1,1,0)", len(worldA.send), len(worldA2.send), len(worldB.send))
	}

	hub.broadcast(chat.Message{ID: "2", Channel: "cross_world", Content: "cross", CreatedAt: time.Now()})
	if len(worldA.send) != 2 || len(worldA2.send) != 2 || len(worldB.send) != 1 {
		t.Fatalf("cross-world broadcast recipients = (%d,%d,%d), want (2,2,1)", len(worldA.send), len(worldA2.send), len(worldB.send))
	}
}
