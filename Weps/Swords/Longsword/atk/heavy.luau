--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

local function dimensionalSlash(this:wepTyp&any, humObj:any)
	local range = 2000

	print("test")
	local dir = humObj.HRootPart.CFrame.LookVector*4000

	local hit,endp, normal = workspace:FindPartOnRayWithIgnoreList(Ray.new(humObj.HRootPart.Position, dir), {workspace.Entities})

	local flipmult = if math.random(0,1) == 1 then 1 else -1

	destruction.Ellipsoid(humObj.plrObj.Plr,
		CFrame.new(endp, endp + normal) * CFrame.Angles(0, 0, math.rad(math.random(20,40)*flipmult)),
		Vector3.new(18,100,18))
	destruction.Ellipsoid(humObj.plrObj.Plr,
		CFrame.new(endp, endp + normal) * CFrame.Angles(0, 0, math.rad(math.random(20,40)*flipmult)),
		Vector3.new(100,18,18))

end

local function lerp(a: Vector3, b: Vector3, t: number)
	--return a:Lerp(b, t)
	return a * (1 - t) + b * t
end

return function (this:wepTyp&any): wepType.atkResult
	if not this:canTriggerCD("heavy") then return end
	this:triggerCD("heavy")
	local humObj = this._humObj
	local root = humObj.HRootPart
	local hurtbox = humObj.HurtBox
	
	local anim = this:PlayAnim(script.HeavyStart, 0.25, 1.5, 0.2, true)

	task.wait(0.2)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	this:indicateAtk()

	
	local totalDuration = 1.4
	local accelTime = 1.2
	local maxSpeed = 75

	local startTime = tick()
	local endTime = startTime + totalDuration

	while tick() - startTime < totalDuration do
		local elapsed = tick() - startTime
		local speed = 0

		if elapsed < accelTime then
			local t = elapsed / accelTime
			t = t * t * (3 - 2 * t) 
			speed = maxSpeed * t
		else
			speed = maxSpeed
		end
		
		root.AssemblyLinearVelocity = root.CFrame.LookVector * speed


		anim:AdjustSpeed(0.45 + (speed / maxSpeed) * 1.1)

		task.wait()
	end

	local hitCFrame = CFrame.new(0, 0, -20)
	local hitboxSize = Vector3.new(8, 6, 40)
	
	--task.wait(0.15)
	local hitbox, hits = this:hitbox(hitCFrame, hitboxSize, true)

	local hitLanded = false
	
	local enemyHum = nil
	
	
	for _, enemhum in ipairs(hits) do
		local atk = this:makeAtk(
			dmgConfig.heavy,
			enemhum,
			root.CFrame.LookVector
		)
		atk.hitbox = hitbox
		this:executeAttack(atk)

		if atk:isHit() then
			enemyHum = atk.enemyEntity
			hitLanded = true
		end
	end

	if hitLanded then
		
		local hitAnim = this:PlayAnim(script.HeavyCharge, 0.35, 1, 0.85, true)
		
		
		humObj:setTransparency(1)
		local dir = root.CFrame.LookVector * 4000
		local hit, endp, normal =
			workspace:FindPartOnRayWithIgnoreList(
				Ray.new(root.Position, dir),
				{workspace.Entities}
			)

		if endp then
			
			--[[
			local endt = tick() + 5
			while tick() < endt do ??
			--
			end
			]]
			local duration = 0.25
			local st = tick()
			local endt = st + duration
			-- u could move this in local
			local lerpStart = root.Position
			
			humObj:FireVFXClient(
				"slash",
				Vector3.new(0,0,-1.5)
			)
			
			
			
			
			--humObj.HRootPart.CFrame = root.CFrame * CFrame.Angles(math.rad(-10), 0, 0)
			while tick() <= endt do
				local t = (tick()-st)/duration -- 0-1
				t = 1 - (1 - t) * (1 - t)
				local target:any = enemyHum.HRootPart.Position + enemyHum.HRootPart.CFrame.LookVector * -0.25
				root.Position = lerp(lerpStart, target, t)
				task.wait()
			end
			
			humObj.walkSpeed:RemoveMod("stopMoving")
		end
		humObj:setTransparency()
		task.wait(1)
		hitAnim:Stop()

	else
		
		anim:Stop()
		local slideAnim = this:PlayAnim(script.Slide, 0.65, 91, 0.65, false)
		
		humObj.Hum.HipHeight = -1
		
		local decelTime = 1.75
		local startVel = root.AssemblyLinearVelocity
		local st = tick()
		while tick() - st < decelTime do
			local t = (tick() - st) / decelTime
			t = t * t * (3 - 2 * t)
			root.AssemblyLinearVelocity = startVel * (1 - t)
			slideAnim:AdjustSpeed(0.2 + (startVel.Magnitude / maxSpeed) * 1.8 * (1 - t))
			task.wait()
		end
		

		humObj.walkSpeed:RemoveMod("stopMoving")
		humObj.Hum.HipHeight = 0
		slideAnim:Stop()
		
	end 

	return hitLanded
end
--