--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	-- my own stuff here
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	-- my own stuff here
	
	self:addConnection(
		humObj.onAttacked:Connect(function(attack, returnValue: number) 
			if attack:isParried() then
				humObj.walkSpeed:SetMod("parry", 4)
				task.wait(1) -- TODO why this hold heap?
				humObj.walkSpeed:RemoveMod("parry")
			end
		end),
		"speedOnParry"
	)
	
	
	return self
end

function module.destroy(self:myself)
	-- destroy my own stuff here
	self:remConnection("speedOnParry")
	baseClass.destroy(self)
end

return table.freeze(module)
