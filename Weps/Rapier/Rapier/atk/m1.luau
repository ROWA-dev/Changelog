--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

local FLOURISH = table.freeze({
	anim = script.swing5, cycle = 5, speed = 1.2,
	windup = 0.36,
	cf = CFrame.new(0, 0, -2),
	sz = Vector3.new(5.5,6,5.5),
	dmg = dmgConfig.punch,
})

return function(this:wepBase.myself&any): wepBase.atkResult
	local function indicator()
		this:indicateAtk()
	end

	if tick() > this.lastAttacked + this.atkRate.Value then this.m1cycle = 0 end

	if this.m1cycle == 4 then 
		return this.basicAtks.flourish(this, FLOURISH)
	end
	
	return this.basicAtks.m1(
		this,
		script, -- animsParent
		5, -- m1CycleCount
		dmgConfig.m1,
		0.4, -- windup
		CFrame.new(0, 0, -3), -- hitboxoffset
		Vector3.new(4,6,6.5), -- hitbox sz
		indicator,
		-- anim stuff
		0.08, -- fadetime
		1,   -- weight
		1,   -- speed
		0.02 -- endlag
	)
end
