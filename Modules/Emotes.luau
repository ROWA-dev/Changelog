--!strict
export type emote = {
	name: string,
	module: ModuleScript,
}

type elType = {
	[number]: emote
}

local manifold = script
local emoteList:elType = {
	[1] = {
		name = "Fraud",
		module = manifold.StayInPlace.Fraud,
	},
	[2] = {
		name = "Flex",
		module = manifold.StayInPlace.Flex,
	},
	[3] = {
		name = "Selfie",
		module = manifold.Camera,
	},
	[4] = {
		name = "Phone",
		module = manifold.Phone,
	},
	[5] = {
		name = "Sherbet",
		module = manifold.StayInPlace.Sherbet,
	},
	[6] = {
		name = "Piano",
		module = manifold.Piano,
	},
	[7] = {
		name = "Scary", -- ts ass
		module = manifold.StayInPlace.Scary,
	}
}
table.freeze(emoteList)

--


local module = {
}

function module.isValidId(id:any): boolean
	return emoteList[id] ~= nil
end

-- ARRAY of {id, name}, sorted, NEVER keyed by id: retiring an emote leaves a gap
-- and a gapped numeric table does not survive a remote (same reason containers
-- use array-of-pairs, DOC_DATASTORE 17). Built once, shared. NAMES ONLY, so the
-- picker requires no emote module and Phone's remote hook stays cold.
local catalogue:{{any}}
function module.catalogue(): {{any}}
	if catalogue == nil then
		local built = {}
		for id, emote in pairs(emoteList) do
			table.insert(built, {id, emote.name})
		end
		table.sort(built, function(a, b) return a[1] < b[1] end)
		catalogue = table.freeze(built)
	end
	return catalogue
end

function module.getEmoteClass(id:number)
	local emote = emoteList[id]

	if emote == nil then
		error("emote_id["..tostring(id).."] does not exist")
	end
	
	local sreq:any = require
	local emoteClass = sreq(emote.module)
	return emoteClass
end

function module.getEmoteName(id:number): string?
	local emote = emoteList[id]
	return emote and emote.name
end

local Humanoids = require(game.ServerScriptService.Entities)
function module.playEmote(id:number, hum:Humanoid)
	if module.isValidId(id) == false then return end -- ids come from the client
	local humObj = Humanoids.Get(hum)
	if humObj == nil or humObj.isActive ~= true then return end
	if humObj:inStun() == true or humObj.attacking.Value == true then return end
	
	local animator = hum:FindFirstChild("Animator")
	
	humObj:StopEmote() -- stop previous
	
	-- weapon put-away/give-back is owned by EmoteBase.new/.destroy so that every
	-- emote teardown path restores it. UnwieldWeapon() here orphaned the weapon.
	local emoteClass = module.getEmoteClass(id)
	local emoteInstance = emoteClass.new(animator)
	humObj._emoteInstance = emoteInstance -- register BEFORE Play: an emote that
	emoteInstance:Play()                  -- ends inside Play must find itself here
	return
end

function module.plrPlayEmote(plr:Player, id:number)
	if plr.Character == nil then
		return
	end
	
	local hum:Humanoid = plr.Character:FindFirstChild("Humanoid")::any
	if hum == nil then
		return
	end
	
	return module.playEmote(id, hum)
end

return module
