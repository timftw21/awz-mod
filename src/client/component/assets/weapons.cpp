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
#include <span>

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

		struct animation_notify
		{
			game::scr_string_t name;
			float time;
		};

		struct animation_timing
		{
			const char* name;
			std::uint16_t data_counts[3];
			std::uint16_t frame_count;
			std::uint8_t flags;
			std::uint8_t bone_counts[12];
			std::uint8_t notify_count;
			std::uint8_t asset_type;
			std::uint8_t ik_type;
			unsigned int random_counts[3];
			unsigned int index_count;
			float frame_rate;
			float frequency;
			const game::scr_string_t* names;
			const std::uint8_t* bytes;
			const std::int16_t* shorts;
			const float* ints;
			const std::int16_t* random_shorts;
			const std::uint8_t* random_bytes;
			const void* random_ints;
			const void* indices;
			const animation_notify* notify;
			std::byte remaining[88];
		};
		static_assert(offsetof(animation_timing, frame_count) == 0xE);
		static_assert(offsetof(animation_timing, flags) == 0x10);
		static_assert(offsetof(animation_timing, frame_rate) == 0x30);
		static_assert(offsetof(animation_timing, names) == 0x38);
		static_assert(offsetof(animation_timing, ints) == 0x50);
		static_assert(offsetof(animation_timing, notify) == 0x78);
		static_assert(sizeof(animation_timing) == 0xD8);

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

		struct animation_storage
		{
			animation_timing parts{};
			animation_notify end_notify{};
			std::vector<std::uint8_t> bytes;
			std::vector<std::int16_t> shorts;
			std::vector<float> ints;
		};

		template <typename T>
		std::span<const T> consume(std::span<const T>& data, const size_t count)
		{
			if (count > data.size()) throw std::runtime_error("truncated animation data");
			const auto result = data.first(count);
			data = data.subspan(count);
			return result;
		}

		// Bake the actual last pose, including prop bones, into a quiet looping
		// idle. Reusing vm_exo_suit_idle raises the left hand after the flourish.
		void make_intro_idle(const animation_timing& source, animation_storage& output)
		{
			const auto count = source.bone_counts[9];
			if (!count || !source.frame_count || source.frame_count >= 256 || (source.flags & 6) ||
				!source.names || !source.bytes || !source.shorts || !source.ints || !source.random_shorts)
				throw std::runtime_error("unsupported intro animation layout");
			if (!source.notify || !source.notify_count || source.notify[source.notify_count - 1].time != 1.0f ||
				std::strcmp(game::SL_ConvertToString(source.notify[source.notify_count - 1].name), "end"))
				throw std::runtime_error("intro animation has no terminal end marker");
			std::span bytes(source.bytes, source.data_counts[0]);
			std::span shorts(source.shorts, source.data_counts[1]);
			std::span ints(source.ints, source.data_counts[2]);
			std::span random_shorts(source.random_shorts, source.random_counts[1]);
			std::span random_bytes(source.random_bytes, source.random_counts[0]);
			std::vector<std::array<std::int16_t, 4>> rotations;
			std::vector<std::array<float, 3>> translations(count);
			for (unsigned int group = 0; group < 5; ++group)
			{
				for (unsigned int bone = 0; bone < source.bone_counts[group]; ++bone)
				{
					std::array<std::int16_t, 4> rotation{0, 0, 0, 32767};
					if (group)
					{
						const size_t width = (group == 1 || group == 3) ? 2 : 4;
						std::span<const std::int16_t> key;
						if (group < 3)
						{
							const auto keys = static_cast<std::uint16_t>(consume(shorts, 1)[0]) + 1u;
							if (consume(bytes, keys).back() != source.frame_count)
								throw std::runtime_error("intro rotation has no final key");
							key = consume(random_shorts, keys * width).last(width);
						}
						else key = consume(shorts, width);
						std::copy(key.begin(), key.end(), rotation.end() - width);
					}
					rotations.push_back(rotation);
				}
			}
			if (rotations.size() != count) throw std::runtime_error("invalid intro bone counts");
			for (unsigned int group = 5; group < 9; ++group)
			{
				for (unsigned int i = 0; i < source.bone_counts[group]; ++i)
				{
					const auto bone = consume(bytes, 1)[0];
					if (bone >= count) throw std::runtime_error("invalid intro translation bone");
					if (group < 7)
					{
						const auto keys = static_cast<std::uint16_t>(consume(shorts, 1)[0]) + 1u;
						if (consume(bytes, keys).back() != source.frame_count)
							throw std::runtime_error("intro translation has no final key");
						const auto bounds = consume(ints, 6);
						for (size_t axis = 0; axis < 3; ++axis) translations[bone][axis] = bounds[axis];
						if (group == 5)
						{
							const auto key = consume(random_bytes, keys * 3).last(3);
							for (size_t axis = 0; axis < 3; ++axis) translations[bone][axis] += bounds[axis + 3] * key[axis];
						}
						else
						{
							const auto key = consume(random_shorts, keys * 3).last(3);
							for (size_t axis = 0; axis < 3; ++axis) translations[bone][axis] += bounds[axis + 3] * static_cast<std::uint16_t>(key[axis]);
						}
					}
					else if (group == 7)
					{
						const auto key = consume(ints, 3);
						std::copy(key.begin(), key.end(), translations[bone].begin());
					}
				}
			}
			if (!bytes.empty() || !shorts.empty() || !ints.empty() || !random_shorts.empty() || !random_bytes.empty())
				throw std::runtime_error("unconsumed intro animation data");

			output = {};
			for (unsigned int bone = 0; bone < count; ++bone)
			{
				output.bytes.push_back(static_cast<std::uint8_t>(bone));
				output.shorts.insert(output.shorts.end(), rotations[bone].begin(), rotations[bone].end());
				output.ints.insert(output.ints.end(), translations[bone].begin(), translations[bone].end());
			}
			auto& idle = output.parts;
			idle.name = source.name;
			idle.data_counts[0] = count;
			idle.data_counts[1] = count * 4;
			idle.data_counts[2] = count * 3;
			idle.frame_count = 1;
			idle.flags = 1;
			idle.bone_counts[4] = idle.bone_counts[7] = idle.bone_counts[9] = count;
			idle.asset_type = source.asset_type;
			idle.ik_type = source.ik_type;
			idle.frame_rate = idle.frequency = source.frame_rate;
			idle.names = source.names;
			idle.bytes = output.bytes.data();
			idle.shorts = output.shorts.data();
			idle.ints = output.ints.data();
			// XAnim's client notification walker (0x1404E7470) reads the next
			// marker even on a constant idle pose. Retain the stock end sentinel;
			// omitting it dereferences null at 0x1404E7687 as the intro finishes.
			// Only the end marker belongs here; intro sounds must not replay.
			output.end_notify = source.notify[source.notify_count - 1];
			idle.notify_count = 1;
			idle.notify = &output.end_notify;
		}

		size_t static_translation(const animation_timing& animation, const char* name)
		{
			// Static/zero translation bone indices form the tail of dataByte;
			// each preceding animated translation uses six floats for its bounds.
			const auto tail = animation.bone_counts[7] + animation.bone_counts[8];
			if (!animation.names || !animation.bytes || !animation.ints || tail > animation.data_counts[0])
				throw std::runtime_error("invalid static animation data");
			const auto* bones = animation.bytes + animation.data_counts[0] - tail;
			for (unsigned int i = 0; i < animation.bone_counts[7]; ++i)
			{
				if (bones[i] >= animation.bone_counts[9]) throw std::runtime_error("invalid static translation bone");
				if (std::strcmp(game::SL_ConvertToString(animation.names[bones[i]]), name)) continue;
				const auto offset = (animation.bone_counts[5] + animation.bone_counts[6]) * 6 + i * 3;
				if (offset + 3 <= animation.data_counts[2]) return offset;
			}
			throw std::runtime_error("missing static weapon translation");
		}

		void fix_animation_poses(weapon_visuals* weapon)
		{
			if (!weapon || !weapon->name || !weapon->animations) return;
			constexpr const char* intros[] = {"char_intro_guardzm_mp", "char_intro_execzm_mp",
				"char_intro_itzm_mp", "char_intro_janitorzm_mp", "char_intro_pilotzm_mp"};
			static animation_storage idle_poses[std::size(intros)];
			static std::array<animation_timing*, 180> intro_tables[std::size(intros)];
			try
			{
				for (size_t i = 0; i < std::size(intros); ++i)
				{
					if (std::strcmp(weapon->name, intros[i])) continue;
					if (weapon->animations == intro_tables[i].data()) return;
					const auto* raise = weapon->animations[37];
					if (!raise) throw std::runtime_error("missing character flourish");
					make_intro_idle(*raise, idle_poses[i]);
					std::copy_n(weapon->animations, intro_tables[i].size(), intro_tables[i].begin());
					for (const auto slot : {1, 2, 39, 44, 46}) intro_tables[i][slot] = &idle_poses[i].parts;
					weapon->animations = intro_tables[i].data();
					console::info("[Zombies Animations] %s: idle/drop now hold %s frame %u with stock end marker; intro and pistol timing preserved\n",
						weapon->name, raise->name, static_cast<unsigned int>(raise->frame_count));
					return;
				}

				if (std::strcmp(weapon->name, "iw5_m182sprzm_mp")) return;
				static animation_storage melee_poses[7];
				static std::array<animation_timing*, 180> melee_table;
				if (weapon->animations == melee_table.data()) return;
				const auto* miss = weapon->animations[12];
				if (!miss) throw std::runtime_error("missing knife miss animation");
				const auto parking = static_translation(*miss, "tag_weapon");
				std::copy_n(weapon->animations, melee_table.size(), melee_table.begin());
				for (unsigned int slot = 9; slot <= 15; ++slot)
				{
					const auto* source = weapon->animations[slot];
					if (!source) continue;
					const auto offset = static_translation(*source, "tag_weapon");
					auto& pose = melee_poses[slot - 9];
					pose.parts = *source;
					pose.ints.assign(source->ints, source->ints + source->data_counts[2]);
					// The stock miss already parks the rifle behind the camera. Use
					// that same position for swings/hits; keep hand and knife keys.
					std::copy_n(miss->ints + parking, 3, pose.ints.begin() + offset);
					pose.parts.ints = pose.ints.data();
					melee_table[slot] = &pose.parts;
				}
				weapon->animations = melee_table.data();
				console::info("[Zombies Animations] MK14: knife swings/hits use %s weapon parking (%.2f, %.2f, %.2f); hands, notetracks and timers preserved\n",
					miss->name, miss->ints[parking], miss->ints[parking + 1], miss->ints[parking + 2]);
			}
			catch (const std::exception& error)
			{
				console::warn("[Zombies Animations] Cannot repair %s: %s\n", weapon->name, error.what());
			}
		}

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
				// An exported empty script string is nonzero, so it suppresses the
				// engine's default knife tag and merges the knife into j_gun instead.
				const auto knife_tag = *reinterpret_cast<const game::scr_string_t*>(weapon + 0xD24);
				const auto* visuals = reinterpret_cast<const weapon_visuals*>(weapon);
				const auto animation_name = [visuals](const size_t index)
				{
					return visuals->animations && visuals->animations[index] ? visuals->animations[index]->name : "<missing>";
				};
				console::info("[Classic] 1911 animations: knife tag='%s'; reload=%s; empty=%s; quick=%s\n",
					knife_tag ? game::SL_ConvertToString(knife_tag) : "<default>",
					animation_name(24), animation_name(25), animation_name(34));
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

	void fix_visuals(const game::XAssetHeader header)
	{
		auto* weapon = static_cast<weapon_visuals*>(header.data);
		fix_animation_poses(weapon);
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
