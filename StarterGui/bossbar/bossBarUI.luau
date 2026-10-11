--!nonstrict
-- S2C.bossBar names the boss Model; health is read off its already-replicated Humanoid, so nothing else rides the wire.
local BOSS_BAR = require(game.ReplicatedStorage.Class.HumObjClient.replIds).S2C.bossBar
local FADE = 2 -- secs the bar takes to fade out once the boss dies

local gui = script.Parent
local hp, label = gui:WaitForChild("Bar"):WaitForChild("HP"), gui:WaitForChild("TextLabel")
local conns = {}
-- every transparency in the bar and its authored value, so the death fade can lerp them all to 1 and back
local fades = {}
for _, d in gui:GetDescendants() do
	if d:IsA("GuiObject") then table.insert(fades, { d, "BackgroundTransparency", d.BackgroundTransparency }) end
	if d:IsA("ImageLabel") then table.insert(fades, { d, "ImageTransparency", d.ImageTransparency }) end
	if d:IsA("TextLabel") then table.insert(fades, { d, "TextTransparency", d.TextTransparency }) end
	if d:IsA("UIStroke") then table.insert(fades, { d, "Transparency", d.Transparency }) end
end
local function setFade(a)
	for _, f in fades do f[1][f[2]] = f[3] + (1 - f[3]) * a end
end

local function hide()
	gui.Enabled = false
	for _, c in conns do c:Disconnect() end
	table.clear(conns)
end
local function fadeOut()
	hide()
	gui.Enabled = true
	local t0 = os.clock()
	conns[1] = game:GetService("RunService").RenderStepped:Connect(function()
		local a = (os.clock() - t0) / FADE
		if a >= 1 then return hide() end
		setFade(a)
	end)
end

game.ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("CharacterRepli").OnClientEvent:Connect(function(id, model)
	if id ~= BOSS_BAR or not model then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	hide()
	setFade(0)
	local function set(h)
		hp.Size = UDim2.new(math.max(h, 0) / hum.MaxHealth, -2, 1, -2)
		if h <= 0 then fadeOut() end
	end
	set(hum.Health)
	label.Text = model.Name:upper()
	conns[1] = hum.HealthChanged:Connect(set)
	conns[2] = model.AncestryChanged:Connect(function(_, p) if not p then hide() end end)
	gui.Enabled = true
end)
