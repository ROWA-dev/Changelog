--!strict
local class = script.Parent:WaitForChild("Class")
local baseClass = require(class:WaitForChild("ContainerUI"))
local container = require(class:WaitForChild("ContainerClient"))

export type myself = baseClass.myself & {
	-- my own stuff here
}

local module = {}
--module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

local itemFrameClass = require(script:WaitForChild("ItemFrame"))
function module.new(container:container.myself, uiFrame: Frame):myself
	local abstract = baseClass.new(container, uiFrame, itemFrameClass) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	-- my own stuff here
	return self
end

function module.destroy(self:myself)
	-- destroy my own stuff here
	baseClass.destroy(self)
end


--- methods

function module.setOpen(self:myself, open:boolean)
	self.uiFrame.Visible = open
	baseClass.setOpen(self, open)
end

local CELL_SIZE = 65
function module.getGridIndex(self:myself, point: Vector2): number
	local frame = self.uiFrame
	local localPos = point - frame.AbsolutePosition

	-- outside frame check
	if localPos.X < 0 or localPos.Y < 0
		or localPos.X > frame.AbsoluteSize.X
		or localPos.Y > frame.AbsoluteSize.Y then
		return 0
	end

	local col = math.floor(localPos.X / CELL_SIZE)
	local row = math.floor(localPos.Y / CELL_SIZE)

	local columns = math.floor(frame.AbsoluteSize.X / CELL_SIZE)
	local index = row * columns + col + 1 -- +1 for Lua indexing

	return index
end

return table.freeze(module)
