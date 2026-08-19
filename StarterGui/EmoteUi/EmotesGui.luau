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
	print("PLAY EMOTE!", emoteID)
	inputRemoteEvent:FireServer(inputEnums.initEmote, emoteID)
	emoteWheelStuff()
end

local playerDescription = game.Players:GetHumanoidDescriptionFromUserId(plr.UserId) -- TODO pcall this
local emoteSlotTemp = script:WaitForChild("slot")
local numSlots = 5

local radius = 0.5
local center = UDim2.fromScale(0.5, 0.5)

local pi2 = math.pi*2
local pihalf = math.pi/2
for i = 1, numSlots do
	local slot = emoteSlotTemp:Clone()
	local humanoid = slot
		:WaitForChild("ViewportFrame")
		:WaitForChild("WorldModel")
		:WaitForChild("Humanoid")

	task.spawn(function()
		wait()
		humanoid:ApplyDescription(playerDescription)
	end)
	
	slot.TextLabel.Text = "slot "..tostring(i)
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	
	--local angle = ((i - 2) / numSlots) * math.pi * 2
	local angle = ((i - 1) / numSlots) * pi2 - pihalf


	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius
	slot.Position = UDim2.fromScale(
		center.X.Scale + x,
		center.Y.Scale + y
	)


	slot.MouseButton1Up:Connect(function()
		playEmote(emoteSlots[i].id)
	end)
	slot.Parent = SlotsFolder
	
	emoteSlots[i] = {
		id = 1 + i%5,
		button = slot
	}
end


local ts = game:GetService("TweenService")
local topbar = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TopbarIcons"))
local emoteIcon = topbar.register({
	name  = "emotes",
	order = 2,
	frame = script.Parent:WaitForChild("TopbarIcon"),
	onClick = function() emoteWheelStuff() end,
})
local rf = game.ReplicatedStorage:WaitForChild("RemoteFunction")

local function requestAnims()
	local list = {}
	for i,emote in pairs(emoteSlots) do
		if table.find(list, emote.id) == nil then
			table.insert(list, emote.id)
		end
	end
	local toAnimId = rf:InvokeServer("listEmotes", list)
	for i,emote in pairs(emoteSlots) do
		local pair = toAnimId[emote.id]
		if pair == nil then
			continue
		end
		
		local animID = pair[1]
		local emotName = pair[2]
		if animID then
			--warn(i, emote)
			if emote.anim then
				emote.anim:Destroy()
				emote.anim = nil
			end
			if emote.track then
				emote.track:Stop()
				emote.track:Destroy()
				emote.track = nil
			end
			
			local anim = Instance.new("Animation")
			anim.AnimationId = animID
			
			local animator = emote.button.ViewportFrame.WorldModel.Humanoid.Animator
			local animTrak = animator:LoadAnimation(anim)
			animTrak:Play()
			emote.anim = anim
			emote.track = animTrak

			--print(emote,animTrak)
		end
		if emotName then
			emote.button.TextLabel.Text = emotName
		end
	end
end

local isOpen = false
local canEmote = 0
function emoteWheelStuff()
	if isOpen == false then -- will be opening...
		canEmote = tick() + 0.2
		task.spawn(requestAnims)
	else
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
		for i, slotData in pairs(emoteSlots) do
			if isMouseOverGui(slotData.button) then
				--print(i)
				playEmote(slotData.id)
				-- trigger emote here
				break
			end
		end
	end

	if began == true then
		emoteWheelStuff()
	elseif began == false then
		--[[if isOpen == false then
			return
		end
		for i, slotData in pairs(emoteSlots) do
			if isMouseOverGui(slotData.button) then
				--print(i)
				playEmote(slotData.id)
				-- trigger emote here
				break
			end
		end]]
		
	end
end