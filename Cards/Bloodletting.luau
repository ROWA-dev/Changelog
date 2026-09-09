--!strict
return require(script.Parent:WaitForChild("heavyOnBleeding"))("bloodletting",
	function(humObj, victim, bleed)
		-- READ BEFORE REMOVE: destroy table.clears the effect. What is left to tick IS the heal.
		local healed = math.max(0, (bleed.startedAt + bleed.duration) - tick()) * bleed.damage
		victim.statusEffects:remove(humObj.statusEffects.Bleed)
		humObj:Heal(healed)
	end)
