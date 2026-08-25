--!strict
--- Slayer - rowa1 Items/Weps/Slayer/Main. Notes: README.md/PORTW_Slayer,
--- PORTW_00 first.
--- !! THE DOC IS SUBSTANTIALLY WRONG: there is no five-hit m1 chain.
---   m1 is THREE links (combo 0->1->2->0, and only Atk1/2/3 exist), and all
---   three share the SAME row, slM1 -- they differ only in flinch direction.
---   slM2/3/5/4 are the four beats of the HEAVY, which is a grab-and-drag:
---   catch (welds them to the blade), guard-break, x13 grind, launch. THAT is
---   the escalation the doc thought was an m1 chain, and it is one move.
---   gsM2 is the DOWNSLAM, not "the heavy".
---   So the doc's 74-damage-confirmed-combo warning reasons about a chain that
---   does not exist; slM2's 2.0 stun is the GRAB HOLD and is meant to be guaranteed.
--- FAMILY: Heavy/Greatsword, built on Executer's shape -- Greatsword parks the
--- model on unequip, so there is no `strap` weld to invent.
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	arialCD = 2,
	postureGain = 6,
	Name = "Slayer",
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	self._model = script.Model:Clone()

	--[[ rowa1's `local AtkRate = 1.18` (its comment records 1.1 as the
		previous value). PORTW_00 trap 2: this scales every wait through
		scaledTime AND divides anim speed in PlayAnim, so omitting it runs
		the weapon fast on both axes. AdditiveValue is base 1 -> pass the
		delta. This is the slowest AtkRate of any rowa1 weapon read so far,
		which is the whole character of a greatsword this size. ]]
	self.atkRate:SetMod("slayer", 0.18)
	return self
end

--[[ unequip FIRST -- Heavy.destroy calls it and Greatsword.unequip re-parents
	the model, which throws on an instance we already destroyed. PORTW_00
	trap 1's sibling; see Oblitar for the long version. ]]
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
	humobj.cooldowns:setCooldown("heavy", 10)

	local char:any = humobj.Hum.Parent
	local model = self._model
	model.Motor6D.Part0 = char["Right Arm"]
	model.Motor6D.Part1 = model.Hold
	model.Parent = char

	self._trail = model:WaitForChild("Trail1")
	baseWep.wield(self)
end

--- unwield
--[[ Greatsword parks the model in :unequip only, so :unwield has to park it
	too or the blade stays Motor6D'd to the arm. lastAnim is stopped first
	because baseWep.unwield goes via stopLastAnim, which honours dontStopAnim. ]]
function module.unwield(self:myself&any)
	if self.lastAnim then
		self.lastAnim:Stop()
	end

	local model = self._model
	if model then
		model.Parent = script
	end

	baseWep.unwield(self)
end

--- attack
module.attack = require(script.attack)

return table.freeze(module)