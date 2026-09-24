if game:issingleplayer() then
	return
end

if Engine.IsZombiesMode() then
	game:addlocalizedstring("AWZ_MODE_STANDARD", "Standard")
	game:addlocalizedstring("AWZ_MODE_CLASSIC", "Classic")
	game:addlocalizedstring("AWZ_HEADSHOTS", "HEADSHOTS")
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
		local build_page = LUI.MenuBuilder.m_definitions.mp_scoreboard_page
		LUI.MenuBuilder.m_definitions.mp_scoreboard_page = function(...)
			local page = build_page(...)
			local title = Engine.Localize("AWZ_HEADSHOTS")
			local left, _, right = GetTextDimensions(title, ScoreboardShared.HeaderFont.Font,
				ScoreboardShared.HeaderFont.Height)
			local width = math.max(90, right - left + 55)
			page.states.default.width = page.states.default.width + width
			local feed_rows = page.childrenFeeder
			page.childrenFeeder = function(...)
				local rows = feed_rows(...)
				for _, row in ipairs(rows) do
					local team = row.id and row.id:match("^team([12])_root$")
					if team then
						local columns = row.children[1].children
						local header = LUI.mp_menus.AARScoreboard.CreateScoreBoardHeaderCell(3, width, team == "2")
						header.id = "scoreboard_header_headshots"
						header.children[2].properties.text = title
						table.insert(columns, 3, header)
					else
						local player = row.id and row.id:match("^scoreboard_line_(%d+)$")
						if player then
							local list = row.children[#row.children]
							local feed_cells = list.childrenFeeder
							list.childrenFeeder = function(...)
								local cells = feed_cells(...)
								local value = AAR.GetPlayerStat(tonumber(player), "headshots") or 0
								table.insert(cells, 3, LUI.mp_menus.AARScoreboard.CreateScoreBoardEntryCell(
									"headshots_" .. player, tostring(value), width))
								return cells
							end
						end
					end
				end
				return rows
			end
			print("[Scoreboard] After-action Zombies headshot column registered")
			return page
		end
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

if Engine.IsZombiesMode() then
	local previous_snapshot
	scoreboard.scoreColumns.zm_headshots = {
		width = 90,
		title = "AWZ_HEADSHOTS",
		getter = function(scoreinfo)
			local snapshot = Engine.GetDvarString("ui_awz_headshots") or ""
			if snapshot ~= previous_snapshot then
				previous_snapshot = snapshot
				print("[Scoreboard] Received live headshots: " .. snapshot)
			end
			return ("," .. snapshot):match("," .. scoreinfo.client .. ":(%d+),") or "0"
		end
	}
	print("[Scoreboard] Live Zombies headshot column registered")
end

local getcolumns = scoreboard.getColumnsForCurrentGameMode
scoreboard.getColumnsForCurrentGameMode = function(a1)
	local columns = getcolumns(a1)

	if (Engine.IsZombiesMode()) then
		table.insert(columns, 2, scoreboard.scoreColumns.zm_headshots)
		table.insert(columns, scoreboard.scoreColumns.ping)
	end

	return columns
end
