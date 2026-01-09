local LuaTypes = require(script.Parent:WaitForChild("LuaTypes"))

type Item_Type = LuaTypes.Item

-- ⚠️ Categories:
-- CaptureCubes - Items used to capture creatures
-- Heals - Items that heal or boost stats by percentage
-- Items - General items
-- MoveLearners - Items that teach moves to creatures (like TMs, called ML)
-- Repels - Items that prevent wild encounters for a number of steps

local function createItem(stats: {HP: number, Attack: number, Defense: number, Speed: number}, description: string, category: string, usableInBattle: boolean?, usableInOverworld: boolean?, image: string?): Item_Type
	return {
		Stats = stats,
		Description = description,
		Category = category,
        UsableInBattle = usableInBattle,
        UsableInOverworld = usableInOverworld,
		Image = image or "rbxassetid://0",
	}
end

-- Helper function to parse move name from ML item name (format: "ML - [MoveName]")
local function parseMoveNameFromML(itemName: string): string?
	local parts = itemName:split(" - ")
	if #parts >= 2 then
		return parts[2]
	end
	return nil
end

return {
	-- ⚕️ Heals
	["Apple"] = createItem({
		HP = 35, Attack = 0, Defense = 0, Speed = 0,
	}, "A crispy red apple that boosts your creature's HP by 35 percent.", "Heals", true, true, "rbxassetid://89580074029562"),

	["Potion"] = createItem({
		HP = 25, Attack = 0, Defense = 0, Speed = 0,
	}, "A potion that boosts your creature's HP by 25 percent.", "Heals", true, true, "rbxassetid://113507846322926"),

	["Epic Potion"] = createItem({
		HP = 50, Attack = 0, Defense = 0, Speed = 0,
	}, "A high-quality potion that restores 50 percent HP.", "Heals", true, true, "rbxassetid://105838711562581"),

	["Maximum Potion"] = createItem({
		HP = 100, Attack = 0, Defense = 0, Speed = 0,
	}, "A top-tier potion that restores 100 percent HP.", "Heals", true, true, "rbxassetid://118496899872192"),

	["Revive"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Revives your creature, restoring 50% of total HP.", "Heals", true, true, "rbxassetid://134114221174913"),

	["Maximum Revive"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Revives your creature, restoring 100% of total HP.", "Heals", true, true, "rbxassetid://132224763853286"),

	["Toxic Candy"] = createItem({
		HP = -10, Attack = 25, Defense = 0, Speed = 10,
	}, "Raises Attack and Speed but slightly harms HP. Risky but powerful.", "Heals", true, true, "rbxassetid://104789865067236"),

	["Golden Apple"] = createItem({
		HP = 100, Attack = 0, Defense = 0, Speed = 0,
	}, "A mythical fruit that fully restores HP and cleanses all status effects.", "Heals", true, true, "rbxassetid://101214224866598"),


	-- 🌀 Capture Cubes
	["Capture Cube"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "The best invention of the century, use it to capture creatures!", "CaptureCubes", true, false, "rbxassetid://78797852452861"),

	["Premium Cube"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "A more expensive capture cube that has a higher success rate.", "CaptureCubes", true, false, "rbxassetid://78797852452861"),

	["Excellence Cube"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "A very expensive capture cube that has a very high success rate.", "CaptureCubes", true, false, "rbxassetid://78797852452861"),

	["Rot Cube"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Infused with chaotic energy. Said to have the highest success rate out of any cubes.", "CaptureCubes", true, false),

	["Glitch Cube"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "A strange unstable cube. Has a very small chance to duplicate the captured creature... or fail completely.", "CaptureCubes", true, false),

	["Rapid Cube"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "When used on the first turn of a battle, it has a higher success rate.", "CaptureCubes", true, false),


	-- 🎒 Items (Holdables, Buffs, Evolutions)
	["Metal Fist"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Boosts Steel-type moves when held by a Fighting-type creature.", "Items", false, false, "rbxassetid://123491437551514"),

	["Fairy Dust"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Boosts Fairy-type moves.", "Items", false, false, "rbxassetid://84406508756109"),

	["Static Chip"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Boosts Electric-type moves slightly.", "Items", false, false),

	["Spike Band"] = createItem({
		HP = 0, Attack = 10, Defense = -5, Speed = 0,
	}, "Boosts Attack but slightly lowers Defense.", "Items", false, false, "rbxassetid://127002348069157"),

	["Rage Core"] = createItem({
		HP = 0, Attack = 25, Defense = -10, Speed = 5,
	}, "Raises Attack sharply when HP drops below 25%.", "Items", false, false, "rbxassetid://102157045676821"),

	["Crumbs"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Heals the creature at the end of every turn by 1/16th of its HP.", "Items", false, false, "rbxassetid://101218544460247"),

	["Echo Bell"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "When held, slightly heals the creature when it deals damage.", "Items", false, false, "rbxassetid://105427967462490"),

	["Focus Bandage"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "A mysterious cloth that sometimes allows the holder to endure a fatal hit with 1 HP remaining.", "Items", false, false, "rbxassetid://77092682172457"),

	["Stone Armor"] = createItem({
		HP = 0, Attack = 0, Defense = 20, Speed = -10,
	}, "Increases Defense but reduces Speed. Good for tanky creatures.", "Items", false, false),

	["Sleep Mask"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Prevents the holder from falling asleep during battle.", "Items", false, false, "rbxassetid://103377350545351"),

	["Bright Core"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "When held, slightly increases accuracy of all moves.", "Items", false, false, "rbxassetid://82882248622375"),

	["Inferno Seed"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Used to evolve certain Fire-type creatures.", "Items", false, false),

	["Tore Stone"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "When held by a beaked creature, it is said to trigger a mystical event.", "Items", false, false, "rbxassetid://86893072345080"),

	["Shiny Core"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "A mysterious core that passively increases your chances of encountering shiny creatures. Cannot be held or used.", "Items", false, false, "rbxassetid://0"),


	-- 🛡️ Repels
	["Focus Spray"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Keeps wild encounters away for a short time.", "Items", false, true, "rbxassetid://90607842337478"),

	["Super Focus Spray"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "A stronger spray that lasts longer.", "Items", false, true, "rbxassetid://87726456247355"),

	["Max Focus Spray"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "The longest-lasting Focus Spray.", "Items", false, true, "rbxassetid://119631326721437"),


	-- 📚 Move Learners (ML)
	-- All ML items use the same sprite sheet with type-based rect offsets
	-- ImageRectOffset and ImageRectSize are set in UI code based on move type
	["ML - Tackle"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Tackle to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Scratch"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Scratch to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Bite"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Bite to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Crunch"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Crunch to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Earthquake"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Earthquake to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Fast Attack"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Fast Attack to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Double-Edge"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Double-Edge to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
	
	["ML - Flare Blitz"] = createItem({
		HP = 0, Attack = 0, Defense = 0, Speed = 0,
	}, "Teaches Flare Blitz to a creature.", "MoveLearners", false, true, "rbxassetid://131215110444098"),
}
