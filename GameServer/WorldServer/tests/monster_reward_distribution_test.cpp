#include "persistence/monster_reward_distribution.hpp"

#include <algorithm>
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

    // Reconnecting during the same monster life must not split one character's
    // reward into multiple independently rounded session shares.
    const std::vector<MonsterContributionRecord> reconnected_contributions{
        MonsterContributionRecord{"write-e", "life-2", "wraith", "old-session", "same-character", 60, 3,
                                  1000, 2000},
        MonsterContributionRecord{"write-f", "life-2", "wraith", "new-session", "same-character", 40, 2,
                                  3000, 4000},
        MonsterContributionRecord{"write-g", "life-2", "wraith", "other-session", "other-character", 100, 4,
                                  1500, 2500}
    };
    const auto reconnected = allocate_monster_combat_rewards(
        reconnected_contributions, 101, 51);
    assert(reconnected.size() == 2);
    const auto same_character = std::find_if(reconnected.begin(), reconnected.end(),
        [](const auto& share) { return share.character_id == "same-character"; });
    assert(same_character != reconnected.end());
    assert(same_character->session_id == "new-session");
    assert(same_character->damage == 100);
    assert(same_character->experience == 50);
    assert(same_character->cultivation == 25);

    const auto empty = allocate_monster_combat_rewards({}, 0, 0, 100, 5);
    assert(empty.empty());
    return 0;
}
