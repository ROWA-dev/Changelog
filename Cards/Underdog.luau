--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	
	self:addConnection(
		humObj.beforeAttacked:Connect(function(attack) -- under dog card
			local victim:Humanoid   = attack.enemyEntity.Hum
			local attacker:Humanoid = attack.myEntity.Hum

			-- if victim(humobj) has less health than the attacker then
			if victim.Health < attacker.Health then
				-- deal 15% less
				attack.dmgMult = math.max(0, attack.dmgMult - 0.15)
			end
		end)
	)
	
	
	return self
end

return table.freeze(module)
