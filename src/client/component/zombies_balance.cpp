#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "gsc/script_extension.hpp"
#include "console.hpp"
#include "solo.hpp"
#include <utils/hook.hpp>

namespace zombies_balance
{
	namespace
	{
		// Upgrade camos identify the weapon's level on both server and client.
		std::array<std::atomic<float>, 128> ammo_scales{};
		utils::hook::detour get_max_ammo_hook;
		utils::hook::detour format_hint_hook;
		std::atomic_bool hint_trim_reported{false};
		std::atomic_bool melee_release_reported{false};
		utils::hook::detour melee_return_time_hook;
		utils::hook::detour weapon_animation_rate_hook;
		std::atomic_uint melee_return_reported{0};

		int fast_knife_pistol(const std::byte* state)
		{
			if (!state || game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES ||
				(*reinterpret_cast<const unsigned int*>(state + 0x318) & 1)) return -1; // Exo punch, not knife.
			const auto weapon = *reinterpret_cast<const unsigned int*>(state + 0x5C4);
			const auto* definition = reinterpret_cast<game::WeaponCompleteDef**>(0x141469110)[weapon & 0x3FF];
			if (!definition || !definition->szInternalName) return -1;
			if (!std::strcmp(definition->szInternalName, "iw5_titan45zm_mp")) return 0;
			if (!std::strcmp(definition->szInternalName, "iw5_dlcgun13_mp")) return 1;
			return -1;
		}

		void log_knife_return(const std::byte* state, const int pistol, const bool animation, const float before, const float after)
		{
			const auto dual = *reinterpret_cast<const int*>(state + 0x5E8) == 1;
			const auto bit = 1u << (pistol + (dual ? 2 : 0) + (animation ? 4 : 0));
			if (!(melee_return_reported.fetch_or(bit) & bit))
				console::info("[Zombies Balance] Knife return: weapon=%s dual=%d %s=%.3f -> %.3f\n",
					pistol ? "1911" : "Atlas 45", dual, animation ? "animation rate" : "recovery ms", before, after);
		}

		int melee_return_time_stub(const std::byte* state, const int hand)
		{
			const auto stock = melee_return_time_hook.invoke<int>(state, hand);
			const auto pistol = fast_knife_pistol(state);
			if (pistol < 0 || stock <= 0) return stock;
			const auto reduced = (stock + 1) / 2;
			log_knife_return(state, pistol, false, static_cast<float>(stock), static_cast<float>(reduced));
			return reduced;
		}

		float weapon_animation_rate_stub(const std::byte* state, const unsigned int weapon, const int hand,
			const void* animations, const unsigned int animation)
		{
			const auto stock = weapon_animation_rate_hook.invoke<float>(state, weapon, hand, animations, animation);
			// QUICK_RAISE (43) is reused by normal switches. Only accelerate the
			// knife return, whose player-state phase is WEAPON_MELEE_END (17).
			if (!state || animation != 43 || hand < 0 || hand > 1 ||
				*reinterpret_cast<const int*>(state + 0x374 + hand * 0x1C) != 17) return stock;
			const auto pistol = fast_knife_pistol(state);
			if (pistol < 0) return stock;
			log_knife_return(state, pistol, true, stock, stock * 2);
			return stock * 2;
		}

		bool melee_recovery_complete(const std::byte* movement)
		{
			if (game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES) return false;
			const auto* state = *reinterpret_cast<const std::byte* const*>(movement);
			const auto flags = *reinterpret_cast<const unsigned int*>(state + 0x54);
			const auto target = *reinterpret_cast<const std::int16_t*>(state + 0x2A);
			if (!(flags & 0x10000) || target < 0 || target >= 2047) return false;

			// Use the same animation/notetrack query as standing melee. The last
			// argument selects server or predicted-client animation data.
			const auto server = *reinterpret_cast<const bool*>(movement + 0x18C);
			if (utils::hook::invoke<int>(0x14013C610, state, server)) return false;
			if (!melee_release_reported.exchange(true))
			{
				console::info("[Zombies Balance] Melee movement released at stock animation recovery while crouched/prone; weapon timer=%dms\n",
					*reinterpret_cast<const int*>(state + 0x368));
			}
			return true;
		}

		const auto melee_stance_recovery_stub = utils::hook::assemble([](utils::hook::assembler& a)
		{
			const auto crouched = a.newLabel();
			const auto recovering = a.newLabel();
			// PM_UpdateMeleeCharge branches on stance before checking whether
			// the animation has released movement. Check recovery on the other
			// stance path too, then reuse its existing velocity/charge cleanup.
			a.mov(rcx, rbx);
			a.call(0x140144EF0); // Original effective-stance query.
			a.xor_(edi, edi);
			a.test(eax, eax);
			a.jnz(crouched);
			a.jmp(0x140147385); // Original standing path.
			a.bind(crouched);
			a.mov(rcx, rsi); // pmove_t; nonvolatile registers hold all live state.
			a.call(&melee_recovery_complete);
			a.test(al, al);
			a.jz(recovering);
			a.jmp(0x1401473CF); // Original animation-release cleanup.
			a.bind(recovering);
			a.jmp(0x1401473EB); // Original crouched/prone charge handling.
		});

		bool strip_hint_period(char* text)
		{
			if (!text) return false;
			const auto length = std::strlen(text);
			auto end = length;
			// Keep trailing color resets and whitespace; inspect the visible ending.
			while (end)
			{
				const auto c = text[end - 1];
				if (c == ' ' || c == '\t' || c == '\r' || c == '\n') --end;
				else if (end >= 2 && text[end - 2] == '^' && c >= '0' && c <= '9') end -= 2;
				else break;
			}
			auto start = end;
			while (start && text[start - 1] == '.') --start;
			if (start == end) return false;
			std::memmove(text + start, text + end, length - end + 1);
			return true;
		}

		void format_hint_stub(const int local_client, const int hint_index, char* output)
		{
			format_hint_hook.invoke<void>(local_client, hint_index, output);
			if (game::Com_GetCurrentCoDPlayMode() == game::CODPLAYMODE_ZOMBIES && strip_hint_period(output) &&
				!hint_trim_reported.exchange(true))
			{
				console::info("[Zombies Balance] Removed terminal hint punctuation; stock localization, bindings and colors preserved\n");
			}
		}

		void set_gold_upgrade_camo()
		{
			auto* table = game::DB_FindXAssetHeader(game::ASSET_TYPE_STRINGTABLE, "mp/zmWeaponLevels.csv", false).stringTable;
			if (!table || table->columnCount != 4 || table->rowCount != 26)
			{
				gsc::scr_error("Unexpected Zombies weapon-level table");
				return;
			}
			auto& mark10 = table->values[10 * table->columnCount + 1];
			auto& mark19 = table->values[19 * table->columnCount + 1];
			// mp/camotable.csv identifies camo 15 by MPUI_GOLD and camo_gold_02_col.
			// Swap complete cells (including lookup hashes), so both the native
			// display name and GSC use Mk 10 for gold. Repeated map init is safe.
			if (std::strcmp(mark10.string, "25") == 0 && std::strcmp(mark19.string, "15") == 0)
			{
				std::swap(mark10, mark19);
			}
			if (std::strcmp(mark10.string, "15") != 0 || std::strcmp(mark19.string, "25") != 0)
			{
				gsc::scr_error("Unexpected Zombies upgrade camo mapping");
				return;
			}
			console::info("[Zombies Balance] Mk 10 mapped to gold camo 15; native label remains Mk 10\n");
		}

		void localized_number()
		{
			const auto* key = game::Scr_GetString(0);
			const std::string number = game::Scr_GetString(1);
			const std::string replacement = game::Scr_GetString(2);
			const auto entry = game::DB_FindXAssetHeader(game::ASSET_TYPE_LOCALIZE_ENTRY, key, false);
			if (!entry.data || number.empty())
			{
				gsc::scr_error("Missing stock Zombies localization");
				return;
			}
			// LocalizeEntry's first field is its translated text. Read the asset
			// directly: script hints do not consistently use the UI localization hook.
			std::string text = *static_cast<const char* const*>(entry.data);
			const auto position = text.find(number);
			if (position == std::string::npos)
			{
				gsc::scr_error("Number missing from stock Zombies localization");
				return;
			}
			text.replace(position, number.size(), replacement);
			game::Scr_AddString(text.c_str());
		}

		int get_max_ammo_stub(const void* player_state, const unsigned int weapon, const bool alternate)
		{
			const auto stock = get_max_ammo_hook.invoke<int>(player_state, weapon, alternate);
			if (game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES) return stock;
			// BG_GetWeaponNameComplete extracts camo from bits 11..17 (MP 0x1401656AE).
			const auto scale = ammo_scales[(weapon >> 11) & 0x7F].load(std::memory_order_relaxed);
			return scale > 1.0f ? static_cast<int>(stock * scale) : stock;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::is_mp()) return;
			utils::hook::nop(0x140147377, 14);
			utils::hook::jump(0x140147377, melee_stance_recovery_stub, true);
			console::info("[Zombies Balance] Installed animation-based melee movement recovery for all stances in Zombies\n");
			// PM's knife-return timer caps quickRaiseTime at 350 ms. Halve its
			// result, not the shared weapon asset, and match the client clip rate.
			melee_return_time_hook.create(0x1401540B0, &melee_return_time_stub);
			weapon_animation_rate_hook.create(0x1401F06D0, &weapon_animation_rate_stub);
			console::info("[Zombies Balance] Atlas 45/1911 knife return: 50%% recovery time; 2x return-animation speed\n");
			// Shared reserve capacity query, used by pickups, refill scripts and ammo limits.
			get_max_ammo_hook.create(0x14016EA60, &get_max_ammo_stub);
			// Client hint formatter: config string 0x11E + index, localization,
			// use-key substitution, then binding/icon conversion into the caller's buffer.
			format_hint_hook.create(0x1401AE870, &format_hint_stub);
			gsc::add_function("awz_issolo", [] { game::Scr_AddInt(solo::active()); });
			gsc::add_function("awz_localizednumber", &localized_number);
			gsc::add_function("awz_resetammoscales", []
			{
				set_gold_upgrade_camo();
				hint_trim_reported = false;
				melee_release_reported = false;
				melee_return_reported = 0;
				for (auto& scale : ammo_scales) scale.store(1.0f, std::memory_order_relaxed);
				console::info("[Zombies Balance] Reset upgrade ammo capacities for new match\n");
			});
			gsc::add_function("awz_setammoscale", []
			{
				const auto camo = game::Scr_GetInt(0);
				const auto scale = game::Scr_GetFloat(1);
				if (camo <= 0 || camo >= static_cast<int>(ammo_scales.size()) || !std::isfinite(scale) || scale < 1.0f || scale > 3.0f)
				{
					gsc::scr_error("Invalid Zombies upgrade ammo scale");
					return;
				}
				ammo_scales[camo].store(scale, std::memory_order_relaxed);
				console::info("[Zombies Balance] Upgrade camo=%d reserve ammo=%.3fx\n", camo, scale);
			});
		}
	};
}

REGISTER_COMPONENT(zombies_balance::component)
