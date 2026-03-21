# Changelog Guidelines
This file contains guidelines for editing the [changelog] for the purpose of standardizing a changelog format.

## Version
The version and title should be in the same second-level heading using the following format:
` [VERSION] - [UPDATE NAME] `

Here is an example:
## 1.1 - The Swap Ends Here
## Changes
The changes made by an update can be organized and formatted in three different ways:

1. Added
2. Fixed
3. Removed

If there is no changes in a category, do not add that category to the changes.

Here is an example:
### Added ✅
(Added would not be in the change but I added it for example sake)
### Changes 🛠️
- Removed ability to unequip weapons during attack
  - This fixes crit cooldown swapping by proxy
- Blocking is now angle and position based
- Barrage stops if parrying victim attacks user

### Removed ❌
(Removed would not be in the change but I added it for example sake)

Finally, the date.

Time should be formatted like this: `<sub>YYYY-MM-DD</sub>` and placed at the bottom of the page with a line break (`<br>`).

Example:

`<br><sub>2026-03-20</sub>` results in

<br><sub>2026-03-20</sub>

[Changelog]: ./CHANGELOG.md