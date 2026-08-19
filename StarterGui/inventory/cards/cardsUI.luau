--!strict
-- Inventory > cards. Opens beside the info panel and lists the cards this
-- character actually has.
--
-- Data rides the SAME pull the settings Slot tab uses (plrObj:requestSlotInfo ->
-- S2C.SlotInfo, server rate-gated). No second remote: slotInfo is cached on
-- plrObj, so whichever panel opens first warms it for the other.
local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local plrObj = clientData.plrObj

local panel = script.Parent
local list  = panel:WaitForChild("ScrollingFrame")
local cardTemplate = panel:WaitForChild("card")

-- Fixed tab on info's left edge. It's a child of info, so it hides with the panel
-- for free. It used to be a button inside info's ScrollingFrame, which meant
-- scrolling to the bottom to find it.
local infoFrame = panel.Parent:WaitForChild("info")
local toggle = infoFrame:WaitForChild("cardsTab")
local toggleLabel = toggle:WaitForChild("label")
local toggleStroke = toggle:WaitForChild("UIStroke")

local function clear()
	for _, v in pairs(list:GetChildren()) do
		if v:IsA("GuiObject") then game.Debris:AddItem(v, 0) end
	end
end

local function render(info: any)
	clear()

	local cards = if info then info.cards else nil
	if cards == nil then
		local c = cardTemplate:Clone()
		c.cardName.Text = "loading..."
		c.desc.Text = ""
		c.Visible = true
		c.Parent = list
		return
	end

	if #cards == 0 then
		local c = cardTemplate:Clone()
		c.cardName.Text = "no cards"
		c.desc.Text = "cards are granted on spawn; innate ones apply to every character."
		c.Visible = true
		c.Parent = list
		return
	end

	for i, entry in ipairs(cards) do
		local c = cardTemplate:Clone()
		c.cardName.Text = tostring(entry[1])
		c.desc.Text = if entry[2] then tostring(entry[2]) else "no description"
		c.LayoutOrder = i
		c.Visible = true
		c.Parent = list
	end
end

local function setOpen(open: boolean)
	panel.Visible = open
	-- tab reads as pressed-in while the panel is up
	toggle.BackgroundTransparency = if open then 0.35 else infoFrame.BackgroundTransparency
	toggleStroke.Transparency = if open then 0.6 else 0.9
	toggleLabel.TextTransparency = if open then 0 else 0.25

	if open then
		render(plrObj.slotInfo)
		plrObj:requestSlotInfo()
	else
		clear() -- don't hold the entries while it's shut
	end
end

-- ONE persistent connection, not one per open
plrObj.slotInfoRecieved:Connect(function(info)
	if panel.Visible then render(info) end
end)

toggle.MouseButton1Up:Connect(function()
	setOpen(not panel.Visible)
end)

panel:WaitForChild("close").MouseButton1Up:Connect(function()
	setOpen(false)
end)

-- the info panel owns whether the whole right side is up; follow it down so this
-- can't be left floating over the world after the backpack closes
infoFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if not infoFrame.Visible and panel.Visible then
		setOpen(false)
	end
end)

toggle.MouseEnter:Connect(function()
	if not panel.Visible then toggleStroke.Transparency = 0.7 end
end)
toggle.MouseLeave:Connect(function()
	if not panel.Visible then toggleStroke.Transparency = 0.9 end
end)

setOpen(false)
