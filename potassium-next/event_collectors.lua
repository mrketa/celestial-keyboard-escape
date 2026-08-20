--!strict
local CollectionService = game:GetService("CollectionService")

-- One serialized scheduler. Collection is touch-driven except for the source-verified Coin Battle acknowledgement.
local EventCollectors = {}
local KINDS = table.freeze({ "summer", "battle", "egg", "disco", "soccer", "rings", "masked", "overdrive" })
local RETRY =
	table.freeze({ summer = 2, battle = 2, egg = 2, disco = 2, soccer = 2, rings = 2, masked = 2, overdrive = 2 })
local MOVE_HORIZON, MOVE_STEP, CORRECTION_LIMIT, POLL = 30, 1 / 30, 12, 0.05
local BATTLE_REQUEST_INTERVAL = 0.13

local function routePoint(name: string, position: Vector3, options: { [string]: any }?): { [string]: any }
	local value = {
		name = name,
		position = position,
	}
	if options then
		for key, option in pairs(options) do
			value[key] = option
		end
	end
	return table.freeze(value)
end

local ROUTE = table.freeze({
	routePoint("Safe Start", Vector3.new(-1473.716797, -158.274429, -956.626160)),
	routePoint("Stage 1", Vector3.new(-1490.1263427734375, -68.3874282836914, -533.1188354492188)),
	routePoint("Stage 2", Vector3.new(-1476.367431640625, -56.145263671875, -36.770565032958984)),
	routePoint("Stage 3 Rise", Vector3.new(-1453.0216064453125, 258.1046447753906, 12.547174453735352)),
	routePoint("Stage 3 Gate", Vector3.new(-1454.333984375, 215.8647003173828, 328.38763427734375)),
	routePoint("Stage 4 Ladder", Vector3.new(-1453.474365234375, 215.8647003173828, 623.4430541992188)),
	routePoint("Stage 4 Top", Vector3.new(-1403.07275390625, 589.49755859375, 723.4365234375)),
	routePoint("Stage 5 Lower", Vector3.new(-1404.4468, 390.5382, 724.7380)),
	routePoint("Stage 5 Rise", Vector3.new(-1404.4468, 533.8660, 724.7380)),
	routePoint("Stage 5 Curve 1", Vector3.new(-1400.3630, 533.8660, 772.5512), { speed = 400 }),
	routePoint("Stage 5 Curve 2", Vector3.new(-1362.1042, 533.8660, 840.0916), { speed = 400 }),
	routePoint("Stage 5 Curve 3", Vector3.new(-1303.8162, 533.8660, 915.6722), { speed = 400 }),
	routePoint("Stage 5 Curve 4", Vector3.new(-1260.5690, 533.8660, 1030.5386), { speed = 400 }),
	routePoint("Stage 5 Curve 5", Vector3.new(-1280.7828, 533.8660, 1100.2794), { speed = 400 }),
	routePoint("Stage 5 Curve 6", Vector3.new(-1337.5544, 533.8660, 1205.0078), { speed = 400 }),
	routePoint("Stage 5 Curve 7", Vector3.new(-1397.1460, 533.8660, 1344.5568), { speed = 400 }),
	routePoint("Stage 6 Curve 1", Vector3.new(-1391.9022, 533.8642, 1365.9102)),
	routePoint("Stage 6 Curve 2", Vector3.new(-1397.8521, 533.8641, 1406.8398)),
	routePoint("Stage 6 Gate", Vector3.new(-1402.4264, 533.8641, 1427.2498)),
	routePoint(
		"Stage 6 Drop 1",
		Vector3.new(-1397.9819, 541.0258, 1448.9692),
		{ tsunamiGate = true, dwell = 0.02, speed = 300 }
	),
	routePoint("Stage 6 Drop 2", Vector3.new(-1433.3904, 502.0983, 1465.3796), { dwell = 0.02, speed = 300 }),
	routePoint("Stage 6 Floor", Vector3.new(-1475.4453, 443.2820, 1472.2993), { dwell = 0.02, speed = 300 }),
	routePoint(
		"Stage 6 Run 1",
		Vector3.new(-1582.7493, 443.8641, 1475.2930),
		{ hazardPosition = Vector3.new(-1582.7493, 520, 1475.2930), dwell = 0.02, speed = 300 }
	),
	routePoint(
		"Stage 6 Run 2",
		Vector3.new(-1708.5725, 443.8643, 1477.6670),
		{ hazardPosition = Vector3.new(-1708.5725, 520, 1477.6670), dwell = 0.02, speed = 300 }
	),
	routePoint(
		"Stage 6 Run 3",
		Vector3.new(-1834.3958, 443.8653, 1478.9807),
		{ hazardPosition = Vector3.new(-1834.3958, 520, 1478.9807), dwell = 0.02, speed = 300 }
	),
	routePoint(
		"Stage 6 Run 4",
		Vector3.new(-1951.4202, 446.4776, 1479.5720),
		{ hazardPosition = Vector3.new(-1951.4202, 520, 1479.5720), dwell = 0.02, speed = 300 }
	),
	routePoint("WinBlock37 safezone", Vector3.new(-2058.228516, 443.873718, 1484.287231), {
		dwell = 0.25,
		speed = 300,
	}),
	routePoint("Stage 7 Ramp 1", Vector3.new(-2130.1968, 443.0, 1486.1375)),
	routePoint("Stage 7 Ramp 2", Vector3.new(-2302.0222, 443.0, 1486.1375)),
	routePoint("Stage 7 Ramp 3", Vector3.new(-2441.5222, 443.0, 1486.1375)),
	routePoint("Stage 8 Floor", Vector3.new(-3059.9753, 675.6495, 1503.9557)),
	routePoint("Stage 9 Floor", Vector3.new(-4049.3909, 620.9781, 1483.2378)),
})

local function err(code: string, message: string)
	return { code = code, message = message }
end
local function part(x: Instance?): boolean
	return x ~= nil and x:IsA("BasePart")
end
local function cloneConfig(config: any)
	local out: { [string]: boolean } = {}
	for _, k in ipairs(KINDS) do
		out[k] = type(config) == "table" and config[k] == true or false
	end
	return out
end
local function cloneRetry(retry: any)
	local out: { [string]: number } = {}
	for _, k in ipairs(KINDS) do
		local n = type(retry) == "table" and retry[k] or RETRY[k]
		out[k] = type(n) == "number" and math.clamp(n, 0.5, 10) or RETRY[k]
	end
	return out
end
local function validConfig(config: any): boolean
	if type(config) ~= "table" then
		return false
	end
	for key, value in pairs(config) do
		if key == "summerOnlyStorm" then
			if type(value) ~= "boolean" then
				return false
			end
		elseif key == "retry" then
			if type(value) ~= "table" then
				return false
			end
			for retryKey, seconds in pairs(value) do
				if not table.find(KINDS, retryKey) or type(seconds) ~= "number" or seconds < 0.5 or seconds > 10 then
					return false
				end
			end
		elseif table.find(KINDS, key) then
			if type(value) ~= "boolean" then
				return false
			end
		else
			return false
		end
	end
	for _, kind in ipairs(KINDS) do
		if type(config[kind]) ~= "boolean" or type(config.retry) ~= "table" or type(config.retry[kind]) ~= "number" then
			return false
		end
	end
	return type(config.summerOnlyStorm) == "boolean"
end
local function enabled(h: any): boolean
	for _, k in ipairs(KINDS) do
		if h.enabled[k] then
			return true
		end
	end
	return false
end
local function root(h: any): BasePart?
	if type(h.options.getRoot) == "function" then
		local ok, value = pcall(h.options.getRoot)
		if ok and part(value) then
			return value
		end
	end
	local p = game:GetService("Players").LocalPlayer
	local x = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return part(x) and x or nil
end
local function numericWinsValue(value: any): boolean
	return typeof(value) == "Instance" and (value:IsA("NumberValue") or value:IsA("IntValue"))
end

local function wins(h: any): any
	if type(h.options.getWins) == "function" then
		local ok, value = pcall(h.options.getWins)
		if ok and numericWinsValue(value) then
			return value
		end
	end
	local player = game:GetService("Players").LocalPlayer
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Wins")
	if numericWinsValue(value) then
		return value
	end
	local data = player and player:FindFirstChild("Data")
	value = data and data:FindFirstChild("Wins")
	return numericWinsValue(value) and value or nil
end
local function halt(r: BasePart?)
	if r then
		pcall(function()
			local humanoid = r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.zero)
			end
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end)
	end
end
local function live(h: any): boolean
	return not h.stopped and h.alive() == true and enabled(h)
end
local function liveKind(h: any, kind: string?): boolean
	return live(h) and type(kind) == "string" and h.enabled[kind] == true
end
local function emit(h: any, kind: string, fields: any)
	pcall(h.emit, kind, fields)
end
local function key(kind: string, object: Instance): string
	local ok, address = pcall(function()
		return (object :: any).Address
	end)
	local identity = ok and address ~= nil and address or object
	return kind .. ":" .. tostring(identity)
end
local function disconnectEggHide(h: any)
	local connection = h.eggHideConnection
	h.eggHideConnection = nil
	if connection then
		pcall(connection.Disconnect, connection)
	end
end

local function connectEggHide(h: any): boolean
	if h.eggHideConnection then
		return true
	end
	local replicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = replicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("EggRainHide")
	if not remote or not remote:IsA("RemoteEvent") then
		return false
	end
	local connected, connection = pcall(function()
		return remote.OnClientEvent:Connect(function(payload)
			local eggId = type(payload) == "table" and payload.eggId or nil
			if type(eggId) == "number" and eggId == eggId and math.abs(eggId) < math.huge then
				h.hiddenEggs[eggId] = os.clock()
			end
		end)
	end)
	if not connected then
		return false
	end
	h.eggHideConnection = connection
	return true
end

local function safety(h: any, message: string, distance: number?)
	for _, k in ipairs(KINDS) do
		h.enabled[k] = false
	end
	h.stopped = true
	h.status = message
	h.safety = "stopped"
	h.lastError = "movement_safety"
	halt(root(h))
	emit(h, "events_safety_stop", { message = message })
	emit(h, "collector_safety_stopped", {
		distance = distance,
		collectorKind = h.travelKind or "unknown",
		code = "movement_safety",
		message = message,
	})
end
local function movementSpeed(h: any): number?
	local r = root(h)
	local humanoid = r and r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
	local speed = humanoid and humanoid.WalkSpeed
	if type(speed) ~= "number" or speed ~= speed or speed <= 0 or speed == math.huge then
		return nil
	end
	return math.clamp(speed, 1, 400)
end

local function withinMovementEnvelope(h: any, distance: number): boolean
	local speed = movementSpeed(h)
	return speed ~= nil and distance <= speed * MOVE_HORIZON
end
local function teleportDirect(
	h: any,
	kind: string,
	destination: Vector3,
	destinationName: string,
	traceTeleport: boolean?
): boolean
	local r = root(h)
	if not r or not liveKind(h, kind) then
		return false
	end
	local distance = (destination - r.Position).Magnitude
	halt(r)
	local rotation = r.CFrame.Rotation
	local teleported = pcall(function()
		r.CFrame = CFrame.new(destination) * rotation
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end)
	if not teleported or not liveKind(h, kind) then
		return false
	end
	if traceTeleport ~= false then
		emit(h, "event_teleport", {
			collectorKind = kind,
			destination = destinationName,
			distance = distance,
		})
	end
	return true
end

local COLLECTOR_SPAWN_FALLBACK = Vector3.new(-1455.074951, -157.889206, -999.510254)
local function collectorSpawnPosition(): Vector3
	local persistentSpawn = workspace:FindFirstChild("PersistentSpawn")
	local spawn = persistentSpawn and persistentSpawn:FindFirstChild("SpawnLocation", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn.Position + Vector3.new(0, 4.7, 0)
	end
	return COLLECTOR_SPAWN_FALLBACK
end

local function movePaced(h: any, kind: string, target: Vector3, moving: BasePart?): boolean
	local r = root(h)
	local speed = movementSpeed(h)
	local humanoid = r and r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
	if not r or not speed or not humanoid or not liveKind(h, kind) or (moving and not moving.Parent) then
		return false
	end
	if moving then
		target = moving.Position + h.offset
	end
	local initialDistance = (target - r.Position).Magnitude
	if not withinMovementEnvelope(h, initialDistance) then
		h.status = string.format("%s is outside the %.0fs movement envelope", kind, MOVE_HORIZON)
		return false
	end
	local deadline = os.clock() + math.min(initialDistance / speed + 2, MOVE_HORIZON + 2)
	local previousDistance = initialDistance
	local nextCommandAt = 0
	h.status = string.format("Moving to %s at %.0f studs/s", kind, speed)
	emit(h, "collector_movement", {
		collectorKind = kind,
		distance = initialDistance,
		speed = speed,
		horizon = MOVE_HORIZON,
	})
	while liveKind(h, kind) and os.clock() < deadline do
		r = root(h)
		if not r or (moving and not moving.Parent) then
			return false
		end
		if moving then
			target = moving.Position + h.offset
		end
		local targetDistance = (target - r.Position).Magnitude
		if targetDistance <= 4 then
			halt(r)
			return true
		end
		if targetDistance > previousDistance + CORRECTION_LIMIT then
			safety(h, "Movement correction detected; collectors stopped", initialDistance)
			return false
		end
		previousDistance = targetDistance
		local now = os.clock()
		if now >= nextCommandAt then
			nextCommandAt = now + 0.25
			humanoid:MoveTo(target)
		end
		task.wait(MOVE_STEP)
	end
	humanoid:Move(Vector3.zero)
	return false
end
local function tsunamiReady(): boolean
	local hazards = workspace:FindFirstChild("NPC & Piege")
	local model = hazards and hazards:FindFirstChild("Tsunami1")
	local wave = model and model:FindFirstChild("Tsunami")
	if not wave or not wave:IsA("BasePart") then
		return false
	end
	local spawn = model:FindFirstChild("TsunamiSpawn")
	local finish = model:FindFirstChild("TsunamiEnd")
	local travelTime = model:GetAttribute("TravelTime")
	if
		spawn
		and spawn:IsA("BasePart")
		and finish
		and finish:IsA("BasePart")
		and type(travelTime) == "number"
		and travelTime > 0
	then
		local travelDistance = (finish.Position - spawn.Position).Magnitude
		if travelDistance > 0 then
			local speed = travelDistance / travelTime
			local remaining = (finish.Position - wave.Position).Magnitude / speed
			return remaining >= 0.35 and remaining <= 0.60
		end
	end
	return wave.Position.X > -1925 and wave.Position.X < -1875
end

local function waitForTsunami(h: any): boolean
	local deadline = os.clock() + 8
	h.status = "Waiting for safe tsunami route"
	while liveKind(h, h.travelKind) and os.clock() < deadline do
		if tsunamiReady() then
			return true
		end
		task.wait(0.02)
	end
	return false
end

local function route(h: any, destination: Vector3): boolean
	local r = root(h)
	if not r then
		return false
	end
	local origin = r.Position
	local currentIndex, targetIndex = 1, 1
	local currentDistance, targetDistance = math.huge, math.huge
	for index, pointValue in ipairs(ROUTE) do
		local fromCurrent = (pointValue.position - origin).Magnitude
		local fromTarget = (pointValue.position - destination).Magnitude
		if fromCurrent < currentDistance then
			currentIndex, currentDistance = index, fromCurrent
		end
		if fromTarget < targetDistance then
			targetIndex, targetDistance = index, fromTarget
		end
	end
	local nextIndex
	if targetIndex > currentIndex then
		nextIndex = currentIndex + 1
	elseif targetIndex < currentIndex then
		nextIndex = currentIndex - 1
	elseif destination.X < origin.X and currentIndex < #ROUTE then
		nextIndex = currentIndex + 1
	elseif currentIndex > 1 then
		nextIndex = currentIndex - 1
	else
		return false
	end
	local pointValue = ROUTE[nextIndex]
	if not pointValue then
		return false
	end
	if pointValue.tsunamiGate and not waitForTsunami(h) then
		return false
	end
	local target = pointValue.hazardPosition or pointValue.position
	if not withinMovementEnvelope(h, (target - origin).Magnitude) then
		return false
	end
	h.status = "Traveling across map"
	h.current = pointValue.name
	if not movePaced(h, h.travelKind, target, nil) then
		return false
	end
	task.wait(pointValue.dwell or 0.2)
	return true
end
local function multiplier(model: Instance): number
	local r = model:FindFirstChild("Root")
	local b = r and r:FindFirstChild("BillboardGui")
	local t = b and b:FindFirstChild("Top")
	local l = t and t:FindFirstChild("TextLabel")
	local text = l and (l :: TextLabel).Text or ""
	text = string.upper(string.gsub(text, "%s+", " "))
	return text == "WINS" and 1 or tonumber(string.match(text, "^X(%d+) WINS$")) or 0
end
local function payout(s: string): number
	return tonumber(string.match(string.upper(string.gsub(s, "%s+", "")), "^([%d%.]+)[%a]*WINS$")) or 0
end
local function scanPad(c: Instance?): (TextLabel?, BasePart?)
	if not c then
		return nil, nil
	end
	for _, x in ipairs(c:GetDescendants()) do
		if x:IsA("TextLabel") and payout(x.Text) > 0 then
			local q: Instance? = x.Parent
			while q and q ~= c.Parent do
				if q:IsA("BasePart") then
					return x, q
				end
				q = q.Parent
			end
		end
	end
	return nil, nil
end
local function pad(a: Instance?, b: Instance?): (TextLabel?, BasePart?)
	local label, target = scanPad(a)
	if label and target then
		return label, target
	end
	return scanPad(b)
end
local function confirm(h: any, t: any): boolean
	if t.kind == "rings" or t.kind == "overdrive" or (t.kind == "masked" and t.id.type == "pad") then
		local v = wins(h)
		return v ~= nil and t.before ~= nil and v.Value ~= t.before
	end
	if t.kind == "egg" then
		return h.pendingEggId == t.id and h.hiddenEggs[t.id] ~= nil
	end
	if t.kind == "soccer" then
		if not t.model.Parent then
			return true
		end
		local ok, transparency = pcall(function()
			return t.part.Transparency
		end)
		return ok and type(transparency) == "number" and transparency >= 1
	end
	if t.kind == "disco" then
		if not t.model.Parent then
			return true
		end
		local ok, collected = pcall(t.model.GetAttribute, t.model, "Collected")
		return ok and collected == true
	end
	return not t.model.Parent
end
local function take(h: any, best: any, k: string, m: Instance, p: BasePart?, id: any): any
	if not p or not p.Parent or not m.Parent then
		return best
	end
	local rk = k == "masked" and id.key or k == "egg" and ("egg:" .. tostring(id)) or key(k, m)
	if (h.retryAt[rk] or 0) > os.clock() then
		return best
	end
	local r = root(h)
	if not r then
		return best
	end
	local d = (p.Position - r.Position).Magnitude
	return (not best or d < best.distance) and { kind = k, model = m, part = p, id = id, key = rk, distance = d }
		or best
end
local function summerTarget(h: any): (any, boolean)
	if not h.enabled.summer then
		return nil, false
	end
	local best: any = nil
	local now = os.clock()
	local folder = workspace:FindFirstChild("SummerCoinsLocal")
	local seen, scanned = 0, 0
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") and model.Name == "SummerCoin" then
				scanned += 1
				local coin = model:FindFirstChild("Coin", true)
				if part(coin) then
					seen += 1
					best = take(h, best, "summer", model, coin, {})
				end
				if scanned >= 64 then
					break
				end
			end
		end
	end
	if h.summerOnlyStorm then
		local player = game:GetService("Players").LocalPlayer
		local gui = player and player:FindFirstChild("PlayerGui")
		if gui and now >= h.stormScan then
			h.stormScan = now + 1
			for _, label in ipairs(gui:GetDescendants()) do
				if label:IsA("TextLabel") and label.Name == "CenterMessage" then
					local text = string.lower(label.Text)
					if string.find(text, "coin", 1, true) and string.find(text, "storm", 1, true) then
						local ended = string.find(text, "stop", 1, true)
							or string.find(text, "end", 1, true)
							or string.find(text, "over", 1, true)
							or string.find(text, "finish", 1, true)
						h.stormUntil = ended and 0 or now + 90
					end
				end
			end
		end
		if seen >= 10 then
			h.stormUntil = math.max(h.stormUntil, now + 5)
		end
		if now >= h.stormUntil then
			best = nil
		end
	end
	return best, seen > 0
end
local BATTLE_COLLECTIBLES = table.freeze({
	table.freeze({
		folder = "CoinBattleCoinsLocal",
		patterns = table.freeze({ "^CoinBattleCoin_(.+)$", "^Coin_(.+)$" }),
		remote = "CoinBattleCollect",
		label = "Coin Battle coin",
	}),
	table.freeze({
		folder = "CheeseBattleCoinsLocal",
		patterns = table.freeze({ "^CheeseBattleCoin_(.+)$" }),
		remote = "CheeseBattleCollect",
		label = "Cheese Battle cheese",
	}),
	table.freeze({
		folder = "MilkBattleCoinsLocal",
		patterns = table.freeze({ "^MilkBattleCoin_(.+)$" }),
		remote = "MilkBattleCollect",
		label = "Milk Battle milk",
	}),
})

local function battleTarget(h: any): (any, boolean)
	if not h.enabled.battle then
		return nil, false
	end
	local best: any = nil
	local present = false
	for _, descriptor in ipairs(BATTLE_COLLECTIBLES) do
		local folder = workspace:FindFirstChild(descriptor.folder)
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local rawId: string? = nil
					for _, pattern in ipairs(descriptor.patterns) do
						rawId = string.match(model.Name, pattern)
						if rawId then
							break
						end
					end
					if rawId then
						local collectible = model:FindFirstChild("CollectHitbox", true)
							or model:FindFirstChild("CoinPart", true)
							or model:FindFirstChild("Coin", true)
							or model.PrimaryPart
							or model:FindFirstChildWhichIsA("BasePart", true)
						if part(collectible) then
							present = true
							best = take(h, best, "battle", model, collectible, {
								coinId = rawId,
								remoteName = descriptor.remote,
								label = descriptor.label,
							})
						end
					end
				end
			end
		end
	end
	return best, present
end
local function visibleEggPart(object: Instance): BasePart?
	if object:IsA("BasePart") and object.Transparency < 1 then
		return object
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			return descendant
		end
	end
	return nil
end

local function eggTarget(h: any): (any, boolean)
	if not h.enabled.egg then
		return nil, false
	end
	local best: any = nil
	local present = false
	local scanned = 0
	local now = os.clock()
	for _, object in ipairs(CollectionService:GetTagged("EggRainEgg")) do
		scanned += 1
		local eggId = object:GetAttribute("EggId")
		local targetPart = visibleEggPart(object)
		if
			type(eggId) == "number"
			and eggId == eggId
			and math.abs(eggId) < math.huge
			and object.Parent
			and targetPart
		then
			local hiddenAt = h.hiddenEggs[eggId]
			if hiddenAt == nil or now - hiddenAt >= 1 then
				if hiddenAt ~= nil then
					h.hiddenEggs[eggId] = nil
				end
				present = true
				best = take(h, best, "egg", object, targetPart, eggId)
			end
		end
		if scanned >= 128 then
			break
		end
	end
	return best, present
end
local function overdriveTarget(h: any, initialBest: any): (any, boolean)
	if not h.enabled.overdrive then
		return initialBest, false
	end
	local best = initialBest
	local present = false
	for _, model in ipairs(workspace:GetChildren()) do
		if model.Name == "TixCollectibleOrb" and model:IsA("Model") then
			local orb = model.PrimaryPart or model:FindFirstChild("CollectibleOrb")
			if part(orb) then
				present = true
				best = take(h, best, "overdrive", model, orb, {})
			end
		end
	end
	return best, present
end

local function maskedTarget(h: any, initialBest: any): (any, boolean)
	if not h.enabled.masked then
		return initialBest, false
	end
	local best = initialBest
	local present = false
	local admin = workspace:FindFirstChild("AdminAbuse")
	local maps = admin and admin:FindFirstChild("Map")
	local liveMap = maps and maps:FindFirstChild("MaskedManColorMania_Live")
	h.maskedActive = liveMap ~= nil
	if not liveMap then
		return best, false
	end
	local presentation = workspace:FindFirstChild("AdminAbuseMaps")
	presentation = presentation and presentation:FindFirstChild("MaskedManColorMania")
	local debris = presentation and presentation:FindFirstChild("Debris")
	if debris then
		for _, orb in ipairs(debris:GetChildren()) do
			if (orb.Name == "CollectibleOrb" or orb.Name == "BigCollectibleOrb") and orb:IsA("BasePart") then
				present = true
				best = take(h, best, "masked", orb, orb, { type = "orb", key = key("masked", orb) })
			end
		end
	else
		for _, name in ipairs({ "CollectibleOrb", "BigCollectibleOrb" }) do
			local orb = workspace:FindFirstChild(name)
			if part(orb) then
				present = true
				best = take(h, best, "masked", orb, orb, { type = "orb", key = key("masked", orb) })
			end
		end
	end
	local now = os.clock()
	if now >= h.padScan then
		h.padScan = now + 2
		h.padLabel, h.padPart = pad(liveMap, presentation)
	end
	if h.padLabel and h.padLabel.Parent and h.padPart and h.padPart.Parent and payout(h.padLabel.Text) > 0 then
		present = true
		best = take(h, best, "masked", h.padPart, h.padPart, { type = "pad", key = key("masked", h.padPart) })
	else
		h.padLabel, h.padPart = nil, nil
	end
	return best, present
end

local function activeCruzVsSplinkMap(): Instance?
	local admin = workspace:FindFirstChild("AdminAbuse")
	local maps = admin and admin:FindFirstChild("Map")
	return maps and maps:FindFirstChild("CruzVsSplinkAdminAbuse_Live")
end

local function chaseZone(map: Instance): BasePart?
	local zone = map:FindFirstChild("ChaseZone", true)
	return part(zone) and zone or nil
end

local function chaserRoot(object: Instance): BasePart?
	if object:IsA("BasePart") then
		return object
	end
	local rootPart = object:FindFirstChild("HumanoidRootPart", true)
	return part(rootPart) and rootPart or nil
end

local function survivalAction(h: any): boolean
	local map = activeCruzVsSplinkMap()
	local zone = map and chaseZone(map)
	if not map or not zone then
		return false
	end
	local r = root(h)
	if not r then
		return true
	end
	if not h.home then
		h.home = r.Position
	end
	h.atHome = false
	h.travelKind = "battle"
	h.current = "Survival Chase"

	local chasers = {}
	for _, object in ipairs(CollectionService:GetTagged("AABossNpc")) do
		if object:IsDescendantOf(map) then
			local chaser = chaserRoot(object)
			if chaser then
				table.insert(chasers, chaser)
			end
		end
	end
	local bestPosition = zone.Position
	local bestClearance = -1
	for _, xScale in ipairs({ -0.35, 0, 0.35 }) do
		for _, zScale in ipairs({ -0.35, 0, 0.35 }) do
			local candidate = zone.CFrame:PointToWorldSpace(
				Vector3.new(zone.Size.X * xScale, -zone.Size.Y * 0.5 + 3, zone.Size.Z * zScale)
			)
			local clearance = math.huge
			for _, chaser in ipairs(chasers) do
				local delta = chaser.Position - candidate
				clearance = math.min(clearance, Vector3.new(delta.X, 0, delta.Z).Magnitude)
			end
			if clearance > bestClearance then
				bestPosition = candidate
				bestClearance = clearance
			end
		end
	end
	local localPosition = zone.CFrame:PointToObjectSpace(r.Position)
	local inside = math.abs(localPosition.X) <= zone.Size.X * 0.48
		and math.abs(localPosition.Y) <= zone.Size.Y * 0.48
		and math.abs(localPosition.Z) <= zone.Size.Z * 0.48
	local nearestThreat = math.huge
	for _, chaser in ipairs(chasers) do
		local delta = chaser.Position - r.Position
		nearestThreat = math.min(nearestThreat, Vector3.new(delta.X, 0, delta.Z).Magnitude)
	end
	if inside and nearestThreat >= 35 then
		halt(r)
		h.status = string.format("Surviving chase (nearest threat %.0f studs)", nearestThreat)
		return true
	end
	h.status = string.format("Evading chase (safe clearance %.0f studs)", bestClearance)
	teleportDirect(h, "battle", bestPosition, "survival_safe", false)
	return true
end

local function battleGlove(): Tool?
	local player = game:GetService("Players").LocalPlayer
	local character = player and player.Character
	local equipped = character and character:FindFirstChild("Battle Glove")
	if equipped and equipped:IsA("Tool") then
		return equipped
	end
	local backpack = player and player:FindFirstChildOfClass("Backpack")
	local stored = backpack and backpack:FindFirstChild("Battle Glove")
	return stored and stored:IsA("Tool") and stored or nil
end

local function slapAction(h: any): boolean
	local glove = battleGlove()
	if not glove then
		return false
	end
	local player = game:GetService("Players").LocalPlayer
	local r = root(h)
	local humanoid = r and r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
	if not player or not r or not humanoid then
		return true
	end
	if glove.Parent ~= r.Parent then
		humanoid:EquipTool(glove)
	end
	local targetRoot: BasePart? = nil
	local targetDistance = math.huge
	for _, candidate in ipairs(game:GetService("Players"):GetPlayers()) do
		local character = candidate.Character
		local candidateHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		local candidateRoot = character and character:FindFirstChild("HumanoidRootPart")
		if candidate ~= player and candidateHumanoid and candidateHumanoid.Health > 0 and part(candidateRoot) then
			local distance = (candidateRoot.Position - r.Position).Magnitude
			if distance < targetDistance then
				targetRoot = candidateRoot
				targetDistance = distance
			end
		end
	end
	if not targetRoot then
		h.status = "Waiting for Glove Battle target"
		return true
	end
	if not h.home then
		h.home = r.Position
	end
	h.atHome = false
	h.travelKind = "battle"
	h.current = "Glove Battle"
	local away = r.Position - targetRoot.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.01 then
		local look = targetRoot.CFrame.LookVector
		away = Vector3.new(-look.X, 0, -look.Z)
	end
	local destination = targetRoot.Position + away.Unit * 18
	if targetDistance > 28 then
		teleportDirect(h, "battle", destination, "slap_target", false)
		r = root(h)
	end
	if r then
		r.CFrame = CFrame.lookAt(r.Position, targetRoot.Position)
	end
	local now = os.clock()
	if now >= h.nextSlapAt then
		h.nextSlapAt = now + 1.05
		glove:Activate()
		h.status = "Attacking Glove Battle target"
	else
		h.status = "Waiting for Glove Battle cooldown"
	end
	return true
end

local function battleAction(h: any): boolean
	if not h.enabled.battle then
		return false
	end
	return survivalAction(h) or slapAction(h)
end
local function target(h: any): any
	local w = workspace
	local best = select(1, summerTarget(h))
	local now = os.clock()
	local battleBest = select(1, battleTarget(h))
	if battleBest then
		return battleBest
	end
	local eggBest = select(1, eggTarget(h))
	if eggBest then
		return eggBest
	end
	if h.enabled.disco then
		local f = w:FindFirstChild("SpecialKeys")
		if f then
			for _, m in ipairs(f:GetChildren()) do
				if m:GetAttribute("IsDiscoKey") == true then
					best = take(
						h,
						best,
						"disco",
						m,
						m:IsA("BasePart") and m or m:FindFirstChildWhichIsA("BasePart", true),
						{}
					)
				end
			end
		end
	end
	if h.enabled.soccer then
		for _, m in ipairs(w:GetChildren()) do
			if m.Name == "SoccerBall" and m:IsA("BasePart") then
				best = take(h, best, "soccer", m, m, {})
			end
		end
	end
	best = select(1, overdriveTarget(h, best))
	if h.enabled.rings then
		local bestRing: any = nil
		local currentRoot = root(h)
		for _, m in ipairs(w:GetChildren()) do
			if m.Name == "WinRing" and m:IsA("Model") then
				local p = m:FindFirstChild("Root") or m:FindFirstChild("Cylinder")
				local n = multiplier(m)
				local retryKey = key("rings", m)
				local retryAt = h.retryAt[retryKey] or 0
				if n > 0 and part(p) and retryAt <= now and currentRoot then
					local distance = (p.Position - currentRoot.Position).Magnitude
					if
						not bestRing
						or n > bestRing.id.multiplier
						or (n == bestRing.id.multiplier and distance < bestRing.distance)
					then
						local c = m:FindFirstChild("Cylinder")
						bestRing = {
							kind = "rings",
							model = m,
							part = p,
							distance = distance,
							id = {
								type = "ring",
								key = retryKey,
								multiplier = n,
								radius = part(c) and math.max(c.Size.X, c.Size.Z) / 2 or 10,
							},
						}
					end
				end
			end
		end
		if bestRing then
			best = take(h, best, bestRing.kind, bestRing.model, bestRing.part, bestRing.id)
		end
	end
	local admin = w:FindFirstChild("AdminAbuse")
	local maps = admin and admin:FindFirstChild("Map")
	h.variant = maps and maps:FindFirstChild("SummerBossAA_August15th_Live") and "August15th"
		or maps and maps:FindFirstChild("SummerBossAA_Live") and "Legacy"
		or nil
	best = select(1, maskedTarget(h, best))
	return best
end
local function requestBattleCollect(t: any)
	if t.kind ~= "battle" or type(t.id) ~= "table" then
		return
	end
	pcall(function()
		local replicatedStorage = game:GetService("ReplicatedStorage")
		local admin = replicatedStorage:FindFirstChild("AdminAbuse")
		local remotes = admin and admin:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild(t.id.remoteName)
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(t.id.coinId)
		end
	end)
end

local function collect(h: any, t: any)
	local r = root(h)
	if not r or not t.part.Parent or not liveKind(h, t.kind) then
		return
	end
	if not h.home then
		h.home = r.Position
	end
	h.current = t.kind == "rings" and ("Summer Boss x" .. tostring(t.id.multiplier) .. " Win Ring")
		or t.kind == "battle" and t.id.label
		or t.kind
	h.atHome = false
	h.travelKind = t.kind
	if h.lastTargetKey ~= t.key then
		h.lastTargetKey = t.key
		emit(h, "collector_target", {
			collectorKind = t.kind,
			variant = h.variant,
		})
	end
	h.offset = (t.kind == "battle" or t.kind == "egg" or t.kind == "overdrive") and Vector3.zero
		or t.kind == "masked" and Vector3.new(0, 1.5, 0)
		or Vector3.new(0, 3, 0)
	local destination = t.part.Position + h.offset
	local travelDistance = (destination - r.Position).Magnitude
	local directTeleportKind = t.kind == "summer"
		or t.kind == "battle"
		or t.kind == "egg"
		or t.kind == "overdrive"
		or t.kind == "masked"
	if not directTeleportKind and not withinMovementEnvelope(h, travelDistance) then
		h.status = string.format("Routing to distant %s (%.0f studs)", h.current, travelDistance)
		route(h, destination)
		return
	end
	h.status = t.kind == "summer" and "Teleporting to Summer Coin"
		or t.kind == "battle" and ("Teleporting onto " .. t.id.label)
		or t.kind == "egg" and "Teleporting to Egg Rain egg"
		or t.kind == "overdrive" and "Teleporting to Overdrive orb"
		or t.kind == "masked" and ("Teleporting to Masked " .. t.id.type)
		or "Collecting " .. h.current
	if t.kind == "rings" or t.kind == "overdrive" or (t.kind == "masked" and t.id.type == "pad") then
		local value = wins(h)
		t.before = value and value.Value
	end
	local function finishConfirmed()
		if t.kind == "egg" then
			h.pendingEggId = nil
		end
		h.counts[t.kind] += 1
		h.counts.total += 1
		h.retryAt[t.key] = nil
		local result = t.kind == "masked" and t.id and t.id.type == "orb" and "touched" or "confirmed"
		h.status = h.current .. " " .. result
		if t.kind == "rings" or t.kind == "overdrive" then
			halt(root(h))
		end
		emit(h, "collector_result", {
			collectorKind = t.kind,
			variant = h.variant,
			result = result,
			count = h.counts[t.kind],
			total = h.counts.total,
		})
		h.lastTargetKey = nil
	end
	local moved = false
	if directTeleportKind then
		if t.kind == "egg" then
			h.pendingEggId = t.id
		end
		local destinationName = (t.kind == "summer" or t.kind == "battle") and "coin"
			or t.kind == "egg" and "egg"
			or t.kind == "overdrive" and "orb"
			or t.id.type
		moved = teleportDirect(h, t.kind, destination, destinationName)
		if moved then
			if t.kind == "summer" then
				h.summerReturnPending = true
			elseif t.kind == "battle" then
				h.battleReturnPending = false
			elseif t.kind == "egg" then
				h.eggReturnPending = true
			elseif t.kind == "overdrive" then
				h.overdriveReturnPending = true
			else
				h.maskedReturnPending = true
			end
		elseif t.kind == "egg" then
			h.pendingEggId = nil
		end
	elseif t.kind == "rings" then
		local delta = t.part.Position - r.Position
		moved = Vector3.new(delta.X, 0, delta.Z).Magnitude <= math.max(t.id.radius * 0.8, 4)
	end
	if not moved and not directTeleportKind then
		moved = movePaced(h, t.kind, destination, t.part)
	end
	if not moved then
		return
	end
	if t.kind == "battle" then
		-- Retry at the server's 0.12s collection cooldown until position replication catches up.
		task.wait(POLL)
	end
	requestBattleCollect(t)
	local nextBattleRequestAt = os.clock() + BATTLE_REQUEST_INTERVAL
	local deadline = os.clock()
		+ (
			t.kind == "rings" and 12
			or t.kind == "overdrive" and math.min(math.max(t.distance / 12 + 4, 8), 55)
			or t.kind == "soccer" and 3
			or t.kind == "egg" and 2
			or t.kind == "battle" and 4
			or 1
		)
	local nextMoveAt = 0
	while liveKind(h, t.kind) and os.clock() < deadline do
		if confirm(h, t) then
			finishConfirmed()
			return
		end
		r = root(h)
		local currentTime = os.clock()
		if t.kind == "battle" and t.model.Parent and currentTime >= nextBattleRequestAt then
			nextBattleRequestAt = currentTime + BATTLE_REQUEST_INTERVAL
			requestBattleCollect(t)
		end
		if r and t.part.Parent and currentTime >= nextMoveAt then
			nextMoveAt = currentTime + 0.2
			if t.kind == "rings" then
				local delta = t.part.Position - r.Position
				local horizontal = Vector3.new(delta.X, 0, delta.Z)
				local desiredX, desiredZ = 0, 0
				if horizontal.Magnitude > math.max(t.id.radius * 0.45, 4) then
					local speed = math.min(math.max(horizontal.Magnitude * 2, 20), movementSpeed(h) or 16)
					desiredX = horizontal.Unit.X * speed
					desiredZ = horizontal.Unit.Z * speed
				end
				local velocity = r.AssemblyLinearVelocity
				local velocityDelta = Vector3.new(velocity.X - desiredX, 0, velocity.Z - desiredZ).Magnitude
				if velocityDelta > 5 then
					r.AssemblyLinearVelocity = Vector3.new(desiredX, velocity.Y, desiredZ)
				end
			elseif t.kind == "overdrive" then
				local followDestination = t.part.Position + h.offset
				if (followDestination - r.Position).Magnitude > 3 then
					teleportDirect(h, "overdrive", followDestination, "orb_follow", false)
				end
			end
		end
		task.wait(POLL)
	end
	if liveKind(h, t.kind) and confirm(h, t) then
		finishConfirmed()
		return
	end
	if t.kind == "egg" then
		h.pendingEggId = nil
	end
	halt(root(h))
	if t.kind == "overdrive" and not t.model.Parent then
		h.status = "Overdrive Tix reward not confirmed"
	elseif t.kind == "egg" and not t.model.Parent then
		h.status = "Egg Rain egg despawned without confirmation"
	elseif t.model.Parent and liveKind(h, t.kind) then
		h.retryAt[t.key] = os.clock() + h.retry[t.kind]
		h.status = h.current .. " not confirmed"
	end
	if liveKind(h, t.kind) then
		emit(h, "collector_result", {
			collectorKind = t.kind,
			variant = h.variant,
			result = "not_confirmed",
			count = h.counts[t.kind],
			total = h.counts.total,
		})
		h.lastTargetKey = nil
	end
end
local function returnDirectCollectorToSpawn(h: any, kind: string, pendingField: string)
	h.offset = Vector3.zero
	h.status = "Returning to spawn"
	if teleportDirect(h, kind, collectorSpawnPosition(), "spawn") then
		h[pendingField] = false
		h.atHome = true
		h.current = "-"
	end
end

local function returnHome(h: any)
	if h.atHome or not h.home then
		return
	end
	local r = root(h)
	if not r then
		return
	end
	h.offset = Vector3.zero
	h.status = "Returning to World 3 route"
	local distance = (h.home - r.Position).Magnitude
	if not withinMovementEnvelope(h, distance) then
		route(h, h.home)
		return
	end
	if movePaced(h, h.travelKind or "summer", h.home, nil) then
		h.atHome = true
		h.current = "-"
	end
end

function EventCollectors.create(options: any)
	options = type(options) == "table" and options or {}
	local policy = {}

	function policy.newSession(config: any, epoch: any, emitCallback: any, aliveCallback: any)
		if
			type(epoch) ~= "number"
			or epoch < 0
			or epoch % 1 ~= 0
			or type(emitCallback) ~= "function"
			or type(aliveCallback) ~= "function"
			or not validConfig(config)
		then
			return nil, err("events_session_invalid", "event session dependencies or configuration are invalid")
		end
		return {
			owner = "events",
			epoch = epoch,
			options = options,
			emit = emitCallback,
			alive = aliveCallback,
			enabled = cloneConfig(config),
			retry = cloneRetry(config.retry),
			summerOnlyStorm = config.summerOnlyStorm,
			counts = {
				summer = 0,
				battle = 0,
				egg = 0,
				disco = 0,
				soccer = 0,
				rings = 0,
				masked = 0,
				overdrive = 0,
				total = 0,
			},
			retryAt = {},
			lastTargetKey = nil,
			status = "Ready",
			current = "-",
			atHome = true,
			summerReturnPending = false,
			battleReturnPending = false,
			eggReturnPending = false,
			overdriveReturnPending = false,
			maskedReturnPending = false,
			hiddenEggs = {},
			pendingEggId = nil,
			eggHideConnection = nil,
			safety = "clear",
			stopped = false,
			running = false,
			stormUntil = 0,
			stormScan = 0,
			maskedScan = 0,
			padScan = 0,
			padLabel = nil,
			padPart = nil,
			maskedActive = false,
			variant = nil,
			lastError = nil,
			nextSlapAt = 0,
		},
			nil
	end

	function policy.configure(h: any, config: any)
		if type(h) ~= "table" or h.owner ~= "events" or not validConfig(config) then
			return nil, err("events_config_invalid", "event configuration is invalid")
		end
		h.enabled = cloneConfig(config)
		h.retry = cloneRetry(config.retry)
		h.summerOnlyStorm = config.summerOnlyStorm
		if not h.enabled.summer then
			h.summerReturnPending = false
		end
		if not h.enabled.battle then
			h.battleReturnPending = false
		end
		if not h.enabled.egg then
			h.eggReturnPending = false
			h.pendingEggId = nil
		end
		if not h.enabled.overdrive then
			h.overdriveReturnPending = false
		end
		if not h.enabled.masked then
			h.maskedReturnPending = false
		end
		return true
	end

	function policy.run(h: any)
		if type(h) ~= "table" or h.owner ~= "events" or h.running then
			return nil, err("events_handle_invalid", "event handle is invalid")
		end
		h.running = true
		while live(h) do
			if h.enabled.egg and not connectEggHide(h) then
				h.status = "Egg Rain confirmation remote unavailable"
				task.wait(0.25)
				continue
			end
			local selected: any = nil
			local handled = false
			if h.summerReturnPending then
				local summerPresent
				selected, summerPresent = summerTarget(h)
				if not selected then
					handled = true
					if summerPresent then
						h.status = h.summerOnlyStorm and "Waiting for Coin Storm" or "Waiting to retry Summer Coin"
					else
						returnDirectCollectorToSpawn(h, "summer", "summerReturnPending")
					end
				end
			elseif h.battleReturnPending then
				local battlePresent
				selected, battlePresent = battleTarget(h)
				if not selected then
					handled = true
					if battlePresent then
						h.status = "Waiting to retry Coin Battle coin"
					else
						returnDirectCollectorToSpawn(h, "battle", "battleReturnPending")
					end
				end
			elseif h.eggReturnPending then
				local eggPresent
				selected, eggPresent = eggTarget(h)
				if not selected then
					handled = true
					if eggPresent then
						h.status = "Waiting to retry Egg Rain egg"
					else
						returnDirectCollectorToSpawn(h, "egg", "eggReturnPending")
					end
				end
			elseif h.overdriveReturnPending then
				local overdrivePresent
				selected, overdrivePresent = overdriveTarget(h, nil)
				if not selected then
					handled = true
					if overdrivePresent then
						h.status = "Waiting to retry Overdrive orb"
					else
						returnDirectCollectorToSpawn(h, "overdrive", "overdriveReturnPending")
					end
				end
			elseif h.maskedReturnPending then
				local maskedPresent
				selected, maskedPresent = maskedTarget(h, nil)
				if not selected then
					handled = true
					if maskedPresent then
						h.status = "Waiting to retry Masked target"
					else
						returnDirectCollectorToSpawn(h, "masked", "maskedReturnPending")
					end
				end
			end
			if not handled and not selected then
				selected = target(h)
			end
			if not handled and not selected and battleAction(h) then
				handled = true
			end
			if selected then
				h.travelKind = selected.kind
				collect(h, selected)
			elseif not handled and not h.atHome then
				returnHome(h)
			elseif not handled then
				h.status = h.enabled.summer
						and h.summerOnlyStorm
						and os.clock() >= h.stormUntil
						and "Waiting for Coin Storm"
					or h.enabled.egg and "Waiting for Egg Rain wave"
					or h.enabled.rings and "Waiting for Summer Boss Win Rings"
					or h.enabled.masked and not h.maskedActive and "Waiting for Masked Man event"
					or h.enabled.overdrive and "Waiting for Overdrive Tix orbs"
					or "Waiting for event targets"
			end
			if live(h) then
				task.wait(0.25)
			end
		end
		disconnectEggHide(h)
		h.running = false
		halt(root(h))
		return policy.snapshot(h)
	end

	function policy.stop(h: any)
		if h == nil then
			return true
		end
		if type(h) ~= "table" or h.owner ~= "events" then
			return nil, err("events_handle_invalid", "event handle is invalid")
		end
		h.stopped = true
		h.running = false
		h.status = "Stopped"
		h.eggReturnPending = false
		h.overdriveReturnPending = false
		h.maskedReturnPending = false
		h.pendingEggId = nil
		disconnectEggHide(h)
		halt(root(h))
		return true
	end

	function policy.snapshot(h: any)
		if type(h) ~= "table" or h.owner ~= "events" then
			return nil
		end
		local counts = {
			summer = h.counts.summer,
			battle = h.counts.battle,
			egg = h.counts.egg,
			disco = h.counts.disco,
			soccer = h.counts.soccer,
			rings = h.counts.rings,
			masked = h.counts.masked,
			overdrive = h.counts.overdrive,
			total = h.counts.total,
		}
		local speed = movementSpeed(h) or 0
		return {
			owner = "events",
			enabled = cloneConfig(h.enabled),
			counts = counts,
			total = counts.total,
			status = h.status,
			current = h.current,
			variant = h.variant,
			summerVariant = h.variant,
			safety = h.safety,
			atHome = h.atHome,
			lastError = h.lastError,
			movement = {
				speed = speed,
				horizon = MOVE_HORIZON,
				maxStraightDistance = speed * MOVE_HORIZON,
			},
		}
	end

	return table.freeze(policy)
end
return table.freeze(EventCollectors)
