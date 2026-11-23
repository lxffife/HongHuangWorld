package party

import (
 "context"
 "database/sql"
 "errors"
 "fmt"
 "strings"
 "time"
)

var (
 ErrInvalid = errors.New("invalid party request")
 ErrNotFound = errors.New("party or invitation not found")
 ErrForbidden = errors.New("party permission denied")
 ErrAlreadyInParty = errors.New("account already belongs to a party")
 ErrNotSameInstance = errors.New("players must be in the same world instance")
 ErrPartyFull = errors.New("party is full")
 ErrInvitationExpired = errors.New("party invitation expired")
 ErrNotLeader = errors.New("party leader permission required")
)

type Service struct { db *sql.DB }
func NewService(db *sql.DB) *Service { return &Service{db:db} }

type Member struct {
 AccountID string `json:"account_id"`
 Username string `json:"username"`
 CharacterID string `json:"character_id"`
 CharacterName string `json:"character_name"`
 Role string `json:"role"`
 Online bool `json:"online"`
 IsSelf bool `json:"is_self"`
 JoinedAt time.Time `json:"joined_at"`
}
type Invitation struct {
 ID string `json:"id"`
 PartyID string `json:"party_id"`
 PartyWorldID string `json:"world_id"`
 InviterName string `json:"inviter_name"`
 ExpiresAt time.Time `json:"expires_at"`
}
type Party struct {
 ID string `json:"id"`
 WorldID string `json:"world_id"`
 WorldInstanceID string `json:"world_instance_id"`
 LeaderAccountID string `json:"leader_account_id"`
 MaxMembers int `json:"max_members"`
 MaterialLootMode string `json:"material_loot_mode"`
 EquipmentLootMode string `json:"equipment_loot_mode"`
 Members []Member `json:"members"`
 Invitations []Invitation `json:"pending_invitations,omitempty"`
}

type currentCharacter struct { id, worldID, instanceID, name string }
func currentForAccount(ctx context.Context, q interface{ QueryRowContext(context.Context,string,...any)*sql.Row }, accountID string) (currentCharacter,error) {
 var c currentCharacter
 err:=q.QueryRowContext(ctx,`SELECT c.id::text,c.world_id,ws.instance_id::text,c.name
 FROM souls s JOIN characters c ON c.id=s.current_character_id
 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
 WHERE s.account_id=$1 AND c.status='alive' ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`,accountID).Scan(&c.id,&c.worldID,&c.instanceID,&c.name)
 if errors.Is(err,sql.ErrNoRows) { return currentCharacter{},ErrNotFound }
 if err!=nil { return currentCharacter{},fmt.Errorf("load active character: %w",err) }
 if c.instanceID=="" { return currentCharacter{},ErrNotFound }
 return c,nil
}

func (s *Service) Create(ctx context.Context, accountID string) (Party,error) {
 if accountID=="" { return Party{},ErrInvalid }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil{return Party{},fmt.Errorf("begin party creation: %w",err)}; defer tx.Rollback()
 c,err:=currentForAccount(ctx,tx,accountID); if err!=nil{return Party{},err}
 var exists bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM party_members WHERE account_id=$1)`,accountID).Scan(&exists);err!=nil{return Party{},fmt.Errorf("check party membership: %w",err)}
 if exists{return Party{},ErrAlreadyInParty}
 var p Party
 err=tx.QueryRowContext(ctx,`INSERT INTO parties(world_id,world_instance_id,leader_account_id) VALUES($1,$2,$3)
 RETURNING id::text,world_id,world_instance_id::text,leader_account_id::text,max_members`,c.worldID,c.instanceID,accountID).
 Scan(&p.ID,&p.WorldID,&p.WorldInstanceID,&p.LeaderAccountID,&p.MaxMembers)
 if err!=nil{return Party{},fmt.Errorf("create party: %w",err)}
 if _,err=tx.ExecContext(ctx,`INSERT INTO party_members(party_id,account_id,character_id,role) VALUES($1,$2,$3,'leader')`,p.ID,accountID,c.id);err!=nil{return Party{},fmt.Errorf("add party leader: %w",err)}
 if err=tx.Commit();err!=nil{return Party{},fmt.Errorf("commit party creation: %w",err)}
 return s.Get(ctx,accountID)
}

func (s *Service) Invite(ctx context.Context, accountID, username string) (Invitation,error) {
 username=strings.TrimSpace(username)
 if accountID==""||len(username)<3||len(username)>32{return Invitation{},ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return Invitation{},fmt.Errorf("begin party invite: %w",err)};defer tx.Rollback()
 var partyID,worldID,instanceID,role string
 err=tx.QueryRowContext(ctx,`SELECT p.id::text,p.world_id,p.world_instance_id::text,m.role
 FROM party_members m JOIN parties p ON p.id=m.party_id
 WHERE m.account_id=$1 AND p.status='active' FOR UPDATE OF p`,accountID).Scan(&partyID,&worldID,&instanceID,&role)
 if errors.Is(err,sql.ErrNoRows){return Invitation{},ErrNotFound};if err!=nil{return Invitation{},fmt.Errorf("load party for invite: %w",err)}
 if role!="leader"{return Invitation{},ErrNotLeader}
 var inviteeID,inviteeName string
 err=tx.QueryRowContext(ctx,`SELECT id::text,username FROM accounts WHERE lower(username)=lower($1) AND status='active'`,username).Scan(&inviteeID,&inviteeName)
 if errors.Is(err,sql.ErrNoRows){return Invitation{},ErrNotFound};if err!=nil{return Invitation{},fmt.Errorf("find invite target: %w",err)}
 if inviteeID==accountID{return Invitation{},ErrInvalid}
 target,err:=currentForAccount(ctx,tx,inviteeID);if err!=nil{return Invitation{},err}
 if target.worldID!=worldID||target.instanceID!=instanceID{return Invitation{},ErrNotSameInstance}
 var inParty bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM party_members WHERE account_id=$1)`,inviteeID).Scan(&inParty);err!=nil{return Invitation{},fmt.Errorf("check invitee party: %w",err)}
 if inParty{return Invitation{},ErrAlreadyInParty}
 var count int
 if err=tx.QueryRowContext(ctx,`SELECT count(*) FROM party_members WHERE party_id=$1`,partyID).Scan(&count);err!=nil{return Invitation{},fmt.Errorf("count party members: %w",err)}
 var max int
 if err=tx.QueryRowContext(ctx,`SELECT max_members FROM parties WHERE id=$1`,partyID).Scan(&max);err!=nil{return Invitation{},fmt.Errorf("read party capacity: %w",err)}
 if count>=max{return Invitation{},ErrPartyFull}
 // Expire stale invitations before checking the partial unique pending-invite index.
 if _,err=tx.ExecContext(ctx,`UPDATE party_invitations SET status='expired',responded_at=now()
 WHERE party_id=$1 AND invitee_account_id=$2 AND status='pending' AND expires_at<=now()`,partyID,inviteeID);err!=nil{return Invitation{},fmt.Errorf("expire stale party invitations: %w",err)}
 var result Invitation
 err=tx.QueryRowContext(ctx,`SELECT id::text,party_id::text,expires_at FROM party_invitations
 WHERE party_id=$1 AND invitee_account_id=$2 AND status='pending' AND expires_at>now()`,partyID,inviteeID).Scan(&result.ID,&result.PartyID,&result.ExpiresAt)
 if errors.Is(err,sql.ErrNoRows) {
  err=tx.QueryRowContext(ctx,`INSERT INTO party_invitations(party_id,inviter_account_id,invitee_account_id,expires_at)
  VALUES($1,$2,$3,now()+interval '5 minutes') RETURNING id::text,party_id::text,expires_at`,
  partyID,accountID,inviteeID).Scan(&result.ID,&result.PartyID,&result.ExpiresAt)
 }
 if err!=nil{return Invitation{},fmt.Errorf("create or reuse party invitation: %w",err)}
 result.PartyWorldID=worldID
 if err=tx.Commit();err!=nil{return Invitation{},fmt.Errorf("commit party invitation: %w",err)}
 return result,nil
}

func (s *Service) Respond(ctx context.Context, accountID, invitationID, decision string) error {
 if accountID==""||invitationID==""||(decision!="accept"&&decision!="decline"){return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin invitation response: %w",err)};defer tx.Rollback()
 var partyID,worldID,instanceID,status string
 err=tx.QueryRowContext(ctx,`SELECT i.party_id::text,p.world_id,p.world_instance_id::text,i.status
 FROM party_invitations i JOIN parties p ON p.id=i.party_id
 WHERE i.id=$1 AND i.invitee_account_id=$2 FOR UPDATE OF i,p`,invitationID,accountID).Scan(&partyID,&worldID,&instanceID,&status)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock invitation: %w",err)}
 if status!="pending"{return ErrNotFound}
 var expired bool
 if err=tx.QueryRowContext(ctx,`SELECT expires_at<=now() FROM party_invitations WHERE id=$1`,invitationID).Scan(&expired);err!=nil{return fmt.Errorf("check invitation expiry: %w",err)}
 if expired { _,_=tx.ExecContext(ctx,`UPDATE party_invitations SET status='expired',responded_at=now() WHERE id=$1`,invitationID);_ = tx.Commit();return ErrInvitationExpired }
 if decision=="decline" {
  if _,err=tx.ExecContext(ctx,`UPDATE party_invitations SET status='declined',responded_at=now() WHERE id=$1`,invitationID);err!=nil{return fmt.Errorf("decline invitation: %w",err)}
  return tx.Commit()
 }
 c,err:=currentForAccount(ctx,tx,accountID);if err!=nil{return err}
 if c.worldID!=worldID||c.instanceID!=instanceID{return ErrNotSameInstance}
 var existing bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM party_members WHERE account_id=$1)`,accountID).Scan(&existing);err!=nil{return fmt.Errorf("check current membership: %w",err)}
 if existing{return ErrAlreadyInParty}
 var count,max int
 if err=tx.QueryRowContext(ctx,`SELECT count(*),p.max_members FROM party_members m JOIN parties p ON p.id=m.party_id WHERE p.id=$1 GROUP BY p.max_members`,partyID).Scan(&count,&max);err!=nil{return fmt.Errorf("check party capacity: %w",err)}
 if count>=max{return ErrPartyFull}
 if _,err=tx.ExecContext(ctx,`INSERT INTO party_members(party_id,account_id,character_id,role) VALUES($1,$2,$3,'member')`,partyID,accountID,c.id);err!=nil{return fmt.Errorf("join party: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE party_invitations SET status='accepted',responded_at=now() WHERE id=$1`,invitationID);err!=nil{return fmt.Errorf("accept invitation: %w",err)}
 return tx.Commit()
}

func (s *Service) Leave(ctx context.Context, accountID string) error {
 if accountID==""{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin party leave: %w",err)};defer tx.Rollback()
 var partyID,role string
 err=tx.QueryRowContext(ctx,`SELECT p.id::text,m.role FROM party_members m JOIN parties p ON p.id=m.party_id WHERE m.account_id=$1 AND p.status='active' FOR UPDATE OF p`,accountID).Scan(&partyID,&role)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock party for leave: %w",err)}
 if role=="leader" {
  var successor string
  err=tx.QueryRowContext(ctx,`SELECT account_id::text FROM party_members WHERE party_id=$1 AND account_id<>$2 ORDER BY joined_at,account_id LIMIT 1 FOR UPDATE`,partyID,accountID).Scan(&successor)
  if errors.Is(err,sql.ErrNoRows) {
   if _,err=tx.ExecContext(ctx,`DELETE FROM party_members WHERE party_id=$1`,partyID);err!=nil{return fmt.Errorf("remove final party member: %w",err)}
   if _,err=tx.ExecContext(ctx,`UPDATE parties SET status='disbanded',updated_at=now() WHERE id=$1`,partyID);err!=nil{return fmt.Errorf("disband empty party: %w",err)}
  } else if err!=nil{return fmt.Errorf("select party successor: %w",err)} else {
   if _,err=tx.ExecContext(ctx,`UPDATE party_members SET role='leader' WHERE party_id=$1 AND account_id=$2`,partyID,successor);err!=nil{return fmt.Errorf("promote party successor: %w",err)}
   if _,err=tx.ExecContext(ctx,`UPDATE parties SET leader_account_id=$2,updated_at=now() WHERE id=$1`,partyID,successor);err!=nil{return fmt.Errorf("transfer party leadership: %w",err)}
   if _,err=tx.ExecContext(ctx,`DELETE FROM party_members WHERE party_id=$1 AND account_id=$2`,partyID,accountID);err!=nil{return fmt.Errorf("remove departing leader: %w",err)}
  }
 } else if _,err=tx.ExecContext(ctx,`DELETE FROM party_members WHERE party_id=$1 AND account_id=$2`,partyID,accountID);err!=nil{return fmt.Errorf("leave party: %w",err)}
 _,_=tx.ExecContext(ctx,`UPDATE party_invitations SET status='revoked',responded_at=now() WHERE party_id=$1 AND status='pending'`,partyID)
 return tx.Commit()
}

func (s *Service) Kick(ctx context.Context, leaderID,targetID string) error {
 if leaderID==""||targetID==""||leaderID==targetID{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin party kick: %w",err)};defer tx.Rollback()
 var partyID,role string
 err=tx.QueryRowContext(ctx,`SELECT p.id::text,m.role FROM party_members m JOIN parties p ON p.id=m.party_id WHERE m.account_id=$1 AND p.status='active' FOR UPDATE OF p`,leaderID).Scan(&partyID,&role)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock party for kick: %w",err)}
 if role!="leader"{return ErrNotLeader}
 result,err:=tx.ExecContext(ctx,`DELETE FROM party_members WHERE party_id=$1 AND account_id=$2 AND role='member'`,partyID,targetID)
 if err!=nil{return fmt.Errorf("remove party member: %w",err)}
 n,_:=result.RowsAffected();if n==0{return ErrNotFound}
 _,_=tx.ExecContext(ctx,`UPDATE party_invitations SET status='revoked',responded_at=now() WHERE party_id=$1 AND invitee_account_id=$2 AND status='pending'`,partyID,targetID)
 return tx.Commit()
}

func (s *Service) Transfer(ctx context.Context, leaderID,targetID string) error {
 if leaderID==""||targetID==""||leaderID==targetID{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin leadership transfer: %w",err)};defer tx.Rollback()
 var partyID,role string
 err=tx.QueryRowContext(ctx,`SELECT p.id::text,m.role FROM party_members m JOIN parties p ON p.id=m.party_id WHERE m.account_id=$1 AND p.status='active' FOR UPDATE OF p`,leaderID).Scan(&partyID,&role)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock party for transfer: %w",err)}
 if role!="leader"{return ErrNotLeader}
 var targetRole string
 err=tx.QueryRowContext(ctx,`SELECT role FROM party_members WHERE party_id=$1 AND account_id=$2 FOR UPDATE`,partyID,targetID).Scan(&targetRole)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("validate new leader: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE party_members SET role='member' WHERE party_id=$1 AND account_id=$2`,partyID,leaderID);err!=nil{return fmt.Errorf("demote previous leader: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE party_members SET role='leader' WHERE party_id=$1 AND account_id=$2`,partyID,targetID);err!=nil{return fmt.Errorf("promote new leader: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE parties SET leader_account_id=$2,updated_at=now() WHERE id=$1`,partyID,targetID);err!=nil{return fmt.Errorf("update party leader: %w",err)}
 return tx.Commit()
}

func (s *Service) Disband(ctx context.Context, accountID string) error {
 if accountID==""{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin party disband: %w",err)};defer tx.Rollback()
 var partyID,role string
 err=tx.QueryRowContext(ctx,`SELECT p.id::text,m.role FROM party_members m JOIN parties p ON p.id=m.party_id WHERE m.account_id=$1 AND p.status='active' FOR UPDATE OF p`,accountID).Scan(&partyID,&role)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock party for disband: %w",err)}
 if role!="leader"{return ErrNotLeader}
 if _,err=tx.ExecContext(ctx,`DELETE FROM party_members WHERE party_id=$1`,partyID);err!=nil{return fmt.Errorf("clear party members: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE parties SET status='disbanded',updated_at=now() WHERE id=$1`,partyID);err!=nil{return fmt.Errorf("mark party disbanded: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE party_invitations SET status='revoked',responded_at=now() WHERE party_id=$1 AND status='pending'`,partyID);err!=nil{return fmt.Errorf("revoke party invitations: %w",err)}
 return tx.Commit()
}

func (s *Service) Get(ctx context.Context, accountID string) (Party,error) {
 if accountID==""{return Party{},ErrInvalid}
 var p Party
 err:=s.db.QueryRowContext(ctx,`SELECT p.id::text,p.world_id,p.world_instance_id::text,p.leader_account_id::text,p.max_members,p.material_loot_mode,p.equipment_loot_mode
 FROM party_members mine JOIN parties p ON p.id=mine.party_id WHERE mine.account_id=$1 AND p.status='active'`,accountID).
 Scan(&p.ID,&p.WorldID,&p.WorldInstanceID,&p.LeaderAccountID,&p.MaxMembers,&p.MaterialLootMode,&p.EquipmentLootMode)
 if errors.Is(err,sql.ErrNoRows){return Party{},ErrNotFound};if err!=nil{return Party{},fmt.Errorf("load current party: %w",err)}
 rows,err:=s.db.QueryContext(ctx,`SELECT m.account_id::text,a.username,m.character_id::text,c.name,m.role,
 EXISTS(SELECT 1 FROM world_sessions ws
        WHERE ws.character_id=m.character_id
          AND ws.instance_id=p.world_instance_id
          AND ws.session_state='active'
          AND ws.connected_at IS NOT NULL),
 m.account_id=$2::uuid,m.joined_at
 FROM party_members m
 JOIN parties p ON p.id=m.party_id
 JOIN accounts a ON a.id=m.account_id
 JOIN characters c ON c.id=m.character_id
 WHERE m.party_id=$1
 ORDER BY CASE m.role WHEN 'leader' THEN 0 ELSE 1 END,m.joined_at`,p.ID,accountID)
 if err!=nil{return Party{},fmt.Errorf("list party members: %w",err)}
 defer rows.Close();p.Members=make([]Member,0)
 for rows.Next(){var m Member;if err:=rows.Scan(&m.AccountID,&m.Username,&m.CharacterID,&m.CharacterName,&m.Role,&m.Online,&m.IsSelf,&m.JoinedAt);err!=nil{return Party{},fmt.Errorf("scan party member: %w",err)};p.Members=append(p.Members,m)}
 if err:=rows.Err();err!=nil{return Party{},fmt.Errorf("iterate party members: %w",err)}
 return p,nil
}

type LootRules struct {
 MaterialMode string `json:"material_loot_mode"`
 EquipmentMode string `json:"equipment_loot_mode"`
}

func validLootMode(mode string) bool {
 switch mode {
 case "personal", "free_for_all", "round_robin", "leader": return true
 default: return false
 }
}

// SetLootRules changes material and equipment policies independently.
func (s *Service) SetLootRules(ctx context.Context, accountID string, rules LootRules) (Party, error) {
 if accountID == "" || !validLootMode(rules.MaterialMode) || !validLootMode(rules.EquipmentMode) { return Party{}, ErrInvalid }
 tx, err := s.db.BeginTx(ctx, nil)
 if err != nil { return Party{}, fmt.Errorf("begin party loot rule update: %w", err) }
 defer tx.Rollback()
 var partyID, role string
 err = tx.QueryRowContext(ctx, `SELECT p.id::text,m.role FROM party_members m JOIN parties p ON p.id=m.party_id WHERE m.account_id=$1 AND p.status='active' FOR UPDATE OF p`, accountID).Scan(&partyID, &role)
 if errors.Is(err, sql.ErrNoRows) { return Party{}, ErrNotFound }
 if err != nil { return Party{}, fmt.Errorf("lock party for loot rule update: %w", err) }
 if role != "leader" { return Party{}, ErrNotLeader }
 if _, err = tx.ExecContext(ctx, `UPDATE parties SET material_loot_mode=$2,equipment_loot_mode=$3,updated_at=now() WHERE id=$1`, partyID, rules.MaterialMode, rules.EquipmentMode); err != nil { return Party{}, fmt.Errorf("update party loot rules: %w", err) }
 if err = tx.Commit(); err != nil { return Party{}, fmt.Errorf("commit party loot rules: %w", err) }
 return s.Get(ctx, accountID)
}

func (s *Service) Invitations(ctx context.Context, accountID string) ([]Invitation,error) {
 if accountID==""{return nil,ErrInvalid}
 rows,err:=s.db.QueryContext(ctx,`SELECT i.id::text,i.party_id::text,p.world_id,a.username,i.expires_at
 FROM party_invitations i JOIN parties p ON p.id=i.party_id JOIN accounts a ON a.id=i.inviter_account_id
 WHERE i.invitee_account_id=$1 AND i.status='pending' AND i.expires_at>now() AND p.status='active'
 ORDER BY i.created_at DESC`,accountID)
 if err!=nil{return nil,fmt.Errorf("list party invitations: %w",err)}
 defer rows.Close();result:=make([]Invitation,0)
 for rows.Next(){var item Invitation;if err:=rows.Scan(&item.ID,&item.PartyID,&item.PartyWorldID,&item.InviterName,&item.ExpiresAt);err!=nil{return nil,fmt.Errorf("scan party invitation: %w",err)};result=append(result,item)}
 if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate party invitations: %w",err)}
 return result,nil
}
