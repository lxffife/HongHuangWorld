package faction

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

var (
	ErrInvalid = errors.New("invalid faction request")
	ErrNotFound = errors.New("faction or application not found")
	ErrForbidden = errors.New("faction permission denied")
	ErrAlreadyMember = errors.New("account is already a faction member")
	ErrPendingApplication = errors.New("a pending application already exists")
)

type Service struct { db *sql.DB }

func NewService(db *sql.DB) *Service { return &Service{db: db} }

type Faction struct {
	ID string `json:"id"`
	WorldID string `json:"world_id"`
	Type string `json:"type"`
	Name string `json:"name"`
	Description string `json:"description"`
	Level int `json:"level"`
	TreasuryAccountID string `json:"treasury_account_id,omitempty"`
	Role string `json:"my_role,omitempty"`
	MemberCount int `json:"member_count,omitempty"`
}

type Application struct {
	ID string `json:"id"`
	FactionID string `json:"faction_id"`
	AccountID string `json:"account_id"`
	Message string `json:"message"`
	Status string `json:"status"`
	CreatedAt string `json:"created_at"`
}

type Member struct {
	AccountID string `json:"account_id"`
	Role string `json:"role"`
	ContributionPoints int64 `json:"contribution_points"`
	JoinedAt string `json:"joined_at"`
}

func validName(name string) bool {
	name = strings.TrimSpace(name)
	return utf8.RuneCountInString(name) >= 2 && utf8.RuneCountInString(name) <= 24
}

// CreateSect deliberately does not accept a faction type. Trusted city and
// government organizations are provisioned separately by server administration.
func (s *Service) CreateSect(ctx context.Context, accountID, worldID, name, description string) (Faction, error) {
	name = strings.TrimSpace(name)
	description = strings.TrimSpace(description)
	worldID = strings.TrimSpace(worldID)
	if accountID == "" || worldID == "" || len(worldID) > 64 || !validName(name) ||
		utf8.RuneCountInString(description) > 240 {
		return Faction{}, ErrInvalid
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return Faction{}, fmt.Errorf("begin sect creation: %w", err) }
	defer tx.Rollback()
	var exists bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM world_definitions WHERE id = $1 AND enabled)`, worldID).Scan(&exists); err != nil {
		return Faction{}, fmt.Errorf("validate sect world: %w", err)
	}
	if !exists { return Faction{}, ErrInvalid }
	var characterInWorld bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(
		SELECT 1 FROM souls s JOIN characters c ON c.id=s.current_character_id
		WHERE s.account_id=$1 AND c.world_id=$2 AND c.status='alive'
	)`, accountID, worldID).Scan(&characterInWorld); err != nil {
		return Faction{}, fmt.Errorf("validate founder world presence: %w", err)
	}
	if !characterInWorld { return Faction{}, ErrForbidden }
	var result Faction
	err = tx.QueryRowContext(ctx, `INSERT INTO factions
		(world_id, faction_type, name, description, created_by)
		VALUES ($1, 'sect', $2, $3, $4)
		RETURNING id::text, world_id, faction_type, name, description, level`,
		worldID, name, description, accountID).Scan(&result.ID, &result.WorldID, &result.Type,
		&result.Name, &result.Description, &result.Level)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "uq_factions_world_name") { return Faction{}, ErrInvalid }
		return Faction{}, fmt.Errorf("insert sect: %w", err)
	}
	var treasuryID string
	if err := tx.QueryRowContext(ctx, `INSERT INTO economy_treasury_accounts
		(world_id, account_key, display_name, account_type)
		VALUES ($1, $2, $3, 'faction_treasury') RETURNING id::text`,
		worldID, "faction:"+result.ID, name+"库").Scan(&treasuryID); err != nil {
		return Faction{}, fmt.Errorf("create sect treasury account: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `UPDATE factions SET treasury_account_id=$2 WHERE id=$1`, result.ID, treasuryID); err != nil {
		return Faction{}, fmt.Errorf("attach sect treasury account: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO faction_members(faction_id, account_id, role)
		VALUES ($1, $2, 'leader')`, result.ID, accountID); err != nil {
		return Faction{}, fmt.Errorf("appoint sect founder: %w", err)
	}
	if err := tx.Commit(); err != nil { return Faction{}, fmt.Errorf("commit sect creation: %w", err) }
	result.Role = "leader"
	result.TreasuryAccountID = treasuryID
	result.MemberCount = 1
	return result, nil
}

func (s *Service) ListMine(ctx context.Context, accountID string) ([]Faction, error) {
	if accountID == "" { return nil, ErrInvalid }
	rows, err := s.db.QueryContext(ctx, `SELECT f.id::text, f.world_id, f.faction_type, f.name,
		f.description, f.level, COALESCE(f.treasury_account_id::text, ''), m.role,
		(SELECT count(*) FROM faction_members count_members WHERE count_members.faction_id=f.id)
		FROM faction_members m JOIN factions f ON f.id=m.faction_id
		WHERE m.account_id=$1 AND f.status='active'
		ORDER BY m.joined_at DESC`, accountID)
	if err != nil { return nil, fmt.Errorf("list account factions: %w", err) }
	defer rows.Close()
	result := make([]Faction, 0)
	for rows.Next() {
		var item Faction
		if err := rows.Scan(&item.ID, &item.WorldID, &item.Type, &item.Name,
			&item.Description, &item.Level, &item.TreasuryAccountID, &item.Role, &item.MemberCount); err != nil {
			return nil, fmt.Errorf("scan faction: %w", err)
		}
		result = append(result, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate factions: %w", err) }
	return result, nil
}

func (s *Service) Apply(ctx context.Context, accountID, factionID, message string) (Application, error) {
	message = strings.TrimSpace(message)
	if accountID == "" || factionID == "" || utf8.RuneCountInString(message) > 240 { return Application{}, ErrInvalid }
	var member bool
	if err := s.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM faction_members WHERE faction_id=$1 AND account_id=$2)`, factionID, accountID).Scan(&member); err != nil {
		return Application{}, fmt.Errorf("check faction membership: %w", err)
	}
	if member { return Application{}, ErrAlreadyMember }
	var result Application
	err := s.db.QueryRowContext(ctx, `INSERT INTO faction_membership_applications(faction_id, account_id, message)
		SELECT id, $2, $3 FROM factions WHERE id=$1 AND status='active'
		RETURNING id::text, faction_id::text, account_id::text, message, status, created_at::text`,
		factionID, accountID, message).Scan(&result.ID, &result.FactionID, &result.AccountID,
		&result.Message, &result.Status, &result.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) { return Application{}, ErrNotFound }
		if strings.Contains(strings.ToLower(err.Error()), "uq_faction_pending_application") { return Application{}, ErrPendingApplication }
		return Application{}, fmt.Errorf("create faction application: %w", err)
	}
	return result, nil
}

func (s *Service) ReviewApplication(ctx context.Context, reviewerID, factionID, applicationID, decision string) error {
	if reviewerID == "" || factionID == "" || applicationID == "" || (decision != "approve" && decision != "reject") { return ErrInvalid }
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return fmt.Errorf("begin faction application review: %w", err) }
	defer tx.Rollback()
	var role, applicantID, status string
	err = tx.QueryRowContext(ctx, `SELECT m.role, a.account_id::text, a.status
		FROM faction_members m
		JOIN faction_membership_applications a ON a.faction_id=m.faction_id
		JOIN factions f ON f.id=m.faction_id AND f.status='active'
		WHERE m.faction_id=$1 AND m.account_id=$2 AND a.id=$3
		FOR UPDATE OF a`, factionID, reviewerID, applicationID).Scan(&role, &applicantID, &status)
	if errors.Is(err, sql.ErrNoRows) { return ErrForbidden }
	if err != nil { return fmt.Errorf("authorize faction application review: %w", err) }
	if !canManageRole(role) { return ErrForbidden }
	if status != "pending" { return ErrInvalid }
	if decision == "approve" {
		if _, err := tx.ExecContext(ctx, `INSERT INTO faction_members(faction_id, account_id, role)
			VALUES ($1, $2, 'member') ON CONFLICT (faction_id, account_id) DO NOTHING`, factionID, applicantID); err != nil {
			return fmt.Errorf("add approved faction member: %w", err)
		}
	}
	nextStatus := "rejected"
	if decision == "approve" { nextStatus = "approved" }
	if _, err := tx.ExecContext(ctx, `UPDATE faction_membership_applications
		SET status=$2, reviewed_by=$3, reviewed_at=now() WHERE id=$1`, applicationID, nextStatus, reviewerID); err != nil {
		return fmt.Errorf("update faction application: %w", err)
	}
	if err := tx.Commit(); err != nil { return fmt.Errorf("commit faction application review: %w", err) }
	return nil
}

func (s *Service) ListApplications(ctx context.Context, reviewerID, factionID string) ([]Application, error) {
	if reviewerID == "" || factionID == "" { return nil, ErrInvalid }
	var role string
	if err := s.db.QueryRowContext(ctx, `SELECT m.role FROM faction_members m JOIN factions f ON f.id=m.faction_id AND f.status='active' WHERE m.faction_id=$1 AND m.account_id=$2`, factionID, reviewerID).Scan(&role); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return nil, ErrForbidden }
		return nil, fmt.Errorf("authorize application listing: %w", err)
	}
	if !canManageRole(role) { return nil, ErrForbidden }
	rows, err := s.db.QueryContext(ctx, `SELECT id::text, faction_id::text, account_id::text, message, status, created_at::text
		FROM faction_membership_applications WHERE faction_id=$1 AND status='pending' ORDER BY created_at`, factionID)
	if err != nil { return nil, fmt.Errorf("list pending applications: %w", err) }
	defer rows.Close()
	result := make([]Application, 0)
	for rows.Next() {
		var item Application
		if err := rows.Scan(&item.ID, &item.FactionID, &item.AccountID, &item.Message, &item.Status, &item.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan faction application: %w", err)
		}
		result = append(result, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate faction applications: %w", err) }
	return result, nil
}

func canManageRole(role string) bool { return role == "leader" || role == "officer" }

func (s *Service) AuthorizeTaskPublisher(ctx context.Context, accountID, factionID string) error {
	if accountID == "" || factionID == "" { return ErrForbidden }
	var role string
	err := s.db.QueryRowContext(ctx, `SELECT m.role FROM faction_members m
		JOIN factions f ON f.id=m.faction_id
		WHERE m.faction_id=$1 AND m.account_id=$2 AND f.status='active'`, factionID, accountID).Scan(&role)
	if errors.Is(err, sql.ErrNoRows) { return ErrForbidden }
	if err != nil { return fmt.Errorf("authorize faction task publisher: %w", err) }
	if !canManageRole(role) { return ErrForbidden }
	return nil
}


func (s *Service) ListMembers(ctx context.Context, requesterID, factionID string) ([]Member, error) {
	if requesterID == "" || factionID == "" { return nil, ErrInvalid }
	var member bool
	if err := s.db.QueryRowContext(ctx, `SELECT EXISTS(
		SELECT 1 FROM faction_members m JOIN factions f ON f.id=m.faction_id AND f.status='active'
		WHERE m.faction_id=$1 AND m.account_id=$2
	)`, factionID, requesterID).Scan(&member); err != nil {
		return nil, fmt.Errorf("authorize faction member listing: %w", err)
	}
	if !member { return nil, ErrForbidden }
	rows, err := s.db.QueryContext(ctx, `SELECT account_id::text, role, contribution_points, joined_at::text
		FROM faction_members WHERE faction_id=$1
		ORDER BY CASE role WHEN 'leader' THEN 0 WHEN 'officer' THEN 1 ELSE 2 END, joined_at`, factionID)
	if err != nil { return nil, fmt.Errorf("list faction members: %w", err) }
	defer rows.Close()
	result := make([]Member, 0)
	for rows.Next() {
		var item Member
		if err := rows.Scan(&item.AccountID, &item.Role, &item.ContributionPoints, &item.JoinedAt); err != nil {
			return nil, fmt.Errorf("scan faction member: %w", err)
		}
		result = append(result, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate faction members: %w", err) }
	return result, nil
}
