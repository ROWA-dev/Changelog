--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself): wepBase.atkResult
	local humObj = this._humObj
	local function indicator()
		this:indicateAtk()
	end

	return this.basicAtks.m1(
		this,
		script, -- animsParent
		4, -- m1CycleCount
		dmgConfig.m1,
		0.48, -- windup
		CFrame.new(0,0,-3), -- hitboxoffset
		Vector3.new(6,6,6), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1.05 -- speed
	)
end