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
	
	local slots:any = self.slots
	for i = 1,container.sz do
		local frame:itemFrameClass.myself = slots[i]
		frame.Frame.Visible = true
	end
	
	return self
end

function module.destroy(self:myself)
	-- destroy my own stuff here
	baseClass.destroy(self)
end


--- methods


local ts = game:GetService("TweenService")
function module.updateUI(self:myself)
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local DEFAULT_SIZE = script.ItemFrame.IF.Size

	local open = self.open
	local slots = self.slots
	for i = 1,self.container.sz do
		local itmFrame:itemFrameClass.myself = slots[i]
		local frame = itmFrame.Frame
		local item = itmFrame.item
		if open == false and item == nil then
			ts:Create(frame, tweenInfo, {
				Size = UDim2.new(0,0,0,60)
			}):Play()
			frame.emptyText.Visible = false
			frame.num.Visible = false
		else
			ts:Create(frame, tweenInfo, {
				Size = DEFAULT_SIZE
			}):Play()
			frame.num.Text = tostring(i)
			frame.num.Visible = true
			frame.emptyText.Visible = true
			if item then
				frame.emptyText.Transparency = 1
			else
				frame.emptyText.Transparency = 0.6
			end
		end

	end
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

	local slots = self.slots
	for i = 1,self.container.sz do
		local itmFrame:itemFrameClass.myself = slots[i]
		local slotFrame = itmFrame.Frame
		--local item = itmFrame.item

		local pos = slotFrame.AbsolutePosition
		local size = slotFrame.AbsoluteSize

		if point.X >= pos.X and point.X <= pos.X + size.X and point.Y >= pos.Y and point.Y <= pos.Y + size.Y then
			return i
		end
	end
	
	return 0
end


return table.freeze(module)
