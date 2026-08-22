--!strict
--[[ Oblitar sprint attack - rowa1's THRUST (Main `typ == 3`, Anims.Thrust).

	rowa1: Attacking.Time 0.45 * AtkRate, MiniDash(LookVector, 30, 0.4),
	Hold.Swing1 + Hold.afterswing, then Damage(6).

	!! Damage(6) IS `oblM1`, NOT `oblH2`. PORTW_Oblitar's PORT section reads
	as though oblH2 were the thrust; it is not, it is the heavy's second beat
	(Damage(9)). The two sit four branches apart in the same if-chain. The
	thrust is an m1-strength poke with a lunge, which is also why it is bound
	to sprintAtk rather than to a heavy.

	FORCE 12, not the 6 a literal MiniDash conversion gives.
	S7 rule 10 converts a rowa1 MiniDash power P to P/5 -- but that ratio is
	for a FLAT mover. rowa1's BodyVelocity holds 30 studs/s for the whole
	0.4s; rowa2's bodyForce DECAYS across the same window, so it needs roughly
	double the number to cover the same ground. 12 is also exactly what the
	shipped Claymore sprint uses, and PORTW_00's rule for weapons is to
	compare against the nearest shipped rowa2 weapon rather than against
	rowa1.

	NOT PORTED: rowa1 re-queried the hitbox twice more on a whiff
	(`if #Damage(6) == 0 then ... if #Damage(6) == 0 then`). basicAtks.sprint
	owns whiff handling for every weapon; re-adding a bespoke retry here is
	the per-caller duplication PORTW_00 exists to prevent. ]]
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
		--[[ 0.55 BASE. rowa1's real waits are 0.2 + 0.25 = 0.45, and that is
			what shipped -- but the m1 was deliberately slowed +0.1 in
			playtest and this was left behind, so the running attack came out
			faster than the standing one on a weapon that is supposed to
			commit. Carries the same +0.1. Like the m1's, this is a tuning
			call, NOT a rowa1 number -- do not "correct" it back by reading
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
