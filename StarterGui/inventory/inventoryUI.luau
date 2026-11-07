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

-- nil for a chest that has since closed
local function uiOf(c:any): any
	return if c == hotbarContainer then hotbarUI elseif c == inventoryContainer then inventoryUI elseif c == outsideContainer then outsideContainerUI else nil
end

local function clearSweep(held:any)
	local sweep = held.sweep
	held.sweep = nil
	if sweep then for _, s in sweep do s[3]:Destroy() end end
end

-- a carry never leaves its slot server-side (its slot just draws less, ContainerUI:hold),
-- so dropping one is pure UI: nothing to put back.
local function cancelCarry()
	local held = carrying
	if held == nil then return end
	carrying = nil
	resetSelectionLook()
	clearSweep(held)
	held.ghost:destroy()
	local ui = uiOf(held.sourceContainer)
	if ui then ui:release(held) end
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
local progressionSlot:any? = nil
local progressionCon:RBXScriptConnection? = nil
local refreshInvestmentPrompt: () -> () = function() end

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
	refreshInvestmentPrompt()
	inventoryRemote:FireServer(inventoryEnums.openInventory, isOpen)
end

-- Persistent CTA while a point pair is blocking the next draft. The actual
-- investment coaching lives inside charInfoUI once this opens the inventory.
local ACCENT = Color3.fromRGB(255, 217, 103) -- the draft LevelButton's gold
local investPrompt = Instance.new("Frame")
investPrompt.Name = "SpendPointsPrompt"
investPrompt.AnchorPoint = Vector2.new(1, 0)
investPrompt.Position = UDim2.new(1, -40, 0, 20)
investPrompt.Size = UDim2.fromOffset(270, 62)
investPrompt.BackgroundColor3 = Color3.new(0, 0, 0)
investPrompt.BackgroundTransparency = 0.6
investPrompt.BorderSizePixel = 0
investPrompt.ZIndex = 40
investPrompt.Visible = false
investPrompt.Parent = script.Parent

local promptTitle = Instance.new("TextLabel")
promptTitle.Name = "Title"
promptTitle.Position = UDim2.fromOffset(10, 8)
promptTitle.Size = UDim2.new(1, -20, 0, 20)
promptTitle.BackgroundTransparency = 1
promptTitle.Font = Enum.Font.SourceSans
promptTitle.Text = "points ready"
promptTitle.TextColor3 = ACCENT
promptTitle.TextSize = 16
promptTitle.TextXAlignment = Enum.TextXAlignment.Left
promptTitle.ZIndex = 41
promptTitle.Parent = investPrompt

local promptBody = Instance.new("TextLabel")
promptBody.Name = "Body"
promptBody.Position = UDim2.fromOffset(10, 28)
promptBody.Size = UDim2.new(1, -20, 0, 26)
promptBody.BackgroundTransparency = 1
promptBody.Font = Enum.Font.SourceSans
promptBody.Text = "open stats to unlock your next draft."
promptBody.TextColor3 = Color3.new(0.87, 0.87, 0.87)
promptBody.TextSize = 14
promptBody.TextWrapped = true
promptBody.TextXAlignment = Enum.TextXAlignment.Left
promptBody.TextYAlignment = Enum.TextYAlignment.Top
promptBody.ZIndex = 41
promptBody.Parent = investPrompt

local promptButton = Instance.new("TextButton")
promptButton.Name = "OpenStats"
promptButton.Size = UDim2.fromScale(1, 1)
promptButton.BackgroundTransparency = 1
promptButton.Text = ""
promptButton.ZIndex = 42
promptButton.Parent = investPrompt
promptButton.MouseButton1Up:Connect(function()
	if not isOpen then triggerbackpack() end
end)

refreshInvestmentPrompt = function()
	local needed = if progressionSlot then progressionSlot:pointsToNextProg() else 0
	investPrompt.Visible = not isOpen and needed > 0
	if needed <= 0 or progressionSlot == nil then return end
	local available = progressionSlot.allocPts
	promptTitle.Text = if available == 1 then "1 point left" else tostring(available) .. " points ready"
	promptBody.Text = if needed == 1
		then "spend 1 more point to unlock your next draft."
		else "open stats and spend " .. tostring(needed) .. " to unlock your next draft."
end

local function bindProgression(slotData:any)
	if progressionCon then progressionCon:Disconnect() end
	progressionSlot = slotData
	refreshInvestmentPrompt()
	progressionCon = slotData.onStatChange:Connect(function(patch)
		if patch.lvl or patch.allocPts or patch.prog then refreshInvestmentPrompt() end
	end)

	-- The starter pair teaches the loop once. Later levels use the click-to-open CTA
	-- so gaining XP never forces a combat-blocking window onto the player.
	if slotData.lvl == 1 and slotData.prog == 0 and slotData:pointsToNextProg() > 0
		and not slotData._starterInvestmentOpened
	then
		slotData._starterInvestmentOpened = true
		task.defer(function()
			if progressionSlot == slotData and not isOpen then triggerbackpack() end
		end)
	end
end

plrObj.slotLoaded:Connect(bindProgression)
if plrObj:IsSlotLoaded() and plrObj.Data then
	local existing = plrObj.Data.slots[plrObj.loadedSlotId]
	if existing then bindProgression(existing) end
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

-- the charge release (CombatAction:chargeWait). EVERY way of pressing a hotbar slot must send it, or a charge runs to full
local function hotbarRelease(index:number)
	inventoryRemote:FireServer(inventoryEnums.releaseHotbar, index)
end

local function hotbarUse(index:number)	
	--equipItem(hotbarObj:GetItem(number))
	inventoryRemote:FireServer(inventoryEnums.selectHotbar, index)
	--[[local itemFrame = hotbarUI.slots[index]
	local item = itemFrame.item
	if item then
		item:select(true)
	end]]
end

-- the whole-slot verb: same container moves, otherwise transfers
local function moveArgs(from:any, fromIndex:number, to:any, toIndex:number): ...any
	if from == to then return "moveItem", from.replicationID, fromIndex, toIndex end
	return "transferItem", from.replicationID, to.replicationID, fromIndex, toIndex
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
	remoteFunc:InvokeServer(moveArgs(from, fromIndex, to, toIndex))
	return true
end

local modules = game.ReplicatedStorage:WaitForChild("Modules")
local keybindEnums = require(modules.keybindEnums)
local bindFuncs    = require(modules.bindFuncs)
for i = 1, 10 do
	bindFuncs[keybindEnums["hotbar"..i]] = function(down) -- lambda
		if not down then
			hotbarRelease(i)
			return
		end
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

local itemUI = require(class:WaitForChild("ItemUI"))
local containerUI = require(class:WaitForChild("ContainerUI"))
local MB1, MB2 = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2

-- client stacks match on name, and only counted ones merge
local function sameStack(a:any, b:any): boolean
	return a ~= nil and b ~= nil and a.stack ~= nil and a.name == b.name
end

-- the cursor stack. Pickup sends nothing: its slot draws `shown` (stack - amount)
-- and a ghost rides `selection`. Each placement is one RF call.
local function startCarry(from:any, index:number, half:boolean, button:Enum.UserInputType)
	local serial = from.slots[index]
	if carrying or serial == nil then return end
	local stack = serial.stack or 1
	local amount = if half then math.ceil(stack / 2) else stack

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

	local ghost = itemUI.new()
	ghost.Frame.TextButton.Text = containerUI.label(serial, amount)
	ghost.Frame.Parent = selection
	carrying = {
		sourceContainer = from, sourceIndex = index, button = button, t = tick(),
		amount = amount, shown = stack - amount, ghost = ghost, sticky = false,
	}
	uiOf(from):hold(carrying, index, stack - amount)
end

-- moves units between the cursor and its own slot: no server, they never left it
local function setAmount(held:any, amount:number)
	local serial = held.sourceContainer.slots[held.sourceIndex]
	if serial == nil or amount <= 0 then cancelCarry() return end
	held.shown += held.amount - amount
	held.amount = amount
	held.ghost.Frame.TextButton.Text = containerUI.label(serial, amount)
	uiOf(held.sourceContainer):hold(held, held.sourceIndex, held.shown)
end

-- one placement off the cursor. The last one ends the carry but keeps the ghost
-- (parked on `at`) and the slot's claim until the server's redraw has landed.
local function spend(held:any, used:number, at:any?, ...:any)
	held.amount -= used
	local last = held.amount <= 0
	if last then
		if carrying == held then carrying = nil resetSelectionLook() end
		held.ghost.Frame.Parent = if at then at.Frame else nil
	else
		held.ghost.Frame.TextButton.Text = containerUI.label(held.sourceContainer.slots[held.sourceIndex], held.amount)
	end
	remoteFunc:InvokeServer(...)
	if last then
		held.ghost:destroy()
		local ui = uiOf(held.sourceContainer)
		if ui then ui:release(held) end
	end
end

-- everything on the cursor into one slot. A whole stack moves/swaps/merges; a
-- partial one only lands on empty or the same item. False = nothing sent.
local function placeAll(held:any, to:any, toIndex:number): boolean
	local from, fromIndex = held.sourceContainer, held.sourceIndex
	local src, dst = from.slots[fromIndex], to.slots[toIndex]
	if src == nil or (to == from and toIndex == fromIndex) then return false end
	local at = uiOf(to).slots[toIndex]
	if sameStack(dst, src) or (dst == nil and held.amount < (src.stack or 1)) then
		spend(held, held.amount, at, "splitItem", from.replicationID, fromIndex, held.amount, to.replicationID, toIndex)
	elseif held.amount >= (src.stack or 1) then
		spend(held, held.amount, at, moveArgs(from, fromIndex, to, toIndex))
	else
		return false -- a partial can't swap
	end
	return true
end

-- a sticky carry's press starts a sweep: every empty / same-item slot the mouse crosses joins
local function sweepAdd(held:any, to:any, toIndex:number)
	local list = held.sweep
	if #list >= held.amount or (to == held.sourceContainer and toIndex == held.sourceIndex) then return end
	for _, s in list do
		if s[1] == to and s[2] == toIndex then return end
	end
	local dst = to.slots[toIndex]
	-- the pressed slot always joins: a plain click on another item is a swap
	if #list > 0 and dst ~= nil and not sameStack(dst, held.sourceContainer.slots[held.sourceIndex]) then return end
	local mark = selection.UIStroke:Clone()
	mark.Parent = uiOf(to).slots[toIndex].Frame
	table.insert(list, {to, toIndex, mark})
end

-- left: one slot = place all, several = split evenly. right: one each. The rest stays on the cursor
local function sweepEnd(held:any, button:Enum.UserInputType)
	local list = held.sweep
	clearSweep(held)
	local src = held.sourceContainer.slots[held.sourceIndex]
	if src == nil then cancelCarry() return end
	if #list == 1 and button == MB1 then placeAll(held, list[1][1], list[1][2]) return end
	local args = {}
	for _, s in list do
		local dst = s[1].slots[s[2]]
		if dst == nil or sameStack(dst, src) then
			table.insert(args, s[1].replicationID)
			table.insert(args, s[2])
		end
	end
	local n = #args // 2
	if n == 0 then return end
	local per = if button == MB2 then 1 else held.amount // n
	spend(held, per * n, nil, "splitItem", held.sourceContainer.replicationID, held.sourceIndex, per, table.unpack(args))
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
		local held = carrying
		if held and held.sweep and hoverHit then sweepAdd(held, refContainer, refIndex) end
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
local hotbarPress:{input:InputObject, index:number}? = nil -- a closed-bag press: its lift is the charge release

-- Mouse: left picks up the stack, right half. Released on its own slot the carry
-- goes STICKY (minecraft's click-to-pick-up): a press then sweeps slots, a press
-- on its own slot puts it back (right: one), a quick second click there collects.
-- Touch: drag as before, a long-press takes half.
local LONG_PRESS = 0.45
uis.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
	local inputType = input.UserInputType
	local isTouch = inputType == Enum.UserInputType.Touch
	if inputType ~= MB1 and inputType ~= MB2 and not isTouch then return end
	if isTouch then
		local inputP = input.Position
		-- no hover on touch: resolve on press. a miss records nothing, so the
		-- closed-bag hotbar tap below stays the only thing that fires.
		hoverHit = hoverAt(Vector2.new(inputP.X, inputP.Y))
		touchDown = if hoverHit then {t = tick(), index = refIndex, container = refContainer} else nil
	end

	local held = carrying
	if held then
		if not held.sticky or held.sweep then return end -- a drag or sweep already owns the pointer
		if not hoverHit then cancelCarry() return end -- clicked off the grid
		if refContainer == held.sourceContainer and refIndex == held.sourceIndex then
			if inputType == MB2 then setAmount(held, held.amount - 1) return end
			local src = refContainer.slots[refIndex]
			cancelCarry()
			if src and src.stack and tick() - held.t < DOUBLE_TAP then
				remoteFunc:InvokeServer("collectItem", refContainer.replicationID, refIndex)
			end
			return
		end
		held.sweep, held.sweepBtn = {}, inputType
		sweepAdd(held, refContainer, refIndex)
		return
	end

	if hoverHit and prevFrame and prevFrame.item then
		if inputType == MB1 and shiftHeld() then
			quickMove(refContainer, refIndex)
			return
		end
		startCarry(refContainer, refIndex, inputType == MB2, inputType)
		local c, down = carrying, touchDown
		if isTouch and c then
			task.delay(LONG_PRESS, function()
				if carrying ~= c or touchDown ~= down or refIndex ~= c.sourceIndex or refContainer ~= c.sourceContainer then return end
				local src = c.sourceContainer.slots[c.sourceIndex]
				if src and src.stack then setAmount(c, math.ceil(src.stack / 2)) end
			end)
		end
	elseif inputType ~= MB2 then -- default
		local inputP = input.Position
		local p = Vector2.new(inputP.X, inputP.Y)

		local hotbarIndex = hotbarUI:getGridIndex(p)
		if hotbarIndex ~= 0 then
			hotbarUse(hotbarIndex)
			hotbarPress = {input = input, index = hotbarIndex}
		end
	end
end)
uis.InputEnded:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
	local inputType = input.UserInputType
	local isTouch = inputType == Enum.UserInputType.Touch
	if inputType ~= MB1 and inputType ~= MB2 and not isTouch then return end
	if inputType ~= MB2 then
		-- that finger, wherever it lifts (a mouse may not hand back the same object)
		local press = hotbarPress
		if press and (press.input == input or (not isTouch and press.input.UserInputType == inputType)) then
			hotbarPress = nil
			hotbarRelease(press.index)
		end

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
				hotbarRelease(down.index) -- cast on the lift, so it's already a tap
			end
			return
		end
	end

	local held = carrying
	if held == nil then return end
	if held.sweep then
		if held.sweepBtn == inputType then sweepEnd(held, inputType) end
		return
	end
	if held.sticky or held.button ~= inputType then return end
	if not hoverHit then
		cancelCarry() -- released with no slot under the pointer
	elseif refContainer == held.sourceContainer and refIndex == held.sourceIndex then
		if isTouch then cancelCarry() else held.sticky = true end -- a click picks it up
	elseif not placeAll(held, refContainer, refIndex) then
		cancelCarry()
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
