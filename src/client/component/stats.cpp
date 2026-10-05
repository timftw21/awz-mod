#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "command.hpp"
#include "console.hpp"

#include <utils/hook.hpp>

namespace stats
{
	namespace
	{
		const game::dvar_t* cg_unlock_all_items;
		const game::dvar_t* cg_unlock_all_loot;

		utils::hook::detour is_item_locked_hook1;
		utils::hook::detour is_item_locked_hook2;
		utils::hook::detour is_item_locked_hook3;
		utils::hook::detour data_lookup_hook;

		// StructuredDataLookup: definition, current type, byte offset, error state.
		struct data_lookup
		{
			const int* definition;
			const void* type;
			unsigned int offset;
			int error;
		};
		static_assert(sizeof(data_lookup) == 24);

		bool data_lookup_stub(data_lookup* lookup, const game::scr_string_t* path, int count, int* consumed)
		{
			const auto initial = *lookup;
			const auto result = data_lookup_hook.invoke<bool>(lookup, path, count, consumed);
			if (!result)
			{
				// The stock fatal popup omits the field that failed. Record it before
				// the caller raises Com_Error, without changing lookup/error behavior.
				std::string field;
				for (int i = 0; i < std::clamp(count, 0, 16); ++i)
				{
					if (i) field += '.';
					const auto* name = game::SL_ConvertToString(path[i]);
					field += name ? name : "<null>";
				}
				console::error("[Stats] Persistent lookup failed: version=%d; group offset=%u; path=%s; consumed=%d/%d; error=%d; mode=%d\n",
					*initial.definition, initial.offset, field.c_str(), *consumed, count, lookup->error,
					game::Com_GetCurrentCoDPlayMode());
				void* frames[16]{};
				const auto depth = CaptureStackBackTrace(0, 16, frames, nullptr);
				for (USHORT i = 0; i < depth; ++i)
					console::error("[Stats] Lookup caller %u: %p\n", i, frames[i]);
			}
			return result;
		}

		int is_item_locked_stub1(void* a1, void* a2, void* a3)
		{
			if (cg_unlock_all_items->current.enabled)
			{
				return 0;
			}

			return is_item_locked_hook1.invoke<int>(a1, a2, a3);
		}

		int is_item_locked_stub2(void* a1, void* a2, void* a3, void* a4, void* a5)
		{
			if (cg_unlock_all_items->current.enabled)
			{
				return 0;
			}

			return is_item_locked_hook2.invoke<int>(a1, a2, a3, a4, a5);
		}

		int is_loot_locked_stub(void* a1)
		{
			if (cg_unlock_all_loot->current.enabled)
			{
				return 0;
			}

			return is_item_locked_hook3.invoke<int>(a1);
		}

		int is_item_locked()
		{
			return 0;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_sp())
			{
				return;
			}

			data_lookup_hook.create(0x1404BA3F0, data_lookup_stub);
			console::info("[Stats] Persistent lookup failure diagnostics enabled\n");

			if (game::environment::is_dedi())
			{
				// unlock all
				utils::hook::jump(0x1403BD790, is_item_locked); // LiveStorage_IsItemUnlockedFromTable_LocalClient
				utils::hook::jump(0x1403BD290, is_item_locked); // LiveStorage_IsItemUnlockedFromTable
				utils::hook::jump(0x1403BAF60, is_item_locked); // unlocks supply drop loot
			}
			else
			{
				// unlock all
				cg_unlock_all_items = game::Dvar_RegisterBool("cg_unlockall_items", false, game::DVAR_FLAG_SAVED);
				cg_unlock_all_loot = game::Dvar_RegisterBool("cg_unlockall_loot", false, game::DVAR_FLAG_SAVED);
				game::Dvar_RegisterBool("cg_unlockall_classes", false, game::DVAR_FLAG_SAVED);

				is_item_locked_hook1.create(0x1403BD790, is_item_locked_stub1); // LiveStorage_IsItemUnlockedFromTable_LocalClient
				is_item_locked_hook2.create(0x1403BD290, is_item_locked_stub2); // LiveStorage_IsItemUnlockedFromTable
				is_item_locked_hook3.create(0x1403BAF60, is_loot_locked_stub);  // unlocks supply drop loot
			}

			command::add("setPlayerDataInt", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: setPlayerDataInt <data>, <value>\n");
					return;
				}

				// SL_FindString
				const auto lookup_string = game::SL_FindString(params.get(1));
				const auto value = atoi(params.get(2));

				// SetPlayerDataInt
				reinterpret_cast<void(*)(signed int, unsigned int, unsigned int, unsigned int)>(0x1403BF550)(
					0, lookup_string, value, 0);
			});

			command::add("getPlayerDataInt", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: getPlayerDataInt <data>\n");
					return;
				}

				// SL_FindString
				const auto lookup_string = game::SL_FindString(params.get(1));

				// GetPlayerDataInt
				const auto result = reinterpret_cast<int(*)(signed int, unsigned int, unsigned int)>(0x1403BE860)(
					0, lookup_string, 0);
				console::info("%d\n", result);
			});

			command::add("unlockstats", []()
			{
				command::execute("setPlayerDataInt prestige 30");
				command::execute("setPlayerDataInt experience 1002100");
			});
		}
	};
}

REGISTER_COMPONENT(stats::component)
