--!strict
--[[ Oblitar - rowa1 Items/Weps/Oblitar/Main (585 lines).
	Notes: README.md/PORTW_Oblitar, and PORTW_00 for the checklist.

	A large slashing weapon whose HEAVY IS TWO BEATS, the second of which
	decapitates a victim at low health (rowa1's `oblH2`, one of the five ids
	in AttackModule's `decapitation` set). That finisher is the whole reason
	the second beat exists -- see Modules/execute.

	FAMILY: Heavy/GreatAxe. PORTW_Oblitar argued Medium/Swords from the
	numbers (oblM1/oblH/oblH2 are all Medium WEIGHT) and it shipped there
	first, but weight class and family are different questions -- it plays as
	an axe closer to Executer than to Claymore, so it moved. See GreatAxe for
	what that inheritance actually changes (Heavy recovers faster from a parry
	and stuns on block; Medium does neither).

	THE dmgTbl WEIGHTS ARE STILL Medium, deliberately. That field is the
	ATTACK weight -- it decides trades -- and rowa1 authored all three rows as
	Medium. Executer's m1 is Heavy. Moving family did not change those rows on
	its own; if the axe should win trades like Executer, that is a separate
	one-word call in dmgConfig, not a consequence of this move.

	!! TWO CORRECTIONS TO PORTW_Oblitar, both from reading Main rather than
	the doc:

	  1. THE HEAVY IS NOT A CHARGE. The doc's step 4 says
	     "heavyStart -> heavy, heavyEnd -> heavy2", which describes Katana's
	     hold-and-release. rowa1's Oblitar is nothing like that: ONE press
	     (`typ == 2`) plays the whole two-beat sequence automatically, with
	     cancel checks between beats and a 5s internal gate
	     (`tick() > lastHeavy + 5`). So there is no heavyEnd binding here and
	     adding one would require a release the player never makes.

	  2. THE THRUST USES oblM1, NOT oblH2. `Damage(6)` -- the thrust's hit --
	     resolves `oblM1`. oblH2 is `Damage(9)`, the heavy's second beat.
	     The two sit near each other in a 9-branch if-chain and are easy to
	     transpose; the doc's numbers table is right, its mapping was not.

	onParried is NOT implemented here on purpose: PORTW_00 step 7 calls it
	mandatory per weapon, but Medium already defines it and Katana/Claymore
	both rely on that. Adding a local one would just shadow the family's. ]]
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

	--[[ rowa1's `local AtkRate = 1.05`, its one Settings constant. PORTW_00
		maps it to self.atkRate and OMITTING IT WAS A REAL MISS -- it is not
		cosmetic. atkRate does two things at once, matching rowa1 exactly:
		  * scaledTime multiplies EVERY wait by it, so windups, beats and
		    endlag all stretch 5% (CombatAction.scaledTime)
		  * PlayAnim divides anim speed by it -> 1/1.05 = 0.952, which is
		    literally rowa1's `AtkAnim:AdjustSpeed(1/AtkRate)`
		Without it the weapon ran at 1.0 on both, so every swing was 5% quick
		AND the animation played 5% fast on top -- which is what read as the
		windup being too fast.
		AdditiveValue is base 1, so the mod is the 0.05 delta, not 1.05. ]]
	self.atkRate:SetMod("oblitar", 0.05)
	return self
end

--[[ ORDER MATTERS HERE, and it changed when this moved to Heavy.
	Medium.destroy has its `self:unequip()` COMMENTED OUT, so destroying the
	model first was safe under Swords. Heavy.destroy DOES call unequip, and
	GreatAxe.unequip does `self._model.Parent = script` -- on an instance we
	had already destroyed, which throws "The Parent property is locked".
	So: unequip FIRST, then drop the model.
	Executer and StarkAxe never destroy their clone at all and leave it parked
	under the family module; this keeps the cleanup, which is the house RAM
	rule, without fighting the family's order. ]]
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

	--[[ 5, not Claymore's 10. rowa1 gated this heavy on
		`tick() > lastHeavy + 5` and set lastHeavy AFTER the second beat
		landed, so the real gap is 5s from the END of the sequence. Kept as
		written; it is short for a two-beat heavy and is the first number to
		revisit if the weapon reads as oppressive. ]]
	humobj.cooldowns:setCooldown("heavy", 5)
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
