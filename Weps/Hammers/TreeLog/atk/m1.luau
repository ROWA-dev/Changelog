--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)


return function(this:wepBase.myself): wepBase.atkResult
	local function indicator()
		this:indicateAtk()
	end
	
	local atkCB = function(atk:any)
		local lookVec = atk.myEntity.HRootPart.CFrame.LookVector
		atk.knockback = this:knockback(lookVec*12, 0.1)
	end
	
	return this.basicAtks.m1(
		this,
		script, -- animsParent
		3, -- m1CycleCount
		dmgConfig.m1,
		0.9, -- windup
		CFrame.new(0,0,-6), -- hitboxoffset
		Vector3.new(10,8,10), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		0.6, -- speed
		0.1, -- endlag
		atkCB
	)
end