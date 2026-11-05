-- Deck Wars card list (lanes with a Front and a Back row).
-- Edit numbers here; abilities live in MatchEngine (onPlay, spark, castSpell, startTurn and the aura helpers).

local CardData = {}

CardData.Rarities = { "Common", "Rare", "Epic", "Mythic", "Legendary", "Secret" } -- low to high
CardData.RarityColors = { Common = {170,165,150}, Rare = {61,165,255}, Epic = {166,77,255}, Mythic = {255,59,92}, Legendary = {255,194,26}, Secret = {255,255,255} }
CardData.Families = { "Snack", "Junk", "Weather", "Critter", "Spooky", "Robo" }
CardData.FamilyColors = { Snack = {255,150,90}, Junk = {140,130,110}, Weather = {120,190,255}, Critter = {150,220,110}, Spooky = {170,110,220}, Robo = {200,200,215}, Any = {240,240,240} }
-- The landscape of each family (the lanes of a Snack deck are Soda Swamp, and so on).
CardData.Terrains = { Snack = "Soda Swamp", Junk = "Glitter Junkyard", Weather = "Static Snowfield", Critter = "Pillow Peaks", Spooky = "Mushroom Mall", Robo = "Lava Laundromat" }
CardData.Keywords = { "Zoom", "Ranged", "Sturdy", "Splash", "Haunt", "Pack", "Zap", "Grudge" }
CardData.KeywordText = {
	Zoom = "Attacks in the battle of the turn it's played (other creatures wait a turn)",
	Ranged = "From the Back row it shoots the weakest enemy in its lane or the lanes next to it, either row (the hero only when all three lanes are empty). From the Front row it fights like everyone else",
	Sturdy = "Takes 1 less damage",
	Splash = "Its attacks also deal 1 damage to the enemy creatures next to its target (beside it and behind or in front of it)",
	Haunt = "When it pops, a 1/1 Ghost rises where it stood",
	Pack = "+1 attack for each friendly Critter next to it (beside it in its row, or in the other row of its lane)",
	Zap = "Deals 2 more damage to Soaked creatures",
	Grudge = "When it pops, it deals its attack to the first enemy in the lane across (or the enemy hero)",
}
CardData.Heroes = {
	bonk = { id = "bonk", name = "Bonk", bigMove = "Hat Trick", text = "Pull a random spell from the hat. It costs 0.", target = nil },
	granny_bolt = { id = "granny_bolt", name = "Granny Bolt", bigMove = "Strike", text = "Bowl down an enemy lane: 4 damage to the Front creature, what it doesn't need rolls on to the Back creature, then the enemy hero.", target = "enemyLane" },
}
-- The match: every player has 4 lanes, each with a landscape. Each lane has two tiles on your
-- side, the Front row (toward the middle) and the Back row, and a building slot behind them.
-- Front creatures fight the first enemy in the lane across; Back creatures are the reserve.
CardData.Lanes = 4 -- lanes per player (a 2v2 team has 8 side by side)
CardData.Cols = CardData.Lanes -- (older name: the deck builder's lane count)
CardData.Rows = 2 -- 1 = Front, 2 = Back
CardData.RowNames = { "Front", "Back" }
-- Shift: once per turn, pay this much magic to move a creature to the other row of its lane
-- (it trades places with your creature there). A Shifted creature skips its attack that turn.
CardData.ShiftCost = 1
-- Overkill: when a melee attack pops the Front creature, the damage it didn't need rolls on to
-- the Back creature of that lane, and past it to the hero. Keeps big creatures from stalling.
CardData.CarryOverkill = true
CardData.HeroMaxHp = 25 -- 1v1: each player's hit points
CardData.TeamMaxHp = 40 -- 2v2: each team shares one pool of hit points
-- Magic: you get StartMagic on your first turn and 1 more each turn after, up to MaxMagic.
CardData.StartMagic = 2
CardData.MaxMagic = 8
CardData.MaxEnergy = CardData.MaxMagic -- older name, still used for the crystals on the table
CardData.StartHand = 5
CardData.MaxHand = 8
CardData.DeckSize = 30
CardData.MaxCopies = 3
CardData.BigMoveCharge = 10 -- damage you must deal before your hero's Big Move is ready (once per match)
-- Going first is an edge. The team that goes first starts with FirstHandPenalty cards fewer
-- and its first player skips their very first draw. In Hard bot games that took the first
-- team from 62% wins to about 50-57% in 1v1 and about 56% in 2v2 (bal/balance.luau).
-- SecondPlayerCard (a card id) gives the other team a bonus card; a Spare Battery overshoots
-- (the first team then wins only about 36%).
CardData.FirstHandPenalty = 1
CardData.FirstTurnDraw = false
CardData.FirstTurnBattle = false
CardData.SecondPlayerCard = nil
-- A creature standing on its own family's landscape gets this much more attack.
CardData.HomeBonus = 1
-- Power: counters on a creature, +1 attack each, up to PowerMax.
CardData.PowerMax = 3
-- Soak: a Soaked creature takes SoakBonus more damage from the next hit, then dries off.
-- Zap creatures deal ZapBonus more on top of that to Soaked creatures.
CardData.SoakBonus = 1
CardData.ZapBonus = 2
-- Pack: +1 attack for each friendly Critter in the lanes next to it, up to PackMax.
CardData.PackMax = 2
-- Scrap: popped Junk leaves Scrap in its lane, up to ScrapMax. A Junk creature played or moved
-- into a lane picks it up: +ScrapGain/+ScrapGain for each one. (Junk's family rule.)
CardData.ScrapMax = 3
CardData.ScrapGain = 1
-- How each family plays (shown in the deck picker). Everything a card does is written on the card;
-- the one rule that isn't is Junk's Scrap (`rule = true`), which the card previews explain too.
CardData.FamilyRules = {
	Snack = { name = "Heal up", text = "Snacks heal your creatures and your hero, and outlast the other side" },
	Junk = { name = "Scrap", text = "Popped Junk creatures leave Scrap in their lane. A Junk creature that lands there picks it up: +1/+1 each", rule = true },
	Weather = { name = "Soak", text = "Soak enemies, then Zap them: a Soaked creature takes more damage from the next hit" },
	Critter = { name = "Pack", text = "Lots of small creatures that get stronger standing next to each other" },
	Spooky = { name = "Haunt", text = "Spooky creatures come back as Ghosts and hit back when they pop" },
	Robo = { name = "Charge", text = "Robos power up a little every turn, so they hit harder the longer they last" },
}
-- Rules every deck uses, for help screens.
CardData.RuleText = {
	Landscape = "Every lane has a landscape. A creature on its own family's landscape gets +1 attack",
	Spark = "Pay a creature's Spark cost to use its Spark ability, once per turn. A Sparked creature skips its attack that turn",
	Battle = "When you press BATTLE, each Front creature hits the first enemy in the lane across (the Front one, else the Back one, else the enemy hero). Back creatures wait, unless they have Ranged. Then your Back creatures step up into empty Front tiles and your turn ends. New creatures wait a turn before they attack (unless they have Zoom)",
	Rows = "Each lane has a Front tile and a Back tile on your side. The Front fights and shields the Back; the Back is your reserve and steps up when the Front falls",
	Shift = "Pay 1 magic to move a creature to the other row of its lane (it trades places with your creature there). Once per turn; the Shifted creature skips its attack",
	Overkill = "When a melee attack pops the Front creature, the leftover damage rolls on to the Back creature behind it, then the hero",
	Combo = "The Combo bonus happens if you already played another card this turn",
	Power = "+1 attack for each Power, up to 3",
	Charge = "Gets this much Power at the start of each of your turns",
	Soak = "A Soaked creature takes +1 damage from the next hit, then dries off",
	Scrap = "Left in a lane by popped Junk. Junk creatures that land in that lane (either row) get +1/+1 each",
	SnackTime = "Snack Time: when played, heal your hero this much",
}

CardData.Cards = {
	jelly_bean_scout = { id = "jelly_bean_scout", name = "Jelly Bean Scout", type = "Creature", family = "Snack", cost = 1, atk = 2, hp = 2, text = "Snack Time 1", rarity = "Common", sparkCost = 1, sparkText = "Heal your hero 2", keywords = {}, snackTime = 1 },
	pretzel_guard = { id = "pretzel_guard", name = "Pretzel Guard", type = "Creature", family = "Snack", cost = 2, atk = 2, hp = 5, text = "Sturdy. Combo: heal your other creatures 1", rarity = "Common", sparkCost = 1, sparkText = "Heal the creatures next to it 2", keywords = {Sturdy = true}, combo = true },
	pancake_paladin = { id = "pancake_paladin", name = "Pancake Paladin", type = "Creature", family = "Snack", cost = 3, atk = 3, hp = 5, text = "Snack Time 2. When played, heal the creatures next to it 2", rarity = "Rare", sparkCost = 2, sparkText = "Heal all your creatures 1", keywords = {}, snackTime = 2 },
	hot_sauce_imp = { id = "hot_sauce_imp", name = "Hot Sauce Imp", type = "Creature", family = "Snack", cost = 2, atk = 2, hp = 3, text = "Zoom. Gets 2 Power from every heal", rarity = "Rare", sparkCost = 1, sparkText = "Heal itself 1", keywords = {Zoom = true} },
	spaghetti_hydra = { id = "spaghetti_hydra", name = "Spaghetti Hydra", type = "Creature", family = "Snack", cost = 5, atk = 5, hp = 6, text = "Splash. Combo: gets 2 Power", rarity = "Epic", sparkCost = 2, sparkText = "Deal 1 damage to every enemy creature", keywords = {Splash = true}, combo = true },
	burrito_bouncer = { id = "burrito_bouncer", name = "Burrito Bouncer", type = "Creature", family = "Snack", cost = 4, atk = 3, hp = 6, text = "Creatures that hit it take 1 damage back", rarity = "Mythic", sparkCost = 1, sparkText = "Heal itself 3", keywords = {} },
	queen_parfait = { id = "queen_parfait", name = "Queen Parfait", type = "Creature", family = "Snack", cost = 7, atk = 5, hp = 8, text = "When played, fully heal your creatures. Snack Time 3", rarity = "Legendary", sparkCost = 3, sparkText = "Heal your hero 3 and give your Snacks 1 Power", keywords = {}, snackTime = 3 },
	tin_can_tom = { id = "tin_can_tom", name = "Tin Can Tom", type = "Creature", family = "Junk", cost = 1, atk = 2, hp = 2, text = "When it pops, it leaves 2 Scrap in its lane", rarity = "Common", sparkCost = 0, sparkText = "Self-destruct: pops and deals 2 damage to the enemy creature across", keywords = {} },
	couch_golem = { id = "couch_golem", name = "Couch Golem", type = "Creature", family = "Junk", cost = 3, atk = 3, hp = 6, text = "Sturdy", rarity = "Common", sparkCost = 1, sparkText = "Heal itself 3", keywords = {Sturdy = true} },
	rusty_shopping_cart = { id = "rusty_shopping_cart", name = "Rusty Shopping Cart", type = "Creature", family = "Junk", cost = 2, atk = 2, hp = 3, text = "When played, it also picks up the Scrap in the lanes next to it", rarity = "Rare", sparkCost = 1, sparkText = "Pick up all the Scrap in your other lanes", keywords = {} },
	dumpster_diver = { id = "dumpster_diver", name = "Dumpster Diver", type = "Creature", family = "Junk", cost = 3, atk = 3, hp = 4, text = "When played, get back a random spell from your discard pile. Combo: picks up the Scrap next to it", rarity = "Rare", sparkCost = 2, sparkText = "Get back a random card from your discard pile", keywords = {}, combo = true },
	glitter_gremlin = { id = "glitter_gremlin", name = "Glitter Gremlin", type = "Creature", family = "Junk", cost = 2, atk = 2, hp = 3, text = "When played, Roll: Zoom, Sturdy or +2 attack", rarity = "Epic", sparkCost = 1, sparkText = "Roll again", keywords = {} },
	scrapheap_titan = { id = "scrapheap_titan", name = "Scrapheap Titan", type = "Creature", family = "Junk", cost = 6, atk = 5, hp = 7, text = "Costs 1 less for each Scrap on your side (up to 3 less)", rarity = "Mythic", sparkCost = 2, sparkText = "Eat the Scrap in its lane: +2/+2 for each", keywords = {} },
	the_junk_king = { id = "the_junk_king", name = "The Junk King", type = "Creature", family = "Junk", cost = 8, atk = 7, hp = 9, text = "Sturdy. When played, destroy every building on the board", rarity = "Legendary", sparkCost = 2, sparkText = "Crush the enemy creature across if it has 3 or less health (it leaves 2 Scrap)", keywords = {Sturdy = true} },
	drizzle_sprite = { id = "drizzle_sprite", name = "Drizzle Sprite", type = "Creature", family = "Weather", cost = 1, atk = 1, hp = 3, text = "Ranged. Its attacks Soak", rarity = "Common", sparkCost = 0, sparkText = "Soak the enemy creature across", keywords = {Ranged = true}, soaks = true },
	grumpy_cloud = { id = "grumpy_cloud", name = "Grumpy Cloud", type = "Creature", family = "Weather", cost = 2, atk = 2, hp = 4, text = "When played, hit a random enemy creature for 1 and Soak it. Combo: Soak every enemy creature", rarity = "Common", sparkCost = 1, sparkText = "Soak the enemy creatures across and next to it", keywords = {}, combo = true },
	hailstone_hopper = { id = "hailstone_hopper", name = "Hailstone Hopper", type = "Creature", family = "Weather", cost = 3, atk = 3, hp = 4, text = "Splash. Combo: Zoom", rarity = "Rare", sparkCost = 1, sparkText = "Deal 1 damage to the enemy creature across and the ones next to it", keywords = {Splash = true}, combo = true },
	fog_bank = { id = "fog_bank", name = "Fog Bank", type = "Creature", family = "Weather", cost = 3, atk = 0, hp = 6, text = "Enemy creatures across and next to it have -2 attack", rarity = "Rare", sparkCost = 2, sparkText = "Freeze the enemy creature across: it skips its next attack", keywords = {} },
	lightning_llama = { id = "lightning_llama", name = "Lightning Llama", type = "Creature", family = "Weather", cost = 4, atk = 4, hp = 4, text = "Zoom. Zap. When played, Roll: 2 damage to a random enemy creature or the enemy hero", rarity = "Epic", sparkCost = 2, sparkText = "Deal 3 damage to the enemy creature across (Zap counts)", keywords = {Zoom = true, Zap = true} },
	tornado_twins = { id = "tornado_twins", name = "Tornado Twins", type = "Creature", family = "Weather", cost = 5, atk = 4, hp = 5, text = "When played, blow every enemy creature onto a random tile on its side and Soak them", rarity = "Mythic", sparkCost = 2, sparkText = "Swap the enemy creature across with a random enemy creature", keywords = {} },
	stormlord_nimbus = { id = "stormlord_nimbus", name = "Stormlord Nimbus", type = "Creature", family = "Weather", cost = 7, atk = 6, hp = 6, text = "Ranged. At the start of your turn, deal 1 damage to every enemy creature", rarity = "Legendary", sparkCost = 3, sparkText = "Soak every enemy creature and deal 1 damage to them", keywords = {Ranged = true} },
	pocket_mouse = { id = "pocket_mouse", name = "Pocket Mouse", type = "Creature", family = "Critter", cost = 1, atk = 1, hp = 2, text = "Zoom. Pack", rarity = "Common", sparkCost = 0, sparkText = "Scurry to the empty tile of yours furthest away", keywords = {Zoom = true, Pack = true} },
	moth_mailman = { id = "moth_mailman", name = "Moth Mailman", type = "Creature", family = "Critter", cost = 2, atk = 2, hp = 2, text = "When played, draw a card. Combo: draw 2", rarity = "Common", sparkCost = 2, sparkText = "Draw a card", keywords = {}, combo = true },
	pillow_bunny = { id = "pillow_bunny", name = "Pillow Bunny", type = "Creature", family = "Critter", cost = 2, atk = 1, hp = 3, text = "When played, give another friendly creature +0/+2. Combo: +1/+2", rarity = "Rare", sparkCost = 1, sparkText = "Give the creatures next to it +0/+2", keywords = {}, combo = true, target = "otherFriendlyCreature" },
	hamster_wheel_hero = { id = "hamster_wheel_hero", name = "Hamster Wheel Hero", type = "Creature", family = "Critter", cost = 3, atk = 2, hp = 3, text = "Pack. Combo: Zoom", rarity = "Rare", sparkCost = 1, sparkText = "Your other creatures get +1 attack this turn", keywords = {Pack = true}, combo = true },
	pigeon_squad = { id = "pigeon_squad", name = "Pigeon Squad", type = "Creature", family = "Critter", cost = 4, atk = 3, hp = 3, text = "When played, 1/1 Pigeons fly into the empty tiles beside it in its row", rarity = "Epic", sparkCost = 2, sparkText = "A 1/1 Pigeon flies onto a random empty tile of yours", keywords = {} },
	sergeant_snail = { id = "sergeant_snail", name = "Sergeant Snail", type = "Creature", family = "Critter", cost = 4, atk = 2, hp = 7, text = "Sturdy. Your Critters next to it have Sturdy", rarity = "Mythic", sparkCost = 1, sparkText = "Heal the creatures next to it 2", keywords = {Sturdy = true} },
	big_momma_moose = { id = "big_momma_moose", name = "Big Momma Moose", type = "Creature", family = "Critter", cost = 7, atk = 6, hp = 7, text = "Zoom. When played, give your other Critters +1/+1", rarity = "Legendary", sparkCost = 2, sparkText = "Give your other creatures +1/+1", keywords = {Zoom = true} },
	sheet_ghost = { id = "sheet_ghost", name = "Sheet Ghost", type = "Creature", family = "Spooky", cost = 1, atk = 1, hp = 1, text = "Combo: Zoom", rarity = "Common", sparkCost = 0, sparkText = "Boo! The enemy creature across has -2 attack until your next turn", keywords = {}, combo = true },
	skeleton_mascot = { id = "skeleton_mascot", name = "Skeleton Mascot", type = "Creature", family = "Spooky", cost = 2, atk = 2, hp = 4, text = "Grudge", rarity = "Common", sparkCost = 1, sparkText = "Deal 1 damage to the enemy creature across", keywords = {Grudge = true} },
	haunted_vending_machine = { id = "haunted_vending_machine", name = "Haunted Vending Machine", type = "Creature", family = "Spooky", cost = 3, atk = 3, hp = 4, text = "When played, Roll: add a random 1-cost card to your hand. Combo: add 2", rarity = "Rare", sparkCost = 2, sparkText = "Add a random 1-cost card to your hand", keywords = {}, combo = true },
	mushroom_witch = { id = "mushroom_witch", name = "Mushroom Witch", type = "Creature", family = "Spooky", cost = 3, atk = 2, hp = 5, text = "When another friendly creature pops, deal 1 damage to the enemy hero", rarity = "Rare", sparkCost = 2, sparkText = "Deal 1 damage to the enemy hero for each creature in your discard pile (up to 3)", keywords = {} },
	mall_cop_phantom = { id = "mall_cop_phantom", name = "Mall Cop Phantom", type = "Creature", family = "Spooky", cost = 4, atk = 3, hp = 4, text = "Haunt. Enemy spells cost 1 more", rarity = "Epic", sparkCost = 2, sparkText = "Send the enemy creature across back to its owner's hand if it costs 2 or less", keywords = {Haunt = true} },
	escalator_wraith = { id = "escalator_wraith", name = "Escalator Wraith", type = "Creature", family = "Spooky", cost = 5, atk = 4, hp = 5, text = "When played, return an enemy creature costing 3 or less to its owner's hand", rarity = "Mythic", sparkCost = 2, sparkText = "Ride the escalator: the enemy creature across moves to a random empty tile on its side", keywords = {}, target = "enemyCreatureCost3" },
	the_mannequin_duke = { id = "the_mannequin_duke", name = "The Mannequin Duke", type = "Creature", family = "Spooky", cost = 7, atk = 5, hp = 6, text = "Haunt. Grudge. When played, bring back the last creature you lost onto an empty tile", rarity = "Legendary", sparkCost = 3, sparkText = "Bring back the last creature you lost onto an empty tile", keywords = {Haunt = true, Grudge = true} },
	bolt_bug = { id = "bolt_bug", name = "Bolt Bug", type = "Creature", family = "Robo", cost = 1, atk = 1, hp = 4, text = "Charge 1. Zap", rarity = "Common", sparkCost = 0, sparkText = "Give the creatures next to it 1 Power", keywords = {Zap = true}, charge = 1 },
	roomba_rex = { id = "roomba_rex", name = "Roomba Rex", type = "Creature", family = "Robo", cost = 2, atk = 2, hp = 4, text = "Charge 1. Combo: gets 2 Power", rarity = "Common", sparkCost = 1, sparkText = "Gets 2 Power", keywords = {}, charge = 1, combo = true },
	toaster_knight = { id = "toaster_knight", name = "Toaster Knight", type = "Creature", family = "Robo", cost = 3, atk = 3, hp = 3, text = "When played, deal 1 damage to a random enemy creature. Combo: 2 damage", rarity = "Rare", sparkCost = 1, sparkText = "Pop! Deal 2 damage to the enemy creature across", keywords = {}, combo = true },
	laundry_bot_3000 = { id = "laundry_bot_3000", name = "Laundry Bot 3000", type = "Creature", family = "Robo", cost = 3, atk = 2, hp = 4, text = "Sturdy. When played, wash an enemy creature: it loses all its buffs and Power", rarity = "Rare", sparkCost = 1, sparkText = "Wash the enemy creature across", keywords = {Sturdy = true}, target = "enemyCreature" },
	microwave_mage = { id = "microwave_mage", name = "Microwave Mage", type = "Creature", family = "Robo", cost = 4, atk = 3, hp = 4, text = "Ranged. Zap. At the start of your turn, deal 1 damage to the first enemy in its lane and in the lanes next to it", rarity = "Epic", sparkCost = 2, sparkText = "Deal 2 damage to the enemy creature across", keywords = {Ranged = true, Zap = true} },
	mecha_fridge = { id = "mecha_fridge", name = "Mecha Fridge", type = "Creature", family = "Robo", cost = 6, atk = 4, hp = 8, text = "Sturdy. Charge 2", rarity = "Mythic", sparkCost = 2, sparkText = "Give the creatures next to it 1 Power", keywords = {Sturdy = true}, charge = 2 },
	mega_blender_prime = { id = "mega_blender_prime", name = "Mega Blender Prime", type = "Creature", family = "Robo", cost = 8, atk = 6, hp = 8, text = "When played, Roll: destroy a random enemy creature, or 4 damage to the enemy hero", rarity = "Legendary", sparkCost = 3, sparkText = "Blend the enemy creature across: 5 damage", keywords = {} },
	spare_battery = { id = "spare_battery", name = "Spare Battery", type = "Spell", family = "Any", cost = 0, text = "Gain 1 magic this turn", rarity = "Common", keywords = {} },
	wrong_turn = { id = "wrong_turn", name = "Wrong Turn", type = "Spell", family = "Any", cost = 1, text = "An enemy creature moves to a random empty tile on its side. If there's none, it takes 2 damage", rarity = "Common", keywords = {}, target = "enemyCreature", targetRequired = true },
	water_balloon = { id = "water_balloon", name = "Water Balloon", type = "Spell", family = "Any", cost = 1, text = "Soak an enemy creature and deal 1 damage to it", rarity = "Common", keywords = {}, target = "enemyCreature", targetRequired = true },
	snack_break = { id = "snack_break", name = "Snack Break", type = "Spell", family = "Any", cost = 2, text = "Heal your hero 4", rarity = "Common", keywords = {} },
	coin_flip_fury = { id = "coin_flip_fury", name = "Coin Flip Fury", type = "Spell", family = "Any", cost = 2, text = "Pick an enemy creature. 50%: deal 5 damage to it. 50%: deal 2 damage to your hero", rarity = "Rare", keywords = {}, target = "enemyCreature", targetRequired = true },
	sneeze_storm = { id = "sneeze_storm", name = "Sneeze Storm", type = "Spell", family = "Any", cost = 3, text = "Deal 1 damage to every enemy creature", rarity = "Rare", keywords = {} },
	bubble_wrap = { id = "bubble_wrap", name = "Bubble Wrap", type = "Spell", family = "Any", cost = 1, text = "A creature ignores the next damage it takes", rarity = "Rare", keywords = {}, target = "anyCreature", targetRequired = true },
	pep_talk = { id = "pep_talk", name = "Pep Talk", type = "Spell", family = "Any", cost = 2, text = "Give a creature +2/+2", rarity = "Epic", keywords = {}, target = "anyCreature", targetRequired = true },
	terrain_shift = { id = "terrain_shift", name = "Terrain Shift", type = "Spell", family = "Any", cost = 2, text = "Turn a lane's landscape into your home landscape, then draw a card", rarity = "Epic", keywords = {}, target = "lane", targetRequired = true },
	pothole = { id = "pothole", name = "Pothole", type = "Spell", family = "Any", cost = 3, text = "Destroy an enemy creature with 3 or less attack", rarity = "Epic", keywords = {}, target = "enemyCreatureAtk3", targetRequired = true },
	mystery_box = { id = "mystery_box", name = "Mystery Box", type = "Spell", family = "Any", cost = 3, text = "Add 2 random cards to your hand. They cost 1 less", rarity = "Mythic", keywords = {} },
	earthquake_dance = { id = "earthquake_dance", name = "Earthquake Dance", type = "Spell", family = "Any", cost = 6, text = "Deal 3 damage to every creature", rarity = "Mythic", keywords = {} },
	total_chaos = { id = "total_chaos", name = "Total Chaos", type = "Spell", family = "Any", cost = 5, text = "Every creature jumps to a random tile on its side, and every landscape changes", rarity = "Legendary", keywords = {} },
	spiked_fence = { id = "spiked_fence", name = "Spiked Fence", type = "Building", family = "Any", cost = 1, text = "Enemy creatures that attack this lane take 1 damage", rarity = "Common", keywords = {} },
	bouncy_castle = { id = "bouncy_castle", name = "Bouncy Castle", type = "Building", family = "Any", cost = 2, text = "The creatures in this lane have Sturdy", rarity = "Common", keywords = {} },
	snack_bar = { id = "snack_bar", name = "Snack Bar", type = "Building", family = "Snack", cost = 2, text = "At the start of your turn, heal the creatures in this lane 2", rarity = "Common", keywords = {} },
	bunny_burrow = { id = "bunny_burrow", name = "Bunny Burrow", type = "Building", family = "Critter", cost = 2, text = "At the start of your turn, if this lane has an empty tile, a 1/1 Pigeon moves in", rarity = "Rare", keywords = {} },
	wind_turbine = { id = "wind_turbine", name = "Wind Turbine", type = "Building", family = "Weather", cost = 2, text = "The creatures in this lane have Splash", rarity = "Rare", keywords = {} },
	lemonade_stand = { id = "lemonade_stand", name = "Lemonade Stand", type = "Building", family = "Any", cost = 2, text = "Gain 1 extra magic each turn (doesn't stack)", rarity = "Rare", keywords = {} },
	spooky_crypt = { id = "spooky_crypt", name = "Spooky Crypt", type = "Building", family = "Spooky", cost = 2, text = "The creatures in this lane have Haunt", rarity = "Rare", keywords = {} },
	disco_cactus = { id = "disco_cactus", name = "Disco Cactus", type = "Building", family = "Any", cost = 3, text = "At the start of your turn, Roll: the creatures in this lane get 1 Power, or heal 2", rarity = "Epic", keywords = {} },
	charging_station = { id = "charging_station", name = "Charging Station", type = "Building", family = "Robo", cost = 3, text = "The creatures in this lane have +1 attack and Charge 1", rarity = "Epic", keywords = {} },
	scrap_catapult = { id = "scrap_catapult", name = "Scrap Catapult", type = "Building", family = "Junk", cost = 3, text = "At the start of your turn, deal 2 damage to a random enemy creature", rarity = "Epic", keywords = {} },
	haunted_arcade = { id = "haunted_arcade", name = "Haunted Arcade", type = "Building", family = "Any", cost = 4, text = "At the start of your turn, a 1/1 Ghost rises on a random empty tile of yours", rarity = "Mythic", keywords = {} },
	rocket_lunchbox = { id = "rocket_lunchbox", name = "Rocket Lunchbox", type = "Building", family = "Any", cost = 5, text = "At the start of your turn, deal 2 damage to the enemy hero", rarity = "Legendary", keywords = {} },
	captain_confetti = { id = "captain_confetti", name = "Captain Confetti", type = "Creature", family = "Critter", cost = 6, atk = 5, hp = 5, text = "Zoom. When played, give each of your creatures a random keyword", rarity = "Secret", sparkCost = 2, sparkText = "Give each of your creatures a random keyword", keywords = {Zoom = true} },
	omega_microwave = { id = "omega_microwave", name = "Omega Microwave", type = "Creature", family = "Robo", cost = 8, atk = 8, hp = 10, text = "Sturdy. At the start of your turn, deal 3 damage to every enemy creature", rarity = "Secret", sparkCost = 3, sparkText = "Overload: deal 4 damage to every enemy creature", keywords = {Sturdy = true} },
	-- Tokens (made by other cards, not in packs)
	ghost = { id = "ghost", name = "Ghost", type = "Creature", family = "Spooky", cost = 0, atk = 1, hp = 1, text = "", rarity = "Common", sparkCost = 0, sparkText = "Boo! The enemy creature across has -1 attack until your next turn", keywords = {}, token = true },
	pigeon = { id = "pigeon", name = "Pigeon", type = "Creature", family = "Critter", cost = 0, atk = 1, hp = 1, text = "", rarity = "Common", sparkCost = 1, sparkText = "Fly to the empty tile of yours furthest away", keywords = {}, token = true },
	scrap = { id = "scrap", name = "Scrap", type = "Spell", family = "Any", cost = 0, text = "Gain 1 magic this turn", rarity = "Common", keywords = {}, token = true },
}

CardData.List = {}
for _, id in ipairs({"jelly_bean_scout", "pretzel_guard", "pancake_paladin", "hot_sauce_imp", "spaghetti_hydra", "burrito_bouncer", "queen_parfait", "tin_can_tom", "couch_golem", "rusty_shopping_cart", "dumpster_diver", "glitter_gremlin", "scrapheap_titan", "the_junk_king", "drizzle_sprite", "grumpy_cloud", "hailstone_hopper", "fog_bank", "lightning_llama", "tornado_twins", "stormlord_nimbus", "pocket_mouse", "moth_mailman", "pillow_bunny", "hamster_wheel_hero", "pigeon_squad", "sergeant_snail", "big_momma_moose", "sheet_ghost", "skeleton_mascot", "haunted_vending_machine", "mushroom_witch", "mall_cop_phantom", "escalator_wraith", "the_mannequin_duke", "bolt_bug", "roomba_rex", "toaster_knight", "laundry_bot_3000", "microwave_mage", "mecha_fridge", "mega_blender_prime", "spare_battery", "wrong_turn", "water_balloon", "snack_break", "coin_flip_fury", "sneeze_storm", "bubble_wrap", "pep_talk", "terrain_shift", "pothole", "mystery_box", "earthquake_dance", "total_chaos", "spiked_fence", "bouncy_castle", "snack_bar", "bunny_burrow", "wind_turbine", "lemonade_stand", "spooky_crypt", "disco_cactus", "charging_station", "scrap_catapult", "haunted_arcade", "rocket_lunchbox", "captain_confetti", "omega_microwave"}) do
	table.insert(CardData.List, id)
end

function CardData.get(id)
	local c = CardData.Cards[id]
	assert(c, "Unknown card: " .. tostring(id))
	return c
end

return CardData
