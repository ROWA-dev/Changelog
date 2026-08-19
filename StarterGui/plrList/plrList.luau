--!strict

repeat
	local startergui = game:GetService("StarterGui")
	local load = pcall(function()
		startergui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	wait(0.2)
until load

local frame = script.Parent:WaitForChild("Frame")
frame.Visible = true
local plrList = frame:WaitForChild("ScrollingFrame")

--- https://voxlenox.github.io/RobloxBuilderIconList/
local function getIcon(plr:Player): string?
	if plr.UserId == 154495872 then -- ninjakick
		return "ninja"
	elseif plr.UserId == 222313015 then -- lockjau
		return "crown"
	end
	
	local localPlr = game.Players.LocalPlayer
	
	local ok, areFriends = pcall(localPlr.IsFriendsWithAsync, localPlr, plr.UserId)
	if ok and areFriends then
		return "two-people"
	end
	
	local groupId = game.CreatorId
	local ok, rank = pcall(plr.GetRankInGroupAsync, plr, groupId)
	if rank == 255 or rank == 254 then
		return "hammer-code"
	end
	
	local ok, inStarGroup = pcall(plr.IsInGroupAsync, plr, 4199740)
	if not ok then
		inStarGroup = false
	end
	if plr:GetAttribute("VideoStar") or inStarGroup then
		return "star"
	end
	
	-- Premium
	if plr.HasRobloxSubscription or plr.MembershipType == Enum.MembershipType.Premium then
		return "premium"
	end

	--
	local ok, isVerified = pcall(plr.IsVerified, plr)
	if not ok then
		isVerified = false
	end
	if plr.HasVerifiedBadge or isVerified then
		return "verified-check"
	end
		
	--
	return nil
end

local ts = game:GetService("TweenService")

local currentViewingId = 0
local viewFrame = script.viewFrame

viewFrame:WaitForChild("ImageButton").MouseButton1Down:Connect(function() 
	pcall(function()
		game.StarterGui:SetCore("ShowPlayerProfile", currentViewingId)
	end)
end)

viewFrame:WaitForChild("addF").MouseButton1Down:Connect(function() 
	pcall(function()
		game.Players:RequestFriendAsync(currentViewingId)
	end)
end)

local function animateText(tb:TextLabel, text:string)
	local id = tostring(tick()).."-"..tostring(math.random(1,1e9))
	tb:SetAttribute("typingId", id)
	tb.Text = ""
	for i = 1, #text do
		if tb:GetAttribute("typingId") ~= id then return end
		tb.Text = text:sub(1, i)
		task.wait(0.02)
	end
	tb:SetAttribute("typingId", nil)
end

local listener:RBXScriptConnection? = nil
local closeCon:RBXScriptConnection? = nil
local function openViewFrame(newUI:TextButton)	
	local plr:Player = nil
	for _,v in pairs(game.Players:GetPlayers()) do
		if v.UserId == tonumber(newUI.Name) then
			plr = v
			break
		end
	end
	
	if closeCon and currentViewingId == plr.UserId then
		if listener then
			listener:Disconnect()
			listener = nil
		end
		if closeCon then
			closeCon:Disconnect()
			closeCon = nil
		end
		currentViewingId = 0
		viewFrame.Visible = false
		return
	end
	currentViewingId = plr.UserId

	viewFrame.Visible = true
	viewFrame.Position = UDim2.new(1,-174,0,newUI.AbsolutePosition.Y)
	viewFrame.Size = UDim2.new(0,9,0,100)
	ts:Create(viewFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0,300,0,100)
	}):Play()
	task.spawn(animateText, viewFrame.fullname, plr.Name)
	task.spawn(animateText, viewFrame.uid, tostring(plr.UserId))
	
	local currentDate = DateTime.now()
	local accountDays = plr.AccountAge
	local accountSeconds = accountDays * 24 * 60 * 60
	local creationTimestamp = currentDate.UnixTimestamp - accountSeconds
	local creationDate = DateTime.fromUnixTimestamp(creationTimestamp)
	local creationTable = creationDate:ToLocalTime()
	task.spawn(animateText, viewFrame.year, string.format("%d/%d/%d",
		creationTable.Month,
		creationTable.Day,
		creationTable.Year
	))
	viewFrame.Parent = script.Parent
	
	local thumbnail, isReady = game.Players:GetUserThumbnailAsync(
		currentViewingId,
		Enum.ThumbnailType.AvatarThumbnail,
		Enum.ThumbnailSize.Size100x100
	)
	viewFrame.ImageButton.Image = thumbnail
	
	local plrPing = tonumber(plr:GetAttribute("p"))
	local pingLabel = viewFrame.ping
	if plrPing then
		pingLabel.Text = tostring(plrPing).."ms"

		local hue = math.max(0, 0.4 * (1 - plrPing/200)^2)
		pingLabel.TextColor3 = Color3.fromHSV(hue, 0.6, 1)
	end
	
	listener = plr.AttributeChanged:Connect(function(attribute: string) 
		--print("ATT CHANGE!", attribute, plr:GetAttribute(attribute))
		if attribute == "p" then
			local plrPing = tonumber(plr:GetAttribute("p"))
			local pingLabel = viewFrame.ping
			if plrPing then
				pingLabel.Text = tostring(plrPing).."ms"

				local hue = math.max(0, 0.4 * (1 - plrPing/200)^2)
				pingLabel.TextColor3 = Color3.fromHSV(hue, 0.6, 1)
			end
		end
	end)
	
	if closeCon then
		closeCon:Disconnect()
		closeCon = nil
	end
	closeCon = game.UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
		if gameProcessedEvent == true then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if listener then
				listener:Disconnect()
				listener = nil
			end
			if closeCon then
				closeCon:Disconnect()
				closeCon = nil
			end
			currentViewingId = 0
			viewFrame.Visible = false
		end
	end)
	
	local otherTxt = viewFrame.other
	otherTxt.Text = ""
	local ok, plrFriends = pcall(plr.GetFriendsOnlineAsync, plr)
	if plrFriends and #plrFriends > 0 then
		otherTxt.Text ..= "friends online: "..tostring(#plrFriends)
	end
end


local function getPlrId(plr:Player):string
	return tostring(plr.UserId)
end


local function onPlrChange()
	local allPlrs = game.Players:GetPlayers()

	local existing = {}
	for _, child in ipairs(plrList:GetChildren()) do
		if child:IsA("TextButton") then
			existing[child.Name] = child
		end
	end

	local sz = 0
	for _, plr in pairs(allPlrs) do
		local plrUI:TextButton? = existing[getPlrId(plr)]
		if plrUI then
			-- im found so
			--plrUI.Text = plr.DisplayName
			existing[getPlrId(plr)] = nil
		else
			local newUI:TextButton&{UIPadding:UIPadding, PlayerIcon:TextLabel, title:TextLabel, ping:TextLabel} = script.plr:Clone()
			newUI.Name = getPlrId(plr)
			newUI.Text = plr.DisplayName
			newUI.Visible = true
			newUI.Parent = plrList
			if plr == game.Players.LocalPlayer then
				newUI.TextColor3 = Color3.new(1, 1, 1)
			else
				newUI.TextColor3 = Color3.new(0.74902, 0.74902, 0.74902)
			end
			
			-- this might mem leak?? or am in 2am stupid mode rn
			-- 3/24/2026 fixed mem leak holding plr as attribute
			local conn

			local function attChange()
				local value = plr:GetAttribute("t")
				if value == nil then return end

				local title: TextLabel = newUI:FindFirstChild("title") or script.title:Clone()
				title.Text = tostring(value)
				title.Parent = newUI
			end

			attChange()
			conn = plr:GetAttributeChangedSignal("t"):Connect(attChange)

			plr.AncestryChanged:Connect(function(_, parent)
				if parent == nil and conn then
					conn:Disconnect()
					conn = nil
				end
			end)
			
			--[[plr.Changed:Connect(function(property: string) 
				if property == "Team" then
					local newTeam:Team? = plr.Team
					if newTeam then -- use newteam color
						newUI.TextColor = newTeam.TeamColor
					else -- DEFAULT
						newUI.TextColor3 = script.plr.TextColor3
					end
				end
			end)]]
			
			local plrIcon = getIcon(plr)
			if plrIcon then
				local icon = script.PlayerIcon:Clone()
				icon.Visible = true
				icon.Text = plrIcon
				icon.Parent = newUI
			end
			
			newUI.MouseEnter:Connect(function() 
				newUI.Text = tostring(plr)
				newUI.UIPadding.PaddingLeft = UDim.new(0.3,0)
				newUI.BackgroundTransparency = 0.9
			
				local plrPing = tonumber(plr:GetAttribute("p"))
				if plrPing then
					local ping = newUI:FindFirstChild("ping") or script.ping:Clone()
					ping.Text = tostring(plrPing).."ms"
					ping.TextTransparency = 0
					
					local hue = math.max(0, 0.4 * (1 - plrPing/200)^2)
					ping.TextColor3 = Color3.fromHSV(hue, 0.6, 1)
					ping.Parent = newUI
				end
				
				if newUI:FindFirstChild("PlayerIcon") then
					newUI.PlayerIcon.Visible = false
				end
			end)
			newUI.MouseLeave:Connect(function()
				newUI.Text = plr.DisplayName
				newUI.UIPadding.PaddingLeft = UDim.new(0.2,0)
				newUI.BackgroundTransparency = 1
				
				if newUI:FindFirstChild("ping") then
					newUI.ping.TextTransparency = 1
				end
				
				if newUI:FindFirstChild("PlayerIcon") then
					newUI.PlayerIcon.Visible = true
				end
			end)
			newUI.MouseButton1Down:Connect(function()
				openViewFrame(newUI)
			end)
		end
		sz += 36
	end
	for _, leftover in pairs(existing) do
		leftover:Destroy()
	end

	local maxSz = math.floor(workspace.CurrentCamera.ViewportSize.Y / 2)
	if sz > maxSz then
		plrList.CanvasSize = UDim2.new(0,0,0,sz)
		sz = maxSz
	else
		plrList.CanvasSize = UDim2.new(0,0,0,0)
	end
	frame.Size = UDim2.new(0, 164, 0, 28 + sz)
end

local isOpen = true
local function close()
	isOpen = false
	ts:Create(frame, TweenInfo.new(0.2), {
		Position = UDim2.new(1, 10, 0, 4)
	}):Play()
end
local function open()
	isOpen = true
	ts:Create(frame, TweenInfo.new(0.2), {
		Position = UDim2.new(1, -170, 0, 4)
	}):Play()
end

frame:WaitForChild("exit").MouseButton1Up:Connect(function() 
	close()
end)

local uis = game:GetService("UserInputService")
if uis.TouchEnabled == true then
else
	uis.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
		if gameProcessedEvent == true then return end
		if input.KeyCode == Enum.KeyCode.Tab then
			if isOpen then close() else open() end
		end
	end)
end

onPlrChange()
game.Players.PlayerAdded:Connect(onPlrChange)
game.Players.PlayerRemoving:Connect(onPlrChange)

wait(4)
onPlrChange()