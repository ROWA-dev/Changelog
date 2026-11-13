--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

local FLOURISH = table.freeze({
	anim = script.swing3, cycle = 3, speed = 1.1,
	windup = 0.46,
	cf = CFrame.new(0, 0, -2),
	sz = Vector3.new(5.5,6,5.5),
	dmg = dmgConfig.kick,
	leftLeg = true,
})

return function(this:wepBase.myself&any): wepBase.atkResult
	local function indicator()
		this:indicateAtk()
	end
	

	if tick() > this.lastAttacked + this.atkRate.Value then this.m1cycle = 0 end

	if this.m1cycle == 2 then 
		return this.basicAtks.flourish(this, FLOURISH)
	end
	
	return this.basicAtks.m1(
		this,
		script, -- animsParent
		3, -- m1CycleCount
		dmgConfig.m1,
		0.5, -- windup
		CFrame.new(0,0,-3.5), -- hitboxoffset
		Vector3.new(6.5,6,6.5), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1.02, -- speed
		0.08  -- endlag
	)
end
