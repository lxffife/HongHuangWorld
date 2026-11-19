package adminauth

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

type AuditFilter struct {
	ActorID string
	Action string
	Result string
	From *time.Time
	To *time.Time
	Limit int
	Offset int
}

type AuditEntry struct {
	ID int64 `json:"id"`
	ActorUserID *string `json:"actor_user_id,omitempty"`
	ActorUsername string `json:"actor_username,omitempty"`
	Action string `json:"action"`
	ResourceType string `json:"resource_type"`
	ResourceID string `json:"resource_id"`
	Result string `json:"result"`
	Details map[string]any `json:"details"`
	RemoteAddr *string `json:"remote_addr,omitempty"`
	UserAgent string `json:"user_agent,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type AuditPage struct {
	Items []AuditEntry `json:"items"`
	Total int64 `json:"total"`
	Limit int `json:"limit"`
	Offset int `json:"offset"`
}

func (s *Service) ListAuditLogs(ctx context.Context, f AuditFilter) (AuditPage, error) {
	if f.Limit < 1 || f.Limit > 100 { f.Limit = 50 }
	if f.Offset < 0 { f.Offset = 0 }
	where := []string{"1=1"}
	args := []any{}
	add := func(expr string, value any) {
		args = append(args, value)
		where = append(where, fmt.Sprintf(expr, len(args)))
	}
	if f.ActorID != "" { add("l.actor_user_id = $%d", f.ActorID) }
	if f.Action != "" { add("l.action = $%d", f.Action) }
	if f.Result != "" { add("l.result = $%d", f.Result) }
	if f.From != nil { add("l.created_at >= $%d", *f.From) }
	if f.To != nil { add("l.created_at < $%d", *f.To) }
	clause := strings.Join(where, " AND ")
	var total int64
	if err := s.db.QueryRowContext(ctx, "SELECT count(*) FROM admin_audit_logs l WHERE "+clause, args...).Scan(&total); err != nil {
		return AuditPage{}, err
	}
	queryArgs := append([]any{}, args...)
	queryArgs = append(queryArgs, f.Limit, f.Offset)
	query := "SELECT l.id,l.actor_user_id::text,COALESCE(u.username,''),l.action,l.resource_type,l.resource_id,l.result,l.details,host(l.remote_addr),l.user_agent,l.created_at " +
		"FROM admin_audit_logs l LEFT JOIN admin_users u ON u.id=l.actor_user_id WHERE " + clause +
		fmt.Sprintf(" ORDER BY l.created_at DESC,l.id DESC LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	rows, err := s.db.QueryContext(ctx, query, queryArgs...)
	if err != nil { return AuditPage{}, err }
	defer rows.Close()
	out := AuditPage{Items: []AuditEntry{}, Total: total, Limit: f.Limit, Offset: f.Offset}
	for rows.Next() {
		var item AuditEntry
		var actor, remote sql.NullString
		var details []byte
		if err := rows.Scan(&item.ID,&actor,&item.ActorUsername,&item.Action,&item.ResourceType,&item.ResourceID,&item.Result,&details,&remote,&item.UserAgent,&item.CreatedAt); err != nil {
			return AuditPage{}, err
		}
		if actor.Valid { item.ActorUserID = &actor.String }
		if remote.Valid { item.RemoteAddr = &remote.String }
		item.Details = map[string]any{}
		if len(details) > 0 { if err := json.Unmarshal(details, &item.Details); err != nil { return AuditPage{}, err } }
		out.Items = append(out.Items, item)
	}
	if err := rows.Err(); err != nil { return AuditPage{}, err }
	return out, nil
}
