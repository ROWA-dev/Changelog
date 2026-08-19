--!strict
-- by air ofc <3
local class = script.Parent.Parent:WaitForChild("Class")
local interface = require(class:WaitForChild("ItemFrameInterface"))
type itemUI = interface.itemUI
export type myself = interface.itemFrame & {
	Frame: Frame&{emptyText:TextLabel, num:TextLabel},
	item: itemUI?,

	setItem: (self:myself, item:itemUI?)->(),
	
	new: ()->myself,
	destroy: (self:myself)->(),
}

local module = {}
module.__index = module


function module.new():myself
	local self = setmetatable({
		Frame = script.IF:Clone(),
		item = nil
	}, module) :: any&myself
	return self
end

function module.destroy(self:myself)
	self.Frame:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end


--- methods


function module.setItem(self:myself, item:itemUI?)
	if self.item then
		self.item:destroy()
	end
	self.item = item
	if item then
		item.Frame.Parent = self.Frame
	end
end


return table.freeze(module)
