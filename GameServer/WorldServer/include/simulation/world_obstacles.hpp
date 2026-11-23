#pragma once

#include "simulation/movement.hpp"

#include <array>
#include <algorithm>

namespace honghuang::simulation {

struct WorldObstacle {
    float min_x;
    float max_x;
    float min_z;
    float max_z;
};

inline constexpr float kPlayerCollisionRadius = 0.45F;

// Server-authoritative solid footprints for the current Fengdu capital graybox.
// Coordinates mirror FengduCityBuilder's schematic-to-world transform:
// world_x = schematic_x * 0.12, world_z = -schematic_y * 0.12 - 60.
// Gate openings are intentionally absent from the wall rectangles.
inline constexpr std::array<WorldObstacle, 19> kFengduObstacles{{
    // Main building footprints (the visible/collidable halls, not decorative roofs).
    {-6.283F, 6.283F, -84.845F, -77.875F},       // Imperial Palace
    {-28.186F, -17.414F, -74.290F, -68.270F},    // Ten Kings Manors
    {17.414F, 28.186F, -74.290F, -68.270F},      // Judge Court
    {-28.186F, -17.414F, -62.050F, -56.030F},    // Ghost Registry
    {17.414F, 28.186F, -62.050F, -56.030F},      // Merit Bureau
    {-4.814F, 4.814F, -63.895F, -58.985F},       // Patrol Office
    {-6.120F, 6.120F, -46.049F, -39.871F},       // Reincarnation Bureau
    {17.006F, 28.594F, -43.090F, -37.070F},      // Ghost Market
    {-28.594F, -17.006F, -43.090F, -37.070F},    // Residential Quarter
    {-40.191F, -33.009F, -65.172F, -59.628F},    // Yin Army Camp
    {33.009F, 40.191F, -65.172F, -59.628F},      // Soul Waystation

    // North and south walls: 12 m centered gate openings.
    {-47.0F, -6.0F, -97.9F, -96.1F},
    {6.0F, 47.0F, -97.9F, -96.1F},
    {-47.0F, -6.0F, -23.9F, -22.1F},
    {6.0F, 47.0F, -23.9F, -22.1F},

    // East and west walls: matching 12 m gate openings.
    {-47.9F, -46.1F, -94.0F, -63.0F},
    {-47.9F, -46.1F, -57.0F, -26.0F},
    {46.1F, 47.9F, -94.0F, -63.0F},
    {46.1F, 47.9F, -57.0F, -26.0F}
}};

inline bool circle_overlaps_obstacle(float x, float z, const WorldObstacle& obstacle,
                                     float radius = kPlayerCollisionRadius) {
    if (!std::isfinite(x) || !std::isfinite(z) || !std::isfinite(radius) || radius < 0.0F) {
        return true;
    }
    const float closest_x = std::clamp(x, obstacle.min_x, obstacle.max_x);
    const float closest_z = std::clamp(z, obstacle.min_z, obstacle.max_z);
    const float dx = x - closest_x;
    const float dz = z - closest_z;
    return dx * dx + dz * dz < radius * radius;
}

inline void integrate_horizontal_with_obstacles(
    float& x, float& z, float move_x, float move_z, float delta,
    const WorldObstacle* obstacles, std::size_t obstacle_count,
    float speed = 5.0F, float bound = 100.0F,
    float radius = kPlayerCollisionRadius) {
    if (!std::isfinite(x) || !std::isfinite(z) ||
        !std::isfinite(move_x) || !std::isfinite(move_z) ||
        !std::isfinite(speed) || !std::isfinite(bound) ||
        !std::isfinite(radius) || radius < 0.0F || bound <= 0.0F) {
        return;
    }
    const float dt = std::clamp(delta, 0.0F, 0.1F);
    const float dx = move_x * speed * dt;
    const float dz = move_z * speed * dt;
    const float candidate_x = std::clamp(x + dx, -bound, bound);
    const float candidate_z = std::clamp(z + dz, -bound, bound);

    // Resolve axes independently so a blocked diagonal move can slide along a wall.
    bool blocked_x = false;
    for (std::size_t i = 0; i < obstacle_count; ++i) {
        if (circle_overlaps_obstacle(candidate_x, z, obstacles[i], radius)) {
            blocked_x = true;
            break;
        }
    }
    if (!blocked_x) x = candidate_x;

    bool blocked_z = false;
    for (std::size_t i = 0; i < obstacle_count; ++i) {
        if (circle_overlaps_obstacle(x, candidate_z, obstacles[i], radius)) {
            blocked_z = true;
            break;
        }
    }
    if (!blocked_z) z = candidate_z;
}

inline void integrate_fengdu_horizontal(float& x, float& z, float move_x, float move_z,
                                        float delta, float speed = 5.0F) {
    integrate_horizontal_with_obstacles(x, z, move_x, move_z, delta,
        kFengduObstacles.data(), kFengduObstacles.size(), speed);
}

} // namespace honghuang::simulation
