package npc

import (
	"encoding/json"
	"math"
	"time"
)

type PatrolWaypoint struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
	Z float64 `json:"z"`
	WaitSeconds float64 `json:"wait_seconds,omitempty"`
}

type PatrolRoute struct {
	Waypoints []PatrolWaypoint `json:"waypoints"`
	SpeedMPS float64 `json:"speed_mps"`
	DefaultWaitSeconds float64 `json:"default_wait_seconds,omitempty"`
	PhaseOffsetSeconds float64 `json:"phase_offset_seconds,omitempty"`
	Loop bool `json:"loop"`
}

// ResolvePatrolPosition evaluates an authored route against an absolute server
// clock. The same route and timestamp therefore produce the same NPC position
// on every game server and client. Invalid/unsafe routes are ignored.
func ResolvePatrolPosition(raw json.RawMessage, now time.Time) (x, y, z, yaw, phase float64, ok bool) {
	if len(raw) == 0 || string(raw) == "{}" || string(raw) == "null" {
		return 0, 0, 0, 0, 0, false
	}
	var route PatrolRoute
	if err := json.Unmarshal(raw, &route); err != nil {
		return 0, 0, 0, 0, 0, false
	}
	if len(route.Waypoints) < 2 || len(route.Waypoints) > 32 ||
		route.SpeedMPS < 0.1 || route.SpeedMPS > 8.0 {
		return 0, 0, 0, 0, 0, false
	}
	if !route.Loop {
		return 0, 0, 0, 0, 0, false
	}
	for _, point := range route.Waypoints {
		if !finite(point.X) || !finite(point.Y) || !finite(point.Z) ||
			!finite(point.WaitSeconds) || point.WaitSeconds < 0 || point.WaitSeconds > 120 {
			return 0, 0, 0, 0, 0, false
		}
	}
	if !finite(route.DefaultWaitSeconds) || route.DefaultWaitSeconds < 0 || route.DefaultWaitSeconds > 120 ||
		!finite(route.PhaseOffsetSeconds) || math.Abs(route.PhaseOffsetSeconds) > 86400 {
		return 0, 0, 0, 0, 0, false
	}

	segmentLengths := make([]float64, len(route.Waypoints))
	totalDuration := 0.0
	for i, point := range route.Waypoints {
		next := route.Waypoints[(i+1)%len(route.Waypoints)]
		dx, dy, dz := next.X-point.X, next.Y-point.Y, next.Z-point.Z
		length := math.Sqrt(dx*dx + dy*dy + dz*dz)
		if length < 0.05 {
			return 0, 0, 0, 0, 0, false
		}
		segmentLengths[i] = length
		wait := point.WaitSeconds
		if wait == 0 {
			wait = route.DefaultWaitSeconds
		}
		totalDuration += wait + length/route.SpeedMPS
	}
	if totalDuration <= 0 || !finite(totalDuration) {
		return 0, 0, 0, 0, 0, false
	}
	phase = math.Mod(float64(now.UnixNano())/1e9+route.PhaseOffsetSeconds, totalDuration)
	if phase < 0 {
		phase += totalDuration
	}
	routePhase := phase

	for i, point := range route.Waypoints {
		next := route.Waypoints[(i+1)%len(route.Waypoints)]
		wait := point.WaitSeconds
		if wait == 0 {
			wait = route.DefaultWaitSeconds
		}
		if phase < wait {
			return point.X, point.Y, point.Z, math.Atan2(next.X-point.X, next.Z-point.Z), routePhase, true
		}
		phase -= wait
		travel := segmentLengths[i] / route.SpeedMPS
		if phase < travel {
			t := phase / travel
			dx, dy, dz := next.X-point.X, next.Y-point.Y, next.Z-point.Z
			return point.X + dx*t, point.Y + dy*t, point.Z + dz*t,
				math.Atan2(dx, dz), routePhase, true
		}
		phase -= travel
	}
	return 0, 0, 0, 0, 0, false
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}
