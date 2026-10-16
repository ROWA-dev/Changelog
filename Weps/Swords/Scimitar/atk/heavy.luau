--!strict
-- Scimitar heavy: a diagonal cut; land it and the next heavy is the launching uppercut (heavy2).
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local uppercutLift = require(game.ServerStorage.ROWA.Weps.WepBase.dmgConfig.uppercut.lift)

local FX = "scimHvy" -- stages: 1 swing, 2 hit (dmgConfig)
local SLASH_SIZE = Vector3.new(26, 6, 26)
local BOX_CF, BOX_SIZE = CFrame.new(0, 0, -6), Vector3.new(10, 10, 10)
local ACTIVE = table.freeze({ window = 0.1 })
local MISS_CD = 4 -- whiffed/parried cut or lapsed follow-up; the uppercut pays the registered 10 (Scimitar:wield)
local WINDOW = 1.5 -- after a cut lands or is blocked, a heavy within this is the uppercut
local SPACING, KB_STUDS = 14, 1.1 -- the cut leaves them ~SPACING ahead at any range; studs per knockback(f, 0.3) unit
local PULL = Vector3.new(0, 0, -6) -- a landed cut steps you ~5 after them
local LUNGE = Vector3.new(0, 0, -5) -- the uppercut closes ~5 over its windup

-- BigSlash face up (single-sided mesh). hit = anim time of the whip; the windup plays sped up to land it on windup
local CUT = table.freeze({
	anim = script.heavy, windup = 0.5, hit = 0.667, dmg = dmgConfig.heavy,
	slash = CFrame.Angles(0, 0, math.rad(-28)) * CFrame.Angles(0, math.rad(-115), 0), -- left high to right low, clockwise
})
local UPPER = table.freeze({
	anim = script.heavy2, windup = 0.4, hit = 0.45, dmg = dmgConfig.heavy2,
	slash = CFrame.Angles(0, 0, math.rad(-65)) * CFrame.Angles(0, math.rad(-205), 0), -- right low to left high, steep, ccw
})

return function(this:wepTyp&any): wepType.atkResult
	local up = tick() < (this._h2Until or 0)
	if not up and this:canTriggerCD("heavy") == false then return end
	local beat = if up then UPPER else CUT
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox
	local root = humObj.HRootPart

	local anim = this:PlayAnim(beat.anim, 0.08, 1, beat.hit / beat.windup)
	this:indicateAtk()
	local tip: any = this._model.scimitar.Blade.Top
	local spark = tip:FindFirstChild("hspark") or script.hspark:Clone() -- one per blade, cloned on first heavy
	spark.Parent = tip
	spark:Emit(1)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	fireVFX("hshock", root)
	local lunge = if up then this:bodyForce(LUNGE, beat.windup, true, beat.windup) else nil
	local function bail()
		this:stopLastAnim(true)
		humObj.walkSpeed:RemoveMod("stopMoving")
		if lunge then lunge:destroy() end
	end

	if this:feintWait(beat.windup) then bail() return end
	-- cds only go up, so the cut pays the whiff price now and a hit Resets it
	this:triggerCD("heavy", if up then nil else MISS_CD)
	if up then this._h2Until = nil end
	anim:AdjustSpeed(anim.Speed * beat.windup / beat.hit) -- follow-through back at normal speed
	fireVFX("BigSlash", hurtbox.CFrame * beat.slash, hurtbox, SLASH_SIZE, nil, up or nil)
	fireVFX(FX, 1, root)

	local hitbox, hits = this:sweep(BOX_CF, BOX_SIZE, ACTIVE)
	if humObj:inStun() then bail() return end

	local look = hurtbox.CFrame.LookVector
	local hitLanded, connected = false, false
	for _, enemy in hits do
		local attack = this:makeAtk(beat.dmg, enemy, if up then Vector3.yAxis else look)
		attack.hitbox = hitbox
		if not up then
			local gap = (enemy.HRootPart.Position - root.Position):Dot(look)
			attack.knockback = this:knockback(look * math.max(SPACING - gap, 2) / KB_STUDS, 0.3)
		end
		this:executeAttack(attack)
		if attack:isHit() then hitLanded = true end
		if attack:isBlocked() then connected = true end
		if up and (attack:isHit() or attack:isBlocked()) then uppercutLift(attack) end -- a block goes up too
	end
	connected = connected or hitLanded -- a block chains like a hit

	if connected and not up then
		humObj.cooldowns:Reset("heavy")
		this:bodyForce(PULL, 0.3, true, 0.3)
		local armed = tick() + WINDOW
		this._h2Until = armed
		task.delay(WINDOW, function() -- lapsed = a miss
			if this._h2Until ~= armed then return end
			this._h2Until = nil
			this:triggerCD("heavy", MISS_CD)
		end)
	end

	-- a whiff already spent the 0.1 sweep window, so 0.3 + 0.1 = the house 0.4
	this:endLag(if connected then 0.2 else 0.3)
	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end
