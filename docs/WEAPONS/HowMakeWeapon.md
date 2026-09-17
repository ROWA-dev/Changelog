# HowMakeWeapon — the 5-minute version

*(index: parent `ServerStorage/README.md/WEAPONS.md`)*

Cookbook. Every rule here has a reason and the reason is in WEAPONS.md —
this file is just the order you do things in. Copy the closest existing weapon
if it is closer than this.

## 1. Put the ModuleScript in the right place

Under a **family** (`Light/Fists`, `Medium/Swords`, `Heavy/GreatAxe`...), never
directly under `Light`/`Medium`/`Heavy`. The family is where your block, parry
and idle animations already live, and the weight class is where your `req` and
`postureGain` already live. Parenting one layer too high loses both.

Children it owns: `Model`, `dmgConfig.luau`, `attack.luau`.

## 2. Copy this

```lua
--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {}

local module = {
	Name = "myWeapon",                         -- == script.Name, lowercase
	idleAnim = script:WaitForChild("idle"),    -- only if it overrides the family's
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	-- ONE CLONE PER INSTANCE, here and never in :wield
	local model = script.Model:Clone()
	self._model = model
	self._trail = model:WaitForChild("Trail1")
	return self
end

function module.destroy(self:myself)
	if self._model then self._model:Destroy() end
	baseWep.destroy(self)
end

module.attack = require(script.attack)

return table.freeze(module)
```

That is a complete weapon. `req`, `postureGain`, `locomotionProfile`,
`onParried` and the block/parry anims all arrive by inheritance — **declare none
of them** unless this weapon is genuinely different.

## 3. Weld it, if it has a model

Override `:wield()` to point the model's Motor6D at `Right Arm`, and
`:unequip()` to park the model back under `script`. End both with
`baseWep.wield(self)` / `baseWep.unequip(self)`.

`:wield` is the **only** weld impl — `:holdOut()` re-runs it for the held pose.
Never write a second one.

Want a back pose? Give the model a Motor6D named `strap` and flip it in
`:unwield()`. No Motor6D, no back pose, and that is fine.

## 4. `dmgConfig.luau`

```lua
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)
local weighEnum, dmgFlag = dmgUtils.weighEnum, dmgUtils.dmgFlags

type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1 = {
		weight  = weighEnum.Medium,                            -- Light/Medium/Heavy
		type    = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),  -- by NAME, never a bit value
		dmg     = 10,
		stun    = 0.66,
		posMult = 1,                                           -- posture. NEVER nil
		onHit   = require(script.slash),                       -- impact VFX/sound child
	},
}

deepFreeze(config)
return config
```

Need a plain off-hand punch? `WepBase/dmgConfig` already has `punch`. Do not
copy one in.

## 5. `attack.luau` — the dispatcher

```lua
--!strict
local atkTypeEnums = require(game.ServerStorage.ROWA.Weps.Utils.atkTypeEnums)
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)

type atkFormat = {[any]: (self:wepBase.myself)->()}
local attacks:atkFormat = {
	[atkTypeEnums.m1] = require(script.m1),
}

return function(self:wepBase.myself, atkType:number)
	wepBase.attack(self, atkType, attacks[atkType])
end
```

Map only what you wrote. Anything you leave out falls through to
`defaultAttacks`, which no-ops on what it does not know — so a weapon with just
`m1` is a valid weapon.

## 6. `attack/m1.luau` — let the helper do it

Put your `swing1..swingN` Animations under this script, then:

```lua
--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any): wepBase.atkResult
	local function indicator()
		this:indicateAtk()          -- blade shine, or your own telegraph
	end

	return this.basicAtks.m1(
		this,
		script,                     -- animsParent, holds swing1..swingN
		5,                          -- m1CycleCount, match the anim count
		dmgConfig.m1,
		0.38,                       -- windup
		CFrame.new(0, 0, -2),       -- hitbox offset
		Vector3.new(5, 6, 5),       -- hitbox size
		indicator
	)
end
```

Only hand-roll a swing when the helper genuinely cannot express it. When you do,
the shape is windup -> `feintWait` -> `hitbox` -> `makeAtk` -> `executeAttack` ->
`endLag`, and **`feintWait` returns true when the player CANCELLED** — that
branch owes you cleanup: stop the anim, Debris the VFX, remove every
walkSpeed/atkRate mod. Return `true` when a hit landed.

## 7. Register it

Append to `wepList` in `ROWA/Weps.luau` with a **new id at the end**. Ids are
persisted on saved items: never renumber, never reuse. Unregistered is a valid
state while you iterate — `getWepClass` just errors on it, so require the module
directly until you are ready.

## 8. Before you call it done

- Model cloned in `.new()`, destroyed in `:destroy()`
- `:wield` is your only weld; `:holdOut` is not overridden
- `dmgConfig` is `deepFreeze`d, `posMult` set on every entry
- `return table.freeze(module)`
- You added **no** `req`, `onParried` or `WepType` unless you meant it
