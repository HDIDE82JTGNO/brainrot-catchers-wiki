local LuaTypes = require(script.Parent:WaitForChild("LuaTypes"))
local Types = require(script.Parent:WaitForChild("Types"))

-- Type declarations
type Moves_Type = LuaTypes.Move
type StatStageEffect = LuaTypes.StatStageEffect
type MultiHitConfig = LuaTypes.MultiHitConfig

-- Constructor helper
local function createMove(
    basePower: number, 
    accuracy: number, 
    priority: number, 
    typeValue, 
    category: "Physical" | "Special" | "Status",
    description: string?, 
    healsPercent: number?,
    statusEffect: string?,
    statusChance: number?,
    causesFlinch: boolean?,
    causesConfusion: boolean?,
    statChanges: {StatStageEffect}?,
    multiHit: MultiHitConfig?
): Moves_Type
    local move: Moves_Type = {
        BasePower = basePower,
        Accuracy = accuracy,
        Priority = priority,
        Type = typeValue,
        Category = category,
        Description = description or "",
        HealsPercent = healsPercent,
    }
    
    if statusEffect then
        move.StatusEffect = statusEffect
        move.StatusChance = statusChance or 100
    end
    
    if causesFlinch then
        move.CausesFlinch = true
    end
    
    if causesConfusion then
        move.CausesConfusion = true
    end
    
    if statChanges and #statChanges > 0 then
        move.StatChanges = statChanges
    end
    
    if multiHit then
        move.MultiHit = multiHit
    end
    
    return move
end

-- Helper to create multi-hit moves
local function createMultiHitMove(
    basePower: number,
    accuracy: number,
    priority: number,
    typeValue,
    category: "Physical" | "Special",
    description: string,
    minHits: number,
    maxHits: number,
    fixed: boolean?,
    statusEffect: string?,
    statusChance: number?,
    causesFlinch: boolean?
): Moves_Type
    return createMove(
        basePower, accuracy, priority, typeValue, category, description,
        nil, statusEffect, statusChance, causesFlinch, nil, nil,
        { MinHits = minHits, MaxHits = maxHits, Fixed = fixed or false }
    )
end

-- Helper to create recoil moves (high-power moves that damage the user)
local function createRecoilMove(
    basePower: number,
    accuracy: number,
    priority: number,
    typeValue,
    category: "Physical" | "Special",
    description: string,
    recoilPercent: number,
    statusEffect: string?,
    statusChance: number?,
    causesFlinch: boolean?
): Moves_Type
    local move = createMove(
        basePower, accuracy, priority, typeValue, category, description,
        nil, statusEffect, statusChance, causesFlinch, nil, nil, nil
    )
    move.RecoilPercent = recoilPercent
    return move
end

-- Helper to create stat boost moves (status moves that only change stats)
local function createStatMove(
    accuracy: number,
    priority: number,
    typeValue,
    description: string,
    statChanges: {StatStageEffect}
): Moves_Type
    return {
        BasePower = 0,
        Accuracy = accuracy,
        Priority = priority,
        Type = typeValue,
        Category = "Status",
        Description = description,
        StatChanges = statChanges,
    }
end

--[[
	MOVE BALANCE PHILOSOPHY (inspired by modern Pokemon):
	
	Base Power Tiers:
	- Very Weak (utility): 0-30 BP
	- Weak (early game): 35-50 BP  
	- Medium (mid game): 55-75 BP
	- Strong (late game): 80-95 BP
	- Very Strong (signature/risky): 100-150 BP
	
	Priority:
	- +2: Extreme priority (protect-like)
	- +1: Quick Attack tier
	- 0: Normal
	- -1: Slow moves
	
	Accuracy Guidelines:
	- 100%: Reliable moves (usually lower power)
	- 90-95%: Standard strong moves
	- 80-85%: High power moves
	- 50-70%: High risk/reward moves
	
	Status Effect Chances:
	- 10%: Low (on strong moves)
	- 20-30%: Moderate
	- 100%: Guaranteed (on utility moves or low-power moves)
]]

return {
	--==========================================================================
	-- NORMAL TYPE MOVES
	--==========================================================================
	["Tackle"] = createMove(40, 100, 0, Types.Normal, "Physical",
		"A straightforward physical charge. Reliable but basic."),
	["Scratch"] = createMove(40, 100, 0, Types.Normal, "Physical",
		"A quick claw swipe. A basic but reliable attack."),
	["Fast Attack"] = createMove(40, 100, 1, Types.Normal, "Physical",
		"A swift strike that always hits first. Priority +1."),
	["Tail Slap"] = createMultiHitMove(25, 85, 0, Types.Normal, "Physical",
		"Strikes the foe with its tail 2-5 times.", 2, 5),
	["Comet Punch"] = createMultiHitMove(18, 85, 0, Types.Normal, "Physical",
		"A flurry of punches that hits 2-5 times.", 2, 5),
	["Barrage"] = createMultiHitMove(15, 85, 0, Types.Normal, "Physical",
		"Hurls round objects 2-5 times in a row.", 2, 5),
	["Pin Missile"] = createMultiHitMove(25, 95, 0, Types.Normal, "Physical",
		"Sharp spikes are fired 2-5 times.", 2, 5),
	
	-- Recoil Moves (Normal)
	["Take Down"] = createRecoilMove(90, 85, 0, Types.Normal, "Physical",
		"A reckless full-body charge. The user takes 25% of the damage dealt.", 25),
	["Double-Edge"] = createRecoilMove(120, 100, 0, Types.Normal, "Physical",
		"A life-risking tackle with extreme power. The user takes 33% of the damage dealt.", 33),
	["Head Smash"] = createRecoilMove(150, 80, 0, Types.Normal, "Physical",
		"A devastating headbutt with tremendous power. The user takes 50% of the damage dealt.", 50),

	--==========================================================================
	-- FIRE TYPE MOVES
	--==========================================================================
	["Grease Jab"] = createMove(60, 100, 0, Types.Fire, "Physical",
		"A sizzling punch coated in hot oil. 20% chance to burn the target.", nil, "BRN", 20),
	["Searing Splat"] = createMove(90, 95, 0, Types.Fire, "Special",
		"Slams the foe with scalding fryer oil, leaving lingering embers.", nil, "BRN", 20),
	
	-- Recoil Moves (Fire)
	["Flare Blitz"] = createRecoilMove(120, 100, 0, Types.Fire, "Physical",
		"Cloaked in flames, charges recklessly. 10% burn chance. User takes 33% recoil.", 33, "BRN", 10),

	--==========================================================================
	-- ELECTRIC TYPE MOVES
	--==========================================================================
	["Static Peck"] = createMove(55, 100, 0, Types.Electric, "Physical",
		"A quick, charged peck. 20% chance to paralyze the target.", nil, "PAR", 20),
	["Thunder Burst"] = createMove(90, 90, 0, Types.Electric, "Special",
		"A mid-air electrical discharge. 30% chance to paralyze.", nil, "PAR", 30),
	
	-- Recoil Moves (Electric)
	["Wild Charge"] = createRecoilMove(90, 100, 0, Types.Electric, "Physical",
		"An electrified tackle with reckless abandon. User takes 25% recoil.", 25),
	["Volt Tackle"] = createRecoilMove(120, 100, 0, Types.Electric, "Physical",
		"Charges with overwhelming voltage. 10% paralysis chance. User takes 33% recoil.", 33, "PAR", 10),

	--==========================================================================
	-- GROUND TYPE MOVES
	--==========================================================================
	["Earthquake"] = createMove(100, 100, 0, Types.Ground, "Physical",
		"A massive tremor that shakes all around. One of the strongest ground moves."),
	["Sand Storm"] = createMove(60, 100, 0, Types.Ground, "Special",
		"Blasts the foe with cutting sand. May lower accuracy."),

	--==========================================================================
	-- DARK TYPE MOVES
	--==========================================================================
	["Bite"] = createMove(60, 100, 0, Types.Dark, "Physical",
		"A quick, vicious bite. May cause the target to flinch.", nil, nil, nil, true),
	["Crunch"] = createMove(80, 100, 0, Types.Dark, "Physical",
		"Crushes the foe with sharp fangs. May cause flinching.", nil, nil, nil, true),
	["Beat Up"] = createMultiHitMove(10, 100, 0, Types.Dark, "Physical",
		"Calls allies to attack. Hits 2-5 times with varying strength.", 2, 5),

	--==========================================================================
	-- FLYING TYPE MOVES
	--==========================================================================
	["Peck"] = createMove(40, 100, 0, Types.Flying, "Physical",
		"A sharp beak jab. Basic but reliable flying attack."),
	["Dive Bomb"] = createMove(90, 80, 0, Types.Flying, "Physical",
		"A risky aerial plunge from great heights. High power but can miss."),
	["Duststorm Dash"] = createMove(70, 95, 1, Types.Flying, "Physical",
		"Dashes through a duststorm with priority. Excels in sandy weather."),
	["Perch"] = createMove(0, 100, 0, Types.Flying, "Status",
		"Recovers composure by briefly perching. Heals 50% of max HP.", 50),
	
	-- Recoil Moves (Flying)
	["Brave Bird"] = createRecoilMove(120, 100, 0, Types.Flying, "Physical",
		"A fearless dive from the sky. The user takes 33% of the damage dealt.", 33),
	["Sky Crash"] = createRecoilMove(100, 95, 0, Types.Flying, "Physical",
		"A high-speed aerial collision. The user takes 25% of the damage dealt.", 25),

	--==========================================================================
	-- WATER TYPE MOVES
	--==========================================================================
	["Water Jet"] = createMove(40, 100, 1, Types.Water, "Physical",
		"A pressurized burst of water that always strikes first. Priority +1."),
	["Aqua Slash"] = createMove(75, 100, 0, Types.Water, "Physical",
		"Slices the foe with a blade of pressurized water."),
	["Hydro Burst"] = createMove(110, 80, 0, Types.Water, "Special",
		"Unleashes a devastating water blast. High power but can miss."),
	["Water Shuriken"] = createMultiHitMove(15, 100, 1, Types.Water, "Special",
		"Throws sharp shurikens of water 2-5 times. Priority +1.", 2, 5),

	--==========================================================================
	-- FIGHTING TYPE MOVES
	--==========================================================================
	["Double Kick"] = createMultiHitMove(30, 100, 0, Types.Fighting, "Physical",
		"Rapid successive kicks. Always hits exactly twice.", 2, 2, true),
	["Uppercut"] = createMove(70, 100, 0, Types.Fighting, "Physical",
		"A rising punch aimed at the chin. May cause flinching.", nil, nil, nil, true),
	["Grand Slam"] = createMove(100, 90, 0, Types.Fighting, "Physical",
		"A show-stopping finishing blow. Powerful but slightly inaccurate."),
	["Knockout"] = createMove(150, 50, 0, Types.Fighting, "Physical",
		"A devastating haymaker. Extreme power but very hard to land.", nil, nil, nil, true),
	
	-- Recoil Moves (Fighting)
	["Submission"] = createRecoilMove(80, 80, 0, Types.Fighting, "Physical",
		"A reckless body slam that pins the foe. User takes 25% recoil.", 25),
	["Triple Kick"] = createMultiHitMove(10, 90, 0, Types.Fighting, "Physical",
		"Three consecutive kicks. Each hit gains 10 power: 10, 20, 30.", 3, 3, true),
	["Fury Swipes"] = createMultiHitMove(18, 80, 0, Types.Normal, "Physical",
		"Rakes the foe with claws 2-5 times in a row.", 2, 5),
	["Arm Thrust"] = createMultiHitMove(15, 100, 0, Types.Fighting, "Physical",
		"A flurry of open-palmed arm thrusts that hits 2-5 times.", 2, 5),
	["Close Flurry"] = createMultiHitMove(25, 90, 0, Types.Fighting, "Physical",
		"A rapid combo of punches that hits exactly twice.", 2, 2, true),

	--==========================================================================
	-- GRASS TYPE MOVES
	--==========================================================================
	["Vine Whip"] = createMove(45, 100, 0, Types.Grass, "Physical",
		"Strikes with snapping vines. A reliable grass attack."),
	["Seed Toss"] = createMove(60, 95, 0, Types.Grass, "Physical",
		"Pelts the foe with hardened seeds."),
	["Leaf Slash"] = createMove(75, 100, 0, Types.Grass, "Physical",
		"Slashes with razor-sharp leaves. Strong and reliable."),
	["Bullet Seed"] = createMultiHitMove(25, 100, 0, Types.Grass, "Physical",
		"Fires seeds in rapid succession. Hits 2-5 times.", 2, 5),
	["Thorn Barrage"] = createMultiHitMove(20, 90, 0, Types.Grass, "Physical",
		"Launches sharp thorns 2-5 times.", 2, 5),

	--==========================================================================
	-- PSYCHIC TYPE MOVES
	--==========================================================================
	["Psychic Pulse"] = createMove(60, 100, 0, Types.Psychic, "Special",
		"Emits a sharp mental pulse. 20% chance to confuse the target.", nil, nil, nil, nil, true),
	["Mind Slam"] = createMove(85, 100, 0, Types.Psychic, "Special",
		"Throws mental force like a hammer. May cause confusion.", nil, nil, nil, nil, true),

	--==========================================================================
	-- STEEL TYPE MOVES
	--==========================================================================
	["Shield Bash"] = createMove(70, 100, 0, Types.Steel, "Physical",
		"Bashes the foe with a sturdy guard. May cause flinching.", nil, nil, nil, true),
	["Gear Grind"] = createMultiHitMove(50, 85, 0, Types.Steel, "Physical",
		"Grinds the foe with steel gears. Always hits twice.", 2, 2, true),
	["Spike Cannon"] = createMultiHitMove(20, 100, 0, Types.Steel, "Physical",
		"Launches steel spikes 2-5 times in succession.", 2, 5),

	--==========================================================================
	-- FAIRY TYPE MOVES
	--==========================================================================
	["Dance Strike"] = createMove(60, 100, 0, Types.Fairy, "Physical",
		"A rhythmic strike executed mid-dance. Graceful and reliable."),
	["Dazzle Beam"] = createMove(75, 100, 0, Types.Fairy, "Special",
		"Fires a brilliant, disorienting ray. May cause confusion.", nil, nil, nil, nil, true),
	["Fairy Strike"] = createMove(85, 95, 0, Types.Fairy, "Physical",
		"A charged blow infused with fairy power. Strong fairy attack."),
	["Sunbeam"] = createMove(120, 90, 0, Types.Fairy, "Special",
		"Concentrates radiance into a piercing beam. Extremely powerful."),

	--==========================================================================
	-- POISON TYPE MOVES
	--==========================================================================
	["Ooze Shot"] = createMove(45, 100, 0, Types.Poison, "Special",
		"Fires a glob of toxic ooze. 30% chance to poison.", nil, "PSN", 30),
	["Sludge Puff"] = createMove(60, 100, 0, Types.Poison, "Special",
		"A burst of sludge coats the foe. 30% chance to poison.", nil, "PSN", 30),
	["Toxic Wave"] = createMove(70, 90, 0, Types.Poison, "Special",
		"A rolling wave of toxins. Guaranteed to badly poison.", nil, "TOX", 100),
	["Corrosive Grasp"] = createMove(65, 95, 0, Types.Poison, "Physical",
		"Burning toxins corrode armor. 30% chance to poison.", nil, "PSN", 30),
	["Acidic Deluge"] = createMove(90, 85, 0, Types.Poison, "Special",
		"Drowns the foe in corrosive acid. 50% chance to poison.", nil, "PSN", 50),

	--==========================================================================
	-- STAT-CHANGING MOVES (Status Moves)
	--==========================================================================
	
	-- ATTACK BOOSTING MOVES
	["Power Up"] = createStatMove(0, 0, Types.Normal,
		"Focuses energy to sharply raise Attack.", {
		{ Stat = "Attack", Stages = 2, Target = "Self" },
	}),
	["Battle Cry"] = createStatMove(0, 0, Types.Fighting,
		"A fierce roar that boosts Attack and Speed.", {
		{ Stat = "Attack", Stages = 1, Target = "Self" },
		{ Stat = "Speed", Stages = 1, Target = "Self" },
	}),
	["Rage Boost"] = createStatMove(0, 0, Types.Dark,
		"Channels rage to drastically raise Attack.", {
		{ Stat = "Attack", Stages = 3, Target = "Self" },
	}),
	
	-- DEFENSE BOOSTING MOVES
	["Harden"] = createStatMove(0, 0, Types.Normal,
		"Stiffens the body to raise Defense.", {
		{ Stat = "Defense", Stages = 1, Target = "Self" },
	}),
	["Iron Defense"] = createStatMove(0, 0, Types.Steel,
		"Hardens the body like iron to sharply raise Defense.", {
		{ Stat = "Defense", Stages = 2, Target = "Self" },
	}),
	["Barrier"] = createStatMove(0, 0, Types.Psychic,
		"Creates a psychic barrier that sharply raises Defense.", {
		{ Stat = "Defense", Stages = 2, Target = "Self" },
	}),
	
	-- SPEED BOOSTING MOVES
	["Agility"] = createStatMove(0, 0, Types.Psychic,
		"Relaxes the body to move faster. Sharply raises Speed.", {
		{ Stat = "Speed", Stages = 2, Target = "Self" },
	}),
	["Quick Step"] = createStatMove(0, 0, Types.Normal,
		"Prepares for quick movements. Raises Speed.", {
		{ Stat = "Speed", Stages = 1, Target = "Self" },
	}),
	["Jet Stream"] = createStatMove(0, 0, Types.Flying,
		"Rides air currents to drastically raise Speed.", {
		{ Stat = "Speed", Stages = 3, Target = "Self" },
	}),
	
	-- MULTI-STAT BOOSTING MOVES
	["Bulk Up"] = createStatMove(0, 0, Types.Fighting,
		"Bulks up muscles to raise Attack and Defense.", {
		{ Stat = "Attack", Stages = 1, Target = "Self" },
		{ Stat = "Defense", Stages = 1, Target = "Self" },
	}),
	["Dragon Dance"] = createStatMove(0, 0, Types.Normal,
		"A mystic dance that raises Attack and Speed.", {
		{ Stat = "Attack", Stages = 1, Target = "Self" },
		{ Stat = "Speed", Stages = 1, Target = "Self" },
	}),
	["Calm Mind"] = createStatMove(0, 0, Types.Psychic,
		"Clears the mind to raise Special Attack and Special Defense.", {
		{ Stat = "SpecialAttack", Stages = 1, Target = "Self" },
		{ Stat = "SpecialDefense", Stages = 1, Target = "Self" },
	}),
	
	-- ACCURACY/EVASION MOVES
	["Focus Energy"] = createStatMove(0, 0, Types.Normal,
		"Concentrates deeply to raise Accuracy.", {
		{ Stat = "Accuracy", Stages = 1, Target = "Self" },
	}),
	["Double Team"] = createStatMove(0, 0, Types.Normal,
		"Creates illusory copies to raise Evasion.", {
		{ Stat = "Evasion", Stages = 1, Target = "Self" },
	}),
	["Minimize"] = createStatMove(0, 0, Types.Normal,
		"Shrinks to raise Evasion sharply.", {
		{ Stat = "Evasion", Stages = 2, Target = "Self" },
	}),
	
	-- OPPONENT STAT LOWERING MOVES
	["Growl"] = createStatMove(100, 0, Types.Normal,
		"A cute growl that lowers the foe's Attack.", {
		{ Stat = "Attack", Stages = -1, Target = "Opponent" },
	}),
	["Leer"] = createStatMove(100, 0, Types.Normal,
		"An intimidating look that lowers the foe's Defense.", {
		{ Stat = "Defense", Stages = -1, Target = "Opponent" },
	}),
	["Tail Whip"] = createStatMove(100, 0, Types.Normal,
		"Wags tail cutely to lower the foe's Defense.", {
		{ Stat = "Defense", Stages = -1, Target = "Opponent" },
	}),
	["Screech"] = createStatMove(85, 0, Types.Normal,
		"An earsplitting screech that harshly lowers Defense.", {
		{ Stat = "Defense", Stages = -2, Target = "Opponent" },
	}),
	["Scary Face"] = createStatMove(100, 0, Types.Normal,
		"A terrifying face that harshly lowers Speed.", {
		{ Stat = "Speed", Stages = -2, Target = "Opponent" },
	}),
	["Charm"] = createStatMove(100, 0, Types.Fairy,
		"Charms the foe to harshly lower Attack.", {
		{ Stat = "Attack", Stages = -2, Target = "Opponent" },
	}),
	["Sweet Scent"] = createStatMove(100, 0, Types.Normal,
		"A sweet aroma that lowers the foe's Evasion.", {
		{ Stat = "Evasion", Stages = -1, Target = "Opponent" },
	}),
	["Sand Attack"] = createStatMove(100, 0, Types.Ground,
		"Throws sand to lower the foe's Accuracy.", {
		{ Stat = "Accuracy", Stages = -1, Target = "Opponent" },
	}),
	["Smokescreen"] = createStatMove(100, 0, Types.Normal,
		"Obscures with smoke to lower the foe's Accuracy.", {
		{ Stat = "Accuracy", Stages = -1, Target = "Opponent" },
	}),
	["Flash"] = createStatMove(100, 0, Types.Normal,
		"A bright flash that sharply lowers Accuracy.", {
		{ Stat = "Accuracy", Stages = -2, Target = "Opponent" },
	}),
	
	-- ATTACKING MOVES WITH STAT CHANGES
	["Crush Claw"] = createMove(75, 95, 0, Types.Normal, "Physical", 
		"A vicious claw attack. 50% chance to lower Defense.", nil, nil, nil, nil, nil, {
		{ Stat = "Defense", Stages = -1, Target = "Opponent", Chance = 50 },
	}),
	["Metal Claw"] = createMove(50, 95, 0, Types.Steel, "Physical", 
		"A steel claw attack. 10% chance to raise Attack.", nil, nil, nil, nil, nil, {
		{ Stat = "Attack", Stages = 1, Target = "Self", Chance = 10 },
	}),
	["Flame Charge"] = createMove(50, 100, 0, Types.Fire, "Physical", 
		"Cloaked in flame, charges the foe. Raises Speed.", nil, nil, nil, nil, nil, {
		{ Stat = "Speed", Stages = 1, Target = "Self", Chance = 100 },
	}),
	["Rock Smash"] = createMove(40, 100, 0, Types.Fighting, "Physical", 
		"A smashing attack. 50% chance to lower Defense.", nil, nil, nil, nil, nil, {
		{ Stat = "Defense", Stages = -1, Target = "Opponent", Chance = 50 },
	}),
	["Shadow Ball"] = createMove(80, 100, 0, Types.Dark, "Special", 
		"A shadowy blob of energy. 20% chance to lower Special Defense.", nil, nil, nil, nil, nil, {
		{ Stat = "SpecialDefense", Stages = -1, Target = "Opponent", Chance = 20 },
	}),
	["Psychic Blast"] = createMove(90, 100, 0, Types.Psychic, "Special", 
		"A powerful psychic attack. 10% chance to lower Special Defense.", nil, nil, nil, nil, nil, {
		{ Stat = "SpecialDefense", Stages = -1, Target = "Opponent", Chance = 10 },
	}),
	["Power-Up Punch"] = createMove(40, 100, 0, Types.Fighting, "Physical", 
		"A punch that builds power. Always raises Attack.", nil, nil, nil, nil, nil, {
		{ Stat = "Attack", Stages = 1, Target = "Self", Chance = 100 },
	}),
	["Icy Wind"] = createMove(55, 95, 0, Types.Water, "Special", 
		"A chilling gust. Always lowers the foe's Speed.", nil, nil, nil, nil, nil, {
		{ Stat = "Speed", Stages = -1, Target = "Opponent", Chance = 100 },
	}),
	["Mud Slap"] = createMove(20, 100, 0, Types.Ground, "Special", 
		"Hurls mud at the foe. Always lowers Accuracy.", nil, nil, nil, nil, nil, {
		{ Stat = "Accuracy", Stages = -1, Target = "Opponent", Chance = 100 },
	}),
	["Ancient Power"] = createMove(60, 100, 0, Types.Ground, "Special", 
		"An ancient power. 10% chance to raise all stats.", nil, nil, nil, nil, nil, {
		{ Stat = "Attack", Stages = 1, Target = "Self", Chance = 10 },
		{ Stat = "Defense", Stages = 1, Target = "Self", Chance = 10 },
		{ Stat = "SpecialAttack", Stages = 1, Target = "Self", Chance = 10 },
		{ Stat = "SpecialDefense", Stages = 1, Target = "Self", Chance = 10 },
		{ Stat = "Speed", Stages = 1, Target = "Self", Chance = 10 },
	}),
	["Close Combat"] = createMove(120, 100, 0, Types.Fighting, "Physical", 
		"A powerful attack, but lowers your defenses.", nil, nil, nil, nil, nil, {
		{ Stat = "Defense", Stages = -1, Target = "Self", Chance = 100 },
		{ Stat = "SpecialDefense", Stages = -1, Target = "Self", Chance = 100 },
	}),
	["Overheat"] = createMove(130, 90, 0, Types.Fire, "Special", 
		"Attacks with maximum heat. Sharply lowers your Special Attack.", nil, nil, nil, nil, nil, {
		{ Stat = "SpecialAttack", Stages = -2, Target = "Self", Chance = 100 },
	}),
	["Superpower"] = createMove(120, 100, 0, Types.Fighting, "Physical", 
		"A powerful attack that lowers Attack and Defense.", nil, nil, nil, nil, nil, {
		{ Stat = "Attack", Stages = -1, Target = "Self", Chance = 100 },
		{ Stat = "Defense", Stages = -1, Target = "Self", Chance = 100 },
	}),

	--==========================================================================
	-- ENTRY HAZARD MOVES
	--==========================================================================
	
	-- Stealth Rock: Rock-type hazard that damages on switch-in based on type effectiveness
	-- Damage ranges from 3.125% (4x resist) to 50% (4x weak) of max HP
	["Stealth Rock"] = {
		BasePower = 0,
		Accuracy = 0,  -- Never misses (status move)
		Priority = 0,
		Type = Types.Rock,
		Category = "Status",
		Description = "Sets up floating rocks around the foe's side. Foes take Rock-type damage on switch-in.",
		IsHazard = true,
		HazardType = "StealthRock",
	},
	
	-- Spikes: Ground-type hazard that damages grounded foes on switch-in
	-- Stacks up to 3 layers: 12.5%, 16.67%, 25% of max HP
	["Spikes"] = {
		BasePower = 0,
		Accuracy = 0,  -- Never misses (status move)
		Priority = 0,
		Type = Types.Ground,
		Category = "Status",
		Description = "Sets up sharp spikes around the foe's side. Grounded foes take damage on switch-in. Stacks up to 3 times.",
		IsHazard = true,
		HazardType = "Spikes",
		MaxLayers = 3,
	},
	
	-- Toxic Spikes: Poison-type hazard that poisons grounded foes on switch-in
	-- 1 layer = Poison, 2 layers = Badly Poisoned (TOX)
	-- Poison-type foes absorb (remove) the hazard on switch-in
	["Toxic Spikes"] = {
		BasePower = 0,
		Accuracy = 0,  -- Never misses (status move)
		Priority = 0,
		Type = Types.Poison,
		Category = "Status",
		Description = "Sets up poisonous spikes around the foe's side. Grounded foes are poisoned on switch-in. Stacks to 2 layers for bad poison.",
		IsHazard = true,
		HazardType = "ToxicSpikes",
		MaxLayers = 2,
	},
	
	--==========================================================================
	-- HAZARD REMOVAL MOVES
	--==========================================================================
	
	-- Rapid Spin: Removes hazards from your side
	["Rapid Spin"] = createMove(50, 100, 0, Types.Normal, "Physical",
		"Spins rapidly, damaging the foe and removing entry hazards from your side.", nil, nil, nil, nil, nil, {
		{ Stat = "Speed", Stages = 1, Target = "Self", Chance = 100 },
	}),
	
	-- Defog: Removes hazards from both sides (and lowers foe's evasion)
	["Defog"] = createStatMove(0, 0, Types.Flying,
		"Blows away hazards from both sides of the field. Also lowers foe's evasion.", {
		{ Stat = "Evasion", Stages = -1, Target = "Opponent" },
	}),
}
