-- The uploaded pictures LayerFx draws its effects with: one sheet per effect, four layers on it
-- (glow, rim, middle, core). The sheets are drawn by vfx/draw_layers.py into vfx/sheets/.
--
-- A sheet with no id here simply isn't drawn (the game plays as before, without that effect).
-- After uploading new sheets, put their ids here (see vfx/README.md).
return {
	burst = "rbxassetid://123637812146033",
	slash = "rbxassetid://104095930928625",
	ring = "rbxassetid://135709324694874",
	circle = "rbxassetid://74635027159655",
	pillar = "rbxassetid://106826129686444",
	bolt = "rbxassetid://79883028944932",
	puff = "rbxassetid://129099440604882",
	bloom = "rbxassetid://97490190035795",
	shield = "rbxassetid://113728490102459",
	shard = "rbxassetid://128211886727016",
	flame = "rbxassetid://123273213313146",
	spark = "rbxassetid://101672694844069",
	bits = "rbxassetid://121044323219504",
}
