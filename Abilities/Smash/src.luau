--!strict
--- Smash - uppercut someone into the air, flash-step up after them, drive them
--- back into the ground. rowa1 port: README.md/PORT_Smash.
---
--- ONE authored track (script.Smash) carries all four segments with the WHIFF
--- parked in the middle, so the move SEEKS rather than swapping clips.
--- Track seconds; MARK below is the spec, every beat is a gap between two marks:
---   0.00-0.70  windup, LEFT arm gathers      0.70  UPPERCUT LANDS
---   0.70-0.80  freeze frame -- the CLIP holds itself (identical keys), code
---              only holds the VICTIM through it
---   0.80-1.45  jump prep, they hang where the punch put them
---   1.45-2.60  SEEKED OVER on the hit path (it contains the whiff)
---   1.85-2.13  MISS ONLY: seek 0.70 -> 1.85, the whiff replaces the freeze
---   2.60-3.28  flash-step up and drive down    3.28  SLAM LANDS
---   3.28-3.87  land and recover, end of track
---
--- Victim is held with Modules/pinTo, the same call Divide makes -- NOT the
--- `floating` air-combo system, which is turned off all move. See killFloat.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Smash"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local pinTo    = require(game.ServerStorage.ROWA.Modules.pinTo)

--- rowa1 "ucut": Light, blunt, 10 dmg, stun 1.0, posMult 3. Shared with Divide.
local UCUT = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	--- 0.8s FLAT ragdoll (no ground check) so they flop through the launch
	--- instead of standing up mid-air. Shares Divide's rowa1 row -- keep them in
	--- step. Not extended here; the hang is topped up at the pin, see HOLD.
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * -40)
	end,
}

--- rowa1 "ssmash" was 60 dmg, the highest single hit outside Cero off ONE
--- confirmed uppercut. Cut hard.
local SSMASH = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blunt),
	dmg      = 40,
	stun     = 0.6,
	posMult  = 3,
	parryH   = -0.04,
	--- rowa1 ssmash sounds: HeavyHit, wet_punch2
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyHit", "wet_punch2")
	end,
}

local SLOW_KEY = "smash"

--- the throw AND the angle of its fx: one pair with two users, so the pillar
--- and the victim cannot drift apart. x0.6 off rowa1's lookVec*30 + (0,40,0).
local LAUNCH_FWD, LAUNCH_UP = 15, 21

--- rowa1's roll about the pillar's own axis; decides only where the two rings
--- sit around the column, not the lean.
local FX_ROLL = CFrame.Angles(math.rad(-180), math.rad(75), 0)

--- Marks along the one track, in seconds. THE ANIMATION IS THE SPEC; if the
--- clip is re-exported these move and nothing else does. See the header.
local MARK = table.freeze({
	UPPERCUT   = 0.70,
	FREEZE_END = 0.80,
	PREP_END   = 1.45,
	MISS_IN    = 1.85,
	MISS_OUT   = 2.13,
	TELE_IN    = 2.60,
	SLAM       = 3.28,
	TRACK_END  = 3.87,
})

--- the pin captures a FIXED world point, so it must be taken at the top:
--- 0.38s of rise, measured from FREEZE_END because the launch does not really
--- begin until the freeze lets go. Grab earlier and they hang low.
local APEX = MARK.FREEZE_END + 0.38

--- how long the victim hangs pinned: the tail of the prep, plus the whole
--- flash-step. Derived, never typed as its own number.
local HOLD = (MARK.PREP_END - APEX) + (MARK.SLAM - MARK.TELE_IN)

--- !! this hold has to WIN against the launch it just ate. pinTo's default arm
--- (mass*4000) loses to the live knockback mover (mass*10000), so passing
--- `axes` is required -- it switches pinTo to MaxAxesForce = axes*1e7.
--- All three axes, unlike Divide's (1,0,1): for 0.1s nothing may move at all.
local FREEZE_HOLD = table.freeze({
	axes = Vector3.one,
	responsiveness = 200,
	maxTime = 0.35,
})

--- where the caster is hauled for the flash-step, relative to the pinned
--- victim. Up and slightly short -- their exact point ends the step INSIDE
--- them. smashDown's hold expires 0.18s early, so the last stretch is a fall.
local CASTER_OVER = Vector3.new(0, 7, 0)
local CASTER_BACK = 2

--- !! the air-combo float and this move cannot both own the victim's height:
--- the float makes their client apply anti-gravity every frame (rubber-banding
--- against the pin) and unragdolls them mid-air. Armed from `blockedOrHit`,
--- which runs AFTER dmgTbl.onHit, so this cannot live in a dmgTbl -- it has to
--- be here, after executeAttack. Guarded: `floating` is not in Combatant.
local function killFloat(entity:any)
	if entity == nil then return end
	if entity.floating then entity.floating.Value = 0 end
	if entity.targetFloatY then entity.targetFloatY.Value = nil end
end

--- jump the single track to a mark. A second :PlayAnim would stop this track
--- and load another, which is exactly what the one-clip rebuild exists to avoid.
local function seek(track:AnimationTrack?, to:number)
	if track == nil then return end
	track.TimePosition = to
end

local function useFunc(this:myself)
	local cooldownID = "smash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	--- the WHOLE move. Nothing below may call :PlayAnim again.
	local anim = this:PlayAnim(script.Smash, 0, 1, 1)

	fireVFX("hideTool", char)
	--- LEFT arm. The new clip winds up and throws the uppercut with the left,
	--- so the gather has to be on the hand that actually connects.
	fireVFX("smashCharge", char:FindFirstChild("Left Arm"), 1.2)

	--- rowa1 plays this on the root for the whole gather
	local chargeSnd = script["magic attack sound"]:Clone()
	chargeSnd.Parent = humObj.HRootPart
	chargeSnd:Play()
	chargeSnd.TimePosition = 0.1
	game.Debris:AddItem(chargeSnd, 6)

	--- set at the apex, nil until then. bail() has to see it, so it is
	--- declared above bail.
	local release:(()->())? = nil

	--- EVERY exit path owes the arms, the tool and the charge; rowa1 forgot it
	--- on several of its seven branches, which is how players ended up armless.
	local function restore()
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		fireVFX("smashCharge", nil, 0)
		fireVFX("showArms", char)
		game.Debris:AddItem(chargeSnd, 0)
	end

	--- cancelled: kill the track, drop the pin, put the player back together.
	--- A stranded pin drags the victim around forever and throws nothing.
	local function bail()
		if release then
			release()
			release = nil
		end
		if anim then anim:Stop(0.1) end
		restore()
	end

	--- 0.00 -> 0.70. The windup is the ANIMATION's: the punch comes out on the
	--- frame the clip punches on.
	if this:feintWait(MARK.UPPERCUT) then
		bail()
		return
	end
	
	--- rowa1 slowed the WINDUP; this starts at the PUNCH, so you keep your feet
	--- while gathering and pay from the moment you commit.
	humObj.walkSpeed:SetMod(SLOW_KEY, -8)


	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -2), Vector3.new(7, 7, 7))

	--- ONE victim goes up, but a PARRY IS NOT A CONNECT and must not end the
	--- scan -- an unconditional break threw away everyone else in the box.
	--- The parry still ends the move normally: resolveParry stuns the attacker,
	--- so the next feintWait bails. The scan exists so a second victim EATS the
	--- punch, not so you can smash through a parry.
	local caught = nil
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(UCUT, enemy, forward)
		--- !! NO DECAY: a decaying vertical mover fights gravity the whole way
		--- down its own ramp and barely lifts -- with decay this stopped
		--- launching at all. Pulled slightly under rowa1's x0.6 (18 + 24): the
		--- apex only has to be high enough for the pin to hold them.
		attack.knockback = this:knockback(
			forward * LAUNCH_FWD + Vector3.new(0, LAUNCH_UP, 0), 0.25, false, -1)
		this:executeAttack(attack)

		--- parried, dodged or aborted -- not a connect. Someone behind them may
		--- still eat it, so keep scanning.
		if not (attack:isHit() or attack:isBlocked()) then continue end

		--- ~the punch -> slam gap, so the launch carries the whole ride. A BLOCK
		--- does not get this (they kept their feet) but still counts as a catch.
		if attack:isHit() and enemy.TrueStun then
			enemy:TrueStun(1.6)
		end

		caught = enemy
		break
	end

	if caught == nil or caught.HRootPart == nil then
		--- MISS. The whiff is parked at 1.85, not next on the timeline, so seek
		--- straight to it past the freeze frame and the jump prep.
		seek(anim, MARK.MISS_IN)
		restore()
		this:endLag(MARK.MISS_OUT - MARK.MISS_IN)
		--- MUST stop. Past 2.13 the clip runs on into the flash-step and
		--- would play a full slam at nobody.
		if anim then anim:Stop(0.15) end
		return
	end

	--- 0.70 -> 0.80, the hit freeze frame. The track holds itself; this only
	--- stops the VICTIM leaving. atkWait, not feintWait: the punch has landed,
	--- so this is the one uncancellable wait in the move.
	local contact = caught.HRootPart.Position
	local unfreeze = pinTo(caught.HRootPart, function() return contact end,
		FREEZE_HOLD)

	this:atkWait(MARK.FREEZE_END - MARK.UPPERCUT)

	unfreeze()

	--- both of these, before anything tries to hold anyone. See killFloat.
	killFloat(caught)
	killFloat(humObj)

	fireVFX("camShake", hurtbox.Position, 200, 2, 0.1)

	--- !! the pillar LEANS along the launch, it does not stand up straight --
	--- sending a bare position lands it on an identity rotation. The aim is the
	--- throw with its components swapped and the vertical negated, i.e. exactly
	--- perpendicular at any tuning, derived from LAUNCH so the two cannot drift.
	local fxAt  = hurtbox.Position + Vector3.new(0, 6, 0)
	local fxAim = forward * LAUNCH_UP - Vector3.new(0, LAUNCH_FWD, 0)
	fireVFX("smashUppercut", CFrame.lookAt(fxAt, fxAt + fxAim) * FX_ROLL)
	
	--- 0.80 -> 1.18, the first half of the prep: let the launch happen.
	if this:feintWait(APEX - MARK.FREEZE_END) then
		bail()
		return
	end

	--- hold them at the apex while you close. maxTime is the hang plus a margin,
	--- so even a thrown error cannot strand the pin.
	local apex = caught.HRootPart.Position + forward * 4
	release = pinTo(caught.HRootPart, function() return apex end,
		{ maxTime = HOLD + 0.35 })

	--- the hang outlasts UCUT's 0.8s ragdoll, so without this they go limp and
	--- then STAND BACK UP mid-air while pinned. ragdoll() takes a max() against
	--- the live lifetime, so this extends rather than restarts it.
	caught.ragdoll:ragdoll(HOLD, false)

	--- TrueStun, not :Stun -- only TrueStun passes bypassArmour, so under hyper
	--- armour the whole pin was otherwise free. DERIVED from the hold, so it
	--- stays correct across a re-export. Also the only stun a BLOCKER gets.
	--- Guarded: TrueStun is not in the Combatant contract.
	if caught.TrueStun then
		caught:TrueStun(HOLD)
	end

	--- 1.18 -> 1.45, the rest of the prep.
	if this:feintWait(MARK.PREP_END - APEX) then
		bail()
		return
	end

	--- 1.45 -> 2.60: seek over the whiff, which sits in the middle of the clip.
	seek(anim, MARK.TELE_IN)
	fireVFX("phantom", char, char.PrimaryPart and char.PrimaryPart.CFrame or hurtbox.CFrame)
	fireVFX("fstep", char, 0.4)
	--- hauls the CASTER up, client-side, for 0.5s of this 0.68s window -- so
	--- the last stretch is a real fall into the slam. NOT to `apex`: that is
	--- where the victim is, see CASTER_OVER.
	fireVFX("smashDown", humObj.HRootPart,
		apex + CASTER_OVER - forward * CASTER_BACK)

	--- 2.60 -> 3.28, up and back down. The slam lands on the last frame.
	if this:feintWait(MARK.SLAM - MARK.TELE_IN) then
		bail()
		return
	end

	if release then
		release()
		release = nil
	end

	if caught.isActive == true and caught.HRootPart then
		local eroot = caught.HRootPart
		fireVFX("camShake", eroot.Position, 400, 4, 0.2)

		forward = hurtbox.CFrame.LookVector
		local attack = this:makeAtk(SSMASH, caught, forward)
		-- rowa1 lookVec*10 + (0,-60,0), at the x0.6 ratio (README S7)
		attack.knockback = this:knockback(
			forward * 6 + Vector3.new(0, -36, 0), 0.25, false, -1)
		this:executeAttack(attack)

		--- again, and this is the one that matters: both fighters are airborne on
		--- the slam, so the float arms anti-gravity on the frame we drive them down.
		killFloat(caught)
		killFloat(humObj)

		if attack:isHit() then
			--- flat 0.8s: `true` would be wrong here, stopOnGround would end it on
			--- the first frame since they are being driven INTO the ground.
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, Vector3.new(0, -10, 0))
			fireVFX("smashLand", eroot.Position)
			fireVFX("pauseF", char, eroot.Parent)
		end
	end

	restore()
	--- 3.28 -> 3.87, the landing. The clip ends by itself on the last frame.
	this:endLag(MARK.TRACK_END - MARK.SLAM)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
