--!strict
local signal = require(game.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Signal"))
local baseClass = require(game.ReplicatedStorage.Class.baseContainer)

type anyItem = any
type serialItem = any

export type myself = baseClass.myself & {
	-- my own stuff here
	slots: {[number]: anyItem},
	replicationID: number,
	onEquip: signal.Signal<boolean, number>,
	onCooldown: signal.Signal<number, number, string>, -- index, seconds, cdId
	initReplicateClient: (self: myself, remoteEvent:RemoteEvent, containerID:number)->(),
	uploadSerialData: (self:myself, data:any)->(),
	SubscribedEventCB: (id:number, any, any, any)->(),
}

local module = {}
--module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(width:number, height:number):myself
	local abstract = baseClass.new(width, height) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self.onEquip = signal.new()
	self.onCooldown = signal.new()
	-- my own stuff here
	return self
end

function module.destroy(self:myself)
	-- destroy my own stuff here
	self.SubscribedEventCB = nil
	self.onEquip:Destroy() -- neither of these was being destroyed
	self.onCooldown:Destroy()
	baseClass.destroy(self)
end


--- methods


function module.uploadSerialData(self:myself, data:any)
	local slots = self.slots

	for i = 1,self.sz do
		slots[i] = nil
	end

	if data.s == nil then return end
	for _,entry in pairs(data.s) do
		local i = entry[1]
		local serialItem = entry[2]
		slots[i] = serialItem
	end
end


local inventoryEnums = require(game.ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Inventory"):WaitForChild("enums"))
function module.initReplicateClient(self:myself, remoteEvent:RemoteEvent, containerID:number)
	self.replicationID = containerID
	self.SubscribedEventCB = function(id:number, ...) 
		if id == inventoryEnums.itemUpdated then -- item updated
			local index, serialItem = ...
			self:set(serialItem, index)
		elseif id == inventoryEnums.itemMoved then
			local prev, nex = ...
			self:move(prev, nex)
		elseif id == inventoryEnums.itemCooldown then
			local index, seconds, cdId = ...
			self.onCooldown:Fire(index, seconds, cdId)
		elseif id == inventoryEnums.itemEquip then
			local equipping, index = ...
			self.onEquip:Fire(equipping, index)
			--[[warn(equipping, index, self.slots[index])
			local found = self.slots[index]
			if found then
				found:
			end]]
		end
	end
end


return table.freeze(module)
