#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace honghuang::protocol {

inline constexpr std::uint32_t kMagic = 0x48485731U; // HHW1
inline constexpr std::uint16_t kVersion = 1;
inline constexpr std::size_t kHeaderSize = 12;
inline constexpr std::size_t kMaxPayloadSize = 64U * 1024U;

enum class MessageType : std::uint16_t {
    ClientHello = 1,
    ServerWelcome = 2,
    ServerReject = 3,
    Heartbeat = 4,
    HeartbeatAck = 5,
    InputCommand = 10,
    EntitySnapshot = 11,
    PlayerJoined = 12,
    PlayerLeft = 13,
    AttackCommand = 14,
    CombatEvent = 15,
    PickupCommand = 16,
    PickupEvent = 17,
    ChatSendCommand = 18,
    ChatEvent = 19,
    MonsterActionEvent = 20,
    PlayerActionEvent = 21,
    SpellCastCommand = 22,
};

struct Frame {
    std::uint16_t version{};
    MessageType type{};
    std::vector<std::uint8_t> payload;
};

struct ClientHello {
    std::string ticket;
    std::string client_build;
};

bool decode_frame(std::span<const std::uint8_t> bytes, Frame& out, std::string& error);
std::vector<std::uint8_t> encode_frame(MessageType type, std::span<const std::uint8_t> payload);
bool decode_client_hello(std::span<const std::uint8_t> payload, ClientHello& out, std::string& error);

} // namespace honghuang::protocol
