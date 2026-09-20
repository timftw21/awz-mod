#pragma once

namespace solo
{
	bool active();
	bool begin();
	void leave();
	void lobby_ready();
	bool map_available(const std::string& map);
	bool start(const std::string& map);
}
