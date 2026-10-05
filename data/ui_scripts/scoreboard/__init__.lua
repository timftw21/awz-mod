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
		local matchRanks = Engine.GetDvarString("ui_awz_match_ranks") or ""
		-- Capture alongside the stock round/time data. Later lobby selections must
		-- not relabel the completed match when its summary is reopened.
		local on_back_from_match = AAR.OnBackFromMatch
		AAR.OnBackFromMatch = function(...)
			on_back_from_match(...)
			mode = mode_name()
			matchRanks = Engine.GetDvarString("ui_awz_match_ranks") or ""
			print("[Scoreboard] Match ranks captured: " .. matchRanks)
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
			local rankWidth = 50
			page.states.default.width = page.states.default.width + width + rankWidth
			local feed_rows = page.childrenFeeder
			page.childrenFeeder = function(...)
				local rows = feed_rows(...)
				for _, row in ipairs(rows) do
					local team = row.id and row.id:match("^team([12])_root$")
					if team then
						local columns = row.children[1].children
						columns[1].states.default.right = columns[1].states.default.right + rankWidth
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
								local rank, prestige = ("," .. matchRanks):match("," .. player .. ":(%d+):(%d+),")
								local hasRank = rank ~= nil
								rank = math.max(0, math.min(Rank.GetMaxRank(), tonumber(rank) or 0))
								prestige = tonumber(prestige) or 0
								local nameCell = cells[1]
								local name = nameCell.children[1]
								local nameState = name.states.default
								local left = nameState.left
								nameCell.states.default.right = nameCell.states.default.right + rankWidth
								nameState.left = left + rankWidth
								name.properties.text = ScoreboardTruncate(name.properties.text,
									nameCell.states.default.right - nameState.left - 8, nameState.height)
								table.insert(nameCell.children, {
									type = "UIImage", id = "awz_aar_rank_icon",
									states = {default = {leftAnchor = true, rightAnchor = false, topAnchor = false, bottomAnchor = false,
										left = left, width = 26, height = 26, alpha = hasRank and 1 or 0,
										material = RegisterMaterial(Rank.GetRankIcon(rank, prestige))}}
								})
								table.insert(nameCell.children, {
									type = "UIText", id = "awz_aar_rank_number", properties = {text = hasRank and Rank.GetRankDisplay(rank) or ""},
									states = {default = {leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
										left = left + 28, width = 20, top = nameState.top, height = nameState.height,
										font = nameState.font, color = nameState.color, alignment = LUI.Alignment.Center}}
								})
								print("[Scoreboard] Match rank: player=" .. player .. "; available=" .. tostring(hasRank) .. "; level=" .. (rank + 1) .. "; prestige=" .. prestige)
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
	local baseWidth = scoreboard.baseWidth
	scoreboard.baseWidth = function(compact)
		return baseWidth(compact) + (compact and 0 or 50)
	end
	local buildRow = scoreboard.scoreboardRow
	scoreboard.scoreboardRow = function(team, index, compact, ...)
		local row = buildRow(team, index, compact, ...)
		if compact then return row end
		local name = row:getFirstDescendentById("gamertag")
		row.rankIcon = LUI.UIImage.new({leftAnchor = true, rightAnchor = false, topAnchor = false, bottomAnchor = false,
			left = 0, width = 26, height = 26})
		row.rankIcon.id = "rankIcon"
		row.rankIcon:addElementBefore(name)
		row.rankNumber = LUI.UIText.new({leftAnchor = true, rightAnchor = false, topAnchor = false, bottomAnchor = false,
			left = 0, width = 20, height = ScoreboardShared.CellFont.Height,
			font = ScoreboardShared.CellFont.Font, alignment = LUI.Alignment.Center})
		row.rankNumber.id = "rankNumber"
		row.rankNumber:addElementBefore(name)
		-- Leave room for the character, voice indicator and rank before the name.
		local setName = name.setText
		name.setText = function(element, text)
			setName(element, ScoreboardTruncate(text, scoreboard.baseWidth(false) - 120, ScoreboardShared.CellFont.Height))
		end
		row:processEvent({name = "refresh_row"})
		return row
	end
	print("[Scoreboard] Live Zombies rank icons and levels enabled")

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
