local barheight = 18
local textheight = 13
local textoffsety = barheight / 2 - textheight / 2
local backgroundmaterial = Engine.InFrontend() and "distort_fe_bkgnd_ui_blur_mip0" or "distort_hud_bkgnd_ui_blur"

local function createinfobar()
	local infobar = LUI.UIElement.new({
		left = 180,
		top = 5,
		height = barheight,
		width = 195,
		leftAnchor = true,
		topAnchor = true
	})

	return infobar
end

local function infoelement(text, width)
	local container = LUI.UIElement.new({
		bottomAnchor = true,
		leftAnchor = true,
		topAnchor = true,
		rightAnchor = false,
		top = 0,
		bottom = 0,
		width = width,
		left = 0
	})

	local background = LUI.UIImage.new({
		bottomAnchor = true,
		leftAnchor = true,
		topAnchor = true,
		rightAnchor = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		color = {
			r = 0.3,
			g = 0.3,
			b = 0.3,
		},
		-- Preserve s1-mod's blur and tint. Frontend panels sample the menu target.
		material = RegisterMaterial(backgroundmaterial)
	})
	if Engine.InFrontend() then
		background:setupTiles(256)
	end

	local labelfont = RegisterFont("fonts/bodyFontBold", textheight)

	local label = LUI.UIText.new({
		left = 5,
		top = textoffsety + 1,
		font = labelfont,
		height = textheight,
		leftAnchor = true,
		topAnchor = true,
		color = {
			r = 0.8,
			g = 0.8,
			b = 0.8,
		}
	})

	label:setText(text)

	local _, _, left = GetTextDimensions(text, labelfont, textheight)
	local value = LUI.UIText.new({
		left = left + 5,
		top = textoffsety,
		font = RegisterFont("fonts/bodyFont", textheight),
		height = textheight + 1,
		leftAnchor = true,
		topAnchor = true,
		color = {
			r = 0.6,
			g = 0.6,
			b = 0.6,
		}
	})

	container:addElement(background)
	container:addElement(label)
	container:addElement(value)

	return container, value
end

local function attachinfobar(root)
	if root.awzInfobar then
		return
	end

	local infobar = createinfobar()
	infobar.id = "awz_infobar"
	infobar:setPriority(LUI.UIRoot.childPriorities.debugInfo)
	root.awzInfobar = infobar
	local fps, fpsvalue = infoelement("FPS: ", 70)
	local ping, pingvalue = infoelement("Latency: ", 115)
	infobar:addElement(fps)
	infobar:addElement(ping)
	local previousfps, previousping, previousavailable
	local function update()
		local showfps = Engine.GetDvarBool("cg_infobar_fps")
		local showping = Engine.GetDvarBool("cg_infobar_ping")
		if showfps ~= previousfps or showping ~= previousping then
			fps:setAlpha(showfps and 1 or 0)
			ping:setAlpha(showping and 1 or 0)
			-- Set both edges without replacing the counter's vertical layout.
			local left = showfps and 80 or 0
			ping:setLeftRight(true, false, left, left + 115)
			print(string.format("[HUD] Counters: FPS=%s, latency=%s; latency bounds=%d..%d, height=%d",
				tostring(showfps), tostring(showping), left, left + 115, barheight))
			previousfps, previousping = showfps, showping
		end
		if showfps then
			fpsvalue:setText(tostring(game:getfps()))
		end
		if showping then
			local latency = Engine.InFrontend() and -1 or game:getping()
			local available = latency >= 0
			pingvalue:setText(available and (latency .. " ms") or "N/A")
			if available ~= previousavailable then
				print("[HUD] Server latency " .. (available and "available" or "unavailable (no active game server)"))
				previousavailable = available
			end
		end
	end
	infobar:registerEventHandler("awz_infobar_update", update)
	root:registerEventHandler("update_hud_infobar_settings", update)
	infobar:addElement(LUI.UITimer.new(100, "awz_infobar_update"))
	root:addElement(infobar)
	update()
	print("[HUD] Counter overlay attached to UI root: " .. tostring(root.name) .. "; background=" .. backgroundmaterial .. ", original tint=0.3")
end

-- The root survives menu and HUD changes. Cover both existing roots and future
-- roots created after this script loads, including a fresh root after map changes.
local newroot = LUI.UIRoot.new
LUI.UIRoot.new = function(...)
	local root = newroot(...)
	attachinfobar(root)
	return root
end
for _, root in pairs(LUI.roots) do
	attachinfobar(root)
end
