#pragma once

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace honghuang::simulation {

enum class IncidentSeverity { low, medium, high };
enum class IncidentState { reported, dispatched, investigating, resolved, closed };
enum class CityAlertLevel { normal, watch, lockdown };

struct FengduIncident {
    std::string id;
    std::string type;
    IncidentSeverity severity{IncidentSeverity::low};
    IncidentState state{IncidentState::reported};
    std::size_t assigned_units{0};
    std::size_t arrived_units{0};
};

class FengduIncidentDirector {
public:
    const FengduIncident* report(std::string type, IncidentSeverity severity) {
        if (type.empty()) return nullptr;
        FengduIncident incident;
        incident.id = "fengdu.incident." + std::to_string(next_id_++);
        incident.type = std::move(type);
        incident.severity = severity;
        incidents_.push_back(std::move(incident));
        return &incidents_.back();
    }

    bool dispatch(std::string_view incident_id, std::size_t unit_count) {
        auto* incident = find_mutable(incident_id);
        if (incident == nullptr || incident->state != IncidentState::reported || unit_count == 0) {
            return false;
        }
        incident->assigned_units = unit_count;
        incident->state = IncidentState::dispatched;
        return true;
    }

    bool mark_units_arrived(std::string_view incident_id, std::size_t unit_count) {
        auto* incident = find_mutable(incident_id);
        if (incident == nullptr || incident->state != IncidentState::dispatched ||
            unit_count == 0 || unit_count > incident->assigned_units - incident->arrived_units) {
            return false;
        }
        incident->arrived_units += unit_count;
        if (incident->arrived_units == incident->assigned_units) {
            incident->state = IncidentState::investigating;
        }
        return true;
    }

    bool resolve(std::string_view incident_id) {
        auto* incident = find_mutable(incident_id);
        if (incident == nullptr || incident->state != IncidentState::investigating) return false;
        incident->state = IncidentState::resolved;
        return true;
    }

    bool close(std::string_view incident_id) {
        auto* incident = find_mutable(incident_id);
        if (incident == nullptr || incident->state != IncidentState::resolved) return false;
        incident->state = IncidentState::closed;
        return true;
    }

    CityAlertLevel alert_level() const {
        CityAlertLevel level = CityAlertLevel::normal;
        for (const auto& incident : incidents_) {
            if (incident.state == IncidentState::resolved || incident.state == IncidentState::closed) {
                continue;
            }
            if (incident.severity == IncidentSeverity::high) return CityAlertLevel::lockdown;
            if (incident.severity == IncidentSeverity::medium) level = CityAlertLevel::watch;
        }
        return level;
    }

    const std::vector<FengduIncident>& incidents() const { return incidents_; }

    const FengduIncident* find(std::string_view incident_id) const {
        for (const auto& incident : incidents_) {
            if (incident.id == incident_id) return &incident;
        }
        return nullptr;
    }

private:
    FengduIncident* find_mutable(std::string_view incident_id) {
        for (auto& incident : incidents_) {
            if (incident.id == incident_id) return &incident;
        }
        return nullptr;
    }

    std::size_t next_id_{1};
    std::vector<FengduIncident> incidents_;
};

} // namespace honghuang::simulation
