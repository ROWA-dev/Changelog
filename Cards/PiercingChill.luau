--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

--- extra damage the chilled take, additive onto dmgMult like Underdog/Hemorrhage
local DEF_CUT = 0.05

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- outgoing, so it rides beforeAttack (Frontliner's hook), the last stop before
	-- the defender reads the damage. Chilled == a live Freeze, meter or full stop.
	self:addConnection(humObj.beforeAttack:Connect(function(attack)
		local victim = attack.enemyEntity
		if victim == nil then return end
		if victim.statusEffects:get(humObj.statusEffects.Freeze) == nil then return end
		attack.dmgMult += DEF_CUT
	end), "piercingChill")

	return self
end

function module.destroy(self:myself)
	self:remConnection("piercingChill")
	baseClass.destroy(self)
end

return table.freeze(module)
