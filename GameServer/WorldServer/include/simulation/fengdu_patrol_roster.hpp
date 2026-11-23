#pragma once

#include <cstddef>
#include <deque>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "simulation/fengdu_incident_director.hpp"

namespace honghuang::simulation {

enum class PatrolUnitState { available, responding, investigating, returning };

struct FengduPatrolUnit {
    std::string id;
    std::string home_post;
    std::string incident_id;
    PatrolUnitState state{PatrolUnitState::available};
};

struct PatrolDispatchResult {
    bool dispatched{false};
    std::string reason;
    std::vector<std::string> unit_ids;
};

class FengduPatrolRoster {
public:
    bool add_unit(std::string id, std::string home_post) {
        if (id.empty() || home_post.empty() || find_unit(id) != nullptr) return false;
        units_.push_back({std::move(id), std::move(home_post), {}, PatrolUnitState::available});
        return true;
    }

    PatrolDispatchResult dispatch(
        FengduIncidentDirector& director, std::string_view incident_id, std::size_t required_units) {
        PatrolDispatchResult result;
        const auto* incident = director.find(incident_id);
        if (incident == nullptr) {
            result.reason = "incident_not_found";
            return result;
        }
        if (incident->state != IncidentState::reported) {
            result.reason = "incident_not_reported";
            return result;
        }
        if (required_units == 0) {
            result.reason = "invalid_unit_count";
            return result;
        }

        if (required_units > units_.size()) {
            result.reason = "insufficient_available_units";
            return result;
        }

        std::vector<FengduPatrolUnit*> candidates;
        candidates.reserve(required_units);
        for (auto& unit : units_) {
            if (unit.state == PatrolUnitState::available) {
                candidates.push_back(&unit);
                if (candidates.size() == required_units) break;
            }
        }
        if (candidates.size() < required_units) {
            result.reason = "insufficient_available_units";
            return result;
        }

        // Prepare all potentially allocating data before mutating the incident state.
        result.unit_ids.reserve(required_units);
        std::vector<std::string> incident_refs;
        incident_refs.reserve(required_units);
        for (const auto* unit : candidates) {
            result.unit_ids.push_back(unit->id);
            incident_refs.emplace_back(incident_id);
        }
        if (!director.dispatch(incident_id, required_units)) {
            result.unit_ids.clear();
            result.reason = "incident_dispatch_rejected";
            return result;
        }

        for (std::size_t index = 0; index < candidates.size(); ++index) {
            candidates[index]->state = PatrolUnitState::responding;
            candidates[index]->incident_id = std::move(incident_refs[index]);
        }
        result.dispatched = true;
        return result;
    }

    bool mark_unit_arrived(FengduIncidentDirector& director, std::string_view unit_id) {
        auto* unit = find_unit(unit_id);
        if (unit == nullptr || unit->state != PatrolUnitState::responding) return false;
        if (!director.mark_units_arrived(unit->incident_id, 1)) return false;
        unit->state = PatrolUnitState::investigating;
        const auto* incident = director.find(unit->incident_id);
        if (incident != nullptr && incident->state == IncidentState::investigating) {
            for (auto& assigned : units_) {
                if (assigned.incident_id == unit->incident_id &&
                    assigned.state == PatrolUnitState::responding) {
                    assigned.state = PatrolUnitState::investigating;
                }
            }
        }
        return true;
    }

    bool begin_return(FengduIncidentDirector& director, std::string_view incident_id) {
        const auto* incident = director.find(incident_id);
        if (incident == nullptr ||
            (incident->state != IncidentState::resolved && incident->state != IncidentState::closed)) {
            return false;
        }
        bool found = false;
        for (auto& unit : units_) {
            if (unit.incident_id != incident_id) continue;
            if (unit.state != PatrolUnitState::investigating) return false;
            found = true;
        }
        if (!found) return false;
        for (auto& unit : units_) {
            if (unit.incident_id == incident_id) unit.state = PatrolUnitState::returning;
        }
        return true;
    }

    bool mark_unit_returned(FengduIncidentDirector& director, std::string_view unit_id) {
        auto* unit = find_unit(unit_id);
        if (unit == nullptr || unit->state != PatrolUnitState::returning) return false;
        const std::string incident_id = unit->incident_id;
        unit->state = PatrolUnitState::available;
        unit->incident_id.clear();

        bool all_returned = true;
        for (const auto& assigned : units_) {
            if (assigned.incident_id == incident_id) {
                all_returned = false;
                break;
            }
        }
        if (all_returned) {
            const auto* incident = director.find(incident_id);
            if (incident != nullptr && incident->state == IncidentState::resolved) {
                director.close(incident_id);
            }
        }
        return true;
    }

    const FengduPatrolUnit* find_unit(std::string_view unit_id) const {
        for (const auto& unit : units_) {
            if (unit.id == unit_id) return &unit;
        }
        return nullptr;
    }

    std::size_t available_count() const {
        std::size_t count = 0;
        for (const auto& unit : units_) {
            if (unit.state == PatrolUnitState::available) ++count;
        }
        return count;
    }

    std::size_t deployed_count() const { return units_.size() - available_count(); }
    const std::deque<FengduPatrolUnit>& units() const { return units_; }

private:
    FengduPatrolUnit* find_unit(std::string_view unit_id) {
        for (auto& unit : units_) {
            if (unit.id == unit_id) return &unit;
        }
        return nullptr;
    }

    std::deque<FengduPatrolUnit> units_;
};

} // namespace honghuang::simulation
