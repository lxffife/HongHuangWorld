package serverregistry

import (
	"context"
	"errors"
	"testing"
)

func TestHeartbeatRejectsInvalidHellFloorBeforeDatabaseAccess(t *testing.T) {
 service := NewService(nil)
 cases := []struct { name, worldID string; floor int }{
  {name: "negative floor", worldID: "underworld_fengdu", floor: -1},
  {name: "floor above eighteen", worldID: "underworld_fengdu", floor: 19},
  {name: "floor on non-underworld world", worldID: "qingyun_human", floor: 1},
 }
 for _, tc := range cases {
  t.Run(tc.name, func(t *testing.T) {
   _, err := service.Heartbeat(context.Background(), Heartbeat{
    NodeKey: "node-1", Host: "127.0.0.1", UDPPort: 7777, Region: "local",
    Capacity: 10, CurrentPlayers: 0, WorldID: tc.worldID, InstanceKey: "instance-1",
    HellFloor: tc.floor, Status: "ready",
   })
   if !errors.Is(err, ErrInvalidHeartbeat) { t.Fatalf("expected ErrInvalidHeartbeat, got %v", err) }
  })
 }
}

func TestSetAdminStateRejectsInvalidInputBeforeDatabaseAccess(t *testing.T) {
	service := NewService(nil)
	cases := []struct {
		name string
		nodeKey string
		state string
	}{
		{name:"empty node key",nodeKey:"",state:"draining"},
		{name:"unknown state",nodeKey:"node-1",state:"stopped"},
		{name:"state cannot be blank",nodeKey:"node-1",state:""},
	}
	for _, tc := range cases {
		t.Run(tc.name,func(t *testing.T) {
			_, err := service.SetAdminState(context.Background(),tc.nodeKey,tc.state)
			if !errors.Is(err,ErrInvalidNodeState) { t.Fatalf("expected ErrInvalidNodeState, got %v",err) }
		})
	}
}
