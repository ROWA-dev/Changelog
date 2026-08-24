--!strict
--- IceShards - hop backwards and rain TWENTY ice shards on a target: five waves
--- of 2/3/4/5/6, each forming in the air for 0.4s before it dives.
--- rowa1 port: README.md/PORT_IceShards.
--- NOT homing despite the doc -- each shard picks its direction ONCE at launch;
--- rowa1 only re-aims during the 0.4s formation. BaseProjectile, not Homing.
--- They dive at a PITCH (70 deg about X, flown along -UpVector), which is why
--- the aim is LookVector + (0,-0.4,0): looking down so the arc lands on the
--- target rather than over their head.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "IceShards"
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
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 reused "ice2" (18 dmg) here, the SAME table IceSlash uses. But
	IceSlash throws TWO crescents and this throws TWENTY shards, so the
	shared number is far too high -- a target caught in the middle of the
	fan would eat several. Cut to 8, and the Freeze fill per shard is small
	for the same reason. ]]
local ICE_SHARD = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = bit32.bor(dmgFlag.ice, dmgFlag.slash),
	dmg      = 8,
	stun     = 0.4,
	posMult  = 1,
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash2")
	end,
}

--- 20 shards, so each fills a fifth of what a single IceBash hit does
local FREEZE_FILL = 0.6
local WAVES       = 5
local FORM_TIME   = 0.4
local SHARD_GAP   = 0.05
local BLAST       = 8
--- rowa1 pitched every shard 70 degrees about X before flying it
local PITCH       = 70
--- rowa1 aimed slightly DOWN so the pitched dive lands on the target
local AIM_DROP    = Vector3.new(0, -0.4, 0)

local SHARD = table.freeze({
	--- rowa1 randomised 260-300 per shard; the mean reads the same
	speed       = 280,
	lifetime    = 1,
	maxDistance = 300,
	size        = Vector3.new(4, 4, 6),
	--- the shard is inert in flight; the landing burst is the payload
	dmgTbl      = nil,
	stopOnWorld = true,
})

--- one shard: form, then dive. Runs per shard, off the main thread.
local function launchShard(this: myself, offset: Vector3, shardId: number)
	local humObj = this._humObj
	if humObj == nil or humObj.isActive ~= true then return end
	local root = humObj.HRootPart
	if root == nil then return end

	local rotate = CFrame.Angles(math.rad(PITCH), 0, 0)

	--- rowa1 used GetNearestInDirection5: the TIGHT preset.
	local aimDir = (root.CFrame.LookVector + AIM_DROP).Unit
	local target = Targeting.nearestInDirection(root.Position, aimDir, humObj, 200, Targeting.TIGHT)

	fireVFX("iceShard", 0, shardId, root, offset, rotate, target and target.HRootPart)

	task.wait(FORM_TIME)
	if humObj.isActive ~= true or humObj:inStun() then
		fireVFX("iceShard", 2, shardId)
		return
	end
	root = humObj.HRootPart
	if root == nil then
		fireVFX("iceShard", 2, shardId)
		return
	end

	--- re-aim at launch: rowa1 recomputed targDir AFTER the formation wait
	local targDir = if target and target.isActive == true and target.HRootPart
		then (target.HRootPart.Position - root.Position).Unit
		else root.CFrame.LookVector

	local cf = CFrame.new(root.Position, root.Position + targDir)
		* CFrame.new(offset.X, offset.Y, offset.Z)
		* rotate

	--[[ !! THE SHARD FLIES ALONG ITS OWN -UpVector AND KEEPS ITS PITCHED
		ORIENTATION -- two different things. Sending CFrame.new(pos, pos+flyDir)
		points the mesh along its travel and throws the 70 degree pitch away.
		`cf` carries BOTH: the client uses it as the visual orientation and
		derives the heading from its own -UpVector. ]]
	local flyDir = -cf.UpVector

	--[[ SERVER gets a look-at: BaseProjectile only reads .Position and
		.LookVector off this, so it wants the HEADING and does not care how
		the mesh is angled. Same two vectors, different consumer. ]]
	local originCF = CFrame.new(cf.Position, cf.Position + flyDir)

	local cfg = table.clone(SHARD)
	cfg.onExpire = function(proj, pos, hitWorld)
		local action = proj.action
		if action == nil or action._humObj == nil then return end

		fireVFX("iceShard", 2, shardId, nil, pos)

		--[[ rowa1 called placeSnow() on any ANCHORED surface it struck,
			leaving a 16-stud sheet of ice for 50 seconds. That ground layer
			is most of what the ability leaves behind and an earlier pass
			dropped it entirely.
			The surface NORMAL comes off proj.worldHit, which BaseProjectile
			now records when its sweep hits geometry. ]]
		local wh = proj.worldHit
		if hitWorld and wh and wh.Instance and wh.Instance.Anchored then
			fireVFX("placeSnow", pos, wh.Normal, 16)
		end

		local _, hits = action:hitbox(CFrame.new(pos), Vector3.one * BLAST, nil, true)
		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			local attack = action:makeAtk(ICE_SHARD, enemy, flyDir)
			action:executeAttack(attack)
			if attack:isHit() then
				enemy.statusEffects:apply(statusEffects.Freeze, 4, FREEZE_FILL)
				--- rowa1's "ice2" row carries onHit = ragdtillground
				enemy.ragdoll:ragdoll(60, true, flyDir * 8)
			end
		end
	end

	local p = this:projectile(table.freeze(cfg), originCF)

	--[[ !! FIRED AFTER THE PROJECTILE, so the shard can be handed its `id` and
		follow a deflect or an early end. It used to go first, which is why the
		drawn shard was on its own the moment the real one was interfered with.
		CLIENT gets the pitched CFrame: it needs the ORIENTATION, not the
		heading -- see the note on flyDir above. ]]
	fireVFX("iceShard", 1, shardId, root, cf, SHARD.speed,
		{ id = p and p.id, maxDistance = SHARD.maxDistance, lifetime = SHARD.lifetime })
end

local function useFunc(this:myself)
	local cooldownID = "iceShards"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	local snd = script.magicFreeze:Clone()
	snd.Parent = humObj.HRootPart
	snd:Play()
	game.Debris:AddItem(snd, 4)

	--[[ rowa1 declares Attacking.Time 0.1 AND waits 0.1 -- for once the
		claim and the truth agree. ]]
	--- the hop: rowa1 MiniDash(-look + up, 50); bodyForce scales by 5.
	local hop = this:bodyForce(Vector3.new(0, 1, 1).Unit * 10, 0.3, true)

	if this:feintWait(0.1) then
		if anim then anim:Stop() end
		if hop then hop:destroy() end
		game.Debris:AddItem(snd, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 20, true)

	for x = 1, WAVES do
		if humObj:inStun() then break end

		local amt = x + 1
		local halfpt = amt / 2 + 0.5
		for i = 1, amt do
			if humObj:inStun() then break end
			--[[ the fan: shards spread sideways by rank and climb by wave,
				so each wave arcs over the one before it. ]]
			local offset = Vector3.new((i - halfpt) * 8, x * 6, 10)
			task.spawn(launchShard, this, offset, math.random(1, 65536))
			task.wait(SHARD_GAP)
		end
	end

	if anim then anim:Stop(0.2) end
	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
