--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp): wepType.atkResult
	local function indicator()
		this:indicateAtk()
	end

	return this.basicAtks.arial(
		this,
		script.arial, -- anim
		dmgConfig.m1, -- dmgtbl
		0.9, -- windup
		9, -- force
		0.8, -- force duration
		CFrame.new(0, -2, -7), -- hitboxoffset
		Vector3.new(6, 6, 10), -- hitbox sz
		indicator,
		0.08, -- fadetime
		1,    -- weight
		0.6     -- speed
	)
end