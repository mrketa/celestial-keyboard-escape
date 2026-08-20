local HttpService = game:GetService("HttpService")

local Trace = {}
Trace.__index = Trace

local DIRECTORY = "potassium-next/diagnostics"
local MAX_TEXT_LENGTH = 240

local ALLOWED_KINDS = {
	runtime_created = true,
	command_received = true,
	command_result = true,
	runtime_ejecting = true,
	runtime_ejected = true,
	cleanup_failed = true,
	stop_no_active_session = true,
	safe_start_movement_started = true,
	safe_start_movement_completed = true,
	safe_start_movement_cancelled = true,
	safe_start_movement_failed = true,
	stage1_hold_started = true,
	stage1_hold_entered = true,
	stage1_hold_reward = true,
	stage1_one_time_completed = true,
	stage1_pulse_ready = true,
	stage1_hold_cancelled = true,
	stage1_hold_failed = true,
	stage2_started = true,
	stage2_point_started = true,
	stage2_point_completed = true,
	stage2_point_corrected = true,
	stage2_plate_entered = true,
	stage2_reward = true,
	stage2_spawn_returned = true,
	stage2_completed = true,
	stage2_cancelled = true,
	stage2_failed = true,
	stage5_diagnostic_snapshot = true,
	stage5_motion_summary = true,
	stage5_server_signal = true,
	motion_probe_started = true,
	motion_probe_variant_completed = true,
	motion_probe_completed = true,
	motion_probe_cancelled = true,
	motion_probe_failed = true,
	observation_captured = true,
	observation_failed = true,
	collector_started = true,
	collector_configured = true,
	collector_target = true,
	collector_movement = true,
	collector_result = true,
	collector_safety_stopped = true,
	collector_cancelled = true,
	collector_failed = true,
	event_teleport = true,
	events_safety_stop = true,
}
local KIND_FIELDS = {
	runtime_created = {
		"generation",
		"version",
		"placeSupported",
		"traceState",
	},
	command_received = { "name", "reason" },
	command_result = { "name", "ok", "code" },
	runtime_ejecting = { "reason" },
	runtime_ejected = {},
	stop_no_active_session = {},
	safe_start_movement_started = { "sessionId", "distance" },
	safe_start_movement_completed = { "sessionId", "distance", "elapsed", "finalError" },
	safe_start_movement_cancelled = { "sessionId", "reason" },
	safe_start_movement_failed = { "sessionId", "code", "message" },
	stage1_hold_started = { "sessionId", "mode" },
	stage1_hold_entered = { "sessionId", "winsBefore", "cycle" },
	stage1_hold_reward = {
		"sessionId",
		"winsBefore",
		"winsAfter",
		"reward",
		"cycle",
		"rewardInterval",
		"plateDwell",
	},
	stage1_one_time_completed = { "sessionId", "reward" },
	stage1_pulse_ready = { "sessionId", "cycle", "waited", "spawnDistance" },
	stage1_hold_cancelled = { "sessionId", "reason" },
	stage1_hold_failed = { "sessionId", "code", "message" },
	stage2_started = { "sessionId" },
	stage2_point_started = {
		"sessionId",
		"pointIndex",
		"name",
		"attempt",
		"distance",
		"speed",
		"cooldownRemaining",
	},
	stage2_point_completed = { "sessionId", "pointIndex", "name", "attempt", "elapsed", "finalError" },
	stage2_point_corrected = { "sessionId", "pointIndex", "name", "attempt", "deviation" },
	stage2_plate_entered = { "sessionId", "winsBefore", "touchSignal" },
	stage2_reward = { "sessionId", "winsBefore", "winsAfter", "reward", "plateDwell", "elapsed" },
	stage2_spawn_returned = { "sessionId", "spawnDistance", "elapsed" },
	stage2_completed = { "sessionId", "reward", "elapsed", "corrections" },
	stage2_cancelled = { "sessionId", "reason" },
	stage2_failed = { "sessionId", "code", "message" },
	stage5_diagnostic_snapshot = {
		"sessionId",
		"label",
		"pointIndex",
		"elapsed",
		"serverTime",
		"x",
		"y",
		"z",
		"velocityX",
		"velocityY",
		"velocityZ",
		"assemblySpeed",
		"receiveAge",
		"networkOwner",
		"humanoidState",
		"floorMaterial",
		"health",
		"autoRotate",
		"platformStand",
		"raceStageCount",
		"racePlayerStage",
		"raceState",
		"raceLiveState",
		"playerFlags",
		"characterFlags",
		"characterTags",
		"characterDebugId",
		"rootDebugId",
		"eventsDropped",
		"cheatHistoryCount",
		"cheatReason",
		"cheatBlock",
		"cheatRequired",
		"cheatTime",
		"cheatLevel",
		"raceDataCheckpoint",
		"raceDataCount",
		"raceDataVersion",
	},
	stage5_motion_summary = {
		"sessionId",
		"driver",
		"pointIndex",
		"name",
		"attempt",
		"outcome",
		"frameCount",
		"duration",
		"targetDistance",
		"meanFrameDelta",
		"maxFrameDelta",
		"maxDeviation",
		"maxActualSpeed",
		"maxAssemblySpeed",
		"commandedDistance",
	},
	stage5_server_signal = { "sessionId", "source", "elapsed", "arg1", "arg2", "arg3", "x", "y", "z" },
	collector_started = { "sessionId", "enabled" },
	collector_configured = { "sessionId", "enabled" },
	collector_target = { "sessionId", "collectorKind", "variant" },
	collector_movement = { "collectorKind", "distance", "speed" },
	collector_result = { "sessionId", "collectorKind", "variant", "result", "count", "total" },
	collector_safety_stopped = { "sessionId", "collectorKind", "code", "message", "distance" },
	collector_cancelled = { "sessionId", "reason" },
	collector_failed = { "sessionId", "code", "message" },
	event_teleport = { "collectorKind", "destination", "distance" },
	events_safety_stop = { "message" },
	motion_probe_started = { "sessionId" },
	motion_probe_variant_completed = {
		"sessionId",
		"variant",
		"frameCount",
		"duration",
		"meanFrameDelta",
		"p95FrameDelta",
		"maxFrameDelta",
		"meanStep",
		"stepVariance",
		"forwardRatio",
		"backwardSteps",
		"directionReversals",
		"maxBackwardStep",
		"maxLateralError",
		"maxDeviation",
		"stallsOver100ms",
		"finalError",
	},
	motion_probe_completed = { "sessionId", "variantsCompleted" },
	motion_probe_cancelled = { "sessionId", "reason" },
	motion_probe_failed = { "sessionId", "code", "message" },
	observation_captured = {
		"schemaVersion",
		"capturedAt",
		"placeSupported",
		"characterState",
		"rootPresent",
		"atSpawn",
		"winsState",
		"winsAvailable",
		"winBlock32State",
		"winBlock32Available",
	},
	observation_failed = { "code", "message" },
	cleanup_failed = { "label", "errorCode", "message" },
}

for _, stageKey in ipairs({ "stage3", "stage4", "stage5", "stage6", "stage7", "stage8", "stage9" }) do
	for _, suffix in ipairs({
		"started",
		"point_started",
		"point_completed",
		"point_corrected",
		"plate_entered",
		"reward",
		"spawn_returned",
		"completed",
		"cancelled",
		"failed",
	}) do
		local kind = stageKey .. "_" .. suffix
		ALLOWED_KINDS[kind] = true
		KIND_FIELDS[kind] = KIND_FIELDS["stage2_" .. suffix]
	end
end
for _, stageKey in ipairs({ "stage6", "stage7", "stage8", "stage9" }) do
	local kind = stageKey .. "_tsunami_gate"
	ALLOWED_KINDS[kind] = true
	KIND_FIELDS[kind] = { "sessionId", "status", "point" }
end

local function now()
	return os.time()
end

local function copyPlain(value, seen)
	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "number" then
		return value
	end

	if valueType == "string" then
		return value
	end

	if valueType ~= "table" then
		return nil
	end

	seen = seen or {}
	if seen[value] then
		return nil
	end

	seen[value] = true
	local result = {}
	for key, item in pairs(value) do
		if type(key) == "string" then
			local copied = copyPlain(item, seen)
			if copied ~= nil then
				result[key] = copied
			end
		end
	end
	seen[value] = nil
	return result
end

local function sanitizeText(value)
	if type(value) ~= "string" then
		return nil
	end

	local sanitized = value
		:gsub("[%c]", " ")
		:gsub("[A-Za-z]:[\\/][^%s]+", "[redacted-path]")
		:gsub("/[A-Za-z0-9_%.%-/]+", "[redacted-path]")
		:gsub("\\[A-Za-z0-9_%.%-\\]+", "[redacted-path]")
		:gsub("[Jj]ob[Ii][Dd]%s*[:=]%s*[^%s,;]+", "JobId=[redacted]")
		:gsub("[Pp]lace[Ii][Dd]%s*[:=]%s*[^%s,;]+", "PlaceId=[redacted]")
		:gsub("[Uu]ser[Ii][Dd]%s*[:=]%s*[^%s,;]+", "UserId=[redacted]")
		:gsub("[Ss]erver%s*[Ii][Dd]%s*[:=]%s*[^%s,;]+", "ServerId=[redacted]")
		:gsub("[Pp]layers%.[A-Za-z0-9_]+", "Players.[redacted]")
		:gsub("[Pp]layer%s*[:=]%s*[^%s,;]+", "player=[redacted]")
		:gsub("[Tt]oken%s*[:=]%s*[^%s,;]+", "token=[redacted]")
		:gsub("[Cc]ookie%s*[:=]%s*[^%s,;]+", "cookie=[redacted]")
		:gsub("[Aa]uthorization%s*[:=]%s*[^%s,;]+", "authorization=[redacted]")

	if #sanitized > MAX_TEXT_LENGTH then
		sanitized = string.sub(sanitized, 1, MAX_TEXT_LENGTH)
	end

	return sanitized
end

local function normalizeError(code, value)
	local message = sanitizeText(tostring(value)) or "diagnostic operation failed"
	return {
		code = code,
		message = message,
	}
end

local function safeBasename(path)
	if type(path) ~= "string" then
		return nil
	end

	local basename = string.match(path, "([^/\\]+)$")
	if not basename or basename == "" then
		return nil
	end

	return sanitizeText(basename)
end

local function sanitizeFields(kind, fields)
	if fields == nil then
		return {}
	end
	if type(fields) ~= "table" then
		return nil, normalizeError("trace_record_invalid", "diagnostic fields must be a table")
	end

	local result = {}
	for _, field in ipairs(KIND_FIELDS[kind]) do
		local value = fields[field]
		if value ~= nil then
			if
				field == "generation"
				or field == "schemaVersion"
				or field == "capturedAt"
				or field == "winsBefore"
				or field == "winsAfter"
				or field == "reward"
				or field == "distance"
				or field == "elapsed"
				or field == "finalError"
				or field == "cycle"
				or field == "rewardInterval"
				or field == "plateDwell"
				or field == "waited"
				or field == "spawnDistance"
				or field == "pointIndex"
				or field == "attempt"
				or field == "deviation"
				or field == "corrections"
				or field == "frameCount"
				or field == "duration"
				or field == "meanFrameDelta"
				or field == "p95FrameDelta"
				or field == "maxFrameDelta"
				or field == "meanStep"
				or field == "stepVariance"
				or field == "forwardRatio"
				or field == "backwardSteps"
				or field == "directionReversals"
				or field == "maxBackwardStep"
				or field == "maxLateralError"
				or field == "maxDeviation"
				or field == "stallsOver100ms"
				or field == "variantsCompleted"
				or field == "serverTime"
				or field == "x"
				or field == "y"
				or field == "z"
				or field == "velocityX"
				or field == "velocityY"
				or field == "velocityZ"
				or field == "assemblySpeed"
				or field == "receiveAge"
				or field == "health"
				or field == "raceStageCount"
				or field == "racePlayerStage"
				or field == "eventsDropped"
				or field == "targetDistance"
				or field == "maxActualSpeed"
				or field == "maxAssemblySpeed"
				or field == "commandedDistance"
				or field == "cheatHistoryCount"
				or field == "cheatRequired"
				or field == "cheatTime"
				or field == "cheatLevel"
				or field == "raceDataCheckpoint"
				or field == "raceDataCount"
				or field == "raceDataVersion"
				or field == "count"
				or field == "total"
				or field == "speed"
				or field == "cooldownRemaining"
			then
				if type(value) == "number" then
					result[field] = value
				end
			elseif
				field == "placeSupported"
				or field == "ok"
				or field == "rootPresent"
				or field == "atSpawn"
				or field == "winsAvailable"
				or field == "winBlock32Available"
				or field == "touchSignal"
				or field == "networkOwner"
				or field == "autoRotate"
				or field == "platformStand"
			then
				if type(value) == "boolean" then
					result[field] = value
				end
			elseif
				field == "version"
				or field == "traceState"
				or field == "name"
				or field == "kind"
				or field == "sessionId"
				or field == "reason"
				or field == "code"
				or field == "label"
				or field == "errorCode"
				or field == "message"
				or field == "mode"
				or field == "characterState"
				or field == "winsState"
				or field == "winBlock32State"
				or field == "variant"
				or field == "outcome"
				or field == "driver"
				or field == "source"
				or field == "arg1"
				or field == "arg2"
				or field == "arg3"
				or field == "humanoidState"
				or field == "floorMaterial"
				or field == "raceState"
				or field == "raceLiveState"
				or field == "playerFlags"
				or field == "characterFlags"
				or field == "characterTags"
				or field == "cheatReason"
				or field == "cheatBlock"
				or field == "characterDebugId"
				or field == "rootDebugId"
				or field == "enabled"
				or field == "collectorKind"
				or field == "destination"
				or field == "result"
			then
				local sanitized = sanitizeText(value)
				if sanitized then
					result[field] = sanitized
				end
			end
		end
	end

	return result
end

function Trace.new(path)
	local fileName = safeBasename(path)
	if not fileName then
		return nil, normalizeError("trace_create_failed", "diagnostic path is invalid")
	end
	if not string.match(path, "^potassium%-next/diagnostics/[^/\\]+$") then
		return nil, normalizeError("trace_create_failed", "diagnostic path is outside the allowed folder")
	end

	local folderChecked, folderExists = pcall(isfolder, DIRECTORY)
	if not folderChecked then
		return nil, normalizeError("trace_create_failed", folderExists)
	end

	if not folderExists then
		local made, makeError = pcall(makefolder, DIRECTORY)
		if not made then
			return nil, normalizeError("trace_create_failed", makeError)
		end
	end

	local created, createError = pcall(writefile, path, "")
	if not created then
		return nil, normalizeError("trace_create_failed", createError)
	end

	return setmetatable({
		fileName = fileName,
		path = path,
		state = "READY",
		lastError = nil,
		queue = {},
		writing = false,
	}, Trace)
end

function Trace:_fail(code, value)
	local errorValue = normalizeError(code, value)
	self.state = "ERROR"
	self.lastError = errorValue
	return nil, copyPlain(errorValue)
end

function Trace:flush()
	if self.writing then
		return true
	end

	self.writing = true
	while #self.queue > 0 do
		local line = self.queue[1]
		local appended, appendError = pcall(appendfile, self.path, line)
		if not appended then
			self.writing = false
			return self:_fail("trace_write_failed", appendError)
		end
		table.remove(self.queue, 1)
	end
	self.writing = false
	return true
end

function Trace:record(kind, fields)
	if self.state == "ERROR" then
		return nil, copyPlain(self.lastError)
	end
	if not ALLOWED_KINDS[kind] then
		return self:_fail("trace_record_invalid", "diagnostic kind is not allowed")
	end

	local sanitizedFields, fieldsError = sanitizeFields(kind, fields)
	if not sanitizedFields then
		return self:_fail(fieldsError.code, fieldsError.message)
	end

	local event = {
		kind = kind,
		at = now(),
	}
	for key, value in pairs(sanitizedFields) do
		event[key] = value
	end

	local encoded, jsonOrError = pcall(HttpService.JSONEncode, HttpService, event)
	if not encoded then
		return self:_fail("trace_write_failed", jsonOrError)
	end

	table.insert(self.queue, jsonOrError .. "\n")
	return self:flush()
end

function Trace:recordRequired(kind, fields)
	if self.state == "ERROR" then
		return nil, copyPlain(self.lastError)
	end
	if self.writing then
		return self:_fail("trace_write_failed", "diagnostic writer is busy")
	end
	if #self.queue > 0 then
		local flushed, flushError = self:flush()
		if not flushed then
			return nil, flushError
		end
	end
	if not ALLOWED_KINDS[kind] then
		return self:_fail("trace_record_invalid", "diagnostic kind is not allowed")
	end

	local sanitizedFields, fieldsError = sanitizeFields(kind, fields)
	if not sanitizedFields then
		return self:_fail(fieldsError.code, fieldsError.message)
	end
	local event = {
		kind = kind,
		at = now(),
	}
	for key, value in pairs(sanitizedFields) do
		event[key] = value
	end
	local encoded, jsonOrError = pcall(HttpService.JSONEncode, HttpService, event)
	if not encoded then
		return self:_fail("trace_write_failed", jsonOrError)
	end
	local appended, appendError = pcall(appendfile, self.path, jsonOrError .. "\n")
	if not appended then
		return self:_fail("trace_write_failed", appendError)
	end
	return true
end

function Trace:status()
	return copyPlain({
		state = self.state,
		fileName = self.fileName,
		lastError = self.lastError,
	})
end

return Trace
