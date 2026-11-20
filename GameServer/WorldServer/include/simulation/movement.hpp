#pragma once

#include <algorithm>
#include <cmath>

namespace honghuang::simulation {

inline bool normalize_direction(float& x, float& z) {
    if (!std::isfinite(x) || !std::isfinite(z)) return false;
    const double magnitude = std::hypot(static_cast<double>(x), static_cast<double>(z));
    if (magnitude > 1.0) {
        x = static_cast<float>(static_cast<double>(x) / magnitude);
        z = static_cast<float>(static_cast<double>(z) / magnitude);
    }
    return true;
}

inline bool within_interest_radius(float ax, float az, float bx, float bz, float radius) {
    if (!std::isfinite(ax) || !std::isfinite(az) ||
        !std::isfinite(bx) || !std::isfinite(bz) ||
        !std::isfinite(radius) || radius < 0.0F) {
        return false;
    }
    const double dx = static_cast<double>(ax) - static_cast<double>(bx);
    const double dz = static_cast<double>(az) - static_cast<double>(bz);
    const double r = static_cast<double>(radius);
    return dx * dx + dz * dz <= r * r;
}

// Character and equipment movement bonuses are authoritative backend values.
// Keep a conservative range so malformed snapshots or extreme attributes cannot
// create teleport-like movement; invalid values fall back to the base speed.
inline float effective_player_movement_speed(float requested_speed) {
    if (!std::isfinite(requested_speed)) return 5.0F;
    return std::clamp(requested_speed, 1.0F, 10.0F);
}

inline void integrate_horizontal(float& x, float& z, float move_x, float move_z,
                                 float delta, float speed = 5.0F, float bound = 100.0F) {
    const float dt = std::clamp(delta, 0.0F, 0.1F);
    x = std::clamp(x + move_x * speed * dt, -bound, bound);
    z = std::clamp(z + move_z * speed * dt, -bound, bound);
}

inline void integrate_vertical(float& y, float& velocity, bool& jump_requested,
                               float delta, float gravity = 18.0F, float jump_velocity = 6.5F) {
    const float dt = std::clamp(delta, 0.0F, 0.1F);
    if (jump_requested && y <= 0.2F && velocity <= 0.0F) velocity = jump_velocity;
    jump_requested = false;
    velocity -= gravity * dt;
    y += velocity * dt;
    if (y < 0.0F) {
        y = 0.0F;
        velocity = 0.0F;
    }
}

} // namespace honghuang::simulation
