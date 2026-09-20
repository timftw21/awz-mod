#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "solo.hpp"
#include "command.hpp"
#include "console.hpp"
#include "party.hpp"
#include "scheduler.hpp"
#include "gsc/script_extension.hpp"

namespace solo
{
	namespace
	{
		std::atomic_bool enabled{false};
		bool starting{};
		bool reported{};
		unsigned int generation{};
		std::string last_map;
		game::BuiltinFunction original_iprintln{};
		std::vector<std::pair<std::string, std::string>> saved_dvars;

		// These settings belong to this session, never to the player's saved config.
		const std::pair<const char*, const char*> settings[] = {
			{"onlinegame", "0"}, {"systemlink", "0"}, {"splitscreen", "0"},
			{"xblive_privatematch", "1"}, {"party_maxplayers", "1"},
			{"sv_maxclients", "1"}, {"ui_gametype", "zombies"}, {"g_gametype", "zombies"}
		};

		void iprintln_stub()
		{
			// _playerlogic::callback_playerconnect prints this localized token first.
			// Preserve the original builtin (and its argument/error handling) for every other message.
			const auto* vm = game::scr_VmPub.get();
			if (active() && vm->outparamcount && vm->top->type == game::VAR_ISTRING &&
				std::strcmp(game::SL_ConvertToString(static_cast<game::scr_string_t>(vm->top->u.stringValue)), "MP_CONNECTED") == 0)
			{
				console::info("[Solo] Suppressed local player connection announcement\n");
				return;
			}
			original_iprintln();
		}
	}

	bool active()
	{
		return enabled.load();
	}

	bool map_available(const std::string& map)
	{
		return (map == "mp_zombie_lab" || map == "mp_zombie_brg" ||
			map == "mp_zombie_ark" || map == "mp_zombie_h2o") && game::SV_MapExists(map.c_str());
	}

	bool begin()
	{
		if (active()) return true;
		if (game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES ||
			(game::CL_IsCgameInitialized() && !game::VirtualLobby_Loaded())) return false;

		saved_dvars.clear();
		for (const auto& [name, value] : settings)
		{
			auto* dvar = game::Dvar_FindVar(name);
			if (!dvar)
			{
				console::error("[Solo] Cannot enter: missing dvar %s\n", name);
				saved_dvars.clear();
				return false;
			}
			saved_dvars.emplace_back(name, game::Dvar_ValueToString(dvar, dvar->latched));
		}

		// Leave any existing party before closing the network boundary. Do not create a new one.
		command::execute("xstopparty", true);
		command::execute("xstopprivateparty", true);
		party::reset_connect_state();
		enabled = true;
		starting = reported = false;
		++generation;
		for (const auto& [name, value] : settings)
		{
			game::Dvar_SetFromStringByNameFromSource(name, value, game::DVAR_SOURCE_INTERNAL);
		}
		console::info("[Solo] Session entered: offline, one player, no party; external game packets disabled\n");
		return true;
	}

	void leave()
	{
		if (!active()) return;
		// Called by the frontend, never by CL_Disconnect (which also runs during map loading).
		for (const auto& [name, value] : saved_dvars)
		{
			game::Dvar_SetFromStringByNameFromSource(name.c_str(), value.c_str(), game::DVAR_SOURCE_INTERNAL);
		}
		saved_dvars.clear();
		starting = reported = false;
		last_map.clear();
		++generation;
		enabled = false;
		console::info("[Solo] Session left; previous multiplayer settings restored\n");
	}

	void lobby_ready()
	{
		// Only called when a fresh frontend VM loads, not when closing an intro or submenu.
		if (!active() || !starting) return;
		starting = reported = false;
		++generation;
		for (const auto& [name, value] : settings)
		{
			game::Dvar_SetFromStringByNameFromSource(name, value, game::DVAR_SOURCE_INTERNAL);
		}
		game::Dvar_SetFromStringByNameFromSource("ui_mapname", last_map.c_str(), game::DVAR_SOURCE_INTERNAL);
		console::info("[Solo] Returned to pre-game lobby; retained map=%s and offline session\n", last_map.c_str());
	}

	bool start(const std::string& map)
	{
		if (!active() || starting || !map_available(map))
		{
			console::error("[Solo] Map start rejected: %s (active=%d, starting=%d)\n", map.c_str(), active(), starting);
			return false;
		}
		starting = true;
		last_map = map;
		const auto request_generation = generation;
		// Let the movie callback return before map loading destroys its Lua VM.
		scheduler::once([map, request_generation]
		{
			if (!active() || request_generation != generation) return;
			game::Dvar_SetFromStringByNameFromSource("ui_mapname", map.c_str(), game::DVAR_SOURCE_INTERNAL);
			console::info("[Solo] Starting %s through local server startup; no xpartygo or online-data wait\n", map.c_str());
			// RE: this entry only sets sv_migrate=false, then enters SV_StartMap.
			game::SV_StartMapForParty(0, map.c_str(), false, false);
		}, scheduler::pipeline::main);
		return true;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::is_mp()) return;
			// Lua's typed getters return nil for unregistered dvars. Create the
			// selection before the frontend loads; GSC reads the same value at map start.
			game::Dvar_RegisterInt("ui_awz_solo_character", 0, 0, 3, game::DVAR_FLAG_NONE);
			game::Dvar_RegisterInt("ui_awz_classic", 0, 0, 1, game::DVAR_FLAG_NONE);
			console::info("[Solo] Mode selection registered: 0=Standard (default), 1=Classic\n");
			console::info("[Solo] Character selection registered: default=0, range=0-3\n");
			gsc::override_function("iprintln", &iprintln_stub, &original_iprintln);
			scheduler::loop([]
			{
				if (active() && starting && !reported && game::CL_IsCgameInitialized() && !game::VirtualLobby_Loaded())
				{
					reported = true;
					console::info("[Solo] Gameplay active: onlinegame=%d, systemlink=%d, sv_maxclients=%d, clients=%d\n",
						game::Dvar_FindVar("onlinegame")->current.enabled,
						game::Dvar_FindVar("systemlink")->current.enabled,
						game::Dvar_FindVar("sv_maxclients")->current.integer, party::get_client_count());
				}
			}, scheduler::pipeline::main, 1s);
		}
	};
}

REGISTER_COMPONENT(solo::component)
