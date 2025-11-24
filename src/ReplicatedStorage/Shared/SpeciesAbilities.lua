--!strict
-- SpeciesAbilities.lua
-- Maps species name -> list of { Name = ability, Chance = percent }

local SpeciesAbilities: {[string]: { {Name: string, Chance: number} }} = {
    ["Doggolino"] = {
        { Name = "Fireup", Chance = 98 }, -- blaze analogue
        { Name = "Menace", Chance = 2 }, -- Intimidate analogue
    },
    ["Frulli Frulla"] = {
        { Name = "Big Beaks", Chance = 98 },
        { Name = "Wind Wings", Chance = 2 }, -- Gale Wings analogue
    },
    ["Kitung"] = {
        { Name = "Steadfast", Chance = 50 },
        { Name = "Absolute Focus", Chance = 50 }, -- Inner Focus analogue
    },
    ["Sir Tung"] = {
        { Name = "Steadspeed", Chance = 68 },
        { Name = "Magic Mirror", Chance = 30 }, -- Synchronize-like effects per spec
        { Name = "Magic Eyes", Chance = 2 },
    },
    ["Magi-Tung"] = {
        { Name = "Steadspeed", Chance = 68 },
        { Name = "Synchronize", Chance = 30 },
        { Name = "Magic Eyes", Chance = 2 },
    },
    ["Twirlina"] = {
        { Name = "Fairy Sense", Chance = 98 },
        { Name = "Pixelate", Chance = 2 },
    },
    ["Ballerina Cappuccina"] = {
        { Name = "Fairy Sense", Chance = 98 },
        { Name = "Ball Room", Chance = 2 },
    },
    ["Primarina Ballerina"] = {
        { Name = "Fairy Sense", Chance = 98 },
        { Name = "Ball Room", Chance = 2 },
    },
    ["Frigo Camelo"] = {
        { Name = "Hard Head", Chance = 50 },
        { Name = "Sand Speed", Chance = 50 },
    },
    ["Refricamel"] = {
        { Name = "Hard Head", Chance = 50 },
        { Name = "Refrigerate", Chance = 50 },
    },
    ["Glacimel"] = {
        { Name = "Hard Head", Chance = 68 },
        { Name = "Refrigerate", Chance = 30 },
        { Name = "Thickness", Chance = 2 },
    },
    ["Timmy Cheddar"] = {
        { Name = "Run Away", Chance = 68 },
        { Name = "Scrapper", Chance = 30 },
        { Name = "Dispirit", Chance = 2 },
    },
    ["Tim Cheese"] = {
        { Name = "Dispirit", Chance = 68 },
        { Name = "Scrapper", Chance = 30 },
        { Name = "Lithe", Chance = 2 },
    },
    ["Burbaloni Lulliloli"] = {
        { Name = "Sand Cover", Chance = 68 },
        { Name = "Water Press", Chance = 30 },
        { Name = "Matrix Breaker", Chance = 2 },
    },
    ["Chimpanini"] = {
        { Name = "Sun Bounty", Chance = 68 },
        { Name = "Permeate", Chance = 30 },
        { Name = "Sap Siphon", Chance = 2 },
    },
    ["Chimpanzini Bananini"] = {
        { Name = "Sun Bounty", Chance = 68 },
        { Name = "Permeate", Chance = 30 },
        { Name = "Sap Siphon", Chance = 2 },
    },
    ["Duckaroo"] = {
        { Name = "Sand Cover", Chance = 68 },
        { Name = "Great Fortune", Chance = 30 },
        { Name = "Wind Wings", Chance = 2 },
    },
    ["Tadbalabu"] = {
        { Name = "Permeate", Chance = 68 },
        { Name = "Grass Veil", Chance = 30 },
        { Name = "Sap Siphon", Chance = 2 },
    },
    ["Abrazard"] = {
        { Name = "Trickster", Chance = 68 },
        { Name = "Magic Mirror", Chance = 30 },
        { Name = "Arcane Veil", Chance = 2 },
    },
    ["Bolasaeg Selluaim"] = {
        { Name = "Sticky Goo", Chance = 68 },
        { Name = "Corrosive Skin", Chance = 30 },
        { Name = "Sludge Shield", Chance = 2 },
    },
    ["Trippi Troppi"] = {
        { Name = "Amphibious", Chance = 68 },
        { Name = "Stubborn Waddle", Chance = 30 },
        { Name = "Mudslide", Chance = 2 },
    },
    ["Il Cacto Hipopotamo"] = {
        { Name = "Sun Bounty", Chance = 68 },
        { Name = "Needle Guard", Chance = 30 },
        { Name = "Desert Reservoir", Chance = 2 },
    },
    ["Chicleteira"] = {
        { Name = "Bubble Trap", Chance = 68 },
        { Name = "Steel Jaw", Chance = 30 },
        { Name = "Elastic Trap", Chance = 2 },
    },
    ["Špijuniro Golubiro"] = {
        { Name = "Recon Flight", Chance = 68 },
        { Name = "Stealth Feathers", Chance = 30 },
        { Name = "Spy Lens", Chance = 2 },
    },
    ["Avocadini Guffo"] = {
        { Name = "Seed Shield", Chance = 68 },
        { Name = "Waddle Stomp", Chance = 30 },
        { Name = "Solar Wrath", Chance = 2 },
    },
    ["Bombombini Gusini"] = {
        { Name = "Jetstream", Chance = 68 },
        { Name = "Metallic Glide", Chance = 30 },
        { Name = "Overdrive", Chance = 2 },
    },
    ["Tralalero Tralala"] = {
        { Name = "Swift Current", Chance = 68 },
        { Name = "Sharp Fins", Chance = 30 },
        { Name = "Triple Kick", Chance = 2 },
    },
    ["Boneca Ambalabu"] = {
        { Name = "Permeate", Chance = 68 },
        { Name = "Grass Veil", Chance = 30 },
        { Name = "Sap Siphon", Chance = 2 },
    },
    ["Ambalabu Ton-ton"] = {
        { Name = "Permeate", Chance = 68 },
        { Name = "Sap Siphon", Chance = 30 },
        { Name = "Drumming Beat", Chance = 2 },
    },
}

return SpeciesAbilities


