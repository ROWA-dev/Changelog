--!strict
-- by air ofc <3
local container = require(script.Parent:WaitForChild("ContainerClient"))
local interface = require(script.Parent:WaitForChild("ItemFrameInterface"))
local claims = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CooldownClaims"))

type anyFrame = any
export type myself = {
	open: boolean,
	uiFrame: Frame,
	container: container.myself,
	slots: {[number]: interface.itemFrame},
	holder: any, -- the carry claiming `held` (see hold)
	held: number?,
	shown: number?,
	
	draw: (self:myself, i:number)->(),
	hold: (self:myself, owner:any, i:number, shown:number)->(),
	release: (self:myself, owner:any)->(),
	update: (self:myself)->(),
	updateUI: (self:myself)->(),
	setOpen: (self:myself, open:boolean)->(),
	getGridIndex: (self:myself, point: Vector2)->number,
	
	new: (container:container.myself, uiFrame: Frame, frameClass:anyFrame)->myself,
	destroy: (self:myself)->(),
}

local module = {
	
}
module.__index = module

local itemUI = require(script.Parent:WaitForChild("ItemUI"))

-- "Banana x12". `n` overrides the count (the cursor's share, or what it leaves behind)
function module.label(serial:any, n:number?): string
	local count = n or serial.stack
	local name = serial.name or tostring(serial)
	return if count then name.." x"..count else name
end

local function build(itmFrame:interface.itemFrame, serial:any?)
	local itmUI:any = if serial then itemUI.new() else nil
	if itmUI then itmUI.name = serial.name end -- what a recount is matched on
	itmFrame:setItem(itmUI)
end

function module.new(container:container.myself, uiFrame: Frame, frameClass:anyFrame):myself
	local self = setmetatable({
		open = false,
		uiFrame = uiFrame,
		container = container,
		slots = table.create(container.sz)
	}, module) :: any&myself
	self.container = container
	
	local slots:any = self.slots
	for i = 1,container.sz do
		local newIFrame = frameClass.new()
		newIFrame.Frame.Parent = uiFrame
		slots[i] = newIFrame
	end
	
	container.ItemUpdated:Connect(function(index: number, newItm: any?)
		local itmFrame:interface.itemFrame = slots[index]
		local old:any = itmFrame.item
		-- a recount of the same stack keeps its ItemUI, so the equip border and cd wipe survive
		if not (old and newItm and newItm.stack and old.name == newItm.name) then
			build(itmFrame, newItm)
		end
		self:draw(index)
		self:updateUI()
	end)
	
	container.ItemMoved:Connect(function(prev: number, moveTo: number) 
		local itmFrame:interface.itemFrame = slots[prev]
		if itmFrame.item then
			local moveToFrame:interface.itemFrame = slots[moveTo]
			if moveToFrame.item == nil then
				local thisItmUI = itmFrame.item
				itmFrame.item = nil
				moveToFrame:setItem(thisItmUI)
				itmFrame:setItem(nil)
			else
				local thisItmUI = itmFrame.item
				local moveToItmUI = moveToFrame.item
				itmFrame.item = nil
				moveToFrame.item = nil
				itmFrame:setItem(moveToItmUI)
				moveToFrame:setItem(thisItmUI) 
			end
		end
		self:draw(prev)
		self:draw(moveTo)
		self:updateUI()
	end)
	
	-- an ability's cooldown draws ON its slot instead of in the cooldowns list.
	-- claim() is what tells the list to stay out of it.
	container.onCooldown:Connect(function(indx: number, seconds: number, cdId: string) 
		claims.claim(cdId)
		local itmFrame:interface.itemFrame = slots[indx]
		local item = itmFrame and itmFrame.item
		if item then
			item:cooldown(seconds)
		end
	end)
	
	container.onEquip:Connect(function(equipping: boolean, indx: number) 
		local itmFrame:interface.itemFrame = slots[indx]
		local item = itmFrame.item
		if item then
			item:select(equipping)
		end
	end)
	
	self:updateUI()
	return self
end

function module.destroy(self:myself)
	local container = self.container
	assert(container.sz, "container destroyed before ui is destroyed...")
	
	local slots = self.slots
	for i = 1,container.sz do
		slots[i]:destroy()
	end
	
	table.clear(self)
	setmetatable(self, nil)
end


--- methods

function module.updateUI(self:myself)
	--[[local open = self.open
	local slots = self.slots
	for i = 1,self.container.sz do
		local itmFrame:interface.itemFrame = slots[i]
		local frame = itmFrame.Frame
		
		if itmFrame.item then
			frame.Visible = true
		else
			frame.Visible = false
		end
	end]]
end

function module.update(self:myself)
	for i = 1,self.container.sz do
		build(self.slots[i], self.container.slots[i])
		self:draw(i)
	end
	self:updateUI()
end

-- one slot's label, minus the cursor's claim on it; a fully claimed slot hides
function module.draw(self:myself, i:number)
	local itmUI = self.slots[i].item
	local serial = self.container.slots[i]
	if itmUI == nil or serial == nil then return end
	local shown = if self.held == i then self.shown else nil
	itmUI.Frame.Visible = shown ~= 0
	itmUI.Frame.TextButton.Text = module.label(serial, shown)
end

-- inventoryUI's carry claims part of slot i: it draws `shown` until release(owner)
function module.hold(self:myself, owner:any, i:number, shown:number)
	local prev = self.held
	self.holder, self.held, self.shown = owner, i, shown
	if prev and prev ~= i then self:draw(prev) end
	self:draw(i)
end

function module.release(self:myself, owner:any)
	local i = self.held
	if self.holder ~= owner or i == nil then return end
	self.holder, self.held, self.shown = nil, nil, nil
	self:draw(i)
end


function module.setOpen(self:myself, open:boolean)
	self.open = open
	self:updateUI()
end

local CELL_SIZE = 60
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
