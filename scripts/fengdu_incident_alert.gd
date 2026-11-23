extends RefCounted
## Derives the city-wide alert from active patrol incidents. Resolved/closed cases no longer hold gates.

const ACTIVE_STATES := ["queued", "assigned", "investigating"]


static func resolve_alert_level(records: Array) -> String:
	var level := "normal"
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var incident: Dictionary = value
		if str(incident.get("state", "")) not in ACTIVE_STATES:
			continue
		var severity := str(incident.get("severity", "low"))
		if severity == "high":
			return "lockdown"
		if severity == "medium":
			level = "watch"
	return level
