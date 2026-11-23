#include "simulation/fengdu_patrol_roster.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;

    FengduIncidentDirector director;
    FengduPatrolRoster roster;
    assert(roster.add_unit("guard.north.01", "north_post"));
    assert(roster.add_unit("guard.south.01", "south_post"));
    assert(roster.add_unit("guard.east.01", "east_post"));
    assert(!roster.add_unit("guard.east.01", "duplicate_post"));
    assert(!roster.add_unit("", "west_post"));
    assert(roster.available_count() == 3);

    const auto* medium = director.report("market_dispute", IncidentSeverity::medium);
    assert(medium != nullptr);
    const std::string medium_id = medium->id;
    const auto first = roster.dispatch(director, medium_id, 2);
    assert(first.dispatched && first.unit_ids.size() == 2);
    assert(roster.available_count() == 1);
    assert(roster.deployed_count() == 2);

    const auto* high = director.report("gate_breach", IncidentSeverity::high);
    assert(high != nullptr);
    const std::string high_id = high->id;
    const auto shortage = roster.dispatch(director, high_id, 2);
    assert(!shortage.dispatched && shortage.reason == "insufficient_available_units");
    assert(shortage.unit_ids.empty());
    assert(roster.available_count() == 1);
    assert(director.find(high_id)->state == IncidentState::reported);

    assert(!roster.mark_unit_arrived(director, "unknown_guard"));
    assert(roster.mark_unit_arrived(director, first.unit_ids[0]));
    assert(!roster.mark_unit_arrived(director, first.unit_ids[0]));
    assert(director.find(medium_id)->state == IncidentState::dispatched);
    assert(roster.mark_unit_arrived(director, first.unit_ids[1]));
    assert(director.find(medium_id)->state == IncidentState::investigating);
    assert(!roster.begin_return(director, medium_id));
    assert(director.resolve(medium_id));
    assert(roster.begin_return(director, medium_id));
    assert(!roster.dispatch(director, high_id, 1).dispatched);
    assert(roster.mark_unit_returned(director, first.unit_ids[0]));
    assert(roster.available_count() == 2);
    assert(director.find(medium_id)->state == IncidentState::resolved);
    assert(roster.mark_unit_returned(director, first.unit_ids[1]));
    assert(roster.available_count() == 3);
    assert(director.find(medium_id)->state == IncidentState::closed);
    assert(!roster.mark_unit_returned(director, first.unit_ids[1]));

    const auto second = roster.dispatch(director, high_id, 3);
    assert(second.dispatched && second.unit_ids.size() == 3);
    assert(roster.available_count() == 0);
    for (const auto& id : second.unit_ids) assert(roster.mark_unit_arrived(director, id));
    assert(director.find(high_id)->state == IncidentState::investigating);
    assert(director.resolve(high_id));
    assert(roster.begin_return(director, high_id));
    for (const auto& id : second.unit_ids) assert(roster.mark_unit_returned(director, id));
    assert(roster.available_count() == 3);
    assert(roster.deployed_count() == 0);
    assert(director.find(high_id)->state == IncidentState::closed);
    return 0;
}
