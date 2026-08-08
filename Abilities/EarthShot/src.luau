--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "EarthShot"
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
local dmgFlag = dmgUtils.dmgFlags
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local function useFunc(this:myself, targetPos:Vector3)
	local cooldownID = "earthShot"
	if not this:canTriggerCD(cooldownID) then return end
	print("USE ABILITY!")

	local root = this._humObj.HurtBox

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {root.Parent}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist

	local result = workspace:Raycast(root.Position, Vector3.new(0, -10, 0), rayParams)
	if not result then return end

	local ground = result.Instance
	local groundPos = result.Position

	this:useMana()
	this:triggerCD(cooldownID, 5, true)
	
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.new(0,2.5,0)
	bv.MaxForce = Vector3.new(1e5,1e5,1e5)
	bv.Parent = root.Parent.HumanoidRootPart
	game.Debris:AddItem(bv, 0.85)
	
	local rocks = {}
	for i = 1, 15 do
		local rock = Instance.new("Part")
		local size = math.random(1,2.5)
		rock.Size = Vector3.new(size, size, size)
		rock.Material = ground.Material
		rock.Color = ground.Color

		local offset = Vector3.new(math.random(-10,10), 0, math.random(-10,10))
		local spawnPos = groundPos + offset
		rock.Position = spawnPos
		rock.Anchored = true
		rock.CanCollide = false
		rock.Parent = workspace

		table.insert(rocks, {part = rock, basePos = spawnPos})

	end

	local riseTime = 0.85
	local startTime = tick()
	while tick() - startTime < riseTime do
		for i, rockData in pairs(rocks) do
			local rock = rockData.part
			local basePos = rockData.basePos
			local height = 3 + math.sin(i + tick()*5)
			local targetPos = basePos + Vector3.new(0, height, 0)
			rock.CFrame = rock.CFrame:Lerp(CFrame.new(targetPos), 0.15)
		end
		task.wait()
	end

	local dir = targetPos and (targetPos - root.Position).Unit or root.CFrame.LookVector
	for _, rockData in pairs(rocks) do
		local rock = rockData.part
		rock.Anchored = false
		rock.CanCollide = true

		local bv = Instance.new("BodyVelocity")
		bv.Velocity = dir * 100 + Vector3.new(0,10,0)
		bv.MaxForce = Vector3.new(1e5,1e5,1e5)
		bv.Parent = rock
		game.Debris:AddItem(bv, 0.55)

		local hitAlready = false
		rock.Touched:Connect(function(hit)
			if hitAlready then return end
			if not hit:IsDescendantOf(this._humObj.Hum.Parent) then
				hitAlready = true

				destruction.Sphere(nil, rock.Position, 4, 2.5 ,Vector3.new(0,0,0))

				for j = 1, math.random(3,6) do
					local frag = Instance.new("Part")
					frag.Size = Vector3.new(0.5,0.5,0.5)
					frag.Position = rock.Position + Vector3.new(math.random(), math.random(), math.random())
					frag.Anchored = false
					frag.CanCollide = true
					frag.Material = rock.Material
					frag.Color = rock.Color
					frag.Parent = workspace

					local fv = Instance.new("BodyVelocity")
					fv.Velocity = Vector3.new(math.random(-5,5), math.random(5,10), math.random(-5,5))
					fv.MaxForce = Vector3.new(1e5,1e5,1e5)
					fv.Parent = frag
					game.Debris:AddItem(frag, 3)
				end

				rock:Destroy()
			end
		end)
	end

	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox

	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(8,8,8)
	local _, hits	   = this:hitbox(hitboxOffset, hitboxSize)

	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt),
		dmg      = 20,
		stun     = 1,
		posMult  = 3,
		parryH   = -0.04,
		onHit    = function(attack, source)
			local eroot = attack.enemyEntity.HRootPart
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("strpunch", eroot)
		end,
	}

	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(dmgTbl, enemy, hurtbox.CFrame.LookVector)

		local newkb = this:knockback(attack.atkDir*9 + Vector3.new(0,5,0), 0.1, false, -1)
		attack.knockback = newkb

		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir*10)
		end
	end

	humObj.canAtkThreshold = tick() + 0.24
	this:endLag(0.1)
end

function module.use(self:myself, targetPos: Vector3)
	return baseClass.use(self, function(self)
		useFunc(self, targetPos)
	end)
end

return table.freeze(module)