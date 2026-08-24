--!strict
--- Bastar - a greatsword move in two beats: SLAM someone into the ground and
--- pin them on the blade, hold, then hurl the sword down the lane.
--- Needs a weapon with a blade. rowa1 port: README.md/PORT_Bastar.
--- Slam stun halved from rowa1's 2.0 (its longest): rowa2's stun is a single
--- field, and the weld already guarantees the follow-up.
--- !! THE ORDER IS THE MOVE:
---   cast   P1 + hshock, blade sings and glows. NO SHAKE, nothing has hit yet.
---   0.55   the overhead ARC, then a 0.1 beat
---   0.65   IMPACT: carve, shake, stomp, THEN the hitbox resolves and pins
---   +0.0   P2 starts IMMEDIATELY on the pin -- the throw wind-up IS the hold
---   +0.8   the second ARC, the release, the throw
--- The carve belongs to the SLAM, not the throw: it is the floor breaking under
--- an overhead greatsword, not a trench the sword ploughs.
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
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--- ability-local sounds, rowa1's own, cloned onto the blade (StrongLeft pattern)
local function bladeSfx(blade: BasePart?, name: string, from: number?)
	if blade == nil or blade.Parent == nil then return end
	local src = script:FindFirstChild(name)
	if src == nil or not src:IsA("Sound") then return end
	local snd = src:Clone()
	snd.Parent = blade
	snd:Play()
	--- rowa1 skips hs3's first 0.1s so the two swings do not double up
	if from then snd.TimePosition = from end
	game.Debris:AddItem(snd, 4)
end

--- rowa1 "bastard": Heavy, slash, 20 dmg, truestun 1.6 / stun 2.0, posMult 4.
local BASTARD = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.slash,
	dmg      = 18,
	--- 2.0 halved: see the header
	stun     = 1,
	posMult  = 4,
	--parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
	end,
}

--- rowa1 "gsThrow": Heavy, slash, 20 dmg, truestun 0.6 / stun 0.8, posMult 5.
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
	if humObj.wielding_weapon == nil then
		return -- greatsword move; rowa1 gated on the Tool having a Blade
	end

	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Part1, 0, 1, 1)

	--- hshock takes a BASEPART in rowa2, not a Humanoid (README S5 step 7e)
	fireVFX("hshock", humObj.HRootPart)

	local blade = humObj:GetBlade()
	if blade then
		bladeSfx(blade, "heavySwung2")
		bladeSfx(blade, "hs3", 0.1)
		--- the wind trail off the blade for the length of the wind-up
		fireVFX("emit", blade, "Wind", 8, 4)
		--- rowa1 tints the blade red for the whole windup
		fireVFX("partOutline", blade, Color3.fromRGB(255, 0, 0), 0.4)
	end

	if this:feintWait(0.47) then
		if anim then anim:Stop() end
		return
	end

	--[[ the overhead ARC, and it lands BEFORE the impact does. rowa1's
		literal CFrame; the quiver id tracks the root for the 0.6s it fades. ]]
	fireVFX("BigSlash",
		hurtbox.CFrame * CFrame.Angles(math.rad(-45), 0, math.rad(-110)),
		hurtbox)

	--[[ rowa1's second beat: 0.1s between the arc and the impact, and it
		re-checked stun across it. ]]
	if this:feintWait(0.12) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	local forward = hurtbox.CFrame.LookVector

	--[[ THE IMPACT, in rowa1's order: the floor goes first, then the shake
		and the stomp, then the hitbox.
		rowa1 stepped six 7^3 SmallBreak2s -- three positions at two heights --
		down the lane in front of the caster. One ELLIPSOID does it properly:
		wide and tall along the lane, in a single call. ]]
	local laneMid = hurtbox.Position + forward * 12 + Vector3.new(0, 1, 0)
	Destruction.Ellipsoid(nil, CFrame.new(laneMid, laneMid + forward),
		--- studs/SECOND: a greatsword driven into the floor throws it
		Vector3.new(4, 5, 12), 2.4, forward * 55)

	--[[ rowa1 gated these three on having actually broken something
		(breakCount > 8), which on any normal floor is always true.
		The ring lies FLAT: rowa1 aims it at origin + (0,-10,0), i.e. straight
		down into the floor it just cracked, six studs ahead and two down.
		11 x 11 x 1 at 0.96, and this is the caller that DOES play `boom`. ]]
	local slamAt = hurtbox.Position + forward * 6 + Vector3.new(0, -2, 0)
	fireVFX("shockRing",
		CFrame.new(slamAt, slamAt + Vector3.new(0, -10, 0)),
		Vector3.new(11, 11, 1), 0.96, true)
	fireVFX("camShake", hurtbox.Position, 300, 1, 0.1)
	bladeSfx(blade, "Stomp")

	--[[ the SLAM. atkDir is DOWNWARD -- HumObj reads it for the victim's
		reaction, and this drives them into the floor rather than away. ]]
	local _, hits = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(5, 7, 7))

	local pinned: {any} = {}
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(BASTARD, enemy, Vector3.new(0, -1, 0))
		-- rowa1 (0,-10,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = this:knockback(Vector3.new(0, -6, 0), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() and enemy.grab then
			--[[ !! PINNED ON THE BLADE, not the root -- they are IMPALED and
				carried on the sword. Welding to the root leaves them floating
				at the caster's waist. The offset runs along the blade, and
				falls back to the root if there is no blade. ]]
			--- PURE ROTATION: the blade already IS where they should hang.
			--- rowa1: C0 = CFrame.Angles(90, 0, 180).
			enemy.grab:grab(humObj,
				CFrame.Angles(math.rad(90), 0, math.rad(180)), 2, blade)
			--[[ TRUE stun for the pin: an ordinary :Stun REFUSES TO WRITE under
				hyper armour, so an armoured victim could swing off the blade.
				GUARDED because TrueStun is NOT in the Combatant contract --
				SimpleEntity has :Stun only. Same guard Freeze/ToshiCounter use. ]]
			if enemy.TrueStun then
				enemy:TrueStun(0.88)
			end
			table.insert(pinned, enemy)
		end
	end

	if #pinned == 0 then
		this:endLag(0.25)
		return
	end

	--[[ !! THE THROW ANIMATION STARTS HERE, ON THE PIN, and the hold happens
		underneath it -- that is what the hold IS. It used to play after the
		hold, in the same frame as its own hitbox, so the sword was never seen
		being raised or thrown: the victim just took a second hit out of a
		static pose. rowa1 stops P1 and starts P2 the instant the weld lands,
		then waits its 0.8s. ]]
	bladeSfx(blade, "heavySwung")
	if anim then anim:Stop(0.1) end
	local throwAnim = this:PlayAnim(script.Part2, 0.05, 1, 1)

	--[[ the hold. rowa1 waits 0.8s pinned before the throw, and releases the
		welds on the same 0.8s timer.
		THE PIN MUST COME OFF ON EVERY EXIT -- a stranded weld is a player
		who can never move again, and it is silent. ]]
	local function unpin()
		for _, enemy in ipairs(pinned) do
			if enemy.grab then enemy.grab:release() end
		end
	end

	if this:feintWait(0.8) then
		if throwAnim then throwAnim:Stop() end
		unpin()
		return
	end

	unpin()

	--- the release ARC, before the hit it belongs to. rowa1's literal CFrame.
	forward = hurtbox.CFrame.LookVector
	fireVFX("BigSlash",
		hurtbox.CFrame * CFrame.Angles(math.rad(45), 0, math.rad(200)),
		hurtbox)

	local _, thrown = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(5, 7, 7))
	for _, enemy in pairs(thrown) do
		local attack = this:makeAtk(GS_THROW, enemy, forward)
		-- rowa1 look*40 + (0,8,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = this:knockback(
			attack.atkDir * 24 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--- rowa1's gsThrow onHit is ragdtillground: a CAP ended by landing
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
