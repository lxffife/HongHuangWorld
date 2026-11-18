package httpapi

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"testing"
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
	frame := []byte{0x81, 0xff, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0}
	reader := bufio.NewReader(bytes.NewReader(frame))
	if _, _, err := readChatSocketFrame(reader); err == nil {
		t.Fatal("expected oversized client frame to be rejected")
	}
}
