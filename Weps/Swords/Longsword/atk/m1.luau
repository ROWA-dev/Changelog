--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any): wepBase.atkResult
	local humObj = this._humObj
	local function indicator()
		this:indicateAtk()
	end

	return this.basicAtks.m1(
		this,
		script, -- animsParent
		4, -- m1CycleCount
		dmgConfig.m1,
		0.5, -- windup
		CFrame.new(0,0,-4.5), -- hitboxoffset
		Vector3.new(6,6,6), -- hitbox sz
		indicator,
		-- anim stuff
		0.15, -- fadetime
		1,   -- weight
		0.99 -- speed
	)
end