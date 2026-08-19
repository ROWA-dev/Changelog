--!strict
local clientData = require(game:GetService("ReplicatedFirst"):WaitForChild("ClientData"))
local container = script.Parent:WaitForChild("container")
local container2 = script.Parent:WaitForChild("container2")
local cduiTEMPLATE = script:WaitForChild("cdui")

local ts = game:GetService("TweenService")

-- ability cooldowns are drawn ON the hotbar/inventory slot holding them, so
-- this list skips any id a slot has claimed. Everything else (dash, slide,
-- feint...) has no item to sit on and still shows up here.
local claims = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CooldownClaims"))
claims.setOnClaim(function(id: string) 
	-- claimed mid-flight: the slot and this list listen on different remotes,
	-- so on the first use of an ability we can already have drawn it
	local found = container:FindFirstChild(id)
	if found then found:Destroy() end
end)

local function visual(id: string, value: number)
	--print("COOLDOWN:",id, value)
	if claims.isClaimed(id) then return end
	if container:FindFirstChild(id) then
		--container[id]:Destroy()
		local found = container[id]
		found.Name = "?"
		found.bar.BackgroundTransparency = 0.9
		local texlabel = found:FindFirstChild("TextLabel")
		if texlabel then
			texlabel.TextTransparency = 0.8
			texlabel.Text = id.." -> "..tostring(value)
		end
		found.Parent = container2
	end
	if value == 0 then
		return
	end
	local uicd = cduiTEMPLATE:Clone()
	uicd.Visible = true
	uicd.Name = id
	local textLabel = uicd:FindFirstChild("texLabel")
	if textLabel then
		local rounded = math.floor(value * 10)/10
		textLabel.Text = id.." "..tostring(rounded).."s"
	end
	
	local tween = ts:Create(uicd.bar, TweenInfo.new(value, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0,0,0,20)
	})
	tween:Play()
	
	uicd.Parent = container
	
	tween.Completed:Wait()
	
	uicd:Destroy()
	tween:Destroy()
end

local function onHumObj(humObj:any)
	humObj:AddConnection(
		humObj.cooldowns.CooldownTriggered:Connect(visual)
	, "cooldownVisual")
end

if clientData.HumObj then
	onHumObj(clientData.HumObj)
end
clientData.onHumObjSetup:Connect(onHumObj)