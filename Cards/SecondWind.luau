--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_gen: number,
	_on: boolean,
}

--- regen multiple while under HALF posture
local MULT = 2
local HALF = 0.5
local MOD = "secondWind"

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

--[[ Applied as a postureHeal MOD rather than as maths in the regen step, because
	CharController steps posture on the client too and AdditiveValue replicates
	its mods -- so both halves change rate together and the bar does not drift. ]]
local function refresh(self: any, humObj: any)
	local posture, postureHeal = humObj.posture, humObj.postureHeal
	local half = humObj.maxPosture.Value * HALF
	self._gen += 1

	if posture.Value >= half then
		if self._on then
			self._on = false
			postureHeal:RemoveMod(MOD)
		end
		return
	end

	if not self._on then
		self._on = true
		-- a multiple of the CURRENT rate, so other postureHeal mods still count
		postureHeal:SetMod(MOD, postureHeal.Value * (MULT - 1))
	end

	-- ONE wake, timed for when regen should have carried us back over half. Nothing
	-- polls: more posture damage fires Changed and re-arms this with a fresh eta.
	local rate = postureHeal.Value
	if rate <= 0 then return end -- no rate, no crossing; a 1/0 delay is StatusEffects' spin scar
	local gen = self._gen
	task.delay((half - posture.Value) / rate, function()
		if self._gen == gen and humObj.isActive then refresh(self, humObj) end
	end)
end

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._gen = 0
	self._on = false

	-- regen rawsets on purpose, so Changed is exactly the damage/parry/break writes
	self:addConnection(humObj.posture.Changed:Connect(function()
		refresh(self, humObj)
	end), MOD)
	refresh(self, humObj)

	return self
end

function module.destroy(self:myself)
	self:remConnection(MOD)
	self._gen += 1 -- orphan any pending wake, the gen check drops it
	local humObj = self._humObj
	if humObj and humObj.postureHeal then humObj.postureHeal:RemoveMod(MOD) end
	baseClass.destroy(self)
end

return table.freeze(module)
