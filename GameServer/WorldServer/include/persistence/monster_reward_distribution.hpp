#pragma once

#include "persistence/durable_outbox.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace honghuang::persistence {

struct MonsterCombatRewardShare {
    std::string session_id;
    std::string character_id;
    std::int64_t damage{};
    std::int64_t experience{};
    std::int64_t cultivation{};
};

// Deterministic integer allocation: proportional floors first, then distribute
// the rounding remainder by damage descending and stable identity order.
inline std::vector<MonsterCombatRewardShare> allocate_monster_combat_rewards(
    const std::vector<MonsterContributionRecord>& records,
    std::int64_t total_experience,
    std::int64_t total_cultivation) {
    std::vector<MonsterCombatRewardShare> shares;
    long double total_damage = 0.0L;
    for (const auto& record : records) {
        if (record.total_damage <= 0 || record.hit_count <= 0 ||
            record.session_id.empty() || record.character_id.empty()) continue;
        shares.push_back(MonsterCombatRewardShare{
            record.session_id, record.character_id, record.total_damage, 0, 0
        });
        total_damage += static_cast<long double>(record.total_damage);
    }
    if (shares.empty() || total_damage <= 0.0L) return {};

    std::sort(shares.begin(), shares.end(),
        [](const MonsterCombatRewardShare& left, const MonsterCombatRewardShare& right) {
            if (left.damage != right.damage) return left.damage > right.damage;
            if (left.character_id != right.character_id)
                return left.character_id < right.character_id;
            return left.session_id < right.session_id;
        });

    const auto reward_experience = std::max<std::int64_t>(0, total_experience);
    const auto reward_cultivation = std::max<std::int64_t>(0, total_cultivation);
    std::int64_t assigned_experience = 0;
    std::int64_t assigned_cultivation = 0;
    for (auto& share : shares) {
        const auto ratio = static_cast<long double>(share.damage) / total_damage;
        share.experience = static_cast<std::int64_t>(std::floor(
            static_cast<long double>(reward_experience) * ratio));
        share.cultivation = static_cast<std::int64_t>(std::floor(
            static_cast<long double>(reward_cultivation) * ratio));
        assigned_experience += share.experience;
        assigned_cultivation += share.cultivation;
    }

    auto experience_remainder = reward_experience - assigned_experience;
    auto cultivation_remainder = reward_cultivation - assigned_cultivation;
    for (auto& share : shares) {
        if (experience_remainder > 0) {
            ++share.experience;
            --experience_remainder;
        }
        if (cultivation_remainder > 0) {
            ++share.cultivation;
            --cultivation_remainder;
        }
    }
    return shares;
}

} // namespace honghuang::persistence
