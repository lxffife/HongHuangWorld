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
 Status string `json:"status"`
 LastLoginAt *time.Time `json:"last_login_at,omitempty"`
 Permissions []string `json:"permissions"`
}

type Service struct { db *sql.DB; sessionTTL time.Duration }

func NewService(db *sql.DB) *Service { return &Service{db:db, sessionTTL:12*time.Hour} }

func (s *Service) Bootstrap(ctx context.Context, username,email,password string) (bool,error) {
 username=strings.TrimSpace(username); email=strings.TrimSpace(email)
 var exists bool
 if err:=s.db.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM admin_users WHERE is_super_admin=true)`).Scan(&exists); err!=nil { return false,fmt.Errorf("check bootstrap administrator: %w",err) }
 if exists { return false,nil }
 if username=="" || password=="" { return false,ErrBootstrapRequired }
 if !adminUsernamePattern.MatchString(username) || len(password)<12 || len(password)>72 || strings.Contains(strings.ToLower(password),"replace-with") || (email!="" && (len(email)>254 || !strings.Contains(email,"@"))) { return false,ErrInvalidInput }
 hash,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.DefaultCost); if err!=nil { return false,fmt.Errorf("hash bootstrap password: %w",err) }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return false,err }; defer tx.Rollback()
 if _,err=tx.ExecContext(ctx,`SELECT pg_advisory_xact_lock(7419202601)`); err!=nil { return false,fmt.Errorf("lock admin bootstrap: %w",err) }
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM admin_users WHERE is_super_admin=true)`).Scan(&exists); err!=nil { return false,err }
 if exists { return false,nil }
 var id string
 err=tx.QueryRowContext(ctx,`INSERT INTO admin_users(username,email,password_hash,is_super_admin) VALUES($1,NULLIF($2,''),$3,true) RETURNING id::text`,username,email,string(hash)).Scan(&id)
 if err!=nil { var pgErr *pgconn.PgError; if errors.As(err,&pgErr)&&pgErr.Code=="23505" { return false,ErrConflict }; return false,fmt.Errorf("create bootstrap administrator: %w",err) }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_user_roles(user_id,role_id) SELECT $1,id FROM admin_roles WHERE role_key='super_admin' ON CONFLICT DO NOTHING`,id); err!=nil { return false,err }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details) VALUES($1,'admin.bootstrap','admin_user',$2,'success','{}'::jsonb)`,id,id); err!=nil { return false,err }
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
 user.Status = status
 token,tokenHash,expires,err:=newToken(s.sessionTTL); if err!=nil { return User{},"",time.Time{},err }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return User{},"",time.Time{},err }; defer tx.Rollback()
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_sessions(user_id,token_hash,expires_at) VALUES($1,$2,$3)`,user.ID,tokenHash[:],expires); err!=nil { return User{},"",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`UPDATE admin_users SET last_login_at=now(),updated_at=now() WHERE id=$1`,user.ID); err!=nil { return User{},"",time.Time{},err }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details,remote_addr,user_agent) VALUES($1,'admin.login','admin_user',$2,'success','{}'::jsonb,NULLIF($3,'')::inet,$4)`,user.ID,user.ID,remote,agent); err!=nil { return User{},"",time.Time{},err }
 if err=tx.Commit(); err!=nil { return User{},"",time.Time{},err }
 loggedInAt := time.Now().UTC()
 user.LastLoginAt = &loggedInAt
 user,err=s.loadPermissions(ctx,user); if err!=nil { return User{},"",time.Time{},err }
 return user,token,expires,nil
}

func (s *Service) Authenticate(ctx context.Context,token string) (User,error) {
 if token=="" || len(token)>128 { return User{},ErrUnauthorized }
 sum:=sha256.Sum256([]byte(token)); var u User; var email sql.NullString; var lastLogin sql.NullTime
 err:=s.db.QueryRowContext(ctx,`SELECT u.id::text,u.username,u.email,u.is_super_admin,u.status,u.last_login_at FROM admin_sessions ss JOIN admin_users u ON u.id=ss.user_id WHERE ss.token_hash=$1 AND ss.expires_at>now() AND ss.revoked_at IS NULL AND u.status='active'`,sum[:]).Scan(&u.ID,&u.Username,&email,&u.IsSuperAdmin,&u.Status,&lastLogin)
 if err!=nil { return User{},ErrUnauthorized }; if email.Valid { u.Email=&email.String }; if lastLogin.Valid { value:=lastLogin.Time; u.LastLoginAt=&value }
 u,err=s.loadPermissions(ctx,u); if err!=nil { return User{},err }; return u,nil
}

func (s *Service) loadPermissions(ctx context.Context,u User) (User,error) {
 rows,err:=s.db.QueryContext(ctx,`SELECT permission_key FROM admin_user_permissions WHERE user_id=$1 UNION SELECT rp.permission_key FROM admin_user_roles ur JOIN admin_role_permissions rp ON rp.role_id=ur.role_id WHERE ur.user_id=$1 ORDER BY permission_key`,u.ID)
 if err!=nil { return User{},err }; defer rows.Close()
 u.Permissions=[]string{}
 for rows.Next() { var p string; if err:=rows.Scan(&p); err!=nil { return User{},err }; u.Permissions=append(u.Permissions,p) }
 return u,rows.Err()
}

func (s *Service) RevokeSession(ctx context.Context,token string) error {
 if token==""||len(token)>128{return ErrUnauthorized}
 sum:=sha256.Sum256([]byte(token))
 _,err:=s.db.ExecContext(ctx,`UPDATE admin_sessions SET revoked_at=now() WHERE token_hash=$1 AND revoked_at IS NULL`,sum[:])
 return err
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
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details,remote_addr,user_agent) VALUES($1,'admin.password.change','admin_user',$2,'success','{}'::jsonb,NULLIF($3,'')::inet,$4)`,u.ID,u.ID,remote,agent); err!=nil { return "",time.Time{},err }
 if err=tx.Commit(); err!=nil { return "",time.Time{},err }; return token,expires,nil
}

func (s *Service) CreateUser(ctx context.Context,actor User,username,email,password string) (User,error) {
 username=strings.TrimSpace(username); email=strings.TrimSpace(email)
 if !adminUsernamePattern.MatchString(username)||len(password)<12||len(password)>72||(email!=""&&(len(email)>254||!strings.Contains(email,"@"))) { return User{},ErrInvalidInput }
 hash,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.DefaultCost); if err!=nil { return User{},err }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return User{},fmt.Errorf("begin admin user creation: %w",err) }; defer tx.Rollback()
 var u User; var em sql.NullString
 var lastLogin sql.NullTime
 err=tx.QueryRowContext(ctx,`INSERT INTO admin_users(username,email,password_hash,created_by) VALUES($1,NULLIF($2,''),$3,$4) RETURNING id::text,username,email,is_super_admin,status,last_login_at`,username,email,string(hash),actor.ID).Scan(&u.ID,&u.Username,&em,&u.IsSuperAdmin,&u.Status,&lastLogin)
 if err!=nil { var pgErr *pgconn.PgError; if errors.As(err,&pgErr)&&pgErr.Code=="23505" { return User{},ErrConflict }; return User{},fmt.Errorf("insert admin user: %w",err) }
 if em.Valid { u.Email=&em.String }
 details,err:=json.Marshal(map[string]string{"username":u.Username})
 if err!=nil { return User{},fmt.Errorf("encode admin user audit: %w",err) }
 if _,err=tx.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details) VALUES($1,'admin.user.create','admin_user',$2,'success',$3::jsonb)`,actor.ID,u.ID,string(details)); err!=nil {
  return User{},fmt.Errorf("record admin user creation audit: %w",err)
 }
 if err=tx.Commit(); err!=nil { return User{},fmt.Errorf("commit admin user creation: %w",err) }
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

type Dashboard struct {
 TotalSouls int64 `json:"total_souls"`
 TotalCharacters int64 `json:"total_characters"`
 EnabledWorlds int64 `json:"enabled_worlds"`
 ReadyInstances int64 `json:"ready_instances"`
 OnlinePlayers int64 `json:"online_players"`
 ReadyServers int64 `json:"ready_servers"`
}

func (s *Service) Dashboard(ctx context.Context) (Dashboard,error) {
 var out Dashboard
 queries:=[]struct{query string;dest *int64}{
  {`SELECT count(*) FROM souls`,&out.TotalSouls},
  {`SELECT count(*) FROM characters`,&out.TotalCharacters},
  {`SELECT count(*) FROM world_definitions WHERE enabled=true`,&out.EnabledWorlds},
  {`SELECT count(*) FROM world_instances WHERE status='ready'`,&out.ReadyInstances},
  {`SELECT count(*) FROM world_sessions WHERE session_state='active'`,&out.OnlinePlayers},
  {`SELECT count(*) FROM server_registry WHERE status='ready'`,&out.ReadyServers},
 }
 for _,q:=range queries { if err:=s.db.QueryRowContext(ctx,q.query).Scan(q.dest);err!=nil{return Dashboard{},err} }
 return out,nil
}

func (s *Service) ListUsers(ctx context.Context) ([]User,error) {
 rows,err:=s.db.QueryContext(ctx,`
  SELECT u.id::text,u.username,u.email,u.is_super_admin,u.status,u.last_login_at,p.permission_key
  FROM admin_users u
  LEFT JOIN (
   SELECT user_id,permission_key FROM admin_user_permissions
   UNION
   SELECT ur.user_id,rp.permission_key
   FROM admin_user_roles ur JOIN admin_role_permissions rp ON rp.role_id=ur.role_id
  ) p ON p.user_id=u.id
  ORDER BY u.created_at DESC,p.permission_key`)
 if err!=nil{return nil,err}
 defer rows.Close()
 out:=[]User{}
 byUser:=map[string]int{}
 for rows.Next(){
  var id,username string
  var email sql.NullString
  var superAdmin bool
  var status string
  var lastLogin sql.NullTime
  var permission sql.NullString
  if err:=rows.Scan(&id,&username,&email,&superAdmin,&status,&lastLogin,&permission);err!=nil{return nil,err}
  index,exists:=byUser[id]
  if !exists {
   user:=User{ID:id,Username:username,IsSuperAdmin:superAdmin,Status:status,Permissions:[]string{}}
   if email.Valid { user.Email=&email.String }
   if lastLogin.Valid { value:=lastLogin.Time; user.LastLoginAt=&value }
   out=append(out,user)
   index=len(out)-1
   byUser[id]=index
  }
  if permission.Valid { out[index].Permissions=append(out[index].Permissions,permission.String) }
 }
 if err:=rows.Err();err!=nil{return nil,err}
 return out,nil
}

func (s *Service) audit(ctx context.Context,actor *string,action,kind,id,result,details,remote,agent string) error {
 _,err:=s.db.ExecContext(ctx,`INSERT INTO admin_audit_logs(actor_user_id,action,resource_type,resource_id,result,details,remote_addr,user_agent) VALUES($1,$2,$3,$4,$5,$6::jsonb,NULLIF($7,'')::inet,$8)`,actor,action,kind,id,result,details,remote,agent);return err
}

func newToken(ttl time.Duration)(string,[32]byte,time.Time,error){
 var raw [32]byte;if _,err:=rand.Read(raw[:]);err!=nil{return "",[32]byte{},time.Time{},err}
 token:=base64.RawURLEncoding.EncodeToString(raw[:]);return token,sha256.Sum256([]byte(token)),time.Now().UTC().Add(ttl),nil
}

type AnalyticsDailyPoint struct {
 Date string `json:"date"`
 Registrations int64 `json:"registrations"`
 NewCharacters int64 `json:"new_characters"`
 ActiveCharacters int64 `json:"active_characters"`
}
type AnalyticsBreakdown struct {
 Key string `json:"key"`
 Name string `json:"name"`
 Count int64 `json:"count"`
}
type Analytics struct {
 From string `json:"from"`
 To string `json:"to"`
 TotalAccounts int64 `json:"total_accounts"`
 TotalCharacters int64 `json:"total_characters"`
 OnlineCharacters int64 `json:"online_characters"`
 Daily []AnalyticsDailyPoint `json:"daily"`
 Worlds []AnalyticsBreakdown `json:"worlds"`
 Levels []AnalyticsBreakdown `json:"levels"`
}

func (s *Service) Analytics(ctx context.Context, from, to time.Time) (Analytics, error) {
 out := Analytics{From: from.Format("2006-01-02"), To: to.Add(-time.Nanosecond).Format("2006-01-02"), Daily: []AnalyticsDailyPoint{}, Worlds: []AnalyticsBreakdown{}, Levels: []AnalyticsBreakdown{}}
 if err := s.db.QueryRowContext(ctx, `SELECT count(*) FROM accounts`).Scan(&out.TotalAccounts); err != nil { return Analytics{}, err }
 if err := s.db.QueryRowContext(ctx, `SELECT count(*) FROM characters`).Scan(&out.TotalCharacters); err != nil { return Analytics{}, err }
 if err := s.db.QueryRowContext(ctx, `SELECT count(DISTINCT character_id) FROM world_sessions WHERE session_state IN ('connecting','active','saving')`).Scan(&out.OnlineCharacters); err != nil { return Analytics{}, err }

 rows, err := s.db.QueryContext(ctx, `
  WITH days AS (
   SELECT generate_series($1::date, ($2::date - interval '1 day')::date, interval '1 day')::date AS day
  ), registrations AS (
   SELECT created_at::date day, count(*) amount FROM accounts WHERE created_at >= $1 AND created_at < $2 GROUP BY 1
  ), characters AS (
   SELECT created_at::date day, count(*) amount FROM characters WHERE created_at >= $1 AND created_at < $2 GROUP BY 1
  ), active AS (
   SELECT connected_at::date day, count(DISTINCT character_id) amount FROM world_sessions
   WHERE connected_at >= $1 AND connected_at < $2 AND session_state IN ('active','saving') GROUP BY 1
  )
  SELECT days.day::text, COALESCE(registrations.amount,0), COALESCE(characters.amount,0), COALESCE(active.amount,0)
  FROM days LEFT JOIN registrations USING(day) LEFT JOIN characters USING(day) LEFT JOIN active USING(day)
  ORDER BY days.day`, from, to)
 if err != nil { return Analytics{}, err }
 for rows.Next() {
  var p AnalyticsDailyPoint
  if err := rows.Scan(&p.Date, &p.Registrations, &p.NewCharacters, &p.ActiveCharacters); err != nil { rows.Close(); return Analytics{}, err }
  out.Daily = append(out.Daily, p)
 }
 if err := rows.Err(); err != nil { rows.Close(); return Analytics{}, err }; rows.Close()

 rows, err = s.db.QueryContext(ctx, `
  SELECT wd.id, wd.name, count(DISTINCT ws.character_id)
  FROM world_sessions ws JOIN world_instances wi ON wi.id=ws.instance_id
  JOIN world_definitions wd ON wd.id=wi.world_id
  WHERE ws.session_state IN ('connecting','active','saving')
  GROUP BY wd.id, wd.name ORDER BY count(DISTINCT ws.character_id) DESC, wd.id`)
 if err != nil { return Analytics{}, err }
 for rows.Next() { var p AnalyticsBreakdown; if err := rows.Scan(&p.Key,&p.Name,&p.Count); err != nil { rows.Close(); return Analytics{}, err }; out.Worlds=append(out.Worlds,p) }
 if err := rows.Err(); err != nil { rows.Close(); return Analytics{}, err }; rows.Close()

 rows, err = s.db.QueryContext(ctx, `
  SELECT CASE WHEN level < 10 THEN '1-9' WHEN level < 20 THEN '10-19' WHEN level < 30 THEN '20-29' WHEN level < 40 THEN '30-39' ELSE '40+' END AS bucket,
   CASE WHEN level < 10 THEN '1–9级' WHEN level < 20 THEN '10–19级' WHEN level < 30 THEN '20–29级' WHEN level < 40 THEN '30–39级' ELSE '40级以上' END AS label,
   count(*) FROM characters GROUP BY 1,2
  ORDER BY min(CASE WHEN level < 10 THEN 1 WHEN level < 20 THEN 10 WHEN level < 30 THEN 20 WHEN level < 40 THEN 30 ELSE 40 END)`)
 if err != nil { return Analytics{}, err }
 for rows.Next() { var p AnalyticsBreakdown; if err := rows.Scan(&p.Key,&p.Name,&p.Count); err != nil { rows.Close(); return Analytics{}, err }; out.Levels=append(out.Levels,p) }
 if err := rows.Err(); err != nil { rows.Close(); return Analytics{}, err }; rows.Close()
 return out, nil
}
