# Deck Wars

A 3D card battler for Roblox. You walk around a cozy game room, sit down at the Duel Table and fight on a 5x6 tile board with six themed decks (Snack, Junk, Weather, Critter, Spooky and Robo), 69 cards, combos and a bot with three difficulties.

![The duel table](docs/table_preview.png)

## Play it
1. Get the newest place file: **[DeckWars.rbxlx](https://github.com/Nash0723/deck-wars/releases/latest/download/DeckWars.rbxlx)** (it is rebuilt automatically every time something is merged into `main`).
2. Install Roblox Studio, sign in and double-click `DeckWars.rbxlx` (or in Studio: File > Open from File).
3. Press **Play** (F5).

You can also build the file yourself, see "Build it" below.

## Working together
This repo is the real home of the game. Everyone works on their own branch and changes reach `main` through a pull request (PR), so nobody overwrites anybody else's work.

1. **Get the code (once):** `git clone https://github.com/Nash0723/deck-wars.git` and `cd deck-wars`. (Or, in GitHub Desktop: File > Clone repository.)
2. **Start fresh each time:** `git checkout main` and `git pull`, then make a branch for your change: `git checkout -b my-change` (a short name like `new-spooky-card`).
3. **Change things** in the files under `src/` (or the generators, see below). Don't edit the built `.rbxlx`: it is made from these files and is not kept in git.
4. **Build and try it:** `rojo build default.project.json -o DeckWars.rbxlx`, open it in Studio and press Play. If you work with a Claude, it can run the tests too (see "Tests").
5. **Save and share:** `git add -A`, `git commit -m "What I changed"`, `git push -u origin my-change`. GitHub then shows a button to **open a pull request**.
6. **Review and merge:** the other person (or their Claude) looks at the PR, GitHub builds the game and runs the tests on it, and when it's green and you both agree, press **Merge**. Then everyone does step 2 again.

Small tips: keep each PR about one thing, pull `main` often, and if two people change the same lines, GitHub will ask you to pick which version to keep (a "merge conflict"); ask your Claude to sort it out.

**Changing in Studio instead of in files:** if you change a script or the room in Studio, the files in `src/` don't change by themselves. Either copy your script change into the matching file in `src/`, or connect Studio to the files with the Rojo plugin (`rojo serve` + the Rojo plugin in Studio) so they stay in sync. Changes to the room (`Workspace > MenuRoom`) come from `gen_world.py`, so tell your Claude what you changed and it can carry it over.

## Build it
You need [Rojo](https://rojo.space) once: `cargo install rojo --locked` (needs [Rust](https://rustup.rs)), or download it from Rojo's releases page. Then, in this folder:

```
rojo build default.project.json -o DeckWars.rbxlx
```

### Generators
Some files in `src/` are made by Python scripts. Don't edit the made files by hand; change the script and run it again (needs Python 3 and `pip install -r requirements.txt`; the model and room checks also need Rojo installed with cargo, because they read Roblox's API list from it):

| Run this | It makes | From |
| --- | --- | --- |
| `python3 gen_carddata.py` | `src/shared/CardData.luau` | `cards.py` (the card list) and the rules text in `gen_carddata.py` |
| `python3 gen_models.py` | `src/shared/CreatureModelData.luau` | `models_*.py` and `modelkit.py` |
| `python3 gen_world.py` | `src/world/MenuRoom.model.json` | `gen_world.py` |
| `python3 mock_roblox/gen_world_lua.py src/world/MenuRoom.model.json mock_roblox/WorldData.luau` | the room for the simulated Studio | the room file |

`preview/*.py` render rough pictures of the table and models with a small ray tracer (no Roblox needed).

### Tests
The tests run outside Roblox with a small Luau runner in `tools/luaurun` (needs Rust):

```
cargo build --release --manifest-path tools/luaurun/Cargo.toml
tools/luaurun/target/release/luaurun tests/run_tests.luau src/shared                   # rules: 211 checks + 120 bot games, about 1 minute
tools/luaurun/target/release/luaurun -D BAL_GAMES=60 bal/balance.luau src/shared         # deck balance, bot vs bot
tools/luaurun/target/release/luaurun mock_roblox/harness.luau mock_roblox                # plays matches in a simulated Studio, about 8 minutes
tools/luaurun/target/release/luaurun tests/packbrawl_tests.luau src/packbrawl src/shared  # Pack Brawl: odds, casting, every card's fight script, every rig and move
tools/luaurun/target/release/luaurun mock_roblox/pullharness.luau mock_roblox src/shared src/packbrawl  # Pack Brawl in a simulated Studio, about 10 s
```

`-D NAME=VALUE` sets a setting before the script runs: `SOAK_GAMES` for the tests, `BAL_GAMES`, `BAL_DIFF`, `BAL_SEED` and `BAL_FIRSTDRAW` for the balance check.

GitHub runs the rules tests and the Pack Brawl tests and builds both place files for every pull request (`.github/workflows/build.yml`).

## Project layout
| Path | What it is |
| --- | --- |
| `default.project.json` | The Rojo project: where each file goes in the Roblox place, plus the Lighting settings |
| `src/shared/` | ReplicatedStorage > DeckWars: CardData, MatchEngine (all the rules), BotBrain, StarterDecks, Rng, CreatureModelData, CreatureBuilder |
| `src/server/` | ServerScriptService > MatchServer |
| `src/client/` | StarterPlayerScripts > DeckWarsClient (menus, table, animations, camera) |
| `src/world/` | Workspace > MenuRoom (made by `gen_world.py`) |
| `cards.py`, `gen_*.py`, `models_*.py`, `modelkit.py` | Generators (see above) |
| `tests/`, `bal/`, `mock_roblox/`, `tools/luaurun/` | Tests, balance check, the simulated Studio and the Luau runner |
| `pullcinematic.project.json` | The separate Pack Brawl test place (`DeckWars_PullCinematic.rbxlx`) |
| `src/packbrawl/` | ReplicatedStorage > PackBrawl: the pull cinematic (see "Pack Brawl" below) |
| `src/pullserver/` | ServerScriptService > PullServer: rolls every pull (main game and test place) |
| `src/pullclient/` | The test place's Pack Party test panel |
| `assets/sounds/` | Our own Pack Brawl sounds (made by `tools/make_sounds.py`), ready to upload |
| `docs/` | Pictures for this README |

## How to play
- In the menu room, click a station or a button at the bottom, or press **A / ←** and **D / →** to go to the station before or after (it wraps around; on a gamepad the D-pad or bumpers). **S / ↓** (or Backspace, gamepad B) goes back to the room view. The station you're at has its button lit up.
- The **Settings** station (the radio) has: Sound effects and Music volume, Action camera, Camera lean, Screen shake (Off, Low, Full), Table speed (Slow, Normal, Fast), Pack fights (Full, or Quick = always fast-forwarded), Quality (High, or Low = no shadows or glow, for slower devices) and Background blur, plus Reset to defaults. In a match the **⚙ Settings** button opens the same options. Changes apply at once and are saved to your Roblox account.
- Click the Duel Table (or its button). Pick a deck and a bot difficulty, then press "Sit down and play!".
- Each turn you get 1 more energy (up to 8) and draw a card. The first player starts with 4 cards and skips the draw on their very first turn; the second player starts with 5.
- **Play a card:** click it in your hand. Gold tiles show where it can go: creatures go on your back two rows (or next to your Bunny Burrow), and buildings go anywhere in your half. Spells that need a target light up what they can hit.
- **Command a creature:** your creatures that can still act glow green. Click one: blue tiles are where it can walk (1 tile, or 2 if it's Fast), green tiles are friends it can swap places with, and red ones are what it can hit (on the 8 tiles around it, or 2 tiles away if it's Ranged). The buttons under the message are its other commands: **🛡 Defend** (until your next turn it takes 1 less damage and hits back 1 harder) and its family chant (like **✨ Picnic · 2⚡**). A grey chant button tells you why it can't be used right now. When the creature stands in the enemy's half, the enemy hero's pedestal glows red, so click the hero to hit it. New creatures sleep (zZ) for a turn unless they have Zoom.
- A creature can walk first and then attack, defend or chant. After it walks it stays picked, so you can give it its command right away.
- In a fight both creatures hit each other. A Ranged creature hitting from 2 tiles away doesn't get hit back.
- **Big Move:** once you've dealt 10 damage, the READY! button lights up. You can use it once per match.
- Press **END TURN** when you're done. Right-click or press Cancel to stop aiming.
- You win by bringing the enemy hero from 20 health to 0.

| Family | Chant | Energy | What it does |
| --- | --- | --- | --- |
| Snack | Picnic | 2 | Heals itself and your creatures next to it 2 (Snacks get Power, even at full health) |
| Junk | Scrap Toss | 1 | 1 damage to an enemy creature or building up to 2 tiles away |
| Weather | Gust | 1 | Blows an enemy creature up to 2 tiles away 1 tile back and Soaks it. If something is in the way, it takes 1 damage instead |
| Critter | Call a Friend | 2 | A 1/1 Pigeon flies in next to it |
| Spooky | Raise | 2 | Brings back your last creature that popped, next to it, with 1 health. Once per turn. If it pops again, it just fades away |
| Robo | Power Up | 1 | Gets 1 Power (+1 attack, up to 3) |

## Change the speed
| Setting | Where | Default |
| --- | --- | --- |
| Turn length | ServerScriptService > MatchServer, `TURN_SECONDS` | 90 |
| Bot's pause before its turn | MatchServer, `BOT_TURN_START_PAUSE` | 1.5 |
| Bot's pause before each action | MatchServer, `BOT_THINK_SECONDS` | play 2.0, move 1.2, attack 1.4, defend 1.0, chant 1.6 |
| Speed of all table animations | players pick Slow / Normal / Fast in Settings; the numbers are `Settings.Pace` in ReplicatedStorage > DeckWars > Settings | Normal = 1.0 (Slow 1.3, Fast 0.75) |
| Default settings for new players (volumes, action camera, shake, speed...) | ReplicatedStorage > DeckWars > Settings, `Settings.Defaults` | see the file |
| Where the camera sits on your turn and on the bot's turn | DeckWarsClient, `SeatYou` and `SeatOpp` in the `CAMS` list near the top | position, the point it looks at, and the zoom (field of view) |

## Change cards and rules
- Every card's cost, attack, health and text is in ReplicatedStorage > DeckWars > CardData. What a card actually does lives in MatchEngine.
- The combo numbers are near the top of CardData: `PowerMax` (most Power a creature can hold, 3), `SandwichBonus` (1), `SoakBonus` (1), `ZapBonus` (2), `PackMax` (most attack Pack can add, 2), `ScrapMax` (most Scrap on one tile, 3) and `ScrapGain` (+1/+1 per Scrap). `FamilyRules` and `RuleText` hold the help texts.
- Going first: `FirstTurnDraw` in CardData (false = the first player skips their first draw; set it to true to undo that) and `SecondPlayerCard` (a card id to give the second player an extra card).
- Board size and reach are at the top of the card list in CardData: `Cols`, `Rows`, `HomeRows` (your half), `SummonRows` (where creatures appear) and `HeroAttackRows` (how deep in the enemy half a creature must stand to hit the hero).
- Defend and the chants are in CardData too: `DefendArmor`, `DefendCounter`, `RaisedFades` and `Chants` (each family's chant: name, energy cost, amount, range and text). What each chant does is in MatchEngine (`chantWith`).
- The six decks and their blurbs are in StarterDecks.

## Change the lighting
Click **Lighting** in Studio's Explorer. `Ambient` is the overall room brightness (now 0.14, 0.11, 0.10) and `ExposureCompensation` brightens or darkens everything (now -0.2; the last update had 0.25). If the board is too dark on your screen, raise ExposureCompensation a little (try 0). Under Lighting there are **Bloom** (glow), **ColorCorrection** (color and contrast) and **DepthOfField** (soft blur far away). The two table lamps (SpotLights over the board), the fireplace and the room lamps are lights inside Workspace > MenuRoom. The terrain colors are in DeckWarsClient (`TERRAIN_LOOK`), and the creature bases are made in `spawnUnit`.

## Where things are in Studio
| Place | What it is |
| --- | --- |
| ReplicatedStorage > DeckWars > CardData | Every card's numbers and text, the combo numbers and the board size. Edit here to rebalance |
| ReplicatedStorage > DeckWars > MatchEngine | All the rules: walking, swapping, attacking, defending, chants, Power, Soak, Scrap, Sandwich, Combo, buildings, terrain and every card ability |
| ReplicatedStorage > DeckWars > BotBrain | The bot (Easy, Medium, Hard). It walks, swaps, builds, defends, chants and picks its fights |
| ReplicatedStorage > DeckWars > StarterDecks | The six themed 30-card decks |
| ReplicatedStorage > DeckWars > CreatureModelData | The built-in 3D models, as data (made by `gen_models.py`) |
| ReplicatedStorage > DeckWars > CreatureBuilder | Turns that data into Roblox models |
| ServerScriptService > MatchServer | Runs matches on the server so nobody can cheat, runs the bot and the turn timer |
| StarterPlayer > StarterPlayerScripts > DeckWarsClient | Menu room camera, menus, the match screen, the hand of cards, tile glows, clicking on the table, the command buttons, the action camera (`actionCam`), Scrap heaps (`scrapFx`) and all table animations |
| Workspace > MenuRoom | The room. Move or restyle anything, but keep the names of the parts in Stations > DuelTable > Board (`Tile_1_1` to `Tile_5_6`, `Hero_Near`, `Energy_Near_1` and so on) |
| ReplicatedStorage > CreatureModels | Empty folder for your own models (see below) |

## Use your own models
Put a Model in ReplicatedStorage > CreatureModels and name it after the card id, for example `toaster_knight` or `snack_bar` (ids are in CardData). Build it facing the front (-Z); the game shrinks it to fit a tile, stands it on its feet and puts a round base under creatures. The same works for the heroes (`hero_bonk`, `hero_granny_bolt`). Parts named `Lid` are hidden eyelids the game flashes to make a model blink.

## What was tested, and what wasn't
- **Rules:** the rules engine passes 211 automatic checks, including new ones for Power, Sandwich, Combo, Soak and Zap, Scrap and the Titan discount, Pack, Grudge, Upload and the going-first rule, plus 120 bot-vs-bot games between the Easy, Medium and Hard bots with no errors, in which every card in the six decks got played.
- **Balance (bot-vs-bot games on Hard, five rounds of 1,080 games):** the first combo version was lopsided (Critter Crew won only 31%, Sugar Rush 62% and Scrap Heap 60%), so cards were adjusted between rounds (see "Balance changes" above). In the final 1,080 games every deck won between 46% and 54%: Sugar Rush 51%, Scrap Heap 54%, Storm Front 52%, Critter Crew 49%, Haunted Mall 48% and Robo Rumble 46%. Scrap Heap against Storm Front is still the most one-sided pair (Scrap Heap wins 72%), so tell me if it feels unfair when you play it. With the old first-turn draw the first player won 61% (still 61% when the second player got a Spare Battery instead), so now they skip it; in the final games the first player won 45%.
- **Simulated Studio:** the Studio scripts ran in a simulated Roblox that checks every property, enum and method name against Roblox's API list. It played 6 full matches through the real menus, buttons and table clicks, plus an idle match ended by the turn timer, leaving mid-match and junk data from a cheating client, and replayed every animation on a real board. New checks for this update: every combo animation (Power, Soak, Zap, Scrap, Upload, Sandwich, Combo, spell cast and heal) plays without errors, Scrap heaps show on their tile, the line under a creature shows ⚡ Power and 💧 Soaked, the log calls out a Combo, creatures stand on round bases, and the dark screen edges are on during a match. All 79 checks passed with 0 errors and 0 warnings.
- It has **not** been opened in real Roblox Studio yet (that can't be done from here). The new lighting was judged with a rough preview render (`docs/table_preview.png`: the last version on top, this one below), not Roblox's own renderer, so brightness is the thing most likely to need a tweak. If the board looks too dark on your screen, raise Lighting > ExposureCompensation a little (see "Change the lighting"); if it's still too bright, lower it. If you see a red error in Studio's Output window, copy it to me.
- Realistic lighting with shadows is heavier on old phones. If it runs slowly, set Lighting > PrioritizeLightingQuality to off.
- **Settings update:** a new 12-step check in the simulated Studio walks the stations with A, D and the arrow keys (including wrapping around both ways), changes settings through the real buttons, checks they reach the server once (not on every click) and that the in-match window shows the same values, then Reset and S back to the room. The rules tests check that the server throws away bad saved settings. Saving to a DataStore can't run in the simulator, so test it in Studio: turn on Game Settings > Security > "Enable Studio Access to API Services", change a setting, stop, play again. Without that switch settings simply reset every time you play; nothing breaks.
- Known limits: one duel table, so only one player per server should play a bot at a time. Table matches have no sound yet (only Pack Brawl does). Playing friends, building your own decks, opening packs and saving progress come in step 3.


## Pack Brawl: the pack-opening cinematic
Every pack pull is a fight in the Brawl Box, and the card you pulled always wins. The rarer the card, the more creatures crash the fight first: Common is a 4 second 1v1, Secret is 15 seconds of chaos that cracks the screen. The full blueprint (script for every tier, camera, effects, sound, Roblox setup) is in the design doc: https://claude.ai/artifact/3kHVcDqDcoNJascS8k77S6

It is part of the main game: walk to the Pack Party corner (click the prize machine, or the Pack Party button) and press "Open 1 pack" or "Open 10 packs". While you test in Studio there is also one button per tier to preview that tier's cinematic (those only work in Studio, so live players can't force a Secret). During a cinematic, hold the mouse (or Space) to play it 3x faster, or press SKIP. Pulls are free and the collection is not saved yet (prices, currency and saving come with step 3).

The separate test place still builds, for trying the cinematic on its own:

```
rojo build pullcinematic.project.json -o DeckWars_PullCinematic.rbxlx
```

### Real fights
The creatures fight with moving parts: arms, legs, heads, tails and wings move on their own. They jab, cross, hook, uppercut and throw haymakers, swing whatever they hold (spears, wands, plungers, canes...), kick, stomp, headbutt and tail-whip. Some punches get blocked ("BLOCK!") or dodged with a duck, sway or sidestep ("MISS!"). A hit creature flinches or staggers; a knocked-out one flies off flailing and lands flat on its back. Every Epic, Mythic, Legendary and Secret creature has a named signature move (Rocket Punch, Cane Riposte, Antler Toss, Omega Rush...) for its big hits, and the winner cheers or flexes at the end.

- `Rig.luau` splits each creature model into moving parts by its part names and where they sit, and works out shoulders, hips and necks. `Rig.Overrides` fixes odd shapes by hand.
- `Moves.luau` has every move as keyframed poses, the signature moves (`Moves.Signatures`, keyed by card id), and which creature uses which move (`Moves.pickAttack`).
- `Scripts.luau` adds a `swing` cue before every hit, timed so the blow lands exactly on the hit, plus `dodge` cues.
- `luaurun -D IDS="toaster_knight,lightning_llama" preview/rig_poses.luau src/packbrawl src/shared > poses.log` then `python3 preview/brawl.py poses.log out/` draws creatures frozen mid-move, to check a rig without Studio.

Rarity tiers are now Common, Rare, Epic, Mythic, Legendary, Secret (low to high), in the main game too. The old tiers moved up one name each (Uncommon became Rare, Rare became Epic, Legendary became Mythic, Mythic became Legendary), so no card got stronger or weaker.

| File (in `src/packbrawl/`) | Job |
| --- | --- |
| `PackParty` | The Open 1 / Open 10 (and Studio-only tier preview) buttons; used by the main game's Pack Party corner and the test place |
| `Rig`, `Moves` | Moving parts and fighting moves (see "Real fights") |
| `PullRates` | Odds (Common 55%, Rare 27%, Epic 12%, Mythic 4.5%, Legendary 1.2%, Secret 0.3%) and the 10-pull Epic guarantee |
| `Casting` | Who fights: 2 Common starters, crashers by tier, the "It's Not Over" fake ending (30% on Mythic and up) |
| `Scripts` | The choreography of each tier as a list of timed cues |
| `Director` | Plays the cues on one clock; skip, fast-forward and cleanup |
| `Arena`, `Fighters`, `CamRig`, `Fx`, `Poses` | The Brawl Box, moving the creature models, the camera, effects, victory poses and ultimates |
| `Sfx`, `Reveal` | Sound and the card reveal / 10-card fan |

### Sounds
All sounds were made from scratch for this project by `tools/make_sounds.py` (no samples), so you own them. Nash uploaded them to Roblox, and their ids are in the project files (SoundService > PackBrawlSounds in `default.project.json` and `pullcinematic.project.json`), so every build has sound. Music (`brawl`, `theme`) plays through its own SoundGroup so the Music and Sound effects settings work separately.

To change a sound: upload a new file (View > Asset Manager > Bulk Import) or pick a Creator Store sound, and paste its id into the matching `SoundId` in both project files (or in Studio, SoundService > PackBrawlSounds).

### Where to tweak it
- Lengths, who crashes in and when: `Scripts.luau` (one function per tier).
- Odds: `PullRates.luau`. Fake ending chance: `Casting.FakeOutChance`.
- Colors, bloom and camera shake per tier: `Kit.luau` (`TierColor`, `TierGrade`, `TierCamera`).
- Tier preview buttons: on only in Studio. The test place forces them on with the `AllowTierPreview` attribute on ServerScriptService > PullServer.
- A move looks wrong on one creature: tweak its keyframes in `Moves.luau`, or its rig in `Rig.Overrides`.

`preview/brawl.py` renders rough frames of the cinematic from the simulated Studio (`-D SNAP=1`), to check camera framing without Roblox.

## Latest update: combos and a calmer, heavier table

### Cards that build up together
You can still play simply: walk, attack, defend. But a player who plans can now grow a much stronger board. The ideas come from other games: Star Realms (cards of the same faction help each other), Slay the Spire (stacking buffs), Go and old Viking board games (surrounding an enemy), Into the Breach (pushing enemies into position) and auto-battlers like Teamfight Tactics (families that are stronger together).

- **Power ⚡.** Counters that stay on a creature: +1 attack each, up to 3. Several cards and rules give it out. A creature's Power shows under its stats.
- **Sandwich.** Attack an enemy that has one of your creatures right behind it (on the far side, in line with the attacker): +1 damage. While you aim, hovering the target says "Sandwich!" when it works.
- **Combo.** Cards with "Combo:" on them get a bonus if you already played another card of the same family this turn. Example: Moth Mailman draws 1 card, or 2 with Combo. When a card in your hand is ready to combo, it gets a gold **COMBO** tag and a gold glow.
- **Every family has its own way to grow:**

| Family | Rule | How to use it |
| --- | --- | --- |
| Snack | **Sweet Tooth**: every heal gives a Snack 1 Power, even at full health | Heal all the time: Snack Time, Pancake Paladin, Pretzel Guard's Combo and the Picnic chant. Hot Sauce Imp gets 2 Power from every heal |
| Junk | **Scrap**: Junk creatures and buildings leave Scrap on their tile when they pop. A Junk creature that steps on Scrap picks it up: +1/+1 for each | Tin Can Tom leaves 2 Scrap. Rusty Shopping Cart also picks up Scrap next to where it stops. Scrapheap Titan costs 1 less for each Scrap on the board (up to 3 less), so you choose: grow now, or save the Scrap for a cheap Titan |
| Weather | **Soak** 💧: a Soaked creature takes 1 more damage from the next hit, then dries off | Soak first (Drizzle Sprite, Grumpy Cloud, Tornado Twins, the new Water Balloon spell, the Gust chant), then hit. Zap creatures (Lightning Llama, Bolt Bug, Microwave Mage) deal 2 more on top |
| Critter | **Pack**: every Critter gets +1 attack for each friendly Critter next to it (up to +2) | Keep them together. Sergeant Snail gives the Critters next to it Sturdy |
| Spooky | **Grudge**: Grudge creatures get 1 Power whenever another of your creatures pops | Skeleton Mascot and The Mannequin Duke grow as your side takes losses, and Haunt still leaves Ghosts |
| Robo | **Upload**: when a Robo pops, its Power jumps to the Robo next to it with the least Power | Charge now gives Power at the start of your turns, and the Power Up chant gives Power |

- **26 cards were rewritten** to use these rules, and there's a new spell: **Water Balloon** (1 energy: Soak an enemy creature and push it 1 tile back). It replaced Wrong Turn in Storm Front and Coin Flip Fury in Robo Rumble.
- **Chant changes:** Picnic now costs 2 energy and gives Snacks Power even when nobody is hurt. Gust also Soaks what it blows. Power Up gives 1 Power (max 3).
- **Balance changes** after 5,400 bot-vs-bot games: Drizzle Sprite is now 1/2, Grumpy Cloud 2/3 and Roomba Rex 2/3. Scrap Heap plays one Scrap Catapult and one Pothole fewer (a second Snack Break and a Wrong Turn instead), and Robo Rumble swapped Earthquake Dance, which hurt its own small robots, for Sneeze Storm.
- **Going first:** with the combos the first player won 61% of bot games, so now the first player skips the draw on their very first turn (they still start with 4 cards and the second player with 5). In the final bot games the first player won 45%, much closer to even.
- The deck picker's blurbs now say how each deck builds up.
- **The bot plays with all of it.** It tries out its moves before it makes them, so it sees Combos, Sandwiches, Soak and Scrap.

### A darker, heavier table
- **Lighting:** the room is much darker (less ambient light, lower exposure, less glow, more contrast). The lamps over the table make a warm pool of light on the board while the rest of the room falls into shadow, and shadows are crisper.
- **Tiles feel like stone slabs:** every tile sits on a dark plinth, so it has a thick, stepped edge.
- **Terrain colors are deep and match each family's card color,** so you can see at a glance where your creatures get +1 attack: Soda Swamp is amber (Snack), Glitter Junkyard is rusty metal (Junk), Static Snowfield is deep ice blue (Weather), Pillow Peaks is soft moss green felt (Critter), Mushroom Mall is dusky purple tile (Spooky) and Lava Laundromat is grey steel plate (Robo).
- **Every creature stands on a heavy round base,** like a painted miniature: dark stone with a thin ring in its side's color (blue for yours, red for the opponent's).
- During a match the edges of the screen are softly darkened, so your eye goes to the board.

### Less going on at once, more punch when it counts
- **A quiet board:** creatures breathe slowly, glance around now and then and no longer hop. Hand cards rest still. Glows barely pulse. There are fewer particles everywhere, the purple screen flash on spells is gone, and the Big Move and Total Chaos flashes are much softer.
- **Under each creature's stats, only what's going on right now:** ⚡ Power, 💧 Soaked, 🔋 Charge left, Bubble, zZ (just arrived) and 🛡 (guarding). Its keywords are on its card: hover the creature to see it. Hovering a creature or tile also explains its Power, Soak and Scrap.
- **Hits land harder:** the target flashes white, a ring of light spreads at its feet, and everything holds for a split second (hit-stop) before the knock-back.
- **Spells:** light gathers into a glowing orb over the caster's side of the table, then bursts.
- **Heals:** a soft column of green light rises through the creature.
- **The new rules have their own small moments:** a gold glint and "+1 ⚡" for Power, a splash of water for Soak, Scrap clattering onto a tile and flying into the Junk creature that picks it up, "Sandwich! +1" over the helper, and "Combo!" when a combo goes off.

