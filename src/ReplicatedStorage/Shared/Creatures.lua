local LuaTypes = require(script.Parent:WaitForChild("LuaTypes"))
local Types = require(script.Parent:WaitForChild("Types"))
local Moves = require(script.Parent:WaitForChild("Moves"))

type Creature_Type = LuaTypes.Creature
type StatBlock = LuaTypes.StatBlock

local function createCreature(
	dexNumber: number,
	name: string,
	sprite: string,
	shinySprite: string?,
	description: string,
	types: {any},
	baseStats: StatBlock,
	learnset: {[number]: {string}}?,
	evolutionLevel: number?,
	evolvesInto: string?,
	baseWeightKg: number?,
	shinyColors: {[string]: Color3}?,
	class: LuaTypes.CreatureClass?,
    catchRateScalar: number?,
    femaleChance: number?
): Creature_Type
	-- Normalize legacy move arrays (e.g. { Moves.Tackle, Moves.Scratch, ... }) to a level-1 learnset
	local normalizedLearnset = nil
	if learnset then
		local isNewFormat = false
		for k, v in pairs(learnset) do
			if type(k) == "number" and type(v) == "table" and type(v[1]) == "string" then
				isNewFormat = true
				break
			end
		end
		if isNewFormat then
			normalizedLearnset = learnset
		else
			-- Treat as legacy: array of move tables or names
			normalizedLearnset = { [1] = {} }
			for _, mv in ipairs(learnset) do
				if type(mv) == "string" then
					table.insert(normalizedLearnset[1], mv)
				else
					for moveName, moveData in pairs(Moves) do
						if moveData == mv then
							table.insert(normalizedLearnset[1], moveName)
							break
						end
					end
				end
			end
		end
	end

	return {
		-- Identity
		DexNumber = dexNumber,
		Name = name,
		Sprite = sprite,
		ShinySprite = shinySprite or "rbxassetid://000000",

		-- Flavor
		Description = description,
		Type = types,
		Class = class,

		-- Gameplay
		BaseStats = baseStats,
		Learnset = normalizedLearnset,
		EvolutionLevel = evolutionLevel,
		EvolvesInto = evolvesInto,
		BaseWeightKg = baseWeightKg,
		CatchRateScalar = catchRateScalar,
		FemaleChance = (type(femaleChance) == "number" and femaleChance or 50),

		-- Visual customization
		ShinyColors = shinyColors,
	}
end

--[[
	CREATURE BALANCE PHILOSOPHY (4-stat system inspired by modern Pokemon):
	
	Base Stat Total (BST) Targets:
	- Basic/Unevolved: 180-220 BST
	- Middle Evolution: 280-310 BST  
	- Final Evolution (starter): 350-380 BST
	- Single-stage common: 200-250 BST
	- Single-stage rare: 300-350 BST
	- Legendary/Boss: 400-450 BST
	
	Catch Rate Guidelines (higher = easier to catch):
	- Starters/Gift: 45 (moderately easy since gifted)
	- Common wild: 255 (very easy)
	- Uncommon wild: 150-200
	- Rare wild: 75-120
	- Very rare: 30-60
	- Legendary: 3-15
	
	Evolution Level Guidelines:
	- Stage 1 -> Stage 2: Level 16-18
	- Stage 2 -> Stage 3: Level 32-38
]]

local Creatures: { [string]: Creature_Type } = {
	--============================================================================
	-- STARTER LINE 1: Kitung (Fighting -> Fighting/Psychic)
	-- Role: Fast physical sweeper with late-game psychic coverage
	--============================================================================
	["Kitung"] = createCreature(
		1,
		"Kitung",
		"rbxassetid://122057835034579",
		"rbxassetid://130838050112224",
		"A small enthusiastic fighter with a wooden stick. Its determination far exceeds its tiny frame.",
		{ "Fighting" },
		{ -- BST: 210 (Speedy attacker archetype)
			HP = 45,
			Attack = 60,
			Defense = 40,
			SpecialAttack = 35,
			SpecialDefense = 40,
			Speed = 65,
		},
		{
			[1] = {"Scratch", "Tackle"},
			[5] = {"Double Kick"},
			[9] = {"Fast Attack"},
			[14] = {"Uppercut"},
		},
		16,      -- Evolution level
		"Sir Tung",
		8.5,     -- Weight kg (small creature)
		{["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["UpperArmL"]=Color3.new(0.937,0.722,0.220),["ForeArmL"]=Color3.new(0.937,0.722,0.220),["Torso"]=Color3.new(0.937,0.722,0.220),["UpperArmR"]=Color3.new(0.937,0.722,0.220),["ForeArmR"]=Color3.new(0.937,0.722,0.220),["ThighR"]=Color3.new(0.937,0.722,0.220),["ThighL"]=Color3.new(0.937,0.722,0.220),["CalfL"]=Color3.new(0.937,0.722,0.220),["CalfR"]=Color3.new(0.937,0.722,0.220),["EyesBack"]=Color3.new(0.910,0.776,0.584),["Eyes_Black"]=Color3.new(0.035,0.537,0.812),["Eyes_White"]=Color3.new(0.929,0.918,0.918),["FootL"]=Color3.new(0.937,0.722,0.220),["FootR"]=Color3.new(0.937,0.722,0.220),["HandL"]=Color3.new(0.937,0.722,0.220),["HandR"]=Color3.new(0.937,0.722,0.220),["Neck"]=Color3.new(0.937,0.722,0.220),["Stick_One"]=Color3.new(1.000,0.000,0.000),["Stick_Two"]=Color3.new(1.000,0.314,0.043),["HeadMesh"]=Color3.new(0.937,0.722,0.220)},
		"Basic",
		45,      -- Catch rate (starter - moderate)
		20       -- Female chance %
	),
	["Sir Tung"] = createCreature(
		2,
		"Sir Tung",
		"rbxassetid://117004729912755",
		"rbxassetid://80170237167870",
		"A refined Kitung that has adopted a gentleman's demeanor. Its wand channels focused fighting spirit.",
		{ "Fighting" },
		{ -- BST: 295 (Middle evolution, faster with better attack)
			HP = 60,
			Attack = 80,
			Defense = 55,
			SpecialAttack = 50,
			SpecialDefense = 55,
			Speed = 100,
		},
		{
			[1] = {"Scratch", "Tackle", "Double Kick"},
			[16] = {"Fast Attack"},
			[20] = {"Uppercut"},
			[26] = {"Grand Slam"},
			[32] = {"Shield Bash"},
		},
		36,
		"Magi-Tung",
		28.0,
		{["CalfL"]=Color3.new(0.937,0.722,0.220),["CalfR"]=Color3.new(0.937,0.722,0.220),["Eyebrows"]=Color3.new(0.937,0.722,0.220),["Eyelids"]=Color3.new(0.937,0.722,0.220),["EyesBlack"]=Color3.new(0.035,0.537,0.812),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FootL"]=Color3.new(0.937,0.722,0.220),["FootR"]=Color3.new(0.937,0.722,0.220),["ForeArmL"]=Color3.new(0.937,0.722,0.220),["ForeArmR"]=Color3.new(0.937,0.722,0.220),["HandL"]=Color3.new(0.937,0.722,0.220),["HandR"]=Color3.new(0.937,0.722,0.220),["HeadMesh"]=Color3.new(0.937,0.722,0.220),["Iris"]=Color3.new(0.973,0.973,0.973),["Mouth"]=Color3.new(0.973,0.973,0.973),["Nose"]=Color3.new(0.937,0.722,0.220),["ThighL"]=Color3.new(0.937,0.722,0.220),["ThighR"]=Color3.new(0.937,0.722,0.220),["Tie"]=Color3.new(0.769,0.157,0.110),["TopHat"]=Color3.new(0.973,0.973,0.973),["TopHatWhite"]=Color3.new(0.051,0.412,0.675),["Torso"]=Color3.new(0.937,0.722,0.220),["UpperArmL"]=Color3.new(0.937,0.722,0.220),["UpperArmR"]=Color3.new(0.937,0.722,0.220),["WandExt"]=Color3.new(1.000,0.314,0.043),["WandHandle"]=Color3.new(1.000,0.000,0.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		20
	),
	["Magi-Tung"] = createCreature(
		3,
		"Magi-Tung",
		"rbxassetid://79578637985806",
		"rbxassetid://123561772385659",
		"A master of both martial arts and mental prowess. Its psychic wand can bend reality itself.",
		{ "Fighting", "Psychic" },
		{ -- BST: 365 (Final starter evolution - elite mixed attacker)
			HP = 75,
			Attack = 100,
			Defense = 70,
			SpecialAttack = 110,
			SpecialDefense = 80,
			Speed = 120,
		},
		{
			[1] = {"Scratch", "Double Kick", "Fast Attack"},
			[20] = {"Uppercut"},
			[28] = {"Grand Slam"},
			[36] = {"Mind Slam"},
			[42] = {"Shield Bash"},
			[50] = {"Knockout"},
		},
		nil,
		nil,
		52.0,
		{["CalfL"]=Color3.new(0.973,0.973,0.973),["CalfR"]=Color3.new(0.973,0.973,0.973),["Eyebrows"]=Color3.new(0.357,0.365,0.412),["Eyelids"]=Color3.new(0.357,0.365,0.412),["EyesBlack"]=Color3.new(0.459,0.000,0.000),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FootL"]=Color3.new(0.067,0.067,0.067),["FootR"]=Color3.new(0.067,0.067,0.067),["ForeArmL"]=Color3.new(0.973,0.973,0.973),["ForeArmR"]=Color3.new(0.973,0.973,0.973),["HandL"]=Color3.new(0.067,0.067,0.067),["HandR"]=Color3.new(0.067,0.067,0.067),["HeadMesh"]=Color3.new(0.357,0.365,0.412),["Inner"]=Color3.new(0.106,0.165,0.208),["Iris"]=Color3.new(1.000,1.000,1.000),["Mouth"]=Color3.new(1.000,1.000,1.000),["Nose"]=Color3.new(0.357,0.365,0.412),["Outer"]=Color3.new(0.973,0.973,0.973),["ThighL"]=Color3.new(0.973,0.973,0.973),["ThighR"]=Color3.new(0.973,0.973,0.973),["Tie"]=Color3.new(0.769,0.157,0.110),["TopHat"]=Color3.new(0.973,0.973,0.973),["TopHatRibbon"]=Color3.new(0.051,0.412,0.675),["Torso"]=Color3.new(0.624,0.631,0.675),["UpperArmL"]=Color3.new(0.973,0.973,0.973),["UpperArmR"]=Color3.new(0.973,0.973,0.973),["WandExt"]=Color3.new(1.000,0.314,0.043),["WandHandle"]=Color3.new(1.000,0.000,0.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		20
	),

	--============================================================================
	-- STARTER LINE 2: Frigo Camelo (Ground -> Ground/Ice)
	-- Role: Bulky physical attacker with good mixed offense
	--============================================================================
	["Frigo Camelo"] = createCreature(
		4,
		"Frigo Camelo",
		"rbxassetid://114863676276555",
		"rbxassetid://79220464709099",
		"A fridge-bodied camel who wanders aimlessly, embodying surreal melancholy and cursed Italian energy.",
		{ "Ground" },
		{ -- BST: 205 (Balanced starter with slight attack lean)
			HP = 55,
			Attack = 55,
			Defense = 50,
			SpecialAttack = 40,
			SpecialDefense = 45,
			Speed = 45,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[5] = {"Sand Storm"},
			[9] = {"Bite"},
			[14] = {"Fast Attack"},
		},
		16,
		"Refricamel",
		45.0,
		{["Ears"]=Color3.new(0.541,0.392,0.188),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FridgeMain"]=Color3.new(0.737,0.718,0.808),["FootL"]=Color3.new(0.541,0.392,0.188),["LegL"]=Color3.new(0.541,0.392,0.188),["FootR"]=Color3.new(0.541,0.392,0.188),["LegR"]=Color3.new(0.541,0.392,0.188),["HeadMesh"]=Color3.new(0.541,0.392,0.188),["HeadBlack"]=Color3.new(0.067,0.067,0.067),["Neck1"]=Color3.new(0.541,0.392,0.188),["Neck2"]=Color3.new(0.541,0.392,0.188),["Neck3"]=Color3.new(0.541,0.392,0.188),["Neck4"]=Color3.new(0.541,0.392,0.188),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		45,
		40
	),
	["Refricamel"] = createCreature(
		5,
		"Refricamel",
		"rbxassetid://87061586813050",
		"rbxassetid://121958256639798",
		"Now with proper refrigeration coils, it keeps its cool in deserts and stores snacks for later.",
		{ "Ground" },
		{ -- BST: 290 (Bulkier mid-evolution)
			HP = 75,
			Attack = 75,
			Defense = 70,
			SpecialAttack = 60,
			SpecialDefense = 65,
			Speed = 70,
		},
		{
			[1] = {"Tackle", "Scratch", "Sand Storm"},
			[16] = {"Bite"},
			[20] = {"Fast Attack"},
			[26] = {"Crunch"},
			[32] = {"Earthquake"},
		},
		36,
		"Glacimel",
		95.0,
		{["BackLeftFoot"]=Color3.new(0.471,0.278,0.761),["BackLeftLeg"]=Color3.new(0.541,0.392,0.188),["BackRightFoot"]=Color3.new(0.471,0.278,0.761),["BackRightLeg"]=Color3.new(0.541,0.392,0.188),["Body"]=Color3.new(0.737,0.718,0.808),["Ears"]=Color3.new(0.541,0.392,0.188),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FridgeHandles"]=Color3.new(0.373,0.373,0.373),["FrontLeftFoot"]=Color3.new(0.471,0.278,0.761),["FrontLeftLeg"]=Color3.new(0.541,0.392,0.188),["FrontRightFoot"]=Color3.new(0.471,0.278,0.761),["FrontRightLeg"]=Color3.new(0.541,0.392,0.188),["HeadMesh"]=Color3.new(0.541,0.392,0.188),["Head_Black"]=Color3.new(0.000,0.000,0.000),["Neck1"]=Color3.new(0.541,0.392,0.188),["Neck2"]=Color3.new(0.541,0.392,0.188),["CubeTop"]=Color3.new(0.678,0.451,1.000),["Neck3"]=Color3.new(0.541,0.392,0.188),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		40
	),
	["Glacimel"] = createCreature(
		6,
		"Glacimel",
		"rbxassetid://140155612806063",
		"rbxassetid://nil",
		"Its freezer core turned cryogenic. It sculpts dune-ice into elegant ridges as it roams.",
		{ "Ground", "Ice" },
		{ -- BST: 360 (Tanky final evolution with power)
			HP = 95,
			Attack = 95,
			Defense = 90,
			SpecialAttack = 85,
			SpecialDefense = 85,
			Speed = 80,
		},
		{
			[1] = {"Sand Storm", "Bite", "Fast Attack"},
			[20] = {"Crunch"},
			[28] = {"Earthquake"},
			[36] = {"Dive Bomb"},  -- Ice wind attack flavor
		},
		nil,
		nil,
		180.0,
		{["BackLeftFoot"]=Color3.new(0.471,0.278,0.761),["BackLeftLeg"]=Color3.new(0.471,0.278,0.761),["BackRightFoot"]=Color3.new(0.471,0.278,0.761),["BackRightLeg"]=Color3.new(0.471,0.278,0.761),["Body"]=Color3.new(0.639,0.635,0.647),["CubeTop"]=Color3.new(0.678,0.451,1.000),["Ears"]=Color3.new(0.541,0.392,0.188),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FrontLeftFoot"]=Color3.new(0.471,0.278,0.761),["FrontLeftLeg"]=Color3.new(0.471,0.278,0.761),["FrontRightFoot"]=Color3.new(0.471,0.278,0.761),["FrontRightLeg"]=Color3.new(0.471,0.278,0.761),["HeadMesh"]=Color3.new(0.541,0.392,0.188),["Head_Black"]=Color3.new(0.067,0.067,0.067),["IceHead"]=Color3.new(0.678,0.451,1.000),["Inside"]=Color3.new(0.639,0.635,0.647),["NeckIce"]=Color3.new(0.545,0.365,0.812),["NeckNormal"]=Color3.new(0.541,0.392,0.188),["Tail"]=Color3.new(0.541,0.271,0.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		40
	),

	--============================================================================
	-- STARTER LINE 3: Twirlina (Fairy -> Fairy/Steel)
	-- Role: Speedy special-feeling attacker with good defensive typing
	--============================================================================
	["Twirlina"] = createCreature(
		7,
		"Twirlina",
		"rbxassetid://91063591914096",
		"rbxassetid://100838791633365",
		"A tiny cup dancer who practices spins until she's dizzy with delight. Her grace belies her power.",
		{ "Fairy" },
		{ -- BST: 205 (Speed-focused starter)
			HP = 45,
			Attack = 50,
			Defense = 45,
			SpecialAttack = 60,
			SpecialDefense = 50,
			Speed = 65,
		},
		{
			[1] = {"Tackle", "Dance Strike"},
			[5] = {"Fast Attack"},
			[9] = {"Dazzle Beam"},
			[14] = {"Fairy Strike"},
		},
		16,
		"Ballerina Cappuccina",
		6.5,
		{["ArmL"]=Color3.new(0.976,0.765,0.576),["ArmR"]=Color3.new(0.976,0.765,0.576),["EyesBlack"]=Color3.new(0.067,0.067,0.067),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FaceParts"]=Color3.new(0.016,0.686,0.925),["FootL"]=Color3.new(0.529,0.812,1.000),["FootR"]=Color3.new(0.529,0.812,1.000),["HandL"]=Color3.new(0.016,0.686,0.925),["HandR"]=Color3.new(0.016,0.686,0.925),["HeadMesh"]=Color3.new(0.871,0.945,1.000),["Hips"]=Color3.new(0.420,0.757,1.000),["LegL"]=Color3.new(0.773,0.875,1.000),["LegR"]=Color3.new(0.773,0.875,1.000),["Skirt"]=Color3.new(0.290,0.557,0.847),["Torso"]=Color3.new(0.239,0.463,0.702),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		45,
		95
	),
	["Ballerina Cappuccina"] = createCreature(
		8,
		"Ballerina Cappuccina",
		"rbxassetid://88795634363100",
		"rbxassetid://116535707779582",
		"A poised ballerina with a swirling coffee cup for a head. She pirouettes into battle with elegance.",
		{ "Fairy" },
		{ -- BST: 295 (Fast mid-evolution with balanced offense/defense)
			HP = 65,
			Attack = 70,
			Defense = 60,
			SpecialAttack = 85,
			SpecialDefense = 70,
			Speed = 100,
		},
		{
			[1] = {"Dance Strike", "Fast Attack", "Dazzle Beam"},
			[16] = {"Fairy Strike"},
			[22] = {"Sunbeam"},
			[30] = {"Mind Slam"},
		},
		36,
		"Primarina Ballerina",
		14.0,
		{["ArmL"]=Color3.new(0.976,0.765,0.576),["ArmR"]=Color3.new(0.976,0.765,0.576),["CupHandle"]=Color3.new(0.871,0.945,1.000),["EyesBlack"]=Color3.new(0.067,0.067,0.067),["EyesBrown"]=Color3.new(0.482,0.592,0.635),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FootL"]=Color3.new(0.529,0.812,1.000),["FootR"]=Color3.new(0.529,0.812,1.000),["HandL"]=Color3.new(0.016,0.686,0.925),["HandR"]=Color3.new(0.016,0.686,0.925),["HeadMesh"]=Color3.new(0.871,0.945,1.000),["Hips"]=Color3.new(0.420,0.757,1.000),["LegL"]=Color3.new(0.773,0.875,1.000),["LegR"]=Color3.new(0.773,0.875,1.000),["MouthWhite"]=Color3.new(0.973,0.973,0.973),["NoseMouth"]=Color3.new(0.016,0.686,0.925),["Skirt"]=Color3.new(0.290,0.557,0.847),["Torso"]=Color3.new(0.239,0.463,0.702),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		95
	),
	["Primarina Ballerina"] = createCreature(
		9,
		"Primarina Ballerina",
		"rbxassetid://131374577373923",
		"rbxassetid://91194678993432",
		"The cup now forged into steel trim, her grand jeté leaves shimmering trails. A master of dance and defense.",
		{ "Fairy", "Steel" },
		{ -- BST: 365 (Excellent defensive typing, fast and powerful)
			HP = 80,
			Attack = 90,
			Defense = 85,
			SpecialAttack = 110,
			SpecialDefense = 95,
			Speed = 110,
		},
		{
			[1] = {"Dance Strike", "Dazzle Beam", "Fairy Strike"},
			[22] = {"Sunbeam"},
			[30] = {"Shield Bash"},
			[38] = {"Mind Slam"},
			[46] = {"Grand Slam"},
		},
		nil,
		nil,
		24.0,
		{["Crown"]=Color3.new(0.988,0.980,1.000),["CupHandle"]=Color3.new(0.988,0.980,1.000),["EyesBlack"]=Color3.new(0.067,0.067,0.067),["EyesBrown"]=Color3.new(0.482,0.592,0.635),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FootL"]=Color3.new(0.675,0.831,0.886),["FootR"]=Color3.new(0.675,0.831,0.886),["ForeArmL"]=Color3.new(0.976,0.765,0.576),["ForeArmR"]=Color3.new(0.976,0.765,0.576),["HandL"]=Color3.new(0.988,0.980,1.000),["HandR"]=Color3.new(0.988,0.980,1.000),["HeadMesh"]=Color3.new(1.000,0.910,0.890),["LegL"]=Color3.new(0.988,0.980,1.000),["LegR"]=Color3.new(0.988,0.980,1.000),["MouthWhite"]=Color3.new(0.973,0.973,0.973),["Neck"]=Color3.new(0.988,0.980,1.000),["NoseMouth"]=Color3.new(0.016,0.686,0.925),["Seperator"]=Color3.new(0.639,0.635,0.647),["SkirtPink"]=Color3.new(0.722,0.890,1.000),["SkirtWhite"]=Color3.new(0.988,0.980,1.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["UpperArmL"]=Color3.new(0.988,0.980,1.000),["UpperArmR"]=Color3.new(0.988,0.980,1.000),["Torso"]=Color3.new(0.988,0.980,1.000)},
		"Advanced",
		45,
		95
	),

	--============================================================================
	-- WILD CREATURES: Early-game commons and uncommons
	--============================================================================
	
	-- 10: Frulli line (fast 3-stage bird -> Flying/Electric sweeper)
	["Frulli Frulla"] = createCreature(
		10,
		"Frulli Frulla",
		"rbxassetid://96032956018193",
		"rbxassetid://91862509821498",
		"A jittery coffee-fueled bird with orange glasses. Its caffeine-enhanced reflexes make it hard to catch.",
		{ "Flying" },
		{ -- BST: 220 (Fast but fragile first-stage)
			HP = 40,
			Attack = 48,
			Defense = 37,
			SpecialAttack = 40,
			SpecialDefense = 35,
			Speed = 95,
		},
		{
			[1] = {"Tackle", "Peck"},
			[5] = {"Fast Attack"},
			[9] = {"Perch"},
			[12] = {"Static Peck"},
			[15] = {"Bite"},
		},
		16,
		"Frulilala",
		2.8,
		{["Bird_Beak"]=Color3.new(1.000,0.690,0.000),["Bird_Beak.001"]=Color3.new(1.000,0.690,0.000),["Bird_Beak.002"]=Color3.new(1.000,0.690,0.000),["Bird_Beak.003"]=Color3.new(1.000,0.690,0.000),["Bird_BodyBack"]=Color3.new(0.549,0.506,0.192),["Bird_BodyFront"]=Color3.new(0.769,0.757,0.392),["Bird_Glasses"]=Color3.new(0.973,0.973,0.973),["Bird_GlassesGlass"]=Color3.new(0.145,0.141,0.227),["Bird_Head"]=Color3.new(0.549,0.506,0.192),["Bird_Legs"]=Color3.new(1.000,0.690,0.000),["Bird_Wings"]=Color3.new(0.549,0.506,0.192),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		255,  -- Very common catch rate (max)
		50
	),
	["Frulilala"] = createCreature(
		31,
		"Frulilala",
		"rbxassetid://114056605728290",
		"rbxassetid://85886665555660",
		"The caffeine finally focuses into static. Its wingbeats crackle as it darts between rooftops.",
		{ "Flying", "Electric" },
		{ -- BST: 295 (Agile mid-evolution with better punch)
			HP = 60,
			Attack = 70,
			Defense = 60,
			SpecialAttack = 65,
			SpecialDefense = 55,
			Speed = 105,
		},
		{
			[1] = {"Tackle", "Peck", "Fast Attack", "Perch", "Static Peck", "Bite"},
			[18] = {"Duststorm Dash"},
			[22] = {"Dive Bomb"},
			[28] = {"Thunder Burst"},
			[32] = {"Crunch"},
		},
		34,
		"Frulli Fruletro",
		6.5,
		nil,
		"Advanced",
		120, -- Uncommon mid-stage
		50
	),
	["Frulli Fruletro"] = createCreature(
		32,
		"Frulli Fruletro",
		"rbxassetid://0",
		"rbxassetid://0",
		"A hypercharged flyer that channels thunderstorms through its feathers. It blitzes foes before they can react.",
		{ "Flying", "Electric" },
		{ -- BST: 375 (Lightning-fast final evolution)
			HP = 75,
			Attack = 95,
			Defense = 80,
			SpecialAttack = 105,
			SpecialDefense = 75,
			Speed = 125,
		},
		{
			[1] = {"Tackle", "Fast Attack", "Perch", "Static Peck", "Duststorm Dash"},
			[22] = {"Dive Bomb"},
			[28] = {"Thunder Burst"},
			[36] = {"Shield Bash"},
			[44] = {"Grand Slam"},
			[50] = {"Crunch"},
		},
		nil,
		nil,
		9.5,
		nil,
		"Advanced",
		45,  -- Rare, final-stage catch rate
		50
	),

	--============================================================================
	-- Tim Line (Normal type 2-stage - "Rattata equivalent")
	--============================================================================
	["Timmy Cheddar"] = createCreature(
		11,
		"Timmy Cheddar",
		"rbxassetid://133982229544496",
		"rbxassetid://110379113786610",
		"A young, ambitious rat with big dreams. Still learning the ropes of the underworld but shows great potential.",
		{ "Normal" },
		{ -- BST: 175 (Very weak early-game fodder, but evolves quickly)
			HP = 40,
			Attack = 45,
			Defense = 35,
			SpecialAttack = 35,
			SpecialDefense = 35,
			Speed = 55,
		},
		{
			[1] = {"Scratch", "Tackle"},
			[5] = {"Fast Attack"},
			[9] = {"Bite"},
			[14] = {"Crunch"},
		},
		18,  -- Early evolution
		"Tim Cheese",
		3.5,
		{["ArmL"]=Color3.new(0.937,0.722,0.220),["ArmR"]=Color3.new(0.937,0.722,0.220),["EarLInner"]=Color3.new(0.843,0.773,0.604),["EarLOuter"]=Color3.new(0.486,0.612,0.420),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["EarROuter"]=Color3.new(0.486,0.612,0.420),["FootL"]=Color3.new(0.486,0.612,0.420),["FootR"]=Color3.new(0.486,0.612,0.420),["GlassesFrame"]=Color3.new(0.973,0.973,0.973),["GlassesLens"]=Color3.new(0.384,0.145,0.820),["HandL"]=Color3.new(0.486,0.612,0.420),["HandR"]=Color3.new(0.486,0.612,0.420),["HeadPart"]=Color3.new(0.486,0.612,0.420),["LegL"]=Color3.new(0.937,0.722,0.220),["LegR"]=Color3.new(0.937,0.722,0.220),["Nose"]=Color3.new(0.906,0.584,0.573),["Shirt"]=Color3.new(0.827,0.827,0.827),["Tie"]=Color3.new(0.906,0.396,0.565),["Torso"]=Color3.new(0.937,0.722,0.220),["Whiskers"]=Color3.new(0.827,0.827,0.827),["HR2"]=Color3.new(0.639,0.635,0.647),["EarRInner"]=Color3.new(0.843,0.773,0.604)},
		"Basic",
		255,  -- Very common (max)
		50    -- Balanced gender ratio (rats)
	),
	["Tim Cheese"] = createCreature(
		12,
		"Tim Cheese",
		"rbxassetid://94327505972766",
		"rbxassetid://89991911558326",
		"A sharp-dressed humanoid rat who oozes confidence and cunning. Said to run the city's underworld.",
		{ "Normal", "Dark" },  -- Gains Dark type on evolution (thematic)
		{ -- BST: 280 (Decent evolved form with good speed)
			HP = 60,
			Attack = 75,
			Defense = 50,
			SpecialAttack = 45,
			SpecialDefense = 50,
			Speed = 95,
		},
		{
			[1] = {"Scratch", "Tackle", "Fast Attack", "Bite"},
			[18] = {"Crunch"},
			[26] = {"Double Kick"},
			[34] = {"Grand Slam"},
		},
		nil,
		nil,
		8.5,
		{["ArmL"]=Color3.new(0.533,0.243,0.243),["ArmR"]=Color3.new(0.533,0.243,0.243),["EarLInner"]=Color3.new(0.800,0.557,0.412),["EarLOuter"]=Color3.new(0.835,0.353,0.161),["EarRInner"]=Color3.new(0.800,0.557,0.412),["EarROuter"]=Color3.new(0.835,0.353,0.161),["FootL"]=Color3.new(0.533,0.243,0.243),["FootR"]=Color3.new(0.533,0.243,0.243),["GlassesFrame"]=Color3.new(0.973,0.973,0.973),["GlassesLens"]=Color3.new(0.067,0.067,0.067),["HandL"]=Color3.new(0.533,0.243,0.243),["HandR"]=Color3.new(0.533,0.243,0.243),["HeadPart"]=Color3.new(0.835,0.353,0.161),["LegL"]=Color3.new(0.533,0.243,0.243),["LegR"]=Color3.new(0.533,0.243,0.243),["Nose"]=Color3.new(0.631,0.769,0.549),["Shirt"]=Color3.new(0.639,0.635,0.647),["Tie"]=Color3.new(0.647,0.188,0.188),["Torso"]=Color3.new(0.533,0.243,0.243),["Whiskers"]=Color3.new(0.580,0.745,0.506),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HR2"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		127,  -- Uncommon (evolved form)
		50
	),

	--============================================================================
	-- Burbaloni (Single-stage rare - "Snorlax-lite equivalent")
	--============================================================================
	["Burbaloni Lulliloli"] = createCreature(
		13,
		"Burbaloni Lulliloli",
		"rbxassetid://77803433335556",
		"rbxassetid://100237176694463",
		"A divine capybara within a coconut, worshipped for its calm yet immense power. Extremely rare.",
		{ "Ground", "Normal" },
		{ -- BST: 320 (Strong single-stage rare, very tanky)
			HP = 100,
			Attack = 80,
			Defense = 85,
			SpecialAttack = 60,
			SpecialDefense = 80,
			Speed = 55,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[8] = {"Sand Storm"},
			[14] = {"Bite"},
			[20] = {"Fast Attack"},
			[28] = {"Earthquake"},
			[36] = {"Crunch"},
		},
		nil,
		nil,
		85.0,
		{["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["Ears"]=Color3.new(0.322,0.486,0.682),["Coconut"]=Color3.new(0.706,0.824,0.894),["Back_left_leg"]=Color3.new(0.035,0.537,0.812),["Back_right_leg"]=Color3.new(0.035,0.537,0.812),["Body"]=Color3.new(0.129,0.329,0.725),["Eyes"]=Color3.new(0.067,0.067,0.067),["Front_left_leg"]=Color3.new(0.035,0.537,0.812),["Front_right_leg"]=Color3.new(0.035,0.537,0.812),["Head"]=Color3.new(0.035,0.537,0.812),["Teeth"]=Color3.new(1.000,1.000,1.000),["Nose"]=Color3.new(0.067,0.067,0.067)},
		"Rare",
		45,   -- Rare catch rate
		50
	),

	--============================================================================
	-- Jungle Chimps (Grass type 2-stage line)
	--============================================================================
	["Chimpanini"] = createCreature(
		14,
		"Chimpanini",
		"rbxassetid://nil",
		nil,
		"A hyperactive jungle prankster that flings seeds and swings through trees with reckless abandon.",
		{ "Grass" },
		{ -- BST: 195 (Speedy early-game grass type)
			HP = 45,
			Attack = 50,
			Defense = 40,
			SpecialAttack = 45,
			SpecialDefense = 40,
			Speed = 60,
		},
		{
			[1] = {"Scratch", "Tackle"},
			[5] = {"Vine Whip"},
			[9] = {"Fast Attack"},
			[14] = {"Seed Toss"},
		},
		20,
		"Chimpanzini Bananini",
		12.0,
		{["HeadWhite"]=Color3.new(0.973,0.973,0.973),["ArmL"]=Color3.new(0.961,0.804,0.188),["Tail1"]=Color3.new(0.416,0.224,0.035),["Tail2"]=Color3.new(0.416,0.224,0.035),["Tail3"]=Color3.new(0.416,0.224,0.035),["Tail4"]=Color3.new(0.416,0.224,0.035),["LegL"]=Color3.new(0.961,0.804,0.188),["Torso"]=Color3.new(0.992,0.918,0.553),["LegR"]=Color3.new(0.961,0.804,0.188),["ArmR"]=Color3.new(0.961,0.804,0.188),["Tail5"]=Color3.new(0.416,0.224,0.035),["HandL"]=Color3.new(0.416,0.224,0.035),["HandR"]=Color3.new(0.416,0.224,0.035),["HeadPastel"]=Color3.new(1.000,0.675,0.565),["FootL"]=Color3.new(0.416,0.224,0.035),["FootR"]=Color3.new(0.416,0.224,0.035),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HeadBlack"]=Color3.new(0.067,0.067,0.067),["HeadGreen"]=Color3.new(0.416,0.224,0.035)},
		"Basic",
		190,  -- Common
		50
	),
	["Chimpanzini Bananini"] = createCreature(
		15,
		"Chimpanzini Bananini",
		"rbxassetid://nil",
		nil,
		"Though armless, it hops and rolls through the jungle with surprising speed. Its banana body stores energy from sunlight.",
		{ "Grass" },
		{ -- BST: 285 (Good evolved form, speedy attacker)
			HP = 65,
			Attack = 75,
			Defense = 55,
			SpecialAttack = 65,
			SpecialDefense = 55,
			Speed = 90,
		},
		{
			[1] = {"Scratch", "Vine Whip", "Fast Attack"},
			[20] = {"Seed Toss"},
			[26] = {"Leaf Slash"},
			[34] = {"Grand Slam"},
		},
		nil,
		nil,
		22.0,
		{["HeadWhite"]=Color3.new(0.973,0.973,0.973),["ArmL"]=Color3.new(0.961,0.804,0.188),["Tail1"]=Color3.new(0.204,0.557,0.251),["HeadGreen"]=Color3.new(0.533,0.325,0.204),["Tail2"]=Color3.new(0.204,0.557,0.251),["Tail3"]=Color3.new(0.204,0.557,0.251),["Tail4"]=Color3.new(0.204,0.557,0.251),["LegL"]=Color3.new(0.961,0.804,0.188),["Torso"]=Color3.new(0.992,0.918,0.553),["LegR"]=Color3.new(0.961,0.804,0.188),["ArmR"]=Color3.new(0.961,0.804,0.188),["Tail5"]=Color3.new(0.416,0.224,0.035),["HandL"]=Color3.new(0.416,0.224,0.035),["HandR"]=Color3.new(0.416,0.224,0.035),["HeadPastel"]=Color3.new(1.000,0.675,0.514),["FootL"]=Color3.new(0.416,0.224,0.035),["FootR"]=Color3.new(0.416,0.224,0.035),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HeadBlack"]=Color3.new(0.067,0.067,0.067)},
		"Advanced",
		90,
		50
	),

	--============================================================================
	-- Duckaroo (Single-stage rare - Flying/Ground cowboy duck)
	--============================================================================
	["Duckaroo"] = createCreature(
		16,
		"Duckaroo",
		"rbxassetid://nil",
		nil,
		"A cowboy duck that patrols dry plains and dusty canyons, kicking up sand as it chases bandits.",
		{ "Flying", "Ground" },
		{ -- BST: 310 (Strong single-stage rare, offensive powerhouse)
			HP = 65,
			Attack = 90,
			Defense = 60,
			SpecialAttack = 55,
			SpecialDefense = 60,
			Speed = 95,
		},
		{
			[1] = {"Peck", "Tackle"},
			[6] = {"Fast Attack"},
			[10] = {"Sand Storm"},
			[16] = {"Bite"},
			[22] = {"Duststorm Dash"},
			[30] = {"Earthquake"},
			[38] = {"Dive Bomb"},
			[46] = {"Crunch"},
		},
		nil,
		nil,
		18.0,
		{["Beak"]=Color3.new(1.000,0.647,0.000),["Body"]=Color3.new(0.824,0.706,0.549),["BootL"]=Color3.new(0.333,0.420,0.184),["BootR"]=Color3.new(0.333,0.420,0.184),["EyeL"]=Color3.new(0.294,0.180,0.020),["EyeR"]=Color3.new(0.294,0.180,0.020),["FootBackL"]=Color3.new(0.761,0.698,0.502),["FootBackR"]=Color3.new(0.761,0.698,0.502),["FootBuckleL"]=Color3.new(0.149,0.149,0.153),["FootBuckleR"]=Color3.new(0.149,0.149,0.153),["FootStudL"]=Color3.new(0.722,0.525,0.043),["FootStudR"]=Color3.new(0.722,0.525,0.043),["Hat"]=Color3.new(0.333,0.420,0.184),["HatBack"]=Color3.new(0.333,0.420,0.184),["Head"]=Color3.new(0.937,0.902,0.839),["HeelL"]=Color3.new(0.169,0.212,0.094),["HeelR"]=Color3.new(0.169,0.212,0.094),["LowerLegL"]=Color3.new(1.000,0.647,0.000),["LowerLegR"]=Color3.new(1.000,0.647,0.000),["Neck"]=Color3.new(0.937,0.902,0.839),["StudL"]=Color3.new(0.722,0.525,0.043),["StudL_L"]=Color3.new(0.722,0.525,0.043),["StudMiddle"]=Color3.new(0.722,0.525,0.043),["StudR"]=Color3.new(0.722,0.525,0.043),["StudR_R"]=Color3.new(0.722,0.525,0.043),["Tail"]=Color3.new(0.824,0.706,0.549),["UpperLegL"]=Color3.new(0.824,0.706,0.549),["UpperLegR"]=Color3.new(0.824,0.706,0.549),["WingL"]=Color3.new(0.824,0.706,0.549),["WingR"]=Color3.new(0.824,0.706,0.549),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Rare",
		60,   -- Rare catch rate
		40
	),

	--============================================================================
	-- Doggolino (Single-stage Fire type - uncommon)
	--============================================================================
	["Doggolino"] = createCreature(
		18,
		"Doggolino",
		"rbxassetid://93010466071138",
		"rbxassetid://88110777970394",
		"A furious hot-dog spirit. It barks in sizzles and pops, leaving scorch marks where it walks.",
		{ "Fire" },
		{ -- BST: 265 (Good single-stage uncommon, offensive Fire type)
			HP = 60,
			Attack = 75,
			Defense = 50,
			SpecialAttack = 70,
			SpecialDefense = 50,
			Speed = 80,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[6] = {"Fast Attack"},
			[12] = {"Bite"},
			[18] = {"Crunch"},
			[26] = {"Grand Slam"},
		},
		nil,
		nil,
		12.0,
		{["BottomTeeth"]=Color3.new(0.973,0.973,0.973),["Bun"]=Color3.new(0.639,0.294,0.294),["Eyes"]=Color3.new(0.067,0.067,0.067),["Ketchup"]=Color3.new(0.639,0.294,0.294),["Nose"]=Color3.new(0.067,0.067,0.067),["Red"]=Color3.new(0.996,0.953,0.733),["Tongue"]=Color3.new(0.769,0.157,0.110),["TopTeeth"]=Color3.new(0.973,0.973,0.973),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		150,  -- Uncommon
		50
	),

	--============================================================================
	-- Tadbalabu Line (Grass 3-stage - "Bulbasaur equivalent")
	--============================================================================
	["Tadbalabu"] = createCreature(
		19,
		"Tadbalabu",
		"rbxassetid://73449852108494",
		"rbxassetid://99593933734854",
		"A little frog-tad that drums on puddles with its tail. Its rhythm attracts other creatures.",
		{ "Grass" },
		{ -- BST: 195 (Basic grass type)
			HP = 50,
			Attack = 45,
			Defense = 45,
			SpecialAttack = 55,
			SpecialDefense = 50,
			Speed = 55,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[5] = {"Vine Whip"},
			[9] = {"Fast Attack"},
			[14] = {"Seed Toss"},
		},
		16,
		"Boneca Ambalabu",
		6.0,
		{["LToeNails"]=Color3.new(0.973,0.973,0.973),["RightLeg"]=Color3.new(0.769,0.157,0.110),["RToeNails"]=Color3.new(0.973,0.973,0.973),["RightLegTop"]=Color3.new(0.200,0.345,0.510),["Torso"]=Color3.new(0.686,0.867,1.000),["BottomHead"]=Color3.new(0.937,0.722,0.220),["Nose"]=Color3.new(0.067,0.067,0.067),["TopHead"]=Color3.new(0.769,0.157,0.110),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HR2"]=Color3.new(0.639,0.635,0.647),["Eyes"]=Color3.new(0.106,0.165,0.208),["LeftLeg"]=Color3.new(0.769,0.157,0.110),["LeftLegTop"]=Color3.new(0.200,0.345,0.510)},
		"Basic",
		190,
		50
	),
	["Boneca Ambalabu"] = createCreature(
		20,
		"Boneca Ambalabu",
		"rbxassetid://75248703568577",
		"rbxassetid://111827317838725",
		"It grows longer limbs like a doll, keeping a steady jungle rhythm that boosts nearby plants.",
		{ "Grass" },
		{ -- BST: 280 (Mid-evolution, balanced)
			HP = 70,
			Attack = 65,
			Defense = 60,
			SpecialAttack = 75,
			SpecialDefense = 65,
			Speed = 85,
		},
		{
			[1] = {"Vine Whip", "Seed Toss", "Fast Attack"},
			[18] = {"Leaf Slash"},
			[26] = {"Double Kick"},
		},
		36,
		"Ambalabu Ton-Ton",
		15.0,
		{["Nose"]=Color3.new(0.067,0.067,0.067),["Eyes"]=Color3.new(0.973,0.851,0.427),["TopHead"]=Color3.new(1.000,0.000,0.000),["Torso"]=Color3.new(0.051,0.412,0.675),["BottomHead"]=Color3.new(0.937,0.722,0.220),["LeftLeg"]=Color3.new(1.000,0.000,0.000),["RightLeg"]=Color3.new(1.000,0.000,0.000),["RToeNails"]=Color3.new(0.973,0.973,0.973),["LToeNails"]=Color3.new(0.973,0.973,0.973),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		90,
		50
	),
	["Ambalabu Ton-Ton"] = createCreature(
		21,
		"Ambalabu Ton-Ton",
		"rbxassetid://nil",
		nil,
		"Stacked like drums, it pounds a beat that spurs seedlings to sprout. Its rhythm can shake the earth.",
		{ "Grass", "Fighting" },  -- Gains Fighting on final evolution
		{ -- BST: 350 (Strong final evolution)
			HP = 90,
			Attack = 90,
			Defense = 75,
			SpecialAttack = 85,
			SpecialDefense = 80,
			Speed = 95,
		},
		{
			[1] = {"Vine Whip", "Seed Toss", "Leaf Slash"},
			[28] = {"Double Kick"},
			[36] = {"Grand Slam"},
			[44] = {"Earthquake"},
		},
		nil,
		nil,
		32.0,
		{["Nose"]=Color3.new(0.067,0.067,0.067),["Eyes"]=Color3.new(0.067,0.067,0.067),["FaceMarks"]=Color3.new(1.000,0.000,0.000),["TopHead"]=Color3.new(1.000,0.000,0.000),["BottomHead"]=Color3.new(0.937,0.722,0.220),["TopHat"]=Color3.new(0.973,0.973,0.973),["Tire1"]=Color3.new(0.624,0.678,0.753),["Tire2"]=Color3.new(0.035,0.537,0.812),["Torso"]=Color3.new(1.000,0.000,0.000),["Tire3"]=Color3.new(0.000,0.063,0.690),["RightLeg"]=Color3.new(1.000,0.000,0.000),["LeftLeg"]=Color3.new(1.000,0.000,0.000),["RToeNail"]=Color3.new(0.973,0.973,0.973),["LToeNail"]=Color3.new(0.973,0.973,0.973),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		50
	),

	--============================================================================
	-- Abrazard (Single-stage Psychic - uncommon magic creature)
	--============================================================================
	["Abrazard"] = createCreature(
		22,
		"Abrazard",
		"rbxassetid://nil",
		nil,
		"A small wizard who loves playful mischief. Its spells are mostly harmless, but its psychic power is no joke.",
		{ "Psychic" },
		{ -- BST: 255 (Glass cannon psychic type)
			HP = 50,
			Attack = 45,
			Defense = 45,
			SpecialAttack = 95,
			SpecialDefense = 55,
			Speed = 75,
		},
		{
			[1] = {"Scratch", "Tackle"},
			[6] = {"Fast Attack"},
			[12] = {"Mind Slam"},
			[18] = {"Dazzle Beam"},
			[26] = {"Sunbeam"},
		},
		nil,
		nil,
		8.0,
		{["ArmL"]=Color3.new(0.369,0.271,0.220),["ArmR"]=Color3.new(0.369,0.271,0.220),["Beard"]=Color3.new(1.000,1.000,1.000),["Candy"]=Color3.new(1.000,0.698,0.094),["EyesBlue"]=Color3.new(1.000,0.698,0.094),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FootL"]=Color3.new(1.000,0.698,0.094),["FootR"]=Color3.new(1.000,0.698,0.094),["Gold"]=Color3.new(1.000,0.698,0.094),["HandL"]=Color3.new(1.000,0.808,0.576),["HandR"]=Color3.new(1.000,0.808,0.576),["HatBottom"]=Color3.new(1.000,0.698,0.094),["HatTop"]=Color3.new(0.369,0.271,0.220),["HeadTop"]=Color3.new(1.000,0.808,0.576),["Torso"]=Color3.new(0.369,0.271,0.220),["Stars"]=Color3.new(1.000,0.698,0.094),["Wood"]=Color3.new(0.412,0.251,0.157),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		120,  -- Uncommon
		40
	),

	--============================================================================
	-- Bolasaeg Selluaim (Single-stage Poison - tanky uncommon)
	--============================================================================
	["Bolasaeg Selluaim"] = createCreature(
		23,
		"Bolasaeg Selluaim",
		"rbxassetid://75020717494654",
		"rbxassetid://98225384445928",
		"A creature made entirely of gelatinous ooze. It slowly devours anything in its path with corrosive acid.",
		{ "Poison" },
		{ -- BST: 285 (Tanky poison type, slow but powerful)
			HP = 95,
			Attack = 70,
			Defense = 80,
			SpecialAttack = 75,
			SpecialDefense = 85,
			Speed = 40,
		},
		{
			[1] = {"Tackle", "Ooze Shot"},
			[6] = {"Scratch"},
			[10] = {"Sludge Puff"},
			[16] = {"Toxic Wave"},
			[24] = {"Corrosive Grasp"},
			[32] = {"Acidic Deluge"},
		},
		nil,
		nil,
		35.0,
		{["jSE"]=Color3.new(0.510,0.604,0.173),["HumanoidRootPart"]=Color3.new(0.067,0.067,0.067),["rSu"]=Color3.new(0.553,0.749,0.125),["TYp"]=Color3.new(0.510,0.604,0.173),["Head"]=Color3.new(0.553,0.749,0.125),["zuB"]=Color3.new(0.553,0.749,0.125),["vhM"]=Color3.new(0.553,0.749,0.125),["Orx"]=Color3.new(0.553,0.749,0.125),["qVd"]=Color3.new(0.553,0.749,0.125),["Main"]=Color3.new(0.553,0.749,0.125),["IKv"]=Color3.new(0.510,0.604,0.173),["BuV"]=Color3.new(0.510,0.604,0.173),["TUQ"]=Color3.new(0.510,0.604,0.173),["nHd"]=Color3.new(0.510,0.604,0.173),["pwZ"]=Color3.new(0.553,0.749,0.125),["Ndd"]=Color3.new(0.553,0.749,0.125),["EyeL"]=Color3.new(0.067,0.067,0.067),["EyeR"]=Color3.new(0.067,0.067,0.067),["eUG"]=Color3.new(0.553,0.749,0.125)},
		"Basic",
		100,  -- Uncommon
		50
	),


	--============================================================================
	-- Trippi Troppi (Water/Normal - tanky water type)
	--============================================================================
	["Trippi Troppi"] = createCreature(
		24,
		"Trippi Troppi",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A fish that adapted to land but never let go of its aquatic nature. Despite its dopey look, it becomes fierce if provoked.",
		{ "Water", "Normal" },
		{ -- BST: 270 (Tanky water type, slow but durable)
			HP = 85,
			Attack = 60,
			Defense = 70,
			SpecialAttack = 65,
			SpecialDefense = 75,
			Speed = 55,
		},
		{
			[1] = {"Tackle", "Water Jet"},
			[6] = {"Bite"},
			[12] = {"Fast Attack"},
			[18] = {"Aqua Slash"},
			[26] = {"Crunch"},
			[34] = {"Hydro Burst"},
		},
		nil,
		nil,
		28.0,
		{["TopFin"]=Color3.new(0.624,0.631,0.675),["BottomFin"]=Color3.new(0.800,0.557,0.412),["HeadMesh"]=Color3.new(0.792,0.796,0.820),["BackFin"]=Color3.new(0.624,0.631,0.675),["Body"]=Color3.new(0.800,1.000,0.800),["ArmR"]=Color3.new(0.388,0.373,0.384),["ArmL"]=Color3.new(0.388,0.373,0.384),["LegR"]=Color3.new(0.388,0.373,0.384),["LegL"]=Color3.new(0.388,0.373,0.384),["BlackEyeR"]=Color3.new(0.067,0.067,0.067),["BlackEyeL"]=Color3.new(0.067,0.067,0.067),["Eyes"]=Color3.new(0.580,0.745,0.506),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		150,  -- Uncommon
		50
	),

	--============================================================================
	-- Il Cacto Hipopotamo (Grass/Ground - defensive rare)
	--============================================================================
	["Il Cacto Hipopotamo"] = createCreature(
		25,
		"Il Cacto Hipopotamo",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A mysterious fusion of flora and fauna. It thrives in deserts, absorbing sunlight and storing water. Fiercely territorial.",
		{ "Grass", "Ground" },
		{ -- BST: 300 (Tanky rare with good mixed bulk)
			HP = 90,
			Attack = 70,
			Defense = 85,
			SpecialAttack = 75,
			SpecialDefense = 80,
			Speed = 55,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[6] = {"Vine Whip"},
			[12] = {"Sand Storm"},
			[18] = {"Seed Toss"},
			[26] = {"Leaf Slash"},
			[34] = {"Earthquake"},
		},
		nil,
		nil,
		145.0,
		{["BodyMain"]=Color3.new(0.549,0.357,0.624),["Ears"]=Color3.new(1.000,0.596,0.863),["FootL"]=Color3.new(0.627,0.518,0.310),["FootR"]=Color3.new(0.627,0.518,0.310),["HeadMesh"]=Color3.new(0.612,0.627,0.706),["EyePartR"]=Color3.new(1.000,0.596,0.863),["EyePartL"]=Color3.new(1.000,0.596,0.863),["EyeR"]=Color3.new(0.973,0.973,0.973),["EyeL"]=Color3.new(0.067,0.067,0.067),["Dark"]=Color3.new(0.408,0.231,0.380),["HeadParts"]=Color3.new(0.243,0.239,0.227),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Rare",
		60,   -- Rare
		50
	),

	--============================================================================
	-- Chicleteira (Steel - defensive uncommon)
	--============================================================================
	["Chicleteira"] = createCreature(
		26,
		"Chicleteira",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A humanoid gumball machine that fires sticky gum to trap prey. Its laughter echoes in alleys long after it's gone.",
		{ "Steel" },
		{ -- BST: 275 (Defensive steel type)
			HP = 75,
			Attack = 55,
			Defense = 90,
			SpecialAttack = 65,
			SpecialDefense = 85,
			Speed = 55,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[6] = {"Fast Attack"},
			[12] = {"Shield Bash"},
			[18] = {"Bite"},
			[26] = {"Grand Slam"},
		},
		nil,
		nil,
		42.0,
		{["Main_Body"]=Color3.new(0.035,0.537,0.812),["Cap"]=Color3.new(0.035,0.537,0.812),["Glass_Container"]=Color3.new(0.388,0.373,0.384),["CoinMain"]=Color3.new(0.388,0.373,0.384),["Coin"]=Color3.new(0.275,0.263,0.271),["Arm_Right"]=Color3.new(0.051,0.412,0.675),["Arm_left"]=Color3.new(0.051,0.412,0.675),["Leg_Right"]=Color3.new(0.035,0.537,0.812),["Leg_Left"]=Color3.new(0.035,0.537,0.812),["Gumballs"]=Color3.new(0.035,0.537,0.812),["Smile"]=Color3.new(0.906,0.906,0.925),["Face_Piece"]=Color3.new(0.427,0.522,0.584),["Eyebrow_Left"]=Color3.new(0.067,0.067,0.067),["Eyebrow_Right"]=Color3.new(0.067,0.067,0.067),["Eyeball_Right"]=Color3.new(0.875,0.875,0.871),["Eyeball_Left"]=Color3.new(0.875,0.875,0.871),["Iris_Left"]=Color3.new(0.067,0.067,0.067),["Iris_Right"]=Color3.new(0.067,0.067,0.067),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		120,  -- Uncommon
		50
	),

	--============================================================================
	-- Špijuniro Golubiro (Flying/Steel - speedy rare spy pigeon)
	--============================================================================
	["Špijuniro Golubiro"] = createCreature(
		27,
		"Špijuniro Golubiro",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A mechanical pigeon that acts as a covert agent. Its lens-like eyes record everything. It vanishes the moment it's spotted.",
		{ "Flying", "Steel" },
		{ -- BST: 295 (Fast and evasive rare)
			HP = 60,
			Attack = 70,
			Defense = 75,
			SpecialAttack = 65,
			SpecialDefense = 70,
			Speed = 90,
		},
		{
			[1] = {"Peck", "Tackle"},
			[6] = {"Fast Attack"},
			[12] = {"Dive Bomb"},
			[18] = {"Shield Bash"},
			[26] = {"Duststorm Dash"},
			[34] = {"Grand Slam"},
		},
		nil,
		nil,
		8.5,
		{["AntennaOne"]=Color3.new(0.208,0.208,0.208),["Armour"]=Color3.new(0.412,0.400,0.361),["AtnennaTwo"]=Color3.new(0.208,0.208,0.208),["Beak"]=Color3.new(0.106,0.165,0.208),["BodyMain"]=Color3.new(0.486,0.361,0.275),["Box"]=Color3.new(0.388,0.373,0.384),["Camera"]=Color3.new(0.208,0.208,0.208),["Communication"]=Color3.new(0.208,0.208,0.208),["Connector"]=Color3.new(0.208,0.208,0.208),["DeviceL"]=Color3.new(0.208,0.208,0.208),["DeviceR"]=Color3.new(0.208,0.208,0.208),["EyesWhite"]=Color3.new(1.000,0.690,0.000),["FootL"]=Color3.new(0.745,0.675,0.529),["FootR"]=Color3.new(0.745,0.675,0.529),["Iris"]=Color3.new(0.588,0.404,0.000),["WingL"]=Color3.new(0.486,0.361,0.275),["WingR"]=Color3.new(0.486,0.361,0.275),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Rare",
		75,   -- Rare
		50
	),

	--============================================================================
	-- Avocadini Guffo (Grass - tanky uncommon owl)
	--============================================================================
	["Avocadini Guffo"] = createCreature(
		28,
		"Avocadini Guffo",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A plump owl with the body of an avocado. Its wings are too small to fly, so it waddles instead. Rich in nutrients.",
		{ "Grass" },
		{ -- BST: 260 (Bulky grass type, slow but tanky)
			HP = 80,
			Attack = 60,
			Defense = 70,
			SpecialAttack = 65,
			SpecialDefense = 75,
			Speed = 50,
		},
		{
			[1] = {"Tackle", "Peck"},
			[6] = {"Vine Whip"},
			[12] = {"Seed Toss"},
			[18] = {"Perch"},
			[26] = {"Leaf Slash"},
		},
		nil,
		nil,
		18.0,
		{["Body"]=Color3.new(0.514,0.365,0.694),["Crest"]=Color3.new(0.518,0.216,0.502),["Eye_Ring_Thing"]=Color3.new(0.792,0.749,0.639),["PulpTwo"]=Color3.new(0.412,0.251,0.157),["Right_Leg"]=Color3.new(0.337,0.259,0.212),["Left_Leg"]=Color3.new(0.337,0.259,0.212),["Right_Eye"]=Color3.new(0.396,0.165,0.384),["Left_Eye"]=Color3.new(0.396,0.165,0.384),["Right_Wing"]=Color3.new(0.396,0.165,0.384),["Left_Wing"]=Color3.new(0.396,0.165,0.384),["Black_Right"]=Color3.new(0.067,0.067,0.067),["Pulp"]=Color3.new(0.412,0.251,0.157),["White_Right"]=Color3.new(0.973,0.973,0.973),["Black_Left"]=Color3.new(0.067,0.067,0.067),["White_Left"]=Color3.new(0.973,0.973,0.973),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		150,  -- Uncommon
		50
	),

	--============================================================================
	-- Bombombini Gusini (Flying/Steel - fast and powerful rare)
	--============================================================================
	["Bombombini Gusini"] = createCreature(
		29,
		"Bombombini Gusini",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A fusion of goose and fighter jet, known for breaking the sound barrier while honking furiously. Extremely aggressive.",
		{ "Flying", "Steel" },
		{ -- BST: 320 (Powerful rare, fast attacker)
			HP = 70,
			Attack = 85,
			Defense = 65,
			SpecialAttack = 75,
			SpecialDefense = 65,
			Speed = 100,
		},
		{
			[1] = {"Peck", "Tackle"},
			[6] = {"Fast Attack"},
			[12] = {"Shield Bash"},
			[18] = {"Dive Bomb"},
			[26] = {"Duststorm Dash"},
			[34] = {"Grand Slam"},
			[42] = {"Earthquake"},
		},
		nil,
		nil,
		35.0,
		{["Beak"]=Color3.new(0.855,0.522,0.255),["BlackNose"]=Color3.new(0.067,0.067,0.067),["Torso"]=Color3.new(0.961,0.804,0.188),["WingR"]=Color3.new(0.973,0.973,0.973),["Eye"]=Color3.new(0.067,0.067,0.067),["EyeWhite"]=Color3.new(0.973,0.973,0.973),["FootL"]=Color3.new(0.886,0.608,0.251),["FootR"]=Color3.new(0.886,0.608,0.251),["Head"]=Color3.new(0.961,0.804,0.188),["LegL"]=Color3.new(0.886,0.608,0.251),["Middle"]=Color3.new(0.973,0.973,0.973),["ThighL"]=Color3.new(0.961,0.804,0.188),["ThighR"]=Color3.new(0.961,0.804,0.188),["C_R"]=Color3.new(0.035,0.537,0.812),["WingL"]=Color3.new(0.973,0.973,0.973),["WingBack"]=Color3.new(0.973,0.973,0.973),["WingBackBottom"]=Color3.new(0.973,0.973,0.973),["C_L"]=Color3.new(0.035,0.537,0.812),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["LegR"]=Color3.new(0.886,0.608,0.251)},
		"Rare",
		45,   -- Rare
		50
	),

	--============================================================================
	-- Brr Brr Patapim (Grass - tanky defensive common)
	--============================================================================
	["Brr Brr Patapim"] = createCreature(
		30,
		"Brr Brr Patapim",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A peculiar grass creature with extremely thick bark. It moves slowly but can take enormous punishment.",
		{ "Grass" },
		{ -- BST: 250 (Tanky slow defender)
			HP = 90,
			Attack = 50,
			Defense = 80,
			SpecialAttack = 55,
			SpecialDefense = 85,
			Speed = 30,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[6] = {"Vine Whip"},
			[12] = {"Seed Toss"},
			[18] = {"Leaf Slash"},
			[26] = {"Grand Slam"},
		},
		nil,
		nil,
		55.0,
		{["rightmiddlefinger2"]=Color3.new(0.918,0.722,0.573),["rightindex2"]=Color3.new(0.918,0.722,0.573),["rightringfinger2"]=Color3.new(0.918,0.722,0.573),["rightindex1"]=Color3.new(0.918,0.722,0.573),["rightmiddlefinger1"]=Color3.new(0.918,0.722,0.573),["rightringfinger1"]=Color3.new(0.918,0.722,0.573),["rightthumb2"]=Color3.new(0.918,0.722,0.573),["rightthumb1"]=Color3.new(0.918,0.722,0.573),["rightpalm"]=Color3.new(0.918,0.722,0.573),["rightforearm"]=Color3.new(0.667,0.333,0.000),["rightpinky2"]=Color3.new(0.918,0.722,0.573),["rightpinky1"]=Color3.new(0.918,0.722,0.573),["rightarm"]=Color3.new(0.667,0.333,0.000),["beard"]=Color3.new(0.337,0.259,0.212),["rightleg1"]=Color3.new(0.667,0.333,0.000),["rightleg2"]=Color3.new(0.918,0.722,0.573),["backofhead"]=Color3.new(0.667,0.333,0.000),["pupils"]=Color3.new(0.067,0.067,0.067),["nose"]=Color3.new(0.918,0.722,0.573),["mouth"]=Color3.new(0.067,0.067,0.067),["hat"]=Color3.new(0.667,0.333,0.000),["face"]=Color3.new(0.918,0.722,0.573),["eyes"]=Color3.new(0.016,0.686,0.925),["rightfoot"]=Color3.new(0.918,0.722,0.573),["leftfoot"]=Color3.new(0.918,0.722,0.573),["leftarm"]=Color3.new(0.667,0.333,0.000),["leftleg1"]=Color3.new(0.667,0.333,0.000),["leftleg2"]=Color3.new(0.918,0.722,0.573),["lefttoes"]=Color3.new(0.973,0.973,0.973),["righttoes"]=Color3.new(0.973,0.973,0.973),["leftforearm"]=Color3.new(0.667,0.333,0.000),["leftpalm"]=Color3.new(0.918,0.722,0.573),["leftpinky1"]=Color3.new(0.918,0.722,0.573),["leftringfinger1"]=Color3.new(0.918,0.722,0.573),["leftthumb2"]=Color3.new(0.918,0.722,0.573),["leftthumb1"]=Color3.new(0.918,0.722,0.573),["leftmiddlefinger1"]=Color3.new(0.918,0.722,0.573),["leftpinky2"]=Color3.new(0.918,0.722,0.573),["leftringfinger2"]=Color3.new(0.918,0.722,0.573),["leftindex1"]=Color3.new(0.918,0.722,0.573),["leftindex2"]=Color3.new(0.918,0.722,0.573),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["Torso"]=Color3.new(0.639,0.635,0.647),["leftmiddlefinger2"]=Color3.new(0.918,0.722,0.573)},
		"Basic",
		180,  -- Common
		50
	),

	--============================================================================
	-- Frycito (Fire/Fighting - rare single-stage)
	--============================================================================
	["Frycito"] = createCreature(
		31,
		"Frycito",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"Born from a box of superheated fries, Frycito's body crackles with oily flames. It charges into battle with sizzling punches, splattering sparks and crumbs everywhere.",
		{ "Fire", "Fighting" },
		{ -- BST: 325 (Rare single-stage bruiser)
			HP = 75,
			Attack = 95,
			Defense = 70,
			SpecialAttack = 65,
			SpecialDefense = 65,
			Speed = 85,
		},
		{
			[1] = {"Scratch", "Grease Jab"},
			[6] = {"Double Kick"},
			[12] = {"Fast Attack"},
			[18] = {"Uppercut"},
			[26] = {"Searing Splat"},
			[34] = {"Grand Slam"},
		},
		nil,
		nil,
		32.5,
		{
			["Frycito_LeftArm"] = Color3.new(0.561,0.298,0.165),
			["Frycito_LeftHand"] = Color3.new(0.561,0.298,0.165),
			["Frycito_Pupil"] = Color3.new(0.067,0.067,0.067),
			["Frycito_Bucket"] = Color3.new(0.937,0.722,0.220),
			["Frycito_Eyebrows"] = Color3.new(0.067,0.067,0.067),
			["Frycito_Fries"] = Color3.new(0.561,0.298,0.165),
			["Frycito_RightArm"] = Color3.new(0.561,0.298,0.165),
			["Frycito_RightFoot"] = Color3.new(0.561,0.298,0.165),
			["Frycito_Eyes"] = Color3.new(0.973,0.973,0.973),
			["Frycito_LeftFoot"] = Color3.new(0.561,0.298,0.165),
			["Frycito_Mouth"] = Color3.new(0.067,0.067,0.067),
			["Frycito_RightHand"] = Color3.new(0.561,0.298,0.165),
			["Frycito_FryBat"] = Color3.new(0.561,0.298,0.165),
			["HR2"] = Color3.new(0.639,0.635,0.647),
			["HumanoidRootPart"] = Color3.new(0.639,0.635,0.647),
			["Frycito_Torso"] = Color3.new(0.459,0.000,0.000),
		},
		"Rare",
		90,   -- Rare catch rate
		50
	),

	--============================================================================
	-- Yoyoi Shaur Line (Normal/Psychic - 2-stage spinner)
	--============================================================================
	["Yoyoi Shaur"] = createCreature(
		32,
		"Yoyoi Shaur",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"A playful yoyo creature that moves by spinning, bouncing, and snapping back into position. Its sunglasses hide faint psychic glows it uses to sense movement around it. When it spins rapidly, it can send out short psychic pulses that disorient opponents.",
		{ "Normal", "Psychic" },
		{ -- BST: 220 (Basic agile spinner)
			HP = 60,
			Attack = 55,
			Defense = 55,
			SpecialAttack = 55,
			SpecialDefense = 55,
			Speed = 50,
		},
		{
			[1] = {"Tackle", "Fast Attack"},
			[6] = {"Scratch"},
			[12] = {"Psychic Pulse"},
			[18] = {"Mind Slam"},
			[24] = {"Grand Slam"},
		},
		18,
		"Yoyoya Shaur",
		7.2,
		{
			["Yoyo_RightFoot"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_RightFootString"] = Color3.new(0.973,0.973,0.973),
			["Yoyo_LeftFoot"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_RightLowerLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_LeftLowerLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_RightHand"] = Color3.new(0.973,0.973,0.973),
			["Yoyo_RightUpperLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_LeftUpperLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_RightLowerArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_Circle"] = Color3.new(0.106,0.165,0.208),
			["Yoyo_RightUpperArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_Head"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_Glasses"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_GlassesGlass"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_Torso"] = Color3.new(0.937,0.722,0.220),
			["Yoyo_LeftHand"] = Color3.new(0.973,0.973,0.973),
			["Yoyo_LeftLowerArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_LeftUpperArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyo_String"] = Color3.new(0.973,0.973,0.973),
			["Yoyo_LeftFootString"] = Color3.new(0.973,0.973,0.973),
			["HR2"] = Color3.new(0.639,0.635,0.647),
			["HumanoidRootPart"] = Color3.new(0.639,0.635,0.647),
			["Yoyo_Head2"] = Color3.new(0.973,0.973,0.973),
		},
		"Basic",
		150,  -- Uncommon
		50
	),
	["Yoyoya Shaur"] = createCreature(
		33,
		"Yoyoya Shaur",
		"rbxassetid://nil",
		"rbxassetid://nil",
		"After evolving, its spin becomes perfectly balanced, allowing it to move with incredible precision. It battles with controlled, whip-like motions, predicting attacks before they land. Its shades serve as psychic focus lenses, sharpening its awareness and reactions.",
		{ "Normal", "Psychic" },
		{ -- BST: 330 (Advanced balanced spinner)
			HP = 80,
			Attack = 85,
			Defense = 80,
			SpecialAttack = 85,
			SpecialDefense = 80,
			Speed = 85,
		},
		{
			[1] = {"Tackle", "Fast Attack", "Psychic Pulse"},
			[18] = {"Mind Slam"},
			[26] = {"Dazzle Beam"},
			[32] = {"Grand Slam"},
			[40] = {"Knockout"},
		},
		nil,
		nil,
		12.8,
		{
			["Yoyoyo_Head2"] = Color3.new(0.973,0.973,0.973),
			["Yoyoyo_LeftHand"] = Color3.new(0.973,0.973,0.973),
			["Yoyoyo_LeftLowerArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_LeftUpperArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_String"] = Color3.new(0.973,0.973,0.973),
			["Yoyoyo_Glasses"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_GlassesGlass"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_LeftLowerLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_LeftUpperLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_RightLowerLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_RightUpperArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_RightUpperLeg"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_LeftFoot"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_LeftFootString"] = Color3.new(0.973,0.973,0.973),
			["Yoyoyo_RightFoot"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_RightFootString"] = Color3.new(0.973,0.973,0.973),
			["Yoyoyo_RightLowerArm"] = Color3.new(0.067,0.067,0.067),
			["Yoyoyo_RightHand"] = Color3.new(0.973,0.973,0.973),
			["HR2"] = Color3.new(0.639,0.635,0.647),
			["HumanoidRootPart"] = Color3.new(0.639,0.635,0.647),
			["Yoyoyo_Torso"] = Color3.new(0.459,0.000,0.000),
			["Yoyoyo_Head"] = Color3.new(0.067,0.067,0.067),
		},
		"Advanced",
		75,   -- Rare
		50
	),


	--============================================================================
	-- LEGENDARY/SPECIAL: Tralalero Tralala
	-- The iconic three-legged shark. Very rare and powerful.
	--============================================================================
	["Tralalero Tralala"] = createCreature(
		400,
		"Tralalero Tralala",
		"rbxassetid://140328234982946",
		"rbxassetid://nil",
		"A mythical three-legged shark wearing fashionable shoes. Said to outswim any creature in existence.",
		{ "Water" },
		{ -- BST: 400 (Legendary tier - incredibly fast water sweeper)
			HP = 75,
			Attack = 95,
			Defense = 70,
			SpecialAttack = 95,
			SpecialDefense = 70,
			Speed = 160,
		},
		{
			[1] = {"Water Jet", "Tackle"},
			[10] = {"Fast Attack"},
			[18] = {"Bite"},
			[28] = {"Aqua Slash"},
			[36] = {"Crunch"},
			[46] = {"Hydro Burst"},
			[56] = {"Grand Slam"},
		},
		nil,
		nil,
		180.0,
		nil,
		"Legendary",
		3,    -- Extremely rare catch rate (legendary)
		50
	),
}

return Creatures
