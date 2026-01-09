--!strict
--[[
	ChunkStreamer.lua
	Handles optimized chunk transmission from server to client using batched streaming.
	Prevents freezing/crashes by streaming chunks in smaller batches across multiple frames.
	
	The streaming process works by:
	1. Temporarily removing all children from the cloned chunk
	2. Parenting the root chunk to PlayerGui (lightweight operation)
	3. Re-parenting children in batches across multiple Heartbeat frames
	4. Setting a StreamingComplete attribute when done
	
	This approach spreads the replication load across multiple frames, preventing
	client-side freezing when loading large chunks.
]]

local RunService = game:GetService("RunService")

export type ChunkStreamer = {
	StreamChunk: (self: ChunkStreamer, chunk: Instance, targetParent: Instance, player: Player) -> boolean,
	CancelStream: (self: ChunkStreamer, player: Player) -> (),
	Cleanup: (self: ChunkStreamer, player: Player) -> (),
}

local ChunkStreamer = {}
ChunkStreamer.__index = ChunkStreamer

-- Configuration constants
local BATCH_SIZE = 50 -- Number of direct children to parent per batch

-- Track active streams per player
local activeStreams: {[Player]: RBXScriptConnection?} = {}

--[[
	Creates a new ChunkStreamer instance
	@return ChunkStreamer
]]
function ChunkStreamer.new(): ChunkStreamer
	local self = setmetatable({}, ChunkStreamer)
	return self
end

--[[
	Streams a chunk to the target parent in batches
	Optimized approach: temporarily removes children, parents root, then re-parents children incrementally
	@param chunk The chunk instance to stream
	@param targetParent The parent to stream to (typically PlayerGui)
	@param player The player receiving the chunk
	@return boolean Success status
]]
function ChunkStreamer:StreamChunk(chunk: Instance, targetParent: Instance, player: Player): boolean
	-- Cancel any existing stream for this player
	self:CancelStream(player)
	
	-- Validate inputs
	if not chunk or not targetParent or not player then
		warn("[ChunkStreamer] Invalid parameters for StreamChunk")
		return false
	end
	
	-- Check if player is still in game
	if not player.Parent then
		warn("[ChunkStreamer] Player no longer in game")
		return false
	end
	
	-- Get all direct children before parenting
	local childrenToStream: {Instance} = {}
	for _, child in ipairs(chunk:GetChildren()) do
		table.insert(childrenToStream, child)
	end
	
	-- For small chunks, parent everything immediately
	if #childrenToStream < BATCH_SIZE then
		chunk.Parent = targetParent
		-- Mark as complete immediately for small chunks
		pcall(function()
			chunk:SetAttribute("StreamingComplete", true)
		end)
		return true
	end
	
	-- For large chunks, use streaming approach:
	-- 1. Temporarily remove children
	local tempStorage: {Instance} = {}
	for _, child in ipairs(childrenToStream) do
		child.Parent = nil
		table.insert(tempStorage, child)
	end
	
	-- 2. Parent the root chunk (lightweight, no descendants yet)
	chunk.Parent = targetParent
	
	-- 3. Create batches for re-parenting children
	local batches: {{Instance}} = {}
	local currentBatch: {Instance} = {}
	
	for _, child in ipairs(tempStorage) do
		table.insert(currentBatch, child)
		
		if #currentBatch >= BATCH_SIZE then
			table.insert(batches, currentBatch)
			currentBatch = {}
		end
	end
	
	-- Add remaining items as final batch
	if #currentBatch > 0 then
		table.insert(batches, currentBatch)
	end
	
	-- 4. Stream batches across multiple frames
	local batchIndex = 1
	local connection: RBXScriptConnection?
	
	connection = RunService.Heartbeat:Connect(function()
		-- Check if player/chunk is still valid
		if not player.Parent or not chunk.Parent then
			if connection then
				connection:Disconnect()
				activeStreams[player] = nil
			end
			return
		end
		
		-- Process current batch
		if batchIndex <= #batches then
			local batch = batches[batchIndex]
			for _, child in ipairs(batch) do
				-- Re-parent child to chunk (triggers replication for this subtree)
				if child.Parent == nil then
					child.Parent = chunk
				end
			end
			
			batchIndex = batchIndex + 1
			
			-- If all batches processed, mark as complete and disconnect
			if batchIndex > #batches then
				-- Set attribute to signal streaming completion
				pcall(function()
					chunk:SetAttribute("StreamingComplete", true)
				end)
				
				if connection then
					connection:Disconnect()
					activeStreams[player] = nil
				end
			end
		else
			-- All batches processed
			pcall(function()
				chunk:SetAttribute("StreamingComplete", true)
			end)
			
			if connection then
				connection:Disconnect()
				activeStreams[player] = nil
			end
		end
	end)
	
	-- Store connection for potential cancellation
	activeStreams[player] = connection
	
	return true
end

--[[
	Cancels an active stream for a player
	@param player The player whose stream should be cancelled
]]
function ChunkStreamer:CancelStream(player: Player): ()
	if activeStreams[player] then
		activeStreams[player]:Disconnect()
		activeStreams[player] = nil
	end
end

--[[
	Cleans up all streams (called when player leaves)
	@param player The player who left
]]
function ChunkStreamer:Cleanup(player: Player): ()
	self:CancelStream(player)
end

-- Create singleton instance
local streamer = ChunkStreamer.new()

-- Auto-cleanup on player removal
do
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player: Player)
		streamer:Cleanup(player)
	end)
end

return streamer

