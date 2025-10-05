<div align="center">
	
# SharpTween - Extended Tweening Library
	
<img width="690" height="180" alt="SharpTween logo sin fondo" src="https://github.com/user-attachments/assets/33765284-a1a3-4723-90d7-a3ae792cc134" 
/>
#### *Ilustration by [Doual Studio](https://www.instagram.com/doualstudio?igsh=dWJlNGJqdjAzbGlx)*
</div>

## [See more - DevForum post](https://devforum.roblox.com/t/sharptween-extended-tweening-library/3962195)

### Documentation
**CONSTRUCTOR**

```luau
Constructor.Init() SharpTween
"Returns a SharpTween object"
```

**SharpTween PROPERTIES**

```luau
CustomTweens table {CustomTween}
"Created CustomTweens are stored here"
```
```luau
NewCustomTween LemonSignal<CustomTween> LemonSignal.new()
"Fired when a CustomTween is created"
```

**SharpTween METHODS**
```luau
Create(self: SharpTween, ...) CustomTween
"Creates a new CustomTween"
```

```luau
new(self: SharpTween) ()
"Returns a new group"
```

```luau
SetDefaultGroup(group: CustomTweenGroup) ()
"Created CustomTweens will now be redirected to the given group"
```

**CustomTween and CustomTweenGroup METHODS**
```luau
type InheritedMethods<self> = {
	PlayPreloaded: (self: self, newProgress: number?, goalProgress: number?) -> (),
	Preload: (self: self, fps: number?, overrides: boolean?) -> (),
	SetInstanceToAlpha: (self: self, alpha: number) -> (),
	AdjustTime: (self: self, newTime: number) -> (),
	AdjustDelayTime: (self: self, delayTime: number) -> (),
	GetReverse: (self: self) -> CustomTween,
	UpdateInitialProperties: (self: self) -> (),
	GetAlpha: (self: self) -> (number, number),
	SetAlpha: (self: self, alpha: number) -> (),
	RandomizeProperties: (self: self, percentage: number) -> (),
	Clone: (self: self) -> (),
	Cancel: (self: self) -> (),
	Pause: (self: self) -> (),
	Play: (self: self) -> (),
}
```
### Examples
**Creating a CustomTween**

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharpTween = require(ReplicatedStorage.SharpTween).Init()

local Frame = Instance.new("Frame")
local twinfo = TweenInfo.new(1)
local goal = {Position = UDim2.fromScale(1, 1)}

local newTween = SharpTween:Create(Frame, twinfo, goal)
```

**Playing a CustomTween**
```luau
newTween:Play()
-- or --
newTween:Preload()
newTween:PlayPreloaded()

task.wait(1)

-- will work, no need to preload twice
newTween:PlayPreloaded(0.1, 0.5) 
-- the tweening will start at 0.1
-- and stop when the progress hits 0.5
```
>Calling PlayPreloaded() when the CustomTween is already playing has no effect, just like a regular Tween. Setting a *goalProgress* as seen in the example (0.5) will fire the Completed Event after the progress is hit.
```
>Calling PlayPreload() when the CustomTween is already playing has no effect, just like a regular Tween.

**Preloading with a specific framerate**
```luau
newTween:Preload(120)
newTween:PlayPreloaded()

task.wait(1)

newTween:Preload(75, true) -- overwrite preloaded frames
newTween:PlayPreloaded()
```
**Setting the instance to a given point in the interpolation**
```luau
local Frame = Instance.new("Frame")
local twinfo = TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
local goal = {Position = UDim2.fromScale(1, 1)}
local newTween = SharpTween:Create(Frame, twinfo, goal)
newTween:Preload()

print(Frame.Position)
-- output: {0, 0}, {0, 0}

newTween:SetInstanceToAlpha(0.5)

print(Frame.Position)
-- output: {0.5, 0}, {0.5, 0}
```

> Preloading is optional, if not preloaded, it will do it automatically. However, it is recommended to avoid lag.

**Randomizing properties**
```luau
newTween:SetInstanceToAlpha(1)
print(Frame.Position)
-- output: {1, 0}, {1, 0}

newTween:RandomizeProperties(10) -- randomize the properties up to a 10%
newTween:Preload(nil, true) -- Default fps, overwrite preloaded frames

newTween:SetInstanceToAlpha(1)
print(newTween)
-- output in this case: {1.01728737, 0}, {1.05772877, 0} 
```
**Play reverse**
```luau
local reverseTween = newTween:GetReverse()

newTween:Play()
task.wait(1)
print(Frame.Position)
-- output: {1, 0}, {1, 0}

reverseTween:Play()
task.wait(1)
print(Frame.Position)
-- output: {0, 0}, {0, 0}
```
**Play preloaded reverse**
```luau
newTween:Play()
task.wait(1)
print(Frame.Position)
-- output: {1, 0}, {1, 0}

-- update the initial properties as they're the goal for the
-- reverse, if not, it would remain in {0, 0}, {0, 0} (The position where it was created).
newTween:UpdateInitialProperties()

local reverseTween = newTween:GetReverse()
reverseTween:Preload()
reverseTween:PlayPreloaded()
task.wait(1)
print(Frame.Position)
-- output: {0, 0}, {0, 0}
```
**SetAlpha() usage example**
```luau
-- Goal: Start the tween from a given alpha

local ALPHA = 0.8

newTween:SetInstanceToAlpha(ALPHA) -- sets the instance to that point
newTween:SetAlpha(ALPHA) -- adjusts the time with the given alpha
newTween:Play()
```
**SetDefaultGroup() usage example**
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharpTween = require(ReplicatedStorage.SharpTween).Init()

local Frame = Instance.new("Frame")
local TextLabel = Instance.new("TextLabel")

local twinfo = TweenInfo.new(1)

local Group = SharpTween.new()
SharpTween:SetDefaultGroup(group)

Group:NewObserver("Blue")

local newTween1 = SharpTween:Create(Frame, twinfo, {Position = UDim2.fromScale(1, 1)})
local newTween2 = SharpTween:Create(TextLabel, twinfo, {Size = UDim2.fromScale(0, 1)})

-- both CustomTweens will be added to the group automatically and will
-- listen to the attribute "Blue"

SharpTween:SetDefaultGroup(nil)

local newTween3 = SharpTween:Create(TextLabel, twinfo, {Size = UDim2.fromScale(0, 1)})
-- will not be added to the group automatically.
```
**[ADDED] AdjustMultiplier() usage example**
```luau
local CustomTween = SharpTween:Create(Frame2, twinfo, {Position = UDim2.fromScale(0.9, Frame2.Position.Y.Scale)})

CustomTween:AdjustMultiplier(2)
CustomTween:Play()
```

> The Speed Multiplier can be changed while the CustomTween is playing! Works best in pair with PlayPreloaded(), as the easing isn't reset.

**[ADDED] Bezier curves usage example**
```luau
local CustomTween = SharpTween:Create(Frame2, twinfo, {Position = UDim2.fromScale(0.9, Frame2.Position.Y.Scale)})

-- cuadratic curve in this case
CustomTween.Bezier = SharpTween.NewBezier({
	{x=0, y=0},
	{x=0.5, y=1},
	{x=1, y=1},
})

CustomTween:Preload(120)

-- PlayPreloaded() as inserting bezier curves in regular Tweens is not possible
CustomTween:PlayPreloaded() 
```

> No limit on the amount of elements in the table!

**AutoWait property usage example**
```luau
Group.AutoWait = true

Group:Play() -- Yields the script until Play() is called upon every group member
Group:Cancel() -- should not cause any issue. Yields too
```

> Without AutoWait, the function WaitTweens() should be called after Play() to avoid issues.
