#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "localized_strings.hpp"
#include "loading_tips.hpp"
#include "console.hpp"
#include "solo.hpp"
#include <utils/hook.hpp>
#include <utils/string.hpp>
#include <utils/concurrency.hpp>
#include "game/game.hpp"

namespace localized_strings
{
	namespace
	{
		utils::hook::detour seh_string_ed_get_string_hook;

		using localized_map = std::unordered_map<std::string, std::string>;
		utils::concurrency::container<localized_map> localized_overrides;
		std::atomic_uint reported_tip_modes{0};

		const char* seh_string_ed_get_string(const char* reference)
		{
			return localized_overrides.access<const char*>([&](const localized_map& map)
			{
				const auto entry = map.find(reference);
				if (entry != map.end())
				{
					return utils::string::va("%s", entry->second.data());
				}

				const auto* stock = seh_string_ed_get_string_hook.invoke<const char*>(reference);
				const auto tip = loading_tips::index(reference);
				if (!stock || !tip || !game::environment::is_mp() ||
					game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES) return stock;

				// Loading screens run before GSC and the in-game Lua VM. Resolve the
				// mode here so a stale Classic selection cannot affect Private Match.
				const auto* mode = game::Dvar_FindVar("ui_awz_classic");
				const bool classic = solo::active() && mode && mode->current.integer == 1;
				const bool english = !std::strcmp(game::SEH_GetCurrentLanguageName(), "english");
				const auto text = loading_tips::text(tip, stock, classic, english);
				const unsigned int bit = classic ? 2u : 1u;
				if (!(reported_tip_modes.fetch_or(bit) & bit))
				{
					console::info("[Loading Tips] %s: spacing normalized; English wording=%d; stock map rotations retained\n",
						classic ? "Classic" : "Standard", english);
				}
				return utils::string::va("%s", text.c_str());
			});
		}
	}

	void override(const std::string& key, const std::string& value)
	{
		localized_overrides.access([&](localized_map& map)
		{
			map[key] = value;
		});
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			// Change some localized strings
			seh_string_ed_get_string_hook.create(SELECT_VALUE(0x140339CF0, 0x140474FC0), &seh_string_ed_get_string);
		}
	};
}

REGISTER_COMPONENT(localized_strings::component)
