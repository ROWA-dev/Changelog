--!strict
--- Slayer m1 - a THREE link chain (PORTW_Slayer says five), all sharing the
--- `slM1` row. See Slayer.luau's header. Every link is 0.2 + 0.3 = 0.5 base;
--- link 3 is the FLOURISH -- same row, plus a knockback.
--- 0.5 is the BASE: atkRate scales it to rowa1's real 0.59, do not pre-multiply
--- (PORTW_00 trap 2). The declared Attacking.Time agrees here, unlike Oblitar's.
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

	--- knockback on EVERY link, not just the flourish: a literal read of rowa1
	--- gives links 1 and 2 none, which made the chain feel like it hit air.
	--- Safe against the helper -- attackHelpers/m1 runs atkCB first and then
	--- overwrites knockback on the wrap, so this only ever sets links 1 and 2.
	--- 7 is well under the flourish's 16: the chain nudges, the flourish sends.
	local function nudge(attack)
		attack.knockback = this:knockback(this._humObj.HurtBox.CFrame.LookVector * 6, 0.1)
	end

	local result = this.basicAtks.m1(
		this,
		script, -- animsParent, expects swing1..swing3
		3, -- m1CycleCount. THREE, not five.
		dmgConfig.m1,
		--[[ 0.5, and the arithmetic matters. rowa1's real windup is
			0.2 + 0.3 = 0.5 base, x AtkRate 1.18 = 0.59s to the hit, and
			scaledTime does exactly that multiply -- so the base passes
			straight through and the hit lands where rowa1 puts it. ]]
		0.5, -- windup
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
		--- !! ZERO, NOT nil: the helper only sets `m1last` inside `elseif endlag`,
		--- and 0 is truthy, so 0 gates the chain with an already-expired time
		--- while nil leaves it ungated. Same delay, different meaning.
		--- Zero rather than 0.08 because rowa1's gate has already expired by the
		--- time the swing resolves -- the cadence correction lives in the windup
		--- above, where rowa1 pays it, not after the hit where it reads as sticky.
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
