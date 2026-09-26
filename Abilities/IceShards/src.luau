--!strict
--- IceShards - hop back and fire 20 shards (waves of 2..6) that form behind you for 0.4s, then fly at the target's lead point; they stick in whoever they hit and a parry scatters them.
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
local layIce   = require(game.ServerStorage.ROWA.Modules.layIce)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)

--- per shard, and all 20 can land: Barrage/FlameDance's multi-hit numbers
local ICE_SHARD = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = bit32.bor(dmgFlag.ice, dmgFlag.slash),
	dmg      = 4,
	stun     = 0.4,
	posMult  = 0, -- the knockback's 3^0.8 is the posture now, ~the old 2
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash2")
	end,
}

local FREEZE_FILL = 1.5
local WAVES       = 5
local FORM_TIME   = 0.4
local SHARD_GAP   = 0.05
local RANGE       = 200
--- no lock: the fan converges this far ahead instead of flying parallel
local NO_LOCK_DIST = 60

local SHARD = table.freeze({
	speed       = 280,
	lifetime    = 1,
	maxDistance = 300,
	size        = Vector3.new(2, 2, 4),
	dmgTbl      = ICE_SHARD,
	stopOnWorld = true,
	--- each hit re-arms the mover, so a volley reads as one steady shove
	knockbackForce = 4,

	onHit = function(proj, attack)
		local enemy = attack.enemyEntity
		if attack:isHit() then
			--- rides the end packet, so the drawn shard sticks in them
			proj.target = enemy
			enemy.statusEffects:apply(statusEffects.Freeze, 4, FREEZE_FILL)
			--- a long CAP ended by the ground check, not a 60s ragdoll
			enemy.ragdoll:ragdoll(60, true, proj.dir * 8)
		elseif attack:isParried() then
			--- scattered like a side gun bullet but NOT handed to the parrier, so it can't come back into its caster and break the volley
			local eroot = enemy.HRootPart
			if eroot then proj:deflect(proj:parryDir(eroot.CFrame.LookVector, 0.2)) end
		end
	end,

	onExpire = function(proj, pos, hitWorld)
		local wh = proj.worldHit
		if hitWorld and wh and wh.Instance.Anchored then
			layIce(pos, wh.Normal, 16, wh.Instance :: BasePart)
		end
	end,
})

--- client key for a shard before its projectile exists; monotonic so casts never collide
local nextShard = 0

local function launchShard(this: myself, offset: Vector3, shardId: number)
	local humObj = this._humObj
	local root = humObj.HRootPart
	if humObj.isActive ~= true or root == nil then return end

	local target = Targeting.nearestInDirection(root.Position, root.CFrame.LookVector, humObj, RANGE, Targeting.TIGHT)
	local troot = target and target.HRootPart
	local ahead = root.Position + root.CFrame.LookVector * NO_LOCK_DIST
	fireVFX("iceShard", 0, shardId, root, offset, troot or ahead)

	task.wait(FORM_TIME)
	root = humObj.HRootPart
	if humObj.isActive ~= true or root == nil or humObj:inStun() then
		fireVFX("iceShard", 2, shardId)
		return
	end

	local from = root.CFrame:PointToWorldSpace(offset)
	local lock = target and target.isActive == true and target.HRootPart
	local at = if lock then Targeting.lead(lock, from, SHARD.speed) else ahead
	local launchCF = CFrame.lookAt(from, at)
	local p = this:projectile(SHARD, launchCF)
	fireVFX("iceShard", 1, shardId, launchCF, SHARD.speed, p and p.id)
end

local function useFunc(this:myself)
	local cooldownID = "iceShards"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	local snd = script.magicFreeze:Clone()
	snd.Parent = humObj.HRootPart
	snd:Play()
	game.Debris:AddItem(snd, 4)

	--- the backwards hop. bodyForce scales by 5 internally.
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
		local amt = x + 1
		local halfpt = amt / 2 + 0.5
		for i = 1, amt do
			if humObj.isActive ~= true or humObj:inStun() then break end
			nextShard += 1
			--- sideways by rank, higher each wave, 10 studs behind the caster
			task.spawn(launchShard, this, Vector3.new((i - halfpt) * 8, x * 6, 10), nextShard)
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
