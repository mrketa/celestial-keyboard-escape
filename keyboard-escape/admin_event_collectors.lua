--!strict

local Module = {}

Module.CHOICES = {
	"Alien", "Coin Battle", "Orbs", "WC Soccer", "Fab Checkpoints",
	"Survival Chase", "Special Keys", "Lightning Keycaps", "Chocolate Hunt",
}

-- Native target families stay internal; Orbs visits them in this order.
local ORB_FAMILIES = {
	{ kind = "Chichine Orbs", event = "ChichineBossRoom", endpoint = "ChichineOrbCollected", giantEndpoint = "ChichineGiantOrbCollected" },
	{ kind = "Masked Man Orbs", event = "MaskedManColorMania", endpoint = "MaskedManOrbCollected", giantEndpoint = "MaskedManGiantOrbCollected" },
	{ kind = "WC Finale", event = "WCFinaleAdminAbuse", endpoint = "WCFinaleOrbCollected" },
	{ kind = "Concert Orbs", event = "Concert", endpoint = "ConcertOrbCollected" },
	{ kind = "Independence Orbs", event = "IndependenceDay", endpoint = "IndependenceDayWinOrbCollected", spawnGate = true },
	{ kind = "July 14 Orbs", event = "July14thAdminAbuse", endpoint = "July14thAdminAbuseWinOrbCollected", spawnGate = true },
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

local function disconnect(connection: any): ()
	if type(connection) == "function" then call(connection)
	elseif connection then call(function() connection:Disconnect() end) end
end

local function winOrbEvent(channel: any): string?
	local name = tostring(channel)
	if string.find(name, "Independence", 1, true) then return "IndependenceDay" end
	if string.find(name, "July", 1, true) then return "July14thAdminAbuse" end
	return nil
end

local Collector = {}
Collector.__index = Collector

function Collector:_owns(generation: number, selectedOrder: any?): boolean
	return self._running and not self._destroyed and self._generation == generation
		and (selectedOrder == nil or self._selectedOrder == selectedOrder)
end

function Collector:_service(name: string): any
	if self._options[name] ~= nil then return self._options[name] end
	local names = { players = "Players", replicatedStorage = "ReplicatedStorage", workspace = "Workspace", runService = "RunService", collectionService = "CollectionService" }
	return call(function() return game:GetService(names[name] or name) end)
end
function Collector:_now(): number
	return tonumber(call(self._options.clock)) or os.clock()
end

function Collector:_state(): any
	local supplied = call(self._options.getState)
	if type(supplied) == "table" then return supplied end
	local players = self:_service("players")
	local player = players and players.LocalPlayer
	local replicated = self:_service("replicatedStorage")
	local state = (player and player:FindFirstChild("ClientState")) or (replicated and replicated:FindFirstChild("ClientState"))
	local loaded = state and call(require, state)
	local snapshot = type(loaded) == "table" and call(loaded.Get, loaded)
	return type(snapshot) == "table" and snapshot or {}
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
	local folders = { ["Coin Battle"] = "CoinBattleCoinsLocal", ["Orb Event"] = "OrbEventOrbsLocal" }
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
	elseif kind == "Lightning Keycaps" then
		local keys = world:FindFirstChild("Keycaps")
		for _, item in ipairs(keys and keys:GetChildren() or {}) do
			if item:IsA("MeshPart") and item:FindFirstChild("LightingEffects") then table.insert(result, item) end
		end
	elseif kind == "Chocolate Hunt" then
		local folder = world:FindFirstChild("ChocolateHuntCollectibles")
		for _, item in ipairs(folder and folder:GetChildren() or {}) do
			if item.Name == "ChocolateHuntCollectible" and (item:IsA("Model") or item:IsA("BasePart")) then table.insert(result, item) end
		end
	elseif kind == "Special Keys" then
		local keys = world:FindFirstChild("SpecialKeys")
		for _, item in ipairs(keys and keys:GetDescendants() or {}) do if item:IsA("MeshPart") and item:GetAttribute("IsDiscoKey") == true and type(item:GetAttribute("DiscoKeyId")) == "string" then table.insert(result, item) end end
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
			local maps = world:FindFirstChild("AdminAbuseMaps")
			local container = maps and maps:FindFirstChild(scope)
			if container then for _, item in ipairs(container:GetDescendants()) do if item.Name == "CollectibleOrb" or item.Name == "BigCollectibleOrb" then table.insert(result, item) end end end
		elseif geometryName then
			local anchor
			if kind == "Concert Orbs" then
				anchor = world:FindFirstChild(geometryName, true)
			else
				local admin = world:FindFirstChild("AdminAbuse")
				local maps = admin and admin:FindFirstChild("Map")
				local map = maps and maps:FindFirstChild(geometryName)
				local scriptables = map and map:FindFirstChild("Scriptables")
				local zones = scriptables and scriptables:FindFirstChild("Zones")
				anchor = zones and zones:FindFirstChild("OrbsSpawn")
			end
			if anchor and anchor:IsA("BasePart") then
				for _, item in ipairs(world:GetChildren()) do
					local part = partOf(item)
					if (item.Name == "CollectibleOrb" or item.Name == "BigCollectibleOrb") and part and part.Anchored ~= true
						and (part.Position - anchor.Position).Magnitude <= math.max(anchor.Size.X, anchor.Size.Y, anchor.Size.Z) * 4 then table.insert(result, item) end
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

function Collector:_move(target: any, current: string, lead: boolean?, isCurrent: (() -> boolean)?): boolean
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
	if (isCurrent and not isCurrent()) or not self:_owns(generation, selectedOrder)
		or not isLive(target) or (part and not isLive(part)) then
		if self:_owns(generation) then call(self._options.setMovementActive, false) end
		return false
	end
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
		local loaded = self:_frameworkModule()
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
	if endpoint == "ConcertOrbCollected" then
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
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_available(key, cooldown) or not self:_owns(generation, selectedOrder) then return false end
	if not self:_send(endpoint, ...) then return false end
	self:_mark(key)
	return true
end

function Collector:_frameworkModule(): any
	local replicated = self:_service("replicatedStorage")
	local framework = replicated and replicated:FindFirstChild("_FRAMEWORK")
	local module = framework and framework:FindFirstChild("Features") and framework.Features:FindFirstChild("Admins") and framework.Features.Admins:FindFirstChild("AdminAbuseEvent")
	return module and call(require, module)
end

function Collector:_defaultFrameworkStates(): { any }
	local loaded = self:_frameworkModule()
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
	local prefixes = { ["Coin Battle"] = "CoinBattleCoin_", ["Orb Event"] = "OrbEventOrb_" }
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

function Collector:_collectId(kind: string, endpoint: string, event: string, current: string): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_isEventActive(event) or not self:_owns(generation, selectedOrder) then return false end
	for _, target in ipairs(self:_targets(kind)) do
		if not self:_owns(generation, selectedOrder) then return false end
		local id = self:_targetId(kind, target)
		local key = kind .. tostring(id)
		local part = partOf(target)
		if id ~= nil and (kind ~= "Orb Event" or (part and part.Anchored ~= true))
			and self:_available(key, 0.25) and self:_owns(generation, selectedOrder)
			and self:_move(target, current, kind == "Orb Event") and self:_sendWithKey(key, 0.25, endpoint, id) then return true end
	end
	return false
end

function Collector:_collectOrb(family: any): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if not self:_isEventActive(family.event) or not self:_owns(generation, selectedOrder) then return false end
	local targets = self:_targets(family.kind)
	if not self:_owns(generation, selectedOrder) then return false end
	if family.spawnGate and not (self._sseWinOrbs[family.event] or #targets > 0) then return false end
	for _, target in ipairs(targets) do
		if not self:_owns(generation, selectedOrder) then return false end
		local key = family.kind .. tostring(target)
		if isLive(target) and self:_available(key, .25) and self:_owns(generation, selectedOrder)
			and self:_move(target, "Orbs", true) then
			local endpoint = family.endpoint
			if family.giantEndpoint and self:_isGiant(target) then endpoint = family.giantEndpoint end
			if not self:_owns(generation, selectedOrder) then return false end
			if isLive(target) and self:_sendWithKey(key, .25, endpoint) then return true end
		end
	end
	return false
end

function Collector:_orbs(): boolean
	local generation, selectedOrder = self._generation, self._selectedOrder
	if self:_collectId("Orb Event", "OrbEventCollect", "OrbEvent", "Orbs") then return true end
	for _, family in ipairs(ORB_FAMILIES) do
		if not self:_owns(generation, selectedOrder) then return false end
		if self:_collectOrb(family) then return true end
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

function Collector:_clearLightning(): ()
	disconnect(self._lightningConnection)
	self._lightningConnection, self._lightningSession, self._lightningTarget = nil, nil, nil
	self._lightningZones, self._lightningClaims = {}, {}
	self._lightningEffects = setmetatable({}, { __mode = "k" })
	self._lightningPackets = setmetatable({}, { __mode = "k" })
	self._lightningScanAt = 0
end

function Collector:_lightningSettings(): any
	local supplied = call(self._options.getLightningConfig)
	if type(supplied) ~= "table" then
		local replicated = self:_service("replicatedStorage")
		local framework = replicated and replicated:FindFirstChild("_FRAMEWORK")
		local module = framework and framework:FindFirstChild("LightingEvent", true)
		local config = module and module:FindFirstChild("Config")
		supplied = config and call(require, config) or {}
	end
	local defaults = {
		strikeWarningSeconds = .7, electrifiedDurationSeconds = 12, keycapCheckIntervalSeconds = .15,
		superStrikeRadiusStuds = 70, keycapHorizontalMarginStuds = 2.5, keycapVerticalRangeStuds = 10,
		superChargeCount = 3,
	}
	for key, fallback in pairs(defaults) do
		local value = type(supplied) == "table" and tonumber(supplied[key])
		if value and value > 0 and value < math.huge then defaults[key] = value else defaults[key] = fallback end
	end
	return defaults
end

function Collector:_syncLightning(state: any): ()
	if not self._running or not self._selected["Lightning Keycaps"] then state = nil end
	local startedAt = state and state.startedAt
	if not self._lightningSession and startedAt == nil then return end
	if self._lightningSession and self._lightningSession.startedAt == startedAt then return end
	self:_clearLightning()
	if type(startedAt) ~= "number" then return end
	local generation, selectedOrder = self._generation, self._selectedOrder
	local session = { startedAt = startedAt }
	self._lightningSession = session
	local settings = self:_lightningSettings()
	if not self:_owns(generation, selectedOrder) or self._lightningSession ~= session then return end
	self._lightningConfig = settings
	local observe = function(name: any, packetStartedAt: any, packet: any)
		if not self:_owns(generation, selectedOrder) or self._lightningSession ~= session or name ~= "LightingEvent" or packetStartedAt ~= startedAt then return end
		-- The framework may replace/stop its session between worker ticks.
		local states = call(self._options.getFrameworkStates) or self:_defaultFrameworkStates()
		if not self:_owns(generation, selectedOrder) or self._lightningSession ~= session then return end
		local active = false
		for _, current in ipairs(states) do
			if current.name == name and current.startedAt == startedAt then active = true; break end
		end
		if not active then self:_clearLightning(); return end
		self:_observeLightning(packet)
	end
	local connection = call(self._options.subscribeFrameworkMessage, observe)
	if not connection and self:_owns(generation, selectedOrder) and self._lightningSession == session then
		local loaded = self:_frameworkModule()
		local remote = loaded and loaded.remotes and loaded.remotes.Message
		connection = remote and call(remote.connect, remote, observe)
	end
	if self:_owns(generation, selectedOrder) and self._lightningSession == session then
		self._lightningConnection = connection
	else
		disconnect(connection)
	end
end

function Collector:_pruneLightning(now: number): ()
	for index = #self._lightningZones, 1, -1 do
		local zone = self._lightningZones[index]
		if now >= zone.expiresAt + 1 then
			if self._lightningTarget == zone then self._lightningTarget = nil end
			table.remove(self._lightningZones, index)
		end
	end
	for index = #self._lightningClaims, 1, -1 do
		if now >= self._lightningClaims[index].expiresAt then table.remove(self._lightningClaims, index) end
	end
end

function Collector:_observeLightning(packet: any): ()
	if type(packet) ~= "table" or typeof(packet.cframe) ~= "CFrame" then return end
	if self._lightningPackets[packet] then return end
	self._lightningPackets[packet] = true
	local now, config = self:_now(), self._lightningConfig
	local position, super = packet.cframe.Position, packet.isSuper == true
	self:_pruneLightning(now)
	if packet.kind == "claim" then
		for _, claim in ipairs(self._lightningClaims) do
			if claim.position == position and claim.isSuper == super and claim.multiplier == packet.multiplier and claim.chargeCount == packet.chargeCount then return end
		end
		for _, zone in ipairs(self._lightningZones) do
			if not zone.claimed and zone.isSuper == super and (zone.cframe.Position - position).Magnitude < 2
				and (zone.chargeCount == nil or zone.chargeCount == packet.chargeCount)
				and (zone.color == nil or zone.color == packet.color) and now < zone.expiresAt + 1 then
				zone.claimed = true
				if self._lightningTarget == zone then self._lightningTarget = nil end
				self._confirmed += 1
				if #self._lightningClaims == 256 then table.remove(self._lightningClaims, 1) end
				table.insert(self._lightningClaims, { position = position, isSuper = super, multiplier = packet.multiplier, chargeCount = packet.chargeCount, expiresAt = now + config.electrifiedDurationSeconds + 1 })
				return
			end
		end
		return
	end
	if (packet.kind ~= "strike" and packet.kind ~= "zone") or typeof(packet.size) ~= "Vector3" then return end
	local duration = tonumber(packet.activeDurationSeconds) or config.electrifiedDurationSeconds
	if duration <= 0 or duration >= math.huge or duration ~= duration or (super and packet.kind ~= "strike") then return end
	duration = math.min(duration, config.electrifiedDurationSeconds)
	if #self._lightningZones >= 256 then return end
	local activeAt = now + (packet.kind == "strike" and config.strikeWarningSeconds or 0)
	table.insert(self._lightningZones, {
		cframe = packet.cframe, size = packet.size, isSuper = super, chargeCount = super and config.superChargeCount or packet.chargeCount, color = packet.color,
		activeAt = activeAt, expiresAt = activeAt + (super and 0 or duration), attempts = 0, nextVisitAt = 0,
	})
end

function Collector:_scanLightning(now: number): ()
	if now < self._lightningScanAt then return end
	self._lightningScanAt = now + self._lightningConfig.keycapCheckIntervalSeconds
	for _, keycap in ipairs(self:_targets("Lightning Keycaps")) do
		local part = partOf(keycap)
		local effect = if type(keycap) == "table" then keycap.effects else part and part:FindFirstChild("LightingEffects")
		if part and effect and isLive(part) and not self._lightningEffects[effect] then
			local position = if type(keycap) == "table" then keycap.positionAttribute else part:GetAttribute("Position")
			if typeof(position) ~= "Vector3" then position = part.Position end
			local matched = false
			for _, zone in ipairs(self._lightningZones) do
				if not zone.isSuper and not zone.claimed and (zone.cframe.Position - position).Magnitude < 2
					and now < zone.expiresAt and (zone.effects == nil or zone.effects == effect) then
					zone.effects = effect
					matched = true
					break
				end
			end
			if matched or #self._lightningZones < 256 then
				self._lightningEffects[effect] = true
				if not matched then
					table.insert(self._lightningZones, {
						cframe = part.CFrame - part.Position + position, size = part.Size, isSuper = false, effects = effect, fromVisual = true,
						activeAt = now, expiresAt = now + self._lightningConfig.electrifiedDurationSeconds,
						attempts = 0, nextVisitAt = 0,
					})
				end
			end
		end
	end
end

function Collector:_lightningInside(zone: any, root: any): boolean
	local config = self._lightningConfig
	if zone.isSuper then
		local impact = (zone.cframe * CFrame.new(0, zone.size.Y * .5, 0)).Position
		return (root.Position - impact).Magnitude <= config.superStrikeRadiusStuds
	end
	local point = zone.cframe:PointToObjectSpace(root.Position)
	return math.abs(point.X) <= zone.size.X * .5 + config.keycapHorizontalMarginStuds
		and math.abs(point.Z) <= zone.size.Z * .5 + config.keycapHorizontalMarginStuds
		and point.Y >= -config.keycapVerticalRangeStuds and point.Y <= zone.size.Y * .5 + config.keycapVerticalRangeStuds
end

function Collector:_lightning(): boolean
	local session, root = self._lightningSession, self:_root()
	if not session or not root then return false end
	local generation, selectedOrder = self._generation, self._selectedOrder
	local now, config = self:_now(), self._lightningConfig
	self:_pruneLightning(now)
	self:_scanLightning(now)
	if not self:_owns(generation, selectedOrder) or self._lightningSession ~= session then return false end
	local target, score = nil, math.huge
	for _, zone in ipairs(self._lightningZones) do
		if not zone.claimed and now < zone.expiresAt and now >= zone.nextVisitAt
			and (not zone.fromVisual or isLive(zone.effects)) then
			local distance = (zone.cframe.Position - root.Position).Magnitude
			-- Instant super pickups expire at impact. Regular zones favor untouched,
			-- expiring nearby keys rather than repeatedly returning to one color.
			local priority = zone.isSuper and -100000 + zone.activeAt - now
				or zone.attempts * 10000 + zone.expiresAt - now + distance * .001
			if priority < score then target, score = zone, priority end
		end
	end
	local current = self._lightningTarget
	if current and not current.claimed and now < current.waitUntil
		and (not current.fromVisual or isLive(current.effects))
		and self:_lightningInside(current, root) and (not target or not target.isSuper or current.isSuper) then
		self._current = "Lightning Keycaps"
		return true
	end
	self._lightningTarget = nil
	if current and target and target.isSuper and not current.isSuper then
		current.nextVisitAt = now
	end
	if not target then return false end
	local inside = self:_lightningInside(target, root)
	if not inside then
		local height = target.size.Y * .5 + math.min(2, config.keycapVerticalRangeStuds * .5)
		local destination = { position = (target.cframe * CFrame.new(0, height, 0)).Position }
		local moved = self:_move(destination, "Lightning Keycaps")
		if not self:_owns(generation, selectedOrder) or self._lightningSession ~= session then return false end
		now = self:_now()
		if not moved or now >= target.expiresAt or not self:_lightningInside(target, root) then
			target.attempts += 1
			target.nextVisitAt = now + config.keycapCheckIntervalSeconds
			return false
		end
	end
	if target.claimed then return true end
	target.attempts += 1
	target.waitUntil = math.min(target.expiresAt + (target.isSuper and config.keycapCheckIntervalSeconds or 0),
		math.max(now, target.activeAt) + math.max(.6, config.keycapCheckIntervalSeconds * 4))
	target.nextVisitAt = target.waitUntil
	self._lightningTarget, self._current = target, "Lightning Keycaps"
	return true
end

local function chocolateId(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

local function chocolatePosition(visual: any): any
	if type(visual) == "table" then return positionOf(visual) end
	if visual:IsA("Model") then return visual:GetPivot().Position end
	return visual.Position
end

function Collector:_ownsChocolate(generation: number, selectedOrder: any, session: any): boolean
	return session ~= nil and self:_owns(generation, selectedOrder) and self._chocolateSession == session
end

function Collector:_clearChocolate(): ()
	-- Invalidate destinations before disconnecting: either callback may yield.
	for _, item in ipairs(self._chocolateItems) do item.destroyed = true end
	local connection = self._chocolateConnection
	self._chocolateConnection, self._chocolateSession, self._chocolateTarget, self._chocolateConfig = nil, nil, nil, nil
	self._chocolateItems, self._chocolateIds = {}, {}
	self._chocolateVisuals = setmetatable({}, { __mode = "k" })
	self._chocolateScanAt = 0
	disconnect(connection)
end

function Collector:_chocolateSettings(): any
	local supplied = call(self._options.getChocolateConfig)
	if type(supplied) ~= "table" then
		local replicated = self:_service("replicatedStorage")
		local framework = replicated and replicated:FindFirstChild("_FRAMEWORK")
		local module = framework and framework:FindFirstChild("ChocolateHunt", true)
		local config = module and module:FindFirstChild("Config")
		supplied = config and call(require, config) or {}
	end
	local settings = { collectionRadiusStuds = 7, collectionCheckIntervalSeconds = .1 }
	for key, fallback in pairs(settings) do
		local value = type(supplied) == "table" and tonumber(supplied[key])
		settings[key] = if value and value > 0 and value < math.huge then value else fallback
	end
	return settings
end

function Collector:_refreshChocolate(generation: number, selectedOrder: any, session: any): boolean
	if not self:_ownsChocolate(generation, selectedOrder, session) then return false end
	local states = call(self._options.getFrameworkStates) or self:_defaultFrameworkStates()
	if not self:_ownsChocolate(generation, selectedOrder, session) then return false end
	self._frameworkStates = states
	for _, state in ipairs(states) do
		if type(state) == "table" and state.name == "ChocolateHunt" and state.startedAt == session.startedAt then return true end
	end
	self:_clearChocolate()
	return false
end

function Collector:_syncChocolate(state: any): ()
	if not self._running or not self._selected["Chocolate Hunt"] then state = nil end
	local startedAt = state and state.startedAt
	if not self._chocolateSession and startedAt == nil then return end
	if self._chocolateSession and self._chocolateSession.startedAt == startedAt then return end
	local generation, selectedOrder = self._generation, self._selectedOrder
	self:_clearChocolate()
	if not self:_owns(generation, selectedOrder) or type(startedAt) ~= "number"
		or startedAt ~= startedAt or math.abs(startedAt) == math.huge then return end
	local session = { startedAt = startedAt }
	self._chocolateSession = session
	-- Preserve receipt deduplication across toggles of the same native session.
	if self._chocolateReceiptSession ~= startedAt then
		self._chocolateReceiptSession, self._chocolateReceipts = startedAt, {}
	end
	local settings = self:_chocolateSettings()
	if not self:_refreshChocolate(generation, selectedOrder, session) then return end
	self._chocolateConfig = settings
	session.isCurrent = function() return self:_refreshChocolate(generation, selectedOrder, session) end
	local observe = function(name: any, packetStartedAt: any, packet: any)
		if name ~= "ChocolateHunt" or packetStartedAt ~= startedAt then return end
		if self:_refreshChocolate(generation, selectedOrder, session) then self:_observeChocolate(packet) end
	end
	local connection = call(self._options.subscribeFrameworkMessage, observe)
	if not connection and self:_refreshChocolate(generation, selectedOrder, session) then
		local loaded = self:_frameworkModule()
		if self:_refreshChocolate(generation, selectedOrder, session) then
			local remote = loaded and loaded.remotes and loaded.remotes.Message
			connection = remote and call(remote.connect, remote, observe)
		end
	end
	if self:_refreshChocolate(generation, selectedOrder, session) then
		self._chocolateConnection = connection
	else
		disconnect(connection)
	end
end

function Collector:_retireChocolate(item: any): ()
	if not item or item.destroyed then return end
	item.destroyed = true
	if self._chocolateTarget == item then self._chocolateTarget = nil end
	for index = #self._chocolateItems, 1, -1 do
		if self._chocolateItems[index] == item then table.remove(self._chocolateItems, index); break end
	end
end

function Collector:_chocolateLive(item: any): boolean
	if item.destroyed then return false end
	local visual = item.visual
	if not visual then return true end
	if not isLive(visual) then return false end
	if type(visual) == "table" then return true end
	local parent = visual.Parent
	return visual.Name == "ChocolateHuntCollectible" and parent == item.visualParent
		and parent.Name == "ChocolateHuntCollectibles" and parent.Parent == self:_service("workspace")
end

function Collector:_addChocolate(packet: any): ()
	if type(packet) ~= "table" or not chocolateId(packet.id) or typeof(packet.cframe) ~= "CFrame"
		or self._chocolateReceipts[packet.id] or self._chocolateIds[packet.id] then return end
	local position, item, nearest = packet.cframe.Position, nil, .8
	-- Native visuals have no IDs. Match their pivot within the .7-stud bob,
	-- then retain the authoritative original position for physical collection.
	for _, candidate in ipairs(self._chocolateItems) do
		if candidate.id == nil and self:_chocolateLive(candidate) then
			local distance = (candidate.position - position).Magnitude
			if distance < nearest then item, nearest = candidate, distance end
		end
	end
	if not item then
		item = { position = position, nextVisitAt = 0 }
		table.insert(self._chocolateItems, item)
	end
	item.id, item.position = packet.id, position
	self._chocolateIds[packet.id] = item
end

function Collector:_observeChocolate(packet: any): ()
	if type(packet) ~= "table" then return end
	if packet.kind == "spawn" then
		self:_addChocolate(packet)
	elseif packet.kind == "snapshot" and type(packet.collectibles) == "table" then
		for _, collectible in ipairs(packet.collectibles) do self:_addChocolate(collectible) end
	elseif packet.kind == "collected" and chocolateId(packet.id) and type(packet.collectorUserId) == "number" then
		if self._chocolateReceipts[packet.id] then return end
		self._chocolateReceipts[packet.id] = true
		self:_retireChocolate(self._chocolateIds[packet.id])
		local players = self:_service("players")
		local userId = players and players.LocalPlayer and players.LocalPlayer.UserId
		-- Global progress/milestones are XP bonuses, not our collection or Wins.
		-- A server receipt is sufficient even when enabled after the ID's spawn.
		if type(userId) == "number" and packet.collectorUserId == userId then self._confirmed += 1 end
	end
end

function Collector:_scanChocolate(now: number, generation: number, selectedOrder: any, session: any): boolean
	if now < self._chocolateScanAt then return true end
	local visuals = self:_targets("Chocolate Hunt")
	if not self:_refreshChocolate(generation, selectedOrder, session) then return false end
	self._chocolateScanAt = now + math.max(.25, self._chocolateConfig.collectionCheckIntervalSeconds)
	for index = #self._chocolateItems, 1, -1 do
		local item = self._chocolateItems[index]
		if not self:_chocolateLive(item) then self:_retireChocolate(item) end
	end
	for _, visual in ipairs(visuals) do
		if isLive(visual) and not self._chocolateVisuals[visual] then
			local position = chocolatePosition(visual)
			if typeof(position) == "Vector3" then
				local item, nearest = nil, .8
				for _, candidate in ipairs(self._chocolateItems) do
					if not candidate.visual then
						local distance = (candidate.position - position).Magnitude
						if distance < nearest then item, nearest = candidate, distance end
					end
				end
				if not item then
					item = { position = position, nextVisitAt = 0 }
					table.insert(self._chocolateItems, item)
				end
				item.visual = visual
				item.visualParent = if type(visual) == "table" then nil else visual.Parent
				self._chocolateVisuals[visual] = item
			end
		end
	end
	return true
end

function Collector:_chocolateInside(item: any, root: any): boolean
	local delta = root.Position - item.position
	local radius = self._chocolateConfig.collectionRadiusStuds
	-- A late-enable pivot may be bobbed .7 studs from the server origin.
	if item.id == nil then radius = math.max(0, radius - .7) end
	return delta:Dot(delta) <= radius * radius
end

function Collector:_chocolate(): boolean
	local generation, selectedOrder, session = self._generation, self._selectedOrder, self._chocolateSession
	if not self:_ownsChocolate(generation, selectedOrder, session) or not self._chocolateConfig then return false end
	local root = self:_root()
	if not self:_refreshChocolate(generation, selectedOrder, session) then return false end
	if not root then return false end
	local now = self:_now()
	if not self:_ownsChocolate(generation, selectedOrder, session)
		or not self:_scanChocolate(now, generation, selectedOrder, session) then return false end
	local config = self._chocolateConfig
	local dwell = math.max(.6, config.collectionCheckIntervalSeconds * 4)
	local target, newVisit = self._chocolateTarget, false
	if target and (not self:_chocolateLive(target) or now >= target.waitUntil) then
		if self:_chocolateLive(target) then target.nextVisitAt = now + dwell else self:_retireChocolate(target) end
		self._chocolateTarget, target = nil, nil
	end
	if not target then
		local nearest = math.huge
		for _, item in ipairs(self._chocolateItems) do
			if now >= item.nextVisitAt and self:_chocolateLive(item) then
				local delta = root.Position - item.position
				local distance = delta:Dot(delta)
				if distance < nearest then target, nearest = item, distance end
			end
		end
		if not target then return false end
		target.waitUntil = now + dwell
		self._chocolateTarget = target
		newVisit = true
	end
	if not self:_chocolateInside(target, root) then
		if not self:_refreshChocolate(generation, selectedOrder, session) or not self:_chocolateLive(target) then return false end
		local moved = self:_move(target, "Chocolate Hunt", nil, session.isCurrent)
		if not self:_refreshChocolate(generation, selectedOrder, session) then return false end
		if target.destroyed then return moved end
		root = self:_root()
		if not self:_refreshChocolate(generation, selectedOrder, session) then return false end
		if not moved or not root or not self:_chocolateLive(target) or not self:_chocolateInside(target, root) then
			target.nextVisitAt = now + dwell
			self._chocolateTarget = nil
			return false
		end
	end
	if newVisit then
		local arrivedAt = self:_now()
		if not self:_refreshChocolate(generation, selectedOrder, session) then return false end
		target.waitUntil = arrivedAt + dwell
	end
	self._current = "Chocolate Hunt"
	return true
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
	if choice == "Lightning Keycaps" then return self:_lightning() end
	if choice == "Chocolate Hunt" then return self:_chocolate() end
	if choice == "Coin Battle" then return self:_collectId(choice, "CoinBattleCollect", "CoinBattle", choice) end
	if choice == "Orbs" then return self:_orbs() end
	if choice == "WC Soccer" then
		if self:_isEventActive("WCFinaleAdminAbuse") and self:_owns(generation, selectedOrder) then
			for _, ball in ipairs(self:_targets(choice)) do
				if not self:_owns(generation, selectedOrder) then return false end
				if isLive(ball) and not self._soccerBalls[ball] and self:_move(ball, choice, true) then
					self._soccerBalls[ball] = true
					break
				end
			end
		end
	elseif choice == "Fab Checkpoints" then
		local state = self:_framework("FabBossEvent")
		return #self:_targets(choice) > 0 and self:_frameworkRequest(choice, state, "CheckpointPassed", 1.05) or false
	elseif choice == "Survival Chase" then
		if not self:_framework("SurvivalChase") or not self:_available(choice, 1) then return false end
		local destination = self:_survivalDestination(self:_targets(choice))
		if destination and self:_move(destination, choice) then self:_mark(choice); return true end
	elseif choice == "Special Keys" then
		for _, target in ipairs(self:_targets(choice)) do
			if not self:_owns(generation, selectedOrder) then return false end
			if self:_available(choice, .5) and self:_move(target, choice) then self:_mark(choice); return true end
		end
	end
	return false
end

function Collector:_observeSSE(channel: any, packet: any): ()
	if type(packet) ~= "table" then return end
	local matching = winOrbEvent(channel)
	if not matching then return end
	local function inspect(entry: any)
		if type(entry) == "table" and entry.command == "SpawnWinOrbs" and (tonumber(entry.arg) or 0) > 0 then self._sseWinOrbs[matching] = true end
	end
	if type(packet.d) == "table" then
		for _, value in pairs(packet.d) do inspect(value) end
	end
	if type(packet.e) == "table" then
		for _, entries in pairs(packet.e) do
			for _, entry in ipairs(type(entries) == "table" and entries or {}) do inspect(entry) end
		end
	end
end

function Collector:_connect(connection: any, generation: number): ()
	if not connection then return end
	if self:_owns(generation) then
		table.insert(self._connections, connection)
	else
		disconnect(connection)
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
			if remote and remote:IsA("RemoteEvent") and (remote.Name == "SharedSyncedEvent" or winOrbEvent(remote.Name)) then
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
	local states = call(self._options.getFrameworkStates) or self:_defaultFrameworkStates()
	if not self:_owns(generation) then return false, "collector start cancelled" end
	self._frameworkStates = states
	self:_syncLightning(self:_framework("LightingEvent"))
	if not self:_owns(generation) then return false, "collector start cancelled" end
	self:_syncChocolate(self:_framework("ChocolateHunt"))
	if not self:_owns(generation) then return false, "collector start cancelled" end
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
	self:_clearLightning()
	self:_clearChocolate()
	for _, connection in ipairs(self._connections) do disconnect(connection) end
	self._connections, self._legacy, self._revisions, self._frameworkStates, self._sseWinOrbs, self._pendingWins, self._soccerBalls = {}, {}, {}, {}, {}, nil, {}
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
	self:_syncLightning(self:_framework("LightingEvent"))
	if not self:_owns(generation, selectedOrder) then return false end
	self:_syncChocolate(self:_framework("ChocolateHunt"))
	if not self:_owns(generation, selectedOrder) then return false end
	local now, wins = self:_now(), tonumber(self:_state().Wins) or 0
	if not self:_owns(generation, selectedOrder) then return false end
	if now >= self._nextCooldownPrune then
		self._nextCooldownPrune = now + 8
		for key, last in pairs(self._lastByKey) do
			-- String IDs are not reclaimed by weak-key tables; all are ready by 1.05s.
			if type(key) == "string" and now - last >= 1.05 then
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
	-- Lightning's warning is shorter than other collectors' cooldowns. It shares
	-- this worker but gets first refusal while a pickup/impact is pending.
	if self._selected["Lightning Keycaps"] then
		local acted = self:_lightning()
		if not self:_owns(generation, selectedOrder) then return false end
		if acted then self._status = "awaiting claim"; return true end
	end
	-- Chocolate has no item expiry, but must retain proximity through native
	-- collection checks instead of being displaced by ordinary collectors.
	if self._selected["Chocolate Hunt"] then
		local acted = self:_chocolate()
		if not self:_owns(generation, selectedOrder) then return false end
		if acted then self._status = "awaiting collection"; return true end
	end
	for _, choice in ipairs(selectedOrder) do
		local requests = self._requests
		local acted = choice ~= "Lightning Keycaps" and choice ~= "Chocolate Hunt" and self:_stepChoice(choice)
		if not self:_owns(generation, selectedOrder) then return false end
		if acted then
			self._status = self._requests > requests and "request sent" or "moving"
			return true
		end
	end
	return false
end

function Collector:SetSelected(choices: { string }): (boolean, string?)
	if self._destroyed then return false, "collector destroyed" end
	local set, err = selectedSet(choices)
	if not set then return false, err end
	if not set.Alien then self._alienTarget, self._alienDwellAt, self._alienRoot = nil, nil, nil end
	self:_clearLightning()
	self:_clearChocolate()
	self._selected, self._selectedOrder = set, copyArray(choices)
	if self._running then
		self:_syncLightning(self:_framework("LightingEvent"))
		self:_syncChocolate(self:_framework("ChocolateHunt"))
	end
	return true
end
function Collector:Snapshot(): any
	return {
		active = self._running, selected = copyArray(self._selectedOrder), status = self._status, current = self._current,
		requests = self._requests, confirmed = self._confirmed, lastError = self._lastError, legacyMain = self._legacy.main,
		legacyEvent = self._legacy.event, frameworkStates = copyArray(self._frameworkStates),
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
		_pendingWins = nil, _alienTarget = nil, _alienDwellAt = nil, _alienRoot = nil, _soccerBalls = {}, _ordinaryOrbSize = nil,
		_lightningZones = {}, _lightningClaims = {}, _lightningEffects = setmetatable({}, { __mode = "k" }),
		_lightningPackets = setmetatable({}, { __mode = "k" }), _lightningScanAt = 0,
		_chocolateItems = {}, _chocolateIds = {}, _chocolateReceipts = {}, _chocolateScanAt = 0,
		_chocolateVisuals = setmetatable({}, { __mode = "k" }),
	}, Collector)
end

return Module
