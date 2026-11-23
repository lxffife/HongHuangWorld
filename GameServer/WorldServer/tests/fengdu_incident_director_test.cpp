#include "simulation/fengdu_incident_director.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;

    FengduIncidentDirector director;
    GatePolicySnapshot base_gate{"north_heaven_gate"};
    GateAccessRequest visitor{};
    auto normal_decision = evaluate_gate_access(
        apply_city_alert_to_gate_policy(base_gate, CityAlertLevel::normal), visitor);
    assert(normal_decision.allowed);
    auto watch_decision = evaluate_gate_access(
        apply_city_alert_to_gate_policy(base_gate, CityAlertLevel::watch), visitor);
    assert(!watch_decision.allowed && watch_decision.code == GateAccessCode::pass_required);
    visitor.has_valid_pass = true;
    watch_decision = evaluate_gate_access(
        apply_city_alert_to_gate_policy(base_gate, CityAlertLevel::watch), visitor);
    assert(watch_decision.allowed);
    visitor = {};
    auto lockdown_decision = evaluate_gate_access(
        apply_city_alert_to_gate_policy(base_gate, CityAlertLevel::lockdown), visitor);
    assert(!lockdown_decision.allowed && lockdown_decision.code == GateAccessCode::lockdown);
    visitor.is_emergency_responder = true;
    visitor.has_gate_override = true;
    lockdown_decision = evaluate_gate_access(
        apply_city_alert_to_gate_policy(base_gate, CityAlertLevel::lockdown), visitor);
    assert(lockdown_decision.allowed);

    assert(director.report("", IncidentSeverity::low) == nullptr);
    const auto* low = director.report("suspicious_activity", IncidentSeverity::low);
    assert(low != nullptr);
    const std::string low_id = low->id;
    assert(director.alert_level() == CityAlertLevel::normal);
    assert(!director.dispatch(low_id, 0));
    assert(director.dispatch(low_id, 1));
    assert(!director.resolve(low_id));
    assert(director.mark_units_arrived(low_id, 1));
    assert(!director.mark_units_arrived(low_id, 1));
    assert(director.resolve(low_id));
    assert(director.alert_level() == CityAlertLevel::normal);
    assert(director.close(low_id));
    assert(!director.close(low_id));

    const auto* medium = director.report("crowd_disorder", IncidentSeverity::medium);
    assert(medium != nullptr);
    const std::string medium_id = medium->id;
    assert(director.alert_level() == CityAlertLevel::watch);
    assert(director.dispatch(medium_id, 2));
    assert(director.mark_units_arrived(medium_id, 1));
    assert(director.alert_level() == CityAlertLevel::watch);
    assert(director.mark_units_arrived(medium_id, 1));
    assert(director.resolve(medium_id));
    assert(director.alert_level() == CityAlertLevel::normal);

    const auto* high = director.report("violent_conflict", IncidentSeverity::high);
    assert(high != nullptr);
    const std::string high_id = high->id;
    assert(director.alert_level() == CityAlertLevel::lockdown);
    assert(director.dispatch(high_id, 3));
    assert(!director.mark_units_arrived(high_id, 4));
    assert(director.mark_units_arrived(high_id, 2));
    assert(director.alert_level() == CityAlertLevel::lockdown);
    assert(director.mark_units_arrived(high_id, 1));
    assert(director.resolve(high_id));
    assert(director.alert_level() == CityAlertLevel::normal);

    // Concurrent incidents retain the strongest remaining alert.
    const auto* remaining_medium = director.report("market_dispute", IncidentSeverity::medium);
    assert(remaining_medium != nullptr);
    const std::string remaining_id = remaining_medium->id;
    const auto* another_high = director.report("gate_breach", IncidentSeverity::high);
    assert(another_high != nullptr);
    const std::string another_high_id = another_high->id;
    assert(director.alert_level() == CityAlertLevel::lockdown);
    assert(director.dispatch(another_high_id, 1));
    assert(director.mark_units_arrived(another_high_id, 1));
    assert(director.resolve(another_high_id));
    assert(director.alert_level() == CityAlertLevel::watch);
    assert(director.dispatch(remaining_id, 1));
    assert(director.mark_units_arrived(remaining_id, 1));
    assert(director.resolve(remaining_id));
    assert(director.alert_level() == CityAlertLevel::normal);

    assert(director.find("missing") == nullptr);
    assert(director.incidents().size() == 5);
    return 0;
}
