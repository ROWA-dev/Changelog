local plrHandler = require(game.ServerScriptService.PlrHandler)
local plrObj = plrHandler.Get(script.Parent.Parent.Parent)

local weps = require(game.ServerStorage.ROWA.Weps)
local items = require(game.ServerStorage.ROWA.Items)

for i,v in pairs(weps.wepList) do
	local wepButton = script.TextButton:Clone()
	wepButton.MouseButton1Down:Connect(function() 
		--local newWep = weps.newWep(i)
		if plrObj.loadedSlot == nil then return end
		local newItem = items.newItem(2, i)
		local leftover = plrObj.loadedSlot:insertItem(newItem)
		if leftover then
			leftover:destroy()
		end
	end)
	wepButton.Text = v.Name
	wepButton.Name = v.Name
	wepButton.Parent = script.Parent.ScrollingFrame
end