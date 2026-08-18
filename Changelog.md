### ⚠️ This is a community-maintained changelog and may be updated slower than [README.md].
For any contributors wanting to help push changes faster, check the [guidelines].

# Changelog
## 1.6.0 - Port ROWA

> Note: This update I changed the version structuring a whole lot. Nobody will know though. 🤫

> Note: Air was lazy so even though it looks like there's a lot of new abilties it's just because he ported them from ROWA.

### Added ✅
- New ability: Blight
- New ability: Bolt Punch
- New ability: Cero
- New ability: Flame Dance
- New ability: Huozi
- New ability: Ice Bash
- New ability: Ice Beam
- New ability: Jolt Kick
- New ability: Lightning
- New ability: Piercing Stab
- New ability: Power Strike
- New ability: Rend
- New ability: Storm Up
- New ability: Stronger Left
- New ability: Tendrils
- New ability: Zoltraak

### Changes 🛠️
- Axe name changed to Stark Axe
- Barrage damage increased (2.5 -> 3 per hit)

<br><sub>2026-08-17</sub>

## 1.5.3 - What To Name This Version? Gubby Glider

### Changes 🛠️
- Barrage can now be parried mid stun
- Glider physics fixed
- Added unique Axe M1s

<br><sub>2026-08-16</sub>

## 1.5.2 - Hyperarmor Hotfix

### Changes 🛠️
- Hyperarmor math changed

<br><sub>2026-08-10</sub>

## 1.5.1 - Hyperarmor Patch

### Changes 🛠️
- Hyperarmor is now applied to the end of heavy weapon M1s rather than the start to prevent annoying wakeup interactions
- Fixed rare infinite slide bug
- Ingame changelog now correctly shows markdown (it's readable)

<br><sub>2026-08-10</sub>

## 1.5.0 - The Birth Of Hyperarmor

### Added ✅
- Heavy weapons now have hyperarmor at the start of an M1
  - The duration of said hyperarmor is determined by the windup length of the M1

### Changes 🛠️
- Barrage windup decreased (0.6s -> 0.5s)

<br><sub>2026-08-08</sub>

## 1.4.1 - The Refactoring
### Added ✅
- New card: Ability Haste (testing card)
- Added VFX for Axe heavy attack
- Debug stuff for development

### Changes 🛠️
- Hitbox refactor thing; hits are entities now
- Speed boosts are stronger
- Some sneaky client and server changes because of the refactor that I don't understand

<br><sub>2026-08-07</sub>

## 1.4.0 - The Two Month Wait
### Added ✅
- New ability: Fulminate

### Changes 🛠️
- Fire Stab burn damage decreased (6 -> 3)
- Blaze is now limited
- Sprint speed increased (12 -> 14)
- Cannot dash for 0.3s after attacking
- Cannot dash for 0.1s after a feint
- Fixed nasty hitbox bug
- Axe heavy attack movement no longer sends you back I think
- Hammer heavy attack hitbox reduced (-2 studs)
- Claymore M1 hitbox reduced (-0.5 studs)

<br><sub>2026-07-25</sub>

## 1.3.4 - Status Effects
### Added ✅
- Implemented base status effects class for entities
- Fire Stab now applies burn status
- Dagger crit now has an indicator

<br><sub>2026-05-28</sub>

## 1.3.3 - Base Progression
### Added ✅
- Added weapon and elemental stats serverside base
- Leveling up gives stat points
- Points can be allocated
- UI displays stats

### Changes 🛠️
- Tree M1s do more knockback
- Tree heavy attack damage increased (32 > 50)
- Tree heavy attack posture damage increased (x5)

<br><sub>2026-05-24</sub>

## 1.3.2 - More Refactoring
### Added ✅
- Safer and better fast replication during combat or whatever that means
- Slight client side prediction to mitigate unnoticeable loss

### Changes 🛠️
- Parry is cancelled on dash
  - Parrying against Barrage, charged Katana heavy attack, or any multi-hit moves will cancel parry upon dodging away so good luck
- Fist heavy attack movement force increased by 10%

<br><sub>2026-05-24</sub>

## 1.3.1 - Progression Preparation
### Added ✅
- More admin commands: /giveexp, /wipeslot
- Updated UI to include EXP and level

### Changes 🛠️
- Dagger heavy attack range decreased (-1 stud)
- Dagger heavy attack damage increased (5 -> 6)
- Refactored more stuff in preparation for progression

<br><sub>2026-05-21</sub>

## 1.3.0 - Dagger? I Barely Know Her!
### Added ✅
- Slide jump has momentum now
- New weapon: Dagger (from ROWA)

### Changes 🛠️
- Barrage stun increased (0.5s -> 0.6s)
- Rapier heavy attack endlag decreased (0.4s -> 0.2s)

<br><sub>2026-05-12</sub>

## 1.2.0 - ROWA 2 Might Be Back
### Added ✅
- New ability: Earth Shot

### Changes 🛠️
- Longsword heavy attack VFX changed
- Vaulted Longsword (LOL)
- Refactored destruction

<br><sub>2026-05-10</sub>

## 1.1.5 - Some Small Changes
### Changes 🛠️
- Mace heavy attack damage decreased (24 -> 20)
- Spear M1 damage decreased (13 -> 12)
- Bo Staff flourish end damage decreased (9 -> 6)
- Bo Staff heavy attack end damage decreased (9 -> 6)
- Unvaulted Longsword
- Fixed memory leak from Speed On Parry card
- Attacking while dashing now cancels dash

<br><sub>2026-04-08</sub>

## 1.1.4 - Grabbing Guts
### Changes 🛠️
- Rah heavy attack hitbox reduced (-0.5 studs)
- Vise heavy attack hitbox reduced (-0.5 studs)
- Vise heavy attack hitbox offset reduced (-0.5 studs)
- Bo Staff heavy attack hitbox reduced (-0.5 studs)
- Bo Staff M1 hitbox offset reduced (-4.5 studs -> -2.5 studs)

<br><sub>2026-03-25</sub>

## 1.1.3 - ROWA Sunset
### Added ✅
- /time command
- WIP character stat UI

### Changes 🛠️
- Fixed memory leaks
- Slot optimization; Slot data is wiped
  - Wipe is not significant because game has no progression at this point

<br><sub>2026-03-25</sub>

## 1.1.2 - The Much Needed Rah Nerf
### Added ✅
- Barrage now hides arms while punching

### Changes 🛠️
- Rah heavy attack damage decreased (24 -> 20)
- Rah heavy attack cooldown increased (3s -> 4s)

<br><sub>2026-03-23</sub>

## 1.1.1 - Minimal Changes
### Changes 🛠️
- Feinting Fire Stab now puts the move on half cooldown after you use it
  - This is to stop people from feinting > using fire stab > using fire stab again
- ToshiCounter punish window increased (0.5s -> 0.7s)
- Heaven's Equalizer (new player buff) now scales based on number of player's wins instead of being a flat parry window buff
- Rah heavy attack range decreased (3 studs -> 2.5 studs)

<br><sub>2026-03-23</sub>

## 1.1.0 - The Gutter

### Changes 🛠️
- Strong Left parry window increased again (by 0.02s)
- Canine heavy attack damage decreased (20 -> 18)
- Rah heavy attack damage decreased (27 -> 24)
- Rapier M1 hitbox reduced (-0.5 studs)
- Spear M1 hitbox reduced (-1 stud)
- Katana charged heavy attack damage decreased (54 -> 45)
- Barrage has endlag on miss (0.2s)
- Bunny eating animation fixed 🥕

<br><sub>2026-03-22</sub>

## 1.0.1 - Strong Left Too OP

### Added ✅
- New ability: Fire Stab

### Changes 🛠️
- Strong Left is now a bit easier to parry (by 0.02s)

<br><sub>2026-03-21</sub>

## 1.0.0 - The Swap Ends Here

> Note: Although this update is the first in the changelog, ROWA 2 has been updated somewhat consistently since 2025-08-21.

### Changes 🛠️
- Removed ability to unequip weapons during attack
  - This fixes crit cooldown swapping by proxy
- Blocking is now angle and position based
- Barrage stops if parrying victim attacks user

<br><sub>2026-03-20</sub>

[Guidelines]: ./Guidelines.md
[README.md]: ./README.md