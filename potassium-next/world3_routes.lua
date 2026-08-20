--!strict

local function point(name: string, x: number, y: number, z: number, options: { [string]: any }?): { [string]: any }
	local value = { name = name, position = Vector3.new(x, y, z) }
	if options ~= nil then
		for key, option in pairs(options) do
			value[key] = option
		end
	end
	return table.freeze(value)
end

local function extendRoute(route: { any }, extension: { any }): { any }
	local combined = table.create(#route + #extension)
	for index, value in ipairs(route) do
		combined[index] = value
	end
	for index, value in ipairs(extension) do
		combined[#route + index] = value
	end
	return table.freeze(combined)
end

local stage2 = table.freeze({
	key = "stage2",
	label = "Stage 2",
	speed = 300,
	minimumCycleTime = 5,
	raceMinimumTime = 5,
	cooldownAligned = true,
	plate = Vector3.new(-1480.758911, -57.906536, -15.813429),
	blockPath = table.freeze({ "Structure", "Stage2", "SAS", "WinBlock33" }),
	route = table.freeze({
		point("Stage 1", -1490.1263427734375, -68.3874282836914, -533.1188354492188, { raceStart = true }),
		point("Stage 2", -1476.367431640625, -56.145263671875, -36.770565032958984),
	}),
})

local stage3 = table.freeze({
	key = "stage3",
	label = "Stage 3",
	speed = 300,
	minimumCycleTime = 8,
	raceMinimumTime = 8,
	plate = Vector3.new(-1480.769409, 214.103485, 332.140778),
	blockPath = table.freeze({ "Structure", "Stage3", "SAS", "WinBlock34" }),
	directPlate = true,
	route = table.freeze({
		point("Stage 1", -1490.1263427734375, -68.3874282836914, -533.1188354492188, { raceStart = true }),
		point("Stage 2", -1476.367431640625, -56.145263671875, -36.770565032958984),
		point("Stage 3 Rise", -1453.0216064453125, 280, 12.547174453735352),
	}),
})

local stage4 = table.freeze({
	key = "stage4",
	label = "Stage 4",
	speed = 300,
	minimumCycleTime = 12.5,
	raceMinimumTime = 12.5,
	plate = Vector3.new(-1431.3326, 536.1462, 759.6248),
	blockPath = table.freeze({ "Structure", "Stage4", "SAS", "WinBlock35" }),
	directPlate = true,
	route = table.freeze({
		point("Stage 1", -1490.1263427734375, -68.3874282836914, -533.1188354492188, { raceStart = true }),
		point("Stage 2", -1476.367431640625, -56.145263671875, -36.770565032958984),
		point("Stage 3 Rise", -1453.0216064453125, 280, 12.547174453735352),
		point("Stage 3 Gate", -1454.333984375, 215.8647003173828, 328.38763427734375),
		point("Stage 4 Ladder", -1453.474365234375, 215.8647003173828, 623.4430541992188),
		point("Stage 4 Top", -1403.07275390625, 589.49755859375, 723.4365234375),
		point("Win staging", -1403.2591552734375, 533.8761596679688, 768.9608764648438),
	}),
})

local stage5 = table.freeze({
	key = "stage5",
	label = "Stage 5",
	speed = 300,
	minimumCycleTime = 15.5,
	raceMinimumTime = 15.5,
	plate = Vector3.new(-1431.4525, 533.6140, 1329.8270),
	blockPath = table.freeze({ "Structure", "Stage5", "SAS", "WinBlock36" }),
	route = table.freeze({
		point("Stage 1", -1490.1263427734375, -68.3874282836914, -533.1188354492188, { raceStart = true }),
		point("Stage 2", -1476.367431640625, -56.145263671875, -36.770565032958984),
		point("Stage 3 Rise", -1453.0216064453125, 258.1046447753906, 12.547174453735352),
		point("Stage 3 Gate", -1454.333984375, 215.8647003173828, 328.38763427734375),
		point("Stage 4 Ladder", -1453.474365234375, 215.8647003173828, 623.4430541992188),
		point("Stage 4 Top", -1403.07275390625, 589.49755859375, 723.4365234375),
		point("Stage 5 Lower", -1404.4468, 390.5382, 724.7380),
		point("Stage 5 Rise", -1404.4468, 533.8660, 724.7380),
		point("Stage 5 Curve 1", -1400.3630, 533.8660, 772.5512, { speed = 400 }),
		point("Stage 5 Curve 2", -1362.1042, 533.8660, 840.0916, { speed = 400 }),
		point("Stage 5 Curve 3", -1303.8162, 533.8660, 915.6722, { speed = 400 }),
		point("Stage 5 Curve 4", -1260.5690, 533.8660, 1030.5386, { speed = 400 }),
		point("Stage 5 Curve 5", -1280.7828, 533.8660, 1100.2794, { speed = 400 }),
		point("Stage 5 Curve 6", -1337.5544, 533.8660, 1205.0078, { speed = 400 }),
		point("Stage 5 Curve 7", -1397.1460, 533.8660, 1344.5568, { speed = 400 }),
		point("WinBlock36 staging", -1422.8318, 533.8660, 1335.9071),
	}),
})

local stage6 = table.freeze({
	key = "stage6",
	label = "Stage 6",
	speed = 300,
	minimumCycleTime = 18.5,
	raceMinimumTime = 18.5,
	plate = Vector3.new(-2062.3730, 443.6126, 1459.3718),
	blockPath = table.freeze({ "Structure", "Stage6", "SAS", "WinBlock37" }),
	tsunami = table.freeze({
		before = "Stage 6 Drop 1",
		timeout = 8,
		poll = 0.02,
		remainingMin = 0.35,
		remainingMax = 0.60,
		xMin = -1925,
		xMax = -1875,
	}),
	route = table.freeze({
		point("Stage 1", -1490.1263427734375, -68.3874282836914, -533.1188354492188, { raceStart = true }),
		point("Stage 2", -1476.367431640625, -56.145263671875, -36.770565032958984),
		point("Stage 3 Rise", -1453.0216064453125, 258.1046447753906, 12.547174453735352),
		point("Stage 3 Gate", -1454.333984375, 215.8647003173828, 328.38763427734375),
		point("Stage 4 Ladder", -1453.474365234375, 215.8647003173828, 623.4430541992188),
		point("Stage 4 Top", -1403.07275390625, 589.49755859375, 723.4365234375),
		point("Stage 5 Lower", -1404.4468, 390.5382, 724.7380),
		point("Stage 5 Rise", -1404.4468, 533.8660, 724.7380),
		point("Stage 5 Curve 1", -1400.3630, 533.8660, 772.5512, { speed = 400 }),
		point("Stage 5 Curve 2", -1362.1042, 533.8660, 840.0916, { speed = 400 }),
		point("Stage 5 Curve 3", -1303.8162, 533.8660, 915.6722, { speed = 400 }),
		point("Stage 5 Curve 4", -1260.5690, 533.8660, 1030.5386, { speed = 400 }),
		point("Stage 5 Curve 5", -1280.7828, 533.8660, 1100.2794, { speed = 400 }),
		point("Stage 5 Curve 6", -1337.5544, 533.8660, 1205.0078, { speed = 400 }),
		point("Stage 5 Curve 7", -1397.1460, 533.8660, 1344.5568, { speed = 400 }),
		point("Stage 6 Curve 1", -1391.9022, 533.8642, 1365.9102),
		point("Stage 6 Curve 2", -1397.8521, 533.8641, 1406.8398),
		point("Stage 6 Gate", -1402.4264, 533.8641, 1427.2498, { minimumRaceElapsed = 14.25 }),
		point("Stage 6 Drop 1", -1397.9819, 541.0258, 1448.9692, { tsunamiGate = true, dwell = 0.02, speed = 300 }),
		point("Stage 6 Drop 2", -1433.3904, 502.0983, 1465.3796, { dwell = 0.02, speed = 300 }),
		point("Stage 6 Floor", -1475.4453, 443.2820, 1472.2993, { dwell = 0.02, speed = 300 }),
		point(
			"Stage 6 Run 1",
			-1582.7493,
			443.8641,
			1475.2930,
			{ hazardPosition = Vector3.new(-1582.7493, 520, 1475.2930), dwell = 0.02, speed = 300 }
		),
		point(
			"Stage 6 Run 2",
			-1708.5725,
			443.8643,
			1477.6670,
			{ hazardPosition = Vector3.new(-1708.5725, 520, 1477.6670), dwell = 0.02, speed = 300 }
		),
		point(
			"Stage 6 Run 3",
			-1834.3958,
			443.8653,
			1478.9807,
			{ hazardPosition = Vector3.new(-1834.3958, 520, 1478.9807), dwell = 0.02, speed = 300 }
		),
		point(
			"Stage 6 Run 4",
			-1951.4202,
			446.4776,
			1479.5720,
			{ hazardPosition = Vector3.new(-1951.4202, 520, 1479.5720), dwell = 0.02, speed = 300 }
		),
		point("WinBlock37 safezone", -2058.228516, 443.873718, 1484.287231, { dwell = 0.25, speed = 300 }),
	}),
})

local stage7 = table.freeze({
	key = "stage7",
	label = "Stage 7",
	speed = 300,
	minimumCycleTime = 22,
	raceMinimumTime = 22,
	plate = Vector3.new(-3217.248291, 673.124329, 1459.436890),
	blockPath = table.freeze({ "Structure", "Stage7", "SAS", "WinBlock38" }),
	tsunami = stage6.tsunami,
	directPlate = true,
	plateNudge = true,
	route = extendRoute(stage6.route, {
		point("Stage 7 Bypass Rise", -2130.1968, 700, 1486.1375, { speed = 400 }),
		point("Stage 7 Bypass Mid", -2600, 700, 1486.1375, { speed = 400 }),
		point("Stage 7 Bypass End", -3150, 700, 1486.1375, { speed = 400 }),
		point("Stage 7 Zone", -3217.4749, 689.9922, 1486.1816, { dwell = 0.25, speed = 300 }),
	}),
})

local stage8 = table.freeze({
	key = "stage8",
	label = "Stage 8",
	speed = 300,
	speedMultiplier = 2.05,
	minimumCycleTime = 26,
	raceMinimumTime = 26,
	rewardCooldown = 180,
	plate = Vector3.new(-3657.565674, 617.461792, 1459.280396),
	blockPath = table.freeze({ "Structure", "Stage8", "SAS", "WinBlock39" }),
	tsunami = table.freeze({
		before = "Stage 6 Drop 1",
		timeout = 8,
		poll = 0.02,
		remainingMin = 0.35,
		remainingMax = 0.60,
		xMin = -1925,
		xMax = -1875,
		allowPassed = 1,
	}),
	humanoidPlate = true,
	route = extendRoute(stage6.route, {
		point("Stage 7 Bounce Approach", -2820.4934, 438.7875, 1486.1375, { speed = 400 }),
		point(
			"Stage 7 Bounce Validation",
			-2862.0237,
			438.2380,
			1486.1375,
			{ dwell = 0.05, humanoidWalk = true, touchValidation = true }
		),
		point(
			"Stage 7 Bounce Validation 2",
			-2938.0596,
			515.7750,
			1486.1283,
			{ dwell = 0.05, humanoidWalk = true, touchValidation = true }
		),
		point(
			"Stage 7 Bounce Validation 3",
			-3013.0247,
			591.6240,
			1486.1283,
			{ dwell = 0.05, humanoidWalk = true, touchValidation = true }
		),
		point("Stage 7 Bypass End", -3150, 700, 1486.1375, { dwell = 0.1, humanoidWalk = true }),
		point("Stage 7 Zone", -3217.4749, 689.9922, 1486.1816, { dwell = 0.25, speed = 300, minimumRaceElapsed = 20 }),
		point(
			"Stage 8 Bounce 1",
			-3260.9424,
			671.0512,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 2",
			-3308.9475,
			664.1522,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 3",
			-3384.9775,
			653.2253,
			1482.2904,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 4",
			-3436.9717,
			645.7529,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 5",
			-3488.9880,
			638.2774,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 6",
			-3533.0969,
			631.9381,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 7",
			-3573.1008,
			626.1890,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Bounce 8",
			-3625.0964,
			618.7162,
			1486.2006,
			{ dwell = 0.1, humanoidWalk = true, requiresBridge = true }
		),
		point(
			"Stage 8 Zone",
			-3659.139893,
			617.5,
			1486.181641,
			{ dwell = 0.25, humanoidWalk = true, requiresBridge = true, bridgeCommit = true }
		),
		point("WinBlock39 staging", -3645, 615.961792, 1475, { dwell = 0.25, speed = 250 }),
	}),
})

local stage9 = table.freeze({
	key = "stage9",
	label = "Stage 9",
	speed = 300,
	speedMultiplier = 2.05,
	minimumCycleTime = 36,
	raceMinimumTime = 36,
	rewardCooldown = 180,
	plate = Vector3.new(-4130.5625, 614.4604, 1458.6608),
	blockPath = table.freeze({ "Structure", "Stage9", "SAS", "WinBlock40" }),
	tsunami = stage8.tsunami,
	directPlate = true,
	route = extendRoute(stage8.route, {
		point("Stage 9 Entry Staging", -3675, 617.5, 1486.1816, { dwell = 0.05, speed = 250, minimumRaceElapsed = 31 }),
		point("Stage 9 Entry", -3692, 617.5, 1486.1816, { dwell = 0.02, speed = 400, movingWallGate = 1 }),
		point("Stage 9 Roof Rise", -3692, 820, 1486.1816, { dwell = 0.02, speed = 700 }),
		point("Stage 9 Roof Traverse", -4130, 820, 1458.6608, { dwell = 0.05, speed = 700 }),
		point("WinBlock40 staging", -4130, 617.5, 1475, { dwell = 0.1, speed = 700 }),
	}),
})

return table.freeze({
	stage2 = stage2,
	stage3 = stage3,
	stage4 = stage4,
	stage5 = stage5,
	stage6 = stage6,
	stage7 = stage7,
	stage8 = stage8,
	stage9 = stage9,
})
