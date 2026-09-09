--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- beforeAttacked is the last point before HandleAttack asks isDodge, and inCombat
	-- still answers about the state this blow is about to change (addEntry is in resolveHit).
	self:addConnection(humObj.beforeAttacked:Connect(function(attack)
		if humObj:inCombat() then return end
		-- a parry beats a dodge and Dash CLEARS the parry window, so never step on one
		if humObj:isParry(attack) then return end

		-- a real dash, Inputs' shape, so the owner client draws and moves it. It sets
		-- dodgeThreshold itself; the manual i-frame is the fallback for when it cannot
		-- run (stunned, mid-attack, dash on cooldown) so the dodge is never lost.
		if humObj:Dash(Vector3.zero, true) == false then
			humObj.dodgeThreshold = tick()
		end

		-- !! WITHOUT THIS IT NEVER STOPS FIRING: a dodge deals no damage, so nothing
		-- calls addEntry, so every next swing is "the first hit" too. A zero-damage
		-- entry is the honest fix -- you are in the fight, you just took nothing.
		local attacker = attack.myEntity
		if attacker then humObj.dmgRecord:addEntry(attacker, 0) end
	end), "firstInstinct")

	return self
end

function module.destroy(self:myself)
	self:remConnection("firstInstinct")
	baseClass.destroy(self)
end

return table.freeze(module)
