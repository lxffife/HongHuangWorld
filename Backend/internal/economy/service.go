package economy

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strings"
)

var (
	ErrInvalidRequest = errors.New("invalid economy request")
	ErrInsufficientFunds = errors.New("insufficient currency balance")
	ErrIdempotencyConflict = errors.New("economy event key was already used with different values")
)

type Service struct { db *sql.DB }

func NewService(db *sql.DB) *Service { return &Service{db: db} }

type Currency struct {
	ID string `json:"id"`
	Name string `json:"name"`
	Symbol string `json:"symbol"`
	Class string `json:"class"`
	HomeWorldID string `json:"home_world_id,omitempty"`
	Element string `json:"energy_element"`
	QualityGrade int `json:"quality_grade"`
	CultivationUsable bool `json:"cultivation_usable"`
	Tradeable bool `json:"tradeable"`
	CrossWorldExchangeable bool `json:"cross_world_exchangeable"`
	Description string `json:"description"`
}

type WalletEntry struct {
	Currency Currency `json:"currency"`
	Available int64 `json:"available"`
	Frozen int64 `json:"frozen"`
}

type LedgerResult struct {
	Applied bool `json:"applied"`
	CurrencyID string `json:"currency_id"`
	Delta int64 `json:"delta"`
	AvailableAfter int64 `json:"available_after"`
	FrozenAfter int64 `json:"frozen_after"`
}

func (s *Service) ListCurrencies(ctx context.Context) ([]Currency, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, display_name, symbol, currency_class,
		COALESCE(home_world_id, ''), energy_element, quality_grade, cultivation_usable,
		tradeable, cross_world_exchangeable, description
		FROM currency_definitions WHERE enabled ORDER BY currency_class, home_world_id NULLS LAST, quality_grade, id`)
	if err != nil { return nil, fmt.Errorf("list currency definitions: %w", err) }
	defer rows.Close()
	result := make([]Currency, 0)
	for rows.Next() {
		var c Currency
		if err := rows.Scan(&c.ID, &c.Name, &c.Symbol, &c.Class, &c.HomeWorldID, &c.Element,
			&c.QualityGrade, &c.CultivationUsable, &c.Tradeable, &c.CrossWorldExchangeable, &c.Description); err != nil {
			return nil, fmt.Errorf("scan currency definition: %w", err)
		}
		result = append(result, c)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate currency definitions: %w", err) }
	return result, nil
}

func (s *Service) Wallet(ctx context.Context, accountID string) ([]WalletEntry, error) {
	if strings.TrimSpace(accountID) == "" { return nil, ErrInvalidRequest }
	rows, err := s.db.QueryContext(ctx, `SELECT c.id, c.display_name, c.symbol, c.currency_class,
		COALESCE(c.home_world_id, ''), c.energy_element, c.quality_grade, c.cultivation_usable,
		c.tradeable, c.cross_world_exchangeable, c.description,
		COALESCE(b.available_amount, 0), COALESCE(b.frozen_amount, 0)
		FROM currency_definitions c
		LEFT JOIN currency_balances b ON b.currency_id = c.id AND b.account_id = $1
		WHERE c.enabled AND (c.tradeable OR c.currency_class = 'origin')
		ORDER BY c.currency_class, c.home_world_id NULLS LAST, c.quality_grade, c.id`, accountID)
	if err != nil { return nil, fmt.Errorf("load account currency wallet: %w", err) }
	defer rows.Close()
	result := make([]WalletEntry, 0)
	for rows.Next() {
		var entry WalletEntry
		c := &entry.Currency
		if err := rows.Scan(&c.ID, &c.Name, &c.Symbol, &c.Class, &c.HomeWorldID, &c.Element,
			&c.QualityGrade, &c.CultivationUsable, &c.Tradeable, &c.CrossWorldExchangeable,
			&c.Description, &entry.Available, &entry.Frozen); err != nil {
			return nil, fmt.Errorf("scan account currency balance: %w", err)
		}
		result = append(result, entry)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate account currency wallet: %w", err) }
	return result, nil
}

// ApplyDelta is the only balance mutation primitive. Callers must first authorize
// the source event (for example, a trusted world-server reward or a validated
// cultivation action). Every committed delta writes an immutable ledger row.
func (s *Service) ApplyDelta(ctx context.Context, accountID, currencyID, eventKey, entryType string, delta int64, sourceType, sourceID, note string) (LedgerResult, error) {
	if !validDeltaRequest(accountID, currencyID, eventKey, entryType, delta) {
		return LedgerResult{}, ErrInvalidRequest
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return LedgerResult{}, fmt.Errorf("begin economy ledger transaction: %w", err) }
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, accountID); err != nil {
		return LedgerResult{}, fmt.Errorf("lock economy account scope: %w", err)
	}

	var existing LedgerResult
	var existingType string
	err = tx.QueryRowContext(ctx, `SELECT currency_id, entry_type, delta, available_after, frozen_after
		FROM economy_ledger_entries WHERE account_id = $1 AND event_key = $2`, accountID, eventKey).
		Scan(&existing.CurrencyID, &existingType, &existing.Delta, &existing.AvailableAfter, &existing.FrozenAfter)
	if err == nil {
		if existing.CurrencyID != currencyID || existing.Delta != delta || existingType != entryType { return LedgerResult{}, ErrIdempotencyConflict }
		existing.Applied = false
		if err := tx.Commit(); err != nil { return LedgerResult{}, fmt.Errorf("commit recovered economy event: %w", err) }
		return existing, nil
	}
	if !errors.Is(err, sql.ErrNoRows) { return LedgerResult{}, fmt.Errorf("check economy idempotency key: %w", err) }

	var enabled, cultivationUsable bool
	if err := tx.QueryRowContext(ctx, `SELECT enabled, cultivation_usable FROM currency_definitions WHERE id = $1`, currencyID).Scan(&enabled, &cultivationUsable); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return LedgerResult{}, ErrInvalidRequest }
		return LedgerResult{}, fmt.Errorf("load currency definition: %w", err)
	}
	if !enabled || (entryType == "cultivation" && !cultivationUsable) { return LedgerResult{}, ErrInvalidRequest }

	if _, err := tx.ExecContext(ctx, `INSERT INTO currency_balances (account_id, currency_id)
		VALUES ($1, $2) ON CONFLICT (account_id, currency_id) DO NOTHING`, accountID, currencyID); err != nil {
		return LedgerResult{}, fmt.Errorf("initialize currency balance: %w", err)
	}
	var available, frozen int64
	if err := tx.QueryRowContext(ctx, `SELECT available_amount, frozen_amount FROM currency_balances
		WHERE account_id = $1 AND currency_id = $2 FOR UPDATE`, accountID, currencyID).Scan(&available, &frozen); err != nil {
		return LedgerResult{}, fmt.Errorf("lock currency balance: %w", err)
	}
	if delta < 0 && available < -delta { return LedgerResult{}, ErrInsufficientFunds }
	if delta > 0 && available > math.MaxInt64-delta { return LedgerResult{}, ErrInvalidRequest }
	available += delta
	if _, err := tx.ExecContext(ctx, `UPDATE currency_balances SET available_amount = $3, updated_at = now()
		WHERE account_id = $1 AND currency_id = $2`, accountID, currencyID, available); err != nil {
		return LedgerResult{}, fmt.Errorf("update currency balance: %w", err)
	}
	result := LedgerResult{Applied: true, CurrencyID: currencyID, Delta: delta, AvailableAfter: available, FrozenAfter: frozen}
	if _, err := tx.ExecContext(ctx, `INSERT INTO economy_ledger_entries
		(account_id, currency_id, event_key, entry_type, delta, available_after, frozen_after, source_type, source_id, note)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		accountID, currencyID, eventKey, entryType, delta, available, frozen, sourceType, sourceID, note); err != nil {
		return LedgerResult{}, fmt.Errorf("append immutable economy ledger entry: %w", err)
	}
	if err := tx.Commit(); err != nil { return LedgerResult{}, fmt.Errorf("commit economy ledger transaction: %w", err) }
	return result, nil
}

func validDeltaRequest(accountID, currencyID, eventKey, entryType string, delta int64) bool {
	if strings.TrimSpace(accountID) == "" || len(currencyID) == 0 || len(currencyID) > 64 ||
		len(eventKey) == 0 || len(eventKey) > 128 || delta == 0 || delta == math.MinInt64 { return false }
	switch entryType {
	case "grant":
		return delta > 0
	case "spend", "cultivation", "craft":
		return delta < 0
	case "system_adjustment":
		return true
	default:
		return false
	}
}
