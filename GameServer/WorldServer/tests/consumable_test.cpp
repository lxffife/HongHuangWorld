#include "simulation/consumable.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using honghuang::simulation::ConsumableResources;
    using honghuang::simulation::valid_consumable_resources;
    using honghuang::simulation::valid_consumable_request;

    assert(valid_consumable_request(
        "00000000-0000-4000-8000-000000000001", "small_mana_pill", 1));
    assert(valid_consumable_request(
        "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", "healing_pill", 20));
    assert(!valid_consumable_request("", "small_mana_pill", 1));
    assert(!valid_consumable_request(
        "00000000000040008000000000000001", "small_mana_pill", 1));
    assert(!valid_consumable_request(
        "00000000-0000-4000-8000-00000000000z", "small_mana_pill", 1));
    assert(!valid_consumable_request(
        "00000000-0000-4000-8000-000000000001", "", 1));
    assert(!valid_consumable_request(
        "00000000-0000-4000-8000-000000000001", "small_mana_pill", 0));
    assert(!valid_consumable_request(
        "00000000-0000-4000-8000-000000000001", "small_mana_pill", 21));

    assert(valid_consumable_resources(ConsumableResources{75, 100, 42, 60}));
    assert(valid_consumable_resources(ConsumableResources{0, 100, 0, 0}));
    assert(!valid_consumable_resources(ConsumableResources{-1, 100, 0, 60}));
    assert(!valid_consumable_resources(ConsumableResources{101, 100, 0, 60}));
    assert(!valid_consumable_resources(ConsumableResources{0, 0, 0, 60}));
    assert(!valid_consumable_resources(ConsumableResources{0, 100, -1, 60}));
    assert(!valid_consumable_resources(ConsumableResources{0, 100, 61, 60}));

    return 0;
}
