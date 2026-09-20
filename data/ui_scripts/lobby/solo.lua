if not Engine.IsZombiesMode() then
	return
end

AWZSolo = {}
game:addlocalizedstring("AWZ_SOLO", "Solo")
game:addlocalizedstring("AWZ_CHANGE_MAP", "Change Map")
game:addlocalizedstring("AWZ_CHANGE_MODE", "Change Mode")
game:addlocalizedstring("AWZ_MODE_DETAILS", "MODE DETAILS")
game:addlocalizedstring("AWZ_MODE_STANDARD", "Standard")
game:addlocalizedstring("AWZ_MODE_CLASSIC", "Classic")
game:addlocalizedstring("AWZ_MODE_STANDARD_DESC", "Exo Zombies with the current awz-mod balance changes. Equip an Exo Suit, buy perks, and face the full range of enemies and special rounds. Upgrade weapons through nine purchases to Mk 10. Easter eggs are enabled.")
game:addlocalizedstring("AWZ_MODE_CLASSIC_DESC", "Start with the 1911. Regular zombies and dogs, with slower sprints. No Exo Suit, Slam, orbital drops, or Easter eggs. Self-revive removes all perks. Upgrade to Mk 5, then Mk 10 for 5,000 credits each.")
game:addlocalizedstring("AWZ_CHARACTER_SELECT", "CHARACTER SELECT")

local intros = {
	mp_zombie_lab = Zombies.IntroDLC1,
	mp_zombie_brg = Zombies.IntroDLC2,
	mp_zombie_ark = Zombies.IntroDLC3,
	mp_zombie_h2o = Zombies.IntroDLC4
}

local map_order = {"mp_zombie_lab", "mp_zombie_brg", "mp_zombie_ark", "mp_zombie_h2o"}

local function selected_character()
	local index = Engine.GetDvarInt("ui_awz_solo_character") or 0
	if index < 0 or index > 3 then index = 0 end
	return index
end

local function child_definition(children, id)
	for _, child in ipairs(children) do
		if child.id == id then return child end
	end
	error("[Solo] Missing stock UI definition: " .. id)
end

local function size_details(panel, details, description_state, description, padding)
	local _, text_bottom, _, text_top = GetTextDimensions(description, description_state.font, description_state.height, description_state.width)
	local height = description_state.top + math.max(description_state.height, text_bottom - text_top) + padding
	details.states.default.height = height
	panel:registerAnimationState("default", details.states.default)
	panel:animateToState("default", 0)
	return height
end

LUI.MenuBuilder.registerType("awz_solo_modes", function(menu_type)
	local menu = LUI.MenuTemplate.new(menu_type, {
		menu_title = "@AWZ_CHANGE_MODE", uppercase_title = true,
		menu_width = CoD.DesignGridHelper(6, 1)
	})
	-- Reuse the map-details panel's title bar, backing and text styling.
	local details = LUI.MenuBuilder.m_definitions["mapsetup_details_window"]()
	details.states.default.top = LUI.MenuTemplate.ListTop
	details.states.default.left = CoD.DesignGridHelper(6, 1) + DesignGridDims.horz_gutter
	local heading = child_definition(details.children, "mapsetup_details_title")
	heading.properties.title_bar_text = Engine.Localize("AWZ_MODE_DETAILS")
	local title = child_definition(details.children, "mapsetup_mapname")
	local description = child_definition(details.children, "mapsetup_mapdesc")
	local padding = child_definition(details.children, "mapsetup_mapimage").states.default.left
	title.states.default.top = GenericTitleBarDims.TitleBarHeight + padding
	description.states.default.top = title.states.default.top + title.states.default.height + description.states.default.height
	details.children = {heading, child_definition(details.children, "mapsetup_details_window_bg"), title, description}
	local panel = LUI.MenuBuilder.BuildAddChild(menu, details)
	local modes = {"STANDARD", "CLASSIC"}
	local function preview(index)
		local key = "AWZ_MODE_" .. modes[index + 1]
		local text = Engine.Localize(key .. "_DESC")
		panel:getFirstDescendentById("mapsetup_mapname"):setText(Engine.ToUpperCase(Engine.Localize(key)))
		panel:getFirstDescendentById("mapsetup_mapdesc"):setText(text)
		local height = size_details(panel, details, description.states.default, text, padding)
		print("[Solo] Mode details: " .. modes[index + 1] .. "; characters=" .. #text .. "; panel height=" .. height)
	end
	for index, mode in ipairs(modes) do
		menu:AddButton("@AWZ_MODE_" .. mode, function(element)
			Engine.SetDvarInt("ui_awz_classic", index - 1)
			print("[Solo] Mode selected: " .. mode)
			LUI.FlowManager.RequestLeaveMenu(element)
		end, nil, true, nil, {button_over_func = function() preview(index - 1) end})
	end
	local selected = Engine.GetDvarInt("ui_awz_classic") == 1 and 1 or 0
	preview(selected)
	menu:AddBackButton()
	print("[Solo] Mode selector ready; selected=" .. modes[selected + 1])
	return menu
end)

local function add_player_list(menu)
	-- Keep the stock header, backing and local-player name styling, but supply
	-- our one local player directly: the networked feeder requires a party.
	local screen = LUI.MenuBuilder.m_definitions["MpLobbyMemberScreen"]()
	local header = child_definition(screen.childrenFeeder({}), "memberscreen_list_header")
	local label = header.children[1]
	label.postBuildHandler = nil
	label.properties = {text = Engine.Localize("MENU_LOBBYPLAYERCOUNT", 1, 1)}

	local row = LUI.MenuBuilder.m_definitions["memberListButton"]()
	local background = child_definition(row.children, "memberListButton_background")
	local text = child_definition(row.children, "memberListButton_textContainer")
	local name = child_definition(text.children, "memberListButton_gamerTag")
	name.handlers = nil
	name.postBuildHandler = nil
	name.properties = {text = Engine.GetUsernameByController(Engine.GetFirstActiveController())}
	name.states.default = name.states.local_player
	text.children = {name}
	row.type = "UIElement"
	row.handlers = nil
	row.postBuildHandler = nil
	row.children = {background, text}
	row.states.default.top = header.states.default.height
	row.states.default.bottom = row.states.default.top + row.properties.buttonHeight
	screen.type = "UIElement"
	screen.handlers = nil
	screen.childrenFeeder = nil
	screen.children = {header, row}
	local list = LUI.MenuBuilder.BuildAddChild(menu, screen, true)
	-- Match the scoreboard's 40px portrait, immediately outside the name row.
	local icon = LUI.UIImage.new({
		leftAnchor = true, rightAnchor = false, topAnchor = false, bottomAnchor = false,
		left = -48, width = 40, height = 40
	})
	icon.id = "awz_solo_character_icon"
	list:getFirstDescendentById("memberListButton"):addElement(icon)
	local function refresh_character()
		local icons = GetZombiesCharIcons(Engine.GetDvarString("ui_mapname"))
		icon:setImage(RegisterMaterial(icons[selected_character() + 1]))
	end
	menu:addEventHandler("gain_focus", refresh_character)
	refresh_character()
	print("[Solo] Local player list ready; players=1/1")
end

LUI.MenuBuilder.registerType("awz_solo_characters", function(menu_type)
	local menu = LUI.MenuTemplate.new(menu_type, {
		menu_title = "@AWZ_CHARACTER_SELECT",
		uppercase_title = true,
		menu_width = CoD.DesignGridHelper(6, 1)
	})
	local map = Engine.GetDvarString("ui_mapname")
	local later_map = map == "mp_zombie_ark" or map == "mp_zombie_h2o"
	for index, name in ipairs({"Decker", "Kahn", "Lilith", later_map and "Lennox" or "Oz"}) do
		menu:AddButton(Engine.MarkLocalized(name), function(element)
			Engine.SetDvarInt("ui_awz_solo_character", index - 1)
			print("[Solo] Character selected: " .. name .. "; index=" .. (index - 1) .. "; map=" .. map)
			LUI.FlowManager.RequestLeaveMenu(element)
		end)
	end
	add_player_list(menu)
	menu:AddBackButton()
	return menu
end)

-- The multiplayer selector queries party-owned map-rotation data even with
-- rotationAllowed=false. Solo has no party: select the map directly instead.
LUI.MenuBuilder.registerType("awz_solo_maps", function(menu_type)
	local menu = LUI.MenuTemplate.new(menu_type, {
		menu_title = "@LUA_MENU_MAP_SELECT_CAPS",
		uppercase_title = true,
		menu_width = CoD.DesignGridHelper(6, 1)
	})
	local details = LUI.MenuBuilder.m_definitions["mapsetup_details_window"]()
	details.states.default.top = LUI.MenuTemplate.ListTop
	details.states.default.left = CoD.DesignGridHelper(6, 1) + DesignGridDims.horz_gutter
	local title_state = child_definition(details.children, "mapsetup_mapname").states.default
	local description_state = child_definition(details.children, "mapsetup_mapdesc").states.default
	local padding = child_definition(details.children, "mapsetup_mapimage").states.default.left
	description_state.top = title_state.top + title_state.height + description_state.height
	local panel = LUI.MenuBuilder.BuildAddChild(menu, details)
	-- The map feeder reads arena metadata, not party-owned rotation data.
	Engine.SetDvarBool("ui_showDLCMaps", true)
	local indices = {}
	for index = 0, Lobby.GetMapFeederCount() - 1 do
		indices[Lobby.GetMapLoadNameByIndex(index)] = index
	end
	local previewed_map
	local function preview(map)
		if previewed_map == map then return end
		previewed_map = map
		local index = indices[map]
		local description = index and Engine.Localize(Lobby.GetMapDescByIndex(index)) or ""
		description = description:gsub("%s+", " "):match("^%s*(.-)%s*$")
		panel:getFirstDescendentById("mapsetup_mapname"):setText(Engine.ToUpperCase(Lobby.GetMapName(map)))
		panel:getFirstDescendentById("mapsetup_mapdesc"):setText(description)
		-- Measure wrapped text as stock menus do; retain the panel's image inset below it.
		local height = size_details(panel, details, description_state, description, padding)
		panel:getFirstDescendentById("mapsetup_mapimage"):setImage(RegisterMaterial(index and Lobby.GetMapImageByIndex(index) or "ui_transparent"))
		print("[Solo] Map details sized: " .. map .. "; panel height=" .. height)
		if not index then print("[Solo] Map details unavailable in arena metadata: " .. map) end
	end
	for _, map in ipairs(map_order) do
		local button = menu:AddButton(Lobby.GetMapName(map), function(element)
			if not game:solomapavailable(map) then
				print("[Solo] Map selection rejected (unavailable): " .. map)
				return
			end
			local previous = Engine.GetDvarString("ui_mapname")
			Engine.SetDvarString("ui_mapname", map)
			print("[Solo] Map selected: " .. previous .. " -> " .. map)
			LUI.FlowManager.RequestLeaveMenu(element)
		end, function()
			return not game:solomapavailable(map)
		end, nil, nil, {button_over_func = function() preview(map) end})
		button:rename("awz_solo_map_" .. map)
		button:setDisabledRefreshRate(500)
	end
	preview(Engine.GetDvarString("ui_mapname"))
	menu:AddBackButton()
	print("[Solo] Map details ready; title spacing and description whitespace normalized; selected=" .. Engine.GetDvarString("ui_mapname"))
	return menu
end)

function AWZSolo.Open(element, event)
	if not game:beginsolo() then
		return
	end
	Engine.SetSplitScreen(false)
	Engine.SetDvarInt("ui_awz_solo_character", selected_character())
	MatchRules.SetUsingMatchRulesData(1)
	MatchRules.SetData("gametype", "zombies")
	if not game:solomapavailable(Engine.GetDvarString("ui_mapname")) then
		Engine.SetDvarString("ui_mapname", "mp_zombie_lab")
	end
	LUI.FlowManager.RequestAddMenu(element, "awz_solo_lobby", true, event.controller)
end

local function start_movie(element, event)
	local map = Engine.GetDvarString("ui_mapname")
	if not game:solomapavailable(map) then
		print("[Solo] Selected map is unavailable: " .. tostring(map))
		return
	end
	print("[Solo] Playing " .. Zombies.Intros[intros[map]] .. " before " .. map)
	LUI.FlowManager.RequestAddMenu(element, "awz_solo_intro", false, event.controller, false, {
		movieIndex = intros[map],
		disableSkip = false,
		handleBackground = true,
		soloMap = map
	})
end

-- Use AW's actual movie playback, background/audio cleanup, and input bindings.
-- Only successful completion/skip queues the map; closing the UI for another reason does not.
LUI.MenuBuilder.registerDef("awz_solo_intro", function()
	local definition = LUI.MenuBuilder.m_definitions["zombies_intro"]()
	local map
	local root
	local completed = false
	local original_create = definition.handlers.menu_create
	definition.handlers.menu_create = function(element, event)
		root = element
		map = element.properties.soloMap
		original_create(element, event)
	end
	local function finish(callback, element, event, reason)
		if completed then return end
		completed = true
		if not game:startsolo(map) then
			callback(element, event)
			return
		end
		-- Keep the intro's opaque background until native map loading replaces the UI.
		-- The stock exit handler would first reveal the lobby and restart its music.
		root:getFirstDescendentById("Attract_bg_video"):setAlpha(0)
		Engine.StopMenuVideo()
		if root.properties.handleBackground then
			PersistentBackground.PopStackedBackground()
			root.properties.handleBackground = false
		end
		Engine.StopMusic(0)
		if CoD.Music.MainMPZombiesAmbientID ~= nil then
			Engine.StopSound(CoD.Music.MainMPZombiesAmbientID)
			CoD.Music.MainMPZombiesAmbientID = nil
		end
		print("[Solo] Intro " .. reason .. "; transitioning directly to loading " .. tostring(map))
	end
	local original_update = definition.handlers.cinematic_update
	definition.handlers.cinematic_update = function(element, event)
		if Engine.IsVideoFinished() then
			finish(original_update, element, event, "finished")
		end
	end
	for _, child in ipairs(definition.children) do
		for _, name in ipairs({"button_action", "button_start", "button_secondary"}) do
			if child.handlers and child.handlers[name] then
				local callback = child.handlers[name]
				child.handlers[name] = function(element, event)
					finish(callback, element, event, "skipped")
				end
			end
		end
	end
	return definition
end)

LUI.MenuBuilder.registerType("awz_solo_lobby", function(menu_type, properties)
	ZombiesUpdateMapBkg()
	-- MenuTemplate keeps the normal layout without MPLobbyBase's party/member listeners.
	local menu = LUI.MenuTemplate.new(menu_type, {
		menu_title = "@AWZ_SOLO",
		uppercase_title = true,
		menu_width = CoD.DesignGridHelper(6, 1)
	})
	SetupTheLobby(menu, true)
	local start = menu:AddButton("@LUA_MENU_START_GAME", start_movie, function()
		return not game:solomapavailable(Engine.GetDvarString("ui_mapname"))
	end)
	start:setDisabledRefreshRate(500)
	menu:AddButton("@AWZ_CHANGE_MAP", function(element, event)
		LUI.FlowManager.RequestAddMenu(element, "awz_solo_maps", true, event.controller)
	end)
	menu:AddButton("@AWZ_CHANGE_MODE", function(element, event)
		LUI.FlowManager.RequestAddMenu(element, "awz_solo_modes", true, event.controller)
	end)
	menu:AddButton("@AWZ_CHARACTER_SELECT", function(element, event)
		LUI.FlowManager.RequestAddMenu(element, "awz_solo_characters", true, event.controller)
	end)
	menu:AddOptionsButton()
	menu:AddBackButton(function(element, event)
		game:endsolo()
		-- The parent is the online menu. Recreate only our own empty party on returning to it.
		if Engine.GetOnlineGame() then Engine.ExecNow("xstartprivateparty", event.controller) end
		LUI.FlowManager.RequestLeaveMenu(element)
	end)
	-- Reuse the stock map background and personal-best display; neither creates a party.
	menu.ZombiesRefreshStats = LUI.MPLobbyBase.ZombiesRefreshStats
	menu:AddMapDisplay(function()
		local display = LUI.MPLobbyMap.new()
		-- Supply the complete stock title layout: partial states lose its alignment.
		local height = CoD.TextSettings.TitleFontSmall.Height
		local top = (LUI.MPLobbyMap.TitleHeight - height) / 2 + GenericButtonSettings.Styles.FlatButton.y_offset
		local title = CoD.CreateState(10, top, 0, top + height, CoD.AnchorTypes.TopLeftRight)
		title.font = CoD.TextSettings.zmHeaderFont.Font
		title.color = Colors.white
		title.alignment = LUI.HorizontalAlignment.Left
		display.title:registerAnimationState("default", title)
		display.title:animateToState("default", 0)
		-- Retain the stock layout; Solo only needs the selected map's name.
		display.Refresh = function(element)
			local name = Lobby.GetMapName()
			if Engine.GetDvarInt("ui_awz_classic") == 1 then name = name .. " (Classic)" end
			element.title:setText(name)
			element:SetMapImage(Lobby.GetMapImage())
		end
		display:registerEventHandler("refresh", display.Refresh)
		return display
	end)
	LUI.MPLobbyBase.AddZombiesStats(menu)
	LUI.MPLobbyBase.AddZombiesMapTimer(menu)
	add_player_list(menu)
	if Engine.GetDvarBool("ui_opensummary") then
		print("[Solo] Opening stock after-action report for completed match")
	end
	LobbyInitAAR(menu, Lobby.AARTypes.Normal)
	print("[Solo] Setup menu ready; map=" .. Engine.GetDvarString("ui_mapname") .. "; mode=" .. (Engine.GetDvarInt("ui_awz_classic") == 1 and "Classic" or "Standard"))
	return menu
end)

-- Register the same parents as Private Match. FlowManager stores these lazily:
-- the online menu is only constructed after Back has restored multiplayer settings.
LUI.FlowManager.RegisterMenuStack("awz_solo_lobby", {"mp_main_menu", "menu_xboxlive"})

-- Offline match teardown asks for the main menu. Redirect before construction,
-- preserving ui_opensummary and avoiding MainMenu's reset to the Outbreak map.
local original_add_menu = LUI.FlowManager.addMenu
LUI.FlowManager.addMenu = function(manager, event, root)
	if game:issolo() and event.menu == "mp_main_menu" then
		print("[Solo] Routing frontend return to Solo pre-game lobby")
		event.menu = "awz_solo_lobby"
	end
	return original_add_menu(manager, event, root)
end

print("[Solo] Zombies Solo menu and skippable map intros registered")
