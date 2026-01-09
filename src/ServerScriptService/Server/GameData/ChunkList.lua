
local ChunkList = {
	["Title"] = {
		ProperName = "Title",
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"nil","Any"},
		Description = "The beginning of your journey. Here, trainers prepare to embark on their adventure across the region.",
	},

	["Trade"] = {
		ProperName = "Trade Hub",
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"Any"},
		Description = "A bustling trading center where trainers from across the region gather to exchange their companions and share stories of their adventures.",
	},

	["Battle"] = {
		ProperName = "Battle Hub",
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"Any"},
		Description = "The ultimate proving ground for trainers. Champions and challengers test their skills in epic battles that echo throughout the region.",
	},
	
	--Chunk 1 and Sub rooms
	["Chunk1"] = {
		ProperName = "Cloveroot Town",
		IsSubRoom = false,
		Encounters = {
			{"Frulli Frulla",3,5,20}, -- Min level,Max Level, Chance
			{"Timmy Cheddar",3,5,20}, -- Min level,Max Level, Chance - Pre-evolution
		},
		Description = "A peaceful starting town nestled among rolling green hills. The grand community center with its distinctive striped facade stands as a beacon for new trainers, while the ancient lighthouse tower watches over the town from the distance.",
		SubChunks = {
			["Professor's Lab"] = {
				ProperName = "Professor's Lab",
				IsSubRoom = true,
				ScriptedCam = false,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
				Description = "A state-of-the-art research facility filled with scientific equipment and books. Here, the Professor studies the region's creatures and guides new trainers on their journey.",
			},
			
			["PlayersHouse"] = {
				ProperName = "Your House",
				IsSubRoom = true,
				ScriptedCam = false,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
				Description = "Your cozy home where your adventure began. A place of comfort and rest before heading out into the wider world.",
			},

			["Chunk1House1"] = {
				ProperName = "",
				IsSubRoom = true,
				ScriptedCam = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
				Description = "A friendly neighbor's home where local residents share tips and stories with passing trainers.",
			},

			["Chunk1House2"] = {
				ProperName = "",
				IsSubRoom = true,
				ScriptedCam = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk1"},
				Description = "A welcoming house where townsfolk offer advice and encouragement to trainers starting their journey.",
			},
		},
		ValidPrevious = {"nil","Title","Professor's Lab","PlayersHouse","House1"}
	},
	
	-- Sub-chunks (interior areas)
	["Professor's Lab"] = {
		ProperName = "Professor's Lab",
		IsSubRoom = true,
		ScriptedCam = false,
		Encounters = {},
		ValidPrevious = {"Chunk1"},
		Description = "A state-of-the-art research facility filled with scientific equipment and books. Here, the Professor studies the region's creatures and guides new trainers on their journey.",
	},
	
	["PlayersHouse"] = {
		ProperName = "Your House",
		IsSubRoom = true,
		ScriptedCam = false,
		Encounters = {},
		ValidPrevious = {"Chunk1"},
		Description = "Your cozy home where your adventure began. A place of comfort and rest before heading out into the wider world.",
	},
	
	["House1"] = {
		ProperName = "House 1",
		IsSubRoom = true,
		ScriptedCam = true,
		Encounters = {},
		ValidPrevious = {"Chunk1"},
		Description = "A friendly neighbor's home where local residents share tips and stories with passing trainers.",
	},

	["CatchCare"] = {
		ProperName = "CatchCare",
		IsSubRoom = true,
		ScriptedCam = false,
		Encounters = {},
		ValidPrevious = {"Any"},
		Description = "A healing center where trainers can rest their companions and receive expert care. The friendly staff ensures every creature leaves refreshed and ready for battle.",
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
		ValidPrevious = {"Chunk1","Chunk3"},
		Description = "A dense forest route where ancient trees tower overhead and dappled sunlight filters through the canopy. An old stone monument stands at the heart of the woods, marking this as a place of significance for trainers and wild creatures alike.",
	},
	--Chunk 3 and sub rooms
	["Chunk3"] = {
		ProperName = "Cresamore Town",
		IsSubRoom = false,
		Encounters = {},
		SubChunks = {
			["Chunk3House1"] = {
				ProperName = "",
				IsSubRoom = true,
				ScriptedCam = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk3"},
				Description = "A quaint residential home where friendly locals welcome trainers and share tales of the region.",
			},
			["Chunk3House2"] = {
				ProperName = "",
				IsSubRoom = true,
				ScriptedCam = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk3"},
				Description = "A cozy cottage where residents offer helpful advice and warm hospitality to travelers.",
			},
			["Chunk3House3"] = {
				ProperName = "",
				IsSubRoom = true,
				ScriptedCam = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk3"},
				Description = "A charming home where townsfolk gather to discuss local news and trainer strategies.",
			},
			["Chunk3House4"] = {
				ProperName = "",
				IsSubRoom = true,
				ScriptedCam = true,
				Encounters = {

				},
				ValidPrevious = {"Chunk3"},
				Description = "A welcoming house where neighbors share tips and stories with visiting trainers.",
			},
		},
		ValidPrevious = {"Chunk2","Chunk4"},
		HasCatchCareDoor = true,
		Description = "A peaceful suburban town with well-kept homes and manicured lawns. The local CatchCare center provides essential services, while streetlamps cast a warm glow over the quiet streets where trainers rest between routes.",
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
		ValidPrevious = {"Chunk3", "Chunk5"}, -- Can come from Cresamore Town or Asterden
		Description = "A short but vibrant route connecting two major towns. Lush grass covers raised platforms where trainers often pause to battle, making this a popular spot for those seeking to test their skills.",
	},

	--Chunk 5 and sub rooms
	["Chunk5"] = {
		ProperName = "Asterden", -- Fredd's city (grass gym)
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"Chunk4", "Chunk6"}, -- Can come from Route 3 or Route 4
		HasCatchCareDoor = true,
		SubChunks = {
			["Gym1"] = {
				ProperName = "Asterden Gym",
				IsSubRoom = true,
				ScriptedCam = false,
				Encounters = {},
				ValidPrevious = {"Chunk5"},
				Description = "The Grass-type Gym of Asterden, where nature and training come together. Trainers face challenging battles among lush greenery and natural obstacles.",
			},
		},
		Description = "A bustling modern city where sleek architecture meets urban energy. Colorful storefronts line the busy streets, and cars zip past buildings adorned with decorative domes and green rooftops. The city's gym leader awaits challengers in a gym that celebrates the power of nature.",
	},
	
	["Gym1"] = {
		ProperName = "Asterden Gym",
		IsSubRoom = true,
		ScriptedCam = false,
		Encounters = {},
		ValidPrevious = {"Chunk5"},
		Description = "The Grass-type Gym of Asterden, where nature and training come together. Trainers face challenging battles among lush greenery and natural obstacles.",
	},

	["Chunk6"] = {
		ProperName = "Route 4", -- desert chunk leading to the wild west town (ground gym)
		IsSubRoom = false,
		Encounters = {
			{"Duckaroo",16,18,20},
			{"Bombombini Gusini",15,17,20},
			{"Il Cacto Hipopotamo",15,16,30},
		},
		ValidPrevious = {"Chunk5", "Chunk7"}, -- Can come from Asterden or Dustnook Town
		Description = "A harsh desert route where sparse orange trees dot the sandy landscape. Towering rock formations rise in the distance, and a natural waterfall cascades down the cliffs, providing a rare source of water in this arid wilderness.",
	},

	["Chunk7"] = {
		ProperName = "Dustnook City", -- ground gym
		IsSubRoom = false,
		Encounters = {},
		ValidPrevious = {"Chunk6", "Chunk8"},
		Description = "A dusty desert town where wooden buildings bake under the sun. Trainers stop at the Duckshot Diner to rest, trade rumors, and prepare for the harsh routes outside town.",
	},

	["Chunk8"] = {
		ProperName = "Route 5", 
		IsSubRoom = false,
		Encounters = {
			{"Duckaroo",16,18,20},
			{"Bombombini Gusini",15,17,20},
			{"Il Cacto Hipopotamo",15,16,30},
		},
		ValidPrevious = {"Chunk7"},
		Description = "A continuation of the desert route beyond Dustnook City. The unforgiving landscape tests trainers' resolve as they navigate through canyons and mesas, with only hardy desert-dwelling creatures for company.",
	},
	
}

return ChunkList


