--!strict
-- Bastar - slam someone onto the blade, hold, hurl them down the lane. Blade only; only the windup feints.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Bastar"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local function bladeSfx(blade: Instance, name: string, from: number?)
	if blade.Parent == nil then return end
	local src = script:FindFirstChild(name)
	if src == nil or not src:IsA("Sound") then return end
	local snd = src:Clone()
	if from then snd.TimePosition = from end
	snd.Parent = blade
	snd:Play()
	game.Debris:AddItem(snd, 4)
end

-- rowa1's six SmallBreak2 cubes as one ellipsoid
local CARVE_SZ = Vector3.new(7, 13, 19)
local PIN_C0 = CFrame.Angles(math.rad(90), 0, math.rad(180))
local RED = Color3.fromRGB(190, 25, 25)
-- roll (+ = ccw from behind), then rowa1's arc yawed 90 left
local THROW_ARC = CFrame.Angles(0, 0, math.rad(45))
	* CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(45), 0, math.rad(200))

-- the slam.
local BASTARD = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.slash,
	dmg      = 18,
	stun     = 1, -- rowa1's 2, halved
	posMult  = 4,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
	end,
}

-- the throw.
local GS_THROW = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.slash,
	dmg      = 10,
	stun     = 0.8,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "BladeStab", "HeavyCut", "BombFall")
	end,
}

local function useFunc(this:myself)
	local cooldownID = "bastar"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	-- bladeless, the pin welds them inside you
	local blade = humObj:GetBlade()
	if blade == nil then return end

	local hurtbox = humObj.HurtBox
	local anim = this:PlayAnim(script.Part1, 0, 1, 1)

	fireVFX("hshock", humObj.HRootPart)
	bladeSfx(blade, "heavySwung2")
	bladeSfx(blade, "hs3", 0.1)
	fireVFX("emit", blade, "RedWind", 8, 4)
	fireVFX("partOutline", blade, RED, this:scaledTime(0.55) + this:scaledTime(0.1), true)

	-- rowa1's timing: arc at 0.55, impact 0.1 later
	if this:feintWait(0.55) then
		if anim then anim:Stop() end
		return
	end

	fireVFX("BigSlash",
		hurtbox.CFrame * CFrame.Angles(math.rad(-45), 0, math.rad(-110)),
		hurtbox, nil, RED)

	if this:feintWait(0.1) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	local forward = hurtbox.CFrame.LookVector

	local laneMid = hurtbox.Position + forward * 12 + Vector3.new(0, 1, 0)
	Destruction.Ellipsoid(nil, CFrame.new(laneMid, laneMid + forward),
		CARVE_SZ, 3, forward * 55) -- coarse minSz: fewer fragments

	local slamAt = hurtbox.Position + forward * 6 + Vector3.new(0, -2, 0)
	fireVFX("shockRing",
		CFrame.new(slamAt, slamAt + Vector3.new(0, -10, 0)),
		Vector3.new(11, 11, 1), 0.8, true)
	bladeSfx(blade, "Stomp")

	local _, hits = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(5, 7, 7))
	local hold = this:scaledTime(0.8)

	local pinned: {any} = {}
	local welds: {Weld} = {}
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(BASTARD, enemy, Vector3.new(0, -1, 0))
		attack.knockback = this:knockback(Vector3.new(0, -6, 0), 0.2, false, -1)
		this:executeAttack(attack)

		-- Reflect swaps enemyEntity: nobody to pin
		if attack:isHit() and attack.enemyEntity == enemy and enemy.grab then
			table.insert(welds, enemy.grab:grab(humObj, PIN_C0, hold + 1, blade))
			-- true stun pierces hyper armour
			if enemy.TrueStun then
				enemy:TrueStun(hold + 0.08)
			end
			table.insert(pinned, enemy)
		end
	end
	fireVFX("bastar", 1, humObj.HRootPart, welds, hold)

	if #pinned == 0 then
		this:endLag(0.25)
		return
	end

	bladeSfx(blade, "heavySwung")
	local throwAnim = this:PlayAnim(script.Part2, 0.05, 1, 1)

	local holdEnd, dropped = tick() + hold, false
	while not dropped and tick() < holdEnd do
		task.wait()
		dropped = humObj.isActive ~= true or humObj:inStun()
	end
	-- !! release on every exit or they are stuck for good
	for _, enemy in ipairs(pinned) do enemy.grab:release() end
	if dropped then
		if throwAnim then throwAnim:Stop() end
		return
	end

	forward = hurtbox.CFrame.LookVector
	fireVFX("BigSlash", hurtbox.CFrame * THROW_ARC, hurtbox, nil, RED)
	fireVFX("bastar", 2, humObj.HRootPart)

	-- the held, not a new box, as rowa1
	for _, enemy in ipairs(pinned) do
		local attack = this:makeAtk(GS_THROW, enemy, forward)
		attack.knockback = this:knockback(
			attack.atkDir * 24 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
