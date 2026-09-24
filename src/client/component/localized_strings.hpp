#pragma once

namespace game
{
	union XAssetHeader;
}

namespace localized_strings
{
	void override(const std::string& key, const std::string& value);
	game::XAssetHeader override_zombies_hint(const char* name, game::XAssetHeader asset);
}
