if (game:issingleplayer()) then
	return
end

-- The stock cursor rebuilds its 64x64 rectangle on every mouse move. Scale
-- the offsets around the pointer hotspot so the visible tip still clicks accurately.
local cursor_scale = 0.75
LUI.UIMouseCursor.MouseMove = function(cursor, event)
	cursor:applyElementTransform()
	cursor.id = "mouse_cursor"
	local x, y = ProjectRootCoordinate(event.rootName, event.x, event.y)
	if x ~= nil and y ~= nil then
		x, y = event.root:pixelsToUnits(x, y)
		if x ~= nil and y ~= nil then
			cursor:registerAnimationState("default", {
				left = x - 30 * cursor_scale,
				right = x + 34 * cursor_scale,
				top = y - 25 * cursor_scale,
				bottom = y + 39 * cursor_scale,
				leftAnchor = true,
				topAnchor = true,
				rightAnchor = false,
				bottomAnchor = false,
				alpha = 1
			})
			cursor:animateToState("default")
		end
	end
	cursor:dispatchEventToChildren(event)
	cursor:undoElementTransform()
	cursor.lastMoveTime = Engine.GetMilliseconds()
end

-- Cursors created before this script loaded already captured the old handler.
for _, root in pairs(LUI.roots) do
	local cursor = root:getChildById("mouse_cursor")
	if cursor then
		cursor:registerEventHandler("mousemove", LUI.UIMouseCursor.MouseMove)
	end
end
print("[UI] Custom cursor scale=0.75 (48x48); pointer hotspot preserved")

if Engine.IsZombiesMode() then
	-- MainMenu checks this session flag before automatically opening zombies_intro.
	Engine.SetDvarBool("ui_zm_skip_intro", true)
	print("[Zombies] Automatic startup story cinematic disabled (ui_zm_skip_intro=1)")
end

function GetGameModeName()
	return Engine.Localize(Engine.TableLookup(GameTypesTable.File, GameTypesTable.Cols.Ref, GameX.GetGameMode(), GameTypesTable.Cols.Name))
end

-- Allow players to change teams in game.
function CanChangeTeam()
	local f9_local0 = GameX.GetGameMode()
	local f9_local1
	if f9_local0 ~= "aliens" and Engine.TableLookup(GameTypesTable.File, GameTypesTable.Cols.Ref, f9_local0, GameTypesTable.Cols.TeamChoice) == "1" then
		f9_local1 = not MLG.IsMLGSpectator()
	else
		f9_local1 = false
	end
	return f9_local1
end
