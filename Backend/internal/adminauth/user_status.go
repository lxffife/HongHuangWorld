package adminauth

import (
	"context"
	"encoding/json"
	"errors"
)

func (s *Service) SetUserStatus(ctx context.Context, actor User, targetID, status string) error {
	if status != "active" && status != "disabled" { return ErrInvalidInput }
	if targetID == actor.ID { return ErrForbidden }
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return err }
	defer tx.Rollback()
	var exists bool
	err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM admin_users WHERE id=$1 AND is_super_admin=false)`, targetID).Scan(&exists)
	if err != nil {
		var pgErr interface{ SQLState() string }
		if errors.As(err, &pgErr) && pgErr.SQLState() == "22P02" { return ErrInvalidInput }
		return err
	}
	if !exists { return ErrInvalidInput }
	if _, err = tx.ExecContext(ctx, `UPDATE admin_users SET status=$2,updated_at=now() WHERE id=$1`, targetID, status); err != nil { return err }
	details, _ := json.Marshal(map[string]string{"status": status})
	if _, err = tx.ExecContext(ctx, `INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details) VALUES($1,'admin.user.status','admin_user',$2,'success',$3::jsonb)`, actor.ID, targetID, string(details)); err != nil { return err }
	return tx.Commit()
}

