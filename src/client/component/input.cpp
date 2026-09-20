#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"

#include "game_console.hpp"
#include "server_list.hpp"
#include "console.hpp"

#include <utils/hook.hpp>

namespace input
{
	namespace
	{
		utils::hook::detour cl_char_event_hook;
		utils::hook::detour cl_key_event_hook;
		utils::hook::detour cl_mouse_event_hook;

		int cl_mouse_event_stub(const int x, const int y, const int delta_x, const int delta_y)
		{
			const auto window = *reinterpret_cast<HWND*>(0x14B5B9D70);
			const bool foreground = window && GetForegroundWindow() == window;
			static int last_foreground = -1;
			if (last_foreground != static_cast<int>(foreground))
			{
				last_foreground = foreground;
				console::info("[Input] Mouse dispatch %s: game window %s foreground\n",
					foreground ? "resumed" : "suspended", foreground ? "is" : "is not");
			}

			// The native menu branch polls GetCursorPos even when IN_Activate marks
			// the mouse inactive. Returning zero skips UI/gameplay dispatch and
			// recentering, while IN_MouseMove still consumes its accumulated deltas.
			if (!foreground) return 0;
			return cl_mouse_event_hook.invoke<int>(x, y, delta_x, delta_y);
		}

		void cl_char_event_stub(const int local_client_num, const int key)
		{
			if (!game_console::console_char_event(local_client_num, key))
			{
				return;
			}

			cl_char_event_hook.invoke<void>(local_client_num, key);
		}

		void cl_key_event_stub(const int local_client_num, const int key, const signed int down, const int arg4)
		{
			if (!game_console::console_key_event(local_client_num, key, down))
			{
				return;
			}

			if (game::environment::is_mp() && !server_list::sl_key_event(key, down))
			{
				return;
			}

			cl_key_event_hook.invoke<void>(local_client_num, key, down, arg4);
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

			cl_char_event_hook.create(SELECT_VALUE(0x14013E7B0, 0x140206690), cl_char_event_stub);
			cl_key_event_hook.create(SELECT_VALUE(0x14013EB20, 0x140206900), cl_key_event_stub);
			if (game::environment::is_mp())
			{
				cl_mouse_event_hook.create(0x140204D90, cl_mouse_event_stub);
				console::info("[Input] Foreground-window check enabled for mouse dispatch\n");
			}
		}
	};
}

REGISTER_COMPONENT(input::component)
