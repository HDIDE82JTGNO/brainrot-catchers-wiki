local LuaTypes = require(script.Parent:WaitForChild("LuaTypes"))
local Types = require(script.Parent:WaitForChild("Types"))

-- Type declarations
type Moves_Type = LuaTypes.Move

-- Constructor helper
local function createMove(
    basePower: number, 
    accuracy: number, 
    priority: number, 
    typeValue, 
    description: string?, 
    healsPercent: number?,
    statusEffect: string?,
    statusChance: number?,
    causesFlinch: boolean?,
    causesConfusion: boolean?
): Moves_Type
    local move: Moves_Type = {
        BasePower = basePower,
        Accuracy = accuracy,
        Priority = priority,
        Type = typeValue,
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
    
    return move
end

return { -- BasePower, Accuracy, Priority, Type, Description
    ["Tackle"] = createMove(40, 100, 0, Types.Normal, "A straightforward physical charge."),
    ["Scratch"] = createMove(40, 100, 0, Types.Normal, "A quick claw swipe."),
    ["Earthquake"] = createMove(100, 100, 0, Types.Ground, "A massive tremor that shakes all around."),
    ["Fast Attack"] = createMove(40, 100, 1, Types.Normal, "A swift strike that often hits first.", nil, "FRZ", 100),
    ["Crunch"] = createMove(80, 100, 0, Types.Dark, "Crushes the foe with sharp fangs.", nil, nil, true), -- Causes Flinch
    ["Sand Storm"] = createMove(60, 100, 0, Types.Ground, "Blasts the foe with cutting sand."),
    ["Peck"] = createMove(60, 85, 0, Types.Flying, "A sharp beak jab.", nil, nil, true), -- Causes Flinch
	["Duststorm Dash"] = createMove(70, 100, 1, Types.Flying, "Dashes through a duststorm; excels in sandy weather."),
    ["Dive Bomb"] = createMove(70, 50, 0, Types.Flying, "A risky aerial plunge."),
    ["Bite"] = createMove(50, 95, 0, Types.Dark, "A quick, vicious bite.", nil, nil, true), -- Causes Flinch
    ["Perch"] = createMove(0, 100, 0, Types.Flying, "Recovers composure by briefly perching. Recovers 50% of max HP.", 50),
    -- Water type moves
    ["Water Jet"] = createMove(60, 100, 0, Types.Water, "A pressurized burst of water."),
    ["Aqua Slash"] = createMove(75, 100, 0, Types.Water, "Slices the foe with a blade of water."),
    ["Hydro Burst"] = createMove(100, 85, 0, Types.Water, "Unleashes a powerful water blast."),
    -- Fighting type moves
    ["Double Kick"] = createMove(30, 100, 0, Types.Fighting, "Rapid successive kicks."),
    ["Grand Slam"] = createMove(120, 85, 0, Types.Fighting, "A show-stopping finishing blow."),
    ["Uppercut"] = createMove(70, 100, 0, Types.Fighting, "A rising punch aimed at the chin.", nil, nil, true), -- Causes Flinch
    ["Knockout"] = createMove(150, 30, 0, Types.Fighting, "A devastating punch that rarely connects.", nil, nil, true), -- Causes Flinch
    -- Grass type moves
    ["Vine Whip"] = createMove(45, 100, 0, Types.Grass, "Strikes with snapping vines."),
    ["Seed Toss"] = createMove(60, 95, 0, Types.Grass, "Pelts the foe with hardened seeds."),
    ["Leaf Slash"] = createMove(70, 100, 0, Types.Grass, "Slashes with razor-sharp leaves."),
    -- Psychic type moves
    ["Mind Slam"] = createMove(80, 100, 0, Types.Psychic, "Throws mental force like a hammer.", nil, nil, nil, true), -- Causes Confusion
    -- Steel type moves
    ["Shield Bash"] = createMove(75, 100, 0, Types.Steel, "Bashes the foe with a sturdy guard.", nil, nil, true), -- Causes Flinch
    -- Fairy type moves
    ["Dazzle Beam"] = createMove(80, 100, 0, Types.Fairy, "Fires a brilliant, disorienting ray.", nil, nil, nil, true), -- Causes Confusion
    ["Dance Strike"] = createMove(60, 100, 0, Types.Fairy, "A rhythmic strike executed mid-dance."),
    ["Fairy Strike"] = createMove(90, 95, 0, Types.Fairy, "A charged blow infused with fairy power."),
    ["Sunbeam"] = createMove(100, 100, 0, Types.Fairy, "Concentrates radiance into a piercing beam."),
    -- Poison type moves
    ["Ooze Shot"] = createMove(50, 100, 0, Types.Poison, "Fires a glob of toxic ooze.", nil, "PSN", 30), -- 30% chance to Poison
    ["Sludge Puff"] = createMove(60, 100, 0, Types.Poison, "A burst of sludge coats the foe.", nil, "PSN", 30), -- 30% chance to Poison
    ["Toxic Wave"] = createMove(80, 90, 0, Types.Poison, "A rolling poisonous wave engulfs the foe.", nil, "TOX", 100), -- 100% chance to Badly Poison
    ["Corrosive Grasp"] = createMove(70, 95, 0, Types.Poison, "Burning toxins grasp and corrode armor.", nil, "PSN", 30), -- 30% chance to Poison
    ["Acidic Deluge"] = createMove(95, 85, 0, Types.Poison, "Drowns the foe in corrosive acid.", nil, "PSN", 30), -- 30% chance to Poison
}
