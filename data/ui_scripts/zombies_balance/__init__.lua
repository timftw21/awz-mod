if game:issingleplayer() or Engine.InFrontend() or not Engine.IsZombiesMode() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local original = builders.zombiesWeaponInfoHudDef
local upgradeColors = {
	[10] = { r = 1, g = 0.78, b = 0.2 },
	[25] = { r = 0.9, g = 0.22, b = 0.3 }
}

builders.zombiesWeaponInfoHudDef = function(...)
	local hud = original(...)
	local name = hud:getFirstDescendentById("weaponInfoWeaponName")
	if not name then
		print("[Zombies Balance] Weapon name element unavailable; upgrade colors not attached")
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
		-- The stock update selects rarity_0; change its color while keeping its
		-- name, underbarrel tooltip, visibility, and map-specific behavior.
		element:registerAnimationState("rarity_0", {
			color = upgradeColors[mark] or Colors.s1.text_rarity0
		})
		stockUpdate(element, event)
		if element.awzWeapon ~= weapon then
			element.awzWeapon = weapon
			local color = mark == 25 and "royalty ruby" or mark == 10 and "gold" or "stock"
			print("[Zombies Balance] Weapon HUD " .. weapon .. "; Mk=" .. tostring(mark) .. "; color=" .. color)
		end
	end

	name:registerEventHandler("weapon_change", update)
	name:registerEventHandler("playerstate_client_changed", update)
	update(name, {})
	return hud
end

print("[Zombies Balance] Mk 10 gold and Mk 25 Royalty ruby text synchronized with the displayed weapon")

-- Terminal purchases print these localized names through game_message. Attach
-- the icon to that same text so replacements and its fade also clear the icon.
local perk_icons = {}
for name, material in pairs({
	ZOMBIES_PERK_HEALTH = "hud_exo_upgrade_health2x",
	ZOMBIES_PERK_RELOAD = "hud_exo_upgrade_speed",
	ZOMBIES_PERK_REVIVE = "hud_exo_upgrade_revive",
	ZOMBIES_PERK_STABILIZER = "hud_exo_upgrade_stabilizer",
	ZOMBIES_PERK_SLAM = "hud_exo_upgrade_slam",
	ZOMBIES_PERK_TACTICALARMOR = "hud_exo_upgrade_stockpile"
}) do
	-- LUI wraps localized strings in 0x1F/0x1E markers; GSC game_message
	-- events contain plain text. Compare the same displayed name on both sides.
	local text = Engine.Localize(name):gsub("[\030\031]", "")
	perk_icons[text] = material
	print(string.format("[Zombies Perks] Purchase icon bound: %q -> %s", text, material))
end

local definitions = LUI.MenuBuilder.m_definitions
local game_message = definitions.gameMessageHudDef
definitions.gameMessageHudDef = function(...)
	local definition = game_message(...)
	local text = definition.children[1]
	-- This HUD uses buildItemsOld. Declare the child and message handler in
	-- the definition; that builder never invokes a definition's postBuildHandler.
	text.children = text.children or {}
	table.insert(text.children, {
		type = "UIImage", id = "awz_perk_notification_icon",
		states = {
			default = {
				topAnchor = true, bottomAnchor = false,
				leftAnchor = false, rightAnchor = false,
				top = CoD.TextSettings.zmTitleFont.Height + 10,
				left = -32, right = 32, height = 64, alpha = 0
			},
			hidden = { alpha = 0, scale = -0.15 },
			visible = { alpha = 1, scale = 0 }
		}
	})
	local show_message = text.handlers.game_message
	text.handlers.game_message = function(element, event)
		show_message(element, event)
		if event and event.bold == true and event.message then
			local icon = element:getChildById("awz_perk_notification_icon")
			icon:animateToState("hidden", 0)
			local material = perk_icons[event.message]
			if material then
				icon:setImage(RegisterMaterial(material))
				icon:animateToState("visible", 100)
			end
			print(string.format("[Zombies Perks] HUD message=%q; icon=%s", event.message, material or "none"))
		end
	end
	return definition
end
print("[Zombies Perks] Purchase icon definitions registered for the stock HUD builder")
