--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Stage1 = {}

local OWNER = "stage1"
local PHASE = "hold"
local UINT32_RANGE = 4294967296
local ENTRANCE = Vector3.new(-1490.1263427734375, -68.3874282836914, -533.1188354492188)
local SAFE_START = Vector3.new(-1473.716797, -158.274429, -956.626160)
local SPAWN = Vector3.new(-1455.074951171875, -157.8892059326172, -999.51025390625)
local SPAWN_RADIUS = 15

local function errorResult(code: string, message: string): { code: string, message: string }
	return { code = code, message = message }
end

local function isNonNegativeInteger(value: any): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
		and value >= 0
end

local function isSession(value: any): boolean
	return type(value) == "table"
		and type(value.id) == "string"
		and value.id ~= ""
		and value.owner == OWNER
		and value.phase == PHASE
		and isNonNegativeInteger(value.epoch)
		and isNonNegativeInteger(value.startedAt)
end

local function getRoot(): any
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getWins(): any
	local player = Players.LocalPlayer
	local leaderstats = player and player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Wins")
end

local function getWinBlock(): any
	local structure = workspace:FindFirstChild("Structure")
	local stage1 = structure and structure:FindFirstChild("Stage1")
	local sas = stage1 and stage1:FindFirstChild("SAS")
	local winBlock = sas and sas:FindFirstChild("WinBlock32")
	if winBlock and winBlock:IsA("BasePart") then
		return winBlock
	end
	return nil
end

local function stopRoot(root: any)
	if root == nil then
		return
	end
	pcall(function()
		if root.AssemblyLinearVelocity.Magnitude > 0.05 then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

local function setRootCFrame(root: any, cframe: CFrame): boolean
	stopRoot(root)
	local ok = pcall(function()
		root.CFrame = cframe
	end)
	stopRoot(root)
	return ok
end

local function retreatRoot(root: any): boolean
	if root == nil then
		return false
	end
	return setRootCFrame(root, CFrame.new(SAFE_START))
end

function Stage1.newSession(id: string, epoch: number, startedAt: number): (any?, { code: string, message: string }?)
	if type(id) ~= "string" or id == "" then
		return nil, errorResult("stage1_session_id_invalid", "session id must be a non-empty string")
	end
	if not isNonNegativeInteger(epoch) then
		return nil, errorResult("stage1_session_epoch_invalid", "session epoch must be a non-negative integer")
	end
	if not isNonNegativeInteger(startedAt) then
		return nil,
			errorResult("stage1_session_started_at_invalid", "session start time must be a non-negative integer")
	end
	return table.freeze({
		id = id,
		owner = OWNER,
		phase = PHASE,
		epoch = epoch,
		startedAt = startedAt,
	})
end

function Stage1.snapshot(session: any): (any?, { code: string, message: string }?)
	if not isSession(session) then
		return nil, errorResult("stage1_session_invalid", "session must be a valid Stage 1 hold lease")
	end
	return {
		id = session.id,
		owner = session.owner,
		phase = session.phase,
		epoch = session.epoch,
		startedAt = session.startedAt,
	}
end

function Stage1.beginHold(alive: any, oneTime: any): (any?, any)
	if type(alive) ~= "function" or alive() ~= true then
		return nil, errorResult("stage1_cancelled", "Stage 1 hold was cancelled")
	end
	if oneTime ~= nil and type(oneTime) ~= "boolean" then
		return nil, errorResult("stage1_mode_invalid", "one-time mode must be a boolean")
	end
	local wins = getWins()
	if wins == nil or type(wins.Value) ~= "number" then
		return nil, errorResult("wins_unavailable", "Wins value is unavailable")
	end
	local winBlock = getWinBlock()
	if winBlock == nil then
		return nil, errorResult("winblock32_unavailable", "WinBlock32 is unavailable")
	end

	local reachedEntrance = false
	local entranceCFrame = CFrame.new(ENTRANCE)
	for _ = 1, 3 do
		if alive() ~= true then
			retreatRoot(getRoot())
			return nil, errorResult("stage1_cancelled", "Stage 1 hold was cancelled")
		end
		local root = getRoot()
		if root == nil then
			return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
		end
		if not setRootCFrame(root, entranceCFrame) then
			stopRoot(root)
			return nil, errorResult("movement_failed", "Stage 1 entrance write failed")
		end
		task.wait(0.08)
		if alive() ~= true then
			retreatRoot(root)
			return nil, errorResult("stage1_cancelled", "Stage 1 hold was cancelled")
		end
		root = getRoot()
		if root and (root.Position - ENTRANCE).Magnitude <= 15 then
			reachedEntrance = true
			break
		end
	end
	if not reachedEntrance then
		stopRoot(getRoot())
		return nil, errorResult("entrance_corrected", "Stage 1 entrance was corrected")
	end
	if alive() ~= true then
		retreatRoot(root)
		return nil, errorResult("stage1_cancelled", "Stage 1 hold was cancelled")
	end

	local holdPosition = winBlock.Position + Vector3.new(0, 1.5, 0)
	local holdCFrame = CFrame.new(holdPosition)
	local root = getRoot()
	if root == nil then
		stopRoot(getRoot())
		return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
	end
	local winsOk, winsBefore = pcall(function()
		return wins.Value
	end)
	if not winsOk or type(winsBefore) ~= "number" then
		stopRoot(root)
		return nil, errorResult("wins_unavailable", "Wins value is unavailable")
	end
	local handle = {
		alive = alive,
		connection = nil,
		corrections = 0,
		failure = nil,
		holdCFrame = holdCFrame,
		holdPosition = holdPosition,
		lastCorrectionAt = 0,
		plateAtClock = nil,
		retreated = false,
		rewardConnection = nil,
		rewardTransition = nil,
		stopped = false,
		rewardAtClock = nil,
		root = root,
		wins = wins,
		winsBefore = winsBefore,
	}
	if oneTime == true then
		local signalOk, signal = pcall(wins.GetPropertyChangedSignal, wins, "Value")
		if not signalOk or signal == nil then
			stopRoot(root)
			return nil, errorResult("wins_signal_unavailable", "Wins change signal is unavailable")
		end
		local connected, connection = pcall(signal.Connect, signal, function()
			if handle.stopped or handle.rewardTransition ~= nil then
				return
			end
			local currentOk, current = pcall(function()
				return handle.wins.Value
			end)
			if currentOk and type(current) == "number" and current ~= handle.winsBefore then
				handle.rewardAtClock = os.clock()
				handle.rewardTransition = {
					previous = handle.winsBefore,
					current = current,
				}
				local rewardConnection = handle.rewardConnection
				if rewardConnection ~= nil then
					local disconnected = pcall(rewardConnection.Disconnect, rewardConnection)
					if disconnected then
						handle.rewardConnection = nil
					else
						handle.failure =
							errorResult("hold_disconnect_failed", "Wins connection could not be disconnected")
					end
				end
				local holdConnection = handle.connection
				if holdConnection ~= nil then
					local disconnected = pcall(holdConnection.Disconnect, holdConnection)
					if disconnected then
						handle.connection = nil
					else
						handle.failure =
							errorResult("hold_disconnect_failed", "RenderStepped connection could not be disconnected")
					end
				end
				stopRoot(handle.root)
			end
		end)
		if not connected or connection == nil then
			stopRoot(root)
			return nil, errorResult("wins_signal_unavailable", "Wins change signal could not be connected")
		end
		handle.rewardConnection = connection
	end
	handle.plateAtClock = os.clock()
	if not setRootCFrame(root, holdCFrame) then
		if handle.rewardConnection ~= nil then
			local disconnected = pcall(handle.rewardConnection.Disconnect, handle.rewardConnection)
			if disconnected then
				handle.rewardConnection = nil
			else
				handle.failure = errorResult("hold_disconnect_failed", "Wins connection could not be disconnected")
				stopRoot(root)
				return handle, handle.failure
			end
		end
		stopRoot(root)
		return nil, errorResult("movement_failed", "WinBlock32 hold write failed")
	end

	local connected, connection = pcall(RunService.RenderStepped.Connect, RunService.RenderStepped, function()
		if handle.stopped or handle.rewardTransition ~= nil or handle.alive() ~= true then
			return
		end
		local ok, failure = pcall(function()
			local liveRoot = getRoot()
			local current = os.clock()
			if
				liveRoot
				and current >= handle.lastCorrectionAt
				and (liveRoot.Position - handle.holdPosition).Magnitude > 2
			then
				handle.lastCorrectionAt = current + 0.1
				handle.corrections += 1
				if not setRootCFrame(liveRoot, handle.holdCFrame) then
					error("hold write failed")
				end
			end
		end)
		if not ok then
			handle.failure = errorResult("hold_failed", tostring(failure))
		end
	end)
	if not connected or connection == nil then
		if handle.rewardConnection ~= nil then
			local disconnected = pcall(handle.rewardConnection.Disconnect, handle.rewardConnection)
			if disconnected then
				handle.rewardConnection = nil
			else
				handle.failure = errorResult("hold_disconnect_failed", "Wins connection could not be disconnected")
				stopRoot(root)
				return handle, handle.failure
			end
		end
		stopRoot(root)
		return nil, errorResult("hold_signal_unavailable", "RenderStepped connection could not be created")
	end
	handle.connection = connection
	return handle, nil
end

function Stage1.pollHold(handle: any): (number?, number?, number?, any, number?)
	if type(handle) ~= "table" or handle.stopped then
		return nil, nil, nil, errorResult("stage1_inactive", "Stage 1 hold is inactive")
	end
	if type(handle.rewardTransition) == "table" then
		local transition = handle.rewardTransition
		handle.rewardTransition = nil
		handle.winsBefore = transition.current
		return (transition.current - transition.previous) % UINT32_RANGE,
			transition.previous,
			transition.current,
			nil,
			handle.rewardAtClock
	end
	if handle.failure ~= nil then
		return nil, nil, nil, handle.failure
	end
	local ok, current = pcall(function()
		return handle.wins.Value
	end)
	if not ok or type(current) ~= "number" then
		return nil, nil, nil, errorResult("wins_unavailable", "Wins value is unavailable")
	end
	local previous = handle.winsBefore
	if current == previous then
		return nil, previous, current, nil
	end
	handle.winsBefore = current
	return (current - previous) % UINT32_RANGE, previous, current, nil
end

function Stage1.atPulseStart(): (boolean?, number?, any)
	local root = getRoot()
	if root == nil then
		return nil, nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
	end
	local ok, distance = pcall(function()
		return math.min((root.Position - SPAWN).Magnitude, (root.Position - SAFE_START).Magnitude)
	end)
	if not ok or type(distance) ~= "number" then
		return nil, nil, errorResult("pulse_start_read_failed", "Pulse start distance could not be read")
	end
	return distance <= SPAWN_RADIUS, distance, nil
end

function Stage1.atSpawn(): (boolean?, number?, any)
	local root = getRoot()
	if root == nil then
		return nil, nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
	end
	local ok, distance = pcall(function()
		return (root.Position - SPAWN).Magnitude
	end)
	if not ok or type(distance) ~= "number" then
		return nil, nil, errorResult("spawn_read_failed", "Spawn distance could not be read")
	end
	return distance <= SPAWN_RADIUS, distance, nil
end

function Stage1.releaseHold(handle: any): (boolean?, any)
	if type(handle) ~= "table" then
		return true
	end
	handle.stopped = true
	local cleanupError = nil
	if handle.connection ~= nil then
		local disconnected = pcall(handle.connection.Disconnect, handle.connection)
		if disconnected then
			handle.connection = nil
		else
			cleanupError = errorResult("hold_disconnect_failed", "RenderStepped connection could not be disconnected")
		end
	end
	if handle.rewardConnection ~= nil then
		local disconnected = pcall(handle.rewardConnection.Disconnect, handle.rewardConnection)
		if disconnected then
			handle.rewardConnection = nil
		elseif cleanupError == nil then
			cleanupError = errorResult("hold_disconnect_failed", "Wins connection could not be disconnected")
		end
	end
	stopRoot(handle.root)
	if cleanupError ~= nil then
		return nil, cleanupError
	end
	return true
end

function Stage1.stopHold(handle: any): (boolean?, any)
	if type(handle) ~= "table" then
		return true
	end
	local released, releaseError = Stage1.releaseHold(handle)
	local cleanupError = released == true and nil or releaseError
	if not handle.retreated then
		local root = handle.root
		stopRoot(root)
		if root == nil then
			cleanupError = cleanupError
				or errorResult("hold_retreat_failed", "Owned HumanoidRootPart is unavailable during retreat")
		elseif not retreatRoot(root) then
			cleanupError = cleanupError or errorResult("hold_retreat_failed", "Safe Start retreat write failed")
		else
			handle.retreated = true
			stopRoot(root)
		end
	end
	if cleanupError ~= nil then
		return nil, cleanupError
	end
	return true
end

return table.freeze(Stage1)
