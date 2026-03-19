--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Clap"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local function getNear(Root)
	local found, gdist = nil,40
	for _,v in pairs(workspace.Entities:GetChildren()) do
		if v and v:FindFirstChild("hurtbox") and v.Parent then
			local hum = v:FindFirstChild("Humanoid")
			local vRoot = v.hurtbox
			local vdist = (v.hurtbox.Position - Root.Position).Magnitude
			if Root~=vRoot and hum and hum.Health > 0 and vdist < gdist then
				gdist = vdist
				found = vRoot
			end
		end
	end
	return found, gdist
end

local function useFunc(this:myself)
	local cooldownID = "clap"
	if this:canTriggerCD(cooldownID) ~= true then return end
	this:triggerCD(cooldownID, 6)
	
	local humObj = this._humObj
	local root:any = humObj.HurtBox
	local found,dist = getNear(root)
	if found == nil then return end
	
	humObj.dodgeThreshold = tick() + 0.2
	
	local rcf = root.CFrame
	root.Parent:SetPrimaryPartCFrame(found.CFrame)
	found.Parent:SetPrimaryPartCFrame(rcf)
	
	local fplr = game.Players:FindFirstChild(found.Parent.Name)
	local lplr = game.Players:FindFirstChild(root.Parent.Name)
	if fplr then
		game.ReplicatedStorage.RemoteEvents.VFX:FireClient(fplr, "clap", root)
	end
	game.ReplicatedStorage.RemoteEvents.VFX:FireClient(lplr, "clap",root)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
