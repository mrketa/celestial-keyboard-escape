--!strict

local Menu = {}

local REQUIRED_METHODS = {
	"Snapshot",
	"SetWinStrategies",
	"SetAutoWins",
	"SetGodMode",
	"SetRemoveObstacles",
	"SetAutoRebirth",
	"SetAutoBuyTrails",
	"SetAutoBuyAuras",
	"SetAutoBuyItems",
	"SetItemVariants",
	"SetAutoKeys",
	"SetKeyKinds",
	"SetAutoFuse",
	"SetAutoEquipItems",
	"SetAutoGloveBattle",
	"SetAutoEquipTrails",
	"SetAutoEquipAuras",
	"SetFuseItems",
	"SetAdminEventKinds",
	"SetAutoAdminEvents",
	"Destroy",
}

local STRATEGIES = { "Stage 1 (Instant TP)", "Max Stage" }
local KEY_KINDS = { "Gold Key", "Secret Key" }

local SESSION_METRICS = {
	{ method = "SetAutoWins", key = "autoWins", flag = "autoWins", counter = "wins", verb = "Gained", resource = "Wins" },
	{ method = "SetAutoAdminEvents", key = "adminEvents", flag = "autoAdminEvents", counter = "wins", verb = "Gained", resource = "Wins" },
	{ method = "SetAutoRebirth", key = "rebirths", flag = "autoRebirth", counter = "rebirths", verb = "Gained", resource = "Rebirths" },
	{ method = "SetAutoKeys", key = "keys", flag = "autoKeys", counter = "keysCollected", verb = "Collected", resource = "Keys" },
	{ method = "SetAutoFuse", key = "fuses", flag = "autoFuse", counter = "fusesCompleted", verb = "Completed", resource = "Fuses" },
	{ method = "SetAutoGloveBattle", key = "gloves", flag = "autoGloveBattle", counter = "gloveActivations", verb = "Triggered", resource = "Glove activations" },
}

local function merge(base: { [any]: any }, override: { [any]: any }?): { [any]: any }
	local result = {}
	for key, value in pairs(base) do result[key] = value end
	for key, value in pairs(override or {}) do result[key] = value end
	return result
end

local function copyArray(values: any): { any }
	local result = {}
	if type(values) == "table" then
		for index, value in ipairs(values) do result[index] = value end
	end
	return result
end

local function sameArray(left: any, right: any): boolean
	if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
	for index, value in ipairs(left) do
		if right[index] ~= value then return false end
	end
	return true
end


function Menu.new(Library: any, controller: any, options: any?): (any?, any?)
	assert(type(Library) == "table" and type(Library.bootstrap) == "function", "Fluxcore 1.x with Library.bootstrap is required")
	assert(type(controller) == "table", "Keyboard Escape controller must be a table")
	assert(options == nil or type(options) == "table", "Keyboard Escape menu options must be a table")
	for _, method in ipairs(REQUIRED_METHODS) do
		assert(type(controller[method]) == "function", "Keyboard Escape controller is missing " .. method)
	end

	local input = options or {}
	assert(input.Library == nil or type(input.Library) == "table", "Library options must be a table")
	assert(input.Window == nil or type(input.Window) == "table", "Window options must be a table")
	local initial = controller:Snapshot()
	assert(type(initial) == "table", "Keyboard Escape Snapshot must return a table")

	local libraryOptions = merge({ Name = "KeyboardEscapePotassium" }, input.Library)
	local windowOptions = merge({ Id = "keyboard-escape", Title = "Keyboard Escape", StartOpen = true }, input.Window)
	libraryOptions.Name = "KeyboardEscapePotassium"
	windowOptions.Id = "keyboard-escape"
	windowOptions.Title = "Keyboard Escape"

	local ui, window, bootstrapError = Library.bootstrap({ Library = libraryOptions, Window = windowOptions })
	if ui == nil or window == nil then return nil, bootstrapError end

	local constructed, appOrError = xpcall(function()
		ui.ScreenGui.AutoLocalize = false
		local controls: { [string]: any } = {}
		local renderedValues: { [string]: any } = {}
		local app: any = {
			UI = ui,
			Window = window,
			Controller = controller,
			_destroyed = false,
			_pollGeneration = 0,
			_snapshot = initial,
			_refreshGeneration = 0,
			_minimizedStatusEnabled = input.ShowMinimizedStatus ~= false,
			_sessionBaselines = {},
		}

		local function setValue(control: any, key: string, value: any, force: boolean?)
			local nextValue = if type(value) == "table" then copyArray(value) else value
			local current = if type(control.Get) == "function" then control:Get() else control.Value
			local changed = if type(nextValue) == "table"
				then not sameArray(renderedValues[key], nextValue) or not sameArray(current, nextValue)
				else renderedValues[key] ~= nextValue or current ~= nextValue
			if force or changed then
				renderedValues[key] = if type(nextValue) == "table" then copyArray(nextValue) else nextValue
				if type(control.Set) == "function" then
					control:Set(nextValue, { Silent = true })
				else
					control:SetValue(nextValue)
				end
			end
		end

		local renderedChoices: { [string]: { any } } = {}
		local function setChoices(control: any, key: string, choices: any, force: boolean?)
			local nextChoices = copyArray(choices)
			if force or not sameArray(renderedChoices[key], nextChoices) then
				renderedChoices[key] = copyArray(nextChoices)
				control:SetChoices(nextChoices)
			end
		end
		local function invoke(method: string, ...: any): boolean
			local arguments = table.pack(...)
			local ok, result, detail = pcall(function()
				return controller[method](controller, table.unpack(arguments, 1, arguments.n))
			end)
			if app._destroyed then return false end
			if not ok then
				ui:Notify({ Title = "Keyboard Escape", Text = tostring(result), Type = "danger", Duration = 5 })
				return false
			end
			if result ~= true then
				ui:Notify({ Title = "Keyboard Escape", Text = tostring(detail or result or "The action was not accepted."), Type = "danger", Duration = 5 })
				return false
			end
			return true
		end

		local sessionGenerations: { [string]: number } = {}
		local function action(method: string, ...: any)
			if app._destroyed then return end
			local baselineKey: string? = nil
			local baselineGeneration = 0
			local baselineAmount: number? = nil
			local previousBaseline: number? = nil
			for _, metric in ipairs(SESSION_METRICS) do
				if metric.method == method then
					local generation = (sessionGenerations[metric.key] or 0) + 1
					sessionGenerations[metric.key] = generation
					if select(1, ...) == true then
						local ok, snapshot = pcall(function() return controller:Snapshot() end)
						if app._destroyed or sessionGenerations[metric.key] ~= generation then return end
						if ok and type(snapshot) == "table" and snapshot[metric.flag] ~= true then
							baselineKey = metric.key
							baselineGeneration = generation
							previousBaseline = app._sessionBaselines[metric.key]
							local amount = snapshot[metric.counter]
							baselineAmount = if type(amount) == "number" then amount else 0
							-- Workers may report their first gain before the setter returns.
							app._sessionBaselines[metric.key] = baselineAmount
						end
					end
					break
				end
			end
			local accepted = invoke(method, ...)
			if baselineKey ~= nil and sessionGenerations[baselineKey] == baselineGeneration then
				-- A poll may have cleared the seed while the setter awaited a worker.
				app._sessionBaselines[baselineKey] = if accepted then baselineAmount else previousBaseline
			end
			app:Refresh(true)
		end

		local automation = window:Tab({ Id = "automation", Title = "Automation", Icon = "automation" })
		local autoWins = automation:Section({ Id = "auto-wins", Title = "Auto Wins", Icon = "auto win", Side = "Left", Collapsible = false })
		controls.AutoWins = autoWins:Toggle({
			Id = "auto-wins",
			Title = "Auto Wins",
			Description = "World 3 uses checkpoints. Galaxy 2 / World 1 uses tweens; Stage 10 waits at SAS10, then teleports to SAS11.",
			Default = initial.autoWins == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoWins", value) end,
			Options = {
				Id = "win-strategies",
				Title = "Strategies",
				Description = "Run Stage 1 instantly or collect the highest supported stage unlocked by the current world's level gates.",
				Choices = copyArray(STRATEGIES),
				Default = copyArray(initial.winStrategies),
				MaxSelections = 1,
				Persist = false,
				Callback = function(value: { string }) action("SetWinStrategies", copyArray(value)) end,
			},
		})
		controls.WinStrategies = controls.AutoWins.Options

		local rebirth = automation:Section({ Id = "auto-rebirth", Title = "Auto Rebirth", Icon = "auto rebirth", Side = "Left", Collapsible = false })
		controls.AutoRebirth = rebirth:Toggle({
			Id = "auto-rebirth",
			Title = "Auto Rebirth",
			Description = "Rebirths only after the replicated player level reaches the next configured gate.",
			Default = initial.autoRebirth == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoRebirth", value) end,
		})

		local adminEvents = automation:Section({ Id = "admin-events", Title = "Admin Events", Icon = "admin events", Side = "Left", Collapsible = false })
		controls.AutoAdminEvents = adminEvents:Toggle({
			Id = "auto-admin-events",
			Title = "Auto Admin Events",
			Description = "Collects supported Admin Events remote-first; unresolved Summer Coins/EggRain are excluded.",
			Default = initial.autoAdminEvents == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoAdminEvents", value) end,
			Options = {
				Id = "admin-event-kinds",
				Title = "Event Kinds",
				Description = "Collects supported Admin Events remote-first; unresolved Summer Coins/EggRain are excluded.",
				Choices = copyArray(initial.adminEventChoices),
				Default = copyArray(initial.selectedAdminEvents),
				Persist = false,
				Callback = function(value: { string }) action("SetAdminEventKinds", copyArray(value)) end,
			},
		})
		controls.AdminEventKinds = controls.AutoAdminEvents.Options

		local autoKeys = automation:Section({ Id = "auto-keys", Title = "Auto Keys", Icon = "key", Side = "Right", Collapsible = false })
		controls.AutoKeys = autoKeys:Toggle({
			Id = "auto-keys",
			Title = "Auto Keys",
			Description = "Collects only the selected special key types by direct contact.",
			Default = initial.autoKeys == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoKeys", value) end,
			Options = {
				Id = "key-types",
				Title = "Key Types",
				Description = "Choose the special key types Auto Keys may collect.",
				Choices = copyArray(KEY_KINDS),
				Default = copyArray(initial.selectedKeyKinds),
				Persist = false,
				Callback = function(value: { string }) action("SetKeyKinds", copyArray(value)) end,
			},
		})
		controls.KeyTypes = controls.AutoKeys.Options

		local gloveBattle = automation:Section({ Id = "glove-battle", Title = "Glove Battle", Icon = "glove", Side = "Right", Collapsible = false })
		controls.AutoGloveBattle = gloveBattle:Toggle({
			Id = "auto-glove-battle",
			Title = "Auto Glove Battle",
			Description = "Equips the Battle Glove and engages only an active, supported Slap Battle session.",
			Default = initial.autoGloveBattle == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoGloveBattle", value) end,
		})

		local items = window:Tab({ Id = "items", Title = "Items", Icon = "box" })
		local autoBuyItems = items:Section({ Id = "auto-buy-items", Title = "Auto Buy Items", Icon = "shop", Side = "Left", Collapsible = false })
		controls.AutoBuyItems = autoBuyItems:Toggle({
			Id = "auto-buy-items",
			Title = "Items",
			Description = "Buys the highest affordable selected variant currently in stock with Wins only.",
			Default = initial.autoBuyItems == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoBuyItems", value) end,
			Options = {
				Id = "item-variants",
				Title = "Item Variants",
				Description = "Choose which shop rarities Auto Buy may purchase with Wins.",
				Choices = copyArray(initial.itemVariants),
				Default = copyArray(initial.selectedItemVariants),
				Persist = false,
				Callback = function(value: { string }) action("SetItemVariants", copyArray(value)) end,
			},
		})
		controls.ItemVariants = controls.AutoBuyItems.Options
		local autoFuse = items:Section({ Id = "auto-fuse", Title = "Auto Fuse", Icon = "fuse", Side = "Right", Collapsible = false })
		controls.AutoFuse = autoFuse:Toggle({
			Id = "auto-fuse",
			Title = "Auto Fuse",
			Description = "Fuses only selected, currently owned item groups after revalidating their exact identity.",
			Default = initial.autoFuse == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoFuse", value) end,
			Options = {
				Id = "fuse-items",
				Title = "Fuse Items",
				Description = "Choose owned item groups Auto Fuse may merge.",
				Choices = copyArray(initial.fuseChoices),
				Default = copyArray(initial.selectedFuseItems),
				Persist = false,
				Callback = function(value: { string }) action("SetFuseItems", copyArray(value)) end,
			},
		})
		controls.FuseItems = controls.AutoFuse.Options
		local equipItems = items:Section({ Id = "equip-items", Title = "Equip Best", Icon = "inventory", Side = "Left", Collapsible = false })
		controls.AutoEquipItems = equipItems:Toggle({
			Id = "auto-equip-items",
			Title = "Equip Best",
			Description = "Equips the best owned items across the available slots.",
			Default = initial.autoEquipItems == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoEquipItems", value) end,
		})

		local trails = window:Tab({ Id = "trails", Title = "Trails", Icon = "trail" })
		local autoBuyTrails = trails:Section({ Id = "auto-buy-trails", Title = "Auto Buy Trails", Icon = "shop", Side = "Left", Collapsible = false })
		controls.AutoBuyTrails = autoBuyTrails:Toggle({
			Id = "auto-buy-trails",
			Title = "Trails",
			Description = "Buys only the next unowned trail upgrade with Wins; it never skips ahead.",
			Default = initial.autoBuyTrails == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoBuyTrails", value) end,
		})
		local equipTrails = trails:Section({ Id = "equip-trails", Title = "Equip Best", Icon = "speed", Side = "Right", Collapsible = false })
		controls.AutoEquipTrails = equipTrails:Toggle({
			Id = "auto-equip-trails",
			Title = "Equip Best",
			Description = "Equips the best owned trail.",
			Default = initial.autoEquipTrails == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoEquipTrails", value) end,
		})

		local aura = window:Tab({ Id = "aura", Title = "Aura", Icon = "aura" })
		local autoBuyAuras = aura:Section({ Id = "auto-buy-auras", Title = "Auto Buy Auras", Icon = "shop", Side = "Left", Collapsible = false })
		controls.AutoBuyAuras = autoBuyAuras:Toggle({
			Id = "auto-buy-auras",
			Title = "Auras",
			Description = "Buys only the next unowned aura upgrade with Wins; it never skips ahead.",
			Default = initial.autoBuyAuras == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoBuyAuras", value) end,
		})
		local equipAuras = aura:Section({ Id = "equip-auras", Title = "Equip Best", Icon = "sun", Side = "Right", Collapsible = false })
		controls.AutoEquipAuras = equipAuras:Toggle({
			Id = "auto-equip-auras",
			Title = "Equip Best",
			Description = "Equips the best owned aura.",
			Default = initial.autoEquipAuras == true,
			Persist = false,
			Callback = function(value: boolean) action("SetAutoEquipAuras", value) end,
		})

		local settings = window:Tab({ Id = "settings", Title = "Settings", Icon = "sliders" })
		local safety = settings:Section({ Id = "safety", Title = "Safety", Icon = "godmode", Side = "Left", Collapsible = false })
		controls.GodMode = safety:Toggle({
			Id = "godmode",
			Title = "Godmode",
			Description = "Local anti-fling and ragdoll recovery without moving you away from the roller or wave. Normal freefall stays intact.",
			Default = initial.godMode == true,
			Persist = false,
			Callback = function(value: boolean) action("SetGodMode", value) end,
		})
		controls.RemoveObstacles = safety:Toggle({
			Id = "remove-obstacles",
			Title = "Remove Obstacles",
			Description = "Locally removes the boss, boss trigger, and ordinary course hazards. The server-authoritative roller and wave remain visible.",
			Default = initial.removeObstacles == true,
			Persist = false,
			Callback = function(value: boolean) action("SetRemoveObstacles", value) end,
		})
		local interface = settings:Section({ Id = "interface", Title = "Interface", Icon = "settings", Side = "Right", Collapsible = false })
		controls.MinimizedStatus = interface:Toggle({
			Id = "minimized-status",
			Title = "Minimized Status",
			Description = "Show live automation status beneath Fluxcore while the menu is minimized.",
			Default = app._minimizedStatusEnabled,
			Persist = false,
			Callback = function(value: boolean)
				app._minimizedStatusEnabled = value == true
				app:Refresh(true)
			end,
		})

		local COMPACT_SUFFIXES = {
			"", "k", "m", "b", "t", "qa", "qi", "sx", "sp", "oc", "no", "dc",
			"ud", "dd", "td", "qad", "qid", "sxd", "spd", "ocd", "nod",
		}

		local function compactNumber(value: any): string
			local amount = if type(value) == "number" then math.max(0, value) else 0
			local suffix = 1
			while amount >= 1000 and suffix < #COMPACT_SUFFIXES do
				amount /= 1000
				suffix += 1
			end
			local rounded = math.floor(amount * 10 + 0.5) / 10
			local text = string.format("%.1f", rounded)
			if string.sub(text, -2) == ".0" then text = string.sub(text, 1, -3) end
			return text .. COMPACT_SUFFIXES[suffix]
		end

		local function sessionGain(key: string, active: boolean, value: any): number?
			local amount = if type(value) == "number" then value else 0
			local baseline = app._sessionBaselines[key]
			if not active then
				app._sessionBaselines[key] = nil
				return nil
			end
			if baseline == nil then
				app._sessionBaselines[key] = amount
				return 0
			end
			return math.max(0, amount - baseline)
		end

		local function minimizedStatusFor(snapshot: any): any
			local entries = {}
			local function add(active: any, name: string, status: any)
				if active == true then table.insert(entries, { name = name, status = tostring(status or "Running") }) end
			end
			add(snapshot.autoWins, "Auto Wins", snapshot.winsStatus)
			add(snapshot.autoGloveBattle, "Glove Battle", snapshot.gloveStatus)
			add(snapshot.autoAdminEvents, "Admin Events", snapshot.adminEventsCurrent or snapshot.adminEventsStatus)
			add(snapshot.autoKeys, "Auto Keys", snapshot.keysStatus)
			add(snapshot.autoFuse, "Auto Fuse", snapshot.fuseStatus)
			add(snapshot.autoBuyItems, "Buy Items", snapshot.itemsStatus)
			add(snapshot.autoEquipItems, "Equip Items", snapshot.equipItemsStatus)
			add(snapshot.autoBuyTrails, "Buy Trails", snapshot.trailsStatus)
			add(snapshot.autoBuyAuras, "Buy Auras", snapshot.aurasStatus)
			add(snapshot.autoEquipTrails, "Equip Trails", snapshot.equipTrailsStatus)
			add(snapshot.autoEquipAuras, "Equip Auras", snapshot.equipAurasStatus)
			add(snapshot.autoRebirth, "Auto Rebirth", snapshot.rebirthStatus)
			add(snapshot.godMode, "Godmode", snapshot.godModeStatus)
			add(snapshot.removeObstacles, "Obstacles", "Removed")
			if #entries == 0 then
				app._sessionBaselines = {}
				return { Text = "Idle", Detail = "No automation running", Tone = "neutral", Lines = { "All automation is off." } }
			end

			local lines = {}
			for _, metric in ipairs(SESSION_METRICS) do
				local gained = sessionGain(metric.key, snapshot[metric.flag] == true, snapshot[metric.counter])
				if gained ~= nil and (gained > 0 or #entries == 1) then
					table.insert(lines, metric.verb .. " +" .. compactNumber(gained) .. " " .. metric.resource)
				end
			end
			if #entries > 1 then
				for _, entry in ipairs(entries) do
					if #lines == 4 then break end
					table.insert(lines, entry.name .. ": " .. entry.status)
				end
			end
			while #lines > 4 do table.remove(lines) end
			local names = {}
			for _, entry in ipairs(entries) do table.insert(names, entry.name) end
			return {
				Text = if #entries == 1 then entries[1].name else tostring(#entries) .. " running",
				Detail = if #entries == 1 then entries[1].status else table.concat(names, ", "),
				Tone = "success",
				Lines = lines,
			}
		end

		local function project(snapshot: any, force: boolean?)
			setValue(controls.WinStrategies, "winStrategies", snapshot.winStrategies or {}, force)
			setValue(controls.AutoWins, "autoWins", snapshot.autoWins == true, force)
			setValue(controls.GodMode, "godMode", snapshot.godMode == true, force)
			setValue(controls.RemoveObstacles, "removeObstacles", snapshot.removeObstacles == true, force)
			setValue(controls.AutoRebirth, "autoRebirth", snapshot.autoRebirth == true, force)
			setValue(controls.KeyTypes, "selectedKeyKinds", snapshot.selectedKeyKinds or {}, force)
			setValue(controls.AutoKeys, "autoKeys", snapshot.autoKeys == true, force)
			setValue(controls.AutoBuyTrails, "autoBuyTrails", snapshot.autoBuyTrails == true, force)
			setValue(controls.AutoBuyAuras, "autoBuyAuras", snapshot.autoBuyAuras == true, force)
			setValue(controls.AutoEquipTrails, "autoEquipTrails", snapshot.autoEquipTrails == true, force)
			setValue(controls.AutoEquipAuras, "autoEquipAuras", snapshot.autoEquipAuras == true, force)
			setChoices(controls.ItemVariants, "itemVariants", snapshot.itemVariants or {}, force)
			setValue(controls.ItemVariants, "selectedItemVariants", snapshot.selectedItemVariants or {}, force)
			setValue(controls.AutoBuyItems, "autoBuyItems", snapshot.autoBuyItems == true, force)
			setValue(controls.AutoEquipItems, "autoEquipItems", snapshot.autoEquipItems == true, force)
			setChoices(controls.FuseItems, "fuseItems", snapshot.fuseChoices or {}, force)
			setValue(controls.FuseItems, "selectedFuseItems", snapshot.selectedFuseItems or {}, force)
			setValue(controls.AutoFuse, "autoFuse", snapshot.autoFuse == true, force)
			setValue(controls.AdminEventKinds, "selectedAdminEvents", snapshot.selectedAdminEvents or {}, force)
			setValue(controls.AutoAdminEvents, "autoAdminEvents", snapshot.autoAdminEvents == true, force)
			setValue(controls.AutoGloveBattle, "autoGloveBattle", snapshot.autoGloveBattle == true, force)
			local minimizedStatus = minimizedStatusFor(snapshot)
			if app._minimizedStatusEnabled then
				window:SetMinimizedStatus(minimizedStatus)
			else
				window:SetMinimizedStatus(nil)
			end
			return snapshot
		end

		function app:Refresh(force: boolean?)
			if self._destroyed then return nil end
			self._refreshGeneration += 1
			local generation = self._refreshGeneration
			local ok, snapshot = pcall(function() return controller:Snapshot() end)
			if self._destroyed then return nil end
			if self._refreshGeneration ~= generation then return self._snapshot end
			if not ok or type(snapshot) ~= "table" then
				ui:Notify({ Title = "Keyboard Escape", Text = tostring(snapshot), Type = "danger", Duration = 5 })
				if type(self._snapshot) ~= "table" then return nil end
				return project(self._snapshot, true)
			end
			self._snapshot = snapshot
			return project(snapshot, force)
		end

		app.Controls = table.freeze(controls)
		app:Refresh()
		if input.StartPoll ~= false then
			app._pollGeneration += 1
			local generation = app._pollGeneration
			task.spawn(function()
				while not app._destroyed and app._pollGeneration == generation do
					task.wait(0.35)
					if not app._destroyed and app._pollGeneration == generation then app:Refresh() end
				end
			end)
		end

		function app:Destroy(reason: any?)
			if self._destroyed then return end
			self._destroyed = true
			self._pollGeneration += 1
			pcall(function() controller:Destroy(reason) end)
			ui:Destroy()
		end
		ui:SetCloseHandler(function() app:Destroy("close") end)
		return app
	end, debug.traceback)
	if not constructed then
		pcall(ui.Destroy, ui)
		return nil, { code = "menu_construction_failed", message = tostring(appOrError) }
	end
	return appOrError, nil
end

return Menu
