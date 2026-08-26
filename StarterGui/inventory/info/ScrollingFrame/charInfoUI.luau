--!strict
local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local ElementRegistry = require(game.ReplicatedStorage.Modules.ElementRegistry)
local MAX_STAT = require(game.ReplicatedStorage.Class.plrObjClient.slot).MAX_STAT
local plrObj = clientData.plrObj

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
}

local function clearContainer(container: Frame)
	for _, v in pairs(container:GetChildren()) do
		if v:IsA("Frame") then game.Debris:AddItem(v, 0) end
	end
end

local loadedSlot -- the click guard needs allocPts at CLICK time, not at build time.

local function makeStatBar(container: Frame, name: string, value: number, color: Color3?, onClickFn: () -> ())
	local stat = script.stat:Clone()
	stat.Name = name
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

plrObj.slotLoaded:Connect(function(slotData, _serialData)
	loadedSlot = slotData

	local function updateExpUI()
		lvlLabel.Text = "LVL " .. slotData.lvl .. "   PROG " .. slotData:earnedProg()
		xpBar.Size = UDim2.new(slotData.exp / slotData:nextLevelXp(), 0, 1, 0)
	end

	local function updateAllocPtsUI()
		allocPtsLabel.Text = "Points: " .. tostring(slotData.allocPts)
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

	local function updateElementsUI()
		for _, name in ipairs(ElementRegistry) do
			local statFrame = elemContainer:FindFirstChild(name)
			if statFrame then
				statFrame:WaitForChild("bar"):WaitForChild("bar").Size = UDim2.new(slotData.elements:Get(name) / MAX_STAT, 0, 1, 0)
			end
		end
	end

	frame.characterName.Text = slotData.name
	updateExpUI()
	updateAllocPtsUI()

	clearContainer(statsContainer)
	for k, v in pairs(slotData.baseStats) do
		makeStatBar(statsContainer, k, v, BASE_STAT_COLORS[k], function()
			plrObj:allocateStat(k)
		end)
	end

	clearContainer(wepContainer)
	for k, v in pairs(slotData.weaponStats) do
		makeStatBar(wepContainer, k, v, WEP_STAT_COLORS[k], function()
			plrObj:allocateWeaponStat(k)
		end)
	end

	clearContainer(elemContainer)
	for _, name in ipairs(ElementRegistry) do
		makeStatBar(elemContainer, name, slotData.elements:Get(name), ELEM_COLORS[name], function()
			plrObj:allocateElement(name)
		end)
	end

	slotData.onStatChange:Connect(function(patch)
		if patch.exp or patch.lvl or patch.allocPts then
			updateExpUI() -- earnedProg moves with allocPts, not just lvl
		end
		if patch.allocPts then
			updateAllocPtsUI()
		end
		if patch.baseStats then
			updateBaseStatsUI()
		end
		if patch.weaponStats then
			updateWeaponStatsUI()
		end
		if patch.elements then
			updateElementsUI()
		end
	end)
end)