--!strict
--- Oblitar - rowa1 Items/Weps/Oblitar/Main. Notes: README.md/PORTW_Oblitar,
--- PORTW_00 for the checklist.
--- A large slashing weapon whose HEAVY IS TWO BEATS, the second decapitating a
--- low-health victim (rowa1's `oblH2`, in AttackModule's `decapitation` set) --
--- that finisher is the whole reason the second beat exists. See Modules/execute.
--- FAMILY: Heavy/GreatAxe. It shipped as Medium/Swords first; weight class and
--- family are different questions and it plays closer to Executer.
--- The dmgTbl weights are STILL Medium, deliberately: that field is the ATTACK
--- weight, it decides trades, and rowa1 authored all three rows Medium.
--- !! TWO CORRECTIONS TO THE DOC, both from reading Main:
---   1. the heavy is NOT a charge -- one press plays both beats automatically,
---      so there is no heavyEnd binding and adding one needs a release the
---      player never makes.
---   2. the THRUST uses oblM1, not oblH2. The doc's numbers are right, its
---      mapping was not.
--- onParried is deliberately absent: Medium already defines it and a local one
--- would just shadow the family's.
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "oblitar",
	idleAnim = script:WaitForChild("idle")
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	local model = script.Model:Clone()
	self._model = model
	self._trail = model:WaitForChild("Trail1")

	--[[ rowa1's `local AtkRate = 1.05`. It does two things at once: scaledTime
		multiplies EVERY wait by it, and PlayAnim divides anim speed by it
		(1/1.05 = 0.952, rowa1's `AtkAnim:AdjustSpeed(1/AtkRate)`).
		AdditiveValue is base 1, so the mod is the 0.05 delta, not 1.05. ]]
	self.atkRate:SetMod("oblitar", 0.05)
	return self
end

--[[ unequip FIRST, then drop the model. Heavy.destroy calls unequip, and
	GreatAxe.unequip does `self._model.Parent = script` -- on an already
	destroyed instance that throws "The Parent property is locked". ]]
function module.destroy(self:myself)
	self:unequip()
	if self._model then
		self._model:Destroy()
	end
	baseWep.destroy(self)
end

--methods

--- wield
function module.wield(self:myself&any)
	local humobj = self._humObj
	local char:any = humobj.Hum.Parent
	local model = self._model
	model.mtr.Enabled = true
	model.strap.Enabled = false
	model.mtr.Part0 = char["Right Arm"]
	model.mtr.Part1 = model.Hold
	model.Parent = char

	humobj.cooldowns:setCooldown("heavy", 6)
	baseWep.wield(self)
end

--- unwield
function module.unwield(self:myself)
	if self.lastAnim then
		self.lastAnim:Stop()
	end

	local humobj:any = self._humObj
	if humobj and humobj.Hum then
		local char:Model = humobj.Hum.Parent::any
		local torso = char:FindFirstChild("Torso")
		local model = self._model
		model.mtr.Enabled = false
		model.strap.Enabled = true
		model.strap.Part1 = model.Hold
		model.strap.Part0 = torso
		model.Parent = char
	end

	baseWep.unwield(self)
end


--- attack
module.attack = require(script.attack)



return table.freeze(module)
