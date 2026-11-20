#pragma once

#include <cstdint>
#include <string_view>

namespace honghuang::simulation {

struct ConsumableResources {
    std::int64_t health{};
    std::int64_t max_health{};
    std::int64_t mana{};
    std::int64_t max_mana{};
};

inline bool valid_consumable_resources(const ConsumableResources& value) {
    return value.health >= 0 && value.max_health > 0 &&
           value.health <= value.max_health && value.mana >= 0 &&
           value.max_mana >= 0 && value.mana <= value.max_mana;
}

inline bool valid_consumable_request(std::string_view request_id,
                                     std::string_view item_id,
                                     int quantity) {
    if (request_id.size() != 36 || item_id.empty() || item_id.size() > 96 ||
        quantity < 1 || quantity > 20) {
        return false;
    }
    for (std::size_t i = 0; i < request_id.size(); ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (request_id[i] != '-') return false;
            continue;
        }
        const char c = request_id[i];
        const bool hex = (c >= '0' && c <= '9') ||
                         (c >= 'a' && c <= 'f') ||
                         (c >= 'A' && c <= 'F');
        if (!hex) return false;
    }
    return true;
}

} // namespace honghuang::simulation
