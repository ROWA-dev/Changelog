--!strict
-- QuickStep - a successful dodge regrants a short second window to
-- dodge, as long as you spend the gap defending rather than swinging.
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

export type myself = baseClass.myself & {
	_pending: boolean,
}

local REGRANT_DELAY = 0.3 -- rowa1 waited this before deciding
local REGRANT_WINDOW = 0.6

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._pending = false

	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not attack:isDodged() then return end
		-- one regrant in flight at a time; rowa1 spawned a thread per dodge.
		if self._pending then return end
		self._pending = true

		local char = humObj.Hum and humObj.Hum.Parent
		if char then fireVFX("fstep", char, 0.4) end

		task.delay(REGRANT_DELAY, function()
			self._pending = false
			local hobj = self._humObj
			if hobj == nil or hobj.isActive ~= true then return end
			-- rowa1's condition: the window is for staying on the defensive.
			if hobj.attacking.Value == true then return end
			-- math.max: a dash in the gap already set a longer one, never shorten it.
			hobj.dodgeThreshold = math.max(hobj.dodgeThreshold, tick() + REGRANT_WINDOW)
		end)
	end), "quickstep")

	return self
end

function module.destroy(self:myself)
	self:remConnection("quickstep")
	baseClass.destroy(self)
end

return table.freeze(module)
