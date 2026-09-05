--!strict

local BASE_URL = "https://raw.githubusercontent.com/mrketa/celestial-keyboard-escape/7ee146202ff900a59f9d97b57a9a0a1e88936235/"
local ENTRY_PATH = "keyboard-escape/autofarm.lua"
local MODULES = {
	["keyboard-escape/autofarm.lua"] = "77e07ceac626cb181e449d0befb72c5bf625bea2eecfad1f4a3b277edc6e8f47",
	["keyboard-escape/keyboard_escape_runtime.lua"] = "7c5d7507c1148b2395fb6469cd2f9b72579b42771d49309240727c4d2a531257",
	["keyboard-escape/admin_event_collectors.lua"] = "d20b602904f655bec31a666e7dfdbea74486b37f76c23de74c13d7c55f1fae7f",
	["keyboard-escape/keyboard_escape_menu.lua"] = "16536f73e45044d49fafb6080fc3eb63eccc123148466838e639bf5e324d35cd",
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
