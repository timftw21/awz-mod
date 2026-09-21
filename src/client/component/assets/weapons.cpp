#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"

#include "component/console.hpp"
#include "component/solo.hpp"
#include "component/gsc/script_extension.hpp"
#include "component/scheduler.hpp"
#include "component/scripting.hpp"
#include "weapons.hpp"

#include <utils/hook.hpp>

namespace weapons
{
	namespace
	{
		// The stock hand-throw definitions reuse the Exo launcher's model with
		// M67 animations. Those animations leave the launcher below the camera,
		// where it protrudes into view. Hide its bones through the weapon's own
		// hideTags; the hands and the actual Exo-launcher weapons stay intact.
		struct model_bones
		{
			const char* name;
			std::uint8_t count;
			std::byte padding[47];
			const game::scr_string_t* names;
		};
		static_assert(offsetof(model_bones, names) == 0x38);

		struct animation_timing
		{
			const char* name;
			std::uint16_t data_counts[3];
			std::uint16_t frame_count;
			std::uint8_t flags;
			std::byte unused[31];
			float frame_rate;
		};
		static_assert(offsetof(animation_timing, frame_count) == 0xE);
		static_assert(offsetof(animation_timing, flags) == 0x10);
		static_assert(offsetof(animation_timing, frame_rate) == 0x30);

		struct weapon_visuals
		{
			const char* name;
			std::byte names[16];
			model_bones** gun_models;
			std::byte unused[56];
			game::scr_string_t* hide_tags;
			void* attachments;
			animation_timing** animations;
		};
		static_assert(offsetof(weapon_visuals, gun_models) == 0x18);
		static_assert(offsetof(weapon_visuals, hide_tags) == 0x58);
		static_assert(offsetof(weapon_visuals, animations) == 0x68);

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

		constexpr unsigned int first_raise = 37;
		struct animation_entry
		{
			std::byte linkage[8];
			const animation_timing* parts;
		};
		struct animation_set
		{
			unsigned int size;
			std::byte unused[4];
			animation_entry entries[first_raise + 1];
		};
		struct animation_tree
		{
			const animation_set* anims;
			std::uint16_t children;
		};
		struct viewmodel
		{
			const animation_tree* tree;
		};
		static_assert(offsetof(animation_set, entries) + offsetof(animation_entry, parts) == 0x10);
		static_assert(sizeof(animation_entry) == 0x10);
		static_assert(offsetof(animation_tree, children) == 8);

		enum class flourish_state { idle, waiting, playing, finished, interrupted };
		std::mutex flourish_mutex;
		struct
		{
			flourish_state state = flourish_state::idle;
			const animation_timing* animation = nullptr;
			float progress = 0;
			std::chrono::steady_clock::time_point requested_at;
		} flourish;

		void begin_weapon_flourish()
		{
			const auto* name = game::Scr_GetString(0);
			const auto* weapon = static_cast<const weapon_visuals*>(
				game::DB_FindXAssetHeader(game::ASSET_TYPE_WEAPON, name, false).data);
			const auto* animation = weapon && weapon->animations ? weapon->animations[first_raise] : nullptr;
			if (game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES || !game::CL_IsCgameInitialized() ||
				!animation || !animation->frame_count || (animation->flags & 1) ||
				!std::isfinite(animation->frame_rate) || animation->frame_rate <= 0)
			{
				console::warn("[Zombies Perks] Skipping perk flourish: %s has no supported local one-shot playback\n", name);
				game::Scr_AddInt(0);
				return;
			}
			std::lock_guard lock(flourish_mutex);
			flourish = {flourish_state::waiting, animation, 0, std::chrono::steady_clock::now()};
			console::info("[Zombies Perks] Perk flourish armed: weapon=%s animation=%s; waiting for actual playback\n", name, animation->name);
			game::Scr_AddInt(1);
		}

		void weapon_flourish_status()
		{
			std::lock_guard lock(flourish_mutex);
			game::Scr_AddInt(flourish.state == flourish_state::finished ? 1 :
				(flourish.state == flourish_state::waiting || flourish.state == flourish_state::playing ? 0 : -1));
		}

		void end_weapon_flourish()
		{
			std::lock_guard lock(flourish_mutex);
			if (flourish.state == flourish_state::waiting || flourish.state == flourish_state::playing)
				console::info("[Zombies Perks] Perk flourish cancelled: progress=%.4f\n", flourish.progress);
			flourish = {};
		}

		void update_weapon_flourish()
		{
			// Only the main thread reads the client animation tree. GSC runs on the
			// server; it reads the latched result, so a one-frame end cannot be missed.
			std::lock_guard lock(flourish_mutex);
			if (flourish.state != flourish_state::waiting && flourish.state != flourish_state::playing) return;
			const auto* object = game::CL_IsCgameInitialized() ? *reinterpret_cast<viewmodel**>(0x1417A0360) : nullptr;
			const auto* tree = object ? object->tree : nullptr;
			if (!tree || !tree->anims || tree->anims->size <= first_raise ||
				tree->anims->entries[first_raise].parts != flourish.animation)
			{
				if (flourish.state == flourish_state::playing)
				{
					flourish.state = flourish_state::interrupted;
					console::info("[Zombies Perks] Perk flourish interrupted: viewmodel changed at progress=%.4f\n", flourish.progress);
				}
				return;
			}

			// XAnimGetInfoIndex / XAnimGetTime / XAnimHasFinished. The latter also
			// handles a completed node retiring when the weapon enters idle. Require
			// the raise node to have started first: a missing node alone is not a finish.
			const auto info = tree->children ? utils::hook::invoke<unsigned int>(0x1404E6390, tree, first_raise, tree->children) : 0;
			if (flourish.state == flourish_state::waiting)
			{
				if (!info) return;
				flourish.state = flourish_state::playing;
				const auto delay = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - flourish.requested_at).count();
				console::info("[Zombies Perks] Perk flourish playback started: animation=%s; start delay=%lldms\n", flourish.animation->name, delay);
			}
			if (info) flourish.progress = utils::hook::invoke<float>(0x1404E6BB0, tree, first_raise);
			if (utils::hook::invoke<bool>(0x1404E6C30, tree, first_raise))
			{
				flourish.state = flourish_state::finished;
				console::info("[Zombies Perks] Perk flourish playback finished: progress=%.4f; raise node=%s\n",
					flourish.progress, info ? "finished" : "retired");
			}
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

	void hide_unused_grenade_launcher(const game::XAssetHeader header)
	{
		auto* weapon = static_cast<weapon_visuals*>(header.data);
		if (!weapon || !weapon->name) return;
		constexpr const char* weapon_names[] = {"frag_grenade_throw_zombies_mp", "contact_grenade_throw_zombies_mp"};
		constexpr const char* model_names[] = {"vm_exo_arm_launcher_frag", "vm_exo_arm_launcher_contact"};
		static std::array<game::scr_string_t, 32> hidden_bones[std::size(weapon_names)];
		for (size_t i = 0; i < std::size(weapon_names); ++i)
		{
			if (std::strcmp(weapon->name, weapon_names[i])) continue;
			if (weapon->hide_tags == hidden_bones[i].data()) return;
			const auto* model = weapon->gun_models ? weapon->gun_models[0] : nullptr;
			if (!model || !model->name || std::strcmp(model->name, model_names[i])) return;

			// Use private storage: stock empty hide-tag arrays may be shared.
			// Bone strings are already owned by this loaded model.
			std::array<game::scr_string_t, 32> tags{};
			if (weapon->hide_tags) std::copy_n(weapon->hide_tags, tags.size(), tags.begin());
			if (!model->names || !model->count || model->count > tags.size())
			{
				console::warn("[Zombies] Cannot hide %s: invalid launcher bones\n", weapon->name);
				return;
			}
			for (unsigned int bone = 0; bone < model->count; ++bone)
			{
				const auto tag = model->names[bone];
				if (std::find(tags.begin(), tags.end(), tag) != tags.end()) continue;
				const auto empty = std::find(tags.begin(), tags.end(), game::scr_string_t{});
				if (empty == tags.end())
				{
					console::warn("[Zombies] Cannot hide %s: hide-tag list is full\n", weapon->name);
					return;
				}
				*empty = tag;
			}
			hidden_bones[i] = tags;
			weapon->hide_tags = hidden_bones[i].data();
			console::info("[Zombies] %s: hidden unused %s (%u bones) for hand throws\n",
				weapon->name, model->name, static_cast<unsigned int>(model->count));
			return;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_sp()) return;
			gsc::add_function("awz_beginweaponflourish", &begin_weapon_flourish);
			gsc::add_function("awz_weaponflourishstatus", &weapon_flourish_status);
			gsc::add_function("awz_endweaponflourish", &end_weapon_flourish);
			scheduler::loop(update_weapon_flourish, scheduler::pipeline::main);
			scripting::on_shutdown([](int) { end_weapon_flourish(); });
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
