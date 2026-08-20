--!strict

local Players = game:GetService("Players")

local Movement = {}

local OWNER = "movement"
local PHASE = "safe_start"
local SAFE_START = Vector3.new(-1473.716797, -158.274429, -956.626160)
local HORIZONTAL_SPEED = 100
local REACHED_DISTANCE = 3
local MOTION_TICK = 0.1
local ACTIVE_TIMEOUT = 2
local DWELL = 0.15
local POLL_TICK = 0.05
local SPAWN_TIMEOUT = 8
local SPAWN_STABLE_TIME = 0.35
local SPAWN_STABLE_DISTANCE = 1
local SPAWN_MIN_Y = -300
local SPAWN_MAX_Y = -120
local SPAWN_MAX_Z = -900

local function errorResult(code: string, message: string): { code: string, message: string }
	return { code = code, message = message }
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

local function stopRoot(root: any): boolean
	if root == nil then
		return true
	end
	return pcall(function()
		if root.AssemblyLinearVelocity.Magnitude > 0.05 then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

local function isHandle(value: any): boolean
	return type(value) == "table"
		and value.owner == OWNER
		and value.phase == PHASE
		and type(value.alive) == "function"
		and type(value.stopped) == "boolean"
end

function Movement.newSafeStart(alive: any): (any?, any)
	if type(alive) ~= "function" or alive() ~= true then
		return nil, errorResult("movement_cancelled", "Safe Start movement was cancelled")
	end
	local root = getRoot()
	if root == nil then
		return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
	end
	local positionOk, position = pcall(function()
		return root.Position
	end)
	if not positionOk or typeof(position) ~= "Vector3" then
		return nil, errorResult("movement_read_failed", "HumanoidRootPart position is unavailable")
	end
	return {
		owner = OWNER,
		phase = PHASE,
		alive = alive,
		root = root,
		startedAt = os.clock(),
		activeElapsed = 0,
		initialDistance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(SAFE_START.X, 0, SAFE_START.Z)).Magnitude,
		finalError = nil,
		stopped = false,
		running = false,
	},
		nil
end

function Movement.snapshot(handle: any): (any?, any)
	if not isHandle(handle) then
		return nil, errorResult("movement_handle_invalid", "movement handle is invalid")
	end
	return {
		owner = handle.owner,
		phase = handle.phase,
		activeElapsed = handle.activeElapsed,
		initialDistance = handle.initialDistance,
		finalError = handle.finalError,
		stopped = handle.stopped,
		running = handle.running,
		target = {
			x = SAFE_START.X,
			y = SAFE_START.Y,
			z = SAFE_START.Z,
		},
	}
end

local function updateElapsed(handle: any): number
	handle.activeElapsed = math.max(os.clock() - handle.startedAt, 0)
	return handle.activeElapsed
end

local function releaseRoot(handle: any): boolean
	local root = handle.root
	if not stopRoot(root) then
		handle.running = false
		return false
	end
	handle.root = nil
	handle.running = false
	return true
end

function Movement.waitForSpawn(alive: any): (any?, any)
	if type(alive) ~= "function" or alive() ~= true then
		return nil, errorResult("movement_cancelled", "Spawn synchronization was cancelled")
	end
	local deadline = os.clock() + SPAWN_TIMEOUT
	local stableSince = nil
	local lastPosition = nil
	while os.clock() < deadline do
		if alive() ~= true then
			return nil, errorResult("movement_cancelled", "Spawn synchronization was cancelled")
		end
		local root = getRoot()
		if root ~= nil then
			local readOk, position = pcall(function()
				return root.Position
			end)
			if readOk and typeof(position) == "Vector3" then
				local atSpawn = position.Y > SPAWN_MIN_Y and position.Y < SPAWN_MAX_Y and position.Z < SPAWN_MAX_Z
				local stable = lastPosition ~= nil and (position - lastPosition).Magnitude < SPAWN_STABLE_DISTANCE
				if atSpawn and stable then
					stableSince = stableSince or os.clock()
					if os.clock() - stableSince >= SPAWN_STABLE_TIME then
						if not stopRoot(root) then
							return nil,
								errorResult(
									"movement_stop_failed",
									"HumanoidRootPart velocity could not be cleared at spawn"
								)
						end
						return {
							position = position,
							stableFor = os.clock() - stableSince,
						}, nil
					end
				else
					stableSince = nil
				end
				lastPosition = position
			else
				stableSince = nil
				lastPosition = nil
			end
		else
			stableSince = nil
			lastPosition = nil
		end
		task.wait(POLL_TICK)
	end
	return nil, errorResult("spawn_timeout", "No stable World 3 spawn was observed")
end

function Movement.runSafeStart(handle: any): (any?, any)
	if not isHandle(handle) or handle.running or handle.root == nil then
		return nil, errorResult("movement_handle_invalid", "movement handle is invalid or already running")
	end
	handle.running = true

	while updateElapsed(handle) < ACTIVE_TIMEOUT do
		if handle.stopped then
			releaseRoot(handle)
			return nil, errorResult("movement_cancelled", "Safe Start movement was cancelled")
		end
		if handle.alive() ~= true then
			releaseRoot(handle)
			return nil, errorResult("movement_cancelled", "Safe Start movement was cancelled")
		end

		local root = getRoot()
		if root == nil then
			releaseRoot(handle)
			return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
		end
		handle.root = root

		local readOk, position, velocity = pcall(function()
			return root.Position, root.AssemblyLinearVelocity
		end)
		if not readOk or typeof(position) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
			releaseRoot(handle)
			return nil, errorResult("movement_read_failed", "HumanoidRootPart movement state is unavailable")
		end
		local offset = Vector3.new(SAFE_START.X - position.X, 0, SAFE_START.Z - position.Z)
		if offset.Magnitude <= REACHED_DISTANCE then
			stopRoot(root)
			task.wait(DWELL)
			updateElapsed(handle)
			if handle.stopped then
				releaseRoot(handle)
				return nil, errorResult("movement_cancelled", "Safe Start movement was cancelled")
			end
			if handle.alive() ~= true then
				releaseRoot(handle)
				return nil, errorResult("movement_cancelled", "Safe Start movement was cancelled")
			end
			local finalRoot = getRoot()
			if finalRoot == nil then
				releaseRoot(handle)
				return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
			end
			handle.root = finalRoot
			local finalPosition = finalRoot.Position
			handle.finalError = (Vector3.new(finalPosition.X, 0, finalPosition.Z) - Vector3.new(
				SAFE_START.X,
				0,
				SAFE_START.Z
			)).Magnitude
			if handle.finalError > REACHED_DISTANCE then
				continue
			end
			if not releaseRoot(handle) then
				return nil, errorResult("movement_stop_failed", "HumanoidRootPart velocity could not be cleared")
			end
			return Movement.snapshot(handle)
		end

		if updateElapsed(handle) >= ACTIVE_TIMEOUT then
			releaseRoot(handle)
			return nil, errorResult("safe_start_timeout", "Safe Start was not reached within the movement deadline")
		end
		stopRoot(root)
		local direction = offset.Unit
		local wrote = pcall(function()
			root.AssemblyLinearVelocity =
				Vector3.new(direction.X * HORIZONTAL_SPEED, velocity.Y, direction.Z * HORIZONTAL_SPEED)
		end)
		if not wrote then
			releaseRoot(handle)
			return nil, errorResult("movement_write_failed", "HumanoidRootPart velocity write failed")
		end
		task.wait(MOTION_TICK)
		updateElapsed(handle)
		if handle.stopped then
			releaseRoot(handle)
			return nil, errorResult("movement_cancelled", "Safe Start movement was cancelled")
		end
	end

	local finalRoot = getRoot()
	if finalRoot ~= nil then
		handle.root = finalRoot
		local readOk, finalPosition = pcall(function()
			return finalRoot.Position
		end)
		if readOk and typeof(finalPosition) == "Vector3" then
			handle.finalError = (Vector3.new(finalPosition.X, 0, finalPosition.Z) - Vector3.new(
				SAFE_START.X,
				0,
				SAFE_START.Z
			)).Magnitude
			if handle.finalError <= REACHED_DISTANCE then
				if not releaseRoot(handle) then
					return nil, errorResult("movement_stop_failed", "HumanoidRootPart velocity could not be cleared")
				end
				return Movement.snapshot(handle)
			end
		end
	end
	releaseRoot(handle)
	return nil, errorResult("safe_start_timeout", "Safe Start was not reached within the movement deadline")
end

function Movement.stop(handle: any): (boolean?, any)
	if handle == nil then
		return true
	end
	if not isHandle(handle) then
		return nil, errorResult("movement_handle_invalid", "movement handle is invalid")
	end
	handle.stopped = true
	if not releaseRoot(handle) then
		return nil, errorResult("movement_stop_failed", "HumanoidRootPart velocity could not be cleared")
	end
	return true
end

return table.freeze(Movement)
