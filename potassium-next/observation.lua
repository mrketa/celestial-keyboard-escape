--!strict

local Players = game:GetService("Players")

local Observation = {}

local WORLD3_PLACE_ID = 93411036959889
local SPAWN_MIN_Y = -300
local SPAWN_MAX_Y = -120
local SPAWN_MAX_Z = -900
local WIN_BLOCK_PATH = "Workspace.Structure.Stage1.SAS.WinBlock32"

local function errorResult(code: string, message: string): { code: string, message: string }
	return { code = code, message = message }
end

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function finiteInteger(value: any): number?
	local number = finiteNumber(value)
	if number == nil or number ~= math.floor(number) then
		return nil
	end
	return number
end

local function vectorSnapshot(value: any): any
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local x = finiteNumber(value.X)
	local y = finiteNumber(value.Y)
	local z = finiteNumber(value.Z)
	if x == nil or y == nil or z == nil then
		return nil
	end
	return table.freeze({ x = x, y = y, z = z })
end

local function readProperty(instance: any, name: string): (boolean, any)
	if instance == nil then
		return false, nil
	end
	local ok, value = pcall(function()
		return instance[name]
	end)
	return ok, value
end

local function find(parent: any, name: string): any
	if parent == nil then
		return nil
	end
	local ok, child = pcall(parent.FindFirstChild, parent, name)
	if not ok then
		return nil
	end
	return child
end

local function findHumanoid(character: any): any
	if character == nil then
		return nil
	end
	local ok, humanoid = pcall(character.FindFirstChildOfClass, character, "Humanoid")
	if not ok then
		return nil
	end
	return humanoid
end

local function isBasePart(instance: any): boolean
	if instance == nil then
		return false
	end
	local ok, result = pcall(instance.IsA, instance, "BasePart")
	return ok and result == true
end

local function characterState(character: any, humanoid: any, root: any, health: number?): string
	if character == nil then
		return "MISSING"
	end
	if humanoid == nil or root == nil then
		return "RESPAWNING"
	end
	if health ~= nil and health <= 0 then
		return "DEAD"
	end
	return "READY"
end

function Observation.capture(): (any, any)
	local player = Players.LocalPlayer
	if player == nil then
		return nil, errorResult("player_unavailable", "LocalPlayer is unavailable")
	end

	local characterOk, character = readProperty(player, "Character")
	if not characterOk then
		return nil, errorResult("observation_read_failed", "Character could not be read")
	end
	local humanoid = findHumanoid(character)
	local root = find(character, "HumanoidRootPart")
	if not isBasePart(root) then
		root = nil
	end

	local healthOk, healthValue = readProperty(humanoid, "Health")
	local maxHealthOk, maxHealthValue = readProperty(humanoid, "MaxHealth")
	local health = healthOk and finiteNumber(healthValue) or nil
	local maxHealth = maxHealthOk and finiteNumber(maxHealthValue) or nil

	local positionOk, positionValue = readProperty(root, "Position")
	local velocityOk, velocityValue = readProperty(root, "AssemblyLinearVelocity")
	local anchoredOk, anchoredValue = readProperty(root, "Anchored")
	local rootPosition = positionOk and vectorSnapshot(positionValue) or nil
	local rootVelocity = velocityOk and vectorSnapshot(velocityValue) or nil
	local spawnInBounds = rootPosition ~= nil
			and rootPosition.y > SPAWN_MIN_Y
			and rootPosition.y < SPAWN_MAX_Y
			and rootPosition.z < SPAWN_MAX_Z
		or false

	local leaderstats = find(player, "leaderstats")
	local wins = find(leaderstats, "Wins")
	local winsOk, winsRaw = readProperty(wins, "Value")
	local winsValue = winsOk and finiteInteger(winsRaw) or nil
	local winsState = "READY"
	if leaderstats == nil then
		winsState = "LEADERSTATS_MISSING"
	elseif wins == nil then
		winsState = "WINS_MISSING"
	elseif winsValue == nil then
		winsState = "WINS_INVALID"
	end

	local structure = find(workspace, "Structure")
	local stage1 = find(structure, "Stage1")
	local sas = find(stage1, "SAS")
	local winBlock = find(sas, "WinBlock32")
	local winBlockState = "READY"
	if structure == nil then
		winBlockState = "STRUCTURE_MISSING"
	elseif stage1 == nil then
		winBlockState = "STAGE1_MISSING"
	elseif sas == nil then
		winBlockState = "SAS_MISSING"
	elseif winBlock == nil then
		winBlockState = "WINBLOCK32_MISSING"
	elseif not isBasePart(winBlock) then
		winBlockState = "WINBLOCK32_WRONG_CLASS"
	end

	local winPositionOk, winPositionValue = readProperty(winBlock, "Position")
	local winSizeOk, winSizeValue = readProperty(winBlock, "Size")
	local canCollideOk, canCollideValue = readProperty(winBlock, "CanCollide")
	local winBlockPosition = winPositionOk and vectorSnapshot(winPositionValue) or nil
	local winBlockSize = winSizeOk and vectorSnapshot(winSizeValue) or nil
	if winBlockState == "READY" and (winBlockPosition == nil or winBlockSize == nil or not canCollideOk) then
		winBlockState = "PROPERTY_READ_FAILED"
	end
	local winBlockCanCollide: boolean? = nil
	if canCollideOk and type(canCollideValue) == "boolean" then
		winBlockCanCollide = canCollideValue
	end

	local placeId = finiteInteger(game.PlaceId)
	local capturedAt = finiteInteger(os.time())
	if placeId == nil or placeId < 0 or capturedAt == nil or capturedAt < 0 then
		return nil, errorResult("observation_read_failed", "Place or capture time is invalid")
	end

	return table.freeze({
		schemaVersion = 1,
		capturedAt = capturedAt,
		place = table.freeze({
			id = placeId,
			supported = placeId == WORLD3_PLACE_ID,
		}),
		character = table.freeze({
			state = characterState(character, humanoid, root, health),
			present = character ~= nil,
			humanoidPresent = humanoid ~= nil,
			health = health,
			maxHealth = maxHealth,
		}),
		root = table.freeze({
			present = root ~= nil,
			position = rootPosition,
			velocity = rootVelocity,
			anchored = anchoredOk and anchoredValue == true or false,
		}),
		spawn = table.freeze({
			inBounds = spawnInBounds,
			bounds = table.freeze({
				minYExclusive = SPAWN_MIN_Y,
				maxYExclusive = SPAWN_MAX_Y,
				maxZExclusive = SPAWN_MAX_Z,
			}),
		}),
		wins = table.freeze({
			state = winsState,
			available = winsState == "READY",
			value = winsValue,
		}),
		winBlock32 = table.freeze({
			state = winBlockState,
			available = winBlockState == "READY",
			path = WIN_BLOCK_PATH,
			position = winBlockPosition,
			size = winBlockSize,
			canCollide = winBlockCanCollide,
		}),
	}),
		nil
end

return table.freeze(Observation)
