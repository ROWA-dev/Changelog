--!strict
--- Slayer heavy - a GRAB AND DRAG, not a swing. rowa1 Main `typ == 2`, gated on
--- `tick() > lastHeavy + 8`. PORTW_Slayer never describes this move; read
--- Slayer.luau's header first.
--- The beats: catch (slM2, welds them to the blade) -> guard break (slM3) ->
--- drag + 13x grind (slM5) -> launch (slM4) -> release.
--- !! THE WELD OFFSET IS ROTATION *AND* TRANSLATION, against PORT_00_INDEX's
--- shared prelude: it starts at -3 and moves to -2 mid-move, so the victim
--- slides UP the blade. Porting it as pure rotation loses the whole gesture.
--- !! Attacking.Time claims 1.4; the real windup is a 1.0s loop (S5 7g). Ported
--- the waits, not the claim -- 1.4 makes an already slow weapon unusable.
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local GRIND_TICKS = 13
local GRIND_STEP  = 0.05
--- how long the blade may hold someone. The drag is ~1s; this is the leash.
local GRAB_MAXTIME = 2.5

--[[ +2 on every axis over the straight rowa1 translation (was 4,11,8).
	rowa2's hurtbox is a single 4x7x4 part where rowa1 tested against the
	character's real limbs, so hitboxes sized off rowa1 numbers under-reach.
	This one matters more than the others: if the CATCH misses, the entire
	move is spent for nothing. ]]
local CATCH_SZ = Vector3.new(6, 13, 10)

local CATCH_C0 = CFrame.Angles(math.rad(-90), 0, math.rad(90)) * CFrame.new(0, 0, -3)
local DRIVE_C0 = CFrame.Angles(math.rad(-90), 0, math.rad(90)) * CFrame.new(0, 0, -2)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function emit(holder: Instance?, name: string, n: number)
	local e = holder and holder:FindFirstChild(name)
	if e and e:IsA("ParticleEmitter") then e:Emit(n) end
end

local function playSound(parent: Instance?, name: string, timePos: number?)
	local s = parent and parent:FindFirstChild(name)
	if s and s:IsA("Sound") then
		if timePos then s.TimePosition = timePos end
		s:Play()
	end
end

--- hit everyone currently on the blade with `dmgTbl`.
local function beat(this:wepTyp&any, held, dmgTbl, kb: Vector3?)
	local hurtbox = this._humObj.HurtBox
	for _, enemy in held do
		if enemy.isActive then
			local attack = this:makeAtk(dmgTbl, enemy, hurtbox.CFrame.LookVector)
			if kb then
				--[[ decayT -1 = LINEAR, i.e. no decay. Copied from StrongLeft,
					whose comment explains it: a decaying knockback leaves a
					"magic break force" tailing off after the hit. A throw wants
					to commit its whole velocity at once.
					isRootRelative false because the vector is already in world
					space (it has a Y component that must stay up). ]]
				attack.knockback = this:knockback(kb, 0.3, false, -1)
			end
			this:executeAttack(attack)
		end
	end
end

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local model   = this._model
	local hold    = model:FindFirstChild("Hold")
	local blade   = model:FindFirstChild("Blade", true)

	local anim = this:PlayAnim(script.Heavy, 0.08, 1, 1.18)
	this:indicateAtk()
	playSound(hold, "heavier", 0.2)

	--[[ 0.915, NOT 1. This is the one windup in the weapon that must NOT be
		written as a base number, and shipping it as 1 made the catch land
		early relative to its own telegraph.

		rowa1's heavy windup is `local endt = tick() + 1` -- a RAW 1.0s, with
		no AtkRate on it, unlike its m1 which writes `0.2*AtkRate`. So 1.0 is
		already the final number, not a base to be scaled. Passing 1 here
		would run it through scaledTime (x1.18).
		Solving `t*1.18 = 1.0` gives 0.847, which lands the catch at exactly
		rowa1's 1.0s.
		(Its DECLARED Attacking.Time is 1.4, which is a lie in the other
		direction -- S5 note 7g. Neither number is usable as written.) ]]
	if this:feintWait(0.847) then
		if anim then anim:Stop() end
		return
	end

	this:triggerCD("heavy")

	--- the commit tell
	local ringCF = CFrame.new(
		hurtbox.Position + hurtbox.CFrame.LookVector*5,
		hurtbox.Position + hurtbox.CFrame.LookVector*10)
	fireVFX("shockRing", ringCF, Vector3.new(8, 8, 0.5), 0.9, true)
	fireVFX("cyldrshock", ringCF * CFrame.Angles(0, math.rad(90), math.rad(90)))
	fireVFX("camShake", hurtbox.Position, 200, 0.3, 0.2)
	emit(blade and blade:FindFirstChild("Bottom"), "Spike", 1)

	-- THE CATCH
	local hitbox, hits = this:hitbox(CFrame.new(0, 0, -4.5), CATCH_SZ)
	local held = {}
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(dmgConfig.heavyCatch, enemy, hurtbox.CFrame.LookVector)
		attack.hitbox = hitbox
		this:executeAttack(attack)

		--[[ rowa1 welds on anything that is not a parry or a dodge -- so a
			BLOCK still gets you carried. Kept: it is what makes the move
			worth its 8s gate, and blocking already costs posture. ]]
		if attack:isHit() or attack:isBlocked() then
			enemy.grab:grab(humObj, CATCH_C0, GRAB_MAXTIME, blade)
			table.insert(held, enemy)
		end
	end

	local function release()
		for _, enemy in held do
			if enemy.grab then enemy.grab:release() end
		end
	end

	if #held == 0 then
		--- whiffed the catch. rowa1 simply ends here.
		this:endLag(0.4)
		return false
	end

	local bottom = blade and blade:FindFirstChild("Bottom")
	emit(bottom, "47", 2)
	emit(bottom, "48", 2)
	emit(bottom, "53", 2)

	local att    = blade and blade:FindFirstChild("Attachment")
	local debris = att and att:FindFirstChild("Debris")
	local smoke  = att and att:FindFirstChild("smoke")

	this:atkWait(0.2)
	if anim then anim:Stop() end
	local anim2 = this:PlayAnim(script.Heavy2, 0.08, 1, 1.18)
	this:atkWait(0.2)

	fireVFX("camShake", hurtbox.Position, 200, 0.5, 1)
	fireVFX("shockRing",
		CFrame.new(hurtbox.Position + Vector3.new(0,-2,0),
		           hurtbox.Position + Vector3.new(0,-100,0)),
		Vector3.new(8, 8, 0.5), 0.9, true)

	--[[ tint the debris to whatever is underfoot. Small touch, but it is the
		difference between "the ground is being torn up" and "some grey
		particles". rowa1 raycasts 10 studs down, ignoring Effects, itself
		and everyone currently on the blade. ]]
	local ignore = { workspace.Effects, humObj.Hum.Parent }
	for _, enemy in held do
		if enemy.Hum and enemy.Hum.Parent then table.insert(ignore, enemy.Hum.Parent) end
	end
	rayParams.FilterDescendantsInstances = ignore
	local ground = workspace:Raycast(hurtbox.Position, Vector3.new(0,-10,0), rayParams)
	if ground and ground.Instance then
		local col = ColorSequence.new(ground.Instance.Color)
		if debris then (debris :: any).Color = col end
		if smoke then (smoke :: any).Color = col end
	end

	emit(att, "Debris", 8)
	emit(att, "smoke", 8)
	playSound(hold, "Rock Impact 2 (SFX)")

	task.wait(0.1)

	-- drive it in: the victim slides up the blade
	for _, enemy in held do
		if enemy.grab and enemy.grab.weld then
			enemy.grab.weld.C0 = DRIVE_C0
		end
	end
	beat(this, held, dmgConfig.heavyBreak)

	--- THE DRAG. rowa1 MiniDash2, which differs from MiniDash in one expression:
	--- it claims FULL vertical authority at Velocity.Y 0, pinning the caster's
	--- vertical motion. That is what makes it a skate rather than a shove.
	--- !! bodymover derives maxforce from the velocity's own direction, so a
	--- purely horizontal (0,0,-n) can only ever be a MiniDash. The small -2 on Y
	--- is the fix: it skips the Y-flattening branch AND puts a real number in
	--- maxforce.Y, and pressing slightly down is the closest this gets to the pin.
	--- decayT IS DELIBERATELY OMITTED -- a falling scaler is right for a sprint
	--- lunge and wrong for a drag. 0.7 not 0.6 so the slide covers the whole grind.
	local drag = this:bodyForce(Vector3.new(0, -2, -10), 0.7, true)

	-- THE GRIND
	local cancelled = false
	for _ = 1, GRIND_TICKS do
		if humObj:inStun() or not humObj.isActive then
			cancelled = true
			break
		end
		emit(att, "Debris", 3)
		emit(att, "smoke", 4)
		task.spawn(beat, this, held, dmgConfig.heavyGrind)
		task.wait(GRIND_STEP)
	end

	drag:destroy()

	--- rowa1 shoves the CASTER down and back as they plant the finisher
	this:bodyForce(Vector3.new(0, -2, 2), 0.2, true, 0.2)
	emit(att, "Debris", 12)
	emit(att, "smoke", 12)

	--- !! RELEASE THE WELD *BEFORE* THE LAUNCH -- the whole reason the throw was
	--- ragdolling people without sending them anywhere. rowa1 releases after, but
	--- the engines invert: rowa2 applies knockback INSIDE HandleAttack, i.e.
	--- BEFORE the row's onHit, so the force hit a root still welded to the blade
	--- and had nothing to push. Unweld first for knockback -> ragdoll on a free body.
	release()

	-- THE LAUNCH
	if not cancelled then
		--- rowa1 Knockback (0,12,0) + look*12 -> S7 rule 9, K * 0.6
		beat(this, held, dmgConfig.heavyLaunch, Vector3.new(0, 4, 0) + hurtbox.CFrame.LookVector*4)
	end

	if anim2 then anim2:Stop() end
	this:endLag(0.2)
	return not cancelled
end
