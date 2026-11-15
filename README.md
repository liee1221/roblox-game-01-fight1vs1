# Fight 1vs1

A 2D stick-arena fighting game for Roblox: pick your weapon, pick a level, and
duel the AI fighter in the arena until one of you goes down.

**Battle 1v1 with your signature weapon.**

## How it plays

- **Start screen** — START takes you to level select, PANDUAN (guide) explains
  the controls.
- **Pick a level** — 5 levels, each a tougher AI opponent. Level 1 is unlocked
  from the start; beating a level unlocks the next.
- **Pick a weapon** — Katana (fast, long reach), Palu / Hammer (heavy hits),
  Tombak / Spear (balanced). Each weapon has its own ultimate attack.
- **Fight!** — side-view 2D combat in the arena. Light and heavy attacks,
  block, counter, and an ultimate meter that charges as you land hits. Fill
  it and unleash your weapon's ultimate: BLADE RUSH, EARTHQUAKE, or the
  spear's finisher. Fall out of the arena and you lose.
- **Win or lose** — the end screen shows Victory or Defeat and sends you back
  to level select to try again or climb to the next level.

## The code

- `src/server/MainGame.server.luau` — the whole match on the server: levels,
  AI opponent, combat, damage, knockback, block/counter windows, ultimates,
  win/lose and the fall-out-of-arena watchdog.
- `src/client/FightingClient.client.luau` — the 2D side-view camera, menus
  (main menu, guide, level select, end screen), keyboard + button input, and
  the HUD (HP bars, ultimate meter, weapon display).
- `src/shared/GameConfig.luau` — the shared config: the three weapons, their
  attacks, and the five level definitions.

## Play it

https://www.roblox.com/games/90103679709497 — published Public as "Fight 1vs1".
