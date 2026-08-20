--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MotionProbe = {}

local OWNER = "motion_probe"
local SAFE_START = Vector3.new(-1473.716797, -158.274429, -956.626160)
local SPAWN_MIN_Y = -300
local SPAWN_MAX_Y = -120
local SPAWN_MAX_Z = -900
local SPEED = 100
local MOTION_TICK = 1 / 30
local SAMPLE_LIMIT = 600
local REACHED_DISTANCE = 1
local CORRECTION_DISTANCE = 0.75
local SETTLE_TIME = 0.35

local VARIANTS = {
	{ name = "baseline", driver = "baseline" },
	{ name = "heartbeat_cframe", driver = "heartbeat_cframe" },
	{ name = "heartbeat_velocity", driver = "heartbeat_velocity" },
}

type ErrorResult = { code: string, message: string }
type Sample = {
	t: number,
	dt: number,
	expected: Vector3,
	actual: Vector3,
	commanded: Vector3,
	step: number,
	expectedStep: number,
	lateralError: number,
	longitudinalError: number,
	velocity: Vector3,
	forward: number,
}

local function errorResult(code: string, message: string): ErrorResult
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
local function identity(instance: any): string?
	if instance == nil then
		return nil
	end
	local ok, value = pcall(function()
		return instance:GetDebugId(0)
	end)
	if ok and type(value) == "string" and value ~= "" then
		return value
	end
	local addressOk, address = pcall(tostring, instance)
	if addressOk and type(address) == "string" then
		return address
	end
	return nil
end

local function currentCharacterIdentity(): string?
	local player = Players.LocalPlayer
	return identity(player and player.Character)
end

local function getHumanoid(): Humanoid?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	return nil
end

local function readPosition(root: BasePart): Vector3?
	local ok, position = pcall(function()
		return root.Position
	end)
	if ok and typeof(position) == "Vector3" then
		return position
	end
	return nil
end

local function writeVelocity(root: BasePart, velocity: Vector3): boolean
	return pcall(function()
		root.AssemblyLinearVelocity = velocity
		root.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function writeCFrame(root: BasePart, position: Vector3, rotation: CFrame): boolean
	return pcall(function()
		root.CFrame = CFrame.new(position) * rotation
	end)
end

local function settle(handle: any): boolean
	if handle.connection ~= nil then
		pcall(function()
			handle.connection:Disconnect()
		end)
		handle.connection = nil
	end
	if handle.renderConnection ~= nil then
		pcall(function()
			handle.renderConnection:Disconnect()
		end)
		handle.renderConnection = nil
	end
	local root = handle.ownedRoot
	if root ~= nil then
		writeVelocity(root, Vector3.zero)
	end
	local humanoid = handle.humanoid
	if humanoid ~= nil and handle.autoRotate ~= nil then
		pcall(function()
			humanoid.AutoRotate = handle.autoRotate
		end)
	end
	handle.humanoid = nil
	handle.autoRotate = nil
	handle.ownedRoot = nil
	return true
end

local function isCurrent(handle: any): boolean
	if handle.running ~= true then
		return false
	end
	local ok, active = pcall(handle.isActive)
	return ok and active == true
end

local function appendSample(samples: { Sample }, sample: Sample)
	if #samples < SAMPLE_LIMIT then
		table.insert(samples, sample)
	end
end

local function percentile(values: { number }, fraction: number): number
	if #values == 0 then
		return 0
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local index = math.clamp(math.ceil(#sorted * fraction), 1, #sorted)
	return sorted[index]
end

local function summarize(name: string, samples: { Sample }, startedAt: number, finalError: number): any
	local frameDeltas = {}
	local totalDelta = 0
	local totalStep = 0
	local totalStepSquared = 0
	local forwardFrames = 0
	local backwardSteps = 0
	local directionReversals = 0
	local maxBackwardStep = 0
	local maxLateralError = 0
	local maxDeviation = 0
	local maxFrameDelta = 0
	local stallsOver100ms = 0
	local lastSign = 0
	for _, sample in ipairs(samples) do
		table.insert(frameDeltas, sample.dt)
		totalDelta += sample.dt
		totalStep += sample.step
		totalStepSquared += sample.step * sample.step
		maxFrameDelta = math.max(maxFrameDelta, sample.dt)
		maxLateralError = math.max(maxLateralError, sample.lateralError)
		maxDeviation = math.max(maxDeviation, (sample.actual - sample.expected).Magnitude)
		if sample.dt > 0.1 then
			stallsOver100ms += 1
		end
		if sample.forward >= -0.001 then
			forwardFrames += 1
		else
			backwardSteps += 1
			maxBackwardStep = math.max(maxBackwardStep, -sample.forward)
		end
		local sign = if sample.forward > 0.001 then 1 elseif sample.forward < -0.001 then -1 else 0
		if sign ~= 0 then
			if lastSign ~= 0 and sign ~= lastSign then
				directionReversals += 1
			end
			lastSign = sign
		end
	end
	local count = #samples
	local meanStep = if count > 0 then totalStep / count else 0
	local variance = if count > 0 then math.max(totalStepSquared / count - meanStep * meanStep, 0) else 0
	return {
		variant = name,
		frameCount = count,
		duration = math.max(os.clock() - startedAt, 0),
		meanFrameDelta = if count > 0 then totalDelta / count else 0,
		p95FrameDelta = percentile(frameDeltas, 0.95),
		maxFrameDelta = maxFrameDelta,
		meanStep = meanStep,
		stepVariance = variance,
		forwardRatio = if count > 0 then forwardFrames / count else 0,
		backwardSteps = backwardSteps,
		directionReversals = directionReversals,
		maxBackwardStep = maxBackwardStep,
		maxLateralError = maxLateralError,
		maxDeviation = maxDeviation,
		stallsOver100ms = stallsOver100ms,
		finalError = finalError,
	}
end

local function runLeg(handle: any, driver: string, destination: Vector3): (any?, ErrorResult?)
	local root = getRoot()
	local startPosition = root and readPosition(root)
	if root == nil or startPosition == nil then
		return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
	end
	if currentCharacterIdentity() ~= handle.characterIdentity then
		return nil, errorResult("character_replaced", "Character changed during the motion probe")
	end
	local offset = destination - startPosition
	local distance = offset.Magnitude
	if distance <= REACHED_DISTANCE then
		return { samples = {}, finalError = distance }, nil
	end
	local direction = offset.Unit
	local duration = distance / SPEED
	local startedAt = os.clock()
	local deadline = startedAt + duration + 3
	local rotation = root.CFrame.Rotation
	handle.ownedRoot = root
	local samples = {}
	local lastObserved = startPosition
	local lastObservedAt = startedAt
	local expected = startPosition
	local commanded = startPosition
	local finished = false
	local failure: ErrorResult? = nil

	local function capture(actual: Vector3, sampleAt: number)
		local elapsed = math.clamp(sampleAt - startedAt, 0, duration)
		expected = startPosition:Lerp(destination, elapsed / duration)
		local delta = actual - lastObserved
		local forward = delta:Dot(direction)
		local lateral = delta - direction * forward
		local expectedOffset = actual - expected
		appendSample(samples, {
			t = sampleAt - startedAt,
			dt = math.max(sampleAt - lastObservedAt, 0),
			expected = expected,
			actual = actual,
			commanded = commanded,
			step = delta.Magnitude,
			expectedStep = SPEED * math.max(sampleAt - lastObservedAt, 0),
			lateralError = lateral.Magnitude,
			longitudinalError = expectedOffset:Dot(direction),
			velocity = root.AssemblyLinearVelocity,
			forward = forward,
		})
		lastObserved = actual
		lastObservedAt = sampleAt
	end
	handle.renderConnection = RunService.RenderStepped:Connect(function()
		if finished or failure ~= nil or not isCurrent(handle) then
			return
		end
		local actual = readPosition(root)
		if actual == nil then
			failure = errorResult("movement_read_failed", "Motion probe could not read HumanoidRootPart")
			return
		end
		capture(actual, os.clock())
	end)

	if driver == "baseline" then
		while isCurrent(handle) and os.clock() < deadline do
			local sampleAt = os.clock()
			local elapsed = math.clamp(sampleAt - startedAt, 0, duration)
			commanded = startPosition:Lerp(destination, elapsed / duration)
			if not writeVelocity(root, Vector3.zero) or not writeCFrame(root, commanded, CFrame.identity) then
				failure = errorResult("movement_write_failed", "Baseline motion probe write failed")
				break
			end
			if elapsed >= duration then
				finished = true
				break
			end
			task.wait(MOTION_TICK)
		end
	else
		local humanoid = getHumanoid()
		if humanoid ~= nil then
			handle.humanoid = humanoid
			local readOk, autoRotate = pcall(function()
				return humanoid.AutoRotate
			end)
			if readOk then
				handle.autoRotate = autoRotate
				pcall(function()
					humanoid.AutoRotate = false
				end)
			end
		end
		handle.ownedRoot = root
		if driver == "heartbeat_cframe" then
			writeVelocity(root, Vector3.zero)
		else
			writeVelocity(root, direction * SPEED)
		end
		handle.connection = RunService.Heartbeat:Connect(function()
			if finished or failure ~= nil or not isCurrent(handle) then
				return
			end
			local sampleAt = os.clock()
			local actual = readPosition(root)
			if actual == nil then
				failure = errorResult("movement_read_failed", "Motion probe could not read HumanoidRootPart")
				return
			end
			local elapsed = math.clamp(sampleAt - startedAt, 0, duration)
			expected = startPosition:Lerp(destination, elapsed / duration)
			if driver == "heartbeat_cframe" then
				commanded = expected
				if not writeCFrame(root, commanded, rotation) then
					failure = errorResult("movement_write_failed", "Heartbeat CFrame probe write failed")
					return
				end
			else
				commanded = actual
				if (actual - expected).Magnitude > CORRECTION_DISTANCE then
					commanded = expected
					if not writeCFrame(root, commanded, rotation) then
						failure = errorResult("movement_write_failed", "Heartbeat velocity correction failed")
						return
					end
				end
				if not writeVelocity(root, direction * SPEED) then
					failure = errorResult("movement_write_failed", "Heartbeat velocity probe write failed")
					return
				end
			end
			if elapsed >= duration then
				finished = true
			end
		end)
		while isCurrent(handle) and not finished and failure == nil and os.clock() < deadline do
			task.wait(0.01)
		end
		if handle.connection ~= nil then
			handle.connection:Disconnect()
			handle.connection = nil
		end
	end
	if handle.renderConnection ~= nil then
		handle.renderConnection:Disconnect()
		handle.renderConnection = nil
	end

	if not isCurrent(handle) then
		return nil, errorResult("cancelled", "Motion probe was cancelled")
	end
	if failure ~= nil then
		return nil, failure
	end
	if not finished then
		return nil, errorResult("movement_timeout", "Motion probe leg exceeded its deadline")
	end
	if not writeCFrame(root, destination, rotation) then
		return nil, errorResult("movement_write_failed", "Motion probe final position write failed")
	end
	writeVelocity(root, Vector3.zero)
	task.wait(SETTLE_TIME)
	local finalPosition = readPosition(root)
	if finalPosition == nil then
		return nil, errorResult("movement_read_failed", "Motion probe final position is unavailable")
	end
	return { samples = samples, finalError = (finalPosition - destination).Magnitude }, nil
end

function MotionProbe.newSession(sessionId: any, isActive: any): (any?, ErrorResult?)
	if type(sessionId) ~= "string" or sessionId == "" or type(isActive) ~= "function" then
		return nil, errorResult("motion_probe_handle_invalid", "Motion probe session inputs are invalid")
	end
	local root = getRoot()
	local position = root and readPosition(root)
	if root == nil or position == nil then
		return nil, errorResult("character_unavailable", "HumanoidRootPart is unavailable")
	end
	if not (position.Y > SPAWN_MIN_Y and position.Y < SPAWN_MAX_Y and position.Z < SPAWN_MAX_Z) then
		return nil, errorResult("motion_probe_start_invalid", "Motion probe must start inside World 3 spawn bounds")
	end
	return {
		owner = OWNER,
		sessionId = sessionId,
		isActive = isActive,
		running = true,
		characterIdentity = currentCharacterIdentity(),
		startPosition = position,
		variant = nil,
		variantsCompleted = 0,
		results = {},
		connection = nil,
		renderConnection = nil,
		ownedRoot = nil,
		humanoid = nil,
		autoRotate = nil,
	},
		nil
end

function MotionProbe.run(handle: any): (any?, ErrorResult?)
	if type(handle) ~= "table" or handle.owner ~= OWNER or handle.running ~= true then
		return nil, errorResult("motion_probe_handle_invalid", "Motion probe handle is invalid")
	end
	for _, variant in ipairs(VARIANTS) do
		if not isCurrent(handle) then
			return nil, errorResult("cancelled", "Motion probe was cancelled")
		end
		handle.variant = variant.name
		local variantStartedAt = os.clock()
		local outbound, outboundError = runLeg(handle, variant.driver, SAFE_START)
		if outbound == nil then
			settle(handle)
			return nil, outboundError
		end
		settle(handle)
		local inbound, inboundError = runLeg(handle, variant.driver, handle.startPosition)
		settle(handle)
		if inbound == nil then
			return nil, inboundError
		end
		local samples = {}
		for _, sample in ipairs(outbound.samples) do
			table.insert(samples, sample)
		end
		for _, sample in ipairs(inbound.samples) do
			if #samples < SAMPLE_LIMIT then
				table.insert(samples, sample)
			end
		end
		local summary =
			summarize(variant.name, samples, variantStartedAt, math.max(outbound.finalError, inbound.finalError))
		table.insert(handle.results, summary)
		handle.variantsCompleted += 1
		task.wait(SETTLE_TIME)
	end
	handle.variant = nil
	return { variants = table.clone(handle.results), variantsCompleted = handle.variantsCompleted }, nil
end

function MotionProbe.snapshot(handle: any): any
	if type(handle) ~= "table" or handle.owner ~= OWNER then
		return nil
	end
	return {
		variant = handle.variant,
		variantsCompleted = handle.variantsCompleted,
		results = table.clone(handle.results),
		running = handle.running == true,
	}
end

function MotionProbe.stop(handle: any): (boolean?, ErrorResult?)
	if handle == nil then
		return true, nil
	end
	if type(handle) ~= "table" or handle.owner ~= OWNER then
		return nil, errorResult("motion_probe_handle_invalid", "Motion probe handle is invalid")
	end
	handle.running = false
	settle(handle)
	return true, nil
end

return table.freeze(MotionProbe)
