#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "updater.hpp"
#include "console.hpp"

namespace updater
{
	void update()
	{
		// The inherited feed publishes another client's executable and data files.
		// Do not invoke it, even with -update, until awz-mod has its own release feed.
		console::info("[Updater] Upstream updates disabled for awz-mod; keeping local executable and data\n");
	}

	class component final : public component_interface
	{
	public:
		void post_start() override
		{
			update();
		}
	};
}

REGISTER_COMPONENT(updater::component)
