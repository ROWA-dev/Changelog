--!strict
--[[ Slayer sprint attack - rowa1's THRUST (Main `typ == 3`, Anims.Thrust).

	rowa1: Attacking.Time 0.52*AtkRate, and the real waits are
	0.32 + 0.2 = 0.52 base -- claim and truth AGREE here, so 0.52 is honest.
	MiniDash(look, 26, 0.5), Hold.Swing1 at pitch 1.1 between the two waits,
	then Damage(5) = `slM1` plus Knockback LookVector*30.

	Uses the m1 row, as rowa1 does -- the thrust is a repositioning poke, not
	a heavy. Its knockback is what makes it a disengage. ]]
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp&any): wepType.atkResult
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox

	local function indicator()
		humObj.limbTrails:indicatorLeft()
		local hold = this._model and this._model:FindFirstChild("Hold")
		task.delay(this:scaledTime(0.32), function()
			if this._humObj == nil or this._humObj:inStun() then return end
			local s = hold and hold:FindFirstChild("Swing1")
			if s and s:IsA("Sound") then
				s.Pitch = 1.1
				s:Play()
			end
		end)
	end

	--- rowa1 Knockback look*30 -> S7 rule 9, K * 0.6 = 18.
	local function addKb(attack)
		attack.knockback = this:knockback(hurtbox.CFrame.LookVector*18, 0.3)
	end

	return this.basicAtks.sprint(
		this,
		script.sprintAtk, -- anim
		dmgConfig.m1, -- dmgtbl
		0.52, -- windup BASE; atkRate 1.18 scales it
		--[[ 10, not 26/5. rowa1's MiniDash holds 26 studs/s FLAT for 0.5s;
			rowa2's bodyForce decays over the same window, so the naive P/5
			undershoots badly. Same correction Oblitar's thrust needed. ]]
		10, -- force
		0.5, -- force duration
		CFrame.new(0, 0, -4.5), -- hitboxoffset
		--- +2 per axis over the rowa1 translation (was 5.5,7,6.5). See m1.
		Vector3.new(7.5, 9, 8.5), -- hitbox sz
		indicator,
		-- anim stuff
		0.08, -- fadetime
		1,    -- weight
		1,    -- speed. atkRate divides -> 0.847, rowa1's AdjustSpeed
		addKb -- atkCB comes straight after speed, there is no endlag param
	)
end
