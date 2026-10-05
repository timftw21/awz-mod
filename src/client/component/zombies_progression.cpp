#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "game/ui_scripting/execution.hpp"
#include "command.hpp"
#include "console.hpp"
#include "filesystem.hpp"
#include "gsc/script_extension.hpp"
#include "localized_strings.hpp"
#include "scheduler.hpp"
#include "zombies_progression.hpp"

#include <utils/string.hpp>
#include <charconv>

namespace zombies_progression
{
	namespace
	{
		// Native layouts from the installed playerdata.def and S1 asset exporter.
		struct data_type { int type; int index; };
		struct property { game::scr_string_t name; data_type type; unsigned int offset; int validation; };
		struct data_struct { int count; property* properties; int size; unsigned int bit_offset; };
		struct indexed_array { int count; data_type type; unsigned int element_size; };
		struct definition
		{
			int version; unsigned int checksum;
			int enum_count; void* enums;
			int struct_count; data_struct* structs;
			int array_count; indexed_array* arrays;
			int enum_array_count; void* enum_arrays;
			data_type root; unsigned int size;
		};
		struct definition_set { const char* name; unsigned int count; definition* definitions; };
		static_assert(sizeof(property) == 20 && sizeof(data_struct) == 24);
		static_assert(sizeof(definition) == 88 && sizeof(definition_set) == 24);

		constexpr int reserved_size = 304;
		constexpr const char* table_name = "mp/awzGateChallenges.csv";
		std::mutex asset_mutex;
		std::vector<std::string> strings;
		std::vector<game::StringTableCell> cells;
		game::StringTable gates{};

		property* find_property(data_struct& object, const char* name)
		{
			for (int i = 0; i < object.count; ++i)
				if (!std::strcmp(game::SL_ConvertToString(object.properties[i].name), name))
					return &object.properties[i];
			return nullptr;
		}

		bool extend_definition(definition& def)
		{
			if (def.root.type != 5 || def.root.index < 0 || def.root.index >= def.struct_count) return false;
			auto& root = def.structs[def.root.index];
			for (int i = 0; i < root.count; ++i)
			{
				const auto& group = root.properties[i];
				if (group.type.type != 5 || group.type.index < 0 || group.type.index >= def.struct_count) continue;
				auto& coop = def.structs[group.type.index];
				if (!find_property(coop, "totalKills") || !find_property(coop, "highestRound")) continue;
				const auto* reserved = find_property(coop, "reserved");
				if (!reserved || reserved->type.type != 6 || reserved->type.index < 0 || reserved->type.index >= def.array_count) return false;
				auto& array = def.arrays[reserved->type.index];
				if (array.type.type != 1 || array.element_size != 1 || reserved->offset != 82) return false;
				if (array.count == reserved_size && coop.size == 82 + reserved_size) return true;
				if (array.count != 256 || coop.size != 338) return false;

				// The co-op group has a fixed 1240-byte slot in versions 470/471.
				// Extend into its unused tail, never move existing fields or grow the file.
				auto limit = def.size;
				for (int j = 0; j < root.count; ++j)
					if (root.properties[j].offset > group.offset)
						limit = std::min(limit, root.properties[j].offset);
				if (group.offset + 82 + reserved_size > limit) return false;
				for (int s = 0; s < def.struct_count; ++s)
					for (int p = 0; p < def.structs[s].count; ++p)
					{
						const auto* other = &def.structs[s].properties[p];
						if (other != reserved && other->type.type == 6 && other->type.index == reserved->type.index) return false;
					}
				array.count = reserved_size;
				coop.size = 82 + reserved_size;
				console::info("[Zombies Ranks] Profile v%d: reserved bytes 256-303 enabled in co-op slot %u..%u; file size=%u unchanged\n",
					def.version, group.offset, limit, def.size);
				return true;
			}
			return false;
		}

		void run_progression_command(const char* name, const char* method, int player_level = 0)
		{
			const auto leave = gsl::finally(game::LUI_LeaveCriticalSection);
			game::LUI_EnterCriticalSection();
			const auto state = *game::hks::lua_state;
			if (!state)
			{
				console::warn("[Zombies Ranks] Open the Zombies lobby before using %s\n", name);
				return;
			}
			try
			{
				const auto progression = ui_scripting::table(state->globals.v.table).get("AWZProgression");
				if (!progression.is<ui_scripting::table>())
				{
					console::warn("[Zombies Ranks] Open the Zombies lobby before using %s\n", name);
					return;
				}
				const auto callback = progression.as<ui_scripting::table>().get(method);
				if (player_level) callback(player_level);
				else callback();
			}
			catch (const std::exception& error)
			{
				console::error("[Zombies Ranks] %s failed: %s\n", name, error.what());
			}
		}
	}

	void extend_profile(const game::XAssetHeader asset)
	{
		if (!asset.data) return;
		const auto* set = static_cast<definition_set*>(asset.data);
		if (std::strcmp(set->name, "mp/playerdata.def")) return;
		std::lock_guard lock(asset_mutex);
		for (unsigned int i = 0; i < set->count; ++i)
			if (set->definitions[i].version == 470 || set->definitions[i].version == 471)
				extend_definition(set->definitions[i]);
	}

	bool available()
	{
		if (!challenge_table(table_name)) return false;
		const auto asset = game::DB_FindXAssetHeader(game::ASSET_TYPE_STRUCTURED_DATA_DEF, "mp/playerdata.def", false);
		if (!asset.data) return false;
		std::lock_guard lock(asset_mutex);
		const auto* set = static_cast<definition_set*>(asset.data);
		definition* latest = nullptr;
		for (unsigned int i = 0; i < set->count; ++i)
			if (!latest || set->definitions[i].version > latest->version) latest = &set->definitions[i];
		return latest && (latest->version == 470 || latest->version == 471) && extend_definition(*latest);
	}

	game::StringTable* challenge_table(const char* name)
	{
		if (_stricmp(name, table_name)) return nullptr;
		std::lock_guard lock(asset_mutex);
		if (gates.values) return &gates;
		static bool failed = false;
		if (failed) return nullptr;
		const auto reject = [](const char* reason) -> game::StringTable*
		{
			failed = true;
			console::error("[Zombies Ranks] Gate Challenges disabled: %s\n", reason);
			return nullptr;
		};
		const auto source = filesystem::read_file(table_name);
		if (source.empty()) return reject("missing mp/awzGateChallenges.csv");
		std::vector<std::string> values;
		for (auto line : utils::string::split(source, '\n'))
		{
			if (!line.empty() && line.back() == '\r') line.pop_back();
			if (line.empty()) continue;
			auto row = utils::string::split(line, ',');
			if (row.size() != 45) return reject("expected 45 columns per challenge row");
			const auto index = values.size() / 45;
			if (index > 0)
			{
				char* end{};
				const auto target = std::strtol(row[9].c_str(), &end, 10);
				if (row[9].empty() || *end || target < 1 || target > 65535 ||
					row[6] != std::to_string(((index - 1) / 3 + 1) * 10) ||
					(row[44] != "kills" && row[44] != "headshots" && row[44] != "melee" && row[44] != "rounds" && row[44] != "flawless"))
					return reject("invalid gate level, target or event");
			}
			values.insert(values.end(), row.begin(), row.end());
		}
		if (values.size() != 16 * 45) return reject("expected exactly 15 Gate Challenges");
		strings = std::move(values);
		cells.reserve(strings.size());
		for (const auto& value : strings)
		{
			// S1 StringTable hashes are case-insensitive, with a multiplier of 31.
			unsigned int hash = 0;
			for (const unsigned char c : value) hash = hash * 31 + std::tolower(c);
			cells.push_back({value.c_str(), static_cast<int>(hash)});
		}
		gates = {table_name, 45, 16, cells.data()};
		console::info("[Zombies Ranks] Loaded 15 multiplayer-format Gate Challenges for levels 10/20/30/40/50\n");
		return &gates;
	}

	game::StringTable* notification_table(const char* name, game::StringTable* stock)
	{
		if (!stock || game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES) return stock;
		const bool splash = !_stricmp(name, "mp/splashTable.csv");
		if (!splash && _stricmp(name, "mp/allChallengesTable.csv")) return stock;
		const auto* challenges = challenge_table(table_name);
		if (!challenges || stock->columnCount < (splash ? 12 : 44)) return stock;
		std::lock_guard lock(asset_mutex);
		struct extended_table
		{
			std::vector<std::string> strings;
			std::vector<game::StringTableCell> cells;
			game::StringTable table{};
		};
		static std::unordered_map<const game::StringTableCell*, std::unique_ptr<extended_table>> tables;
		if (const auto found = tables.find(stock->values); found != tables.end()) return &found->second->table;
		auto extended = std::make_unique<extended_table>();
		auto& values = extended->strings;
		for (int i = 0; i < stock->rowCount * stock->columnCount; ++i)
			values.emplace_back(stock->values[i].string ? stock->values[i].string : "");
		for (int i = 0; i < 16; ++i)
		{
			const bool bank = i == 15;
			const std::string ref = bank ? "ch_awz_banked_xp" : challenges->values[(i + 1) * 45].string;
			const auto title = "AWZ_SPLASH_" + std::to_string(i);
			const auto description = title + "_DESC";
			localized_strings::override(title, bank ? "BANKED XP" : challenges->values[(i + 1) * 45 + 1].string);
			localized_strings::override(description, bank ? "+&&1 XP" : "Gate Challenge Complete");
			std::vector<std::string> row(stock->columnCount);
			if (splash)
			{
				row[0] = ref; row[1] = title; row[2] = description;
				row[3] = "ui_reward_xp"; row[4] = "3.5";
				row[5] = "0.25"; row[6] = "0.75"; row[7] = "0.25"; row[8] = "1";
				row[9] = "mp_s1_challenge_complete"; row[11] = "challenge_splash";
			}
			else
			{
				if (!bank)
					for (int column = 0; column < 44; ++column)
						row[column] = challenges->values[(i + 1) * 45 + column].string;
				row[0] = ref; row[1] = title; row[9] = bank ? "1" : row[9];
				row[2] = description; row[4] = "1"; row[10] = "0";
				// This omnvar is limited to -1..2046; 2000..2015 are unused stock IDs.
				row[27] = std::to_string(2000 + i);
				// These rows only supply notifications. Column 43 excludes them from
				// native Ranked challenge validation and stock GSC registration;
				// ranks.gsc registers Gate Challenges separately in the co-op profile.
				row[43] = "1";
			}
			values.insert(values.end(), row.begin(), row.end());
		}
		for (const auto& value : values)
		{
			unsigned int hash = 0;
			for (const unsigned char c : value) hash = hash * 31 + std::tolower(c);
			extended->cells.push_back({value.c_str(), static_cast<int>(hash)});
		}
		extended->table = {stock->name, stock->columnCount, stock->rowCount + 16, extended->cells.data()};
		const auto result = &extended->table;
		tables.emplace(stock->values, std::move(extended));
		console::info("[Zombies Ranks] Extended %s with 15 Gate Challenge notifications and BANKED XP; icon=ui_reward_xp\n", name);
		if (!splash)
			console::info("[Zombies Ranks] All 16 notification rows excluded from Ranked challenge persistence; Gate progress uses the co-op profile\n");
		return result;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::is_mp()) return;
			// SetClientDvar only transmits registered SCRIPTINFO dvars. Register after
			// the engine's script-string allocator is ready, before a match can start.
			scheduler::once([]
			{
				game::Dvar_RegisterString("ui_awz_match_ranks", "", game::DVAR_FLAG_SCRIPTINFO);
				console::info("[Zombies Ranks] Registered script-writable AAR rank snapshot channel\n");
			}, scheduler::pipeline::main);
			gsc::add_function("awz_progressionavailable", [] { game::Scr_AddInt(available()); });
			command::add("awz_resetprogression", [] { run_progression_command("awz_resetprogression", "Reset"); });
			command::add("awz_prestige", [] { run_progression_command("awz_prestige", "Prestige"); });
			command::add("awz_readytoprestige", [] { run_progression_command("awz_readytoprestige", "ReadyToPrestige"); });
			command::add("awz_setlevel", [](const command::params& params)
			{
				int player_level = 0;
				if (params.size() == 2)
				{
					const auto* text = params[1];
					const auto* end = text + std::strlen(text);
					const auto parsed = std::from_chars(text, end, player_level);
					if (parsed.ec == std::errc{} && parsed.ptr == end && player_level >= 1 && player_level <= 50)
					{
						run_progression_command("awz_setlevel", "SetLevel", player_level);
						return;
					}
				}
				console::warn("[Zombies Ranks] Usage: awz_setlevel <1-50> (in the Zombies lobby)\n");
			});
		}
	};
}

REGISTER_COMPONENT(zombies_progression::component)
