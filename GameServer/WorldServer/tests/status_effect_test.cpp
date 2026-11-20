#include "simulation/status_effect.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <limits>

int main() {
    using namespace honghuang::simulation;
    TimedSlowEffect effect;
    assert(!slow_is_active(effect, 1000));
    assert(apply_slow(effect, 1000, 3000, 0.55F));
    assert(slow_is_active(effect, 1001));
    assert(!slow_is_active(effect, 4000));
    assert(std::abs(movement_delta_with_effect(0.1F, effect, 2000) - 0.055F) < 0.00001F);
    assert(std::abs(movement_delta_with_effect(0.1F, effect, 4000) - 0.1F) < 0.00001F);

    // A refresh extends duration, while a weaker slow cannot overwrite a stronger one.
    assert(apply_slow(effect, 2000, 3000, 0.8F));
    assert(effect.expires_at_ms == 5000);
    assert(effect.movement_multiplier == 0.55F);
    assert(apply_slow(effect, 4500, 1000, 0.7F));
    assert(effect.expires_at_ms == 5500);
    assert(effect.movement_multiplier == 0.55F);

    assert(!apply_slow(effect, 0, 0, 0.5F));
    assert(!apply_slow(effect, 0, 1000, 1.0F));
    assert(!apply_slow(effect, 0, 1000, std::numeric_limits<float>::quiet_NaN()));
    assert(!apply_slow(effect, INT64_MAX - 10, 1000, 0.5F));
    assert(movement_delta_with_effect(-1.0F, effect, 4500) == 0.0F);
    return 0;
}
