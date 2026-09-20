#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console.hpp"

#include <utils/hook.hpp>

namespace loading_screen
{
	namespace
	{
		utils::hook::detour get_font_handle_hook;
		utils::hook::detour register_ui_assets_hook;
		game::Font_s* large_title_font = nullptr;
		bool reported_title = false;

		void register_ui_assets_stub()
		{
			large_title_font = nullptr;
			reported_title = false;
			register_ui_assets_hook.invoke<void>();
			if (game::Com_GetCurrentCoDPlayMode() == game::CODPLAYMODE_ZOMBIES)
			{
				large_title_font = game::DB_FindXAssetHeader(game::ASSET_TYPE_FONT, "fonts/zmTitleFontLarge", false).font;
			}
		}

		game::Font_s* get_font_handle_stub(const game::ScreenPlacement* placement, int font_index, float scale)
		{
			auto* font = get_font_handle_hook.invoke<game::Font_s*>(placement, font_index, scale);
			// The stock selector ignores scale and always returns the 42px Zombies
			// title. Native text rendering normalizes both variants to 48 * scale,
			// so selecting the 72px glyphs improves detail without enlarging the text.
			if (font_index == 3 && font && placement && large_title_font &&
				!std::strcmp(font->fontName, "fonts/zmTitleFont") &&
				large_title_font->pixelHeight > font->pixelHeight &&
				48.0f * scale * placement->scaleVirtualToReal[1] > font->pixelHeight)
			{
				if (!reported_title)
				{
					reported_title = true;
					console::info("[Loading Screen] Title glyphs: %d -> %d pixels; display height=%.1f; layout scale=%.3f\n",
						font->pixelHeight, large_title_font->pixelHeight, 48.0f * scale * placement->scaleVirtualToReal[1], scale);
				}
				return large_title_font;
			}
			return font;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_sp()) return;
			register_ui_assets_hook.create(0x140488930, register_ui_assets_stub);
			get_font_handle_hook.create(0x14048D9C0, get_font_handle_stub);
		}
	};
}

REGISTER_COMPONENT(loading_screen::component)
