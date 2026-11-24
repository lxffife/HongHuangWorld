#include "persistence/bounty_contribution_aggregation.hpp"

#include <cassert>
#include <cstdint>
#include <limits>
#include <vector>

using honghuang::persistence::MonsterContributionRecord;
using honghuang::persistence::aggregate_bounty_monster_contributors;

int main() {
    const std::vector<MonsterContributionRecord> records{
        {"write-old", "life-1", "wraith", "session-old", "character-a", 60, 3, 1000, 2000},
        {"write-new", "life-1", "wraith", "session-new", "character-a", 40, 2, 3000, 4000},
        // Equal timestamps use lexicographically smaller session ID, independent
        // of the order in which the durable ledger is replayed.
        {"write-tie-z", "life-1", "wraith", "session-z", "character-b", 10, 1, 5000, 5000},
        {"write-tie-a", "life-1", "wraith", "session-a", "character-b", 20, 2, 5000, 5000},
        {"write-invalid", "life-1", "wraith", "session-invalid", "", 100, 1, 1, 1},
        {"write-zero", "life-1", "wraith", "session-zero", "character-zero", 0, 1, 1, 1},
        {"write-no-hits", "life-1", "wraith", "session-no-hits", "character-no-hits", 50, 0, 1, 1}
    };

    const auto merged = aggregate_bounty_monster_contributors(records);
    assert(merged.size() == 2);
    assert(merged[0].character_id == "character-a");
    assert(merged[0].session_id == "session-new");
    assert(merged[0].damage == 100);
    assert(merged[0].hit_count == 5);
    assert(merged[1].character_id == "character-b");
    assert(merged[1].session_id == "session-a");
    assert(merged[1].damage == 30);
    assert(merged[1].hit_count == 3);

    auto reversed_records = records;
    std::reverse(reversed_records.begin(), reversed_records.end());
    const auto reversed = aggregate_bounty_monster_contributors(reversed_records);
    assert(reversed.size() == merged.size());
    for (std::size_t index = 0; index < merged.size(); ++index) {
        assert(reversed[index].character_id == merged[index].character_id);
        assert(reversed[index].session_id == merged[index].session_id);
        assert(reversed[index].damage == merged[index].damage);
        assert(reversed[index].hit_count == merged[index].hit_count);
    }

    const std::vector<MonsterContributionRecord> older_replay{
        {"write-latest", "life-2", "wraith", "session-latest", "character-c", 10, 1, 9000, 9000},
        {"write-stale", "life-2", "wraith", "session-stale", "character-c", 5, 1, 1000, 1000}
    };
    const auto replayed = aggregate_bounty_monster_contributors(older_replay);
    assert(replayed.size() == 1);
    assert(replayed[0].session_id == "session-latest");
    assert(replayed[0].damage == 15);

    const std::vector<MonsterContributionRecord> overflow{
        {"write-max", "life-3", "wraith", "session-max", "character-overflow",
         std::numeric_limits<std::int64_t>::max(), 1, 1, 1},
        {"write-extra", "life-3", "wraith", "session-extra", "character-overflow", 1, 1, 2, 2}
    };
    const auto saturated = aggregate_bounty_monster_contributors(overflow);
    assert(saturated.size() == 1);
    assert(saturated[0].damage == std::numeric_limits<std::int64_t>::max());
    assert(saturated[0].hit_count == 2);

    const std::vector<MonsterContributionRecord> hit_overflow{
        {"write-hit-max", "life-4", "wraith", "session-hit-max", "character-hit-overflow",
         1, std::numeric_limits<std::int64_t>::max(), 1, 1},
        {"write-hit-extra", "life-4", "wraith", "session-hit-extra", "character-hit-overflow", 1, 1, 2, 2}
    };
    const auto saturated_hits = aggregate_bounty_monster_contributors(hit_overflow);
    assert(saturated_hits.size() == 1);
    assert(saturated_hits[0].hit_count == std::numeric_limits<std::int64_t>::max());

    const auto empty = aggregate_bounty_monster_contributors({});
    assert(empty.empty());
    return 0;
}
