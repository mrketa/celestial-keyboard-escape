local Menu = {}
Menu.__index = Menu

local TweenService = game:GetService("TweenService")

local TOKENS = {
	windowWidth = 690,
	expandedHeight = 500,
	debugWidth = 440,
	debugHeight = 360,
	viewportMargin = 14,
	headerHeight = 46,
	debugHeaderHeight = 36,
	sidebarWidth = 170,
	narrowBreakpoint = 600,
	narrowSidebarHeight = 52,
	cornerRadius = 9,
	panelRadius = 0,
	controlRadius = 4,
	refreshInterval = 0.25,
	armMinimum = 0.6,
	visibilityDuration = 0.18,
	visibilityOffset = 10,
	pageTransitionDuration = 0.24,
	pageTransitionOffset = 16,
	patternPulseDuration = 6.5,
	armMaximum = 4,
	inactive = Color3.new(0.023, 0.039, 0.07),
	active = Color3.new(0.043, 0.07, 0.137),
	button = Color3.new(0.031, 0.035, 0.058),
	hover = Color3.new(0.05, 0.054, 0.078),
	activeButton = Color3.new(0.07, 0.074, 0.098),
	group = Color3.new(0.019, 0.035, 0.062),
	navigation = Color3.fromRGB(44, 43, 47),
	main = Color3.fromRGB(14, 13, 15),
	mainTransparency = 0.04,
	border = Color3.new(1, 1, 1),
	text = Color3.new(1, 1, 1),
	disabled = Color3.new(0.51, 0.52, 0.56),
	mutedText = Color3.fromRGB(189, 188, 196),
	accent = Color3.new(0.3, 0.49, 1),
	success = Color3.fromRGB(92, 201, 146),
	warning = Color3.fromRGB(239, 181, 73),
	danger = Color3.fromRGB(235, 91, 103),
}
TOKENS.background = TOKENS.main
TOKENS.surface = TOKENS.main
TOKENS.surfaceRaised = TOKENS.button
TOKENS.sidebar = TOKENS.navigation
TOKENS.sidebarRaised = TOKENS.active
TOKENS.borderSoft = TOKENS.border
TOKENS.muted = TOKENS.mutedText

local STATE_COLORS = {
	idle = TOKENS.success,
	ejecting = TOKENS.warning,
	error = TOKENS.danger,
	ejected = TOKENS.disabled,
}

local function fixedError(code, message)
	return {
		code = code,
		message = message,
	}
end

local function cleanText(value, fallback, maximumLength)
	if type(value) ~= "string" and type(value) ~= "number" then
		return fallback
	end

	local text = tostring(value)
	text = string.gsub(text, "[%c]", " ")
	text = string.gsub(text, "%s+", " ")
	if #text > maximumLength then
		text = string.sub(text, 1, math.max(1, maximumLength - 1)) .. "…"
	end
	if text == "" then
		return fallback
	end
	return text
end

local function cleanCode(value, fallback)
	if type(value) ~= "string" then
		return fallback
	end

	local code = string.match(value, "^[%w_.-]+$")
	if not code then
		return fallback
	end
	return string.sub(code, 1, 48)
end

local function cleanBasename(value)
	if type(value) ~= "string" then
		return "unavailable"
	end

	local basename = string.match(value, "[^/\\]+$") or "unavailable"
	return cleanText(basename, "unavailable", 52)
end

local function makeLabel(parent, properties)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Gotham
	label.TextColor3 = TOKENS.text
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	for key, value in pairs(properties) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

local addCorner
local addStroke

local function makeButton(parent, name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = TOKENS.button
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.Text = text
	button.TextColor3 = TOKENS.text
	button.TextSize = 12
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.Selectable = true
	button.Parent = parent
	addCorner(button, TOKENS.controlRadius)
	local stroke = addStroke(button, TOKENS.border, 0.97)
	return button, stroke
end

local function makeSwitchRow(parent, name, title, detail, position, size)
	local row = Instance.new("TextButton")
	row.Name = name
	row.Active = true
	row.AutoButtonColor = false
	row.BackgroundColor3 = TOKENS.button
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Text = ""
	row.Position = position
	row.Size = size
	row.Parent = parent
	addCorner(row, TOKENS.controlRadius)
	local stroke = addStroke(row, TOKENS.border, 1)
	local titleLabel = makeLabel(row, {
		Name = "Title",
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -54, 0, detail and 16 or 26),
		Text = title,
		TextSize = 11,
	})
	local detailLabel = makeLabel(row, {
		Name = "Detail",
		Position = UDim2.fromOffset(10, 18),
		Size = UDim2.new(1, -54, 0, 13),
		Text = detail or "",
		TextColor3 = TOKENS.muted,
		TextSize = 10,
		Visible = detail ~= nil,
	})
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = TOKENS.inactive
	track.BorderSizePixel = 0
	track.Position = UDim2.new(1, -40, 0.5, -8)
	track.Size = UDim2.fromOffset(30, 17)
	track.Parent = row
	addCorner(track, 9)
	addStroke(track, TOKENS.border, 0.97)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundColor3 = TOKENS.disabled
	knob.BorderSizePixel = 0
	knob.Position = UDim2.fromOffset(2, 1)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.Parent = track
	addCorner(knob, 8)
	return {
		button = row,
		stroke = stroke,
		title = titleLabel,
		detail = detailLabel,
		baseDetail = detail or "",
		track = track,
		knob = knob,
	}
end
local function polishPanelSwitch(switch)
	switch.title.Font = Enum.Font.GothamBold
	switch.title.Position = UDim2.fromOffset(28, 0)
	switch.title.Size = UDim2.new(1, -88, 1, 0)
	switch.title.TextSize = 14
	switch.track.Position = UDim2.new(1, -48, 0.5, -10)
	switch.track.Size = UDim2.fromOffset(36, 20)
	switch.knob.Position = UDim2.fromOffset(2, 2)
	switch.knob.Size = UDim2.fromOffset(16, 16)
	switch.knobOffX = 2
	switch.knobOnX = 18
	switch.knobY = 2
	switch.polished = true
	switch.hovered = false
	switch.focused = false
	local statusDot = Instance.new("Frame")
	statusDot.Name = "ControlStatus"
	statusDot.BackgroundColor3 = TOKENS.disabled
	statusDot.BackgroundTransparency = 0.55
	statusDot.BorderSizePixel = 0
	statusDot.Position = UDim2.new(0, 12, 0.5, -3)
	statusDot.Size = UDim2.fromOffset(7, 7)
	statusDot.Parent = switch.button
	addCorner(statusDot, 7)
	switch.statusDot = statusDot
end

local function makePanelDividers(parent, prefix, count)
	local separators = {}
	for index = 1, count or 7 do
		local separator = Instance.new("Frame")
		separator.Name = prefix .. "Separator_" .. index
		separator.BackgroundColor3 = TOKENS.borderSoft
		separator.BackgroundTransparency = 0.94
		separator.BorderSizePixel = 0
		separator.Parent = parent
		table.insert(separators, separator)
	end
	local columnDivider = Instance.new("Frame")
	columnDivider.Name = prefix .. "ColumnDivider"
	columnDivider.BackgroundColor3 = TOKENS.borderSoft
	columnDivider.BackgroundTransparency = 0.94
	columnDivider.BorderSizePixel = 0
	columnDivider.Parent = parent
	return separators, columnDivider
end

local function updatePanelSwitchChrome(switch)
	if not switch.polished then
		return
	end
	local selected = switch.selected == true
	local enabled = switch.enabled == true
	local interactive = enabled and (switch.hovered == true or switch.focused == true)
	local backgroundColor = selected and TOKENS.active or TOKENS.hover
	local backgroundTransparency = selected and 0.55 or (interactive and 0.72 or 1)
	local strokeColor = selected and TOKENS.accent or TOKENS.border
	local strokeTransparency = selected and 0.72
		or (switch.focused and 0.55)
		or (switch.hovered and enabled and 0.88)
		or 1
	local dotColor = selected and TOKENS.accent or TOKENS.disabled
	local dotTransparency = selected and 0 or (enabled and 0.55 or 0.82)
	local chromeKey = table.concat({
		selected and "1" or "0",
		enabled and "1" or "0",
		switch.hovered and "1" or "0",
		switch.focused and "1" or "0",
	}, ":")
	if switch.chromeKey == nil then
		switch.button.BackgroundColor3 = backgroundColor
		switch.button.BackgroundTransparency = backgroundTransparency
		switch.stroke.Color = strokeColor
		switch.stroke.Transparency = strokeTransparency
		switch.statusDot.BackgroundColor3 = dotColor
		switch.statusDot.BackgroundTransparency = dotTransparency
	elseif switch.chromeKey ~= chromeKey then
		local tweenInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		TweenService:Create(
			switch.button,
			tweenInfo,
			{ BackgroundColor3 = backgroundColor, BackgroundTransparency = backgroundTransparency }
		):Play()
		TweenService:Create(switch.stroke, tweenInfo, { Color = strokeColor, Transparency = strokeTransparency }):Play()
		TweenService
			:Create(
				switch.statusDot,
				tweenInfo,
				{ BackgroundColor3 = dotColor, BackgroundTransparency = dotTransparency }
			)
			:Play()
	end
	switch.chromeKey = chromeKey
end

local function setSwitch(switch, selected, enabled, busyText)
	switch.button.Active = enabled
	switch.button.Selectable = enabled
	switch.enabled = enabled
	switch.title.TextColor3 = if switch.polished
		then ((selected or enabled) and TOKENS.text or TOKENS.disabled)
		else (selected and TOKENS.text or TOKENS.disabled)
	switch.detail.TextColor3 = TOKENS.muted
	switch.detail.Text = busyText or switch.baseDetail
	switch.detail.Visible = switch.detail.Text ~= ""
	if not switch.polished then
		switch.button.BackgroundTransparency = 1
		switch.stroke.Transparency = 1
	end
	local knobPosition =
		UDim2.fromOffset(selected and (switch.knobOnX or 15) or (switch.knobOffX or 1), switch.knobY or 1)
	local trackColor = selected and TOKENS.active or TOKENS.inactive
	local knobColor = selected and TOKENS.accent or TOKENS.disabled
	if switch.selected ~= selected then
		switch.selected = selected
		TweenService:Create(
			switch.track,
			TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ BackgroundColor3 = trackColor }
		):Play()
		TweenService:Create(
			switch.knob,
			TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = knobPosition, BackgroundColor3 = knobColor }
		):Play()
	else
		switch.track.BackgroundColor3 = trackColor
		switch.knob.BackgroundColor3 = knobColor
		switch.knob.Position = knobPosition
	end
	if not enabled then
		switch.title.TextTransparency = 0.45
		switch.detail.TextTransparency = 0.45
		switch.track.BackgroundTransparency = 0.45
		switch.knob.BackgroundTransparency = 0.45
	else
		switch.title.TextTransparency = 0
		switch.detail.TextTransparency = 0
		switch.track.BackgroundTransparency = 0
		switch.knob.BackgroundTransparency = 0
	end
	updatePanelSwitchChrome(switch)
end

local function makeNavIcon(parent, kind)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Position = UDim2.fromOffset(10, 7)
	icon.Size = UDim2.fromOffset(16, 16)
	icon.Parent = parent
	local function outline(name, position, size, radius)
		local part = Instance.new("Frame")
		part.Name = name
		part.BackgroundTransparency = 1
		part.BorderSizePixel = 0
		part.Position = position
		part.Size = size
		part.Parent = icon
		addCorner(part, radius or 1)
		addStroke(part, TOKENS.accent, 0)
		return part
	end
	local function node(name, position)
		local part = Instance.new("Frame")
		part.Name = name
		part.BackgroundColor3 = TOKENS.accent
		part.BorderSizePixel = 0
		part.Position = position
		part.Size = UDim2.fromOffset(4, 4)
		part.Parent = icon
		addCorner(part, 4)
	end
	local function line(name, position, size)
		local part = Instance.new("Frame")
		part.Name = name
		part.BackgroundColor3 = TOKENS.accent
		part.BorderSizePixel = 0
		part.Position = position
		part.Size = size
		part.Parent = icon
		addCorner(part, 1)
	end
	if kind == "world3" then
		line("RouteA", UDim2.fromOffset(4, 7), UDim2.fromOffset(5, 1))
		line("RouteB", UDim2.fromOffset(8, 5), UDim2.fromOffset(1, 6))
		line("RouteC", UDim2.fromOffset(8, 10), UDim2.fromOffset(4, 1))
		node("StartNode", UDim2.fromOffset(1, 5))
		node("BranchNode", UDim2.fromOffset(7, 4))
		node("EndNode", UDim2.fromOffset(11, 9))
	elseif kind == "events" then
		outline("Orbit", UDim2.fromOffset(2, 2), UDim2.fromOffset(12, 12), 6)
		line("Latitude", UDim2.fromOffset(3, 7), UDim2.fromOffset(10, 1))
		outline("Meridian", UDim2.fromOffset(6, 3), UDim2.fromOffset(4, 10), 3)
		node("Orbiter", UDim2.fromOffset(12, 1))
	else
		line("SliderOne", UDim2.fromOffset(1, 3), UDim2.fromOffset(14, 1))
		line("SliderTwo", UDim2.fromOffset(1, 8), UDim2.fromOffset(14, 1))
		line("SliderThree", UDim2.fromOffset(1, 13), UDim2.fromOffset(14, 1))
		outline("KnobOne", UDim2.fromOffset(4, 1), UDim2.fromOffset(4, 4), 2)
		outline("KnobTwo", UDim2.fromOffset(9, 6), UDim2.fromOffset(4, 4), 2)
		outline("KnobThree", UDim2.fromOffset(3, 11), UDim2.fromOffset(4, 4), 2)
	end
	return icon
end

addCorner = function(target, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
	return corner
end

addStroke = function(target, color, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Transparency = transparency or 0
	stroke.Parent = target
	return stroke
end

local function makePanel(parent, name, position, size, color, transparency, radiusOverride)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = color
	panel.BackgroundTransparency = transparency or 0
	panel.BorderSizePixel = 0
	panel.Position = position
	panel.Size = size
	panel.Parent = parent
	local radius = radiusOverride == nil and TOKENS.panelRadius or radiusOverride
	if radius > 0 then
		addCorner(panel, radius)
	end
	addStroke(panel, TOKENS.borderSoft, 0.97)
	return panel
end
local function makeMainPattern(parent, name, startX, stripeCount)
	local pattern = Instance.new("CanvasGroup")
	pattern.Name = name
	pattern.Active = false
	pattern.BackgroundTransparency = 1
	pattern.BorderSizePixel = 0
	pattern.ClipsDescendants = true
	pattern.GroupTransparency = 0.14
	pattern.Size = UDim2.fromScale(1, 1)
	pattern.ZIndex = 1
	pattern.Parent = parent
	for index = 0, stripeCount - 1 do
		local stripe = Instance.new("Frame")
		stripe.Name = string.format("Pinstripe_%03d", index)
		stripe.BackgroundColor3 = index % 2 == 0 and Color3.fromRGB(34, 33, 38) or Color3.fromRGB(6, 6, 7)
		stripe.BackgroundTransparency = index % 2 == 0 and 0.94 or 0.965
		stripe.BorderSizePixel = 0
		stripe.Position = UDim2.fromOffset(startX + index * 5, -130)
		stripe.Rotation = 18
		stripe.Size = UDim2.fromOffset(1, 720)
		stripe.ZIndex = 1
		stripe.Parent = pattern
	end
	return pattern
end

local function makePage(parent, name, canvasHeight)
	local page = Instance.new("ScrollingFrame")
	page.Name = name
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.CanvasSize = UDim2.fromOffset(0, canvasHeight)
	page.ScrollBarImageColor3 = TOKENS.border
	page.ScrollBarImageTransparency = 0.2
	page.ScrollBarThickness = 3
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Size = UDim2.fromScale(1, 1)
	page.ZIndex = 2
	page.Visible = false
	page.Parent = parent
	return page
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(800, 600)
end
local function reducedMotionEnabled(): boolean
	local enabled = false
	pcall(function()
		enabled = UserSettings():GetService("UserGameSettings").ReducedMotion == true
	end)
	return enabled
end

local function isPointerInput(input)
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local function cleanupFailure(label, errorCode, message)
	return {
		label = label,
		errorCode = errorCode,
		message = message,
	}
end

local function cloneEventConfig(config)
	local cloned = {}
	for key, value in pairs(config) do
		if key == "retry" then
			local retry = {}
			for kind, interval in pairs(value) do
				retry[kind] = interval
			end
			cloned.retry = retry
		else
			cloned[key] = value
		end
	end
	return cloned
end

function Menu.new(options)
	if
		type(options) ~= "table"
		or type(options.snapshot) ~= "function"
		or type(options.command) ~= "function"
		or type(options.runStage1Auto) ~= "function"
		or type(options.runStageOnce) ~= "function"
		or type(options.startCollectors) ~= "function"
		or type(options.configureCollectors) ~= "function"
	then
		return nil, fixedError("menu_invalid", "Menu requires snapshot, command, and stage callbacks")
	end

	local self = setmetatable({}, Menu)
	self._snapshot = options.snapshot
	self._command = options.command
	self._runStage1Auto = options.runStage1Auto
	self._runStageOnce = options.runStageOnce
	self._startCollectors = options.startCollectors
	self._configureCollectors = options.configureCollectors
	self._eventConfig = {
		summer = false,
		battle = false,
		egg = false,
		disco = false,
		soccer = false,
		rings = false,
		masked = false,
		overdrive = false,
		fab = false,
		survival = false,
		summerOnlyStorm = false,
		retry = {
			summer = 2,
			battle = 2,
			egg = 2,
			disco = 2,
			soccer = 2,
			rings = 2,
			masked = 2,
			overdrive = 2,
			fab = 2,
			survival = 2,
		},
	}
	self._pageTransitionEpoch = 0
	self._pageTransitionTweens = {}
	self._patternTweens = {}
	self._patternAnimationActive = false
	self._reducedMotion = reducedMotionEnabled()
	self._eventConfigKeys = {
		"summer",
		"battle",
		"egg",
		"disco",
		"soccer",
		"rings",
		"masked",
		"overdrive",
		"fab",
		"survival",
	}
	self._eventConfigDirty = false
	self._connections = {}
	self._shown = false
	self._menuVisible = false
	self._visibilityEpoch = 0
	self._visibilityTweens = {}
	self._menuRestPosition = nil
	self._destroyed = false
	self._destroying = false
	self._busy = false
	self._busyAction = nil
	self._armedAt = nil
	self._stageLoopKey = nil
	self._stageLoopStarted = false
	self._stageLoopStoppingKey = nil
	self._summerSettingsOpen = false
	self._refreshElapsed = 0
	self._dragInput = nil
	self._dragOrigin = nil
	self._debugVisible = false
	self._debugVisualDirty = true
	self._debugDragInput = nil
	self._debugDragOrigin = nil
	self._debugWindowOrigin = nil
	self._windowOrigin = nil
	self._localErrorCode = nil
	self._lastSnapshot = nil
	self._stale = true
	self._activePage = nil

	local screen = Instance.new("ScreenGui")
	screen.Name = "PotassiumNextPhase0"
	screen.DisplayOrder = 80
	screen.IgnoreGuiInset = false
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._screen = screen

	local window = Instance.new("CanvasGroup")
	window.Name = "Window"
	window.BackgroundColor3 = TOKENS.background
	window.BorderSizePixel = 0
	window.BackgroundTransparency = 1
	window.ClipsDescendants = true
	window.GroupTransparency = 1
	window.Size = UDim2.fromOffset(TOKENS.windowWidth, TOKENS.expandedHeight)
	window.Parent = screen
	self._window = window
	addCorner(window, TOKENS.cornerRadius)
	addStroke(window, TOKENS.border, 0.97)

	local navigationSurface = Instance.new("Frame")
	navigationSurface.Name = "NavigationSurface"
	navigationSurface.BackgroundColor3 = TOKENS.sidebar
	navigationSurface.BackgroundTransparency = 0.3
	navigationSurface.BorderSizePixel = 0
	navigationSurface.Size = UDim2.new(0, TOKENS.sidebarWidth, 1, 0)
	navigationSurface.Parent = window
	local navigationGradient = Instance.new("UIGradient")
	navigationGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, TOKENS.sidebar),
		ColorSequenceKeypoint.new(1, TOKENS.sidebar),
	})
	navigationGradient.Rotation = 90
	navigationGradient.Parent = navigationSurface
	local frostWash = Instance.new("Frame")
	frostWash.Name = "FrostWash"
	frostWash.BackgroundColor3 = TOKENS.sidebar
	frostWash.BackgroundTransparency = 0.72
	frostWash.BorderSizePixel = 0
	frostWash.Size = UDim2.fromScale(1, 1)
	frostWash.Parent = navigationSurface
	local frostGradient = Instance.new("UIGradient")
	frostGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, TOKENS.sidebar),
		ColorSequenceKeypoint.new(0.5, TOKENS.sidebar),
		ColorSequenceKeypoint.new(1, TOKENS.sidebar),
	})
	frostGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.48, 0.34),
		NumberSequenceKeypoint.new(1, 0.18),
	})
	frostGradient.Rotation = -18
	frostGradient.Parent = frostWash
	local frostHighlight = Instance.new("Frame")
	frostHighlight.Name = "FrostHighlight"
	frostHighlight.BackgroundColor3 = TOKENS.text
	frostHighlight.BackgroundTransparency = 0.94
	frostHighlight.BorderSizePixel = 0
	frostHighlight.Size = UDim2.new(1, 0, 0, 1)
	frostHighlight.Parent = navigationSurface
	local navigationDivider = Instance.new("Frame")
	navigationDivider.Name = "Divider"
	navigationDivider.BackgroundColor3 = TOKENS.borderSoft
	navigationDivider.BackgroundTransparency = 0.95
	navigationDivider.BorderSizePixel = 0
	navigationDivider.Position = UDim2.new(1, -1, 0, 0)
	navigationDivider.Size = UDim2.new(0, 1, 1, 0)
	navigationDivider.Parent = navigationSurface
	self._navigationPattern = makeMainPattern(navigationSurface, "NavigationPattern", -140, 89)
	self._navigationSurface = navigationSurface

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Active = true
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, TOKENS.headerHeight)
	header.Parent = window
	self._header = header
	local headerSurface = Instance.new("Frame")
	headerSurface.Name = "PageHeaderSurface"
	headerSurface.BackgroundColor3 = TOKENS.surface
	headerSurface.BackgroundTransparency = TOKENS.mainTransparency
	headerSurface.BorderSizePixel = 0
	headerSurface.Position = UDim2.fromOffset(TOKENS.sidebarWidth, 0)
	headerSurface.Size = UDim2.new(1, -TOKENS.sidebarWidth, 1, 0)
	headerSurface.Parent = header
	self._headerSurface = headerSurface
	self._headerPattern = makeMainPattern(headerSurface, "HeaderPattern", -140, 161)
	self._brandLabel = makeLabel(header, {
		Name = "Brand",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(TOKENS.sidebarWidth, TOKENS.headerHeight),
		Text = "Celestial",
		TextColor3 = TOKENS.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	self._brandDetailLabel = makeLabel(header, {
		Name = "BrandDetail",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 0),
		Text = "",
		Visible = false,
	})
	self._pageTitle = makeLabel(header, {
		Name = "PageTitle",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(TOKENS.sidebarWidth + 18, 0),
		Size = UDim2.new(1, -(TOKENS.sidebarWidth + 36), 1, 0),
		Text = "World 3",
		TextSize = 13,
	})
	self._pageSubtitle = makeLabel(header, {
		Name = "PageSubtitle",
		Position = UDim2.fromOffset(TOKENS.sidebarWidth + 18, 0),
		Size = UDim2.new(1, -(TOKENS.sidebarWidth + 36), 1, 0),
		Text = "",
		TextColor3 = TOKENS.muted,
		TextSize = 10,
		Visible = false,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, TOKENS.headerHeight)
	content.Size = UDim2.new(1, 0, 1, -TOKENS.headerHeight)
	content.Parent = window
	self._content = content

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = TOKENS.sidebar
	sidebar.BackgroundTransparency = 1
	sidebar.BorderSizePixel = 0
	sidebar.Position = UDim2.fromOffset(0, 0)
	sidebar.Size = UDim2.new(0, TOKENS.sidebarWidth, 1, 0)
	sidebar.Parent = content
	self._sidebar = sidebar

	self._navigationLabel = makeLabel(sidebar, {
		Name = "NavigationLabel",
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 0, 16),
		Text = "Core",
		TextColor3 = TOKENS.muted,
		TextSize = 9,
	})
	self._adminNavigationLabel = makeLabel(sidebar, {
		Name = "AdminNavigationLabel",
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(14, 74),
		Size = UDim2.new(1, -28, 0, 16),
		Text = "Admin",
		TextColor3 = TOKENS.muted,
		TextSize = 9,
	})
	self._systemNavigationLabel = makeLabel(sidebar, {
		Name = "SystemNavigationLabel",
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(14, 128),
		Size = UDim2.new(1, -28, 0, 16),
		Text = "System",
		TextColor3 = TOKENS.muted,
		TextSize = 9,
	})
	self._navSeparators = {}
	for index, y in ipairs({ 66, 120 }) do
		local separator = Instance.new("Frame")
		separator.Name = index == 1 and "CoreAdminSeparator" or "AdminSystemSeparator"
		separator.BackgroundColor3 = TOKENS.borderSoft
		separator.BackgroundTransparency = 0.94
		separator.BorderSizePixel = 0
		separator.Position = UDim2.fromOffset(14, y)
		separator.Size = UDim2.new(1, -28, 0, 1)
		separator.Parent = sidebar
		table.insert(self._navSeparators, separator)
	end

	self._pages = {}
	self._navButtons = {}
	self._pageOrder = { "world3", "events", "settings" }
	local navDefinitions = {
		{ key = "world3", label = "World 3", narrowLabel = "W3", wideY = 34 },
		{ key = "events", label = "Admin Events", narrowLabel = "Events", wideY = 94 },
		{ key = "settings", label = "Settings", narrowLabel = "Settings", wideY = 148 },
	}
	for _, definition in ipairs(navDefinitions) do
		local button, stroke = makeButton(sidebar, "Nav_" .. definition.key, "")
		button.Position = UDim2.fromOffset(8, definition.wideY)
		button.Size = UDim2.new(1, -16, 0, 30)
		button.BackgroundTransparency = 1
		stroke.Transparency = 1
		local icon = makeNavIcon(button, definition.key)
		local label = makeLabel(button, {
			Name = "Label",
			Position = UDim2.fromOffset(35, 0),
			Size = UDim2.new(1, -40, 1, 0),
			Text = definition.label,
			TextSize = 12,
		})
		self._navButtons[definition.key] = {
			button = button,
			stroke = stroke,
			icon = icon,
			label = definition.label,
			labelView = label,
			wideY = definition.wideY,
			narrowLabel = definition.narrowLabel,
		}
	end

	local sidebarStatus = Instance.new("Frame")
	sidebarStatus.Name = "RuntimeDot"
	sidebarStatus.BackgroundColor3 = TOKENS.success
	sidebarStatus.BorderSizePixel = 0
	sidebarStatus.Position = UDim2.new(0, 14, 1, -50)
	sidebarStatus.Size = UDim2.fromOffset(7, 7)
	sidebarStatus.Parent = sidebar
	addCorner(sidebarStatus, 7)
	self._sidebarStatus = sidebarStatus
	self._runtimeLabel = makeLabel(sidebar, {
		Name = "RuntimeLabel",
		Font = Enum.Font.GothamMedium,
		Position = UDim2.new(0, 30, 1, -59),
		Size = UDim2.new(1, -42, 0, 20),
		Text = "CELESTIAL RUNTIME",
		TextSize = 9,
	})
	self._safetyLabel = makeLabel(sidebar, {
		Name = "SafetyLabel",
		Position = UDim2.new(0, 14, 1, -31),
		Size = UDim2.new(1, -28, 0, 16),
		Text = "ESC disarms eject",
		TextColor3 = TOKENS.muted,
		TextSize = 9,
	})

	local pageHost = Instance.new("Frame")
	pageHost.Name = "PageHost"
	pageHost.BackgroundColor3 = TOKENS.surface
	pageHost.BackgroundTransparency = TOKENS.mainTransparency
	pageHost.BorderSizePixel = 0
	pageHost.ClipsDescendants = true
	pageHost.Position = UDim2.fromOffset(TOKENS.sidebarWidth, 0)
	pageHost.Size = UDim2.new(1, -TOKENS.sidebarWidth, 1, 0)
	pageHost.Parent = content
	self._pageHost = pageHost
	self._mainPattern = makeMainPattern(pageHost, "MainSurfacePattern", -140, 161)
	self._patterns = { self._navigationPattern, self._headerPattern, self._mainPattern }

	if self._reducedMotion then
		for _, pattern in ipairs(self._patterns) do
			pattern.GroupTransparency = 0.2
		end
	else
		for _, pattern in ipairs(self._patterns) do
			local tween = TweenService:Create(
				pattern,
				TweenInfo.new(TOKENS.patternPulseDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ GroupTransparency = 0.3 }
			)
			table.insert(self._patternTweens, tween)
			tween:Play()
		end
	end
	self._patternAnimationActive = not self._reducedMotion and #self._patternTweens > 0
	local world3 = makePage(pageHost, "World3Page", 388)
	self._pages.world3 = world3
	makeLabel(world3, {
		Name = "CoursesTitle",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(18, 18),
		Size = UDim2.new(1, -36, 0, 22),
		Text = "World 3 stages",
		TextSize = 13,
	})
	makeLabel(world3, {
		Name = "CoursesDetail",
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.new(1, -36, 0, 18),
		Text = "One active loop at a time.",
		TextColor3 = TOKENS.muted,
		TextSize = 10,
	})
	local stageControls =
		makePanel(world3, "StageControls", UDim2.fromOffset(18, 70), UDim2.new(1, -36, 0, 304), TOKENS.main, 0.08)
	self._stageActionSwitches = {}
	self._stageDisplayOrder =
		{ "stage1auto", "stage2", "stage3", "stage4", "stage5", "stage6", "stage7", "stage8", "stage9" }
	self._stageSeparators, self._stageColumnDivider = makePanelDividers(stageControls, "Stage", 8)
	for index, key in ipairs(self._stageDisplayOrder) do
		local stage = if key == "stage1auto" then 1 else tonumber(string.match(key, "%d+"))
		local column = ((index - 1) % 2) + 1
		local row = math.floor((index - 1) / 2) + 1
		local name = if key == "stage1auto" then "Stage1AutoSwitch" else "Stage" .. stage .. "RunOnceSwitch"
		local position = UDim2.new((column - 1) * 0.5, column == 1 and 12 or 6, 0, 12 + ((row - 1) * 58))
		local switch = makeSwitchRow(stageControls, name, "Stage " .. stage, nil, position, UDim2.new(0.5, -18, 0, 48))
		polishPanelSwitch(switch)
		self._stageActionSwitches[key] = switch
	end
	local events = makePage(pageHost, "AdminEventsPage", 398)
	self._pages.events = events
	makeLabel(events, {
		Name = "AdminEventsTitle",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(18, 18),
		Size = UDim2.new(1, -36, 0, 20),
		Text = "Admin Events",
		TextSize = 12,
	})
	self._eventStatusLabel = makeLabel(events, {
		Name = "EventsStatus",
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.new(1, -36, 0, 18),
		Text = "Select event collectors.",
		TextColor3 = TOKENS.muted,
		TextSize = 10,
	})
	local eventPanel =
		makePanel(events, "EventControls", UDim2.fromOffset(18, 70), UDim2.new(1, -36, 0, 304), TOKENS.main, 0.08)
	self._eventButtons = {}
	self._eventDisplayOrder = { "summer", "battle", "disco", "rings", "masked", "overdrive", "fab", "survival", "egg" }
	self._eventNames = {
		summer = "Summer Coins",
		battle = "Coin Battle",
		disco = "Disco Keycaps",
		rings = "Win Rings",
		masked = "Masked",
		overdrive = "Overdrive",
		fab = "Fab Minigame",
		survival = "Survival Chase",
		egg = "Egg Rain",
	}
	self._eventSeparators, self._eventColumnDivider = makePanelDividers(eventPanel, "Event", 8)
	for index, key in ipairs(self._eventDisplayOrder) do
		local column = ((index - 1) % 2) + 1
		local row = math.floor((index - 1) / 2) + 1
		local position = UDim2.new((column - 1) * 0.5, column == 1 and 12 or 6, 0, 12 + ((row - 1) * 58))
		local switch =
			makeSwitchRow(eventPanel, "Event_" .. key, self._eventNames[key], nil, position, UDim2.new(0.5, -18, 0, 48))
		polishPanelSwitch(switch)
		if key == "summer" then
			switch.title.Size = UDim2.new(1, -126, 1, 0)
		end
		self._eventButtons[key] = {
			button = switch.button,
			stroke = switch.stroke,
			switch = switch,
			name = self._eventNames[key],
		}
	end
	local stormGear, stormGearStroke = makeButton(eventPanel, "SummerStormGear", "⚙")
	stormGear.Position = UDim2.new(0.5, -88, 0, 23)
	stormGear.Size = UDim2.fromOffset(26, 26)
	stormGear.TextSize = 15
	stormGear.ZIndex = 2
	self._stormButton, self._stormStroke = stormGear, stormGearStroke

	local summerPopover = makePanel(
		eventPanel,
		"SummerSettingsPopover",
		UDim2.new(0.5, -88, 0, 57),
		UDim2.fromOffset(260, 96),
		TOKENS.main,
		0.02,
		0
	)
	summerPopover.ZIndex = 4
	summerPopover.Visible = false
	local summerPopoverAnchor = Instance.new("Frame")
	summerPopoverAnchor.Name = "GearAnchor"
	summerPopoverAnchor.BackgroundColor3 = TOKENS.borderSoft
	summerPopoverAnchor.BackgroundTransparency = 0.45
	summerPopoverAnchor.BorderSizePixel = 0
	summerPopoverAnchor.Position = UDim2.fromOffset(13, -8)
	summerPopoverAnchor.Size = UDim2.fromOffset(1, 8)
	summerPopoverAnchor.ZIndex = 5
	summerPopoverAnchor.Parent = summerPopover
	local summerPopoverStroke = summerPopover:FindFirstChildOfClass("UIStroke")
	if summerPopoverStroke then
		summerPopoverStroke.Transparency = 0.86
	end
	local summerPopoverTitle = makeLabel(summerPopover, {
		Name = "PopoverTitle",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -54, 0, 30),
		Text = "Summer Coins",
		TextSize = 12,
		ZIndex = 5,
	})
	local summerPopoverClose, summerPopoverCloseStroke = makeButton(summerPopover, "SummerSettingsClose", "×")
	summerPopoverClose.Position = UDim2.new(1, -38, 0, 5)
	summerPopoverClose.Size = UDim2.fromOffset(30, 28)
	summerPopoverClose.BackgroundTransparency = 1
	summerPopoverClose.TextSize = 16
	summerPopoverClose.ZIndex = 5
	summerPopoverCloseStroke.Transparency = 1
	local summerStormSwitch = makeSwitchRow(
		summerPopover,
		"SummerStormOnlySwitch",
		"Coin Storm only",
		nil,
		UDim2.fromOffset(8, 38),
		UDim2.new(1, -16, 0, 50)
	)
	summerStormSwitch.title.Font = Enum.Font.GothamMedium
	summerStormSwitch.title.Position = UDim2.fromOffset(12, 0)
	summerStormSwitch.title.Size = UDim2.new(1, -64, 1, 0)
	summerStormSwitch.title.TextSize = 12
	summerStormSwitch.button.ZIndex = 5
	for _, child in ipairs(summerStormSwitch.button:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.ZIndex = 5
		end
	end
	self._summerSettingsPopover = summerPopover
	self._summerSettingsAnchor = summerPopoverAnchor
	self._summerSettingsStroke = summerPopoverStroke
	self._summerSettingsTitle = summerPopoverTitle
	self._summerSettingsCloseButton = summerPopoverClose
	self._summerStormSwitch = summerStormSwitch
	local settings = makePage(pageHost, "SettingsPage", 360)
	self._pages.settings = settings
	makeLabel(settings, {
		Name = "SafetyTitle",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(18, 18),
		Size = UDim2.new(1, -36, 0, 20),
		Text = "Runtime safety",
		TextSize = 12,
	})
	local safetyCard =
		makePanel(settings, "SafetyCard", UDim2.fromOffset(18, 48), UDim2.new(1, -36, 0, 142), TOKENS.group, 0.1)
	makeLabel(safetyCard, {
		Name = "SafetyDetail",
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 34),
		Text = "Stop ends the current automation. Eject releases the runtime export and disconnects active menu signals.",
		TextColor3 = TOKENS.disabled,
		TextSize = 10,
		TextWrapped = true,
	})
	local stopButton, stopStroke = makeButton(safetyCard, "Stop", "Stop Current Automation")
	stopButton.Position = UDim2.fromOffset(14, 58)
	stopButton.Size = UDim2.new(0.5, -20, 0, 38)
	self._stopButton, self._stopStroke = stopButton, stopStroke
	local ejectButton, ejectStroke = makeButton(safetyCard, "Eject", "Eject Runtime")
	ejectButton.Position = UDim2.new(0.5, 6, 0, 58)
	ejectButton.Size = UDim2.new(0.5, -20, 0, 38)
	self._ejectButton, self._ejectStroke = ejectButton, ejectStroke
	makeLabel(settings, {
		Name = "InterfaceTitle",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(18, 180),
		Size = UDim2.new(1, -36, 0, 20),
		Text = "Interface",
		TextSize = 12,
	})
	local interfaceCard =
		makePanel(settings, "InterfaceCard", UDim2.fromOffset(18, 210), UDim2.new(1, -36, 0, 70), TOKENS.group, 0.1)
	local debugSwitch = makeSwitchRow(
		interfaceCard,
		"DebugMenu",
		"Debug menu",
		"Open the live runtime diagnostic window.",
		UDim2.fromOffset(10, 14),
		UDim2.new(1, -20, 0, 42)
	)
	self._debugSwitch = debugSwitch
	self._debugButton = debugSwitch.button

	local debugWindow = makePanel(
		screen,
		"DebugWindow",
		UDim2.fromOffset(TOKENS.viewportMargin, TOKENS.viewportMargin),
		UDim2.fromOffset(TOKENS.debugWidth, TOKENS.debugHeight),
		TOKENS.inactive,
		0,
		TOKENS.cornerRadius
	)
	debugWindow.Visible = false
	debugWindow.ZIndex = 90
	self._debugWindow = debugWindow
	local debugHeader = Instance.new("Frame")
	debugHeader.Name = "Header"
	debugHeader.Active = true
	debugHeader.BackgroundColor3 = TOKENS.button
	debugHeader.BorderSizePixel = 0
	debugHeader.Size = UDim2.new(1, 0, 0, TOKENS.debugHeaderHeight)
	debugHeader.ZIndex = 91
	debugHeader.Parent = debugWindow
	makeLabel(debugHeader, {
		Name = "Title",
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Text = "Celestial Debug",
		TextSize = 13,
		ZIndex = 92,
	})
	local debugClose, _ = makeButton(debugHeader, "Close", "×")
	debugClose.Position = UDim2.new(1, -31, 0, 5)
	debugClose.Size = UDim2.fromOffset(24, 24)
	debugClose.ZIndex = 92
	self._debugCloseButton = debugClose
	local debugBody = makePage(debugWindow, "Body", 1)
	debugBody.Position = UDim2.fromOffset(8, TOKENS.debugHeaderHeight + 6)
	debugBody.Size = UDim2.new(1, -16, 1, -(TOKENS.debugHeaderHeight + 14))
	debugBody.Visible = true
	debugBody.ZIndex = 91
	self._debugBody = debugBody
	self._debugHeader = debugHeader
	self._debugText = makeLabel(debugBody, {
		Name = "Rows",
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -8, 0, 1),
		Text = "",
		TextColor3 = TOKENS.disabled,
		TextSize = 10,
		TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 92,
	})

	self:_selectPage("world3")
	return self
end

function Menu:_hasRole(role)
	for _, item in ipairs(self._connections) do
		if item.role == role then
			return true
		end
	end
	return false
end

function Menu:_connect(role, signal, callback)
	if self:_hasRole(role) then
		return true
	end
	local ok, connection = pcall(function()
		return signal:Connect(callback)
	end)
	if not ok or not connection then
		return nil, fixedError("menu_connect_failed", "Menu signal connection failed")
	end
	table.insert(self._connections, {
		role = role,
		connection = connection,
	})
	return true
end
function Menu:_cancelPageTransitions()
	self._pageTransitionEpoch += 1
	for _, tween in ipairs(self._pageTransitionTweens) do
		pcall(tween.Cancel, tween)
	end
	table.clear(self._pageTransitionTweens)
	for _, page in pairs(self._pages or {}) do
		page.Position = UDim2.fromOffset(0, 0)
		page.ZIndex = 2
	end
end

function Menu:_selectPage(pageKey)
	local page = self._pages and self._pages[pageKey]
	local navItem = self._navButtons and self._navButtons[pageKey]
	if not page or not navItem then
		return false
	end

	local previousKey = self._activePage
	local previousPage = previousKey and self._pages[previousKey] or nil
	local changed = previousKey ~= pageKey
	if changed then
		self._armedAt = nil
		if pageKey ~= "events" then
			self._summerSettingsOpen = false
			if self._summerSettingsPopover then
				self._summerSettingsPopover.Visible = false
			end
		end
	end
	self:_cancelPageTransitions()
	self._activePage = pageKey
	for _, candidate in pairs(self._pages) do
		candidate.Visible = false
	end
	if changed and previousPage and not self._reducedMotion then
		local previousIndex = table.find(self._pageOrder, previousKey) or 1
		local nextIndex = table.find(self._pageOrder, pageKey) or previousIndex
		local direction = nextIndex >= previousIndex and 1 or -1
		local epoch = self._pageTransitionEpoch
		previousPage.Visible = true
		previousPage.Position = UDim2.fromOffset(0, 0)
		page.Visible = true
		page.Position = UDim2.fromOffset(direction * TOKENS.pageTransitionOffset, 0)
		page.ZIndex = 3
		local exitTween = TweenService:Create(
			previousPage,
			TweenInfo.new(TOKENS.pageTransitionDuration * 0.72, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(-direction * math.floor(TOKENS.pageTransitionOffset * 0.5), 0) }
		)
		local enterTween = TweenService:Create(
			page,
			TweenInfo.new(TOKENS.pageTransitionDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 0) }
		)
		table.insert(self._pageTransitionTweens, exitTween)
		table.insert(self._pageTransitionTweens, enterTween)
		exitTween:Play()
		enterTween:Play()
		task.delay(TOKENS.pageTransitionDuration, function()
			if not self._destroyed and self._pageTransitionEpoch == epoch and self._activePage == pageKey then
				previousPage.Visible = false
				previousPage.Position = UDim2.fromOffset(0, 0)
				page.ZIndex = 2
			end
		end)
	else
		page.Visible = true
	end
	for key, item in pairs(self._navButtons) do
		local selected = key == pageKey
		item.button.BackgroundColor3 = TOKENS.sidebarRaised
		local targetTransparency = selected and 0.5 or 1
		if changed and not self._reducedMotion then
			local navTween = TweenService:Create(
				item.button,
				TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ BackgroundTransparency = targetTransparency }
			)
			table.insert(self._pageTransitionTweens, navTween)
			navTween:Play()
		else
			item.button.BackgroundTransparency = targetTransparency
		end
		item.button.TextColor3 = TOKENS.text
		item.labelView.TextColor3 = TOKENS.text
		item.stroke.Color = TOKENS.border
		item.stroke.Transparency = 1
	end

	local metadata = {
		world3 = { title = "World 3", subtitle = "Supported course automation and runtime activity" },
		events = { title = "Admin Events", subtitle = "Configure World 3 event collectors" },
		settings = { title = "Settings", subtitle = "Runtime safety and interface behavior" },
	}
	local selectedMetadata = metadata[pageKey]
	self._pageTitle.Text = selectedMetadata.title
	self._pageSubtitle.Text = selectedMetadata.subtitle
	return true
end

function Menu:_disarm()
	self._armedAt = nil
	if self._ejectButton and not self._busy then
		self:_updateControls(self._lastSnapshot)
	end
end

function Menu:_viewportSize()
	if self._screen ~= nil then
		local ok, size = pcall(function()
			return self._screen.AbsoluteSize
		end)
		if ok and typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then
			return size
		end
	end
	return viewportSize()
end

function Menu:_applyResponsiveLayout(width)
	if not self._sidebar or not self._pageHost or not self._navButtons then
		return
	end
	local narrow = width < TOKENS.narrowBreakpoint
	if self._narrow == narrow then
		return
	end
	self._narrow = narrow

	self._brandLabel.Size = narrow and UDim2.new(1, -76, 1, 0)
		or UDim2.fromOffset(TOKENS.sidebarWidth, TOKENS.headerHeight)
	self._brandDetailLabel.Visible = false
	self._pageTitle.Visible = not narrow
	self._pageSubtitle.Visible = false
	self._navigationLabel.Visible = not narrow
	self._adminNavigationLabel.Visible = not narrow
	self._systemNavigationLabel.Visible = not narrow
	self._sidebarStatus.Visible = not narrow
	self._runtimeLabel.Visible = not narrow
	self._safetyLabel.Visible = not narrow
	for _, separator in ipairs(self._navSeparators) do
		separator.Visible = not narrow
	end

	self._navigationSurface.Visible = not narrow
	self._headerSurface.Position = narrow and UDim2.fromOffset(0, 0) or UDim2.fromOffset(TOKENS.sidebarWidth, 0)
	self._headerSurface.Size = narrow and UDim2.fromScale(1, 1) or UDim2.new(1, -TOKENS.sidebarWidth, 1, 0)
	self._sidebar.BackgroundTransparency = narrow and 0.35 or 1
	if narrow then
		self._sidebar.Position = UDim2.fromOffset(8, 8)
		self._sidebar.Size = UDim2.new(1, -16, 0, TOKENS.narrowSidebarHeight)
		self._pageHost.Position = UDim2.fromOffset(8, TOKENS.narrowSidebarHeight + 16)
		self._pageHost.Size = UDim2.new(1, -16, 1, -(TOKENS.narrowSidebarHeight + 24))
	else
		self._sidebar.Position = UDim2.fromOffset(0, 0)
		self._sidebar.Size = UDim2.new(0, TOKENS.sidebarWidth, 1, 0)
		self._pageHost.Position = UDim2.fromOffset(TOKENS.sidebarWidth, 0)
		self._pageHost.Size = UDim2.new(1, -TOKENS.sidebarWidth, 1, 0)
	end

	for index, pageKey in ipairs(self._pageOrder) do
		local item = self._navButtons[pageKey]
		if narrow then
			item.button.Position = UDim2.new((index - 1) / #self._pageOrder, 5, 0, 10)
			item.button.Size = UDim2.new(1 / #self._pageOrder, -10, 0, 32)
			item.labelView.Text = item.narrowLabel
			item.labelView.Position = UDim2.fromOffset(35, 0)
			item.labelView.Size = UDim2.new(1, -38, 1, 0)
			item.labelView.TextSize = 9
		else
			item.button.Position = UDim2.fromOffset(8, item.wideY)
			item.button.Size = UDim2.new(1, -16, 0, 30)
			item.labelView.Text = item.label
			item.labelView.Position = UDim2.fromOffset(35, 0)
			item.labelView.Size = UDim2.new(1, -40, 1, 0)
			item.labelView.TextSize = 12
		end
	end

	local world3 = self._pages.world3
	world3.CoursesTitle.Position = UDim2.fromOffset(14, 14)
	world3.CoursesTitle.Size = UDim2.new(1, -28, 0, 22)
	world3.CoursesDetail.Position = UDim2.fromOffset(14, 36)
	world3.CoursesDetail.Size = UDim2.new(1, -28, 0, 18)
	world3.StageControls.Position = UDim2.fromOffset(14, 66)
	if narrow then
		world3.StageControls.Size = UDim2.new(1, -28, 0, 516)
		world3.CanvasSize = UDim2.fromOffset(0, 596)
		self._stageColumnDivider.Visible = false
		for index, key in ipairs(self._stageDisplayOrder) do
			local switch = self._stageActionSwitches[key]
			switch.button.Position = UDim2.fromOffset(12, 12 + ((index - 1) * 56))
			switch.button.Size = UDim2.new(1, -24, 0, 48)
		end
		for index, separator in ipairs(self._stageSeparators) do
			separator.Visible = true
			separator.Position = UDim2.fromOffset(12, 65 + ((index - 1) * 56))
			separator.Size = UDim2.new(1, -24, 0, 1)
		end
	else
		world3.StageControls.Size = UDim2.new(1, -28, 0, 304)
		world3.CanvasSize = UDim2.fromOffset(0, 388)
		self._stageColumnDivider.Visible = true
		self._stageColumnDivider.Position = UDim2.new(0.5, 0, 0, 12)
		self._stageColumnDivider.Size = UDim2.new(0, 1, 1, -24)
		for index, key in ipairs(self._stageDisplayOrder) do
			local switch = self._stageActionSwitches[key]
			local column = ((index - 1) % 2) + 1
			local row = math.floor((index - 1) / 2) + 1
			switch.button.Position = UDim2.new((column - 1) * 0.5, column == 1 and 12 or 6, 0, 12 + ((row - 1) * 58))
			switch.button.Size = UDim2.new(0.5, -18, 0, 48)
		end
		for index, separator in ipairs(self._stageSeparators) do
			separator.Visible = index <= 4
			if index <= 4 then
				separator.Position = UDim2.fromOffset(12, 65 + ((index - 1) * 58))
				separator.Size = UDim2.new(1, -24, 0, 1)
			end
		end
	end

	local events = self._pages.events
	events.AdminEventsTitle.Position = UDim2.fromOffset(14, 14)
	events.AdminEventsTitle.Size = UDim2.new(1, -28, 0, 22)
	events.EventsStatus.Position = UDim2.fromOffset(14, 36)
	events.EventsStatus.Size = UDim2.new(1, -28, 0, 18)
	events.EventControls.Position = UDim2.fromOffset(14, 66)
	if narrow then
		events.CanvasSize = UDim2.fromOffset(0, 600)
		events.EventControls.Size = UDim2.new(1, -28, 0, 516)
		self._eventColumnDivider.Visible = false
		for index, kind in ipairs(self._eventDisplayOrder) do
			local switch = self._eventButtons[kind].switch
			switch.button.Position = UDim2.fromOffset(12, 12 + ((index - 1) * 56))
			switch.button.Size = UDim2.new(1, -24, 0, 48)
		end
		for index, separator in ipairs(self._eventSeparators) do
			separator.Visible = index <= 8
			if index <= 8 then
				separator.Position = UDim2.fromOffset(12, 65 + ((index - 1) * 56))
				separator.Size = UDim2.new(1, -24, 0, 1)
			end
		end
		self._stormButton.Position = UDim2.new(1, -94, 0, 23)
		self._summerSettingsPopover.AnchorPoint = Vector2.new(1, 0)
		self._summerSettingsPopover.Position = UDim2.new(1, -12, 0, 57)
		self._summerSettingsPopover.Size = UDim2.new(1, -24, 0, 96)
		self._summerSettingsAnchor.Position = UDim2.new(1, -13, 0, -8)
	else
		events.CanvasSize = UDim2.fromOffset(0, 388)
		events.EventControls.Size = UDim2.new(1, -28, 0, 304)
		self._eventColumnDivider.Visible = true
		self._eventColumnDivider.Position = UDim2.new(0.5, 0, 0, 12)
		self._eventColumnDivider.Size = UDim2.new(0, 1, 1, -24)
		for index, kind in ipairs(self._eventDisplayOrder) do
			local switch = self._eventButtons[kind].switch
			local column = ((index - 1) % 2) + 1
			local row = math.floor((index - 1) / 2) + 1
			switch.button.Position = UDim2.new((column - 1) * 0.5, column == 1 and 12 or 6, 0, 12 + ((row - 1) * 58))
			switch.button.Size = UDim2.new(0.5, -18, 0, 48)
		end
		for index, separator in ipairs(self._eventSeparators) do
			separator.Visible = index <= 4
			if index <= 4 then
				separator.Position = UDim2.fromOffset(12, 65 + ((index - 1) * 58))
				separator.Size = UDim2.new(1, -24, 0, 1)
			end
		end
		self._stormButton.Position = UDim2.new(0.5, -88, 0, 23)
		self._summerSettingsPopover.AnchorPoint = Vector2.zero
		self._summerSettingsPopover.Position = UDim2.new(0.5, -88, 0, 57)
		self._summerSettingsPopover.Size = UDim2.fromOffset(260, 96)
		self._summerSettingsAnchor.Position = UDim2.fromOffset(13, -8)
	end
	self._stormButton.Size = UDim2.fromOffset(26, 26)

	local settings = self._pages.settings
	if narrow then
		settings.SafetyTitle.Position, settings.SafetyTitle.Size = UDim2.fromOffset(14, 18), UDim2.new(1, -28, 0, 20)
		settings.SafetyCard.Position, settings.SafetyCard.Size = UDim2.fromOffset(14, 48), UDim2.new(1, -28, 0, 142)
		settings.InterfaceTitle.Position, settings.InterfaceTitle.Size =
			UDim2.fromOffset(14, 210), UDim2.new(1, -28, 0, 20)
		settings.InterfaceCard.Position, settings.InterfaceCard.Size =
			UDim2.fromOffset(14, 240), UDim2.new(1, -28, 0, 70)
	else
		settings.SafetyTitle.Position, settings.SafetyTitle.Size = UDim2.fromOffset(14, 18), UDim2.new(0.62, -21, 0, 20)
		settings.SafetyCard.Position, settings.SafetyCard.Size = UDim2.fromOffset(14, 48), UDim2.new(0.62, -21, 0, 142)
		settings.InterfaceTitle.Position, settings.InterfaceTitle.Size =
			UDim2.new(0.62, 7, 0, 18), UDim2.new(0.38, -21, 0, 20)
		settings.InterfaceCard.Position, settings.InterfaceCard.Size =
			UDim2.new(0.62, 7, 0, 48), UDim2.new(0.38, -21, 0, 70)
	end
end

function Menu:_fitWindow()
	if not self._window then
		return
	end

	local viewport = self:_viewportSize()
	local margin = TOKENS.viewportMargin
	local availableWidth = math.max(1, viewport.X - (margin * 2))
	local availableHeight = math.max(1, viewport.Y - (margin * 2))
	local width = math.min(TOKENS.windowWidth, availableWidth)
	local height = math.min(TOKENS.expandedHeight, availableHeight)
	self:_applyResponsiveLayout(width)
	self._window.Size = UDim2.fromOffset(width, height)

	local position = self._menuRestPosition or self._window.Position
	local maxX = math.max(margin, viewport.X - width - margin)
	local maxY = math.max(margin, viewport.Y - height - margin)
	local restPosition =
		UDim2.fromOffset(math.clamp(position.X.Offset, margin, maxX), math.clamp(position.Y.Offset, margin, maxY))
	self._menuRestPosition = restPosition
	if #self._visibilityTweens == 0 then
		self._window.Position = self._menuVisible and restPosition
			or UDim2.fromOffset(restPosition.X.Offset, restPosition.Y.Offset + TOKENS.visibilityOffset)
	end
end

function Menu:_centerWindow()
	local viewport = self:_viewportSize()
	local margin = TOKENS.viewportMargin
	local width = math.min(TOKENS.windowWidth, math.max(1, viewport.X - (margin * 2)))
	local height = math.min(TOKENS.expandedHeight, math.max(1, viewport.Y - (margin * 2)))
	self:_applyResponsiveLayout(width)
	self._window.Size = UDim2.fromOffset(width, height)
	local restPosition = UDim2.fromOffset(
		math.max(margin, math.floor((viewport.X - width) / 2)),
		math.max(margin, math.floor((viewport.Y - height) / 2))
	)
	self._window.Position = restPosition
	self._menuRestPosition = restPosition
end

function Menu:_cancelVisibilityTweens()
	local tweens = self._visibilityTweens
	self._visibilityTweens = {}
	for _, tween in ipairs(tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
end

function Menu:_setPatternAnimationActive(active)
	active = active == true and not self._reducedMotion and not self._destroyed
	if self._patternAnimationActive == active then
		return
	end
	self._patternAnimationActive = active
	for _, tween in ipairs(self._patternTweens) do
		pcall(function()
			if active then
				tween:Play()
			else
				tween:Pause()
			end
		end)
	end
end

function Menu:_isFullyHidden()
	return not self._menuVisible
		and self._screen ~= nil
		and self._screen.Enabled == false
		and #self._visibilityTweens == 0
end

function Menu:_setMenuVisible(visible, instant)
	if self._destroyed or not self._screen or not self._window then
		return false
	end
	self._visibilityEpoch += 1
	local epoch = self._visibilityEpoch
	local wasVisible = self._menuVisible
	self:_cancelVisibilityTweens()
	self._menuVisible = visible == true
	if self._menuVisible then
		self:_refresh(true)
		self:_setPatternAnimationActive(true)
	end
	local restPosition = self._menuRestPosition or self._window.Position
	local hiddenPosition = UDim2.fromOffset(restPosition.X.Offset, restPosition.Y.Offset + TOKENS.visibilityOffset)
	if self._menuVisible then
		self._screen.Enabled = true
		if not wasVisible and self._window.GroupTransparency >= 0.999 then
			self._window.Position = hiddenPosition
		end
	end
	if instant then
		self._window.GroupTransparency = self._menuVisible and 0 or 1
		self._window.Position = self._menuVisible and restPosition or hiddenPosition
		self._screen.Enabled = self._menuVisible
		if not self._menuVisible then
			self:_setPatternAnimationActive(false)
		end
		return true
	end
	local easingDirection = self._menuVisible and Enum.EasingDirection.Out or Enum.EasingDirection.In
	local tweenInfo = TweenInfo.new(TOKENS.visibilityDuration, Enum.EasingStyle.Quart, easingDirection)
	local fade = TweenService:Create(self._window, tweenInfo, { GroupTransparency = self._menuVisible and 0 or 1 })
	local slide = TweenService:Create(
		self._window,
		tweenInfo,
		{ Position = self._menuVisible and restPosition or hiddenPosition }
	)
	self._visibilityTweens = { fade, slide }
	fade:Play()
	slide:Play()
	task.spawn(function()
		fade.Completed:Wait()
		if not self._destroyed and self._visibilityEpoch == epoch then
			self._visibilityTweens = {}
			if not self._menuVisible and self._screen then
				self._screen.Enabled = false
				self:_setPatternAnimationActive(false)
			end
		end
	end)
	return true
end

function Menu:_setDebugVisible(visible)
	self._debugVisible = visible == true
	if not self._debugVisible then
		self._debugDragInput = nil
		self._debugDragOrigin = nil
		self._debugWindowOrigin = nil
		self._debugVisualDirty = true
	elseif self._debugVisualDirty then
		self:_renderDebug(self._lastSnapshot)
	end
	if self._debugWindow then
		self._debugWindow.Visible = self._debugVisible
		if self._debugVisible then
			self:_fitDebugWindow()
		end
	end
end

function Menu:_fitDebugWindow()
	if not self._debugWindow then
		return
	end
	local viewport = self:_viewportSize()
	local margin = TOKENS.viewportMargin
	local width = math.min(TOKENS.debugWidth, math.max(1, viewport.X - margin * 2))
	local height = math.min(TOKENS.debugHeight, math.max(TOKENS.debugHeaderHeight, viewport.Y - margin * 2))
	self._debugWindow.Size = UDim2.fromOffset(width, height)
	local position = self._debugWindow.Position
	self._debugWindow.Position = UDim2.fromOffset(
		math.clamp(position.X.Offset, margin, math.max(margin, viewport.X - width - margin)),
		math.clamp(position.Y.Offset, margin, math.max(margin, viewport.Y - height - margin))
	)
end

function Menu:_renderDebug(snapshot)
	if not self._debugText then
		return
	end
	if not self._debugVisible then
		self._debugVisualDirty = true
		return
	end
	local maximumLines = 240
	local maximumSectionLines = 48
	local lines = {}
	local function debugScalar(value)
		if value == nil then
			return "nil"
		end
		local valueType = typeof(value)
		if valueType == "boolean" then
			return value and "true" or "false"
		elseif valueType == "string" or valueType == "number" then
			return cleanText(value, "nil", 72)
		elseif
			valueType == "Vector2"
			or valueType == "Vector3"
			or valueType == "CFrame"
			or valueType == "Color3"
			or valueType == "EnumItem"
		then
			return cleanText(tostring(value), "nil", 72)
		end
		return "<" .. valueType .. ">"
	end
	local function append(value, prefix, depth, sectionStart)
		if #lines >= maximumLines or #lines - sectionStart >= maximumSectionLines then
			return
		end
		if type(value) ~= "table" or depth >= 4 then
			table.insert(lines, cleanText(prefix .. debugScalar(value), "nil", 72))
			return
		end
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, { key = key, name = tostring(key) })
		end
		table.sort(keys, function(left, right)
			return left.name < right.name
		end)
		if #keys == 0 then
			table.insert(lines, prefix .. "{}")
			return
		end
		for _, item in ipairs(keys) do
			append(value[item.key], prefix .. item.name .. ": ", depth + 1, sectionStart)
			if #lines >= maximumLines or #lines - sectionStart >= maximumSectionLines then
				return
			end
		end
	end
	local source = type(snapshot) == "table" and snapshot or {}
	local runtime = {
		version = source.version,
		generation = source.generation,
		state = source.state,
		owner = source.owner,
		epoch = source.epoch,
		startedAt = source.startedAt,
		updatedAt = source.updatedAt,
		activeTasks = source.activeTasks,
		activeConnections = source.activeConnections,
		inputCaptured = source.inputCaptured,
		exportOwned = source.exportOwned,
		lastCourse = source.lastCourse,
		menu = {
			busy = self._busy,
			busyAction = self._busyAction,
			stale = self._stale,
			page = self._activePage,
			connections = #self._connections,
		},
	}
	local environment = {
		placeSupported = source.placeSupported,
		characterState = source.characterState,
		traceState = source.traceState,
		traceFileName = cleanBasename(source.traceFileName),
		executorName = source.executorName,
		executorVersion = source.executorVersion,
	}
	local sections = {
		{ "Runtime", runtime },
		{ "Environment", environment },
		{ "Session", source.session },
		{ "Stage 1", source.stage1 },
		{ "Stage 2", source.stage2 },
		{ "Stage 3", source.stage3 },
		{ "Stage 4", source.stage4 },
		{ "Stage 5", source.stage5 },
		{ "Stage 6", source.stage6 },
		{ "Stage 7", source.stage7 },
		{ "Stage 8", source.stage8 },
		{ "Stage 9", source.stage9 },
		{ "Movement", source.movement },
		{ "Motion probe", source.motionProbe },
		{ "Event collectors", source.events },
		{ "Last command", source.lastCommand },
		{ "Last event", source.lastEvent },
		{ "Last error", source.lastError },
		{ "Local error", self._localErrorCode },
		{ "Last observation", source.lastObservation },
	}
	for _, section in ipairs(sections) do
		if #lines >= maximumLines then
			break
		end
		table.insert(lines, section[1])
		local sectionStart = #lines
		append(section[2], "  ", 0, sectionStart)
		if #lines - sectionStart >= maximumSectionLines then
			table.insert(lines, "  … section truncated")
		end
	end
	if #lines >= maximumLines then
		lines[maximumLines] = "… diagnostics truncated"
	end
	self._debugText.Text = table.concat(lines, "\n")
	local height = math.max(20, #lines * 14)
	self._debugText.Size = UDim2.new(1, -8, 0, height)
	self._debugBody.CanvasSize = UDim2.fromOffset(0, height + 8)
	self._debugVisualDirty = false
end

function Menu:_reconcileEventConfig(snapshot)
	local owner = type(snapshot) == "table" and snapshot.owner or nil
	local events = type(snapshot) == "table" and type(snapshot.events) == "table" and snapshot.events or {}
	local externalConfig = events.config
	if
		owner ~= "events"
		or self._busy
		or self._eventConfigDirty
		or type(externalConfig) ~= "table"
		or type(externalConfig.retry) ~= "table"
	then
		return
	end
	for _, kind in ipairs(self._eventConfigKeys) do
		if type(externalConfig[kind]) == "boolean" then
			self._eventConfig[kind] = externalConfig[kind]
		end
		local retry = externalConfig.retry[kind]
		if type(retry) == "number" and retry >= 0.5 and retry <= 10 then
			self._eventConfig.retry[kind] = retry
		end
	end
	if type(externalConfig.summerOnlyStorm) == "boolean" then
		self._eventConfig.summerOnlyStorm = externalConfig.summerOnlyStorm
	end
end

function Menu:_updateEventControls(snapshot)
	local state = type(snapshot) == "table" and snapshot.state or nil
	local owner = type(snapshot) == "table" and snapshot.owner or nil
	local enabled = not self._stale
		and not self._busy
		and state == "idle"
		and snapshot.placeSupported == true
		and snapshot.characterState == "READY"
		and snapshot.traceState == "READY"
		and (owner == nil or owner == "events")
	for kind, item in pairs(self._eventButtons) do
		setSwitch(item.switch, self._eventConfig[kind] == true, enabled)
	end
	local stormSelected = self._eventConfig.summerOnlyStorm == true
	self._stormButton.Active = true
	local gearSelected = self._summerSettingsOpen or stormSelected
	self._stormButton.BackgroundColor3 = gearSelected and TOKENS.activeButton or TOKENS.button
	self._stormButton.TextColor3 = TOKENS.text
	self._stormStroke.Color = gearSelected and TOKENS.accent or TOKENS.border
	self._summerSettingsPopover.Visible = self._summerSettingsOpen
	if self._summerSettingsStroke then
		self._summerSettingsStroke.Color = TOKENS.borderSoft
		self._summerSettingsStroke.Transparency = 0.86
	end
	setSwitch(self._summerStormSwitch, stormSelected, enabled)
end

function Menu:_dispatchEvents(previousConfig)
	local snapshot = self._lastSnapshot
	local state = type(snapshot) == "table" and snapshot.state or nil
	local owner = type(snapshot) == "table" and snapshot.owner or nil
	if
		type(snapshot) ~= "table"
		or self._stale
		or self._busy
		or state ~= "idle"
		or snapshot.placeSupported ~= true
		or snapshot.characterState ~= "READY"
		or snapshot.traceState ~= "READY"
		or (owner ~= nil and owner ~= "events")
	then
		if type(previousConfig) == "table" then
			self._eventConfig = previousConfig
			self:_updateEventControls(snapshot)
		end
		return
	end
	local nextConfig = cloneEventConfig(self._eventConfig)
	local anyEnabled = false
	for _, kind in ipairs({
		"summer",
		"battle",
		"egg",
		"disco",
		"soccer",
		"rings",
		"masked",
		"overdrive",
		"fab",
		"survival",
	}) do
		anyEnabled = anyEnabled or nextConfig[kind] == true
	end
	self._busy = true
	self._busyAction = "events"
	self:_updateControls(snapshot)
	task.spawn(function()
		local called, ok, _, eventError
		if not anyEnabled and owner == "events" then
			called, ok, _, eventError = pcall(self._command, "stop", { reason = "ui_stop" })
		elseif owner == "events" then
			called, ok, _, eventError = pcall(self._configureCollectors, nextConfig)
		elseif anyEnabled then
			called, ok, _, eventError = pcall(self._startCollectors, nextConfig)
		else
			called, ok = true, true
		end
		if self._destroyed then
			return
		end
		self._busy = false
		self._busyAction = nil
		if not called or ok ~= true then
			if type(previousConfig) == "table" then
				self._eventConfig = previousConfig
				self._eventConfigDirty = false
			end
			self._localErrorCode = type(eventError) == "table" and cleanCode(eventError.code, "events_update_failed")
				or "events_update_failed"
		else
			if anyEnabled or owner == "events" then
				self._eventConfigDirty = false
			end
			self._localErrorCode = nil
		end
		self:_refresh(true)
	end)
end

function Menu:_toggleEvent(kind)
	if self._eventConfig[kind] == nil then
		return
	end
	local previousConfig = cloneEventConfig(self._eventConfig)
	self._eventConfig[kind] = not self._eventConfig[kind]
	self:_dispatchEvents(previousConfig)
end

function Menu:_updateControls(snapshot)
	if not self._stageActionSwitches or not self._stopButton or not self._ejectButton then
		return
	end
	local state = type(snapshot) == "table" and snapshot.state or nil
	local owner = type(snapshot) == "table" and snapshot.owner or nil
	local hasOwner = owner ~= nil
	local stage1 = type(snapshot) == "table" and type(snapshot.stage1) == "table" and snapshot.stage1 or {}
	local fresh = not self._stale and state ~= nil
	local runEnabled = fresh
		and state == "idle"
		and not hasOwner
		and snapshot.activeTasks == 0
		and not self._busy
		and snapshot.placeSupported == true
		and snapshot.characterState == "READY"
		and snapshot.traceState == "READY"
	local active = {
		stage1auto = self._busyAction == "run_auto" or owner == "stage1" and stage1.mode == "pulse",
	}
	for stage = 2, 8 do
		local key = "stage" .. stage
		local stopping = self._stageLoopStoppingKey == key
		active[key] = not stopping and (self._busyAction == "run_" .. key or owner == key or self._stageLoopKey == key)
	end
	local hasSelectedStage = self._stageLoopKey ~= nil or self._stageLoopStoppingKey ~= nil or active.stage1auto
	for key, switch in pairs(self._stageActionSwitches) do
		local selected = active[key]
		local stopping = self._stageLoopStoppingKey == key
		setSwitch(
			switch,
			selected,
			not stopping and not self._busy and (selected or (not hasSelectedStage and runEnabled))
		)
	end
	setSwitch(self._debugSwitch, self._debugVisible, not self._destroying)
	local stopEnabled = fresh
		and hasOwner
		and not self._busy
		and state ~= "ejecting"
		and state ~= "error"
		and state ~= "ejected"
	self._stopButton.Active = stopEnabled
	self._stopButton.Text = self._busyAction == "stop" and "Stopping…" or "Stop Current Automation"
	self._stopButton.BackgroundColor3 = stopEnabled and TOKENS.surfaceRaised or TOKENS.surface
	self._stopButton.TextColor3 = stopEnabled and TOKENS.text or TOKENS.disabled
	self._stopStroke.Color = stopEnabled and TOKENS.border or TOKENS.surfaceRaised
	local ejectEnabled = fresh and not self._busy and state ~= "ejecting" and state ~= "ejected"
	self._ejectButton.Active = ejectEnabled
	self._ejectButton.Text = self._busyAction == "eject"
		or state == "ejecting" and "Ejecting…"
		or state == "error" and (self._armedAt and "Confirm Retry" or "Retry Eject")
		or self._armedAt and "Confirm Eject"
		or state == "ejected" and "Ejected"
		or "Eject"
	self._ejectButton.BackgroundColor3 = self._armedAt and TOKENS.activeButton or TOKENS.surfaceRaised
	self._ejectButton.TextColor3 = self._armedAt and TOKENS.text or (ejectEnabled and TOKENS.text or TOKENS.disabled)
end
function Menu:_render(snapshot, stale)
	if self._destroyed or not self._window then
		return
	end
	if type(snapshot) ~= "table" then
		self._eventStatusLabel.Text = "Snapshot unavailable · events cannot start"
		self._eventStatusLabel.TextColor3 = TOKENS.warning
		self:_updateControls(nil)
		self:_updateEventControls(nil)
		self:_renderDebug(nil)
		return
	end
	local events = type(snapshot.events) == "table" and snapshot.events or {}
	local eventsStatus = cleanText(events.status, "idle", 48)
	local eventCounts = type(events.counts) == "table" and events.counts or {}
	local eventTotal = type(events.total) == "number" and events.total or eventCounts.total or 0
	self._eventStatusLabel.Text = string.format(
		"Events · %s · %s collected · %s",
		string.upper(eventsStatus),
		cleanText(eventTotal, "0", 12),
		cleanText(events.variant or events.current, "waiting", 24)
	)
	self._eventStatusLabel.TextColor3 = stale and TOKENS.warning
		or (eventsStatus == "error" and TOKENS.danger)
		or TOKENS.muted
	self:_updateControls(snapshot)
	self:_updateEventControls(snapshot)
	self:_renderDebug(snapshot)
end

function Menu:_projectVisuals()
	self:_render(self._lastSnapshot, self._stale)
	self:_fitWindow()
	if self._debugVisible then
		self:_fitDebugWindow()
	end
end

function Menu:_refresh(force)
	if self._destroyed or self._destroying then
		return
	end
	if not force and self._refreshElapsed < TOKENS.refreshInterval then
		return
	end
	self._refreshElapsed = 0

	local ok, snapshot = pcall(self._snapshot)
	if ok and type(snapshot) == "table" then
		self._lastSnapshot = snapshot
		self._stale = false
	else
		self._stale = true
	end
	self:_reconcileEventConfig(self._lastSnapshot)
	self:_reconcileStageLoop()
	if self:_isFullyHidden() then
		self._debugVisualDirty = true
		return
	end
	self:_projectVisuals()
end

function Menu:_clearStageLoop()
	self._stageLoopKey = nil
	self._stageLoopStarted = false
	self._stageLoopStoppingKey = nil
end

function Menu:_toggleStageLoop(stageKey)
	if self._stageLoopKey == stageKey then
		self:_clearStageLoop()
		self._stageLoopStoppingKey = stageKey
		if self._lastSnapshot and self._lastSnapshot.owner == stageKey then
			self:_dispatchStop(true)
		else
			self._stageLoopStoppingKey = nil
			self:_updateControls(self._lastSnapshot)
		end
		return
	end
	if self._stageLoopKey ~= nil then
		return
	end
	self._stageLoopKey = stageKey
	self._stageLoopStoppingKey = nil
	self._stageLoopStarted = false
	self:_reconcileStageLoop()
	self:_updateControls(self._lastSnapshot)
end

function Menu:_reconcileStageLoop()
	local stageKey = self._stageLoopKey
	local snapshot = self._lastSnapshot
	if not stageKey or self._destroyed or self._destroying or type(snapshot) ~= "table" then
		return
	end
	if self._stale then
		return
	end
	local state = snapshot.state
	local owner = snapshot.owner
	if state == "error" or state == "ejecting" or state == "ejected" then
		self:_clearStageLoop()
		return
	end
	if owner ~= nil and owner ~= stageKey then
		return
	end
	local routeSnapshot = snapshot[stageKey]
	if self._stageLoopStarted and type(routeSnapshot) == "table" then
		if routeSnapshot.status == "error" then
			self:_clearStageLoop()
			self._localErrorCode = cleanCode(routeSnapshot.lastError, stageKey .. "_loop_failed")
			self:_updateControls(snapshot)
			return
		end
		if
			routeSnapshot.status == "completed"
			or routeSnapshot.status == "stopped"
			or routeSnapshot.status == "idle"
		then
			self._stageLoopStarted = false
		else
			return
		end
	end
	if
		self._busy
		or owner ~= nil
		or state ~= "idle"
		or snapshot.activeTasks ~= 0
		or snapshot.placeSupported ~= true
		or snapshot.characterState ~= "READY"
		or snapshot.traceState ~= "READY"
	then
		return
	end
	self._stageLoopStarted = true
	self:_dispatchStageOnce(stageKey)
end

function Menu:_dispatchRunAuto()
	if self._stageLoopKey ~= nil then
		return
	end
	self:_disarm()
	local snapshot = self._lastSnapshot
	local state = type(snapshot) == "table" and snapshot.state or nil
	local hasOwner = type(snapshot) == "table" and snapshot.owner ~= nil
	if
		self._stale
		or self._busy
		or state ~= "idle"
		or hasOwner
		or snapshot.activeTasks ~= 0
		or snapshot.placeSupported ~= true
		or snapshot.characterState ~= "READY"
		or snapshot.traceState ~= "READY"
	then
		return
	end

	self._busy = true
	self._busyAction = "run_auto"
	self:_updateControls(snapshot)
	task.spawn(function()
		local called, ok, _, runError = pcall(self._runStage1Auto)
		if self._destroyed then
			return
		end
		self._busy = false
		self._busyAction = nil
		if not called or ok ~= true then
			self._localErrorCode = type(runError) == "table" and cleanCode(runError.code, "stage1_start_failed")
				or "stage1_start_failed"
		else
			self._localErrorCode = nil
		end
		self:_refresh(true)
	end)
end

function Menu:_dispatchStageOnce(stageKey)
	if
		stageKey ~= "stage2"
		and stageKey ~= "stage3"
		and stageKey ~= "stage4"
		and stageKey ~= "stage5"
		and stageKey ~= "stage6"
		and stageKey ~= "stage7"
		and stageKey ~= "stage8"
		and stageKey ~= "stage9"
	then
		return
	end

	self:_disarm()
	local snapshot = self._lastSnapshot
	local state = type(snapshot) == "table" and snapshot.state or nil
	local hasOwner = type(snapshot) == "table" and snapshot.owner ~= nil
	if
		self._stale
		or self._busy
		or state ~= "idle"
		or hasOwner
		or snapshot.activeTasks ~= 0
		or snapshot.placeSupported ~= true
		or snapshot.characterState ~= "READY"
		or snapshot.traceState ~= "READY"
	then
		return
	end

	self._busy = true
	self._busyAction = "run_" .. stageKey
	self:_updateControls(snapshot)
	task.spawn(function()
		local called, ok, _, runError = pcall(self._runStageOnce, stageKey)
		if self._destroyed then
			return
		end
		self._busy = false
		self._busyAction = nil
		local fallbackCode = stageKey .. "_start_failed"
		if not called or ok ~= true then
			if self._stageLoopKey == stageKey then
				self:_clearStageLoop()
			end
			self._localErrorCode = type(runError) == "table" and cleanCode(runError.code, fallbackCode) or fallbackCode
		else
			self._localErrorCode = nil
		end
		self:_refresh(true)
	end)
end

function Menu:_dispatchStop(preserveStopping)
	self:_disarm()
	local stoppingKey = preserveStopping and self._stageLoopStoppingKey or nil
	self:_clearStageLoop()
	self._stageLoopStoppingKey = stoppingKey
	local snapshot = self._lastSnapshot
	local state = type(snapshot) == "table" and snapshot.state or nil
	local hasOwner = type(snapshot) == "table" and snapshot.owner ~= nil
	if self._stale or self._busy or not hasOwner or state == "ejecting" or state == "error" or state == "ejected" then
		return
	end

	self._busy = true
	self._busyAction = "stop"
	self:_updateControls(snapshot)
	local called, ok = pcall(self._command, "stop", { reason = "ui_stop" })
	self._busy = false
	self._busyAction = nil
	self._stageLoopStoppingKey = nil
	if not called or ok ~= true then
		self._localErrorCode = "command_failed"
	end
	self:_refresh(true)
end

function Menu:_dispatchEject()
	self:_clearStageLoop()
	self._stageLoopStoppingKey = nil
	if self._busy then
		return
	end

	self._busy = true
	self._busyAction = "eject"
	self._armedAt = nil
	self:_updateControls(self._lastSnapshot)
	local called, ok = pcall(self._command, "eject", { reason = "ui_eject" })
	if self._destroyed then
		return
	end

	self._busy = false
	self._busyAction = nil
	if not called or ok ~= true then
		self._localErrorCode = "eject_failed"
	end
	self:_refresh(true)
end

function Menu:_handleEjectActivation()
	local snapshot = self._lastSnapshot
	local state = type(snapshot) == "table" and snapshot.state or nil
	if self._stale or self._busy or state == "ejecting" or state == "ejected" then
		return
	end

	local now = os.clock()
	if not self._armedAt then
		self._armedAt = now
		self:_updateControls(snapshot)
		return
	end

	local elapsed = now - self._armedAt
	if elapsed < TOKENS.armMinimum then
		return
	end
	if elapsed > TOKENS.armMaximum then
		self:_disarm()
		return
	end
	self:_dispatchEject()
end

function Menu:_wire()
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	for _, pageKey in ipairs(self._pageOrder) do
		local selectedPage = pageKey
		local item = self._navButtons[selectedPage]
		local connected, connectionError = self:_connect("page-" .. selectedPage, item.button.Activated, function()
			self:_selectPage(selectedPage)
		end)
		if not connected then
			return nil, connectionError
		end
	end
	local function wirePanelSwitch(prefix, key, switch)
		for _, definition in ipairs({
			{ "hover-enter", switch.button.MouseEnter, "hovered", true },
			{ "hover-leave", switch.button.MouseLeave, "hovered", false },
			{ "focus-enter", switch.button.SelectionGained, "focused", true },
			{ "focus-leave", switch.button.SelectionLost, "focused", false },
		}) do
			local role = prefix .. "-" .. definition[1] .. "-" .. key
			local signal = definition[2]
			local field = definition[3]
			local value = definition[4]
			local connected, connectionError = self:_connect(role, signal, function()
				switch[field] = value
				updatePanelSwitchChrome(switch)
			end)
			if not connected then
				return nil, connectionError
			end
		end
		return true
	end
	for _, key in ipairs(self._stageDisplayOrder) do
		local connected, connectionError = wirePanelSwitch("stage", key, self._stageActionSwitches[key])
		if not connected then
			return nil, connectionError
		end
	end
	for _, key in ipairs(self._eventDisplayOrder) do
		local connected, connectionError = wirePanelSwitch("event", key, self._eventButtons[key].switch)
		if not connected then
			return nil, connectionError
		end
	end

	local roles = {
		{
			"heartbeat",
			RunService.Heartbeat,
			function(deltaTime)
				self._refreshElapsed += math.min(deltaTime, TOKENS.refreshInterval)
				if self._armedAt and os.clock() - self._armedAt > TOKENS.armMaximum then
					self:_disarm()
				end
				self:_refresh(false)
			end,
		},
		{
			"stage1-auto",
			self._stageActionSwitches.stage1auto.button.Activated,
			function()
				local stage1 = type(self._lastSnapshot) == "table" and self._lastSnapshot.stage1 or {}
				if self._lastSnapshot and self._lastSnapshot.owner == "stage1" and stage1.mode == "pulse" then
					self:_dispatchStop()
				else
					self:_dispatchRunAuto()
				end
			end,
		},
		{
			"stage2-loop",
			self._stageActionSwitches.stage2.button.Activated,
			function()
				self:_toggleStageLoop("stage2")
			end,
		},
		{
			"stage3-loop",
			self._stageActionSwitches.stage3.button.Activated,
			function()
				self:_toggleStageLoop("stage3")
			end,
		},
		{
			"stage4-loop",
			self._stageActionSwitches.stage4.button.Activated,
			function()
				self:_toggleStageLoop("stage4")
			end,
		},
		{
			"stage5-loop",
			self._stageActionSwitches.stage5.button.Activated,
			function()
				self:_toggleStageLoop("stage5")
			end,
		},
		{
			"stage6-loop",
			self._stageActionSwitches.stage6.button.Activated,
			function()
				self:_toggleStageLoop("stage6")
			end,
		},
		{
			"event-summer",
			self._eventButtons.summer.button.Activated,
			function()
				self:_toggleEvent("summer")
			end,
		},
		{
			"event-battle",
			self._eventButtons.battle.button.Activated,
			function()
				self:_toggleEvent("battle")
			end,
		},
		{
			"event-disco",
			self._eventButtons.disco.button.Activated,
			function()
				self:_toggleEvent("disco")
			end,
		},
		{
			"event-rings",
			self._eventButtons.rings.button.Activated,
			function()
				self:_toggleEvent("rings")
			end,
		},
		{
			"event-masked",
			self._eventButtons.masked.button.Activated,
			function()
				self:_toggleEvent("masked")
			end,
		},
		{
			"event-overdrive",
			self._eventButtons.overdrive.button.Activated,
			function()
				self:_toggleEvent("overdrive")
			end,
		},
		{
			"event-fab",
			self._eventButtons.fab.button.Activated,
			function()
				self:_toggleEvent("fab")
			end,
		},
		{
			"event-survival",
			self._eventButtons.survival.button.Activated,
			function()
				self:_toggleEvent("survival")
			end,
		},
		{
			"event-egg",
			self._eventButtons.egg.button.Activated,
			function()
				self:_toggleEvent("egg")
			end,
		},
		{
			"summer-storm-gear",
			self._stormButton.Activated,
			function()
				self._summerSettingsOpen = not self._summerSettingsOpen
				self:_updateEventControls(self._lastSnapshot)
			end,
		},
		{
			"summer-settings-close",
			self._summerSettingsCloseButton.Activated,
			function()
				self._summerSettingsOpen = false
				self:_updateEventControls(self._lastSnapshot)
			end,
		},
		{
			"summer-storm-only",
			self._summerStormSwitch.button.Activated,
			function()
				local previousConfig = cloneEventConfig(self._eventConfig)
				self._eventConfig.summerOnlyStorm = not self._eventConfig.summerOnlyStorm
				self._eventConfigDirty = true
				self:_dispatchEvents(previousConfig)
			end,
		},
		{
			"stage7-loop",
			self._stageActionSwitches.stage7.button.Activated,
			function()
				self:_toggleStageLoop("stage7")
			end,
		},
		{
			"stage8-loop",
			self._stageActionSwitches.stage8.button.Activated,
			function()
				self:_toggleStageLoop("stage8")
			end,
		},
		{
			"stage9-loop",
			self._stageActionSwitches.stage9.button.Activated,
			function()
				self:_toggleStageLoop("stage9")
			end,
		},
		{
			"stop",
			self._stopButton.Activated,
			function()
				self:_dispatchStop()
			end,
		},
		{
			"eject",
			self._ejectButton.Activated,
			function()
				self:_handleEjectActivation()
			end,
		},
		{
			"debug-menu",
			self._debugButton.Activated,
			function()
				self:_setDebugVisible(not self._debugVisible)
				self:_updateControls(self._lastSnapshot)
			end,
		},
		{
			"debug-close",
			self._debugCloseButton.Activated,
			function()
				self:_setDebugVisible(false)
				self:_updateControls(self._lastSnapshot)
			end,
		},
		{
			"debug-drag-begin",
			self._debugHeader.InputBegan,
			function(input)
				if isPointerInput(input) then
					local point = input.Position
					local closePosition = self._debugCloseButton.AbsolutePosition
					local closeSize = self._debugCloseButton.AbsoluteSize
					if
						point.X >= closePosition.X
						and point.X <= closePosition.X + closeSize.X
						and point.Y >= closePosition.Y
						and point.Y <= closePosition.Y + closeSize.Y
					then
						return
					end
					self._debugDragInput = input
					self._debugDragOrigin = Vector2.new(point.X, point.Y)
					self._debugWindowOrigin =
						Vector2.new(self._debugWindow.Position.X.Offset, self._debugWindow.Position.Y.Offset)
				end
			end,
		},
		{
			"debug-drag-change",
			UserInputService.InputChanged,
			function(input)
				if not self._debugDragInput or not self._debugDragOrigin or not self._debugWindowOrigin then
					return
				end
				local isTouch = self._debugDragInput.UserInputType == Enum.UserInputType.Touch
					and input == self._debugDragInput
				local isMouse = self._debugDragInput.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement
				if not isTouch and not isMouse then
					return
				end
				local viewport = self:_viewportSize()
				local size = self._debugWindow.AbsoluteSize
				local margin = TOKENS.viewportMargin
				local delta = Vector2.new(input.Position.X, input.Position.Y) - self._debugDragOrigin
				self._debugWindow.Position = UDim2.fromOffset(
					math.clamp(
						self._debugWindowOrigin.X + delta.X,
						margin,
						math.max(margin, viewport.X - size.X - margin)
					),
					math.clamp(
						self._debugWindowOrigin.Y + delta.Y,
						margin,
						math.max(margin, viewport.Y - size.Y - margin)
					)
				)
			end,
		},
		{
			"debug-drag-end",
			UserInputService.InputEnded,
			function(input)
				if
					input == self._debugDragInput
					or (
						self._debugDragInput
						and self._debugDragInput.UserInputType == Enum.UserInputType.MouseButton1
						and input.UserInputType == Enum.UserInputType.MouseButton1
					)
				then
					self._debugDragInput = nil
					self._debugDragOrigin = nil
					self._debugWindowOrigin = nil
				end
			end,
		},
		{
			"drag-begin",
			self._header.InputBegan,
			function(input)
				if not isPointerInput(input) or self._busy then
					return
				end
				local point = input.Position
				self:_disarm()
				self._dragInput = input
				self._dragOrigin = Vector2.new(point.X, point.Y)
				self._windowOrigin = Vector2.new(self._window.Position.X.Offset, self._window.Position.Y.Offset)
			end,
		},
		{
			"drag-change",
			UserInputService.InputChanged,
			function(input)
				if not self._dragInput or not self._dragOrigin or not self._windowOrigin then
					return
				end
				local isTouch = self._dragInput.UserInputType == Enum.UserInputType.Touch and input == self._dragInput
				local isMouse = self._dragInput.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement
				if not isTouch and not isMouse then
					return
				end
				local viewport = self:_viewportSize()
				local size = self._window.AbsoluteSize
				local margin = TOKENS.viewportMargin
				local delta = Vector2.new(input.Position.X, input.Position.Y) - self._dragOrigin
				local x =
					math.clamp(self._windowOrigin.X + delta.X, margin, math.max(margin, viewport.X - size.X - margin))
				local y =
					math.clamp(self._windowOrigin.Y + delta.Y, margin, math.max(margin, viewport.Y - size.Y - margin))
				self._window.Position = UDim2.fromOffset(x, y)
				self._menuRestPosition = self._window.Position
			end,
		},
		{
			"drag-end",
			UserInputService.InputEnded,
			function(input)
				if not self._dragInput then
					return
				end
				local endsTouch = input == self._dragInput
				local endsMouse = self._dragInput.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseButton1
				if endsTouch or endsMouse then
					self._dragInput = nil
					self._dragOrigin = nil
					self._windowOrigin = nil
				end
			end,
		},
		{
			"keyboard",
			UserInputService.InputBegan,
			function(input, gameProcessed)
				if input.KeyCode == Enum.KeyCode.Escape then
					self:_disarm()
				elseif
					input.KeyCode == Enum.KeyCode.Delete
					and not gameProcessed
					and UserInputService:GetFocusedTextBox() == nil
				then
					self:_setMenuVisible(not self._menuVisible, false)
				end
			end,
		},
		{
			"focus-loss",
			UserInputService.WindowFocusReleased,
			function()
				self:_disarm()
				self._dragInput = nil
				self._dragOrigin = nil
				self._windowOrigin = nil
				self._debugDragInput = nil
				self._debugDragOrigin = nil
				self._debugWindowOrigin = nil
			end,
		},
	}

	for _, definition in ipairs(roles) do
		local ok, err = self:_connect(definition[1], definition[2], definition[3])
		if not ok then
			return nil, err
		end
	end
	return true
end

function Menu:Show()
	if self._destroyed then
		return nil, fixedError("menu_destroyed", "Menu was already destroyed")
	end
	if self._shown then
		return true
	end

	local parentOk, parent = pcall(gethui)
	if not parentOk or parent == nil then
		return nil, fixedError("menu_parent_failed", "Hidden UI container is unavailable")
	end

	local shownOk = pcall(function()
		self._screen.Parent = parent
	end)
	if not shownOk then
		return nil, fixedError("menu_parent_failed", "Menu could not be shown")
	end

	self:_centerWindow()
	local wired, wireError = self:_wire()
	if not wired then
		self:Destroy()
		return nil, wireError
	end
	self._shown = true
	self:_setMenuVisible(true, false)
	return true
end

function Menu:stats()
	return {
		connections = #self._connections,
	}
end

function Menu:Destroy()
	if self._destroyed then
		return true
	end
	if self._destroying then
		return nil, fixedError("menu_destroy_busy", "Menu cleanup is already running")
	end

	self._destroying = true
	self._busy = true
	self:_clearStageLoop()
	self._stageLoopStoppingKey = nil
	self._summerSettingsOpen = false
	if self._summerSettingsPopover then
		self._summerSettingsPopover.Visible = false
	end
	self._busyAction = "eject"
	self._armedAt = nil
	self._dragInput = nil
	self._dragOrigin = nil
	self._windowOrigin = nil
	self._debugDragInput = nil
	self._debugDragOrigin = nil
	self._debugWindowOrigin = nil
	self:_setDebugVisible(false)
	self:_cancelVisibilityTweens()
	self:_cancelPageTransitions()
	for _, tween in ipairs(self._patternTweens) do
		pcall(tween.Cancel, tween)
	end
	self._patternAnimationActive = false

	local failures = {}
	local remaining = {}
	for _, item in ipairs(self._connections) do
		local disconnected = pcall(function()
			item.connection:Disconnect()
		end)
		if disconnected then
			-- Successfully disconnected connections are deliberately omitted.
		else
			table.insert(remaining, item)
			table.insert(failures, cleanupFailure(item.role, "disconnect_failed", "Signal disconnect failed"))
		end
	end
	self._connections = remaining

	if #failures == 0 and self._screen then
		local destroyed = pcall(function()
			self._screen:Destroy()
		end)
		if not destroyed then
			table.insert(failures, cleanupFailure("screen", "destroy_failed", "ScreenGui destruction failed"))
		else
			self._screen = nil
			self._window = nil
			self._debugWindow = nil
			self._debugHeader = nil
			self._debugBody = nil
			self._debugText = nil
			table.clear(self._patternTweens)
			self._patterns = nil
			self._navigationPattern = nil
			self._headerPattern = nil
			self._mainPattern = nil
			table.clear(self._pageTransitionTweens)
		end
	end

	if #failures > 0 then
		self._destroying = false
		self._busy = false
		self._busyAction = nil
		if not self._reducedMotion then
			for _, tween in ipairs(self._patternTweens) do
				pcall(tween.Play, tween)
			end
			self._patternAnimationActive = not self._reducedMotion and #self._patternTweens > 0
		end
		self._shown = self._screen ~= nil and self._screen.Parent ~= nil
		local rewired, wireError = self:_wire()
		if not rewired then
			table.insert(failures, cleanupFailure("signals", "reconnect_failed", wireError.message))
		end
		self._localErrorCode = "eject_failed"
		self:_refresh(true)
		return nil,
			{
				code = "menu_destroy_failed",
				message = "Menu cleanup did not complete",
				cleanupErrors = failures,
			}
	end

	self._destroying = false
	self._destroyed = true
	self._shown = false
	self._busy = false
	self._busyAction = nil
	self._snapshot = nil
	self._runStage1Auto = nil
	self._runStageOnce = nil
	self._command = nil
	self._startCollectors = nil
	self._configureCollectors = nil
	self._lastSnapshot = nil
	return true
end

return Menu
