--!nonstrict
-- Minecraft-style active effects under the player list, drawn like the cooldown list. Rows come and go on S2C.statusEdge; nothing ticks, the bar is a tween.

local ts = game:GetService("TweenService")
local clientData = require(game:GetService("ReplicatedFirst"):WaitForChild("ClientData"))

local list = script.Parent:WaitForChild("list")
local template = list:WaitForChild("template")
local plrList = script.Parent.Parent:WaitForChild("plrList"):WaitForChild("Frame")

local FULL = template.bar.Size
local EMPTY = UDim2.new(0, 0, FULL.Y.Scale, FULL.Y.Offset)

-- flush right, under the player list, following it as players join/leave
local function follow()
	list.Position = UDim2.new(1, -6, 0, plrList.AbsoluteSize.Y + 12)
end
plrList:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
follow()

-- the server owns removal (its 0 edge), so an empty bar waits a ping rather than guessing
local function set(key: string, remaining: number)
	local row = list:FindFirstChild(key)
	if remaining <= 0 then
		if row then row:Destroy() end
		return
	end
	if row == nil then
		row = template:Clone()
		row.Name = key
		row.Visible = true
		row.Parent = list
	end
	-- "HyperArmour" -> "Hyper Armour". The number is the time left at the last refresh; the bar is the live part.
	row.texLabel.Text = key:gsub("(%l)(%u)", "%1 %2") .. " " .. (if remaining == math.huge then "∞" elseif remaining < 60 then math.ceil(remaining) .. "s" else math.round(remaining / 60) .. "m")
	row.bar.Size = FULL
	if remaining ~= math.huge then
		ts:Create(row.bar, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = EMPTY }):Play() -- a refresh's tween overrides the last
	end
end

-- re-binds on every respawn; the dead humObj's onStatus goes with it
local function bind(humObj)
	for _, row in list:GetChildren() do
		if row:IsA("Frame") and row ~= template then row:Destroy() end
	end
	humObj.onStatus = set
end

if clientData.HumObj then bind(clientData.HumObj) end
clientData.onHumObjSetup:Connect(bind)
