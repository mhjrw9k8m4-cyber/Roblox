--!nocheck
--[[
	Náhrada Roblox prostředí.

	Umožňuje načíst herní moduly a nastartovat server mimo Roblox. Cílem
	NENÍ věrná simulace enginu — to by byla práce na měsíce. Cílem je
	dostat se dost daleko na to, aby se provedl veškerý kód, který běží
	při startu, a odhalily se chyby, které kompilace nevidí: volání
	neexistující funkce na jiném modulu, špatný počet argumentů, překlep
	v názvu služby.

	Přesně takovou chybu měl projekt v sobě několik kol: osm remotů se
	používalo, ale nebylo definováno. Build byl zelený a hra nemohla
	naběhnout.

	Klíčové rozhodnutí — `task.wait` se nikdy nevrátí. Nekonečné smyčky
	(`while true do task.wait(1) ... end`) se tím provedou právě jednou
	až k prvnímu čekání a pak se odloží. Chyba v prvním průchodu se
	odhalí, ale test neuvízne.
]]

local stub = {}

-- Události ------------------------------------------------------------------

local function newSignal()
	local signal = { _handlers = {} }

	function signal:Connect(handler)
		table.insert(self._handlers, handler)
		return {
			Disconnect = function() end,
			Connected = true,
		}
	end

	signal.Once = signal.Connect
	signal.ConnectParallel = signal.Connect

	function signal:Wait()
		return nil
	end

	function signal:Fire(...)
		for _, handler in self._handlers do
			handler(...)
		end
	end

	return signal
end

stub.newSignal = newSignal

-- Instance -------------------------------------------------------------------

--[[
	Mock instance. Vlastnosti se nekontrolují — v testu jde o to, jestli
	kód proběhne, ne jestli by Roblox danou vlastnost přijal. Kontrolu
	názvů vlastností dělá kompilátor typů, ne tenhle stub.
]]
local function newInstance(className, name)
	local children = {}
	local attributes = {}

	local instance
	instance = {
		ClassName = className,
		Name = name or className,
		Parent = nil,
		_children = children,

		-- Nejčastější vlastnosti, na které se v kódu sahá bez nastavení
		Value = 0,
		Text = "",
		Size = nil,
		Position = nil,
		Transparency = 0,
		Visible = true,
		Enabled = true,
		Volume = 1,
		Scale = 1,
	}

	function instance:IsA(query)
		-- Hrubé, ale pro testy stačí: buď přesná shoda, nebo běžný předek
		if self.ClassName == query then
			return true
		end
		if query == "BasePart" then
			return self.ClassName == "Part" or self.ClassName == "SpawnLocation"
		end
		if query == "GuiObject" then
			return string.find(self.ClassName, "Frame") ~= nil
				or string.find(self.ClassName, "Label") ~= nil
				or string.find(self.ClassName, "Button") ~= nil
		end
		return false
	end

	function instance:GetChildren()
		local copy = {}
		for _, child in children do
			table.insert(copy, child)
		end
		return copy
	end

	function instance:GetDescendants()
		local list = {}
		for _, child in children do
			table.insert(list, child)
			for _, deep in child:GetDescendants() do
				table.insert(list, deep)
			end
		end
		return list
	end

	function instance:FindFirstChild(childName)
		for _, child in children do
			if child.Name == childName then
				return child
			end
		end
		return nil
	end

	function instance:FindFirstChildOfClass(query)
		for _, child in children do
			if child.ClassName == query then
				return child
			end
		end
		return nil
	end

	instance.FindFirstChildWhichIsA = instance.FindFirstChildOfClass
	instance.FindFirstAncestorOfClass = function()
		return nil
	end

	--[[
		`WaitForChild` v testu čekat nesmí — vytvoří chybějící dítě.
		Kód, který si na něco počká, tak proběhne dál, místo aby se
		zasekl na něčem, co v testu nikdo nevytvoří.
	]]
	function instance:WaitForChild(childName)
		local found = self:FindFirstChild(childName)
		if found then
			return found
		end

		local created = newInstance("Folder", childName)
		created.Parent = self
		table.insert(children, created)
		return created
	end

	function instance:Destroy()
		self.Parent = nil
		table.clear(children)
	end

	instance.Remove = instance.Destroy

	function instance:Clone()
		return newInstance(self.ClassName, self.Name)
	end

	function instance:SetAttribute(key, value)
		attributes[key] = value
	end

	function instance:GetAttribute(key)
		return attributes[key]
	end

	function instance:GetPropertyChangedSignal()
		return newSignal()
	end

	function instance:GetAttributeChangedSignal()
		return newSignal()
	end

	function instance:PivotTo() end
	function instance:Play() end
	function instance:Stop() end
	function instance:Emit() end
	function instance:EquipTool() end

	-- Události, které se na instancích běžně používají
	instance.Touched = newSignal()
	instance.Changed = newSignal()
	instance.ChildAdded = newSignal()
	instance.AncestryChanged = newSignal()
	instance.StateChanged = newSignal()
	instance.Completed = newSignal()
	instance.FocusLost = newSignal()
	instance.MouseButton1Click = newSignal()
	instance.MouseButton1Down = newSignal()
	instance.MouseButton1Up = newSignal()
	instance.MouseEnter = newSignal()
	instance.MouseLeave = newSignal()
	instance.Activated = newSignal()

	-- Remote rozhraní
	instance.OnServerEvent = newSignal()
	instance.OnClientEvent = newSignal()
	instance.OnServerInvoke = nil
	function instance:FireClient() end
	function instance:FireAllClients() end
	function instance:FireServer() end
	function instance:InvokeServer()
		return nil
	end

	--[[
		Jediný metatable na instanci. Byly tu chvíli dva a ten druhý ten
		první tiše přepsal — `setmetatable` nesestavuje, nahrazuje. Šlo to
		poznat jen na tom, že žádný díl neměl polohu.
	]]
	setmetatable(instance, {
		__newindex = function(self, key, value)
			if key == "Parent" then
				rawset(self, "Parent", value)
				if value and value._children then
					table.insert(value._children, self)
				end
				return
			end

			rawset(self, key, value)

			--[[
				Nastavení `CFrame` přepíše i `Position`, stejně jako to dělá
				skutečný engine. Bez toho měl každý díl postavený přes
				`CFrame` polohu `nil` a testy na geometrii přes ně jen
				tiše přeskočily.
			]]
			if key == "CFrame" and typeof(value) == "table" and value.Position then
				rawset(self, "Position", value.Position)
			end
		end,
	})

	return instance
end

stub.newInstance = newInstance

-- Kořen hierarchie -------------------------------------------------------------

local services = {}

local function service(className)
	if not services[className] then
		services[className] = newInstance(className, className)
	end
	return services[className]
end

stub.service = service

-- Instalace globálů --------------------------------------------------------------

--[[
	Sestaví prostředí a vrátí ho jako tabulku.

	Nezapisuje do `_G` schválně — v Luau CLI je globální tabulka jen ke
	čtení, a hlavně je čistší, když si volající globály navěsí sám do
	lokálních proměnných. Moduly je pak vidí ve svém uzávěru.
]]
function stub.build()
	local env = {}
	env.Instance = {
		new = function(className, parent)
			local created = newInstance(className)
			if parent then
				created.Parent = parent
			end
			return created
		end,
	}

	-- Enum: libovolně hluboký přístup vrací značku se jménem
	local function enumTree()
		return setmetatable({}, {
			__index = function(_, key)
				return setmetatable({ Name = key, Value = 0 }, {
					__index = function(_, deep)
						return { Name = deep, Value = 0 }
					end,
					__tostring = function()
						return key
					end,
				})
			end,
		})
	end
	env.Enum = enumTree()

	-- Datové typy
	local function vector(x, y, z)
		local self
		self = setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, {
			__add = function(a, b)
				return vector(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
			end,
			__sub = function(a, b)
				return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
			end,
			__mul = function(a, b)
				if typeof(b) == "number" then
					return vector(a.X * b, a.Y * b, a.Z * b)
				end
				return vector(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
			end,
			__index = function(_, key)
				if key == "Magnitude" then
					return math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2 + (z or 0) ^ 2)
				end
				if key == "Unit" then
					return vector(0, 1, 0)
				end
				if key == "Lerp" then
					return function(a, b)
						return b
					end
				end
				return nil
			end,
		})
		return self
	end

	env.Vector3 = setmetatable({
		new = vector,
		zero = vector(0, 0, 0),
		one = vector(1, 1, 1),
		yAxis = vector(0, 1, 0),
	}, {})

	env.Vector2 = { new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end }

	local function color(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, {
			__index = function(_, key)
				if key == "Lerp" then
					return function(self, other)
						return other
					end
				end
				return nil
			end,
		})
	end

	env.Color3 = {
		new = color,
		fromRGB = function(r, g, b)
			return color((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
		end,
		fromHSV = function()
			return color(1, 1, 1)
		end,
	}

	--[[
		`CFrame`, který si opravdu nese polohu.

		Původní verze byla prázdná skořápka: `Position` vracela vždycky
		(0, 0, 1) a `__mul` vracel sám sebe. Testy na geometrii tím
		nemohly fungovat — a hůř, **tiše procházely**, protože všechny
		díly vyšly na stejném místě a nebylo co porovnávat.

		Rotace se nesleduje, jen posun. Skládání dvou posunů je přesné;
		posun otočeného rámu se aproximuje jako neotočený. Pro kontroly
		typu "nestojí dva díly v sobě" to stačí a je to čitelně méně,
		než co dělá skutečný engine.
	]]
	local function cframe(a, b, c)
		local px, py, pz = 0, 0, 0

		if typeof(a) == "number" then
			px, py, pz = a, b or 0, c or 0
		elseif typeof(a) == "table" and a.X then
			px, py, pz = a.X, a.Y, a.Z
		end

		local self
		self = setmetatable({ _px = px, _py = py, _pz = pz }, {
			__mul = function(left, right)
				-- Posun se skládá; otočení (CFrame.Angles) polohu nemění
				if typeof(right) == "table" and right._px then
					return cframe(left._px + right._px, left._py + right._py, left._pz + right._pz)
				end
				return left
			end,
			__add = function(left, right)
				if typeof(right) == "table" and right.X then
					return cframe(left._px + right.X, left._py + right.Y, left._pz + right.Z)
				end
				return left
			end,
			__sub = function(left)
				return left
			end,
			__index = function(_, key)
				if key == "Position" then
					return env.Vector3.new(px, py, pz)
				end
				if key == "X" then
					return px
				elseif key == "Y" then
					return py
				elseif key == "Z" then
					return pz
				end
				if key == "LookVector" or key == "RightVector" or key == "UpVector" then
					return env.Vector3.new(0, 0, 1)
				end
				if key == "Dot" then
					return function()
						return 0
					end
				end
				return nil
			end,
		})
		return self
	end

	env.CFrame = {
		new = cframe,
		Angles = cframe,
		lookAt = cframe,
		identity = cframe(),
	}

	local function udim2()
		local self
		self = setmetatable({
			X = { Scale = 0, Offset = 0 },
			Y = { Scale = 0, Offset = 0 },
		}, {
			__add = function()
				return self
			end,
			__sub = function()
				return self
			end,
		})
		return self
	end

	env.UDim2 = {
		new = udim2,
		fromScale = udim2,
		fromOffset = udim2,
	}
	env.UDim = { new = function()
		return { Scale = 0, Offset = 0 }
	end }

	env.NumberSequence = { new = function()
		return {}
	end }
	env.NumberSequenceKeypoint = { new = function()
		return {}
	end }
	env.ColorSequence = { new = function()
		return {}
	end }
	env.ColorSequenceKeypoint = { new = function()
		return {}
	end }
	env.NumberRange = { new = function()
		return {}
	end }
	env.TweenInfo = { new = function()
		return {}
	end }
	env.PhysicalProperties = { new = function()
		return {}
	end }
	env.Rect = { new = function()
		return {}
	end }

	--[[
		Generátor s pevným seedem. Testy tak dávají stejný výsledek
		při každém běhu — jinak by "občas selže" bylo nejhorší možné
		chování testu.
	]]
	env.Random = {
		new = function(seed)
			local state = (seed or 12345) % 2147483647
			local generator = {}

			function generator:NextNumber(min, max)
				state = (state * 1103515245 + 12345) % 2147483648
				local value = state / 2147483648
				if min then
					return min + value * ((max or 1) - min)
				end
				return value
			end

			function generator:NextInteger(min, max)
				return math.floor(generator:NextNumber(min, (max or 1) + 1))
			end

			return generator
		end,
	}

	--[[
		Plánovač. `task.wait` nikdy nekončí, takže se nekonečná smyčka
		provede jednou až k prvnímu čekání a odloží se — chyba v prvním
		průchodu se najde, test neuvízne.
	]]
	env.task = {
		spawn = function(fn, ...)
			local thread = coroutine.create(fn)
			local ok, err = coroutine.resume(thread, ...)
			if not ok then
				error(`task.spawn: {err}`, 0)
			end
			return thread
		end,
		defer = function(fn, ...)
			return env.task.spawn(fn, ...)
		end,
		-- Odložené volání se v testu neprovádí: je to budoucnost, ne start
		delay = function()
			return nil
		end,
		wait = function()
			coroutine.yield()
		end,
		cancel = function() end,
		synchronize = function() end,
		desynchronize = function() end,
	}

	env.wait = env.task.wait
	env.spawn = env.task.spawn
	env.delay = env.task.delay

	-- Herní strom -----------------------------------------------------------------

	local game = newInstance("DataModel", "game")
	game.JobId = ""
	game.PlaceId = 0

	function game:GetService(name)
		return service(name)
	end

	game.FindService = game.GetService
	game.service = game.GetService

	function game:BindToClose() end
	function game:IsLoaded()
		return true
	end
	game.Loaded = newSignal()

	env.game = game
	env.workspace = service("Workspace")

	-- Doplňky konkrétních služeb, na které kód sahá
	local players = service("Players")
	players.LocalPlayer = nil
	players.PlayerAdded = newSignal()
	players.PlayerRemoving = newSignal()

	--[[
		Seznam hráčů je opravdový, aby šlo simulovat připojení. Bez toho
		by se `onPlayerAdded` — načtení profilu, offline odměna, questy,
		kosmetika, gamepassy — v testech nikdy nespustilo.
	]]
	local roster = {}

	function players:GetPlayers()
		return table.clone(roster)
	end
	function players:GetPlayerByUserId(userId)
		for _, player in roster do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end

	function players:_add(name, userId)
		local player = newInstance("Player", name)
		player.UserId = userId
		player.CharacterAdded = newSignal()
		player.CharacterRemoving = newSignal()
		player.Character = nil
		player.Parent = players
		table.insert(roster, player)
		players.PlayerAdded:Fire(player)
		return player
	end

	function players:_remove(player)
		local index = table.find(roster, player)
		if index then
			table.remove(roster, index)
		end
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
	end
	function players:GetNameFromUserIdAsync()
		return "TestPlayer"
	end

	local runService = service("RunService")
	runService.Heartbeat = newSignal()
	runService.RenderStepped = newSignal()
	runService.Stepped = newSignal()
	function runService:IsServer()
		return true
	end
	function runService:IsClient()
		return false
	end
	function runService:IsStudio()
		return true
	end
	function runService:BindToRenderStep() end

	local tweenService = service("TweenService")
	function tweenService:Create()
		local tween = newInstance("Tween")
		return tween
	end

	local dataStoreService = service("DataStoreService")
	--[[
		DataStore v paměti. Testy tak projdou celou cestu načtení
		i uložení včetně zámku, aniž by se někam sahalo po síti.
	]]
	local storage = {}
	function dataStoreService:GetDataStore(name)
		storage[name] = storage[name] or {}
		local data = storage[name]

		return {
			GetAsync = function(_, key)
				return data[key]
			end,
			SetAsync = function(_, key, value)
				data[key] = value
			end,
			UpdateAsync = function(_, key, transform)
				local result = transform(data[key])
				if result ~= nil then
					data[key] = result
				end
				return result
			end,
		}
	end

	function dataStoreService:GetOrderedDataStore()
		return {
			GetSortedAsync = function()
				return {
					GetCurrentPage = function()
						return {}
					end,
				}
			end,
			SetAsync = function() end,
		}
	end

	local marketplace = service("MarketplaceService")
	marketplace.PromptGamePassPurchaseFinished = newSignal()
	marketplace.ProcessReceipt = nil
	function marketplace:UserOwnsGamePassAsync()
		return false
	end
	function marketplace:PromptGamePassPurchase() end
	function marketplace:PromptProductPurchase() end

	local physics = service("PhysicsService")
	function physics:RegisterCollisionGroup() end
	function physics:CollisionGroupSetCollidable() end

	local debris = service("Debris")
	function debris:AddItem() end

	local analytics = service("AnalyticsService")
	function analytics:LogOnboardingFunnelStepEvent() end
	function analytics:LogFunnelStepEvent() end
	function analytics:LogEconomyEvent() end
	function analytics:LogProgressionEvent() end
	function analytics:LogCustomEvent() end

	local badges = service("BadgeService")
	function badges:AwardBadge() end

	local content = service("ContentProvider")
	function content:PreloadAsync() end

	local uis = service("UserInputService")
	uis.TouchEnabled = false
	uis.InputBegan = newSignal()
	uis.InputEnded = newSignal()

	local cas = service("ContextActionService")
	function cas:BindAction() end

	local lighting = service("Lighting")
	local sound = service("SoundService")
	local replicated = service("ReplicatedStorage")
	local serverScripts = service("ServerScriptService")
	local replicatedFirst = service("ReplicatedFirst")
	function replicatedFirst:RemoveDefaultLoadingScreen() end

	local workspaceService = service("Workspace")
	workspaceService.CurrentCamera = newInstance("Camera")
	workspaceService.Terrain = newInstance("Terrain")
	function workspaceService:GetPartBoundsInRadius()
		return {}
	end

	env._world = {
		game = game,
		service = service,
		players = players,
		storage = storage,
	}

	return env
end

return stub
