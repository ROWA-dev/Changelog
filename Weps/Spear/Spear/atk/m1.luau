--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

local FLOURISH = table.freeze({
	anim = script.swing4, cycle = 4, speed = 0.9,
	windup = 0.42,
	cf = CFrame.new(0, 0, -3),
	sz = Vector3.new(6.5,6.5,6.5),
	dmg = dmgConfig.punch,
})

return function(this:wepBase.myself&any): wepBase.atkResult
	local humObj = this._humObj
	local function indicator()
		this:indicateAtk()
	end

	if tick() > this.lastAttacked + this.atkRate.Value then this.m1cycle = 0 end

	if this.m1cycle == 3 then 
		return this.basicAtks.flourish(this, FLOURISH)
	end
	
	return this.basicAtks.m1(
		this,
		script, -- animsParent
		4, -- m1CycleCount
		dmgConfig.m1,
		0.46, -- windup
		CFrame.new(0,0,-4), -- hitboxoffset
		Vector3.new(5,6.5,6), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1    -- speed
	   -- 0.08  -- endlag
	)
end
