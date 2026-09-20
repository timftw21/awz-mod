#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"

#include "component/console.hpp"
#include "component/solo.hpp"

#include <utils/hook.hpp>

namespace weapons
{
	namespace
	{
		// DB_BuildLevelLoadPlan (0x14026E7C0). The progress tracker and all three
		// DB_LoadXAssets batches consume this same plan.
		struct level_load_plan
		{
			game::XZoneInfo zones[24];
			std::uint64_t estimated_bytes[24];
			char names[24][64];
			unsigned int count;
			unsigned int batch_counts[3];
			unsigned int current_batch;
			unsigned int padding;
		};
		static_assert(offsetof(level_load_plan, estimated_bytes) == 0x180);
		static_assert(offsetof(level_load_plan, count) == 0x840);
		static_assert(sizeof(level_load_plan) == 0x858);

		// Prefix of S1's WeaponAttachment asset; weaponType is at 0x14.
		struct attachment_header
		{
			const char* name;
			const char* display_name;
			int type;
			int weapon_type;
		};
		static_assert(offsetof(attachment_header, weapon_type) == 0x14);

		bool is_classic()
		{
			if (!solo::active() || game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES) return false;
			const auto* classic = game::Dvar_FindVar("ui_awz_classic");
			return classic && classic->current.integer == 1;
		}

		void build_level_load_plan_stub(level_load_plan* plan, const char* map)
		{
			utils::hook::invoke<void>(0x14026E7C0, plan, map);
			if (!is_classic()) return;

			const game::XZoneInfo* map_zone = nullptr;
			for (unsigned int i = 0; i < plan->count; ++i)
			{
				const auto& zone = plan->zones[i];
				if (!zone.name) continue;
				if (!std::strcmp(zone.name, "awz_classic_1911")) return;
				if (zone.allocFlags && !std::strcmp(zone.name, map) &&
					(!std::strcmp(map, "mp_zombie_lab") || !std::strcmp(map, "mp_zombie_brg") ||
					 !std::strcmp(map, "mp_zombie_ark") || !std::strcmp(map, "mp_zombie_h2o"))) map_zone = &zone;
			}
			if (!map_zone) return;
			if (plan->count >= std::size(plan->zones))
			{
				game::Com_Error(game::ERR_DROP, "Classic 1911 exceeds map load plan capacity");
				return;
			}

			char path[MAX_PATH]{};
			game::Sys_BuildAbsPath(path, sizeof(path), game::SF_ZONE, "awz_classic_1911", ".ff");
			std::error_code error;
			const auto bytes = std::filesystem::file_size(path, error);
			if (error || !bytes)
			{
				game::Com_Error(game::ERR_DROP, "Classic 1911 asset package is missing or empty");
				return;
			}
			// Add it before LoadBar_Init, not at DB_LoadXAssets: an unplanned file
			// makes LoadBar_BeginFastFile abandon its remaining progress steps.
			const auto index = plan->count++;
			plan->zones[index] = {"awz_classic_1911", map_zone->allocFlags | game::DB_ZONE_CUSTOM, 0};
			plan->estimated_bytes[index] = bytes;
			++plan->batch_counts[2];
			console::info("[Classic] Planned 1911 after %s: %llu bytes; zones=%u; batches=%u/%u/%u; progress includes weapon package\n",
				map, bytes, plan->count, plan->batch_counts[0], plan->batch_counts[1], plan->batch_counts[2]);
		}

		void g_setup_level_weapon_def_stub()
		{
			if (is_classic() && !game::VirtualLobby_Loaded())
			{
				const auto* weapon = static_cast<const std::byte*>(
					game::DB_FindXAssetHeader(game::ASSET_TYPE_WEAPON, "iw5_dlcgun13_mp", false).data);
				if (!weapon)
				{
					game::Com_Error(game::ERR_DROP, "Classic 1911 asset package did not load");
					return;
				}
				const auto* explosive = static_cast<const attachment_header*>(
					game::DB_FindXAssetHeader(game::ASSET_TYPE_ATTACHMENT, "explosive1911", false).data);
				if (!explosive || explosive->weapon_type != 3)
				{
					game::Com_Error(game::ERR_DROP, "Classic 1911 explosive attachment is missing or invalid; update the weapon package");
					return;
				}
				console::info("[Classic] 1911 ready for weapon registration\n");
				console::info("[Classic] 1911 projectile attachment verified; upgrade registration left to normal gameplay\n");
				// S1 WeaponDef's native projectile damage fields (also used by grenades).
				console::info("[Classic] 1911 projectile blast: radius=%d inner=%d outer=%d cone=%.1f degrees\n",
					*reinterpret_cast<const int*>(weapon + 0xA60),
					*reinterpret_cast<const int*>(weapon + 0xA68),
					*reinterpret_cast<const int*>(weapon + 0xA6C),
					*reinterpret_cast<const float*>(weapon + 0xA70));
			}
			game::G_SetupLevelWeaponDef();

			// The count on this game seems pretty high
			std::array<game::WeaponCompleteDef*, 2048> weapons{};
			const auto count = game::DB_GetAllXAssetOfType_FastFile(game::ASSET_TYPE_WEAPON, (void**)weapons.data(), static_cast<int>(weapons.max_size()));

			std::sort(weapons.begin(), weapons.begin() + count, [](game::WeaponCompleteDef* weapon1, game::WeaponCompleteDef* weapon2)
			{
				assert(weapon1->szInternalName);
				assert(weapon2->szInternalName);

				return std::strcmp(weapon1->szInternalName, weapon2->szInternalName) < 0;
			});

#ifdef _DEBUG
			console::info("Found %i weapons to precache\n", count);
#endif

			// Do not resolve attachment variants here. G_GetWeaponForName can
			// allocate a shared custom-weapon index before the server publishes
			// its configstrings, shifting the client's expected indices.
			for (auto i = 0; i < count; ++i)
			{
#ifdef _DEBUG
				console::info("Precaching weapon \"%s\"\n", weapons[i]->szInternalName);
#endif
				(void)game::G_GetWeaponForName(weapons[i]->szInternalName);
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_sp()) return;
			utils::hook::call(0x140270DC4, build_level_load_plan_stub);

			// Kill Scr_PrecacheItem (We are going to do this from code)
			utils::hook::nop(0x1403101D0, 4);
			utils::hook::set<std::uint8_t>(0x1403101D0, 0xC3);

			// Load weapons from the DB
			utils::hook::call(0x1402F6EF4, g_setup_level_weapon_def_stub);
			utils::hook::call(0x140307401, g_setup_level_weapon_def_stub);
		}
	};
}

REGISTER_COMPONENT(weapons::component)
