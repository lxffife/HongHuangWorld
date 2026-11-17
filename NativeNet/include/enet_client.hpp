#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

struct _ENetHost;
struct _ENetPeer;

namespace honghuang {

class EnetClient final : public godot::Node {
    GDCLASS(EnetClient, godot::Node)

public:
    EnetClient() = default;
    ~EnetClient() override;

    godot::Error connect_to_host(const godot::String& host, int port);
    godot::Error send_frame(const godot::PackedByteArray& frame, bool reliable = true);
    void disconnect_from_host();
    bool is_connected_to_server() const;

protected:
    static void _bind_methods();
    void _process(double delta) override;

private:
    _ENetHost* host_{nullptr};
    _ENetPeer* peer_{nullptr};
    bool initialized_enet_{false};
    bool connected_{false};

    void close_transport();
};

} // namespace honghuang
