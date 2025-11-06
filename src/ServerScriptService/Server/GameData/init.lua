local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local LuaTypes = require(Shared:WaitForChild("LuaTypes"))
local Types = require(Shared:WaitForChild("Types"))

-- Type declarations
type Creature_Type = LuaTypes.Creature
type Moves_Type = LuaTypes.Move
type Item_Type = LuaTypes.Item

local ChunkList = require(script:WaitForChild("ChunkList"))
print("=== GAMEDATA DEBUG ===")
print("ChunkList loaded, Chunk1 encounters:", ChunkList.Chunk1 and #ChunkList.Chunk1.Encounters or "nil")
if ChunkList.Chunk1 and ChunkList.Chunk1.Encounters then
	for i, encounter in ipairs(ChunkList.Chunk1.Encounters) do
		print("Encounter", i, ":", encounter[1])
	end
end
print("=== END GAMEDATA DEBUG ===")

local GameData = {
	Creatures = require(Shared:WaitForChild("Creatures")),
	Moves = require(Shared:WaitForChild("Moves")),
	Items = require(Shared:WaitForChild("Items")),
	LuaTypes = require(Shared:WaitForChild("LuaTypes")),
	Types = require(Shared:WaitForChild("Types")),
	Config = require(script:WaitForChild("Config")),
	ChunkList = ChunkList,
}

return GameData
