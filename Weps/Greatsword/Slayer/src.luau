--!strict
--[[ Slayer - rowa1 Items/Weps/Slayer/Main (613 lines, ties Katana for the
	largest rowa1 weapon). Notes: README.md/PORTW_Slayer, PORTW_00 first.

	!! PORTW_Slayer IS SUBSTANTIALLY WRONG ABOUT THIS WEAPON. It describes
	"a FIVE-HIT m1 chain" whose five dmg tables escalate and "that is the
	entire weapon". None of that survives reading Main:

	  1. THE m1 IS THREE LINKS, not five. `combo` runs 0 -> 1 -> 2 -> 0
	     (Main:385/413/441) and MeleeAnims/Slayer only ever had THREE attack
	     animations: Atk1, Atk2, Atk3. There is no Atk4 or Atk5 to rename, so
	     the doc's step 4 ("there must be FIVE swings named swing1..swing5")
	     could never have been followed.

	  2. ALL THREE m1 LINKS USE THE SAME ROW, `slM1`. They differ only in
	     flinch direction and, on link 3, a knockback. So the "designed
	     escalation curve" the doc tells you to copy is not in the m1 at all.

	  3. slM2/slM3/slM4/slM5 ARE ALL INSIDE THE HEAVY, which is a
	     GRAB-AND-DRAG, not a swing:
	         slM2  the catch. On anything but parry/dodge the victim is
	               WELDED TO THE BLADE and carried.
	         slM3  a guard-break beat once they are on the blade
	         slM5  x13 at 0.05s, the grind while you drag them forward
	         slM4  the launch that ends it
	     That IS the escalation, and it is one move rather than a chain.

	  4. `gsM2` is the DOWNSLAM (Damage id 6), not "the heavy".

	  So the doc's WATCH -- "slM2's stun 2.0 mid-chain means links 3-5 are
	  guaranteed, a 74-damage confirmed combo off one m1" -- is reasoning
	  about a chain that does not exist. The 2.0 stun is the GRAB HOLD. It is
	  supposed to be guaranteed; that is what being impaled on a sword is.

	FAMILY: Heavy/Greatsword, alongside Executer, which the doc did get
	right. Built on Executer's shape rather than Claymore's -- Greatsword
	parks the model on unequip, so there is no `strap` weld to invent, and
	rowa1's own Motor6D name carries over unchanged. ]]
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
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
	--- rowa1 gates the heavy on `tick() > lastHeavy + 8`, set AFTER it lands.
	humobj.cooldowns:setCooldown("heavy", 8)

	local char:any = humobj.Hum.Parent
	local model = self._model
	model.Motor6D.Part0 = char["Right Arm"]
	model.Motor6D.Part1 = model.Hold
	model.Parent = char

	self._trail = model:WaitForChild("Trail1")
	baseWep.wield(self)
end

--- attack
module.attack = require(script.attack)

return table.freeze(module)
