#include "persistence/monster_reward_distribution.hpp"

#include <cassert>
#include <cstdint>
#include <vector>

using honghuang::persistence::MonsterContributionRecord;
using honghuang::persistence::allocate_monster_combat_rewards;

int main() {
    const std::vector<MonsterContributionRecord> contributions{
        MonsterContributionRecord{"write-a", "life-1", "wraith", "session-a", "character-a", 75, 3},
        MonsterContributionRecord{"write-b", "life-1", "wraith", "session-b", "character-b", 25, 1},
        // Invalid or unauthenticated contributors must never receive currency.
        MonsterContributionRecord{"write-c", "life-1", "wraith", "session-c", "", 100, 1},
        MonsterContributionRecord{"write-d", "life-1", "wraith", "session-d", "character-d", 0, 1}
    };

    const auto shares = allocate_monster_combat_rewards(contributions, 0, 0, 10, 3);
    assert(shares.size() == 2);
    assert(shares[0].character_id == "character-a");
    assert(shares[1].character_id == "character-b");
    assert(shares[0].ghost_cash == 8);
    assert(shares[1].ghost_cash == 2);
    assert(shares[0].nether_stone == 3);
    assert(shares[1].nether_stone == 0);

    std::int64_t total_cash = 0;
    std::int64_t total_stone = 0;
    for (const auto& share : shares) {
        total_cash += share.ghost_cash;
        total_stone += share.nether_stone;
    }
    assert(total_cash == 10);
    assert(total_stone == 3);

    const auto empty = allocate_monster_combat_rewards({}, 0, 0, 100, 5);
    assert(empty.empty());
    return 0;
}
