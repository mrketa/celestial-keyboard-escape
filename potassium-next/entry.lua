--!strict

local VERSION = "0.1.0-beta.2"
local MODULE_ROOT = "potassium-next/"
local EXPORT_NAME = "PotassiumNextRuntime"
local MODULE_HASHES = {
	["potassium-next/trace.lua"] = "2ac5d32a5f0fe6ece988d26ab01085f230c90fe09a0b1ca1b0b96e46b4caa555",
	["potassium-next/runtime.lua"] = "dc030e245ecdc81ece3303978849c795f468eb23caa45b212ba5e0effa705283",
	["potassium-next/menu.lua"] = "e57cbe848466abe572ffc07bddbf1ab169512544f33fe05cb9bad3423581dda3",
	["potassium-next/event_collectors.lua"] = "0a99b98728d051a244dc554c507e05e7e3897d58d081f07e377f7a92e291d40b",
	["potassium-next/stage1.lua"] = "f3473a8e30382ba3932926ee6b03a2d79a4e230527e08b3ac5b9d6b04f03bd24",
	["potassium-next/world3_route.lua"] = "9d913ddd869e4f9b70acd949dbeec32937fab6834e6e360e612ba5e8ac1b887e",
	["potassium-next/world3_routes.lua"] = "05badb3613d4aa3a43cd0bede0ff40a7b0e34416d11162963e327c0a943a4196",
	["potassium-next/movement.lua"] = "643a13d2f79d3a2114f99d16721717a05a1d097c0de6d73f092663b44c4cdff1",
	["potassium-next/observation.lua"] = "44615420af998c4814405b0358353431789a0d930ec79d8ae17e4e8aab368d3a",
	["potassium-next/motion_probe.lua"] = "b1a31fa87a98c93a2b668011c79aae264895dacfae49a33ea2463e8ef5d1f978",
	["potassium-next/stage5_diagnostics.lua"] = "0c47834a35e12c466f74879bb7521bd69a876eb7bdf00821a1c81e7816edfa61",
}
local function entryError(code: string): never
	error("PotassiumNext entry: " .. code, 0)
end

local function loadModule(path: string, chunkName: string): any
	local expectedHash = MODULE_HASHES[path]
	if expectedHash == nil then
		entryError("module_untrusted:" .. chunkName)
	end

	local readOk, source = pcall(readfile, path)
	if not readOk or type(source) ~= "string" then
		entryError("module_read_failed:" .. chunkName)
	end

	local hashOk, actualHash = pcall(function()
		return crypt.hash(source, "sha256")
	end)
	if not hashOk or type(actualHash) ~= "string" then
		entryError("module_hash_failed:" .. chunkName)
	end
	if string.lower(actualHash) ~= expectedHash then
		entryError("module_integrity_failed:" .. chunkName)
	end

	local compileOk, chunkOrError = pcall(loadstring, source, chunkName)
	if not compileOk or type(chunkOrError) ~= "function" then
		entryError("module_compile_failed:" .. chunkName)
	end

	local executeOk, moduleOrError = pcall(chunkOrError)
	if not executeOk then
		entryError("module_execute_failed:" .. chunkName)
	end
	if type(moduleOrError) ~= "table" then
		entryError("module_invalid:" .. chunkName)
	end
	return moduleOrError
end

local function callEject(runtime: any, reason: string): boolean
	if type(runtime) ~= "table" or type(runtime.Eject) ~= "function" then
		return false
	end

	local callOk, success = pcall(runtime.Eject, runtime, reason)
	return callOk and success == true
end

local function predecessorGeneration(runtime: any): number
	if type(runtime) ~= "table" or type(runtime.snapshot) ~= "function" then
		return 0
	end

	local snapshotOk, snapshot = pcall(runtime.snapshot, runtime)
	if not snapshotOk or type(snapshot) ~= "table" then
		return 0
	end

	local generation = snapshot.generation
	if
		type(generation) ~= "number"
		or generation ~= generation
		or generation == math.huge
		or generation == -math.huge
	then
		return 0
	end

	return math.max(0, math.floor(generation))
end

local Trace = loadModule(MODULE_ROOT .. "trace.lua", "@PotassiumNext/trace")
local Stage1 = loadModule(MODULE_ROOT .. "stage1.lua", "@PotassiumNext/stage1")
local World3Route = loadModule(MODULE_ROOT .. "world3_route.lua", "@PotassiumNext/world3_route")
local World3Routes = loadModule(MODULE_ROOT .. "world3_routes.lua", "@PotassiumNext/world3_routes")
local Stage5Diagnostics = loadModule(MODULE_ROOT .. "stage5_diagnostics.lua", "@PotassiumNext/stage5_diagnostics")
local Observation = loadModule(MODULE_ROOT .. "observation.lua", "@PotassiumNext/observation")
local Movement = loadModule(MODULE_ROOT .. "movement.lua", "@PotassiumNext/movement")
local MotionProbe = loadModule(MODULE_ROOT .. "motion_probe.lua", "@PotassiumNext/motion_probe")
local EventCollectors = loadModule(MODULE_ROOT .. "event_collectors.lua", "@PotassiumNext/event_collectors")
local Runtime = loadModule(MODULE_ROOT .. "runtime.lua", "@PotassiumNext/runtime")
local Menu = loadModule(MODULE_ROOT .. "menu.lua", "@PotassiumNext/menu")

if type(Trace.new) ~= "function" then
	entryError("module_invalid:trace")
end
if
	type(Stage1.newSession) ~= "function"
	or type(Stage1.snapshot) ~= "function"
	or type(Stage1.beginHold) ~= "function"
	or type(Stage1.pollHold) ~= "function"
	or type(Stage1.stopHold) ~= "function"
then
	entryError("module_invalid:stage1")
end
if type(World3Route.create) ~= "function" then
	entryError("module_invalid:world3_route")
end
if
	type(World3Routes.stage2) ~= "table"
	or type(World3Routes.stage3) ~= "table"
	or type(World3Routes.stage4) ~= "table"
	or type(World3Routes.stage5) ~= "table"
	or type(World3Routes.stage6) ~= "table"
	or type(World3Routes.stage7) ~= "table"
	or type(World3Routes.stage8) ~= "table"
	or type(World3Routes.stage9) ~= "table"
then
	entryError("module_invalid:world3_routes")
end
local coursesCallOk, Courses = pcall(function()
	return table.freeze({
		stage2 = World3Route.create(World3Routes.stage2),
		stage3 = World3Route.create(World3Routes.stage3),
		stage4 = World3Route.create(World3Routes.stage4),
		stage5 = World3Route.create(World3Routes.stage5),
		stage6 = World3Route.create(World3Routes.stage6),
		stage7 = World3Route.create(World3Routes.stage7),
		stage8 = World3Route.create(World3Routes.stage8),
		stage9 = World3Route.create(World3Routes.stage9),
	})
end)
if not coursesCallOk or type(Courses) ~= "table" then
	entryError("course_policy_initialization_failed")
end
for _, stageKey in { "stage2", "stage3", "stage4", "stage5", "stage6", "stage7", "stage8", "stage9" } do
	local policy = Courses[stageKey]
	if
		type(policy) ~= "table"
		or type(policy.newSession) ~= "function"
		or type(policy.run) ~= "function"
		or type(policy.stop) ~= "function"
		or type(policy.snapshot) ~= "function"
	then
		entryError("module_invalid:" .. stageKey)
	end
end
if
	type(Stage5Diagnostics.newSession) ~= "function"
	or type(Stage5Diagnostics.start) ~= "function"
	or type(Stage5Diagnostics.sample) ~= "function"
	or type(Stage5Diagnostics.motion) ~= "function"
	or type(Stage5Diagnostics.stop) ~= "function"
then
	entryError("module_invalid:stage5_diagnostics")
end
if
	type(Movement.newSafeStart) ~= "function"
	or type(Movement.snapshot) ~= "function"
	or type(Movement.runSafeStart) ~= "function"
	or type(Movement.stop) ~= "function"
then
	entryError("module_invalid:movement")
end
if
	type(MotionProbe.newSession) ~= "function"
	or type(MotionProbe.run) ~= "function"
	or type(MotionProbe.stop) ~= "function"
	or type(MotionProbe.snapshot) ~= "function"
then
	entryError("module_invalid:motion_probe")
end
if type(EventCollectors.create) ~= "function" then
	entryError("module_invalid:event_collectors")
end
local eventPolicyCallOk, EventPolicy = pcall(function()
	return EventCollectors.create({})
end)
if
	not eventPolicyCallOk
	or type(EventPolicy) ~= "table"
	or type(EventPolicy.newSession) ~= "function"
	or type(EventPolicy.run) ~= "function"
	or type(EventPolicy.configure) ~= "function"
	or type(EventPolicy.stop) ~= "function"
	or type(EventPolicy.snapshot) ~= "function"
then
	entryError("event_policy_initialization_failed")
end
if type(Observation.capture) ~= "function" then
	entryError("module_invalid:observation")
end
if type(Runtime.new) ~= "function" then
	entryError("module_invalid:runtime")
end
if type(Menu.new) ~= "function" then
	entryError("module_invalid:menu")
end

local environmentOk, environment = pcall(getgenv)
if not environmentOk or type(environment) ~= "table" then
	entryError("environment_unavailable")
end

local executorCallOk, executorName, executorVersion = pcall(identifyexecutor)
if not executorCallOk or type(executorName) ~= "string" then
	executorName = nil
end
if type(executorVersion) ~= "string" then
	executorVersion = nil
end

local predecessor = environment[EXPORT_NAME]
local generation = predecessorGeneration(predecessor) + 1
if predecessor ~= nil then
	if not callEject(predecessor, "reload") then
		entryError("predecessor_eject_failed")
	end

	if environment[EXPORT_NAME] ~= nil then
		entryError("predecessor_lease_retained")
	end
end

local nowOk, unix = pcall(os.time)
if not nowOk or type(unix) ~= "number" then
	unix = 0
end
local HttpService = game:GetService("HttpService")
local nonceOk, nonce = pcall(HttpService.GenerateGUID, HttpService, false)
if not nonceOk or type(nonce) ~= "string" then
	nonce = tostring(math.floor(os.clock() * 1000000))
else
	nonce = string.sub(string.gsub(nonce, "%-", ""), 1, 12)
end

local tracePath = MODULE_ROOT
	.. "diagnostics/runtime-"
	.. tostring(math.floor(unix))
	.. "-"
	.. nonce
	.. "-g"
	.. tostring(generation)
	.. ".ndjson"

local traceCallOk, trace, traceInitError = pcall(Trace.new, tracePath)
if not traceCallOk then
	trace = nil
	traceInitError = {
		code = "trace_create_failed",
		message = "Trace initialization failed",
	}
elseif trace == nil and traceInitError == nil then
	traceInitError = {
		code = "trace_create_failed",
		message = "Trace initialization failed",
	}
end

local menu: any = nil
local runtime: any = nil
local facade: any = nil

local function destroyMenu(): any
	if menu == nil then
		return true
	end
	return menu:Destroy()
end

local function menuStats(): any
	if menu == nil then
		return { connections = 0 }
	end
	return menu:stats()
end

local runtimeCallOk, runtimeResult = pcall(Runtime.new, {
	version = VERSION,
	generation = generation,
	trace = trace,
	traceInitError = traceInitError,
	traceFileName = tracePath,
	placeSupported = game.PlaceId == 93411036959889,
	characterState = "MISSING",
	exportIdentity = function()
		return facade
	end,
	executorName = executorName,
	executorVersion = executorVersion,
	destroyMenu = destroyMenu,
	menuStats = menuStats,
	stage1 = Stage1,
	movement = Movement,
	courses = Courses,
	stage5Diagnostics = Stage5Diagnostics,
	motionProbe = MotionProbe,
	eventCollectors = EventPolicy,
	observation = Observation,
})

if not runtimeCallOk or runtimeResult == nil then
	if trace ~= nil and type(trace.flush) == "function" then
		pcall(trace.flush, trace)
	end
	entryError("runtime_initialization_failed")
end
runtime = runtimeResult

local stage1Facade = {
	startHold = function(_self: any)
		return runtime:startStage1Hold()
	end,
	runOnce = function(_self: any)
		return runtime:startStage1Hold(true)
	end,
	auto = function(_self: any)
		return runtime:startStage1Pulse()
	end,
}
table.freeze(stage1Facade)
local stage2Facade = {
	runOnce = function(_self: any)
		return runtime:startStage2Once()
	end,
}
table.freeze(stage2Facade)
local stage3Facade = {
	runOnce = function(_self: any)
		return runtime:startStage3Once()
	end,
}
table.freeze(stage3Facade)
local stage4Facade = {
	runOnce = function(_self: any)
		return runtime:startStage4Once()
	end,
}
table.freeze(stage4Facade)
local stage5Facade = {
	runOnce = function(_self: any)
		return runtime:startStage5Once()
	end,
}
table.freeze(stage5Facade)
local stage6Facade = {
	runOnce = function(_self: any)
		return runtime:startStage6Once()
	end,
}
table.freeze(stage6Facade)
local stage7Facade = {
	runOnce = function(_self: any)
		return runtime:startStage7Once()
	end,
}
table.freeze(stage7Facade)
local stage8Facade = {
	runOnce = function(_self: any)
		return runtime:startStage8Once()
	end,
}
table.freeze(stage8Facade)
local stage9Facade = {
	runOnce = function(_self: any)
		return runtime:startStage9Once()
	end,
}
table.freeze(stage9Facade)
local motionProbeFacade = {
	run = function(_self: any)
		return runtime:startMotionProbe()
	end,
}
table.freeze(motionProbeFacade)
local movementFacade = {
	moveToSafeStart = function(_self: any)
		return runtime:startSafeStart()
	end,
}
table.freeze(movementFacade)
local eventsFacade = {
	start = function(_self: any, config: any)
		return runtime:startCollectors(config)
	end,
	configure = function(_self: any, config: any)
		return runtime:configureCollectors(config)
	end,
}
table.freeze(eventsFacade)

facade = {
	snapshot = function(_self: any)
		return runtime:snapshot()
	end,
	observe = function(_self: any)
		return runtime:observe()
	end,
	command = function(_self: any, name: string, payload: any)
		return runtime:command(name, payload)
	end,
	Eject = function(_self: any, reason: any)
		return runtime:Eject(reason)
	end,
	stage1 = stage1Facade,
	stage2 = stage2Facade,
	stage3 = stage3Facade,
	stage4 = stage4Facade,
	stage5 = stage5Facade,
	stage6 = stage6Facade,
	stage7 = stage7Facade,
	stage8 = stage8Facade,
	stage9 = stage9Facade,
	movement = movementFacade,
	motionProbe = motionProbeFacade,
	events = eventsFacade,
}
table.freeze(facade)

local menuCallOk, menuResult = pcall(Menu.new, {
	snapshot = function()
		return runtime:snapshot()
	end,
	command = function(name: string, payload: any)
		return runtime:command(name, payload)
	end,
	runStage1Auto = function()
		return runtime:startStage1Pulse()
	end,
	runStageOnce = function(stageKey: string)
		if stageKey == "stage2" then
			return runtime:startStage2Once()
		elseif stageKey == "stage3" then
			return runtime:startStage3Once()
		elseif stageKey == "stage4" then
			return runtime:startStage4Once()
		elseif stageKey == "stage5" then
			return runtime:startStage5Once()
		elseif stageKey == "stage6" then
			return runtime:startStage6Once()
		elseif stageKey == "stage7" then
			return runtime:startStage7Once()
		elseif stageKey == "stage8" then
			return runtime:startStage8Once()
		elseif stageKey == "stage9" then
			return runtime:startStage9Once()
		end
		return nil, nil, { code = "course_unknown", message = "course stage is not supported" }
	end,
	startCollectors = function(config: any)
		return runtime:startCollectors(config)
	end,
	configureCollectors = function(config: any)
		return runtime:configureCollectors(config)
	end,
})

if not menuCallOk or menuResult == nil then
	callEject(runtime, "init_failed")
	entryError("menu_initialization_failed")
end
menu = menuResult

local showCallOk, showOk = pcall(menu.Show, menu)
if not showCallOk or showOk ~= true then
	callEject(runtime, "init_failed")
	entryError("menu_show_failed")
end

if environment[EXPORT_NAME] ~= nil then
	callEject(runtime, "init_failed")
	entryError("export_lease_unavailable")
end

environment[EXPORT_NAME] = facade

return facade
