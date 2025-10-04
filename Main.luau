--!strict
--!optimize 2
--@author: Jetto59
--@date: 12/9/25
--@last updated: 19/9/25
--[[@description:
	Extended Tweening library

	This module provides a "SharpTween" object that extends the built-in TweenService
    with features such as groups, attribute-based observation (canceling/blocking playback),
    preloading, etc. Created Tweens with this module will be referred as CustomTweens.
		
    Main features:
    -- Tween groups: call inherited methods across multiple CustomTweens.
    
    -- Attribute observation: cancel or block tweens automatically when specified attributes are set.
    
    -- Preloaded playback: optionally precalculate every step/frame of a tween (frames table) then
    	play them with PlayPreloaded(). Preloading can be expensive (typical measurements: ~85+ μs per call) so
    	call Preload() at a convenient time before calling PlayPreloaded(). Preloading and playing does not always
    	improve perfomance; PlayPreloaded() takes 1-4 μs and Regular Tween Play() takes 3-4 μs. Preloading and playing 
    	a CustomTween may reduce starting-lag-spike in some cases.
    	
    	(Preloading may not be fully accurate)
    
    -- GC: if a CustomTween or its associated instance is not referenced by any script, it 
    	participates in garbage collection due to the weak table (weak keys and values) used for storing
    	CustomTweens.
    	
    -- Signal preservation: when a Tween is replaced with the default methods, CustomTween signals 
    	aren't lost.
    	
    -- AutoWait (RECOMMENDED): CustomTweenGroup property that automatically yields execution when an
    	inherited method is called until every CustomTween has been iterated.
    	
    	(Disabled by default to avoid yielding on scripts that should't be interrupted)
		
	NOTE:
		Calling inherited methods in a CustomTweenGroup do not yield the script by default to avoid
		interrupting scripts that shouldn't be interrumped.
		
		This can lead to unexpected behavior if:
			-- More that one inherited method is called at the same time
			-- Two or more groups which work with the same instance call an inherited method at the same time.
		
		This could be avoided by enabling the CustomTweenGroup property 'AutoWait' or calling WaitTweens() after
		a call to wait for the method to iterate over every CustomTween.
		
		Accesing the created tween on CustomTween objects with the property <code>_createdTween</code> is not 
		advised as it can be replaced with a copy when calling some methods.
		
	GitHub Repository: https://github.com/Dungoler/SharpTween
]]

-----------------------------
-- SERVICES --
-----------------------------
local storage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-----------------------------
-- DEPENDENCIES --
-----------------------------
local Trove = require(script.Trove)
local Observers = require(script.Observers)
local LemonSignal = require(script.LemonSignal)
local throttle = require(script.throttle)

type PropertyTable = {[string]: any}
type CustomTweenFunction<self> = (self: self) -> ()

type InheritedMethods<self, n, m> = {
	PlayPreloaded: typeof(
		-- Plays from preloaded frames. <code>Play()</code> and <code>PlayPreloaded()</code> have no effect until the tween is stopped or canceled. Preload() should be called before executing. <strong>No tween object is used.</strong>
		function(self: self, progress: number?) end),
	Preload: typeof(
		-- Builds frames using the current instance values (not the initial stored properties). Preloading with a different fps parameter replaces the old one.
		function(self: self, fps: number?, overrides: boolean?) end),
	SetInstanceToAlpha: typeof(
		-- Immediately set the instance properties to a specific alpha using preloaded frames.
		function(self: self, alpha: number) end),
	AdjustTime: typeof(
		-- Replace the current Tween with a copy using a different <code>Time</code>. If currently playing, the new Tween will start playing.
		function(self: self, newTime: number) end),
	AdjustDelayTime: typeof(
		-- Replace the current Tween with a copy using a different <code>DelayTime</code>. If currently playing, the new Tween will start playing after the given delay.
		function(self: self, delayTime: number) end),
	GetReverse: typeof(
		-- Returns a new CustomTween with initial properties and goals reversed (end->start)
		-- <strong>Note:</strong> this does not fully "reset" the instance; it only provides a tween that animates back over the set of tweening properties.
		function(self: self): n return nil :: any end),
	UpdateInitialProperties: typeof(
		-- Overwrites the stored initial properties used by GetReverse() with the current instance values.
		function(self: self) end),
	GetAlpha: typeof(
		-- Returns two values: 
		--->	<code>Alpha:</code> the eased alpha of the Tween obtained with the TweenInfo easing parameters.
		--->	<code>Progress:</code> the progress or fixed alpha of the Tween (0..1).
		--This does not reflect PlayPreloaded() progress (PreloadedAlpha property does).
		function(self: self): (m, m) return nil :: any, nil :: any end),
	SetAlpha: typeof(
		-- Adjusts the Tween's time such that the given alpha corresponds to the new starting point. The alpha is always relative to the original <code>TweenInfo.Time</code>
		-- CustomTween has to be preloaded manually to be affected.
		function(self: self, alpha: number) end),
	RandomizeProperties: typeof(
		-- Randomizes the Tweening properties with the given percentage. The percentage is always relative to the default goals.
		function(self: self, percentage: number) end),
	AdjustMultiplier: typeof(
		-- Sets the Tweening Speed Multiplier to the given number, relative to the original <code>TweenInfo.Time</code>.
		-- The multiplier is persistent, and will keep multiplying even when calling CustomTween methods that modify the Tweening time such as <code>AdjustTime()</code> or <code>SetAlpha()</code>.
		-- Default is 1
		function(self: self, newMultiplier: number?) end),
	GetPropertyTable: (self: self) -> {[string]: any},
	Clone: (self: self) -> n,
	Cancel: CustomTweenFunction<self>,
	Pause: CustomTweenFunction<self>,
	Play: CustomTweenFunction<self>,
}

type CustomTweenProperties = {
	_createdTween: Tween,
	Instance: Instance,
	observerSignals: {[string]: Trove.Trove},
	observedAttributes: {string},
	TweenInfo: TweenInfo,
	PlaybackState: Enum.PlaybackState,
	newAttributeSignal: LemonSignal.Signal<string>,
	StartObservingAttribute: (...any) -> (),
	StopObservingAttribute: (...any) -> (),
	frames: {[number]: any}, -- preloaded frame snapshots
	fps: number,
	isPreloadedRunning: boolean,
	manualCompletionSignal: LemonSignal.Signal<>,
	PreloadedAlpha: number, -- alpha of preloaded playback
	PreloadedProgress: number, -- progress of preloaded playback (0..1)
	Completed: LemonSignal.Signal<>,
	GetPropertyChangedSignal: (self: CustomTween, property: "PlaybackState" | string) -> LemonSignal.Signal<>,
	PropertyChangedSignals: {[string]: LemonSignal.Signal<>},
	InitialTweenInfo: TweenInfo,
	Bezier: (alpha: number) -> ()?
}

type GroupProperties = {
	-- An object that forwards inherited methods to every member CustomTween.
	GroupTweens: {CustomTween},
	Add: (self: GroupProperties, CustomTween) -> (),
	Remove: (self: GroupProperties, CustomTween) -> (),
	AutoWait: boolean,
	isParsing: boolean,
	observedAttributes: {},
	WaitTweens: typeof(
		-- Wait until any ongoing group method finishes iterating over members. If there's no 
		-- ongoing method, it will not yield.
		function(self: GroupProperties) end),
	NewObserver: typeof(
		-- Adds an observer for current and added CustomTweens.
		function(self: GroupProperties, attribute: string) end),
	RemoveObserver: typeof(
		-- Removes the observer on all the CustomTweens, even the ones that observed it manually with <code>StartObservingAttribute()</code>.
		-- If you want to remove the observer for new CustomTween but keep it for current, then remove the attribute from the <code>observedAttributes</code> group table. 
		function(self: GroupProperties, attribute: string) end)
}

export type CustomTween = CustomTweenProperties & InheritedMethods<CustomTween, CustomTween, number>
export type CustomTweenGroup = GroupProperties & InheritedMethods<GroupProperties, {CustomTween}, {number}>

type SharpTween = {
	NewCustomTween: LemonSignal.Signal<CustomTween>,
	CustomTweens: typeof(setmetatable({} :: {[Instance]: {CustomTween}}, {__mode = "kv"})),
	Create: (self: SharpTween, Instance, TweenInfo, PropertyTable) -> CustomTween,
	SetDefaultGroup: (self: SharpTween, Group: CustomTweenGroup) -> (),
	new: () -> CustomTweenGroup,
}

-----------------------------
-- VARIABLES --
-----------------------------

-- Update if a new method is created
local inheritedMethods = {
	PlayPreloaded = true,
	Preload = true,
	SetInstanceToAlpha = true,
	AdjustTime = true,
	GetReverse = true,
	UpdateInitialProperties = true,
	GetAlpha = true,
	SetAlpha = true,
	RandomizeProperties = true,
	Clone = true,
	Cancel = true,
	Pause = true,
	Play = true
}

local TweenClass = {}
TweenClass.__index = TweenClass

local DEFAULT_FPS = 60

local SharpTween = {}
SharpTween.__index = SharpTween

local Constructor = {}

-----------------------------
-- PRIVATE FUNCTIONS --
-----------------------------

-- Throttle the warn message to avoid massive lag spikes
local function warnAttempt(msg: string)
	throttle("warn", 0.01, function()
		warn(msg)
	end)
end

local function GetCustomTween(mainTrove: Trove.Trove): CustomTween
	local base: CustomTween = setmetatable({}, {
		__newindex = function(tab: CustomTween, key, value: Tween)
			rawset(tab, key, value)
			
			if key ~= "_createdTween" then
				return
			end
			
			mainTrove:Clean()
			mainTrove:Add(value)
			mainTrove:Add(value.Completed:Connect(function()
				if tab._createdTween ~= value then
					return
				end

				tab.Completed:Fire()
			end))

			mainTrove:Add(value:GetPropertyChangedSignal("PlaybackState"):Connect(function()
				if tab._createdTween ~= value then
					return
				end

				tab.PlaybackState = value.PlaybackState

				local PlaybackStateSignal = tab.PropertyChangedSignals.PlaybackState
				if PlaybackStateSignal then
					PlaybackStateSignal:Fire()
				end
			end))

			for property, signal in pairs(tab.PropertyChangedSignals) do
				if property == "PlaybackState" then
					continue
				end

				mainTrove:Add(value:GetPropertyChangedSignal(property):Connect(function()
					if tab._createdTween ~= value then
						return
					end

					signal:Fire()
				end))
			end
		end,
	}) :: any

	return base
end

local function StopObservingAttribute(self: CustomTween, attribute: string)
	local trove = self.observerSignals[attribute]
	
	if trove then
		trove:Clean()
	end
end

local function StartObservingAttribute(self: CustomTween, attribute: string)
	local element = self.Instance
	local trove = Trove.new()
	
	trove:Add(Observers.observeAttribute(element, attribute, function()
		table.insert(self.observedAttributes, attribute)
		self.newAttributeSignal:Fire(attribute)
		return function()
			local index = table.find(self.observedAttributes, attribute)
			table.remove(self.observedAttributes, index)
		end
	end))

	self.observerSignals[attribute] = trove
end

-- binomial coefficient
@native
local function binomial(n: number, k: number)
	local res = 1
	for i = 1, k do
		res = res * (n - (k - i)) / i
	end
	return res
end

-- general Bezier polynomial
@native
local function bezier1D(t: number, coord: string, controlPoints: {{x: number, y: number}}): number
	local n = #controlPoints - 1
	local sum = 0
	for i, point in ipairs(controlPoints) do
		assert(point[coord], "x and y have to be numbers")

		local coeff = binomial(n, i - 1) * ((1 - t)^(n - (i - 1))) * (t^(i - 1))
		sum += point[coord] * coeff
	end
	return sum
end

@native
local function lerpNumber(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function lerp(a: {[any]: any}, b: {[any]: any}, alpha: number): any
	if typeof(a) == "number" then
		return lerpNumber(a, b, alpha)
	elseif typeof(a) == "Vector3" or typeof(a) == "Vector2" or typeof(a) == "Color3" or typeof(a) == "CFrame" then
		return a:Lerp(b, alpha)
	elseif typeof(a) == "UDim2" then
		local x = UDim.new(lerpNumber(a.X.Scale, b.X.Scale, alpha), lerpNumber(a.X.Offset, b.X.Offset, alpha))
		local y = UDim.new(lerpNumber(a.Y.Scale, b.Y.Scale, alpha), lerpNumber(a.Y.Offset, b.Y.Offset, alpha))
		return UDim2.new(x.Scale, x.Offset, y.Scale, y.Offset)
	elseif typeof(a) == "UDim" then
		return UDim.new(lerpNumber(a.Scale, b.Scale, alpha), lerpNumber(a.Offset, b.Offset, alpha))
	else
		error(`Unsupported type for tweening: {typeof(a)}`)
	end
end

local function GetFromRandom(...)
	local args = {...}
	local newTab = {}
	
	for i, arg in pairs(args) do
		newTab[i] = (math.random() * 2 - 1) * arg
	end
	
	return table.unpack(newTab)
end

local function ReplaceTweenInfo(CustomTween: CustomTween, newTweenInfo: TweenInfo, propertyTable: PropertyTable)
	local previousTween = CustomTween._createdTween
	local twinfo = CustomTween.TweenInfo

	local newTweenInfo = newTweenInfo
	local newTween = TweenService:Create(CustomTween.Instance, newTweenInfo, propertyTable)
	CustomTween.TweenInfo = newTweenInfo
	CustomTween._createdTween = nil :: any --__newindex wouldn't run because it is already set
	CustomTween._createdTween = newTween
	previousTween:Cancel()
	return newTween
end

local function SetMainMethods(self: CustomTween, Class: SharpTween, propertyTable: PropertyTable, initialProperties: PropertyTable, mainTrove: Trove.Trove)
	local element = self.Instance
	local DefaultProperties = table.clone(propertyTable)
	local preloaded = false
	local playing = false
	local RegularAlpha: number?, progress = 0, 0
	local lastPlayed: number?
	local speedMultiplier = 1
	local thread: thread?
	local waitSignal = LemonSignal.new()
	local isPreloading = false
	local hasToWait = false
	
	self.newAttributeSignal:Connect(function()
		if #self.observedAttributes > 0 then
			self:Cancel()
		end
	end)
	
	function self:Clone()
		local newTween = Class:Create(element, self.TweenInfo, propertyTable)
		return newTween
	end

	function self:Cancel()
		if thread then
			pcall(task.cancel, thread)
			thread = nil
		end
		
		playing = false -- to avoid race conditions
		self.isPreloadedRunning = false
		RegularAlpha, progress = self:GetAlpha()
		self.PreloadedAlpha = 0
		self.PreloadedProgress = 0
		self._createdTween:Cancel()
		-- self.Completed:Fire() Completed should already fire if the tween is cancelled
	end

	function self:Pause()
		playing = false
		RegularAlpha, progress = self:GetAlpha()
		self._createdTween:Pause()
	end
	
	function self:Play()
		if #self.observedAttributes > 0 or self.isPreloadedRunning or playing then
			return
		end
		
		if element ~= self.Instance or self.TweenInfo ~= self._createdTween.TweenInfo then
			ReplaceTweenInfo(self, self.TweenInfo, propertyTable)
			element = self.Instance
		end
		
		playing = true
		RegularAlpha = nil
		lastPlayed = os.clock()
		
		self._createdTween:Play()
	end
	
	function self:AdjustMultiplier(newMultiplier: number?)
		if newMultiplier then
			assert(typeof(newMultiplier) == "number", "newMultiplier has to be a number or nil")
		else
			newMultiplier = 1
		end
		
		speedMultiplier = newMultiplier :: number
		self:AdjustTime(self.InitialTweenInfo.Time)
	end
	
	function self:GetPropertyTable()
		return propertyTable
	end
	
	function self:Preload(fps: number?, overrides: boolean?)
		if preloaded and not overrides then
			return
		end
		
		local twinfo = self.TweenInfo
		
		local fps = fps or DEFAULT_FPS
		local steps = math.floor(twinfo.Time * fps)
		self.frames = {}
		self.fps = fps

		for i = 1, steps do
			local alpha = i / steps
			-- easing aplicado
			local eased = if self.Bezier then self.Bezier(alpha) else TweenService:GetValue(alpha, twinfo.EasingStyle, twinfo.EasingDirection)
			local snapshot = {}
			for property, goal in pairs(propertyTable) do
				local start = (self.Instance :: any)[property]
				snapshot[property] = lerp(start, goal, eased)
			end
			self.frames[i] = snapshot
		end
		
		preloaded = true
	end
	
	function self:PlayPreloaded(newProgress: number?, goalProgress: number?)
		if #self.observedAttributes > 0 or playing then
			return
		end
		
		if self.PreloadedProgress >= 1 then
			self.PreloadedProgress = 0
		end
		
		if newProgress then
			assert(typeof(newProgress) == "number", "newProgress has to be a number or nil")
		end
		
		if goalProgress then
			assert(typeof(goalProgress) == "number", "goalProgress has to be a number or nil")
		end
		
		local twinfo = self.TweenInfo
		local newProgress = newProgress or self.PreloadedProgress
		
		if not preloaded or not self.frames then
			self:Preload()
			warnAttempt("Tween is not preloaded. Preloading manually")
		end
		
		playing = true
		self.isPreloadedRunning = true
		
		local goalFrame = if goalProgress then math.ceil(#self.frames * goalProgress) else #self.frames
		
		local startingNumber = math.ceil(#self.frames * newProgress)
		startingNumber = startingNumber > 0 and startingNumber or 1
		
		thread = task.spawn(function()
			local amountToSkip = 0
			
			for i = startingNumber, goalFrame do
				if not playing then
					break
				end
				
				self.PreloadedProgress = i / #self.frames
				self.PreloadedAlpha = TweenService:GetValue(self.PreloadedProgress, twinfo.EasingStyle, twinfo.EasingDirection)
				local toWait = 1 / self.fps
				
				if amountToSkip > 0 then
					amountToSkip -= toWait
					continue
				end
				
				for property, value in pairs(self.frames[i]) do
					(self.Instance :: any)[property] = value
				end
				
				local num = task.wait()
				if num > (toWait * 1.084) then
					amountToSkip += num - toWait
				end
			end
			
			if playing then
				playing = false
				self.isPreloadedRunning = false
				self.Completed:Fire()
			end
		end)
	end
	
	function self:SetInstanceToAlpha(alpha: number)
		if #self.observedAttributes > 0 then
			return
		end
		
		assert(typeof(progress) == "number", "alpha has to be a number")
		
		if not preloaded or not self.frames then
			self:Preload()
			warnAttempt("Tween is not preloaded. Preloading manually")
		end
		
		local clampedAlpha = math.clamp(alpha, 0, 1)

		local index = math.ceil(#self.frames * clampedAlpha)
		local frame = self.frames[index > 0 and index or 1]
		
		for property, value in pairs(frame) do
			(element :: any)[property] = value
		end
	end
	
	function self:GetAlpha()
		local twinfo = self.TweenInfo
		
		if not lastPlayed then -- CustomTween has not been played yet
			return 0, 0
		end
		
		if RegularAlpha and progress then
			return RegularAlpha, progress
		end
		
		local elapsed: number = os.clock() - lastPlayed
		local progress = elapsed / self.TweenInfo.Time
		local clampedProgress = math.clamp(progress, 0, 1)
		local alpha = TweenService:GetValue(clampedProgress, twinfo.EasingStyle, twinfo.EasingDirection)
		
		return alpha, clampedProgress
	end
	
	function self:AdjustTime(newTime: number)
		assert(typeof(newTime) == "number", "newTime has to be a number")
		
		newTime *= 1 / speedMultiplier
		
		local twinfo = self.TweenInfo
		
		local newTweenInfo = TweenInfo.new(newTime, twinfo.EasingStyle, twinfo.EasingDirection, twinfo.RepeatCount, twinfo.Reverses, twinfo.DelayTime)
		ReplaceTweenInfo(self, newTweenInfo, propertyTable)
		
		if playing and not self.isPreloadedRunning then
			self._createdTween:Play()
		end
	end
	
	function self:AdjustDelayTime(delayTime: number)
		assert(typeof(delayTime) == "number", "delayTime has to be a number")

		local twinfo = self.TweenInfo

		local newTweenInfo = TweenInfo.new(twinfo.Time, twinfo.EasingStyle, twinfo.EasingDirection, twinfo.RepeatCount, twinfo.Reverses, delayTime)
		ReplaceTweenInfo(self, newTweenInfo, propertyTable)
		
		if playing and not self.isPreloadedRunning then
			self._createdTween:Play()
		end
	end
	
	function self:SetAlpha(alpha: number)
		assert(typeof(alpha) == "number", "alpha has to be a number")
		local clampedAlpha = math.clamp(alpha, 0, 1)
		local newTime = self.InitialTweenInfo.Time * (1 - clampedAlpha)
		self:AdjustTime(newTime)
	end
	
	function self:RandomizeProperties(percentage: number)
		assert(typeof(percentage) == "number", "percentage has to be a number")
		
		if percentage == 0 then
			propertyTable = table.clone(DefaultProperties)
			ReplaceTweenInfo(self, self.TweenInfo, propertyTable)
			return
		end
		
		for property, value in pairs(DefaultProperties) do			
			local newValue: any
			
			if typeof(value) == "UDim2" then
				local obtainedOffsetX = value.X.Offset * percentage / 100
				local obtainedOffsetY = value.Y.Offset * percentage / 100
				
				local changedOffsetX, changedOffsetY = GetFromRandom(obtainedOffsetX, obtainedOffsetY)
				
				local obtainedScaleX = value.X.Scale * percentage / 100
				local obtainedScaleY = value.Y.Scale * percentage / 100
				
				local changedScaleX, changedScaleY = GetFromRandom(obtainedScaleX, obtainedScaleY)
				
				newValue = UDim2.new(value.X.Scale + changedScaleX, value.X.Offset + changedOffsetX, value.Y.Scale + changedScaleY, value.Y.Offset + changedOffsetY)
			elseif typeof(value) == "Vector2" or typeof(value) == "Vector3" then
				local obtainedX, obtainedY, obtainedZ = value.X, value.Y, typeof(value) == "Vector3" and value.Z or nil
				local changedX, changedY, changedZ = GetFromRandom(obtainedX, obtainedY, obtainedZ)
				
				if typeof(value) == "Vector2" then
					newValue = Vector2.new(value.X + changedX, value.Y + changedY)
				else
					newValue = Vector3.new(value.X + changedX, value.Y + changedY, value.Z + changedZ)
				end
			elseif typeof(value) == "CFrame" then
				local PosVector = value.Position
				local LookVector = value.LookVector
				
				local obtainedXPos, obtainedYPos, obtainedZPos = PosVector.X, PosVector.Y, PosVector.Z
				local changedXPos, changedYPos, changedZPos = GetFromRandom(obtainedXPos, obtainedYPos, obtainedZPos)
				
				local newPosVector = Vector3.new(changedXPos, changedYPos, changedZPos)
				
				local obtainedXLook, obtainedYLook, obtainedZLook = LookVector.X, LookVector.Y, LookVector.Z
				local changedXLook, changedYLook, changedZLook = GetFromRandom(obtainedXLook, obtainedYLook, obtainedZLook)
				
				local newLookVector = Vector3.new(changedXLook, changedYLook, changedZLook)
				
				newValue = CFrame.new(newPosVector, newLookVector)
			elseif typeof(value) == "number" then
				local obtainedNum = value * percentage / 100
				local changedNum = GetFromRandom(obtainedNum)
			
				newValue = value + changedNum
			elseif typeof(value) == "Color3" then
				local obtainedR, obtainedG, obtainedB = value.R, value.G, value.B
				local changedR, changedG, changedB = GetFromRandom(obtainedR, obtainedG, obtainedB)
				
				newValue = Color3.new(
					math.clamp(value.R + changedR, 0, 1),
					math.clamp(value.G + changedG, 0, 1),
					math.clamp(value.B + changedB, 0, 1)
				)
			elseif typeof(value) == "UDim" then
				local obtainedScale = value.Scale * percentage / 100
				local obtainedOffset = value.Offset * percentage / 100
				
				local changedScale, changedOffset = GetFromRandom(obtainedScale, obtainedOffset)
				
				newValue = UDim.new(value.Scale + changedScale, value.Offset + changedOffset)
			end
			
			propertyTable[property] = newValue
			ReplaceTweenInfo(self, self.TweenInfo, propertyTable)
		end
	end
	
	function self:GetReverse()
		local newTween = Class:Create(element, self.TweenInfo, initialProperties)
		return newTween
	end
	
	function self:UpdateInitialProperties()
		for property, _ in pairs(initialProperties) do
			initialProperties[property] = (element :: any)[property]
		end
	end
	
	function self:GetPropertyChangedSignal(property: "PlaybackState" | string)
		local check = self._createdTween:GetPropertyChangedSignal(property)
		self.PropertyChangedSignals[property] = self.PropertyChangedSignals[property] or LemonSignal.new()
		return self.PropertyChangedSignals[property]
	end
	
	return self -- to get the type
end

local function IterateOverMethods(group: CustomTweenGroup, iteratedSignal: LemonSignal.Signal<>, key: string, ...)
	local returnedValues = {}
	local secondaryReturnedValues = {}
	local args = {...}

	task.defer(function()
		for _, custom in pairs(group.GroupTweens) do
			local func = custom[key]
			local returnedValue, returnedValue2 = func(custom, table.unpack(args))
			if returnedValue2 then
				table.insert(secondaryReturnedValues, returnedValue2)
			end
			table.insert(returnedValues, returnedValue)
		end

		group.isParsing = false
		iteratedSignal:Fire()
	end)
	
	return returnedValues, secondaryReturnedValues
end

-----------------------------
-- PUBLIC FUNCTIONS --
-----------------------------

function SharpTween.NewBezier(controlPoints: {{x: number, y: number}})
	-- return easing function
	return 
		@native 
		function(alpha: number): number
		assert(alpha, "alpha has to be a number")

		-- find param `t` such that bezierX(t) ~= alpha
		-- approximate with Newton-Raphson
		local t = alpha
		for _ = 1, 6 do
			local x = bezier1D(t, "x", controlPoints)
			local dx = (bezier1D(t + 1e-5, "x", controlPoints) - bezier1D(t - 1e-5, "x", controlPoints)) / 2e-5
			if dx == 0 then break end
			t -= (x - alpha) / dx
			if t < 0 then t = 0 elseif t > 1 then t = 1 end
		end
		-- evaluate y
		return bezier1D(t, "y", controlPoints)
	end
end

-- Automatically redirects all created CustomTweens to the given group. Useful for attribute observation without manually adding each CustomTween to the group.
function SharpTween:SetDefaultGroup(Group: CustomTweenGroup)
	self.NewCustomTween:DisconnectAll()
	
	if not Group then
		return
	end
	
	self.NewCustomTween:Connect(function(CustomTween: CustomTween)
		Group:Add(CustomTween)
	end)
end

--[[
Creates a tween group object for batching operations across multiple CustomTweens.

If an inherited CustomTween method returns a value, calling that method returns a
list of all the returned values provided by the CustomTweens.
]]
function SharpTween.new(): CustomTweenGroup
	local newSignal = LemonSignal.new()
	
	local newGroup = {} :: CustomTweenGroup
	newGroup.observedAttributes = {}
	newGroup.GroupTweens = {}
	newGroup.AutoWait = false
	newGroup.isParsing = false
	
	local iteratedSignal = LemonSignal.new()
	
	setmetatable(newGroup :: {}, {
		__index = function(tab, key): any
			local exists = inheritedMethods[key]

			if exists then
				newGroup.isParsing = true
				
				return function(_, ...)
					local values, values2 = IterateOverMethods(newGroup, iteratedSignal, key, ...)
					if newGroup.AutoWait then
						newGroup:WaitTweens()
					end
					return values, values2
				end
			else
				return rawget(tab, key)
			end
		end,
	})
	
	function newGroup:Add(newCustomTween: CustomTween)
		for _, attribute in pairs(newGroup.observedAttributes) do
			newCustomTween.StartObservingAttribute(attribute)
		end
		
		table.insert(self.GroupTweens, newCustomTween)
	end
	
	function newGroup:Remove(CustomTween: CustomTween)
		local index = table.find(self.GroupTweens, CustomTween)
		
		if index then
			table.remove(self.GroupTweens, index)
		end
	end
	
	function newGroup:WaitTweens()
		if newGroup.isParsing then
			iteratedSignal:Wait()
		end
	end
	
	function newGroup:NewObserver(attribute: string)
		table.insert(newGroup.observedAttributes, attribute)
		
		for _, CustomTween in pairs(newGroup.GroupTweens) do
			CustomTween.StartObservingAttribute(attribute)
		end
	end
	
	function newGroup:RemoveObserver(attribute: string)
		local index = table.find(newGroup.observedAttributes, attribute)
		if index then
			table.remove(newGroup.observedAttributes, index)
		end
		
		for _, CustomTween in pairs(newGroup.GroupTweens) do
			CustomTween.StopObservingAttribute(attribute)
		end
	end
	
	return newGroup
end

function SharpTween:Create(instance: Instance & any, twinfo: TweenInfo, propertyTable: PropertyTable): CustomTween
	local mainTrove = Trove.new()
	
	local initialProperties = {}

	for property, _ in pairs(propertyTable) do
		initialProperties[property] = (instance :: any)[property]
	end
	
	local base = GetCustomTween(mainTrove)
	base.newAttributeSignal = LemonSignal.new()
	
	base.observerSignals = {}
	base.observedAttributes = {}
	base.Instance = instance
	base.PreloadedAlpha = 0
	base.PreloadedProgress = 0
	
	base.StartObservingAttribute = function(self, attribute: string)
		StartObservingAttribute(base, attribute)
	end
	base.StopObservingAttribute = function(self, attribute: string)
		StopObservingAttribute(base, attribute)
	end
	
	base.PlaybackState = Enum.PlaybackState.Begin
	base.TweenInfo = twinfo
	base.InitialTweenInfo = twinfo
	
	base.Completed = LemonSignal.new()
	base.PropertyChangedSignals = {}

	base._createdTween = TweenService:Create(instance, twinfo, propertyTable)
	SetMainMethods(base, self, propertyTable, initialProperties, mainTrove)

	base.newAttributeSignal:Connect(function(attribute: string)
		if instance:GetAttribute(attribute) then
			base:Pause()
		end
	end)
	self.CustomTweens[instance] = self.CustomTweens[instance] or {}
	table.insert(self.CustomTweens[instance], base)
	
	self.NewCustomTween:Fire(base)
	return base
end

function Constructor.Init(): typeof(SharpTween) & SharpTween -- typeof to get the function comments
	local newSharpTween = setmetatable({
		NewCustomTween = LemonSignal.new(),
		CustomTweens = setmetatable({}, {__mode = "kv"})
	}, SharpTween :: any) :: any
	return newSharpTween
end

-----------------------------
-- BENCHMARK --
-----------------------------
--[[
--Rename the module to SharpTween.bench and benchmark it with the Scriptbench plugin by @bitsplicer

local benchSharpTween = Constructor.Init()
local instance = Instance.new("Frame")
local twinfo = TweenInfo.new(1)
local propertyTable = {Position = UDim2.new(1, 0, 1, 0)}

local CustomTween = benchSharpTween:Create(instance, twinfo, propertyTable)
CustomTween:Preload()
local RegularTween = TweenService:Create(instance, twinfo, propertyTable)

local benchmarkTab = {
	Name = "SharpTween and TweenService",

	Parameter = function()
		return math.random(1,100)
	end,

	-- These optional functions also exist, and can be used to set up and tear down the environment without
	-- interfering with the benchmark results.
	BeforeAll = function() end,
	AfterAll = function() end,
	BeforeEach = function() end,
	AfterEach = function() end,

	Functions = {
		["Create"] = function(lib)
			lib.profilebegin("call")
			benchSharpTween:Create(instance, twinfo, propertyTable)
			lib.profileend()
		end,
		["Play"] = function(lib)
			lib.profilebegin("call")
			RegularTween:Play()
			lib.profileend()
		end,
		["CustomTween Play"] = function(lib)
			lib.profilebegin("call")
			CustomTween:Play()
			lib.profileend()
		end,
		["Preload"] = function(lib)
			lib.profilebegin("call")
			CustomTween:Preload(nil, true)
			lib.profileend()
		end,
		["PlayPreloaded"] = function(lib)
			lib.profilebegin("call")
			CustomTween:PlayPreloaded()
			lib.profileend()
		end
	}
}

if true then
	return benchmarkTab
end
--]]

return Constructor
