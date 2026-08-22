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
		0.49, -- windup
		9, -- force
		0.48, -- force duration
		CFrame.new(0, -2, -5), -- hitboxoffset
		Vector3.new(6, 6, 7), -- hitbox sz
		indicator,
		0.08, -- fadetime
		1,    -- weight
		0.8     -- speed
	)
end
