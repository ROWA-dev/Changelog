--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

export type myself = baseClass.myself

local REGRANT_DELAY = 0.3
local REGRANT_WINDOW = 0.5
-- total damage ONE chain may evade. refills whenever the chain lapses.
local DODGE_BUDGET = 40

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	local pending, spent, chainUntil = false, 0, 0

	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not attack:isDodged() then return end
		-- the chain is live while a regrant is pending OR the window it granted is still up.
		-- pending is load bearing: without it a dodge in the decide gap refills the budget.
		if not pending and tick() > chainUntil then spent = 0 end
		-- charged ABOVE the pending guard, or dodges landing in the decide gap are free.
		spent += attack:CalculateDamage()
		if spent > DODGE_BUDGET or pending then return end
		pending = true

		fireVFX("fstep", humObj.Model, 0.4)

		task.delay(REGRANT_DELAY, function()
			pending = false
			local hobj = self._humObj
			if hobj == nil or hobj.isActive ~= true then return end
			if hobj.attacking.Value == true then return end
			-- math.max: never shorten a longer window something else set.
			hobj.dodgeThreshold = math.max(hobj.dodgeThreshold, tick() + REGRANT_WINDOW)
			-- copied AFTER the max, so it is the window actually being ridden.
			chainUntil = hobj.dodgeThreshold
		end)
	end))

	-- swinging forfeits the regranted window, never a window something else set.
	self:addConnection(humObj.attacking.Changed:Connect(function(attacking: boolean)
		if attacking and humObj.dodgeThreshold == chainUntil then humObj.dodgeThreshold = 0 end
	end))

	return self
end

return table.freeze(module)
