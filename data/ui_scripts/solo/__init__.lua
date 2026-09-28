if game:issingleplayer() or Engine.InFrontend() or not Engine.IsZombiesMode() or not game:issolo() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local original = builders.spectatorHudDef

builders.spectatorHudDef = function(...)
	local hud = original(...)
	local spawned = Game.GetOmnvar("ui_session_state") == "playing"
	if spawned then return hud end

	-- Connecting players temporarily spectate while the stock scripts assign
	-- their team and loadout. That is not a spectator session to display.
	hud:setAlpha(0)
	hud:registerOmnvarHandler("ui_session_state", function(element, event)
		if event.value == "playing" and not spawned then
			spawned = true
			print("[Solo] First spawn ready; startup spectating HUD suppressed")
		elseif event.value == "spectator" and spawned then
			-- Restore only for a later spectator session. Revealing it at spawn
			-- would expose the parent HUD's normal fade-out animation.
			element:setAlpha(1)
		end
	end)
	print("[Solo] Hiding spectator HUD until the initial spawn has completed")
	return hud
end
