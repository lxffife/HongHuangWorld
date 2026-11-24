#pragma once

#include "persistence/durable_outbox.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

namespace honghuang::persistence {

struct BountyMonsterContributor {
    std::string session_id;
    std::string character_id;
    std::int64_t damage{};
    std::int64_t hit_count{};
    std::int64_t latest_hit_at_ms{};
};

// Merge one monster-life/task's records by character. A reconnect must not
// create a second bounty participant or overwrite a newer session with an older
// replayed contribution. Sorting makes serialized outbox payloads deterministic.
inline std::vector<BountyMonsterContributor> aggregate_bounty_monster_contributors(
    const std::vector<MonsterContributionRecord>& records) {
    std::vector<BountyMonsterContributor> contributors;
    std::unordered_map<std::string, std::size_t> index_by_character;

    const auto saturating_add = [](std::int64_t current, std::int64_t value) {
        if (value <= 0) return current;
        return current > std::numeric_limits<std::int64_t>::max() - value
            ? std::numeric_limits<std::int64_t>::max() : current + value;
    };

    for (const auto& record : records) {
        if (record.total_damage <= 0 || record.hit_count <= 0 ||
            record.character_id.empty() || record.session_id.empty()) continue;

        const auto [found, inserted] = index_by_character.emplace(
            record.character_id, contributors.size());
        if (inserted) {
            contributors.push_back(BountyMonsterContributor{
                record.session_id, record.character_id, record.total_damage,
                record.hit_count, record.last_hit_at_ms
            });
            continue;
        }

        auto& aggregate = contributors[found->second];
        aggregate.damage = saturating_add(aggregate.damage, record.total_damage);
        aggregate.hit_count = saturating_add(aggregate.hit_count, record.hit_count);
        if (record.last_hit_at_ms > aggregate.latest_hit_at_ms ||
            (record.last_hit_at_ms == aggregate.latest_hit_at_ms &&
             record.session_id < aggregate.session_id)) {
            aggregate.session_id = record.session_id;
            aggregate.latest_hit_at_ms = record.last_hit_at_ms;
        }
    }

    std::sort(contributors.begin(), contributors.end(),
        [](const BountyMonsterContributor& left, const BountyMonsterContributor& right) {
            return left.character_id < right.character_id;
        });
    return contributors;
}

} // namespace honghuang::persistence
