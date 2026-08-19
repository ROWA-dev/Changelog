--!strict
if game:GetService("RunService"):IsClient() == false then
	return
end

local clientData = require(game:GetService("ReplicatedFirst"):WaitForChild("ClientData"))
local markdownFolder = game:GetService("ReplicatedStorage"):WaitForChild("Utils"):WaitForChild("Markdown")
local markdownRender = require(markdownFolder:WaitForChild("Render"))
local markdownTheme = require(markdownFolder:WaitForChild("Theme"))
local plrObj = clientData.plrObj
script.Parent:WaitForChild("Frame").Visible = true

local clouds = workspace:WaitForChild("Terrain"):WaitForChild("Clouds")
local surface = script:WaitForChild("slotsSurface")
local blur = script:WaitForChild("Blur")
local sunrays = game.Lighting:WaitForChild("SunRays")
--local conn = nil

plrObj.slotLoaded:Connect(function(slotData)  -- slot is loaded so get out of menu duh
	--[[if conn then
		conn:Disconnect()
	end]]
	surface:WaitForChild("Highlight").Enabled = false
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	script.Parent.Frame.Visible = false
	clouds.Density = 0.2
	workspace.GlobalWind = Vector3.new(20,0,-20)
	script.Parent.Parent:WaitForChild("combat").Enabled = true
	blur.Enabled = false
	sunrays.Intensity = 5 -- DEFAULT
end)

local screenFrame = script.Parent:WaitForChild("Frame")
local slotsFrame = script.Parent.Frame:WaitForChild("slots")
local slotsScroll = slotsFrame:WaitForChild("ScrollingFrame")

-- ---------------------------------------------------------------------------
-- SLOT CARD  (the "..." on each slot button)
--
-- Replaces createTableMap, which cloned script.map/list/keypair, walked the
-- table with pairs() and JSONEncode'd anything nested. Two problems: it stacked
-- a NEW panel on every click with no way to close the old ones, and since
-- Slots:ToClient sends a censored summary it had exactly one key to show, so
-- the "table" was always a single row reading `name: Character #1`.
--
-- Now it renders that summary as a character sheet.
--
-- Styling stays in the MENU's language, not a new one: SourceSans, the same
-- greys, the 4px corner off `slot`/`slots`, and the white 0.5/0.5 hairline that
-- slot and newSlot both use. What it drops is what actually read as old -- the
-- banded `key:` column, the flat title strip, and rows all at one weight. Label
-- dim / value bright carries the hierarchy instead.
--
-- The map clone survives for its dropshadow and UIDragDetector; everything
-- inside it is laid out here against a running y cursor, so the height is exact
-- and nothing depends on a template's row height.
-- ---------------------------------------------------------------------------
local slotClass = require(game.ReplicatedStorage.Class.plrObjClient.slot)

local CARD_W    = 260
local CARD_PAD  = 12
local ROW_H     = 19
-- See-through like the rest of the menu. Theme.luau's note applies: a
-- translucent panel must start from BLACK, not the (34,34,34) grey the opaque
-- map used, because the sky behind lifts the effective backdrop and grey loses
-- the contrast the small label text needs.
local CARD_BG    = Color3.new(0, 0, 0)
local CARD_CLEAR = 0.45
local CARD_TITLE = Color3.fromRGB(240, 240, 240)
local CARD_VALUE = Color3.fromRGB(226, 226, 226)
local CARD_LABEL = Color3.fromRGB(146, 146, 146)
local CARD_TRACK = Color3.fromRGB(58, 58, 58)

local function mk(cls: string, props: {[string]: any}): any
	local parent = props.Parent
	props.Parent = nil
	local o: any = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function comma(v: any): string
	local n = math.floor(tonumber(v) or 0)
	local s, k = tostring(math.abs(n)), nil
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return (if n < 0 then "-" else "") .. s
end

local function dateOf(v: any): string
	local n = tonumber(v)
	if n == nil or n <= 0 then return "-" end
	return os.date("!%d %b %Y", n) :: string
end

local function ratio(a: any, b: any): string
	local kills, deaths = tonumber(a) or 0, tonumber(b) or 0
	if deaths <= 0 then return string.format("%.2f", kills) end
	return string.format("%.2f", kills / deaths)
end

local openCard: Instance? = nil
local function closeSlotCard()
	if openCard then
		openCard:Destroy()
		openCard = nil
	end
end

-- `anchorGui` is the button that opened it, NOT a mouse position -- see the
-- placement note at the bottom of this function.
local function openSlotCard(anchorGui: GuiObject, id: number, entry: any)
	closeSlotCard() -- one at a time. the old one stacked forever.

	-- cloned for the dropshadow + UIDragDetector only; atitle is the flat strip
	-- that dated the whole thing, so it goes.
	local map = script.map:Clone()
	local oldTitle = map:FindFirstChild("atitle")
	if oldTitle then oldTitle:Destroy() end

	map.BackgroundColor3 = CARD_BG
	map.BackgroundTransparency = CARD_CLEAR
	mk("UICorner", { CornerRadius = UDim.new(0, 2), Parent = map })
	-- 1px and DARKER than the fill: the fill is black at 0.45, so an opaque black
	-- edge reads as a definite border against it instead of a white hairline.
	mk("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1,
		Transparency = 0.15, Parent = map })
	-- the shadow sat at full opacity behind an OPAQUE panel; through a
	-- see-through one it would darken the middle, so it only edges now.
	local shadow = map:FindFirstChild("dropshadow")
	if shadow then shadow.ImageTransparency = 0.55 end

	local lvl = tonumber(entry.lvl) or 0
	-- ONE source of truth for the curve. nextLevelXp only reads .lvl, so the
	-- summary stub satisfies it and the formula stays in the slot class.
	local need = slotClass.nextLevelXp({ lvl = lvl } :: any)

	-- slot.wins is KILL CREDIT, not match wins: processElo bumps it on whoever
	-- dealt top damage. Settings > Slot labels it the same way.
	local rows = {
		{ "elo",      comma(entry.elo) },
		{ "kills",    comma(entry.wins) },
		{ "deaths",   comma(entry.loss) },
		{ "k/d",      ratio(entry.wins, entry.loss) },
		{ "lives",    comma(entry.lives) },
		{ "credits",  comma(entry.creds) },
		{ "progress", comma(entry.prog) },
	}
	local pts = tonumber(entry.pts) or 0
	if pts > 0 then table.insert(rows, { "points", tostring(pts) }) end

	local inner = CARD_W - CARD_PAD * 2
	local y = 10

	-- The name is the rename field. A TextBox rather than a label + pencil: the
	-- title IS the control, so there is nothing extra to lay out. Server filters
	-- and echoes the result on S2C.PlrData, so we never keep the typed string --
	-- on commit we snap back to the current value and let the reply redraw.
	local current = tostring(entry.name or "?")
	local nameBox = mk("TextBox", {
		Position = UDim2.fromOffset(CARD_PAD, y), Size = UDim2.fromOffset(inner - 18, 20),
		BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 18,
		TextColor3 = CARD_TITLE, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false, Text = current, Parent = map,
	})
	-- hover/focus underline is the only affordance; nothing else changes shape
	local underline = mk("Frame", {
		Position = UDim2.fromOffset(CARD_PAD, y + 20), Size = UDim2.fromOffset(inner - 18, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, Parent = map,
	})
	nameBox.MouseEnter:Connect(function() underline.BackgroundTransparency = 0.8 end)
	nameBox.MouseLeave:Connect(function()
		underline.BackgroundTransparency = if nameBox:IsFocused() then 0.55 else 1
	end)
	nameBox.Focused:Connect(function() underline.BackgroundTransparency = 0.55 end)
	nameBox.FocusLost:Connect(function(enterPressed: boolean)
		underline.BackgroundTransparency = 1
		local typed = nameBox.Text:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
		nameBox.Text = current -- server is the authority; reply redraws the card
		if not enterPressed or typed == "" or typed == current then return end
		plrObj:renameSlot(id, typed)
	end)
	local close = mk("TextButton", {
		Position = UDim2.new(1, -CARD_PAD - 16, 0, y + 1), Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 16,
		TextColor3 = CARD_LABEL, Text = "x", Parent = map,
	})
	close.MouseEnter:Connect(function() close.TextColor3 = CARD_TITLE end)
	close.MouseLeave:Connect(function() close.TextColor3 = CARD_LABEL end)
	close.MouseButton1Up:Connect(closeSlotCard)
	y += 21

	mk("TextLabel", {
		Position = UDim2.fromOffset(CARD_PAD, y), Size = UDim2.fromOffset(inner, 13),
		BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 13,
		TextColor3 = CARD_LABEL, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "slot " .. tostring(id) .. "   \u{2022}   " .. dateOf(entry.first),
		Parent = map,
	})
	y += 13 + 9

	mk("Frame", {
		Position = UDim2.fromOffset(CARD_PAD, y), Size = UDim2.fromOffset(inner, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.86,
		BorderSizePixel = 0, Parent = map,
	})
	y += 1 + 9

	-- level + xp, the one thing worth a graphic on a character select
	mk("TextLabel", {
		Position = UDim2.fromOffset(CARD_PAD, y), Size = UDim2.fromOffset(inner // 2, 15),
		BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14,
		TextColor3 = CARD_LABEL, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "level " .. tostring(lvl), Parent = map,
	})
	mk("TextLabel", {
		Position = UDim2.fromOffset(CARD_PAD + inner // 2, y),
		Size = UDim2.fromOffset(inner - inner // 2, 15),
		BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 14,
		TextColor3 = CARD_VALUE, TextXAlignment = Enum.TextXAlignment.Right,
		Text = comma(entry.xp) .. " / " .. comma(need), Parent = map,
	})
	y += 16

	local track = mk("Frame", {
		Position = UDim2.fromOffset(CARD_PAD, y), Size = UDim2.fromOffset(inner, 3),
		BackgroundColor3 = CARD_TRACK, BorderSizePixel = 0, Parent = map,
	})
	mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	local pct = math.clamp(if need > 0 then (tonumber(entry.xp) or 0) / need else 0, 0, 1)
	local fill = mk("Frame", {
		Size = UDim2.fromScale(pct, 1), BackgroundColor3 = CARD_VALUE,
		BorderSizePixel = 0, Parent = track,
	})
	mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })
	y += 3 + 11

	-- label dim / value bright. no colons, no banded key column: that two-tone
	-- keypair strip is what made the old panel read as a debug dump.
	for _, pair in ipairs(rows) do
		mk("TextLabel", {
			Position = UDim2.fromOffset(CARD_PAD, y), Size = UDim2.fromOffset(inner // 2, ROW_H),
			BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14,
			TextColor3 = CARD_LABEL, TextXAlignment = Enum.TextXAlignment.Left,
			Text = pair[1], Parent = map,
		})
		mk("TextLabel", {
			Position = UDim2.fromOffset(CARD_PAD + inner // 2, y),
			Size = UDim2.fromOffset(inner - inner // 2, ROW_H),
			BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 14,
			TextColor3 = CARD_VALUE, TextXAlignment = Enum.TextXAlignment.Right,
			Text = pair[2], Parent = map,
		})
		y += ROW_H
	end

	local h = y + 10
	map.Size = UDim2.fromOffset(CARD_W, h)

	-- Anchored to the BUTTON, never the cursor. MouseButton1Up's x/y are raw
	-- screen coords and INCLUDE the topbar inset; AbsolutePosition does not.
	-- Subtracting one space from the other is what put the panel far from the
	-- click. Two AbsolutePositions cannot disagree.
	local origin = screenFrame.AbsolutePosition
	local bounds = screenFrame.AbsoluteSize
	local a = anchorGui.AbsolutePosition - origin

	-- opens to the right of the "...", flipping to its left near the edge
	local px = a.X + anchorGui.AbsoluteSize.X + 6
	if px + CARD_W > bounds.X then px = a.X - CARD_W - 6 end

	map.Position = UDim2.fromOffset(
		math.clamp(px, 0, math.max(0, bounds.X - CARD_W)),
		math.clamp(a.Y, 0, math.max(0, bounds.Y - h))
	)

	map.Visible = true
	-- parented to the menu Frame, not the ScreenGui, so loading a slot (which
	-- hides that Frame) takes the card with it.
	map.Parent = screenFrame
	openCard = map
end

local cam = workspace.CurrentCamera
local function updSlotSurfaceSz()
	--print("Viewport changed:", cam.ViewportSize)

	local d = 8
	local vp = cam.ViewportSize
	local uiSize = slotsFrame.AbsoluteSize
	local vfov = math.rad(cam.FieldOfView)
	local aspect = vp.X / vp.Y
	local hfov = 2 * math.atan(math.tan(vfov/2) * aspect)
	local sppY = (2 * d * math.tan(vfov/2)) / vp.Y
	local sppX = (2 * d * math.tan(hfov/2)) / vp.X
	local desiredStudH = uiSize.Y * sppY
	local desiredStudW = uiSize.X * sppX
	--surface.Size = Vector3.new(desiredStudW, desiredStudH, surface.Size.Z)
	surface.Size = Vector3.new(0, desiredStudH, desiredStudW)
end

cam:GetPropertyChangedSignal("ViewportSize"):Connect(updSlotSurfaceSz)

local function onDataLoad(data:clientData.plrObjData)
	if data.err then
		script.Parent:WaitForChild("dataErrMsg").Visible = true
		script.Parent.dataErrMsg.Text = data.err
	end
	screenFrame.loading.Visible = false
	
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.new(0,6000,0) * CFrame.Angles(math.rad(45),0,0)
	clouds.Density = 1
	workspace.GlobalWind = Vector3.new(-80,0,80)
	
	--
	local d = 8
	surface:WaitForChild("Highlight").Enabled = true
	surface.CFrame = cam.CFrame * CFrame.new(0,0,-d) * CFrame.Angles(0,math.rad(90),0)
	surface.Parent = workspace.CurrentCamera
	--
	
	blur.Parent = game.Lighting
	blur.Enabled = true
	sunrays.Intensity = 10

	--[[conn = game:GetService("RunService").RenderStepped:Connect(function(dt:number)
		local mouse = game.UserInputService:GetMouseLocation()
		local vp = cam.ViewportSize

		-- normalized offset from screen center (-1 to 1)
		local x = (mouse.X / vp.X - 0.5) * 2
		local y = (mouse.Y / vp.Y - 0.5) * 2

		local tilt = math.rad(10)

		cam.CFrame = cam.CFrame:Lerp(
			CFrame.new(0,1000,0) * CFrame.Angles(math.rad(90) + y*tilt, 0, -x*tilt),
			dt/4
		)
		
		local d = 8
		surface:WaitForChild("Highlight").Enabled = true
		surface.CFrame = cam.CFrame * CFrame.new(0,0,-d) * CFrame.Angles(0,math.rad(90),0)
	end)]]

	script.Parent.Parent:WaitForChild("combat").Enabled = false
	
	slotsFrame.Visible = true
	if slotsFrame.AbsoluteSize.Y > screenFrame.AbsoluteSize.Y then
		print("screen so small!")
		slotsFrame.Size = UDim2.new(
			slotsFrame.Size.X.Scale, slotsFrame.Size.X.Offset,
			0, screenFrame.AbsoluteSize.Y
		)
	end
	updSlotSurfaceSz()
	
	screenFrame.Visible = true
	
	-- clear first. the card holds an id from the PREVIOUS list, so it must go
	-- too -- this re-runs on every onDataRecieve, including after New Slot.
	closeSlotCard()
	for _,v in pairs(slotsScroll:GetChildren()) do
		if v:IsA("GuiObject") then
			v:Destroy()
		end
	end
	
	-- then load
	for id,slot in pairs(data.slots) do
		local slotName = slot.name
		if slotName == nil then
			warn("ERROR SLOT["..tostring(id).."] is empty?!")
			continue
		end
		local slotUI = script.slot:Clone()
		slotUI.Text = slotName
		
		slotUI.MouseButton1Up:Connect(function() 
			plrObj:LoadSlot(id)			
		end)
		slotUI.MouseEnter:Connect(function() 
			slotUI.UIStroke.Transparency = 0
			--slotUI.UIStroke.Thickness = 1
		end)
		slotUI.MouseLeave:Connect(function() 
			slotUI.UIStroke.Transparency = script.slot.UIStroke.Transparency
			--slotUI.UIStroke.Thickness = 0.5
		end)
		slotUI.moreinfo.MouseButton1Up:Connect(function()
			openSlotCard(slotUI.moreinfo, id, slot)
		end)
		
		slotUI.Visible = true
		slotUI.Parent = slotsScroll
	end
	
	
	--
	
	local newSlot = script.newSlot:Clone()
	newSlot.MouseEnter:Connect(function() 
		newSlot.UIStroke.Transparency = 0
		--slotUI.UIStroke.Thickness = 1
	end)
	newSlot.MouseLeave:Connect(function() 
		newSlot.UIStroke.Transparency = script.newSlot.UIStroke.Transparency
		--slotUI.UIStroke.Thickness = 0.5
	end)
	newSlot.Visible = true
	newSlot.MouseButton1Up:Connect(function() 
		plrObj:createSlot()
	end)
	newSlot.Parent = slotsScroll
	
	--
	
	local infoLabel = screenFrame:WaitForChild("info"):WaitForChild("TextLabel")
	local servName = workspace:GetAttribute("servName")
	infoLabel.Text = "[server] "..tostring(servName)
end

-- Changelog. Outside onDataLoad because it uses nothing from player data, and
-- that function re-runs on every onDataRecieve, which would stack a fresh
-- attribute listener per slot load.
local changeLogFrame = screenFrame:WaitForChild("changelog")

-- Stays see-through, but from a black base rather than a lifted one: the sky
-- behind it raises the effective backdrop, and starting at black is what keeps
-- light text readable while still showing the world through the panel.
changeLogFrame.BackgroundColor3 = markdownTheme.BG_PANEL
changeLogFrame.BackgroundTransparency = markdownTheme.PANEL_TRANSPARENCY

-- Close button. The frame only had a way in, so opening the changelog was a
-- one-way trip until the slot list was clicked.
local closeChangelog = changeLogFrame:WaitForChild("closeChangelog")
local function setChangelogOpen(open: boolean)
	changeLogFrame.Visible = open
	screenFrame.info.Visible = not open
	-- Authored Interactable = false, which propagates to every descendant and
	-- swallows the scroll wheel; Active makes the frame take input itself.
	changeLogFrame.Interactable = open
	changeLogFrame.Active = open
end

closeChangelog.MouseEnter:Connect(function()
	closeChangelog.BackgroundTransparency = 0.7
end)
closeChangelog.MouseLeave:Connect(function()
	closeChangelog.BackgroundTransparency = 0.9
end)
closeChangelog.MouseButton1Up:Connect(function()
	setChangelogOpen(false)
end)

-- The changelog is a .md file, so the old TextLabel showed raw source: "## 1.19",
-- "- item", literal <br>. TextLabel has no markdown and RichText is a different
-- syntax, so Markdown.Render builds real GUI objects instead.
local oldChangelogLabel = changeLogFrame:FindFirstChild("TextLabel")
if oldChangelogLabel then
	oldChangelogLabel.Visible = false
end

-- Inset so the first heading clears the close button rather than sitting under it.
local changeLogView = markdownRender.mount(changeLogFrame, 34)

local function drawChangelog(): boolean
	local md = workspace:GetAttribute("upd")
	if typeof(md) ~= "string" or md == "" then
		return false
	end
	markdownRender.render(changeLogView, md)
	return true
end

-- "request changelog" is a server-side HTTP GET, so on a fresh server the
-- attribute is usually still empty when the menu first draws.
if not drawChangelog() then
	local conn: RBXScriptConnection
	conn = workspace:GetAttributeChangedSignal("upd"):Connect(function()
		if drawChangelog() then
			conn:Disconnect()
		end
	end)
end

screenFrame:WaitForChild("info"):WaitForChild("openChangelog").MouseButton1Up:Connect(function() 
	setChangelogOpen(true)
end)

if plrObj.Data then
	onDataLoad(plrObj.Data)
end
plrObj.onDataRecieve:Connect(onDataLoad)