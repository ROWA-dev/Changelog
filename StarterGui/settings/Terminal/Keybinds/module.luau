local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local keybindEnums = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("keybindEnums"))
local uis = game:GetService("UserInputService")

local frame = script.Parent
local list  = frame:WaitForChild("ScrollingFrame")
local resetBtn = frame:WaitForChild("reset")

local isOpen = false
local open -- forward declared: capture handlers re-render through it

local function inputToValue(input:InputObject)
	if input.KeyCode and input.KeyCode.Value ~= 0 then
		return input.KeyCode.Value
	end
	return input.UserInputType.Value
end
local function valueToInput(value:number):Enum.UserInputType | Enum.KeyCode
	for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
		if keyCode.Value == value and keyCode ~= Enum.KeyCode.Unknown then
			return keyCode
		end
	end
	for _, inputType in ipairs(Enum.UserInputType:GetEnumItems()) do
		if inputType.Value == value then
			return inputType
		end
	end
	return Enum.KeyCode.Unknown
end

local function inputValueToName(value:number?)
	if value == nil or value == -1 then
		return ""
	end
	local name = valueToInput(value).Name
	name = string.gsub(name, "MouseButton", "M")
	name = string.gsub(name, "Control", "Ctrl")
	name = string.gsub(name, "Keypad", "keyp")
	return name
end

-- ONE key capture may be live at a time. Previously every "click a slot" handler
-- opened its own InputBegan listener and only ever tore them down on re-render, so
-- clicking two slots before pressing a key rebound BOTH of them off one keypress.
local captureConn: RBXScriptConnection? = nil
local pendingRevert: (() -> ())? = nil

local function clearCapture() -- drop the listener, leave the row as it looks
	if captureConn then
		captureConn:Disconnect()
		captureConn = nil
	end
	pendingRevert = nil
end

local function cancelCapture() -- drop the listener AND put the row back
	local revert = pendingRevert
	clearCapture()
	if revert then revert() end
end

local function beginCapture(slot: TextButton, noneBtn: TextButton, apply: (InputObject) -> ())
	cancelCapture()

	local was = slot.Text
	slot.Text = "_"
	noneBtn.Visible = true
	pendingRevert = function()
		slot.Text = was
		noneBtn.Visible = false
	end

	captureConn = uis.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent == true and input.UserInputType == Enum.UserInputType.Keyboard then return end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			task.wait(0.1)
		end
		if captureConn == nil then return end -- cancelled while we waited out the key
		clearCapture()
		apply(input)
		clientData:saveKeyBinds()
		open()
	end)
end

local function clear()
	cancelCapture()
	for _, v in pairs(list:GetChildren()) do
		if v.Name == script.keybind.Name then
			game.Debris:AddItem(v, 0)
		end
	end
end

local function sortedKeys()
	local keys = {}
	for k in pairs(keybindEnums) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		local aIsHotbar = string.sub(a, 1, 6) == "hotbar"
		local bIsHotbar = string.sub(b, 1, 6) == "hotbar"
		if aIsHotbar ~= bIsHotbar then
			return not aIsHotbar
		end
		return a < b
	end)
	return keys
end

function open()
	isOpen = true
	clear()

	local keybindsNow = {}
	local plrObjData = clientData.plrObj.Data or clientData.plrObj.onDataRecieve:Wait()
	if plrObjData then
		keybindsNow = plrObjData.keybindData
	end

	for _, k in pairs(sortedKeys()) do
		local value = keybindsNow[keybindEnums[k]]
		if value == nil then
			warn(tostring(k).." keybindNow not found")
			continue
		end

		local ui = script.keybind:Clone()
		ui.keyName.Text = tostring(k)
		ui.first.Text = inputValueToName(value[1])
		ui.second.Text = inputValueToName(value[2])

		ui.first.MouseButton1Up:Connect(function()
			beginCapture(ui.first, ui.none, function(input)
				value[1] = inputToValue(input)
			end)
		end)
		ui.second.MouseButton1Up:Connect(function()
			beginCapture(ui.second, ui.none, function(input)
				-- never leave a hole: an empty primary takes the bind instead
				if value[1] == nil or value[1] == -1 then
					value[1] = inputToValue(input)
				else
					value[2] = inputToValue(input)
				end
			end)
		end)

		ui.none.MouseButton1Down:Connect(function()
			clearCapture() -- "none" IS the answer, so don't revert the row
			if ui.first.Text == "_"  then value[1] = -1 end
			if ui.second.Text == "_" then value[2] = -1 end
			clientData:saveKeyBinds()
			open()
		end)

		ui.Visible = true
		ui.Parent = list
	end
end

local function close()
	isOpen = false
	clear()
end

-- Connected ONCE, not per open. The old code re-hooked `reset` on every render, so
-- the handler count grew with each visit to the tab.
resetBtn.MouseButton1Up:Connect(function()
	clientData:resetKeyBinds()
end)

-- Reset is a server round trip; rebuild when it lands rather than leaving the list
-- emptied out until the player reopens the tab.
clientData.plrObj.onKeybindsUpd:Connect(function()
	if isOpen then open() end
end)

return {
	order = 100,
	open = open,
	close = close,
}
