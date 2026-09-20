if game:issingleplayer() or Engine.InFrontend() or not Engine.IsZombiesMode() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local original = builders.zombiesWeaponInfoHudDef

builders.zombiesWeaponInfoHudDef = function(...)
	local hud = original(...)
	local name = hud:getFirstDescendentById("weaponInfoWeaponName")
	if not name then
		print("[Zombies Balance] Weapon name element unavailable; gold text not attached")
		return hud
	end

	local stockUpdate = name.m_eventHandlers.weapon_change
	local function update(element, event)
		local mark = Game.GetOmnvar("ui_horde_count")
		local gold = mark == 10
		-- The stock update selects rarity_0; change its color while keeping its
		-- name, underbarrel tooltip, visibility, and map-specific behavior.
		element:registerAnimationState("rarity_0", {
			color = gold and { r = 1, g = 0.78, b = 0.2 } or Colors.s1.text_rarity0
		})
		stockUpdate(element, event)
		if element.awzMark ~= mark then
			element.awzMark = mark
			print("[Zombies Balance] Weapon HUD Mk=" .. tostring(mark) .. "; gold=" .. tostring(gold))
		end
	end

	name:registerEventHandler("weapon_change", update)
	name:registerEventHandler("playerstate_client_changed", update)
	-- This also corrects the color when the server's level arrives after the
	-- weapon-change event, and when viewing another player.
	name:registerOmnvarHandler("ui_horde_count", update)
	update(name, {})
	return hud
end

print("[Zombies Balance] Mk 10 gold weapon text registered")
