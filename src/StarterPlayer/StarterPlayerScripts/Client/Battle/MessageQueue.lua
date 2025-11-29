--!strict
--[[
	MessageQueue.lua
	Manages battle message queue with proper state management
	Handles message display, callbacks, and drain detection
	Enhanced with typewriter effect and message history
]]

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local MessageQueue = {}
MessageQueue.__index = MessageQueue

export type MessageCallback = () -> ()
export type MessageQueueType = typeof(MessageQueue.new())

--[[
	Creates a new message queue instance
	@param battleNotification The UI frame for displaying messages
	@return MessageQueue
]]
function MessageQueue.new(battleNotification: Frame): any
	local self = setmetatable({}, MessageQueue)
	
	self._queue = {} :: {string}
	self._history = {} :: {string}
	self._drainCallbacks = {} :: {MessageCallback}
	self._isProcessing = false
	self._battleNotification = battleNotification
	self._messageLabel = battleNotification:FindFirstChild("Message")
	self._suppressPostFaint = false
	self._faintAnimationCallback = nil
	self._statusEffectCallback = nil
	self._thawCallback = nil
	
	return self
end

--[[
	Sets a callback to be triggered when a faint message is displayed
	@param callback The callback function
]]
function MessageQueue:SetFaintAnimationCallback(callback: (() -> ())?)
	self._faintAnimationCallback = callback
end

--[[
	Sets a callback to be triggered when a status message is displayed
	@param callback The callback function
]]
function MessageQueue:SetStatusEffectCallback(callback: (() -> ())?)
	self._statusEffectCallback = callback
end

--[[
	Sets a callback to be triggered when a thaw message is displayed
	@param callback The callback function
]]
function MessageQueue:SetThawCallback(callback: (() -> ())?)
	self._thawCallback = callback
end

--[[]
	Registers a callback invoked when a message is displayed (after label text is set).
	@param callback Function taking the message string
]]
function MessageQueue:SetOnDisplay(callback: ((message: string) -> ())?)
	self._onDisplay = callback
end

--[[
	Adds a message to the queue
	@param message The message to add
]]
function MessageQueue:Enqueue(message: string)
	if not message or message == "" then
		return
	end
	
	table.insert(self._queue, message)
	self:_processQueue()
end

--[[
	Adds multiple messages to the queue
	@param messages Array of messages
]]
function MessageQueue:EnqueueBatch(messages: {string})
	if not messages then
		return
	end
	
	for _, message in ipairs(messages) do
		if message and message ~= "" then
			table.insert(self._queue, message)
		end
	end
	
	self:_processQueue()
end

--[[
	Registers a callback to be called when the queue is empty
	@param callback The callback function
]]
function MessageQueue:OnDrained(callback: MessageCallback)
	if not callback then
		return
	end
	
	table.insert(self._drainCallbacks, callback)
	
	-- If queue is already empty, execute immediately
	if not self._isProcessing and #self._queue == 0 then
		task.spawn(function()
			self:_executeDrainCallbacks()
		end)
	else
		-- Otherwise, process the queue to trigger callbacks when done
		self:_processQueue()
	end
end

--[[
	Clears all messages from the queue
]]
function MessageQueue:Clear()
	self._queue = {}
end

--[[
	Gets the current queue length
	@return number Queue length
]]
function MessageQueue:GetLength(): number
	return #self._queue
end

--[[
	Checks if the queue is currently processing
	@return boolean True if processing
]]
function MessageQueue:IsProcessing(): boolean
	return self._isProcessing
end

--[[
	Sets the post-faint message suppression flag
	@param suppress Whether to suppress post-faint messages
]]
function MessageQueue:SetPostFaintSuppression(suppress: boolean)
	self._suppressPostFaint = suppress
end

--[[
	Gets the post-faint message suppression flag
	@return boolean True if suppressing
]]
function MessageQueue:IsPostFaintSuppressed(): boolean
	return self._suppressPostFaint
end

--[[
	Waits until the queue is fully drained
]]
function MessageQueue:WaitForDrain()
	while self._isProcessing or #self._queue > 0 do
		task.wait()
	end
end

--[[
	Gets the message history
	@return {string} Array of messages
]]
function MessageQueue:GetHistory(): {string}
	return self._history
end

--[[
	Sets whether the next message should stay on screen persistently
	@param persistent If true, message won't auto-drain
]]
function MessageQueue:SetPersistent(persistent: boolean)
	self._keepMessagePersistent = persistent
end

--[[
	Manually clears the current persistent message
]]
function MessageQueue:ClearPersistent()
	if self._keepMessagePersistent then
		self._keepMessagePersistent = false
		-- Slide out the current message
		if self._battleNotification then
			local slideOutTween = TweenService:Create(
				self._battleNotification,
				TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
				{Position = UDim2.new(0, 0, 1, 0)}
			)
			slideOutTween:Play()
			slideOutTween.Completed:Wait()
			self._battleNotification.Visible = false
		end
	end
end

--[[
	Internal: Displays a single message with typewriter effect
	@param message The message to display
]]
function MessageQueue:_displayMessage(message: string)
	if not self._battleNotification or not self._messageLabel then
		return
	end
	
	-- Add to history
	table.insert(self._history, message)
	
	-- Position notification at bottom
	self._battleNotification.Position = UDim2.new(0, 0, 1, 0)
	self._battleNotification.Visible = true
	self._messageLabel.Text = message
	self._messageLabel.MaxVisibleGraphemes = 0  -- Hide text immediately to prevent flash
	self._messageLabel.Size = UDim2.new(0.83, 0, 0.34, 0)

	-- Check if this is a thaw message (status removal)
	local messageLower = message:lower()
	local isThawMessage = string.find(messageLower, "thawed out")
	
	-- Check if this is a status message and trigger status effect callback immediately
	local isStatusMessage = string.find(messageLower, "burned") or 
	                       string.find(messageLower, "paralyzed") or 
	                       string.find(messageLower, "poisoned") or 
	                       string.find(messageLower, "asleep") or 
	                       string.find(messageLower, "frozen") or
	                       string.find(messageLower, "confused") or
	                       string.find(messageLower, "hurt by") or
	                       string.find(messageLower, "frozen solid")
	
	if isStatusMessage and self._statusEffectCallback then
		print("[MessageQueue] Status message detected - triggering status effect callback")
		task.spawn(self._statusEffectCallback)
		self._statusEffectCallback = nil  -- Clear the callback after use
	end
	
	-- Trigger thaw callback if this is a thaw message
	if isThawMessage and self._thawCallback then
		print("[MessageQueue] Thaw message detected - triggering thaw callback")
		task.spawn(self._thawCallback)
		self._thawCallback = nil  -- Clear the callback after use
	end

	-- Notify display hook
	if self._onDisplay then
		local ok, err = pcall(self._onDisplay, message)
		if not ok then
			warn("MessageQueue onDisplay error:", err)
		end
	end
	
	-- Slide in
	local slideInTween = TweenService:Create(
		self._battleNotification,
		TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{Position = UDim2.new(0, 0, 0.465, 0)} --2nd line {0, 0},{0.281, 0}
	)
	slideInTween:Play()
	
	-- Check if this is a faint message for faster timing
	local isFaintMessage = string.find(message:lower(), "fainted") or string.find(message:lower(), "faint")
	
	-- Start typewriter 0.25 seconds earlier (while slide-in is still happening)
	task.wait(0.1)  -- Start typewriter 0.25s before slide-in completes (0.35 - 0.25 = 0.1)
	
    -- Typewriter effect
    local length = #message
    local wrappedOnce = false
    local lastSpaceIndex = 0
    local wrapLimitChars = 40 -- manual cutoff for first line only
    local function maybeWrapAt(count)
        if wrappedOnce then return end
        if not self._messageLabel or not self._battleNotification then return end
        local chNow = string.sub(message, count, count)
        if string.match(chNow, "%s") then
            lastSpaceIndex = count
        end
        if count >= wrapLimitChars then
            local breakAt = (lastSpaceIndex > 0) and (lastSpaceIndex - 1) or wrapLimitChars
            if breakAt < 1 then breakAt = wrapLimitChars end
            local newMsg = string.sub(message, 1, breakAt) .. "\n" .. string.sub(message, breakAt + 1)
            message = newMsg
            self._messageLabel.Text = newMsg
            length = #newMsg
            wrappedOnce = true
            lastSpaceIndex = 0
            TweenService:Create(
                self._battleNotification,
                TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                {Position = UDim2.new(0, 0, 0.281, 0)}
            ):Play()
			-- Expand TextLabel height for two-line layout
			TweenService:Create(
					self._messageLabel,
					TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
					{Size = UDim2.new(0.833, 0, 0.556, 0)}
				):Play()
        end
    end
	if isFaintMessage then
		-- Faster timing for faint messages (keep typewriter speed the same)
		-- No additional delay needed since we already started early
		
        for count = 1, length do
            maybeWrapAt(count)
            self._messageLabel.MaxVisibleGraphemes = count
            task.wait(0.012)  -- Keep same typewriter speed
        end
		
		self._messageLabel.MaxVisibleGraphemes = -1
		task.wait(0.2)  -- Reduced from 0.55
	else
		-- Normal timing for other messages
		-- No additional delay needed since we already started early
		
        for count = 1, length do
            maybeWrapAt(count)
            self._messageLabel.MaxVisibleGraphemes = count
            task.wait(0.012)
        end
		
		self._messageLabel.MaxVisibleGraphemes = -1
		task.wait(0.55)
	end
	
	-- Check if this is a faint message and trigger animation callback when sliding out
    if isFaintMessage and self._faintAnimationCallback then
        print("[FAINT][MessageQueue] sliding out - trigger animation callback")
		-- Trigger the faint animation callback when faint message starts sliding out
		task.spawn(self._faintAnimationCallback)
		self._faintAnimationCallback = nil  -- Clear the callback after use
	end
	
	-- Check if we should keep the message persistent (for switch preview, etc.)
	if not self._keepMessagePersistent then
		-- Slide out
		local slideOutTween = TweenService:Create(
			self._battleNotification,
			TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
			{Position = UDim2.new(0, 0, 1, 0)}
		)
		slideOutTween:Play()
		slideOutTween.Completed:Wait()
		self._battleNotification.Visible = false
	else
		-- Keep message on screen - it will be manually cleared
		print("[MessageQueue] Keeping message persistent - not hiding")
		-- Don't set Visible to false - message stays on screen
	end
end

--[[
	Internal: Processes the message queue
]]
function MessageQueue:_processQueue()
	if self._isProcessing then
		return
	end
	
	self._isProcessing = true
	
	task.spawn(function()
		while #self._queue > 0 do
			local message = table.remove(self._queue, 1)
			if message then
				self:_displayMessage(message)
			end
		end
		
		self._isProcessing = false
		self._suppressPostFaint = false
		
		-- Execute drain callbacks
		self:_executeDrainCallbacks()
	end)
end

--[[
	Internal: Executes all drain callbacks
]]
function MessageQueue:_executeDrainCallbacks()
	local callbacks = self._drainCallbacks
	self._drainCallbacks = {}
	
	for _, callback in ipairs(callbacks) do
		local success, err = pcall(callback)
		if not success then
			warn("MessageQueue drain callback error:", err)
		end
	end
end

return MessageQueue
