--!strict
local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local ElementRegistry = require(game.ReplicatedStorage.Modules.ElementRegistry)
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
local ACCENT = Color3.fromRGB(255, 217, 103) -- the draft LevelButton's gold, the only progression accent

local BASE_STAT_COLORS = {
	strength  = Color3.new(0.800, 0.282, 0.282),
	fortitude = Color3.new(0.776, 0.772, 0.756),
	dexterity = Color3.new(0.564, 0.847, 0.513),
	mind      = Color3.new(0.564, 0.682, 0.870),
}

local WEP_STAT_COLORS = {
	hvy = Color3.new(0.776, 0.772, 0.756),
	med = Color3.new(0.776, 0.772, 0.756),
	lht = Color3.new(0.776, 0.772, 0.756),
}

local ELEM_COLORS = {
	flame    = Color3.new(1.000, 0.350, 0.100),
	ice      = Color3.new(0.550, 0.850, 1.000),
	earth    = Color3.new(0.500, 0.750, 0.300),
	wind     = Color3.new(0.750, 0.950, 0.700),
	blood    = Color3.new(0.750, 0.100, 0.150),
	creation = Color3.new(1.000, 0.900, 0.400),
	light    = Color3.new(1.000, 1.000, 0.800),
	dark     = Color3.new(0.350, 0.200, 0.550),
	lightning = Color3.new(1.000, 0.950, 0.250),
}

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

local loadedSlot -- the click guard needs allocPts at CLICK time, not at build time.
local elemOtherOpen = false
local otherToggle: TextButton? = nil

type section = {
	frame: Frame,
	container: Frame,
	label: TextLabel,
	sign: TextLabel,
	title: string,
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
		label = label,
		sign = sign,
		title = label.Text,
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

	allocPtsLabel.TextColor3 = ACCENT -- tint the count, don't outline the glyphs
	pulseSpendable(statsContainer, function(name) return loadedSlot.baseStats[name] or MAX_STAT end)
	pulseSpendable(wepContainer, function(name) return loadedSlot.weaponStats[name] or MAX_STAT end)
	pulseSpendable(elemContainer, function(name) return loadedSlot.elements:Get(name) end)
	-- every uninvested element hides behind the toggle, so a fresh slot has no elemental
	-- bar to point at. Pulse the toggle instead of rows nobody can see.
	if otherToggle then pulse(otherToggle) end
end

local function makeStatBar(container: Frame, name: string, value: number, color: Color3?, onClickFn: () -> (), order: number?)
	local stat = script.stat:Clone()
	stat.Name = name
	stat.LayoutOrder = order or 0
	local mainBarFrame = stat:WaitForChild("bar")
	local statBar = mainBarFrame:WaitForChild("bar")
	if color then statBar.BackgroundColor3 = color end
	stat.label.Text = name
	statBar.Size = UDim2.new(value / MAX_STAT, 0, 1, 0)
	stat.Visible = true
	stat.Parent = container
	mainBarFrame.MouseButton1Click:Connect(function()
		if loadedSlot == nil or loadedSlot.allocPts <= 0 then return end
		onClickFn()
	end)
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
			makeStatBar(elemContainer, name, value, ELEM_COLORS[name], function()
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
				makeRow(elemContainer, name, ELEM_COLORS[name], order, function()
					if loadedSlot == nil or loadedSlot.allocPts <= 0 then return end
					plrObj:allocateElement(name) -- the point moves it out to a bar on the next patch
				end)
			end
		end
	end

	elemSec.contentH = bars * (BAR_ROW_H + ROW_PAD) + (order - bars) * (OTHER_ROW_H + ROW_PAD)
	reflow()
end

plrObj.slotLoaded:Connect(function(slotData, _serialData)
	if slotCon then slotCon:Disconnect() end
	loadedSlot = slotData

	local function updateExpUI()
		lvlLabel.Text = "LVL " .. slotData:earnedProg()
		xpBar.Size = UDim2.new(slotData.exp / slotData:nextLevelXp(), 0, 1, 0)
	end

	local function updateBaseStatsUI()
		for k, v:number in pairs(slotData.baseStats) do
			local statFrame = statsContainer:FindFirstChild(k)
			if statFrame then
				statFrame:WaitForChild("bar"):WaitForChild("bar").Size = UDim2.new(v / MAX_STAT, 0, 1, 0)
			end
		end
	end

	local function updateWeaponStatsUI()
		for k, v:number in pairs(slotData.weaponStats) do
			local statFrame = wepContainer:FindFirstChild(k)
			if statFrame then
				statFrame:WaitForChild("bar"):WaitForChild("bar").Size = UDim2.new(v / MAX_STAT, 0, 1, 0)
			end
		end
	end

	frame.characterName.Text = slotData.name
	updateExpUI()

	-- both counted, not hardcoded 4 and 3: reflow sizes each section off its own rows.
	clearContainer(statsContainer)
	local rows = 0
	for k, v in pairs(slotData.baseStats) do
		rows += 1
		makeStatBar(statsContainer, k, v, BASE_STAT_COLORS[k], function()
			plrObj:allocateStat(k)
		end)
	end
	baseSec.contentH = rows * (BAR_ROW_H + ROW_PAD)

	clearContainer(wepContainer)
	rows = 0
	for k, v in pairs(slotData.weaponStats) do
		rows += 1
		makeStatBar(wepContainer, k, v, WEP_STAT_COLORS[k], function()
			plrObj:allocateWeaponStat(k)
		end)
	end
	wepSec.contentH = rows * (BAR_ROW_H + ROW_PAD)

	buildElementsUI() -- clears the container, sets elemSec.contentH, and reflows
	refreshInvestmentGuide()

	slotCon = slotData.onStatChange:Connect(function(patch)
		if patch.exp or patch.lvl or patch.allocPts then
			updateExpUI() -- earnedProg moves with allocPts, not just lvl
		end
		if patch.baseStats then
			updateBaseStatsUI()
		end
		if patch.weaponStats then
			updateWeaponStatsUI()
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
infoSec.contentH = #INFO_ROWS * (OTHER_ROW_H + ROW_PAD)

--[[ CONNECTED ONLY WHILE WATCHED. walkSpeed alone fires on sprint, block, attack, land-hit,
	shock and every dash, so a permanent listener burns cpu for a panel nobody is looking at.
	The sheet is `info.Visible` (inventoryUI sets it from isOpen), and this section starts
	collapsed -- so by default there is NOTHING connected here at all. ]]
local panel = frame.Parent :: GuiObject
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
panel:GetPropertyChangedSignal("Visible"):Connect(syncInfoBinding)
clientData.onHumObjSetup:Connect(function(humObj)
	liveHumObj = humObj
	unbindInfo() -- the dead character's signals are gone, the list holding them is not
	syncInfoBinding()
end)
liveHumObj = clientData.HumObj
syncInfoBinding()
reflow()
