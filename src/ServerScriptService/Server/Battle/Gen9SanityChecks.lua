--!strict
--[[
	Gen9SanityChecks.lua
	Lightweight assertions to catch regressions in Pokémon-faithful mechanics.

	Intended to be gated behind Config.BATTLE_SANITY_CHECKS.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TypeChart = require(ReplicatedStorage.Shared.TypeChart)
local Status = require(ReplicatedStorage.Shared.Status)
local Moves = require(ReplicatedStorage.Shared.Moves)
local Types = require(ReplicatedStorage.Shared.Types)

local Gen9SanityChecks = {}

local function assertEq(label: string, a: any, b: any)
	if a ~= b then
		error(("[Gen9SanityChecks] %s failed: expected %s, got %s"):format(label, tostring(b), tostring(a)))
	end
end

function Gen9SanityChecks.Run()
	-- Type chart spot checks (Gen 9)
	assertEq("Fire->Grass", TypeChart.GetMultiplier("Fire", { "Grass" }), 2)
	assertEq("Fire->Water", TypeChart.GetMultiplier("Fire", { "Water" }), 0.5)
	assertEq("Electric->Ground", TypeChart.GetMultiplier("Electric", { "Ground" }), 0)
	assertEq("Rock->Fire", TypeChart.GetMultiplier("Rock", { "Fire" }), 2)
	assertEq("Fairy->Dragon", TypeChart.GetMultiplier("Fairy", { "Dragon" }), 2)

	-- Dual-type multiplication
	assertEq("Rock->FireFlying", TypeChart.GetMultiplier("Rock", { "Fire", "Flying" }), 4)

	-- Move type resolution for table-based `Type` values
	local tackle = Moves["Tackle"]
	assertEq("Resolve Tackle.Type", TypeChart.ResolveTypeName(tackle.Type), "Normal")
	assertEq("Resolve Types.Normal", TypeChart.ResolveTypeName(Types.Normal), "Normal")

	-- Major status rules
	local poisonMon = { Type = { "Poison" } }
	assertEq("Poison immune to PSN", Status.CanBeInflicted(poisonMon, "PSN"), false)
	assertEq("Poison immune to TOX", Status.CanBeInflicted(poisonMon, "TOX"), false)

	local alreadyBurned = { Type = { "Normal" }, Status = { Type = "BRN" } }
	assertEq("No status refresh", Status.CanBeInflicted(alreadyBurned, "BRN"), false)

	-- Fire type can be frozen, but cannot be burned (Gen 9)
	local fireMon = { Type = { "Fire" } }
	assertEq("Fire immune to BRN", Status.CanBeInflicted(fireMon, "BRN"), false)
	assertEq("Fire NOT immune to FRZ", Status.CanBeInflicted(fireMon, "FRZ"), true)
end

return Gen9SanityChecks


