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
