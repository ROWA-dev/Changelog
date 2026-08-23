--!strict
--- HollowPurple - 4.25s charge (1.22 cancellable + 3.03 committed and
--- untouchable), then a 350 studs/s beam that carves the lane and does not
--- stop on world geometry. rowa1 EmptyPurple, renamed after its own assets.
--- Port notes: README.md/PORT_EmptyPurple (which wrongly calls it damageless).
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "HollowPurple",
	--- rowa1's 200 is unpayable against a 100 pool; scaled to a third like Armor's 120->40.
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

--- rowa1 `purple`: 180 dmg / stun 2. 90 sits deliberately just under a one-shot
--- from full; 1.6 stun matches a guard break rather than beating it.
--- parryH/dodgeH -10 = rowa1's unParryableIds + bypassiframes: blockable only,
--- and posMult 4 means blocking it is a guard break and the hit lands anyway.
local PURPLE = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 90,
	stun     = 1.6,
	posMult  = 4,
	parryH   = -10,
	dodgeH   = -10,
})

--- THE TUNNEL: one Sphere_Fast per tick at the orb's own centre (craterBeam's
--- loop), NOT one Cylinder on expire -- the hole opens as the beam passes, and
--- the lane stops being straight the moment gravWells bends the shot.
--- Sphere_Fast skips visualizeDestroyed, so ~50 carves cost no dbri payload.
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local CARVE_R   = 12
--- craterBeam's, verbatim
local CARVE_MIN = 2 + (CARVE_R ^ 0.9) / 2
--- own ceiling (pinTo's rule): a projectile that never reports dead would carve forever.
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
		--- THE CORPSE VANISHES -- the most recognisable thing about the move.
		--- Feature-detected: setTransparency is HumObj's, not in the Combatant contract.
		if enemy.setTransparency then
			enemy:setTransparency(1)
		end
		return
	end

	--- ...and survivors scream, once per cast. The field lives on `proj` because
	--- the config is shared and frozen and cannot hold per-cast state.
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
	--- rowa1 caps neither: 30s at 350 studs/s is a 10k-stud shot still live half a minute later.
	maxDistance = 300,
	lifetime    = 1.5,
	--- rowa1's literal ports unchanged: projectiles query world space, no charSize scale.
	size   = Vector3.new(12, 12, 12),
	dmgTbl = PURPLE,
	--- `seen` is the dedupe, so this is only the cap -- and why the beam is not
	--- stopped by the first body it meets.
	pierce = 8,
	--- IT GOES THROUGH THE WALL. rowa1 never raycasts; see the header.
	stopOnWorld = false,
	fxId = "purpleOrb",
	--- rowa1 look*60 + lift, x0.6 to rowa2 units (S7.9); the ragdoll carries the tumble.
	knockbackForce = 36,
	knockbackTime  = 0.25,
	onHit = onHit,
})

--- rowa1's own waits. The client cinematic runs 4.27 by its own internal
--- beats and is meant to land with these; retune both or neither.
local CHARGE_OPEN   = 1.22    -- cancellable
local CHARGE_LOCKED = 3.03    -- committed + untouchable
local CHARGE_TOTAL  = CHARGE_OPEN + CHARGE_LOCKED

--- rowa1 spawns the orb at root + look * 10
local SPAWN_AHEAD = 10

local CD_FULL        = 60     -- rowa1's Tool attribute, unchanged
--- two-tier like PowerStrike: 12 up front, overwritten with 60 at commit, so a
--- clipped wind-up is not a free taunt nor a deleted ultimate. Trigger never shortens.
local CD_INTERRUPTED = 12

local SLOW_KEY = "hollowPurple"

local function useFunc(this:myself)
	local cooldownID = "hollowPurple"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--- see CD_INTERRUPTED; also the double-fire guard for UseAbility's 0.2s retry loop.
	this:triggerCD(cooldownID, CD_INTERRUPTED, true)

	--- !! NOT a full root (Cero's reason): a rooted R6 cannot turn, and this
	--- samples its direction at RELEASE four seconds later.
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	--- rowa1's arialControll: 4s of freefall would drop you out of your own aim
	--- before the orb exists. No-ops grounded and on NPCs.
	local releaseAir = aerialAim(humObj, CHARGE_TOTAL + 1)

	fireVFX("hideTool", char)
	--- the whole cinematic, Pattern B; its last beat is the flash and must land ON the release.
	fireVFX("hollowPurpleCharge", char, CHARGE_TOTAL)

	local function bail()
		if anim then anim:Stop(0.2) end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		releaseAir()
		--- duration <= 0 is the quiver's cancel convention (icelasers, bground, ststep).
		fireVFX("hollowPurpleCharge", char, 0)
		--- hideTool has no `showTool`; every exit path owes the restore.
		fireVFX("showArms", char)
	end

	--- THE PUNISH WINDOW. rowa1 polls stun/block/offence-stun for 1.22s.
	if this:feintWait(CHARGE_OPEN) then
		bail()
		return
	end

	this:useMana()
	--- stage 2: overwrite the 12 with the real minute. No dontOverwrite -- that is the mechanism.
	this:triggerCD(cooldownID, CD_FULL)

	--- NOW UNTOUCHABLE: rowa1's `iframes` BoolValue, spelt as dodgeThreshold
	--- (dodge is answered before block and hit). Expires on its own, nothing to
	--- unwind. Not absolute -- an attack carrying dodgeH still beats it.
	humObj.dodgeThreshold = tick() + CHARGE_LOCKED + 0.2

	--- !! bare wait, not atkWait: the client cinematic is a fixed timeline and
	--- atkRate would slide the release out from under it (S7.6's exemption).
	task.wait(CHARGE_LOCKED)

	--- hand everything back BEFORE the shot, so a launch error cannot strand it
	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	fireVFX("showArms", char)
	if anim then anim:Stop(0.2) end

	--- guarded: useFunc runs in a pcall that would silently swallow a missing
	--- asset and abandon the payload below.
	local outSrc = script:FindFirstChild("PurpleOut")
	if outSrc then
		local outSnd = outSrc:Clone() :: Sound
		outSnd.Parent = humObj.HRootPart
		outSnd:Play()
		game.Debris:AddItem(outSnd, 6)
	end

	--- direction sampled HERE, once -- the beam does not track.
	local orb = this:projectile(PURPLE_CFG, hurtbox.CFrame * CFrame.new(0, 0, -SPAWN_AHEAD))

	--- SPAWNED, not awaited: the beam outlives this call and endLag must not wait on the carve.
	if orb then task.spawn(carveLane, orb) end

	--- after the orb, not before: the aim is read off the root and the client
	--- takes a frame to drop the gyro. camShake lives in VFXQuiver/purpleOrb.
	releaseAir()

	this:endLag(0.5)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
