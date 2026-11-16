package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidInput       = errors.New("invalid input")
	ErrConflict           = errors.New("account already exists")
	ErrInvalidCredentials = errors.New("invalid username or password")
	ErrUnauthorized       = errors.New("unauthorized")
	usernamePattern       = regexp.MustCompile(`^[A-Za-z0-9_]{3,32}$`)
)

type Account struct {
	ID       string  `json:"id"`
	Username string  `json:"username"`
	Email    *string `json:"email,omitempty"`
}

type Service struct {
	db        *sql.DB
	sessionTTL time.Duration
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db, sessionTTL: 30 * 24 * time.Hour}
}

func (s *Service) Register(ctx context.Context, username, email, password string) (Account, string, time.Time, error) {
	username = strings.TrimSpace(username)
	email = strings.TrimSpace(email)
	if !usernamePattern.MatchString(username) || len(password) < 12 || len(password) > 72 {
		return Account{}, "", time.Time{}, ErrInvalidInput
	}
	if email != "" && (len(email) > 254 || !strings.Contains(email, "@")) {
		return Account{}, "", time.Time{}, ErrInvalidInput
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return Account{}, "", time.Time{}, fmt.Errorf("hash password: %w", err)
	}
	token, tokenHash, expiresAt, err := newSessionToken(s.sessionTTL)
	if err != nil {
		return Account{}, "", time.Time{}, err
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Account{}, "", time.Time{}, fmt.Errorf("begin account registration: %w", err)
	}
	defer tx.Rollback()

	var account Account
	var emailValue sql.NullString
	err = tx.QueryRowContext(ctx,
		`INSERT INTO accounts (username, email, password_hash) VALUES ($1, NULLIF($2, ''), $3) RETURNING id::text, username, email`,
		username, email, string(passwordHash),
	).Scan(&account.ID, &account.Username, &emailValue)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Account{}, "", time.Time{}, ErrConflict
		}
		return Account{}, "", time.Time{}, fmt.Errorf("insert account: %w", err)
	}
	if emailValue.Valid {
		account.Email = &emailValue.String
	}

	if _, err = tx.ExecContext(ctx,
		`INSERT INTO account_sessions (account_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		account.ID, tokenHash[:], expiresAt,
	); err != nil {
		return Account{}, "", time.Time{}, fmt.Errorf("create account session: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return Account{}, "", time.Time{}, fmt.Errorf("commit account registration: %w", err)
	}
	return account, token, expiresAt, nil
}

func (s *Service) Login(ctx context.Context, username, password string) (Account, string, time.Time, error) {
	username = strings.TrimSpace(username)
	var account Account
	var passwordHash, status string
	var email sql.NullString
	err := s.db.QueryRowContext(ctx,
		`SELECT id::text, username, email, password_hash, status FROM accounts WHERE username = $1`, username,
	).Scan(&account.ID, &account.Username, &email, &passwordHash, &status)
	if err != nil || status != "active" || bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(password)) != nil {
		return Account{}, "", time.Time{}, ErrInvalidCredentials
	}
	if email.Valid {
		account.Email = &email.String
	}

	token, tokenHash, expiresAt, err := newSessionToken(s.sessionTTL)
	if err != nil {
		return Account{}, "", time.Time{}, err
	}
	if _, err := s.db.ExecContext(ctx,
		`INSERT INTO account_sessions (account_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		account.ID, tokenHash[:], expiresAt,
	); err != nil {
		return Account{}, "", time.Time{}, fmt.Errorf("create login session: %w", err)
	}
	return account, token, expiresAt, nil
}

func (s *Service) Authenticate(ctx context.Context, token string) (Account, error) {
	if token == "" || len(token) > 128 {
		return Account{}, ErrUnauthorized
	}
	hash := sha256.Sum256([]byte(token))
	var account Account
	var email sql.NullString
	err := s.db.QueryRowContext(ctx,
		`SELECT a.id::text, a.username, a.email
		 FROM account_sessions s
		 JOIN accounts a ON a.id = s.account_id
		 WHERE s.token_hash = $1 AND s.expires_at > now() AND s.revoked_at IS NULL AND a.status = 'active'`,
		hash[:],
	).Scan(&account.ID, &account.Username, &email)
	if err != nil {
		return Account{}, ErrUnauthorized
	}
	if email.Valid {
		account.Email = &email.String
	}
	return account, nil
}

func newSessionToken(ttl time.Duration) (string, [32]byte, time.Time, error) {
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", [32]byte{}, time.Time{}, fmt.Errorf("generate session token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(raw[:])
	hash := sha256.Sum256([]byte(token))
	return token, hash, time.Now().UTC().Add(ttl), nil
}
