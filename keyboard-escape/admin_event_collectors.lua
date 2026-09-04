--!strict

local Module = {}

Module.CHOICES = {
	"Alien", "Cheese Battle", "Coin Battle", "Milk Battle", "Orb Event",
	"Chichine Orbs", "Masked Man Orbs", "WC Finale", "Concert Orbs", "Independence Orbs",
	"July 14 Orbs", "Fab Checkpoints", "Last Summer Rings", "August 15 Rings",
	"Survival Chase", "Team Battle", "Special Keys", "Admin Abuse Treadmill",
}

local function call(fn: any, ...: any): any
	if type(fn) ~= "function" then return nil end
	local packed = table.pack(pcall(fn, ...))
	if packed[1] then return packed[2] end
	return nil
end

local function completed(fn: any, ...: any): boolean
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function copyArray(values: { any }): { any }
	local out = {}
	for i, value in ipairs(values) do out[i] = value end
	return out
end

local function selectedSet(values: { string }): ({ [string]: boolean }?, string?)
	local known, result = {}, {}
	for _, name in ipairs(Module.CHOICES) do known[name] = true end
	for _, name in ipairs(values) do
		if not known[name] then return nil, "unknown admin event: " .. tostring(name) end
		if result[name] then return nil, "duplicate admin event: " .. name end
		result[name] = true
	end
	return result, nil
end

local function isLive(value: any): boolean
	if type(value) == "table" then return value.destroyed ~= true end
	return value ~= nil and value.Parent ~= nil
end

local function partOf(value: any): any
	if type(value) == "table" then return value.part or value.root or value end
	if value and value:IsA("BasePart") then return value end
	if value and value:IsA("Model") then
		return value.PrimaryPart or value:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function positionOf(value: any): any
	if type(value) == "table" then return value.position or value.Position or value.pivot end
	local part = partOf(value)
	if part then return part.Position end
	return nil
end

local function velocityOf(value: any): any
	if type(value) == "table" then return value.velocity or value.AssemblyLinearVelocity end
	local part = partOf(value)
	return part and part.AssemblyLinearVelocity or nil
end

local function addLead(value: any): any
	local position, velocity = positionOf(value), velocityOf(value)
	if position and velocity then return position + velocity * 0.08 end
	return position
end

local Collector = {}
Collector.__index = Collector

function Collector:_owns(generation: number, selectedOrder: any?): boolean
	return self._running and not self._destroyed and self._generation == generation
		and (selectedOrder == nil or self._selectedOrder == selectedOrder)
end

function Collector:_service(name: string): any
	if self._options[name] ~= nil then return self._options[name] end
	local names = { players = "Players", replicatedStorage = "ReplicatedStorage", workspace = "Workspace", runService = "RunService", collectionService = "CollectionService", starterPlayer = "StarterPlayer" }
	return call(function() return game:GetService(names[name] or name) end)
end
function Collector:_now(): number
	return tonumber(call(self._options.clock)) or os.clock()
end

function Collector:_serverNow(): number
	local supplied = call(self._options.serverClock)
	if type(supplied) == "number" then return supplied end
	local world = self:_service("workspace")
	local value = world and call(world.GetServerTimeNow, world)
	return tonumber(value) or self:_now()
end

function Collector:_state(): any
	local supplied = call(self._options.getState)
	if type(supplied) == "table" then return supplied end
	local players = self:_service("players")
	local player = players and players.LocalPlayer
	local replicated = self:_service("replicatedStorage")
	local state = (player and player:FindFirstChild("ClientState")) or (replicated and replicated:FindFirstChild("ClientState"))
	local loaded = state and call(require, state)
	return type(loaded) == "table" and loaded or {}
end

function Collector:_root(): any
	local injected = call(self._options.getRoot)
	if injected then return injected end
	local players = self:_service("players")
	local player = players and players.LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 and root.Anchored ~= true then return root end
	return nil
end

function Collector:_defaultTargets(kind: string): { any }
	local world = self:_service("workspace")
	if not world then return {} end
	local folders = { ["Cheese Battle"] = "CheeseBattleCoinsLocal", ["Coin Battle"] = "CoinBattleCoinsLocal", ["Milk Battle"] = "MilkBattleCoinsLocal", ["Orb Event"] = "OrbEventOrbsLocal" }
	if folders[kind] then
		local folder = world:FindFirstChild(folders[kind])
		return folder and folder:GetChildren() or {}
	end
	local result = {}
	if kind == "Alien" then
		for _, item in ipairs(world:GetDescendants()) do if item:IsA("BasePart") and item.Name == "Ray" and item.Parent and string.find(item.Parent.Name, "UFO", 1, true) then table.insert(result, item) end end
	elseif kind == "WC Soccer" then
		for _, item in ipairs(world:GetDescendants()) do
			if item.Name == "SoccerBall" and (item:IsA("BasePart") or item:IsA("Model")) then table.insert(result, item) end
		end
	elseif kind == "Special Keys" then
		local keys = world:FindFirstChild("SpecialKeys")
		for _, item in ipairs(keys and keys:GetDescendants() or {}) do if item:IsA("MeshPart") and item:GetAttribute("IsDiscoKey") == true and type(item:GetAttribute("DiscoKeyId")) == "string" then table.insert(result, item) end end
	elseif kind == "Admin Abuse Treadmill" then
		local collection = self:_service("collectionService")
		for _, item in ipairs(collection and collection:GetTagged("AdminAbuseTreadmill") or {}) do
			if isLive(item) and item:IsDescendantOf(world) then table.insert(result, item) end
		end
	elseif kind == "Fab Checkpoints" then
		local collection = self:_service("collectionService")
		for _, map in ipairs(collection and collection:GetTagged("FABADMINABUSE_V1_MAP") or {}) do if map:FindFirstChild("AllStructures", true) then table.insert(result, map) end end
	elseif kind == "Survival Chase" then
		for _, item in ipairs(world:GetDescendants()) do
			if item:IsA("BasePart") and item.Name == "ZonePart" and item.Parent and string.sub(item.Parent.Name, -6) == "Bounds" then table.insert(result, item) end
		end
	else
		local eventGeometry = {
			["Concert Orbs"] = "WinsSpawn",
			["Independence Orbs"] = "IndependenceDay_Live",
			["July 14 Orbs"] = "July14thAdminAbuse_Live",
		}
		local scoped = { ["Chichine Orbs"] = "ChichineBossRoom", ["Masked Man Orbs"] = "MaskedManColorMania", ["WC Finale"] = "WCFinaleAdminAbuse" }
		local geometryName, scope = eventGeometry[kind], scoped[kind]
		if scope then
			local container = world:FindFirstChild(scope, true)
			if container then for _, item in ipairs(container:GetDescendants()) do if item.Name == "CollectibleOrb" or item.Name == "BigCollectibleOrb" then table.insert(result, item) end end end
		elseif geometryName then
			local geometry = world:FindFirstChild(geometryName, true)
			if geometry then
				local anchor = partOf(geometry) or geometry:FindFirstChildWhichIsA("BasePart", true)
				for _, item in ipairs(world:GetChildren()) do
					if (item.Name == "CollectibleOrb" or item.Name == "BigCollectibleOrb") and (not anchor or (positionOf(item) and (positionOf(item) - anchor.Position).Magnitude <= math.max(anchor.Size.X, anchor.Size.Y, anchor.Size.Z) * 4)) then table.insert(result, item) end
				end
			end
		end
	end
	return result
end

function Collector:_targets(kind: string): { any }
	local supplied = call(self._options.listTargets, kind)
	return type(supplied) == "table" and supplied or self:_defaultTargets(kind)
end

function Collector:_move(target: any, current: string, lead: boolean?): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_owns(generation, selectedOrder) or not isLive(target) then return false end
	local part = partOf(target)
	if part and not isLive(part) then return false end
	local position = lead and addLead(target) or positionOf(target)
	if position == nil then return false end
	local move = self._options.moveTo
	if type(move) ~= "function" then return false end
	self._current = current
	call(self._options.setMovementActive, true)
	local movedOk, moved = pcall(move, position, target)
	if self:_owns(generation) then call(self._options.setMovementActive, false) end
	return movedOk and moved ~= false and self:_owns(generation, selectedOrder)
		and isLive(target) and (part == nil or isLive(part))
end

function Collector:_defaultSend(endpoint: string, ...: any): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	local replicated = self:_service("replicatedStorage")
	if not replicated then return false end
	if endpoint == "FrameworkClientEvent" then
		local framework = replicated:FindFirstChild("_FRAMEWORK")
		local module = framework and framework:FindFirstChild("Features") and framework.Features:FindFirstChild("Admins") and framework.Features.Admins:FindFirstChild("AdminAbuseEvent")
		local loaded = module and call(require, module)
		local remote = loaded and loaded.remotes and loaded.remotes.ClientEvent
		return remote and self:_owns(generation, selectedOrder) and completed(remote.fire, remote, ...) or false
	end
	if endpoint == "AlienAbductRequest" then
		local admin = replicated:FindFirstChild("AdminAbuse")
		local loaded = admin and admin:FindFirstChild("AlienRemotes") and call(require, admin.AlienRemotes)
		local remote = loaded and loaded.AlienAbductRequest
		return remote and self:_owns(generation, selectedOrder) and completed(remote.fire, remote) or false
	end
	local remote
	if endpoint == "ConcertOrbCollected" or endpoint == "UpdateSpeed" then
		local remotes = replicated:FindFirstChild("Remotes")
		remote = remotes and remotes:FindFirstChild(endpoint)
	else
		local admin = replicated:FindFirstChild("AdminAbuse")
		local remotes = admin and admin:FindFirstChild("Remotes")
		remote = remotes and remotes:FindFirstChild(endpoint)
	end
	return remote and remote:IsA("RemoteEvent") and self:_owns(generation, selectedOrder) and completed(remote.FireServer, remote, ...) or false
end

function Collector:_send(endpoint: string, ...: any): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_owns(generation, selectedOrder) then return false end
	local now = self:_now()
	if now - self._lastGlobal < 0.12 then return false end
	local baseline = tonumber(self:_state().Wins) or 0
	if not self:_owns(generation, selectedOrder) then return false end
	local sender = self._options.sendRequest
	local ok
	if type(sender) == "function" then
		local sent, result = pcall(sender, endpoint, ...)
		ok = sent and result ~= false
	else
		ok = self:_defaultSend(endpoint, ...)
	end
	if not ok then return false end
	self._lastGlobal, self._requests = now, self._requests + 1
	if not self:_owns(generation, selectedOrder) then return false end
	self._pendingWins = { baseline = baseline, expiresAt = now + 8 }
	return true
end

function Collector:_available(key: any, seconds: number): boolean
	return self:_now() - (self._lastByKey[key] or -math.huge) >= seconds
end

function Collector:_mark(key: any): ()
	self._lastByKey[key] = self:_now()
end

function Collector:_sendWithKey(key: any, cooldown: number, endpoint: string, ...: any): boolean
	if not self:_available(key, cooldown) then return false end
	if not self:_send(endpoint, ...) then return false end
	self:_mark(key)
	return true
end

function Collector:_defaultFrameworkStates(): { any }
	local replicated = self:_service("replicatedStorage")
	local framework = replicated and replicated:FindFirstChild("_FRAMEWORK")
	local module = framework and framework:FindFirstChild("Features") and framework.Features:FindFirstChild("Admins") and framework.Features.Admins:FindFirstChild("AdminAbuseEvent")
	local loaded = module and call(require, module)
	local states = loaded and call(loaded.getActiveStates, loaded)
	return type(states) == "table" and states or {}
end

function Collector:_isEventActive(name: string): boolean
	for _, lane in pairs(self._legacy) do if type(lane) == "table" and lane.name == name and lane.active ~= false then return true end end
	local supplied = call(self._options.getLegacyActive)
	for _, lane in pairs(type(supplied) == "table" and supplied or {}) do if type(lane) == "table" and lane.name == name and lane.active ~= false then return true end end
	return self:_framework(name) ~= nil
end

function Collector:_framework(name: string): any
	for _, state in ipairs(self._frameworkStates) do if type(state) == "table" and state.name == name then return state end end
	return nil
end

function Collector:_targetId(choice: string, target: any): any
	if type(target) == "table" then return target.id or target.Id or target.OrbEventId end
	local name = target and target.Name
	local prefixes = { ["Cheese Battle"] = "CheeseBattleCoin_", ["Coin Battle"] = "CoinBattleCoin_", ["Milk Battle"] = "MilkBattleCoin_", ["Orb Event"] = "OrbEventOrb_" }
	local prefix = prefixes[choice]
	if type(name) == "string" and prefix and string.sub(name, 1, #prefix) == prefix then return string.sub(name, #prefix + 1) end
	return choice == "Orb Event" and target and target:GetAttribute("OrbEventId") or nil
end

function Collector:_isGiant(target: any): boolean
	if type(target) == "table" and target.giant ~= nil then return target.giant == true end
	if target and type(target.Name) == "string" and string.find(target.Name, "Big", 1, true) then return true end
	if not self._ordinaryOrbSize then
		local replicated = self:_service("replicatedStorage")
		local admin = replicated and replicated:FindFirstChild("AdminAbuse")
		local template = admin and admin:FindFirstChild("CollectibleOrb")
		local ordinary = partOf(template)
		self._ordinaryOrbSize = ordinary and ordinary.Size or nil
	end
	local part, ordinary = partOf(target), self._ordinaryOrbSize
	if part and part.Size and ordinary then
		return part.Size.X >= ordinary.X * 2.5 or part.Size.Y >= ordinary.Y * 2.5 or part.Size.Z >= ordinary.Z * 2.5
	end
	return false
end

function Collector:_collectId(choice: string, endpoint: string, event: string): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_isEventActive(event) then return false end
	for _, target in ipairs(self:_targets(choice)) do
		if not self:_owns(generation, selectedOrder) then return false end
		local id, key = self:_targetId(choice, target), choice .. tostring(self:_targetId(choice, target))
		if id ~= nil and self:_available(key, 0.25) and self:_move(target, choice, choice == "Orb Event") and self:_sendWithKey(key, 0.25, endpoint, id) then return true end
	end
	return false
end

function Collector:_collectOrb(choice: string, endpoint: string, event: string, gate: boolean?): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_isEventActive(event) or gate == false then return false end
	for _, target in ipairs(self:_targets(choice)) do
		if not self:_owns(generation, selectedOrder) then return false end
		local key = choice .. tostring(target)
		if isLive(target) and self:_available(key, 0.25) and self:_move(target, choice, true) and self:_sendWithKey(key, 0.25, endpoint) then return true end
	end
	return false
end

function Collector:_frameworkRequest(key: string, state: any, payload: any, cooldown: number): boolean
	return state ~= nil and self:_sendWithKey(key, cooldown, "FrameworkClientEvent", state.name, state.startedAt, payload)
end


function Collector:_alien(): boolean
	local root = self:_isEventActive("Alien") and self:_root()
	if not root then
		self._alienTarget, self._alienDwellAt, self._alienRoot = nil, nil, nil
		return false
	end
	if root ~= self._alienRoot then
		self._alienRoot, self._alienDwellAt = root, nil
	end
	local world = self:_service("workspace")
	local spawn = world and world:FindFirstChild("SpawnLocation", true)
	local ray, first = nil, nil
	for _, candidate in ipairs(self:_targets("Alien")) do
		local position = positionOf(candidate)
		if isLive(candidate) and (not spawn or (position and (position - spawn.Position).Magnitude > 40)) then
			first = first or candidate
			if candidate == self._alienTarget then ray = candidate; break end
		end
	end
	ray = ray or first
	if ray ~= self._alienTarget then self._alienTarget, self._alienDwellAt = ray, nil end
	if not ray then return false end
	local localPoint = ray.CFrame:PointToObjectSpace(root.Position)
	local half = ray.Size * 0.5
	local inside = math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
	if not inside or (spawn and (root.Position - spawn.Position).Magnitude <= 40) then
		self._alienDwellAt = nil
		self:_move(ray, "Alien")
	elseif not self._alienDwellAt then
		self._alienDwellAt = self:_now()
	elseif self:_now() - self._alienDwellAt >= 1 and self:_sendWithKey(ray, 1, "AlienAbductRequest") then
		self._alienTarget, self._alienDwellAt = nil, nil
		return true
	end
	return false
end

function Collector:_personalTreadmillActive(): boolean
	local supplied = call(self._options.isPersonalTreadmillActive)
	if type(supplied) == "boolean" then return supplied end
	local starterPlayer = self:_service("starterPlayer")
	local scripts = starterPlayer and starterPlayer:FindFirstChild("StarterPlayerScripts")
	local module = scripts and scripts:FindFirstChild("PersonalTreadmill")
	local treadmill = module and call(require, module)
	return type(treadmill) == "table" and call(treadmill.isActive, treadmill) == true
end

function Collector:_treadmill(): boolean
	local root = self:_root()
	if not root or self:_personalTreadmillActive() then return false end
	local treadmill = self:_targets("Admin Abuse Treadmill")[1]
	local treadmillPart = treadmill and partOf(treadmill)
	if not treadmillPart then return false end
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local replicated = self:_service("replicatedStorage")
	local configModule = replicated and replicated:FindFirstChild("Config")
	local config = call(self._options.getTreadmillConfig) or (configModule and call(require, configModule))
	local timing = type(config) == "table" and config.XP_TIME_BASED or nil
	local cadence = .5
	if type(timing) == "table" and humanoid then
		local minSpeed, maxSpeed = tonumber(timing.MIN_SPEED), tonumber(timing.MAX_SPEED)
		local minCooldown, maxCooldown = tonumber(timing.MIN_COOLDOWN), tonumber(timing.MAX_COOLDOWN)
		if minSpeed and maxSpeed and minCooldown and maxCooldown and maxSpeed > minSpeed then
			local progress = math.clamp((humanoid.WalkSpeed - minSpeed) / (maxSpeed - minSpeed), 0, 1)
			cadence = maxCooldown - progress * (maxCooldown - minCooldown)
		end
	end
	if not self:_available("Admin Abuse Treadmill", cadence) then return false end
	local rootHalfHeight = root.Size.Y * .5
	local targetPosition = treadmillPart.Position + treadmillPart.CFrame.UpVector * (treadmillPart.Size.Y * .5 + rootHalfHeight + .1)
	if not self:_move({ position = targetPosition, part = treadmillPart }, "Admin Abuse Treadmill") then return false end
	local world, collection = self:_service("workspace"), self:_service("collectionService")
	if not world or not collection then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { treadmillPart }
	local hit = world:Raycast(root.Position, Vector3.new(0, -7, 0), params)
	if not hit or not collection:HasTag(hit.Instance, "AdminAbuseTreadmill") then return false end
	return self:_sendWithKey("Admin Abuse Treadmill", cadence, "UpdateSpeed", "AdminAbuseTreadmill")
end

function Collector:_survivalDestination(zones: { any }): any
	local world = self:_service("workspace")
	local chasers = call(self._options.listSurvivalChasers)
	if type(chasers) ~= "table" then
		chasers = {}
		for _, item in ipairs(world and world:GetDescendants() or {}) do
			if item:IsA("Model") and (item.Name == "AABossNpc" or string.find(item.Name, "SurvivalChaser", 1, true)) then table.insert(chasers, item) end
		end
	end
	local best, bestDistance = nil, -math.huge
	for _, zone in ipairs(zones) do
		local part = partOf(zone)
		if part then
			local origin = part.Position + Vector3.new(0, part.Size.Y * .5 - 1, 0)
			local floor = world and world:Raycast(origin, Vector3.new(0, -(part.Size.Y + 40), 0))
			if floor then
				local point, nearest = floor.Position + Vector3.new(0, 3, 0), math.huge
				for _, chaser in ipairs(chasers) do
					local chaserRoot = partOf(chaser)
					if chaserRoot then nearest = math.min(nearest, (point - chaserRoot.Position).Magnitude) end
				end
				if nearest > bestDistance then best, bestDistance = { position = point }, nearest end
			end
		end
	end
	return best
end

function Collector:_stepChoice(choice: string): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if choice == "Alien" then return self:_alien() end
	if choice == "Cheese Battle" then return self:_collectId(choice, "CheeseBattleCollect", "CheeseBattle") end
	if choice == "Coin Battle" then return self:_collectId(choice, "CoinBattleCollect", "CoinBattle") end
	if choice == "Milk Battle" then return self:_collectId(choice, "MilkBattleCollect", "MilkBattle") end
	if choice == "Orb Event" then return self:_collectId(choice, "OrbEventCollect", "OrbEvent") end
	if choice == "Chichine Orbs" then
		if not self:_isEventActive("ChichineBossRoom") then return false end
		for _, target in ipairs(self:_targets(choice)) do
			if not self:_owns(generation, selectedOrder) then return false end
			local key = choice .. tostring(target)
			if self:_available(key, .25) and self:_move(target, choice, true) then
				local giant = self:_isGiant(target)
				if not self:_owns(generation, selectedOrder) then return false end
				if isLive(target) and self:_sendWithKey(key, .25, giant and "ChichineGiantOrbCollected" or "ChichineOrbCollected") then return true end
			end
		end
	elseif choice == "Masked Man Orbs" then
		if not self:_isEventActive("MaskedManColorMania") then return false end
		for _, target in ipairs(self:_targets(choice)) do
			if not self:_owns(generation, selectedOrder) then return false end
			local key = choice .. tostring(target)
			if self:_available(key, .25) and self:_move(target, choice, true) then
				local giant = self:_isGiant(target)
				if not self:_owns(generation, selectedOrder) then return false end
				if isLive(target) and self:_sendWithKey(key, .25, giant and "MaskedManGiantOrbCollected" or "MaskedManOrbCollected") then return true end
			end
		end
	elseif choice == "WC Finale" then
		if self:_collectOrb(choice, "WCFinaleOrbCollected", "WCFinaleAdminAbuse") then return true end
		if not self:_owns(generation, selectedOrder) then return false end
		if self:_isEventActive("WCFinaleAdminAbuse") then
			for _, ball in ipairs(self:_targets("WC Soccer")) do
				if not self:_owns(generation, selectedOrder) then return false end
				if isLive(ball) and not self._soccerBalls[ball] and self:_move(ball, "WC Soccer", true) then
					self._soccerBalls[ball] = true
					break
				end
			end
		end
	elseif choice == "Concert Orbs" then return self:_collectOrb(choice, "ConcertOrbCollected", "Concert")
	elseif choice == "Independence Orbs" then return self:_collectOrb(choice, "IndependenceDayWinOrbCollected", "IndependenceDay", self._sseWinOrbs.IndependenceDay or #self:_targets(choice) > 0)
	elseif choice == "July 14 Orbs" then return self:_collectOrb(choice, "July14thAdminAbuseWinOrbCollected", "July14thAdminAbuse", self._sseWinOrbs.July14thAdminAbuse or #self:_targets(choice) > 0)
	elseif choice == "Fab Checkpoints" then
		local state = self:_framework("FabBossEvent")
		return #self:_targets(choice) > 0 and self:_frameworkRequest(choice, state, "CheckpointPassed", 1.05) or false
	elseif choice == "Last Summer Rings" then
		local state = self:_framework("LastSummerBoss")
		local elapsed = state and self:_serverNow() - state.startedAt or -math.huge
		if elapsed >= 38 and self:_frameworkRequest(choice .. "1", state, { "AwardWin", 1 }, .8) then return true end
		if not self:_owns(generation, selectedOrder) then return false end
		return elapsed >= 292 and elapsed < 592 and self:_frameworkRequest(choice .. "2", state, { "AwardWin", 2 }, .8) or false
	elseif choice == "August 15 Rings" then
		local state = self:_framework("SummerBossEvent_August15th")
		local elapsed = state and self:_serverNow() - state.startedAt or -math.huge
		local duration = state and (state.durationSeconds or 720) or 720
		if elapsed >= duration - 30 then return false end
		for index, threshold in ipairs({ 34, 266.25, 528.75 }) do
			if not self:_owns(generation, selectedOrder) then return false end
			if elapsed >= threshold and self:_frameworkRequest(choice .. tostring(index), state, { "AwardWin", index }, .8) then return true end
		end
	elseif choice == "Survival Chase" then
		if not self:_framework("SurvivalChase") or not self:_available(choice, 1) then return false end
		local destination = self:_survivalDestination(self:_targets(choice))
		if destination and self:_move(destination, choice) then self:_mark(choice); return true end
	elseif choice == "Team Battle" then
		return false
	elseif choice == "Special Keys" then
		for _, target in ipairs(self:_targets(choice)) do
			if not self:_owns(generation, selectedOrder) then return false end
			if self:_available(choice, .5) and self:_move(target, choice) then self:_mark(choice); return true end
		end
	elseif choice == "Admin Abuse Treadmill" then return self:_treadmill()
	end
	return false
end

function Collector:_observeSSE(channel: any, packet: any): ()
	if type(packet) ~= "table" then return end
	local key = tostring(channel)
	local matching = string.find(key, "Independence", 1, true) and "IndependenceDay" or (string.find(key, "July", 1, true) and "July14thAdminAbuse" or nil)
	local function inspect(entry: any)
		if matching and type(entry) == "table" and entry.command == "SpawnWinOrbs" and (tonumber(entry.arg) or 0) > 0 then self._sseWinOrbs[matching] = true end
	end
	if type(packet.d) == "table" then
		local teamFields = { Teams = true, Phase = true, CountdownEndsAt = true, CombatEndsAt = true, WinnerTeamIds = true }
		for field, value in pairs(packet.d) do
			inspect(value)
			if teamFields[field] then self._teamBattle[field] = value end
		end
	end
	local players = self:_service("players")
	local localUserId = players and players.LocalPlayer and players.LocalPlayer.UserId
	if type(packet.e) == "table" then
		for event, entries in pairs(packet.e) do
			for _, entry in ipairs(type(entries) == "table" and entries or {}) do
				inspect(entry)
				if event == "WinPayout" and type(entry) == "table" and (entry.userId == localUserId or entry.UserId == localUserId or entry.playerUserId == localUserId) then self._teamPayouts = { entry } end
			end
		end
	end
end

function Collector:_connect(connection: any, generation: number): ()
	if not connection then return end
	if self:_owns(generation) then
		table.insert(self._connections, connection)
	else
		call(function() connection:Disconnect() end)
	end
end
function Collector:Start(): (boolean, string?)
	if self._destroyed then return false, "collector destroyed" end
	if self._running then return true end
	self._running, self._status, self._generation = true, "watching", self._generation + 1
	local generation = self._generation
	local observe = function(action: any, name: any, duration: any, skip: any, revision: any, skipDoor: any, lane: any)
		if not self:_owns(generation) then return end
		local key = lane == "Event" and "event" or "main"
		local current = self._revisions[key] or 0
		if type(revision) == "number" and revision > 0 and revision <= current then return end
		self._revisions[key] = tonumber(revision) or current
		if action == "Stop" or action == "stop" or action == "Deactivated" then
			self._legacy[key] = nil
		else
			self._legacy[key] = { name = name, duration = duration, skip = skip, skipDoor = skipDoor, active = true }
		end
	end
	local legacy = call(self._options.subscribeLegacy, observe)
	if not self:_owns(generation) then self:_connect(legacy, generation); return false, "collector start cancelled" end
	local rep = self:_service("replicatedStorage")
	local admin = rep and rep:FindFirstChild("AdminAbuse")
	local remotes = admin and admin:FindFirstChild("Remotes")
	if not legacy then
		local sync = remotes and remotes:FindFirstChild("AdminAbuseSync")
		if sync and sync:IsA("RemoteEvent") then legacy = sync.OnClientEvent:Connect(observe) end
	end
	self:_connect(legacy, generation)
	local initialized = call(self._options.requestLegacyState)
	if not self:_owns(generation) then return false, "collector start cancelled" end
	if initialized == nil then
		local request = remotes and remotes:FindFirstChild("AdminAbuseRequest")
		if request and request:IsA("RemoteEvent") then completed(request.FireServer, request, "GetState") end
	end
	local injected = call(self._options.subscribeSSE, function(channel: any, packet: any)
		if self:_owns(generation) then self:_observeSSE(channel, packet) end
	end)
	self:_connect(injected, generation)
	if not self:_owns(generation) then return false, "collector start cancelled" end
	if not injected then
		local function bind(remote: any)
			if remote and remote:IsA("RemoteEvent") then
				self:_connect(remote.OnClientEvent:Connect(function(packet: any)
					if self:_owns(generation) then self:_observeSSE(remote.Name, packet) end
				end), generation)
			end
		end
		local shared = admin and admin:FindFirstChild("SharedSyncedEvent", true)
		if shared and shared:IsA("RemoteEvent") then
			bind(shared)
		else
			local folder = remotes and remotes:FindFirstChild("SSE")
			if folder then
				for _, child in ipairs(folder:GetChildren()) do bind(child) end
				self:_connect(folder.ChildAdded:Connect(bind), generation)
			end
		end
	end
	local worker = function()
		local ok, err = xpcall(function()
			while self:_owns(generation) do
				self:Step()
				if not self:_owns(generation) then break end
				local waitFn = self._options.wait or task.wait
				waitFn(.1)
			end
		end, debug.traceback)
		if not ok and self:_owns(generation) then
			self:Stop()
			if self._generation == generation + 1 and not self._running then
				self._lastError, self._status = tostring(err), "Error: " .. tostring(err)
			end
		end
	end
	(self._options.spawn or task.spawn)(worker)
	return self:_owns(generation), if self:_owns(generation) then nil else self._lastError or "collector start cancelled"
end

function Collector:Stop(): boolean
	if not self._running then return true end
	self._running, self._generation, self._status, self._current = false, self._generation + 1, "stopped", nil
	for _, connection in ipairs(self._connections) do call(function() connection:Disconnect() end) end
	self._connections, self._legacy, self._revisions, self._frameworkStates, self._sseWinOrbs, self._pendingWins, self._soccerBalls, self._teamBattle, self._teamPayouts = {}, {}, {}, {}, {}, nil, {}, {}, {}
	self._alienTarget, self._alienDwellAt, self._alienRoot = nil, nil, nil
	call(self._options.setMovementActive, false)
	return true
end

function Collector:Step(): boolean
	if not self._running or self._destroyed then return false end
	local generation, selectedOrder = self._generation, self._selectedOrder
	local frameworkStates = call(self._options.getFrameworkStates) or self:_defaultFrameworkStates()
	if not self:_owns(generation, selectedOrder) then return false end
	self._frameworkStates = frameworkStates
	local now, wins = self:_now(), tonumber(self:_state().Wins) or 0
	if not self:_owns(generation, selectedOrder) then return false end
	if now >= self._nextCooldownPrune then
		self._nextCooldownPrune = now + 8
		for key, last in pairs(self._lastByKey) do
			-- String IDs are not reclaimed by weak-key tables. Only the treadmill
			-- has a configurable cooldown; every other string key is ready by 1.05s.
			if type(key) == "string" and key ~= "Admin Abuse Treadmill" and now - last >= 1.05 then
				self._lastByKey[key] = nil
			end
		end
		for ball in pairs(self._soccerBalls) do
			if not isLive(ball) then self._soccerBalls[ball] = nil end
		end
	end
	if self._pendingWins then
		if now > self._pendingWins.expiresAt then self._pendingWins = nil
		elseif wins > self._pendingWins.baseline then self._confirmed += 1; self._pendingWins = nil end
	end
	self._current, self._status = nil, "watching"
	for _, choice in ipairs(selectedOrder) do
		local acted = self:_stepChoice(choice)
		if not self:_owns(generation, selectedOrder) then return false end
		if acted then self._status = self._current == "Survival Chase" and "moving" or "request sent"; return true end
	end
	return false
end

function Collector:SetSelected(choices: { string }): (boolean, string?)
	if self._destroyed then return false, "collector destroyed" end
	local set, err = selectedSet(choices)
	if not set then return false, err end
	if not set.Alien then self._alienTarget, self._alienDwellAt, self._alienRoot = nil, nil, nil end
	self._selected, self._selectedOrder = set, copyArray(choices)
	return true
end
function Collector:Snapshot(): any
	return {
		active = self._running, selected = copyArray(self._selectedOrder), status = self._status, current = self._current,
		requests = self._requests, confirmed = self._confirmed, lastError = self._lastError, legacyMain = self._legacy.main,
		legacyEvent = self._legacy.event, frameworkStates = copyArray(self._frameworkStates), teamBattle = self._teamBattle,
		teamPayouts = copyArray(self._teamPayouts),
	}
end

function Collector:Destroy(): boolean
	if self._destroyed then return true end
	self:Stop(); self._destroyed = true
	return true
end

function Module.new(options: any): any
	options = options or {}
	local selected = copyArray(Module.CHOICES)
	local set = selectedSet(selected)
	return setmetatable({
		_options = options, _running = false, _destroyed = false, _generation = 0, _selected = set, _selectedOrder = selected,
		_status = "stopped", _current = nil, _requests = 0, _confirmed = 0, _lastError = nil, _lastByKey = setmetatable({}, { __mode = "k" }),
		_lastGlobal = -math.huge, _nextCooldownPrune = 0, _connections = {}, _legacy = {}, _revisions = {}, _frameworkStates = {}, _sseWinOrbs = {},
		_pendingWins = nil, _alienTarget = nil, _alienDwellAt = nil, _alienRoot = nil, _soccerBalls = {}, _ordinaryOrbSize = nil, _teamBattle = {}, _teamPayouts = {},
	}, Collector)
end

return Module
