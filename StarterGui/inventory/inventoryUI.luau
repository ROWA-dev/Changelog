--!strict
local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local plrObj = clientData.plrObj
local lplr = game.Players.LocalPlayer

local inventoryRemote = game.ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Inventory")
local inventoryEnums = require(inventoryRemote:WaitForChild("enums"))

local class = script:WaitForChild("Class")
local container = require(class:WaitForChild("ContainerClient"))
local inventoryContainer = container.new(10, 3)
local hotbarContainer    = container.new(10, 1)
local outsideContainer:container.myself? = nil
   
-- visual containers
local otherContainerFrame = script.Parent:WaitForChild("otherContainerFrame")
local outsideFrame = otherContainerFrame:WaitForChild("container")
local horbarFrame = script.Parent:WaitForChild("hotbar")
horbarFrame.Visible = true

local inventoryUI = require(script:WaitForChild("InventoryUI")).new(
	inventoryContainer,
	script.Parent:WaitForChild("backpack")
)

local hotbarUI = require(script:WaitForChild("HotbarUI")).new(
	hotbarContainer,
	horbarFrame
)

local outsideContainerUI:any? = nil

inventoryUI:setOpen(false)
hotbarUI:setOpen(false)

-- the carried ("held on the cursor") item lives up here because closing the bag
-- or a chest has to be able to put it back, and both of those happen below.
local selection = script.Parent:WaitForChild("selection")
local carrying:any? = nil

-- what the cursor is over, hoisted for the same reason. refContainer/refIndex are
-- STICKY -- a miss leaves the last hit sitting there -- so `hoverHit` is the only
-- thing that means "really on a slot right now". The number-key swap below needs
-- that, because unlike a click there is no press to vouch for the position.
local refContainer:any = nil
local refIndex:number? = nil
local hoverHit = false

local function resetSelectionLook()
	selection.BackgroundColor3 = Color3.new(1, 1, 1)
	selection.UIStroke.Color = Color3.new(1, 1, 1)
	selection.UIStroke.Thickness = 0.5
end

-- put a held item back in the slot it came from. closing the inventory mid-drag
-- used to leave the frame parented to `selection`, so the item read as deleted
-- (empty slot) AND `carrying` stayed set, which wedged every later drag.
local function cancelCarry()
	local held = carrying
	if held == nil then return end
	carrying = nil
	resetSelectionLook()

	local itemUI = held.item
	local frame = itemUI and itemUI.Frame
	if frame == nil or frame.Parent == nil then return end -- a server update already ate it

	local home = held.sourceFrame and held.sourceFrame.Frame
	if home and home.Parent then
		frame.Parent = home
	else
		frame:Destroy() -- home is gone (chest closed under us), don't leak it into `selection`
	end
end

local function closeOutsideContainer()
	cancelCarry() -- might be holding something FROM this chest
	otherContainerFrame.Visible = false
	if outsideContainerUI then
		outsideContainerUI:destroy()
		outsideContainerUI = nil
	end
	if outsideContainer then
		if refContainer == outsideContainer then hoverHit = false end -- never aim a key at a dead chest
		inventoryRemote:FireServer(inventoryEnums.closeContainer, outsideContainer.replicationID)
		outsideContainer:destroy()
		outsideContainer = nil
	end
end

local interface = require(class:WaitForChild("ItemFrameInterface"))
local infoFrame:Frame = script.Parent:WaitForChild("info")
local prevFrame:interface.itemFrame? = nil
local isOpen = false

-- while the bag is open SHIFT belongs to shift-click, not to the camera
local shiftLock = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShiftLock"))

-- topbar button. keyboard has the ` key; touch had NO way in at all before this
local topbar = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TopbarIcons"))
local bagIcon = topbar.register({
	name      = "inventory",
	order     = 3,
	frame     = script.Parent:WaitForChild("TopbarIcon"),
	touchOnly = true,
	onClick   = function() triggerbackpack() end,
})

function triggerbackpack()
	if isOpen == false then isOpen = true
		inventoryUI:setOpen(true)
		hotbarUI:setOpen(true)
	else isOpen = false
		cancelCarry() -- BEFORE the frames it could go home to are hidden
		closeOutsideContainer()
		inventoryUI:setOpen(false)
		hotbarUI:setOpen(false)

		selection.Visible = false
		prevFrame = nil
		hoverHit = false
	end
	bagIcon:setActive(isOpen)
	shiftLock.block("inventory", isOpen) -- restores whatever it was on close
	infoFrame.Visible = isOpen
	inventoryRemote:FireServer(inventoryEnums.openInventory, isOpen)
end

local function openOutsideContainer(newContainer:container.myself, name:string?)
	if isOpen == false then -- open inventory
		triggerbackpack()
	end
	
	closeOutsideContainer()
	
	local cellSz = 65
	local widthSz = newContainer.width * cellSz
	local heightSz = newContainer.height * cellSz
	otherContainerFrame.Size = UDim2.fromOffset(widthSz, heightSz+30) 
	outsideFrame.Size = UDim2.fromOffset(widthSz, heightSz)
	
	otherContainerFrame.nameLabel.Text = name or "ROWA Chest"
	otherContainerFrame.Position = UDim2.new(0.5,0,0.5,0) -- reset cuz dragable(might be outside view..)
	otherContainerFrame.Visible = true
	
	print("opening outside container:", newContainer)
	local replicationId = 3
	newContainer:initReplicateClient(inventoryRemote, replicationId)
	
	outsideContainerUI = require(script:WaitForChild("InventoryUI")).new(
		newContainer,
		outsideFrame
	)
	
	if outsideContainerUI then
		outsideContainerUI:setOpen(true)
		outsideContainerUI:update()
	end
	
	outsideContainer = newContainer
end

inventoryRemote.OnClientEvent:Connect(function(_containerID:number, id:number, ...) 
	--warn(_containerID, id, ...)
	if _containerID == hotbarContainer.replicationID then
		hotbarContainer.SubscribedEventCB(id, ...)
	elseif _containerID == inventoryContainer.replicationID then
		inventoryContainer.SubscribedEventCB(id, ...)
	elseif outsideContainer and _containerID == outsideContainer.replicationID then
		outsideContainer.SubscribedEventCB(id, ...)
	elseif id == inventoryEnums.newContainer then
		local serialData = ...
		local newContainer = container.new(serialData.width, serialData.height)
		
		print("opening outside serial:", serialData)
		
		newContainer:uploadSerialData(serialData)
		openOutsideContainer(newContainer, serialData.name)
	else
		warn("inventory no container was found for:", _containerID, id, ...)
	end
end)

local replicationInit = false
plrObj.slotLoaded:Connect(function(slotData, serialData) 
	--print(slotData, serialData)
	local slotInventory = serialData.inventory
	local slotHotbar = serialData.hotbar
	--print("SLOT LOADED REUPLOAD!", serialData)
	if replicationInit == false then replicationInit = true
		--print("INIT REPLICATE", slotHotbar, slotInventory)
		inventoryContainer:initReplicateClient(inventoryRemote, slotInventory.replicationId)
		hotbarContainer:initReplicateClient(inventoryRemote, slotHotbar.replicationId)
	end
	inventoryContainer:uploadSerialData(slotInventory)
	hotbarContainer:uploadSerialData(slotHotbar)
	inventoryUI:update()
	hotbarUI:update()
end)


local remoteFunc = game.ReplicatedStorage:WaitForChild("RemoteFunction")

local function hotbarUse(index:number)	
	--equipItem(hotbarObj:GetItem(number))
	inventoryRemote:FireServer(inventoryEnums.selectHotbar, index)
	--[[local itemFrame = hotbarUI.slots[index]
	local item = itemFrame.item
	if item then
		item:select(true)
	end]]
end

-- minecraft's "hover a slot, press a hotbar number": that item goes to hotbar
-- slot `index`, and whatever was in it comes back to the slot you're pointing at.
-- Pointing at an EMPTY slot pulls the hotbar item out instead, also like mc.
-- Returns false when it doesn't apply, so the key falls back to equipping.
local function hotbarSwap(index:number): boolean
	if isOpen == false or hoverHit == false or carrying then return false end
	local from, fromIndex = refContainer, refIndex
	if from == nil or fromIndex == nil then return false end
	if from == hotbarContainer and fromIndex == index then return false end -- itself

	local to, toIndex = hotbarContainer::any, index
	if from.slots[fromIndex] == nil then -- hovering an empty slot: pull, don't push
		if hotbarContainer.slots[index] == nil then return false end -- both empty, no-op
		from, fromIndex, to, toIndex = hotbarContainer, index, from, fromIndex
	end

	-- deliberately NOT optimistic, same as quickMove: move/transfer replicate back
	-- and the normal redraw is what moves the frames.
	if from == to then
		remoteFunc:InvokeServer("moveItem", from.replicationID, fromIndex, toIndex)
	else
		remoteFunc:InvokeServer("transferItem", from.replicationID, to.replicationID, fromIndex, toIndex)
	end
	return true
end

local modules = game.ReplicatedStorage:WaitForChild("Modules")
local keybindEnums = require(modules.keybindEnums)
local bindFuncs    = require(modules.bindFuncs)
for i = 1, 10 do
	bindFuncs[keybindEnums["hotbar"..i]] = function(down) -- lambda
		if not down then return end
		if hotbarSwap(i) then return end -- bag open + cursor on a slot: swap, don't equip
		hotbarUse(i)
	end
end


---

local function setSelection(itemFrame)
	if prevFrame ~= itemFrame then
		if itemFrame ~= nil then
			selection.Visible = true
			local absolutePos = itemFrame.Frame.AbsolutePosition
			--selection.Position = UDim2.fromOffset(absolutePos.X, absolutePos.Y)
			game.TweenService:Create(selection, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(absolutePos.X, absolutePos.Y)
			}):Play()
		else
			selection.Visible = false
		end
		prevFrame = itemFrame
	end
end

local function startCarry(slotFrame:interface.itemFrame, sourceContainerId, sourceIndex)
	if carrying then
		local held = carrying.item
		if held and held.Frame and held.Frame.Parent then return end -- genuinely still carrying
		cancelCarry() -- stale: a server update destroyed the frame under us
	end
	if not slotFrame or not slotFrame.item then return end
	
	selection.BackgroundColor3 = Color3.new(0.494118, 0.764706, 1)
	selection.UIStroke.Color = Color3.new(0.494118, 0.764706, 1)
	selection.UIStroke.Thickness = 1

	selection.Rotation = 0 -- ensure starting rotation
	
	local ts = game.TweenService
	local rot = math.random(1, 2) * 2 - 3
	local rotateOut = ts:Create(selection, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Rotation = rot*8
	})
	local rotateBack = ts:Create(selection, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Rotation = 0
	})
	rotateOut:Play()
	rotateOut.Completed:Connect(function()
		rotateBack:Play()
	end)
	

	--slotFrame:setItem(nil)
	slotFrame.item.Frame.Parent = selection
	carrying = {
		sourceContainer = sourceContainerId,
		sourceIndex = sourceIndex,
		sourceFrame = slotFrame,
		item = slotFrame.item,
		--quantity = slotFrame.item.quantity or 1,
	}
end

local function stopCarryAndSendRequest(prevFrame:interface.itemFrame, refContainer, refIndex)
	if not carrying then return end
	resetSelectionLook()
	
	if refContainer and refIndex then
		if carrying.sourceContainer == refContainer then
			local prevParent = carrying.sourceFrame.Frame
			local parentTo = prevFrame.Frame
			
			carrying.item.Frame.Parent = parentTo -- ghost it
			local prevItem = prevFrame.item
			if prevItem then
				prevItem.Frame.Parent = carrying.sourceFrame.Frame
			end
			local success = remoteFunc:InvokeServer("moveItem", refContainer.replicationID, carrying.sourceIndex, refIndex)
			-- TODO maybe item might be moved somewhere else whilest this is waiting? race condition
			if success then
				carrying.item.Frame.Parent = parentTo
				if prevItem then
					prevItem.Frame.Parent = carrying.sourceFrame.Frame
				end
			else
				if prevItem then
					prevItem.Frame.Parent = prevFrame.Frame
				end
				if carrying then -- TODO this errored so added carrying but might need to check for carrying.item too?
					carrying.item.Frame.Parent = prevParent
				end
			end
		else
			local prevParent = carrying.sourceFrame.Frame
			local parentTo = prevFrame.Frame
			print("move into another contianer!", carrying.sourceIndex, refIndex)
			
			local success = remoteFunc:InvokeServer("transferItem",
				carrying.sourceContainer.replicationID, -- from container
				refContainer.replicationID, -- to container
				carrying.sourceIndex, -- from index
				refIndex -- toindex
			)
			if success then
			else
				carrying.item.Frame.Parent = prevParent
			end
		end
	else
		carrying.item.Frame.Parent = carrying.sourceFrame.Frame
	end
	carrying = nil
end

local uis = game:GetService("UserInputService")

-- minecraft's shift-click: send the item to the OTHER container, no aiming.
-- the SERVER picks the destination + slot (see RFHandler/quickMoveItem), so we
-- send no target and just let the normal itemUpdated replication redraw us.
local function quickMove(refContainer, refIndex)
	if carrying then return end
	if refContainer == nil or refIndex == nil then return end
	if refContainer.slots[refIndex] == nil then return end -- empty slot
	remoteFunc:InvokeServer("quickMoveItem", refContainer.replicationID, refIndex)
end

local function shiftHeld(): boolean
	return uis:IsKeyDown(Enum.KeyCode.LeftShift) or uis:IsKeyDown(Enum.KeyCode.RightShift)
end

uis.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed == true then return end
	if input.KeyCode == Enum.KeyCode.Backquote then
		triggerbackpack()
	end
end)


-- reset binds?
clientData:setupBinds()

-- point -> the slot under it, returns false if the point hit no grid. TOUCH
-- calls this too now: the hover used to be MouseMovement-only, so on mobile
-- refContainer/refIndex/prevFrame never got set and every drag was dead on
-- arrival. The boolean matters because refIndex is STICKY -- on a miss it
-- still points at the last slot hovered, which a tap must not act on.
local function hoverAt(p: Vector2): boolean
	if isOpen == false then return false end

	local hotbarIndex = hotbarUI:getGridIndex(p)
	local inventoryIndex = inventoryUI:getGridIndex(p)
	local outsideIndex = if outsideContainerUI then outsideContainerUI:getGridIndex(p) else 0
	if hotbarIndex ~= 0 then
		--print("hotbar:", hotbarIndex, hotbarUI.slots[hotbarIndex])
		local slot = hotbarUI.slots[hotbarIndex]
		refContainer = hotbarContainer
		refIndex = hotbarIndex
		setSelection(slot)
		return true
	elseif inventoryIndex ~= 0 then
		--print("inventory:", inventoryIndex, inventoryUI.slots[inventoryIndex])
		local slot = inventoryUI.slots[inventoryIndex]
		refContainer = inventoryContainer
		refIndex = inventoryIndex
		setSelection(slot)
		return true
	elseif outsideIndex ~= 0 and outsideContainer then
		local slot = outsideContainerUI.slots[outsideIndex]
		refContainer = outsideContainer
		refIndex = outsideIndex
		--warn("OUTSIDE CONTAINER!", slot, refContainer, refIndex)
		setSelection(slot)
		return true
	end
	return false
end

uis.InputChanged:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch then
		local inputP = input.Position
		hoverHit = hoverAt(Vector2.new(inputP.X, inputP.Y))
	end
end)

-- touch has no hover, so a press is ambiguous: it could open a drag, or it
-- could be a tap (= equip). Decided on release by whether the finger left the
-- slot it started on. A second tap on that same slot is the quickMove, since
-- there is no shift key to hold.
local TAP_TIME   = 0.3
local DOUBLE_TAP = 0.35
local touchDown:{t:number, index:number?, container:any}? = nil
local lastTap = {t = 0, index = 0, container = nil::any}

uis.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
	local inputType = input.UserInputType
	local isTouch = inputType == Enum.UserInputType.Touch
	if inputType == Enum.UserInputType.MouseButton1 or isTouch then
		if isTouch then
			local inputP = input.Position
			-- no hover on touch: resolve on press. a miss records nothing, so the
			-- closed-bag hotbar tap below stays the only thing that fires.
			local hit = hoverAt(Vector2.new(inputP.X, inputP.Y))
			touchDown = if hit then {t = tick(), index = refIndex, container = refContainer} else nil
		end

		if prevFrame and prevFrame.item then
			if isTouch == false and shiftHeld() then
				quickMove(refContainer, refIndex)
				return
			end
			startCarry(prevFrame, refContainer, refIndex)
		else -- default
			local inputP = input.Position
			local p = Vector2.new(inputP.X, inputP.Y)

			local hotbarIndex = hotbarUI:getGridIndex(p)
			if hotbarIndex ~= 0 then
				--print(hotbarIndex)
				hotbarUse(hotbarIndex)
			end
		end
	end
end)
uis.InputEnded:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
	local inputType = input.UserInputType
	local isTouch = inputType == Enum.UserInputType.Touch
	if inputType == Enum.UserInputType.MouseButton1 or isTouch then
		local down = touchDown
		touchDown = nil
		if isTouch and down and down.index ~= nil
			and down.index == refIndex and down.container == refContainer
			and tick() - down.t < TAP_TIME
		then -- never left the slot it pressed: a tap, not a drag
			cancelCarry()

			local twice = lastTap.index == down.index and lastTap.container == down.container
				and tick() - lastTap.t < DOUBLE_TAP
			lastTap.t, lastTap.index, lastTap.container = tick(), down.index, down.container
			if twice then
				lastTap.t = 0 -- don't let a third tap re-fire
				quickMove(down.container, down.index)
			elseif down.container == hotbarContainer then
				hotbarUse(down.index)
			end
			return
		end

		if prevFrame then
			stopCarryAndSendRequest(prevFrame, refContainer, refIndex)
		else
			cancelCarry() -- released with no slot under the pointer
		end
	end
end)

otherContainerFrame:WaitForChild("exit").MouseButton1Up:Connect(closeOutsideContainer)

plrObj.onDataRecieve:Connect(function(data: clientData.plrObjData) 
	--warn("on data rec",data)
	closeOutsideContainer()
	local empty = {}
	inventoryContainer:uploadSerialData(empty)
	hotbarContainer:uploadSerialData(empty)
	inventoryUI:update()
	hotbarUI:update()
end)


local startergui = game:GetService("StarterGui")
repeat
	local load = pcall(function() startergui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
	wait(0.2)
until load