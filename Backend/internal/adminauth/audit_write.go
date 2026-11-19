package adminauth

import (
	"context"
	"encoding/json"
)

func (s *Service) RecordAudit(ctx context.Context, actor User, action, resourceType, resourceID, result string, details map[string]any) error {
	if result!="success"&&result!="failure"&&result!="denied" { result="failure" }
	payload,err:=json.Marshal(details);if err!=nil{return err}
	_,err=s.db.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details) VALUES($1,$2,$3,$4,$5,$6::jsonb)`,actor.ID,action,resourceType,resourceID,result,string(payload))
	return err
}
