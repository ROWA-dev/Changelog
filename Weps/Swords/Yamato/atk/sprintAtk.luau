--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any): wepBase.atkResult
	return this.basicAtks.sprint(
		this,
		script.sprintAtk,
		dmgConfig.m1,
		0.44, -- windup
		12, -- force
		0.4, -- force duration
		CFrame.new(0, 0, -4.5), -- hitboxoffset
		Vector3.new(5, 5, 6), -- hitbox sz
		function()
			this:indicateAtk()
			this:sheathed(false)
		end,
		0.08, -- fadetime
		1,    -- weight
		1     -- speed
	)
end
