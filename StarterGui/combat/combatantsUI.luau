--!nonstrict

local RunService = game:GetService("RunService")
local clientData = require(game:GetService("ReplicatedFirst"):WaitForChild("ClientData"))

local container = script.Parent:WaitForChild("Combatants")
local template  = container:WaitForChild("template")
local skull     = container:WaitForChild("Skull")
local names     = skull:WaitForChild("Names")
local timer     = skull:WaitForChild("Timer")

local rows = {} -- Model -> TextLabel
local count = 0

local bound   -- humObj we are currently reading combatDeadline off
local ticking -- RBXScriptConnection?, alive ONLY while in combat
local shown = -1

local clearAll -- forward: needs removeRow, which needs refreshSkull, which needs step

--- One property write per SECOND, not per frame: the compare is the whole
--  point, TextLabel.Text is the expensive half.
local function step()
	if bound == nil then return end

	if not bound.isActive then
		clearAll()
		return
	end

	local left = math.max(0, math.ceil(bound.combatDeadline - tick()))
	if left ~= shown then
		shown = left
		timer.Text = tostring(left)
	end
end

local function refreshSkull()
	local active = count > 0
	skull.Visible = active

	if active then
		if ticking == nil then -- nothing ticks while out of combat
			shown = -1
			step()
			ticking = RunService.Heartbeat:Connect(step)
		end
	elseif ticking then
		ticking:Disconnect()
		ticking = nil
		names.Visible = false -- cannot be left hovering something that vanished
		timer.Text = ""
	end
end

local function removeRow(model: Instance)
	local label = rows[model]
	if label == nil then return end
	rows[model] = nil
	count -= 1
	label:Destroy()
	refreshSkull()
end

local function addRow(model: Instance)
	if rows[model] then return end

	local label = template:Clone()
	label.Name = model.Name
	label.Text = model.Name
	label.Visible = true
	label.Parent = names

	rows[model] = label
	count += 1
	refreshSkull()
end

--- Snapshot before sweeping, per the StatusEffects.clearAll scar: mutating a
--  table while iterating it is undefined in Luau.
function clearAll()
	local stale = {}
	for model in rows do
		stale[#stale + 1] = model
	end
	for _, model in stale do
		removeRow(model) -- last one flips count to 0, which disconnects `ticking`
	end
end

skull.MouseEnter:Connect(function()
	names.Visible = true
end)
skull.MouseLeave:Connect(function()
	names.Visible = false
end)

--- Re-binds on every respawn. The old humObj's signal is Destroyed with it, so
--  the previous connection dies on its own and these do not accumulate.
local function bind(humObj)
	clearAll() -- drop the previous character's rows before rebinding
	bound = humObj

	if humObj.combatants then
		for model in humObj.combatants do
			addRow(model)
		end
	end

	if humObj.onCombatChanged then
		humObj.onCombatChanged:Connect(function(model: Instance, joined: boolean)
			if joined then
				addRow(model)
			else
				removeRow(model)
			end
		end)
	end
end

if clientData.HumObj then
	bind(clientData.HumObj)
end
clientData.onHumObjSetup:Connect(bind)
