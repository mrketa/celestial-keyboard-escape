--!strict

local BASE_URL = "https://raw.githubusercontent.com/mrketa/celestial-keyboard-escape/62003665b4178611469960c26f00eae1ad88f389/"
local ENTRY_PATH = "keyboard-escape/autofarm.lua"
local MODULES = {
	["keyboard-escape/autofarm.lua"] = "77e07ceac626cb181e449d0befb72c5bf625bea2eecfad1f4a3b277edc6e8f47",
	["keyboard-escape/keyboard_escape_runtime.lua"] = "ff15bbdfc40ae36666be92a14fb9ab8d62a5f1b132891a8f97ae3a4cdec428f0",
	["keyboard-escape/admin_event_collectors.lua"] = "57329b8a28f3bde9615f92a51588b394727f402c86363106a3ad28c5083bbc34",
	["keyboard-escape/keyboard_escape_menu.lua"] = "4742d8c903d02f85fc3777e60b5b85632f18f81b29a61f1968960e0809d56518",
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
