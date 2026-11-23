#include "simulation/gate_access_policy.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;

    GatePolicySnapshot open_gate{"north_heaven_gate"};
    GateAccessRequest visitor{};
    auto decision = evaluate_gate_access(open_gate, visitor);
    assert(decision.allowed && decision.code == GateAccessCode::allowed);

    open_gate.curfew_active = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::curfew_pass_required);

    visitor.has_valid_pass = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(decision.allowed);

    visitor = {};
    visitor.is_official = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(decision.allowed); // verified officials may pass ordinary curfew/pass checks

    open_gate.require_pass = true;
    visitor = {};
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::pass_required);

    open_gate.is_open = false;
    visitor.has_valid_pass = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::gate_closed);

    visitor.has_gate_override = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(decision.allowed); // gate override is separate from a travel pass

    open_gate.lockdown = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::lockdown);

    visitor.is_emergency_responder = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(decision.allowed); // emergency responder with override

    visitor.is_wanted = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::wanted);

    open_gate = {"west_dark_gate"};
    visitor = {};
    open_gate.restrict_faction = true;
    visitor.faction_permitted = false;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::faction_restricted);

    visitor.is_emergency_responder = true;
    visitor.has_gate_override = true;
    decision = evaluate_gate_access(open_gate, visitor);
    assert(decision.allowed);

    open_gate.gate_id = "unknown_gate";
    decision = evaluate_gate_access(open_gate, visitor);
    assert(!decision.allowed && decision.code == GateAccessCode::unknown_gate);

    return 0;
}
