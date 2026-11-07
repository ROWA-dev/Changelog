--!strict
-- SumiyaNeedle heavy: a lunge that carries you THROUGH them and hooks the line on a hit or block; a heavy while hooked reels them onto a slash.
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local pinTo = require(game.ServerStorage.ROWA.Modules.pinTo)
local kb = require(game.ServerScriptService.Knockback)

local LINE = "sumiyaLine" -- stages: 1 hook, 2 reel, 3 let go (snapped?)
local MISS_CD = 6 -- a whiff or parry. A hook pays the registered 10 (SumiyaNeedle:wield) and lives as long as it; a reel restarts it
local SNAP = 50 -- studs apart and the line breaks
local RIP_DMG, RIP_STUN = 5, 0.4 -- what a snap tears out of them
local HOOKED = game.ServerStorage.ROWA.Class.StatusEffects.Hooked

local LUNGE_T = 0.5 -- the thrust's hit frame, so the anim runs at 1
local DASH = Vector3.new(0, 0, -14) -- ~10 studs on a whiff
local BOX_CF, BOX_SIZE = CFrame.new(0, 0, -5), Vector3.new(5, 6, 8)
local ACTIVE = table.freeze({ window = 0.15, lead = 0.07 })
local BEHIND = 5 -- a hook carries you this far past them
local PASS = table.freeze({ axes = Vector3.new(1, 0, 1), maxSpeed = 60, stopWithin = 1.5, maxTime = 0.35 })

local YANK, SLASH = 0.33, 0.73 -- the reel anim's two whips
local STOP = 4 -- they land this far from you
local REACH = 8 -- the slash lands if the pull got them this close
local PULL = table.freeze({ axes = Vector3.new(1, 0, 1), maxSpeed = 130, stopWithin = 1, maxTime = SLASH - YANK + 0.1 }) -- 130 lands a SNAP-range pull by the slash
local HOP = Vector3.new(0, 7, 0)
local SLASH_KB = 2 -- barely a nudge, so they stay in reach

local function bail(this: any, humObj: any)
	this:stopLastAnim(true)
	humObj.walkSpeed:RemoveMod("stopMoving")
end

-- the line lets go; a snap rips the hook out of them
local function release(this: any, enemy: any, snapped: boolean)
	fireVFX(LINE, 3, this._model.Blade.Top, snapped)
	if enemy.isActive ~= true then return end
	enemy.statusEffects:remove(HOOKED)
	if not snapped then return end
	-- raw, not an attack: a parried snap would stun you from SNAP studs away
	enemy:Damage(RIP_DMG)
	enemy:Stun(RIP_STUN)
	fireVFX("slash", enemy.HRootPart)
end

-- the hook's life: a lapse, a snap or losing either end let it go; the cd has run since the hook, so none costs extra
local function watch(this: any, enemy: any, armed: number)
	local humObj = this._humObj
	local root, eroot = humObj.HRootPart, enemy.HRootPart
	while this._hookUntil == armed do
		local far = (eroot.Position - root.Position).Magnitude > SNAP
		if far or tick() > armed or humObj.wielding_weapon ~= this or enemy.isActive ~= true or eroot.Parent == nil then
			this._hooked, this._hookUntil = nil, nil
			release(this, enemy, far)
			return
		end
		task.wait(0.1)
	end
end

local function lunge(this: any): boolean?
	if this:canTriggerCD("heavy") == false then return end
	local humObj = this._humObj
	local hurtbox, root = humObj.HurtBox, humObj.HRootPart
	local model = this._model

	this:PlayAnim(script.sumiyahvylunge, 0.08, 1, 1)
	this:indicateAtk()
	model.Hold.hvystart:Play()
	fireVFX("hshock", root)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	if this:feintWait(LUNGE_T) then bail(this, humObj) return end
	-- cds only go up, so the whiff price now and a hook pays the full one
	this:triggerCD("heavy", MISS_CD)
	model.Hold.arrowwoosh:Play()
	local dash = this:bodyForce(DASH, 0.3, true, 0.3)

	local hitbox, hits = this:sweep(BOX_CF, BOX_SIZE, ACTIVE)
	if humObj:inStun() then
		dash:destroy()
		bail(this, humObj)
		return
	end

	local look = hurtbox.CFrame.LookVector
	local hitLanded, hooked = false, nil
	for _, enemy in hits do
		local attack = this:makeAtk(dmgConfig.lunge, enemy, look)
		attack.hitbox = hitbox
		this:executeAttack(attack)
		if attack:isHit() then hitLanded = true end
		if attack:isParried() then dash:destroy() end
		-- a block hooks like a hit; Reflect swaps enemyEntity, so a reflected lunge hooks nobody
		if hooked == nil and attack.enemyEntity == enemy and (attack:isHit() or attack:isBlocked()) then hooked = enemy end
	end

	if hooked then
		dash:destroy()
		this:triggerCD("heavy")
		local eroot = hooked.HRootPart
		local window = humObj.cooldowns:remaining("heavy") -- the hook IS the cd: its bar is the hook timer
		fireVFX(LINE, 1, model.Blade.Top, eroot, window)
		hooked.statusEffects:apply(HOOKED, window)
		local armed = tick() + window
		this._hooked, this._hookUntil = hooked, armed
		task.spawn(watch, this, hooked, armed)
		-- only the two roots collide (limbs are charLimb), so one pair is the whole pass
		local nc = Instance.new("NoCollisionConstraint")
		nc.Part0, nc.Part1 = root, eroot
		nc.Parent = root
		game.Debris:AddItem(nc, PASS.maxTime + 0.2)
		local behind = eroot.Position + Vector3.new(look.X, 0, look.Z).Unit * BEHIND
		behind = Vector3.new(behind.X, root.Position.Y, behind.Z)
		pinTo(root, function() return behind end, PASS)
	end

	this:endLag(if hooked then 0.2 else 0.3)
	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end

local function reel(this: any): boolean?
	local humObj = this._humObj
	local root = humObj.HRootPart
	local model = this._model
	-- claimed, so a lapse mid-windup cannot eat an in-time press. A feint lets it go, or feinting would re-stun them every feint cd
	local enemy = this._hooked
	this._hooked, this._hookUntil = nil, nil
	if enemy.isActive ~= true then release(this, enemy, false) return end

	this:PlayAnim(script.sumiyahvyreelin, 0.08, 1, 1)
	model.Hold.fishingrodcast:Play()
	enemy:Stun(this:scaledTime(SLASH)) -- reeled from the first frame; a stun still blocks and parries, so the slash stays answerable
	humObj.walkSpeed:SetMod("stopMoving", -100)
	if this:feintWait(YANK) then
		bail(this, humObj)
		release(this, enemy, false)
		return
	end
	local eroot = enemy.HRootPart
	if enemy.isActive ~= true or eroot.Parent == nil or (eroot.Position - root.Position).Magnitude > SNAP then
		bail(this, humObj)
		release(this, enemy, true)
		return
	end
	enemy.statusEffects:remove(HOOKED)
	this:triggerCD("heavy")
	fireVFX(LINE, 2, model.Blade.Top, SLASH - YANK)

	local unpin = nil
	if not enemy.unlaunchable then -- a Boss's brain owns its body
		unpin = pinTo(eroot, function()
			if root.Parent == nil then return nil end
			local d = eroot.Position - root.Position
			local flat = Vector3.new(d.X, 0, d.Z)
			if flat.Magnitude <= STOP then return nil end
			return root.Position + flat.Unit * STOP
		end, PULL)
		kb(HOP, eroot, 0.25, false, 0.25)
	end
	local cancelled = this:feintWait(SLASH - YANK)
	if unpin then unpin() end
	if cancelled then bail(this, humObj) return end

	model.Hold.Swing1:Play()
	-- no :hitbox, the line is the hitbox; without this every reel reads as a whiff (GOTCHAS)
	this.prevHits = 0
	local hitLanded = false
	local d = eroot.Position - root.Position
	if d.Magnitude <= REACH and enemy.isActive then
		this.prevHits = 1
		local flat = Vector3.new(d.X, 0, d.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else humObj.HurtBox.CFrame.LookVector
		local attack = this:makeAtk(dmgConfig.reel, enemy, dir)
		attack.knockback = this:knockback(dir * SLASH_KB, 0.3)
		this:executeAttack(attack)
		hitLanded = attack:isHit()
	end

	this:endLag(if hitLanded then 0.2 else 0.3)
	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end

return function(this: wepTyp & any): wepType.atkResult
	if this._hooked then return reel(this) end
	return lunge(this)
end
