extends Node

var world_network: HHWorldNetwork
var world_snapshot: Dictionary = {}
var api_base: String = "http://127.0.0.1:8787"
var access_token: String = ""

func get_chat_api_base() -> String:
	var configured := OS.get_environment("CHAT_API_BASE").strip_edges()
	if not configured.is_empty():
		return configured.trim_suffix("/")
	var game_base := api_base.strip_edges().trim_suffix("/")
	if game_base.ends_with(":8787"):
		return game_base.trim_suffix(":8787") + ":8788"
	return game_base
