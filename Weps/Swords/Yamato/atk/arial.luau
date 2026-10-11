--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any): wepBase.atkResult
	return this.basicAtks.arial(
		this,
		script.arial,
		dmgConfig.m1,
		0.42, -- windup
		10, -- force
		0.4, -- force duration
		CFrame.new(0, -2, -5), -- hitboxoffset
		Vector3.new(6, 6, 7), -- hitbox sz
		function()
			this:indicateAtk()
			this:sheathed(false)
		end,
		0.08, -- fadetime
		1,    -- weight
		1.2   -- speed
	)
end
