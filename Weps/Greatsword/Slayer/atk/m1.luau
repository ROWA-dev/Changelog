--!strict
--[[ Slayer m1 - a THREE link chain. PORTW_Slayer says five; it is three,
	and all three links share the `slM1` row. See Slayer.luau's header.

	rowa1 combo -> rowa2 m1cycle, and every link is identical in timing:
	    combo 0  Atk1  waits 0.2 + 0.3 = 0.5 base  -> swing1
	    combo 1  Atk2  waits 0.2 + 0.3 = 0.5 base  -> swing2
	    combo 2  Atk3  waits 0.2 + 0.3 = 0.5 base  -> swing3, and this one
	             is the FLOURISH: same row, plus Knockback LookVector*30.
	The declared Attacking.Time is 0.5*AtkRate on all three and agrees with
	the real waits, so 0.5 is honest here (unlike Oblitar's flourish).

	0.5 is the BASE. atkRate 1.18 scales it to rowa1's real 0.59; do not
	pre-multiply (PORTW_00 trap 2).

	m1CycleCount 3, so the helper's `animParent["swing"..(m1cycle+1)]` only
	ever reaches swing1..swing3 -- which is all MeleeAnims/Slayer has. ]]
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

--[[ rowa1 plays Hold.Swing1 at a DIFFERENT PITCH per link -- 0.9, 1.0, 0.8 --
	partway through each windup. That per-link detune is the chain's whole
	audio identity and it is three lines, so it ports rather than being
	flattened to one call. Scheduled at rowa1's own offset (0.2 of a 0.5
	windup) and guarded so a feint leaves no orphan sound. ]]
local PITCH = { 0.9, 1.0, 0.8 }

local function telegraph(this:wepBase.myself&any, link:number)
	local hold = this._model and this._model:FindFirstChild("Hold")
	if hold == nil then return end
	task.delay(this:scaledTime(0.2), function()
		if this._humObj == nil or this._humObj:inStun() then return end
		local swing = hold:FindFirstChild("Swing1")
		if swing and swing:IsA("Sound") then
			swing.Pitch = PITCH[link] or 1
			swing:Play()
		end
	end)
end

return function(this:wepBase.myself&any): wepBase.atkResult
	local link = (this.m1cycle % 3) + 1

	local function indicator()
		this:indicateAtk()
		telegraph(this, link)
	end

	--[[ KNOCKBACK ON EVERY LINK, not just the flourish.
		rowa1's Main only calls Knockback() on id 3 (the flourish) and id 5
		(the thrust), so a literal read gives links 1 and 2 none -- which is
		how this shipped, and it made the chain feel like it was hitting air.
		Slayer is a Heavy-weight greatsword; the shove is part of the weight.

		SAFE AGAINST THE HELPER: attackHelpers/m1 runs atkCB FIRST and then,
		only when m1cycle wraps to 0, OVERWRITES attack.knockback with its own
		distance-scaled flourish value (16 + a distance term, which is rowa1's
		LookVector*30 -> K*0.6 = 18). So this sets links 1 and 2 and is
		discarded on link 3, leaving the flourish exactly as it was.
		7 is deliberately well under the flourish's 16 -- the chain nudges,
		the flourish sends. ]]
	local function nudge(attack)
		attack.knockback = this:knockback(
			this._humObj.HurtBox.CFrame.LookVector * 7, 0.25)
	end

	local result = this.basicAtks.m1(
		this,
		script, -- animsParent, expects swing1..swing3
		3, -- m1CycleCount. THREE, not five.
		dmgConfig.m1,
		--[[ 0.568, and the arithmetic matters. rowa1's real windup is
			0.2 + 0.3 = 0.5 base, x AtkRate 1.18 = 0.59s to the hit. feintWait
			waits `scaledTime(t) - 0.08`, so solving `t*1.18 - 0.08 = 0.59`
			gives 0.568 and the hit lands exactly where rowa1 puts it. ]]
		0.568, -- windup
		CFrame.new(0,0,-3.5), -- hitboxoffset
		--[[ +2 on every axis over the straight rowa1 translation (was
			6.5,7,6.5). rowa2's hurtbox is a single 4x7x4 part, where rowa1
			tested against the character's actual limbs -- an R6 rig with arms
			out is wider and deeper than that box, so a hitbox sized off rowa1
			numbers under-reaches here. Applies to every hitbox in the weapon. ]]
		Vector3.new(8.5,9,8.5), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1,   -- speed. atkRate divides this -> 0.847, rowa1's AdjustSpeed
		-- endlag, then atkCB. See the note below on why endlag is 0.
		--[[ ENDLAG 0, NOT 0.08 -- AND THE ZERO IS LOAD-BEARING.
			attackHelpers/m1 only sets `m1last` (the gate on the next m1) inside
			`elseif endlag then`, and 0 is TRUTHY in Lua, so passing 0 still
			takes that branch and sets an already-expired gate. Passing nil
			skips it entirely and leaves the chain ungated. They are not the
			same thing even though the delay is identical.

			WHY ZERO AND NOT 0.08: rowa1's gate is `lastatk = tick() +
			0.4*AtkRate` = 0.472s set at the swing's START, and the hit does
			not land until 0.59s -- so by the time the swing resolves the gate
			has ALREADY expired. rowa1 has no post-hit delay on this weapon at
			all. The 0.08 shipped here put the whole cadence correction AFTER
			the hit, where it reads as sticky recovery. It now lives in the
			windup above, where rowa1 pays it, and the same total cadence reads
			as weight instead of endlag. ]]
		0, -- endlag
		nudge
	)

	--[[ rowa1 runs the m1 at TWO speeds: `AdjustSpeed(1/AtkRate)` for the
		windup, then `AdjustSpeed(1)` immediately after Damage (Main:390/410,
		418/438, 446/466 -- all three links do it). So the swing winds up slow
		and the follow-through snaps back to normal. Holding 0.847 for the
		whole track left the recovery dragging, which is most of "it feels
		off". Harmless if the track was stopped by a feint or a parry. ]]
	if this.lastAnim then
		this.lastAnim:AdjustSpeed(1)
	end

	return result
end
