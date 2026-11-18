package adminauth

import (
 "context"
 "crypto/rand"
 "crypto/sha256"
 "database/sql"
 "encoding/json"
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
 ErrInvalidInput = errors.New("invalid input")
 ErrInvalidCredentials = errors.New("invalid username or password")
 ErrUnauthorized = errors.New("unauthorized")
 ErrForbidden = errors.New("forbidden")
 ErrConflict = errors.New("conflict")
 ErrBootstrapRequired = errors.New("no super administrator exists; configure ADMIN_BOOTSTRAP_USERNAME and ADMIN_BOOTSTRAP_PASSWORD")
 adminUsernamePattern = regexp.MustCompile(`^[A-Za-z0-9_]{3,32}$`)
)

type User struct {
 ID string `json:"id"`
 Username string `json:"username"`
 Email *string `json:"email,omitempty"`
 IsSuperAdmin bool `json:"is_super_admin"`
 Permissions []string `json:"permissions"`
}

type Service struct { db *sql.DB; sessionTTL time.Duration }

func NewService(db *sql.DB) *Service { return &Service{db:db, sessionTTL:12*time.Hour} }

func (s *Service) Bootstrap(ctx context.Context, username,email,password string) (bool,error) {
 username=strings.TrimSpace(username); email=strings.TrimSpace(email)
 var exists bool
 if err:=s.db.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM admin_users WHERE is_super_admin=true AND status='active')`).Scan(&exists); err!=nil { return false,fmt.Errorf("check bootstrap administrator: %w",err) }
 if exists { return false,nil }
 if username=="" || password=="" { return false,ErrBootstrapRequired }
 if !adminUsernamePattern.MatchString(username) || len(password)<12 || len(password)>72 || (email!="" && (len(email)>254 || !strings.Contains(email,"@"))) { return false,ErrInvalidInput }
 hash,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.DefaultCost); if err!=nil { return false,fmt.Errorf("hash bootstrap password: %w",err) }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return false,err }; defer tx.Rollback()
 if _,err=tx.ExecContext(ctx,`SELECT pg_advisory_xact_lock(7419202601)`); err!=nil { return false,fmt.Errorf("lock admin bootstrap: %w",err) }
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM admin_users WHERE is_super_admin=true AND status='active')`).Scan(&exists); err!=nil { return false,err }
 if exists { return false,nil }
 var id string
 err=tx.QueryRowContext(ctx,`INSERT INTO admin_users(username,email,password_hash,is_super_admin) VALUES($1,NULLIF($2,''),$3,true) RETURNING id::text`,username,email,string(hash)).Scan(&id)
 if err!=nil { var pgErr *pgconn.PgError; if errors.As(err,&pgErr)&&pgErr.Code=="23505" { return false,ErrConflict }; return false,fmt.Errorf("create bootstrap administrator: %w",err) }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_user_roles(user_id,role_id) SELECT $1,id FROM admin_roles WHERE role_key='super_admin' ON CONFLICT DO NOTHING`,id); err!=nil { return false,err }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details) VALUES($1,'admin.bootstrap','admin_user',$1,'success','{}'::jsonb)`,id); err!=nil { return false,err }
 if err=tx.Commit(); err!=nil { return false,err }; return true,nil
}

func (s *Service) Login(ctx context.Context,username,password,remote,agent string) (User,string,time.Time,error) {
 username=strings.TrimSpace(username)
 var user User; var hash,status string; var email sql.NullString
 err:=s.db.QueryRowContext(ctx,`SELECT id::text,username,email,password_hash,status,is_super_admin FROM admin_users WHERE lower(username)=lower($1)`,username).Scan(&user.ID,&user.Username,&email,&hash,&status,&user.IsSuperAdmin)
 if err!=nil || status!="active" || bcrypt.CompareHashAndPassword([]byte(hash),[]byte(password))!=nil {
  _=s.audit(ctx,nil,"admin.login","admin_user",username,"failure",`{"reason":"invalid_credentials"}`,remote,agent)
  return User{},"",time.Time{},ErrInvalidCredentials
 }
 if email.Valid { user.Email=&email.String }
 token,tokenHash,expires,err:=newToken(s.sessionTTL); if err!=nil { return User{},"",time.Time{},err }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return User{},"",time.Time{},err }; defer tx.Rollback()
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_sessions(user_id,token_hash,expires_at) VALUES($1,$2,$3)`,user.ID,tokenHash[:],expires); err!=nil { return User{},"",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`UPDATE admin_users SET last_login_at=now(),updated_at=now() WHERE id=$1`,user.ID); err!=nil { return User{},"",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details,remote_addr,user_agent) VALUES($1,'admin.login','admin_user',$1,'success','{}'::jsonb,NULLIF($2,'')::inet,$3)`,user.ID,remote,agent); err!=nil { return User{},"",time.Time{},err }
 if err=tx.Commit(); err!=nil { return User{},"",time.Time{},err }
 user,err=s.loadPermissions(ctx,user); if err!=nil { return User{},"",time.Time{},err }
 return user,token,expires,nil
}

func (s *Service) Authenticate(ctx context.Context,token string) (User,error) {
 if token=="" || len(token)>128 { return User{},ErrUnauthorized }
 sum:=sha256.Sum256([]byte(token)); var u User; var email sql.NullString
 err:=s.db.QueryRowContext(ctx,`SELECT u.id::text,u.username,u.email,u.is_super_admin FROM admin_sessions ss JOIN admin_users u ON u.id=ss.user_id WHERE ss.token_hash=$1 AND ss.expires_at>now() AND ss.revoked_at IS NULL AND u.status='active'`,sum[:]).Scan(&u.ID,&u.Username,&email,&u.IsSuperAdmin)
 if err!=nil { return User{},ErrUnauthorized }; if email.Valid { u.Email=&email.String }
 u,err=s.loadPermissions(ctx,u); if err!=nil { return User{},err }; return u,nil
}

func (s *Service) loadPermissions(ctx context.Context,u User) (User,error) {
 rows,err:=s.db.QueryContext(ctx,`SELECT permission_key FROM admin_user_permissions WHERE user_id=$1 UNION SELECT rp.permission_key FROM admin_user_roles ur JOIN admin_role_permissions rp ON rp.role_id=ur.role_id WHERE ur.user_id=$1 ORDER BY permission_key`,u.ID)
 if err!=nil { return User{},err }; defer rows.Close()
 u.Permissions=[]string{}
 for rows.Next() { var p string; if err:=rows.Scan(&p); err!=nil { return User{},err }; u.Permissions=append(u.Permissions,p) }
 return u,rows.Err()
}

func (s *Service) ChangePassword(ctx context.Context,u User,current,next,remote,agent string) (string,time.Time,error) {
 if len(next)<12 || len(next)>72 { return "",time.Time{},ErrInvalidInput }
 var oldHash string
 if err:=s.db.QueryRowContext(ctx,`SELECT password_hash FROM admin_users WHERE id=$1 AND status='active'`,u.ID).Scan(&oldHash); err!=nil { return "",time.Time{},ErrUnauthorized }
 if bcrypt.CompareHashAndPassword([]byte(oldHash),[]byte(current))!=nil { return "",time.Time{},ErrInvalidCredentials }
 hash,err:=bcrypt.GenerateFromPassword([]byte(next),bcrypt.DefaultCost); if err!=nil { return "",time.Time{},err }
 token,tokenHash,expires,err:=newToken(s.sessionTTL); if err!=nil { return "",time.Time{},err }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return "",time.Time{},err }; defer tx.Rollback()
 if _,err=tx.ExecContext(ctx,`UPDATE admin_users SET password_hash=$2,password_changed_at=now(),updated_at=now() WHERE id=$1`,u.ID,string(hash)); err!=nil { return "",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`UPDATE admin_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL`,u.ID); err!=nil { return "",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_sessions(user_id,token_hash,expires_at) VALUES($1,$2,$3)`,u.ID,tokenHash[:],expires); err!=nil { return "",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details,remote_addr,user_agent) VALUES($1,'admin.password.change','admin_user',$1,'success','{}'::jsonb,NULLIF($2,'')::inet,$3)`,u.ID,remote,agent); err!=nil { return "",time.Time{},err }
 if err=tx.Commit(); err!=nil { return "",time.Time{},err }; return token,expires,nil
}

func (s *Service) CreateUser(ctx context.Context,actor User,username,email,password string) (User,error) {
 username=strings.TrimSpace(username); email=strings.TrimSpace(email)
 if !adminUsernamePattern.MatchString(username)||len(password)<12||len(password)>72||(email!=""&&(len(email)>254||!strings.Contains(email,"@"))) { return User{},ErrInvalidInput }
 hash,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.DefaultCost); if err!=nil { return User{},err }
 var u User; var em sql.NullString
 err=s.db.QueryRowContext(ctx,`INSERT INTO admin_users(username,email,password_hash,created_by) VALUES($1,NULLIF($2,''),$3,$4) RETURNING id::text,username,email,is_super_admin`,username,email,string(hash),actor.ID).Scan(&u.ID,&u.Username,&em,&u.IsSuperAdmin)
 if err!=nil { var pgErr *pgconn.PgError; if errors.As(err,&pgErr)&&pgErr.Code=="23505" { return User{},ErrConflict }; return User{},err }
 if em.Valid { u.Email=&em.String }
 _=s.audit(ctx,&actor.ID,"admin.user.create","admin_user",u.ID,"success",`{"username":"`+username+`"}`,"","")
 return u,nil
}

func (s *Service) SetPermissions(ctx context.Context,actor User,targetID string,permissions []string) error {
 if len(permissions)>64 { return ErrInvalidInput }
 seen:=map[string]bool{}
 for _,p:=range permissions { p=strings.TrimSpace(p); if p==""||len(p)>96||seen[p] { return ErrInvalidInput }; seen[p]=true; if p=="admin_users.manage"&&!actor.IsSuperAdmin { return ErrForbidden } }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return err }; defer tx.Rollback()
 var targetExists bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM admin_users WHERE id=$1 AND status='active' AND is_super_admin=false)`,targetID).Scan(&targetExists); err!=nil { return err }; if !targetExists { return ErrInvalidInput }
 if _,err=tx.ExecContext(ctx,`DELETE FROM admin_user_permissions WHERE user_id=$1`,targetID); err!=nil { return err }
 for p:=range seen { if _,err=tx.ExecContext(ctx,`INSERT INTO admin_user_permissions(user_id,permission_key,granted_by) VALUES($1,$2,$3)`,targetID,p,actor.ID); err!=nil { var pgErr *pgconn.PgError; if errors.As(err,&pgErr)&&pgErr.Code=="23503" { return ErrInvalidInput }; return err } }
 details,marshalErr:=json.Marshal(map[string][]string{"permissions":permissions}); if marshalErr!=nil{return marshalErr}
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details) VALUES($1,'admin.permissions.set','admin_user',$2,'success',$3::jsonb)`,actor.ID,targetID,string(details)); err!=nil { return err }
 return tx.Commit()
}

func (s *Service) ListPermissions(ctx context.Context) ([]map[string]string,error) {
 rows,err:=s.db.QueryContext(ctx,`SELECT permission_key,name FROM admin_permissions ORDER BY permission_key`); if err!=nil{return nil,err}; defer rows.Close()
 out:=[]map[string]string{}; for rows.Next(){var k,n string;if err:=rows.Scan(&k,&n);err!=nil{return nil,err};out=append(out,map[string]string{"key":k,"name":n})};return out,rows.Err()
}

func (s *Service) ListUsers(ctx context.Context) ([]User,error) {
 rows,err:=s.db.QueryContext(ctx,`SELECT id::text,username,email,is_super_admin FROM admin_users ORDER BY created_at DESC`);if err!=nil{return nil,err};defer rows.Close()
 out:=[]User{};for rows.Next(){var u User;var e sql.NullString;if err:=rows.Scan(&u.ID,&u.Username,&e,&u.IsSuperAdmin);err!=nil{return nil,err};if e.Valid{u.Email=&e.String};out=append(out,u)};return out,rows.Err()
}

func (s *Service) audit(ctx context.Context,actor *string,action,kind,id,result,details,remote,agent string) error {
 _,err:=s.db.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details,remote_addr,user_agent) VALUES($1,$2,$3,$4,$5,$6::jsonb,NULLIF($7,'')::inet,$8)`,actor,action,kind,id,result,details,remote,agent);return err
}

func newToken(ttl time.Duration)(string,[32]byte,time.Time,error){
 var raw [32]byte;if _,err:=rand.Read(raw[:]);err!=nil{return "",[32]byte{},time.Time{},err}
 token:=base64.RawURLEncoding.EncodeToString(raw[:]);return token,sha256.Sum256([]byte(token)),time.Now().UTC().Add(ttl),nil
}
