--!strict

local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp): wepType.atkResult
	local humObj = this._humObj
	local function indicator()
		humObj.limbTrails:indicatorLeft()
	end

	return this.basicAtks.sprint(
		this,
		script.sprintAtk, -- anim
		dmgConfig.m1, -- dmgtbl
		--[[ 0.55 BASE. rowa1's real waits are 0.2 + 0.25 = 0.45, but the m1 was
			deliberately slowed +0.1 in playtest and this carries the same, or
			the running attack comes out faster than the standing one.
			A TUNING call, NOT a rowa1 number -- do not "correct" it by reading
			Main. ]]
		0.47, -- windup BASE
		12, -- force
		0.4, -- force duration
		CFrame.new(0, 0, -4.5), -- hitboxoffset
		Vector3.new(5.5, 6.5, 6), -- hitbox sz
		indicator,
		-- anim stuff
		0.08, -- fadetime
		1,    -- weight
		--[[ 1, not Claymore's 1.05. PlayAnim divides by atkRate, so 1 here
			becomes 1/1.05 = 0.952 -- which is rowa1's own
			`AtkAnim:AdjustSpeed(1/AtkRate)` on the Thrust. Claymore passes
			1.05 because it has no atkRate mod, so that would land on 1.0. ]]
		1
	)
end
