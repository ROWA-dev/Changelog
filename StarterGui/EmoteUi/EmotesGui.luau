--!strict
local plr = game.Players.LocalPlayer
local Mouse = plr:GetMouse()
local clientData = require(game:GetService("ReplicatedFirst"):WaitForChild("ClientData"))

local EmoteWheel = script.Parent:WaitForChild("EmoteWheel")
local SlotsFolder = EmoteWheel:WaitForChild("slots")

-- instance type of doom and despair
type slot = TextButton & { ViewportFrame:ViewportFrame & { WorldModel:WorldModel & { Humanoid:Humanoid & { Animator:Animator } } }, TextLabel:TextLabel }
type emote = {
	id: number,
	track: AnimationTrack?, -- loaded track
	anim: Animation?,
	button: slot
}

local emoteSlots:{emote} = {}
local inputRemoteEvent = game.ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Inputs")
local inputEnums = require(inputRemoteEvent:WaitForChild("enums"))
local emoteWheelStuff
local function playEmote(emoteID:number)
	inputRemoteEvent:FireServer(inputEnums.initEmote, emoteID)
	emoteWheelStuff()
end

local emoteSlotTemp = script:WaitForChild("slot")
local rf = game.ReplicatedStorage:WaitForChild("RemoteFunction")
local plrObj = clientData.plrObj

local HOLD_TIME = 0.3 -- hold a wheel slot this long to open the replace picker
local radius = 0.5
local center = UDim2.fromScale(0.5, 0.5)
local pi2 = math.pi*2
local pihalf = math.pi/2

local openPicker, requestAnims, closePicker

-- Built on FIRST OPEN, not at init: a viewport rig per slot is real memory, and
-- a player who never opens the wheel should not pay for one. Also means the
-- saved loadout has landed by the time we read it.
local wheelBuilt = false
local function buildWheel(): boolean
	if wheelBuilt then return true end
	local data = plrObj.Data
	if data == nil then return false end -- not loaded yet, ignore this open

	local ids = data.emoteData
	local numSlots = #ids
	for i = 1, numSlots do
		local slot = emoteSlotTemp:Clone()

		slot.TextLabel.Text = ""
		slot.AnchorPoint = Vector2.new(0.5, 0.5)

		local angle = ((i - 1) / numSlots) * pi2 - pihalf
		local x = math.cos(angle) * radius
		local y = math.sin(angle) * radius
		slot.Position = UDim2.fromScale(
			center.X.Scale + x,
			center.Y.Scale + y
		)

		-- tap plays, hold opens the picker. One thread, only while held.
		local holdThread
		local function cancelHold()
			if holdThread then
				task.cancel(holdThread)
				holdThread = nil
			end
		end
		slot.MouseButton1Down:Connect(function()
			cancelHold()
			holdThread = task.delay(HOLD_TIME, function()
				holdThread = nil -- cleared BEFORE openPicker so Up can't cancel a dead thread
				openPicker(i)
			end)
		end)
		slot.MouseButton1Up:Connect(function()
			if holdThread == nil then return end -- the hold already opened the picker
			cancelHold()
			playEmote(emoteSlots[i].id)
		end)
		slot.MouseLeave:Connect(cancelHold)

		slot.Parent = SlotsFolder

		emoteSlots[i] = {
			id = ids[i],
			button = slot
		}
	end

	-- ONE web call for every slot, after the rigs exist.
	task.spawn(function()
		local desc = game.Players:GetHumanoidDescriptionFromUserId(plr.UserId) -- TODO pcall this
		for _, e in pairs(emoteSlots) do
			e.button.ViewportFrame.WorldModel.Humanoid:ApplyDescription(desc)
		end
	end)

	wheelBuilt = true
	return true
end


local ts = game:GetService("TweenService")
local topbar = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TopbarIcons"))
local emoteIcon = topbar.register({
	name  = "emotes",
	order = 2,
	frame = script.Parent:WaitForChild("TopbarIcon"),
	onClick = function() emoteWheelStuff() end,
})

function requestAnims()
	-- ONE ENTRY PER SLOT, in slot order. The reply is index-parallel, so nothing
	-- on the wire is keyed by emote id -- see listEmotes for why that matters.
	local list = table.create(#emoteSlots)
	for i,emote in pairs(emoteSlots) do
		list[i] = emote.id
	end
	local replies = rf:InvokeServer("listEmotes", list)
	if replies == nil then return end
	for i,emote in pairs(emoteSlots) do
		local pair = replies[i]

		-- clear FIRST, always: a slot must never keep the last emote's name or
		-- animation when its own lookup comes back empty.
		if emote.anim then
			emote.anim:Destroy()
			emote.anim = nil
		end
		if emote.track then
			emote.track:Stop()
			emote.track:Destroy()
			emote.track = nil
		end
		if not pair then
			emote.button.TextLabel.Text = ""
			continue
		end

		local animID = pair[1]
		local emotName = pair[2]
		if animID then
			local anim = Instance.new("Animation")
			anim.AnimationId = animID
			
			local animator = emote.button.ViewportFrame.WorldModel.Humanoid.Animator
			local animTrak = animator:LoadAnimation(anim)
			animTrak:Play()
			emote.anim = anim
			emote.track = animTrak
		end
		if emotName then
			emote.button.TextLabel.Text = emotName
		end
	end
end


-- REPLACE PICKER. Rows are TEXT ONLY on purpose: the catalogue is static so they
-- are built once, and a viewport rig per row would cost more than the wheel does.
local rowTemp = script:WaitForChild("emote")
local pickerFrame:ScrollingFrame?, pickerRows:{[number]:TextButton}?, editingSlot:number?
local pickerBuilding = false

local function saveSlots()
	local ids = table.create(#emoteSlots)
	for i, e in pairs(emoteSlots) do
		ids[i] = e.id
	end
	plrObj:saveEmotes(ids)
end

function closePicker()
	editingSlot = nil
	if pickerFrame then
		pickerFrame.Visible = false
	end
end

local function paintRows()
	if pickerRows == nil or editingSlot == nil then return end
	local current = emoteSlots[editingSlot].id
	for id, row in pairs(pickerRows) do
		row.BackgroundTransparency = (id == current) and 0.15 or 0.5
	end
end

local function buildPicker()
	local catalogue = rf:InvokeServer("emoteCatalogue") -- static, one fetch per session

	local frame = Instance.new("ScrollingFrame")
	frame.Name = "picker"
	frame.Size = UDim2.fromScale(0.55, 0.9)
	frame.Position = UDim2.fromScale(1.02, 0.05)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 4
	frame.CanvasSize = UDim2.new()
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.Parent = EmoteWheel -- rides the wheel's tween, so it hides with it

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	pickerRows = {}
	for _, entry in ipairs(catalogue) do -- array of {id, name}, already sorted
		local id = entry[1]
		local row = rowTemp:Clone()
		row.Name = tostring(id)
		row.Text = entry[2]
		row.Size = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = id
		row.MouseButton1Click:Connect(function()
			local editing = editingSlot
			if editing == nil then return end
			emoteSlots[editing].id = id
			saveSlots()
			closePicker()
			task.spawn(requestAnims)
		end)
		row.Parent = frame
		pickerRows[id] = row
	end
	pickerFrame = frame
end

function openPicker(slotIndex:number)
	if pickerFrame == nil then
		if pickerBuilding then return end
		pickerBuilding = true
		local ok, err = pcall(buildPicker) -- yields on the RF
		pickerBuilding = false
		if ok == false then
			warn("emote picker failed to build", err)
			return
		end
	end
	editingSlot = slotIndex
	paintRows();
	(pickerFrame::ScrollingFrame).Visible = true
end


local isOpen = false
local canEmote = 0
function emoteWheelStuff()
	if isOpen == false then -- will be opening...
		if buildWheel() == false then return end
		canEmote = tick() + 0.2
		task.spawn(requestAnims)
	else
		closePicker()
		for i,emote in pairs(emoteSlots) do
			if emote.anim then
				emote.anim:Destroy()
				emote.anim = nil
			end
			if emote.track then
				emote.track:Stop()
				emote.track:Destroy()
				emote.track = nil
			end
			
		end
	end
	
	
	local minSz = math.min(Mouse.ViewSizeX, Mouse.ViewSizeY)
	if minSz < 400 then
		local newSz = minSz-20
		EmoteWheel.Size = UDim2.new(0,newSz,0,newSz)
	else
		EmoteWheel.Size = UDim2.new(0,380,0,380)
	end
	
	if isOpen == false then isOpen = true
		emoteIcon:setActive(true)
		ts:Create(EmoteWheel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.5, 0)
		}):Play()
	else isOpen = false
		emoteIcon:setActive(false)
		ts:Create(EmoteWheel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 1.5, 0)
		}):Play()
	end
end


local UIS = game:GetService("UserInputService")
local function isMouseOverGui(guiObject)
	local mousePos = UIS:GetMouseLocation()

	-- Roblox adds a topbar offset, so adjust:
	mousePos -= Vector2.new(0, 36)

	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize

	return mousePos.X >= pos.X
		and mousePos.X <= pos.X + size.X
		and mousePos.Y >= pos.Y
		and mousePos.Y <= pos.Y + size.Y
end

clientData.emoteEvent = function(began:boolean)
	
	if isOpen == true and tick() > canEmote then
		for _, slotData in pairs(emoteSlots) do
			if isMouseOverGui(slotData.button) then
				playEmote(slotData.id) -- already closes the wheel...
				return                 -- ...so do NOT fall through and re-toggle it
			end
		end
	end

	if began == true then
		emoteWheelStuff()
	end
end
