--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")


local Runtime = {}
Runtime.__index = Runtime

local STRATEGY_STAGE_1 = "Stage 1 (Instant TP)"
local STRATEGY_MAX = "Max Stage"
local WORKER_DELAY = 0.35
local STAGE_1_SAFETY_MARGIN = 0.010
local STAGE_1_WAIT_STEP = 0.1
local STAGE_1_REWARD_POLL = 0.01
local STAGE_1_REWARD_TIMEOUT = 5
local MAX_ROUTE_SPEED = 300
local ROUTE_SPEED = 200
local MOVE_ARRIVAL_RADIUS = 0.05
local TWEEN_SETTLE_TIMEOUT = 0.75
local ANTI_FLING_HORIZONTAL_SPEED = 80
local ANTI_FLING_VERTICAL_SPEED = 110
local ANTI_FLING_ANGULAR_SPEED = 60
local ANTI_FLING_RECOVERY_DISTANCE = 12
local GALAXY_2_PLACE_ID = 75012837977315
local GALAXY_2_MAX_STAGE = 10
local GALAXY_2_ROUTE_SPEED = 300
local GALAXY_2_SAFETY_MARGIN = 0.25
-- Streaming hints are never movement targets; routes use observed SAS parts.
local GALAXY_2_SAS_STREAM_HINTS = {
	Vector3.new(-296.392, 375.870, -759.908),
	Vector3.new(-129.005, 375.870, -759.908),
	Vector3.new(102.522, 375.870, -759.908),
	Vector3.new(463.522, 375.870, -759.908),
	Vector3.new(781.772, 375.870, -759.908),
	Vector3.new(1142.744, 375.870, -759.908),
	Vector3.new(1561.118, 375.870, -759.908),
	Vector3.new(2458.399, 375.870, -759.908),
	Vector3.new(2832.425, 851.875, -759.908),
	Vector3.new(3727.398, 742.534, -759.908),
	Vector3.new(4512.976, 743.075, -759.908),
}
local MAX_DIRECT_STAGE = 14
local DIRECT_ROUTES = {
	[3] = { checkpoint = 1, minNet = 200000000, plate = "WinBlock34", staging = Vector3.new(-1462.791, 214.103, 333.030) },
	[4] = { checkpoint = 2, minNet = 250000000, plate = "WinBlock35", staging = Vector3.new(-1413.355, 532.115, 760.514) },
	[5] = { checkpoint = 3, minNet = 400000000, plate = "WinBlock36", staging = Vector3.new(-1413.474, 532.114, 1330.716) },
	[6] = { checkpoint = 4, minNet = 1000000000, plate = "WinBlock37", staging = Vector3.new(-2063.262, 442.113, 1477.350) },
	[7] = { checkpoint = 5, minNet = 1500000000, plate = "WinBlock38", staging = Vector3.new(-3223.170, 671.624, 1476.435) },
	[8] = {
		checkpoint = 6,
		minNet = 10000000000,
		plate = "WinBlock39",
		staging = Vector3.new(-3645, 615.9617919921875, 1475),
	},
	[9] = { checkpoint = 7, minNet = 5000000000, plate = "WinBlock40", staging = Vector3.new(-4131.452, 615.960, 1476.639) },
	[10] = { checkpoint = 8, minNet = 8000000000, plate = "WinBlock41", staging = Vector3.new(-4968.451, 615.967, 1476.638) },
	[11] = { checkpoint = 9, minNet = 8000000000, plate = "WinBlock42", staging = Vector3.new(-5741.451, 850.980, 1476.571) },
	[12] = { checkpoint = 10, minNet = 15000000000, plate = "WinBlock43", staging = Vector3.new(-6662.904, 850.993, 1476.504) },
	[13] = { checkpoint = 11, minNet = 20000000000, plate = "WinBlock44", staging = Vector3.new(-9514.962, 850.993, 1476.504) },
	[14] = { checkpoint = 12, minNet = 70000000000, plate = "WinBlock45", staging = Vector3.new(-10807.108, 850.990, 1476.499) },
}
local DIRECT_APPROACH_SPEED = 300
local DIRECT_SAFETY_MARGIN = 0.050
local DIRECT_WAIT_STEP = 0.1
local CHECKPOINT_ACK_TIMEOUT = 5
local CHECKPOINT_COST_TIMEOUT = 3
local DIRECT_REWARD_TIMEOUT = 7
local KEY_CHOICES = { "Gold Key", "Secret Key" }
local KEY_CONTACT_TIMEOUT = 2
local FUSE_TIMEOUT = 5
local EQUIP_TIMEOUT = 5
local BUY_CONFIRM_TIMEOUT = 5
local GLOVE_CADENCE = 1.1

local function printable(value: any): string
	return tostring(value):gsub("%z", "\\0")
end

local function fuseLabel(displayName: string, key: string, tier: number): string
	return string.format("%s — Tier %d [%q]", printable(displayName), tier, key)
end

local function fuseGroups(state: any, items: any): { [string]: { key: string, tier: number, count: number } }
	local groups = {}
	local entries = type(state) == "table" and state.Items or nil
	if type(entries) ~= "table" or type(items) ~= "table" then return groups end
	local keyOf, tierOf, isLimitedKey = items.KeyOf, items.TierOf, items.IsLimitedKey
	if type(keyOf) ~= "function" or type(tierOf) ~= "function" or type(isLimitedKey) ~= "function" then return groups end
	local maxTier = if type(items.MAX_TIER) == "number" then items.MAX_TIER else 0
	if maxTier <= 0 then return groups end
	for _, entry in ipairs(entries) do
		local key, tier = keyOf(entry), tierOf(entry)
		local data = if type(key) == "string" and type(items.ITEMS) == "table" then items.ITEMS[key] else nil
		if
			type(key) == "string"
			and key ~= ""
			and type(tier) == "number"
			and tier == math.floor(tier)
			and tier >= 0
			and tier <= maxTier
			and type(data) == "table"
			and not isLimitedKey(key)
		then
			local displayName = data.DisplayName or data.Name or data.name or key
			local label = fuseLabel(type(displayName) == "string" and displayName or key, key, tier)
			local group = groups[label] or { key = key, tier = tier, count = 0 }
			group.count += 1
			groups[label] = group
		end
	end
	return groups
end


local function fuseGroupCount(groups: { [string]: { key: string, tier: number, count: number } }, key: string, tier: number): number
	for _, group in pairs(groups) do
		if group.key == key and group.tier == tier then return group.count end
	end
	return 0
end
local function inventoryEntryIdentity(entry: any, items: any): string?
	local keyOf, tierOf = items.KeyOf, items.TierOf
	if type(keyOf) ~= "function" or type(tierOf) ~= "function" then return nil end
	local key, tier = keyOf(entry), tierOf(entry)
	if type(key) ~= "string" or key == "" or type(tier) ~= "number" or tier ~= math.floor(tier) then return nil end
	local limited = if type(items.LimitedNumberOf) == "function" then items.LimitedNumberOf(entry) else nil
	local maximum = if type(items.MaxLimitedOf) == "function" then items.MaxLimitedOf(entry) else nil
	local signature = if type(items.SignatureOf) == "function" then items.SignatureOf(entry) else nil
	return string.format("%q|%d|%q|%q|%q", key, tier, tostring(limited), tostring(maximum), tostring(signature))
end

local function inventoryRemainder(entries: any, items: any, key: string, sourceTier: number): { [string]: number }?
	if type(entries) ~= "table" then return nil end
	local counts = {}
	for _, entry in ipairs(entries) do
		local entryKey = type(items.KeyOf) == "function" and items.KeyOf(entry) or nil
		local entryTier = type(items.TierOf) == "function" and items.TierOf(entry) or nil
		if entryKey ~= key or (entryTier ~= sourceTier and entryTier ~= sourceTier + 1) then
			local identity = inventoryEntryIdentity(entry, items)
			if identity == nil then return nil end
			counts[identity] = (counts[identity] or 0) + 1
		end
	end
	return counts
end

local function sameCounts(left: any, right: any): boolean
	if type(left) ~= "table" or type(right) ~= "table" then return false end
	for key, count in pairs(left) do if right[key] ~= count then return false end end
	for key, count in pairs(right) do if left[key] ~= count then return false end end
	return true
end
local function child(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name)
end

local function galaxy2HazardRoot(instance: Instance): boolean
	local name = instance.Name
	return (instance:IsA("BasePart") and (name == "Lava" or name:match("^%s*(.-)%s*$") == "KillPart" or name == "InvisibleKillWall"))
		or (instance:IsA("Model") and (name == "EyesLaser" or name == "ReversePad"))
end

local function stageTeleportLocked(storage: Instance): boolean
	local configs = child(storage, "CurrentGameplayConfigs")
	local restrictions = configs and child(configs, "GameplayRestrictions")
	return restrictions ~= nil and restrictions:GetAttribute("StageTeleportLocked") == true
end

local function number(value: any): number
	return if type(value) == "number" then value else 0
end

local function normalizedCatalogName(name: string): string
	return (name:gsub("Trail$", ""):gsub("Aura$", ""))
end

local function owned(state: any, field: string, catalogKey: string): boolean
	local entries = state[field]
	local normalized = normalizedCatalogName(catalogKey)
	return type(entries) == "table" and (
		entries[normalized] == true or entries[catalogKey] == true
		or table.find(entries, normalized) ~= nil or table.find(entries, catalogKey) ~= nil
	)
end

local function itemEquipFingerprint(state: any): string?
	if type(state) ~= "table" or type(state.Items) ~= "table" or type(state.EquippedItems) ~= "table" then return nil end
	local function entryFingerprint(entry: any): string
		if type(entry) ~= "table" then return tostring(entry) end
		return string.format("%q|%s|%s|%s|%s", tostring(entry.Key), tostring(entry.Tier), tostring(entry.Limited), tostring(entry.MaxLimited), tostring(entry.Signature))
	end
	local items, equipped = {}, {}
	for _, entry in ipairs(state.Items) do table.insert(items, entryFingerprint(entry)) end
	for _, entry in ipairs(state.EquippedItems) do table.insert(equipped, entryFingerprint(entry)) end
	table.sort(items)
	table.sort(equipped)
	return table.concat(items, ",") .. "/" .. table.concat(equipped, ",")
end

local function sortedItemVariants(config: any): { string }
	local rows = {}
	local prices = if type(config) == "table" then config.WINS_PRICES else nil
	if type(prices) ~= "table" then return {} end
	for rarity, price in pairs(prices) do
		if type(rarity) == "string" and number(price) > 0 then
			table.insert(rows, { rarity = rarity, price = number(price) })
		end
	end
	table.sort(rows, function(a, b)
		if a.price == b.price then return a.rarity < b.rarity end
		return a.price < b.price
	end)
	local variants = {}
	for index, row in ipairs(rows) do variants[index] = row.rarity end
	return variants
end

function Runtime.new(options: { [string]: any }?): any
	options = options or {}
	local self = setmetatable({}, Runtime)
	self._options = options
	self._galaxy2 = (options.placeId or game.PlaceId) == GALAXY_2_PLACE_ID
	self._players = options.players or Players
	self._storage = options.replicatedStorage or ReplicatedStorage
	self._world = options.workspace or workspace
	self._runService = options.runService or RunService
	self._tweenService = options.tweenService or TweenService
	self._wait = options.wait or task.wait
	self._spawn = options.spawn or task.spawn
	self._clock = options.clock or os.clock
	self._active = true
	self._version = 0
	self._workers = {}
	self._workerVersions = {}
	self._connections = {}
	self._shopConnection = nil
	self._movementOwner = nil
	self._moveTween = nil
	self._movementRestore = nil
	self._obstacleConnection = nil
	self._obstacleParts = {}
	self._removedObstacleRoots = {}
	self._godConnections = {}
	self._godCharacterConnection = nil
	self._godCharacter = nil
	self._stableRoot = nil
	self._lastStable = nil
	self._previousPosition = nil
	self._nextDirectWinAt = 0
	self._lastDirectRewardAt = nil
	self._directPing = 0
	self._stage1Timing = nil
	self._stage1Ping = 0
	self._routeInvalidated = false
	self._flags = {
		autoWins = false, autoAdminEvents = false, godMode = false, removeObstacles = false, autoRebirth = false,
		autoBuyTrails = false, autoBuyAuras = false, autoBuyItems = false, autoEquipTrails = false, autoEquipAuras = false,
		autoEquipItems = false, autoKeys = false, autoFuse = false, autoGloveBattle = false,
	}
	self._strategies = { STRATEGY_MAX }
	self._itemVariants = {}
	self._selectedItemVariants = {}
	self._itemVariantsLoaded = false
	self._selectedKeyKinds = {}
	self._selectedFuseItems = {}
	self._gloveLastTarget = nil
	self._movementLease = nil
	self._adminEventChoices = {}
	self._selectedAdminEvents = {}
	self._fuseConnection = nil
	self._fusePending = nil
	self._buyItemsPending = nil
	self._checkpointPending = nil
	self._lastItemEquipFingerprint = nil
	self._equipItemsPending = nil
	self._telemetry = { keysCollected = 0, fusesCompleted = 0, gloveActivations = 0, itemEquipActions = 0, trailEquipActions = 0, auraEquipActions = 0 }
	self._status = {
		wins = "Off", adminEvents = "Off", godMode = "Off", rebirth = "Off", trails = "Off", auras = "Off", items = "Off",
		keys = "Off", fuse = "Off", glove = "Off", equipItems = "Off", equipTrails = "Off", equipAuras = "Off",
	}
	local eventCollectors = options.eventCollectors
	if type(eventCollectors) == "table" and type(eventCollectors.new) == "function" then
		local choices = type(eventCollectors.CHOICES) == "table" and eventCollectors.CHOICES or {}
		self._adminEventChoices = table.clone(choices)
		self._selectedAdminEvents = table.clone(choices)
		local created, collector = pcall(function()
			return eventCollectors.new({
				players = self._players,
				replicatedStorage = self._storage,
				workspace = self._world,
				runService = self._runService,
				collectionService = options.collectionService or CollectionService,
				clock = self._clock,
				wait = self._wait,
				spawn = self._spawn,
				getState = function() return self:_state() end,
				moveTo = function(position: any) return self:_moveEventTo(position) end,
				setMovementActive = function(active: any) self:_setEventMovementActive(active) end,
				getLegacyActive = options.getLegacyActive,
				getFrameworkStates = options.getFrameworkStates,
				listTargets = options.listTargets,
				sendRequest = options.sendRequest,
			})
		end)
		if created and type(collector) == "table" then
			self._eventCollector = collector
		else
			if created and type(collector) == "table" and type(collector.Destroy) == "function" then
				pcall(function() collector:Destroy() end)
			end
			self._status.adminEvents = "Error: collector initialization failed"
		end
	end
	local cheatWarningRemote = options.cheatWarningRemote or self._storage:FindFirstChild("CheatWarningEvent")
	local function onRouteInvalidated()
		self._routeInvalidated = true
		if self._active then
			self._nextDirectWinAt = math.max(self._nextDirectWinAt, self._clock() + 30)
			if self._flags.autoWins then
				self:_stopAutoWins()
				self._status.wins = "Route invalidated; Auto Wins stopped"
			end
		end
	end
	if typeof(cheatWarningRemote) == "Instance" and cheatWarningRemote:IsA("RemoteEvent") then
		table.insert(self._connections, cheatWarningRemote.OnClientEvent:Connect(onRouteInvalidated))
	elseif type(cheatWarningRemote) == "table" and cheatWarningRemote.OnClientEvent then
		table.insert(self._connections, cheatWarningRemote.OnClientEvent:Connect(onRouteInvalidated))
	end
	return self
end

function Runtime:_setEventMovementActive(active: any)
	if active == true then
		self._movementOwner = "events"
	elseif self._movementOwner == "events" then
		self._movementOwner = nil
	end
end

function Runtime:_moveEventTo(position: any): boolean
	if not self._active or not self._flags.autoAdminEvents then return false end
	if not self:_releaseOutgoingMovement("events") then return false end
	local root = self:_root()
	if root == nil or root.Anchored then return false end
	local character = root.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then return false end
	local targetPosition = if typeof(position) == "CFrame" then position.Position else position
	if typeof(targetPosition) ~= "Vector3" then return false end
	if self._moveTween then
		pcall(function() self._moveTween:Cancel() end)
		self._moveTween = nil
	end
	self:_releaseMovementState(self._movementRestore)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.new(targetPosition) * root.CFrame.Rotation
	if self._flags.godMode then
		self._lastStable = root.CFrame
		self._previousPosition = root.Position
	end
	self._movementOwner = "events"
	return true
end
function Runtime:_adminEventSnapshot(): { [string]: any }
	if self._eventCollector == nil or type(self._eventCollector.Snapshot) ~= "function" then
		return { status = self._status.adminEvents, current = nil, requests = 0, confirmed = 0 }
	end
	local read, snapshot = pcall(function() return self._eventCollector:Snapshot() end)
	if read and type(snapshot) == "table" then
		local transition = self._automationTransition
		if snapshot.active == false and self._flags.autoAdminEvents
			and (transition == nil or transition.owner ~= "events") then
			self._flags.autoAdminEvents = false
			self:_setEventMovementActive(false)
			if type(snapshot.status) == "string" then self._status.adminEvents = snapshot.status end
		end
		return snapshot
	end
	self._status.adminEvents = "Error: collector snapshot failed"
	return { status = self._status.adminEvents, current = nil, requests = 0, confirmed = 0 }
end


function Runtime:_state(): any
	if type(self._options.getState) == "function" then return self._options.getState() or {} end
	return require(self._storage:WaitForChild("ClientState")):Get() or {}
end

function Runtime:_config(): any
	if type(self._options.getWorldConfig) == "function" then return self._options.getWorldConfig() or {} end
	return require(if self._galaxy2 then self._storage.Config.Worlds.World4 else self._storage.Config.Worlds.World3)
end

function Runtime:_winsMultiplier(): number
	if type(self._options.getWinsMultiplier) == "function" then return self._options.getWinsMultiplier() end
	return require(self._storage.BonusManager):GetWinsMultiplier(self._players.LocalPlayer)
end

function Runtime:_rebirthTiers(): any
	if self._options.rebirthTiers ~= nil then return self._options.rebirthTiers end
	return require(self._storage:WaitForChild("Config")).REBIRTH_TIERS
end

function Runtime:_winDebounceDelay(): any
	local rootConfig = self:_winValidationConfig()
	return if type(rootConfig) == "table" then rootConfig.WIN_DEBOUNCE_DELAY else nil
end

function Runtime:_winValidationConfig(): any
	if type(self._options.getWinValidationConfig) == "function" then return self._options.getWinValidationConfig() end
	local module = child(self._storage, "Config")
	return module and require(module)
end

function Runtime:_networkPing(): any
	if type(self._options.getNetworkPing) == "function" then return self._options.getNetworkPing() end
	local player = self._players.LocalPlayer
	return player and player:GetNetworkPing()
end

function Runtime:_root(): BasePart?
	if type(self._options.getRoot) == "function" then return self._options.getRoot() end
	local player = self._players.LocalPlayer
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Runtime:_waitCurrent(name: string, generation: number, seconds: number): boolean
	local elapsed = 0
	while self._active and self._workers[name] == generation and elapsed < seconds do
		local step = math.min(0.1, seconds - elapsed)
		local started = self._clock()
		local actual = self._wait(step)
		local measured = self._clock() - started
		elapsed += math.max(step, measured, if type(actual) == "number" then actual else 0)
	end
	return self._active and self._workers[name] == generation
end

function Runtime:_start(name: string, callback: (number) -> ())
	self._version += 1
	local generation = (self._workerVersions[name] or 0) + 1
	self._workerVersions[name] = generation
	self._workers[name] = generation
	self._spawn(function()
		if not self._active or self._workers[name] ~= generation then return end
		local ok, err = xpcall(function() callback(generation) end, debug.traceback)
		if not ok and self._active and self._workers[name] == generation then
			local status = if name == "wins" then "wins" elseif name == "godMode" then "godMode" elseif name == "rebirth" then "rebirth"
				elseif name == "trails" then "trails" elseif name == "auras" then "auras" elseif name == "equiptrails" then "equipTrails"
				elseif name == "equipauras" then "equipAuras" elseif name == "equipItems" then "equipItems" elseif name == "keys" then "keys"
				elseif name == "fuse" then "fuse" elseif name == "glove" then "glove" else "items"
			if name == "wins" then
				self:_stopAutoWins()
			elseif name == "godMode" then
				self:_stop(name)
				self:SetGodMode(false)
			elseif name == "rebirth" then
				self:SetAutoRebirth(false)
			elseif name == "trails" or name == "auras" then
				self:_setCatalog(name, false)
			elseif name == "equiptrails" or name == "equipauras" then
				self:_setCatalogEquip(if name == "equiptrails" then "trails" else "auras", false)
			elseif name == "equipItems" then
				self._flags.autoEquipItems = false
				self:_stop(name)
				local pending = self._equipItemsPending
				if pending and pending.connection then pending.connection:Disconnect() end
				self._equipItemsPending = nil
			elseif name == "keys" then
				self:SetAutoKeys(false)
			elseif name == "fuse" then
				self:_stopAutoFuse("Off")
			elseif name == "glove" then
				self:SetAutoGloveBattle(false)
			else
				self:SetAutoBuyItems(false)
			end
			if self._workers[name] == generation then self:_stop(name) end
			if self._workers[name] == nil and self._workerVersions[name] == generation + 1 then
				self._status[status] = "Error: " .. tostring(err)
			end
		end
	end)
end

function Runtime:_stop(name: string)
	self._workers[name] = nil
	self._workerVersions[name] = (self._workerVersions[name] or 0) + 1
	self._version += 1
end

function Runtime:ResolveMaxStage(): (number, number, number)
	local level = number(self:_state().Level)
	local requirements = self:_config().STAGE_RECOMMENDED_LEVELS or {}
	if self._galaxy2 then
		local resolvedStage = 1
		for stage = 2, GALAXY_2_MAX_STAGE do
			local requirement = number(requirements[stage])
			if requirement <= 0 or level < requirement then
				return resolvedStage, GALAXY_2_MAX_STAGE, requirement
			end
			resolvedStage = stage
		end
		return resolvedStage, GALAXY_2_MAX_STAGE, 0
	end
	local resolvedStage = 3
	for stage = 4, MAX_DIRECT_STAGE do
		local route = DIRECT_ROUTES[stage]
		local requirement = number(requirements[route.checkpoint])
		if requirement <= 0 or level < requirement then
			return resolvedStage, MAX_DIRECT_STAGE, requirement
		end
		resolvedStage = stage
	end
	return resolvedStage, MAX_DIRECT_STAGE, 0
end

function Runtime:Snapshot(): { [string]: any }
	local state = self:_state()
	self:_settleCheckpointPending()
	self:_settleBuyItemsPending()
	local maxStage, maxSupportedStage, requirement = self:ResolveMaxStage()
	local adminEvents = self:_adminEventSnapshot()
	local fuseChoices = self:_reconcileFuseSelection(state)
	return {
		active = self._active, version = self._version, level = number(state.Level), rebirths = number(state.Rebirths), wins = number(state.Wins),
		maxStage = maxStage, maxStageRequirement = requirement, maxSupportedStage = maxSupportedStage,
		winStrategies = table.clone(self._strategies), autoWins = self._flags.autoWins, adminEventChoices = table.clone(self._adminEventChoices),
		selectedAdminEvents = table.clone(self._selectedAdminEvents), autoAdminEvents = self._flags.autoAdminEvents,
		keyChoices = table.clone(KEY_CHOICES), selectedKeyKinds = table.clone(self._selectedKeyKinds), autoKeys = self._flags.autoKeys,
		fuseChoices = fuseChoices, selectedFuseItems = table.clone(self._selectedFuseItems), autoFuse = self._flags.autoFuse,
		autoGloveBattle = self._flags.autoGloveBattle,
		itemVariants = self:_getItemVariants(), selectedItemVariants = table.clone(self._selectedItemVariants),
		godMode = self._flags.godMode, removeObstacles = self._flags.removeObstacles,
		autoRebirth = self._flags.autoRebirth, autoBuyTrails = self._flags.autoBuyTrails, autoBuyAuras = self._flags.autoBuyAuras, autoBuyItems = self._flags.autoBuyItems,
		autoEquipItems = self._flags.autoEquipItems, autoEquipTrails = self._flags.autoEquipTrails, autoEquipAuras = self._flags.autoEquipAuras,
		winsStatus = self._status.wins, adminEventsStatus = adminEvents.status or self._status.adminEvents,
		adminEventsCurrent = adminEvents.current, adminEventRequests = number(adminEvents.requests),
		adminEventConfirmed = number(adminEvents.confirmed), godModeStatus = self._status.godMode, rebirthStatus = self._status.rebirth,
		trailsStatus = self._status.trails, aurasStatus = self._status.auras, itemsStatus = self._status.items,
		equipItemsStatus = self._status.equipItems, equipTrailsStatus = self._status.equipTrails, equipAurasStatus = self._status.equipAuras,
		keysStatus = self._status.keys, fuseStatus = self._status.fuse, gloveStatus = self._status.glove,
		keysCollected = self._telemetry.keysCollected, fusesCompleted = self._telemetry.fusesCompleted, gloveActivations = self._telemetry.gloveActivations,
		itemEquipActions = self._telemetry.itemEquipActions, trailEquipActions = self._telemetry.trailEquipActions, auraEquipActions = self._telemetry.auraEquipActions,
	}
end

function Runtime:SetWinStrategies(strategies: any): boolean
	if not self._active or type(strategies) ~= "table" or #strategies > 1 then return false end
	local accepted, seen = {}, {}
	for _, strategy in ipairs(strategies) do
		if (strategy ~= STRATEGY_STAGE_1 and strategy ~= STRATEGY_MAX) or seen[strategy] then return false end
		seen[strategy] = true
		table.insert(accepted, strategy)
	end
	self._strategies = accepted
	return true
end

function Runtime:SetAdminEventKinds(choices: any): boolean
	if not self._active or self._eventCollector == nil or type(self._eventCollector.SetSelected) ~= "function" then return false end
	local called, accepted = pcall(function() return self._eventCollector:SetSelected(choices) end)
	if called and accepted == true then
		self._selectedAdminEvents = table.clone(choices)
		return true
	end
	return false
end

function Runtime:_withAutomationTransition(owner: string, status: string, callback: (any) -> (boolean, string?)): (boolean, string?)
	if self._automationTransition ~= nil then return false, "Wait for the current movement transition to finish before trying again" end
	local transition = { owner = owner, cancelled = false }
	self._automationTransition = transition
	local ok, result, detail = xpcall(function() return callback(transition) end, debug.traceback)
	if self._automationTransition == transition then self._automationTransition = nil end
	if not ok then
		self._status[status] = "Error: " .. tostring(result)
		return false, self._status[status]
	end
	return result == true, detail
end

function Runtime:_cancelAutomationTransition(owner: string)
	local transition = self._automationTransition
	if transition and transition.owner == owner then transition.cancelled = true end
end

function Runtime:_stopAutoWins(): boolean
	self._flags.autoWins = false
	self._status.wins = if self._checkpointPending then "Off; checkpoint request still pending" else "Off"
	self:_stop("wins")
	local stoppedVersion = self._workerVersions.wins
	local movementState = self._movementRestore
	local tween = self._moveTween
	if tween then
		pcall(function() tween:Cancel() end)
		local deadline = self._clock() + 0.25
		while self._moveTween == tween and self._clock() < deadline do self._runService.Heartbeat:Wait() end
		if self._moveTween == tween then self._moveTween = nil end
	end
	self:_releaseMovementState(movementState)
	if self._workerVersions.wins == stoppedVersion and self._movementOwner == "wins" then self._movementOwner = nil end
	return true
end

function Runtime:_stopAutoAdminEvents(): boolean
	local stopped = true
	if type(self._eventCollector.Stop) == "function" then
		local called, result = pcall(function() return self._eventCollector:Stop() end)
		stopped = called and result ~= false
	else
		stopped = false
	end
	if stopped then
		self._flags.autoAdminEvents = false
		self:_setEventMovementActive(false)
		self._status.adminEvents = "Off"
	else
		self._status.adminEvents = "Error: collector stop failed"
	end
	return stopped
end

function Runtime:SetAutoAdminEvents(enabled: any): (boolean, string?)
	if not self._active or self._eventCollector == nil then return false end
	if enabled ~= true then
		self:_cancelAutomationTransition("events")
		return self:_stopAutoAdminEvents()
	end
	if self._flags.autoAdminEvents then return true end
	return self:_withAutomationTransition("events", "adminEvents", function(transition)
		if self._flags.autoKeys then self:SetAutoKeys(false) end
		if self._flags.autoGloveBattle then self:SetAutoGloveBattle(false) end
		local restoreAutoWins = self._flags.autoWins
		if restoreAutoWins then self:_stopAutoWins() end
		local stoppedWinsVersion = self._workerVersions.wins
		local released, reason = self:_awaitOutgoingMovement("events")
		if not released then return false, reason end
		if not self._active or transition.cancelled then return false end
		self._flags.autoAdminEvents = true
		local result = false
		if type(self._eventCollector.Start) ~= "function" then
			self._flags.autoAdminEvents = false
			self:_setEventMovementActive(false)
			self._status.adminEvents = "Error: collector start unavailable"
		else
			local called, started, err = pcall(function() return self._eventCollector:Start() end)
			if not called or started ~= true or not self._active or transition.cancelled then
				if type(self._eventCollector.Stop) == "function" then pcall(function() self._eventCollector:Stop() end) end
				self._flags.autoAdminEvents = false
				self:_setEventMovementActive(false)
				self._status.adminEvents = if transition.cancelled then "Off" else "Error: " .. tostring(if called then err else started)
			else
				self._status.adminEvents = "Starting"
				result = true
			end
		end
		if not result and restoreAutoWins and self._active and not transition.cancelled
			and self._workerVersions.wins == stoppedWinsVersion and self:_releaseOutgoingMovement("wins") then
			self._flags.autoWins = true
			self._status.wins = "Starting"
			self:_start("wins", function(generation) self:_runWins(generation) end)
		end
		return result
	end)
end

function Runtime:RunStage1(timing: any?): boolean
	if not self._active or (timing ~= nil and not self:_stage1Current(timing)) then return false end
	if not self:_releaseOutgoingMovement("wins") then return false end
	if not self._active or (timing ~= nil and not self:_stage1Current(timing)) then return false end
	local structure = child(self._world, if self._galaxy2 then "Stages" else "Structure")
	local stage = structure and child(structure, "Stage1")
	local sas = stage and child(stage, "SAS")
	local plate = sas and child(sas, if self._galaxy2 then "WinBlock1" else "WinBlock32")
	if plate == nil or not plate:IsA("BasePart") then self._status.wins = "Stage 1 plate unavailable" return false end
	local root = self:_root()
	if not self._active or (timing ~= nil and not self:_stage1Current(timing)) then return false end
	if root == nil or root.Anchored then self._status.wins = "Character unavailable" return false end
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then self._status.wins = "Character unavailable" return false end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = plate.CFrame * CFrame.new(0, 1.5, 0)
	self:_refreshStablePose(root)
	return true
end

function Runtime:_releaseMovementState(state: any): boolean
	if state == nil or self._movementRestore ~= state then return false end
	self._movementRestore = nil
	if state.collisionConnection then state.collisionConnection:Disconnect() end
	if state.collisionParts then
		for part, canCollide in pairs(state.collisionParts) do
			pcall(function() part.CanCollide = canCollide end)
		end
	end
	if state.managesHumanoid then
		pcall(function()
			state.humanoid.AutoRotate = state.autoRotate
			state.humanoid.WalkSpeed = state.walkSpeed
		end)
	end
	return true
end

function Runtime:_moveTo(position: Vector3, generation: number, speed: number?, expectedRoot: BasePart?, timing: any?, holdTeleportLabel: string?): boolean
	local root = self:_root()
	if not self._active or self._workers.wins ~= generation or (timing ~= nil and not self:_directCurrent(timing)) then return false end
	if root == nil or root.Anchored or self._movementRestore ~= nil or (expectedRoot ~= nil and root ~= expectedRoot) then return false end
	local character = root.Parent
	if character == nil then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or (timing ~= nil and timing.tweenOnly and humanoid.Health <= 0) then return false end
	local start = root.CFrame
	local target = CFrame.new(position) * start.Rotation
	local distance = (start.Position - position).Magnitude
	local requestedSpeed = if number(speed) > 0 then number(speed) else ROUTE_SPEED
	local duration = math.max(0.001, distance / math.min(requestedSpeed, MAX_ROUTE_SPEED))
	local previousAutoRotate, previousWalkSpeed = humanoid.AutoRotate, humanoid.WalkSpeed
	local movementState: any = {
		humanoid = humanoid, autoRotate = previousAutoRotate, walkSpeed = previousWalkSpeed,
		managesHumanoid = timing == nil or not timing.tweenOnly,
	}
	self._movementRestore = movementState
	if timing ~= nil and timing.tweenOnly then
		local collisionParts = {}
		movementState.collisionParts = collisionParts
		local function disableCollision(instance: Instance)
			if not instance:IsA("BasePart") or not self:_directCurrent(timing) or self._movementRestore ~= movementState then return end
			if collisionParts[instance] == nil then collisionParts[instance] = instance.CanCollide end
			instance.CanCollide = false
		end
		movementState.collisionConnection = character.DescendantAdded:Connect(disableCollision)
		for _, instance in ipairs(character:GetDescendants()) do disableCollision(instance) end
	end
	if not self._active or self._workers.wins ~= generation or self._movementRestore ~= movementState
		or (timing ~= nil and not self:_directCurrent(timing))
		or (holdTeleportLabel ~= nil and (root.Anchored or root.Parent ~= character or humanoid.Parent ~= character or humanoid.Health <= 0)) then
		self:_releaseMovementState(movementState)
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if movementState.managesHumanoid then
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.Jump = false
		humanoid:Move(Vector3.zero, false)
	end

	local created, tween = pcall(function()
		return self._tweenService:Create(
			root,
			TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
			{ CFrame = if holdTeleportLabel ~= nil then start else target }
		)
	end)
	if not created or tween == nil or not self._active or self._workers.wins ~= generation
		or (timing ~= nil and not self:_directCurrent(timing))
		or (holdTeleportLabel ~= nil and (self._movementRestore ~= movementState or root.Anchored
			or root.Parent ~= character or humanoid.Parent ~= character or humanoid.Health <= 0)) then
		self:_releaseMovementState(movementState)
		return false
	end
	self._moveTween = tween
	local played = pcall(function() tween:Play() end)
	if not played then
		self._moveTween = nil
		self:_releaseMovementState(movementState)
		return false
	end

	local started = self._clock()
	local arrived = false
	local previousPosition, previousSampleAt = start.Position, started
	while self._clock() - started <= duration + TWEEN_SETTLE_TIMEOUT do
		local currentRoot = self:_root()
		if currentRoot ~= root or not self._active or self._workers.wins ~= generation
			or (timing ~= nil and not self:_directCurrent(timing))
			or (holdTeleportLabel ~= nil and (self._movementRestore ~= movementState or self._moveTween ~= tween
				or root.Anchored or root.Parent ~= character or humanoid.Parent ~= character or humanoid.Health <= 0)) then break end
		if timing ~= nil and timing.tweenOnly and timing.contactWins ~= nil then
			local sampledAt = self._clock()
			local sampledPosition = root.Position
			local expectedTravel = math.min(requestedSpeed, MAX_ROUTE_SPEED) * math.max(0, sampledAt - previousSampleAt)
			-- Native plate handling can reset the pose before Wins replicates.
			-- Stop this tween immediately; only the reward observer may confirm it.
			if (sampledPosition - previousPosition).Magnitude > math.max(50, expectedTravel + 20) then break end
			previousPosition, previousSampleAt = sampledPosition, sampledAt
			local currentWins = number(self:_state().Wins)
			if not self:_directCurrent(timing) then break end
			if currentWins > timing.contactWins then
				timing.rewardAt = self._clock()
				arrived = true
				break
			end
		end
		if holdTeleportLabel ~= nil then
			-- Spend the original distance/speed budget at the source, even if
			-- the stationary tween reports completion or the target is close.
			if self._clock() - started >= duration then arrived = true break end
		else
			local remaining = (position - root.Position).Magnitude
			if remaining <= MOVE_ARRIVAL_RADIUS or (self._clock() - started >= duration and remaining <= 2) then
				arrived = true
				break
			end
		end
		if root.Anchored or (timing ~= nil and timing.tweenOnly and humanoid.Health <= 0) then break end
		if movementState.collisionParts then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			for part, canCollide in pairs(movementState.collisionParts) do
				if part:IsDescendantOf(character) then
					part.CanCollide = false
				else
					pcall(function() part.CanCollide = canCollide end)
					movementState.collisionParts[part] = nil
				end
			end
		end
		if movementState.managesHumanoid then
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 0
			humanoid.Jump = false
			humanoid:Move(Vector3.zero, false)
		end
		self._runService.Heartbeat:Wait()
	end
	if self._moveTween == tween then self._moveTween = nil end
	pcall(function() tween:Cancel() end)
	local ownedMovement = self:_releaseMovementState(movementState)
	if ownedMovement and movementState.managesHumanoid then humanoid:Move(Vector3.zero, false) end
	if self:_root() ~= root or not self._active or self._workers.wins ~= generation or not arrived
		or (timing ~= nil and not self:_directCurrent(timing))
		or (holdTeleportLabel ~= nil and (not ownedMovement or self._moveTween ~= nil or self._movementRestore ~= nil or root.Anchored
			or root.Parent ~= character or humanoid.Parent ~= character or humanoid.Health <= 0)) then return false end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if holdTeleportLabel ~= nil then
		-- The stationary tween is cancelled and ownership rechecked before
		-- this sole jump; the direct-write helper refreshes God Mode's stable pose.
		self:_writeDirectPosition(root, position, holdTeleportLabel)
		return true
	end
	if timing == nil or not timing.tweenOnly then root.CFrame = target end
	self:_refreshStablePose(root)
	return true
end

function Runtime:_isObstacle(instance: Instance): boolean
	if self._galaxy2 then return false end
	local current: Instance? = instance
	while current and current ~= self._world do
		local parent = current.Parent
		if (current.Name == "Ball1" or current.Name == "Tsunami1") and parent and parent.Name == "NPC & Piege" then return false end
		if current.Name == "NPC & Piege" then return true end
		current = parent
	end
	return false
end

function Runtime:_neutralizeObstacle(instance: Instance)
	if not instance:IsA("BasePart") or not self:_isObstacle(instance) then return end
	if self._obstacleParts[instance] == nil then
		local original: any = {
			canCollide = instance.CanCollide,
			canTouch = instance.CanTouch,
			localTransparencyModifier = instance.LocalTransparencyModifier,
			connection = nil,
		}
		self._obstacleParts[instance] = original
		original.connection = instance.AncestryChanged:Connect(function()
			if not self._flags.removeObstacles or self:_isObstacle(instance) then return end
			instance.CanCollide = original.canCollide
			instance.CanTouch = original.canTouch
			instance.LocalTransparencyModifier = original.localTransparencyModifier
			original.connection:Disconnect()
			self._obstacleParts[instance] = nil
		end)
	end
	instance.CanCollide = false
	instance.CanTouch = false
	instance.LocalTransparencyModifier = 1
end

function Runtime:_isObstacleRoot(instance: Instance): boolean
	if self._galaxy2 then
		if not galaxy2HazardRoot(instance) then return false end
		local current = instance.Parent
		while current and current ~= self._world do
			if current.Name == "Stages" and current.Parent == self._world then return true end
			-- Detach the outer hazard only, so nested parts keep their parent
			-- and native touch connections throughout removal and restoration.
			if galaxy2HazardRoot(current) then return false end
			current = current.Parent
		end
		return false
	end
	local parent = instance.Parent
	if instance.Name == "NPC_LolMonster" and parent == self._world then return true end
	if parent and parent.Name == "NPC & Piege" and instance.Name == "NPC_Zone5" then return true end
	if instance.Name == "FoeCakes" and parent and parent.Name == "Stage6" then
		local structure = parent.Parent
		return structure ~= nil and structure.Name == "Structure" and structure.Parent == self._world
	end
	return false
end

function Runtime:_detachObstacleRoot(instance: Instance)
	if not self:_isObstacleRoot(instance) then return end
	local alreadyTracked = self._removedObstacleRoots[instance] ~= nil
	if not alreadyTracked then self._removedObstacleRoots[instance] = instance.Parent end
	local ok = pcall(function() instance.Parent = nil end)
	if not ok and not alreadyTracked then self._removedObstacleRoots[instance] = nil end
end

function Runtime:_restoreObstacles()
	if self._obstacleConnection then self._obstacleConnection:Disconnect() self._obstacleConnection = nil end
	for instance, original in pairs(self._obstacleParts) do
		if original.connection then original.connection:Disconnect() end
		pcall(function()
			instance.CanCollide = original.canCollide
			instance.CanTouch = original.canTouch
			instance.LocalTransparencyModifier = original.localTransparencyModifier
		end)
	end
	table.clear(self._obstacleParts)
	for instance, originalParent in pairs(self._removedObstacleRoots) do
		if originalParent and originalParent.Parent then pcall(function() instance.Parent = originalParent end) end
	end
	table.clear(self._removedObstacleRoots)
end

function Runtime:SetRemoveObstacles(enabled: any): boolean
	if not self._active then return false end
	local nextEnabled = enabled == true
	if self._flags.removeObstacles == nextEnabled then return true end
	self._flags.removeObstacles = nextEnabled
	if nextEnabled then
		local hazards = child(self._world, "NPC & Piege")
		local structure = child(self._world, "Structure")
		local stageSix = structure and child(structure, "Stage6")
		local roots = {
			hazards and child(hazards, "NPC_Zone5"),
			child(self._world, "NPC_LolMonster"),
			stageSix and child(stageSix, "FoeCakes"),
		}
		for index = 1, 3 do
			local root = roots[index]
			if root then self:_detachObstacleRoot(root) end
		end
		if hazards then
			for _, descendant in ipairs(hazards:GetDescendants()) do self:_neutralizeObstacle(descendant) end
		end
		local stages = self._galaxy2 and child(self._world, "Stages")
		if stages then
			for _, descendant in ipairs(stages:GetDescendants()) do self:_detachObstacleRoot(descendant) end
		end
		self._obstacleConnection = self._world.DescendantAdded:Connect(function(descendant)
			if not self._flags.removeObstacles then return end
			if self:_isObstacleRoot(descendant) then self:_detachObstacleRoot(descendant) else self:_neutralizeObstacle(descendant) end
		end)
	else
		self:_restoreObstacles()
	end
	return true
end

function Runtime:_refreshStablePose(root: BasePart)
	if self._flags.godMode and self._stableRoot == root then
		self._lastStable = root.CFrame
		self._previousPosition = root.Position
	end
end

function Runtime:_settleCheckpointPending(): boolean
	local pending = self._checkpointPending
	if pending == nil then return true end
	if not self._active then return false end
	if not pending.accounted then
		if not pending.acknowledged then return false end
		local wins = number(self:_state().Wins)
		if not self._active or self._checkpointPending ~= pending or wins ~= pending.expectedWins then return false end
		pending.accounted = true
	end
	if not pending.poseReady then return false end
	local root = self:_root()
	if not self._active or self._checkpointPending ~= pending then return false end
	if root then self:_refreshStablePose(root) end
	pending.settledAt = pending.settledAt or self._clock()
	pending.readyAt = pending.settledAt + pending.validationDelay + pending.buffer
	if self._lastDirectRewardAt ~= nil then
		pending.readyAt = math.max(pending.readyAt, self._lastDirectRewardAt + pending.debounce + pending.buffer)
	end
	pending.settled = true
	if pending.connection then pending.connection:Disconnect() end
	if pending.poseConnection then pending.poseConnection:Disconnect() end
	self._checkpointPending = nil
	self._nextDirectWinAt = math.max(self._nextDirectWinAt, pending.readyAt)
	if not self._flags.autoWins then self._status.wins = "Off" end
	return true
end

function Runtime:_writeDirectPosition(root: BasePart, position: Vector3, label: string)
	root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	self:_refreshStablePose(root)
	local observer = self._options.onDirectMove
	if type(observer) == "function" then observer(label, position, self._clock()) end
end

function Runtime:_directCurrent(timing: any): boolean
	if not self._active or not self._flags.autoWins or self._workers.wins ~= timing.generation
		or self._strategies ~= timing.strategies or timing.strategies[1] ~= STRATEGY_MAX then return false end
	local root = self:_root()
	-- A root getter can yield as well; recheck the session after it returns.
	return root ~= nil and root == timing.root and self._active and self._flags.autoWins
		and self._workers.wins == timing.generation and self._strategies == timing.strategies
		and timing.strategies[1] == STRATEGY_MAX
end

function Runtime:_directBuffer(timing: any): number?
	local readPing, ping = pcall(self._networkPing, self)
	if not self:_directCurrent(timing) then return nil end
	if readPing and type(ping) == "number" and ping >= 0 and ping < math.huge then
		self._directPing = ping
	end
	return math.max(DIRECT_SAFETY_MARGIN, self._directPing / 2)
end

function Runtime:_directReadyAt(timing: any, pending: any): number?
	local buffer = self:_directBuffer(timing)
	if buffer == nil then return nil end
	pending.buffer = math.max(pending.buffer, buffer)
	pending.readyAt = math.max(pending.readyAt, pending.settledAt + pending.validationDelay + pending.buffer)
	if self._lastDirectRewardAt ~= nil then
		pending.readyAt = math.max(pending.readyAt, self._lastDirectRewardAt + pending.debounce + pending.buffer)
	end
	self._nextDirectWinAt = math.max(self._nextDirectWinAt, pending.readyAt)
	return pending.readyAt
end

function Runtime:_waitDirectReady(timing: any, pending: any, stage: number): boolean
	while self:_directCurrent(timing) do
		-- Every deadline check includes a fresh RTT sample, including the final
		-- one before movement. A larger margin can extend but never shorten it.
		local readyAt = self:_directReadyAt(timing, pending)
		if readyAt == nil then return false end
		local remaining = readyAt - self._clock()
		if remaining <= 0 then return self:_directCurrent(timing) end
		self._status.wins = string.format("Stage %d gate %.2fs", stage, math.ceil(remaining * 100) / 100)
		self._wait(math.min(DIRECT_WAIT_STEP, remaining))
	end
	return false
end

function Runtime:_runGalaxy2Tween(generation: number): boolean
	local timing = { generation = generation, strategies = self._strategies, root = self:_root(), tweenOnly = true }
	if not self:_directCurrent(timing) then return false end
	if not self:_releaseOutgoingMovement("wins") or not self:_directCurrent(timing) or self._buyItemsPending ~= nil then return false end
	while self:_directCurrent(timing) do
		local cooldown = self._nextDirectWinAt - self._clock()
		if cooldown <= 0 then break end
		self._status.wins = string.format("Max Stage retry delay %.0fs", math.ceil(cooldown))
		self._wait(math.min(DIRECT_WAIT_STEP, cooldown))
	end
	if not self:_directCurrent(timing) then return false end
	local targetStage = self:ResolveMaxStage()
	if not self:_directCurrent(timing) then return false end
	local plateName = "WinBlock" .. targetStage
	local loaded, validation = pcall(self._winValidationConfig, self)
	if not self:_directCurrent(timing) then return false end
	local minima = if loaded and type(validation) == "table" then validation.WIN_MIN_TIMES else nil
	local minimum = if targetStage == 1 then 0 elseif type(minima) == "table" then minima[plateName] else nil
	local debounce = if loaded and type(validation) == "table" then validation.WIN_DEBOUNCE_DELAY else nil
	if type(minimum) ~= "number" or not (minimum >= 0 and minimum < math.huge)
		or type(debounce) ~= "number" or not (debounce > 0 and debounce < math.huge) then
		self._status.wins = string.format("Waiting for Stage %d validation configuration", targetStage)
		return false
	end
	local buffer = self:_directBuffer(timing)
	if buffer == nil then return false end
	buffer = math.max(buffer, GALAXY_2_SAFETY_MARGIN)
	local zones = self._galaxy2ZonePositions
	if zones == nil then
		zones = {}
		self._galaxy2ZonePositions = zones
	end
	local function captureZones(): boolean
		local zonesRoot = child(self._world, "Zones")
		local stageZones = zonesRoot and child(zonesRoot, "Stages")
		local seen = {}
		if stageZones then
			for _, instance in ipairs(stageZones:GetDescendants()) do
				if instance:IsA("BasePart") then
					local sas = instance:GetAttribute("SAS")
					if type(sas) == "number" and sas == math.floor(sas) and sas >= 1 and sas <= targetStage + 1 then
						if seen[sas] then
							self._status.wins = string.format("SAS %d route ambiguous", sas)
							return false
						end
						seen[sas] = instance.Position
					end
				end
			end
		end
		for sas, position in pairs(seen) do zones[sas] = position end
		return true
	end
	if not captureZones() or not self:_directCurrent(timing) then return false end
	local player = self._players.LocalPlayer
	for sas = 1, targetStage + 1 do
		if zones[sas] == nil then
			self._status.wins = string.format("Streaming SAS %d route", sas)
			local streamed = pcall(function() player:RequestStreamAroundAsync(GALAXY_2_SAS_STREAM_HINTS[sas], 8) end)
			if not self:_directCurrent(timing) then return false end
			if not streamed then self._status.wins = string.format("SAS %d streaming failed", sas) return false end
			if not captureZones() or not self:_directCurrent(timing) then return false end
			if zones[sas] == nil then self._status.wins = string.format("SAS %d route unavailable", sas) return false end
		end
	end
	local function findPlate(): BasePart?
		local stages = child(self._world, "Stages")
		local stage = stages and child(stages, "Stage" .. targetStage)
		local sas = stage and child(stage, "SAS")
		local found = sas and child(sas, plateName)
		return if found and found:IsA("BasePart") then found else nil
	end
	local plate = findPlate()
	if plate == nil then
		local streamed = pcall(function() player:RequestStreamAroundAsync(zones[targetStage + 1], 8) end)
		if not self:_directCurrent(timing) then return false end
		if not streamed then self._status.wins = string.format("Stage %d streaming failed", targetStage) return false end
		plate = findPlate()
	end
	if plate == nil then
		self._status.wins = string.format("Stage %d plate unavailable", targetStage)
		return false
	end
	local root = timing.root
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	if root.Anchored or humanoid == nil or humanoid.Health <= 0 then
		self._status.wins = "Character unavailable"
		return false
	end
	local points = {}
	local previousPosition, courseDuration = root.Position, 0
	local function append(position: Vector3, speed: number, holdTeleportLabel: string?)
		if #points > 0 then courseDuration += (position - previousPosition).Magnitude / speed end
		previousPosition = position
		table.insert(points, { position = position, speed = speed, holdTeleportLabel = holdTeleportLabel })
	end
	for zoneId = 1, targetStage + 1 do
		local center = zones[zoneId]
		if zoneId == 9 then
			-- Stage 8's left kill wall starts above SAS 8, while its right
			-- wall opens at SAS 9 height. Enter low, then rise between them.
			local previousCenter = zones[8]
			local midpointX = (previousCenter.X + center.X) / 2
			append(Vector3.new(midpointX, previousCenter.Y, previousCenter.Z), GALAXY_2_ROUTE_SPEED)
			append(Vector3.new(midpointX, center.Y, center.Z), GALAXY_2_ROUTE_SPEED)
		end
		-- Only the final SAS leg holds then jumps. Its nominal
		-- distance still contributes to the same course-wide timing scale.
		append(center, GALAXY_2_ROUTE_SPEED, if targetStage == 10 and zoneId == 11 then "SAS10->SAS11" else nil)
		-- The native zone tracker samples at 0.1s. Keep tweening inside each
		-- SAS for 0.2s rather than pausing in midair or skipping its sample.
		append(center + Vector3.new(0, 0, 1), 5)
	end
	append((plate.CFrame * CFrame.new(0, 1.5, 0)).Position, GALAXY_2_ROUTE_SPEED)
	-- Exclude the SAS 1 approach from the configured course-time budget,
	-- then scale remaining legs using the configured minimum and debounce.
	local scale = math.min(1, courseDuration / (math.max(minimum, debounce) + buffer))
	if not self:_directCurrent(timing) then return false end
	self._routeInvalidated = false
	self._movementOwner = "wins"
	local function releaseMovement()
		if self._workers.wins == generation and self._movementOwner == "wins" then self._movementOwner = nil end
	end
	for index, point in ipairs(points) do
		if index == #points then
			plate = findPlate()
			if plate == nil then
				local streamed = pcall(function() player:RequestStreamAroundAsync(zones[targetStage + 1], 8) end)
				if not self:_directCurrent(timing) then releaseMovement() return false end
				if streamed then plate = findPlate() end
			end
			if plate == nil then
				releaseMovement()
				self._nextDirectWinAt = math.max(self._nextDirectWinAt, self._clock() + debounce + buffer)
				self._status.wins = string.format("Stage %d plate unavailable", targetStage)
				return false
			end
			point.position = (plate.CFrame * CFrame.new(0, 1.5, 0)).Position
			timing.contactWins = number(self:_state().Wins)
			if not self:_directCurrent(timing) then releaseMovement() return false end
		end
		self._status.wins = string.format("Stage %d %s %d/%d", targetStage, if point.holdTeleportLabel then "hold + TP" else "tween", index, #points)
		local speed = if index == 1 then point.speed else point.speed * scale
		local moved = self:_moveTo(point.position, generation, speed, root, timing, point.holdTeleportLabel)
		if not self:_directCurrent(timing) then releaseMovement() return false end
		if not moved and index < #points then
			releaseMovement()
			self._nextDirectWinAt = math.max(self._nextDirectWinAt, self._clock() + debounce + buffer)
			self._status.wins = string.format("Stage %d route interrupted; safe retry scheduled", targetStage)
			return false
		end
	end
	-- A native payout can reset the root before the last tween samples its
	-- arrival. Never move back: only a positive authoritative Wins delta wins.
	local rewardDeadline = self._clock() + DIRECT_REWARD_TIMEOUT
	while self:_directCurrent(timing) do
		local currentWins = number(self:_state().Wins)
		if not self:_directCurrent(timing) then releaseMovement() return false end
		local observedAt = self._clock()
		if observedAt > rewardDeadline then break end
		if timing.rewardAt ~= nil or currentWins > timing.contactWins then
			self._lastDirectRewardAt = timing.rewardAt or observedAt
			self._nextDirectWinAt = 0
			self:_refreshStablePose(root)
			releaseMovement()
			self._status.wins = string.format("Stage %d win confirmed by route", targetStage)
			return true
		end
		local remaining = rewardDeadline - observedAt
		if remaining <= 0 then break end
		self._status.wins = string.format("Stage %d observing reward", targetStage)
		self._wait(math.min(0.02, remaining))
	end
	releaseMovement()
	if not self:_directCurrent(timing) then return false end
	self._nextDirectWinAt = math.max(self._nextDirectWinAt, self._clock() + debounce + buffer)
	self._status.wins = string.format("Stage %d reward unconfirmed; safe retry scheduled", targetStage)
	return false
end

function Runtime:_runValidatedDirect(generation: number): boolean
	local timing = { generation = generation, strategies = self._strategies, root = self:_root() }
	if not self:_directCurrent(timing) then return false end
	if stageTeleportLocked(self._storage) then
		self._status.wins = "Waiting for event: stage teleports disabled"
		return false
	end
	if not self:_releaseOutgoingMovement("wins") or not self:_directCurrent(timing) or self._buyItemsPending ~= nil then return false end
	while self:_directCurrent(timing) do
		local cooldown = self._nextDirectWinAt - self._clock()
		if cooldown <= 0 then break end
		self._status.wins = string.format("Max Stage retry delay %.0fs", math.ceil(cooldown))
		self._wait(math.min(DIRECT_WAIT_STEP, cooldown))
	end
	if not self:_directCurrent(timing) then return false end
	local directStage = self:ResolveMaxStage()
	if not self:_directCurrent(timing) then return false end
	local route = DIRECT_ROUTES[directStage]
	if route == nil then self._status.wins = "No validated direct route" return false end
	local loaded, validation = pcall(self._winValidationConfig, self)
	if not self:_directCurrent(timing) then return false end
	local minima = if loaded and type(validation) == "table" then validation.WIN_MIN_TIMES else nil
	local targetMinimum = if type(minima) == "table" then minima[route.plate] else nil
	local previousPlate = "WinBlock" .. (tonumber(string.match(route.plate, "%d+$")) - 1)
	local previousMinimum = if type(minima) == "table" then minima[previousPlate] else nil
	local debounce = if loaded and type(validation) == "table" then validation.WIN_DEBOUNCE_DELAY else nil
	if type(targetMinimum) ~= "number" or not (targetMinimum >= 0 and targetMinimum < math.huge)
		or type(previousMinimum) ~= "number" or not (previousMinimum >= 0 and previousMinimum < math.huge)
		or targetMinimum <= previousMinimum
		or type(debounce) ~= "number" or not (debounce > 0 and debounce < math.huge) then
		self._status.wins = string.format("Waiting for Stage %d validation configuration", directStage)
		return false
	end
	local buffer = self:_directBuffer(timing)
	if buffer == nil then return false end
	self._routeInvalidated = false
	local checkpointStage = route.checkpoint
	local player = self._players.LocalPlayer
	local streamed = pcall(function() player:RequestStreamAroundAsync(route.staging, 8) end)
	if not self:_directCurrent(timing) then return false end
	if not streamed then self._status.wins = string.format("Stage %d streaming failed", directStage) return false end
	if stageTeleportLocked(self._storage) then
		self._status.wins = "Waiting for event: stage teleports disabled"
		return false
	end
	local structure = child(self._world, "Structure")
	local stage = structure and child(structure, "Stage" .. directStage)
	local sas = stage and child(stage, "SAS")
	local plate = sas and child(sas, route.plate)
	if plate == nil or not plate:IsA("BasePart") then self._status.wins = string.format("Stage %d plate unavailable", directStage) return false end

	local worldConfig = self:_config()
	if not self:_directCurrent(timing) then return false end
	local multiplier = self:_winsMultiplier()
	if not self:_directCurrent(timing) then return false end
	local checkpointCost = math.floor(worldConfig.CHECKPOINTS[checkpointStage].WinPrice * multiplier)
	local beforeCheckpoint = number(self:_state().Wins)
	if not self:_directCurrent(timing) then return false end
	if stageTeleportLocked(self._storage) then
		self._status.wins = "Waiting for event: stage teleports disabled"
		return false
	end
	if beforeCheckpoint < checkpointCost then
		self._status.wins = "Waiting for checkpoint Wins"
		return false
	end
	local pending = {
		acknowledged = false, accounted = false, settled = false, poseFrameSeen = false, poseReady = false,
		connection = nil :: any, poseConnection = nil :: any, settledAt = nil :: number?,
		expectedWins = beforeCheckpoint - checkpointCost,
		validationDelay = targetMinimum - previousMinimum, debounce = debounce, buffer = buffer, readyAt = 0,
	}
	local successRemote = self._options.checkpointSuccessRemote or self._storage.Remotes.CheckpointTpSuccess
	local requestRemote = self._options.checkpointRequestRemote or self._storage.Remotes.RequestCheckpointTp
	pending.connection = successRemote.OnClientEvent:Connect(function()
		if self._checkpointPending ~= pending or not self._active then return end
		pending.acknowledged = true
		self:_settleCheckpointPending()
	end)
	-- Acknowledgement/cost can precede CFrame replication. Retain the request
	-- across two post-accounting Heartbeats before starting the remaining gate.
	pending.poseConnection = self._runService.Heartbeat:Connect(function()
		if self._checkpointPending ~= pending or not self._active or not pending.acknowledged then return end
		self:_settleCheckpointPending()
		if self._checkpointPending ~= pending or not self._active then return end
		if pending.accounted then
			if pending.poseFrameSeen then
				pending.poseReady = true
				self:_settleCheckpointPending()
			else
				pending.poseFrameSeen = true
			end
		end
	end)
	self._checkpointPending = pending
	self._movementOwner = "wins"
	local sent, requestError = pcall(function() requestRemote:FireServer(checkpointStage, "wins") end)
	if not sent then
		if pending.connection then pending.connection:Disconnect() end
		if pending.poseConnection then pending.poseConnection:Disconnect() end
		if self._checkpointPending == pending then self._checkpointPending = nil end
		if self:_directCurrent(timing) then
			self:_stopAutoWins()
			self._status.wins = "Checkpoint request failed: " .. tostring(requestError)
		end
		return false
	end
	local ackDeadline = self._clock() + CHECKPOINT_ACK_TIMEOUT
	while self:_directCurrent(timing) and self._checkpointPending == pending and not pending.acknowledged do
		local remaining = ackDeadline - self._clock()
		if remaining <= 0 then break end
		self._wait(math.min(0.02, remaining))
	end
	local costDeadline = self._clock() + CHECKPOINT_COST_TIMEOUT
	while self:_directCurrent(timing) and self._checkpointPending == pending and pending.acknowledged do
		if self:_settleCheckpointPending() then break end
		if not self:_directCurrent(timing) then break end
		if not pending.accounted then
			local currentWins = number(self:_state().Wins)
			if not self:_directCurrent(timing) or currentWins < pending.expectedWins then break end
		end
		local remaining = costDeadline - self._clock()
		if remaining <= 0 then break end
		self._wait(math.min(0.02, remaining))
	end
	if self:_directCurrent(timing) and self._checkpointPending == pending then self:_settleCheckpointPending() end
	if not self:_directCurrent(timing) then
		if self._workers.wins == generation and self._movementOwner == "wins" then self._movementOwner = nil end
		return false
	end
	if not pending.settled then
		self:_stopAutoWins()
		self._status.wins = if pending.accounted
			then string.format("Checkpoint %d movement settlement unconfirmed", checkpointStage)
			elseif pending.acknowledged
			then string.format("Checkpoint %d cost unconfirmed", checkpointStage)
			else string.format("Checkpoint %d for Stage %d unconfirmed", checkpointStage, directStage)
		return false
	end

	if not self:_waitDirectReady(timing, pending, directStage) then
		if self._workers.wins == generation and self._movementOwner == "wins" then self._movementOwner = nil end
		return false
	end
	local root = timing.root
	if root.Anchored or stageTeleportLocked(self._storage) then
		if self._movementOwner == "wins" then self._movementOwner = nil end
		self._status.wins = "Stage movement unavailable"
		return false
	end
	self._movementOwner = "wins"
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	self:_writeDirectPosition(root, route.staging, "staging")
	local moved = self:_directCurrent(timing)
		and self:_moveTo(plate.Position + Vector3.new(0, 1.5, 0), generation, DIRECT_APPROACH_SPEED, root, timing)
	if self._workers.wins == generation and self._movementOwner == "wins" then self._movementOwner = nil end
	if not self:_directCurrent(timing) then return false end
	if not moved then self._status.wins = string.format("Stage %d plate approach failed", directStage) return false end

	local rewardDeadline = self._clock() + DIRECT_REWARD_TIMEOUT
	while self:_directCurrent(timing) do
		local currentWins = number(self:_state().Wins)
		if not self:_directCurrent(timing) then return false end
		local rewardAt = self._clock()
		if rewardAt > rewardDeadline then break end
		if currentWins >= beforeCheckpoint + route.minNet then
			self._nextDirectWinAt = 0
			self._lastDirectRewardAt = rewardAt
			self._status.wins = string.format("Stage %d win confirmed via checkpoint %d", directStage, checkpointStage)
			return true
		end
		local remaining = rewardDeadline - rewardAt
		if remaining <= 0 then break end
		self._wait(math.min(0.02, remaining))
	end
	if not self:_directCurrent(timing) then return false end
	self._status.wins = string.format("Stage %d reward unconfirmed; safe retry scheduled", directStage)
	return false
end

function Runtime:_stage1Current(timing: any): boolean
	return self._active and self._flags.autoWins and self._workers.wins == timing.generation
		and self._stage1Timing == timing and self._strategies == timing.strategies
		and timing.strategies[1] == STRATEGY_STAGE_1
end

function Runtime:_stage1ReadyAt(timing: any): number?
	local readDelay, delay = pcall(self._winDebounceDelay, self)
	if not self:_stage1Current(timing) then return nil end
	if not readDelay or type(delay) ~= "number" or delay ~= delay or delay <= 0 or delay == math.huge then
		timing.anchorAt = self._clock()
		self._status.wins = "Waiting for Stage 1 cooldown configuration"
		return nil
	end
	local readPing, ping = pcall(self._networkPing, self)
	if not self:_stage1Current(timing) then return nil end
	if readPing and type(ping) == "number" and ping == ping and ping >= 0 and ping < math.huge then
		self._stage1Ping = ping
	end
	-- GetNetworkPing is RTT in seconds. Unknown ping keeps the last sample;
	-- no latency estimate is subtracted from the observed cooldown anchor.
	local margin = math.max(STAGE_1_SAFETY_MARGIN, self._stage1Ping / 2)
	timing.readyAt = math.max(timing.readyAt, timing.anchorAt + delay + margin)
	return timing.readyAt
end

function Runtime:_waitStage1Ready(timing: any): (boolean, number?)
	local readyAt, nextTimingRead, nextStatusAt = nil, 0, 0
	while self:_stage1Current(timing) do
		local currentWins = number(self:_state().Wins)
		if not self:_stage1Current(timing) then return false end
		local now = self._clock()
		if currentWins > timing.wins then
			-- Keep observing after a timeout: a late positive reward resets
			-- the cooldown before a queued retry can touch the plate.
			timing.anchorAt = now
			timing.readyAt = 0
			timing.wins = currentWins
			nextTimingRead = 0
		end
		if now >= nextTimingRead or (readyAt ~= nil and now >= readyAt) then
			-- Getters may yield, so ownership is checked after every read.
			-- The final sample can extend, but never shorten, this deadline.
			readyAt = self:_stage1ReadyAt(timing)
			if not self:_stage1Current(timing) then return false end
			now = self._clock()
			nextTimingRead = now + STAGE_1_WAIT_STEP
		end
		local remaining = if readyAt ~= nil then readyAt - now else STAGE_1_WAIT_STEP
		if readyAt ~= nil and remaining <= 0 then
			local latestWins = number(self:_state().Wins)
			if not self:_stage1Current(timing) then return false end
			if latestWins > timing.wins then
				timing.anchorAt = self._clock()
				timing.readyAt = 0
				timing.wins = latestWins
				nextTimingRead = 0
				continue
			end
			return true, latestWins
		end
		if readyAt ~= nil and now >= nextStatusAt then
			self._status.wins = string.format("Stage 1 cooldown %.2fs", math.ceil(remaining * 100) / 100)
			nextStatusAt = now + STAGE_1_WAIT_STEP
		end
		self._wait(math.min(STAGE_1_REWARD_POLL, remaining))
	end
	return false
end

function Runtime:_waitForWins(before: number, generation: number, timing: any): boolean
	local deadline = self._clock() + STAGE_1_REWARD_TIMEOUT
	while self:_stage1Current(timing) and self._workers.wins == generation do
		local currentWins = number(self:_state().Wins)
		if not self:_stage1Current(timing) then return false end
		local observedAt = self._clock()
		if observedAt > deadline then return false end
		if currentWins > before then
			timing.anchorAt = observedAt
			timing.readyAt = 0
			timing.wins = currentWins
			return true
		end
		local remaining = deadline - observedAt
		if remaining <= 0 then return false end
		self._wait(math.min(STAGE_1_REWARD_POLL, remaining))
	end
	return false
end

function Runtime:_runWins(generation: number)
	while self._active and self._flags.autoWins and generation == self._workers.wins do
		local stage1Iteration = false
		local directConfirmed = false
		if #self._strategies == 0 then
			self._status.wins = "Select a win strategy"
		else
			for _, strategy in ipairs(self._strategies) do
				if not self:_waitCurrent("wins", generation, 0) then return end
				if strategy == STRATEGY_STAGE_1 then
					stage1Iteration = true
					local strategies = self._strategies
					local timing = self._stage1Timing
					if timing == nil or timing.generation ~= generation or timing.strategies ~= strategies then
						timing = { generation = generation, strategies = strategies, anchorAt = self._clock(), readyAt = 0, wins = 0 }
						self._stage1Timing = timing
						local currentWins = number(self:_state().Wins)
						if not self:_stage1Current(timing) then continue end
						timing.anchorAt = self._clock()
						timing.wins = currentWins
					end
					local ready, before = self:_waitStage1Ready(timing)
					if ready and before ~= nil and self:_stage1Current(timing) then
						self._movementOwner = "wins"
						local ran = self:RunStage1(timing)
						if self._workers.wins == generation and self._movementOwner == "wins" then self._movementOwner = nil end
						if not self:_stage1Current(timing) then continue end
						local confirmed = ran and self:_waitForWins(before, generation, timing)
						if not self:_stage1Current(timing) then continue end
						if not confirmed then
							-- Unknown acceptance starts a fresh full cooldown instead
							-- of reusing an expired attempt deadline for a rapid retry.
							timing.anchorAt = self._clock()
							timing.readyAt = 0
						end
						if ran then self._status.wins = if confirmed then "Win confirmed" else "Win not confirmed" end
					end
				else
					directConfirmed = if self._galaxy2 then self:_runGalaxy2Tween(generation) else self:_runValidatedDirect(generation)
				end
			end
		end
		if not stage1Iteration and not directConfirmed and not self:_waitCurrent("wins", generation, WORKER_DELAY) then return end
	end
	if self._workers.wins == generation and self._movementOwner == "wins" then self._movementOwner = nil end
end
function Runtime:SetAutoWins(enabled: any): (boolean, string?)
	if not self._active then return false end
	if enabled ~= true then
		self:_cancelAutomationTransition("wins")
		return self:_stopAutoWins()
	end
	if self._flags.autoWins then return true end
	return self:_withAutomationTransition("wins", "wins", function(transition)
		if not self:_settleBuyItemsPending() then
			self._status.wins = "Wait for item purchase confirmation before trying again"
			return false, self._status.wins
		end
		if self._flags.autoKeys then self:SetAutoKeys(false) end
		if self._flags.autoGloveBattle then self:SetAutoGloveBattle(false) end
		if self._flags.autoAdminEvents and not self:_stopAutoAdminEvents() then return false end
		local released, reason = self:_awaitOutgoingMovement("wins")
		if not released then return false, reason end
		if not self._active or transition.cancelled then return false end
		if self._moveTween ~= nil then return false end
		self._flags.autoWins = true
		self._status.wins = "Starting"
		self:_start("wins", function(generation) self:_runWins(generation) end)
		return true
	end)
end

function Runtime:_restoreGodMode()
	for _, connection in ipairs(self._godConnections) do connection:Disconnect() end
	table.clear(self._godConnections)
	self._godCharacter = nil
	self._stableRoot = nil
	self._lastStable = nil
	self._previousPosition = nil
end

function Runtime:_nativeGravityActive(): boolean
	if not self._galaxy2 then return false end
	if not self._gravityControllerLoaded then
		local controller = self._options.gravityController
		if controller == nil then
			local loaded, resolved = pcall(function()
				local framework = child(self._storage, "_FRAMEWORK")
				local features = framework and child(framework, "Features")
				local clientOnly = features and child(features, "ClientOnly")
				local module = clientOnly and child(clientOnly, "GravityController")
				return module and require(module)
			end)
			if loaded then controller = resolved end
		end
		self._gravityController = controller
		self._gravityControllerLoaded = true
	end
	local controller = self._gravityController
	if type(controller) ~= "table" or type(controller.isActive) ~= "function" then return false end
	local readActive, active = pcall(controller.isActive)
	return readActive and active == true
end

function Runtime:_attachGodMode(character: Model?)
	if not self._active or not self._flags.godMode or character == nil then return end
	self:_restoreGodMode()
	self._godCharacter = character
	if self._galaxy2 then
		-- Resolve the optional native module before installing heartbeat
		-- listeners, so a yielding require cannot misclassify its active rig.
		self:_nativeGravityActive()
		if not self._active or not self._flags.godMode or self._godCharacter ~= character then return end
	end
	local function attachRoot()
		if not self._active or not self._flags.godMode or self._godCharacter ~= character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			self._stableRoot = root
			self._lastStable = root.CFrame
			self._previousPosition = root.Position
		else
			self._stableRoot = nil
			self._lastStable = nil
			self._previousPosition = nil
		end
	end
	attachRoot()
	table.insert(self._godConnections, character.ChildAdded:Connect(function(added)
		if self._stableRoot == nil or (added.Name == "HumanoidRootPart" and added:IsA("BasePart")) then attachRoot() end
	end))
	table.insert(self._godConnections, self._runService.Heartbeat:Connect(function(deltaTime)
		if not self._active or not self._flags.godMode or self._godCharacter ~= character then return end
		local root = self._stableRoot
		if root == nil or root.Parent ~= character then attachRoot() root = self._stableRoot end
		if root == nil then self._status.godMode = "Waiting for character root" return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then self._status.godMode = "Waiting for humanoid" return end
		local nativeGravityActive = self._galaxy2 and self:_nativeGravityActive()
		if not self._active or not self._flags.godMode or self._godCharacter ~= character
			or self._stableRoot ~= root or root.Parent ~= character then return end
		local cframe = root.CFrame
		local linear = root.AssemblyLinearVelocity
		local angular = root.AssemblyAngularVelocity
		local state = humanoid:GetState()
		local ragdolled = state == Enum.HumanoidStateType.Ragdoll
			or (self._galaxy2 and state == Enum.HumanoidStateType.FallingDown)
			or (not nativeGravityActive and (humanoid.PlatformStand or state == Enum.HumanoidStateType.Physics))
		if ragdolled then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		if self._movementLease ~= nil then
			self._status.godMode = if self._movementLease.owner == "keys" then "Protecting Auto Keys" else "Protecting Glove Battle"
			return
		end
		if self._movementOwner == "wins" or self._movementOwner == "events" or self._moveTween ~= nil then
			self._lastStable = cframe
			self._previousPosition = cframe.Position
			self._status.godMode = if self._movementOwner == "events" then "Protecting Admin Events" else "Protecting Auto Wins"
			return
		end

		local frameTime = if type(deltaTime) == "number" and deltaTime > 0 then deltaTime else 1 / 60
		local horizontalLimit = math.max(ANTI_FLING_HORIZONTAL_SPEED, humanoid.WalkSpeed * 2)
		local displacementLimit = math.max(ANTI_FLING_RECOVERY_DISTANCE, humanoid.WalkSpeed * frameTime * 3)
		local horizontal = Vector3.new(linear.X, 0, linear.Z).Magnitude
		local displacement = if self._previousPosition then cframe.Position - self._previousPosition else Vector3.zero
		local horizontalDisplacement = Vector3.new(displacement.X, 0, displacement.Z).Magnitude
		local abnormal = ragdolled
			or horizontal > horizontalLimit
			or linear.Y > ANTI_FLING_VERTICAL_SPEED
			or angular.Magnitude > ANTI_FLING_ANGULAR_SPEED
			or (self._checkpointPending == nil and horizontalDisplacement > displacementLimit)
		if abnormal then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if self._lastStable then root.CFrame = self._lastStable self._previousPosition = self._lastStable.Position end
		else
			self._lastStable = cframe
			self._previousPosition = cframe.Position
		end
		self._status.godMode = "Protecting local movement"
	end))
	self._status.godMode = "Protecting local movement"
end

function Runtime:SetGodMode(enabled: any): boolean
	if not self._active then return false end
	local nextEnabled = enabled == true
	if self._flags.godMode == nextEnabled then
		if not nextEnabled then self:_restoreGodMode() end
		return true
	end
	self._flags.godMode = nextEnabled
	if nextEnabled then
		if self._godCharacterConnection then self._godCharacterConnection:Disconnect() end
		local player = self._players.LocalPlayer
		self._godCharacterConnection = player.CharacterAdded:Connect(function(character) self:_attachGodMode(character) end)
		self:_attachGodMode(player.Character)
	else
		if self._godCharacterConnection then self._godCharacterConnection:Disconnect() self._godCharacterConnection = nil end
		self:_restoreGodMode()
		self._status.godMode = "Off"
	end
	return true
end

function Runtime:_rebirth(generation: number): boolean
	local state = self:_state()
	local tier = self:_rebirthTiers()[number(state.Rebirths) + 1]
	if not self._active or self._workers.rebirth ~= generation then return false end
	if type(tier) ~= "table" or number(state.Level) < number(tier.level) then self._status.rebirth = "Next rebirth requires level " .. tostring(tier and tier.level or "?") return false end
	local remote = self._options.rebirthRemote or self._storage.Remotes.Rebirth
	local beforeRebirths = number(state.Rebirths)
	remote:FireServer()
	self._status.rebirth = "Waiting for rebirth confirmation"
	local elapsed = 0
	while elapsed < 5 do
		local current = self:_state()
		if not self._active or self._workers.rebirth ~= generation then return false end
		if number(current.Rebirths) > beforeRebirths then self._status.rebirth = "Rebirth confirmed" return true end
		if not self:_waitCurrent("rebirth", generation, 0.1) then return false end
		elapsed += 0.1
	end
	self._status.rebirth = "Rebirth unconfirmed; retrying"
	return false
end

function Runtime:_runRebirth(generation: number)
	while self._active and self._flags.autoRebirth and generation == self._workers.rebirth do
		self:_rebirth(generation)
		if not self:_waitCurrent("rebirth", generation, 1) then return end
	end
end

function Runtime:SetAutoRebirth(enabled: any): boolean
	if not self._active then return false end
	local nextEnabled = enabled == true
	if self._flags.autoRebirth == nextEnabled then return true end
	self._flags.autoRebirth = nextEnabled
	self._status.rebirth = if self._flags.autoRebirth then "Starting" else "Off"
	if self._flags.autoRebirth then self:_start("rebirth", function(generation) self:_runRebirth(generation) end) else self:_stop("rebirth") end
	return true
end

function Runtime:_catalog(kind: string, inventory: any?): any
	if type(self._options.getCatalog) == "function" then return self._options.getCatalog(kind, inventory) or {} end
	local module = require(self._storage.FeatureConfigs.PlayerUpgradesCatalog)
	if inventory ~= nil then
		return if kind == "trails" then module.GetInventoryTrails(inventory) else module.GetInventoryAuras(inventory)
	end
	return if kind == "trails" then module.GetTrails() else module.GetAuras()
end

function Runtime:_catalogRequest(kind: string): any
	if type(self._options.getCatalogRequest) == "function" then return self._options.getCatalogRequest(kind) end
	local service = require(self._storage.Services[if kind == "trails" then "TrailRemotes" else "AuraRemotes"])
	return if kind == "trails" then service.BuyTrail else service.BuyAura
end

function Runtime:_buyCatalog(kind: string, generation: number)
	local state = self:_state()
	local field = if kind == "trails" then "OwnedTrails" else "OwnedAuras"
	local status = if kind == "trails" then "trails" else "auras"
	local rows = {}
	for key, row in pairs(self:_catalog(kind)) do
		if type(key) == "string" and type(row) == "table" then
			local price = number(row.Price or row.price)
			local currency = tostring(row.currency or row.Currency or "Wins")
			local blockedCurrency = currency ~= "Wins"
				or row.Robux == true
				or row.robux == true
				or row.Event == true
				or row.event == true
				or row.seasonal == true
			if price > 0 and not blockedCurrency then
				table.insert(rows, {
					key = key,
					row = row,
					price = price,
					multiplier = number(row.Multiplier or row.multiplier),
				})
			end
		end
	end
	if not self._active or self._workers[kind] ~= generation then return end
	table.sort(rows, function(a, b)
		if a.multiplier ~= b.multiplier then return a.multiplier < b.multiplier end
		if a.price ~= b.price then return a.price < b.price end
		return a.key < b.key
	end)

	local highestOwned = 0
	for index, entry in ipairs(rows) do
		if owned(state, field, entry.key) then highestOwned = index end
	end
	local entry = rows[highestOwned + 1]
	if entry == nil then
		self._status[status] = "Catalog complete"
		return
	end
	if number(state.Wins) < entry.price then
		self._status[status] = "Waiting for next upgrade"
		return
	end
	if self._flags.autoWins or not self:_settleCheckpointPending() then
		self._status[status] = "Paused while Auto Wins is active"
		return
	end
	local request = self:_catalogRequest(kind)
	if not self._active or self._workers[kind] ~= generation then return end
	if self._flags.autoWins or not self:_settleCheckpointPending() then
		self._status[status] = "Paused while Auto Wins is active"
		return
	end
	local ok = pcall(function() request:request(entry.key, "Wins"):await() end)
	if not self._active or self._workers[kind] ~= generation then return end
	if not ok then
		self._status[status] = "Purchase request failed"
		return
	end
	local elapsed = 0
	while elapsed < 5 do
		if owned(self:_state(), field, entry.key) then
			self._status[status] = "Purchase confirmed"
			return
		end
		if not self:_waitCurrent(kind, generation, 0.1) then return end
		elapsed += 0.1
	end
	self._status[status] = "Waiting for purchase confirmation"
end

function Runtime:_runCatalog(kind: string, generation: number)
	local flag = if kind == "trails" then "autoBuyTrails" else "autoBuyAuras"
	local status = if kind == "trails" then "trails" else "auras"
	while self._active and self._flags[flag] and generation == self._workers[kind] do
		self:_buyCatalog(kind, generation)
		if not self._active or self._workers[kind] ~= generation then return end
		if self._status[status] == "Starting" then self._status[status] = "Catalog checked" end
		if not self:_waitCurrent(kind, generation, 4) then return end
	end
end

function Runtime:_setCatalog(kind: string, enabled: any): boolean
	if not self._active then return false end
	local flag = if kind == "trails" then "autoBuyTrails" else "autoBuyAuras"
	local status = if kind == "trails" then "trails" else "auras"
	local nextEnabled = enabled == true
	if self._flags[flag] == nextEnabled then return true end
	self._flags[flag] = nextEnabled
	self._status[status] = if self._flags[flag] then "Starting" else "Off"
	if self._flags[flag] then self:_start(kind, function(generation) self:_runCatalog(kind, generation) end) else self:_stop(kind) end
	return true
end

function Runtime:_catalogEquipRequest(kind: string): any
	if type(self._options.getCatalogEquipRequest) == "function" then return self._options.getCatalogEquipRequest(kind) end
	local service = require(self._storage.Services[if kind == "trails" then "TrailRemotes" else "AuraRemotes"])
	return if kind == "trails" then service.EquipTrail else service.EquipAura
end

function Runtime:_strongestOwnedCatalog(kind: string, state: any): string?
	local field = if kind == "trails" then "OwnedTrails" else "OwnedAuras"
	local bestKey: string? = nil
	local bestMultiplier, bestPrice = 0, 0
	for key, row in pairs(self:_catalog(kind, state[field] or {})) do
		if type(key) == "string" and type(row) == "table" and owned(state, field, key) then
			local multiplier, price = number(row.Multiplier or row.multiplier), number(row.Price or row.price)
			if bestKey == nil or multiplier > bestMultiplier or (multiplier == bestMultiplier and (price > bestPrice or (price == bestPrice and key > bestKey))) then
				bestKey, bestMultiplier, bestPrice = key, multiplier, price
			end
		end
	end
	return bestKey
end

function Runtime:_runCatalogEquip(kind: string, generation: number)
	local flag = if kind == "trails" then "autoEquipTrails" else "autoEquipAuras"
	local status = if kind == "trails" then "equipTrails" else "equipAuras"
	local equippedField = if kind == "trails" then "EquippedTrail" else "EquippedAura"
	local counter = if kind == "trails" then "trailEquipActions" else "auraEquipActions"
	while self._active and self._flags[flag] and self._workers["equip" .. kind] == generation do
		local target = self:_strongestOwnedCatalog(kind, self:_state())
		if not self._active or self._workers["equip" .. kind] ~= generation then return end
		if target == nil then
			self._status[status] = "No owned catalog entries"
		elseif self:_state()[equippedField] == target then
			self._status[status] = "Already equipped"
		else
			local request = self:_catalogEquipRequest(kind)
			if not self._active or self._workers["equip" .. kind] ~= generation then return end
			if request == nil or type(request.fire) ~= "function" then
				self._flags[flag] = false
				self:_stop("equip" .. kind)
				self._status[status] = "Equip remote unavailable"
				return
			end
			local sent = pcall(function() request:fire(target) end)
			if not sent then
				self._flags[flag] = false
				self:_stop("equip" .. kind)
				self._status[status] = "Equip request failed"
				return
			end
			self._status[status] = "Equipping " .. target
			local elapsed = 0
			while elapsed < EQUIP_TIMEOUT and self._active and self._workers["equip" .. kind] == generation do
				if self:_state()[equippedField] == target then
					self._telemetry[counter] += 1
					self._status[status] = "Equip confirmed"
					break
				end
				if not self:_waitCurrent("equip" .. kind, generation, 0.1) then return end
				elapsed += 0.1
			end
			if self._status[status] ~= "Equip confirmed" then
				self._flags[flag] = false
				self:_stop("equip" .. kind)
				self._status[status] = "Equip unconfirmed"
				return
			end
		end
		if not self:_waitCurrent("equip" .. kind, generation, 3) then return end
	end
end

function Runtime:_setCatalogEquip(kind: string, enabled: any): boolean
	if not self._active then return false end
	local flag = if kind == "trails" then "autoEquipTrails" else "autoEquipAuras"
	local status = if kind == "trails" then "equipTrails" else "equipAuras"
	local nextEnabled = enabled == true
	if self._flags[flag] == nextEnabled then return true end
	self._flags[flag] = nextEnabled
	self._status[status] = if nextEnabled then "Starting" else "Off"
	if nextEnabled then self:_start("equip" .. kind, function(generation) self:_runCatalogEquip(kind, generation) end) else self:_stop("equip" .. kind) end
	return true
end

function Runtime:SetAutoEquipTrails(enabled: any): boolean return self:_setCatalogEquip("trails", enabled) end
function Runtime:SetAutoEquipAuras(enabled: any): boolean return self:_setCatalogEquip("auras", enabled) end

function Runtime:SetAutoBuyTrails(enabled: any): boolean return self:_setCatalog("trails", enabled) end
function Runtime:SetAutoBuyAuras(enabled: any): boolean return self:_setCatalog("auras", enabled) end

function Runtime:_itemsRemotes(): any
	return self._options.itemsShopRemotes or require(self._storage.Utilities.ItemsShopRemotes)
end

function Runtime:_itemsConfig(): any
	return self._options.itemsShopConfig or require(self._storage:WaitForChild("FeatureConfigs"):WaitForChild("ItemsShopConfig"))
end

function Runtime:_itemsFeatureConfig(): any
	if self._options.itemsFeatureConfig ~= nil then return self._options.itemsFeatureConfig end
	return require(self._storage:WaitForChild("FeatureConfigs"):WaitForChild("Items"))
end

function Runtime:_getItemVariants(): { string }
	if not self._itemVariantsLoaded then
		local loaded, config = pcall(function() return self:_itemsConfig() end)
		if loaded then
			self._itemVariants = sortedItemVariants(config)
			self._selectedItemVariants = table.clone(self._itemVariants)
			self._itemVariantsLoaded = true
		end
	end
	return table.clone(self._itemVariants)
end

function Runtime:SetItemVariants(variants: any): boolean
	if not self._active or type(variants) ~= "table" then return false end
	local choices = self:_getItemVariants()
	local allowed = {}
	for _, choice in ipairs(choices) do allowed[choice] = true end
	local accepted, seen = {}, {}
	for _, variant in ipairs(variants) do
		if type(variant) ~= "string" or not allowed[variant] or seen[variant] then return false end
		seen[variant] = true
		table.insert(accepted, variant)
	end
	self._selectedItemVariants = accepted
	return true
end

function Runtime:_updateShopState(update: any): boolean
	if type(update) ~= "table" then return false end
	local current = self._shopState
	local currentValid = type(current) == "table" and type(current.stocks) == "table" and type(current.active) == "boolean"
	if type(update.stocks) == "table" then
		local fullSnapshot = type(update.active) == "boolean"
		local stocks = {}
		if currentValid and not fullSnapshot then
			for slot, stock in pairs(current.stocks) do stocks[slot] = stock end
		end
		for slot, stock in pairs(update.stocks) do
			if type(slot) == "string" and type(stock) == "number" and stock == stock and stock >= 0 then
				stocks[slot] = stock
			end
		end
		if not currentValid and not fullSnapshot then return false end
		local nextState = {}
		if currentValid then
			for key, value in pairs(current) do nextState[key] = value end
		end
		for key, value in pairs(update) do nextState[key] = value end
		nextState.stocks = stocks
		if type(nextState.active) ~= "boolean" then nextState.active = current.active end
		self._shopState = nextState
		return true
	end
	if currentValid and update.active == false then
		local nextState = {}
		for key, value in pairs(current) do nextState[key] = value end
		nextState.active = false
		self._shopState = nextState
		return true
	end
	return false
end

function Runtime:_settleBuyItemsPending(): boolean
	local pending = self._buyItemsPending
	if pending == nil then return true end
	if not self._active then return false end
	local entries = self:_state().Items
	if type(entries) ~= "table" or #entries <= pending.beforeItems then return false end
	pending.settled = true
	self._buyItemsPending = nil
	if not self._flags.autoBuyItems then
		self:_disconnectShop()
		self._status.items = "Off"
	end
	return true
end

function Runtime:_buyItems(generation: number)
	if not self:_settleBuyItemsPending() then self._status.items = "Item purchase still pending" return end
	local remotes, config = self:_itemsRemotes(), self:_itemsConfig()
	if not self._active or self._workers.items ~= generation then return end
	local prices = type(config) == "table" and config.WINS_PRICES or nil
	if type(prices) ~= "table" then
		self._status.items = "Item shop config unavailable"
		return
	end
	local shop = self._shopState
	if type(shop) ~= "table" or shop.active ~= true then
		remotes.RequestState:fire()
		self._status.items = "Waiting for active shop"
		return
	end
	local stocks = shop.stocks
	if type(stocks) ~= "table" then
		self._status.items = "Waiting for valid shop stock"
		return
	end
	local candidate: string? = nil
	local candidateVariant: string? = nil
	local candidatePrice = 0
	local availableWins = number(self:_state().Wins)
	if not self._active or self._workers.items ~= generation then return end
	local selected = {}
	for _, variant in ipairs(self._selectedItemVariants) do selected[variant] = true end
	local selectedInStock = false
	for slot, stock in pairs(stocks) do
		local variant = if slot == "Mysterious" then shop.mysteriousRarity else slot
		local price = prices[variant]
		local purchased = if type(shop.purchases) == "table" then number(shop.purchases[slot]) else 0
		if type(variant) == "string" and selected[variant] and number(stock) - purchased > 0 then
			selectedInStock = true
			if number(price) > candidatePrice and availableWins >= number(price) then
				candidate, candidateVariant, candidatePrice = slot, variant, number(price)
			end
		end
	end
	if candidate == nil then
		self._status.items = if #self._selectedItemVariants == 0
			then "No item variants selected"
			elseif not selectedInStock
			then "Selected variants out of stock"
			else "No affordable selected stock"
		return
	end
	local beforeState = self:_state()
	if not self._active or self._workers.items ~= generation then return end
	if type(beforeState.Items) ~= "table" then self._status.items = "Waiting for inventory state" return end
	if self._flags.autoWins or not self:_settleCheckpointPending() then
		self._status.items = "Paused while Auto Wins is active"
		return
	end
	local pending = { beforeItems = #beforeState.Items, settled = false }
	self._buyItemsPending = pending
	local sent, requestError = pcall(function() remotes.BuyWins:fire(candidate) end)
	if not sent then
		if self._buyItemsPending == pending then self._buyItemsPending = nil end
		if self._active and self._workers.items == generation then
			self:SetAutoBuyItems(false)
			self._status.items = "Item purchase request failed: " .. tostring(requestError)
		end
		return
	end
	if self._workers.items == generation then self._status.items = "Buying " .. tostring(candidateVariant) .. " for Wins" end
	local elapsed = 0
	while self._active and self._buyItemsPending == pending and elapsed < BUY_CONFIRM_TIMEOUT do
		if self:_settleBuyItemsPending() then break end
		local started = self._clock()
		local actual = self._wait(0.1)
		elapsed += math.max(0.1, self._clock() - started, number(actual))
	end
	if self._active and self._buyItemsPending == pending then self:_settleBuyItemsPending() end
	if not self._active or self._workers.items ~= generation then return end
	if pending.settled then
		self._status.items = "Item purchase confirmed"
	else
		self:SetAutoBuyItems(false)
		self._status.items = "Item purchase unconfirmed; waiting for inventory"
	end
end

function Runtime:_disconnectShop()
	local connection = self._shopConnection
	self._shopConnection = nil
	if type(connection) == "function" then
		pcall(connection)
	elseif connection ~= nil and type(connection.Disconnect) == "function" then
		pcall(function() connection:Disconnect() end)
	end
	self._shopState = nil
end
function Runtime:_runItems(generation: number)
	local remotes = self:_itemsRemotes()
	if not self._active or self._workers.items ~= generation then return end
	if self._shopConnection == nil and remotes.ShopUpdate and type(remotes.ShopUpdate.connect) == "function" then
		self._shopConnection = remotes.ShopUpdate:connect(function(shopState: any)
			self:_updateShopState(shopState)
			self:_settleBuyItemsPending()
		end)
	end
	while self._active and self._flags.autoBuyItems and generation == self._workers.items do
		remotes.RequestState:fire()
		self:_buyItems(generation)
		if not self:_waitCurrent("items", generation, 3) then return end
	end
end

function Runtime:SetAutoBuyItems(enabled: any): (boolean, string?)
	if not self._active then return false end
	if enabled ~= true then
		self._flags.autoBuyItems = false
		self:_stop("items")
		local settled = self._buyItemsPending == nil
		self._status.items = if settled then "Off" else "Off; item purchase still pending"
		if settled then self:_disconnectShop() end
		return true
	end
	local settled = self:_settleBuyItemsPending()
	if self._flags.autoBuyItems then return true end
	if not settled then
		self._status.items = "Item purchase unconfirmed; wait for inventory confirmation before trying again"
		return false, self._status.items
	end
	if self._flags.autoFuse or self._fusePending ~= nil then
		self._status.items = "Disabled while Auto Fuse is active"
		return false
	end
	self._flags.autoBuyItems = true
	self._status.items = "Starting"
	self:_start("items", function(generation) self:_runItems(generation) end)
	return true
end

function Runtime:_itemActionRemote(): any
	if self._options.itemActionRemote ~= nil then return self._options.itemActionRemote end
	local remotes = self._storage:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild("ItemAction")
end

function Runtime:_runEquipItems(generation: number)
	while self._active and self._flags.autoEquipItems and self._workers.equipItems == generation do
		local before = itemEquipFingerprint(self:_state())
		if not self._active or self._workers.equipItems ~= generation then return end
		if before == nil then
			self._status.equipItems = "Waiting for inventory state"
		elseif before == self._lastItemEquipFingerprint then
			self._status.equipItems = "Equip Best confirmed"
		else
			local remote = self:_itemActionRemote()
			if not self._active or self._workers.equipItems ~= generation then return end
			if remote == nil or remote.OnClientEvent == nil or type(remote.FireServer) ~= "function" then
				self._flags.autoEquipItems = false
				self:_stop("equipItems")
				self._status.equipItems = "ItemAction unavailable"
				return
			end
			local pending = { confirmed = false, fingerprint = nil :: string?, connection = nil :: any }
			self._equipItemsPending = pending
			local connected, connection = pcall(function()
				return remote.OnClientEvent:Connect(function(action: any, payload: any)
					if self._equipItemsPending ~= pending or action ~= "Update" or type(payload) ~= "table" then return end
					local fingerprint = itemEquipFingerprint(payload)
					if fingerprint ~= nil then
						pending.confirmed = true
						pending.fingerprint = fingerprint
					end
				end)
			end)
			if not connected or connection == nil then
				self._equipItemsPending = nil
				self._flags.autoEquipItems = false
				self:_stop("equipItems")
				self._status.equipItems = "ItemAction unavailable"
				return
			end
			pending.connection = connection
			local sent = pcall(function() remote:FireServer("EquipBest") end)
			if not sent then
				connection:Disconnect()
				self._equipItemsPending = nil
				self._flags.autoEquipItems = false
				self:_stop("equipItems")
				self._status.equipItems = "Equip Best request failed"
				return
			end
			self._status.equipItems = "Equipping best items"
			local elapsed = 0
			while elapsed < EQUIP_TIMEOUT and self._active and self._workers.equipItems == generation and not pending.confirmed do
				if not self:_waitCurrent("equipItems", generation, 0.1) then connection:Disconnect() return end
				elapsed += 0.1
			end
			connection:Disconnect()
			self._equipItemsPending = nil
			if pending.confirmed then
				self._lastItemEquipFingerprint = pending.fingerprint
				self._telemetry.itemEquipActions += 1
				if not self._flags.autoEquipItems then
					self:_stop("equipItems")
					self._status.equipItems = "Off"
					return
				end
				self._status.equipItems = "Equip Best confirmed"
			else
				self._flags.autoEquipItems = false
				self:_stop("equipItems")
				self._status.equipItems = "Equip Best unconfirmed"
				return
			end
		end
		if not self:_waitCurrent("equipItems", generation, 3) then return end
	end
end

function Runtime:SetAutoEquipItems(enabled: any): boolean
	if not self._active then return false end
	local nextEnabled = enabled == true
	if nextEnabled and self._equipItemsPending ~= nil then
		self._status.equipItems = "Equip Best request still pending"
		return false
	end
	if self._flags.autoEquipItems == nextEnabled then return true end
	if nextEnabled and (self._flags.autoFuse or self._fusePending ~= nil) then
		self._status.equipItems = "Disabled while Auto Fuse is active"
		return false
	end
	if not nextEnabled and self._equipItemsPending ~= nil then
		self._flags.autoEquipItems = false
		self._status.equipItems = "Stopping after pending Equip Best"
		return true
	end
	self._flags.autoEquipItems = nextEnabled
	self._status.equipItems = if nextEnabled then "Starting" else "Off"
	if nextEnabled then self:_start("equipItems", function(currentGeneration) self:_runEquipItems(currentGeneration) end) else self:_stop("equipItems") end
	return true
end

function Runtime:_fuseChoices(state: any?): { string }
	local loaded, items = pcall(function() return self:_itemsFeatureConfig() end)
	if not loaded then return {} end
	local mergeCount = number(items.MERGE_COUNT)
	if mergeCount ~= 5 then return {} end
	local labels = {}
	for label, group in pairs(fuseGroups(state or self:_state(), items)) do
		if group.tier < number(items.MAX_TIER) and group.count >= mergeCount then table.insert(labels, label) end
	end
	table.sort(labels)
	return labels
end

function Runtime:SetKeyKinds(kinds: any): boolean
	if not self._active or type(kinds) ~= "table" then return false end
	local allowed, accepted = { ["Gold Key"] = true, ["Secret Key"] = true }, {}
	for _, kind in ipairs(kinds) do
		if type(kind) ~= "string" or not allowed[kind] or table.find(accepted, kind) then return false end
		table.insert(accepted, kind)
	end
	self._selectedKeyKinds = accepted
	return true
end
function Runtime:_releaseMovementLease(lease: any): boolean
	if lease == nil or self._movementLease ~= lease then return false end
	self._movementLease = nil
	local restored = pcall(function()
		if lease.restorePose then
			lease.root.CFrame = lease.cframe
			lease.root.AssemblyLinearVelocity = lease.linear
			lease.root.AssemblyAngularVelocity = lease.angular
		end
		lease.humanoid.AutoRotate = lease.autoRotate
		lease.humanoid.WalkSpeed = lease.walkSpeed
	end)
	if restored and self._flags.godMode and self._stableRoot == lease.root then
		self._lastStable = lease.root.CFrame
		self._previousPosition = self._lastStable.Position
	end
	if self._movementOwner == lease.owner then self._movementOwner = nil end
	return true
end

function Runtime:_releaseOutgoingMovement(owner: string): boolean
	if not self:_settleCheckpointPending() then return false end
	local lease = self._movementLease
	return lease == nil or lease.owner == owner
end
function Runtime:_awaitOutgoingMovement(owner: string): (boolean, string?)
	if not self:_settleCheckpointPending() then
		local status = if owner == "events" then "adminEvents" elseif owner == "glove" then "glove" elseif owner == "keys" then "keys" else "wins"
		self._status[status] = "Wait for pending checkpoint acknowledgement, cost and movement settlement before trying again"
		return false, self._status[status]
	end
	if self:_releaseOutgoingMovement(owner) then return true end
	for _ = 1, 30 do
		self._wait(0.03)
		if not self._active then return false end
		if self:_releaseOutgoingMovement(owner) then return true end
	end
	return false, "Wait for the previous movement to stop before trying again"
end


function Runtime:_withMovementLease(owner: string, callback: (BasePart, Humanoid) -> boolean, restorePose: boolean?): boolean
	if not self._active or not self:_releaseOutgoingMovement(owner) or self._movementLease ~= nil then return false end
	local root = self:_root()
	local character = root and root.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root == nil or root.Anchored or humanoid == nil or humanoid.Health <= 0 then return false end
	local lease = {
		owner = owner, root = root, humanoid = humanoid, cframe = root.CFrame,
		restorePose = restorePose ~= false,
		linear = root.AssemblyLinearVelocity, angular = root.AssemblyAngularVelocity,
		autoRotate = humanoid.AutoRotate, walkSpeed = humanoid.WalkSpeed,
	}
	self._movementLease = lease
	self._movementOwner = owner
	local completed, result = xpcall(function() return callback(root, humanoid) end, debug.traceback)
	self:_releaseMovementLease(lease)
	return completed and result == true
end

function Runtime:_keyMatches(key: Instance, kind: string): boolean
	return key:IsA("MeshPart")
		and key:GetAttribute("IsSpecialKey") == true
		and key:GetAttribute("Collected") == false
		and key:GetAttribute("IsDiscoKey") == false
		and key:GetAttribute("IsEventKey") == false
		and key:GetAttribute("IsSecretKey") == (kind == "Secret Key")
end

function Runtime:_runKeys(generation: number)
	while self._active and self._flags.autoKeys and self._workers.keys == generation do
		if #self._selectedKeyKinds == 0 then
			self._status.keys = "Select key types"
		else
			local specialKeys = child(self._world, "SpecialKeys")
			local consumed = false
			for _, key in ipairs(specialKeys and specialKeys:GetChildren() or {}) do
				for _, kind in ipairs(self._selectedKeyKinds) do
					if self:_keyMatches(key, kind) and self:_withMovementLease("keys", function(root, humanoid)
						if key.Parent ~= specialKeys or not self:_keyMatches(key, kind) or not self._active or self._workers.keys ~= generation then return false end
						humanoid.AutoRotate = false
						humanoid.WalkSpeed = 0
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
						root.CFrame = key.CFrame
						local elapsed, collected = 0, false
						while elapsed < KEY_CONTACT_TIMEOUT do
							if key:GetAttribute("Collected") == true then collected = true break end
							if key.Parent ~= specialKeys then break end
							if not self:_waitCurrent("keys", generation, 0.1) then return false end
							elapsed += 0.1
						end
						if collected then self._telemetry.keysCollected += 1 end
						return collected
					end) then
						consumed = true
						break
					end
				end
				if consumed then break end
			end
			if not self._active or self._workers.keys ~= generation then return end
			self._status.keys = if consumed then "Key collected" else "Waiting for selected keys"
		end
		if not self:_waitCurrent("keys", generation, WORKER_DELAY) then return end
	end
end
function Runtime:SetAutoKeys(enabled: any): (boolean, string?)
	if not self._active then return false end
	if enabled ~= true then
		self:_cancelAutomationTransition("keys")
		self._flags.autoKeys, self._status.keys = false, "Off"
		self:_stop("keys")
		return true
	end
	if self._flags.autoKeys then return true end
	return self:_withAutomationTransition("keys", "keys", function(transition)
		if #self._selectedKeyKinds == 0 then self._status.keys = "Select key types" return false end
		if self._flags.autoWins then self:_stopAutoWins() end
		if self._flags.autoAdminEvents and not self:_stopAutoAdminEvents() then return false end
		if self._flags.autoGloveBattle then self:SetAutoGloveBattle(false) end
		local released, reason = self:_awaitOutgoingMovement("keys")
		if not released then self._status.keys = reason or "Waiting for previous movement" return false, reason end
		if not self._active or transition.cancelled or #self._selectedKeyKinds == 0 then return false end
		self._flags.autoKeys, self._status.keys = true, "Starting"
		self:_start("keys", function(generation) self:_runKeys(generation) end)
		return true
	end)
end
function Runtime:SetFuseItems(labels: any): boolean
	if not self._active or type(labels) ~= "table" then return false end
	if self._fusePending ~= nil then return false end
	local allowed, accepted = {}, {}
	for _, label in ipairs(self:_fuseChoices()) do allowed[label] = true end
	for _, label in ipairs(labels) do
		if type(label) ~= "string" or not allowed[label] or table.find(accepted, label) then return false end
		table.insert(accepted, label)
	end
	self._selectedFuseItems = accepted
	return true
end

function Runtime:_stopAutoFuse(status: string)
	self._flags.autoFuse = false
	self:_stop("fuse")
	if self._fuseConnection then self._fuseConnection:Disconnect() self._fuseConnection = nil end
	self._fusePending = nil
	self._status.fuse = status
end

function Runtime:_reconcileFuseSelection(state: any?): { string }
	if self._fusePending ~= nil then return self:_fuseChoices(state) end
	local choices = self:_fuseChoices(state)
	local allowed = {}
	for _, label in ipairs(choices) do allowed[label] = true end
	local selected = {}
	for _, label in ipairs(self._selectedFuseItems) do
		if allowed[label] then table.insert(selected, label) end
	end
	if #selected ~= #self._selectedFuseItems then
		self._selectedFuseItems = selected
		if self._flags.autoFuse then self:_stopAutoFuse("Selected fuse item is stale") end
	end
	return choices
end

function Runtime:_runFuse(generation: number)
	while self._active and self._flags.autoFuse and self._workers.fuse == generation do
		local loaded, items = pcall(function() return self:_itemsFeatureConfig() end)
		if not self._active or self._workers.fuse ~= generation then return end
		local mergeCount = loaded and number(items.MERGE_COUNT) or 0
		if mergeCount ~= 5 then self:_stopAutoFuse("Unsupported fuse contract") return end
		local groups = fuseGroups(self:_state(), items)
		if not self._active or self._workers.fuse ~= generation then return end
		local target
		for _, label in ipairs(self._selectedFuseItems) do
			if groups[label] and groups[label].tier < number(items.MAX_TIER) and groups[label].count >= mergeCount then target = groups[label] break end
		end
		if target == nil then self:_stopAutoFuse("Selected fuse item is stale") return end
		local before = self:_state()
		if not self._active or self._workers.fuse ~= generation then return end
		local beforeGroups = fuseGroups(before, items)
		local beforeCount = type(before.Items) == "table" and #before.Items or 0
		local beforeRemainder = inventoryRemainder(before.Items, items, target.key, target.tier)
		if beforeRemainder == nil then self:_stopAutoFuse("Inventory state unavailable") return end
		local remote = self:_itemActionRemote()
		if not self._active or self._workers.fuse ~= generation then return end
		if remote == nil or remote.OnClientEvent == nil or type(remote.FireServer) ~= "function" then
			self:_stopAutoFuse("ItemAction unavailable")
			return
		end
		local pending = { key = target.key, tier = target.tier, success = false, update = false, error = false }
		self._fusePending = pending
		local connected, connection = pcall(function()
			return remote.OnClientEvent:Connect(function(action: any, payload: any)
				if self._fusePending ~= pending or pending.error then return end
				if action == "MergeSuccess" then
					if type(payload) == "table" and payload.Key == pending.key and payload.Tier == pending.tier + 1 then
						pending.success = true
					else
						pending.error = true
					end
				elseif action == "Update" then
					local updatedItems = type(payload) == "table" and payload.Items or nil
					if type(updatedItems) ~= "table" then pending.error = true return end
					local nowGroups = fuseGroups({ Items = updatedItems }, items)
					local sourceBefore = fuseGroupCount(beforeGroups, target.key, target.tier)
					local outputBefore = fuseGroupCount(beforeGroups, target.key, target.tier + 1)
					local sourceNow = fuseGroupCount(nowGroups, target.key, target.tier)
					local outputNow = fuseGroupCount(nowGroups, target.key, target.tier + 1)
					local nowRemainder = inventoryRemainder(updatedItems, items, target.key, target.tier)
					pending.update = sameCounts(beforeRemainder, nowRemainder)
						and sourceNow == sourceBefore - mergeCount
						and outputNow == outputBefore + 1
						and #updatedItems == beforeCount - (mergeCount - 1)
					if not pending.update then pending.error = true end
				elseif action == "Error" then
					pending.error = true
				end
			end)
		end)
		if not connected or connection == nil then self:_stopAutoFuse("ItemAction unavailable") return end
		self._fuseConnection = connection
		local sent = pcall(function() remote:FireServer("Merge", target.key, target.tier) end)
		if not sent then self:_stopAutoFuse("Fuse request failed") return end
		local elapsed = 0
		while elapsed < FUSE_TIMEOUT and self._active and self._workers.fuse == generation do
			if pending.error then break end
			if pending.success and pending.update then break end
			if not self:_waitCurrent("fuse", generation, 0.1) then return end
			elapsed += 0.1
		end
		if self._fuseConnection then self._fuseConnection:Disconnect() self._fuseConnection = nil end
		if pending.error then
			self:_stopAutoFuse("Fuse rejected")
			return
		elseif pending.success and pending.update then
			self._fusePending = nil
			self._telemetry.fusesCompleted += 1
			self._status.fuse = "Fuse confirmed"
			if not self._flags.autoFuse then self:_stopAutoFuse("Off") return end
		else
			self:_stopAutoFuse("Fuse unconfirmed")
			return
		end
		if not self:_waitCurrent("fuse", generation, WORKER_DELAY) then return end
	end
end

function Runtime:SetAutoFuse(enabled: any): (boolean, string?)
	if not self._active then return false end
	local nextEnabled = enabled == true
	if self._flags.autoFuse == nextEnabled then return true end
	if nextEnabled then
		if self._fusePending ~= nil then self._status.fuse = "Fuse request still pending" return false end
		self:_reconcileFuseSelection()
		if #self._selectedFuseItems == 0 then self._status.fuse = "Select fuse items" return false end
		if self._flags.autoBuyItems then self:SetAutoBuyItems(false) end
		if not self:_settleBuyItemsPending() then
			self._status.fuse = "Wait for item purchase inventory confirmation before trying Fuse again"
			return false, self._status.fuse
		end
		if self._flags.autoEquipItems or self._equipItemsPending ~= nil then self:SetAutoEquipItems(false) end
		if self._equipItemsPending ~= nil then
			self._status.fuse = "Waiting for Equip Best confirmation"
			return false
		end
		self._flags.autoFuse, self._status.fuse = true, "Starting"
		self:_start("fuse", function(generation) self:_runFuse(generation) end)
	elseif self._fusePending ~= nil then
		self._flags.autoFuse = false
		self._status.fuse = "Stopping after pending fuse"
	else
		self:_stopAutoFuse("Off")
	end
	return true
end
function Runtime:_slapBattle(): any
	if self._options.slapBattle then return self._options.slapBattle end
	local adminAbuse = self._storage:FindFirstChild("AdminAbuse")
	local modules = adminAbuse and adminAbuse:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("SlapBattle")
	if module == nil then return nil end
	local loaded, battle = pcall(require, module)
	return if loaded and type(battle) == "table" then battle else nil
end

function Runtime:_battleActive(battle: any): boolean
	if type(battle) ~= "table" or battle._activeSession == nil or battle._phase ~= "running" then return false end
	local endsAt = battle._combatEndsAt
	if type(endsAt) ~= "number" or endsAt ~= endsAt or math.abs(endsAt) == math.huge then return false end
	local now = if type(self._world.GetServerTimeNow) == "function" then self._world:GetServerTimeNow() else self._clock()
	return endsAt > now
end

function Runtime:_nearestGloveTarget(root: BasePart): (BasePart?, any?)
	local bestRoot, bestPlayer, bestDistance, alternateRoot, alternatePlayer, alternateDistance = nil, nil, math.huge, nil, nil, math.huge
	for _, player in ipairs(self._players:GetPlayers()) do
		if player ~= self._players.LocalPlayer then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and targetRoot and targetRoot:IsA("BasePart") then
				local distance = (targetRoot.Position - root.Position).Magnitude
				if player ~= self._gloveLastTarget and distance < alternateDistance then alternateRoot, alternatePlayer, alternateDistance = targetRoot, player, distance end
				if distance < bestDistance then bestRoot, bestPlayer, bestDistance = targetRoot, player, distance end
			end
		end
	end
	return alternateRoot or bestRoot, alternatePlayer or bestPlayer
end

function Runtime:_gloveStep(generation: number)
	local battle = self:_slapBattle()
	if not self._active or self._workers.glove ~= generation then return end
	if not self:_battleActive(battle) then self._status.glove = "Waiting for active battle" return end
	local root = self:_root()
	if root == nil then self._status.glove = "Character unavailable" return end
	local target, player = self:_nearestGloveTarget(root)
	if target == nil or player == nil then self._status.glove = "Waiting for opponent" return end
	-- Stay at the attack position; only equipment and humanoid controls are temporary.
	local worked = self:_withMovementLease("glove", function(localRoot, humanoid)
		if not self._active or self._workers.glove ~= generation or not self:_battleActive(battle) then return false end
		local character = localRoot.Parent
		local localPlayer = self._players.LocalPlayer
		local backpack = localPlayer and (localPlayer.Backpack or (type(localPlayer.FindFirstChildOfClass) == "function" and localPlayer:FindFirstChildOfClass("Backpack")))
		local tool = character and character:FindFirstChild("Battle Glove") or backpack and backpack:FindFirstChild("Battle Glove")
		if tool == nil or not tool:IsA("Tool") or tool.Enabled ~= true then self._status.glove = "Battle Glove unavailable" return false end
		local originalParent = tool.Parent
		local previousTool = nil
		for _, equipped in ipairs(character:GetChildren()) do
			if equipped:IsA("Tool") and equipped ~= tool then previousTool = equipped; break end
		end
		local completed, result = xpcall(function()
			if tool.Parent ~= character then
				humanoid:EquipTool(tool)
				if tool.Parent == backpack then tool.Parent = character end
			end
			if tool.Parent ~= character then self._status.glove = "Battle Glove unavailable" return false end
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 0
			local direction = Vector3.new(target.Position.X - localRoot.Position.X, 0, target.Position.Z - localRoot.Position.Z)
			if direction.Magnitude <= 0 then self._status.glove = "Opponent position unavailable" return false end
			local behind = target.Position - direction.Unit * 20
			local aim = Vector3.new(target.Position.X, behind.Y, target.Position.Z)
			localRoot.AssemblyLinearVelocity = Vector3.zero
			localRoot.AssemblyAngularVelocity = Vector3.zero
			localRoot.CFrame = CFrame.lookAt(behind, aim)
			local targetCharacter = player.Character
			local refreshed = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local center = localRoot.Position + localRoot.CFrame.LookVector * 20
			if refreshed == target and targetHumanoid and targetHumanoid.Health > 0 and (target.Position - center).Magnitude <= 28 and self:_battleActive(battle) then
				if type(self._options.activateTool) == "function" then self._options.activateTool(tool) else tool:Activate() end
				self._telemetry.gloveActivations += 1
				self._runService.Heartbeat:Wait()
				if not self._active or self._workers.glove ~= generation or not self:_battleActive(battle) then return false end
				self._gloveLastTarget = player
				self._status.glove = "Glove activated"
				return true
			end
			self._status.glove = "Target left hit range"
			return false
		end, debug.traceback)
		pcall(function()
			tool.Parent = originalParent
			if previousTool ~= nil and previousTool.Parent == backpack then
				humanoid:EquipTool(previousTool)
				if previousTool.Parent == backpack then previousTool.Parent = character end
			end
		end)
		if not completed then self._status.glove = "Glove activation failed" return false end
		return result == true
	end, false)
	if not worked and self._status.glove == "Starting" then self._status.glove = "Movement unavailable" end
end

function Runtime:_runGlove(generation: number)
	while self._active and self._flags.autoGloveBattle and self._workers.glove == generation do
		self:_gloveStep(generation)
		if not self:_waitCurrent("glove", generation, GLOVE_CADENCE) then return end
	end
end

function Runtime:SetAutoGloveBattle(enabled: any): (boolean, string?)
	if not self._active then return false end
	if enabled ~= true then
		self:_cancelAutomationTransition("glove")
		self._flags.autoGloveBattle, self._status.glove = false, "Off"
		self:_stop("glove")
		return true
	end
	if self._flags.autoGloveBattle then return true end
	return self:_withAutomationTransition("glove", "glove", function(transition)
		if self._flags.autoWins then self:_stopAutoWins() end
		if self._flags.autoAdminEvents and not self:_stopAutoAdminEvents() then return false end
		if self._flags.autoKeys then self:SetAutoKeys(false) end
		local released, reason = self:_awaitOutgoingMovement("glove")
		if not released then self._status.glove = reason or "Waiting for previous movement" return false, reason end
		if not self._active or transition.cancelled then return false end
		self._flags.autoGloveBattle, self._status.glove = true, "Starting"
		self:_start("glove", function(generation) self:_runGlove(generation) end)
		return true
	end)
end

function Runtime:Destroy()
	if not self._active then return end
	if self._eventCollector then
		if type(self._eventCollector.Stop) == "function" then pcall(function() self._eventCollector:Stop() end) end
		if type(self._eventCollector.Destroy) == "function" then pcall(function() self._eventCollector:Destroy() end) end
		self._flags.autoAdminEvents = false
	end
	if self._fuseConnection then self._fuseConnection:Disconnect() self._fuseConnection = nil end
	if self._equipItemsPending and self._equipItemsPending.connection then self._equipItemsPending.connection:Disconnect() end
	self._equipItemsPending = nil
	self._active = false
	if self._automationTransition then self._automationTransition.cancelled = true end
	if self._checkpointPending and self._checkpointPending.connection then self._checkpointPending.connection:Disconnect() end
	if self._checkpointPending and self._checkpointPending.poseConnection then self._checkpointPending.poseConnection:Disconnect() end
	self._checkpointPending = nil
	self._buyItemsPending = nil
	self._version += 1
	self:_releaseMovementLease(self._movementLease)
	if self._moveTween then pcall(function() self._moveTween:Cancel() end) self._moveTween = nil end
	self:_releaseMovementState(self._movementRestore)
	if self._godCharacterConnection then self._godCharacterConnection:Disconnect() self._godCharacterConnection = nil end
	self:_restoreObstacles()
	self:_restoreGodMode()
	local workers = {}
	for name in pairs(self._workers) do table.insert(workers, name) end
	for _, name in ipairs(workers) do self:_stop(name) end
	self:_disconnectShop()
	for _, connection in ipairs(self._connections) do connection:Disconnect() end
	table.clear(self._connections)
	self._movementOwner = nil
end
return Runtime
