#pragma once

#include <array>
#include <string_view>

namespace honghuang::simulation {

enum class GateAccessCode {
    allowed,
    unknown_gate,
    wanted,
    lockdown,
    gate_closed,
    faction_restricted,
    curfew_pass_required,
    pass_required
};

struct GatePolicySnapshot {
    std::string_view gate_id;
    bool is_open{true};
    bool lockdown{false};
    bool curfew_active{false};
    bool require_pass{false};
    bool restrict_faction{false};
};

struct GateAccessRequest {
    bool has_valid_pass{false};
    bool faction_permitted{true};
    bool is_official{false};
    bool is_emergency_responder{false};
    bool is_wanted{false};
    bool has_gate_override{false};
};

struct GateAccessDecision {
    GateAccessCode code{GateAccessCode::unknown_gate};
    bool allowed{false};
};

inline constexpr std::array<std::string_view, 4> kFengduGateIds{{
    "north_heaven_gate",
    "south_ghost_gate",
    "east_mystic_gate",
    "west_dark_gate"
}};

inline bool is_known_fengdu_gate(std::string_view gate_id) {
    for (const auto known_id : kFengduGateIds) {
        if (known_id == gate_id) return true;
    }
    return false;
}

// Pure server-side policy primitive. Callers must build the request from
// authenticated identity, server-held warrants, passes and faction records.
inline GateAccessDecision evaluate_gate_access(
    const GatePolicySnapshot& policy, const GateAccessRequest& request) {
    if (!is_known_fengdu_gate(policy.gate_id)) {
        return {GateAccessCode::unknown_gate, false};
    }
    // A warrant is never bypassed by a pass or an ordinary official title.
    if (request.is_wanted) {
        return {GateAccessCode::wanted, false};
    }
    const bool emergency_override =
        request.is_emergency_responder && request.has_gate_override;
    if (policy.lockdown && !emergency_override) {
        return {GateAccessCode::lockdown, false};
    }
    if (!policy.is_open && !request.has_gate_override) {
        return {GateAccessCode::gate_closed, false};
    }
    if (policy.restrict_faction && !request.faction_permitted && !emergency_override) {
        return {GateAccessCode::faction_restricted, false};
    }
    if (policy.curfew_active && !request.has_valid_pass &&
        !request.is_official && !emergency_override) {
        return {GateAccessCode::curfew_pass_required, false};
    }
    if (policy.require_pass && !request.has_valid_pass &&
        !request.is_official && !emergency_override) {
        return {GateAccessCode::pass_required, false};
    }
    return {GateAccessCode::allowed, true};
}

} // namespace honghuang::simulation
