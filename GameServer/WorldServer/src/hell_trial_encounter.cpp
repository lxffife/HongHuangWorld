#include "simulation/hell_trial_encounter.hpp"

#include <algorithm>

namespace honghuang::simulation {
namespace {

const std::array<HellTrialFloorSpec, HellTrialEncounter::floor_count> kFloorSpecs{{
    {1, "拔舌狱", {"hell_f01_tongue_wraith", "hell_f01_sin_clerk", "hell_f01_echo_ghost"},
     {"割舌鬼", "罪簿吏", "回声冤魂"}, "hell_f01_tongue_jailer", "拔舌狱守将·铁舌判官", 8, 3},
    {2, "剪刀狱", {"hell_f02_blade_imp", "hell_f02_red_thread_wraith", "hell_f02_oath_hound"},
     {"断缘刃灵", "红线怨灵", "背誓狱犬"}, "hell_f02_scissor_lord", "剪刀狱守将·断缘鬼王", 12, 3},
    {3, "铁树狱", {"hell_f03_iron_bark", "hell_f03_hooked_root", "hell_f03_bone_gardener"},
     {"铁枝妖", "倒钩树根", "枯骨园丁"}, "hell_f03_iron_tree", "铁树狱守将·千钩木魈", 16, 3},
    {4, "孽镜狱", {"hell_f04_mirror_shard", "hell_f04_false_face", "hell_f04_guilt_seer"},
     {"镜片怨灵", "伪面鬼", "照罪使"}, "hell_f04_mirror_judge", "孽镜狱守将·照业明王", 20, 3},
    {5, "蒸笼狱", {"hell_f05_steam_wraith", "hell_f05_boiling_sinner", "hell_f05_lid_guard"},
     {"蒸汽怨灵", "沸罪囚", "笼盖卫"}, "hell_f05_steam_king", "蒸笼狱守将·沸狱王", 24, 3},
    {6, "铜柱狱", {"hell_f06_copper_sentinel", "hell_f06_molten_chain", "hell_f06_ash_prisoner"},
     {"铜柱卫", "熔链煞", "灰烬囚魂"}, "hell_f06_copper_pillar", "铜柱狱守将·赤铜刑君", 28, 3},
    {7, "刀山狱", {"hell_f07_blade_climber", "hell_f07_edge_hawk", "hell_f07_scarred_wraith"},
     {"攀刃恶魂", "刃羽鹰", "刀痕厉鬼"}, "hell_f07_blade_marshal", "刀山狱守将·万刃将军", 32, 3},
    {8, "冰山狱", {"hell_f08_frost_sinner", "hell_f08_ice_wolf", "hell_f08_frozen_guard"},
     {"寒魄囚", "冰原狱狼", "冻魂卫"}, "hell_f08_ice_empress", "冰山狱守将·玄冰女君", 36, 3},
    {9, "油锅狱", {"hell_f09_oil_imp", "hell_f09_flame_herald", "hell_f09_scorched_sinner"},
     {"油沸小鬼", "引焰使", "焦灼罪魂"}, "hell_f09_oil_demon", "油锅狱守将·九沸魔尊", 40, 3},
    {10, "牛坑狱", {"hell_f10_iron_ox", "hell_f10_bone_stampede", "hell_f10_earthbreaker"},
     {"铁角牛", "踏骨群魂", "裂地兽"}, "hell_f10_ox_commander", "牛坑狱守将·镇坑牛魔", 44, 3},
    {11, "石压狱", {"hell_f11_crushing_stone", "hell_f11_gravestone_wraith", "hell_f11_buried_sinner"},
     {"坠石精", "碑下怨灵", "石封囚魂"}, "hell_f11_stone_jailer", "石压狱守将·镇岳石君", 48, 3},
    {12, "舂臼狱", {"hell_f12_mortar_ghost", "hell_f12_pestle_construct", "hell_f12_grain_wraith"},
     {"石臼鬼", "舂杵机关", "碎骨灵"}, "hell_f12_mortar_king", "舂臼狱守将·碎魂大臼", 52, 3},
    {13, "血池狱", {"hell_f13_blood_leech", "hell_f13_red_river_wraith", "hell_f13_blood_guard"},
     {"噬血虫", "赤河怨灵", "血池卫"}, "hell_f13_blood_lord", "血池狱守将·赤池尊者", 56, 3},
    {14, "枉死狱", {"hell_f14_unclaimed_soul", "hell_f14_grudge_bride", "hell_f14_nameless_wraith"},
     {"无名游魂", "含冤新娘", "无籍厉鬼"}, "hell_f14_wrongful_king", "枉死狱守将·无名鬼王", 60, 3},
    {15, "磔刑狱", {"hell_f15_chain_executioner", "hell_f15_split_soul", "hell_f15_hook_guard"},
     {"锁链刑卒", "裂魂囚", "钩刑卫"}, "hell_f15_executioner", "磔刑狱守将·裂魂刑尊", 64, 3},
    {16, "火山狱", {"hell_f16_lava_wraith", "hell_f16_ash_drake", "hell_f16_magma_guard"},
     {"熔岩怨灵", "灰烬地龙", "岩浆卫"}, "hell_f16_volcano_king", "火山狱守将·焚天炎君", 68, 3},
    {17, "石磨狱", {"hell_f17_grindstone_soul", "hell_f17_mill_wraith", "hell_f17_bone_dust"},
     {"磨魂石灵", "石磨怨灵", "骨粉恶魂"}, "hell_f17_grind_lord", "石磨狱守将·碾业天尊", 72, 3},
    {18, "刀锯狱", {"hell_f18_void_blade", "hell_f18_abyssal_chain", "hell_f18_last_sinner"},
     {"无间刃灵", "深渊锁魂", "终末罪魂"}, "hell_f18_abyss_judge", "刀锯狱终极守将·无间判主", 80, 3}
}};

} // namespace

const std::array<HellTrialFloorSpec, HellTrialEncounter::floor_count>&
hell_trial_floor_specs() {
    return kFloorSpecs;
}

HellTrialEncounter::HellTrialEncounter(int floor) : floor_(floor) {
    if (floor_ >= 1 && floor_ <= floor_count) {
        spec_ = &kFloorSpecs[static_cast<std::size_t>(floor_ - 1)];
    } else {
        floor_ = 0;
    }
}

bool HellTrialEncounter::enabled() const { return spec_ != nullptr; }
int HellTrialEncounter::floor() const { return floor_; }
const HellTrialFloorSpec* HellTrialEncounter::spec() const { return spec_; }
int HellTrialEncounter::objective_kills() const { return objective_kills_; }
bool HellTrialEncounter::guardian_defeated() const { return guardian_defeated_; }
bool HellTrialEncounter::completed() const { return completed_; }

void HellTrialEncounter::clamp_player_position(float& x, float& z) const {
    if (!spec_) return;
    constexpr float kArenaHalfExtent = 27.0F;
    x = std::clamp(x, -kArenaHalfExtent, kArenaHalfExtent);
    z = std::clamp(z, -kArenaHalfExtent, kArenaHalfExtent);
}

HellTrialDeathResult HellTrialEncounter::record_monster_death(
    std::string_view runtime_id, std::string_view definition_id) {
    HellTrialDeathResult result;
    if (!spec_ || runtime_id.empty() || definition_id.empty() || completed_) {
        result.objective_kills = objective_kills_;
        result.objective_required = spec_ ? spec_->objective_required : 0;
        result.guardian_defeated = guardian_defeated_;
        return result;
    }

    if (definition_id == spec_->guardian_id) {
        if (!guardian_defeated_) {
            guardian_defeated_ = true;
            result.guardian_killed = true;
        }
    } else {
        const auto found = std::find(spec_->objective_monster_ids.begin(),
                                     spec_->objective_monster_ids.end(), definition_id);
        if (found != spec_->objective_monster_ids.end()) {
            const auto [_, inserted] = counted_runtime_ids_.emplace(runtime_id);
            if (inserted) {
                ++objective_kills_;
                result.objective_kill_recorded = true;
            }
        }
    }

    result.objective_kills = objective_kills_;
    result.objective_required = spec_->objective_required;
    result.guardian_defeated = guardian_defeated_;
    if (objective_kills_ >= spec_->objective_required && guardian_defeated_) {
        completed_ = true;
        result.completion_ready = true;
    }
    return result;
}

} // namespace honghuang::simulation
