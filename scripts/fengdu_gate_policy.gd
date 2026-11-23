extends RefCounted
## Local preview of the server-side gate rules. Never use this result as an authority decision.

const KNOWN_GATES := [
	"north_heaven_gate",
	"south_ghost_gate",
	"east_mystic_gate",
	"west_dark_gate"
]


static func evaluate(gate_id: String, policy: Dictionary, identity: Dictionary) -> Dictionary:
	if gate_id not in KNOWN_GATES:
		return _decision(false, "unknown_gate", "未知城门")
	if bool(identity.get("is_wanted", false)):
		return _decision(false, "wanted", "你已被阴司通缉，通行申请被拒绝")
	var emergency_override := bool(identity.get("is_emergency_responder", false)) and bool(identity.get("has_gate_override", false))
	if bool(policy.get("lockdown", false)) and not emergency_override:
		return _decision(false, "lockdown", "城防进入战时封锁，暂不允许通行")
	if not bool(policy.get("is_open", true)) and not bool(identity.get("has_gate_override", false)):
		return _decision(false, "gate_closed", "城门关闭，需等待城门官放行")
	if bool(policy.get("restrict_faction", false)) and not bool(identity.get("faction_permitted", true)) and not emergency_override:
		return _decision(false, "faction_restricted", "当前阵营无权通过此门")
	if bool(policy.get("curfew_active", false)) and not bool(identity.get("has_valid_pass", false)) and not bool(identity.get("is_official", false)) and not emergency_override:
		return _decision(false, "curfew_pass_required", "夜间宵禁中，请出示阴司通行令")
	if bool(policy.get("require_pass", false)) and not bool(identity.get("has_valid_pass", false)) and not bool(identity.get("is_official", false)) and not emergency_override:
		return _decision(false, "pass_required", "此门需要有效通行令")
	return _decision(true, "allowed", "身份核验通过，可以通行")


static func _decision(allowed: bool, code: String, message: String) -> Dictionary:
	return {"allowed": allowed, "code": code, "message": message}
