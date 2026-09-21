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
		-- GetPlayerWeaponName and the stock display-name binding both read the
		-- predicted viewmodel weapon. Its camo encodes the upgrade, so the color
		-- changes with the label instead of waiting for the server's omnvar.
		local weapon = Game.GetPlayerWeaponName() or ""
		local camo = tonumber(weapon:match("[_+]camo(%d+)")) or 0
		local mark = tonumber(Engine.TableLookup("mp/zmWeaponLevels.csv", 1, tostring(camo), 0))
		local gold = mark == 10
		-- The stock update selects rarity_0; change its color while keeping its
		-- name, underbarrel tooltip, visibility, and map-specific behavior.
		element:registerAnimationState("rarity_0", {
			color = gold and { r = 1, g = 0.78, b = 0.2 } or Colors.s1.text_rarity0
		})
		stockUpdate(element, event)
		if element.awzWeapon ~= weapon then
			element.awzWeapon = weapon
			print("[Zombies Balance] Weapon HUD " .. weapon .. "; Mk=" .. tostring(mark) .. "; gold=" .. tostring(gold))
		end
	end

	name:registerEventHandler("weapon_change", update)
	name:registerEventHandler("playerstate_client_changed", update)
	update(name, {})
	return hud
end

print("[Zombies Balance] Mk 10 gold weapon text synchronized with the displayed weapon")
