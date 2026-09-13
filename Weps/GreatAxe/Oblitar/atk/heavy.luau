--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local HITBOX_SZ = Vector3.new(6.5, 7, 6.5)

--- emit every emitter under an OblitarFX attachment, the way rowa1 did.
local function emitAll(fx: Instance, name: string)
	local holder = fx:FindFirstChild(name)
	if holder == nil then return end
	for _, v in pairs(holder:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 1)
		end
	end
end

local function playSound(parent: Instance?, name: string)
	local s = parent and parent:FindFirstChild(name)
	if s and s:IsA("Sound") then s:Play() end
end

--- one beat: query, resolve, report whether anything landed.
local function swing(this:wepTyp&any, dmgTbl, offset:number): boolean
	local hurtbox = this._humObj.HurtBox
	local hitbox, hits = this:hitbox(CFrame.new(0, 0, -offset), HITBOX_SZ)

	local landed = false
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(dmgTbl, enemy, hurtbox.CFrame.LookVector)
		attack.hitbox = hitbox

		if dmgTbl == dmgConfig.heavy2 then
			attack.knockback = this:knockback(hurtbox.CFrame.LookVector*18, 0.3)
		end

		this:executeAttack(attack)
		if attack:isHit() then
			landed = true
		end
	end
	return landed
end

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end

	local humObj = this._humObj
	local model  = this._model
	local hold   = model:FindFirstChild("Hold")

	fireVFX("hshock", humObj.HurtBox)

	local anim = this:PlayAnim(script.Heavy, 0.08, 1, 1.05)
	this:indicateAtk()

	local sharp = model:FindFirstChild("sharp", true)
	if sharp and sharp:IsA("ParticleEmitter") then sharp:Emit(1) end
	playSound(hold, "HeavySwing")

	local fx = script.OblitarFX:Clone()
	local weld = fx:FindFirstChild("Weld")
	if weld and weld:IsA("Weld") then
		weld.Part0 = fx
		weld.Part1 = humObj.HRootPart
	end
	fx.Parent = workspace.Effects
	game.Debris:AddItem(fx, 4)

	local function bail()
		if anim then anim:Stop() end
		game.Debris:AddItem(fx, 0)
	end

	--[[ BEAT ONE. rowa1's own base is 0.4 + 0.2 and its claim agrees;
		atkRate 1.05 scales what we pass. Do not pre-multiply. ]]
	if this:feintWait(0.52) then bail() return end

	this:triggerCD("heavy")
	
	playSound(hold, "BladeSwing")
	playSound(fx, "BladeSwing")
	playSound(fx, "Swing")
	emitAll(fx, "slice1")
	emitAll(fx, "line1")

	local landed = swing(this, dmgConfig.heavy, 4.5)

	-- BEAT TWO.
	if this:feintWait(0.4) then bail() return end

	playSound(hold, "BladeSwing")
	playSound(fx, "BladeSwing2")
	playSound(fx, "Swing")
	emitAll(fx, "slice2")
	emitAll(fx, "line2")

	if swing(this, dmgConfig.heavy2, 4) then
		landed = true
	end

	-- 0.4 endlag on miss
	if landed == false then
		this:atkWait(0.4)
	end
	return landed
end
