package soul

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrNotFound = errors.New("soul not found")
	ErrConflict = errors.New("soul already exists")
	ErrInvalid  = errors.New("invalid soul name")
)

type Soul struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Origin     string `json:"origin,omitempty"`
	Karma      int64  `json:"karma"`
	Merit      int64  `json:"merit"`
	CreatedAt  string `json:"created_at"`
}

type Progression struct {
 Experience int64 `json:"experience"`
 RealmID string `json:"realm_id"`
 RealmName string `json:"realm_name"`
 RealmOrder int `json:"realm_order"`
 NextRealmName string `json:"next_realm_name,omitempty"`
 NextRequiredExperience *int64 `json:"next_required_experience,omitempty"`
}

type Service struct {
	db *sql.DB
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

func (s *Service) Create(ctx context.Context, accountID, name, origin string) (Soul, error) {
	name = strings.TrimSpace(name)
	origin = strings.TrimSpace(origin)
	if len([]rune(name)) < 2 || len([]rune(name)) > 48 || len(origin) > 64 {
		return Soul{}, ErrInvalid
	}
	var result Soul
	var createdAt sql.NullTime
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return Soul{}, fmt.Errorf("begin soul creation: %w", err) }
	defer tx.Rollback()
	err = tx.QueryRowContext(ctx,
		`INSERT INTO souls (account_id, soul_name, soul_origin) VALUES ($1, $2, NULLIF($3, ''))
		 RETURNING id::text, soul_name, COALESCE(soul_origin, ''), karma, merit, created_at`,
		accountID, name, origin,
	).Scan(&result.ID, &result.Name, &result.Origin, &result.Karma, &result.Merit, &createdAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Soul{}, ErrConflict
		}
		return Soul{}, fmt.Errorf("create soul: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO soul_progression (soul_id) VALUES ($1)`, result.ID); err != nil {
		return Soul{}, fmt.Errorf("initialize soul progression: %w", err)
	}
	if err := tx.Commit(); err != nil { return Soul{}, fmt.Errorf("commit soul creation: %w", err) }
	if createdAt.Valid {
		result.CreatedAt = createdAt.Time.UTC().Format("2006-01-02T15:04:05Z07:00")
	}
	return result, nil
}

func (s *Service) Current(ctx context.Context, accountID string) (Soul, error) {
	var result Soul
	var createdAt sql.NullTime
	err := s.db.QueryRowContext(ctx,
		`SELECT id::text, soul_name, COALESCE(soul_origin, ''), karma, merit, created_at
		 FROM souls WHERE account_id = $1`, accountID,
	).Scan(&result.ID, &result.Name, &result.Origin, &result.Karma, &result.Merit, &createdAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Soul{}, ErrNotFound
	}
	if err != nil {
		return Soul{}, fmt.Errorf("load current soul: %w", err)
	}
	if createdAt.Valid {
		result.CreatedAt = createdAt.Time.UTC().Format("2006-01-02T15:04:05Z07:00")
	}
	return result, nil
}

 
// CurrentProgression returns permanent soul growth, independent of the active body.
func (s *Service) CurrentProgression(ctx context.Context, accountID string) (Progression, error) {
 var result Progression
 var nextName sql.NullString
 var nextRequired sql.NullInt64
 err := s.db.QueryRowContext(ctx,
  `SELECT p.experience, realm.id, realm.name, realm.realm_order,
          next_realm.name, next_realm.required_experience
   FROM souls soul
   JOIN soul_progression p ON p.soul_id = soul.id
   JOIN soul_realm_definitions realm ON realm.id = p.realm_id
   LEFT JOIN soul_realm_definitions next_realm ON next_realm.realm_order = realm.realm_order + 1
   WHERE soul.account_id = $1`, accountID,
 ).Scan(&result.Experience, &result.RealmID, &result.RealmName, &result.RealmOrder, &nextName, &nextRequired)
 if errors.Is(err, sql.ErrNoRows) { return Progression{}, ErrNotFound }
 if err != nil { return Progression{}, fmt.Errorf("load soul progression: %w", err) }
 if nextName.Valid { result.NextRealmName = nextName.String }
 if nextRequired.Valid { value := nextRequired.Int64; result.NextRequiredExperience = &value }
 return result, nil
}
