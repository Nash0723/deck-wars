-- The uploaded pictures LayerFx draws its effects with: one sheet per effect, four layers on it
-- (glow, rim, middle, core). The sheets are drawn by vfx/draw_layers.py into vfx/sheets/.
--
-- A sheet with no id here simply isn't drawn (the game plays as before, without that effect).
-- After uploading new sheets, put their ids here (see vfx/README.md).
return {
	burst = "",
	slash = "",
	ring = "",
	circle = "",
	pillar = "",
	bolt = "",
	puff = "",
	bloom = "",
	shield = "",
	shard = "",
	flame = "",
	spark = "",
	bits = "",
}
