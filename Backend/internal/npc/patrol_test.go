package npc

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func TestResolvePatrolPositionIsDeterministic(t *testing.T) {
	route := json.RawMessage(`{"waypoints":[{"x":0,"y":0,"z":0},{"x":10,"y":0,"z":0}],"speed_mps":1,"loop":true}`)
	now := time.Unix(100, 0)
	x1, y1, z1, yaw1, phase1, ok1 := ResolvePatrolPosition(route, now)
	x2, y2, z2, yaw2, phase2, ok2 := ResolvePatrolPosition(route, now)
	if !ok1 || !ok2 || x1 != x2 || y1 != y2 || z1 != z2 || yaw1 != yaw2 || phase1 != phase2 {
		t.Fatalf("same route/time must resolve identically: (%v,%v,%v,%v,%v,%v) vs (%v,%v,%v,%v,%v,%v)",
			x1,y1,z1,yaw1,phase1,ok1,x2,y2,z2,yaw2,phase2,ok2)
	}
}

func TestResolvePatrolPositionMovesAlongSegment(t *testing.T) {
	route := json.RawMessage(`{"waypoints":[{"x":0,"y":0,"z":0},{"x":10,"y":0,"z":0}],"speed_mps":1,"loop":true}`)
	x, _, _, _, _, ok := ResolvePatrolPosition(route, time.Unix(102, 0))
	if !ok || math.Abs(x-2) > 0.0001 {
		t.Fatalf("expected 2m along first segment, got x=%v ok=%v", x, ok)
	}
}

func TestResolvePatrolPositionHonorsWaypointWait(t *testing.T) {
	route := json.RawMessage(`{"waypoints":[{"x":0,"y":0,"z":0,"wait_seconds":5},{"x":10,"y":0,"z":0}],"speed_mps":1,"loop":true}`)
	x, _, _, _, _, ok := ResolvePatrolPosition(route, time.Unix(102, 0))
	if !ok || x != 0 {
		t.Fatalf("NPC should remain at first waypoint during wait, got x=%v ok=%v", x, ok)
	}
}

func TestResolvePatrolPositionRejectsUnsafeRoute(t *testing.T) {
	cases := []string{
		`{}`,
		`{"waypoints":[{"x":0,"y":0,"z":0}],"speed_mps":1,"loop":true}`,
		`{"waypoints":[{"x":0,"y":0,"z":0},{"x":1,"y":0,"z":0}],"speed_mps":100,"loop":true}`,
		`{"waypoints":[{"x":0,"y":0,"z":0},{"x":1,"y":0,"z":0}],"speed_mps":1,"loop":false}`,
		`{"waypoints":[{"x":0,"y":0,"z":0},{"x":1,"y":0,"z":0}],"speed_mps":1,"loop":true,"default_wait_seconds":999}`,
	}
	for _, raw := range cases {
		if _, _, _, _, _, ok := ResolvePatrolPosition(json.RawMessage(raw), time.Unix(100,0)); ok {
			t.Errorf("expected invalid route to be rejected: %s", raw)
		}
	}
}
