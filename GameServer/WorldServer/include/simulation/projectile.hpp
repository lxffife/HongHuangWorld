#pragma once

#include <algorithm>
#include <cmath>

namespace honghuang::simulation {

// Advances a server-owned projectile in the XZ plane and performs a swept-circle
// collision check so a fast projectile cannot skip over a small target between ticks.
inline bool advance_projectile(float& x, float& z, float velocity_x, float velocity_z,
                               float delta_seconds, float target_x, float target_z,
                               float hit_radius) {
    if (!std::isfinite(x) || !std::isfinite(z) || !std::isfinite(velocity_x) ||
        !std::isfinite(velocity_z) || !std::isfinite(delta_seconds) ||
        !std::isfinite(target_x) || !std::isfinite(target_z) ||
        !std::isfinite(hit_radius) || delta_seconds < 0.0F || hit_radius <= 0.0F) {
        return false;
    }
    const float start_x = x;
    const float start_z = z;
    const float end_x = start_x + velocity_x * delta_seconds;
    const float end_z = start_z + velocity_z * delta_seconds;
    const float segment_x = end_x - start_x;
    const float segment_z = end_z - start_z;
    const float segment_length_squared = segment_x * segment_x + segment_z * segment_z;
    float t = 0.0F;
    if (segment_length_squared > 0.000001F) {
        t = std::clamp(((target_x - start_x) * segment_x + (target_z - start_z) * segment_z) /
                           segment_length_squared,
                       0.0F, 1.0F);
    }
    const float closest_x = start_x + segment_x * t;
    const float closest_z = start_z + segment_z * t;
    const float dx = target_x - closest_x;
    const float dz = target_z - closest_z;
    x = end_x;
    z = end_z;
    return dx * dx + dz * dz <= hit_radius * hit_radius;
}

} // namespace honghuang::simulation
