-- The six free themed decks (30 cards each). Each one is built around one family,
-- so its creatures, buildings and spells work together.

local StarterDecks = {}

local function expand(counts)
	local deck = {}
	for _, pair in ipairs(counts) do
		for _ = 1, pair[2] do
			table.insert(deck, pair[1])
		end
	end
	assert(#deck == 30, "A themed deck must have 30 cards, has " .. #deck)
	return deck
end

StarterDecks.Snack = {
	name = "Sugar Rush",
	family = "Snack",
	hero = "bonk",
	blurb = "Snacks grow stronger every time they're healed. Build a kitchen around Snack Bars.",
	cards = expand({
		{ "jelly_bean_scout", 3 },
		{ "pretzel_guard", 3 },
		{ "pancake_paladin", 3 },
		{ "hot_sauce_imp", 3 },
		{ "spaghetti_hydra", 2 },
		{ "burrito_bouncer", 1 },
		{ "queen_parfait", 1 },
		{ "snack_bar", 3 },
		{ "bouncy_castle", 2 },
		{ "snack_break", 2 },
		{ "pep_talk", 3 },
		{ "bubble_wrap", 2 },
		{ "coin_flip_fury", 2 },
	}),
}

StarterDecks.Junk = {
	name = "Scrap Heap",
	family = "Junk",
	hero = "granny_bolt",
	blurb = "Popped junk leaves Scrap. Walk over it to grow, or save it for a cheap Titan.",
	cards = expand({
		{ "tin_can_tom", 3 },
		{ "couch_golem", 3 },
		{ "rusty_shopping_cart", 3 },
		{ "dumpster_diver", 3 },
		{ "glitter_gremlin", 2 },
		{ "scrapheap_titan", 1 },
		{ "the_junk_king", 1 },
		{ "scrap_catapult", 1 },
		{ "spiked_fence", 3 },
		{ "lemonade_stand", 1 },
		{ "pothole", 1 },
		{ "wrong_turn", 1 },
		{ "coin_flip_fury", 2 },
		{ "mystery_box", 1 },
		{ "spare_battery", 2 },
		{ "snack_break", 2 },
	}),
}

StarterDecks.Weather = {
	name = "Storm Front",
	family = "Weather",
	hero = "granny_bolt",
	blurb = "Soak enemies first, then hit them harder. Ranged clouds and Wind Turbines.",
	cards = expand({
		{ "drizzle_sprite", 3 },
		{ "grumpy_cloud", 3 },
		{ "hailstone_hopper", 3 },
		{ "fog_bank", 3 },
		{ "lightning_llama", 2 },
		{ "tornado_twins", 1 },
		{ "stormlord_nimbus", 1 },
		{ "wind_turbine", 3 },
		{ "spiked_fence", 2 },
		{ "sneeze_storm", 2 },
		{ "water_balloon", 2 },
		{ "terrain_shift", 1 },
		{ "earthquake_dance", 1 },
		{ "coin_flip_fury", 2 },
		{ "spare_battery", 1 },
	}),
}

StarterDecks.Critter = {
	name = "Critter Crew",
	family = "Critter",
	hero = "bonk",
	blurb = "Every Critter gets stronger side by side. Keep the pack together and swarm the board.",
	cards = expand({
		{ "pocket_mouse", 3 },
		{ "moth_mailman", 3 },
		{ "pillow_bunny", 3 },
		{ "hamster_wheel_hero", 3 },
		{ "pigeon_squad", 2 },
		{ "sergeant_snail", 1 },
		{ "big_momma_moose", 1 },
		{ "bunny_burrow", 3 },
		{ "bouncy_castle", 2 },
		{ "pep_talk", 2 },
		{ "bubble_wrap", 2 },
		{ "spare_battery", 2 },
		{ "wrong_turn", 2 },
		{ "snack_break", 1 },
	}),
}

StarterDecks.Spooky = {
	name = "Haunted Mall",
	family = "Spooky",
	hero = "bonk",
	blurb = "Haunt leaves Ghosts, and Grudge creatures grow when friends pop.",
	cards = expand({
		{ "sheet_ghost", 3 },
		{ "skeleton_mascot", 3 },
		{ "haunted_vending_machine", 3 },
		{ "mushroom_witch", 3 },
		{ "mall_cop_phantom", 2 },
		{ "escalator_wraith", 1 },
		{ "the_mannequin_duke", 1 },
		{ "spooky_crypt", 3 },
		{ "haunted_arcade", 1 },
		{ "spiked_fence", 1 },
		{ "pothole", 2 },
		{ "sneeze_storm", 2 },
		{ "mystery_box", 1 },
		{ "wrong_turn", 2 },
		{ "spare_battery", 2 },
	}),
}

StarterDecks.Robo = {
	name = "Robo Rumble",
	family = "Robo",
	hero = "granny_bolt",
	blurb = "Robots charge up Power and pass it on when they fall. Soak, then zap.",
	cards = expand({
		{ "bolt_bug", 3 },
		{ "roomba_rex", 3 },
		{ "toaster_knight", 3 },
		{ "laundry_bot_3000", 3 },
		{ "microwave_mage", 2 },
		{ "mecha_fridge", 1 },
		{ "mega_blender_prime", 1 },
		{ "charging_station", 3 },
		{ "rocket_lunchbox", 1 },
		{ "lemonade_stand", 1 },
		{ "spare_battery", 2 },
		{ "pep_talk", 2 },
		{ "sneeze_storm", 1 },
		{ "bubble_wrap", 2 },
		{ "water_balloon", 2 },
	}),
}

StarterDecks.Order = { "Snack", "Junk", "Weather", "Critter", "Spooky", "Robo" }

return StarterDecks
