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
 if err:=service.Join(t.Context(),"","task");err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}
 if err:=service.Join(t.Context(),"account","");err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}
}

func TestListOpenRequiresWorld(t *testing.T) {
 service:=NewService(nil,nil)
 if _,err:=service.ListOpen(t.Context()," ");err!=ErrInvalid{t.Fatalf("expected ErrInvalid, got %v",err)}
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
