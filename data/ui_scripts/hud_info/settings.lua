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

local function with_numeric_value(slider, dvar, label)
	local function value_text()
		return string.format("%s: %g", Engine.Localize(label), Engine.GetDvarFloat(dvar))
	end
	slider.properties.button_text = value_text()
	local bound_element
	local update_label
	local function bind_label(element)
		if bound_element ~= element then
			bound_element = element
			update_label = function() element:setText(value_text()) end
			element:registerDvarHandler(dvar, update_label)
			print(string.format("[Options] Numeric label attached: %s=%g; builder=%s; content width=%g", dvar,
				Engine.GetDvarFloat(dvar), element.builtByNewBuilder and "new" or "legacy",
				slider.properties.content_width or GenericButtonSettings.Common.content_width))
		end
		update_label()
	end
	-- Look Controls uses buildItemsOld, which ignores postBuildHandler. Its
	-- menu_create/element_refresh events bind the actual button instead.
	slider.handlers = slider.handlers or {}
	for _, event_name in ipairs({ "menu_create", "element_refresh" }) do
		local previous = slider.handlers[event_name]
		slider.handlers[event_name] = function(element, event)
			if previous then previous(element, event) end
			bind_label(element)
		end
	end
	local post_build = slider.postBuildHandler
	slider.postBuildHandler = function(element)
		if post_build then post_build(element) end
		bind_label(element)
	end
	return on_adjust(slider, function()
		if update_label then update_label() end
	end)
end

local function fov_slider()
	local slider = pcoptions.SliderOptionFactory(
		"cg_fov", "@PLATFORM_FOV", "@PLATFORM_FOV_OPTION_SUB",
		SliderBounds.FOV.Min, 120, 1
	)

	for _, direction in ipairs({ "button_left_func", "button_right_func" }) do
		local adjust = slider.properties[direction]
		slider.properties[direction] = function(element, event)
			local previous = Engine.GetDvarFloat("cg_fov")
			adjust(element, event)
			local value = Engine.GetDvarFloat("cg_fov")
			-- Advanced Video copies this staging value back when another setting changes.
			pcoptions.SetDvarValue("ui_cg_fov", value)
			if value ~= previous then
				print(string.format("[FOV] cg_fov=%g, cg_fovScale=%g",
					value, Engine.GetDvarFloat("cg_fovScale")))
			end
		end
	end

	return with_numeric_value(slider, "cg_fov", "@PLATFORM_FOV")
end

local lookcontrols = require("LUI.LookControls")
local look_slider = lookcontrols.SliderOptionFactory
lookcontrols.SliderOptionFactory = function(dvar, label, ...)
	local slider = look_slider(dvar, label, ...)
	if dvar ~= "sensitivity" then return slider end
	-- GradientButton's narrower content area crowds the slider arrows.
	-- Use the same content width as the PCOptions/FOV slider.
	slider.properties.content_width = GenericButtonSettings.Common.content_width
	local previous = Engine.GetDvarFloat(dvar)
	return with_numeric_value(on_adjust(slider, function()
		local value = Engine.GetDvarFloat(dvar)
		if value ~= previous then
			print(string.format("[Mouse] Sensitivity=%g", value))
			previous = value
		end
	end), dvar, label)
end

game:addlocalizedstring("LUA_MENU_AUTODETECT_SPEAKERS", "AUTO DETECT")
local advanced_option = pcoptions.AdvOptionFactory
pcoptions.AdvOptionFactory = function(dvar, label, description, choices, ...)
	if dvar ~= "snd_speakerConfig" then
		return advanced_option(dvar, label, description, choices, ...)
	end
	local detected = Engine.GetDvarInt("snd_detectedSpeakerConfig")
	-- Zero means detection is unavailable. It must not disable every manual
	-- choice, leaving only Auto Detect selectable. Keep known-device limits.
	if detected == 0 then
		for _, choice in ipairs(choices) do choice.enabled = true end
	end
	return on_adjust(advanced_option(dvar, label, description, choices, ...), function()
		print(string.format("[Audio] Speaker config=%d; detected=%d (0 = unknown)",
			Engine.GetDvarInt(dvar), detected))
	end)
end
print("[Options] Numeric mouse sensitivity enabled; manual speaker configs available when detection is unknown")

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
