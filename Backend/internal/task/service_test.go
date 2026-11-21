package task

import (
 "context"
 "math"
 "strings"
 "testing"
)

func TestPublishFactionRejectsInvalidRequestsBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 tests:=[]struct{name string;request PublishRequest}{
  {"missing faction",PublishRequest{Title:"除祟",CurrencyID:"nether_stone",RewardAmount:5,MaxAssignees:1,DifficultyTier:1}},
  {"empty title",PublishRequest{FactionID:"f",Title:" ",CurrencyID:"nether_stone",RewardAmount:5,MaxAssignees:1,DifficultyTier:1}},
  {"invalid currency",PublishRequest{FactionID:"f",Title:"除祟",CurrencyID:"",RewardAmount:5,MaxAssignees:1,DifficultyTier:1}},
  {"zero reward",PublishRequest{FactionID:"f",Title:"除祟",CurrencyID:"nether_stone",RewardAmount:0,MaxAssignees:1,DifficultyTier:1}},
  {"party too large",PublishRequest{FactionID:"f",Title:"除祟",CurrencyID:"nether_stone",RewardAmount:5,MaxAssignees:21,DifficultyTier:1}},
  {"overflow",PublishRequest{FactionID:"f",Title:"除祟",CurrencyID:"nether_stone",RewardAmount:math.MaxInt64,MaxAssignees:2,DifficultyTier:1}},
  {"invalid difficulty",PublishRequest{FactionID:"f",Title:"除祟",CurrencyID:"nether_stone",RewardAmount:5,MaxAssignees:1,DifficultyTier:11}},
 }
 for _,test:=range tests{t.Run(test.name,func(t *testing.T){test.request.EventKey="stable-test-event";if _,err:=service.PublishFaction(context.Background(),"account",test.request);err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}})}
}

func TestJoinRejectsMissingIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 if err:=service.Join(context.Background(),"","task");err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}
 if err:=service.Join(t.Context(),"account","");err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}
}

func TestListOpenRequiresWorld(t *testing.T) {
 service:=NewService(nil,nil)
 if _,err:=service.ListOpen(context.Background()," ");err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}
}


func TestSettleRejectsInvalidIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 tests:=[]struct{name,accountID,taskID,eventKey string}{
  {"missing account","","task","event"},
  {"missing task","account","","event"},
  {"missing event key","account","task",""},
  {"oversized event key","account","task",strings.Repeat("x",129)},
 }
 for _,test:=range tests{t.Run(test.name,func(t *testing.T){if _,err:=service.Settle(context.Background(),test.accountID,test.taskID,test.eventKey);err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}})}
}


func TestCancelRejectsInvalidIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 if _,err:=service.Cancel(context.Background(),"","task","event");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing account, got %v",err) }
 if _,err:=service.Cancel(context.Background(),"account","","event");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing task, got %v",err) }
 if _,err:=service.Cancel(context.Background(),"account","task","");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing event key, got %v",err) }
 if _,err:=service.Cancel(context.Background(),"account","task",strings.Repeat("x",129));err!=ErrInvalid { t.Fatalf("expected ErrInvalid for oversized event key, got %v",err) }
}

func TestExpireDueRejectsUnsafeBatchSizesBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 for _,limit:=range []int{0,-1,101} {
  if _,err:=service.ExpireDue(context.Background(),limit);err!=ErrInvalid { t.Fatalf("limit %d: expected ErrInvalid, got %v",limit,err) }
 }
}


func TestJoinRejectsMissingIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 if err:=service.Join(context.Background(),"","task");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing account, got %v",err) }
 if err:=service.Join(context.Background(),"account","");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing task, got %v",err) }
}

func TestLeaveRejectsMissingIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 if err:=service.Leave(context.Background(),"","task");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing account, got %v",err) }
 if err:=service.Leave(context.Background(),"account","");err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing task, got %v",err) }
}

func TestPublishFactionRequiresPositiveCharacterLevel(t *testing.T) {
 service:=NewService(nil,nil)
 request:=PublishRequest{EventKey:"event",FactionID:"faction",Title:"除祟任务",CurrencyID:"nether_stone",RewardAmount:5,MaxAssignees:1,DifficultyTier:1,RequiredRealmLevel:1}
 if _,err:=service.PublishFaction(context.Background(),"account",request);err!=ErrInvalid { t.Fatalf("expected ErrInvalid for missing character level requirement, got %v",err) }
 request.RequiredCharacterLevel=10001
 if _,err:=service.PublishFaction(context.Background(),"account",request);err!=ErrInvalid { t.Fatalf("expected ErrInvalid for oversized character level requirement, got %v",err) }
}


func TestValidateJoinParticipationErrorOrder(t *testing.T) {
 tests:=[]struct{
  name string
  exists bool
  status string
  joined,max int
  want error
 }{
  {"accepted member gets already joined even when full",true,"accepted",4,4,ErrAlreadyJoined},
  {"withdrawn member may reclaim a slot",true,"withdrawn",2,4,nil},
  {"new member may join available slot",false,"",2,4,nil},
  {"new member receives full when capacity exhausted",false,"",4,4,ErrTaskFull},
  {"completed participant cannot rejoin",true,"completed",1,4,ErrTaskNotReady},
  {"cancelled participant cannot rejoin",true,"cancelled",1,4,ErrTaskNotReady},
  {"invalid capacity rejected",false,"",0,0,ErrInvalid},
 }
 for _,tt:=range tests {
  t.Run(tt.name,func(t *testing.T) {
   got:=validateJoinParticipation(tt.exists,tt.status,tt.joined,tt.max)
   if got!=tt.want { t.Fatalf("got %v, want %v",got,tt.want) }
  })
 }
}
func TestValidateObjectives(t *testing.T) {
 tests:=[]struct{name string;items []ObjectiveRequest;wantErr bool}{
  {"empty objectives remain valid for legacy manual tasks",nil,false},
  {"valid kill objective",[]ObjectiveRequest{{Key:"kill_wraiths",EventType:"monster_killed",TargetCount:5}},false},
  {"valid exploration objective",[]ObjectiveRequest{{Key:"discover_gate",EventType:"exploration_discovered",TargetCount:1}},false},
  {"duplicate objective keys",[]ObjectiveRequest{{Key:"same",EventType:"monster_killed",TargetCount:1},{Key:"same",EventType:"item_collected",TargetCount:2}},true},
  {"unknown event type",[]ObjectiveRequest{{Key:"objective",EventType:"client_claimed",TargetCount:1}},true},
  {"invalid objective key",[]ObjectiveRequest{{Key:"bad key",EventType:"monster_killed",TargetCount:1}},true},
  {"zero target",[]ObjectiveRequest{{Key:"objective",EventType:"monster_killed",TargetCount:0}},true},
  {"too many objectives",make([]ObjectiveRequest,11),true},
 }
 for _,tt:=range tests { t.Run(tt.name,func(t *testing.T){err:=validateObjectives(tt.items);if (err!=nil)!=tt.wantErr {t.Fatalf("got %v, wantErr %v",err,tt.wantErr)}}) }
}

func TestValidUUID(t *testing.T) {
 if !validUUID("00000000-0000-4000-8000-000000000001") { t.Fatal("expected valid UUID") }
 if !validUUID("00000000-0000-4000-8000-00000000000A") { t.Fatal("expected uppercase hex UUID") }
 for _,value:=range []string{"","not-a-uuid","00000000000040008000000000000001","00000000-0000-4000-8000-00000000000Z"} {
  if validUUID(value) { t.Fatalf("expected invalid UUID %q",value) }
 }
}

func TestApplyWorldEventRejectsInvalidPayloadBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 _,err:=service.ApplyWorldEvent(context.Background(),"node",WorldEvent{})
 if err!=ErrInvalidWorldEvent { t.Fatalf("expected ErrInvalidWorldEvent, got %v",err) }
 _,err=service.ApplyWorldEvent(context.Background(),"",WorldEvent{EventID:"00000000-0000-4000-8000-000000000001",TaskID:"00000000-0000-4000-8000-000000000002",SessionID:"00000000-0000-4000-8000-000000000003",CharacterID:"00000000-0000-4000-8000-000000000004",ObjectiveKey:"kill",EventType:"monster_killed"})
 if err!=ErrInvalidWorldEvent { t.Fatalf("expected invalid node identity, got %v",err) }
}

func TestRecordMonsterContributionsRejectsInvalidPayloadBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 valid:=MonsterContributionEvent{
  EventID:"00000000-0000-4000-8000-000000000001",
  TaskID:"00000000-0000-4000-8000-000000000002",
  MonsterInstanceID:"spawn-1",
  MonsterDefinitionID:"wandering_wraith",
  Contributors:[]MonsterContribution{{
   SessionID:"00000000-0000-4000-8000-000000000003",
   CharacterID:"00000000-0000-4000-8000-000000000004",
   Damage:10,HitCount:1,
  }},
 }
 tests:=[]struct{name,node string;event MonsterContributionEvent}{
  {"missing node","",valid},
  {"missing event id","node",MonsterContributionEvent{TaskID:valid.TaskID,MonsterInstanceID:valid.MonsterInstanceID,MonsterDefinitionID:valid.MonsterDefinitionID,Contributors:valid.Contributors}},
  {"empty contributors","node",MonsterContributionEvent{EventID:valid.EventID,TaskID:valid.TaskID,MonsterInstanceID:valid.MonsterInstanceID,MonsterDefinitionID:valid.MonsterDefinitionID}},
  {"non-positive damage","node",MonsterContributionEvent{EventID:valid.EventID,TaskID:valid.TaskID,MonsterInstanceID:valid.MonsterInstanceID,MonsterDefinitionID:valid.MonsterDefinitionID,Contributors:[]MonsterContribution{{SessionID:valid.Contributors[0].SessionID,CharacterID:valid.Contributors[0].CharacterID,Damage:0,HitCount:1}}}},
  {"duplicate contributor","node",MonsterContributionEvent{EventID:valid.EventID,TaskID:valid.TaskID,MonsterInstanceID:valid.MonsterInstanceID,MonsterDefinitionID:valid.MonsterDefinitionID,Contributors:[]MonsterContribution{valid.Contributors[0],valid.Contributors[0]}}},
  {"aggregate damage overflow","node",MonsterContributionEvent{EventID:valid.EventID,TaskID:valid.TaskID,MonsterInstanceID:valid.MonsterInstanceID,MonsterDefinitionID:valid.MonsterDefinitionID,Contributors:[]MonsterContribution{{SessionID:valid.Contributors[0].SessionID,CharacterID:valid.Contributors[0].CharacterID,Damage:math.MaxInt64,HitCount:1},{SessionID:"00000000-0000-4000-8000-000000000005",CharacterID:"00000000-0000-4000-8000-000000000006",Damage:1,HitCount:1}}}},
 }
 for _,tt:=range tests {
  t.Run(tt.name,func(t *testing.T) {
   if err:=service.RecordMonsterContributions(context.Background(),tt.node,tt.event);err!=ErrInvalidWorldEvent {
    t.Fatalf("expected ErrInvalidWorldEvent before database access, got %v",err)
   }
  })
 }
}

func TestListContributionsRejectsInvalidIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 if _,err:=service.ListContributions(context.Background(),"","00000000-0000-4000-8000-000000000001");err!=ErrInvalid {
  t.Fatalf("expected ErrInvalid for missing account, got %v",err)
 }
 if _,err:=service.ListContributions(context.Background(),"account","not-a-uuid");err!=ErrInvalid {
  t.Fatalf("expected ErrInvalid for malformed task id, got %v",err)
 }
}

func TestListPublisherContributionAuditRejectsInvalidIdentityBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil,nil)
 validFaction:="00000000-0000-4000-8000-000000000001"
 validTask:="00000000-0000-4000-8000-000000000002"
 tests:=[]struct{name,accountID,factionID,taskID string}{
  {"missing account","",validFaction,validTask},
  {"malformed faction","account","not-a-uuid",validTask},
  {"malformed task","account",validFaction,"not-a-uuid"},
 }
 for _,tt:=range tests {
  t.Run(tt.name,func(t *testing.T) {
   if _,err:=service.ListPublisherContributionAudit(context.Background(),tt.accountID,tt.factionID,tt.taskID,0,"");err!=ErrInvalid {
    t.Fatalf("expected ErrInvalid before database access, got %v",err)
   }
  })
 }
}


func TestDecodeBountyAuditCursorRejectsMalformedValues(t *testing.T) {
 for _,value:=range []string{"not-base64","e30","eyJjcmVhdGVkX2F0IjoiMjAyNi0wMS0wMVQwMDowMDowMFoiLCJldmVudF9pZCI6Im5vdC11dWlkIn0"} {
  if _,err:=decodeBountyAuditCursor(value);err!=ErrInvalid { t.Fatalf("expected ErrInvalid for cursor %q, got %v",value,err) }
 }
}
