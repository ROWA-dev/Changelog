--!nonstrict
-- S2C.bossBar names the boss Model; health is read off its already-replicated Humanoid, so nothing else rides the wire.
local BOSS_BAR = require(game.ReplicatedStorage.Class.HumObjClient.replIds).S2C.bossBar

local gui = script.Parent
local hp, label = gui:WaitForChild("Bar"):WaitForChild("HP"), gui:WaitForChild("TextLabel")
local conns = {}

local function hide()
	gui.Enabled = false
	for _, c in conns do c:Disconnect() end
	table.clear(conns)
end

game.ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("CharacterRepli").OnClientEvent:Connect(function(id, model)
	if id ~= BOSS_BAR or not model then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	hide()
	local function set(h)
		if h <= 0 then return hide() end
		hp.Size = UDim2.new(h / hum.MaxHealth, -2, 1, -2)
	end
	set(hum.Health)
	label.Text = model.Name:upper()
	conns[1] = hum.HealthChanged:Connect(set)
	conns[2] = model.AncestryChanged:Connect(function(_, p) if not p then hide() end end)
	gui.Enabled = true
end)
