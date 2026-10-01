--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_atkStart: number,
}

local CUT = 0.2
local GRACE = 0.1 -- the first 0.1s of an attack is unprotected, so mashing attack is not a shield

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	self._atkStart = 0

	self:addConnection(humObj.attacking.Changed:Connect(function(attacking: boolean)
		if attacking then self._atkStart = tick() end
	end))

	-- incoming, so beforeAttacked like Underdog
	self:addConnection(humObj.beforeAttacked:Connect(function(attack)
		if humObj.attacking.Value ~= true or tick() - self._atkStart < GRACE then return end
		attack.dmgMult = math.max(0, attack.dmgMult - CUT)
	end))

	return self
end

return table.freeze(module)
