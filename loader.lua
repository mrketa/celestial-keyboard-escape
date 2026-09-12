--!strict

local BASE_URL = "https://raw.githubusercontent.com/mrketa/celestial-keyboard-escape/8d8c3fab97f73e3c327e4d65ad046282e04727d6/"
local ENTRY_PATH = "keyboard-escape/autofarm.lua"
local MODULES = {
	["keyboard-escape/autofarm.lua"] = "fc8f0c8c672bea06eb6e50b9791e5168f21c6aecbb16d10e1721044128111136",
	["keyboard-escape/keyboard_escape_runtime.lua"] = "b9bd4aa6ef7ad6c5a6b3bed05ad4db2acefcee66a9b9480cdf760658810f220f",
	["keyboard-escape/admin_event_collectors.lua"] = "57329b8a28f3bde9615f92a51588b394727f402c86363106a3ad28c5083bbc34",
	["keyboard-escape/keyboard_escape_menu.lua"] = "6861561f6b84bfeee63dd316c4e4e2f0661032023b36a11b3781661f70cb220d",
	["keyboard-escape/potassium-ui.lua"] = "83a969770b11d2573b2f13b005755fcb56caf0f91c54696004a9c0c17d13e217",
}

local function loaderError(code: string): never
	error("Keyboard Escape loader: " .. code, 0)
end

if type(isfolder) ~= "function" or type(makefolder) ~= "function" or type(writefile) ~= "function" or type(readfile) ~= "function" then
	loaderError("filesystem_unavailable")
end
if type(loadstring) ~= "function" then
	loaderError("loadstring_unavailable")
end
if type(crypt) ~= "table" or type(crypt.hash) ~= "function" then
	loaderError("sha256_unavailable")
end

local downloaded = {}
for path, expectedHash in pairs(MODULES) do
	local fetched, source = pcall(function()
		return game:HttpGet(BASE_URL .. path, true)
	end)
	if not fetched or type(source) ~= "string" or source == "" then
		loaderError("download_failed:" .. path)
	end
	local hashed, actualHash = pcall(function()
		return string.lower(crypt.hash(source, "sha256"))
	end)
	if not hashed or actualHash ~= expectedHash then
		loaderError("integrity_failed:" .. path)
	end
	downloaded[path] = source
end

if not isfolder("keyboard-escape") then
	local created, createError = pcall(makefolder, "keyboard-escape")
	if not created then
		loaderError("directory_failed:" .. tostring(createError))
	end
end

for path, source in pairs(downloaded) do
	local written = pcall(writefile, path, source)
	if not written then
		loaderError("write_failed:" .. path)
	end
end

local chunk, compileError = loadstring(downloaded[ENTRY_PATH], "@KeyboardEscape/autofarm.lua")
if type(chunk) ~= "function" then
	loaderError("compile_failed:" .. tostring(compileError))
end
local executed, runtimeOrError = pcall(chunk)
if not executed then
	loaderError("runtime_failed:" .. tostring(runtimeOrError))
end
local environmentOk, environment = pcall(getgenv)
if
	type(runtimeOrError) ~= "table"
	or not environmentOk
	or type(environment) ~= "table"
	or environment.KeyboardEscapeAutoFarm ~= runtimeOrError
then
	loaderError("runtime_export_invalid")
end

return runtimeOrError
