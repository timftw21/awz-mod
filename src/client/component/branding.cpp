#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"

#include "localized_strings.hpp"
#include "dvars.hpp"
#include "console.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

#include "version.hpp"

namespace branding
{
	namespace
	{
		constexpr auto version_display = "AWZ-MOD 0.5";
		utils::hook::detour ui_get_formatted_build_number_hook;

		const char* ui_get_formatted_build_number_stub()
		{
			const auto* const build_num = ui_get_formatted_build_number_hook.invoke<const char*>();

			return utils::string::va("%s (%s)", version_display, build_num);
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			if (game::environment::is_mp())
			{
				localized_strings::override("LUA_MENU_MULTIPLAYER_CAPS", "s1-mod: MULTIPLAYER\n");
			}
			localized_strings::override("LUA_MENU_LEGAL_COPYRIGHT", "s1-mod: " VERSION);

			dvars::override::set_string("version", version_display);

			ui_get_formatted_build_number_hook.create(
				SELECT_VALUE(0x14035B3F0, 0x1404A8950), ui_get_formatted_build_number_stub);

			console::info("[Branding] Top-left overlay removed; version display: %s\n", version_display);
		}
	};
}

REGISTER_COMPONENT(branding::component)
