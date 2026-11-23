#include "simulation/revive.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>

int main() {
    using namespace honghuang::simulation;

    assert(kAllyReviveRange == 3.5F);
    assert(kAllyReviveChannelMs == 5000);
    assert(kAllyReviveCooldownMs == 45000);
    assert(ally_revive_health(100) == 25);
    assert(ally_revive_health(99) == 24);
    assert(ally_revive_health(3) == 1);
    assert(ally_revive_health(1) == 1);
    assert(ally_revive_health(0) == 0);
    assert(ally_revive_health(-10) == 0);

    assert(ally_revive_in_range(3.5, 0.0));
    assert(ally_revive_in_range(2.1, 2.8));
    assert(!ally_revive_in_range(3.51, 0.0));
    assert(!ally_revive_in_range(0.0, 0.0, 0.0));
    assert(!ally_revive_in_range(NAN, 0.0));
    assert(!ally_revive_in_range(INFINITY, 0.0));

    assert(ally_revive_channel_valid(true, true, true, true, true, true));
    assert(!ally_revive_channel_valid(false, true, true, true, true, true));
    assert(!ally_revive_channel_valid(true, false, true, true, true, true));
    assert(!ally_revive_channel_valid(true, true, false, true, true, true));
    assert(!ally_revive_channel_valid(true, true, true, false, true, true));
    assert(!ally_revive_channel_valid(true, true, true, true, false, true));
    assert(!ally_revive_channel_valid(true, true, true, true, true, false));
}
