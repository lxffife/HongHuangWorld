#include "protocol/frame.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

int main() {
    using namespace honghuang::protocol;

    const std::vector<std::uint8_t> heartbeat_payload{};
    const auto encoded = encode_frame(MessageType::Heartbeat, heartbeat_payload);
    Frame decoded{};
    std::string error;
    assert(decode_frame(encoded, decoded, error));
    assert(decoded.version == kVersion);
    assert(decoded.type == MessageType::Heartbeat);
    assert(decoded.payload.empty());

    const std::vector<std::uint8_t> hello_payload{
        0x00, 0x03, 'a', 'b', 'c',
        0x00, 0x04, 't', 'e', 's', 't'
    };
    ClientHello hello{};
    assert(decode_client_hello(hello_payload, hello, error));
    assert(hello.ticket == "abc");
    assert(hello.client_build == "test");

    const std::vector<std::uint8_t> chat_payload{'{', '"', 'c', 'h', 'a', 'n', 'n', 'e', 'l', '"', ':', '"', 'n', 'e', 'a', 'r', 'b', 'y', '"', '}'};
    for (const auto chat_type : {MessageType::ChatSendCommand, MessageType::ChatEvent}) {
        const auto chat_frame = encode_frame(chat_type, chat_payload);
        Frame chat_decoded{};
        assert(decode_frame(chat_frame, chat_decoded, error));
        assert(chat_decoded.type == chat_type);
        assert(chat_decoded.payload == chat_payload);
    }

    const std::vector<std::uint8_t> action_payload{'{', '}'};
    const auto action_frame = encode_frame(MessageType::MonsterActionEvent, action_payload);
    Frame action_decoded{};
    assert(decode_frame(action_frame, action_decoded, error));
    assert(action_decoded.type == MessageType::MonsterActionEvent);
    assert(action_decoded.payload == action_payload);

    const std::vector<std::uint8_t> lifecycle_payload{'{', '}'};
    for (const auto event_type : {MessageType::PlayerJoined, MessageType::PlayerLeft}) {
        const auto event_frame = encode_frame(event_type, lifecycle_payload);
        Frame event_decoded{};
        assert(decode_frame(event_frame, event_decoded, error));
        assert(event_decoded.type == event_type);
        assert(event_decoded.payload == lifecycle_payload);
    }

    auto truncated = encoded;
    truncated.pop_back();
    assert(!decode_frame(truncated, decoded, error));

    auto invalid_magic = encoded;
    invalid_magic[0] = 0;
    assert(!decode_frame(invalid_magic, decoded, error));
    return 0;
}
