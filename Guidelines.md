# Changelog Guidelines
This file contains guidelines for editing the [changelog] for the purpose of standardizing a changelog format.

## Version
The version and title should be in the same second-level heading using the following format:
` [VERSION] - [UPDATE NAME] `

For determining version number, use this formula:
` [major].[minor].[patch] `

**Major** - Major changes to the game such as a transition from alpha to beta. This could also be used with major additions such as game expansions. As a rule of thumb, if there are too many changes in one update that the jump from the previous version to the new version feels major, increment the major digit. Comparable to a... major update.

**Minor** - Large bugfixes, feature updates, etc. Comparable to a weekly update.

**Patch** - Small bugfixes, minor alterations, some nerfs, etc. Comparable to a balance patch (duh).

When incrementing one of these digits, the lower tier digits should reset to 0. To illustrate, if I were to classify the incoming version as a minor update, I would set the patch digit to 0 (1.5.**3** -> 1.6.**0**).

If there is an update to the repository but it doesn't affect the game, do not include as an update. Such is the case for the times when Air added content that already existed in the game to the repository for consistency.

Finally, here is an example:
## 1.0.0 - The Swap Ends Here
## Changes
The changes made by an update can be organized and formatted in three different ways:

1. Added
2. Fixed
3. Removed

If there is no changes in a category, do not add that category to the changes.

Here is an example:
### Added ✅
(Added was not in the version but I added it to show proper formatting)
### Changes 🛠️
- Removed ability to unequip weapons during attack
  - This fixes crit cooldown swapping by proxy
- Blocking is now angle and position based
- Barrage stops if parrying victim attacks user

### Removed ❌
(Removed was not in the version but I added it to show proper formatting)

Finally, the date.

Time should be formatted like this: `<sub>YYYY-MM-DD</sub>` and placed at the bottom of the page with a line break (`<br>`).

Example:

`<br><sub>2026-03-20</sub>` results in

<br><sub>2026-03-20</sub>

[Changelog]: ./CHANGELOG.md