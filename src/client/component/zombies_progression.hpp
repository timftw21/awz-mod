#pragma once

namespace zombies_progression
{
	game::StringTable* challenge_table(const char* name);
	game::StringTable* notification_table(const char* name, game::StringTable* stock);
	void extend_profile(game::XAssetHeader asset);
	bool available();
}
