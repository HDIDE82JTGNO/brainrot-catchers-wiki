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

local Creatures: { [string]: Creature_Type } = {
	-- 1-3: Kitung line (starter)
	["Kitung"] = createCreature(
		1,
		"Kitung",
		"rbxassetid://122057835034579",
		"rbxassetid://130838050112224",
		"A small enthusiastic fighter with a wooden stick.",
		{ "Fighting" },
		{
			HP = 50,
			Attack = 55,
			Defense = 45,
			Speed = 70,
		},
		{
			[1] = {"Scratch", "Fast Attack"},
			[6] = {"Double Kick"},
			[12] = {"Uppercut"},
			[18] = {"Grand Slam"}
		},
		16,
		"Sir Tung",
		32,
		{["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["UpperArmL"]=Color3.new(0.937,0.722,0.220),["ForeArmL"]=Color3.new(0.937,0.722,0.220),["Torso"]=Color3.new(0.937,0.722,0.220),["UpperArmR"]=Color3.new(0.937,0.722,0.220),["ForeArmR"]=Color3.new(0.937,0.722,0.220),["ThighR"]=Color3.new(0.937,0.722,0.220),["ThighL"]=Color3.new(0.937,0.722,0.220),["CalfL"]=Color3.new(0.937,0.722,0.220),["CalfR"]=Color3.new(0.937,0.722,0.220),["EyesBack"]=Color3.new(0.910,0.776,0.584),["Eyes_Black"]=Color3.new(0.035,0.537,0.812),["Eyes_White"]=Color3.new(0.929,0.918,0.918),["FootL"]=Color3.new(0.937,0.722,0.220),["FootR"]=Color3.new(0.937,0.722,0.220),["HandL"]=Color3.new(0.937,0.722,0.220),["HandR"]=Color3.new(0.937,0.722,0.220),["Neck"]=Color3.new(0.937,0.722,0.220),["Stick_One"]=Color3.new(1.000,0.000,0.000),["Stick_Two"]=Color3.new(1.000,0.314,0.043),["HeadMesh"]=Color3.new(0.937,0.722,0.220)},
		nil,
		40,
		20
	),
	["Sir Tung"] = createCreature(
		2,
		"Sir Tung",
		"rbxassetid://117004729912755",
		"rbxassetid://80170237167870",
		"A more grown Kitung with a tophat, tie, and wooden wand.",
		{ "Fighting" },
		{
			HP = 60,
			Attack = 70,
			Defense = 60,
			Speed = 85,
		},
		{
			[1] = {"Scratch", "Fast Attack"},
			[10] = {"Double Kick"},
			[18] = {"Uppercut"},
			[26] = {"Grand Slam"},
			[38] = {"Shield Bash"},
			[44] = {"Knockout"}
		},
		36,
		"Magi-Tung",
		48,
		{["CalfL"]=Color3.new(0.937,0.722,0.220),["CalfR"]=Color3.new(0.937,0.722,0.220),["Eyebrows"]=Color3.new(0.937,0.722,0.220),["Eyelids"]=Color3.new(0.937,0.722,0.220),["EyesBlack"]=Color3.new(0.035,0.537,0.812),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FootL"]=Color3.new(0.937,0.722,0.220),["FootR"]=Color3.new(0.937,0.722,0.220),["ForeArmL"]=Color3.new(0.937,0.722,0.220),["ForeArmR"]=Color3.new(0.937,0.722,0.220),["HandL"]=Color3.new(0.937,0.722,0.220),["HandR"]=Color3.new(0.937,0.722,0.220),["HeadMesh"]=Color3.new(0.937,0.722,0.220),["Iris"]=Color3.new(0.973,0.973,0.973),["Mouth"]=Color3.new(0.973,0.973,0.973),["Nose"]=Color3.new(0.937,0.722,0.220),["ThighL"]=Color3.new(0.937,0.722,0.220),["ThighR"]=Color3.new(0.937,0.722,0.220),["Tie"]=Color3.new(0.769,0.157,0.110),["TopHat"]=Color3.new(0.973,0.973,0.973),["TopHatWhite"]=Color3.new(0.051,0.412,0.675),["Torso"]=Color3.new(0.937,0.722,0.220),["UpperArmL"]=Color3.new(0.937,0.722,0.220),["UpperArmR"]=Color3.new(0.937,0.722,0.220),["WandExt"]=Color3.new(1.000,0.314,0.043),["WandHandle"]=Color3.new(1.000,0.000,0.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		55,
		20
	),
	["Magi-Tung"] = createCreature(
		3,
		"Magi-Tung",
		"rbxassetid://79578637985806",
		"rbxassetid://123561772385659",
		"Sir Tung now wears a magician's outfit and wields a black-and-white wand.",
		{ "Fighting", "Psychic" },
		{
			HP = 75,
			Attack = 95,
			Defense = 80,
			Speed = 90,
		},
		{
			[1] = {"Scratch", "Fast Attack"},
			[14] = {"Double Kick"},
			[22] = {"Uppercut"},
			[30] = {"Grand Slam"},
			[36] = {"Mind Slam"},
			[44] = {"Shield Bash"},
			[52] = {"Knockout"}
		},
		nil,
		nil,
		70,
		{["CalfL"]=Color3.new(0.973,0.973,0.973),["CalfR"]=Color3.new(0.973,0.973,0.973),["Eyebrows"]=Color3.new(0.357,0.365,0.412),["Eyelids"]=Color3.new(0.357,0.365,0.412),["EyesBlack"]=Color3.new(0.459,0.000,0.000),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FootL"]=Color3.new(0.067,0.067,0.067),["FootR"]=Color3.new(0.067,0.067,0.067),["ForeArmL"]=Color3.new(0.973,0.973,0.973),["ForeArmR"]=Color3.new(0.973,0.973,0.973),["HandL"]=Color3.new(0.067,0.067,0.067),["HandR"]=Color3.new(0.067,0.067,0.067),["HeadMesh"]=Color3.new(0.357,0.365,0.412),["Inner"]=Color3.new(0.106,0.165,0.208),["Iris"]=Color3.new(1.000,1.000,1.000),["Mouth"]=Color3.new(1.000,1.000,1.000),["Nose"]=Color3.new(0.357,0.365,0.412),["Outer"]=Color3.new(0.973,0.973,0.973),["ThighL"]=Color3.new(0.973,0.973,0.973),["ThighR"]=Color3.new(0.973,0.973,0.973),["Tie"]=Color3.new(0.769,0.157,0.110),["TopHat"]=Color3.new(0.973,0.973,0.973),["TopHatRibbon"]=Color3.new(0.051,0.412,0.675),["Torso"]=Color3.new(0.624,0.631,0.675),["UpperArmL"]=Color3.new(0.973,0.973,0.973),["UpperArmR"]=Color3.new(0.973,0.973,0.973),["WandExt"]=Color3.new(1.000,0.314,0.043),["WandHandle"]=Color3.new(1.000,0.000,0.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		65,
		20
	),

	-- 4-6: Frigo camel line (starter)
	["Frigo Camelo"] = createCreature(
		4,
		"Frigo Camelo",
		"rbxassetid://114863676276555",
		"rbxassetid://79220464709099",
		"A fridge-bodied camel who wanders aimlessly, embodying surreal melancholy and cursed Italian energy.",
		{ "Ground" },
		{
			HP = 35,
			Attack = 55,
			Defense = 40,
			Speed = 90,
		},
		{
			[1] = {"Fast Attack"},
			[6] = {"Scratch"},
			[12] = {"Sand Storm"},
			[18] = {"Bite"},
			[26] = {"Crunch"},
			[34] = {"Earthquake"}
		},
		16,
		"Refricamel",
		50,
		{["Ears"]=Color3.new(0.541,0.392,0.188),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FridgeMain"]=Color3.new(0.737,0.718,0.808),["FootL"]=Color3.new(0.541,0.392,0.188),["LegL"]=Color3.new(0.541,0.392,0.188),["FootR"]=Color3.new(0.541,0.392,0.188),["LegR"]=Color3.new(0.541,0.392,0.188),["HeadMesh"]=Color3.new(0.541,0.392,0.188),["HeadBlack"]=Color3.new(0.067,0.067,0.067),["Neck1"]=Color3.new(0.541,0.392,0.188),["Neck2"]=Color3.new(0.541,0.392,0.188),["Neck3"]=Color3.new(0.541,0.392,0.188),["Neck4"]=Color3.new(0.541,0.392,0.188),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		30,
		40
	),
	["Refricamel"] = createCreature(
		5,
		"Refricamel",
		"rbxassetid://87061586813050",
		"rbxassetid://121958256639798",
		"Now with proper refrigeration coils, it keeps its cool in deserts and stores snacks for later.",
		{ "Ground" },
		{
			HP = 55,
			Attack = 70,
			Defense = 60,
			Speed = 80,
		},
		{
			[1] = {"Fast Attack", "Scratch"},
			[14] = {"Sand Storm"},
			[22] = {"Bite"},
			[30] = {"Crunch"},
			[38] = {"Earthquake"},
		},
		36,
		"Glacimel",
		120,
		{["BackLeftFoot"]=Color3.new(0.471,0.278,0.761),["BackLeftLeg"]=Color3.new(0.541,0.392,0.188),["BackRightFoot"]=Color3.new(0.471,0.278,0.761),["BackRightLeg"]=Color3.new(0.541,0.392,0.188),["Body"]=Color3.new(0.737,0.718,0.808),["Ears"]=Color3.new(0.541,0.392,0.188),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FridgeHandles"]=Color3.new(0.373,0.373,0.373),["FrontLeftFoot"]=Color3.new(0.471,0.278,0.761),["FrontLeftLeg"]=Color3.new(0.541,0.392,0.188),["FrontRightFoot"]=Color3.new(0.471,0.278,0.761),["FrontRightLeg"]=Color3.new(0.541,0.392,0.188),["HeadMesh"]=Color3.new(0.541,0.392,0.188),["Head_Black"]=Color3.new(0.000,0.000,0.000),["Neck1"]=Color3.new(0.541,0.392,0.188),["Neck2"]=Color3.new(0.541,0.392,0.188),["CubeTop"]=Color3.new(0.678,0.451,1.000),["Neck3"]=Color3.new(0.541,0.392,0.188),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45,
		40
	),
	["Glacimel"] = createCreature(
		6,
		"Glacimel",
		"rbxassetid://140155612806063",
		nil,
		"Its freezer core turned cryogenic. It sculpts dune-ice into elegant ridges as it roams.",
		{ "Ground", "Ice" },
		{
			HP = 80,
			Attack = 90,
			Defense = 90,
			Speed = 80,
		},
		{
			[1] = {"Fast Attack", "Sand Storm"},
			[20] = {"Bite"},
			[34] = {"Crunch"},
			[46] = {"Earthquake"},
		},
		nil,
		nil,
		180,
		{["BackLeftFoot"]=Color3.new(0.471,0.278,0.761),["BackLeftLeg"]=Color3.new(0.471,0.278,0.761),["BackRightFoot"]=Color3.new(0.471,0.278,0.761),["BackRightLeg"]=Color3.new(0.471,0.278,0.761),["Body"]=Color3.new(0.639,0.635,0.647),["CubeTop"]=Color3.new(0.678,0.451,1.000),["Ears"]=Color3.new(0.541,0.392,0.188),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FrontLeftFoot"]=Color3.new(0.471,0.278,0.761),["FrontLeftLeg"]=Color3.new(0.471,0.278,0.761),["FrontRightFoot"]=Color3.new(0.471,0.278,0.761),["FrontRightLeg"]=Color3.new(0.471,0.278,0.761),["HeadMesh"]=Color3.new(0.541,0.392,0.188),["Head_Black"]=Color3.new(0.067,0.067,0.067),["IceHead"]=Color3.new(0.678,0.451,1.000),["Inside"]=Color3.new(0.639,0.635,0.647),["NeckIce"]=Color3.new(0.545,0.365,0.812),["NeckNormal"]=Color3.new(0.541,0.392,0.188),["Tail"]=Color3.new(0.541,0.271,0.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		55,
		40
	),

	-- 7-9: Cup ballerina line 9start
	["Twirlina"] = createCreature(
		7,
		"Twirlina",
		"rbxassetid://91063591914096",
		"rbxassetid://100838791633365",
		"A tiny cup dancer who practices spins until she’s dizzy with delight.",
		{ "Fairy" },
		{
			HP = 45,
			Attack = 45,
			Defense = 40,
			Speed = 90,
		},
		{
			[1] = {"Dance Strike"},
			[8] = {"Dazzle Beam"},
			[18] = {"Fairy Strike"},
		},
		16,
		"Ballerina Cappuccina",
		10,
		{["ArmL"]=Color3.new(0.976,0.765,0.576),["ArmR"]=Color3.new(0.976,0.765,0.576),["EyesBlack"]=Color3.new(0.067,0.067,0.067),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FaceParts"]=Color3.new(0.016,0.686,0.925),["FootL"]=Color3.new(0.529,0.812,1.000),["FootR"]=Color3.new(0.529,0.812,1.000),["HandL"]=Color3.new(0.016,0.686,0.925),["HandR"]=Color3.new(0.016,0.686,0.925),["HeadMesh"]=Color3.new(0.871,0.945,1.000),["Hips"]=Color3.new(0.420,0.757,1.000),["LegL"]=Color3.new(0.773,0.875,1.000),["LegR"]=Color3.new(0.773,0.875,1.000),["Skirt"]=Color3.new(0.290,0.557,0.847),["Torso"]=Color3.new(0.239,0.463,0.702),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		35,
		95
	),
	["Ballerina Cappuccina"] = createCreature(
		8,
		"Ballerina Cappuccina",
		"rbxassetid://88795634363100",
		"rbxassetid://116535707779582",
		"A poised ballerina with a swirling coffee cup for a head. She pirouettes into battle.",
		{ "Fairy" },
		{
			HP = 60,
			Attack = 45,
			Defense = 55,
			Speed = 105,
		},
		{
			[1] = {"Dance Strike"},
			[10] = {"Dazzle Beam"},
			[20] = {"Fairy Strike"},
			[30] = {"Sunbeam"}
		},
		36,
		"Primarina Ballerina",
		20,
		{["ArmL"]=Color3.new(0.976,0.765,0.576),["ArmR"]=Color3.new(0.976,0.765,0.576),["CupHandle"]=Color3.new(0.871,0.945,1.000),["EyesBlack"]=Color3.new(0.067,0.067,0.067),["EyesBrown"]=Color3.new(0.482,0.592,0.635),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FootL"]=Color3.new(0.529,0.812,1.000),["FootR"]=Color3.new(0.529,0.812,1.000),["HandL"]=Color3.new(0.016,0.686,0.925),["HandR"]=Color3.new(0.016,0.686,0.925),["HeadMesh"]=Color3.new(0.871,0.945,1.000),["Hips"]=Color3.new(0.420,0.757,1.000),["LegL"]=Color3.new(0.773,0.875,1.000),["LegR"]=Color3.new(0.773,0.875,1.000),["MouthWhite"]=Color3.new(0.973,0.973,0.973),["NoseMouth"]=Color3.new(0.016,0.686,0.925),["Skirt"]=Color3.new(0.290,0.557,0.847),["Torso"]=Color3.new(0.239,0.463,0.702),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Rare",
		45,
		95
	),
	["Primarina Ballerina"] = createCreature(
		9,
		"Primarina Ballerina",
		"rbxassetid://TODO",
		nil,
		"The cup now forged into steel trim, her grand jeté leaves shimmering trails.",
		{ "Fairy", "Steel" },
		{
			HP = 80,
			Attack = 70,
			Defense = 90,
			Speed = 95,
		},
		{
			[1] = {"Dance Strike", "Dazzle Beam"},
			[28] = {"Fairy Strike"},
			[36] = {"Shield Bash"},
			[48] = {"Sunbeam"},
		},
		nil,
		nil,
		28,
		{["Crown"]=Color3.new(0.988,0.980,1.000),["CupHandle"]=Color3.new(0.988,0.980,1.000),["EyesBlack"]=Color3.new(0.067,0.067,0.067),["EyesBrown"]=Color3.new(0.482,0.592,0.635),["EyesWhite"]=Color3.new(1.000,1.000,1.000),["FootL"]=Color3.new(0.675,0.831,0.886),["FootR"]=Color3.new(0.675,0.831,0.886),["ForeArmL"]=Color3.new(0.976,0.765,0.576),["ForeArmR"]=Color3.new(0.976,0.765,0.576),["HandL"]=Color3.new(0.988,0.980,1.000),["HandR"]=Color3.new(0.988,0.980,1.000),["HeadMesh"]=Color3.new(1.000,0.910,0.890),["LegL"]=Color3.new(0.988,0.980,1.000),["LegR"]=Color3.new(0.988,0.980,1.000),["MouthWhite"]=Color3.new(0.973,0.973,0.973),["Neck"]=Color3.new(0.988,0.980,1.000),["NoseMouth"]=Color3.new(0.016,0.686,0.925),["Seperator"]=Color3.new(0.639,0.635,0.647),["SkirtPink"]=Color3.new(0.722,0.890,1.000),["SkirtWhite"]=Color3.new(0.988,0.980,1.000),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["UpperArmL"]=Color3.new(0.988,0.980,1.000),["UpperArmR"]=Color3.new(0.988,0.980,1.000),["Torso"]=Color3.new(0.988,0.980,1.000)},
		"Advanced",
		55,
		95
	),

	-- 10: Frulli Frulla
	["Frulli Frulla"] = createCreature(
		10,
		"Frulli Frulla",
		"rbxassetid://96032956018193",
		"rbxassetid://91862509821498",
		"A jittery coffee-fueled bird hybrid with orange glasses, born from a hummingbird that sipped a mad scientist's frullato.",
		{ "Flying" },
		{
			HP = 40,
			Attack = 40,
			Defense = 40,
			Speed = 85,
		},
		{
			[1] = {"Peck"},
			[6] = {"Perch"},
			[14] = {"Fast Attack"},
			[18] = {"Bite"},
			[26] = {"Dive Bomb"}
		},
		nil,
		nil,
		5,
		{["Bird_Beak"]=Color3.new(1.000,0.690,0.000),["Bird_Beak.001"]=Color3.new(1.000,0.690,0.000),["Bird_Beak.002"]=Color3.new(1.000,0.690,0.000),["Bird_Beak.003"]=Color3.new(1.000,0.690,0.000),["Bird_BodyBack"]=Color3.new(0.549,0.506,0.192),["Bird_BodyFront"]=Color3.new(0.769,0.757,0.392),["Bird_Glasses"]=Color3.new(0.973,0.973,0.973),["Bird_GlassesGlass"]=Color3.new(0.145,0.141,0.227),["Bird_Head"]=Color3.new(0.549,0.506,0.192),["Bird_Legs"]=Color3.new(1.000,0.690,0.000),["Bird_Wings"]=Color3.new(0.549,0.506,0.192),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		35,
		50
	),

	-- 11-12: Tim line
	["Timmy Cheddar"] = createCreature(
		11,
		"Timmy Cheddar",
		"rbxassetid://82604607419612",
		nil,
		"A young, ambitious rat with big dreams. Still learning the ropes of the underworld but shows great potential.",
		{ "Normal" },
		{
			HP = 35,
			Attack = 40,
			Defense = 35,
			Speed = 50,
		},
		{
			[1] = {"Scratch", "Tackle"},
			[6] = {"Fast Attack"},
			[12] = {"Bite"},
			[18] = {"Crunch"}
		},
		26,
		"Tim Cheese",
		7,
		{["ArmL"]=Color3.new(0.937,0.722,0.220),["ArmR"]=Color3.new(0.937,0.722,0.220),["EarLInner"]=Color3.new(0.843,0.773,0.604),["EarLOuter"]=Color3.new(0.486,0.612,0.420),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["EarROuter"]=Color3.new(0.486,0.612,0.420),["FootL"]=Color3.new(0.486,0.612,0.420),["FootR"]=Color3.new(0.486,0.612,0.420),["GlassesFrame"]=Color3.new(0.973,0.973,0.973),["GlassesLens"]=Color3.new(0.384,0.145,0.820),["HandL"]=Color3.new(0.486,0.612,0.420),["HandR"]=Color3.new(0.486,0.612,0.420),["HeadPart"]=Color3.new(0.486,0.612,0.420),["LegL"]=Color3.new(0.937,0.722,0.220),["LegR"]=Color3.new(0.937,0.722,0.220),["Nose"]=Color3.new(0.906,0.584,0.573),["Shirt"]=Color3.new(0.827,0.827,0.827),["Tie"]=Color3.new(0.906,0.396,0.565),["Torso"]=Color3.new(0.937,0.722,0.220),["Whiskers"]=Color3.new(0.827,0.827,0.827),["HR2"]=Color3.new(0.639,0.635,0.647),["EarRInner"]=Color3.new(0.843,0.773,0.604)},
		"Basic",
		40,
		0
	),
	["Tim Cheese"] = createCreature(
		12,
		"Tim Cheese",
		"rbxassetid://139429805303301",
		nil,
		"A sharp-dressed humanoid rat who oozes confidence and cunning. Said to run the city's underworld from behind a spotless desk.",
		{ "Normal" },
		{
			HP = 45,
			Attack = 50,
			Defense = 45,
			Speed = 60,
		},
		{
			[1] = {"Scratch", "Tackle"},
			[8] = {"Fast Attack"},
			[14] = {"Bite"},
			[22] = {"Crunch"}
		},
		nil,
		nil,
		12,
		{["ArmL"]=Color3.new(0.533,0.243,0.243),["ArmR"]=Color3.new(0.533,0.243,0.243),["EarLInner"]=Color3.new(0.800,0.557,0.412),["EarLOuter"]=Color3.new(0.835,0.353,0.161),["EarRInner"]=Color3.new(0.800,0.557,0.412),["EarROuter"]=Color3.new(0.835,0.353,0.161),["FootL"]=Color3.new(0.533,0.243,0.243),["FootR"]=Color3.new(0.533,0.243,0.243),["GlassesFrame"]=Color3.new(0.973,0.973,0.973),["GlassesLens"]=Color3.new(0.067,0.067,0.067),["HandL"]=Color3.new(0.533,0.243,0.243),["HandR"]=Color3.new(0.533,0.243,0.243),["HeadPart"]=Color3.new(0.835,0.353,0.161),["LegL"]=Color3.new(0.533,0.243,0.243),["LegR"]=Color3.new(0.533,0.243,0.243),["Nose"]=Color3.new(0.631,0.769,0.549),["Shirt"]=Color3.new(0.639,0.635,0.647),["Tie"]=Color3.new(0.647,0.188,0.188),["Torso"]=Color3.new(0.533,0.243,0.243),["Whiskers"]=Color3.new(0.580,0.745,0.506),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HR2"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		50,
		0
	),

	-- 13: Burbaloni
	["Burbaloni Lulliloli"] = createCreature(
		13,
		"Burbaloni Lulliloli",
		"rbxassetid://139429805303301",
		nil,
		"A divine capybara within a coconut, worshipped for its calm yet immense power.",
		{ "Ground" },
		{
			HP = 45,
			Attack = 50,
			Defense = 45,
			Speed = 60,
		},
		{
			[1] = {"Tackle"},
			[5] = {"Scratch"},
			[12] = {"Fast Attack"},
			[18] = {"Bite"}
		},
		nil,
		nil,
		90,
		{["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["Ears"]=Color3.new(0.322,0.486,0.682),["Coconut"]=Color3.new(0.706,0.824,0.894),["Back_left_leg"]=Color3.new(0.035,0.537,0.812),["Back_right_leg"]=Color3.new(0.035,0.537,0.812),["Body"]=Color3.new(0.129,0.329,0.725),["Eyes"]=Color3.new(0.067,0.067,0.067),["Front_left_leg"]=Color3.new(0.035,0.537,0.812),["Front_right_leg"]=Color3.new(0.035,0.537,0.812),["Head"]=Color3.new(0.035,0.537,0.812),["Teeth"]=Color3.new(1.000,1.000,1.000),["Nose"]=Color3.new(0.067,0.067,0.067)},
		"Rare",
		55,
		50
	),

	-- 14-15: Jungle chimps
	["Chimpanini"] = createCreature(
		14,
		"Chimpanini",
		"rbxassetid://TODO",
		nil,
		"A hyperactive jungle prankster that flings seeds and swings through trees.",
		{ "Grass" },
		{
			HP = 45,
			Attack = 55,
			Defense = 45,
			Speed = 85,
		},
		{
			[1] = {"Scratch", "Fast Attack"},
			[5] = {"Vine Whip"},
			[10] = {"Seed Toss"}
		},
		nil,
		nil,
		28,
		{["HeadWhite"]=Color3.new(0.973,0.973,0.973),["ArmL"]=Color3.new(0.961,0.804,0.188),["Tail1"]=Color3.new(0.416,0.224,0.035),["Tail2"]=Color3.new(0.416,0.224,0.035),["Tail3"]=Color3.new(0.416,0.224,0.035),["Tail4"]=Color3.new(0.416,0.224,0.035),["LegL"]=Color3.new(0.961,0.804,0.188),["Torso"]=Color3.new(0.992,0.918,0.553),["LegR"]=Color3.new(0.961,0.804,0.188),["ArmR"]=Color3.new(0.961,0.804,0.188),["Tail5"]=Color3.new(0.416,0.224,0.035),["HandL"]=Color3.new(0.416,0.224,0.035),["HandR"]=Color3.new(0.416,0.224,0.035),["HeadPastel"]=Color3.new(1.000,0.675,0.565),["FootL"]=Color3.new(0.416,0.224,0.035),["FootR"]=Color3.new(0.416,0.224,0.035),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HeadBlack"]=Color3.new(0.067,0.067,0.067),["HeadGreen"]=Color3.new(0.416,0.224,0.035)} ,
		"Basic",
		35, 50
	),
	["Chimpanzini Bananini"] = createCreature(
		15,
		"Chimpanzini Bananini",
		"rbxassetid://TODO",
		nil,
		"Though armless, Chimpanzini Bananini hops and rolls through the jungle with surprising speed. Its green chimp head bobs from its banana body as it chirps in a strange, songlike language.",
		{ "Grass" },
		{
			HP = 45,
			Attack = 55,
			Defense = 45,
			Speed = 85,
		},
		{
			[1] = {"Scratch", "Fast Attack"},
			[5] = {"Vine Whip"},
			[10] = {"Seed Toss"}
		},
		nil,
		nil,
		28,
		{["HeadWhite"]=Color3.new(0.973,0.973,0.973),["ArmL"]=Color3.new(0.961,0.804,0.188),["Tail1"]=Color3.new(0.204,0.557,0.251),["HeadGreen"]=Color3.new(0.533,0.325,0.204),["Tail2"]=Color3.new(0.204,0.557,0.251),["Tail3"]=Color3.new(0.204,0.557,0.251),["Tail4"]=Color3.new(0.204,0.557,0.251),["LegL"]=Color3.new(0.961,0.804,0.188),["Torso"]=Color3.new(0.992,0.918,0.553),["LegR"]=Color3.new(0.961,0.804,0.188),["ArmR"]=Color3.new(0.961,0.804,0.188),["Tail5"]=Color3.new(0.416,0.224,0.035),["HandL"]=Color3.new(0.416,0.224,0.035),["HandR"]=Color3.new(0.416,0.224,0.035),["HeadPastel"]=Color3.new(1.000,0.675,0.514),["FootL"]=Color3.new(0.416,0.224,0.035),["FootR"]=Color3.new(0.416,0.224,0.035),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HeadBlack"]=Color3.new(0.067,0.067,0.067)},
		"Basic",
		35, 50
	),

	-- 16: Duckaroo (17 intentionally empty for future evo)
	["Duckaroo"] = createCreature(
		16,
		"Duckaroo",
		"rbxassetid://TODO",
		nil,
		"A cowboy duck that patrols dry plains and dusty canyons, kicking up sand as it chases bandits.",
		{ "Flying", "Ground" },
		{
			HP = 52,
			Attack = 90,
			Defense = 70,
			Speed = 88,
		},
		{
			[1] = {"Peck", "Fast Attack"},
			[6] = {"Sand Storm"},
			[12] = {"Bite"},
			[18] = {"Duststorm Dash"},
			[26] = {"Earthquake"},
			[34] = {"Crunch"},
			[42] = {"Dive Bomb"},
		},
		nil,
		nil,
		12,
		{["Beak"]=Color3.new(1.000,0.647,0.000),["Body"]=Color3.new(0.824,0.706,0.549),["BootL"]=Color3.new(0.333,0.420,0.184),["BootR"]=Color3.new(0.333,0.420,0.184),["EyeL"]=Color3.new(0.294,0.180,0.020),["EyeR"]=Color3.new(0.294,0.180,0.020),["FootBackL"]=Color3.new(0.761,0.698,0.502),["FootBackR"]=Color3.new(0.761,0.698,0.502),["FootBuckleL"]=Color3.new(0.149,0.149,0.153),["FootBuckleR"]=Color3.new(0.149,0.149,0.153),["FootStudL"]=Color3.new(0.722,0.525,0.043),["FootStudR"]=Color3.new(0.722,0.525,0.043),["Hat"]=Color3.new(0.333,0.420,0.184),["HatBack"]=Color3.new(0.333,0.420,0.184),["Head"]=Color3.new(0.937,0.902,0.839),["HeelL"]=Color3.new(0.169,0.212,0.094),["HeelR"]=Color3.new(0.169,0.212,0.094),["LowerLegL"]=Color3.new(1.000,0.647,0.000),["LowerLegR"]=Color3.new(1.000,0.647,0.000),["Neck"]=Color3.new(0.937,0.902,0.839),["StudL"]=Color3.new(0.722,0.525,0.043),["StudL_L"]=Color3.new(0.722,0.525,0.043),["StudMiddle"]=Color3.new(0.722,0.525,0.043),["StudR"]=Color3.new(0.722,0.525,0.043),["StudR_R"]=Color3.new(0.722,0.525,0.043),["Tail"]=Color3.new(0.824,0.706,0.549),["UpperLegL"]=Color3.new(0.824,0.706,0.549),["UpperLegR"]=Color3.new(0.824,0.706,0.549),["WingL"]=Color3.new(0.824,0.706,0.549),["WingR"]=Color3.new(0.824,0.706,0.549),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Rare",
		40,
		40
	),

	-- 18+: others
	["Doggolino"] = createCreature(
		18,
		"Doggolino",
		"rbxassetid://TODO",
		nil,
		"A furious hot‑dog spirit. It barks in sizzles and pops.",
		{ "Fire" },
		{
			HP = 60,
			Attack = 70,
			Defense = 45,
			Speed = 65,
		},
		{
			[1] = {"Tackle", "Scratch"},
			[10] = {"Bite"},
			[20] = {"Crunch"},
		},
		nil,
		nil,
		15,
		{["BottomTeeth"]=Color3.new(0.973,0.973,0.973),["Bun"]=Color3.new(0.639,0.294,0.294),["Eyes"]=Color3.new(0.067,0.067,0.067),["Ketchup"]=Color3.new(0.639,0.294,0.294),["Nose"]=Color3.new(0.067,0.067,0.067),["Red"]=Color3.new(0.996,0.953,0.733),["Tongue"]=Color3.new(0.769,0.157,0.110),["TopTeeth"]=Color3.new(0.973,0.973,0.973),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		45,
		50
	),
	["Tadbalabu"] = createCreature(
		19,
		"Tadbalabu",
		"rbxassetid://TODO",
		nil,
		"A little frog‑tad that drums on puddles with its tail.",
		{ "Grass" },
		{
			HP = 45,
			Attack = 45,
			Defense = 40,
			Speed = 50,
		},
		{
			[1] = {"Vine Whip"},
			[8] = {"Seed Toss"},
		},
		16,
		"Boneca Ambalabu",
		9,
		{["LToeNails"]=Color3.new(0.973,0.973,0.973),["RightLeg"]=Color3.new(0.769,0.157,0.110),["RToeNails"]=Color3.new(0.973,0.973,0.973),["RightLegTop"]=Color3.new(0.200,0.345,0.510),["Torso"]=Color3.new(0.686,0.867,1.000),["BottomHead"]=Color3.new(0.937,0.722,0.220),["Nose"]=Color3.new(0.067,0.067,0.067),["TopHead"]=Color3.new(0.769,0.157,0.110),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["HR2"]=Color3.new(0.639,0.635,0.647),["Eyes"]=Color3.new(0.106,0.165,0.208),["LeftLeg"]=Color3.new(0.769,0.157,0.110),["LeftLegTop"]=Color3.new(0.200,0.345,0.510)},
		"Basic",
		35, 50
	),
	["Boneca Ambalabu"] = createCreature(
		20,
		"Boneca Ambalabu",
		"rbxassetid://TODO",
		nil,
		"It grows longer limbs like a doll, keeping a steady jungle rhythm.",
		{ "Grass" },
		{
			HP = 60,
			Attack = 60,
			Defense = 55,
			Speed = 60,
		},
		{
			[1] = {"Vine Whip", "Seed Toss"},
			[20] = {"Leaf Slash"},
		},
		36,
		"Ambalabu Ton-Ton",
		18,
		{["Nose"]=Color3.new(0.067,0.067,0.067),["Eyes"]=Color3.new(0.973,0.851,0.427),["TopHead"]=Color3.new(1.000,0.000,0.000),["Torso"]=Color3.new(0.051,0.412,0.675),["BottomHead"]=Color3.new(0.937,0.722,0.220),["LeftLeg"]=Color3.new(1.000,0.000,0.000),["RightLeg"]=Color3.new(1.000,0.000,0.000),["RToeNails"]=Color3.new(0.973,0.973,0.973),["LToeNails"]=Color3.new(0.973,0.973,0.973),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		45, 50
	),
	["Ambalabu Ton-Ton"] = createCreature(
		21,
		"Ambalabu Ton-Ton",
		"rbxassetid://TODO",
		nil,
		"Stacked like drums, it pounds a beat that spurs seedlings to sprout.",
		{ "Grass" },
		{
			HP = 80,
			Attack = 85,
			Defense = 80,
			Speed = 70,
		},
		{
			[1] = {"Vine Whip", "Seed Toss"},
			[24] = {"Leaf Slash"},
			[40] = {"Grand Slam"},
		},
		nil,
		nil,
		26,
		{["Nose"]=Color3.new(0.067,0.067,0.067),["Eyes"]=Color3.new(0.067,0.067,0.067),["FaceMarks"]=Color3.new(1.000,0.000,0.000),["TopHead"]=Color3.new(1.000,0.000,0.000),["BottomHead"]=Color3.new(0.937,0.722,0.220),["TopHat"]=Color3.new(0.973,0.973,0.973),["Tire1"]=Color3.new(0.624,0.678,0.753),["Tire2"]=Color3.new(0.035,0.537,0.812),["Torso"]=Color3.new(1.000,0.000,0.000),["Tire3"]=Color3.new(0.000,0.063,0.690),["RightLeg"]=Color3.new(1.000,0.000,0.000),["LeftLeg"]=Color3.new(1.000,0.000,0.000),["RToeNail"]=Color3.new(0.973,0.973,0.973),["LToeNail"]=Color3.new(0.973,0.973,0.973),["HR2"]=Color3.new(0.639,0.635,0.647),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Advanced",
		55, 50
	),

	-- 22: Abrazard
	["Abrazard"] = createCreature(
		22,
		"Abrazard",
		"rbxassetid://TODO",
		nil,
		"A small wizard who loves playful mischief, casting silly spells with a grin.",
		{ "Psychic" },
		{
			HP = 45,
			Attack = 35,
			Defense = 40,
			Speed = 70,
		},
		{
			[1] = {"Scratch", "Fast Attack"},
			[8] = {"Mind Slam"},
			[16] = {"Dazzle Beam"},
		},
		nil,
		nil,
		12,
		{["ArmL"]=Color3.new(0.369,0.271,0.220),["ArmR"]=Color3.new(0.369,0.271,0.220),["Beard"]=Color3.new(1.000,1.000,1.000),["Candy"]=Color3.new(1.000,0.698,0.094),["EyesBlue"]=Color3.new(1.000,0.698,0.094),["EyesWhite"]=Color3.new(0.973,0.973,0.973),["FootL"]=Color3.new(1.000,0.698,0.094),["FootR"]=Color3.new(1.000,0.698,0.094),["Gold"]=Color3.new(1.000,0.698,0.094),["HandL"]=Color3.new(1.000,0.808,0.576),["HandR"]=Color3.new(1.000,0.808,0.576),["HatBottom"]=Color3.new(1.000,0.698,0.094),["HatTop"]=Color3.new(0.369,0.271,0.220),["HeadTop"]=Color3.new(1.000,0.808,0.576),["Torso"]=Color3.new(0.369,0.271,0.220),["Stars"]=Color3.new(1.000,0.698,0.094),["Wood"]=Color3.new(0.412,0.251,0.157),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
		"Basic",
		40,
		40
	),

	-- 23: Bolasaeg Selluaim
	["Bolasaeg Selluaim"] = createCreature(
		23,
		"Bolasaeg Selluaim",
		"rbxassetid://75020717494654",
		"rbxassetid://98225384445928",
		"A creature made entirely of gelatinous ooze. It devours anything in its path, from tiny plants to massive beasts.",
		{ "Poison" },
		{
			HP = 70,
			Attack = 45,
			Defense = 55,
			Speed = 30,
		},
		{
			[1] = {"Ooze Shot", "Scratch"},
			[6] = {"Sludge Puff"},
			[12] = {"Toxic Wave"},
			[20] = {"Corrosive Grasp"},
			[30] = {"Acidic Deluge"},
		},
		nil,
		nil,
		2, 
		{["jSE"]=Color3.new(0.510,0.604,0.173),["HumanoidRootPart"]=Color3.new(0.067,0.067,0.067),["rSu"]=Color3.new(0.553,0.749,0.125),["TYp"]=Color3.new(0.510,0.604,0.173),["Head"]=Color3.new(0.553,0.749,0.125),["zuB"]=Color3.new(0.553,0.749,0.125),["vhM"]=Color3.new(0.553,0.749,0.125),["Orx"]=Color3.new(0.553,0.749,0.125),["qVd"]=Color3.new(0.553,0.749,0.125),["Main"]=Color3.new(0.553,0.749,0.125),["IKv"]=Color3.new(0.510,0.604,0.173),["BuV"]=Color3.new(0.510,0.604,0.173),["TUQ"]=Color3.new(0.510,0.604,0.173),["nHd"]=Color3.new(0.510,0.604,0.173),["pwZ"]=Color3.new(0.553,0.749,0.125),["Ndd"]=Color3.new(0.553,0.749,0.125),["EyeL"]=Color3.new(0.067,0.067,0.067),["EyeR"]=Color3.new(0.067,0.067,0.067),["eUG"]=Color3.new(0.553,0.749,0.125)},
		"Basic",
		45,
		50
	),


		["Trippi Troppi"] = createCreature(
			24,
			"Trippi Troppi",
			"rbxassetid://0",
			"rbxassetid://0",
			"Trippi Troppi is said to have evolved when a fish adapted to land but never fully let go of its aquatic nature. It waddles along riverbanks searching for food, using its stubby arms to scoop up berries and insects. Despite its dopey appearance, it becomes fiercely aggressive if its belly is poked.",
			{ "Water", "Normal" },
			{
				HP = 70,
				Attack = 45,
				Defense = 55,
				Speed = 30,
			},
			{
				
			},
			nil,
			nil,
			2, 
			{["TopFin"]=Color3.new(0.624,0.631,0.675),["BottomFin"]=Color3.new(0.800,0.557,0.412),["HeadMesh"]=Color3.new(0.792,0.796,0.820),["BackFin"]=Color3.new(0.624,0.631,0.675),["Body"]=Color3.new(0.800,1.000,0.800),["ArmR"]=Color3.new(0.388,0.373,0.384),["ArmL"]=Color3.new(0.388,0.373,0.384),["LegR"]=Color3.new(0.388,0.373,0.384),["LegL"]=Color3.new(0.388,0.373,0.384),["BlackEyeR"]=Color3.new(0.067,0.067,0.067),["BlackEyeL"]=Color3.new(0.067,0.067,0.067),["Eyes"]=Color3.new(0.580,0.745,0.506),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
			"Basic",
			45,
			50
		),

		["Il Cacto Hipopotamo"] = createCreature(
			25,
			"Il Cacto Hipopotamo",
			"rbxassetid://0",
			"rbxassetid://0",
			"Il Catco Hippotamo is a mysterious fusion of flora and fauna. It thrives in scorching deserts, absorbing sunlight through its cactus body while storing water in its hippo-like head. Despite its lazy stance, it fiercely defends its territory by launching sharp cactus needles when disturbed.",
			{ "Grass", "Ground" },
			{
				HP = 70,
				Attack = 45,
				Defense = 55,
				Speed = 30,
			},
			{
				
			},
			nil,
			nil,
			2, 
			{["BodyMain"]=Color3.new(0.549,0.357,0.624),["Ears"]=Color3.new(1.000,0.596,0.863),["FootL"]=Color3.new(0.627,0.518,0.310),["FootR"]=Color3.new(0.627,0.518,0.310),["HeadMesh"]=Color3.new(0.612,0.627,0.706),["EyePartR"]=Color3.new(1.000,0.596,0.863),["EyePartL"]=Color3.new(1.000,0.596,0.863),["EyeR"]=Color3.new(0.973,0.973,0.973),["EyeL"]=Color3.new(0.067,0.067,0.067),["Dark"]=Color3.new(0.408,0.231,0.380),["HeadParts"]=Color3.new(0.243,0.239,0.227),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
			"Basic",
			45,
			50
		),

		["Chicleteira"] = createCreature(
			26,
			"Chicleteira",
			"rbxassetid://0",
			"rbxassetid://0",
			"A humanoid brainrot that looks like a red gumball machine. It chews and fires sticky gum that traps anything it hits. Its laughter echoes in alleys and malls long after it’s gone.",
			{ "Steel" },
			{
				HP = 70,
				Attack = 45,
				Defense = 55,
				Speed = 30,
			},
			{
				
			},
			nil,
			nil,
			2, 
			{["Main_Body"]=Color3.new(0.035,0.537,0.812),["Cap"]=Color3.new(0.035,0.537,0.812),["Glass_Container"]=Color3.new(0.388,0.373,0.384),["CoinMain"]=Color3.new(0.388,0.373,0.384),["Coin"]=Color3.new(0.275,0.263,0.271),["Arm_Right"]=Color3.new(0.051,0.412,0.675),["Arm_left"]=Color3.new(0.051,0.412,0.675),["Leg_Right"]=Color3.new(0.035,0.537,0.812),["Leg_Left"]=Color3.new(0.035,0.537,0.812),["Gumballs"]=Color3.new(0.035,0.537,0.812),["Smile"]=Color3.new(0.906,0.906,0.925),["Face_Piece"]=Color3.new(0.427,0.522,0.584),["Eyebrow_Left"]=Color3.new(0.067,0.067,0.067),["Eyebrow_Right"]=Color3.new(0.067,0.067,0.067),["Eyeball_Right"]=Color3.new(0.875,0.875,0.871),["Eyeball_Left"]=Color3.new(0.875,0.875,0.871),["Iris_Left"]=Color3.new(0.067,0.067,0.067),["Iris_Right"]=Color3.new(0.067,0.067,0.067),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
			"Basic",
			45,
			50
		),

		["Špijuniro Golubiro"] = createCreature(
			27,
			"Špijuniro Golubiro",
			"rbxassetid://0",
			"rbxassetid://0",
			"A mechanical-coated pigeon that acts as a covert agent. Its trench coat conceals spy gadgets, and its lens-like eyes record everything. It reports what it sees to unknown forces, vanishing the moment it’s spotted.",
			{ "Flying", "Steel" },
			{
				HP = 70,
				Attack = 45,
				Defense = 55,
				Speed = 30,
			},
			{
				
			},
			nil,
			nil,
			2, 
			{["AntennaOne"]=Color3.new(0.208,0.208,0.208),["Armour"]=Color3.new(0.412,0.400,0.361),["AtnennaTwo"]=Color3.new(0.208,0.208,0.208),["Beak"]=Color3.new(0.106,0.165,0.208),["BodyMain"]=Color3.new(0.486,0.361,0.275),["Box"]=Color3.new(0.388,0.373,0.384),["Camera"]=Color3.new(0.208,0.208,0.208),["Communication"]=Color3.new(0.208,0.208,0.208),["Connector"]=Color3.new(0.208,0.208,0.208),["DeviceL"]=Color3.new(0.208,0.208,0.208),["DeviceR"]=Color3.new(0.208,0.208,0.208),["EyesWhite"]=Color3.new(1.000,0.690,0.000),["FootL"]=Color3.new(0.745,0.675,0.529),["FootR"]=Color3.new(0.745,0.675,0.529),["Iris"]=Color3.new(0.588,0.404,0.000),["WingL"]=Color3.new(0.486,0.361,0.275),["WingR"]=Color3.new(0.486,0.361,0.275),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
			"Basic",
			45,
			50
		),

		
		["Avocadini Guffo"] = createCreature(
			28,
			"Avocadini Guffo",
			"rbxassetid://0",
			"rbxassetid://0",
			"A plump owl with the body of an avocado. Though it has wings, they’re too small to lift its weight, so it waddles instead of flies.",
			{ "Grass" },
			{
				HP = 70,
				Attack = 45,
				Defense = 55,
				Speed = 30,
			},
			{
				
			},
			nil,
			nil,
			2, 
			{["Body"]=Color3.new(0.514,0.365,0.694),["Crest"]=Color3.new(0.518,0.216,0.502),["Eye_Ring_Thing"]=Color3.new(0.792,0.749,0.639),["PulpTwo"]=Color3.new(0.412,0.251,0.157),["Right_Leg"]=Color3.new(0.337,0.259,0.212),["Left_Leg"]=Color3.new(0.337,0.259,0.212),["Right_Eye"]=Color3.new(0.396,0.165,0.384),["Left_Eye"]=Color3.new(0.396,0.165,0.384),["Right_Wing"]=Color3.new(0.396,0.165,0.384),["Left_Wing"]=Color3.new(0.396,0.165,0.384),["Black_Right"]=Color3.new(0.067,0.067,0.067),["Pulp"]=Color3.new(0.412,0.251,0.157),["White_Right"]=Color3.new(0.973,0.973,0.973),["Black_Left"]=Color3.new(0.067,0.067,0.067),["White_Left"]=Color3.new(0.973,0.973,0.973),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647)},
			"Basic",
			45,
			50
		),

		["Bombombini Gusini"] = createCreature(
			29,
			"Bombombini Gusini",
			"rbxassetid://0",
			"rbxassetid://0",
			"Bombombini Gusini is a fusion of goose and fighter jet, known for breaking the sound barrier while honking furiously.",
			{ "Flying", "Steel" },
			{
				HP = 70,
				Attack = 45,
				Defense = 55,
				Speed = 30,
			},
			{
				
			},
			nil,
			nil,
			2, 
			{["Beak"]=Color3.new(0.855,0.522,0.255),["BlackNose"]=Color3.new(0.067,0.067,0.067),["Torso"]=Color3.new(0.961,0.804,0.188),["WingR"]=Color3.new(0.973,0.973,0.973),["Eye"]=Color3.new(0.067,0.067,0.067),["EyeWhite"]=Color3.new(0.973,0.973,0.973),["FootL"]=Color3.new(0.886,0.608,0.251),["FootR"]=Color3.new(0.886,0.608,0.251),["Head"]=Color3.new(0.961,0.804,0.188),["LegL"]=Color3.new(0.886,0.608,0.251),["Middle"]=Color3.new(0.973,0.973,0.973),["ThighL"]=Color3.new(0.961,0.804,0.188),["ThighR"]=Color3.new(0.961,0.804,0.188),["C_R"]=Color3.new(0.035,0.537,0.812),["WingL"]=Color3.new(0.973,0.973,0.973),["WingBack"]=Color3.new(0.973,0.973,0.973),["WingBackBottom"]=Color3.new(0.973,0.973,0.973),["C_L"]=Color3.new(0.035,0.537,0.812),["HumanoidRootPart"]=Color3.new(0.639,0.635,0.647),["LegR"]=Color3.new(0.886,0.608,0.251)},
			"Basic",
			45,
			50
		),


	-- Keep this one at a high number
	["Tralalero Tralala"] = createCreature(
		400,
		"Tralalero Tralala",
		"rbxassetid://140328234982946",
		nil,
		"A three‑legged shark wearing shoes. A Fast swimmer.",
		{ "Water" },
		{
			HP = 35,
			Attack = 55,
			Defense = 40,
			Speed = 90,
		},
		{
			[1] = {"Water Jet"},
			[8] = {"Fast Attack"},
			[16] = {"Bite"},
			[24] = {"Aqua Slash"},
			[32] = {"Crunch"},
			[40] = {"Hydro Burst"}
		},
		nil,
		nil,
		210,
		nil,
		"Rare",
		60, 50
	),
}

return Creatures
