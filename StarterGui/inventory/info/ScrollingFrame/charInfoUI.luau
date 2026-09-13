--!strict
local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local ElementRegistry = require(game.ReplicatedStorage.Modules.ElementRegistry)
local StatColors = require(game.ReplicatedStorage.Modules.StatColors)
local MAX_STAT = require(game.ReplicatedStorage.Class.plrObjClient.slot).MAX_STAT
local plrObj = clientData.plrObj
local TweenService = game:GetService("TweenService")

local frame = script.Parent

local lvlBar    = frame:WaitForChild("lvl")
local xpBar     = lvlBar:WaitForChild("bar")
local lvlLabel  = lvlBar:WaitForChild("level")

local baseSection   = frame:WaitForChild("stats")
local wepSection    = frame:WaitForChild("weaponStats")
local elemSection   = frame:WaitForChild("elements")

local statsContainer = baseSection:WaitForChild("container")
local wepContainer   = wepSection:WaitForChild("container")
local elemContainer  = elemSection:WaitForChild("container")

local allocPtsLabel = frame:WaitForChild("allocPts")
-- the sheet's own visibility: inventoryUI sets it from isOpen. Nothing here should run while off.
local panel = frame.Parent :: GuiObject
local ACCENT = Color3.fromRGB(255, 217, 103) -- the draft LevelButton's gold, the only progression accent
-- Montserrat is FontFace-only, there is no Enum.Font entry for it. Built once, shared by every bar.
local NUM_FONT = Font.fromName("Montserrat", Enum.FontWeight.Regular)

-- GuiObject, not Frame: the compact element rows are TextButtons. UIListLayout survives.
local function clearContainer(container: Frame)
	for _, v in pairs(container:GetChildren()) do
		if v:IsA("GuiObject") then game.Debris:AddItem(v, 0) end
	end
end

-- stat template is 30 tall, a compact row 18, and the list pads 5. `container` is {1,-15},
-- so the section is that content plus 15.
local BAR_ROW_H, OTHER_ROW_H, ROW_PAD, ELEM_TOP_PAD = 30, 18, 5, 15
-- sections are ABSOLUTELY positioned (60 / 230 / 365, ten apart), so anything that resizes
-- one has to restack the rest. reflow owns every section Y from here on.
local SECTION_TOP, SECTION_GAP, HEADER_H = baseSection.Position.Y.Offset, 10, 20

-- every section is some bar rows plus some compact rows; all four measure themselves with this.
local function stackH(barRows: number, otherRows: number): number
	return barRows * (BAR_ROW_H + ROW_PAD) + otherRows * (OTHER_ROW_H + ROW_PAD)
end

local loadedSlot -- the click guard needs allocPts at CLICK time, not at build time.
local elemOtherOpen = false
local otherToggle: TextButton? = nil

type section = {
	frame: Frame,
	container: Frame,
	sign: TextLabel,
	collapsed: boolean,
	contentH: number,
	-- fired on collapse AND expand: a section with live readouts binds/unbinds off this
	onToggle: (() -> ())?,
}
local sections: {section} = {}

local function reflow()
	local y = SECTION_TOP
	for _, s in ipairs(sections) do
		local h = if s.collapsed then HEADER_H else ELEM_TOP_PAD + s.contentH
		s.frame.Position = UDim2.new(0, 0, 0, y)
		s.frame.Size = UDim2.new(1, 0, 0, h)
		s.container.Visible = not s.collapsed
		s.sign.Text = if s.collapsed then "+" else "-"
		y += h + SECTION_GAP
	end
	-- the sections are the last children, so the stack reflow just built IS the content height.
	-- The trailing SECTION_GAP doubles as bottom padding.
	frame.CanvasSize = UDim2.fromOffset(0, y)
end

-- the header IS the toggle: a transparent button over the label, so no authored art changes.
local function addSection(sectionFrame: Frame, collapsed: boolean): section
	local label = sectionFrame:WaitForChild("statsLabel") :: TextLabel
	-- the +/- rides the RIGHT edge of the header, so the title keeps its authored centering
	local sign = label:Clone()
	sign.Name = "toggleSign"
	sign.Size = UDim2.new(1, -8, 0, HEADER_H)
	sign.Position = UDim2.fromOffset(0, 0)
	sign.TextXAlignment = Enum.TextXAlignment.Right
	sign.Text = ""
	sign.Parent = sectionFrame

	local s: section = {
		frame = sectionFrame,
		container = sectionFrame:WaitForChild("container") :: Frame,
		sign = sign,
		collapsed = collapsed,
		contentH = 0,
	}
	local hit = Instance.new("TextButton")
	hit.Name = "headerToggle"
	hit.Size = UDim2.new(1, 0, 0, HEADER_H)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = label.ZIndex + 1
	hit.Parent = sectionFrame
	hit.MouseButton1Click:Connect(function()
		s.collapsed = not s.collapsed
		reflow()
		if s.onToggle then s.onToggle() end
	end)
	table.insert(sections, s)
	return s
end

-- CHARACTER INFO: live combat numbers, none of them slot data. Cloned off a real section so
-- it inherits the panel's label, stroke, container and list layout.
local infoSection = baseSection:Clone()
infoSection.Name = "character"
infoSection.Parent = frame
local infoContainer = infoSection:WaitForChild("container") :: Frame
-- named, NOT `(expr).Text = ...`: a line opening with `(` reads as a call on the line above
local infoLabel = infoSection:WaitForChild("statsLabel") :: TextLabel
infoLabel.Text = "character"
clearContainer(infoContainer)

local infoSec  = addSection(infoSection, true) -- default collapsed, as asked
local baseSec  = addSection(baseSection, false)
local wepSec   = addSection(wepSection, false)
local elemSec  = addSection(elemSection, false)
local slotCon:RBXScriptConnection? = nil
local guideTweens:{Tween} = {}

local function clearInvestmentGuide()
	for _, tween in ipairs(guideTweens) do tween:Cancel() end
	table.clear(guideTweens)
	allocPtsLabel.TextColor3 = Color3.new(1, 1, 1)
	for _, root in ipairs({allocPtsLabel, statsContainer, wepContainer, elemContainer}) do
		for _, child in ipairs(root:GetDescendants()) do
			if child:IsA("UIStroke") and child.Name == "InvestmentGuideStroke" then child:Destroy() end
		end
	end
end

-- fade only; a thickness swell reads as neon against the flat panels.
local function pulse(target: GuiObject)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "InvestmentGuideStroke"
	-- Border, NOT the default Contextual: every target here is a TextButton with empty Text, and
	-- Contextual strokes the text on a text object -- so the guide was drawing nothing at all.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.8
	stroke.Parent = target
	local tween = TweenService:Create(stroke,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.95 })
	table.insert(guideTweens, tween)
	tween:Play()
end

local function pulseSpendable(container: Frame, valueOf: (string) -> number)
	for _, statFrame in ipairs(container:GetChildren()) do
		if not statFrame:IsA("Frame") then continue end
		if valueOf(statFrame.Name) >= MAX_STAT then continue end
		local clickBar = statFrame:FindFirstChild("bar")
		if clickBar and clickBar:IsA("GuiObject") then pulse(clickBar) end
	end
end

-- The points line IS the coach; a floating panel would cover the stats it points at.
local function refreshInvestmentGuide()
	clearInvestmentGuide()
	if loadedSlot == nil then return end
	local needed = loadedSlot:pointsToNextProg()
	local points = "Points: " .. tostring(loadedSlot.allocPts)
	-- kept short: the row shares its width with characterName.
	-- the stalled case is why a draft can be owed with no badge showing.
	allocPtsLabel.Text = if needed > 0
		then points .. "  ·  invest " .. tostring(needed) .. " more"
		elseif loadedSlot:pendingProg() > 0 and not loadedSlot.draftable
		then points .. "  ·  no draft options yet"
		else points
	if needed <= 0 then return end
	-- the pulse is a looping tween per spendable row; do not run it at a closed panel.
	if not panel.Visible then return end

	allocPtsLabel.TextColor3 = ACCENT -- tint the count, don't outline the glyphs
	pulseSpendable(statsContainer, function(name) return loadedSlot.baseStats[name] or MAX_STAT end)
	pulseSpendable(wepContainer, function(name) return loadedSlot.weaponStats[name] or MAX_STAT end)
	pulseSpendable(elemContainer, function(name) return loadedSlot.elements:Get(name) end)
	-- every uninvested element hides behind the toggle, so a fresh slot has no elemental
	-- bar to point at. Pulse the toggle instead of rows nobody can see.
	if otherToggle then pulse(otherToggle) end
end

-- fill width and the number on it are one readout: both move here, nowhere else.
-- 0 draws no fill, so there is nothing to sit in -- hide the number rather than float it.
local function setBar(stat: Frame, value: number)
	local fill = stat:WaitForChild("bar"):WaitForChild("bar")
	fill.Size = UDim2.new(value / MAX_STAT, 0, 1, 0)
	local num = fill:WaitForChild("value")
	num.Text = tostring(value)
	num.Visible = value > 0
end

-- the number is its own fill's colour one step off in tone: deeper on bright fills, lighter
-- on the two dark ones (blood, dark). Deliberately a near miss -- push it further and the
-- glyphs stop reading as the bar's colour and just look black or white at this size.
local function numColor(fill: Color3): Color3
	local h, s, v = fill:ToHSV()
	if 0.2126 * fill.R + 0.7152 * fill.G + 0.0722 * fill.B < 0.3 then
		return Color3.fromHSV(h, s * 0.7, math.min(v * 1.45, 1))
	end
	return Color3.fromHSV(h, math.min(s * 1.15, 1), v * 0.55)
end

-- one patch handler for both bar tracks; neither closes over the slot. `stats` is any because
-- the stat tables carry their own methods, so no indexer type accepts them.
local function updateStatsUI(container: Frame, stats: any)
	for k, v in pairs(stats) do
		local statFrame = container:FindFirstChild(k)
		if statFrame then setBar(statFrame :: Frame, v) end
	end
end

local function makeStatBar(container: Frame, name: string, value: number, color: Color3?, onClickFn: () -> (), order: number?)
	local stat = script.stat:Clone()
	stat.Name = name
	stat.LayoutOrder = order or 0
	local mainBarFrame = stat:WaitForChild("bar")
	local statBar = mainBarFrame:WaitForChild("bar")
	if color then statBar.BackgroundColor3 = color end
	stat.label.Text = name

	-- parented to the FILL, not the track, so it centres on the solid part and slides with it.
	-- Z+1: the fill is a same-ZIndex child of the track (Sibling behavior) and would cover it.
	local num = Instance.new("TextLabel")
	num.Name = "value"
	num.Size = UDim2.fromScale(1, 1)
	num.BackgroundTransparency = 1
	num.FontFace = NUM_FONT
	num.TextSize = 10
	num.TextColor3 = numColor(statBar.BackgroundColor3)
	num.ZIndex = statBar.ZIndex + 1
	num.Parent = statBar

	setBar(stat, value)
	stat.Visible = true
	stat.Parent = container
	mainBarFrame.MouseButton1Click:Connect(function()
		if loadedSlot == nil or loadedSlot.allocPts <= 0 then return end
		onClickFn()
	end)
end

-- base and weapon stats build the same way off the same shape; only the container and the
-- allocate call differ. Rows are COUNTED, not hardcoded 4 and 3.
local function buildBars(container: Frame, stats: any, alloc: (string) -> ()): number
	clearContainer(container)
	local rows = 0
	for name, value in pairs(stats) do
		rows += 1
		makeStatBar(container, name, value, StatColors[name], function() alloc(name) end)
	end
	return stackH(rows, 0)
end

-- ONE compact row for both jobs: optional colour chip, name left, value right. No bar,
-- because neither an uninvested element nor a readout has progress to draw.
-- NO allocPts guard in here: the toggle must open with zero points, a readout never clicks.
local function makeRow(container: Instance, text: string, color: Color3?, order: number, onClickFn: (() -> ())?): (TextButton, TextLabel)
	local row = Instance.new("TextButton")
	row.Name = text
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -20, 0, OTHER_ROW_H)
	row.BackgroundTransparency = 1
	row.AutoButtonColor = onClickFn ~= nil
	row.Active = onClickFn ~= nil
	row.Text = ""

	local indent = 0
	if color then
		indent = 16
		local chip = Instance.new("Frame")
		chip.Size = UDim2.fromOffset(10, 10)
		chip.Position = UDim2.new(0, 0, 0.5, -5)
		chip.BorderSizePixel = 0
		chip.BackgroundColor3 = color
		chip.Parent = row
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -indent, 1, 0)
	label.Position = UDim2.fromOffset(indent, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = row

	local value = label:Clone()
	value.Name = "value"
	value.Size = UDim2.new(1, 0, 1, 0)
	value.Position = UDim2.fromOffset(0, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = ""
	value.Parent = row

	if onClickFn then row.MouseButton1Click:Connect(onClickFn) end
	row.Parent = container
	return row, value
end

-- invested elements keep their bar; the rest collapse behind one "other" row, because nine
-- empty bars is most of the panel spent on nothing.
local function buildElementsUI()
	if loadedSlot == nil then return end
	clearContainer(elemContainer)
	otherToggle = nil

	local others: {string} = {}
	local order, bars = 0, 0
	for _, name in ipairs(ElementRegistry) do
		local value = loadedSlot.elements:Get(name)
		if value > 0 then
			order += 1
			bars += 1
			makeStatBar(elemContainer, name, value, StatColors[name], function()
				plrObj:allocateElement(name)
			end, order)
		else
			table.insert(others, name)
		end
	end

	if #others > 0 then
		order += 1
		-- same convention as a section header: name left, +/- right. That is what makeRow's
		-- value label already is, so the row needs nothing extra.
		local toggleRow, toggleSign = makeRow(elemContainer,
			"other (" .. #others .. ")",
			nil, order,
			function()
				elemOtherOpen = not elemOtherOpen
				buildElementsUI()
				refreshInvestmentGuide() -- the rebuild dropped the pulse strokes
			end)
		toggleSign.Text = if elemOtherOpen then "-" else "+"
		otherToggle = toggleRow

		if elemOtherOpen then
			for _, name in ipairs(others) do
				order += 1
				makeRow(elemContainer, name, StatColors[name], order, function()
					if loadedSlot == nil or loadedSlot.allocPts <= 0 then return end
					plrObj:allocateElement(name) -- the point moves it out to a bar on the next patch
				end)
			end
		end
	end

	elemSec.contentH = stackH(bars, order - bars)
	reflow()
end

plrObj.slotLoaded:Connect(function(slotData, _serialData)
	if slotCon then slotCon:Disconnect() end
	loadedSlot = slotData

	local function updateExpUI()
		lvlLabel.Text = "LVL " .. slotData:earnedProg()
		xpBar.Size = UDim2.new(slotData.exp / slotData:nextLevelXp(), 0, 1, 0)
	end

	frame.characterName.Text = slotData.name
	updateExpUI()

	baseSec.contentH = buildBars(statsContainer, slotData.baseStats, function(k) plrObj:allocateStat(k) end)
	wepSec.contentH  = buildBars(wepContainer, slotData.weaponStats, function(k) plrObj:allocateWeaponStat(k) end)

	buildElementsUI() -- clears the container, sets elemSec.contentH, and reflows
	refreshInvestmentGuide()

	slotCon = slotData.onStatChange:Connect(function(patch)
		if patch.exp or patch.lvl or patch.allocPts then
			updateExpUI() -- earnedProg moves with allocPts, not just lvl
		end
		if patch.baseStats then
			updateStatsUI(statsContainer, slotData.baseStats)
		end
		if patch.weaponStats then
			updateStatsUI(wepContainer, slotData.weaponStats)
		end
		if patch.elements then
			-- REBUILD, not resize: a first point moves an element out of `other` into a bar.
			buildElementsUI()
		end
		if patch.lvl or patch.allocPts or patch.prog or patch.baseStats or patch.weaponStats or patch.elements
			or patch.draftable ~= nil then
			refreshInvestmentGuide()
		end
	end)
end)
-- CHARACTER INFO rows. Live combat numbers off the client HumObj, NOT slot data: cards and
-- mods move all four (Fortitude health, Haki posture, ManaPores mana, every walkSpeed mod).
local INFO_ROWS = { "max health", "max posture", "max mana", "walkspeed" }
local infoValues: {[string]: TextLabel} = {}
for i, title in ipairs(INFO_ROWS) do
	local _, value = makeRow(infoContainer, title, nil, i, nil)
	infoValues[title] = value
end
infoSec.contentH = stackH(0, #INFO_ROWS)

--[[ CONNECTED ONLY WHILE WATCHED. walkSpeed alone fires on sprint, block, attack, land-hit,
	shock and every dash, so a permanent listener burns cpu for a panel nobody is looking at.
	The sheet is `info.Visible` (inventoryUI sets it from isOpen), and this section starts
	collapsed -- so by default there is NOTHING connected here at all. ]]
local liveHumObj: any = nil
local infoCons: {RBXScriptConnection} = {}

local function showInfo()
	local hum = liveHumObj and liveHumObj.Hum
	if hum == nil then
		for _, value in pairs(infoValues) do value.Text = "-" end
		return
	end
	infoValues["max health"].Text = tostring(math.floor(hum.MaxHealth))
	infoValues["max posture"].Text = tostring(math.floor(liveHumObj.maxPosture.Value))
	infoValues["max mana"].Text = tostring(math.floor(liveHumObj.maxMana.Value))
	infoValues["walkspeed"].Text = tostring(math.floor(liveHumObj.walkSpeed.Value))
end

local function unbindInfo()
	for _, con in ipairs(infoCons) do con:Disconnect() end
	table.clear(infoCons)
end

local function syncInfoBinding()
	if not (panel.Visible and not infoSec.collapsed) then
		return unbindInfo()
	end
	showInfo() -- catch up on whatever moved while we were not listening
	if #infoCons > 0 then return end -- already live

	local hum = liveHumObj and liveHumObj.Hum
	if hum == nil then return end
	table.insert(infoCons, hum:GetPropertyChangedSignal("MaxHealth"):Connect(showInfo))
	-- AdditiveValue has no Changed, it announces mods: onSet AND onRemove, or a dropped
	-- mod leaves the old number on screen.
	for _, av in ipairs({ liveHumObj.maxPosture, liveHumObj.maxMana, liveHumObj.walkSpeed }) do
		table.insert(infoCons, av.onSet:Connect(showInfo))
		table.insert(infoCons, av.onRemove:Connect(showInfo))
	end
end

infoSec.onToggle = syncInfoBinding
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	syncInfoBinding()
	refreshInvestmentGuide() -- picks the pulses back up on open, drops them on close
end)
clientData.onHumObjSetup:Connect(function(humObj)
	liveHumObj = humObj
	unbindInfo() -- the dead character's signals are gone, the list holding them is not
	syncInfoBinding()
end)
liveHumObj = clientData.HumObj
syncInfoBinding()
reflow()
