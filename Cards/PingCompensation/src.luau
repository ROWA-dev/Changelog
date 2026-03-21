--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	-- my own stuff here
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	-- my own stuff here
	
	if humObj.plrObj == nil then
		error("ping compensation failed because no plrObj is linked to this HumObj")
		--return self
	end
	
	self:addConnection(
		humObj.beforeAttacked:Connect(function(atk)
			local plrObj = humObj.plrObj
			if plrObj == nil then return end
		
			local stepper = game:GetService("RunService").Heartbeat
			local endt = tick() + plrObj.ping.Value*0.9 -- weaken ping comp
			
			--[[if humObj.attacking.Value == true and humObj:canAttack() == true and atk.dmgTbl and atk.dmgTbl.stunMeOnParried ~= 0 then
				if humObj.isParry and (humObj:isParry(atk) or humObj:isDodge(atk)) then
				else
					humObj.stopW = true
				end
				--humObj.stopW = true
				--humObj.canAtkThreshold = math.max(humObj.canAtkThreshold, endt)
			end]]


			while humObj and humObj.isParry and tick() < endt do -- PING COMPENSATION
				if humObj:isParry(atk) or humObj:isDodge(atk) or humObj.attacking.Value == true then
					return
				end
				stepper:Wait()
			end
		end),
		"pingComp"
	)
	
	
	return self
end

function module.destroy(self:myself)
	-- destroy my own stuff here
	self:remConnection("pingComp")
	baseClass.destroy(self)
end

return table.freeze(module)
