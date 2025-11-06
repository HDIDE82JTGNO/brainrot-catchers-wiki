--!strict

local RelocationSignals = {}

local postBattleRelocated = Instance.new("BindableEvent")

export type RelocationContext = { Reason: string?, Chunk: string? }

function RelocationSignals.OnPostBattleRelocated(callback: (ctx: RelocationContext?) -> ()): RBXScriptConnection
	return postBattleRelocated.Event:Connect(callback)
end

function RelocationSignals.FirePostBattleRelocated(ctx: RelocationContext?)
	postBattleRelocated:Fire(ctx)
end

return RelocationSignals


