if game:issingleplayer() or Engine.InFrontend() or not Engine.IsZombiesMode() then
    return
end

local hud = require("LUI.mp_hud.ZombiesWeaponInfoHud")
local stockShouldShowAmmo = hud.shouldWeaponShowAmmo

-- The stock Zombies HUD has a weapon whitelist. Register the imported pistol
-- here so its existing NO AMMO, LOW AMMO and RELOAD logic can handle it too.
hud.shouldWeaponShowAmmo = function(element, weapon)
    weapon = weapon or Game.GetPlayerWeaponName()
    if weapon == "iw5_dlcgun13_mp" or string.sub(weapon, 1, 16) == "iw5_dlcgun13_mp_" then
        if element.current_weaponName ~= weapon then
            print("[Classic] Ammo warnings enabled for " .. weapon)
        end
        element.current_weaponName = weapon
        element.current_showAmmo = true
        return true
    end
    return stockShouldShowAmmo(element, weapon)
end

print("[Classic] 1911 registered with stock Zombies ammo warnings")
