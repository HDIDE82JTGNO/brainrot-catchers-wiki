local ChunkService = {}

local ServerStorage = game:GetService("ServerStorage")

local GameData = require(script.Parent.GameData)
local ClientData = require(script.Parent.ClientData)
local DBG = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DBG"))

-- Resolve chunk metadata (supports top-level and SubChunks entries)
function ChunkService:GetChunkRecord(chunkName: string)
	local ChunkList = GameData.ChunkList
	local chunk = ChunkList[chunkName]
	if chunk then
		return chunk, nil
	end

	local parentName: string? = nil
	for name, record in pairs(ChunkList) do
		local sub = record and record.SubChunks
		if sub and sub[chunkName] then
			parentName = name
			chunk = sub[chunkName]
			break
		end
	end

	return chunk, parentName
end

-- Resolve the actual model container (Chunks vs Interiors) for a chunk
function ChunkService:GetSourceFolder(chunkName: string)
	local chunkData = self:GetChunkRecord(chunkName)
	if not chunkData then
		return nil
	end

	if chunkData.IsSubRoom then
		DBG:warn("Looking for interior chunk:", chunkName, "in ServerStorage.Interiors")
		return ServerStorage.Interiors:FindFirstChild(chunkName)
	else
		DBG:warn("Looking for main chunk:", chunkName, "in ServerStorage.Chunks")
		return ServerStorage.Chunks:FindFirstChild(chunkName)
	end
end

-- Determine if moving to ChunkName is authorized, applying all current rules.
function ChunkService:IsChunkTransitionAuthorized(player: Player, playerData, chunkName: string)
	local ChunkList = GameData.ChunkList

	local chunkData, parentChunk = self:GetChunkRecord(chunkName)
	if not chunkData then
		return false, "[ChunkService] Unknown chunk: " .. tostring(chunkName)
	end

	local validPrev = chunkData.ValidPrevious or {}

	local validFromChunk = table.find(validPrev, playerData.Chunk)
	local validFromSubChunk = table.find(validPrev, playerData.SubChunk)
	local validFromLast = table.find(validPrev, playerData.LastChunk)
	local anyAllowed = table.find(validPrev, "Any")
	local loadingSelf = (playerData.Chunk == chunkName or playerData.SubChunk == chunkName)
	
	-- Debug logging for Route 4 -> Asterden transitions
	if chunkName == "Chunk5" and playerData.Chunk == "Chunk6" then
		DBG:print("[ChunkService] Route 4 -> Asterden transition check:")
		DBG:print("  Current Chunk:", playerData.Chunk)
		DBG:print("  LastChunk:", playerData.LastChunk)
		DBG:print("  Target Chunk:", chunkName)
		DBG:print("  ValidPrevious:", table.concat(validPrev, ", "))
		DBG:print("  validFromChunk:", validFromChunk ~= nil)
		DBG:print("  validFromLast:", validFromLast ~= nil)
	end

	-- Special rule: returning from universal facility (like CatchCare) back to LastChunk
	local returningFromUniversal = false
	if playerData.Chunk and playerData.LastChunk and chunkName == playerData.LastChunk then
		local currentData = ChunkList[playerData.Chunk]
		if currentData and table.find(currentData.ValidPrevious, "Any") then
			returningFromUniversal = true
		end
	end

	-- Title / cold-start "Continue" logic
	local continuingFromTitle = false
	do
		local sessionChunk = playerData.Chunk
		local atTitle = (sessionChunk == nil or sessionChunk == "nil" or sessionChunk == "Title")
		if atTitle then
			local desired = tostring(playerData.LastChunk or "")
			local fallback: string? = nil
			if desired == "" or desired == "CatchCare" then
				local ld = playerData.LeaveData
				local ldChunk = (type(ld) == "table" and tostring(ld.Chunk or "")) or ""
				if ldChunk ~= "" and ldChunk ~= "CatchCare" and ChunkList[ldChunk] then
					fallback = ldChunk
				end
				if not fallback and ChunkList["Chunk1"] then
					fallback = "Chunk1"
				end
			end
			local target = desired ~= "" and desired or fallback
			if target and target ~= "" then
				if chunkName ~= target then
					chunkName = target
				end
				continuingFromTitle = true
			else
				if ChunkList[chunkName] and chunkName ~= "CatchCare" then
					continuingFromTitle = true
				end
			end
		end

		if not continuingFromTitle and sessionChunk == "CatchCare" then
			if chunkName ~= "CatchCare" and ChunkList[chunkName] then
				continuingFromTitle = true
			end
		end
	end

	-- Defeat / blackout scenarios that allow fallback to LastChunk (or specific pairs)
	local defeatScenario = false
	do
		local currentChunk = playerData.Chunk
		if currentChunk and currentChunk ~= "Title" and currentChunk ~= "nil" and currentChunk ~= chunkName then
			if playerData.LastChunk and (chunkName == playerData.LastChunk) then
				defeatScenario = true
			elseif currentChunk == "Chunk2" and chunkName == "Chunk1" then
				defeatScenario = true
			elseif currentChunk == "Chunk3" and chunkName == "Chunk2" then
				defeatScenario = true
			elseif currentChunk == "Chunk6" and chunkName == "Chunk5" then
				-- Route 4 -> Asterden (returning from Route 4)
				defeatScenario = true
			end
		end
	end

	local authorized =
		validFromChunk
		or validFromSubChunk
		or validFromLast
		or anyAllowed
		or loadingSelf
		or returningFromUniversal
		or continuingFromTitle
		or defeatScenario

	-- table.find returns indices (numbers), so treat any non-nil value as authorized.
	return authorized ~= nil, nil
end

-- Update LastChunk when requested (simple helper used by remote handler)
function ChunkService:UpdateLastChunk(player: Player, chunkName: string)
	local playerData = ClientData:Get(player)
	if not playerData then return false end
	playerData.LastChunk = chunkName
	ClientData:UpdateClientData(player, playerData)
	DBG:print("Updated LastChunk for player:", player.Name, "to:", chunkName)
	return true
end

-- Compute and set blackout return LastChunk based on CatchCare doors & ValidPrevious graph
function ChunkService:SetBlackoutReturnChunk(player: Player)
	local playerData = ClientData:Get(player)
	if not playerData then return false end

	local ChunkList = GameData.ChunkList
	local function isValidChunk(name: string?): boolean
		return type(name) == "string" and name ~= "" and name ~= "CatchCare" and ChunkList[name] ~= nil
	end
	local function hasCatchCareDoor(chunkName: string?): boolean
		local c = chunkName and ChunkList[chunkName]
		return c ~= nil and c.HasCatchCareDoor == true
	end
	local function firstPrev(chunkName: string?): string?
		if not chunkName then return nil end
		local c = ChunkList[chunkName]
		if not c or type(c.ValidPrevious) ~= "table" then return nil end
		for _, prev in ipairs(c.ValidPrevious) do
			if type(prev) == "string" and prev ~= "Any" and prev ~= "nil" and ChunkList[prev] then
				return prev
			end
		end
		return nil
	end

	local leaveChunk = (type(playerData.LeaveData) == "table") and tostring(playerData.LeaveData.Chunk or "") or ""
	local candidates: {string} = {}
	if isValidChunk(leaveChunk) then table.insert(candidates, leaveChunk) end
	if isValidChunk(playerData.Chunk) then table.insert(candidates, tostring(playerData.Chunk)) end
	if isValidChunk(playerData.LastChunk) then table.insert(candidates, tostring(playerData.LastChunk)) end
	if #candidates == 0 then
		table.insert(candidates, tostring(playerData.LastChunk or ""))
	end

	local target: string? = nil
	for _, start in ipairs(candidates) do
		local cur = start
		local visited: {[string]: boolean} = {}
		while cur and not visited[cur] do
			visited[cur] = true
			if hasCatchCareDoor(cur) then
				target = cur
				break
			end
			cur = firstPrev(cur)
		end
		if target then break end
	end

	if not target then
		for _, cand in ipairs(candidates) do
			if isValidChunk(cand) then
				target = cand
				break
			end
		end
	end

	if not target then
		target = "Chunk1"
	end

	playerData.LastChunk = target
	ClientData:UpdateClientData(player, playerData)
	DBG:print("[Blackout] Set LastChunk for", player.Name, "to", target)
	return target
end

-- Clear LeaveData position/rotation after using it
function ChunkService:ClearLeaveDataCFrame(player: Player)
	local playerData = ClientData:Get(player)
	if playerData and playerData.LeaveData then
		playerData.LeaveData.Position = nil
		playerData.LeaveData.Rotation = nil
		ClientData:UpdateClientData(player, playerData)
		DBG:print("Cleared LeaveData for player:", player.Name)
		return true
	end
	DBG:warn("No LeaveData found for player:", player.Name)
	return false
end

return ChunkService


