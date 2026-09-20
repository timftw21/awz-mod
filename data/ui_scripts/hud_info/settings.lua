local pcoptions = require("LUI.PCOptions")

local function on_adjust(option, callback)
	for _, direction in ipairs({ "button_left_func", "button_right_func" }) do
		local adjust = option.properties[direction]
		option.properties[direction] = function(element, event)
			adjust(element, event)
			callback()
		end
	end
	return option
end

local function fov_slider()
	local slider = pcoptions.SliderOptionFactory(
		"cg_fov", "@PLATFORM_FOV", "@PLATFORM_FOV_OPTION_SUB",
		SliderBounds.FOV.Min, 120, 1
	)

	local update_label
	for _, direction in ipairs({ "button_left_func", "button_right_func" }) do
		local adjust = slider.properties[direction]
		slider.properties[direction] = function(element, event)
			local previous = Engine.GetDvarFloat("cg_fov")
			adjust(element, event)
			local value = Engine.GetDvarFloat("cg_fov")
			-- Advanced Video copies this staging value back when another setting changes.
			pcoptions.SetDvarValue("ui_cg_fov", value)
			if update_label then
				update_label()
			end
			if value ~= previous then
				print(string.format("[FOV] cg_fov=%g, cg_fovScale=%g",
					value, Engine.GetDvarFloat("cg_fovScale")))
			end
		end
	end

	slider.postBuildHandler = function(element)
		update_label = function()
			element:setText(string.format("%s: %g", Engine.Localize("@PLATFORM_FOV"),
				Engine.GetDvarFloat("cg_fov")))
		end
		element:registerDvarHandler("cg_fov", update_label)
		update_label()
	end
	return slider
end

local function framerate_option()
	local limits = { 30, 60, 75, 90, 120, 125, 144, 165, 180, 200, 240, 250, 300, 333, 360, 480 }
	local current = Engine.GetDvarInt("com_maxfps")
	local found = current == 0
	for _, limit in ipairs(limits) do
		found = found or current == limit
	end
	-- Keep an existing custom cap visible instead of falsely showing a preset.
	if not found then
		table.insert(limits, current)
		table.sort(limits)
	end
	local choices = {{ text = "@AWZ_UNLIMITED", value = 0 }}
	for _, limit in ipairs(limits) do
		table.insert(choices, { text = Engine.MarkLocalized(tostring(limit)), value = limit })
	end
	return on_adjust(pcoptions.OptionFactory("com_maxfps", "@AWZ_FRAMERATE_LIMIT",
		"@AWZ_FRAMERATE_LIMIT_DESC", choices), function()
		print(string.format("[Video] Framerate limit: com_maxfps=%d (0 = unlimited)",
			Engine.GetDvarInt("com_maxfps")))
	end)
end

local function infobar_option(dvar, label, description)
	return on_adjust(pcoptions.OptionFactory(dvar, label, description, {
		{ text = "@LUA_MENU_ENABLED", value = true },
		{ text = "@LUA_MENU_DISABLED", value = false }
	}), function()
		Engine.GetLuiRoot():processEvent({ name = "update_hud_infobar_settings" })
	end)
end

if Engine.IsZombiesMode() then
	local advancedvideo = require("LUI.AdvancedVideo")
	local advanced_video_options = advancedvideo.AdvancedVideoOptionsFeeder
	advancedvideo.AdvancedVideoOptionsFeeder = function(...)
		local items = advanced_video_options(...)
		for index = #items, 1, -1 do
			if items[index].id == "option_@PLATFORM_FOV" then
				table.remove(items, index)
			end
		end
		return items
	end
	print(string.format("[FOV] Zombies Video Options slider enabled: %g-120, step 1; cg_fovScale is independent",
		SliderBounds.FOV.Min))
end

game:addlocalizedstring("LUA_MENU_FPS", "FPS Counter")
game:addlocalizedstring("LUA_MENU_FPS_DESC", "Show FPS Counter")

game:addlocalizedstring("LUA_MENU_LATENCY", "Server Latency")
game:addlocalizedstring("LUA_MENU_LATENCY_DESC", "Show server latency")
game:addlocalizedstring("AWZ_FRAMERATE_LIMIT", "Framerate Limit")
game:addlocalizedstring("AWZ_FRAMERATE_LIMIT_DESC", "Limit frames per second in menus and gameplay. VSync may impose a lower limit.")
game:addlocalizedstring("AWZ_UNLIMITED", "Unlimited")

pcoptions.VideoOptionsFeeder = function()
	local items = {
		pcoptions.OptionFactory(
			"ui_r_displayMode",
			"@LUA_MENU_DISPLAY_MODE",
			nil,
			{
				{
					text = "@LUA_MENU_MODE_FULLSCREEN",
					value = "fullscreen"
				},
				{
					text = "@LUA_MENU_MODE_WINDOWED_NO_BORDER",
					value = "windowed_no_border"
				},
				{
					text = "@LUA_MENU_MODE_WINDOWED",
					value = "windowed"
				}
			},
			nil,
			true
		),
		pcoptions.SliderOptionFactory(
			"profileMenuOption_blacklevel",
			"@MENU_BRIGHTNESS",
			"@MENU_BRIGHTNESS_DESC1",
			SliderBounds.PCBrightness.Min,
			SliderBounds.PCBrightness.Max,
			SliderBounds.PCBrightness.Step,
			function(element)
				element:processEvent({
					name = "brightness_over",
					immediate = true
				})
			end,
			function(element)
				element:processEvent({
					name = "brightness_up",
					immediate = true
				})
			end,
			true,
			nil,
			"brightness_updated"
		),
		pcoptions.OptionFactoryProfileData(
			"renderColorBlind",
			"profile_toggleRenderColorBlind",
			"@LUA_MENU_COLORBLIND_FILTER",
			"@LUA_MENU_COLOR_BLIND_DESC",
			{
				{
					text = "@LUA_MENU_ENABLED",
					value = true
				},
				{
					text = "@LUA_MENU_DISABLED",
					value = false
				}
			},
			nil,
			false
		)
	}

	if Engine.IsZombiesMode() then
		table.insert(items, 2, fov_slider())
	end
	table.insert(items, framerate_option())

	if Engine.IsMultiplayer() and not Engine.IsZombiesMode() then
		table.insert(items, pcoptions.OptionFactory(
			"cg_paintballFx",
			"@LUA_MENU_PAINTBALL",
			"@LUA_MENU_PAINTBALL_DESC",
			{
				{
					text = "@LUA_MENU_ENABLED",
					value = true
				},
				{
					text = "@LUA_MENU_DISABLED",
					value = false
				}
			},
			nil,
			false,
			false
		))
	end

	table.insert(items, infobar_option(
		"cg_infobar_ping",
		"@LUA_MENU_LATENCY",
		"@LUA_MENU_LATENCY_DESC"
	))

	table.insert(items, infobar_option(
		"cg_infobar_fps",
		"@LUA_MENU_FPS",
		"@LUA_MENU_FPS_DESC"
	))

	table.insert(items, {
		type = "UIGenericButton",
		id = "option_advanced_video",
		properties = {
			style = GenericButtonSettings.Styles.GlassButton,
			button_text = Engine.Localize("@LUA_MENU_ADVANCED_VIDEO"),
			desc_text = "",
			button_action_func = pcoptions.ButtonMenuAction,
			text_align_without_content = LUI.Alignment.Left,
			menu = "advanced_video"
		}
	})

	return items
end
