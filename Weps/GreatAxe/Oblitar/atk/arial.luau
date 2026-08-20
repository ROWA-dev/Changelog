--!strict
--[[ Oblitar arial. rowa1 Main `typ == 4 or 5`, Anims.Arial,
	Attacking.Time 0.5. Uses the m1 row, as rowa1 did. ]]
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
		0.5, -- windup
		10, -- force
		0.4, -- force duration
		CFrame.new(0, -2, -5), -- hitboxoffset
		Vector3.new(6.5, 6.5, 7), -- hitbox sz
		indicator,
		0.08, -- fadetime
		1,    -- weight
		1     -- speed
	)
end
