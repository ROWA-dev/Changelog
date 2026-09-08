--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local Debris = game:GetService("Debris")

export type myself = baseClass.myself & {
	_cape: BasePart?,
}

local CRIT_CHANCE = 0.2 -- rowa1 rolled math.random(1,5) == 1 per hit
local CRIT_BONUS  = 1   -- on top of the seeded 1x, so a crit is rowa1's 2x
local OTHER_CUT   = 0.15

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- rolled per HIT, not per swing, and the crit is carried ON the attack: one
	-- swing can land on several victims and each is its own roll.
	self:addConnection(humObj.beforeAttack:Connect(function(attack)
		if not attack:isWep() then
			attack.dmgMult = math.max(0, attack.dmgMult - OTHER_CUT)
			return
		end
		if math.random() >= CRIT_CHANCE then return end
		attack.dmgMult += CRIT_BONUS
		attack.frontlinerCrit = true
	end), "frontliner")

	-- feedback waits for resolution: a parried or blocked crit never landed.
	-- rowa1's own bstreak/Crit, cloned onto the victim: inline VFX, no quiver id.
	self:addConnection(humObj.onAttack:Connect(function(attack)
		if not (attack.frontlinerCrit and attack:isHit()) then return end
		local victim = attack.enemyEntity
		local at = victim and (victim.getFxPart and victim:getFxPart() or victim.HRootPart)
		if at == nil then return end

		local streak = script.bstreak:Clone()
		streak.Parent = at
		streak:Emit(math.floor(attack:CalculateDamage())) -- rowa1 emitted one per point of damage
		Debris:AddItem(streak, 4)

		local sound = script.Crit:Clone()
		sound.Parent = at
		sound:Play()
		Debris:AddItem(sound, 4)
	end), "frontlinerCrit")

	local char = humObj.Hum and humObj.Hum.Parent
	local torso = char and char:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local cape = script:WaitForChild("Cape"):Clone() :: BasePart
		local weld = cape:FindFirstChild("Weld") :: Weld
		weld.Part0 = cape
		weld.Part1 = torso
		cape.Parent = char
		self._cape = cape
	end

	return self
end

function module.destroy(self:myself)
	self:remConnection("frontliner")
	self:remConnection("frontlinerCrit")
	if self._cape then self._cape:Destroy() end
	baseClass.destroy(self)
end

return table.freeze(module)
