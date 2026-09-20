if game:issingleplayer() or Engine.InFrontend() then
	return
end

local options = require("LUI.mp_hud.OptionsMenu")
game:addlocalizedstring("AWZ_RESTART_MATCH", "Restart Match")

local function restart_match(element, event)
	if not Engine.GetDvarBool("sv_running") then return end
	options.LeaveThisMenu(element, event)
	print("[Pause Menu] Restart Match: map_restart")
	Engine.Exec("map_restart")
end

local original_build = LUI.MenuBuilder.m_types_build["mp_pause_menu"]
LUI.MenuBuilder.m_types_build["mp_pause_menu"] = function(...)
	local menu = original_build(...)
	if not Engine.GetDvarBool("sv_running") then return menu end

	local end_game = menu.list:getFirstChild()
	while end_game do
		if end_game.properties and end_game.properties.button_text == Engine.Localize("@LUA_MENU_END_GAME") then
			local button = menu:AddButton("@AWZ_RESTART_MATCH", restart_match)
			button:rename("mp_pause_menu_restart_match")
			menu.list:removeElement(button)
			button:addElementBefore(end_game)
			return menu
		end
		end_game = end_game:getNextSibling()
	end
	print("[Pause Menu] Restart Match unavailable: stock End Game button not found")
	return menu
end
