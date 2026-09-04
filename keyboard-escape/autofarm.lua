--!strict

local MODULE_ROOT = "keyboard-escape/"
local PLACE_ID = 93411036959889
local EXPORT_NAME = "KeyboardEscapeAutoFarm"
local INITIALIZATION_NAME = EXPORT_NAME .. "Initialization"
local UI_BUNDLES = {
	MODULE_ROOT .. "potassium-ui.lua",
	"potassium-ui.lua",
	"potassium-ui/dist/potassium-ui.lua",
}

local initializationEnvironment: any = nil
local initializationToken: any = nil

local function entryError(code: string, detail: any?): never
	if
		initializationEnvironment ~= nil
		and initializationToken ~= nil
		and initializationEnvironment[INITIALIZATION_NAME] == initializationToken
	then
		initializationEnvironment[INITIALIZATION_NAME] = nil
	end
	local suffix = if detail == nil then "" else ":" .. tostring(detail)
	error("Keyboard Escape entry: " .. code .. suffix, 0)
end

local function loadValue(path: string, chunkName: string, source: string?): any
	local readOk = true
	if source == nil then readOk, source = pcall(readfile, path) end
	if not readOk or type(source) ~= "string" then
		entryError("read_failed", chunkName)
	end

	local compileOk, chunkOrError = pcall(loadstring, source, chunkName)
	if not compileOk or type(chunkOrError) ~= "function" then
		entryError("compile_failed", chunkName)
	end

	local executeOk, value = pcall(chunkOrError)
	if not executeOk then
		entryError("execute_failed", chunkName)
	end
	return value
end

local function firstReadablePath(paths: { string }): (string, string)
	for _, path in ipairs(paths) do
		local readOk, source = pcall(readfile, path)
		if readOk and type(source) == "string" then
			return path, source
		end
	end
	entryError("read_failed", "@PotassiumUI")
end

local environmentOk, environment = pcall(getgenv)
if not environmentOk or type(environment) ~= "table" then
	entryError("environment_unavailable")
end

if game.PlaceId ~= PLACE_ID then
	entryError("unsupported_place")
end

initializationEnvironment = environment
initializationToken = {}
environment[INITIALIZATION_NAME] = initializationToken

local function ownsInitialization(): boolean
	return environment[INITIALIZATION_NAME] == initializationToken
end

local predecessor = environment[EXPORT_NAME]
if predecessor ~= nil then
	if type(predecessor) ~= "table" then
		entryError("predecessor_invalid")
	end
	local eject = if type(predecessor.Destroy) == "function" then predecessor.Destroy else predecessor.Eject
	if type(eject) ~= "function" then
		entryError("predecessor_invalid")
	end
	local ejectOk, ejectError = pcall(eject, predecessor, "reload")
	if not ejectOk then
		entryError("predecessor_ejection_failed", ejectError)
	end
	if environment[EXPORT_NAME] ~= nil then
		entryError("predecessor_lease_retained")
	end
end

local uiPath, uiSource = firstReadablePath(UI_BUNDLES)
local Library = loadValue(uiPath, "@PotassiumUI", uiSource)
local Runtime = loadValue(MODULE_ROOT .. "keyboard_escape_runtime.lua", "@KeyboardEscape/runtime")
local EventCollectors = loadValue(MODULE_ROOT .. "admin_event_collectors.lua", "@KeyboardEscape/admin-event-collectors")
local Menu = loadValue(MODULE_ROOT .. "keyboard_escape_menu.lua", "@KeyboardEscape/menu")
if type(Library) ~= "table" or type(Library.bootstrap) ~= "function" then
	entryError("ui_bundle_invalid")
end
if type(Runtime) ~= "table" or type(Runtime.new) ~= "function" then
	entryError("runtime_module_invalid")
end
if type(Menu) ~= "table" or type(Menu.new) ~= "function" then
	entryError("menu_module_invalid")
end
if type(EventCollectors) ~= "table" or type(EventCollectors.new) ~= "function" or type(EventCollectors.CHOICES) ~= "table" then
	entryError("admin_event_collectors_module_invalid")
end

local runtimeOk, runtimeOrError = pcall(Runtime.new, {
	eventCollectors = EventCollectors,
})
if not runtimeOk or type(runtimeOrError) ~= "table" then
	entryError("runtime_initialization_failed", runtimeOrError)
end
local runtime = runtimeOrError

if not ownsInitialization() then
	pcall(runtime.Destroy, runtime)
	entryError("initialization_superseded")
end

local menuOk, appOrError, menuError = pcall(Menu.new, Library, runtime)
if not menuOk or type(appOrError) ~= "table" then
	pcall(runtime.Destroy, runtime)
	entryError("menu_initialization_failed", if menuOk then menuError else appOrError)
end
local app = appOrError

if not ownsInitialization() then
	pcall(app.Destroy, app)
	pcall(runtime.Destroy, runtime)
	entryError("initialization_superseded")
end

local menuDestroy = app.Destroy
if type(menuDestroy) ~= "function" then
	pcall(runtime.Destroy, runtime)
	entryError("menu_destroy_contract_missing")
end

local destroyed = false
function app:Destroy(reason: any?)
	if destroyed then
		return true
	end
	destroyed = true

	if environment[EXPORT_NAME] == self then
		environment[EXPORT_NAME] = nil
	end

	local menuOk, menuError = pcall(menuDestroy, self, reason)
	local runtimeOk, runtimeError = pcall(runtime.Destroy, runtime)
	if not menuOk then
		error(menuError, 0)
	end
	if not runtimeOk then
		error(runtimeError, 0)
	end
	return true
end

if not ownsInitialization() or environment[EXPORT_NAME] ~= nil then
	pcall(app.Destroy, app, "initialization_superseded")
	entryError("initialization_superseded")
end
environment[EXPORT_NAME] = app
environment[INITIALIZATION_NAME] = nil
return app
