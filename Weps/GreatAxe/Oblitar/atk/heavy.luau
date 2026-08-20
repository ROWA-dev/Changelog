--!strict
--[[ Oblitar heavy - TWO BEATS ON ONE PRESS, the second of which executes.

	rowa1 Main, `typ == 2`, gated on `tick() > lastHeavy + 5`:
	    hshock fx, Heavy anim, Blade.Top.sharp:Emit(1), Hold.HeavySwing
	    Attacking.Time = 0.6 * AtkRate
	    clone Effects.OblitarFX, weld to root, Debris 4
	    wait 0.4              [cancel check]
	    Hold.BladeSwing
	    wait 0.2              [cancel check]
	    -> fx.BladeSwing + fx.Swing + emit slice1/line1, Damage(5) = oblH
	    wait 0.2 * AtkRate    [cancel check]
	    Hold.BladeSwing
	    wait 0.2 * AtkRate    [cancel check]
	    -> lastHeavy = tick(), fx.BladeSwing2 + fx.Swing + emit slice2/line2,
	       Damage(9) = oblH2

	NOT A CHARGE. See attack.luau for why there is no heavyEnd.

	!! TIMING, README S7 rule 7f -- the single most common bug in this port.
	feintWait waits t - 0.08 EVERY call, so chaining loses 0.08 a beat.
	  the FIRST call is the WINDUP (rowa1's Attacking.Time 0.6) -> pass 0.6
	  the SECOND is a plain beat between hits (0.2 + 0.2 = 0.4) -> pass 0.48
	Total loss is 0.08 once, not twice, which is the audit rule.

	!! AND rowa1 IS INCONSISTENT ABOUT AtkRate INSIDE THIS ONE MOVE.
	Beat one waits `0.4` then `0.2` -- UNSCALED. Beat two waits `0.2*AtkRate`
	twice -- SCALED. rowa2's scaledTime applies atkRate to everything, so beat
	one runs ~3% longer here than in rowa1 and beat two matches exactly. Left
	as is: 0.018s is well under perception and matching it would mean dividing
	the windup by atkRate, which reads as a typo to the next person.

	!! THE ANIM IS SPEED 1.05, NOT 1. rowa1's heavy calls `AdjustSpeed(1)` --
	unlike its m1/flourish/thrust, which all use `1/AtkRate`. PlayAnim divides
	by atkRate, so 1.05/1.05 lands on rowa1's 1.0. Passing 1 here played the
	whole swing at 0.952 and was half of why the heavy felt slow.

	THE 5s GATE IS SET AFTER THE SECOND BEAT in rowa1, not on press, so the
	real gap is 5s from the END. triggerCD is called at the same point here.
	Wielding sets the cooldown length (Oblitar.wield). ]]
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local HITBOX_SZ = Vector3.new(6.5, 7, 6.5)

--- emit every emitter under an OblitarFX attachment, the way rowa1 did.
local function emitAll(fx: Instance, name: string)
	local holder = fx:FindFirstChild(name)
	if holder == nil then return end
	for _, v in pairs(holder:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 1)
		end
	end
end

local function playSound(parent: Instance?, name: string)
	local s = parent and parent:FindFirstChild(name)
	if s and s:IsA("Sound") then s:Play() end
end

--- one beat: query, resolve, report whether anything landed.
local function swing(this:wepTyp&any, dmgTbl, offset:number): boolean
	local hurtbox = this._humObj.HurtBox
	local hitbox, hits = this:hitbox(CFrame.new(0, 0, -offset), HITBOX_SZ)

	local landed = false
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(dmgTbl, enemy, hurtbox.CFrame.LookVector)
		attack.hitbox = hitbox

		--[[ rowa1 knocks back on the SECOND beat only (Damage(9)), LookVector
			*30 -> force *0.6 = 18. The first beat has none, which is what
			keeps the victim inside the second beat's hitbox. Adding one to
			beat 1 knocks them out of the finisher -- the same mistake
			PORT_Rend documents. ]]
		if dmgTbl == dmgConfig.heavy2 then
			attack.knockback = this:knockback(hurtbox.CFrame.LookVector*18, 0.3)
		end

		this:executeAttack(attack)
		if attack:isHit() then
			landed = true
		end
	end
	return landed
end

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end

	local humObj = this._humObj
	local model  = this._model
	local hold   = model:FindFirstChild("Hold")

	fireVFX("hshock", humObj.HurtBox)

	local anim = this:PlayAnim(script.Heavy, 0.08, 1, 1.05)
	this:indicateAtk()

	local sharp = model:FindFirstChild("sharp", true)
	if sharp and sharp:IsA("ParticleEmitter") then sharp:Emit(1) end
	playSound(hold, "HeavySwing")

	--[[ the trail/slash body. rowa1 parked this in ServerStorage.Effects and
		reached for it by path; rowa2 keeps fx assets as CHILDREN of the thing
		that uses them (README S2), so it is cloned off this module.
		Emitters are fired SERVER-side exactly as rowa1 did -- Emit replicates,
		and the part is welded to a root that every nearby client already has,
		so the streaming rule (S5 7i) does not bite here. ]]
	local fx = script.OblitarFX:Clone()
	local weld = fx:FindFirstChild("Weld")
	if weld and weld:IsA("Weld") then
		weld.Part0 = fx
		weld.Part1 = humObj.HRootPart
	end
	fx.Parent = workspace.Effects
	game.Debris:AddItem(fx, 4)

	local function bail()
		if anim then anim:Stop() end
		game.Debris:AddItem(fx, 0)
	end

	--[[ BEAT ONE. 0.6 is the BASE (rowa1's 0.4 + 0.2, and its claim agrees);
		atkRate 1.05 scales it to rowa1's real 0.63. Do not pre-multiply. ]]
	if this:feintWait(0.6) then bail() return end

	playSound(hold, "BladeSwing")
	playSound(fx, "BladeSwing")
	playSound(fx, "Swing")
	emitAll(fx, "slice1")
	emitAll(fx, "line1")

	local landed = swing(this, dmgConfig.heavy, 4.5)

	-- BEAT TWO. 0.4 of real wait, +0.08 because this is not a windup.
	if this:feintWait(0.48) then bail() return end

	this:triggerCD("heavy")

	playSound(hold, "BladeSwing")
	playSound(fx, "BladeSwing2")
	playSound(fx, "Swing")
	emitAll(fx, "slice2")
	emitAll(fx, "line2")

	if swing(this, dmgConfig.heavy2, 4) then
		landed = true
	end

	--[[ NO ENDLAG, and that is not an oversight.
		This shipped with `endLag(landed and 0.2 or 0.4)`, invented here rather
		than ported -- rowa1 has NONE: after Damage(9) it sets
		`Attacking.Value = false` and the move is simply over. Up to 0.4s of
		invented recovery on the back of an already-committed two-beat swing is
		the main reason the heavy read as sluggish.
		If it needs a whiff punish later, add it on the `not landed` branch
		ONLY, and keep it well under 0.4. ]]
	return landed
end
