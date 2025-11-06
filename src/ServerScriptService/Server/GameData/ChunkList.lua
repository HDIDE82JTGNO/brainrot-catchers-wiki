
local ChunkList = {
	["Title"] = {
		ProperName = "Title",
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"nil","Any"},
	},
	
	--Chunk 1 and Sub rooms
	["Chunk1"] = {
		ProperName = "Cloveroot Town",
		IsSubRoom = false,
		Encounters = {
			{"Frulli Frulla",3,5,20}, -- Min level,Max Level, Chance
			{"Timmy Cheddar",3,5,20}, -- Min level,Max Level, Chance - Pre-evolution
		},
		SubChunks = {
			["Professor's Lab"] = {
				ProperName = "Professor's Lab",
				IsSubRoom = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
			},
			
			["PlayersHouse"] = {
				ProperName = "Your House",
				IsSubRoom = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
			},

			["House1"] = {
				ProperName = "",
				IsSubRoom = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
			},
		},
		ValidPrevious = {"nil","Title","Professor's Lab","PlayersHouse","House1"}
	},
	
	-- Sub-chunks (interior areas)
	["Professor's Lab"] = {
		ProperName = "Professor's Lab",
		IsSubRoom = true,
		Encounters = {},
		ValidPrevious = {"Chunk1"},
	},
	
	["PlayersHouse"] = {
		ProperName = "Your House",
		IsSubRoom = true,
		Encounters = {},
		ValidPrevious = {"Chunk1"},
	},
	
	["House1"] = {
		ProperName = "House 1",
		IsSubRoom = true,
		Encounters = {},
		ValidPrevious = {"Chunk1"},
	},
	
	["CatchCare"] = {
		ProperName = "CatchCare",
		IsSubRoom = true,
		Encounters = {},
		ValidPrevious = {"Any"},
	},
	
	--Chunk 2 and sub rooms
	["Chunk2"] = {
		ProperName = "Route 2",
		IsSubRoom = false,
		Encounters = { 
			{"Frulli Frulla",4,6,35}, -- Min level,Max Level, Chance
			{"Timmy Cheddar",3,6,35},
			{"Burbaloni Lulliloli",5,7,20}, 
			{"Doggolino",3,6,10},
		},
		ValidPrevious = {"Chunk1","Chunk3"}
	},
	--Chunk 3 and sub rooms
	["Chunk3"] = {
		ProperName = "Cresamore Town",
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"Chunk2","Chunk4"},
		HasCatchCareDoor = true,
	},

	--Chunk 4 and sub rooms
	["Chunk4"] = {
		ProperName = "Route 3", -- This is a very small chunk, as we've had quite a big gap between the first area and the first town
		IsSubRoom = false,
		Encounters = {
			{"Chimpanini",10,12,10},
			{"Bolasaeg Selluaim",10,12,30},
			{"Trippi Troppi",10,12,30},
			{"Tadbalabu",10,12,30},
		},
		ValidPrevious = {"Chunk3"}
	},

	--Chunk 4 and sub rooms
	["Chunk5"] = {
		ProperName = "Asterden", -- Fredd's city
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"Chunk4"},
		HasCatchCareDoor = true,
	},
	
}

return ChunkList


