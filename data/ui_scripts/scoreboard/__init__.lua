if game:issingleplayer() then
	return
end

if Engine.IsZombiesMode() then
	game:addlocalizedstring("AWZ_MODE_STANDARD", "Standard")
	game:addlocalizedstring("AWZ_MODE_CLASSIC", "Classic")
	local function mode_name()
		local classic = game:issolo() and Engine.GetDvarInt("ui_awz_classic") == 1
		return Engine.Localize(classic and "AWZ_MODE_CLASSIC" or "AWZ_MODE_STANDARD")
	end
	local mode = mode_name()
	if Engine.InFrontend() then
		-- Capture alongside the stock round/time data. Later lobby selections must
		-- not relabel the completed match when its summary is reopened.
		local on_back_from_match = AAR.OnBackFromMatch
		AAR.OnBackFromMatch = function(...)
			on_back_from_match(...)
			mode = mode_name()
			print("[Scoreboard] Match summary mode captured: " .. mode)
		end
		local get_game_mode_name = AAR.GetGameModeName
		AAR.GetGameModeName = function(gametype)
			if gametype == "zombies" then return mode end
			return get_game_mode_name(gametype)
		end
		print("[Scoreboard] Match summary mode labels installed")
	else
		LUI.mp_hud.Scoreboard.GetZombiesHeaderString = function(duration)
			return Engine.Localize("ZOMBIES_SCOREBOARD_INFO", mode, GetMapName(),
				math.max(1, Game.GetOmnvar("ui_horde_round_number")),
				Engine.FormatTimeDaysHoursMinutesSecondsTight(duration / 1000))
		end
		print("[Scoreboard] In-game mode label: " .. mode)
	end
end

if Engine.InFrontend() then return end

function GetPartyMaxPlayers()
	return Engine.GetDvarInt("sv_maxclients")
end

local scoreboard = LUI.mp_hud.Scoreboard
scoreboard.maxPlayersOnTeam = GetTeamLimitForMaxPlayers(GetPartyMaxPlayers())

scoreboard.scoreColumns.ping = {
	width = Engine.IsZombiesMode() and 90 or 60,
	title = "LUA_MENU_PING",
	getter = function(scoreinfo)
		return scoreinfo.ping == 0 and "BOT" or tostring(scoreinfo.ping)
	end
}

local getcolumns = scoreboard.getColumnsForCurrentGameMode
scoreboard.getColumnsForCurrentGameMode = function(a1)
	local columns = getcolumns(a1)

	if (Engine.IsZombiesMode()) then
		table.insert(columns, scoreboard.scoreColumns.ping)
	end

	return columns
end
