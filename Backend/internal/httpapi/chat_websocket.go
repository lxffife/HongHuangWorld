package httpapi

import (
	"bufio"
	"context"
	"crypto/rand"
	"os"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

const (
	chatPresenceLease = 90 * time.Second
	chatWebSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	maxChatSocketFrame = 64 * 1024
)

type chatSocketHub struct {
	mu sync.RWMutex
	clients map[*chatSocketClient]struct{}
}

type chatSocketClient struct {
	conn net.Conn
	reader *bufio.Reader
	writeMu sync.Mutex
	send chan []byte
	done chan struct{}
	closeOnce sync.Once
	scopeMu sync.RWMutex
	worldID string
	worldInstanceID string
	characterID string
	accountID string
	presenceID string
	service *chat.Service
	logger *slog.Logger
}

func newChatSocketHub() *chatSocketHub {
	return &chatSocketHub{clients: make(map[*chatSocketClient]struct{})}
}

func (h *chatSocketHub) add(client *chatSocketClient) {
	h.mu.Lock()
	h.clients[client] = struct{}{}
	h.mu.Unlock()
}

func (h *chatSocketHub) remove(client *chatSocketClient) {
	h.mu.Lock()
	delete(h.clients, client)
	h.mu.Unlock()
	client.close()
}

func (h *chatSocketHub) broadcast(message chat.Message) {
	payload := map[string]any{
		"type": "message", "accepted": true,
		"id": message.ID, "client_message_id": message.ClientMessageID,
		"channel": message.Channel, "world_id": message.WorldID,
		"sender_character_id": message.SenderCharacterID,
		"sender_name": message.SenderName, "sender_race": message.SenderRace,
		"sender_level": message.SenderLevel, "content": message.Content,
		"created_at": message.CreatedAt,
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for client := range h.clients {
		client.scopeMu.RLock()
		worldID := client.worldID
		worldInstanceID := client.worldInstanceID
		characterID := client.characterID
		client.scopeMu.RUnlock()
		if message.Channel == "world" && worldID != message.WorldID {
			continue
		}
		if message.Channel == "nearby" {
			if worldInstanceID == "" || worldInstanceID != message.WorldInstanceID || !hasRecipient(message.RecipientCharacterIDs, characterID) {
				continue
			}
		}
		select {
		case client.send <- encoded:
		default:
			// A slow consumer is disconnected rather than back-pressuring chat
			// publishers or other recipients.
			go h.remove(client)
		}
	}
}

func hasRecipient(recipients []string, characterID string) bool {
	for _, recipient := range recipients {
		if recipient == characterID { return true }
	}
	return false
}

func (c *chatSocketClient) close() {
	c.closeOnce.Do(func() {
		close(c.done)
		_ = c.conn.Close()
	})
}

func (c *chatSocketClient) writeFrame(opcode byte, payload []byte) error {
	if len(payload) > maxChatSocketFrame {
		return errors.New("websocket payload too large")
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_ = c.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	header := []byte{0x80 | opcode}
	switch {
	case len(payload) < 126:
		header = append(header, byte(len(payload)))
	case len(payload) <= 65535:
		header = append(header, 126, byte(len(payload)>>8), byte(len(payload)))
	default:
		var extended [8]byte
		binary.BigEndian.PutUint64(extended[:], uint64(len(payload)))
		header = append(header, 127)
		header = append(header, extended[:]...)
	}
	if err := writeChatSocketBytes(c.conn, header); err != nil { return err }
	return writeChatSocketBytes(c.conn, payload)
}

func writeChatSocketBytes(conn net.Conn, data []byte) error {
	for len(data) > 0 {
		written, err := conn.Write(data)
		if err != nil { return err }
		if written == 0 { return io.ErrShortWrite }
		data = data[written:]
	}
	return nil
}

func (c *chatSocketClient) writer() {
	defer c.close()
	for {
		select {
		case <-c.done:
			return
		case payload := <-c.send:
			if err := c.writeFrame(1, payload); err != nil {
				c.logger.Debug("chat websocket write failed", "error", err)
				return
			}
		}
	}
}

func readChatSocketFrame(reader *bufio.Reader) (byte, []byte, error) {
	first, err := reader.ReadByte()
	if err != nil { return 0, nil, err }
	second, err := reader.ReadByte()
	if err != nil { return 0, nil, err }
	if first&0x70 != 0 || first&0x80 == 0 { return 0, nil, errors.New("fragmented or reserved websocket frame") }
	if second&0x80 == 0 { return 0, nil, errors.New("client websocket frame must be masked") }
	length := uint64(second & 0x7f)
	if length == 126 {
		var raw [2]byte
		if _, err := io.ReadFull(reader, raw[:]); err != nil { return 0, nil, err }
		length = uint64(binary.BigEndian.Uint16(raw[:]))
	} else if length == 127 {
		var raw [8]byte
		if _, err := io.ReadFull(reader, raw[:]); err != nil { return 0, nil, err }
		length = binary.BigEndian.Uint64(raw[:])
		if length>>63 != 0 { return 0, nil, errors.New("invalid websocket frame length") }
	}
	if length > maxChatSocketFrame { return 0, nil, errors.New("websocket frame too large") }
	if first&0x08 != 0 && length > 125 { return 0, nil, errors.New("websocket control frame too large") }
	var mask [4]byte
	if _, err := io.ReadFull(reader, mask[:]); err != nil { return 0, nil, err }
	payload := make([]byte, int(length))
	if _, err := io.ReadFull(reader, payload); err != nil { return 0, nil, err }
	for i := range payload { payload[i] ^= mask[i&3] }
	return first & 0x0f, payload, nil
}

type chatSocketRequest struct {
	Type string `json:"type"`
	ClientMessageID string `json:"client_message_id"`
	Channel string `json:"channel"`
	Content string `json:"content"`
}

func (h *chatHandlers) socket(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") ||
		!strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade") ||
		r.Header.Get("Sec-WebSocket-Version") != "13" {
		http.Error(w, "websocket upgrade required", http.StatusUpgradeRequired)
		return
	}
	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	decodedKey, err := base64.StdEncoding.DecodeString(key)
	if err != nil || len(decodedKey) != 16 {
		http.Error(w, "invalid websocket key", http.StatusBadRequest)
		return
	}
	if origin := r.Header.Get("Origin"); origin != "" {
		// Native clients may omit Origin. Browser clients must match the
		// ChatServer host to prevent cross-site authenticated socket use.
		if !strings.EqualFold(origin, "http://"+r.Host) && !strings.EqualFold(origin, "https://"+r.Host) {
			http.Error(w, "websocket origin rejected", http.StatusForbidden)
			return
		}
	}
	scope, err := h.service.CurrentChatScope(r.Context(), account.ID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	hijacker, ok := w.(http.Hijacker)
	if !ok { http.Error(w, "websocket not supported", http.StatusInternalServerError); return }
	conn, rw, err := hijacker.Hijack()
	if err != nil { return }
	acceptHash := sha1.Sum([]byte(key + chatWebSocketGUID))
	accept := base64.StdEncoding.EncodeToString(acceptHash[:])
	_, err = fmt.Fprintf(rw, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n", accept)
	if err == nil { err = rw.Flush() }
	if err != nil { _ = conn.Close(); return }

	presenceID, err := newChatPresenceConnectionID()
	if err != nil {
		_ = conn.Close()
		return
	}
	nodeID := strings.TrimSpace(os.Getenv("CHAT_NODE_ID"))
	if nodeID == "" {
		nodeID, _ = os.Hostname()
	}
	if nodeID == "" {
		nodeID = "chat-node"
	}
	presenceCtx, presenceCancel := context.WithTimeout(context.Background(), 3*time.Second)
	presenceErr := h.service.OpenPresenceLease(presenceCtx, presenceID, account.ID, scope.CharacterID, nodeID, chatPresenceLease)
	presenceCancel()
	if presenceErr != nil {
		h.logger.Error("open chat presence lease failed", "account_id", account.ID, "error", presenceErr)
		_ = conn.Close()
		return
	}

	client := &chatSocketClient{
		conn: conn, reader: rw.Reader, send: make(chan []byte, 64),
		done: make(chan struct{}), worldID: scope.WorldID, worldInstanceID: scope.WorldInstanceID,
		characterID: scope.CharacterID, accountID: account.ID, presenceID: presenceID,
		service: h.service, logger: h.logger,
	}
	h.hub.add(client)
	go client.writer()
	defer h.hub.remove(client)
	defer client.closePresenceLease()

	accessToken := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	lastIdentityCheck := time.Now()
	for {
		_ = conn.SetReadDeadline(time.Now().Add(75 * time.Second))
		opcode, payload, readErr := readChatSocketFrame(client.reader)
		if readErr != nil { return }
		if !client.validateIdentitySession(h, account.ID, accessToken, &lastIdentityCheck) { return }
		if opcode != 8 && !client.refreshPresence(client.currentCharacterID()) { return }
		switch opcode {
		case 8:
			_ = client.writeFrame(8, payload)
			return
		case 9:
			if client.writeFrame(10, payload) != nil { return }
		case 10:
			continue
		case 1:
			if !utf8.Valid(payload) { client.sendError("websocket text must be valid UTF-8"); continue }
			var request chatSocketRequest
			if err := json.Unmarshal(payload, &request); err != nil {
				client.sendError("invalid websocket message")
				continue
			}
			if request.Type == "ping" {
				if scope, scopeErr := h.service.CurrentChatScope(r.Context(), account.ID); scopeErr == nil {
					client.scopeMu.Lock()
					client.characterID = scope.CharacterID
					client.worldID = scope.WorldID
					client.worldInstanceID = scope.WorldInstanceID
					client.scopeMu.Unlock()
					if !client.refreshPresence(scope.CharacterID) { return }
				} else {
					client.sendError("chat presence refresh failed")
					return
				}
				client.sendJSON(map[string]any{"type":"pong"})
				continue
			}
			if request.Type != "send" {
				client.sendError("unsupported websocket message type")
				continue
			}
			message, err := h.service.Send(r.Context(), account.ID, chat.SendRequest{
				ClientMessageID: request.ClientMessageID,
				Channel: request.Channel,
				Content: request.Content,
			})
			if err != nil {
				client.sendError(chatSocketErrorText(err))
				continue
			}
			if h.events != nil { h.events.publish(message) } else if h.hub != nil { h.hub.broadcast(message) }
		default:
			client.sendError("unsupported websocket frame")
		}
	}
}

func (c *chatSocketClient) sendJSON(value any) {
	payload, err := json.Marshal(value)
	if err != nil { return }
	select { case c.send <- payload: default: c.close() }
}

func (c *chatSocketClient) sendError(reason string) {
	c.sendJSON(map[string]any{"type":"error","accepted":false,"reason":reason})
}

func chatSocketErrorText(err error) string {
	switch {
	case errors.Is(err, chat.ErrInvalidInput): return "invalid chat request"
	case errors.Is(err, chat.ErrNoCharacter): return "no active character"
	case errors.Is(err, chat.ErrIdempotencyConflict): return "client_message_id already used with different content"
	case errors.Is(err, chat.ErrRateLimited): return "chat rate limit exceeded"
	case errors.Is(err, chat.ErrUnsupportedChannel): return "chat channel is not available yet"
	default: return "chat service temporarily unavailable"
	}
}


func newChatPresenceConnectionID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", fmt.Errorf("generate chat connection id: %w", err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		value[0:4], value[4:6], value[6:8], value[8:10], value[10:16]), nil
}

func (c *chatSocketClient) refreshPresence(characterID string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	refreshed, err := c.service.RefreshPresenceLease(ctx, c.presenceID, characterID, chatPresenceLease)
	if err != nil {
		c.logger.Warn("chat presence heartbeat failed", "account_id", c.accountID, "error", err)
		return false
	}
	if !refreshed {
		c.logger.Info("chat presence lease expired; closing socket", "account_id", c.accountID, "connection_id", c.presenceID)
		return false
	}
	return true
}

func (c *chatSocketClient) closePresenceLease() {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := c.service.ClosePresenceLease(ctx, c.presenceID); err != nil {
		c.logger.Warn("close chat presence lease failed", "account_id", c.accountID, "connection_id", c.presenceID, "error", err)
	}
}

func (c *chatSocketClient) currentCharacterID() string {
	c.scopeMu.RLock()
	defer c.scopeMu.RUnlock()
	return c.characterID
}

func (c *chatSocketClient) validateIdentitySession(h *chatHandlers, expectedAccountID, accessToken string, lastChecked *time.Time) bool {
	if time.Since(*lastChecked) < 30*time.Second {
		return true
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	account, err := h.authService.Authenticate(ctx, accessToken)
	if err != nil || account.ID != expectedAccountID {
		c.logger.Warn("chat websocket identity session is no longer valid", "account_id", expectedAccountID, "error", err)
		return false
	}
	*lastChecked = time.Now()
	return true
}
