#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#endif

#include "enet_client.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <enet/enet.h>

namespace honghuang {

EnetClient::~EnetClient() {
    close_transport();
}

void EnetClient::_bind_methods() {
    using namespace godot;
    ClassDB::bind_method(D_METHOD("connect_to_host", "host", "port"), &EnetClient::connect_to_host);
    ClassDB::bind_method(D_METHOD("send_frame", "frame", "reliable"), &EnetClient::send_frame, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("disconnect_from_host"), &EnetClient::disconnect_from_host);
    ClassDB::bind_method(D_METHOD("is_connected_to_server"), &EnetClient::is_connected_to_server);

    ADD_SIGNAL(MethodInfo("connected"));
    ADD_SIGNAL(MethodInfo("connection_failed"));
    ADD_SIGNAL(MethodInfo("disconnected"));
    ADD_SIGNAL(MethodInfo("frame_received", PropertyInfo(Variant::PACKED_BYTE_ARRAY, "frame")));
}

godot::Error EnetClient::connect_to_host(const godot::String& host, int port) {
    if (port < 1 || port > 65535 || host.is_empty()) {
        return godot::ERR_INVALID_PARAMETER;
    }
    close_transport();
    if (enet_initialize() != 0) {
        return godot::FAILED;
    }
    initialized_enet_ = true;

    host_ = enet_host_create(nullptr, 1, 2, 0, 0);
    if (host_ == nullptr) {
        close_transport();
        return godot::ERR_CANT_CREATE;
    }

    const godot::CharString host_utf8 = host.utf8();
    ENetAddress address{};
    address.port = static_cast<enet_uint16>(port);
    if (enet_address_set_host(&address, host_utf8.get_data()) != 0) {
        close_transport();
        return godot::ERR_CANT_RESOLVE;
    }

    peer_ = enet_host_connect(host_, &address, 2, 0);
    if (peer_ == nullptr) {
        close_transport();
        return godot::ERR_CANT_CONNECT;
    }
    connected_ = false;
    set_process(true);
    return godot::OK;
}

godot::Error EnetClient::send_frame(const godot::PackedByteArray& frame, bool reliable) {
    if (!connected_ || peer_ == nullptr || frame.is_empty()) {
        return godot::ERR_UNCONFIGURED;
    }
    const enet_uint32 flags = reliable ? ENET_PACKET_FLAG_RELIABLE : 0;
    const enet_uint8 channel = reliable ? 0 : 1;
    ENetPacket* packet = enet_packet_create(frame.ptr(), static_cast<std::size_t>(frame.size()), flags);
    if (packet == nullptr) {
        return godot::ERR_OUT_OF_MEMORY;
    }
    if (enet_peer_send(peer_, channel, packet) != 0) {
        enet_packet_destroy(packet);
        return godot::FAILED;
    }
    enet_host_flush(host_);
    return godot::OK;
}

void EnetClient::disconnect_from_host() {
    if (peer_ != nullptr) {
        enet_peer_disconnect(peer_, 0);
        enet_host_flush(host_);
    }
}

bool EnetClient::is_connected_to_server() const {
    return connected_;
}

void EnetClient::_process(double) {
    if (host_ == nullptr) {
        set_process(false);
        return;
    }

    ENetEvent event{};
    while (enet_host_service(host_, &event, 0) > 0) {
        switch (event.type) {
            case ENET_EVENT_TYPE_CONNECT:
                connected_ = true;
                emit_signal("connected");
                break;
            case ENET_EVENT_TYPE_RECEIVE: {
                godot::PackedByteArray bytes;
                bytes.resize(static_cast<int64_t>(event.packet->dataLength));
                for (std::size_t i = 0; i < event.packet->dataLength; ++i) {
                    bytes.set(static_cast<int64_t>(i), event.packet->data[i]);
                }
                emit_signal("frame_received", bytes);
                enet_packet_destroy(event.packet);
                break;
            }
            case ENET_EVENT_TYPE_DISCONNECT: {
                const bool was_connected = connected_;
                connected_ = false;
                peer_ = nullptr;
                if (was_connected) {
                    emit_signal("disconnected");
                } else {
                    emit_signal("connection_failed");
                }
                break;
            }
            case ENET_EVENT_TYPE_NONE:
                break;
        }
    }
}

void EnetClient::close_transport() {
    connected_ = false;
    if (peer_ != nullptr) {
        enet_peer_reset(peer_);
        peer_ = nullptr;
    }
    if (host_ != nullptr) {
        enet_host_destroy(host_);
        host_ = nullptr;
    }
    if (initialized_enet_) {
        enet_deinitialize();
        initialized_enet_ = false;
    }
    set_process(false);
}

} // namespace honghuang
