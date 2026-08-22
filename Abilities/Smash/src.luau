--!strict
--[[ Smash - rowa1 Items/Ability/Smash. Notes: README.md/PORT_Smash.

	Uppercut someone into the air, flash-step up after them, and drive them
	back into the ground.

	ONE ANIMATION, FOUR SEGMENTS.
	This used to be two clips (Uppercut, then Smash). It is now a single
	authored track -- 91080422195416, living on `script.Smash` -- that
	carries the uppercut, the WHIFF variant and the slam on one timeline,
	with the whiff parked in the MIDDLE of it. So the move never swaps clips
	any more, it SEEKS:

	    0.00 -> 0.70   windup, the LEFT arm gathers. UPPERCUT LANDS AT 0.70
	    0.70 -> 0.80   hit freeze frame. The clip's keys at 0.70 and 0.80 are
	                   identical, so it holds itself; the code only holds the
	                   VICTIM through it, see THE FREEZE FRAME below
	    0.80 -> 1.45   prep the jump, while they hang where the punch put them
	    ~~~~ MISS ONLY: seek 0.70 -> 1.85, so the whiff REPLACES the freeze
	    1.85 -> 2.13   whiff recovery, then the move is over ~~~~
	    2.60 -> 3.28   flash-step up and drive down.  SLAM LANDS AT 3.28
	    3.28 -> 3.87   land and recover, end of track

	    1.45 -> 2.60 is SEEKED OVER on the hit path (it contains the whiff).

	Two rules that follow from that, and are the only way to keep this
	readable:
	  * every beat is written as the GAP BETWEEN TWO MARKS, never a raw
	    number, so a re-export is an edit to MARK and nothing else.
	  * marks are TRACK seconds and the waits take the same unit. PlayAnim
	    multiplies speed by timeScale/atkRate and scaledTime divides by
	    exactly the same factor, so one second of wait is always one second
	    of track, at any atkRate.
	The old `script.Uppercut` Animation is DELETED, not orphaned. Divide has
	its own separate copy of that clip; nothing there moved.

	THE FREEZE FRAME IS THE ANIMATION'S, NOT THE CODE'S. 0.70 and 0.80 are
	the same pose, so the caster holds still on his own for that beat --
	nobody calls AdjustSpeed(0) here and nobody should. A halted track is a
	thing that can be left halted; the clip cannot.

	The only thing code adds to the frame is the VICTIM, for 0.1s:
	  * held at the point of contact, the way Divide holds one. That part is
	    not free -- it has to OVERPOWER the launch it just ate, see
	    FREEZE_HOLD.
	  * their own tracks are left alone. UCUT's onHit has already ragdolled
	    them, and a pose freeze no-ops on a ragdoll (VFXQuiver/iceCrystals
	    says so where it does that same trick for Freeze).

	THE AIR-COMBO FLOAT IS TURNED OFF FOR THE WHOLE MOVE. See killFloat.

	KEPT SIMPLE, same call as Divide. rowa1 holds the victim mid-air with a
	BodyPosition; that is Modules/pinTo here, not the `floating` air-combo
	system the port doc proposed. Divide and Smash therefore make the SAME
	choice, which was the doc's actual worry -- if they diverged the game
	would have two air-combo models.

	rowa1's file is 359 lines. Most of that is the four-value guard repeated
	seven times and a commented-out block of TweenService the author had
	already decided belonged on the client. ]]
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
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	--[[ rowa1's "ucut" row carries its own OnHitFunc: a 0.8s FLAT ragdoll,
		no ground check, so the victim flops through the launch instead of
		riding it upright. Flat rather than stopOnGround on purpose -- a
		ground check releases them the instant they land, which reads as
		standing up mid-air.
		SAME rowa1 row as Divide's; keep the two in step. The new clip hangs
		them for longer than 0.8s, so THIS ROW IS NOT EXTENDED -- the hang is
		topped up at the pin instead, see HOLD below. ]]
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
	end,
}

--[[ rowa1 "ssmash": Heavy, magic, 60 dmg -- the highest single hit in the
	whole table outside Cero, off ONE confirmed uppercut. Cut hard. ]]
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

--[[ The apex pin captures a FIXED world point, so it has to be taken when
	they are actually at the top: 0.38s of rise, which is the delay the
	two-clip version was tuned on (it passed 0.46 through the old windup
	lead, which waited 0.38). Grab them earlier and they are still climbing,
	so they hang low.

	MEASURED FROM FREEZE_END, NOT FROM THE PUNCH. The freeze frame holds
	them still, so the launch does not really begin until the frame lets go
	-- the whole 0.38 has to sit after it. It lands at 1.18, comfortably
	inside the prep window, which is why that window is split in two. ]]
local APEX = MARK.FREEZE_END + 0.38

--- how long the victim hangs pinned: the tail of the prep, plus the whole
--- flash-step. Derived, never typed as its own number.
local HOLD = (MARK.PREP_END - APEX) + (MARK.SLAM - MARK.TELE_IN)

--[[ THE FREEZE-FRAME HOLD HAS TO WIN AGAINST THE LAUNCH IT JUST ATE.
	Knockback is a LinearVelocity, not an impulse: it is already live on the
	victim's root (on their own CLIENT, if they own it) and it is still
	driving when this pin appears. pinTo's default arm is MaxForce
	mass*4000, which LOSES to the mover's per-axis mass*10000 -- the victim
	would shudder upward instead of stopping. Passing `axes` switches pinTo
	to MaxAxesForce = axes*1e7, which does not.

	ALL THREE AXES, unlike Divide's (1,0,1) drag. Divide wants gravity and
	the launch left alone because it is pulling someone toward you; this is
	the opposite -- for 0.1s nothing may move at all.

	Costs ~10 studs of rise, and costs nothing else: a velocity constraint
	resumes at full speed the instant the hold is destroyed, so the victim
	still leaves with the exit speed they would have had. That is precisely
	why APEX is measured from the end of the freeze. ]]
local FREEZE_HOLD = table.freeze({
	axes = Vector3.one,
	responsiveness = 200,
	maxTime = 0.35,
})

--[[ WHERE THE CASTER IS HAULED TO for the flash-step, relative to where the
	victim is pinned. It used to be the victim's exact point, so the
	flash-step ended INSIDE them and you spent the slam feeling two rigs
	resolve against each other.
	Up, and slightly short of them: you are smashing DOWN, so the shot wants
	to look down at them, and smashDown's own hold expires 0.18s before the
	slam -- that last stretch is a real fall, which eats most of the 7. ]]
local CASTER_OVER = Vector3.new(0, 7, 0)
local CASTER_BACK = 2

--[[ THE AIR-COMBO FLOAT AND THIS MOVE CANNOT BOTH OWN THE VICTIM'S HEIGHT.
	DOC_COMBAT 4.11: a landed hit with both fighters airborne sets
	`floating` + `targetFloatY` on BOTH, and the victim's own CharController
	then applies an anti-gravity impulse every frame to drag them level with
	the target. Against a server-side AlignPosition that is a fight the
	player sees as rubber-banding -- the client shoves, the pin pulls back.
	It also calls unragdoll() the moment it switches on (HumObj
	"floating_unragdoll"), which stands the victim up in mid-air.

	Smash owns the victim's height from the punch to the slam, so the float
	goes off at every point that could have armed it. It is armed from
	`blockedOrHit`, which runs off onAttack -- i.e. AFTER dmgTbl.onHit -- so
	this CANNOT live in a dmgTbl the way WepBase/dmgConfig/dslam tries to; it
	has to be here, after executeAttack returns.
	GUARDED: `floating` is not in the Combatant contract, SimpleEntity has
	no such thing, and the HumObj block that sets it checks for it too. ]]
local function killFloat(entity:any)
	if entity == nil then return end
	if entity.floating then entity.floating.Value = 0 end
	if entity.targetFloatY then entity.targetFloatY.Value = nil end
end

--[[ Jump the single track to a mark. Every branch of this move is a seek
	rather than a second :PlayAnim -- PlayAnim would stop this track and load
	another one, which is what the old two-clip version did and is exactly
	what the new clip exists to avoid. ]]
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

	--[[ EVERY EXIT PATH RESTORES THE ARMS AND THE TOOL. rowa1 forgot it on
		several of its seven bail branches, which is how players ended up
		armless. The miss path used to forget the CHARGE specifically -- it
		showed the arms again but left the shard gather welded to one of
		them until the next cast reused the slot. ]]
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

	--[[ 0.00 -> 0.70. The windup is the ANIMATION's now: the punch comes out
		on the frame the clip punches on. Both of rowa1's numbers are dead --
		it DECLARED `Attacking.Time = 0.6` and then actually waited `tick()+1`
		-- and the port's 1.0 went with them. ]]
	if this:feintWait(MARK.UPPERCUT) then
		bail()
		return
	end
	
	--[[ rowa1 slowed you for the WINDUP (WalkSpeed 8). This starts it at the
		PUNCH instead: you keep your feet while you gather and pay for it from
		the moment you commit. restore() takes it off on every exit. ]]
	humObj.walkSpeed:SetMod(SLOW_KEY, -8)


	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -2), Vector3.new(7, 7, 7))

	--[[ ONE VICTIM GOES UP -- but A PARRY IS NOT A CONNECT, and it must not
		end the scan either.

		This loop used to `break` unconditionally on the first entry of a
		list that `pairs` orders arbitrarily, so one parry (or dodge, or a
		card abort) threw away everyone else standing in the same box -- and
		which of the two it even tried was luck. Now it keeps looking until
		something actually lands.

		Everything the launch owns -- `caught`, the TrueStun, the pin, the
		slam -- hangs off that connect. A parrier gets the parry and nothing
		else.

		THE PARRY STILL ENDS THE MOVE IN THE NORMAL CASE, and deliberately so:
		resolveParry stuns the ATTACKER (Light -> 0.45s, bypassing armour), so
		even when somebody behind them connects, the next feintWait sees
		inStun and bails. That is the resolver's rule about being parried and
		this move does not get to opt out of it -- the scan exists so the
		second victim EATS THE PUNCH, not so you can smash through a parry. ]]
	local caught = nil
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(UCUT, enemy, forward)
		--[[ rowa1 lookVec*30 + (0,40,0) with `true, 3` -- the 3 meant "no
			knockback damage". rowa2's KnockbackClass builds its own wall
			impact, so the way to opt out is simply a gentler vector rather
			than a magic third argument. x0.6 (README S7). ]]
		--[[ NO DECAY, like rowa1. A decaying vertical mover fights 196
			studs/s^2 the whole way down its own ramp, so it barely lifts --
			an earlier pass swapped to decay and the uppercut stopped
			launching at all.
			rowa1 is lookVec*30 + (0,40,0), which converts to 18 + 24 at the
			x0.6 ratio. Pulled a little under that: the apex only has to be
			high enough for the pin to hold them there. ]]
		attack.knockback = this:knockback(forward * 15 + Vector3.new(0, 21, 0), 0.25, false, -1)
		this:executeAttack(attack)

		--- parried, dodged or aborted. Not a connect: no launch, no stun, no
		--- grab. Somebody behind them may still eat it, so keep scanning.
		if not (attack:isHit() or attack:isBlocked()) then continue end

		--[[ 1.4 is almost exactly the punch -> slam gap (1.43), so the launch
			now carries the whole ride on its own and the pin's TrueStun below
			just re-stamps it. A BLOCK does not get this one -- they held it,
			they keep their feet -- but it still counts as a catch. ]]
		if attack:isHit() and enemy.TrueStun then
			enemy:TrueStun(1.6)
		end

		caught = enemy
		break
	end

	if caught == nil or caught.HRootPart == nil then
		--[[ MISS. The whiff recovery is NOT the next thing on the timeline,
			it is parked at 1.85, so seek straight to it from the punch --
			skipping the freeze frame, which only exists because something
			got hit, and the jump prep, which has nothing to jump after. ]]
		seek(anim, MARK.MISS_IN)
		restore()
		this:endLag(MARK.MISS_OUT - MARK.MISS_IN)
		--- MUST stop. Past 2.13 the clip runs on into the flash-step and
		--- would play a full slam at nobody.
		if anim then anim:Stop(0.15) end
		return
	end

	--[[ 0.70 -> 0.80, THE HIT FREEZE FRAME. The track just plays: those two
		keys are the same pose. All this does is stop the victim from leaving
		during it -- see the header, and FREEZE_HOLD for why the hold has to
		be the heavy kind.
		atkWait, not feintWait: the punch has landed, there is nothing left to
		feint out of. That makes it the one uncancellable wait in the move, so
		the hold is released on the next line and bounded by maxTime regardless. ]]
	local contact = caught.HRootPart.Position
	local unfreeze = pinTo(caught.HRootPart, function() return contact end,
		FREEZE_HOLD)

	this:atkWait(MARK.FREEZE_END - MARK.UPPERCUT)

	unfreeze()

	--- both of these, before anything tries to hold anyone. See killFloat.
	killFloat(caught)
	killFloat(humObj)

	fireVFX("camShake", hurtbox.Position, 200, 2, 0.1)
	fireVFX("smashUppercut", hurtbox.Position + Vector3.new(0, 6, 0))
	
	--- 0.80 -> 1.18, the first half of the prep: let the launch happen.
	if this:feintWait(APEX - MARK.FREEZE_END) then
		bail()
		return
	end

	--[[ hold them at the apex while you close. rowa1 used a BodyPosition at
		`smashPos + lookVec*4`; the pin is the same idea with a guaranteed
		destructor. maxTime is the hang plus a margin, so even a thrown error
		cannot strand it. ]]
	local apex = caught.HRootPart.Position + forward * 4
	release = pinTo(caught.HRootPart, function() return apex end,
		{ maxTime = HOLD + 0.35 })

	--[[ THE HANG IS NOW LONGER THAN THE LAUNCH RAGDOLL. UCUT ragdolls 0.8s
		flat from the punch and the new clip keeps them up there until
		~1.43s after it, so without this they go limp, then STAND BACK UP
		mid-air while pinned -- the exact symptom Divide's header warns
		about. ragdoll() takes a max() against the live lifetime, so this
		EXTENDS the existing one rather than restarting it, and stays flat
		(no ground check) because they are still in the air. ]]
	caught.ragdoll:ragdoll(HOLD, false)

	--[[ TRUE stun for the pin, same call as ToshiCounter. THIS IS THE ONE
		GRAB THAT HAD A REAL GAP: UCUT's stun is 1.0 and the punch lands
		before the pin even starts, so the tail of the hold was already
		unstunned even without armour -- they could act while frozen at the
		apex. Under hyper armour the whole pin was free, since :Stun refuses
		to write and only :TrueStun passes bypassArmour.
		The launch's own 1.4 now covers almost all of it, so this is mostly a
		re-stamp -- but it is the one that is DERIVED from the hold, so it
		stays correct if the clip is re-exported and 1.4 does not.
		Also the only stun a BLOCKER gets: they were caught without being hit.
		GUARDED: TrueStun is not in the Combatant contract (SimpleEntity
		has :Stun only). ]]
	if caught.TrueStun then
		caught:TrueStun(HOLD)
	end

	--- 1.18 -> 1.45, the rest of the prep.
	if this:feintWait(MARK.PREP_END - APEX) then
		bail()
		return
	end

	--[[ 1.45 -> 2.60: THE SEEK OVER THE WHIFF. 1.85-2.13 is the miss variant
		and it sits in the middle of the clip, so the hit path jumps it. ]]
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

		--[[ AGAIN, and this is the one that actually mattered: both fighters
			are airborne on the slam, which is exactly when `blockedOrHit` arms
			the float -- so the victim's client starts applying ANTI-GRAVITY on
			the same frame the slam is trying to drive them into the floor. ]]
		killFloat(caught)
		killFloat(humObj)

		if attack:isHit() then
			--[[ rowa1's onHit is ragdollWait: 0.8s FLAT, not a long cap.
				`true` here would be wrong -- they are being driven INTO the
				ground, so stopOnGround would end it on the first frame. ]]
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
