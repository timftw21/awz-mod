if game:issingleplayer() or not Engine.IsZombiesMode() then return end
if not game:zombiesprogressionavailable() then
	print("[Zombies Ranks] UI disabled: unsupported co-op profile layout")
	return
end

AWZProgression = {}
local P = AWZProgression
local tableName = "mp/awzGateChallenges.csv"
local challenges, minXP, maxXP = {}, {}, {}
local maxRank = Rank.GetMaxRank()
local maxPrestige = tonumber(Engine.TableLookup("mp/rankIconTable.csv", 0, "maxprestige", 1))
for rank = 0, maxRank do
	minXP[rank] = Rank.GetRankMinXP(rank)
	maxXP[rank] = Rank.GetRankMaxXP(rank)
end
for index = 1, 15 do
	local ref = Engine.TableLookupByRow(tableName, index, 0)
	challenges[index] = {
		ref = ref, name = Engine.TableLookupByRow(tableName, index, 1),
		desc = ref .. "_desc", gate = tonumber(Engine.TableLookupByRow(tableName, index, 6)),
		target = tonumber(Engine.TableLookupByRow(tableName, index, 9))
	}
	game:addlocalizedstring(ref .. "_desc", Engine.TableLookupByRow(tableName, index, 2))
end
game:addlocalizedstring("AWZ_RANKS", "Zombies Progression")
game:addlocalizedstring("AWZ_PROGRESSION", "PROGRESSION")
game:addlocalizedstring("AWZ_GATE_CHALLENGES", "GATE CHALLENGES")
game:addlocalizedstring("AWZ_PRESTIGE", "Enter Prestige")
game:addlocalizedstring("AWZ_PRESTIGE_CONFIRM", "Enter the next Zombies prestige? Your Zombies level returns to 1 and all Gate Challenges reset. Career totals and main quest progress are kept.")

if not Engine.InFrontend() then
	require("LUI.mp_hud.SplashesHud")
	local splashes = LUI.mp_hud.SplashesHud
	local getChallengeSplashData = splashes.GetChallengeSplashData
	-- Zombies loads this XP reward material; the generic MP challenge icon is absent.
	local notificationIcon = Cac.GetRewardImageUsingLanguage("ui_reward_xp")
	splashes.GetChallengeSplashData = function(index)
		if index >= 2000 and index < 2015 then
			local challenge = challenges[index - 1999]
			return 3500, notificationIcon, challenge.name, "Gate Challenge Complete", challenge.ref
		elseif index == 2015 then
			local amount = (Game.GetOmnvar("ui_challenge_splash_tier") - 1) * 65536 +
				Game.GetOmnvar("ui_challenge_splash_optional_number")
			print("[Zombies Ranks] BANKED XP notification; awarded=" .. amount)
			return 3500, notificationIcon, "BANKED XP", "+" .. amount .. " XP", "ch_awz_banked_xp"
		end
		return getChallengeSplashData(index)
	end
	print("[Zombies Ranks] Multiplayer challenge notifications enabled; IDs=2000..2015; icon=" .. notificationIcon)
end

local function readValue(controller, offset, bytes)
	local value, multiplier = 0, 1
	for i = 0, bytes - 1 do
		local byte = Engine.GetPlayerDataEx(controller, CoD.StatsGroup.Coop, "reserved", offset + i)
		if byte == nil then return nil end
		value = value + byte * multiplier
		multiplier = multiplier * 256
	end
	return value
end

local function writeValue(controller, offset, bytes, value)
	for i = 0, bytes - 1 do
		Engine.SetPlayerDataEx(controller, CoD.StatsGroup.Coop, "reserved", offset + i, value % 256)
		value = math.floor(value / 256)
	end
end

function P.Read(controller)
	local state = {xp = 0, bankedXP = 0, prestige = 0, rank = 0, progress = {}, gate = 0, cleared = 0, ready = true}
	local magic = readValue(controller, 256, 1)
	if magic == nil then state.ready = false end
	if magic == 167 then
		state.ready = readValue(controller, 257, 1) == 1
		state.xp = readValue(controller, 260, 4) or 0
		state.bankedXP = readValue(controller, 294, 4) or 0
		state.prestige = math.min(readValue(controller, 258, 1) or 0, maxPrestige)
	end
	for index, challenge in ipairs(challenges) do
		state.progress[index] = magic == 167 and (readValue(controller, 264 + (index - 1) * 2, 2) or 0) or 0
	end
	for gateIndex = 1, 5 do
		local done = 0
		for index = gateIndex * 3 - 2, gateIndex * 3 do
			if state.progress[index] >= challenges[index].target then done = done + 1 end
		end
		if done == 3 then
			state.cleared = state.cleared + 1
		elseif state.gate == 0 then
			state.nextGate = gateIndex * 10
			if state.xp >= minXP[state.nextGate - 1] then state.gate = state.nextGate end
			break
		end
	end
	state.xp = math.min(state.xp, state.nextGate and minXP[state.nextGate - 1] or maxXP[maxRank])
	for rank = 1, maxRank do
		if state.xp >= minXP[rank] then state.rank = rank end
	end
	state.canPrestige = state.ready and state.cleared == 5 and state.xp >= maxXP[maxRank] and state.prestige < maxPrestige
	return state
end

local function saveProgression(controller, prestige, readyToPrestige, playerLevel)
	for offset = 256, 303 do
		Engine.SetPlayerDataEx(controller, CoD.StatsGroup.Coop, "reserved", offset, 0)
	end
	Engine.SetPlayerDataEx(controller, CoD.StatsGroup.Coop, "reserved", 258, prestige)
	if readyToPrestige then
		writeValue(controller, 260, 4, maxXP[maxRank])
		for index, challenge in ipairs(challenges) do
			writeValue(controller, 264 + (index - 1) * 2, 2, challenge.target)
		end
	elseif playerLevel then
		writeValue(controller, 260, 4, minXP[playerLevel - 1])
		-- Earlier gates must be cleared or the server would lower the selected level.
		for index, challenge in ipairs(challenges) do
			if challenge.gate < playerLevel then
				writeValue(controller, 264 + (index - 1) * 2, 2, challenge.target)
			end
		end
	end
	Engine.SetPlayerDataEx(controller, CoD.StatsGroup.Coop, "reserved", 257, 1)
	Engine.SetPlayerDataEx(controller, CoD.StatsGroup.Coop, "reserved", 256, 167)
	Engine.ExecNow("uploadStats", controller)
end

function P.SetLevel(playerLevel)
	if not Engine.IsZombiesMode() or not Engine.InFrontend() then
		print("[Zombies Ranks] Return to the Zombies lobby before using awz_setlevel")
		return false
	end
	if type(playerLevel) ~= "number" or playerLevel ~= math.floor(playerLevel) or playerLevel < 1 or playerLevel > maxRank + 1 then
		print("[Zombies Ranks] Usage: awz_setlevel <1-" .. (maxRank + 1) .. ">")
		return false
	end
	local controller = Engine.GetFirstActiveController()
	local state = P.Read(controller)
	if not state.ready then
		print("[Zombies Ranks] Set level rejected: co-op profile unavailable or unsupported")
		return false
	end
	saveProgression(controller, state.prestige, false, playerLevel)
	print("[Zombies Ranks] Set level: " .. (state.rank + 1) .. " -> " .. playerLevel ..
		"; prestige=" .. state.prestige .. "; earlier gates cleared; current/later gates and banked XP reset; profile save requested")
	return true
end

function P.Reset()
	-- A live server owns the in-match counters and would overwrite a local reset.
	if not Engine.IsZombiesMode() or not Engine.InFrontend() then
		print("[Zombies Ranks] Return to the Zombies lobby before using awz_resetprogression")
		return
	end
	local controller = Engine.GetFirstActiveController()
	local state = P.Read(controller)
	if not state.ready then
		print("[Zombies Ranks] Reset rejected: co-op profile unavailable or unsupported")
		return
	end
	saveProgression(controller, 0)
	print("[Zombies Ranks] Reset progression: level=" .. (state.rank + 1) .. " prestige=" .. state.prestige ..
		" xp=" .. state.xp .. " -> level=1 prestige=0 xp=0; all Gate Challenges reset; profile save requested")
end

local function enterPrestige(controller, skipRequirements)
	if not Engine.IsZombiesMode() or not Engine.InFrontend() then
		print("[Zombies Ranks] Return to the Zombies lobby before entering prestige")
		return false
	end
	local state = P.Read(controller)
	if not state.ready or state.prestige >= maxPrestige or (not skipRequirements and not state.canPrestige) then
		print("[Zombies Ranks] Prestige rejected: profile unavailable, maximum prestige, or unmet requirements")
		return false
	end
	saveProgression(controller, state.prestige + 1)
	print("[Zombies Ranks] Entered prestige " .. (state.prestige + 1) .. "; skip requirements=" .. tostring(skipRequirements) ..
		"; Zombies XP and gates reset; profile save requested")
	return true
end

function P.Prestige()
	return enterPrestige(Engine.GetFirstActiveController(), true)
end

function P.ReadyToPrestige()
	if not Engine.IsZombiesMode() or not Engine.InFrontend() then
		print("[Zombies Ranks] Return to the Zombies lobby before using awz_readytoprestige")
		return false
	end
	local controller = Engine.GetFirstActiveController()
	local state = P.Read(controller)
	if not state.ready or state.prestige >= maxPrestige then
		print("[Zombies Ranks] Prestige preparation rejected: profile unavailable, unsupported, or maximum prestige")
		return false
	end
	-- Meet the real requirements so the menu and confirmation use their normal path.
	saveProgression(controller, state.prestige, true)
	print("[Zombies Ranks] Ready to prestige: level=" .. (maxRank + 1) .. "; prestige=" .. state.prestige ..
		"; XP filled and all 15 Gate Challenges complete; select ENTER PRESTIGE in PROGRESSION; profile save requested")
	return true
end

local function rankText(state)
	return "LEVEL " .. (state.rank + 1) .. "  |  PRESTIGE " .. state.prestige
end

local function statusText(state)
	if not state.ready then return "Waiting for player profile" end
	if state.gate > 0 then return "GATE " .. state.gate .. "  |  " .. state.bankedXP .. " BANKED XP" end
	if state.canPrestige then return "READY TO PRESTIGE" end
	if state.xp >= maxXP[maxRank] then return "MAXIMUM RANK" end
	return (state.xp - minXP[state.rank]) .. " / " .. (maxXP[state.rank] - minXP[state.rank]) .. " XP"
end

local function textElement(parent, id, left, top, width, text, height, alignment, font)
	local element = LUI.UIText.new({
		leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
		left = left, top = top, width = width, height = height or 20,
		font = font or CoD.TextSettings.TitleFontSmall.Font, alignment = alignment or LUI.Alignment.Left
	})
	element.id = id
	element:setText(text)
	parent:addElement(element)
	return element
end

local function backing(parent, x, y, width, height)
	parent:addElement(LUI.UIImage.new({
		leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
		left = x, top = y, width = width, height = height,
		material = RegisterMaterial("white"), color = Colors.black, alpha = 0.7
	}))
end

local function gateCards(parent, width, state, gate, compact)
	local height = compact and 92 or 124
	local imageSize = compact and 50 or 80
	local textLeft = compact and 68 or 100
	local textWidth = width - textLeft - 16
	local completed = 0
	for slot = 1, 3 do
		local index = (gate / 10 - 1) * 3 + slot
		local challenge = challenges[index]
		local progress = math.min(state.progress[index], challenge.target)
		local complete = progress >= challenge.target
		local locked = state.rank + 1 < gate
		if complete then completed = completed + 1 end
		local top = (slot - 1) * (height + 8)
		-- Multiplayer's badge, frame and progress bar, shared by both menus.
		-- These are display cards: button hover events must not restore old text sizes.
		local card = LUI.UIElement.new(CoD.CreateState(0, top, width, top + height, CoD.AnchorTypes.TopLeft))
		card.id = "awz_gate_card_" .. slot
		backing(card, 0, 0, width, height)
		card:addElement(LUI.UIBackgroundPanel.new(CoD.CreateState(0, 0, 0, 0, CoD.AnchorTypes.All)))
		card:addElement(LUI.UIImage.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = 5, top = 5, width = imageSize, height = imageSize,
			material = RegisterMaterial(Cac.GetRewardImageUsingLanguage("ui_reward_xp")), alpha = locked and 0.25 or 1}))
		if locked then
			card:addElement(LUI.UIImage.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
				left = 5 + imageSize / 4, top = 5 + imageSize / 4, width = imageSize / 2, height = imageSize / 2,
				material = RegisterMaterial("s1_icon_locked_full")}))
		end
		textElement(card, "challenge_text", textLeft, compact and 7 or 10, textWidth, challenge.name, compact and 17 or 20)
		-- S1 sets fonts through animation states; UIText has no setFont method.
		textElement(card, "challenge_desc_element_id", textLeft, compact and 29 or 36, textWidth,
			Engine.Localize(challenge.desc, challenge.target), compact and 14 or 17, nil, CoD.TextSettings.TitleFontTiny.Font)
		local gateLabel = textElement(card, "challenge_xp_text_id", 5, height - 26, imageSize, "GATE " .. gate,
			compact and 13 or 16, LUI.Alignment.Center)
		gateLabel:setRGB(Colors.s1.text_focused.r, Colors.s1.text_focused.g, Colors.s1.text_focused.b)
		local statusTop = compact and 63 or 82
		local status = textElement(card, "challenge_status_text_id", textLeft, statusTop, textWidth - 112,
			complete and "COMPLETE" or (locked and "REACH LEVEL " .. gate or "IN PROGRESS"), compact and 13 or 16)
		local color = complete and Colors.green or (locked and Colors.red or Colors.white)
		status:setRGB(color.r, color.g, color.b)
		textElement(card, "challenge_progress_text_id", width - 120, statusTop, 104,
			progress .. " / " .. challenge.target, compact and 13 or 16, LUI.Alignment.Right)
		local bar = LUI.UIElement.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = textLeft, top = compact and 83 or 108, width = textWidth, height = 6})
		bar.id = "challenge_progress_container"
		bar:addElement(LUI.UIBorder.new({leftAnchor = true, rightAnchor = true, topAnchor = true, bottomAnchor = true,
			left = 0, top = 0, right = 0, bottom = 0, borderThickness = 1, color = Colors.white, alpha = 0.3}))
		bar:addElement(LUI.UIImage.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = true,
			left = 1, top = 1, bottom = -1, width = (textWidth - 2) * progress / challenge.target,
			material = RegisterMaterial("white"), color = Colors.grey_5}))
		card:addElement(bar)
		card:addElement(LUI.UIBorder.new({leftAnchor = true, rightAnchor = true, topAnchor = true, bottomAnchor = true,
			left = 0, top = 0, right = 0, bottom = 0, borderThickness = 1, color = Colors.white, alpha = 0.6}))
		parent:addElement(card)
	end
	print("[Zombies Ranks] Gate cards built: gate=" .. gate .. "; compact=" .. tostring(compact) .. "; complete=" .. completed .. "/3")
	return completed
end

local function refreshTimer(parent, event, callback, interval)
	parent:registerEventHandler(event, callback)
	local id = event .. "_timer"
	-- Networked rows run postBuildHandler again on the same element when refreshed.
	-- Own one named timer per element; leave the game's other timers intact.
	if not parent:getChildById(id) then
		local timer = LUI.UITimer.new(interval or 500, event)
		timer.id = id
		parent:addElement(timer)
		print("[Zombies Ranks] Refresh timer attached: " .. id .. "; element=" .. tostring(parent.id))
	end
end

if Engine.InFrontend() then
	local function updateMemberRank(properties)
		local visible = properties.isActiveMemberSlot and not properties.isNonPlayingLocalClient
		if visible and properties.isLocalMember then
			local controller = properties.awzSoloController
			if controller == nil then
				controller = Lobby.GetMemberControllerIndex(properties.memberListState, properties.slot, properties.team)
			end
			local state = P.Read(controller or Engine.GetFirstActiveController())
			visible = state.ready
			properties.memberRank = Rank.GetRankDisplay(state.rank)
			properties.memberRankIcon = RegisterMaterial(Rank.GetRankIcon(state.rank, state.prestige,
				Rank.GetCustomRankIcons(state.prestige, state.xp)))
			properties.awzRankKey = state.rank .. ":" .. state.prestige .. ":" .. tostring(state.ready)
		end
		return visible
	end

	local function refreshMemberRank(row)
		local properties = row.properties
		local visible = updateMemberRank(properties)
		local rank = row:getFirstDescendentById("memberListButton_memberRank")
		local icon = row:getFirstDescendentById("memberListButton_rankIcon")
		if properties.isLocalMember then
			local key = tostring(properties.awzRankKey) .. ":" .. tostring(visible)
			if row.awzRankSignature ~= key then
				row.awzRankSignature = key
				print("[Zombies Ranks] Lobby co-op rank refreshed: level=" .. tostring(properties.memberRank) .. "; visible=" .. tostring(visible))
			end
		end
		rank:setAlpha(visible and 1 or 0)
		icon:setAlpha(visible and 1 or 0)
		if visible then
			rank:setText(properties.memberRank)
			icon:registerAnimationState("default", {material = properties.memberRankIcon, alpha = 1})
			icon:setImage(properties.memberRankIcon)
		end
	end

	-- Zombies disables these stock multiplayer fields and removes their name spacing.
	-- Restore them in the shared row so online, private and Solo use the same layout.
	local memberButton = LUI.MenuBuilder.m_definitions.memberListButton
	LUI.MenuBuilder.m_definitions.memberListButton = function(...)
		local definition = memberButton(...)
		local function child(children, id)
			for _, element in ipairs(children) do
				if element.id == id then return element end
			end
		end
		local icon = child(definition.children, "memberListButton_rankIcon")
		local text = child(definition.children, "memberListButton_textContainer")
		local rank = child(text.children, "memberListButton_memberRank")
		local name = child(text.children, "memberListButton_gamerTag")
		-- LUI dispatches member_slot_refresh to children before the parent handler.
		-- Bind co-op rank data before the icon/text handlers can apply MP values.
		icon.states.default.material = {isProperty = true, func = function(properties)
			updateMemberRank(properties)
			return properties.memberRankIcon
		end}
		rank.properties.text = {isProperty = true, func = function(properties)
			updateMemberRank(properties)
			return properties.memberRank
		end}
		for _, element in ipairs({icon, rank}) do
			local refresh = element.handlers.member_slot_refresh
			element.handlers.member_slot_refresh = function(child, event)
				updateMemberRank(event.memberButton.properties)
				return refresh(child, event)
			end
		end
		local iconWidth = definition.properties.buttonHeight
		definition.properties.hasRank = 1
		icon.states.default.alpha = 1
		icon.states.default.width = iconWidth
		rank.states.default.alpha = 1
		rank.states.default.left = S1MenuDims.menu_padding + iconWidth
		for _, stateName in ipairs({"default", "local_player", "private_party"}) do
			name.states[stateName].left = rank.states.default.left + rank.states.default.width + 8
		end
		-- The Zombies ready check used to occupy the now-visible rank icon's slot.
		for _, element in ipairs(definition.children) do
			if element.postBuildHandler == LUI.mp_menus.s1MPMemberList.buildMemberButtonReadyUpIndicator then
				local state = element.states.default
				state.leftAnchor, state.rightAnchor = false, true
				state.left, state.right = nil, -S1MenuDims.menu_padding
				text.states.default.right = -(state.width + S1MenuDims.menu_padding * 2)
			end
		end
		local postBuild = definition.postBuildHandler
		definition.postBuildHandler = function(row)
			postBuild(row)
			refreshTimer(row, "awz_member_rank", refreshMemberRank)
			refreshMemberRank(row)
		end
		local refresh = definition.handlers.member_slot_refresh
		definition.handlers.member_slot_refresh = function(row, event)
			refreshMemberRank(row)
			return refresh(row, event)
		end
		return definition
	end

	function P.AddLobbyButton(menu)
		if not menu.awzRankButton then
			menu.awzRankButton = menu:AddButton("@AWZ_PROGRESSION", "awz_progression")
		end
	end

	LUI.MenuBuilder.registerDef("awz_prestige_confirm", function()
		return {
			type = "generic_yesno_popup", id = "awz_prestige_confirm",
			properties = {
				message_text = Engine.Localize("AWZ_PRESTIGE_CONFIRM"),
				popup_title = Engine.Localize("AWZ_PRESTIGE"),
				yes_text = Engine.Localize("MENU_PRESTIGE_ENTER"), no_text = Engine.Localize("LUA_MENU_CANCEL"),
				yes_action = function(element, event)
					local controller = event.controller or Engine.GetFirstActiveController()
					enterPrestige(controller, false)
				end
			}
		}
	end)

	LUI.MenuBuilder.registerType("awz_progression", function(menuType, properties)
		local controller = properties.exclusiveController or Engine.GetFirstActiveController()
		local menuWidth = CoD.DesignGridHelper(6, 1)
		local menu = LUI.MenuTemplate.new(menuType, {
			menu_title = "@AWZ_RANKS", uppercase_title = true, menu_width = menuWidth
		})
		local left = menuWidth + DesignGridDims.horz_gutter
		local top = LUI.MenuTemplate.ListTop
		local width = CoD.DesignGridHelper(17, 1)
		backing(menu, left, top, width, 78)
		local icon = LUI.UIImage.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = left + 12, top = top + 12, width = 52, height = 52})
		menu:addElement(icon)
		local title = textElement(menu, "awz_rank_title", left + 80, top + 12, width - 96, "")
		local status = textElement(menu, "awz_rank_status", left + 80, top + 42, width - 96, "", 17)
		backing(menu, left, top + 90, width, 36)
		local gateTitle = textElement(menu, "awz_gate_title", left + 12, top + 98, width - 24, "", 18)
		local panel = LUI.UIElement.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = left, top = top + 136, width = width, height = 392})
		menu:addElement(panel)
		local selected = P.Read(controller).nextGate or 50
		local signature
		local function refresh(force)
			local state = P.Read(controller)
			local key = selected .. ":" .. state.xp .. ":" .. state.prestige .. ":" .. tostring(state.ready) .. ":" .. table.concat(state.progress, ",")
			if not force and signature == key then return end
			signature = key
			title:setText(rankText(state))
			status:setText(statusText(state))
			icon:setImage(RegisterMaterial(Rank.GetRankIcon(state.rank, state.prestige, Rank.GetCustomRankIcons(state.prestige, state.xp))))
			panel:closeChildren()
			local completed = gateCards(panel, width, state, selected, false)
			gateTitle:setText("LEVEL " .. selected .. " GATE   |   " .. completed .. " / 3 COMPLETE")
		end
		for gate = 10, 50, 10 do
			local gateLevel = gate
			menu:AddButton(Engine.MarkLocalized("Level " .. gateLevel .. " Gate"), function()
				selected = gateLevel
				refresh(true)
			end, nil, nil, nil, {button_over_func = function() selected = gateLevel; refresh(true) end})
		end
		local prestige = menu:AddButton("@AWZ_PRESTIGE", function(element, event)
			LUI.FlowManager.RequestPopupMenu(element, "awz_prestige_confirm", false, event.controller or controller)
		end, function() return not P.Read(controller).canPrestige end)
		prestige:setDisabledRefreshRate(500)
		-- Keep wrapped instructions inside the left column, after every menu button.
		local notesTop = top + menu.list.buttonCount * LUI.MenuTemplate.ButtonStyle.height + 14
		local notes = LUI.UIElement.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = 0, top = notesTop, width = menuWidth, height = 1})
		menu:addElement(notes)
		local rules = {
			{"GATE CHALLENGES", "XP is banked at each gate and awarded when all three challenges are complete. Banked XP and challenge progress carry across matches."},
			{"PRESTIGE", "Clear all five gates and fill level 50 to prestige. Your level and Gate Challenges reset each prestige."}
		}
		local y = 12
		local positions = {}
		for index, rule in ipairs(rules) do
			positions[index] = y
			local _, bottom, _, textTop = GetTextDimensions(rule[2], CoD.TextSettings.TitleFontSmall.Font, 16, menuWidth - 24)
			y = y + 28 + math.max(16, bottom - textTop) + 16
		end
		backing(notes, 0, 0, menuWidth, y)
		notes:setTopBottom(true, false, notesTop, notesTop + y)
		for index, rule in ipairs(rules) do
			textElement(notes, "awz_rules_title_" .. index, 12, positions[index], menuWidth - 24, rule[1], 18)
			textElement(notes, "awz_rules_" .. index, 12, positions[index] + 28, menuWidth - 24, rule[2], 16)
		end
		menu:AddBackButton()
		refreshTimer(menu, "awz_ranks_refresh", function() refresh(false) end)
		refresh(true)
		print("[Zombies Ranks] Progression menu opened; controller=" .. controller .. "; card width=" .. width .. "; help top=" .. notesTop)
		return menu
	end)

	local addStats = LUI.MPLobbyBase.AddZombiesStats
	LUI.MPLobbyBase.AddZombiesStats = function(menu, ...)
		P.AddLobbyButton(menu)
		return addStats(menu, ...)
	end
else
	local buildPause = LUI.MenuBuilder.m_types_build.mp_pause_menu
	LUI.MenuBuilder.m_types_build.mp_pause_menu = function(menuType, properties)
		local menu = buildPause(menuType, properties)
		local map = menu:getFirstDescendentById("map_Id")
		if map then
			-- Move the title, map and its markers together, keeping the stock dimensions.
			local state = map:getAnimationStateInC("default")
			state.left = state.left + DesignGridDims.grid_width
			state.right = state.right + DesignGridDims.grid_width
			map:registerAnimationState("default", state)
			map:animateToState("default")
			print("[Zombies Ranks] Pause map shifted right by " .. DesignGridDims.grid_width .. "; stock size preserved")
		end
		local controller = properties and properties.exclusiveController or Engine.GetFirstActiveController()
		local width = CoD.DesignGridHelper(12, 1)
		local top = LUI.MenuTemplate.ListTop + menu.list.buttonCount * LUI.MenuTemplate.ButtonStyle.height + 14
		local panel = LUI.UIElement.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = 0, top = top, width = width, height = 384})
		panel.id = "awz_pause_progression"
		menu:addElement(panel)
		backing(panel, 0, 0, width, 54)
		local icon = LUI.UIImage.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = 8, top = 7, width = 40, height = 40})
		panel:addElement(icon)
		local title = textElement(panel, "awz_pause_rank", 62, 6, width - 76, "", 18)
		local status = textElement(panel, "awz_pause_xp", 62, 32, width - 76, "", 15)
		backing(panel, 0, 60, width, 26)
		local gateTitle = textElement(panel, "awz_pause_gate", 10, 64, width - 20, "", 16)
		local cards = LUI.UIElement.new({leftAnchor = true, rightAnchor = false, topAnchor = true, bottomAnchor = false,
			left = 0, top = 92, width = width, height = 292})
		panel:addElement(cards)
		local signature
		local function refresh()
			local state = P.Read(controller)
			local key = state.xp .. ":" .. state.prestige .. ":" .. tostring(state.ready) .. ":" .. table.concat(state.progress, ",")
			if signature == key then return end
			signature = key
			title:setText(rankText(state))
			status:setText(statusText(state))
			icon:setImage(RegisterMaterial(Rank.GetRankIcon(state.rank, state.prestige, Rank.GetCustomRankIcons(state.prestige, state.xp))))
			cards:closeChildren()
			local gate = state.nextGate
			if gate then
				local completed = gateCards(cards, width, state, gate, true)
				gateTitle:setText((state.gate > 0 and "ACTIVE" or "UPCOMING") .. " GATE " .. gate .. "  |  " .. completed .. " / 3 COMPLETE")
			else
				gateTitle:setText("ALL GATES COMPLETE")
				local message = state.canPrestige and "Return to the lobby to enter Prestige." or "Fill level 50 to enter Prestige from the lobby."
				if state.prestige == maxPrestige and state.xp >= maxXP[maxRank] then message = "Maximum Zombies prestige reached." end
				textElement(cards, "awz_prestige_status", 10, 8, width - 20, message, 16)
			end
		end
		refreshTimer(panel, "awz_pause_progression_refresh", refresh)
		refresh()
		print("[Zombies Ranks] Pause progression below buttons; top=" .. top .. "; bottom=" .. (top + 384) ..
			"; shared Gate Challenge cards; map spacing enabled")
		return menu
	end

	local lastSaved = {}
	local function attach(root)
		-- Saving is independent of visible UI; no progression overlay is added to gameplay.
		refreshTimer(root, "awz_progression_checkpoint", function()
			local controller = Engine.GetFirstActiveController()
			local state = P.Read(controller)
			if state.ready then
				local key = state.xp .. ":" .. state.bankedXP .. ":" .. state.prestige .. ":" .. table.concat(state.progress, ",")
				if key ~= lastSaved[controller] then
					lastSaved[controller] = key
					Engine.Exec("uploadStats", controller)
					print("[Zombies Ranks] Requested profile checkpoint; " .. rankText(state) .. "; xp=" .. state.xp .. "; banked=" .. state.bankedXP)
				end
			end
		end, 30000)
	end
	local newRoot = LUI.UIRoot.new
	LUI.UIRoot.new = function(...)
		local root = newRoot(...)
		attach(root)
		return root
	end
	for _, root in pairs(LUI.roots) do attach(root) end
end

print("[Zombies Ranks] Co-op progression UI registered; MP rank icons and challenge cards enabled")
