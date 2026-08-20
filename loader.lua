--!strict

local BASE_URL = "https://raw.githubusercontent.com/mrketa/celestial-keyboard-escape/main/"
local ENTRY_PATH = "potassium-next/entry.lua"
local MODULES = {
	["potassium-next/entry.lua"] = "15cda30d0b0a4490bd96334baf7499d02776f33813a151617b1ae5e653c7b01c",
	["potassium-next/runtime.lua"] = "0cc933d63e099b17cef23205b6b1878e9bc647cf58e290cfb6cd9318fc10ee0d",
	["potassium-next/trace.lua"] = "2ac5d32a5f0fe6ece988d26ab01085f230c90fe09a0b1ca1b0b96e46b4caa555",
	["potassium-next/menu.lua"] = "dd99e42aca38e7e839adb728bfe4f3b9a09d4f638769d8ef7de8c3bcf934cfd0",
	["potassium-next/world3_route.lua"] = "9d913ddd869e4f9b70acd949dbeec32937fab6834e6e360e612ba5e8ac1b887e",
	["potassium-next/world3_routes.lua"] = "05badb3613d4aa3a43cd0bede0ff40a7b0e34416d11162963e327c0a943a4196",
	["potassium-next/movement.lua"] = "643a13d2f79d3a2114f99d16721717a05a1d097c0de6d73f092663b44c4cdff1",
	["potassium-next/event_collectors.lua"] = "09f0bbb595ef1d06ed9468c418187ff3a52c2066723ad0f3effdaf052759a100",
	["potassium-next/stage1.lua"] = "f3473a8e30382ba3932926ee6b03a2d79a4e230527e08b3ac5b9d6b04f03bd24",
	["potassium-next/stage5_diagnostics.lua"] = "0c47834a35e12c466f74879bb7521bd69a876eb7bdf00821a1c81e7816edfa61",
	["potassium-next/motion_probe.lua"] = "b1a31fa87a98c93a2b668011c79aae264895dacfae49a33ea2463e8ef5d1f978",
	["potassium-next/observation.lua"] = "44615420af998c4814405b0358353431789a0d930ec79d8ae17e4e8aab368d3a",
}

local function loaderError(code: string): never
	error("Celestial Keyboard Escape loader: " .. code, 0)
end

if type(isfolder) ~= "function" or type(makefolder) ~= "function" or type(writefile) ~= "function" then
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

if not isfolder("potassium-next") then
	local created, createError = pcall(makefolder, "potassium-next")
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

local chunk, compileError = loadstring(downloaded[ENTRY_PATH], "@potassium-next/entry.lua")
if type(chunk) ~= "function" then
	loaderError("compile_failed:" .. tostring(compileError))
end
return chunk()
