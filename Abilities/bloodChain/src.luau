--!strict
--[[ bloodChain - rowa1 Items/Ability/bloodChain.
	Notes: README.md/PORT_bloodChain.

	Hop backwards, spin up a blood chain, and hurl it at a locked target. On
	a connect, BOTH parties are yanked to the point between them.

	!! THE DOC'S OPEN DESIGN QUESTION IS ANSWERED BY THE SOURCE.
	  It asked whether this is a disengage (only the caster moves) or a
	  gap-closer (the victim is pulled in), and guessed the former.
	  rowa1 does BOTH: two BodyPositions, one on each root, both targeting
	  `(targRoot.Position + Root.Position)/2`. It is a MUTUAL yank to the
	  midpoint, running until they are within 4 studs or one second passes.
	  So the caster's backward hop is a wind-up, not the point of the move.

	The chain WINDS UP as it flies -- 60 studs/s accelerating to 160 -- which
	is why acceleration is a base projectile property rather than something
	bolted onto this ability.

	PARRYING IT DOES NOT BREAK IT, IT REDIRECTS IT -- the same reward the
	rocket and the crescent give, and the reason BaseProjectile:deflect is
	shared. See the parry branch in `onHit` for who the chain may pick next
	and, more importantly, who it may not. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "bloodChain"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils   = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag    = dmgUtils.dmgFlags
local Projectile = require(game.ServerStorage.ROWA.Class.Projectile)
local Targeting  = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 "chain": Heavy, magic, 10 dmg, stun 0.8, posMult 4, parryH -0.1.
	Low damage, high posture, negative parry help -- a guard-breaking opener,
	not a damage move. Preserve that shape.

	!! `blood` MOVED BIT POSITION between the games (rowa1 1024, rowa2 4096 --
	README S4.1), so it is written by NAME. rowa1 tagged this `magic` only
	despite the blood family; the flag is added here because the ability is
	literally called bloodChain and `isElemental` catches both either way. ]]
local CHAIN = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blood),
	dmg      = 10,
	stun     = 1,
	posMult  = 4,
	--parryH   = -0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "grab")
	end,
}

local WINDUP     = 0.8
local RANGE      = 200
local YANK_TIME  = 1
--- rowa1 stopped pulling once they were this close
local YANK_STOP  = 4
--- rowa1 MiniDash(-look + up*0.4, 60); bodyForce scales by 5, so 60/5 = 12
local HOP_FORCE  = 14

--[[ the mutual yank. rowa1 used two BodyPositions, one per root, both aimed
	at the midpoint. AlignPosition is the modern equivalent and nothing in
	rowa2 expresses "converge on a point" -- bodyForce is a fire-and-forget
	impulse and would overshoot.
	Returns a destructor. CALL IT ON EVERY EXIT: a stranded AlignPosition
	drags a player around permanently. ]]
local function yankTogether(rootA: BasePart, rootB: BasePart): () -> ()
	local made = {}

	local function pull(part: BasePart)
		local att = Instance.new("Attachment")
		att.Parent = part
		local align = Instance.new("AlignPosition")
		align.Attachment0 = att
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.MaxForce = part.AssemblyMass * 4000
		align.Responsiveness = 40
		align.Parent = part
		table.insert(made, att)
		table.insert(made, align)
		return align
	end

	local alignA, alignB = pull(rootA), pull(rootB)

	local alive = true
	task.spawn(function()
		local endt = tick() + YANK_TIME
		while alive and tick() < endt do
			if rootA.Parent == nil or rootB.Parent == nil then break end
			local mid = (rootA.Position + rootB.Position) / 2
			alignA.Position = mid
			alignB.Position = mid
			--- rowa1 stopped early once they met
			if (rootA.Position - rootB.Position).Magnitude < YANK_STOP then break end
			task.wait()
		end
		alive = false
		for _, inst in ipairs(made) do inst:Destroy() end
	end)

	return function()
		if not alive then return end
		alive = false
		for _, inst in ipairs(made) do inst:Destroy() end
	end
end

local CHAIN_CFG = table.freeze({
	class       = Projectile.Homing,
	--- rowa1 wound 60 -> 160 over the flight
	speed       = 60,
	accel       = 100,
	maxSpeed    = 160,
	--- it tracks hard; the chain is not meant to be outrun sideways
	steer       = 8,
	lifetime    = 1,
	maxDistance = 220,
	--- rowa1's arrival test was `dist < 3`
	size        = Vector3.new(3, 3, 3),
	dmgTbl      = CHAIN,
	pierce      = 1,
	--- a chain crosses cover; rowa1 never raycast it
	stopOnWorld = false,
	--[[ NO fxId. The generic projectile fx contract only passes
		(originCF, speed, maxDistance, size), and the beam needs the
		CASTER'S ARM for its near end -- without Attachment0 a Beam renders
		nothing at all. So bchain is fired by hand below with the arm and the
		target, and the projectile itself draws nothing. ]]
	fxId        = nil,
})

local function useFunc(this:myself)
	local cooldownID = "bloodChain"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	--[[ the chain hangs off this for its whole life and the fx module KEYS
		ON IT (bchain's `active` registry), so all four stages have to be
		handed the same part. Looked up once. ]]
	local arm = char:FindFirstChild("Right Arm")

	--- the backward wind-up hop, root-relative so it follows your facing
	local hop = this:bodyForce(Vector3.new(0, 0.5, 1).Unit * HOP_FORCE, 0.3, true)

	fireVFX("bchainWindup", humObj.HRootPart, arm, WINDUP)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		if hop then hop:destroy() end
		fireVFX("bchainWindup", nil, nil, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	--[[ rowa1 used GetNearestInDirection5 (TIGHT), aimed slightly DOWN --
		the chain is thrown at chest height, not along the eyeline. ]]
	local aimDir = (hurtbox.CFrame.LookVector + Vector3.new(0, -0.3, 0)).Unit
	local target = Targeting.nearestInDirection(
		hurtbox.Position, aimDir, humObj, RANGE, Targeting.TIGHT)

	--- rowa1 simply did nothing without a target. Refund most of the cost.
	if target == nil or target.HRootPart == nil then
		this:triggerCD(cooldownID, 2)
		this:endLag(0.2)
		return
	end

	local myRoot = humObj.HRootPart
	local cfg = table.clone(CHAIN_CFG)
	cfg.target = target
	cfg.onHit = function(proj, attack)
		--[[ PARRIED: THE CHAIN IS SLAPPED ASIDE, NOT CUT. It used to simply
			die here, which is a fine reward and a boring one. Whipped onto
			somebody else it keeps the read (it is no longer YOUR problem)
			and hands the parrier the aim. ]]
		if attack:isParried() then
			local proot = attack.enemyEntity.HRootPart
			if proot == nil then
				Projectile.kill(proj)
				return
			end
			local look = proot.CFrame.LookVector
			--[[ the new victim is whoever the PARRIER is pointing at, on the
				same TIGHT cone the cast itself used.

				!! `me` IS THE CASTER, AND THAT IS THE WHOLE POINT: it is the
				one argument that excludes both people the chain must not
				pick. The CASTER, because the beam hangs off their own hand --
				a chain that turned around onto its thrower draws as a
				zero-length chain and then yanks a root to the midpoint
				between itself and itself, i.e. nothing happens twice. And the
				PARRIER, who is the search ORIGIN and therefore sits at
				distance 0, which Targeting skips -- handing the chain
				straight back to the person who just parried it is the
				opposite of a reward (BaseProjectile.deflect's own note).
				Nobody in the cone means nobody: deflect re-decides the target
				unconditionally, so the chain flies off straight and times
				out rather than re-locking whoever it had. ]]
			local newTarget = Targeting.nearestInDirection(
				proot.Position, look, humObj, RANGE, Targeting.TIGHT)
			--- rowa1's rocket blend, degeneracy handled. See parryDir.
			proj:deflect(proj:parryDir(look), newTarget, 0.15, attack.enemyEntity)
			--[[ this projectile has NO fxId (see CHAIN_CFG), so the generic
				projSteer correction has nothing to correct -- the drawn chain
				is bchain's own stage 1 loop and stage 3 is how it is turned. ]]
			fireVFX("bchain", 3, arm, proj.pos, proj.dir,
				newTarget and newTarget.HRootPart or nil)
			return
		end

		if not attack:isHit() then
			--- rowa1 only kept flying on a DODGE; anything else ended it
			if not attack:isDodged() then Projectile.kill(proj) end
			return
		end

		local eroot = attack.enemyEntity.HRootPart
		if eroot == nil or myRoot == nil or myRoot.Parent == nil then return end

		--[[ a DEFLECTED chain can run back into its own thrower -- they stop
			being the ignored owner the moment someone parries it -- and the
			targeting above only keeps it from AIMING at them, not from
			flying through them. There is nothing to yank in that case, so it
			takes its damage and drops. ]]
		if eroot == myRoot then
			Projectile.kill(proj)
			return
		end

		fireVFX("bchainYank", myRoot, eroot)
		--[[ LATCH the flying chain onto them for the pull. Without this the
			beam just timed out mid-air and the yank played with nothing
			visibly connecting the two -- see bchain's header. ]]
		fireVFX("bchain", 2, arm, eroot, YANK_TIME)
		local release = yankTogether(myRoot, eroot)
		--- hard stop: the yank must never outlive its own window
		task.delay(YANK_TIME + 0.2, release)
	end

	local originCF = CFrame.new(myRoot.Position, target.HRootPart.Position)

	--[[ fired by hand rather than through cfg.fxId, because the beam's NEAR
		end has to be the caster's hand -- see the note on fxId above. ]]
	fireVFX("bchain", 1, originCF, CHAIN_CFG.speed, CHAIN_CFG.maxDistance,
		arm, target.HRootPart)

	this:projectile(table.freeze(cfg), originCF)

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
