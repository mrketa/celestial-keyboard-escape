--!strict

local Players = game:GetService("Players")

local Route = {}
local MOTION_TICK = 1 / 30
local PROGRESS_CAP = MOTION_TICK
local CORRECTION_DISTANCE = 12
local NORMAL_RETRY_DELAY = 0.2
local HAZARD_RETRY_DELAY = 0.05
local PLATE_SPEED = 70
local PLATE_TIMEOUT = 5
local REWARD_TIMEOUT = 5
local SPAWN_TIMEOUT = 8
local SPAWN_RADIUS = 15
local UINT32_RANGE = 4294967296
local SCHEDULER_STABLE_TICKS = 8
local SCHEDULER_MAX_DELTA = 0.075
local SCHEDULER_TIMEOUT = 30
local MOVING_WALL_OPEN_GAP = 58
local MOVING_WALL_STABLE_SAMPLES = 2
local MOVING_WALL_GATE_TIMEOUT = 12
local MOVING_WALL_GATE_POLL = 0.02
local SPAWN = Vector3.new(-1455.074951171875, -157.8892059326172, -999.51025390625)

type ErrorResult = { code: string, message: string }
type Point = {
	name: string,
	position: Vector3,
	speed: number?,
	dwell: number?,
	hazardPosition: Vector3?,
	tsunamiGate: boolean?,
	raceStart: boolean?,
	humanoidWalk: boolean?,
	requiresBridge: boolean?,
	bridgeCommit: boolean?,
	touchValidation: boolean?,
	minimumRaceElapsed: number?,
	movingWallGate: number?,
}
type Spec = {
	key: string,
	label: string,
	speed: number,
	speedMultiplier: number,
	minimumCycleTime: number,
	raceMinimumTime: number,
	plate: Vector3,
	blockPath: { string },
	route: { Point },
	tsunami: { [string]: number | string }?,
	directPlate: boolean?,
	plateNudge: boolean?,
	humanoidPlate: boolean?,
	cooldownAligned: boolean?,
	rewardCooldown: number,
}

local function failure(code: string, message: string): ErrorResult
	return { code = code, message = message }
end

local function prefixed(spec: Spec, code: string, message: string): ErrorResult
	return failure(spec.key .. "_" .. code, spec.label .. " " .. message)
end

local function root(): BasePart?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local value = character and character:FindFirstChild("HumanoidRootPart")
	return if value and value:IsA("BasePart") then value else nil
end

local function identity(value: Instance?): string?
	if value == nil then
		return nil
	end
	local ok, id = pcall(function()
		return value:GetDebugId()
	end)
	return if ok and type(id) == "string" and id ~= "" then id else nil
end

local function characterIdentity(): string?
	local player = Players.LocalPlayer
	return identity(player and player.Character)
end

local function position(part: BasePart?): Vector3?
	if part == nil then
		return nil
	end
	local ok, value = pcall(function()
		return part.Position
	end)
	return if ok and typeof(value) == "Vector3" then value else nil
end

local function stopRoot(part: BasePart?): boolean
	if part == nil then
		return true
	end
	return pcall(function()
		part.AssemblyLinearVelocity = Vector3.zero
	end)
end

local function settleRoot(part: BasePart?): boolean
	if part == nil then
		return true
	end
	for attempt = 1, 3 do
		if not stopRoot(part) then
			return false
		end
		if attempt < 3 then
			task.wait(MOTION_TICK)
		end
	end
	local ok, velocity = pcall(function()
		return part.AssemblyLinearVelocity
	end)
	return ok and typeof(velocity) == "Vector3" and Vector3.new(velocity.X, 0, velocity.Z).Magnitude <= 0.05
end

local function copySpec(input: any): (Spec?, ErrorResult?)
	if
		type(input) ~= "table"
		or type(input.key) ~= "string"
		or input.key == ""
		or type(input.label) ~= "string"
		or type(input.speed) ~= "number"
		or input.speed <= 0
	then
		return nil, failure("world3_spec_invalid", "World 3 route spec is invalid")
	end
	if
		typeof(input.plate) ~= "Vector3"
		or type(input.minimumCycleTime) ~= "number"
		or input.minimumCycleTime < 0
		or type(input.raceMinimumTime) ~= "number"
		or input.raceMinimumTime < 0
		or type(input.blockPath) ~= "table"
		or type(input.route) ~= "table"
		or #input.route == 0
		or (input.directPlate ~= nil and type(input.directPlate) ~= "boolean")
		or (input.plateNudge ~= nil and type(input.plateNudge) ~= "boolean")
		or (input.humanoidPlate ~= nil and type(input.humanoidPlate) ~= "boolean")
		or (input.cooldownAligned ~= nil and type(input.cooldownAligned) ~= "boolean")
		or (input.rewardCooldown ~= nil and (type(input.rewardCooldown) ~= "number" or input.rewardCooldown < 0))
		or (input.speedMultiplier ~= nil and (type(input.speedMultiplier) ~= "number" or input.speedMultiplier <= 0))
	then
		return nil, failure(input.key .. "_spec_invalid", input.label .. " route spec is invalid")
	end
	local path = table.create(#input.blockPath)
	for index, name in ipairs(input.blockPath) do
		if type(name) ~= "string" or name == "" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " block path is invalid")
		end
		path[index] = name
	end
	local points = table.create(#input.route)
	for index, source in ipairs(input.route) do
		if
			type(source) ~= "table"
			or type(source.name) ~= "string"
			or source.name == ""
			or typeof(source.position) ~= "Vector3"
		then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " point " .. index .. " is invalid")
		end
		if source.speed ~= nil and (type(source.speed) ~= "number" or source.speed <= 0) then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " point speed is invalid")
		end
		if source.dwell ~= nil and (type(source.dwell) ~= "number" or source.dwell < 0) then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " point dwell is invalid")
		end
		if source.humanoidWalk ~= nil and type(source.humanoidWalk) ~= "boolean" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " humanoid walk point is invalid")
		end
		if
			source.minimumRaceElapsed ~= nil
			and (type(source.minimumRaceElapsed) ~= "number" or source.minimumRaceElapsed < 0)
		then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " point timing gate is invalid")
		end
		if
			source.movingWallGate ~= nil
			and (
				type(source.movingWallGate) ~= "number"
				or source.movingWallGate ~= math.floor(source.movingWallGate)
				or source.movingWallGate < 1
				or source.movingWallGate > 6
			)
		then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " moving wall gate is invalid")
		end
		if source.bridgeCommit ~= nil and type(source.bridgeCommit) ~= "boolean" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " bridge commitment point is invalid")
		end
		if source.requiresBridge ~= nil and type(source.requiresBridge) ~= "boolean" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " bridge route point is invalid")
		end
		if source.bridgeCommit == true and (source.humanoidWalk ~= true or source.requiresBridge ~= true) then
			return nil,
				failure(
					input.key .. "_spec_invalid",
					input.label .. " bridge commitment requires a bridge-dependent Humanoid walk point"
				)
		end
		if source.hazardPosition ~= nil and typeof(source.hazardPosition) ~= "Vector3" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " hazard point is invalid")
		end
		if source.raceStart ~= nil and type(source.raceStart) ~= "boolean" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " race start point is invalid")
		end
		points[index] = table.freeze({
			name = source.name,
			position = source.position,
			speed = source.speed,
			dwell = source.dwell,
			humanoidWalk = source.humanoidWalk == true,
			requiresBridge = source.requiresBridge == true,
			bridgeCommit = source.bridgeCommit == true,
			hazardPosition = source.hazardPosition,
			tsunamiGate = source.tsunamiGate == true,
			touchValidation = source.touchValidation == true,
			raceStart = source.raceStart == true,
			minimumRaceElapsed = source.minimumRaceElapsed,
			movingWallGate = source.movingWallGate,
		})
	end
	local raceStartSeen = false
	for index, point in ipairs(points) do
		if point.raceStart then
			raceStartSeen = true
		end
		if point.minimumRaceElapsed ~= nil and (not raceStartSeen or point.requiresBridge or point.bridgeCommit) then
			return nil,
				failure(
					input.key .. "_spec_invalid",
					input.label .. " point timing gate " .. index .. " must precede the bridge from a started race"
				)
		end
	end
	local bridgeCommitIndex: number? = nil
	for index, point in ipairs(points) do
		if point.requiresBridge and bridgeCommitIndex ~= nil then
			return nil,
				failure(input.key .. "_spec_invalid", input.label .. " bridge target follows forward commitment")
		end
		if point.bridgeCommit then
			if bridgeCommitIndex ~= nil then
				return nil, failure(input.key .. "_spec_invalid", input.label .. " bridge commitment is duplicated")
			end
			bridgeCommitIndex = index
		end
	end
	local tsunami: { [string]: number | string }? = nil
	if input.tsunami ~= nil then
		if type(input.tsunami) ~= "table" then
			return nil, failure(input.key .. "_spec_invalid", input.label .. " tsunami gate is invalid")
		end
		local copied: { [string]: number | string } = {}
		for key, value in pairs(input.tsunami) do
			if type(key) ~= "string" or (type(value) ~= "number" and type(value) ~= "string") then
				return nil, failure(input.key .. "_spec_invalid", input.label .. " tsunami gate is invalid")
			end
			copied[key] = value
		end
		tsunami = table.freeze(copied)
	end
	return table.freeze({
		key = input.key,
		label = input.label,
		speed = input.speed,
		speedMultiplier = input.speedMultiplier or 1,
		minimumCycleTime = input.minimumCycleTime,
		plate = input.plate,
		blockPath = table.freeze(path),
		route = table.freeze(points),
		raceMinimumTime = input.raceMinimumTime,
		tsunami = tsunami,
		directPlate = input.directPlate == true,
		plateNudge = input.plateNudge == true,
		humanoidPlate = input.humanoidPlate == true,
		cooldownAligned = input.cooldownAligned ~= false,
		rewardCooldown = input.rewardCooldown or 0,
	}),
		nil
end

function Route.create(input: any): any
	local spec, specError = copySpec(input)
	if spec == nil then
		error(if specError then specError.message else "World 3 route spec is invalid", 2)
	end
	local eventPrefix = spec.key
	local policy = {}
	local lastRewardAtClock: number? = nil

	local function emit(handle: any, suffix: string, fields: { [string]: any }): boolean
		fields.sessionId = handle.id
		local ok, accepted = pcall(handle.emit, eventPrefix .. "_" .. suffix, fields)
		return ok and accepted == true
	end
	local function cancelled(handle: any): boolean
		return handle.stopped or handle.alive() ~= true
	end
	local function live(handle: any): ErrorResult?
		if cancelled(handle) then
			return prefixed(spec, "cancelled", "run was cancelled")
		end
		if
			handle.characterIdentity ~= nil
			and characterIdentity() ~= nil
			and characterIdentity() ~= handle.characterIdentity
		then
			return prefixed(spec, "character_replaced", "character was replaced")
		end
		if root() == nil then
			return prefixed(spec, "character_unavailable", "HumanoidRootPart is unavailable")
		end
		return nil
	end
	local function sample(handle: any, label: string, index: number)
		if handle.diagnostics ~= nil then
			pcall(handle.diagnosticModule.sample, handle.diagnostics, label, index)
		end
	end
	local function waitForRewardCooldown(handle: any): ErrorResult?
		if lastRewardAtClock == nil or spec.rewardCooldown <= 0 then
			return nil
		end
		local deadline = lastRewardAtClock + spec.rewardCooldown
		if os.clock() >= deadline then
			return nil
		end
		handle.status = "Waiting for reward cooldown"
		handle.point = "Reward cooldown"
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			task.wait(math.min(0.25, deadline - os.clock()))
		end
		sample(handle, "reward_cooldown_completed", 0)
		return nil
	end
	local function disconnect(handle: any): boolean
		if handle.motionConnection == nil then
			return true
		end
		local ok = pcall(function()
			handle.motionConnection:Disconnect()
		end)
		handle.motionConnection = nil
		return ok
	end
	local function stopDiagnostics(handle: any): boolean
		if handle.diagnostics == nil then
			return true
		end
		for _ = 1, 2 do
			local ok, stopped = pcall(handle.diagnosticModule.stop, handle.diagnostics)
			if ok and stopped == true then
				handle.diagnostics = nil
				return true
			end
		end
		return false
	end
	local function clean(handle: any): boolean
		local ok = disconnect(handle)
		ok = settleRoot(handle.ownedRoot) and ok
		if handle.safeHandle ~= nil then
			local stopped = handle.movement.stop(handle.safeHandle)
			handle.safeHandle = nil
			ok = stopped == true and ok
		end
		ok = stopDiagnostics(handle) and ok
		handle.ownedRoot = nil
		return ok
	end
	local function finish(handle: any, reason: ErrorResult): (nil, ErrorResult)
		handle.failure = reason
		handle.running = false
		handle.finishedAt = os.clock()
		handle.elapsed = math.max(handle.finishedAt - handle.startedAt, 0)
		sample(handle, "failure_" .. reason.code, handle.pointsCompleted)
		if not clean(handle) then
			handle.failure = prefixed(spec, "cleanup_failed", "could not clear owned movement")
		end
		return nil, handle.failure
	end
	local function pointTarget(point: Point): Vector3
		return point.hazardPosition or point.position
	end
	local function bridgeAvailable(): boolean
		local bridgeRoot = workspace:FindFirstChild("Keycaps")
		local bridge = bridgeRoot and bridgeRoot:FindFirstChild("Bridge1")
		return bridge ~= nil and bridge:FindFirstChild("BidgePart") ~= nil
	end
	local function requireBridge(handle: any, point: Point): ErrorResult?
		if not point.requiresBridge then
			return nil
		end
		if handle.bridgeCommitted then
			return prefixed(
				spec,
				"bridge_target_after_commitment",
				"route attempted a bridge target after forward commitment"
			)
		end
		if not bridgeAvailable() then
			return prefixed(
				spec,
				"bridge_despawned_before_commitment",
				"keycap bridge despawned before forward commitment"
			)
		end
		return nil
	end
	local function acquireTimedHandoff(
		handle: any,
		expectedRoot: BasePart,
		target: Vector3,
		nominalSpeed: number
	): ErrorResult?
		local issue = live(handle)
		if issue then
			return issue
		end
		if root() ~= expectedRoot then
			return prefixed(spec, "character_replaced", "character root changed during timed handoff")
		end
		local current = position(expectedRoot)
		if current == nil then
			return prefixed(spec, "character_unavailable", "timed handoff position is unavailable")
		end
		local remaining = (target - current).Magnitude
		local acquisitionDistance = math.min(remaining, nominalSpeed * PROGRESS_CAP)
		local command = if remaining > 0 then current:Lerp(target, acquisitionDistance / remaining) else current
		if not stopRoot(expectedRoot) then
			return prefixed(spec, "movement_write_failed", "timed handoff velocity reset failed")
		end
		local wrote = pcall(function()
			expectedRoot.CFrame = CFrame.new(command)
			expectedRoot.AssemblyLinearVelocity = Vector3.zero
		end)
		if not wrote then
			return prefixed(spec, "movement_write_failed", "timed handoff acquisition failed")
		end
		task.wait(MOTION_TICK)
		issue = live(handle)
		if issue then
			return issue
		end
		if root() ~= expectedRoot then
			return prefixed(spec, "character_replaced", "character root changed during timed handoff")
		end
		local actual = position(expectedRoot)
		if actual == nil then
			return prefixed(spec, "character_unavailable", "timed handoff position became unavailable")
		end
		local deviation = (actual - command).Magnitude
		if deviation > CORRECTION_DISTANCE then
			return prefixed(spec, "movement_handoff_deviation", "timed handoff exceeded correction distance")
		end
		if not settleRoot(expectedRoot) then
			return prefixed(spec, "movement_write_failed", "timed handoff did not settle")
		end
		return nil
	end
	local function remainingCooldown(handle: any, at: number): number
		if handle.raceStartedAt == nil then
			return math.max(handle.cycleStartedAt + spec.minimumCycleTime - at, 0)
		end
		return math.max(
			math.max(handle.cycleStartedAt + spec.minimumCycleTime, handle.raceStartedAt + spec.raceMinimumTime) - at,
			0
		)
	end

	local function plannedSpeed(handle: any, index: number, current: Vector3): (number, number)
		if handle.raceStartedAt == nil then
			return spec.speed, remainingCooldown(handle, os.clock())
		end
		local now = os.clock()
		local legalGate =
			math.max(handle.cycleStartedAt + spec.minimumCycleTime, handle.raceStartedAt + spec.raceMinimumTime)
		local flexibleDistance, fixedDuration, dwell = 0, 0, 0
		local previous = current
		for routeIndex = index, #spec.route do
			local routePoint = spec.route[routeIndex]
			local target = pointTarget(routePoint)
			local distance = (target - previous).Magnitude
			if routePoint.speed == nil then
				flexibleDistance += distance
			else
				fixedDuration += distance / routePoint.speed
			end
			dwell += routePoint.dwell or 0.2
			previous = target
		end
		local available = legalGate - now - fixedDuration - dwell
		if available <= 0.001 or flexibleDistance <= 0 then
			return spec.speed, remainingCooldown(handle, now)
		end
		return math.clamp(flexibleDistance / available, 50, spec.speed), remainingCooldown(handle, now)
	end
	local function plateTravelDuration(from: Vector3): number
		if spec.directPlate then
			return MOTION_TICK
		end
		local horizontal = Vector3.new(spec.plate.X - from.X, 0, spec.plate.Z - from.Z).Magnitude
		if spec.humanoidPlate then
			local part = root()
			local humanoid = part and part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
			return horizontal / (if humanoid then math.max(humanoid.WalkSpeed, 1) else spec.speed)
		end
		return horizontal / PLATE_SPEED
	end

	local function alignedGate(handle: any): number
		local cycleGate = handle.cycleStartedAt + spec.minimumCycleTime
		if handle.raceStartedAt == nil then
			return cycleGate
		end
		return math.max(cycleGate, handle.raceStartedAt + spec.raceMinimumTime)
	end

	local function waitForAlignedPlate(handle: any): ErrorResult?
		local here = position(root())
		if here == nil then
			return prefixed(spec, "character_unavailable", "plate timing position is unavailable")
		end
		local deadline = alignedGate(handle) - plateTravelDuration(here)
		handle.status = "Aligning winplate cooldown"
		handle.point = "Cooldown alignment"
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			task.wait(MOTION_TICK)
		end
		return nil
	end
	local function waitForPointTiming(handle: any, point: Point): ErrorResult?
		if point.minimumRaceElapsed == nil then
			return nil
		end
		if handle.raceStartedAt == nil then
			return prefixed(spec, "timing_gate_invalid", "point timing gate has no race start")
		end
		handle.status = "Aligning " .. point.name .. " timing"
		while os.clock() - handle.raceStartedAt < point.minimumRaceElapsed do
			local issue = live(handle)
			if issue then
				return issue
			end
			task.wait(MOTION_TICK)
		end
		return nil
	end

	local function movingWallGap(index: number): number?
		local structure = workspace:FindFirstChild("Structure")
		local stage9 = structure and structure:FindFirstChild("Stage9")
		if stage9 == nil then
			return nil
		end
		local groups = {}
		for _, child in ipairs(stage9:GetChildren()) do
			if child.Name == "MovingWalls" then
				table.insert(groups, child)
			end
		end
		if #groups ~= 2 then
			return nil
		end
		local name = "MovingWall" .. tostring(index)
		local first = groups[1]:FindFirstChild(name, true)
		local second = groups[2]:FindFirstChild(name, true)
		if first == nil or second == nil or not first:IsA("BasePart") or not second:IsA("BasePart") then
			return nil
		end
		return math.abs(first.Position.Z - second.Position.Z) - ((first.Size.Z + second.Size.Z) / 2)
	end

	local function waitForMovingWall(handle: any, point: Point): ErrorResult?
		if point.movingWallGate == nil then
			return nil
		end
		local deadline = os.clock() + MOVING_WALL_GATE_TIMEOUT
		local previousGap: number? = nil
		local stableSamples = 0
		handle.status = "Waiting for " .. point.name .. " opening"
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			local gap = movingWallGap(point.movingWallGate)
			if gap == nil then
				return prefixed(spec, "moving_wall_unavailable", "moving wall gate is unavailable")
			end
			if gap >= MOVING_WALL_OPEN_GAP and (previousGap == nil or gap >= previousGap - 0.5) then
				stableSamples += 1
				if stableSamples >= MOVING_WALL_STABLE_SAMPLES then
					sample(handle, "moving_wall_gate_passed", point.movingWallGate)
					return nil
				end
			else
				stableSamples = 0
			end
			previousGap = gap
			task.wait(MOVING_WALL_GATE_POLL)
		end
		return prefixed(spec, "moving_wall_timeout", "moving wall gate did not open")
	end
	local function walk(handle: any, index: number, point: Point): ErrorResult?
		handle.point = point.name
		local part = root()
		local initial = position(part)
		local humanoid = part and part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if part == nil or initial == nil or humanoid == nil then
			return prefixed(spec, "character_unavailable", "Humanoid walk is unavailable")
		end
		handle.ownedRoot = part
		local bridgeIssue = requireBridge(handle, point)
		if bridgeIssue then
			return bridgeIssue
		end
		local target = point.position
		local startedAt = os.clock()
		local deadline = startedAt + math.max(12, (target - initial).Magnitude / math.max(humanoid.WalkSpeed, 1) * 4)
		if
			not emit(handle, "point_started", {
				pointIndex = index,
				name = point.name,
				attempt = 1,
				distance = (target - initial).Magnitude,
				speed = humanoid.WalkSpeed,
				cooldownRemaining = remainingCooldown(handle, startedAt),
			})
		then
			return prefixed(spec, "trace_write_failed", "walk point start could not be recorded")
		end
		humanoid:MoveTo(target)
		local nextMoveAt = startedAt + 0.5
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			local bridgeIssue = requireBridge(handle, point)
			if bridgeIssue then
				return bridgeIssue
			end
			part = root()
			local actual = position(part)
			humanoid = part and part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
			if part == nil or actual == nil or humanoid == nil then
				return prefixed(spec, "character_unavailable", "Humanoid walk lost the character")
			end
			local distanceToTarget = (actual - target).Magnitude
			local verticalSpeed = math.abs(part.AssemblyLinearVelocity.Y)
			local touchAccepted = point.touchValidation and math.abs(actual.X - target.X) <= 80 and verticalSpeed >= 15
			local acceptanceRadius = point.touchValidation and 20 or 8
			if distanceToTarget <= acceptanceRadius or touchAccepted then
				humanoid:MoveTo(actual)
				task.wait(point.dwell or 0.2)
				handle.pointsCompleted = index
				if
					not emit(
						handle,
						"point_completed",
						{ pointIndex = index, name = point.name, attempt = 1, finalError = distanceToTarget }
					)
				then
					return prefixed(spec, "trace_write_failed", "walk point completion could not be recorded")
				end
				if point.bridgeCommit then
					handle.bridgeCommitted = true
				end
				return nil
			end
			if actual.Y < target.Y - 10 then
				part.CFrame = CFrame.new(actual.X, target.Y, actual.Z)
				part.AssemblyLinearVelocity =
					Vector3.new(part.AssemblyLinearVelocity.X, 0, part.AssemblyLinearVelocity.Z)
				humanoid:MoveTo(target)
			elseif os.clock() >= nextMoveAt then
				nextMoveAt = os.clock() + 0.5
				humanoid:MoveTo(target)
			end
			task.wait(0.05)
		end
		return prefixed(spec, "walk_timeout", "Humanoid walk did not reach " .. point.name)
	end

	local function move(handle: any, index: number, point: Point): ErrorResult?
		local bridgeIssue = requireBridge(handle, point)
		if bridgeIssue then
			return bridgeIssue
		end
		if point.humanoidWalk then
			return walk(handle, index, point)
		end
		handle.point = point.name
		local initialPart = root()
		if initialPart == nil then
			return prefixed(spec, "character_unavailable", "HumanoidRootPart is unavailable")
		end
		local nominalSpeed = (point.speed or spec.speed) * spec.speedMultiplier
		local target = pointTarget(point)
		local previousPoint = spec.route[index - 1]
		if previousPoint ~= nil and previousPoint.humanoidWalk then
			handle.ownedRoot = initialPart
			local handoffIssue = acquireTimedHandoff(handle, initialPart, target, nominalSpeed)
			if handoffIssue then
				return handoffIssue
			end
			local afterBridgeHandoff = requireBridge(handle, point)
			if afterBridgeHandoff then
				return afterBridgeHandoff
			end
		end
		local initial = position(initialPart)
		if initial == nil then
			return prefixed(spec, "character_unavailable", "HumanoidRootPart position is unavailable")
		end
		local deadline = os.clock() + math.max(12, 6 * (target - initial).Magnitude / nominalSpeed)
		local attempt = 0
		while os.clock() < deadline do
			attempt += 1
			local startPart = root()
			local start = position(startPart)
			if startPart == nil or start == nil then
				return prefixed(spec, "character_unavailable", "HumanoidRootPart is unavailable")
			end
			handle.ownedRoot = startPart
			local distance = (target - start).Magnitude
			local speed, cooldownRemaining = nominalSpeed, remainingCooldown(handle, os.clock())
			if point.speed == nil and not spec.cooldownAligned then
				speed, cooldownRemaining = plannedSpeed(handle, index, start)
			end
			local duration = distance / speed
			if
				not emit(handle, "point_started", {
					pointIndex = index,
					name = point.name,
					attempt = attempt,
					distance = distance,
					speed = speed,
					cooldownRemaining = cooldownRemaining,
				})
			then
				return prefixed(spec, "trace_write_failed", "point start could not be recorded")
			end
			local elapsed, lastAt, lastCommand = 0, os.clock(), start
			local finished, correcting, callbackFailure = false, nil, nil
			local frames, sumDelta, maxDelta, maxDeviation, commandedDistance = 0, 0, 0, 0, 0
			while os.clock() < deadline and elapsed < duration do
				local issue = live(handle)
				local part = root()
				local actual = position(part)
				if issue ~= nil then
					callbackFailure = issue
					break
				end
				local bridgeIssue = requireBridge(handle, point)
				if bridgeIssue then
					callbackFailure = bridgeIssue
					break
				end
				if part == nil or actual == nil then
					callbackFailure = prefixed(spec, "character_unavailable", "HumanoidRootPart is unavailable")
					break
				end
				local now = os.clock()
				local delta = math.max(now - lastAt, 0)
				local deviation = (actual - lastCommand).Magnitude
				frames += 1
				sumDelta += delta
				maxDelta = math.max(maxDelta, delta)
				maxDeviation = math.max(maxDeviation, deviation)
				if deviation > CORRECTION_DISTANCE then
					correcting = deviation
					stopRoot(part)
					break
				end
				if not stopRoot(part) then
					callbackFailure = prefixed(spec, "movement_write_failed", "velocity reset failed")
					break
				end
				elapsed = math.min(elapsed + math.min(delta, PROGRESS_CAP), duration)
				local command = start:Lerp(target, if duration > 0 then elapsed / duration else 1)
				commandedDistance += (command - lastCommand).Magnitude
				if not pcall(function()
					part.CFrame = CFrame.new(command)
				end) then
					callbackFailure = prefixed(spec, "movement_write_failed", "timed CFrame command failed")
					break
				end
				lastCommand = command
				lastAt = now
				task.wait(MOTION_TICK)
			end
			finished = elapsed >= duration and correcting == nil and callbackFailure == nil
			if handle.diagnostics ~= nil then
				pcall(handle.diagnosticModule.motion, handle.diagnostics, {
					driver = "timed_matcha_profile",
					pointIndex = index,
					name = point.name,
					attempt = attempt,
					outcome = if finished then "completed" elseif correcting ~= nil then "corrected" else "failed",
					frameCount = frames,
					meanFrameDelta = if frames > 0 then sumDelta / frames else 0,
					maxFrameDelta = maxDelta,
					maxDeviation = maxDeviation,
					commandedDistance = commandedDistance,
				})
			end
			if callbackFailure ~= nil then
				return callbackFailure
			end
			if correcting == nil and finished then
				local part = root()
				if part == nil or not pcall(function()
					part.CFrame = CFrame.new(target)
				end) then
					return prefixed(spec, "movement_write_failed", "final CFrame command failed")
				end
				stopRoot(part)
				task.wait(point.dwell or 0.2)
				local final = position(part)
				local errorDistance = final and (final - target).Magnitude
				if errorDistance ~= nil and errorDistance <= CORRECTION_DISTANCE then
					handle.pointsCompleted = index
					if
						not emit(
							handle,
							"point_completed",
							{ pointIndex = index, name = point.name, attempt = attempt, finalError = errorDistance }
						)
					then
						return prefixed(spec, "trace_write_failed", "point completion could not be recorded")
					end
					return nil
				end
				correcting = errorDistance or CORRECTION_DISTANCE + 1
			end
			handle.corrections += 1
			if
				not emit(
					handle,
					"point_corrected",
					{ pointIndex = index, name = point.name, attempt = attempt, deviation = correcting }
				)
			then
				return prefixed(spec, "trace_write_failed", "correction could not be recorded")
			end
			task.wait(
				if point.speed ~= nil or point.hazardPosition ~= nil then HAZARD_RETRY_DELAY else NORMAL_RETRY_DELAY
			)
		end
		return prefixed(
			spec,
			"movement_correction_deadline",
			"movement correction retry deadline elapsed at " .. point.name
		)
	end
	local function waitForStableScheduler(handle: any): ErrorResult?
		local deadline = os.clock() + SCHEDULER_TIMEOUT
		local stableTicks = 0
		local previous = os.clock()
		handle.status = "Waiting for stable scheduler"
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			task.wait(MOTION_TICK)
			local now = os.clock()
			local delta = now - previous
			previous = now
			if delta <= SCHEDULER_MAX_DELTA then
				stableTicks += 1
				if stableTicks >= SCHEDULER_STABLE_TICKS then
					sample(handle, "scheduler_stable", 0)
					return nil
				end
			else
				stableTicks = 0
			end
		end
		return prefixed(spec, "scheduler_unstable", "scheduler did not stabilize before the tsunami gate")
	end
	local function tsunamiGate(handle: any): ErrorResult?
		if spec.tsunami == nil then
			return nil
		end
		local schedulerError = waitForStableScheduler(handle)
		if schedulerError then
			return schedulerError
		end
		handle.status = "Waiting for tsunami gate"
		handle.point = spec.tsunami.before
		local npc = workspace:FindFirstChild("NPC & Piege")
		local tsunami1 = npc and npc:FindFirstChild("Tsunami1")
		local tsunami = tsunami1 and tsunami1:FindFirstChild("Tsunami")
		if tsunami == nil or tsunami1 == nil then
			return prefixed(spec, "tsunami_unavailable", "tsunami gate is unavailable")
		end
		local deadline = os.clock() + (spec.tsunami.timeout :: number)
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			local spawn = tsunami1:FindFirstChild("TsunamiSpawn")
			local ending = tsunami1:FindFirstChild("TsunamiEnd")
			local travel = tsunami1:GetAttribute("TravelTime")
			local valid = false
			local dynamicAvailable = false
			local allowPassed = spec.tsunami.allowPassed == 1
			if
				tsunami:IsA("BasePart")
				and spawn
				and ending
				and spawn:IsA("BasePart")
				and ending:IsA("BasePart")
				and type(travel) == "number"
				and travel > 0
			then
				local distance = (ending.Position - spawn.Position).Magnitude
				if distance > 0 then
					dynamicAvailable = true
					local remaining = (ending.Position - tsunami.Position).Magnitude / (distance / travel)
					valid = remaining <= (spec.tsunami.remainingMax :: number)
						and (allowPassed or remaining >= (spec.tsunami.remainingMin :: number))
				end
			end
			local tsunamiPosition = if tsunami:IsA("BasePart") then position(tsunami) else nil
			if not dynamicAvailable and tsunamiPosition ~= nil then
				valid = if allowPassed
					then tsunamiPosition.X < (spec.tsunami.xMax :: number)
					else tsunamiPosition.X > (spec.tsunami.xMin :: number)
						and tsunamiPosition.X < (spec.tsunami.xMax :: number)
			end
			if valid then
				handle.status = "Tsunami gate passed"
				if not emit(handle, "tsunami_gate", { status = handle.status, point = handle.point }) then
					return prefixed(spec, "trace_write_failed", "tsunami gate could not be recorded")
				end
				return nil
			end
			task.wait(spec.tsunami.poll :: number)
		end
		return prefixed(spec, "tsunami_timeout", "tsunami gate did not open")
	end
	local function block(): BasePart?
		local current: Instance? = workspace
		for _, name in ipairs(spec.blockPath) do
			current = current and current:FindFirstChild(name)
		end
		return if current and current:IsA("BasePart") then current else nil
	end
	local function wins(): any
		local player = Players.LocalPlayer
		local stats = player and player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild("Wins")
		local ok, number = pcall(function()
			return value and value.Value
		end)
		return if ok and type(number) == "number" then value else nil
	end
	local function enterPlate(handle: any, target: BasePart, value: any, before: number): ErrorResult?
		local enteredAt = os.clock()
		local deadline = enteredAt + PLATE_TIMEOUT
		local direction: Vector3? = nil
		local entered = false
		local player = Players.LocalPlayer
		local character = player and player.Character
		local touch: RBXScriptConnection? = nil
		if character then
			pcall(function()
				touch = target.Touched:Connect(function(part)
					if part:IsDescendantOf(character) then
						entered = true
						handle.localTouchObserved = true
					end
				end)
			end)
		end
		local function closeTouch()
			if touch then
				pcall(function()
					touch:Disconnect()
				end)
				touch = nil
			end
		end
		if spec.directPlate then
			local part = root()
			local targetPosition = position(target)
			if part == nil or targetPosition == nil then
				closeTouch()
				return prefixed(spec, "character_unavailable", "direct win block entry is unavailable")
			end
			local moved = pcall(function()
				local entryOffset = spec.plateNudge and Vector3.new(4, 1.5, 0) or Vector3.new(0, 1.5, 0)
				part.CFrame = CFrame.new(targetPosition + entryOffset)
				part.AssemblyLinearVelocity = Vector3.zero
			end)
			if not moved then
				closeTouch()
				return prefixed(spec, "movement_write_failed", "direct win block entry failed")
			end
			task.wait(MOTION_TICK)
		end
		while os.clock() < deadline do
			local issue = live(handle)
			if issue then
				closeTouch()
				return issue
			end
			local ok, current = pcall(function()
				return value.Value
			end)
			if not ok or type(current) ~= "number" then
				closeTouch()
				return prefixed(spec, "wins_unavailable", "Wins value became unavailable")
			end
			if current ~= before then
				handle.plateDwell = os.clock() - enteredAt
				closeTouch()
				return nil
			end
			local part = root()
			local here = position(part)
			local targetPosition = position(target)
			if part == nil or here == nil then
				closeTouch()
				return prefixed(spec, "character_unavailable", "HumanoidRootPart is unavailable")
			end
			if targetPosition == nil then
				closeTouch()
				return prefixed(spec, "winblock_unavailable", "win block position is unavailable")
			end
			local offset = Vector3.new(spec.plate.X - here.X, 0, spec.plate.Z - here.Z)
			local reached = offset.Magnitude <= 1.5
			if direction == nil and offset.Magnitude > 0 then
				direction = offset.Unit
			end
			if reached then
				entered = true
			end
			if entered and not handle.plateEntered then
				handle.plateEntered = true
				if
					not emit(
						handle,
						"plate_entered",
						{ winsBefore = before, touchSignal = handle.localTouchObserved == true }
					)
				then
					closeTouch()
					return prefixed(spec, "trace_write_failed", "plate entry could not be recorded")
				end
			end
			if reached then
				stopRoot(part)
				break
			end
			if entered and offset.Magnitude > 30 then
				break
			end
			local moved = pcall(function()
				if spec.humanoidPlate then
					local humanoid = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
					if humanoid == nil then
						error("Humanoid is unavailable")
					end
					humanoid:MoveTo(Vector3.new(spec.plate.X, targetPosition.Y + 1.5, spec.plate.Z))
				elseif direction ~= nil then
					local velocity = part.AssemblyLinearVelocity
					part.AssemblyLinearVelocity =
						Vector3.new(direction.X * PLATE_SPEED, velocity.Y, direction.Z * PLATE_SPEED)
				end
			end)
			if not moved then
				closeTouch()
				return prefixed(spec, "movement_write_failed", "plate movement could not be written")
			end
			task.wait(MOTION_TICK)
		end
		closeTouch()
		stopRoot(handle.ownedRoot)
		if not entered then
			return prefixed(spec, "reward_timeout", "win block entry did not complete")
		end
		local rewardDeadline = os.clock() + REWARD_TIMEOUT
		while os.clock() < rewardDeadline do
			local issue = live(handle)
			if issue then
				return issue
			end
			local ok, current = pcall(function()
				return value.Value
			end)
			if ok and type(current) == "number" and current ~= before then
				handle.plateDwell = os.clock() - enteredAt
				return nil
			end
			task.wait(MOTION_TICK)
		end
		return prefixed(spec, "reward_timeout", "reward was not observed")
	end
	function policy.newSession(
		id: string,
		epoch: number,
		startedAt: number,
		alive: any,
		movement: any,
		diagnosticModule: any,
		callback: any
	): (any?, ErrorResult?)
		if
			type(id) ~= "string"
			or id == ""
			or type(epoch) ~= "number"
			or epoch < 0
			or epoch % 1 ~= 0
			or type(startedAt) ~= "number"
			or startedAt < 0
			or type(alive) ~= "function"
			or type(callback) ~= "function"
		then
			return nil, prefixed(spec, "session_invalid", "session dependencies are invalid")
		end
		if
			type(movement) ~= "table"
			or type(movement.waitForSpawn) ~= "function"
			or type(movement.newSafeStart) ~= "function"
			or type(movement.runSafeStart) ~= "function"
			or type(movement.stop) ~= "function"
		then
			return nil, prefixed(spec, "movement_invalid", "requires the existing Safe Start movement policy")
		end
		if
			type(diagnosticModule) ~= "table"
			or type(diagnosticModule.newSession) ~= "function"
			or type(diagnosticModule.start) ~= "function"
			or type(diagnosticModule.sample) ~= "function"
			or type(diagnosticModule.motion) ~= "function"
			or type(diagnosticModule.stop) ~= "function"
		then
			return nil, prefixed(spec, "diagnostics_invalid", "diagnostic policy is invalid")
		end
		local diagnostics, diagnosticError = diagnosticModule.newSession(id, startedAt, callback)
		if diagnostics == nil then
			return nil, diagnosticError
		end
		return {
			id = id,
			epoch = epoch,
			startedAt = startedAt,
			alive = alive,
			movement = movement,
			emit = callback,
			diagnosticModule = diagnosticModule,
			diagnostics = diagnostics,
			stopped = false,
			running = false,
			complete = false,
			failure = nil,
			characterIdentity = nil,
			ownedRoot = nil,
			motionConnection = nil,
			safeHandle = nil,
			point = nil,
			status = "Idle",
			pointsCompleted = 0,
			corrections = 0,
			reward = nil,
			winsBefore = nil,
			winsAfter = nil,
			plateDwell = nil,
			plateEntered = false,
			bridgeCommitted = false,
			elapsed = 0,
		},
			nil
	end
	function policy.run(handle: any): (any?, ErrorResult?)
		if type(handle) ~= "table" or handle.running or handle.complete then
			return nil, prefixed(spec, "handle_invalid", "handle is invalid or already used")
		end
		handle.running = true
		local started, startError = handle.diagnosticModule.start(handle.diagnostics)
		if started ~= true then
			return finish(handle, startError or prefixed(spec, "diagnostics_failed", "diagnostics failed"))
		end
		sample(handle, "run_start", 0)
		local _, spawnError = handle.movement.waitForSpawn(handle.alive)
		if spawnError then
			return finish(handle, spawnError)
		end
		local cooldownError = waitForRewardCooldown(handle)
		if cooldownError then
			return finish(handle, cooldownError)
		end
		handle.cycleStartedAt = os.clock()
		local cycle = handle.cycleStartedAt
		handle.characterIdentity = characterIdentity()
		handle.ownedRoot = root()
		if handle.ownedRoot == nil then
			return finish(handle, prefixed(spec, "character_unavailable", "character is unavailable before Safe Start"))
		end
		local safe, safeError = handle.movement.newSafeStart(handle.alive)
		handle.safeHandle = safe
		if safe == nil then
			return finish(handle, safeError or prefixed(spec, "character_unavailable", "Safe Start is unavailable"))
		end
		local _, runError = handle.movement.runSafeStart(safe)
		if runError then
			return finish(handle, runError)
		end
		handle.safeHandle = nil
		local afterSafeStart = live(handle)
		if afterSafeStart then
			return finish(handle, afterSafeStart)
		end
		handle.ownedRoot = root()
		sample(handle, "safe_start_completed", 0)
		for index, point in ipairs(spec.route) do
			if point.tsunamiGate then
				local gateError = tsunamiGate(handle)
				if gateError then
					return finish(handle, gateError)
				end
			end
			local movingWallError = waitForMovingWall(handle, point)
			if movingWallError then
				return finish(handle, movingWallError)
			end
			local moveError = move(handle, index, point)
			if moveError then
				return finish(handle, moveError)
			end
			sample(handle, "point_completed", index)
			if point.raceStart then
				handle.raceStartedAt = os.clock()
			end
			local pointTimingError = waitForPointTiming(handle, point)
			if pointTimingError then
				return finish(handle, pointTimingError)
			end
			if point.minimumRaceElapsed ~= nil then
				sample(handle, "point_timing_aligned", index)
			end
		end
		if spec.cooldownAligned then
			local timingError = waitForAlignedPlate(handle)
			if timingError then
				return finish(handle, timingError)
			end
		else
			while os.clock() - cycle < spec.minimumCycleTime do
				local issue = live(handle)
				if issue then
					return finish(handle, issue)
				end
				task.wait(MOTION_TICK)
			end
			while handle.raceStartedAt ~= nil and os.clock() - handle.raceStartedAt < spec.raceMinimumTime do
				local issue = live(handle)
				if issue then
					return finish(handle, issue)
				end
				task.wait(MOTION_TICK)
			end
		end
		local target = block()
		if target == nil then
			return finish(handle, prefixed(spec, "winblock_unavailable", "workspace win block is unavailable"))
		end
		local value = wins()
		if value == nil then
			return finish(handle, prefixed(spec, "wins_unavailable", "Wins value is unavailable"))
		end
		local ok, before = pcall(function()
			return value.Value
		end)
		if not ok or type(before) ~= "number" then
			return finish(handle, prefixed(spec, "wins_unavailable", "Wins value is unavailable"))
		end
		handle.winsBefore = before
		handle.point = spec.blockPath[#spec.blockPath]
		local plateError = enterPlate(handle, target, value, before)
		if plateError then
			return finish(handle, plateError)
		end
		local afterOk, after = pcall(function()
			return value.Value
		end)
		if not afterOk or type(after) ~= "number" then
			return finish(handle, prefixed(spec, "wins_unavailable", "Wins value became unavailable"))
		end
		handle.winsAfter = after
		handle.reward = (after - before) % UINT32_RANGE
		lastRewardAtClock = os.clock()
		if
			not emit(
				handle,
				"reward",
				{ winsBefore = before, winsAfter = after, reward = handle.reward, elapsed = os.clock() - cycle }
			)
		then
			return finish(handle, prefixed(spec, "trace_write_failed", "reward could not be recorded"))
		end
		handle.point = "Spawn reset"
		local resetDeadline = os.clock() + SPAWN_TIMEOUT
		while os.clock() < resetDeadline do
			local issue = live(handle)
			if issue then
				return finish(handle, issue)
			end
			local here = position(root())
			if here and (here - SPAWN).Magnitude <= SPAWN_RADIUS then
				if not emit(handle, "spawn_returned", { elapsed = os.clock() - cycle }) then
					return finish(handle, prefixed(spec, "trace_write_failed", "spawn return could not be recorded"))
				end
				handle.complete = true
				handle.running = false
				handle.finishedAt = os.clock()
				handle.elapsed = handle.finishedAt - cycle
				if not clean(handle) then
					return finish(handle, prefixed(spec, "cleanup_failed", "could not clear flight state"))
				end
				return policy.snapshot(handle)
			end
			task.wait(MOTION_TICK)
		end
		return finish(handle, prefixed(spec, "spawn_timeout", "spawn reset was not observed"))
	end
	function policy.stop(handle: any): (boolean?, ErrorResult?)
		if handle == nil then
			return true
		end
		if type(handle) ~= "table" then
			return nil, prefixed(spec, "handle_invalid", "handle is invalid")
		end
		handle.stopped = true
		handle.running = false
		if not clean(handle) then
			return nil, prefixed(spec, "cleanup_failed", "cleanup failed")
		end
		return true
	end
	function policy.snapshot(handle: any): (any?, ErrorResult?)
		if type(handle) ~= "table" then
			return nil, prefixed(spec, "handle_invalid", "handle is invalid")
		end
		return table.freeze({
			id = handle.id,
			epoch = handle.epoch,
			startedAt = handle.startedAt,
			complete = handle.complete == true,
			stopped = handle.stopped == true,
			running = handle.running == true,
			point = handle.point,
			status = handle.status,
			pointsCompleted = handle.pointsCompleted,
			corrections = handle.corrections,
			reward = handle.reward,
			winsBefore = handle.winsBefore,
			winsAfter = handle.winsAfter,
			plateDwell = handle.plateDwell,
			localTouchObserved = handle.localTouchObserved == true,
			elapsed = handle.elapsed,
			failureCode = handle.failure and handle.failure.code or nil,
			finishedAt = handle.finishedAt,
		})
	end
	return table.freeze(policy)
end

return table.freeze(Route)
