if (game:issingleplayer() or not Engine.InFrontend()) then
	return
end

-- A Solo session survives its match; only leaving Solo (or changing mode) ends it.
if Engine.IsZombiesMode() then
	game:sololobbyready()
else
	game:endsolo()
end

require("progression")
require("solo")
require("menu_xboxlive")
require("menu_xboxlive_lobby")
