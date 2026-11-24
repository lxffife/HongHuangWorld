#pragma once

#include "persistence/durable_outbox.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <limits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace honghuang::persistence {

struct MonsterCombatRewardShare {
    std::string session_id;
    std::string character_id;
    std::int64_t damage{};
    std::int64_t experience{};
    std::int64_t cultivation{};
    std::int64_t ghost_cash{};
    std::int64_t nether_stone{};
};

// Deterministic integer allocation: proportional floors first, then distribute
// the rounding remainder by damage descending and stable identity order.
inline std::vector<MonsterCombatRewardShare> allocate_monster_combat_rewards(
    const std::vector<MonsterContributionRecord>& records,
    std::int64_t total_experience,
    std::int64_t total_cultivation,
    std::int64_t total_ghost_cash = 0,
    std::int64_t total_nether_stone = 0) {
    // A character may contribute through multiple sessions after reconnecting.
    // Merge damage by character so one life grants one proportional reward per
    // character. Route that reward through the session with the latest contribution;
    // ties use a stable session-id order for deterministic recovery/replay.
    std::vector<MonsterCombatRewardShare> shares;
    std::unordered_map<std::string, std::size_t> share_index_by_character;
    std::unordered_map<std::string, std::pair<std::int64_t, std::string>>
        latest_session_by_character;
    for (const auto& record : records) {
        if (record.total_damage <= 0 || record.hit_count <= 0 ||
            record.session_id.empty() || record.character_id.empty()) continue;
        const auto [found, inserted] = share_index_by_character.emplace(
            record.character_id, shares.size());
        if (inserted) {
            shares.push_back(MonsterCombatRewardShare{
                record.session_id, record.character_id, record.total_damage, 0, 0, 0, 0
            });
            latest_session_by_character.emplace(
                record.character_id, std::make_pair(record.last_hit_at_ms, record.session_id));
            continue;
        }
        auto& share = shares[found->second];
        if (share.damage > std::numeric_limits<std::int64_t>::max() - record.total_damage)
            share.damage = std::numeric_limits<std::int64_t>::max();
        else
            share.damage += record.total_damage;
        auto& latest = latest_session_by_character.at(record.character_id);
        if (record.last_hit_at_ms > latest.first ||
            (record.last_hit_at_ms == latest.first && record.session_id < latest.second)) {
            latest = std::make_pair(record.last_hit_at_ms, record.session_id);
            share.session_id = record.session_id;
        }
    }

    long double total_damage = 0.0L;
    for (const auto& share : shares)
        total_damage += static_cast<long double>(share.damage);
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
    const auto reward_ghost_cash = std::max<std::int64_t>(0, total_ghost_cash);
    const auto reward_nether_stone = std::max<std::int64_t>(0, total_nether_stone);
    std::int64_t assigned_experience = 0;
    std::int64_t assigned_cultivation = 0;
    std::int64_t assigned_ghost_cash = 0;
    std::int64_t assigned_nether_stone = 0;
    for (auto& share : shares) {
        const auto ratio = static_cast<long double>(share.damage) / total_damage;
        share.experience = static_cast<std::int64_t>(std::floor(
            static_cast<long double>(reward_experience) * ratio));
        share.cultivation = static_cast<std::int64_t>(std::floor(
            static_cast<long double>(reward_cultivation) * ratio));
        assigned_experience += share.experience;
        share.ghost_cash = static_cast<std::int64_t>(std::floor(static_cast<long double>(reward_ghost_cash) * ratio));
        share.nether_stone = static_cast<std::int64_t>(std::floor(static_cast<long double>(reward_nether_stone) * ratio));
        assigned_cultivation += share.cultivation;
        assigned_ghost_cash += share.ghost_cash;
        assigned_nether_stone += share.nether_stone;
    }

    auto experience_remainder = reward_experience - assigned_experience;
    auto cultivation_remainder = reward_cultivation - assigned_cultivation;
    auto ghost_cash_remainder = reward_ghost_cash - assigned_ghost_cash;
    auto nether_stone_remainder = reward_nether_stone - assigned_nether_stone;
    for (auto& share : shares) {
        if (experience_remainder > 0) {
            ++share.experience;
            --experience_remainder;
        }
        if (cultivation_remainder > 0) {
            ++share.cultivation;
            --cultivation_remainder;
        }
        if (ghost_cash_remainder > 0) {
            ++share.ghost_cash;
            --ghost_cash_remainder;
        }
        if (nether_stone_remainder > 0) {
            ++share.nether_stone;
            --nether_stone_remainder;
        }
    }
    return shares;
}

} // namespace honghuang::persistence
