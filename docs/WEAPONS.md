# WEAPONS — ServerStorage/ROWA/Weps

*(index: parent `ServerStorage/README.md`)*

A weapon is a class instance owned by a HumObj and swung through
`wep:attack(atkTypeEnum)`. This file is the framework. Feel numbers are
COMBAT.md, footguns are GOTCHAS.md, and neither is repeated here.

**Just want to build one? → `WEAPONS.md/HowMakeWeapon.md`.** That is the
copy-paste recipe; this is the reference it points at.

## 1. Tree

```
ROWA/Weps.luau            REGISTRY: id -> weapon ModuleScript
ROWA/Weps/
  WepBase.luau            the weapon half of the shared attacker base
    types.luau            the `myself` type
    dmgConfig.luau        fallback dmg tables + the shared off-hand punch
    defaultAttacks.luau   atkTypeEnum -> impl, used when a weapon maps nothing
    attackHelpers/        parameterised m1 / sprint / arial, reached via basicAtks
    indicateAtk, downSlam, preloadAnims, block, parry
  Light / Medium / Heavy  WEIGHT CLASS, one file each
    <family>.luau         + the block/parry/idle Animations its weapons share
      <weapon>.luau       + Model, dmgConfig.luau, attack/
  Utils/                  atkTypeEnums, feintwait, Template
  vaulted/                retired, kept for reference
```

Weight and family files are inherited bases, never concrete weapons. The roster
is `wepList` and the tree itself — **it is not mirrored here on purpose**, a
copied roster is wrong within two weapons.

## 2. Registry — `ROWA/Weps.luau`

| call | does |
|---|---|
| `wepList` | frozen `{id -> ModuleScript}`. **The** roster; enumerate off this |
| `getWepClass(id)` | class table, **errors** on an unknown id |
| `newWep(id)` | fresh instance |
| `isClass(wep, module)` | is `wep` that class at ANY depth? Walks the metatable chain, which IS the class chain. Pass a **family** to catch every weapon under it |

Ids are **persisted on saved items: append only**, never renumber, never reuse.

A module can sit in the tree without being in `wepList`. `getWepClass` errors on
those — require the module directly, or register it.

`isClass` is what backs an ability's `notWepClass` (ABILITIES.md §9). It is the
only real family test; see `WepType` below.

## 3. The class chain

`WepBase -> weight -> family -> weapon`, each layer
`setmetatable(module, { __index = parent })`. Statics resolve **up** that chain,
so the layer you declare one on is its blast radius.

| layer | seeds |
|---|---|
| weight (`Light`/`Medium`/`Heavy`) | `req`, `postureGain`, `locomotionProfile`, `onParried`, the m1-cycle fields |
| family | `WepType`, `blockAnim`/`parryAnim`/`idleAnim` + the Animation children they name |
| weapon | `Name`, its `Model`, `dmgConfig`, `attack` |

Any layer may override anything above it — the table is where each is *seeded*,
not where it is allowed. `postureGain` in particular is retuned per family and
per weapon.

**`onParried` is already implemented on all three weight classes**, so anything
parented under a family inherits one. WepBase's `warn("must be implemented")` is
unreachable through the normal tree; do not add a per-weapon override to silence
a warn you will never see.

`WepType` is declared and **nothing reads it** — it is legibility only.

### `req` — the wield requirement

Seeded on the WEIGHT classes (`Light {lht=2}`, `Medium {med=2}`, `Heavy {hvy=2}`).
Tune there, not per weapon. Shape: `ReplicatedStorage/Modules/Requirements`,
shared with Cards, and not restated here.

`req = {}` is FREE. `req = nil` is **not** — it inherits the family's through
`__index`. Fist is the one opt-out, so a fresh character is never locked out of
their own hands.

Enforced **only** in `HumObj:canWield`, i.e. only on the commit. Selecting a
weapon you cannot wield still draws it; it just never becomes usable.

## 4. The four poses

Read before touching wield/unwield. A weapon is in exactly one of these.
`equippedWeapons` is the WIELDED SET (committed, cap `maxWeapons`); `heldWeapon`
is the one drawn but NOT committed.

| pose | is |
|---|---|
| `away` | `_humObj` nil OR model off the body. Not selected |
| `held` | right hand, **inert**, gripped at the model's CENTRE not its handle so it reads as carried. `wielding_weapon` is nil, so every swing path dead-ends — there is no second gate anywhere |
| `holstered` | in the set, not in hand. Whatever that weapon's `:unwield()` does: strap to the Torso if its model has the `holsterJoint` Motor6D, else park it back in its module |
| `active` | right hand + `wielding_weapon == self` + idleTrack + parry/block |

Selecting a weapon ALREADY in the set goes straight to `active`, no click. One
NOT in the set goes to `held`, and M1 promotes it via `HumObj:WieldWeapon` ->
the `req` gate; refusal chats `cannot wield X -- heavy 0 -> 2` via systemMsg.

Both hand poses weld to the SAME Right Arm Motor6D, which is why `WepBase:wield`
evicts held AND active before posing.

## 5. What WepBase adds

`Class/CombatAction.luau` is the shared attacker base — **WepBase and AbilityBase
both inherit it**, so a fix lands once. Its own header lists what is shared and
what stays overridden and why; ABILITIES.md §3 lists the methods. Read either,
not a third copy here.

Subclass constants: `FEINT_CD_ID = "feint"` (weapons **do** gate dashing) and
`KNOCKBACK_USES_CHARSIZE = true`.

`:hitbox` is a one-line wrapper over `Class/HitboxQuery` with the frozen
`WEAPON_HITBOX_OPTS` declared at the top of WepBase: charSize scale, airborne
bonus, `range + 1`, HurtBox→root retry on a miss, and it writes `prevHits`. Every
field carries its own reason in source. Abilities opt out of all four — the
contrast is ABILITIES.md §6.

Lifecycle, the weapon-only half:

| call | does |
|---|---|
| `.new()` | `prevHits = 0` + four AdditiveValues (`atkRateOffset` 0, `atkRate` 1, `range` 0, `knockbackMult` 1). **Clone your model here, never in `:wield`** |
| `:equip(humObj)` | baselines `_baseScale` once then scales to `charSize`, sets `_humObj`, unwields |
| `:wield()` | preloadAnims, evicts the previous active AND held weapon, `setWieldingWeapon(self)`, idle track, block/parry defaults. Honours `_holdOnly` |
| `:holdOut()` | HELD pose. Re-runs the weapon's OWN `:wield()` with `_holdOnly` set, so the state half short-circuits and the grip re-centres. One weld impl, two poses — do **not** write a parallel weld |
| `:unwield()` | HOLSTER, ownership-checked: two weapons can be on the body, so only the one that really holds the slot may clear it |
| `:putAway()` | `:unwield()` + take the model off the character |
| `:stow()` | what the ITEM layer calls: holster if committed, putAway if merely held. Picks for you |
| `:holsterAt(i)` | back-slot offset applied on top of the C0 authored in Studio (captured once into `_strapC0`), indexed by position in `equippedWeapons` |
| `:unequip()` / `:destroy()` | `destroy` destroys all four AdditiveValues; `table.clear` alone leaks their mod lists |

`locomotionProfile` is an inherited numeric id from `Modules/LocomotionProfiles`;
HumObj sends the changed id once to the owner and CharAnims lazily resolves
optional Walk/Sprint assets.

`HumObj:getBlockAnim()` resolves `blockAnimOverride` before the weapon default,
so a card never overwrites a weapon's authored animation.

## 6. Attacks

`:attack(atkTypeEnum, atkFunc?)` is THE entry point.

```
m1 = 1, heavyStart = 2, heavyEnd = 3, uppercut = 4, arialAtk = 5, sprintAtk = 6
```

A weapon sets `module.attack = require(script.attack)`, and that file is a
dispatcher: enum -> impl, then `wepBase.attack(self, atkType, attacks[atkType])`.
An unmapped type passes `nil`, WepBase falls back to `defaultAttacks`, and that
no-ops on anything it does not map either. **Mapping nothing is legal and
silent** — a missing `heavyEnd` is a dead key, not an error.

`self.basicAtks` exposes the parameterised `m1` / `sprint` / `arial` helpers.
They return `hitLanded`, which is the `atkResult` convention: return true when a
hit landed. WepBase itself only reads `prevHits`.

### `:attack` internals

1. asserts `atkFunc` is function|nil, warns + returns if no `_humObj`
2. bails if `attacking.Value` is true or `:canAttack() == false`
3. sets `_atkType` **before** `attacking.Value = true` — Changed fires
   synchronously, so an observer waking on that flag must not read the previous
   swing's type
4. `ChangeBlocking(false)`, enables `_trail` (versioned, so overlapping swings
   don't kill it early)
5. **pcalls** the attack; an error warns with a traceback, it is not a crash
6. on success only, `prevHits == 0` means the swing WHIFFED ->
   `atkRate:SetMod("antiASwing", 0.1)` until 0.4s after the LATEST whiff
   (versioned like the trail, so a second whiff is not cut short by the first)
7. always clears `attacking`; disables the trail 0.4s later if still the latest
   version

Whiffing is what a weapon is punished with. An ability is punished by its
cooldown instead (ABILITIES.md §10).

## 7. Known bad, tracked

- `Light/Rapier/indicateAtk` is a **stale fork** of `WepBase/indicateAtk`, and the
  Rapier family overrides `module.indicateAtk` with it. The base copy grew a size
  ramp and a `bladeTop.Parent:IsA("BasePart")` guard — its comment says a
  mis-parented `Top` used to hard-error and eat the whole swing. The fork has
  neither, so Rapier runs the old one while everything else runs the fixed one.
- `holsterOffset` is a real static that **no weapon sets**; every holstered weapon
  takes the computed fan-out default in `:holsterAt`.
