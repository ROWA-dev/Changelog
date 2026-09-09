--!strict
local EXTEND = 4
local CD_ID, COOLDOWN = "deepWound", 4

return require(script.Parent:WaitForChild("heavyOnBleeding"))(CD_ID,
	function(humObj, _victim, bleed)
		local cooldowns = humObj.cooldowns
		if cooldowns:canTrigger(CD_ID) == false then return end
		cooldowns:trigger(CD_ID, COOLDOWN) -- customCD registers it on first use
		bleed.duration += EXTEND
	end)
