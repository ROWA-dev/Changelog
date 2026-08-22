--!strict
--[[ HollowPurple - rowa1 Items/Ability/EmptyPurple + the Script parented to
	the part it clones, Effects/Purple/purpledmghandler.
	Notes: README.md/PORT_EmptyPurple.

	Four and a quarter seconds of holding a red orb and a blue one apart with
	your hands empty and your weapon gone, hovering if you cast it airborne
	and untouchable for the last three of them -- then they meet, and a
	purple sphere leaves at 350 studs/s and deletes the lane in front of you.
	The last ability in the port and the only one that ends a fight by
	itself.

	## RENAMED FROM EmptyPurple, ON PURPOSE
	  rowa1's TOOL is called EmptyPurple. Every ASSET it uses is called
	  HollowPurple: ServerStorage/HollowPurple, ClientEffects/
	  HollowPurpleSetup, ClientEffects/HollowNuke. The ledger and PORT_
	  EmptyPurple keep the tool name; PORT_00_INDEX now records the rename so
	  nobody goes looking for a port that is sitting here under another name,
	  the same way rowa1's Axe -> StarkAxe was recorded (README S9).

	## PORT_EmptyPurple SAYS THIS ABILITY HAS NO DAMAGE. IT IS WRONG, AND ITS
	## OWN FIRST SECTION IS WHY.
	  That doc opens by warning that PORT_InverseRed and PORT_FullBlue both
	  concluded "spectacle present, mechanics absent" and were both wrong,
	  because rowa1 keeps half of an ability in a Script parented to the
	  EFFECT PART the aEvent clones -- and then makes the same claim itself,
	  flagged "treat as unverified until someone reads the Script inside
	  whatever Part this aEvent clones".
	  Read now. FOURTH TIME, and the tell is identical: the aEvent requires
	  AttackModule, Knockback, HurtBox and Destruction and calls none of
	  them. Its last act is to clone ServerStorage/Effects/Purple, and that
	  part carries `purpledmghandler`, 105 lines that ARE the ability:

	      CamShake 300 at the muzzle, then 200 every other frame
	      flies at ownerlook * 350 studs/s, sampled ONCE at release
	      a 12-cube swept for bodies, one hit per victim, ever (`alrhit`)
	      dmgID `purple` -- DMGS:996, 180 damage, the second-biggest number
	          in rowa1's whole table, behind only wcrush's 600
	      Destruction:PurpleBreak every other frame
	      corpses go fully TRANSPARENT; survivors get a scream

	  The doc's other candidate, the orphaned `imposterPurple`, is a weaker
	  copy of the same script (10-cube, 250 studs/s, no shake, no vanish) and
	  nothing clones it. ServerStorage/HollowPurple -- a THIRD version, an
	  attract field with a 29-stud saturn orbit -- is likewise unreferenced.
	  The shipped move is the one above. Ignore the other two.

	## WHAT THE SCRIPT-ON-THE-PART BECAME: Class/Projectile, not a Part
	  It is a swept box travelling in a straight line, sampled once at
	  release, deduping victims on the way. That is the class, exactly, and
	  the server holds no Instance for it. rowa1's own numbers all survive
	  (350 studs/s, 12-cube, `alrhit`); what is gone is the per-frame CFrame
	  replication and the substep bug it hid -- at 350 studs/s and 30fps
	  rowa1 stepped 11.6 studs through a 12-stud box, which is a coin flip on
	  the frame that matters.

	  It DOES NOT STOP ON WORLD GEOMETRY (`stopOnWorld = false`). rowa1 never
	  raycast at all: the beam eats the wall and keeps going, which is the
	  entire fantasy and also why the carve below is a lane and not a crater.

	## THE TUNNEL IS CARVED AS THE BEAM PASSES, not once at the end. See
	   carveLane below: Sphere_Fast at the orb's own position, spaced by
	   distance, which is Tools/destruction/craterBeam's shape.

	## FOUR SECONDS IS THE MOVE, and it splits in two
	  rowa1 declares `Attacking.Time = 4.49` and then waits 1.22 + 3.03 =
	  4.25 (README 7g: the declared value is a claim, the waits are the
	  truth). The two halves are not the same thing:
	      1.22s  VULNERABLE. rowa1 polls stun/block/offence-stun every frame
	             and bails. That is `feintWait`.
	      3.03s  COMMITTED. rowa1 parents an `iframes` BoolValue onto the
	             Humanoid and does a bare `task.wait(3.03)` with no checks at
	             all. Nothing can stop it and nothing can touch you.
	  So the counterplay is the first second: punish the wind-up or wear it.
	  Port both halves or the ability is a different move. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "HollowPurple",
	--[[ rowa1 `manause` 200 against rowa2's 100 pool, so the literal is
		unpayable (README Q1 is still open). Armor set the only precedent for
		scaling one down -- 120 -> 40, a third -- and 200 at a third is 66.
		60 rather than 66 so it sits on the same grid as everything else, and
		it is still by far the most expensive thing in the game: mana only
		comes from landing weapon hits, so this is "you have been winning the
		fight for a while", which is the right price for a delete button. ]]
	manaUse = 60,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local fireVFX   = require(game.ServerStorage.ROWA.Modules.fireVFX)
local aerialAim = require(game.ServerStorage.ROWA.Modules.aerialAim)

--[[ rowa1 `purple` (DMGS:996): Heavy, magic, 180 damage with the comment
	"nerfed af", truestun 1, stun 2, posMult 4, onHit ragdtillground.

	DAMAGE 180 -> 90. THIS IS THE NUMBER TO ARGUE ABOUT, so here is the
	arithmetic rather than a feeling. The four shipped ports all landed at
	0.60-0.67 of rowa1 (reverseRed 40->24, blue 6.5->4, cero 60->38, strP
	30->20); 0.6 of 180 is 108, and MaxHealth is Roblox's default 100, so the
	ratio says "unconditional kill". 90 is deliberately just under it: it
	deletes anyone who has traded a single hit, and leaves a target who is
	genuinely untouched alive on 10 with a 1.6s stun to be finished by hand.
	Whether the ultimate should one-shot from full is a balance call, not a
	port detail -- if the answer is yes, this is the line to change.

	STUN 2 -> 1.6. rowa1's two seconds is longer than anything in rowa2:
	the longest shipped ability stun is 1.5 and a GUARD BREAK -- the worst
	thing that can happen to you -- is 1.6 true / 1.9 (DOC_COMBAT 3). Landing
	the biggest hit in the game should not be strictly better than breaking
	someone's guard, so it matches it instead.

	rowa1 collapses its truestun/stun pair into rowa2's single `stun`
	(README S4.2). NOTE that InverseRed and Freeze both still carry a
	`truestun` key: rowa2's dmgType has no such field, so those are dead
	keys, not a second knob. Do not copy them.

	parryH -10: `purple` is in rowa1's unParryableIds. Same trick FullBlue
	uses for `blue` -- there is no set to join, it is a number that puts the
	window out of reach.

	dodgeH -10: and it is in `bypassiframes`, alongside only wcrush. THIS IS
	THE ONE ROWA1 FLAG THAT REALLY MATTERS HERE. rowa2 answers an attack
	parry -> dodge -> block -> hit, and a 0.3s dash i-frame window would
	otherwise beat a four-second, unparryable, screen-filling beam for free.
	It cannot be dodged, it cannot be parried; it can be BLOCKED, and posMult
	4 x 90 damage is 360 posture against a pool of 80, so blocking it is a
	guard break and then the hit lands anyway. That is rowa1's intent stated
	in rowa2's vocabulary.

	posMult stays 4: unlike Cero (6 -> 4) it was never tuned against the
	100-posture pool -- it already breaks any guard several times over. ]]
local PURPLE = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 90,
	stun     = 1.6,
	posMult  = 4,
	parryH   = -10,
	dodgeH   = -10,
})

--[[ THE TUNNEL. One Sphere_Fast per tick at the orb's own centre, which is
	Tools/destruction/craterBeam's loop with the projectile handing it the
	positions instead of a mouse ray. At 350 studs/s that is a sphere every
	~6 studs against a radius of 7, so they overlap into one clean bore
	rather than a string of craters.

	NOT one Cylinder in onExpire (PLAN_PROJECTILE 3.8's letter, and what an
	earlier pass here did): the hole has to open as the beam passes, not a
	second later, and a straight lane stops being true the moment
	`gravWells.apply` bends the shot. 3.8 is a rule about the CLASS -- the
	scheduler still makes no Destruction call; this is the ability's own
	loop, the same way FullBlue drives its field.

	Sphere_Fast, NOT Sphere: it skips `visualizeDestroyed` entirely, so ~50
	carves cost no dbri payload and draw no rubble. That is also the right
	look -- purple removes a wall, it does not shatter one, the same call
	Cero makes with `noDebris`.

	r7 is rowa1's PurpleBreak cutter (14^3) inscribed, README S10.4. minSz is
	craterBeam's `1 + r^0.9/2`, coarser than Sphere_Fast's own single-call
	default (`1 + r^0.7/4`) on purpose: fineness is what makes one carve
	expensive and this runs fifty times. ]]
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local CARVE_R   = 12
--- craterBeam's, verbatim
local CARVE_MIN = 2 + (CARVE_R ^ 0.9) / 2
--- pinTo's rule: a loop that follows something else needs its own ceiling,
--- or a projectile that never reports dead carves the map forever. The
--- projectile's own lifetime is 1.5.
local CARVE_CEILING = 4

local function carveLane(p: any)
	local endt = os.clock() + CARVE_CEILING
	while p.dead ~= true and os.clock() < endt do
		--- `plr` is unused by processDestData; every ability passes nil
		Destruction.Sphere_Fast(nil, p.pos, CARVE_R, CARVE_MIN)
		task.wait()
	end
end

--- one Emit is one victim: rowa1 shares `alrhit` across the whole flight.
local function onHit(proj: any, attack: any)
	if not attack:isHit() then return end
	local enemy = attack.enemyEntity
	if enemy == nil then return end

	--- rowa1's row carries ragdtillground (60s cap, released on landing)
	if enemy.ragdoll then
		enemy.ragdoll:ragdoll(60, true, attack.atkDir * 10)
	end

	local hum = enemy.Hum
	if hum and hum.Health <= 0 then
		--[[ THE CORPSE VANISHES. rowa1 walks the dead character and sets
			Transparency 1 on every BasePart, MeshPart and Decal -- you are
			not killed by this, you are ERASED, and it is the single most
			recognisable thing about the move.

			FEATURE-DETECTED, like FullBlue's plrObj branch: setTransparency
			lives on HumObj and not in the Combatant contract, so a boss
			would throw inside the pcall that wraps useFunc... except this
			runs on the projectile's own pcall, which would swallow it
			instead and leave the rest of the flight intact. Guard anyway;
			the failure would be invisible either way.

			rowa2's version records the originals and restores on
			setTransparency(0), so respawn is not left holding an invisible
			character the way rowa1's one-way write was. ]]
		if enemy.setTransparency then
			enemy:setTransparency(1)
		end
		return
	end

	--[[ ...and if you SURVIVE it, you scream. rowa1 plays this once per
		damage tick on the first living victim (`alrplayed`); once per cast
		is the same thing here, since a victim can only be hit once.
		`proj` is a plain table and this field is ours -- the config is
		shared and frozen, so per-cast state cannot live there. ]]
	if proj._screamed then return end
	proj._screamed = true

	local root = enemy.HRootPart
	local src = script:FindFirstChild("Kendrick Scream")
	if root == nil or src == nil then return end
	local snd = src:Clone() :: Sound
	snd.Parent = root
	snd:Play()
	game.Debris:AddItem(snd, 6)
end

local PURPLE_CFG = table.freeze({
	--- rowa1: `purple.CFrame = CFrame.new(pos + ownerlook * 350 * dt)`
	speed = 350,
	--[[ rowa1 caps neither: a 30 SECOND lifetime at 350 studs/s is a ten
		thousand stud shot that is still live half a minute later. Capped the
		way RPG's 30s and InverseRed's 10s were. 300 studs is well past
		anything you can see coming, and lifetime is the belt to that
		braces. ]]
	maxDistance = 300,
	lifetime    = 1.5,
	--- rowa1 RegModule.Box(purple.CFrame, (12,12,12)). A projectile queries
	--- in world space with no charSize scale and no range fudge, so the
	--- literal ports unchanged (S7.7 is about HurtBox-relative boxes).
	size   = Vector3.new(12, 12, 12),
	dmgTbl = PURPLE,
	--[[ rowa1 dedupes forever (`alrhit`) and caps each tick at 8 bodies.
		`seen` is the dedupe, so this is only the cap -- and it is the whole
		reason the beam is not stopped by the first person it meets. ]]
	pierce = 8,
	--- IT GOES THROUGH THE WALL. rowa1 never raycasts; see the header.
	stopOnWorld = false,
	fxId = "purpleOrb",
	--[[ rowa1 Knockback(hum, enemy, ownerlook*60 + (0,8,0), true) -- the 4th
		argument is `noProc`, NOT root-relative. x0.6 to rowa2 force units
		(README S7.9) is 36. The +4.8 lift has no home in the config, which
		expresses one force along the heading; the ragdoll above carries the
		tumble that lift was there for. ]]
	knockbackForce = 36,
	knockbackTime  = 0.25,
	onHit = onHit,
})

--[[ rowa1's two halves, measured off the aEvent's own waits.
	1.22 + 3.03 = 4.25, and the client cinematic ("imaginarypurple", now
	VFXQuiver/hollowPurpleCharge) runs 4.27 by its own internal beats. They
	are meant to land together; keep them that way if you retune either. ]]
local CHARGE_OPEN   = 1.22    -- cancellable
local CHARGE_LOCKED = 3.03    -- committed + untouchable
local CHARGE_TOTAL  = CHARGE_OPEN + CHARGE_LOCKED

--- rowa1 spawns the orb at root + look * 10
local SPAWN_AHEAD = 10

local CD_FULL        = 60     -- rowa1's Tool attribute, unchanged
--[[ rowa1 stamps `cd = tick()` the moment you PRESS it, so being clipped out
	of the wind-up cost the full minute. rowa2's rule is the opposite -- pay
	at commit, a feint costs nothing (README S6.1) -- and neither extreme is
	right for a four second channel: free means you can hold the cinematic up
	as a taunt forever, full means one stray hit deletes your ultimate.
	PowerStrike's two-tier shape says it in the language rowa2 already has: a
	short cd created up front, overwritten with the real one at commit.
	`Cooldown.Trigger` never SHORTENS an existing expiry (`last = max(last,
	now + cd)`) and dontOverwrite reuses the stored Value, so this stays 12
	on the bail path and 60 on the cast path, every time, forever. ]]
local CD_INTERRUPTED = 12

local SLOW_KEY = "hollowPurple"

local function useFunc(this:myself)
	local cooldownID = "hollowPurple"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--- see CD_INTERRUPTED. Also the double-fire guard for UseAbility's 0.2s
	--- retry loop, which canTriggerCD alone cannot close over a 4s cast.
	this:triggerCD(cooldownID, CD_INTERRUPTED, true)

	--[[ !! NOT A FULL ROOT, for Cero's reason. rowa1 writes WalkSpeed 0
		(`_G.inputProxy(plr, 1, 0)`, restored to 15 on every exit) and a
		rooted R6 character CANNOT TURN -- AutoRotate only yaws you while you
		are moving. This move samples its direction at RELEASE, four seconds
		later, so a real root would mean firing wherever you happened to be
		facing when you pressed the button. Heavy slow instead. ]]
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	--[[ AERIAL AIM. rowa1's `arialControll`, and this is one of the two
		abilities Modules/aerialAim was actually built for -- four seconds of
		freefall would otherwise drop you out of your own aim before the orb
		exists. No-ops on the ground and on NPCs. rowa1 leaked the connection
		on three of its four exits; the destructor and the ceiling are why
		this one cannot. ]]
	local releaseAir = aerialAim(humObj, CHARGE_TOTAL + 1)

	fireVFX("hideTool", char)
	--[[ the entire cinematic. Pattern B: the client owns every instance of it.
		The cinematic's last beat is the screen flash and it is supposed to
		land ON the release, so it gets the whole span. ]]
	fireVFX("hollowPurpleCharge", char, CHARGE_TOTAL)

	local function bail()
		if anim then anim:Stop(0.2) end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		releaseAir()
		--- duration <= 0 is the quiver's cancel convention (icelasers,
		--- bground, ststep). Without it the orbs finish merging in the hands
		--- of someone who was interrupted a second in.
		fireVFX("hollowPurpleCharge", char, 0)
		--- hideTool has no `showTool`: the restore is per-CHARACTER and every
		--- exit path owes it one (VFXQuiver/hideTool's header).
		fireVFX("showArms", char)
	end

	--- THE PUNISH WINDOW. rowa1 polls stun/block/offence-stun for 1.22s.
	if this:feintWait(CHARGE_OPEN) then
		bail()
		return
	end

	this:useMana()
	--- stage 2: overwrite the 12 with the real minute. No dontOverwrite --
	--- that is the mechanism (PowerStrike).
	this:triggerCD(cooldownID, CD_FULL)

	--[[ NOW UNTOUCHABLE. rowa1 parents an `iframes` BoolValue onto the
		Humanoid for exactly this stretch; rowa2's equivalent is
		dodgeThreshold, which HumObj:isDodge reads as `tick() <= threshold`,
		so pushing it forward IS an i-frame window (Clap does the same for
		0.2s). README S10.6 called this ability blocked on "does rowa2 grow a
		true invulnerability window" -- it already had one, it is just spelt
		as a dodge, and dodge is answered before block and before hit.

		+0.2 of margin so the last frame of the wind-up is covered too. It
		expires on its own; there is nothing to unwind on the error path.

		IT IS NOT ABSOLUTE, and that is correct: an attack carrying dodgeH
		beats it, which is exactly how THIS ability's own dmgTbl beats
		someone else's dash. Two casters holding purple do not both win. ]]
	humObj.dodgeThreshold = tick() + CHARGE_LOCKED + 0.2

	--[[ A BARE WAIT, not atkWait, and the only one in the file. The client
		cinematic is a FIXED 4.27s timeline of hardcoded beats and the orb has
		to leave as the two halves meet; atkRate is an AdditiveValue that a
		card or a buff can move, and scaling this wait would slide the release
		out from under an animation that cannot be scaled with it. Barrage's
		fixed-rhythm exemption (README S7.6), for the same reason.

		Nothing is polled: rowa1 checks nothing here either, and there is
		nothing left to check -- you cannot be hit, and feintWait already
		cleared isFeinted on the way in (FullBlue's stale-flag trap). ]]
	task.wait(CHARGE_LOCKED)

	--- the caster survived their own wind-up; hand everything back BEFORE
	--- the shot, so an error in the launch cannot strand any of it
	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	fireVFX("showArms", char)
	if anim then anim:Stop(0.2) end

	--[[ rowa1 plays this on the root as the orb leaves. GUARDED, unlike the
		charge sounds in Cero and Smash: everything below this line is the
		payload the player just paid a minute and 60 mana for, and useFunc
		runs inside a pcall that would swallow a missing-asset error and
		abandon the shot silently. Same reasoning as Modules/fireVFX. ]]
	local outSrc = script:FindFirstChild("PurpleOut")
	if outSrc then
		local outSnd = outSrc:Clone() :: Sound
		outSnd.Parent = humObj.HRootPart
		outSnd:Play()
		game.Debris:AddItem(outSnd, 6)
	end

	--[[ direction sampled HERE, once, as rowa1 does (`ownerlook` is read at
		spawn and never re-read -- the beam does not track). ]]
	local orb = this:projectile(PURPLE_CFG, hurtbox.CFrame * CFrame.new(0, 0, -SPAWN_AHEAD))

	--[[ the tunnel follows it. SPAWNED, not awaited: the beam outlives this
		call by design (PLAN_PROJECTILE 3.4) and endLag below must not wait on
		a second of carving. ]]
	if orb then task.spawn(carveLane, orb) end

	--[[ rowa1 releases the hover on the same line it spawns the orb, so the
		caster drops as it leaves. After, not before, for InverseRed's reason:
		the aim above is read off the root and the client takes a frame to
		drop the gyro. ]]
	releaseAir()

	--[[ no camShake fired from here. rowa1 shakes at the muzzle and then
		again every other frame from the flying part -- that is ~29 broadcasts
		of a position the client is already drawing for itself, so the shake
		lives in the fx module where the orb is. See VFXQuiver/purpleOrb. ]]

	this:endLag(0.5)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
