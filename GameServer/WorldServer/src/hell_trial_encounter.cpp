#include "simulation/hell_trial_encounter.hpp"

#include <algorithm>
#include <cmath>

namespace honghuang::simulation {
namespace {

const std::array<HellTrialFloorSpec, HellTrialEncounter::floor_count> kFloorSpecs{{
    {1, "拔舌地狱", {"hell_f01_tongue_wraith", "hell_f01_sin_clerk", "hell_f01_echo_ghost"},
     {"割舌鬼", "罪簿吏", "回声冤魂"}, "hell_f01_tongue_jailer", "拔舌判官", "先辨明三类冤魂的罪簿线索，再逐波清剿；不要越过当前开放的目标。", "拔舌判官会交替使用远距噬魂与近身重击，留意起手动作。", 8, 3},
    {2, "剪刀地狱", {"hell_f02_blade_imp", "hell_f02_red_thread_wraith", "hell_f02_oath_hound"},
     {"断缘刃灵", "红线怨灵", "背誓狱犬"}, "hell_f02_scissor_lord", "剪缘鬼将", "优先追击断缘刃灵，避免被背誓狱犬贴身围困；逐波推进。", "剪缘鬼将擅长快速斩击，近身时注意预留闪避空间。", 12, 3},
    {3, "铁树地狱", {"hell_f03_iron_bark", "hell_f03_hooked_root", "hell_f03_bone_gardener"},
     {"铁枝妖", "倒钩树根", "枯骨园丁"}, "hell_f03_iron_tree", "铁树守狱使", "清理铁枝妖、倒钩树根与枯骨园丁，推进时注意树根与铁刺地形。", "铁树守狱使会扩大近身压迫，避免长时间停留在其正面。", 16, 3},
    {4, "孽镜地狱", {"hell_f04_mirror_shard", "hell_f04_false_face", "hell_f04_guilt_seer"},
     {"镜片怨灵", "伪面鬼", "照罪使"}, "hell_f04_mirror_judge", "孽镜司主", "逐一击破镜片怨灵、伪面鬼与照罪使，观察目标变化再集火。", "孽镜司主擅长制造迷惑与远程压制，保持目标识别。", 20, 3},
    {5, "蒸笼地狱", {"hell_f05_steam_wraith", "hell_f05_boiling_sinner", "hell_f05_lid_guard"},
     {"蒸汽怨灵", "沸罪囚", "笼盖卫"}, "hell_f05_steam_king", "蒸笼狱卒长", "逐波清除蒸汽怨灵、沸罪囚与笼盖卫，避免扎堆承受持续伤害。", "蒸笼狱卒长会强化范围压制，队伍分散站位更稳妥。", 24, 3},
    {6, "铜柱地狱", {"hell_f06_copper_sentinel", "hell_f06_molten_chain", "hell_f06_ash_prisoner"},
     {"铜柱卫", "熔链煞", "灰烬囚魂"}, "hell_f06_copper_pillar", "铜柱刑官", "先处理铜柱卫、熔链煞与灰烬囚魂，再挑战铜柱刑官。", "铜柱刑官攻势沉重，注意其蓄力节奏并及时拉开。", 28, 3},
    {7, "刀山地狱", {"hell_f07_blade_climber", "hell_f07_edge_hawk", "hell_f07_scarred_wraith"},
     {"攀刃恶魂", "刃羽鹰", "刀痕厉鬼"}, "hell_f07_blade_marshal", "刀山巡狱将", "攀刃恶魂、刃羽鹰与刀痕厉鬼依次出现，优先处理远程骚扰目标。", "刀山巡狱将擅长突进与横扫，避免沿单一直线站位。", 32, 3},
    {8, "冰山地狱", {"hell_f08_frost_sinner", "hell_f08_ice_wolf", "hell_f08_frozen_guard"},
     {"寒魄囚", "冰原狱狼", "冻魂卫"}, "hell_f08_ice_empress", "冰山女狱吏", "寒魄囚、冰原狱狼与冻魂卫会逐波迎战，保持移动并照看队友。", "冰山女狱吏会强化寒狱攻势，注意控制距离与队伍状态。", 36, 3},
    {9, "油锅地狱", {"hell_f09_oil_imp", "hell_f09_flame_herald", "hell_f09_scorched_sinner"},
     {"油沸小鬼", "引焰使", "焦灼罪魂"}, "hell_f09_oil_demon", "油锅狱主", "依次清理油沸小鬼、引焰使与焦灼罪魂，避免在同一区域聚集。", "油锅狱主的范围攻击危险，看到蓄力时及时撤出中心区域。", 40, 3},
    {10, "牛坑地狱", {"hell_f10_iron_ox", "hell_f10_bone_stampede", "hell_f10_earthbreaker"},
     {"铁角牛", "踏骨群魂", "裂地兽"}, "hell_f10_ox_commander", "牛坑监狱官", "铁角牛、踏骨群魂与裂地兽会形成冲锋压力，尽量避免正面硬接。", "牛坑监狱官擅长冲撞，注意观察其朝向并及时侧移。", 44, 3},
    {11, "石压地狱", {"hell_f11_crushing_stone", "hell_f11_gravestone_wraith", "hell_f11_buried_sinner"},
     {"坠石精", "碑下怨灵", "石封囚魂"}, "hell_f11_stone_jailer", "石压力士", "坠石精、碑下怨灵与石封囚魂逐波出现，保持队伍阵型不要脱节。", "石压力士攻击迟缓但威力大，利用前摇创造输出窗口。", 48, 3},
    {12, "舂臼地狱", {"hell_f12_mortar_ghost", "hell_f12_pestle_construct", "hell_f12_grain_wraith"},
     {"石臼鬼", "舂杵机关", "碎骨灵"}, "hell_f12_mortar_king", "舂臼刑使", "石臼鬼、舂杵机关与碎骨灵逐波出现，注意目标切换和队伍协同。", "舂臼刑使擅长重击，避免在其攻击范围内持续停留。", 52, 3},
    {13, "血池地狱", {"hell_f13_blood_leech", "hell_f13_red_river_wraith", "hell_f13_blood_guard"},
     {"噬血虫", "赤河怨灵", "血池卫"}, "hell_f13_blood_lord", "血池夜叉统领", "噬血虫、赤河怨灵与血池卫依次出现，及时处理持续威胁。", "血池夜叉统领会持续施压，注意生命值并合理安排治疗。", 56, 3},
    {14, "枉死地狱", {"hell_f14_unclaimed_soul", "hell_f14_grudge_bride", "hell_f14_nameless_wraith"},
     {"无名游魂", "含冤新娘", "无籍厉鬼"}, "hell_f14_wrongful_king", "枉死城主", "无名游魂、含冤新娘与无籍厉鬼逐波迎战，优先清理脆弱目标。", "枉死城主擅长持续追击，队伍应避免被逐个拉开。", 60, 3},
    {15, "磔刑地狱", {"hell_f15_chain_executioner", "hell_f15_split_soul", "hell_f15_hook_guard"},
     {"锁链刑卒", "裂魂囚", "钩刑卫"}, "hell_f15_executioner", "磔刑鬼将", "锁链刑卒、裂魂囚与钩刑卫依次出现，注意被近身控制的风险。", "磔刑鬼将攻击范围较大，近战与远程应错开站位。", 64, 3},
    {16, "火山地狱", {"hell_f16_lava_wraith", "hell_f16_ash_drake", "hell_f16_magma_guard"},
     {"熔岩怨灵", "灰烬地龙", "岩浆卫"}, "hell_f16_volcano_king", "火山狱君", "熔岩怨灵、灰烬地龙与岩浆卫逐波出现，注意危险区域并持续移动。", "火山狱君会强化范围打击，蓄力时及时离开危险区域。", 68, 3},
    {17, "石磨地狱", {"hell_f17_grindstone_soul", "hell_f17_mill_wraith", "hell_f17_bone_dust"},
     {"磨魂石灵", "石磨怨灵", "骨粉恶魂"}, "hell_f17_grind_lord", "石磨鬼王", "磨魂石灵、石磨怨灵与骨粉恶魂逐波出现，避免被持续消耗。", "石磨鬼王攻势沉重，注意其重击节奏与队伍续航。", 72, 3},
    {18, "阿鼻无间地狱", {"hell_f18_void_blade", "hell_f18_abyssal_chain", "hell_f18_last_sinner"},
     {"无间刃灵", "深渊锁魂", "终末罪魂"}, "hell_f18_abyss_judge", "无间狱主", "无间刃灵、深渊锁魂与终末罪魂是最终试炼，保持资源并协同推进。", "无间狱主会组合多阶段攻势，保留关键技能应对最终阶段。", 80, 3}
}};

} // namespace



HellTrialSoulRescue::HellTrialSoulRescue(int floor) : enabled_(floor == 3) {}
bool HellTrialSoulRescue::enabled() const { return enabled_; }
bool HellTrialSoulRescue::completed() const { return enabled_ && completed_; }
int HellTrialSoulRescue::rescued_count() const {
    return completed_ ? 2 : (first_lantern_id_.empty() ? 0 : 1);
}
std::string_view HellTrialSoulRescue::first_lantern_id() const { return first_lantern_id_; }

double HellTrialSoulRescue::remaining_seconds(double now_seconds) const {
    if (!enabled_ || completed_ || first_lantern_id_.empty() || !std::isfinite(now_seconds)) return 0.0;
    return std::max(0.0, deadline_seconds_ - now_seconds);
}

HellTrialSoulRescueResult HellTrialSoulRescue::activate(
    std::string_view lantern_id, std::string_view rescuer_id, double now_seconds) {
    HellTrialSoulRescueResult result;
    result.completed = completed();
    result.rescued_count = rescued_count();
    result.first_lantern_id = first_lantern_id_;
    if (!enabled_) {
        result.message = "当前楼层没有开放魂灯救援。";
        return result;
    }
    if (completed_) {
        result.accepted = true;
        result.message = "两盏魂灯已经复明，亡魂已脱离铁树刑阵。";
        return result;
    }
    if ((lantern_id != "west" && lantern_id != "east") || rescuer_id.empty() ||
        !std::isfinite(now_seconds)) {
        result.message = "魂灯救援请求无效。";
        return result;
    }
    if (!first_lantern_id_.empty() && now_seconds >= deadline_seconds_) {
        first_lantern_id_.clear();
        first_rescuer_id_.clear();
        deadline_seconds_ = 0.0;
        result.expired = true;
    }
    if (first_lantern_id_.empty()) {
        first_lantern_id_ = std::string(lantern_id);
        first_rescuer_id_ = std::string(rescuer_id);
        deadline_seconds_ = now_seconds + 15.0;
        result.accepted = true;
        result.rescued_count = 1;
        result.first_lantern_id = first_lantern_id_;
        result.message = result.expired
            ? "先前的接应时限已过，救援重新开始。守住这盏魂灯，等待另一名队友点亮对侧魂灯。"
            : "魂灯暂时复明！请另一名队友在 15 秒内点亮另一侧魂灯。";
        return result;
    }
    if (lantern_id == first_lantern_id_) {
        result.message = "这盏魂灯已经点亮，请前往另一侧魂灯。";
        return result;
    }
    if (rescuer_id == first_rescuer_id_) {
        result.message = "需要另一名队友同时接应，独自无法稳住两盏魂灯。";
        return result;
    }
    completed_ = true;
    result.accepted = true;
    result.completed = true;
    result.rescued_count = 2;
    result.first_lantern_id = first_lantern_id_;
    result.message = "两名队友同时稳住魂灯，铁树刑阵松动！两名亡魂获救。";
    return result;
}

HellTrialShearHazard::HellTrialShearHazard(int floor) : enabled_(floor == 2) {}
bool HellTrialShearHazard::enabled() const { return enabled_; }
HellTrialHazardPhase HellTrialShearHazard::phase() const { return phase_; }
int HellTrialShearHazard::cycle() const { return cycle_; }

double HellTrialShearHazard::phase_remaining_seconds() const {
    const double duration = phase_ == HellTrialHazardPhase::Warning ? 2.5 :
        (phase_ == HellTrialHazardPhase::Active ? 1.8 : 3.7);
    return std::max(0.0, duration - elapsed_seconds_);
}

HellTrialHazardTransition HellTrialShearHazard::update(double delta_seconds) {
    HellTrialHazardTransition result{false, phase_, cycle_, phase_remaining_seconds()};
    if (!enabled_ || !std::isfinite(delta_seconds) || delta_seconds <= 0.0) return result;
    double remaining = std::min(delta_seconds, 10.0);
    while (remaining > 0.0) {
        const double duration = phase_ == HellTrialHazardPhase::Warning ? 2.5 :
            (phase_ == HellTrialHazardPhase::Active ? 1.8 : 3.7);
        const double step = std::min(remaining, duration - elapsed_seconds_);
        elapsed_seconds_ += step;
        remaining -= step;
        if (elapsed_seconds_ + 1e-9 < duration) break;
        elapsed_seconds_ = 0.0;
        if (phase_ == HellTrialHazardPhase::Warning) {
            phase_ = HellTrialHazardPhase::Active;
        } else if (phase_ == HellTrialHazardPhase::Active) {
            phase_ = HellTrialHazardPhase::Recovery;
        } else {
            phase_ = HellTrialHazardPhase::Warning;
            ++cycle_;
        }
        result.changed = true;
    }
    result.phase = phase_;
    result.cycle = cycle_;
    result.phase_remaining_seconds = phase_remaining_seconds();
    return result;
}

bool HellTrialShearHazard::is_inside_danger_zone(float x, float z) const {
    if (!enabled_ || !std::isfinite(x) || !std::isfinite(z)) return false;
    return x >= -9.0F && x <= 9.0F && z >= -9.0F && z <= 5.0F;
}

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

bool HellTrialEncounter::restore_stage(int stage) {
    if (!enabled() || stage < 0 || stage > 4) return false;
    objective_kills_ = std::min(stage, spec_->objective_required);
    guardian_defeated_ = stage == 4;
    completed_ = stage == 4;
    return true;
}

void HellTrialEncounter::clamp_player_position(float& x, float& z) const {
    if (!spec_) return;
    constexpr float kArenaHalfExtent = 27.0F;
    x = std::clamp(x, -kArenaHalfExtent, kArenaHalfExtent);
    z = std::clamp(z, -kArenaHalfExtent, kArenaHalfExtent);
}

HellTrialDeathResult HellTrialEncounter::record_monster_death(
    std::string_view life_id, std::string_view definition_id) {
    HellTrialDeathResult result;
    if (!spec_ || life_id.empty() || definition_id.empty() || completed_) {
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
            const auto [_, inserted] = counted_life_ids_.emplace(life_id);
            if (inserted && objective_kills_ < spec_->objective_required) {
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

const std::array<HellTrialEvidenceSpec, 3> kFirstFloorEvidence{{
    {"registry_seal", "罪簿封蜡", "西侧卷宗案台", "封蜡边缘有新裂痕，蜡面仍残留未干的朱砂。值守簿记载：三更前封存的卷宗不应出现这道新裂口。",
     {"before_third_bell", "after_third_bell", "never_resealed"},
     {"三更前已封存", "三更后有人重新封卷", "从未重新封卷"},
     "after_third_bell", -10.0F, -3.0F},
    {"echo_stone", "回声石", "北侧回声石柱", "石中残响记录了脚步方向：先有急促脚步穿过西廊，随后才传来封门铜铃声。",
     {"west_corridor", "east_corridor", "north_archive"},
     {"从西廊进入", "从东廊进入", "从北侧档房进入"},
     "west_corridor", 0.0F, -10.0F},
    {"soul_lantern", "魂灯残灰", "东侧魂灯台", "灯盏内侧留有逆风卷灰，灯芯是在有人靠近时被从内侧吹灭，并非门外阴风所致。",
     {"outside_wind", "after_replacement", "before_sealing"},
     {"被门外阴风吹灭", "有人进廊后吹灭魂灯", "封卷前便已熄灭"},
     "after_replacement", 10.0F, -3.0F}
}};

} // namespace

const std::array<HellTrialEvidenceSpec, 3>& hell_trial_evidence_specs() {
    return kFirstFloorEvidence;
}

HellTrialInvestigation::HellTrialInvestigation(int floor) : enabled_(floor == 1) {}
bool HellTrialInvestigation::enabled() const { return enabled_; }
bool HellTrialInvestigation::completed() const { return enabled_ && solved_evidence_ids_.size() == kFirstFloorEvidence.size(); }
int HellTrialInvestigation::solved_count() const { return static_cast<int>(solved_evidence_ids_.size()); }
bool HellTrialInvestigation::is_solved(std::string_view evidence_id) const {
    return solved_evidence_ids_.contains(std::string(evidence_id));
}

HellTrialEvidenceResult HellTrialInvestigation::submit(
    std::string_view evidence_id, std::string_view option_id) {
    HellTrialEvidenceResult result;
    result.required = enabled_ ? static_cast<int>(kFirstFloorEvidence.size()) : 0;
    result.solved_count = solved_count();
    result.completed = completed();
    result.evidence_id = std::string(evidence_id);
    if (!enabled_) {
        result.message = "当前楼层没有开放证词调查。";
        return result;
    }
    const auto found = std::find_if(kFirstFloorEvidence.begin(), kFirstFloorEvidence.end(),
        [&](const HellTrialEvidenceSpec& spec) { return spec.id == evidence_id; });
    if (found == kFirstFloorEvidence.end()) {
        result.message = "未找到这份证词线索。";
        return result;
    }
    if (is_solved(evidence_id)) {
        result.accepted = true;
        result.already_solved = true;
        result.message = "这份证词已经核验，无需重复提交。";
        return result;
    }
    if (found->correct_option_id != option_id) {
        result.message = "证词与现场痕迹不符，再检查线索。";
        return result;
    }
    solved_evidence_ids_.emplace(evidence_id);
    result.accepted = true;
    result.newly_solved = true;
    result.solved_count = solved_count();
    result.completed = completed();
    result.message = result.completed
        ? "三份证词相互印证：有人在三更后从西廊进入并替换罪簿，拔舌判官的伪证已被揭穿。"
        : "证词核验成功。继续寻找另外的线索。";
    return result;
}
