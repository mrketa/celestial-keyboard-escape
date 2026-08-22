--!strict

local Runtime = {}
Runtime.__index = Runtime

local VERSION = "0.0.7-stage1-pulse"
local STAGE1_PULSE_START_DELAY = 2.85
local STAGE1_PULSE_REWARD_TIMEOUT = 1.25
local STAGE1_PULSE_SPAWN_TIMEOUT = 1
local STAGE1_PULSE_POLL_TICK = 0.01
local STAGE1_ACQUISITION_TIMEOUT = 0.5

local DIRECT_EJECT_REASONS = {
	reload = true,
	ui_eject = true,
	external_eject = true,
	init_failed = true,
}

local COMMAND_REASONS = {
	stop = {
		ui_stop = true,
		external_stop = true,
	},
	eject = {
		ui_eject = true,
		external_eject = true,
	},
}

local CHARACTER_STATES = {
	READY = true,
	RESPAWNING = true,
	DEAD = true,
	MISSING = true,
}

local OBSERVATION_CHARACTER_STATES = {
	READY = true,
	RESPAWNING = true,
	DEAD = true,
	MISSING = true,
}
local OBSERVATION_WINS_STATES = {
	READY = true,
	LEADERSTATS_MISSING = true,
	WINS_MISSING = true,
	WINS_INVALID = true,
}
local OBSERVATION_WINBLOCK_STATES = {
	READY = true,
	STRUCTURE_MISSING = true,
	STAGE1_MISSING = true,
	SAS_MISSING = true,
	WINBLOCK32_MISSING = true,
	WINBLOCK32_WRONG_CLASS = true,
	PROPERTY_READ_FAILED = true,
}

local OBSERVATION_SPAWN_MIN_Y = -300
local OBSERVATION_SPAWN_MAX_Y = -120
local OBSERVATION_SPAWN_MAX_Z = -900
local OBSERVATION_WINBLOCK_PATH = "Workspace.Structure.Stage1.SAS.WinBlock32"

local function now(): number
	return os.time()
end

local function sanitizedText(value: any, fallback: string): string
	if type(value) ~= "string" then
		return fallback
	end

	local text = value
	text = string.gsub(text, "%c", " ")
	text = string.gsub(text, "[%a]:[\\/][^%s]+", "<path>")
	text = string.gsub(text, "\\\\[^%s]+", "<path>")
	text = string.gsub(text, "^/[^%s]+", "<path>")
	text = string.gsub(text, "%s/[^%s]+", " <path>")
	text = string.gsub(text, "[Jj]ob[Ii][Dd]%s*[:=]?%s*[%w%-_]+", "jobId=<redacted>")
	text = string.gsub(text, "[Pp]lace[Ii][Dd]%s*[:=]?%s*%d+", "placeId=<redacted>")
	text = string.gsub(text, "[Uu]ser[Ii][Dd]%s*[:=]?%s*%d+", "userId=<redacted>")
	text = string.gsub(text, "[Bb]earer%s+[%w%-%._~%+/%=]+", "<redacted>")
	text = string.gsub(text, "[%w%._%-%+]+@[%w%._%-]+", "<redacted>")
	if #text > 240 then
		text = string.sub(text, 1, 240)
	end
	if text == "" then
		return fallback
	end
	return text
end

local function errorResult(code: string, message: any): { code: string, message: string }
	return {
		code = code,
		message = sanitizedText(message, "runtime operation failed"),
	}
end

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validVectorSnapshot(value: any): boolean
	return type(value) == "table" and finiteNumber(value.x) and finiteNumber(value.y) and finiteNumber(value.z)
end

local function validObservation(value: any): boolean
	if type(value) ~= "table" or value.schemaVersion ~= 1 or not finiteNumber(value.capturedAt) then
		return false
	end
	if value.capturedAt < 0 or value.capturedAt ~= math.floor(value.capturedAt) then
		return false
	end
	if
		type(value.place) ~= "table"
		or not finiteNumber(value.place.id)
		or value.place.id < 0
		or value.place.id ~= math.floor(value.place.id)
		or type(value.place.supported) ~= "boolean"
	then
		return false
	end
	if
		type(value.character) ~= "table"
		or not OBSERVATION_CHARACTER_STATES[value.character.state]
		or type(value.character.present) ~= "boolean"
		or type(value.character.humanoidPresent) ~= "boolean"
	then
		return false
	end
	if value.character.health ~= nil and not finiteNumber(value.character.health) then
		return false
	end
	if value.character.maxHealth ~= nil and not finiteNumber(value.character.maxHealth) then
		return false
	end
	if
		type(value.root) ~= "table"
		or type(value.root.present) ~= "boolean"
		or type(value.root.anchored) ~= "boolean"
	then
		return false
	end
	if value.root.present ~= (value.root.position ~= nil) then
		return false
	end
	if value.root.position ~= nil and not validVectorSnapshot(value.root.position) then
		return false
	end
	if value.root.velocity ~= nil and not validVectorSnapshot(value.root.velocity) then
		return false
	end
	if
		type(value.spawn) ~= "table"
		or type(value.spawn.inBounds) ~= "boolean"
		or type(value.spawn.bounds) ~= "table"
		or value.spawn.bounds.minYExclusive ~= OBSERVATION_SPAWN_MIN_Y
		or value.spawn.bounds.maxYExclusive ~= OBSERVATION_SPAWN_MAX_Y
		or value.spawn.bounds.maxZExclusive ~= OBSERVATION_SPAWN_MAX_Z
	then
		return false
	end
	if
		type(value.wins) ~= "table"
		or not OBSERVATION_WINS_STATES[value.wins.state]
		or type(value.wins.available) ~= "boolean"
		or value.wins.available ~= (value.wins.state == "READY")
	then
		return false
	end
	if
		value.wins.value ~= nil
		and (not finiteNumber(value.wins.value) or value.wins.value ~= math.floor(value.wins.value))
	then
		return false
	end
	if value.wins.available ~= (value.wins.value ~= nil) then
		return false
	end
	if
		type(value.winBlock32) ~= "table"
		or not OBSERVATION_WINBLOCK_STATES[value.winBlock32.state]
		or type(value.winBlock32.available) ~= "boolean"
		or value.winBlock32.available ~= (value.winBlock32.state == "READY")
		or value.winBlock32.path ~= OBSERVATION_WINBLOCK_PATH
	then
		return false
	end
	if value.winBlock32.position ~= nil and not validVectorSnapshot(value.winBlock32.position) then
		return false
	end
	if value.winBlock32.size ~= nil and not validVectorSnapshot(value.winBlock32.size) then
		return false
	end
	if value.winBlock32.canCollide ~= nil and type(value.winBlock32.canCollide) ~= "boolean" then
		return false
	end
	return not value.winBlock32.available
		or (
			value.winBlock32.position ~= nil
			and value.winBlock32.size ~= nil
			and type(value.winBlock32.canCollide) == "boolean"
		)
end
local EVENT_KINDS = {
	summer = true,
	battle = true,
	egg = true,
	disco = true,
	soccer = true,
	rings = true,
	masked = true,
	overdrive = true,
	fab = true,
	survival = true,
}

local function validCollectorConfig(config: any): boolean
	if type(config) ~= "table" or type(config.summerOnlyStorm) ~= "boolean" or type(config.retry) ~= "table" then
		return false
	end
	for kind in pairs(EVENT_KINDS) do
		local retry = config.retry[kind]
		if type(config[kind]) ~= "boolean" or not finiteNumber(retry) or retry < 0.5 or retry > 10 then
			return false
		end
	end
	for key in pairs(config) do
		if key ~= "summerOnlyStorm" and key ~= "retry" and not EVENT_KINDS[key] then
			return false
		end
	end
	for key in pairs(config.retry) do
		if not EVENT_KINDS[key] then
			return false
		end
	end
	return true
end

local function collectorEnabledSummary(config: any): string
	local enabled = {}
	for _, kind in ipairs({
		"summer",
		"battle",
		"egg",
		"disco",
		"soccer",
		"rings",
		"masked",
		"overdrive",
		"fab",
		"survival",
	}) do
		if type(config) == "table" and config[kind] == true then
			enabled[#enabled + 1] = kind
		end
	end
	return #enabled > 0 and table.concat(enabled, ",") or "none"
end

local function deepCopy(value: any, seen: { [table]: any }?): any
	if type(value) ~= "table" then
		return value
	end

	local visited = seen or {}
	if visited[value] ~= nil then
		return nil
	end
	visited[value] = true

	local copy = {}
	for key, item in pairs(value) do
		local keyType = type(key)
		if
			(keyType == "string" or keyType == "number")
			and type(item) ~= "function"
			and type(item) ~= "userdata"
			and type(item) ~= "thread"
		then
			copy[key] = deepCopy(item, visited)
		end
	end
	visited[value] = nil
	return copy
end

local function fileBasename(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	return string.gsub(value, "^.*[\\/]", "")
end

function Runtime.new(options: any): (any, any)
	if type(options) ~= "table" then
		return nil, errorResult("runtime_init_invalid", "runtime options are required")
	end
	if
		not finiteNumber(options.generation)
		or options.generation < 0
		or options.generation ~= math.floor(options.generation)
	then
		return nil, errorResult("runtime_init_invalid", "runtime generation must be a non-negative integer")
	end
	if options.destroyMenu ~= nil and type(options.destroyMenu) ~= "function" then
		return nil, errorResult("runtime_init_invalid", "menu cleanup must be callable")
	end
	if options.menuStats ~= nil and type(options.menuStats) ~= "function" then
		return nil, errorResult("runtime_init_invalid", "menu statistics must be callable")
	end
	if options.characterStateResolver ~= nil and type(options.characterStateResolver) ~= "function" then
		return nil, errorResult("runtime_init_invalid", "character state resolver must be callable")
	end
	if
		type(options.stage1) ~= "table"
		or type(options.stage1.newSession) ~= "function"
		or type(options.stage1.snapshot) ~= "function"
		or type(options.stage1.beginHold) ~= "function"
		or type(options.stage1.pollHold) ~= "function"
		or type(options.stage1.stopHold) ~= "function"
		or type(options.stage1.releaseHold) ~= "function"
		or type(options.stage1.atSpawn) ~= "function"
		or type(options.stage1.atPulseStart) ~= "function"
	then
		return nil, errorResult("runtime_init_invalid", "stage1 policy is required")
	end
	if type(options.courses) ~= "table" then
		return nil, errorResult("runtime_init_invalid", "course policies are required")
	end
	for _, stageKey in { "stage2", "stage3", "stage4", "stage5", "stage6", "stage7", "stage8", "stage9" } do
		local policy = options.courses[stageKey]
		if
			type(policy) ~= "table"
			or type(policy.newSession) ~= "function"
			or type(policy.run) ~= "function"
			or type(policy.stop) ~= "function"
			or type(policy.snapshot) ~= "function"
		then
			return nil, errorResult("runtime_init_invalid", string.format("%s policy is required", stageKey))
		end
	end
	for key in pairs(options.courses) do
		if
			key ~= "stage2"
			and key ~= "stage3"
			and key ~= "stage4"
			and key ~= "stage5"
			and key ~= "stage6"
			and key ~= "stage7"
			and key ~= "stage8"
			and key ~= "stage9"
		then
			return nil, errorResult("runtime_init_invalid", "course policies may only define stages 2 through 9")
		end
	end
	if
		type(options.stage5Diagnostics) ~= "table"
		or type(options.stage5Diagnostics.newSession) ~= "function"
		or type(options.stage5Diagnostics.start) ~= "function"
		or type(options.stage5Diagnostics.sample) ~= "function"
		or type(options.stage5Diagnostics.motion) ~= "function"
		or type(options.stage5Diagnostics.stop) ~= "function"
	then
		return nil, errorResult("runtime_init_invalid", "stage5 diagnostics policy is required")
	end
	if
		type(options.motionProbe) ~= "table"
		or type(options.motionProbe.newSession) ~= "function"
		or type(options.motionProbe.run) ~= "function"
		or type(options.motionProbe.stop) ~= "function"
		or type(options.motionProbe.snapshot) ~= "function"
	then
		return nil, errorResult("runtime_init_invalid", "motion probe policy is required")
	end
	if
		type(options.eventCollectors) ~= "table"
		or type(options.eventCollectors.newSession) ~= "function"
		or type(options.eventCollectors.run) ~= "function"
		or type(options.eventCollectors.configure) ~= "function"
		or type(options.eventCollectors.stop) ~= "function"
		or type(options.eventCollectors.snapshot) ~= "function"
	then
		return nil, errorResult("runtime_init_invalid", "event collector policy is required")
	end
	if
		type(options.movement) ~= "table"
		or type(options.movement.newSafeStart) ~= "function"
		or type(options.movement.snapshot) ~= "function"
		or type(options.movement.runSafeStart) ~= "function"
		or type(options.movement.stop) ~= "function"
	then
		return nil, errorResult("runtime_init_invalid", "movement policy is required")
	end
	if type(options.observation) ~= "table" or type(options.observation.capture) ~= "function" then
		return nil, errorResult("runtime_init_invalid", "observation policy is required")
	end
	if type(options.exportIdentity) ~= "function" then
		return nil, errorResult("runtime_init_invalid", "export identity resolver must be callable")
	end

	local executorName: string? = nil
	local executorVersion: string? = nil
	if type(options.executorName) == "string" then
		executorName = sanitizedText(options.executorName, "executor")
	end
	if type(options.executorVersion) == "string" then
		executorVersion = sanitizedText(options.executorVersion, "version")
	end
	if executorName == nil and executorVersion == nil then
		local identified, name, version = pcall(identifyexecutor)
		if identified then
			if type(name) == "string" then
				executorName = sanitizedText(name, "executor")
			end
			if type(version) == "string" then
				executorVersion = sanitizedText(version, "version")
			end
		end
	end

	local createdAt = now()
	local runtimeVersion = type(options.version) == "string" and sanitizedText(options.version, VERSION) or VERSION
	local self = setmetatable({
		version = runtimeVersion,
		generation = options.generation,
		state = "idle",
		epoch = 1,
		startedAt = createdAt,
		updatedAt = createdAt,
		placeSupported = options.placeSupported == true,
		characterState = CHARACTER_STATES[options.characterState] and options.characterState or "MISSING",
		characterStateResolver = options.characterStateResolver,
		exportIdentity = options.exportIdentity,
		trace = options.trace,
		traceInitError = options.traceInitError,
		traceFileName = fileBasename(options.traceFileName),
		executorName = executorName,
		executorVersion = executorVersion,
		destroyMenu = options.destroyMenu,
		menuStats = options.menuStats,
		stage1 = options.stage1,
		observation = options.observation,
		movement = options.movement,
		courses = options.courses,
		stage5Diagnostics = options.stage5Diagnostics,
		motionProbe = options.motionProbe,
		eventCollectors = options.eventCollectors,
		lastObservation = nil,
		session = nil,
		stage1Handle = nil,
		stage1Acquisition = nil,
		courseSession = nil,
		courseHandle = nil,
		coursePolicy = nil,
		courseKey = nil,
		lastCourseKey = nil,
		motionProbeSession = nil,
		collectorConfig = nil,
		motionProbeHandle = nil,
		collectorSession = nil,
		collectorHandle = nil,
		collectorTask = nil,
		collectorStats = {
			status = "idle",
			config = nil,
			counts = {},
			total = 0,
			current = nil,
			variant = nil,
			safety = nil,
			atHome = nil,
			lastError = nil,
		},
		lastStage1RewardClock = nil,
		movementSession = nil,
		movementHandle = nil,
		stage1Stats = {
			status = "idle",
			rewards = 0,
			earned = 0,
			lastReward = 0,
			lastRewardAt = nil,
			lastError = nil,
		},
		stage2Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage3Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage4Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage5Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage6Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage7Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage8Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		stage9Stats = {
			status = "idle",
			point = nil,
			pointsCompleted = 0,
			corrections = 0,
			reward = 0,
			earned = 0,
			lastError = nil,
		},
		motionProbeStats = {
			status = "idle",
			variant = nil,
			variantsCompleted = 0,
			results = {},
			lastError = nil,
		},
		movementStats = {
			status = "idle",
			initialDistance = nil,
			activeElapsed = 0,
			finalError = nil,
			lastError = nil,
		},
		lastCommand = nil,
		lastEvent = nil,
		lastError = nil,
		cleanupErrors = {},
	}, Runtime)

	if self.trace ~= nil then
		local ok, status = pcall(function()
			return self.trace:status()
		end)
		if ok and type(status) == "table" then
			self.traceFileName = fileBasename(status.fileName or status.path) ~= ""
					and fileBasename(status.fileName or status.path)
				or self.traceFileName
		end
	end
	if self.traceInitError ~= nil then
		local traceMessage = type(self.traceInitError) == "table" and self.traceInitError.message or self.traceInitError
		self.lastError = {
			code = "trace_create_failed",
			message = sanitizedText(traceMessage, "trace unavailable"),
			at = createdAt,
		}
	end

	self:_record("runtime_created", {
		generation = self.generation,
		version = self.version,
	})
	local observed, _, observationError = self:observe()
	if not observed then
		return nil, observationError
	end
	return self
end

function Runtime:_setError(code: string, message: any)
	self.lastError = {
		code = code,
		message = sanitizedText(message, "runtime operation failed"),
		at = now(),
	}
	self.updatedAt = self.lastError.at
end

function Runtime:_record(kind: string, fields: any): boolean
	self.lastEvent = {
		code = kind,
		at = now(),
	}
	self.updatedAt = self.lastEvent.at
	if self.trace == nil then
		return false
	end

	local ok, recorded, traceError = pcall(function()
		return self.trace:record(kind, fields)
	end)
	if not ok or recorded ~= true then
		local message = not ok and recorded
			or (type(traceError) == "table" and traceError.message or "trace write failed")
		self:_setError("trace_write_failed", message)
		return false
	end
	return true
end

function Runtime:_recordRequired(kind: string, fields: any): boolean
	if self.trace == nil or type(self.trace.recordRequired) ~= "function" then
		self:_setError("trace_write_failed", "required trace writer is unavailable")
		return false
	end
	local ok, recorded, traceError = pcall(function()
		return self.trace:recordRequired(kind, fields)
	end)
	if not ok or recorded ~= true then
		local message = not ok and recorded
			or (type(traceError) == "table" and traceError.message or "required trace write failed")
		self:_setError("trace_write_failed", message)
		return false
	end
	self.lastEvent = {
		code = kind,
		at = now(),
	}
	self.updatedAt = self.lastEvent.at
	return true
end

function Runtime:_traceState(): string
	if self.traceInitError ~= nil or self.trace == nil then
		return "ERROR"
	end
	local ok, status = pcall(function()
		return self.trace:status()
	end)
	if not ok or type(status) ~= "table" or status.state == "ERROR" then
		return "ERROR"
	end
	return "READY"
end

function Runtime:_activeConnections(): number
	if self.menuStats == nil then
		return 0
	end
	local ok, stats = pcall(self.menuStats)
	if ok and type(stats) == "table" and type(stats.connections) == "number" and stats.connections >= 0 then
		return math.floor(stats.connections)
	end
	return 0
end

function Runtime:_characterState(): string
	if self.characterStateResolver == nil then
		return self.characterState
	end
	local ok, state = pcall(self.characterStateResolver)
	if ok and CHARACTER_STATES[state] then
		self.characterState = state
	end
	return self.characterState
end

function Runtime:_exportIdentity(): any
	local ok, identity = pcall(self.exportIdentity)
	if ok then
		return identity
	end
	return nil
end

function Runtime:_exportEnvironment(): (any, any)
	local ok, environment = pcall(getgenv)
	if not ok or type(environment) ~= "table" then
		return nil, errorResult("export_clear_failed", "runtime export environment is unavailable")
	end
	return environment
end

function Runtime:_clearExport(environment: any): (boolean?, any)
	local cleared = pcall(function()
		if environment.PotassiumNextRuntime == self:_exportIdentity() then
			environment.PotassiumNextRuntime = nil
		end
	end)
	if not cleared then
		return nil, errorResult("export_clear_failed", "runtime export could not be cleared")
	end
	return true
end

function Runtime:snapshot(): any
	local exportEnvironment = self:_exportEnvironment()
	local exportIdentity = self:_exportIdentity()
	local session = nil
	if self.collectorSession ~= nil then
		session = deepCopy(self.collectorSession)
	elseif self.motionProbeSession ~= nil then
		session = deepCopy(self.motionProbeSession)
	elseif self.courseSession ~= nil then
		session = deepCopy(self.courseSession)
	elseif self.movementSession ~= nil then
		session = deepCopy(self.movementSession)
	elseif self.session ~= nil then
		local copied = self.stage1.snapshot(self.session)
		if type(copied) == "table" then
			session = deepCopy(copied)
		end
	end
	local stage1Stats = deepCopy(self.stage1Stats)
	local holdActive = self.stage1Handle ~= nil
	local completedCorrections = type(stage1Stats.corrections) == "number" and stage1Stats.corrections or 0
	local activeCorrections = holdActive
			and self.stage1Handle.correctionsAccounted ~= true
			and type(self.stage1Handle.corrections) == "number"
			and self.stage1Handle.corrections
		or 0
	stage1Stats.corrections = completedCorrections + activeCorrections
	if type(stage1Stats.nextRunAtClock) == "number" then
		stage1Stats.nextRunIn = math.max(stage1Stats.nextRunAtClock - os.clock(), 0)
		stage1Stats.nextRunAtClock = nil
	end
	local stage1Connections = 0
	if holdActive then
		if self.stage1Handle.connection ~= nil then
			stage1Connections += 1
		end
		if self.stage1Handle.rewardConnection ~= nil then
			stage1Connections += 1
		end
	end
	local movementStats = deepCopy(self.movementStats)
	local movementActive = self.movementHandle ~= nil
	if movementActive then
		local copied = self.movement.snapshot(self.movementHandle)
		if type(copied) == "table" then
			movementStats.initialDistance = copied.initialDistance
			movementStats.activeElapsed = copied.activeElapsed
			movementStats.finalError = copied.finalError
		end
	end
	local courseStats = {
		stage2 = deepCopy(self.stage2Stats),
		stage3 = deepCopy(self.stage3Stats),
		stage4 = deepCopy(self.stage4Stats),
		stage5 = deepCopy(self.stage5Stats),
		stage6 = deepCopy(self.stage6Stats),
		stage7 = deepCopy(self.stage7Stats),
		stage8 = deepCopy(self.stage8Stats),
		stage9 = deepCopy(self.stage9Stats),
	}
	local courseActive = self.courseHandle ~= nil
	local courseConnections = 0
	if courseActive then
		local activeStats = courseStats[self.courseKey]
		local copied = self.coursePolicy.snapshot(self.courseHandle)
		if type(copied) == "table" and activeStats ~= nil then
			activeStats.point = copied.point
			activeStats.pointsCompleted = copied.pointsCompleted
			activeStats.corrections = copied.corrections
			activeStats.elapsed = copied.elapsed
		end
		if self.courseHandle.motionConnection ~= nil then
			courseConnections += 1
		end
		if
			type(self.courseHandle.diagnostics) == "table"
			and type(self.courseHandle.diagnostics.connections) == "table"
		then
			courseConnections += #self.courseHandle.diagnostics.connections
		end
	end
	local motionProbeStats = deepCopy(self.motionProbeStats)
	local motionProbeActive = self.motionProbeHandle ~= nil
	local motionProbeConnections = 0
	if motionProbeActive then
		local copied = self.motionProbe.snapshot(self.motionProbeHandle)
		if type(copied) == "table" then
			motionProbeStats.variant = copied.variant
			motionProbeStats.variantsCompleted = copied.variantsCompleted
			motionProbeStats.results = deepCopy(copied.results)
		end
		if self.motionProbeHandle.connection ~= nil then
			motionProbeConnections += 1
		end
		if self.motionProbeHandle.renderConnection ~= nil then
			motionProbeConnections += 1
		end
	end
	local collectorStats = deepCopy(self.collectorStats)
	local collectorActive = self.collectorHandle ~= nil or self.collectorTask ~= nil
	if self.collectorHandle ~= nil then
		local copied = self.eventCollectors.snapshot(self.collectorHandle)
		if type(copied) == "table" then
			collectorStats = copied
		end
	end
	collectorStats.config = deepCopy(self.collectorConfig)
	local snapshot = {
		version = self.version,
		generation = self.generation,
		state = self.state,
		owner = session and session.owner or nil,
		session = session,
		lastCourse = self.lastCourseKey,
		epoch = self.epoch,
		startedAt = self.startedAt,
		updatedAt = self.updatedAt,
		placeSupported = self.placeSupported,
		characterState = self:_characterState(),
		traceState = self:_traceState(),
		traceFileName = self.traceFileName,
		executorName = self.executorName,
		executorVersion = self.executorVersion,
		lastCommand = deepCopy(self.lastCommand),
		lastEvent = deepCopy(self.lastEvent),
		lastError = deepCopy(self.lastError),
		activeConnections = self:_activeConnections() + stage1Connections + courseConnections + motionProbeConnections,
		lastObservation = deepCopy(self.lastObservation),
		stage1 = stage1Stats,
		stage2 = courseStats.stage2,
		stage3 = courseStats.stage3,
		stage4 = courseStats.stage4,
		stage5 = courseStats.stage5,
		stage6 = courseStats.stage6,
		stage7 = courseStats.stage7,
		stage8 = courseStats.stage8,
		stage9 = courseStats.stage9,
		motionProbe = motionProbeStats,
		events = collectorStats,
		movement = movementStats,
		activeTasks = ((self.session ~= nil or self.stage1Acquisition ~= nil) and 1 or 0)
			+ (movementActive and 1 or 0)
			+ (courseActive and 1 or 0)
			+ (motionProbeActive and 1 or 0)
			+ (collectorActive and 1 or 0),
		inputCaptured = false,
		exportOwned = type(exportEnvironment) == "table"
			and exportIdentity ~= nil
			and exportEnvironment.PotassiumNextRuntime == exportIdentity,
	}
	return snapshot
end
function Runtime:alive(epoch: any): boolean
	return self.state == "idle" and epoch == self.epoch
end

function Runtime:_validatePayload(name: string, payload: any): (boolean, any)
	if payload == nil then
		return true, nil
	end
	if type(payload) ~= "table" then
		return false, errorResult("command_invalid", "command payload must be a reason table")
	end
	local reason = payload.reason
	if type(reason) ~= "string" or not COMMAND_REASONS[name][reason] then
		return false, errorResult("command_invalid", "command reason is not allowed")
	end
	for key in pairs(payload) do
		if key ~= "reason" then
			return false, errorResult("command_invalid", "command payload contains an unsupported field")
		end
	end
	return true, reason
end
function Runtime:observe(): (boolean?, any, any)
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end

	local callOk, observation, captureError = pcall(function()
		return self.observation.capture()
	end)
	if not callOk or observation == nil then
		local message = not callOk and observation
			or (type(captureError) == "table" and captureError.message or "observation capture failed")
		self:_record("observation_failed", {
			code = type(captureError) == "table" and captureError.code or "observation_unavailable",
			message = message,
		})
		return nil, nil, errorResult("observation_unavailable", message)
	end
	if not validObservation(observation) or observation.place.supported ~= self.placeSupported then
		self:_record("observation_failed", {
			code = "observation_invalid_snapshot",
			message = "observation snapshot is invalid",
		})
		return nil, nil, errorResult("observation_invalid_snapshot", "observation snapshot is invalid")
	end

	if
		not self:_recordRequired("observation_captured", {
			schemaVersion = observation.schemaVersion,
			capturedAt = observation.capturedAt,
			placeSupported = observation.place.supported,
			characterState = observation.character.state,
			rootPresent = observation.root.present,
			atSpawn = observation.spawn.inBounds,
			winsState = observation.wins.state,
			winsAvailable = observation.wins.available,
			winBlock32State = observation.winBlock32.state,
			winBlock32Available = observation.winBlock32.available,
		})
	then
		return nil, nil, errorResult("trace_write_failed", "observation could not be recorded")
	end

	self.characterState = observation.character.state
	self.lastObservation = deepCopy(observation)
	self.updatedAt = now()
	return true, deepCopy(self.lastObservation), nil
end

function Runtime:_stopMovement(handle: any): (boolean?, any)
	local callOk, stopped, stopError = pcall(self.movement.stop, handle)
	if callOk and stopped == true then
		if self.movementHandle == handle then
			self.movementHandle = nil
		end
		return true
	end
	local detail = callOk and stopError or stopped
	local code = type(detail) == "table" and detail.code or "movement_stop_failed"
	local message = sanitizedText(type(detail) == "table" and detail.message or detail, "movement cleanup failed")
	self.movementHandle = handle
	self.movementStats.status = "error"
	self.movementStats.lastError = code
	self.state = "error"
	self:_setError(code, message)
	return nil, errorResult(code, message)
end

function Runtime:startSafeStart(): (boolean?, any, any)
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if
		self.session ~= nil
		or self.stage1Handle ~= nil
		or self.stage1Acquisition ~= nil
		or self.movementSession ~= nil
		or self.movementHandle ~= nil
		or self.courseSession ~= nil
		or self.courseHandle ~= nil
		or self.motionProbeSession ~= nil
		or self.motionProbeHandle ~= nil
		or self.collectorSession ~= nil
		or self.collectorHandle ~= nil
	then
		return nil, self:snapshot(), errorResult("session_active", "a movement owner or cleanup is already active")
	end
	if not self.placeSupported then
		return nil, nil, errorResult("place_unsupported", "current place is not supported")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end

	self.epoch += 1
	self.updatedAt = now()
	local epoch = self.epoch
	local sessionId = string.format("movement-%d-%d", self.generation, epoch)
	local session = {
		id = sessionId,
		owner = "movement",
		phase = "safe_start",
		epoch = epoch,
		startedAt = now(),
	}
	self.movementSession = session
	local handle, handleError = self.movement.newSafeStart(function()
		return self:alive(epoch) and self.movementSession == session
	end)
	if handle == nil then
		self.movementSession = nil
		self.epoch += 1
		return nil, nil, handleError
	end
	self.movementHandle = handle
	self.movementStats = {
		status = "moving",
		initialDistance = type(handle.initialDistance) == "number" and handle.initialDistance or nil,
		activeElapsed = 0,
		finalError = nil,
		lastError = nil,
	}
	if
		not self:_recordRequired("safe_start_movement_started", {
			sessionId = sessionId,
			distance = self.movementStats.initialDistance,
		})
	then
		self.epoch += 1
		self.movementSession = nil
		self:_stopMovement(handle)
		self.movementStats.status = "error"
		self.movementStats.lastError = "trace_write_failed"
		return nil, nil, errorResult("trace_write_failed", "Safe Start movement could not be recorded")
	end

	task.spawn(function()
		local callOk, result, movementError = pcall(self.movement.runSafeStart, handle)
		if not self:alive(epoch) or self.movementSession ~= session or self.movementHandle ~= handle then
			return
		end
		self.movementSession = nil
		local snapshot = type(result) == "table" and result or self.movement.snapshot(handle)
		if type(snapshot) == "table" then
			self.movementStats.initialDistance = snapshot.initialDistance
			self.movementStats.activeElapsed = snapshot.activeElapsed
			self.movementStats.finalError = snapshot.finalError
		end
		local cleanupOk, cleanupError = self:_stopMovement(handle)
		if cleanupOk ~= true then
			local code = type(cleanupError) == "table" and cleanupError.code or "movement_stop_failed"
			local message = type(cleanupError) == "table" and cleanupError.message
				or "Safe Start movement cleanup failed"
			self.movementStats.status = "error"
			self.movementStats.lastError = code
			self:_record("safe_start_movement_failed", {
				sessionId = sessionId,
				code = code,
				message = message,
			})
			return
		end
		if callOk and result ~= nil and movementError == nil then
			if
				not self:_recordRequired("safe_start_movement_completed", {
					sessionId = sessionId,
					distance = self.movementStats.initialDistance,
					elapsed = self.movementStats.activeElapsed,
					finalError = self.movementStats.finalError,
				})
			then
				self.movementStats.status = "error"
				self.movementStats.lastError = "trace_write_failed"
				return
			end
			self.movementStats.status = "completed"
			self.updatedAt = now()
			return
		end
		local detail = callOk and movementError or result
		local code = type(detail) == "table" and detail.code or "safe_start_movement_failed"
		local message =
			sanitizedText(type(detail) == "table" and detail.message or detail, "Safe Start movement failed")
		self.movementStats.status = "error"
		self.movementStats.lastError = code
		self:_setError(code, message)
		self:_record("safe_start_movement_failed", {
			sessionId = sessionId,
			code = code,
			message = message,
		})
	end)
	return true, self:snapshot(), nil
end

function Runtime:_stopStage1(handle: any): (boolean?, any)
	local callOk, stopped, stopError = pcall(self.stage1.stopHold, handle)
	if callOk and stopped == true then
		if self.stage1Handle == handle then
			self.stage1Handle = nil
		end
		return true
	end
	local detail = callOk and stopError or stopped
	local code = type(detail) == "table" and detail.code or "stage1_stop_failed"
	local message = sanitizedText(type(detail) == "table" and detail.message or detail, "Stage 1 cleanup failed")
	self.stage1Handle = handle
	self.stage1Stats.status = "error"
	self.stage1Stats.lastError = code
	self.state = "error"
	self:_setError(code, message)
	return nil, errorResult(code, message)
end
function Runtime:_releaseStage1(handle: any): (boolean?, any)
	local callOk, released, releaseError = pcall(self.stage1.releaseHold, handle)
	if callOk and released == true then
		if self.stage1Handle == handle then
			self.stage1Handle = nil
		end
		return true
	end
	local detail = callOk and releaseError or released
	local code = type(detail) == "table" and detail.code or "stage1_release_failed"
	local message = sanitizedText(type(detail) == "table" and detail.message or detail, "Stage 1 release failed")
	self.stage1Handle = handle
	self.stage1Stats.status = "error"
	self.stage1Stats.lastError = code
	return nil, errorResult(code, message)
end
function Runtime:_cancelStage1Acquisition(acquisition: any): (boolean?, any, any)
	if type(acquisition) ~= "table" then
		return true, nil, nil
	end
	acquisition.cancelled = true
	local deadline = os.clock() + STAGE1_ACQUISITION_TIMEOUT
	while acquisition.done ~= true and os.clock() < deadline do
		task.wait(STAGE1_PULSE_POLL_TICK)
	end
	if acquisition.done ~= true then
		return nil,
			nil,
			errorResult("stage1_acquisition_timeout", "Stage 1 acquisition did not stop within the cleanup deadline")
	end
	if self.stage1Acquisition == acquisition then
		self.stage1Acquisition = nil
	end
	return true, acquisition.handle, nil
end

function Runtime:startStage1Pulse(): (boolean?, any, any)
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if
		self.session ~= nil
		or self.stage1Handle ~= nil
		or self.stage1Acquisition ~= nil
		or self.movementSession ~= nil
		or self.movementHandle ~= nil
		or self.courseSession ~= nil
		or self.courseHandle ~= nil
		or self.motionProbeSession ~= nil
		or self.motionProbeHandle ~= nil
		or self.collectorSession ~= nil
		or self.collectorHandle ~= nil
	then
		return nil, self:snapshot(), errorResult("session_active", "a movement owner or cleanup is already active")
	end
	if not self.placeSupported then
		return nil, nil, errorResult("place_unsupported", "current place is not supported")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end
	local startChecked, atStart, startDistance, startError = pcall(self.stage1.atPulseStart)
	if not startChecked or startError ~= nil then
		local detail = startChecked and startError or atStart
		return nil,
			nil,
			errorResult(
				type(detail) == "table" and detail.code or "pulse_start_read_failed",
				type(detail) == "table" and detail.message or "Stage 1 pulse start state could not be read"
			)
	end
	if atStart ~= true then
		return nil,
			nil,
			errorResult(
				"stage1_start_position_required",
				string.format("Auto Stage 1 must start at spawn or Safe Start (%.2f studs away)", startDistance or -1)
			)
	end

	self.epoch += 1
	self.updatedAt = now()
	local epoch = self.epoch
	local sessionId = string.format("stage1-pulse-%d-%d", self.generation, epoch)
	local session, sessionError = self.stage1.newSession(sessionId, epoch, now())
	if session == nil then
		self.epoch += 1
		self.updatedAt = now()
		return nil, nil, sessionError
	end

	self.session = session
	self.stage1Stats = {
		mode = "pulse",
		status = "starting",
		rewards = 0,
		earned = 0,
		lastReward = 0,
		lastRewardAt = nil,
		lastInterval = nil,
		lastPlateDwell = nil,
		nextRunAtClock = nil,
		spawnDistance = nil,
		corrections = 0,
		lastError = nil,
	}
	if not self:_recordRequired("stage1_hold_started", {
		sessionId = sessionId,
		mode = "pulse",
	}) then
		self.session = nil
		self.epoch += 1
		self.stage1Stats.status = "error"
		self.stage1Stats.lastError = "trace_write_failed"
		return nil, nil, errorResult("trace_write_failed", "Stage 1 pulse could not be recorded")
	end

	task.spawn(function()
		local cycle = 0
		local previousRewardAtClock = self.lastStage1RewardClock
		local function failPulse(handle: any, detail: any, fallbackCode: string, fallbackMessage: string)
			if not self:alive(epoch) or self.session ~= session then
				if handle ~= nil then
					self:_stopStage1(handle)
				end
				return
			end
			local code = type(detail) == "table" and detail.code or fallbackCode
			local message = sanitizedText(type(detail) == "table" and detail.message or detail, fallbackMessage)
			self.epoch += 1
			self.session = nil
			self.stage1Handle = handle
			if handle ~= nil then
				if handle.correctionsAccounted ~= true then
					self.stage1Stats.corrections += type(handle.corrections) == "number" and handle.corrections or 0
					handle.correctionsAccounted = true
				end
				local stopped, stopError = self:_stopStage1(handle)
				if stopped ~= true then
					code = type(stopError) == "table" and stopError.code or "stage1_stop_failed"
					message = type(stopError) == "table" and stopError.message or "Stage 1 cleanup failed"
				end
			end
			self.stage1Stats.status = "error"
			self.stage1Stats.lastError = code
			self.stage1Stats.nextRunAtClock = nil
			self:_setError(code, message)
			self:_record("stage1_hold_failed", {
				sessionId = sessionId,
				code = code,
				message = message,
			})
		end

		while self:alive(epoch) and self.session == session do
			if previousRewardAtClock ~= nil then
				self.stage1Stats.status = "cooldown"
				self.stage1Stats.nextRunAtClock = previousRewardAtClock + STAGE1_PULSE_START_DELAY
				local spawnDeadline = previousRewardAtClock + STAGE1_PULSE_SPAWN_TIMEOUT
				local atSpawn = false
				local spawnDistance = nil
				while self:alive(epoch) and self.session == session do
					local checked, currentAtSpawn, currentDistance, spawnError = pcall(self.stage1.atSpawn)
					if not checked or spawnError ~= nil then
						failPulse(
							nil,
							checked and spawnError or currentAtSpawn,
							"spawn_read_failed",
							"Stage 1 spawn state could not be read"
						)
						return
					end
					atSpawn = currentAtSpawn == true
					spawnDistance = currentDistance
					self.stage1Stats.spawnDistance = spawnDistance
					if atSpawn then
						break
					end
					if os.clock() >= spawnDeadline then
						failPulse(
							nil,
							errorResult("spawn_reset_timeout", "Stage 1 did not reset to spawn after reward"),
							"spawn_reset_timeout",
							"Stage 1 did not reset to spawn after reward"
						)
						return
					end
					task.wait(STAGE1_PULSE_POLL_TICK)
				end
				while self:alive(epoch) and self.session == session and os.clock() < self.stage1Stats.nextRunAtClock do
					task.wait(STAGE1_PULSE_POLL_TICK)
				end
				if not self:alive(epoch) or self.session ~= session then
					return
				end
				if
					not self:_recordRequired("stage1_pulse_ready", {
						sessionId = sessionId,
						cycle = cycle + 1,
						waited = os.clock() - previousRewardAtClock,
						spawnDistance = spawnDistance,
					})
				then
					failPulse(
						nil,
						errorResult("trace_write_failed", "Stage 1 pulse readiness could not be recorded"),
						"trace_write_failed",
						"Stage 1 pulse readiness could not be recorded"
					)
					return
				end
			end

			cycle += 1
			self.stage1Stats.status = "starting"
			self.stage1Stats.nextRunAtClock = nil
			local acquisition = {
				cancelled = false,
				done = false,
				handle = nil,
			}
			self.stage1Acquisition = acquisition
			local beginOk, handle, holdError = pcall(function()
				return self.stage1.beginHold(function()
					return self:alive(epoch) and self.session == session
				end, true)
			end)
			acquisition.handle = handle
			acquisition.done = true
			if self.stage1Acquisition == acquisition and acquisition.cancelled ~= true then
				self.stage1Acquisition = nil
			end
			if not self:alive(epoch) or self.session ~= session then
				if acquisition.cancelled ~= true and handle ~= nil then
					self:_stopStage1(handle)
				end
				return
			end
			if not beginOk or handle == nil or holdError ~= nil then
				failPulse(
					handle,
					beginOk and holdError or handle,
					"stage1_start_failed",
					"Stage 1 pulse could not enter WinBlock32"
				)
				return
			end

			self.stage1Handle = handle
			self.stage1Stats.status = "holding"
			if
				not self:_recordRequired("stage1_hold_entered", {
					sessionId = sessionId,
					winsBefore = handle.winsBefore,
					cycle = cycle,
				})
			then
				failPulse(
					handle,
					errorResult("trace_write_failed", "Stage 1 pulse entry could not be recorded"),
					"trace_write_failed",
					"Stage 1 pulse entry could not be recorded"
				)
				return
			end

			local reward = nil
			local previous = nil
			local current = nil
			local rewardAtClock = nil
			while self:alive(epoch) and self.session == session and self.stage1Handle == handle do
				local pollOk, foundReward, foundPrevious, foundCurrent, pollError, foundRewardAt =
					pcall(self.stage1.pollHold, handle)
				if not pollOk or pollError ~= nil then
					failPulse(
						handle,
						pollOk and pollError or foundReward,
						"stage1_hold_failed",
						"Stage 1 pulse reward polling failed"
					)
					return
				end
				if foundReward ~= nil then
					reward = foundReward
					previous = foundPrevious
					current = foundCurrent
					rewardAtClock = type(foundRewardAt) == "number" and foundRewardAt or os.clock()
					break
				end
				if
					type(handle.plateAtClock) ~= "number"
					or os.clock() - handle.plateAtClock >= STAGE1_PULSE_REWARD_TIMEOUT
				then
					failPulse(
						handle,
						errorResult("stage1_reward_timeout", "WinBlock32 did not produce a Wins change in time"),
						"stage1_reward_timeout",
						"WinBlock32 did not produce a Wins change in time"
					)
					return
				end
				task.wait(STAGE1_PULSE_POLL_TICK)
			end
			if not self:alive(epoch) or self.session ~= session or reward == nil then
				return
			end

			local rewardInterval = previousRewardAtClock and rewardAtClock - previousRewardAtClock or nil
			local plateDwell = type(handle.plateAtClock) == "number" and rewardAtClock - handle.plateAtClock or nil
			self.stage1Stats.rewards += 1
			self.stage1Stats.earned += reward
			self.stage1Stats.lastReward = reward
			self.stage1Stats.lastRewardAt = now()
			self.lastStage1RewardClock = rewardAtClock
			self.stage1Stats.lastInterval = rewardInterval
			self.stage1Stats.lastPlateDwell = plateDwell
			if handle.correctionsAccounted ~= true then
				self.stage1Stats.corrections += type(handle.corrections) == "number" and handle.corrections or 0
				handle.correctionsAccounted = true
			end
			if
				not self:_recordRequired("stage1_hold_reward", {
					sessionId = sessionId,
					winsBefore = previous,
					winsAfter = current,
					reward = reward,
					cycle = cycle,
					rewardInterval = rewardInterval,
					plateDwell = plateDwell,
				})
			then
				local released, releaseError = self:_releaseStage1(handle)
				if released ~= true then
					failPulse(
						handle,
						releaseError,
						"stage1_release_failed",
						"Stage 1 pulse could not release WinBlock32"
					)
				else
					self.stage1Handle = nil
					failPulse(
						nil,
						errorResult("trace_write_failed", "Stage 1 pulse reward could not be recorded"),
						"trace_write_failed",
						"Stage 1 pulse reward could not be recorded"
					)
				end
				return
			end
			local released, releaseError = self:_releaseStage1(handle)
			if released ~= true then
				failPulse(handle, releaseError, "stage1_release_failed", "Stage 1 pulse could not release WinBlock32")
				return
			end
			self.stage1Handle = nil
			previousRewardAtClock = rewardAtClock
			self.stage1Stats.status = "cooldown"
			self.stage1Stats.nextRunAtClock = previousRewardAtClock + STAGE1_PULSE_START_DELAY
			self.updatedAt = now()
		end
	end)
	return true, self:snapshot(), nil
end

function Runtime:startStage1Hold(oneTime: any): (boolean?, any, any)
	if oneTime ~= nil and type(oneTime) ~= "boolean" then
		return nil, nil, errorResult("stage1_mode_invalid", "one-time mode must be a boolean")
	end
	local runOnce = oneTime == true
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if
		self.session ~= nil
		or self.stage1Handle ~= nil
		or self.stage1Acquisition ~= nil
		or self.movementSession ~= nil
		or self.movementHandle ~= nil
		or self.courseSession ~= nil
		or self.courseHandle ~= nil
		or self.motionProbeSession ~= nil
		or self.motionProbeHandle ~= nil
		or self.collectorSession ~= nil
		or self.collectorHandle ~= nil
	then
		return nil, self:snapshot(), errorResult("session_active", "a movement owner or cleanup is already active")
	end
	if not self.placeSupported then
		return nil, nil, errorResult("place_unsupported", "current place is not supported")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end

	self.epoch += 1
	self.updatedAt = now()
	local epoch = self.epoch
	local sessionId = string.format("stage1-%d-%d", self.generation, epoch)
	local session, sessionError = self.stage1.newSession(sessionId, epoch, now())
	if session == nil then
		self.epoch += 1
		self.updatedAt = now()
		return nil, nil, sessionError
	end

	self.session = session
	self.stage1Stats = {
		mode = runOnce and "one_time" or "continuous",
		status = "starting",
		rewards = 0,
		earned = 0,
		lastReward = 0,
		lastRewardAt = nil,
		corrections = 0,
		lastError = nil,
	}
	if
		not self:_recordRequired("stage1_hold_started", {
			sessionId = sessionId,
			mode = runOnce and "one_time" or "continuous",
		})
	then
		self.session = nil
		self.epoch += 1
		self.stage1Stats.status = "error"
		self.stage1Stats.lastError = "trace_write_failed"
		return nil, nil, errorResult("trace_write_failed", "stage1 hold could not be recorded")
	end

	local acquisition = {
		cancelled = false,
		done = false,
		handle = nil,
	}
	self.stage1Acquisition = acquisition
	local beginOk, handle, holdError = pcall(function()
		return self.stage1.beginHold(function()
			return self:alive(epoch) and self.session == session
		end, runOnce)
	end)
	acquisition.handle = handle
	acquisition.done = true
	if self.stage1Acquisition == acquisition and acquisition.cancelled ~= true then
		self.stage1Acquisition = nil
	end
	if not self:alive(epoch) or self.session ~= session then
		if acquisition.cancelled ~= true and handle ~= nil then
			self:_stopStage1(handle)
		end
		return nil, nil, errorResult("stage1_cancelled", "Stage 1 hold was cancelled")
	end
	if not beginOk or handle == nil or holdError ~= nil then
		local code = type(holdError) == "table" and holdError.code or "stage1_start_failed"
		local message = beginOk and type(holdError) == "table" and holdError.message or handle
		self.epoch += 1
		self.session = nil
		if handle ~= nil then
			self.stage1Handle = handle
			self:_stopStage1(handle)
		end
		self.stage1Stats.status = "error"
		self.stage1Stats.lastError = code
		self:_record("stage1_hold_failed", {
			sessionId = sessionId,
			code = code,
			message = message,
		})
		return nil, nil, errorResult(code, message)
	end

	self.stage1Handle = handle
	self.stage1Stats.status = "holding"
	if
		not self:_recordRequired("stage1_hold_entered", {
			sessionId = sessionId,
			winsBefore = handle.winsBefore,
		})
	then
		self.epoch += 1
		self.session = nil
		self.stage1Handle = nil
		self.stage1Stats.corrections = type(handle.corrections) == "number" and handle.corrections or 0
		self:_stopStage1(handle)
		self.stage1Stats.status = "error"
		self.stage1Stats.lastError = "trace_write_failed"
		return nil, nil, errorResult("trace_write_failed", "stage1 hold entry could not be recorded")
	end
	task.spawn(function()
		while self:alive(epoch) and self.session == session and self.stage1Handle == handle do
			local pollOk, reward, previous, current, pollError, rewardAtClock = pcall(self.stage1.pollHold, handle)
			if not pollOk or pollError ~= nil then
				if self:alive(epoch) and self.stage1Handle == handle then
					local code = type(pollError) == "table" and pollError.code or "stage1_hold_failed"
					local message = pollOk and type(pollError) == "table" and pollError.message or reward
					self.epoch += 1
					self.session = nil
					self.stage1Handle = nil
					self.stage1Stats.corrections = type(handle.corrections) == "number" and handle.corrections or 0
					self:_stopStage1(handle)
					self.stage1Stats.status = "error"
					self.stage1Stats.lastError = code
					self:_setError(code, message)
					self:_record("stage1_hold_failed", {
						sessionId = sessionId,
						code = code,
						message = message,
					})
				end
				return
			end
			if reward ~= nil then
				if
					not self:_recordRequired("stage1_hold_reward", {
						sessionId = sessionId,
						winsBefore = previous,
						winsAfter = current,
						reward = reward,
					})
				then
					self.epoch += 1
					self.session = nil
					self.stage1Handle = nil
					self.stage1Stats.corrections = type(handle.corrections) == "number" and handle.corrections or 0
					self:_stopStage1(handle)
					self.stage1Stats.status = "error"
					self.stage1Stats.lastError = "trace_write_failed"
					return
				end
				self.stage1Stats.rewards += 1
				self.stage1Stats.earned += reward
				self.stage1Stats.lastReward = reward
				self.stage1Stats.lastRewardAt = now()
				self.lastStage1RewardClock = type(rewardAtClock) == "number" and rewardAtClock or os.clock()
				if runOnce and self:alive(epoch) and self.session == session and self.stage1Handle == handle then
					self.epoch += 1
					self.session = nil
					self.stage1Handle = handle
					self.stage1Stats.corrections = type(handle.corrections) == "number" and handle.corrections or 0
					local stopped, stopError = self:_stopStage1(handle)
					if stopped ~= true then
						local code = type(stopError) == "table" and stopError.code or "stage1_stop_failed"
						local message = type(stopError) == "table" and stopError.message or "Stage 1 cleanup failed"
						self.stage1Stats.status = "error"
						self.stage1Stats.lastError = code
						self:_setError(code, message)
						self:_record("stage1_hold_failed", {
							sessionId = sessionId,
							code = code,
							message = message,
						})
						return
					end
					self.stage1Handle = nil
					if
						not self:_recordRequired("stage1_one_time_completed", {
							sessionId = sessionId,
							reward = reward,
						})
					then
						self.stage1Stats.status = "error"
						self.stage1Stats.lastError = "trace_write_failed"
						return
					end
					self.stage1Stats.status = "completed"
					self.updatedAt = now()
					return
				end
			end
			task.wait(0.05)
		end
	end)
	return true, self:snapshot(), nil
end

function Runtime:_stopCourse(handle: any): (boolean?, any)
	if handle == nil then
		self.courseHandle = nil
		self.coursePolicy = nil
		self.courseKey = nil
		return true
	end
	local policy = self.coursePolicy
	local stageKey = self.courseKey
	local stats = stageKey ~= nil and self[stageKey .. "Stats"] or nil
	local callOk, stopped, stopError = pcall(policy.stop, handle)
	if callOk and stopped == true then
		if self.courseHandle == handle then
			self.courseHandle = nil
			self.coursePolicy = nil
			self.courseKey = nil
		end
		return true
	end
	local detail = callOk and stopError or stopped
	local code = type(detail) == "table" and detail.code or string.format("%s_stop_failed", stageKey or "course")
	local display = string.format("Stage %s", string.sub(stageKey or "", 6))
	local message = sanitizedText(type(detail) == "table" and detail.message or detail, display .. " cleanup failed")
	self.courseHandle = handle
	if stats ~= nil then
		stats.status = "error"
		stats.lastError = code
	end
	self.state = "error"
	self:_setError(code, message)
	return nil, errorResult(code, message)
end

function Runtime:_startCourse(stageKey: string): (boolean?, any, any)
	local policy = self.courses[stageKey]
	if policy == nil then
		return nil, nil, errorResult("course_unknown", "course stage is not supported")
	end
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if
		self.session ~= nil
		or self.stage1Handle ~= nil
		or self.stage1Acquisition ~= nil
		or self.movementSession ~= nil
		or self.movementHandle ~= nil
		or self.courseSession ~= nil
		or self.courseHandle ~= nil
		or self.motionProbeSession ~= nil
		or self.motionProbeHandle ~= nil
		or self.collectorSession ~= nil
		or self.collectorHandle ~= nil
	then
		return nil, self:snapshot(), errorResult("session_active", "a movement owner or cleanup is already active")
	end
	if not self.placeSupported then
		return nil, nil, errorResult("place_unsupported", "current place is not supported")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end

	local display = string.format("Stage %s", string.sub(stageKey, 6))
	self.epoch += 1
	self.updatedAt = now()
	local epoch = self.epoch
	local sessionId = string.format("%s-once-%d-%d", stageKey, self.generation, epoch)
	local session = { id = sessionId, owner = stageKey, phase = "route", epoch = epoch, startedAt = now() }
	local handle, handleError = policy.newSession(
		sessionId,
		epoch,
		os.clock(),
		function()
			return self:alive(epoch) and self.courseSession == session
		end,
		self.movement,
		self.stage5Diagnostics,
		function(kind: any, fields: any)
			return self:_recordRequired(kind, fields)
		end
	)
	if handle == nil then
		self.epoch += 1
		return nil, nil, handleError
	end
	self.courseSession = session
	self.courseHandle = handle
	self.coursePolicy = policy
	self.courseKey = stageKey
	self.lastCourseKey = stageKey
	local stats = self[stageKey .. "Stats"]
	local earned = type(stats.earned) == "number" and stats.earned or 0
	stats.status = "running"
	stats.point = "Safe Start"
	stats.pointsCompleted = 0
	stats.corrections = 0
	stats.reward = 0
	stats.earned = earned
	stats.lastError = nil
	if not self:_recordRequired(stageKey .. "_started", { sessionId = sessionId }) then
		self.epoch += 1
		self.courseSession = nil
		self:_stopCourse(handle)
		stats.status = "error"
		stats.lastError = "trace_write_failed"
		return nil, nil, errorResult("trace_write_failed", display .. " start could not be recorded")
	end
	task.spawn(function()
		local callOk, result, runError = pcall(policy.run, handle)
		if not self:alive(epoch) or self.courseSession ~= session or self.courseHandle ~= handle then
			return
		end
		local policySnapshot = policy.snapshot(handle)
		if type(policySnapshot) == "table" then
			stats.point = policySnapshot.point
			stats.pointsCompleted = policySnapshot.pointsCompleted or 0
			stats.corrections = policySnapshot.corrections or 0
			stats.elapsed = policySnapshot.elapsed
		end
		local cleanupOk, cleanupError = self:_stopCourse(handle)
		if cleanupOk ~= true then
			local code = type(cleanupError) == "table" and cleanupError.code or stageKey .. "_stop_failed"
			local message = type(cleanupError) == "table" and cleanupError.message or display .. " cleanup failed"
			stats.status = "error"
			stats.lastError = code
			self:_record(stageKey .. "_failed", { sessionId = sessionId, code = code, message = message })
			return
		end
		self.courseSession = nil
		if callOk and type(result) == "table" and runError == nil then
			stats.status = "completed"
			stats.reward = type(result.reward) == "number" and result.reward or 0
			stats.earned += stats.reward
			stats.elapsed = result.elapsed or stats.elapsed
			stats.corrections = result.corrections or stats.corrections
			self.updatedAt = now()
			if
				not self:_recordRequired(stageKey .. "_completed", {
					sessionId = sessionId,
					reward = stats.reward,
					elapsed = stats.elapsed,
					corrections = stats.corrections,
				})
			then
				stats.status = "error"
				stats.lastError = "trace_write_failed"
			end
			return
		end
		local detail = callOk and runError or result
		local code = type(detail) == "table" and detail.code or stageKey .. "_failed"
		local message = sanitizedText(type(detail) == "table" and detail.message or detail, display .. " failed")
		stats.status = "error"
		stats.lastError = code
		self:_setError(code, message)
		self:_record(stageKey .. "_failed", { sessionId = sessionId, code = code, message = message })
	end)
	return true, self:snapshot(), nil
end

function Runtime:startStage2Once(): (boolean?, any, any)
	return self:_startCourse("stage2")
end

function Runtime:startStage3Once(): (boolean?, any, any)
	return self:_startCourse("stage3")
end

function Runtime:startStage4Once(): (boolean?, any, any)
	return self:_startCourse("stage4")
end

function Runtime:startStage5Once(): (boolean?, any, any)
	return self:_startCourse("stage5")
end

function Runtime:startStage6Once(): (boolean?, any, any)
	return self:_startCourse("stage6")
end

function Runtime:startStage7Once(): (boolean?, any, any)
	return self:_startCourse("stage7")
end

function Runtime:startStage8Once(): (boolean?, any, any)
	return self:_startCourse("stage8")
end

function Runtime:startStage9Once(): (boolean?, any, any)
	return self:_startCourse("stage9")
end

function Runtime:_stopMotionProbe(handle: any): (boolean?, any)
	local callOk, stopped, stopError = pcall(self.motionProbe.stop, handle)
	if callOk and stopped == true then
		if self.motionProbeHandle == handle then
			self.motionProbeHandle = nil
		end
		return true
	end
	local detail = callOk and stopError or stopped
	local code = type(detail) == "table" and detail.code or "motion_probe_stop_failed"
	local message = sanitizedText(type(detail) == "table" and detail.message or detail, "motion probe cleanup failed")
	self.motionProbeHandle = handle
	self.motionProbeStats.status = "error"
	self.motionProbeStats.lastError = code
	self.state = "error"
	self:_setError(code, message)
	return nil, errorResult(code, message)
end

function Runtime:startMotionProbe(): (boolean?, any, any)
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if
		self.session ~= nil
		or self.stage1Handle ~= nil
		or self.stage1Acquisition ~= nil
		or self.movementSession ~= nil
		or self.movementHandle ~= nil
		or self.courseSession ~= nil
		or self.courseHandle ~= nil
		or self.motionProbeSession ~= nil
		or self.motionProbeHandle ~= nil
		or self.collectorSession ~= nil
		or self.collectorHandle ~= nil
	then
		return nil, self:snapshot(), errorResult("session_active", "a movement owner or cleanup is already active")
	end
	if not self.placeSupported then
		return nil, nil, errorResult("place_unsupported", "current place is not supported")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end

	self.epoch += 1
	self.updatedAt = now()
	local epoch = self.epoch
	local sessionId = string.format("motion-probe-%d-%d", self.generation, epoch)
	local session = {
		id = sessionId,
		owner = "motion_probe",
		phase = "probe",
		epoch = epoch,
		startedAt = now(),
	}
	local handle, handleError = self.motionProbe.newSession(sessionId, function()
		return self:alive(epoch) and self.motionProbeSession == session
	end)
	if handle == nil then
		self.epoch += 1
		return nil, nil, handleError
	end
	self.motionProbeSession = session
	self.motionProbeHandle = handle
	self.motionProbeStats = {
		status = "running",
		variant = "baseline",
		variantsCompleted = 0,
		results = {},
		lastError = nil,
	}
	if not self:_recordRequired("motion_probe_started", { sessionId = sessionId }) then
		self.epoch += 1
		self.motionProbeSession = nil
		self:_stopMotionProbe(handle)
		self.motionProbeStats.status = "error"
		self.motionProbeStats.lastError = "trace_write_failed"
		return nil, nil, errorResult("trace_write_failed", "motion probe start could not be recorded")
	end

	task.spawn(function()
		local callOk, result, runError = pcall(self.motionProbe.run, handle)
		if not self:alive(epoch) or self.motionProbeSession ~= session or self.motionProbeHandle ~= handle then
			return
		end
		local policySnapshot = self.motionProbe.snapshot(handle)
		if type(policySnapshot) == "table" then
			self.motionProbeStats.variant = policySnapshot.variant
			self.motionProbeStats.variantsCompleted = policySnapshot.variantsCompleted or 0
			self.motionProbeStats.results = policySnapshot.results or {}
		end
		local cleanupOk, cleanupError = self:_stopMotionProbe(handle)
		if cleanupOk ~= true then
			local code = type(cleanupError) == "table" and cleanupError.code or "motion_probe_stop_failed"
			local message = type(cleanupError) == "table" and cleanupError.message or "motion probe cleanup failed"
			self.motionProbeStats.status = "error"
			self.motionProbeStats.lastError = code
			self:_record("motion_probe_failed", { sessionId = sessionId, code = code, message = message })
			return
		end
		self.motionProbeSession = nil
		if callOk and type(result) == "table" and runError == nil then
			self.motionProbeStats.status = "completed"
			self.motionProbeStats.variant = nil
			self.motionProbeStats.variantsCompleted = result.variantsCompleted or 0
			self.motionProbeStats.results = result.variants or {}
			for _, summary in ipairs(self.motionProbeStats.results) do
				local fields = deepCopy(summary)
				fields.sessionId = sessionId
				if not self:_recordRequired("motion_probe_variant_completed", fields) then
					self.motionProbeStats.status = "error"
					self.motionProbeStats.lastError = "trace_write_failed"
					return
				end
			end
			self.updatedAt = now()
			if
				not self:_recordRequired("motion_probe_completed", {
					sessionId = sessionId,
					variantsCompleted = self.motionProbeStats.variantsCompleted,
				})
			then
				self.motionProbeStats.status = "error"
				self.motionProbeStats.lastError = "trace_write_failed"
			end
			return
		end
		local detail = callOk and runError or result
		local code = type(detail) == "table" and detail.code or "motion_probe_failed"
		local message = sanitizedText(type(detail) == "table" and detail.message or detail, "motion probe failed")
		self.motionProbeStats.status = "error"
		self.motionProbeStats.lastError = code
		self:_setError(code, message)
		self:_record("motion_probe_failed", { sessionId = sessionId, code = code, message = message })
	end)
	return true, self:snapshot(), nil
end

function Runtime:_stopCollectors(handle: any): (boolean?, any)
	local stopOk, stopError = true, nil
	if handle ~= nil then
		local callOk, stopped, policyError = pcall(self.eventCollectors.stop, handle)
		stopOk = callOk and stopped == true
		stopError = callOk and policyError or stopped
		local snapshotOk, copied = pcall(self.eventCollectors.snapshot, handle)
		if snapshotOk and type(copied) == "table" then
			self.collectorStats = copied
			self.collectorStats.config = deepCopy(self.collectorConfig)
		end
	end
	local runner = self.collectorTask
	if runner ~= nil and runner ~= coroutine.running() then
		local statusOk, status = pcall(coroutine.status, runner)
		if not statusOk or status ~= "dead" then
			local cancelOk, cancelError = pcall(task.cancel, runner)
			if not cancelOk then
				stopOk = false
				stopError = cancelError
			end
		end
	end
	self.collectorTask = nil
	if stopOk then
		if handle == nil or self.collectorHandle == handle then
			self.collectorHandle = nil
		end
		return true
	end
	local code = "events_stop_failed"
	local message =
		sanitizedText(type(stopError) == "table" and stopError.message or stopError, "event collector cleanup failed")
	if type(stopError) == "table" and type(stopError.code) == "string" then
		code = stopError.code
	end
	self.collectorHandle = handle
	self.collectorStats.status = "error"
	self.collectorStats.lastError = code
	self.state = "error"
	self:_setError(code, message)
	return nil, errorResult(code, message)
end

function Runtime:startCollectors(config: any): (boolean?, any, any)
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if not validCollectorConfig(config) then
		return nil, nil, errorResult("events_config_invalid", "event collector configuration is invalid")
	end
	if
		self.session ~= nil
		or self.stage1Handle ~= nil
		or self.stage1Acquisition ~= nil
		or self.movementSession ~= nil
		or self.movementHandle ~= nil
		or self.courseSession ~= nil
		or self.courseHandle ~= nil
		or self.motionProbeSession ~= nil
		or self.motionProbeHandle ~= nil
		or self.collectorSession ~= nil
		or self.collectorHandle ~= nil
		or self.collectorTask ~= nil
	then
		return nil, self:snapshot(), errorResult("session_active", "a movement owner or cleanup is already active")
	end
	if not self.placeSupported then
		return nil, nil, errorResult("place_unsupported", "current place is not supported")
	end
	if self:_traceState() ~= "READY" then
		return nil, nil, errorResult("trace_unavailable", "trace is not ready")
	end

	self.epoch += 1
	local epoch = self.epoch
	local session = {
		id = string.format("events-%d-%d", self.generation, epoch),
		owner = "events",
		phase = "collecting",
		epoch = epoch,
		startedAt = now(),
	}
	local handle, handleError = self.eventCollectors.newSession(config, epoch, function(kind: any, fields: any)
		local eventFields = type(fields) == "table" and fields or {}
		if eventFields.sessionId == nil then
			eventFields.sessionId = session.id
		end
		return self:_record(kind, eventFields)
	end, function()
		return self:alive(epoch) and self.collectorSession == session and self.collectorHandle ~= nil
	end)
	if handle == nil then
		self.epoch += 1
		return nil, nil, handleError
	end
	self.collectorSession = session
	self.collectorHandle = handle
	self.collectorConfig = deepCopy(config)
	self.collectorStats = type(self.eventCollectors.snapshot(handle)) == "table"
			and self.eventCollectors.snapshot(handle)
		or self.collectorStats
	self.collectorStats.config = deepCopy(self.collectorConfig)
	self.collectorStats.status = self.collectorStats.status or "running"
	self.updatedAt = now()
	self:_record("collector_started", {
		sessionId = session.id,
		enabled = collectorEnabledSummary(config),
	})
	self.collectorTask = task.spawn(function()
		local callOk, result, runError = pcall(self.eventCollectors.run, handle)
		if self.collectorTask == coroutine.running() then
			self.collectorTask = nil
		end
		if not self:alive(epoch) or self.collectorSession ~= session or self.collectorHandle ~= handle then
			return
		end
		local copied = self.eventCollectors.snapshot(handle)
		if type(copied) == "table" then
			self.collectorStats = copied
		end
		self.collectorSession = nil
		local stopped, stopError = self:_stopCollectors(handle)
		if stopped ~= true then
			local detail = type(stopError) == "table" and stopError or {}
			self.collectorStats.status = "error"
			self.collectorStats.lastError = detail.code or "events_stop_failed"
			self:_record("collector_failed", {
				sessionId = session.id,
				code = self.collectorStats.lastError,
				message = detail.message or "event collector cleanup failed",
			})
			return
		end
		if callOk and runError == nil then
			self.collectorStats.status = type(result) == "table" and result.status or "completed"
			self.updatedAt = now()
			return
		end
		local detail = callOk and runError or result
		local code = type(detail) == "table" and detail.code or "collector_failed"
		local message = sanitizedText(type(detail) == "table" and detail.message or detail, "event collector failed")
		self.collectorStats.status = "error"
		self.collectorStats.lastError = code
		self:_setError(code, message)
		self:_record("collector_failed", { sessionId = session.id, code = code, message = message })
	end)
	return true, self:snapshot(), nil
end

function Runtime:configureCollectors(config: any): (boolean?, any, any)
	if not validCollectorConfig(config) then
		return nil, nil, errorResult("events_config_invalid", "event collector configuration is invalid")
	end
	if self.state ~= "idle" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if self.collectorSession == nil or self.collectorHandle == nil then
		return self:startCollectors(config)
	end
	local configured, configureError = self.eventCollectors.configure(self.collectorHandle, config)
	if configured ~= true then
		return nil, self:snapshot(), configureError
	end
	self.collectorConfig = deepCopy(config)
	local copied = self.eventCollectors.snapshot(self.collectorHandle)
	if type(copied) == "table" then
		self.collectorStats = copied
	end
	self.collectorStats.config = deepCopy(self.collectorConfig)
	self.updatedAt = now()
	self:_record("collector_configured", {
		sessionId = self.collectorSession.id,
		enabled = collectorEnabledSummary(config),
	})
	return true, self:snapshot(), nil
end

function Runtime:command(name: any, payload: any): (boolean?, any, any)
	if type(name) ~= "string" or (name ~= "stop" and name ~= "eject") then
		return nil, nil, errorResult("command_unknown", "command is not supported")
	end

	local valid, reasonOrError = self:_validatePayload(name, payload)
	if not valid then
		return nil, nil, reasonOrError
	end
	local reason = reasonOrError

	if self.state ~= "idle" and name ~= "eject" then
		return nil, nil, errorResult("runtime_inactive", "runtime is no longer active")
	end
	if self.state == "ejecting" then
		return nil, nil, errorResult("eject_in_progress", "eject is already in progress")
	end

	self:_record("command_received", { name = name })
	if name == "stop" then
		if self.collectorSession ~= nil or self.collectorHandle ~= nil then
			local session = self.collectorSession
			local handle = self.collectorHandle
			self.epoch += 1
			self.collectorSession = nil
			local stopped, stopError = self:_stopCollectors(handle)
			if stopped ~= true then
				local code = type(stopError) == "table" and stopError.code or "events_stop_failed"
				local message = type(stopError) == "table" and stopError.message or "event collector cleanup failed"
				self.collectorStats.status = "error"
				self.collectorStats.lastError = code
				self.lastCommand = { name = "stop", ok = false, code = code, at = now() }
				self:_record("collector_failed", {
					sessionId = type(session) == "table" and session.id or "",
					code = code,
					message = message,
				})
				self:_record("command_result", { name = "stop", ok = false, code = code })
				return nil, nil, errorResult(code, message)
			end
			self.collectorStats.status = "stopped"
			self.updatedAt = now()
			self:_record("collector_cancelled", {
				sessionId = type(session) == "table" and session.id or "",
				reason = reason or "external_stop",
			})
			self.lastCommand = { name = "stop", ok = true, code = "stop_cancelled_events", at = now() }
			self:_record("command_result", { name = "stop", ok = true, code = "stop_cancelled_events" })
			return true, self:snapshot(), nil
		end
		if self.motionProbeSession ~= nil or self.motionProbeHandle ~= nil then
			local session = self.motionProbeSession
			local handle = self.motionProbeHandle
			self.epoch += 1
			self.motionProbeSession = nil
			local stopped, stopError = self:_stopMotionProbe(handle)
			if stopped ~= true then
				local code = type(stopError) == "table" and stopError.code or "motion_probe_stop_failed"
				local message = type(stopError) == "table" and stopError.message or "motion probe cleanup failed"
				self.motionProbeStats.status = "error"
				self.motionProbeStats.lastError = code
				self.lastCommand = { name = "stop", ok = false, code = code, at = now() }
				self:_record("motion_probe_failed", {
					sessionId = type(session) == "table" and session.id or "",
					code = code,
					message = message,
				})
				self:_record("command_result", { name = "stop", ok = false, code = code })
				return nil, nil, errorResult(code, message)
			end
			self.motionProbeHandle = nil
			self.motionProbeStats.status = "stopped"
			self.updatedAt = now()
			self:_record("motion_probe_cancelled", {
				sessionId = type(session) == "table" and session.id or "",
				reason = reason or "external_stop",
			})
			self.lastCommand = { name = "stop", ok = true, code = "stop_cancelled_motion_probe", at = now() }
			self:_record("command_result", { name = "stop", ok = true, code = "stop_cancelled_motion_probe" })
			return true, self:snapshot(), nil
		end
		if self.courseSession ~= nil or self.courseHandle ~= nil then
			local session = self.courseSession
			local handle = self.courseHandle
			local stageKey = self.courseKey
			local stats = self[stageKey .. "Stats"]
			self.epoch += 1
			self.courseSession = nil
			local stopped, stopError = self:_stopCourse(handle)
			if stopped ~= true then
				local code = type(stopError) == "table" and stopError.code or stageKey .. "_stop_failed"
				local message = type(stopError) == "table" and stopError.message
					or string.format("Stage %s cleanup failed", string.sub(stageKey, 6))
				stats.status = "error"
				stats.lastError = code
				self.lastCommand = { name = "stop", ok = false, code = code, at = now() }
				self:_record(stageKey .. "_failed", {
					sessionId = type(session) == "table" and session.id or "",
					code = code,
					message = message,
				})
				self:_record("command_result", { name = "stop", ok = false, code = code })
				return nil, nil, errorResult(code, message)
			end
			stats.status = "stopped"
			self.updatedAt = now()
			self:_record(stageKey .. "_cancelled", {
				sessionId = type(session) == "table" and session.id or "",
				reason = reason or "external_stop",
			})
			local resultCode = "stop_cancelled_" .. stageKey
			self.lastCommand = { name = "stop", ok = true, code = resultCode, at = now() }
			self:_record("command_result", { name = "stop", ok = true, code = resultCode })
			return true, self:snapshot(), nil
		end
		if self.movementSession ~= nil or self.movementHandle ~= nil then
			local session = self.movementSession
			local handle = self.movementHandle
			self.epoch += 1
			self.movementSession = nil
			local stopped, stopError = self:_stopMovement(handle)
			if stopped ~= true then
				local code = type(stopError) == "table" and stopError.code or "movement_stop_failed"
				local message = type(stopError) == "table" and stopError.message or "movement cleanup failed"
				self.movementStats.status = "error"
				self.movementStats.lastError = code
				self.lastCommand = { name = "stop", ok = false, code = code, at = now() }
				self:_record("safe_start_movement_failed", {
					sessionId = type(session) == "table" and session.id or "",
					code = code,
					message = message,
				})
				self:_record("command_result", { name = "stop", ok = false, code = code })
				return nil, nil, errorResult(code, message)
			end
			self.movementHandle = nil
			self.movementStats.status = "stopped"
			self.updatedAt = now()
			self:_record("safe_start_movement_cancelled", {
				sessionId = type(session) == "table" and session.id or "",
				reason = reason or "external_stop",
			})
			self.lastCommand = { name = "stop", ok = true, code = "stop_cancelled_movement", at = now() }
			self:_record("command_result", { name = "stop", ok = true, code = "stop_cancelled_movement" })
			return true, self:snapshot(), nil
		end
		if self.session ~= nil or self.stage1Acquisition ~= nil or self.stage1Handle ~= nil then
			local session = self.stage1.snapshot(self.session)
			local handle = self.stage1Handle
			local acquisition = self.stage1Acquisition
			self.epoch += 1
			self.session = nil
			local acquisitionStopped, acquiredHandle, acquisitionError = self:_cancelStage1Acquisition(acquisition)
			if acquisitionStopped ~= true then
				local code = type(acquisitionError) == "table" and acquisitionError.code or "stage1_acquisition_timeout"
				local message = type(acquisitionError) == "table" and acquisitionError.message
					or "Stage 1 acquisition did not stop"
				self.stage1Stats.status = "error"
				self.stage1Stats.lastError = code
				self.state = "error"
				self:_setError(code, message)
				self.lastCommand = { name = "stop", ok = false, code = code, at = now() }
				self:_record("stage1_hold_failed", {
					sessionId = type(session) == "table" and session.id or "",
					code = code,
					message = message,
				})
				self:_record("command_result", { name = "stop", ok = false, code = code })
				return nil, nil, errorResult(code, message)
			end
			handle = handle or acquiredHandle
			if type(handle) == "table" and handle.correctionsAccounted ~= true then
				self.stage1Stats.corrections = (
					type(self.stage1Stats.corrections) == "number" and self.stage1Stats.corrections or 0
				) + (type(handle.corrections) == "number" and handle.corrections or 0)
				handle.correctionsAccounted = true
			end
			local stopped, stopError = self:_stopStage1(handle)
			if stopped ~= true then
				local code = type(stopError) == "table" and stopError.code or "stage1_stop_failed"
				local message = type(stopError) == "table" and stopError.message or "Stage 1 cleanup failed"
				self.stage1Stats.status = "error"
				self.stage1Stats.lastError = code
				self:_setError(code, message)
				self.lastCommand = { name = "stop", ok = false, code = code, at = now() }
				self:_record("stage1_hold_failed", {
					sessionId = type(session) == "table" and session.id or "",
					code = code,
					message = message,
				})
				self:_record("command_result", { name = "stop", ok = false, code = code })
				return nil, nil, errorResult(code, message)
			end
			self.stage1Handle = nil
			self.stage1Stats.status = "stopped"
			self.updatedAt = now()
			self:_record("stage1_hold_cancelled", {
				sessionId = type(session) == "table" and session.id or "",
				reason = reason or "external_stop",
			})
			self.lastCommand = { name = "stop", ok = true, code = "stop_cancelled_session", at = now() }
			self:_record("command_result", { name = "stop", ok = true, code = "stop_cancelled_session" })
			return true, self:snapshot(), nil
		end
		self.lastCommand = { name = "stop", ok = true, code = "stop_no_active_session", at = now() }
		self:_record("stop_no_active_session", {})
		self:_record("command_result", { name = "stop", ok = true, code = "stop_no_active_session" })
		return true, self:snapshot(), nil
	end

	local ok, result, ejectError = self:Eject(reason or "external_eject")
	if ok then
		self.lastCommand = { name = "eject", ok = true, code = "ejected", at = now() }
		self:_record("command_result", { name = "eject", ok = true, code = "ejected" })
		return true, self:snapshot(), nil
	end
	self.lastCommand = { name = "eject", ok = false, code = ejectError.code, at = now() }
	self:_record("command_result", { name = "eject", ok = false, code = ejectError.code })
	return nil, nil, ejectError
end

function Runtime:Eject(reason: any): (boolean?, any, any)
	local actualReason = reason or "external_eject"
	if type(actualReason) ~= "string" or not DIRECT_EJECT_REASONS[actualReason] then
		return nil, nil, errorResult("eject_invalid", "eject reason is not allowed")
	end
	if self.state == "ejecting" then
		return nil, nil, errorResult("eject_in_progress", "eject is already in progress")
	end
	if self.state == "ejected" then
		local environment, environmentError = self:_exportEnvironment()
		if environment == nil then
			return nil, nil, environmentError
		end
		local cleared, clearError = self:_clearExport(environment)
		if not cleared then
			return nil, nil, clearError
		end
		return true, { state = "ejected", cleanupErrors = {} }, nil
	end

	self.state = "ejecting"
	self.epoch += 1
	self.updatedAt = now()
	self:_record("runtime_ejecting", { reason = actualReason })
	local cleanupErrors = {}
	local collectorSession = self.collectorSession
	local collectorHandle = self.collectorHandle
	self.collectorSession = nil
	local collectorStopped, collectorStopError = self:_stopCollectors(collectorHandle)
	if collectorStopped ~= true then
		local cleanupError = {
			label = "events",
			errorCode = type(collectorStopError) == "table" and collectorStopError.code or "events_stop_failed",
			message = sanitizedText(
				type(collectorStopError) == "table" and collectorStopError.message or collectorStopError,
				"event collector cleanup failed"
			),
		}
		self.cleanupErrors = { cleanupError }
		self:_record("cleanup_failed", cleanupError)
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "event collector cleanup did not complete",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end
	self.collectorHandle = nil
	if collectorSession ~= nil then
		self.collectorStats.status = "stopped"
		self:_record("collector_cancelled", {
			sessionId = type(collectorSession) == "table" and collectorSession.id or "",
			reason = actualReason,
		})
	end
	local motionProbeSession = self.motionProbeSession
	local motionProbeHandle = self.motionProbeHandle
	self.motionProbeSession = nil
	local motionProbeStopped, motionProbeStopError = self:_stopMotionProbe(motionProbeHandle)
	if motionProbeStopped ~= true then
		local cleanupError = {
			label = "motion_probe",
			errorCode = type(motionProbeStopError) == "table" and motionProbeStopError.code
				or "motion_probe_stop_failed",
			message = sanitizedText(
				type(motionProbeStopError) == "table" and motionProbeStopError.message or motionProbeStopError,
				"motion probe cleanup failed"
			),
		}
		self.cleanupErrors = { cleanupError }
		self:_record("cleanup_failed", cleanupError)
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "motion probe cleanup did not complete",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end
	self.motionProbeHandle = nil
	if motionProbeSession ~= nil then
		self.motionProbeStats.status = "stopped"
		self:_record("motion_probe_cancelled", {
			sessionId = type(motionProbeSession) == "table" and motionProbeSession.id or "",
			reason = actualReason,
		})
	end
	local courseSession = self.courseSession
	local courseHandle = self.courseHandle
	local courseKey = self.courseKey
	if courseHandle ~= nil then
		local stageStats = self[courseKey .. "Stats"]
		self.courseSession = nil
		local courseStopped, courseStopError = self:_stopCourse(courseHandle)
		if courseStopped ~= true then
			local display = string.format("Stage %s", string.sub(courseKey, 6))
			local cleanupError = {
				label = courseKey,
				errorCode = type(courseStopError) == "table" and courseStopError.code or courseKey .. "_stop_failed",
				message = sanitizedText(
					type(courseStopError) == "table" and courseStopError.message or courseStopError,
					display .. " cleanup failed"
				),
			}
			self.cleanupErrors = { cleanupError }
			self:_record("cleanup_failed", cleanupError)
			return nil,
				nil,
				{
					code = "eject_failed",
					message = display .. " cleanup did not complete",
					cleanupErrors = deepCopy(self.cleanupErrors),
				}
		end
		if courseSession ~= nil then
			stageStats.status = "stopped"
			self:_record(courseKey .. "_cancelled", {
				sessionId = type(courseSession) == "table" and courseSession.id or "",
				reason = actualReason,
			})
		end
	end
	local movementSession = self.movementSession
	local movementHandle = self.movementHandle
	self.movementSession = nil
	local movementStopped, movementStopError = self:_stopMovement(movementHandle)
	if movementStopped ~= true then
		local cleanupError = {
			label = "movement",
			errorCode = type(movementStopError) == "table" and movementStopError.code or "movement_stop_failed",
			message = sanitizedText(
				type(movementStopError) == "table" and movementStopError.message or movementStopError,
				"movement cleanup failed"
			),
		}
		self.cleanupErrors = { cleanupError }
		self:_record("cleanup_failed", cleanupError)
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "movement cleanup did not complete",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end
	self.movementHandle = nil
	if movementSession ~= nil then
		self.movementStats.status = "stopped"
		self:_record("safe_start_movement_cancelled", {
			sessionId = type(movementSession) == "table" and movementSession.id or "",
			reason = actualReason,
		})
	end
	local session = self.session
	local handle = self.stage1Handle
	local acquisition = self.stage1Acquisition
	self.session = nil
	local acquisitionStopped, acquiredHandle, acquisitionError = self:_cancelStage1Acquisition(acquisition)
	if acquisitionStopped ~= true then
		local cleanupError = {
			label = "stage1",
			errorCode = type(acquisitionError) == "table" and acquisitionError.code or "stage1_acquisition_timeout",
			message = sanitizedText(
				type(acquisitionError) == "table" and acquisitionError.message or acquisitionError,
				"Stage 1 acquisition did not stop"
			),
		}
		self.cleanupErrors = { cleanupError }
		self.state = "error"
		self:_record("cleanup_failed", cleanupError)
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "Stage 1 acquisition did not stop",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end
	handle = handle or acquiredHandle
	if type(handle) == "table" and handle.correctionsAccounted ~= true then
		self.stage1Stats.corrections = (
			type(self.stage1Stats.corrections) == "number" and self.stage1Stats.corrections or 0
		) + (type(handle.corrections) == "number" and handle.corrections or 0)
		handle.correctionsAccounted = true
	end
	local stopped, stopError = self:_stopStage1(handle)
	if stopped ~= true then
		local cleanupError = {
			label = "stage1",
			errorCode = type(stopError) == "table" and stopError.code or "stage1_stop_failed",
			message = sanitizedText(
				type(stopError) == "table" and stopError.message or stopError,
				"Stage 1 cleanup failed"
			),
		}
		self.cleanupErrors = { cleanupError }
		self:_record("cleanup_failed", cleanupError)
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "Stage 1 cleanup did not complete",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end
	if session ~= nil then
		local sessionSnapshot = self.stage1.snapshot(session)
		self.stage1Stats.status = "stopped"
		self:_record("stage1_hold_cancelled", {
			sessionId = type(sessionSnapshot) == "table" and sessionSnapshot.id or "",
			reason = actualReason,
		})
	end
	local environment, environmentError = self:_exportEnvironment()
	if environment == nil then
		self.cleanupErrors = {
			{
				label = "export",
				errorCode = environmentError.code,
				message = environmentError.message,
			},
		}
		self.state = "error"
		self:_setError("eject_failed", "runtime export cleanup unavailable")
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "runtime export cleanup unavailable",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end

	if self.destroyMenu ~= nil then
		local ok, destroyed, destroyError = pcall(self.destroyMenu)
		if not ok or destroyed ~= true then
			local detail = not ok and destroyed or destroyError
			local cleanupError = {
				label = "menu",
				errorCode = "menu_destroy_failed",
				message = sanitizedText(type(detail) == "table" and detail.message or detail, "menu cleanup failed"),
			}
			table.insert(cleanupErrors, cleanupError)
			self:_record("cleanup_failed", {
				label = cleanupError.label,
				errorCode = cleanupError.errorCode,
				message = cleanupError.message,
			})
		end
	end

	if #cleanupErrors > 0 then
		self.cleanupErrors = cleanupErrors
		self.state = "error"
		self:_setError("eject_failed", "runtime cleanup failed")
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "runtime cleanup failed",
				cleanupErrors = deepCopy(cleanupErrors),
			}
	end

	self:_record("runtime_ejected", {})
	if self.trace ~= nil then
		local flushed, flushResult, flushError = pcall(function()
			return self.trace:flush()
		end)
		if not flushed or flushResult ~= true then
			self:_setError(
				"trace_write_failed",
				not flushed and flushResult
					or (type(flushError) == "table" and flushError.message or "trace flush failed")
			)
		end
	end

	local cleared, clearError = self:_clearExport(environment)
	if not cleared then
		self.cleanupErrors = {
			{
				label = "export",
				errorCode = clearError.code,
				message = clearError.message,
			},
		}
		self.state = "error"
		self:_setError("eject_failed", "runtime export cleanup failed")
		return nil,
			nil,
			{
				code = "eject_failed",
				message = "runtime export cleanup failed",
				cleanupErrors = deepCopy(self.cleanupErrors),
			}
	end

	self.cleanupErrors = {}
	self.state = "ejected"
	self.updatedAt = now()
	return true, { state = "ejected", cleanupErrors = {} }, nil
end

return Runtime
