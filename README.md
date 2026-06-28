# GodotSchmovementThing
Idk messing around in game dev again for fun.

## Concept
An attempt to combine Fire Emblem-style tactics (story, characters, positioning, growing attached to units over a campaign) with movement-skill-based combat resolution, inspired by CS surf/momentum movement and Smash Melee movement tech. The pitch: keep FE's strategic layer, but replace its slow turn-by-turn combat math with a real-time movement challenge.

## Core loop
- **Tactics layer** (not yet built): plan positioning and who-attacks-whom for the turn, no time pressure, full information.
- **Resolution layer**: instead of resolving each attack separately, one continuous movement-skill run per turn covers everything queued that turn.
- **Stakes split**: the run's pace/cleanliness drives a shared hit-chance modifier for everyone acting that turn. Optional per-unit "crit coins" sit along harder alternate lines through the course — skippable without penalty, there for skill expression, not to gate basic competence.
- **Difficulty curve**: coins start easy/forgiving, become genuine skill showcases on higher difficulties. Exact tuning is intentionally deferred until the core loop itself is proven fun.
- **Stat tie-in (tentative)**: enemy stats shape overall course harshness; ally stats shape how forgiving their own coin is — keeps FE-style leveling meaningful alongside player skill.
- **Identity split**: characters (not weapons) are what you level up and get attached to. Sentient weapons supply each character's movement kit and are framed as what you're piloting during a "hacking" abstraction of the run — decouples the course from needing to match each battlefield's literal geography, and keeps attachment on the person, not the tool.

## Current prototype status
The repo right now is a single-player movement sandbox used to find and validate the resolution-layer mechanic before any tactics/turn system exists. No characters, weapons, enemies, or combat yet — just the player controller (`Schmove.gd`) and one test level.

Movement kit (deliberately moved away from a literal CS-surf clone toward a more standard action-game kit):
- Grounded walk + air strafing (CS-style: turning into a held direction while airborne builds speed; holding a static direction does not).
- Jump + one double jump (refills on landing).
- Dash (one use in air per airtime, reusable on cooldown on ground) — composes with existing momentum rather than resetting it.
- Ground slide: a timed, cooldown-gated window where speed above base walk speed bleeds off gradually (and can be steered) instead of snapping back instantly — this is what makes a dash on the ground actually go somewhere.
- Ramp bounce: per-surface, opt-in bounciness (`RampSurface.gd`) — reflects velocity off steep surfaces while airborne, scaled by a per-ramp `bounce` value so level builders choose which surfaces are bouncy.
- Fall-respawn: falling below a world-Y threshold resets you to the start.

Validated with a small vertical slice standing in for the eventual tactics layer's stakes: a speedrun-style live timer per attempt, plus a hand-placed `Obstacle.gd` (adds time on touch) and `Coin.gd` (subtracts time on pickup, resets each attempt) standing in for "got hit" / "crit" until real combat exists. Confirmed the core tension — detour for the coin vs. play it safe past the obstacle, under time pressure — is fun and produces a real, felt skill ceiling (casual completion ~10-15s, optimized play under 7s on the current test level).

## Next steps
Not yet built: enemies/obstacle variety tied to enemy identity, the tactics/turn layer, characters and weapons, and the "hacking" presentation layer. The movement kit itself is considered solid for now and mostly needs new levels/obstacle types rather than further core tuning.
