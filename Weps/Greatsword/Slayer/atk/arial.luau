--!strict
--[[ Slayer arial - rowa1's DOWNSLAM (Main `typ == 4 or 5`, Anims.Arial).

	rowa1: 3s gate (`lastArial + 3`), an upward impulse of (0,20,0)*mass,
	then MiniDash forward -- 38 for typ 4, 30 for typ 5 -- Hold.heavySwung
	up front, Hold.Swing1 at pitch 1.2 partway, then Damage(6) = `gsM2` with
	Knockback (0,-20,0) + look*2.

	!! THE DECLARED WINDUP IS A LIE AGAIN. `Attacking.Time` says 0.5*AtkRate;
	the real waits are 0.3 + 0.3 = 0.6 base. S5 note 7g -- ported the waits.
	Slayer lies about its windup in TWO of its four attacks (this and the
	heavy's 1.4-vs-1.0), so do not trust that field anywhere in this weapon.

	THE KNOCKBACK IS THE MOVE. `(0,-20,0)` drives the victim into the floor;
	that is what makes this a slam rather than a jumping swing. It needs the
	atkCB hook, which `arial` did not have -- it was added (matching the one
	`sprint` already had) rather than dropping the knockback.

	NOT PORTED: rowa1 dashes further on typ 4 than typ 5 (38 vs 30). rowa2
	routes both through arialAtk and there is no second variant to branch on,
	so this takes the typ 5 number. ]]
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp&any): wepType.atkResult
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox
	local hold = this._model and this._model:FindFirstChild("Hold")

	local function indicator()
		this:indicateAtk()
		local s = hold and hold:FindFirstChild("heavySwung")
		if s and s:IsA("Sound") then s:Play() end

		task.delay(this:scaledTime(0.3), function()
			if this._humObj == nil or this._humObj:inStun() then return end
			local sw = hold and hold:FindFirstChild("Swing1")
			if sw and sw:IsA("Sound") then
				sw.Pitch = 1.2
				sw:Play()
			end
		end)
	end

	--- rowa1 Knockback (0,-20,0) + look*2 -> S7 rule 9, K * 0.6.
	local function slamDown(attack)
		attack.knockback = this:knockback(
			Vector3.new(0, -12, 0) + hurtbox.CFrame.LookVector*1.2, 0.3)
	end

	return this.basicAtks.arial(
		this,
		script.arial, -- anim
		dmgConfig.downSlam, -- dmgtbl
		0.58, -- windup BASE (real waits 0.3 + 0.3, NOT the declared 0.5)
		12, -- force. rowa1 MiniDash 30 flat; rowa2 bodyForce decays.
		0.6, -- force duration
		CFrame.new(0, -2, -5), -- hitboxoffset
		--- +2 per axis over the rowa1 translation (was 7,7,7.5). See m1.
		Vector3.new(9, 9, 9.5), -- hitbox sz
		indicator,
		0.08, -- fadetime
		1,    -- weight
		1,    -- speed
		slamDown
	)
end
