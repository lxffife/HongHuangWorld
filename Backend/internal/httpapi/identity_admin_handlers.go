package httpapi

import (
	"crypto/subtle"
	"database/sql"
	"errors"
	"strconv"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

type identityAdminHandlers struct {
	db *sql.DB
	internalKey string
	logger *slog.Logger
}

type identityAccountAdminItem struct {
	ID string `json:"id"`
	Username string `json:"username"`
	Email *string `json:"email,omitempty"`
	Status string `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

func (h *identityAdminHandlers) authorize(w http.ResponseWriter,r *http.Request) bool {
	provided:=r.Header.Get("X-Identity-Service-Key")
	if h.internalKey=="" || len(provided)!=len(h.internalKey) || subtle.ConstantTimeCompare([]byte(provided),[]byte(h.internalKey))!=1 {
		http.Error(w,"unauthorized service",http.StatusUnauthorized);return false
	}
	return true
}

func (h *identityAdminHandlers) listAccounts(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return}
	q:=strings.TrimSpace(r.URL.Query().Get("q"))
	if len(q)>64 { http.Error(w,"search query too long",http.StatusBadRequest);return }
	limit:=50
	if raw:=r.URL.Query().Get("limit");raw!="" { n,err:=strconv.Atoi(raw);if err!=nil||n<1||n>100 {http.Error(w,"limit must be between 1 and 100",http.StatusBadRequest);return};limit=n }
	rows,err:=h.db.QueryContext(r.Context(),`SELECT id::text,username,email,status,created_at FROM accounts WHERE ($1='' OR username ILIKE '%'||$1||'%' OR COALESCE(email,'') ILIKE '%'||$1||'%') ORDER BY created_at DESC,id DESC LIMIT $2`,q,limit)
	if err!=nil { h.logger.Error("identity admin account search failed","error",err);http.Error(w,"internal server error",500);return }
	defer rows.Close()
	items:=[]identityAccountAdminItem{}
	for rows.Next(){var item identityAccountAdminItem;var email sql.NullString;if err:=rows.Scan(&item.ID,&item.Username,&email,&item.Status,&item.CreatedAt);err!=nil{http.Error(w,"internal server error",500);return};if email.Valid{item.Email=&email.String};items=append(items,item)}
	if err:=rows.Err();err!=nil{h.logger.Error("identity admin account iteration failed","error",err);http.Error(w,"internal server error",500);return}
	writeJSON(w,200,map[string]any{"items":items})
}

func (h *identityAdminHandlers) setAccountStatus(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return}
	var req struct { Status string `json:"status"` }
	if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	if req.Status!="active"&&req.Status!="locked"&&req.Status!="disabled"{http.Error(w,"status must be active, locked or disabled",400);return}
	id:=strings.TrimSpace(r.PathValue("id"))
	tx,err:=h.db.BeginTx(r.Context(),nil);if err!=nil{http.Error(w,"internal server error",500);return};defer tx.Rollback()
	var exists bool
	err=tx.QueryRowContext(r.Context(),`SELECT EXISTS(SELECT 1 FROM accounts WHERE id=$1::uuid)`,id).Scan(&exists)
	if err!=nil { var pgErr *pgconn.PgError;if errors.As(err,&pgErr)&&pgErr.Code=="22P02"{http.Error(w,"invalid account id",400);return};h.logger.Error("identity admin account lookup failed","error",err);http.Error(w,"internal server error",500);return }
	if !exists{http.Error(w,"account not found",404);return}
	if _,err=tx.ExecContext(r.Context(),`UPDATE accounts SET status=$2,updated_at=now() WHERE id=$1::uuid`,id,req.Status);err!=nil{h.logger.Error("identity admin account status update failed","error",err);http.Error(w,"internal server error",500);return}
	if req.Status!="active" { if _,err=tx.ExecContext(r.Context(),`UPDATE account_sessions SET revoked_at=now() WHERE account_id=$1::uuid AND revoked_at IS NULL`,id);err!=nil{h.logger.Error("identity admin session revoke failed","error",err);http.Error(w,"internal server error",500);return} }
	if err=tx.Commit();err!=nil{http.Error(w,"internal server error",500);return}
	writeJSON(w,200,map[string]string{"status":req.Status})
}

func (h *identityAdminHandlers) getAccount(w http.ResponseWriter, r *http.Request) {
 if !h.authorize(w,r) { return }
 id:=strings.TrimSpace(r.PathValue("id"))
 var item identityAccountAdminItem
 var email sql.NullString
 err:=h.db.QueryRowContext(r.Context(),`
  SELECT id::text,username,email,status,created_at FROM accounts WHERE id=$1::uuid
 `,id).Scan(&item.ID,&item.Username,&email,&item.Status,&item.CreatedAt)
 if err!=nil {
  var pgErr *pgconn.PgError
  if errors.As(err,&pgErr)&&pgErr.Code=="22P02" { http.Error(w,"invalid account id",http.StatusBadRequest);return }
  if errors.Is(err,sql.ErrNoRows) { http.Error(w,"account not found",http.StatusNotFound);return }
  h.logger.Error("identity admin account detail failed","error",err)
  http.Error(w,"internal server error",http.StatusInternalServerError);return
 }
 if email.Valid { item.Email=&email.String }
 writeJSON(w,http.StatusOK,item)
}
