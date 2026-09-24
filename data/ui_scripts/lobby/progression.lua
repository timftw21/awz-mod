if not Engine.IsZombiesMode() then
	return
end

-- These are the persistent eggData bits written by each map's main quest.
-- Descent's 32 is the main quest; 64/128/256 track separate boss/movie progress.
local maps = {
	{ref = "mp_zombie_lab", flag = 1, intro = Zombies.IntroDLC1},
	{ref = "mp_zombie_brg", flag = 4, intro = Zombies.IntroDLC2, outro = Zombies.OutroDLC2, unlockImage = "ui_zm_story_dlc2_outro"},
	{ref = "mp_zombie_ark", flag = 8, intro = Zombies.IntroDLC3, outro = Zombies.OutroDLC3, unlockImage = "ui_zm_story_dlc3_outro"},
	{ref = "mp_zombie_h2o", flag = 32, intro = Zombies.IntroDLC4, outro = Zombies.OutroDLC4, unlockImage = "ui_zm_story_dlc4_outro"}
}
local mapsByName = {}
for _, map in ipairs(maps) do mapsByName[map.ref] = map end

local function completed(map, controller)
	local flags = Engine.GetPlayerDataReservedInt(controller, CoD.StatsGroup.Coop, "eggData")
	if flags == nil then return nil end
	return math.floor(flags / map.flag) % 2 == 1
end

game:addlocalizedstring("AWZ_STORY_INTRO", "&&1 - Intro")
game:addlocalizedstring("AWZ_STORY_OUTRO", "&&1 - Outro")
game:addlocalizedstring("AWZ_STORY_PLAY", "Watch this cinematic.")
game:addlocalizedstring("AWZ_STORY_LOCKED", "Complete the &&1 main quest to unlock this outro.")
game:addlocalizedstring("AWZ_MAIN_QUEST", "MAIN QUEST")
game:addlocalizedstring("AWZ_QUEST_COMPLETE", "COMPLETE")
game:addlocalizedstring("AWZ_QUEST_INCOMPLETE", "UNSOLVED")
game:addlocalizedstring("AWZ_QUEST_UNKNOWN", "UNSOLVED")
game:addlocalizedstring("AWZ_PERSONAL_BEST_HEADSHOTS", "Headshots")
game:addlocalizedstring("AWZ_CAREER", "CAREER")

-- Show every shipped movie, including locked endings. The original menu hides
-- later DLC behind marketing data and treats a previously viewed movie as an unlock.
-- Outbreak has an in-map helicopter ending, not a separate outro video.
LUI.MenuBuilder.m_types_build.ZombiesMoviesMenu = function(menuType, properties)
	local menu = LUI.MenuTemplate.new(menuType, {
		menu_title = "@ZOMBIES_MENU_MOVIES",
		uppercase_title = true,
		menu_width = GenericMenuDims.menu_right_standard - GenericMenuDims.menu_left
	})
	local controller = properties.exclusiveController or Engine.GetFirstActiveController()
	local function addMovie(map, movie, ending)
		local mapName = Engine.MarkLocalized(Lobby.GetMapName(map.ref))
		local lockIcon
		local function locked()
			local isLocked = ending and completed(map, controller) ~= true
			if lockIcon then lockIcon:setAlpha(isLocked and 1 or 0) end
			return isLocked
		end
		local title = Engine.Localize(ending and "AWZ_STORY_OUTRO" or "AWZ_STORY_INTRO", mapName)
		local button = menu:AddButton(Engine.MarkLocalized(title), function(element, event)
			local activeController = event.controller or controller
			if ending and completed(map, activeController) ~= true then
				print("[Zombies Progress] Blocked locked outro: " .. map.ref)
				return
			end
			print("[Zombies Progress] Playing " .. Zombies.Intros[movie] .. "; controller=" .. activeController)
			LUI.FlowManager.RequestAddMenu(menu, "zombies_intro", false, activeController, false, {
				movieIndex = movie, disableSkip = false, handleBackground = true
			})
		end, locked, nil, nil, {
			desc_text = function()
				return locked() and Engine.Localize("AWZ_STORY_LOCKED", mapName) or Engine.Localize("AWZ_STORY_PLAY")
			end
		})
		button:rename("awz_story_" .. map.ref .. (ending and "_outro" or "_intro"))
		if ending then
			lockIcon = LUI.UIImage.new({
				leftAnchor = false, rightAnchor = true, topAnchor = false, bottomAnchor = false,
				right = -12, width = 16, height = 16, material = RegisterMaterial("icon_lock_mini")
			})
			button:addElement(lockIcon)
		end
		button:setDisabledRefreshRate(500)
		print("[Zombies Progress] Story " .. map.ref .. (ending and " outro" or " intro") .. "; locked=" .. tostring(locked()))
	end
	for _, map in ipairs(maps) do
		addMovie(map, map.intro, false)
		if map.outro then addMovie(map, map.outro, true) end
	end
	menu:AddBottomDescription(7)
	menu:AddBackButton()
	return menu
end

-- Keep the stock post-match unlock notification, with the same requirement as
-- the menu. Viewed flags acknowledge the notification; they do not grant access.
function ZombiesCheckUnlockMovie()
	local controller = Engine.GetFirstActiveController()
	local map = mapsByName[AAR.GetMapRefName(controller)]
	if not map or not map.outro or completed(map, controller) ~= true then return end
	if Engine.GetIntroMovieViewed(controller, map.outro) then return end
	Engine.SetIntroMovieViewed(controller, map.outro, true)
	print("[Zombies Progress] Main quest completed; outro unlocked: " .. map.ref)
	LUI.MOTD.ShowZombiesUnlock(nil, map.outro, map.unlockImage)
end

local stockAddStats = LUI.MPLobbyBase.AddZombiesStats
-- The stock lobby reads both labels and map keys by position. Insert the
-- existing headshot best immediately after kills, then grow its four-row box.
table.insert(ZombiesLobbyStats.Labels, 4, "AWZ_PERSONAL_BEST_HEADSHOTS")
for mapName, stats in pairs(ZombiesLobbyStats.Maps) do
	local key = stats.Keys[3]:gsub("Kills", "Headshots")
	table.insert(stats.Keys, 4, key)
	print("[Zombies Progress] Personal Bests headshots: " .. mapName .. "=" .. key)
end

local stockRefreshStats = LUI.MPLobbyBase.ZombiesRefreshStats
local careerFields = {"Revives", "Kills", "Headshots", "MoneyEarned"}
LUI.MPLobbyBase.ZombiesRefreshStats = function(menu)
	if not menu.zmStatsUseDefaultMap then
		return stockRefreshStats(menu)
	end

	local controller = Engine.GetFirstActiveController()
	local values = {AAR.GetZombiesStat(controller, "highestRound") or 0}
	for index, field in ipairs(careerFields) do
		values[index + 1] = AAR.GetZombiesStat(controller, "total" .. field) or 0
	end
	for dlc = 2, 4 do
		local prefix = "dlc" .. dlc
		values[1] = math.max(values[1], Engine.GetPlayerDataReservedInt(controller, CoD.StatsGroup.Coop, prefix .. "RoundsBest") or 0)
		for index, field in ipairs(careerFields) do
			values[index + 1] = values[index + 1] + (Engine.GetPlayerDataReservedInt(controller, CoD.StatsGroup.Coop, prefix .. field) or 0)
		end
	end
	for index, value in ipairs(values) do
		menu.zmStatTexts[index]:setText(value)
	end
	local summary = controller .. ":" .. table.concat(values, ",")
	if summary ~= menu.awzCareerSummary then
		menu.awzCareerSummary = summary
		print("[Zombies Progress] Career controller:round,revives,kills,headshots,credits=" .. summary)
	end
end

LUI.MPLobbyBase.AddZombiesStats = function(menu, useDefaultMap)
	stockAddStats(menu, useDefaultMap)
	local statsPanel = menu.zmStatTexts[1]:getParent()
	local height = 124 + (#ZombiesLobbyStats.Labels - 4) * 27
	statsPanel:registerAnimationState("default", {
		leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
		left = 0, top = 0, width = GenericMenuDims.menu_right_standard - GenericMenuDims.menu_left,
		height = height
	})
	statsPanel:animateToState("default", 0)
	menu.list:setLayoutCached(false)
	print("[Zombies Progress] Personal Bests panel: " .. #ZombiesLobbyStats.Labels .. " rows; height=" .. height)
	if useDefaultMap then
		-- The menu before the lobby passes useDefaultMap. The stock header
		-- sits immediately before the spacer preceding the stats panel.
		local header = statsPanel:getPreviousSibling():getPreviousSibling()
		header:getLastChild():setText(Engine.Localize("AWZ_CAREER"))
		print("[Zombies Progress] Career panel: title=CAREER; main quest hidden")
		return
	end
	menu:AddSpacing(2)
	local row = LUI.UIElement.new({
		leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
		left = 0, top = 0, width = GenericMenuDims.menu_right_standard - GenericMenuDims.menu_left, height = 34
	})
	row.id = "awz_main_quest_status"
	row:addElement(LUI.UIImage.new({
		leftAnchor = true, rightAnchor = true, topAnchor = true, bottomAnchor = true,
		color = Colors.black, alpha = 0.75
	}))
	local font = CoD.TextSettings.TitleFontTiny
	local label = LUI.UIText.new({
		leftAnchor = true, rightAnchor = true, topAnchor = true, bottomAnchor = false,
		left = 10, right = 0, top = (34 - font.Height) / 2, height = font.Height,
		font = font.Font, alignment = LUI.Alignment.Left
	})
	label:setText(Engine.Localize("AWZ_MAIN_QUEST"))
	row:addElement(label)
	local status = LUI.UIText.new({
		leftAnchor = true, rightAnchor = true, topAnchor = true, bottomAnchor = false,
		left = 0, right = -15, top = (34 - font.Height) / 2, height = font.Height,
		font = font.Font, alignment = LUI.Alignment.Right
	})
	row:addElement(status)
	menu.list:addElement(row)
	local previous
	local function refresh()
		local mapName = Engine.GetDvarString("ui_mapname")
		if useDefaultMap then mapName = ZombiesGetNewDefaultMap() or mapName end
		local map = mapsByName[mapName]
		local controller = Engine.GetFirstActiveController()
		local done
		if map then done = completed(map, controller) end
		local state = done == nil and "UNKNOWN" or (done and "COMPLETE" or "INCOMPLETE")
		local key = tostring(controller) .. ":" .. tostring(mapName) .. ":" .. state
		if key == previous then return end
		previous = key
		local color = done and {r = 1, g = 0.78, b = 0.2} or Colors.white
		status:setText(Engine.Localize("AWZ_QUEST_" .. state))
		status:setRGB(color.r, color.g, color.b)
		print("[Zombies Progress] Local player " .. key)
	end
	row:registerEventHandler("awz_progress_refresh", refresh)
	row:registerDvarHandler("ui_mapname", refresh)
	row:addElement(LUI.UITimer.new(500, "awz_progress_refresh"))
	refresh()
end

print("[Zombies Progress] Four intros, three quest-locked outros, Personal Bests headshots and main quest status registered")
