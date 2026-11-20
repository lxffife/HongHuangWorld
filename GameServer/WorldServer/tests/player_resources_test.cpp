#include "simulation/player_resources.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using honghuang::simulation::mana_regeneration_amount;
    using honghuang::simulation::mana_regeneration_interval_ms;

    // Spirit improves recovery by 0.2% per point, capped at 30%.
    assert(mana_regeneration_interval_ms(false, 0, 3000, 6000) == 3000);
    assert(mana_regeneration_interval_ms(false, 5, 3000, 6000) == 2970);
    assert(mana_regeneration_interval_ms(false, 50, 3000, 6000) == 2700);
    assert(mana_regeneration_interval_ms(false, 150, 3000, 6000) == 2100);
    assert(mana_regeneration_interval_ms(false, 100000, 3000, 6000) == 2100);
    assert(mana_regeneration_interval_ms(true, 0, 3000, 6000) == 6000);
    assert(mana_regeneration_interval_ms(true, 150, 3000, 6000) == 4200);
    assert(mana_regeneration_interval_ms(false, -1, 3000, 6000) == 0);
    assert(mana_regeneration_interval_ms(false, 0, 0, 6000) == 0);
    assert(mana_regeneration_interval_ms(true, 0, 3000, 0) == 0);

    // One point every three seconds; partial intervals do not round up.
    assert(mana_regeneration_amount(0, 20, 100, 3000) == 0);
    assert(mana_regeneration_amount(2999, 20, 100, 3000) == 0);
    assert(mana_regeneration_amount(3000, 20, 100, 3000) == 1);
    assert(mana_regeneration_amount(9000, 20, 100, 3000) == 3);

    // Regeneration is capped at maximum mana and never goes negative.
    assert(mana_regeneration_amount(30000, 99, 100, 3000) == 1);
    assert(mana_regeneration_amount(30000, 100, 100, 3000) == 0);
    assert(mana_regeneration_amount(30000, 120, 100, 3000) == 0);

    // Invalid intervals and resource values fail closed.
    assert(mana_regeneration_amount(3000, 10, 100, 0) == 0);
    assert(mana_regeneration_amount(3000, 10, 100, -1) == 0);
    assert(mana_regeneration_amount(-1, 10, 100, 3000) == 0);
    assert(mana_regeneration_amount(3000, -1, 100, 3000) == 0);
    assert(mana_regeneration_amount(3000, 10, -1, 3000) == 0);
    return 0;
}
