--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = {}

local OWNER = "stage5_diagnostics"
local MAX_EVENTS = 64
local REMOTE_NAMES = {
	CheatWarningEvent = true,
	RaceAbort = true,
	RaceSetEnabled = true,
	RaceStageCount = true,
	RaceVoided = true,
	ToggleCheatAlert = true,
}

local function errorResult(code: string, message: string): { code: string, message: string }
	return { code = code, message = message }
end

local function getRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getHumanoid(): Humanoid?
	local player = Players.LocalPlayer
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function safeRead(callback: () -> any): any
	local ok, value = pcall(callback)
	if ok then
		return value
	end
	return nil
end

local function finiteNumber(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

local function safeSignalScalar(value: any): any
	if type(value) == "boolean" then
		return value
	end
	local numberValue = finiteNumber(value)
	if numberValue ~= nil then
		return numberValue
	end
	if type(value) == "string" then
		if #value <= 64 and string.match(value, "^[A-Za-z_][A-Za-z0-9_%-]*$") then
			return value
		end
		return "<text>"
	end
	if typeof(value) == "Instance" then
		return "<" .. value.ClassName .. ">"
	end
	return nil
end

local function scalarSummary(value: any): string?
	if type(value) ~= "table" then
		local scalar = safeSignalScalar(value)
		return scalar ~= nil and tostring(scalar) or nil
	end
	local rows = {}
	for key, item in pairs(value) do
		if type(key) == "string" then
			local scalar = safeSignalScalar(item)
			if scalar ~= nil then
				table.insert(rows, key .. "=" .. tostring(scalar))
			end
		end
	end
	table.sort(rows)
	if #rows == 0 then
		return nil
	end
	local text = table.concat(rows, ",")
	return string.sub(text, 1, 220)
end

local function relevantFlags(instance: Instance?): string?
	if instance == nil then
		return nil
	end
	local attributes = safeRead(function()
		return instance:GetAttributes()
	end)
	if type(attributes) ~= "table" then
		return nil
	end
	local rows = {}
	for key, value in pairs(attributes) do
		local lowered = string.lower(tostring(key))
		if
			string.find(lowered, "race", 1, true)
			or string.find(lowered, "stage", 1, true)
			or string.find(lowered, "checkpoint", 1, true)
			or string.find(lowered, "cheat", 1, true)
			or string.find(lowered, "void", 1, true)
		then
			local scalar = safeSignalScalar(value)
			if scalar ~= nil then
				table.insert(rows, tostring(key) .. "=" .. tostring(scalar))
			end
		end
	end
	table.sort(rows)
	if #rows == 0 then
		return nil
	end
	return string.sub(table.concat(rows, ","), 1, 220)
end

local function tagSummary(instance: Instance?): string?
	if instance == nil then
		return nil
	end
	local tags = safeRead(function()
		return CollectionService:GetTags(instance)
	end)
	if type(tags) ~= "table" then
		return nil
	end
	local relevant = {}
	for _, tag in ipairs(tags) do
		if type(tag) == "string" then
			local lowered = string.lower(tag)
			if
				string.find(lowered, "race", 1, true)
				or string.find(lowered, "stage", 1, true)
				or string.find(lowered, "checkpoint", 1, true)
				or string.find(lowered, "cheat", 1, true)
			then
				table.insert(relevant, tag)
			end
		end
	end
	table.sort(relevant)
	return #relevant > 0 and string.sub(table.concat(relevant, ","), 1, 220) or nil
end
local function gcValidationSnapshot(): any
	local result = {}
	if type(getgc) ~= "function" then
		return result
	end
	local ok, objects = pcall(getgc, true)
	if not ok or type(objects) ~= "table" then
		return result
	end
	local bestHistory = nil
	local bestHistoryCount = 0
	for _, object in ipairs(objects) do
		if type(object) == "table" then
			local history = rawget(object, "CheatHistory")
			if type(history) ~= "table" then
				history = rawget(object, "CheatHistory2")
			end
			if type(history) == "table" then
				local historyCount = rawlen(history)
				if historyCount > bestHistoryCount then
					bestHistory = history
					bestHistoryCount = historyCount
				end
			end
			local raceData = rawget(object, "RaceData")
			if type(raceData) == "table" then
				local checkpoint = finiteNumber(rawget(raceData, "Checkpoint"))
				local count = finiteNumber(rawget(raceData, "RaceDataCount"))
				local version = finiteNumber(rawget(raceData, "DataVersion"))
				if checkpoint ~= nil or count ~= nil or version ~= nil then
					result.raceDataCheckpoint = checkpoint
					result.raceDataCount = count
					result.raceDataVersion = version
				end
			end
		end
	end
	result.cheatHistoryCount = bestHistoryCount
	if bestHistory ~= nil and bestHistoryCount > 0 then
		local last = rawget(bestHistory, bestHistoryCount)
		if type(last) == "table" then
			local reason = safeSignalScalar(rawget(last, "Reason"))
			local block = safeSignalScalar(rawget(last, "Block"))
			result.cheatReason = reason ~= nil and tostring(reason) or nil
			result.cheatBlock = block ~= nil and tostring(block) or nil
			result.cheatRequired = finiteNumber(rawget(last, "Required"))
			result.cheatTime = finiteNumber(rawget(last, "Time"))
			result.cheatLevel = finiteNumber(rawget(last, "Level"))
		end
	end
	return result
end

local function resolveRaceService(): any
	local services = ReplicatedStorage:FindFirstChild("Services")
	local module = services and services:FindFirstChild("RaceService")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, service = pcall(require, module)
	return ok and type(service) == "table" and service or nil
end

local function resolveRaceController(): any
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	local race = scripts and scripts:FindFirstChild("Race")
	local module = race and race:FindFirstChild("RaceController")
	if module == nil then
		module = scripts and scripts:FindFirstChild("RaceController", true)
	end
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, controller = pcall(require, module)
	return ok and type(controller) == "table" and controller or nil
end

local function appendEvent(handle: any, source: string, packed: any)
	if #handle.events >= MAX_EVENTS then
		handle.eventsDropped += 1
		return
	end
	local root = getRoot()
	local position = root and safeRead(function()
		return root.Position
	end)
	local event = {
		source = source,
		elapsed = math.max(os.clock() - handle.startedAt, 0),
	}
	if typeof(position) == "Vector3" then
		event.x = position.X
		event.y = position.Y
		event.z = position.Z
	end
	local outputIndex = 1
	for index = 1, math.min(packed.n or 0, 8) do
		local scalar = safeSignalScalar(packed[index])
		if scalar ~= nil and outputIndex <= 3 then
			event["arg" .. tostring(outputIndex)] = tostring(scalar)
			outputIndex += 1
		end
	end
	table.insert(handle.events, event)
end

local function connectSignal(handle: any, signal: any, source: string)
	if type(signal) ~= "table" or type(signal.Connect) ~= "function" then
		return
	end
	local ok, connection = pcall(function()
		return signal:Connect(function(...)
			local packed = table.pack(...)
			appendEvent(handle, source, packed)
		end)
	end)
	if ok and connection ~= nil then
		table.insert(handle.connections, connection)
	end
end

local function connectRemotes(handle: any)
	for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
		if REMOTE_NAMES[instance.Name] and instance:IsA("RemoteEvent") then
			local ok, connection = pcall(function()
				return instance.OnClientEvent:Connect(function(...)
					local packed = table.pack(...)
					appendEvent(handle, instance.Name, packed)
				end)
			end)
			if ok and connection ~= nil then
				table.insert(handle.connections, connection)
			end
		end
	end
end

local function emit(handle: any, kind: string, fields: any): boolean
	fields.sessionId = handle.sessionId
	local ok, accepted = pcall(handle.emit, kind, fields)
	return ok and accepted == true
end

local function flushEvents(handle: any): boolean
	local events = handle.events
	handle.events = {}
	for _, event in ipairs(events) do
		if not emit(handle, "stage5_server_signal", event) then
			return false
		end
	end
	return true
end

function Diagnostics.newSession(sessionId: any, startedAt: any, emitCallback: any): (any?, any)
	if type(sessionId) ~= "string" or type(startedAt) ~= "number" or type(emitCallback) ~= "function" then
		return nil, errorResult("stage5_diagnostics_invalid", "Stage 5 diagnostic dependencies are invalid")
	end
	return {
		owner = OWNER,
		sessionId = sessionId,
		startedAt = startedAt,
		emit = emitCallback,
		raceService = nil,
		raceController = nil,
		connections = {},
		events = {},
		eventsDropped = 0,
		started = false,
		stopped = false,
	},
		nil
end

function Diagnostics.start(handle: any): (boolean?, any)
	if type(handle) ~= "table" or handle.owner ~= OWNER or handle.started or handle.stopped then
		return nil, errorResult("stage5_diagnostics_invalid", "Stage 5 diagnostic handle is invalid")
	end
	handle.started = true
	handle.raceService = resolveRaceService()
	if handle.stopped then
		return nil, errorResult("stage5_diagnostics_cancelled", "Stage 5 diagnostics were stopped during startup")
	end
	handle.raceController = resolveRaceController()
	if handle.stopped then
		return nil, errorResult("stage5_diagnostics_cancelled", "Stage 5 diagnostics were stopped during startup")
	end
	if handle.raceService ~= nil then
		connectSignal(handle, handle.raceService.PlayerEnteredStage, "PlayerEnteredStage")
		connectSignal(handle, handle.raceService.PlayerLeftStage, "PlayerLeftStage")
	end
	if handle.stopped then
		return nil, errorResult("stage5_diagnostics_cancelled", "Stage 5 diagnostics were stopped during startup")
	end
	connectRemotes(handle)
	if handle.stopped then
		return nil, errorResult("stage5_diagnostics_cancelled", "Stage 5 diagnostics were stopped during startup")
	end
	return true, nil
end

function Diagnostics.sample(handle: any, label: any, pointIndex: any): (boolean?, any)
	if type(handle) ~= "table" or handle.owner ~= OWNER or handle.stopped then
		return nil, errorResult("stage5_diagnostics_invalid", "Stage 5 diagnostic handle is inactive")
	end
	if not flushEvents(handle) then
		return nil, errorResult("trace_write_failed", "Stage 5 server signals could not be recorded")
	end
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = getRoot()
	local humanoid = getHumanoid()
	local characterDebugId = character and safeRead(function()
		return character:GetDebugId()
	end)
	local rootDebugId = root and safeRead(function()
		return root:GetDebugId()
	end)
	local position = root and safeRead(function()
		return root.Position
	end)
	local velocity = root and safeRead(function()
		return root.AssemblyLinearVelocity
	end)
	local receiveAge = root and finiteNumber(safeRead(function()
		return root.ReceiveAge
	end))
	local networkOwner = root and safeRead(function()
		return isnetworkowner(root)
	end)
	local humanoidState = humanoid and safeRead(function()
		return tostring(humanoid:GetState())
	end)
	local floorMaterial = humanoid and safeRead(function()
		return tostring(humanoid.FloorMaterial)
	end)
	local stageCount = nil
	local playerStage = nil
	local raceState = nil
	if handle.raceService ~= nil then
		stageCount = finiteNumber(safeRead(function()
			return handle.raceService.GetStageCount()
		end))
		playerStage = finiteNumber(safeRead(function()
			return handle.raceService.GetPlayerStage(player)
		end))
		raceState = scalarSummary(safeRead(function()
			return handle.raceService.GetPlayerState()
		end))
	end
	local liveState = handle.raceController and safeRead(function()
		return handle.raceController:GetLiveState()
	end)
	local labelText = type(label) == "string" and label or "unknown"
	local validation = {}
	if string.sub(labelText, 1, 8) == "failure_" then
		validation = gcValidationSnapshot()
	end
	local fields = {
		label = labelText,
		pointIndex = finiteNumber(pointIndex),
		elapsed = math.max(os.clock() - handle.startedAt, 0),
		serverTime = finiteNumber(workspace.DistributedGameTime),
		receiveAge = receiveAge,
		networkOwner = type(networkOwner) == "boolean" and networkOwner or nil,
		humanoidState = type(humanoidState) == "string" and humanoidState or nil,
		floorMaterial = type(floorMaterial) == "string" and floorMaterial or nil,
		health = humanoid and finiteNumber(safeRead(function()
			return humanoid.Health
		end)) or nil,
		autoRotate = humanoid and safeRead(function()
			return humanoid.AutoRotate
		end) or nil,
		platformStand = humanoid and safeRead(function()
			return humanoid.PlatformStand
		end) or nil,
		raceStageCount = stageCount,
		racePlayerStage = playerStage,
		raceState = raceState,
		raceLiveState = scalarSummary(liveState),
		playerFlags = relevantFlags(player),
		characterFlags = relevantFlags(character),
		characterTags = tagSummary(character),
		characterDebugId = type(characterDebugId) == "string" and characterDebugId or nil,
		rootDebugId = type(rootDebugId) == "string" and rootDebugId or nil,
		eventsDropped = handle.eventsDropped,
		cheatHistoryCount = validation.cheatHistoryCount,
		cheatReason = validation.cheatReason,
		cheatBlock = validation.cheatBlock,
		cheatRequired = validation.cheatRequired,
		cheatTime = validation.cheatTime,
		cheatLevel = validation.cheatLevel,
		raceDataCheckpoint = validation.raceDataCheckpoint,
		raceDataCount = validation.raceDataCount,
		raceDataVersion = validation.raceDataVersion,
	}
	if typeof(position) == "Vector3" then
		fields.x = position.X
		fields.y = position.Y
		fields.z = position.Z
	end
	if typeof(velocity) == "Vector3" then
		fields.velocityX = velocity.X
		fields.velocityY = velocity.Y
		fields.velocityZ = velocity.Z
		fields.assemblySpeed = velocity.Magnitude
	end
	if not emit(handle, "stage5_diagnostic_snapshot", fields) then
		return nil, errorResult("trace_write_failed", "Stage 5 diagnostic snapshot could not be recorded")
	end
	return true, nil
end

function Diagnostics.motion(handle: any, fields: any): (boolean?, any)
	if type(handle) ~= "table" or handle.owner ~= OWNER or handle.stopped or type(fields) ~= "table" then
		return nil, errorResult("stage5_diagnostics_invalid", "Stage 5 motion diagnostics are inactive")
	end
	if not emit(handle, "stage5_motion_summary", fields) then
		return nil, errorResult("trace_write_failed", "Stage 5 motion summary could not be recorded")
	end
	return true, nil
end

function Diagnostics.stop(handle: any): (boolean?, any)
	if handle == nil then
		return true, nil
	end
	if type(handle) ~= "table" or handle.owner ~= OWNER then
		return nil, errorResult("stage5_diagnostics_invalid", "Stage 5 diagnostic handle is invalid")
	end
	local cleaned = true
	if not handle.stopped then
		cleaned = flushEvents(handle)
	end
	handle.stopped = true
	local remaining = handle.connections
	for _ = 1, 2 do
		local failed = {}
		for _, connection in ipairs(remaining) do
			local disconnected = pcall(function()
				connection:Disconnect()
			end)
			if not disconnected then
				table.insert(failed, connection)
			end
		end
		remaining = failed
		if #remaining == 0 then
			break
		end
	end
	handle.connections = remaining
	if not cleaned or #remaining > 0 then
		return nil, errorResult("stage5_diagnostics_cleanup_failed", "Stage 5 diagnostics did not cleanly stop")
	end
	return true, nil
end

return table.freeze(Diagnostics)
