--[[
    ============================================================================
    PlowUI v3.1 - Delta Executor & Mobile-Optimized Edition
    Author: Moizrgi
    Architecture: Modular Single-File / Zero-Leak Maid / Reactive Theme Engine /
                  4-Component UDim2 Spring Physics / HSV ColorPicker / SubTabs /
                  Modals / Custom Component & Plugin API / Multi-Window Manager
                  + Delta Mobile Compatibility, Virtual Keybind Trigger & Touch UX
    ============================================================================
]]

local PlowUI = {
    Version = "3.1.0",
    Windows = {},
    Plugins = {},
    CustomComponents = {},
    _connections = {}
}
PlowUI.__index = PlowUI

-- ============================================================================
-- 1. SERVICIOS Y ENTORNO MULTIPLATAFORMA (DELTA EXECUTOR & MÓVIL)
-- ============================================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local function IsDeltaMobileEnv()
    local ok, mobile = pcall(function()
        return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    end)
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    return (ok and mobile) or (vp.X <= 820 and UserInputService.TouchEnabled)
end

local function GetSafeGuiParent()
    local targets = {
        function() return (gethui and gethui()) end,
        function() return (syn and syn.protect_gui and CoreGui) end,
        function() return CoreGui end,
        function() return LocalPlayer:WaitForChild("PlayerGui", 10) end
    }
    for _, getter in ipairs(targets) do
        local ok, res = pcall(getter)
        if ok and typeof(res) == "Instance" then
            if syn and syn.protect_gui and res == CoreGui then
                pcall(syn.protect_gui, res)
            end
            return res
        end
    end
    return LocalPlayer:FindFirstChildOfClass("PlayerGui") or workspace
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[PlowUI Callback Error]: " .. tostring(err))
    end
end

local function SanitizeFileName(name)
    local clean = tostring(name or "default"):gsub("[^%w%-%_]", "_")
    if clean == "" then clean = "default" end
    return clean
end

local function CanWriteFiles()
    return type(writefile) == "function" and type(HttpService.JSONEncode) == "function"
end

local function CanReadFiles()
    return type(isfile) == "function" and type(readfile) == "function" and type(HttpService.JSONDecode) == "function"
end

-- ============================================================================
-- 2. SISTEMA DE GESTIÓN DE MEMORIA (MAID) & SEÑALES SEGURAS (SIGNAL)
-- ============================================================================
local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({ _tasks = {} }, Maid)
end

function Maid:GiveTask(taskObj, customId)
    local id = customId or HttpService:GenerateGUID(false)
    if self._tasks[id] then
        self:CleanTask(id)
    end
    self._tasks[id] = taskObj
    return id
end

function Maid:CleanTask(id)
    local taskObj = self._tasks[id]
    if not taskObj then return end
    self._tasks[id] = nil

    if typeof(taskObj) == "RBXScriptConnection" then
        if taskObj.Connected then
            pcall(function() taskObj:Disconnect() end)
        end
    elseif typeof(taskObj) == "Instance" then
        pcall(function() taskObj:Destroy() end)
    elseif type(taskObj) == "function" then
        SafeCall(taskObj)
    elseif type(taskObj) == "table" and type(taskObj.Destroy) == "function" then
        SafeCall(taskObj.Destroy, taskObj)
    end
end

function Maid:DoCleaning()
    local keys = {}
    for k in pairs(self._tasks) do
        table.insert(keys, k)
    end
    for _, k in ipairs(keys) do
        self:CleanTask(k)
    end
end

function Maid:Destroy()
    self:DoCleaning()
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _listeners = {}, _destroyed = false }, Signal)
end

function Signal:Connect(fn)
    if self._destroyed or type(fn) ~= "function" then
        return { Disconnect = function() end }
    end
    local listener = { fn = fn, connected = true }
    table.insert(self._listeners, listener)
    return {
        Disconnect = function()
            if not listener.connected then return end
            listener.connected = false
            for i, v in ipairs(self._listeners) do
                if v == listener then
                    table.remove(self._listeners, i)
                    break
                end
            end
        end
    }
end

function Signal:Once(fn)
    local conn
    conn = self:Connect(function(...)
        conn:Disconnect()
        fn(...)
    end)
    return conn
end

function Signal:Fire(...)
    if self._destroyed then return end
    local snapshot = table.clone(self._listeners)
    for _, listener in ipairs(snapshot) do
        if listener.connected then
            task.spawn(SafeCall, listener.fn, ...)
        end
    end
end

function Signal:Destroy()
    self._destroyed = true
    for _, listener in ipairs(self._listeners) do
        listener.connected = false
    end
    table.clear(self._listeners)
end

-- ============================================================================
-- 3. MOTOR DE ANIMACIONES AVANZADO (SPRINGS DE 4 EJES, TWEENS, CONTROL TOTAL)
-- ============================================================================
local Animator = {
    ActiveSprings = {},
    ActiveTweens = {},
    GradientLoops = {},
    Paused = false
}

local function CreateZeroVelocity(sample)
    local t = typeof(sample)
    if t == "number" then
        return 0
    elseif t == "UDim2" then
        return { XS = 0, XO = 0, YS = 0, YO = 0 }
    elseif t == "UDim" then
        return { S = 0, O = 0 }
    elseif t == "Vector2" then
        return Vector2.zero
    elseif t == "Vector3" then
        return Vector3.zero
    elseif t == "Color3" then
        return { R = 0, G = 0, B = 0 }
    end
    return 0
end

function Animator:CancelSpring(instance, property)
    if not instance or not Animator.ActiveSprings[instance] then return end
    if property then
        Animator.ActiveSprings[instance][property] = nil
        if next(Animator.ActiveSprings[instance]) == nil then
            Animator.ActiveSprings[instance] = nil
        end
    else
        Animator.ActiveSprings[instance] = nil
    end
end

function Animator:CancelAllForInstance(instance)
    self:CancelSpring(instance)
    if Animator.ActiveTweens[instance] then
        for _, tw in pairs(Animator.ActiveTweens[instance]) do
            pcall(function() tw:Cancel() end)
        end
        Animator.ActiveTweens[instance] = nil
    end
    for grad in pairs(Animator.GradientLoops) do
        if grad == instance or (grad and pcall(function() return grad:IsDescendantOf(instance) end) and grad:IsDescendantOf(instance)) then
            Animator.GradientLoops[grad] = nil
        end
    end
end

function Animator:PauseAll()
    Animator.Paused = true
    for _, tweens in pairs(Animator.ActiveTweens) do
        for _, tw in pairs(tweens) do
            pcall(function() tw:Pause() end)
        end
    end
end

function Animator:ResumeAll()
    Animator.Paused = false
    for _, tweens in pairs(Animator.ActiveTweens) do
        for _, tw in pairs(tweens) do
            pcall(function() tw:Play() end)
        end
    end
end

function Animator:Spring(instance, property, target, damping, frequency, onComplete)
    if not instance or not instance.Parent then return end
    damping = damping or 0.75
    frequency = frequency or 14

    if not Animator.ActiveSprings[instance] then
        Animator.ActiveSprings[instance] = {}
    end

    local okProp, current = pcall(function() return instance[property] end)
    if not okProp or current == nil then return end

    local existing = Animator.ActiveSprings[instance][property]
    local velocity = existing and existing.Velocity or CreateZeroVelocity(current)

    Animator.ActiveSprings[instance][property] = {
        Current = current,
        Target = target,
        Velocity = velocity,
        Damping = damping,
        Frequency = frequency,
        OnComplete = onComplete
    }
end

function Animator:Tween(instance, info, properties, onComplete)
    if not instance or not instance.Parent then return nil end
    if not Animator.ActiveTweens[instance] then
        Animator.ActiveTweens[instance] = {}
    end
    local key = table.concat((function()
        local k = {}
        for prop in pairs(properties) do table.insert(k, prop) end
        table.sort(k)
        return k
    end)(), "_")

    if Animator.ActiveTweens[instance][key] then
        pcall(function() Animator.ActiveTweens[instance][key]:Cancel() end)
    end

    local okCreate, tween = pcall(function()
        return TweenService:Create(instance, info, properties)
    end)
    if not okCreate or not tween then return nil end

    Animator.ActiveTweens[instance][key] = tween
    tween.Completed:Connect(function(state)
        if Animator.ActiveTweens[instance] and Animator.ActiveTweens[instance][key] == tween then
            Animator.ActiveTweens[instance][key] = nil
            if next(Animator.ActiveTweens[instance]) == nil then
                Animator.ActiveTweens[instance] = nil
            end
        end
        if state == Enum.PlaybackState.Completed and onComplete then
            SafeCall(onComplete)
        end
    end)
    if not Animator.Paused then
        pcall(function() tween:Play() end)
    end
    return tween
end

local GlobalRenderConnection = RunService.RenderStepped:Connect(function(dt)
    if Animator.Paused then return end
    dt = math.min(dt, 0.05)

    for instance, props in pairs(Animator.ActiveSprings) do
        if not instance or not instance.Parent then
            Animator.ActiveSprings[instance] = nil
            continue
        end

        for prop, data in pairs(props) do
            local k = data.Frequency * data.Frequency
            local c = 2 * data.Damping * data.Frequency
            local target = data.Target
            local t = typeof(target)
            local finished = false

            if t == "number" then
                local force = (target - data.Current) * k
                data.Velocity = (data.Velocity + force * dt) / (1 + c * dt)
                data.Current = data.Current + data.Velocity * dt
                instance[prop] = data.Current

                if math.abs(target - data.Current) < 0.001 and math.abs(data.Velocity) < 0.001 then
                    instance[prop] = target
                    finished = true
                end

            elseif t == "UDim2" then
                local fxs = (target.X.Scale - data.Current.X.Scale) * k
                local fxo = (target.X.Offset - data.Current.X.Offset) * k
                local fys = (target.Y.Scale - data.Current.Y.Scale) * k
                local fyo = (target.Y.Offset - data.Current.Y.Offset) * k

                data.Velocity.XS = (data.Velocity.XS + fxs * dt) / (1 + c * dt)
                data.Velocity.XO = (data.Velocity.XO + fxo * dt) / (1 + c * dt)
                data.Velocity.YS = (data.Velocity.YS + fys * dt) / (1 + c * dt)
                data.Velocity.YO = (data.Velocity.YO + fyo * dt) / (1 + c * dt)

                local nxs = data.Current.X.Scale + data.Velocity.XS * dt
                local nxo = data.Current.X.Offset + data.Velocity.XO * dt
                local nys = data.Current.Y.Scale + data.Velocity.YS * dt
                local nyo = data.Current.Y.Offset + data.Velocity.YO * dt

                data.Current = UDim2.new(nxs, nxo, nys, nyo)
                instance[prop] = data.Current

                if math.abs(target.X.Scale - nxs) < 0.0005
                    and math.abs(target.X.Offset - nxo) < 0.1
                    and math.abs(target.Y.Scale - nys) < 0.0005
                    and math.abs(target.Y.Offset - nyo) < 0.1
                    and math.abs(data.Velocity.XS) < 0.001
                    and math.abs(data.Velocity.XO) < 0.15
                    and math.abs(data.Velocity.YS) < 0.001
                    and math.abs(data.Velocity.YO) < 0.15 then
                    instance[prop] = target
                    finished = true
                end

            elseif t == "UDim" then
                local fs = (target.Scale - data.Current.Scale) * k
                local fo = (target.Offset - data.Current.Offset) * k
                data.Velocity.S = (data.Velocity.S + fs * dt) / (1 + c * dt)
                data.Velocity.O = (data.Velocity.O + fo * dt) / (1 + c * dt)
                local ns = data.Current.Scale + data.Velocity.S * dt
                local no = data.Current.Offset + data.Velocity.O * dt
                data.Current = UDim.new(ns, no)
                instance[prop] = data.Current

                if math.abs(target.Scale - ns) < 0.0005 and math.abs(target.Offset - no) < 0.1 then
                    instance[prop] = target
                    finished = true
                end

            elseif t == "Vector2" or t == "Vector3" then
                local force = (target - data.Current) * k
                data.Velocity = (data.Velocity + force * dt) / (1 + c * dt)
                data.Current = data.Current + data.Velocity * dt
                instance[prop] = data.Current

                if (target - data.Current).Magnitude < 0.002 and data.Velocity.Magnitude < 0.005 then
                    instance[prop] = target
                    finished = true
                end

            elseif t == "Color3" then
                local fr = (target.R - data.Current.R) * k
                local fg = (target.G - data.Current.G) * k
                local fb = (target.B - data.Current.B) * k

                data.Velocity.R = (data.Velocity.R + fr * dt) / (1 + c * dt)
                data.Velocity.G = (data.Velocity.G + fg * dt) / (1 + c * dt)
                data.Velocity.B = (data.Velocity.B + fb * dt) / (1 + c * dt)

                local r = math.clamp(data.Current.R + data.Velocity.R * dt, 0, 1)
                local g = math.clamp(data.Current.G + data.Velocity.G * dt, 0, 1)
                local b = math.clamp(data.Current.B + data.Velocity.B * dt, 0, 1)

                data.Current = Color3.new(r, g, b)
                instance[prop] = data.Current

                if math.abs(target.R - r) < 0.002
                    and math.abs(target.G - g) < 0.002
                    and math.abs(target.B - b) < 0.002 then
                    instance[prop] = target
                    finished = true
                end
            end

            if finished then
                local cb = data.OnComplete
                props[prop] = nil
                if next(props) == nil then
                    Animator.ActiveSprings[instance] = nil
                end
                if cb then
                    task.spawn(SafeCall, cb)
                end
            end
        end
    end

    for gradient, config in pairs(Animator.GradientLoops) do
        if not gradient or not gradient.Parent then
            Animator.GradientLoops[gradient] = nil
            continue
        end
        if not config.Paused then
            gradient.Rotation = (gradient.Rotation + (config.Speed * dt)) % 360
        end
    end
end)

table.insert(PlowUI._connections, GlobalRenderConnection)
PlowUI.Animator = Animator

-- ============================================================================
-- 4. UTILIDADES VISUALES Y SHADERS UI (FX)
-- ============================================================================
local FX = {}

function FX.Create(className, properties, children)
    local inst = Instance.new(className)
    for k, v in pairs(properties or {}) do
        pcall(function() inst[k] = v end)
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

function FX.ApplyGlass(frame, transparency, borderColor, thickness)
    frame.BackgroundTransparency = transparency or 0.25
    local existing = frame:FindFirstChildOfClass("UIStroke")
    if existing then existing:Destroy() end

    local stroke = FX.Create("UIStroke", {
        Color = borderColor or Color3.fromRGB(255, 255, 255),
        Transparency = 0.8,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = frame
    })
    return stroke
end

function FX.AnimatedGradient(parent, colors, speed, rotation)
    local existing = parent:FindFirstChildOfClass("UIGradient")
    if existing then
        Animator.GradientLoops[existing] = nil
        existing:Destroy()
    end

    local keypoints = {}
    for i, col in ipairs(colors) do
        table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), col))
    end
    local grad = FX.Create("UIGradient", {
        Color = ColorSequence.new(keypoints),
        Rotation = rotation or 45,
        Parent = parent
    })
    Animator.GradientLoops[grad] = { Speed = speed or 45, Paused = false }
    return grad
end

function FX.Ripple(button, rippleColor, inputPosition)
    if not button or not button.Parent then return end
    local pos = inputPosition
    if not pos then
        local ok, loc = pcall(function() return UserInputService:GetMouseLocation() end)
        pos = (ok and loc) or Vector2.new(button.AbsolutePosition.X + button.AbsoluteSize.X * 0.5, button.AbsolutePosition.Y + button.AbsoluteSize.Y * 0.5)
    end

    local relX = pos.X - button.AbsolutePosition.X
    local relY = pos.Y - button.AbsolutePosition.Y

    local ripple = FX.Create("Frame", {
        Name = "Ripple",
        BackgroundColor3 = rippleColor or Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.72,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, relX, 0, relY),
        Size = UDim2.new(0, 0, 0, 0),
        ZIndex = button.ZIndex + 3,
        Parent = button
    }, {
        FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
    })

    local maxSize = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.3
    Animator:Tween(ripple, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, maxSize, 0, maxSize),
        BackgroundTransparency = 1
    }, function()
        if ripple and ripple.Parent then
            ripple:Destroy()
        end
    end)
end

PlowUI.FX = FX

-- ============================================================================
-- 5. SISTEMA REACTIVO DE TEMAS (PREDETERMINADOS, PERSONALIZADOS Y ANIMADOS)
-- ============================================================================
local DefaultTheme = {
    Background = Color3.fromRGB(14, 14, 18),
    Surface = Color3.fromRGB(22, 23, 30),
    SurfaceHover = Color3.fromRGB(30, 32, 42),
    Primary = Color3.fromRGB(115, 95, 255),
    Secondary = Color3.fromRGB(0, 210, 255),
    TextPrimary = Color3.fromRGB(245, 245, 250),
    TextSecondary = Color3.fromRGB(150, 155, 175),
    Border = Color3.fromRGB(55, 58, 75),
    Success = Color3.fromRGB(50, 220, 130),
    Warning = Color3.fromRGB(255, 185, 50),
    Error = Color3.fromRGB(255, 75, 95),
    CornerRadius = UDim.new(0, 8),
    FontRegular = Enum.Font.Gotham,
    FontMedium = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold
}

PlowUI.Themes = {
    Dark = DefaultTheme,
    Cyber = {
        Background = Color3.fromRGB(10, 14, 22),
        Surface = Color3.fromRGB(16, 22, 36),
        SurfaceHover = Color3.fromRGB(24, 34, 54),
        Primary = Color3.fromRGB(0, 225, 255),
        Secondary = Color3.fromRGB(255, 45, 145),
        TextPrimary = Color3.fromRGB(240, 248, 255),
        TextSecondary = Color3.fromRGB(140, 160, 190),
        Border = Color3.fromRGB(40, 65, 95),
        Success = Color3.fromRGB(45, 235, 165),
        Warning = Color3.fromRGB(255, 195, 55),
        Error = Color3.fromRGB(255, 65, 105),
        CornerRadius = UDim.new(0, 8)
    },
    Emerald = {
        Background = Color3.fromRGB(11, 17, 15),
        Surface = Color3.fromRGB(18, 27, 24),
        SurfaceHover = Color3.fromRGB(26, 39, 34),
        Primary = Color3.fromRGB(30, 215, 130),
        Secondary = Color3.fromRGB(130, 245, 190),
        TextPrimary = Color3.fromRGB(240, 250, 246),
        TextSecondary = Color3.fromRGB(145, 175, 165),
        Border = Color3.fromRGB(45, 75, 62),
        Success = Color3.fromRGB(55, 235, 145),
        Warning = Color3.fromRGB(255, 190, 60),
        Error = Color3.fromRGB(255, 80, 95),
        CornerRadius = UDim.new(0, 8)
    },
    Crimson = {
        Background = Color3.fromRGB(18, 11, 14),
        Surface = Color3.fromRGB(29, 17, 22),
        SurfaceHover = Color3.fromRGB(42, 24, 31),
        Primary = Color3.fromRGB(245, 55, 95),
        Secondary = Color3.fromRGB(255, 145, 75),
        TextPrimary = Color3.fromRGB(252, 242, 245),
        TextSecondary = Color3.fromRGB(180, 140, 152),
        Border = Color3.fromRGB(82, 42, 55),
        Success = Color3.fromRGB(50, 220, 130),
        Warning = Color3.fromRGB(255, 185, 50),
        Error = Color3.fromRGB(255, 65, 80),
        CornerRadius = UDim.new(0, 8)
    },
    Midnight = {
        Background = Color3.fromRGB(9, 10, 16),
        Surface = Color3.fromRGB(15, 17, 28),
        SurfaceHover = Color3.fromRGB(23, 26, 42),
        Primary = Color3.fromRGB(95, 135, 255),
        Secondary = Color3.fromRGB(175, 115, 255),
        TextPrimary = Color3.fromRGB(242, 244, 255),
        TextSecondary = Color3.fromRGB(135, 145, 180),
        Border = Color3.fromRGB(42, 48, 78),
        Success = Color3.fromRGB(50, 220, 130),
        Warning = Color3.fromRGB(255, 185, 50),
        Error = Color3.fromRGB(255, 75, 95),
        CornerRadius = UDim.new(0, 8)
    },
    Light = {
        Background = Color3.fromRGB(238, 240, 246),
        Surface = Color3.fromRGB(252, 253, 255),
        SurfaceHover = Color3.fromRGB(228, 232, 242),
        Primary = Color3.fromRGB(88, 72, 235),
        Secondary = Color3.fromRGB(0, 155, 220),
        TextPrimary = Color3.fromRGB(22, 24, 34),
        TextSecondary = Color3.fromRGB(95, 102, 122),
        Border = Color3.fromRGB(200, 206, 220),
        Success = Color3.fromRGB(28, 175, 100),
        Warning = Color3.fromRGB(225, 145, 20),
        Error = Color3.fromRGB(220, 50, 70),
        CornerRadius = UDim.new(0, 8)
    }
}

function PlowUI:RegisterTheme(name, themeTable)
    PlowUI.Themes[name] = setmetatable(themeTable, { __index = DefaultTheme })
    return PlowUI.Themes[name]
end

function PlowUI:SaveCustomTheme(name, themeTable)
    PlowUI:RegisterTheme(name, themeTable)
    if not CanWriteFiles() then return false, "writefile no disponible en Delta" end
    local serialized = {}
    for k, v in pairs(themeTable) do
        if typeof(v) == "Color3" then
            serialized[k] = { __type = "Color3", r = v.R, g = v.G, b = v.B }
        end
    end
    local ok, err = pcall(function()
        writefile("PlowUI_Theme_" .. SanitizeFileName(name) .. ".json", HttpService:JSONEncode(serialized))
    end)
    return ok, err
end

function PlowUI:LoadCustomTheme(name)
    if not CanReadFiles() then return nil end
    local path = "PlowUI_Theme_" .. SanitizeFileName(name) .. ".json"
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then return nil end
    local okRead, raw = pcall(readfile, path)
    if not okRead or type(raw) ~= "string" then return nil end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not ok or type(data) ~= "table" then return nil end
    local parsed = {}
    for k, v in pairs(data) do
        if type(v) == "table" and v.__type == "Color3" then
            parsed[k] = Color3.new(v.r, v.g, v.b)
        end
    end
    return PlowUI:RegisterTheme(name, parsed)
end

-- ============================================================================
-- 6. API DE PLUGINS Y COMPONENTES PERSONALIZADOS
-- ============================================================================
function PlowUI:RegisterPlugin(pluginName, pluginDef)
    assert(type(pluginName) == "string", "El nombre del plugin debe ser string")
    assert(type(pluginDef) == "table", "La definición del plugin debe ser una tabla")
    PlowUI.Plugins[pluginName] = pluginDef
    if type(pluginDef.OnRegister) == "function" then
        SafeCall(pluginDef.OnRegister, PlowUI)
    end
end

function PlowUI:RegisterComponent(compName, builderFn)
    assert(type(compName) == "string" and type(builderFn) == "function", "Componente personalizado inválido")
    PlowUI.CustomComponents[compName] = builderFn
end

-- ============================================================================
-- 7. CONSTRUCCIÓN DE VENTANA PRINCIPAL (WINDOW) - DELTA MOBILE & PC
-- ============================================================================
function PlowUI:CreateWindow(config)
    config = config or {}
    local titleText = config.Title or "PlowUI Engine"
    local subtitleText = config.Subtitle or ("v" .. PlowUI.Version .. " Mobile")
    local themeInput = type(config.Theme) == "string" and PlowUI.Themes[config.Theme] or config.Theme
    local theme = setmetatable(table.clone(themeInput or {}), { __index = DefaultTheme })

    local WindowMaid = Maid.new()
    local ThemeBindings = {}
    local ConfigRegistry = {}
    local WindowPlugins = {}

    local function BindTheme(fn)
        table.insert(ThemeBindings, fn)
        SafeCall(fn, theme, false)
    end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(854, 480)
    local isMobile = IsDeltaMobileEnv()

    local defaultW = isMobile and math.clamp(viewport.X - 28, 310, 490) or 580
    local defaultH = isMobile and math.clamp(viewport.Y - 36, 225, 340) or 400
    local initialSize = config.Size or UDim2.new(0, defaultW, 0, defaultH)
    local minSize = config.MinSize or (isMobile and Vector2.new(290, 200) or Vector2.new(320, 220))
    local maxSize = config.MaxSize or Vector2.new(1100, 820)
    local resizable = config.Resizable ~= false
    local globalScale = config.UIScale or (isMobile and 1.0 or 1.0)
    local showFloatingButton = config.MobileButton ~= false and isMobile

    local isMinimized = false
    local isHidden = false
    local storedSize = initialSize

    local ScreenGui = FX.Create("ScreenGui", {
        Name = "PlowUI_" .. HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
        Parent = GetSafeGuiParent()
    })
    WindowMaid:GiveTask(ScreenGui)

    local UIScaleObj = FX.Create("UIScale", {
        Scale = globalScale,
        Parent = ScreenGui
    })

    -- Botón Flotante Táctil para Móvil / Delta (Abrir / Ocultar UI sin teclado)
    local MobileToggleBtn
    if showFloatingButton then
        MobileToggleBtn = FX.Create("TextButton", {
            Name = "MobileQuickToggle",
            Text = "Plow",
            Font = theme.FontBold,
            TextSize = 12,
            TextColor3 = theme.TextPrimary,
            BackgroundColor3 = theme.Surface,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.25, 0),
            Size = UDim2.new(0, 46, 0, 46),
            ZIndex = 75,
            Active = true,
            Parent = ScreenGui
        }, {
            FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
        })
        local mbStroke = FX.ApplyGlass(MobileToggleBtn, 0.1, theme.Primary, 1.5)
        BindTheme(function(t)
            MobileToggleBtn.BackgroundColor3 = t.Surface
            MobileToggleBtn.TextColor3 = t.TextPrimary
            mbStroke.Color = t.Primary
        end)

        -- Arrastre táctil independiente para el botón flotante
        local mbDrag, mbInput, mbStart, mbStartPos, mbMoved
        WindowMaid:GiveTask(MobileToggleBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                mbDrag = true
                mbInput = input
                mbStart = input.Position
                mbStartPos = MobileToggleBtn.Position
                mbMoved = false
            end
        end))

        WindowMaid:GiveTask(UserInputService.InputChanged:Connect(function(input)
            if mbDrag and input == mbInput then
                local delta = input.Position - mbStart
                if delta.Magnitude > 6 then
                    mbMoved = true
                end
                local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(854, 480)
                local nx = math.clamp(mbStartPos.X.Offset + delta.X, 8, vp.X - 54)
                local ny = math.clamp(mbStartPos.Y.Offset + delta.Y, 8, vp.Y - 54)
                MobileToggleBtn.Position = UDim2.new(0, nx, 0, ny)
            end
        end))

        WindowMaid:GiveTask(UserInputService.InputEnded:Connect(function(input)
            if input == mbInput then
                mbDrag = false
                if not mbMoved then
                    Window:Toggle()
                end
                mbInput = nil
            end
        end))
    end

    -- Contenedor de Atajos Virtuales Táctiles (para Keybinds en móviles sin teclado)
    local VirtualKeyHolder = FX.Create("Frame", {
        Name = "VirtualKeybinds",
        Position = UDim2.new(0, 70, 0.15, 0),
        Size = UDim2.new(0, 220, 0, 120),
        BackgroundTransparency = 1,
        ZIndex = 70,
        Parent = ScreenGui
    }, {
        FX.Create("UIGridLayout", {
            CellSize = UDim2.new(0, 54, 0, 32),
            CellPadding = UDim2.new(0, 6, 0, 6),
            FillDirectionMaxCells = 3
        })
    })

    local MainFrame = FX.Create("Frame", {
        Name = "MainFrame",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = theme.Background,
        ClipsDescendants = true,
        Active = true,
        Parent = ScreenGui
    }, {
        FX.Create("UICorner", { CornerRadius = UDim.new(0, 12) })
    })
    local MainStroke = FX.ApplyGlass(MainFrame, 0.06, theme.Primary, 1.2)

    local TopGlow = FX.Create("Frame", {
        Name = "TopGlow",
        Size = UDim2.new(1, 0, 0, 2),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(1, 1, 1),
        ZIndex = 5,
        Parent = MainFrame
    })
    FX.AnimatedGradient(TopGlow, { theme.Primary, theme.Secondary, theme.Primary }, 80, 0)

    Animator:Spring(MainFrame, "Size", storedSize, 0.72, 13)

    local topbarHeight = isMobile and 42 or 46
    local Topbar = FX.Create("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, topbarHeight),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Active = true,
        Parent = MainFrame
    })

    local TitleLabel = FX.Create("TextLabel", {
        Text = titleText,
        Font = theme.FontBold,
        TextSize = isMobile and 14 or 15,
        TextColor3 = theme.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 5),
        Size = UDim2.new(1, -116, 0, 18),
        BackgroundTransparency = 1,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = Topbar
    })

    local SubLabel = FX.Create("TextLabel", {
        Text = subtitleText,
        Font = theme.FontRegular,
        TextSize = 10,
        TextColor3 = theme.Secondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 22),
        Size = UDim2.new(1, -116, 0, 15),
        BackgroundTransparency = 1,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = Topbar
    })

    BindTheme(function(t, animate)
        if animate then
            Animator:Spring(MainFrame, "BackgroundColor3", t.Background, 0.85, 16)
            Animator:Spring(Topbar, "BackgroundColor3", t.Surface, 0.85, 16)
            Animator:Spring(TitleLabel, "TextColor3", t.TextPrimary, 0.85, 16)
            Animator:Spring(SubLabel, "TextColor3", t.Secondary, 0.85, 16)
            Animator:Spring(MainStroke, "Color", t.Primary, 0.85, 16)
        else
            MainFrame.BackgroundColor3 = t.Background
            Topbar.BackgroundColor3 = t.Surface
            TitleLabel.TextColor3 = t.TextPrimary
            SubLabel.TextColor3 = t.Secondary
            MainStroke.Color = t.Primary
        end
        FX.AnimatedGradient(TopGlow, { t.Primary, t.Secondary, t.Primary }, 80, 0)
    end)

    -- Arrastre fluido en Delta Mobile y PC usando Input.Position directo sin jitter
    local dragging, dragInput, dragStart, startPos
    WindowMaid:GiveTask(Topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end))

    WindowMaid:GiveTask(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(854, 480)
            local halfW = MainFrame.AbsoluteSize.X * 0.5
            local halfH = MainFrame.AbsoluteSize.Y * 0.5
            local targetX = math.clamp(startPos.X.Offset + delta.X, -vp.X * 0.5 + halfW, vp.X * 0.5 - halfW)
            local targetY = math.clamp(startPos.Y.Offset + delta.Y, -vp.Y * 0.5 + halfH, vp.Y * 0.5 - halfH)

            MainFrame.Position = UDim2.new(
                startPos.X.Scale, targetX,
                startPos.Y.Scale, targetY
            )
        end
    end))

    WindowMaid:GiveTask(UserInputService.InputEnded:Connect(function(input)
        if input == dragInput then
            dragging = false
            dragInput = nil
        end
    end))

    local btnSize = isMobile and 30 or 26
    local MinBtn = FX.Create("TextButton", {
        Text = "−",
        Font = theme.FontBold,
        TextSize = 18,
        TextColor3 = theme.TextSecondary,
        BackgroundColor3 = theme.SurfaceHover,
        BackgroundTransparency = 0.35,
        Position = UDim2.new(1, -(btnSize * 2 + 16), 0.5, -btnSize * 0.5),
        Size = UDim2.new(0, btnSize, 0, btnSize),
        Parent = Topbar
    }, {
        FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
    })

    local CloseBtn = FX.Create("TextButton", {
        Text = "×",
        Font = theme.FontBold,
        TextSize = 20,
        TextColor3 = theme.TextSecondary,
        BackgroundColor3 = theme.SurfaceHover,
        BackgroundTransparency = 0.35,
        Position = UDim2.new(1, -(btnSize + 10), 0.5, -btnSize * 0.5),
        Size = UDim2.new(0, btnSize, 0, btnSize),
        Parent = Topbar
    }, {
        FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
    })

    BindTheme(function(t)
        MinBtn.BackgroundColor3 = t.SurfaceHover
        MinBtn.TextColor3 = t.TextSecondary
        CloseBtn.BackgroundColor3 = t.SurfaceHover
        CloseBtn.TextColor3 = t.TextSecondary
    end)

    local sidebarWidth = isMobile and 104 or 148
    local bodyTop = topbarHeight + 8
    local Sidebar = FX.Create("ScrollingFrame", {
        Name = "Sidebar",
        Position = UDim2.new(0, 8, 0, bodyTop),
        Size = UDim2.new(0, sidebarWidth, 1, -(bodyTop + 8)),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.45,
        ScrollBarThickness = isMobile and 3 or 2,
        ScrollBarImageColor3 = theme.Primary,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = MainFrame
    }, {
        FX.Create("UICorner", { CornerRadius = theme.CornerRadius }),
        FX.Create("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
        FX.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) })
    })

    local PagesContainer = FX.Create("Frame", {
        Name = "Pages",
        Position = UDim2.new(0, sidebarWidth + 14, 0, bodyTop),
        Size = UDim2.new(1, -(sidebarWidth + 22), 1, -(bodyTop + 8)),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = MainFrame
    })

    BindTheme(function(t, animate)
        Sidebar.ScrollBarImageColor3 = t.Primary
        if animate then
            Animator:Spring(Sidebar, "BackgroundColor3", t.Surface, 0.85, 16)
        else
            Sidebar.BackgroundColor3 = t.Surface
        end
    end)

    local ResizeHandle = FX.Create("TextButton", {
        Name = "ResizeHandle",
        Text = "◢",
        Font = Enum.Font.GothamBold,
        TextSize = isMobile and 14 or 11,
        TextColor3 = theme.TextSecondary,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -2, 1, -2),
        Size = UDim2.new(0, isMobile and 24 or 18, 0, isMobile and 24 or 18),
        Visible = resizable,
        ZIndex = 10,
        Parent = MainFrame
    })

    if resizable then
        local resizing, resizeInput, resizeStart, startSize
        WindowMaid:GiveTask(ResizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                resizeInput = input
                resizeStart = input.Position
                startSize = MainFrame.AbsoluteSize
            end
        end))

        WindowMaid:GiveTask(UserInputService.InputChanged:Connect(function(input)
            if resizing and input == resizeInput then
                local delta = input.Position - resizeStart
                local newW = math.clamp(startSize.X + delta.X, minSize.X, maxSize.X)
                local newH = math.clamp(startSize.Y + delta.Y, minSize.Y, maxSize.Y)
                storedSize = UDim2.new(0, newW, 0, newH)
                MainFrame.Size = storedSize
            end
        end))

        WindowMaid:GiveTask(UserInputService.InputEnded:Connect(function(input)
            if input == resizeInput then
                resizing = false
                resizeInput = nil
            end
        end))
    end

    local NotifyHolder = FX.Create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -12, 1, -12),
        Size = UDim2.new(0, isMobile and 210 or 290, 1, -24),
        BackgroundTransparency = 1,
        ZIndex = 65,
        Parent = ScreenGui
    }, {
        FX.Create("UIListLayout", {
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 8)
        })
    })

    local ModalOverlay = FX.Create("Frame", {
        Name = "ModalOverlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 40,
        Parent = MainFrame
    })

    local Window = {
        Tabs = {},
        ActiveTab = nil,
        Theme = theme,
        Maid = WindowMaid,
        ScreenGui = ScreenGui,
        MainFrame = MainFrame,
        IsMobile = isMobile,
        VirtualKeyHolder = VirtualKeyHolder
    }

    table.insert(PlowUI.Windows, Window)

    function Window:SetSize(newUDim2)
        storedSize = newUDim2
        if not isMinimized then
            Animator:Spring(MainFrame, "Size", storedSize, 0.75, 16)
        end
    end

    function Window:SetScale(scaleVal)
        UIScaleObj.Scale = math.clamp(scaleVal or 1, 0.5, 2)
    end

    function Window:SetMinimized(state)
        isMinimized = state
        if isMinimized then
            Sidebar.Visible = false
            PagesContainer.Visible = false
            ResizeHandle.Visible = false
            Animator:Spring(MainFrame, "Size", UDim2.new(0, storedSize.X.Offset, 0, topbarHeight), 0.78, 18)
        else
            Animator:Spring(MainFrame, "Size", storedSize, 0.72, 15, function()
                if not isMinimized and MainFrame.Parent then
                    Sidebar.Visible = true
                    PagesContainer.Visible = true
                    ResizeHandle.Visible = resizable
                end
            end)
        end
    end

    function Window:SetVisible(visible)
        isHidden = not visible
        if visible then
            MainFrame.Visible = true
            Animator:Spring(MainFrame, "Size", isMinimized and UDim2.new(0, storedSize.X.Offset, 0, topbarHeight) or storedSize, 0.72, 15)
        else
            Animator:Tween(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Size = UDim2.new(0, 0, 0, 0)
            }, function()
                if isHidden and MainFrame.Parent then
                    MainFrame.Visible = false
                end
            end)
        end
    end

    function Window:Toggle()
        Window:SetVisible(isHidden)
    end

    function Window:Destroy()
        for i, w in ipairs(PlowUI.Windows) do
            if w == Window then
                table.remove(PlowUI.Windows, i)
                break
            end
        end
        Animator:CancelAllForInstance(MainFrame)
        WindowMaid:Destroy()
    end

    function Window:ApplyTheme(newThemeInput, animate)
        local targetTheme = type(newThemeInput) == "string" and PlowUI.Themes[newThemeInput] or newThemeInput
        if type(targetTheme) ~= "table" then return end
        animate = animate ~= false

        for k, v in pairs(targetTheme) do
            theme[k] = v
        end
        for _, bindingFn in ipairs(ThemeBindings) do
            SafeCall(bindingFn, theme, animate)
        end
    end

    if config.ToggleKey then
        WindowMaid:GiveTask(UserInputService.InputBegan:Connect(function(input, gp)
            if not gp and input.KeyCode == config.ToggleKey then
                Window:Toggle()
            end
        end))
    end

    local function GetConfigPath(profileName)
        return "PlowUI_Cfg_" .. SanitizeFileName(profileName) .. ".json"
    end

    function Window:SaveConfig(profileName)
        if not CanWriteFiles() then return false, "writefile no disponible en este ejecutor" end
        local data = {
            __meta = { version = PlowUI.Version, timestamp = os.time() },
            flags = {}
        }
        for flag, item in pairs(ConfigRegistry) do
            if item.Get then
                local ok, val = pcall(item.Get)
                if ok and val ~= nil then
                    if typeof(val) == "Color3" then
                        data.flags[flag] = { __type = "Color3", r = val.R, g = val.G, b = val.B }
                    elseif typeof(val) == "EnumItem" then
                        data.flags[flag] = { __type = "EnumItem", enumType = tostring(val.EnumType), name = val.Name }
                    else
                        data.flags[flag] = val
                    end
                end
            end
        end

        local ok, err = pcall(function()
            writefile(GetConfigPath(profileName), HttpService:JSONEncode(data))
        end)
        return ok, err
    end

    function Window:LoadConfig(profileName)
        if not CanReadFiles() then return false, "File API no disponible en este ejecutor" end
        local path = GetConfigPath(profileName)
        local okEx, exists = pcall(isfile, path)
        if not okEx or not exists then return false, "Perfil no encontrado" end

        local okRead, raw = pcall(readfile, path)
        if not okRead or type(raw) ~= "string" then return false, "Error leyendo archivo" end

        local okJson, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if not okJson or type(decoded) ~= "table" then return false, "Archivo JSON corrupto" end

        local flagsTable = type(decoded.flags) == "table" and decoded.flags or decoded
        for flag, val in pairs(flagsTable) do
            local item = ConfigRegistry[flag]
            if item and item.Set then
                if type(val) == "table" and val.__type == "Color3" then
                    if type(val.r) == "number" and type(val.g) == "number" and type(val.b) == "number" then
                        SafeCall(item.Set, item, Color3.new(math.clamp(val.r, 0, 1), math.clamp(val.g, 0, 1), math.clamp(val.b, 0, 1)))
                    end
                elseif type(val) == "table" and val.__type == "EnumItem" then
                    if type(val.name) == "string" and Enum.KeyCode[val.name] then
                        SafeCall(item.Set, item, Enum.KeyCode[val.name])
                    end
                else
                    SafeCall(item.Set, item, val)
                end
            end
        end
        return true
    end

    function Window:DeleteConfig(profileName)
        if type(isfile) ~= "function" or type(delfile) ~= "function" then return false end
        local path = GetConfigPath(profileName)
        local okEx, exists = pcall(isfile, path)
        if okEx and exists then
            return pcall(delfile, path)
        end
        return false
    end

    function Window:ListConfigs()
        if type(listfiles) ~= "function" then return {} end
        local ok, files = pcall(listfiles, "")
        if not ok or type(files) ~= "table" then return {} end
        local profiles = {}
        for _, filePath in ipairs(files) do
            local match = tostring(filePath):match("PlowUI_Cfg_([%w%-%_]+)%.json$")
            if match then
                table.insert(profiles, match)
            end
        end
        return profiles
    end

    WindowMaid:GiveTask(MinBtn.MouseButton1Click:Connect(function()
        Window:SetMinimized(not isMinimized)
    end))

    WindowMaid:GiveTask(CloseBtn.MouseButton1Click:Connect(function()
        Animator:Tween(MainFrame, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 0, 0, 0)
        }, function()
            Window:Destroy()
        end)
    end))

    function Window:Notify(nConfig)
        nConfig = nConfig or {}
        local nTitle = nConfig.Title or "Notificación"
        local nDesc = nConfig.Description or ""
        local duration = nConfig.Duration or 4
        local nType = nConfig.Type or "Info"
        local accent = nConfig.Color
            or (nType == "Success" and theme.Success)
            or (nType == "Warning" and theme.Warning)
            or (nType == "Error" and theme.Error)
            or theme.Primary

        local hasAction = type(nConfig.ActionText) == "string"
        local targetHeight = hasAction and 86 or 66

        local Card = FX.Create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = theme.Surface,
            ClipsDescendants = true,
            ZIndex = 66,
            Parent = NotifyHolder
        }, {
            FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
        })
        FX.ApplyGlass(Card, 0.08, accent, 1.1)

        FX.Create("Frame", {
            Size = UDim2.new(0, 4, 1, 0),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            ZIndex = 67,
            Parent = Card
        })

        FX.Create("TextLabel", {
            Text = nTitle,
            Font = theme.FontBold,
            TextSize = 13,
            TextColor3 = theme.TextPrimary,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 12, 0, 6),
            Size = UDim2.new(1, -20, 0, 18),
            BackgroundTransparency = 1,
            ZIndex = 67,
            Parent = Card
        })

        FX.Create("TextLabel", {
            Text = nDesc,
            Font = theme.FontRegular,
            TextSize = 11,
            TextColor3 = theme.TextSecondary,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            Position = UDim2.new(0, 12, 0, 24),
            Size = UDim2.new(1, -20, 0, 32),
            BackgroundTransparency = 1,
            ZIndex = 67,
            Parent = Card
        })

        local TimerBar = FX.Create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 4, 1, 0),
            Size = UDim2.new(1, -4, 0, 2),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            ZIndex = 68,
            Parent = Card
        })

        local dismissed = false
        local function Dismiss()
            if dismissed then return end
            dismissed = true
            if Card and Card.Parent then
                Animator:Tween(Card, TweenInfo.new(0.28, Enum.EasingStyle.Quad), {
                    Size = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1
                }, function()
                    if Card and Card.Parent then Card:Destroy() end
                end)
            end
        end

        if hasAction then
            local ActBtn = FX.Create("TextButton", {
                Text = nConfig.ActionText,
                Font = theme.FontBold,
                TextSize = 11,
                TextColor3 = theme.TextPrimary,
                BackgroundColor3 = accent,
                Position = UDim2.new(0, 12, 0, 58),
                Size = UDim2.new(0, 90, 0, 20),
                ZIndex = 68,
                Parent = Card
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 5) })
            })
            ActBtn.MouseButton1Click:Connect(function()
                if nConfig.OnAction then SafeCall(nConfig.OnAction) end
                Dismiss()
            end)
        end

        Animator:Spring(Card, "Size", UDim2.new(1, 0, 0, targetHeight), 0.72, 16)
        Animator:Tween(TimerBar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
            Size = UDim2.new(0, 0, 0, 2)
        })

        task.delay(duration, Dismiss)
        return { Dismiss = Dismiss }
    end

    function Window:CreateModal(mConfig)
        mConfig = mConfig or {}
        ModalOverlay.Visible = true
        Animator:Tween(ModalOverlay, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 })

        local ModalBox = FX.Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = theme.Surface,
            ClipsDescendants = true,
            ZIndex = 42,
            Parent = ModalOverlay
        }, {
            FX.Create("UICorner", { CornerRadius = UDim.new(0, 10) })
        })
        FX.ApplyGlass(ModalBox, 0.04, theme.Primary, 1.2)

        local targetW = math.min(mConfig.Width or 320, MainFrame.AbsoluteSize.X - 24)
        local targetH = mConfig.Height or 175
        Animator:Spring(ModalBox, "Size", UDim2.new(0, targetW, 0, targetH), 0.72, 16)

        FX.Create("TextLabel", {
            Text = mConfig.Title or "Ventana Emergente",
            Font = theme.FontBold,
            TextSize = 14,
            TextColor3 = theme.TextPrimary,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 14, 0, 10),
            Size = UDim2.new(1, -28, 0, 20),
            BackgroundTransparency = 1,
            ZIndex = 43,
            Parent = ModalBox
        })

        FX.Create("TextLabel", {
            Text = mConfig.Description or "",
            Font = theme.FontRegular,
            TextSize = 12,
            TextColor3 = theme.TextSecondary,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            Position = UDim2.new(0, 14, 0, 34),
            Size = UDim2.new(1, -28, 1, -82),
            BackgroundTransparency = 1,
            ZIndex = 43,
            Parent = ModalBox
        })

        local BtnRow = FX.Create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 14, 1, -12),
            Size = UDim2.new(1, -28, 0, 32),
            BackgroundTransparency = 1,
            ZIndex = 43,
            Parent = ModalBox
        }, {
            FX.Create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                Padding = UDim.new(0, 8)
            })
        })

        local function CloseModal()
            Animator:Tween(ModalBox, TweenInfo.new(0.18), { Size = UDim2.new(0, 0, 0, 0) }, function()
                if ModalBox and ModalBox.Parent then ModalBox:Destroy() end
                if #ModalOverlay:GetChildren() == 0 then
                    Animator:Tween(ModalOverlay, TweenInfo.new(0.15), { BackgroundTransparency = 1 }, function()
                        ModalOverlay.Visible = false
                    end)
                end
            end)
        end

        for _, btnDef in ipairs(mConfig.Buttons or { { Text = "Cerrar", Primary = true } }) do
            local B = FX.Create("TextButton", {
                Text = btnDef.Text or "OK",
                Font = theme.FontBold,
                TextSize = 12,
                TextColor3 = theme.TextPrimary,
                BackgroundColor3 = btnDef.Primary and theme.Primary or theme.Background,
                Size = UDim2.new(0, 86, 1, 0),
                ZIndex = 44,
                Parent = BtnRow
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
            })
            B.MouseButton1Click:Connect(function()
                if btnDef.Callback then SafeCall(btnDef.Callback) end
                CloseModal()
            end)
        end

        return { Close = CloseModal, Frame = ModalBox }
    end

    function Window:ConfirmDialog(title, description, onConfirm, onCancel)
        return Window:CreateModal({
            Title = title or "Confirmar acción",
            Description = description or "¿Estás seguro de continuar?",
            Buttons = {
                { Text = "Cancelar", Primary = false, Callback = onCancel },
                { Text = "Confirmar", Primary = true, Callback = onConfirm }
            }
        })
    end

    -- ========================================================================
    -- 8. SISTEMA DE COMPONENTES REUTILIZABLES (PARA TABS Y SUBTABS)
    -- ========================================================================
    local function AttachComponentBuilders(containerObj, targetScrollingFrame, tabMaid, itemRegistryList)
        local rowHeight = isMobile and 44 or 40

        local function RegisterItem(itemObj, frame, localMaid, flag)
            table.insert(itemRegistryList, { frame = frame, maid = localMaid, obj = itemObj })
            if flag then
                ConfigRegistry[flag] = itemObj
            end
            itemObj.SetSize = function(_, newHeight)
                Animator:Spring(frame, "Size", UDim2.new(1, 0, 0, newHeight), 0.78, 18)
            end
            itemObj.Destroy = function()
                if flag and ConfigRegistry[flag] == itemObj then
                    ConfigRegistry[flag] = nil
                end
                localMaid:Destroy()
                if frame and frame.Parent then
                    frame:Destroy()
                end
            end
            return itemObj
        end

        function containerObj:AddSection(title)
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local SecFrame = FX.Create("Frame", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundTransparency = 1,
                Parent = targetScrollingFrame
            })
            local Lbl = FX.Create("TextLabel", {
                Text = string.upper(tostring(title or "SECCIÓN")),
                Font = theme.FontBold,
                TextSize = 11,
                TextColor3 = theme.Secondary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Parent = SecFrame
            })
            BindTheme(function(t) Lbl.TextColor3 = t.Secondary end)
            return RegisterItem({
                Set = function(_, txt) Lbl.Text = string.upper(tostring(txt)) end,
                Get = function() return Lbl.Text end
            }, SecFrame, m)
        end

        function containerObj:AddSeparator()
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local Line = FX.Create("Frame", {
                Size = UDim2.new(1, 0, 0, 2),
                BackgroundColor3 = theme.Border,
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })
            BindTheme(function(t) Line.BackgroundColor3 = t.Border end)
            return RegisterItem({}, Line, m)
        end

        function containerObj:AddLabel(lConfig)
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local text = type(lConfig) == "string" and lConfig or (lConfig.Title or lConfig.Text or "Label")
            local Box = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, 34),
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Box, 0.45, theme.Border)
            local Lbl = FX.Create("TextLabel", {
                Text = text,
                Font = theme.FontMedium,
                TextSize = 12,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -24, 1, 0),
                BackgroundTransparency = 1,
                Parent = Box
            })
            BindTheme(function(t)
                Box.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                Lbl.TextColor3 = t.TextPrimary
            end)
            return RegisterItem({
                Set = function(_, newText) Lbl.Text = tostring(newText) end,
                Get = function() return Lbl.Text end
            }, Box, m)
        end

        function containerObj:AddParagraph(pConfig)
            pConfig = pConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local Box = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, 56),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius }),
                FX.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
                FX.Create("UIListLayout", { Padding = UDim.new(0, 4) })
            })
            local Stroke = FX.ApplyGlass(Box, 0.4, theme.Border)

            local TitleLbl = FX.Create("TextLabel", {
                Text = pConfig.Title or "Título",
                Font = theme.FontBold,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Parent = Box
            })

            local DescLbl = FX.Create("TextLabel", {
                Text = pConfig.Description or pConfig.Content or "",
                Font = theme.FontRegular,
                TextSize = 12,
                TextColor3 = theme.TextSecondary,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Parent = Box
            })

            BindTheme(function(t)
                Box.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                DescLbl.TextColor3 = t.TextSecondary
            end)

            return RegisterItem({
                Set = function(_, newTitle, newDesc)
                    if newTitle then TitleLbl.Text = tostring(newTitle) end
                    if newDesc then DescLbl.Text = tostring(newDesc) end
                end,
                Get = function() return { Title = TitleLbl.Text, Description = DescLbl.Text } end
            }, Box, m)
        end

        function containerObj:AddSearch(placeholder)
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local SearchBox = FX.Create("TextBox", {
                PlaceholderText = placeholder or "Buscar componente...",
                Text = "",
                Font = theme.FontRegular,
                TextSize = 12,
                TextColor3 = theme.TextPrimary,
                PlaceholderColor3 = theme.TextSecondary,
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, 36),
                ClearTextOnFocus = false,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius }),
                FX.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
            })
            local Stroke = FX.ApplyGlass(SearchBox, 0.35, theme.Border)

            BindTheme(function(t)
                SearchBox.BackgroundColor3 = t.Surface
                SearchBox.TextColor3 = t.TextPrimary
                SearchBox.PlaceholderColor3 = t.TextSecondary
                Stroke.Color = t.Border
            end)

            m:GiveTask(SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
                local q = string.lower(SearchBox.Text)
                for _, entry in ipairs(itemRegistryList) do
                    if entry.frame ~= SearchBox and entry.frame and entry.frame.Parent then
                        if q == "" then
                            entry.frame.Visible = true
                        else
                            local matched = false
                            for _, desc in ipairs(entry.frame:GetDescendants()) do
                                if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
                                    if string.find(string.lower(desc.Text), q, 1, true) then
                                        matched = true
                                        break
                                    end
                                end
                            end
                            entry.frame.Visible = matched
                        end
                    end
                end
            end))

            return RegisterItem({
                Set = function(_, v) SearchBox.Text = tostring(v or "") end,
                Get = function() return SearchBox.Text end,
                Clear = function() SearchBox.Text = "" end
            }, SearchBox, m)
        end

        function containerObj:AddButton(bConfig)
            bConfig = bConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local OnClick = Signal.new()
            m:GiveTask(OnClick)
            local enabled = bConfig.Enabled ~= false
            local style = bConfig.Style or "Default"

            local function GetBaseColor(t)
                if style == "Primary" then return t.Primary
                elseif style == "Danger" then return t.Error
                elseif style == "Success" then return t.Success
                end
                return t.Surface
            end

            local BtnFrame = FX.Create("TextButton", {
                Text = "",
                BackgroundColor3 = GetBaseColor(theme),
                Size = UDim2.new(1, 0, 0, rowHeight),
                AutoButtonColor = false,
                ClipsDescendants = true,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(BtnFrame, style == "Default" and 0.35 or 0.15, theme.Border)

            local Label = FX.Create("TextLabel", {
                Text = bConfig.Title or "Botón",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -24, 1, 0),
                BackgroundTransparency = 1,
                Parent = BtnFrame
            })

            BindTheme(function(t)
                BtnFrame.BackgroundColor3 = GetBaseColor(t)
                Stroke.Color = t.Border
                Label.TextColor3 = t.TextPrimary
            end)

            m:GiveTask(BtnFrame.MouseEnter:Connect(function()
                if not enabled then return end
                Animator:Spring(BtnFrame, "BackgroundColor3", style == "Default" and theme.SurfaceHover or GetBaseColor(theme), 0.8, 18)
            end))
            m:GiveTask(BtnFrame.MouseLeave:Connect(function()
                Animator:Spring(BtnFrame, "BackgroundColor3", GetBaseColor(theme), 0.8, 18)
            end))
            m:GiveTask(BtnFrame.InputBegan:Connect(function(input)
                if not enabled then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    FX.Ripple(BtnFrame, theme.Primary, input.Position)
                    OnClick:Fire()
                    if bConfig.Callback then
                        task.spawn(SafeCall, bConfig.Callback)
                    end
                end
            end))

            return RegisterItem({
                OnClick = OnClick,
                Set = function(_, newText) Label.Text = tostring(newText) end,
                Get = function() return Label.Text end,
                SetEnabled = function(_, state)
                    enabled = not not state
                    Label.TextTransparency = enabled and 0 or 0.5
                end
            }, BtnFrame, m)
        end

        function containerObj:AddToggle(tConfig)
            tConfig = tConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local state = not not tConfig.Default
            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local Container = FX.Create("TextButton", {
                Text = "",
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, rowHeight),
                AutoButtonColor = false,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local TitleLbl = FX.Create("TextLabel", {
                Text = tConfig.Title or "Toggle",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -72, 1, 0),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local swW = isMobile and 48 or 42
            local swH = isMobile and 26 or 22
            local knobSize = isMobile and 20 or 16
            local SwitchBg = FX.Create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.new(0, swW, 0, swH),
                BackgroundColor3 = state and theme.Primary or theme.Background,
                Parent = Container
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })

            local onX = swW - knobSize - 3
            local Knob = FX.Create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = state and UDim2.new(0, onX, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                Size = UDim2.new(0, knobSize, 0, knobSize),
                BackgroundColor3 = Color3.new(1, 1, 1),
                Parent = SwitchBg
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                SwitchBg.BackgroundColor3 = state and t.Primary or t.Background
            end)

            local function SetState(newState, silent)
                state = not not newState
                Animator:Spring(SwitchBg, "BackgroundColor3", state and theme.Primary or theme.Background, 0.75, 18)
                Animator:Spring(Knob, "Position", state and UDim2.new(0, onX, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), 0.65, 18)

                if not silent then
                    OnChanged:Fire(state)
                    if tConfig.Callback then
                        task.spawn(SafeCall, tConfig.Callback, state)
                    end
                end
            end

            m:GiveTask(Container.MouseButton1Click:Connect(function()
                SetState(not state)
            end))

            return RegisterItem({
                OnChanged = OnChanged,
                Set = function(_, val, silent) SetState(val, silent) end,
                Get = function() return state end
            }, Container, m, tConfig.Flag)
        end

        function containerObj:AddSlider(sConfig)
            sConfig = sConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local min = sConfig.Min or 0
            local max = sConfig.Max or 100
            if max <= min then max = min + 1 end
            local increment = (sConfig.Increment and sConfig.Increment > 0) and sConfig.Increment or 1
            local decimals = sConfig.Decimals or (increment < 1 and 2 or 0)
            local value = math.clamp(sConfig.Default or min, min, max)
            local suffix = sConfig.Suffix or ""

            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local function FormatNum(v)
                if decimals <= 0 then
                    return tostring(math.floor(v + 0.5)) .. suffix
                end
                return string.format("%." .. decimals .. "f", v) .. suffix
            end

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, isMobile and 58 or 52),
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local TitleLbl = FX.Create("TextLabel", {
                Text = sConfig.Title or "Slider",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 6),
                Size = UDim2.new(0.7, 0, 0, 18),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local ValueLabel = FX.Create("TextLabel", {
                Text = FormatNum(value),
                Font = theme.FontBold,
                TextSize = 12,
                TextColor3 = theme.Secondary,
                TextXAlignment = Enum.TextXAlignment.Right,
                Position = UDim2.new(0.7, 0, 0, 6),
                Size = UDim2.new(0.3, -12, 0, 18),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local trackH = isMobile and 12 or 8
            local Track = FX.Create("TextButton", {
                Text = "",
                AutoButtonColor = false,
                Position = UDim2.new(0, 12, 0, isMobile and 34 or 32),
                Size = UDim2.new(1, -24, 0, trackH),
                BackgroundColor3 = theme.Background,
                Parent = Container
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })

            local initialPercent = (value - min) / (max - min)
            local Fill = FX.Create("Frame", {
                Size = UDim2.new(initialPercent, 0, 1, 0),
                BackgroundColor3 = Color3.new(1, 1, 1),
                Parent = Track
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })
            FX.AnimatedGradient(Fill, { theme.Primary, theme.Secondary }, 30, 0)

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                ValueLabel.TextColor3 = t.Secondary
                Track.BackgroundColor3 = t.Background
                FX.AnimatedGradient(Fill, { t.Primary, t.Secondary }, 30, 0)
            end)

            local sliding = false
            local slideInput = nil

            local function ApplyValue(rawVal, silent)
                local steppedVal = math.floor((rawVal / increment) + 0.5) * increment
                steppedVal = math.clamp(tonumber(string.format("%.5f", steppedVal)), min, max)
                value = steppedVal
                ValueLabel.Text = FormatNum(value)
                Animator:Spring(Fill, "Size", UDim2.new((value - min) / (max - min), 0, 1, 0), 0.85, 25)

                if not silent then
                    OnChanged:Fire(value)
                    if sConfig.Callback then
                        task.spawn(SafeCall, sConfig.Callback, value)
                    end
                end
            end

            local function UpdateFromInput(inputPos)
                local relX = math.clamp((inputPos.X - Track.AbsolutePosition.X) / math.max(Track.AbsoluteSize.X, 1), 0, 1)
                ApplyValue(min + (max - min) * relX, false)
            end

            m:GiveTask(Track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    slideInput = input
                    UpdateFromInput(input.Position)
                end
            end))

            m:GiveTask(UserInputService.InputChanged:Connect(function(input)
                if sliding and input == slideInput then
                    UpdateFromInput(input.Position)
                end
            end))

            m:GiveTask(UserInputService.InputEnded:Connect(function(input)
                if input == slideInput then
                    sliding = false
                    slideInput = nil
                end
            end))

            return RegisterItem({
                OnChanged = OnChanged,
                Set = function(_, newVal, silent) ApplyValue(tonumber(newVal) or min, silent) end,
                Get = function() return value end
            }, Container, m, sConfig.Flag)
        end

        function containerObj:AddDropdown(dConfig)
            dConfig = dConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local options = dConfig.Options or {}
            local selected = dConfig.Default or options[1] or "Seleccionar"
            local searchable = dConfig.Searchable ~= false
            local opened = false
            local OptionMaid = Maid.new()
            m:GiveTask(OptionMaid)

            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, rowHeight),
                ClipsDescendants = true,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local HeaderBtn = FX.Create("TextButton", {
                Text = "",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, rowHeight),
                Parent = Container
            })

            local TitleLbl = FX.Create("TextLabel", {
                Text = dConfig.Title or "Dropdown",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(0.45, 0, 1, 0),
                BackgroundTransparency = 1,
                Parent = HeaderBtn
            })

            local SelectedLabel = FX.Create("TextLabel", {
                Text = tostring(selected) .. "  ▼",
                Font = theme.FontBold,
                TextSize = 12,
                TextColor3 = theme.Secondary,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.new(0.45, 0, 0, 0),
                Size = UDim2.new(0.55, -12, 1, 0),
                BackgroundTransparency = 1,
                Parent = HeaderBtn
            })

            local searchOffset = searchable and 34 or 0
            local FilterBox
            if searchable then
                FilterBox = FX.Create("TextBox", {
                    PlaceholderText = "Filtrar opciones...",
                    Text = "",
                    Font = theme.FontRegular,
                    TextSize = 11,
                    TextColor3 = theme.TextPrimary,
                    PlaceholderColor3 = theme.TextSecondary,
                    BackgroundColor3 = theme.Background,
                    Position = UDim2.new(0, 8, 0, rowHeight + 2),
                    Size = UDim2.new(1, -16, 0, 28),
                    ClearTextOnFocus = false,
                    Parent = Container
                }, {
                    FX.Create("UICorner", { CornerRadius = UDim.new(0, 5) })
                })
            end

            local OptionList = FX.Create("ScrollingFrame", {
                Position = UDim2.new(0, 8, 0, rowHeight + 2 + searchOffset),
                Size = UDim2.new(1, -16, 0, 120),
                BackgroundTransparency = 1,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = theme.Primary,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                BorderSizePixel = 0,
                Parent = Container
            }, {
                FX.Create("UIListLayout", { Padding = UDim.new(0, 4) })
            })

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                SelectedLabel.TextColor3 = t.Secondary
                OptionList.ScrollBarImageColor3 = t.Primary
                if FilterBox then
                    FilterBox.BackgroundColor3 = t.Background
                    FilterBox.TextColor3 = t.TextPrimary
                end
            end)

            local optH = isMobile and 30 or 26
            local function GetExpandedHeight(count)
                local visibleCount = math.min(count, 5)
                local listH = math.max(visibleCount * (optH + 4), optH)
                OptionList.Size = UDim2.new(1, -16, 0, listH)
                return rowHeight + 8 + searchOffset + listH
            end

            local function RenderOptions(filterText)
                OptionMaid:DoCleaning()
                for _, child in ipairs(OptionList:GetChildren()) do
                    if child:IsA("TextButton") then child:Destroy() end
                end

                local q = string.lower(filterText or "")
                local shown = 0
                for _, opt in ipairs(options) do
                    if q == "" or string.find(string.lower(tostring(opt)), q, 1, true) then
                        shown += 1
                        local OptBtn = FX.Create("TextButton", {
                            Text = tostring(opt),
                            Font = theme.FontRegular,
                            TextSize = 12,
                            TextColor3 = opt == selected and theme.Secondary or theme.TextSecondary,
                            BackgroundColor3 = theme.Background,
                            BackgroundTransparency = 0.25,
                            Size = UDim2.new(1, 0, 0, optH),
                            Parent = OptionList
                        }, {
                            FX.Create("UICorner", { CornerRadius = UDim.new(0, 5) })
                        })

                        OptionMaid:GiveTask(OptBtn.MouseButton1Click:Connect(function()
                            selected = opt
                            SelectedLabel.Text = tostring(selected) .. "  ▼"
                            opened = false
                            Animator:Spring(Container, "Size", UDim2.new(1, 0, 0, rowHeight), 0.75, 18)
                            OnChanged:Fire(selected)
                            if dConfig.Callback then
                                task.spawn(SafeCall, dConfig.Callback, selected)
                            end
                        end))
                    end
                end

                if opened then
                    Animator:Spring(Container, "Size", UDim2.new(1, 0, 0, GetExpandedHeight(shown)), 0.75, 18)
                end
            end

            if FilterBox then
                m:GiveTask(FilterBox:GetPropertyChangedSignal("Text"):Connect(function()
                    RenderOptions(FilterBox.Text)
                end))
            end

            RenderOptions("")

            m:GiveTask(HeaderBtn.MouseButton1Click:Connect(function()
                opened = not opened
                SelectedLabel.Text = tostring(selected) .. (opened and "  ▲" or "  ▼")
                if opened then
                    RenderOptions(FilterBox and FilterBox.Text or "")
                else
                    Animator:Spring(Container, "Size", UDim2.new(1, 0, 0, rowHeight), 0.72, 16)
                end
            end))

            return RegisterItem({
                OnChanged = OnChanged,
                Refresh = function(_, newOpts)
                    options = newOpts or {}
                    RenderOptions(FilterBox and FilterBox.Text or "")
                end,
                Set = function(_, val)
                    selected = val
                    SelectedLabel.Text = tostring(selected) .. (opened and "  ▲" or "  ▼")
                end,
                Get = function() return selected end
            }, Container, m, dConfig.Flag)
        end

        function containerObj:AddMultiDropdown(dConfig)
            dConfig = dConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local options = dConfig.Options or {}
            local chosenSet = {}
            for _, item in ipairs(dConfig.Default or {}) do
                chosenSet[item] = true
            end
            local opened = false
            local OptionMaid = Maid.new()
            m:GiveTask(OptionMaid)

            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local function GetSelectedList()
                local list = {}
                for _, opt in ipairs(options) do
                    if chosenSet[opt] then table.insert(list, opt) end
                end
                return list
            end

            local function FormatText()
                local list = GetSelectedList()
                return (#list > 0 and table.concat(list, ", ") or "Ninguno") .. (opened and "  ▲" or "  ▼")
            end

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, rowHeight),
                ClipsDescendants = true,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local HeaderBtn = FX.Create("TextButton", {
                Text = "",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, rowHeight),
                Parent = Container
            })

            local TitleLbl = FX.Create("TextLabel", {
                Text = dConfig.Title or "MultiDropdown",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(0.42, 0, 1, 0),
                BackgroundTransparency = 1,
                Parent = HeaderBtn
            })

            local SelectedLabel = FX.Create("TextLabel", {
                Text = FormatText(),
                Font = theme.FontBold,
                TextSize = 12,
                TextColor3 = theme.Secondary,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.new(0.42, 0, 0, 0),
                Size = UDim2.new(0.58, -12, 1, 0),
                BackgroundTransparency = 1,
                Parent = HeaderBtn
            })

            local optH = isMobile and 30 or 26
            local OptionList = FX.Create("Frame", {
                Position = UDim2.new(0, 8, 0, rowHeight + 2),
                Size = UDim2.new(1, -16, 0, #options * (optH + 4)),
                BackgroundTransparency = 1,
                Parent = Container
            }, {
                FX.Create("UIListLayout", { Padding = UDim.new(0, 4) })
            })

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                SelectedLabel.TextColor3 = t.Secondary
            end)

            local function RefreshOptions(newOpts)
                OptionMaid:DoCleaning()
                if newOpts then options = newOpts end
                OptionList.Size = UDim2.new(1, -16, 0, #options * (optH + 4))

                for _, child in ipairs(OptionList:GetChildren()) do
                    if child:IsA("TextButton") then child:Destroy() end
                end

                for _, opt in ipairs(options) do
                    local OptBtn = FX.Create("TextButton", {
                        Text = (chosenSet[opt] and "[✓] " or "[ ] ") .. tostring(opt),
                        Font = theme.FontRegular,
                        TextSize = 12,
                        TextColor3 = chosenSet[opt] and theme.Secondary or theme.TextSecondary,
                        BackgroundColor3 = theme.Background,
                        BackgroundTransparency = 0.25,
                        Size = UDim2.new(1, 0, 0, optH),
                        Parent = OptionList
                    }, {
                        FX.Create("UICorner", { CornerRadius = UDim.new(0, 5) })
                    })

                    OptionMaid:GiveTask(OptBtn.MouseButton1Click:Connect(function()
                        chosenSet[opt] = not chosenSet[opt]
                        local active = chosenSet[opt]
                        OptBtn.Text = (active and "[✓] " or "[ ] ") .. tostring(opt)
                        OptBtn.TextColor3 = active and theme.Secondary or theme.TextSecondary
                        SelectedLabel.Text = FormatText()
                        local list = GetSelectedList()
                        OnChanged:Fire(list)
                        if dConfig.Callback then
                            task.spawn(SafeCall, dConfig.Callback, list)
                        end
                    end))
                end
                SelectedLabel.Text = FormatText()
            end

            RefreshOptions()

            m:GiveTask(HeaderBtn.MouseButton1Click:Connect(function()
                opened = not opened
                local targetHeight = opened and (rowHeight + 8 + (#options * (optH + 4))) or rowHeight
                SelectedLabel.Text = FormatText()
                Animator:Spring(Container, "Size", UDim2.new(1, 0, 0, targetHeight), 0.72, 16)
            end))

            return RegisterItem({
                OnChanged = OnChanged,
                Refresh = function(_, newOpts) RefreshOptions(newOpts) end,
                Set = function(_, list)
                    table.clear(chosenSet)
                    for _, item in ipairs(list or {}) do
                        chosenSet[item] = true
                    end
                    RefreshOptions()
                end,
                Get = GetSelectedList
            }, Container, m, dConfig.Flag)
        end

        function containerObj:AddInput(iConfig)
            iConfig = iConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local maxLength = iConfig.MaxLength or 120
            local numericOnly = iConfig.Numeric or false
            local validator = iConfig.Validator
            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, rowHeight),
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local TitleLbl = FX.Create("TextLabel", {
                Text = iConfig.Title or "Input",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(0.45, 0, 1, 0),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local boxH = isMobile and 30 or 26
            local Box = FX.Create("TextBox", {
                Text = tostring(iConfig.Default or ""),
                PlaceholderText = iConfig.Placeholder or "Escribir...",
                Font = theme.FontRegular,
                TextSize = 12,
                TextColor3 = theme.TextPrimary,
                PlaceholderColor3 = theme.TextSecondary,
                BackgroundColor3 = theme.Background,
                Position = UDim2.new(0.48, 0, 0.5, -boxH * 0.5),
                Size = UDim2.new(0.52, -10, 0, boxH),
                ClearTextOnFocus = iConfig.ClearOnFocus or false,
                Parent = Container
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
            })
            local BoxStroke = FX.ApplyGlass(Box, 0.15, theme.Border)

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                Box.BackgroundColor3 = t.Background
                Box.TextColor3 = t.TextPrimary
                BoxStroke.Color = t.Border
            end)

            m:GiveTask(Box:GetPropertyChangedSignal("Text"):Connect(function()
                local txt = Box.Text
                if numericOnly then
                    txt = txt:gsub("[^%d%.%-]", "")
                end
                if #txt > maxLength then
                    txt = string.sub(txt, 1, maxLength)
                end
                if Box.Text ~= txt then
                    Box.Text = txt
                end
            end))

            m:GiveTask(Box.FocusLost:Connect(function(enterPressed)
                local valid = true
                if type(validator) == "function" then
                    valid = validator(Box.Text)
                end
                Animator:Spring(BoxStroke, "Color", valid and theme.Border or theme.Error, 0.8, 18)
                if valid then
                    OnChanged:Fire(Box.Text, enterPressed)
                    if iConfig.Callback then
                        task.spawn(SafeCall, iConfig.Callback, Box.Text, enterPressed)
                    end
                end
            end))

            return RegisterItem({
                OnChanged = OnChanged,
                Set = function(_, v) Box.Text = string.sub(tostring(v or ""), 1, maxLength) end,
                Get = function() return Box.Text end
            }, Container, m, iConfig.Flag)
        end

        -- KEYBIND CON BOTÓN VIRTUAL TÁCTIL PARA MÓVIL / DELTA
        function containerObj:AddKeybind(kConfig)
            kConfig = kConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local key = kConfig.Default or Enum.KeyCode.F
            local mode = kConfig.Mode or "Toggle"
            local listening = false
            local toggleActive = false
            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, rowHeight),
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local TitleLbl = FX.Create("TextLabel", {
                Text = kConfig.Title or "Keybind",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(0.56, 0, 1, 0),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local KeyBtn = FX.Create("TextButton", {
                Text = key.Name,
                Font = theme.FontBold,
                TextSize = 11,
                TextColor3 = theme.Secondary,
                BackgroundColor3 = theme.Background,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.new(0, 84, 0, 26),
                Parent = Container
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
            })

            -- Botón flotante virtual opcional o automático en móvil para activar el bind con el dedo
            local showPadBtn = (kConfig.MobileTrigger ~= false) and isMobile
            local PadTrigger
            if showPadBtn then
                PadTrigger = FX.Create("TextButton", {
                    Text = key.Name,
                    Font = theme.FontBold,
                    TextSize = 10,
                    TextColor3 = theme.TextPrimary,
                    BackgroundColor3 = theme.Surface,
                    Parent = VirtualKeyHolder
                }, {
                    FX.Create("UICorner", { CornerRadius = UDim.new(0, 8) })
                })
                local ptStroke = FX.ApplyGlass(PadTrigger, 0.15, theme.Primary, 1.2)
                BindTheme(function(t)
                    PadTrigger.BackgroundColor3 = t.Surface
                    PadTrigger.TextColor3 = t.TextPrimary
                    ptStroke.Color = t.Primary
                end)
                m:GiveTask(PadTrigger)
            end

            local function TriggerBind(isDown)
                if mode == "Toggle" then
                    if isDown then
                        toggleActive = not toggleActive
                        if kConfig.Callback then
                            task.spawn(SafeCall, kConfig.Callback, key, toggleActive)
                        end
                    end
                else
                    if kConfig.Callback then
                        task.spawn(SafeCall, kConfig.Callback, key, isDown)
                    end
                end
            end

            if PadTrigger then
                m:GiveTask(PadTrigger.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                        TriggerBind(true)
                    end
                end))
                if mode == "Hold" then
                    m:GiveTask(PadTrigger.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                            TriggerBind(false)
                        end
                    end))
                end
            end

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                KeyBtn.BackgroundColor3 = t.Background
                KeyBtn.TextColor3 = t.Secondary
            end)

            m:GiveTask(KeyBtn.MouseButton1Click:Connect(function()
                if isMobile then
                    -- En móvil permite activar directamente si se pulsa de nuevo o asignar tecla
                    TriggerBind(true)
                else
                    listening = true
                    KeyBtn.Text = "[ ... ]"
                end
            end))

            m:GiveTask(UserInputService.InputBegan:Connect(function(input, gp)
                if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                    listening = false
                    if input.KeyCode ~= Enum.KeyCode.Escape then
                        key = input.KeyCode
                        if PadTrigger then PadTrigger.Text = key.Name end
                        OnChanged:Fire(key)
                    end
                    KeyBtn.Text = key.Name
                elseif not gp and input.KeyCode == key then
                    TriggerBind(true)
                end
            end))

            if mode == "Hold" then
                m:GiveTask(UserInputService.InputEnded:Connect(function(input)
                    if input.KeyCode == key then
                        TriggerBind(false)
                    end
                end))
            end

            return RegisterItem({
                OnChanged = OnChanged,
                Trigger = function(_, stateArg) TriggerBind(stateArg ~= false) end,
                Set = function(_, k)
                    if typeof(k) == "EnumItem" then
                        key = k
                        KeyBtn.Text = key.Name
                        if PadTrigger then PadTrigger.Text = key.Name end
                    end
                end,
                Get = function() return key end
            }, Container, m, kConfig.Flag)
        end

        function containerObj:AddColorPicker(cConfig)
            cConfig = cConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local color = cConfig.Default or theme.Primary
            local h, s, v = Color3.toHSV(color)
            local opened = false
            local OnChanged = Signal.new()
            m:GiveTask(OnChanged)

            local function ColorToHex(c)
                return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
            end

            local function HexToColor(hex)
                hex = tostring(hex):gsub("#", "")
                if #hex ~= 6 then return nil end
                local r = tonumber(hex:sub(1, 2), 16)
                local g = tonumber(hex:sub(3, 4), 16)
                local b = tonumber(hex:sub(5, 6), 16)
                if r and g and b then
                    return Color3.fromRGB(r, g, b)
                end
                return nil
            end

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, rowHeight),
                ClipsDescendants = true,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local HeaderBtn = FX.Create("TextButton", {
                Text = "",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, rowHeight),
                Parent = Container
            })

            local TitleLbl = FX.Create("TextLabel", {
                Text = cConfig.Title or "ColorPicker",
                Font = theme.FontMedium,
                TextSize = 13,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(0.65, 0, 1, 0),
                BackgroundTransparency = 1,
                Parent = HeaderBtn
            })

            local Preview = FX.Create("Frame", {
                BackgroundColor3 = color,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.new(0, 46, 0, 24),
                Parent = HeaderBtn
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
            })

            local PickerPanel = FX.Create("Frame", {
                Position = UDim2.new(0, 12, 0, rowHeight + 4),
                Size = UDim2.new(1, -24, 0, 140),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local SVBox = FX.Create("TextButton", {
                Text = "",
                AutoButtonColor = false,
                Size = UDim2.new(1, -36, 0, 98),
                BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                ClipsDescendants = true,
                Parent = PickerPanel
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
            })

            FX.Create("Frame", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Parent = SVBox
            }, {
                FX.Create("UIGradient", {
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0),
                        NumberSequenceKeypoint.new(1, 1)
                    })
                })
            })

            FX.Create("Frame", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Color3.new(0, 0, 0),
                BorderSizePixel = 0,
                ZIndex = 2,
                Parent = SVBox
            }, {
                FX.Create("UIGradient", {
                    Rotation = 90,
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(1, 0)
                    })
                })
            })

            local SVCursor = FX.Create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(s, 0, 1 - v, 0),
                Size = UDim2.new(0, 14, 0, 14),
                BackgroundColor3 = Color3.new(1, 1, 1),
                ZIndex = 3,
                Parent = SVBox
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })

            local HueBar = FX.Create("TextButton", {
                Text = "",
                AutoButtonColor = false,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0, 24, 0, 98),
                BackgroundColor3 = Color3.new(1, 1, 1),
                Parent = PickerPanel
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
                FX.Create("UIGradient", {
                    Rotation = 90,
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
                    })
                })
            })

            local HueCursor = FX.Create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, h, 0),
                Size = UDim2.new(1, 4, 0, 4),
                BackgroundColor3 = Color3.new(1, 1, 1),
                Parent = HueBar
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })

            local HexInput = FX.Create("TextBox", {
                Text = ColorToHex(color),
                PlaceholderText = "#RRGGBB",
                Font = theme.FontBold,
                TextSize = 12,
                TextColor3 = theme.TextPrimary,
                BackgroundColor3 = theme.Background,
                Position = UDim2.new(0, 0, 0, 106),
                Size = UDim2.new(1, 0, 0, 28),
                ClearTextOnFocus = false,
                Parent = PickerPanel
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
            })

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                HexInput.BackgroundColor3 = t.Background
                HexInput.TextColor3 = t.TextPrimary
            end)

            local function SyncVisuals(silent)
                color = Color3.fromHSV(h, s, v)
                SVBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                Preview.BackgroundColor3 = color
                SVCursor.Position = UDim2.new(s, 0, 1 - v, 0)
                HueCursor.Position = UDim2.new(0.5, 0, h, 0)
                HexInput.Text = ColorToHex(color)

                if not silent then
                    OnChanged:Fire(color)
                    if cConfig.Callback then
                        task.spawn(SafeCall, cConfig.Callback, color)
                    end
                end
            end

            local dragSV, dragHue = false, false

            local function UpdateSV(pos)
                s = math.clamp((pos.X - SVBox.AbsolutePosition.X) / math.max(SVBox.AbsoluteSize.X, 1), 0, 1)
                v = 1 - math.clamp((pos.Y - SVBox.AbsolutePosition.Y) / math.max(SVBox.AbsoluteSize.Y, 1), 0, 1)
                SyncVisuals(false)
            end

            local function UpdateHue(pos)
                h = math.clamp((pos.Y - HueBar.AbsolutePosition.Y) / math.max(HueBar.AbsoluteSize.Y, 1), 0, 1)
                SyncVisuals(false)
            end

            m:GiveTask(SVBox.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragSV = true
                    UpdateSV(input.Position)
                end
            end))

            m:GiveTask(HueBar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragHue = true
                    UpdateHue(input.Position)
                end
            end))

            m:GiveTask(UserInputService.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    if dragSV then UpdateSV(input.Position) end
                    if dragHue then UpdateHue(input.Position) end
                end
            end))

            m:GiveTask(UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragSV = false
                    dragHue = false
                end
            end))

            m:GiveTask(HexInput.FocusLost:Connect(function()
                local parsed = HexToColor(HexInput.Text)
                if parsed then
                    h, s, v = Color3.toHSV(parsed)
                    SyncVisuals(false)
                else
                    HexInput.Text = ColorToHex(color)
                end
            end))

            m:GiveTask(HeaderBtn.MouseButton1Click:Connect(function()
                opened = not opened
                Animator:Spring(Container, "Size", UDim2.new(1, 0, 0, opened and (rowHeight + 150) or rowHeight), 0.72, 16)
            end))

            return RegisterItem({
                OnChanged = OnChanged,
                Set = function(_, newCol, silent)
                    if typeof(newCol) == "Color3" then
                        h, s, v = Color3.toHSV(newCol)
                        SyncVisuals(silent)
                    end
                end,
                Get = function() return color end
            }, Container, m, cConfig.Flag)
        end

        function containerObj:AddProgressBar(pConfig)
            pConfig = pConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local progress = math.clamp(pConfig.Default or 0, 0, 100)
            local customColors = pConfig.Colors

            local Container = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, 46),
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Container, 0.35, theme.Border)

            local TitleLbl = FX.Create("TextLabel", {
                Text = pConfig.Title or "Progreso",
                Font = theme.FontMedium,
                TextSize = 12,
                TextColor3 = theme.TextPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 12, 0, 6),
                Size = UDim2.new(0.7, 0, 0, 16),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local PctLabel = FX.Create("TextLabel", {
                Text = tostring(math.floor(progress + 0.5)) .. "%",
                Font = theme.FontBold,
                TextSize = 11,
                TextColor3 = theme.Secondary,
                TextXAlignment = Enum.TextXAlignment.Right,
                Position = UDim2.new(0.7, 0, 0, 6),
                Size = UDim2.new(0.3, -12, 0, 16),
                BackgroundTransparency = 1,
                Parent = Container
            })

            local BarBg = FX.Create("Frame", {
                Position = UDim2.new(0, 12, 0, 28),
                Size = UDim2.new(1, -24, 0, 8),
                BackgroundColor3 = theme.Background,
                Parent = Container
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })

            local BarFill = FX.Create("Frame", {
                Size = UDim2.new(progress / 100, 0, 1, 0),
                BackgroundColor3 = Color3.new(1, 1, 1),
                Parent = BarBg
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
            })
            FX.AnimatedGradient(BarFill, customColors or { theme.Primary, theme.Secondary }, 35, 0)

            BindTheme(function(t)
                Container.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
                TitleLbl.TextColor3 = t.TextPrimary
                PctLabel.TextColor3 = t.Secondary
                BarBg.BackgroundColor3 = t.Background
                if not customColors then
                    FX.AnimatedGradient(BarFill, { t.Primary, t.Secondary }, 35, 0)
                end
            end)

            return RegisterItem({
                Set = function(_, val, newTitle)
                    progress = math.clamp(tonumber(val) or 0, 0, 100)
                    if newTitle then TitleLbl.Text = tostring(newTitle) end
                    PctLabel.Text = tostring(math.floor(progress + 0.5)) .. "%"
                    Animator:Spring(BarFill, "Size", UDim2.new(progress / 100, 0, 1, 0), 0.78, 18)
                end,
                SetColors = function(_, cols)
                    customColors = cols
                    FX.AnimatedGradient(BarFill, cols, 35, 0)
                end,
                Get = function() return progress end
            }, Container, m)
        end

        function containerObj:AddImage(imgConfig)
            imgConfig = imgConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local h = imgConfig.Height or 120

            local Holder = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, h),
                ClipsDescendants = true,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Holder, 0.35, theme.Border)

            local Img = FX.Create("ImageLabel", {
                Image = tostring(imgConfig.Image or ""),
                ScaleType = imgConfig.ScaleType or Enum.ScaleType.Fit,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -12, 1, -12),
                Position = UDim2.new(0, 6, 0, 6),
                Parent = Holder
            })

            BindTheme(function(t)
                Holder.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
            end)

            return RegisterItem({
                Set = function(_, assetId) Img.Image = tostring(assetId) end,
                Get = function() return Img.Image end
            }, Holder, m)
        end

        function containerObj:AddVideo(vidConfig)
            vidConfig = vidConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local h = vidConfig.Height or 140

            local Holder = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                Size = UDim2.new(1, 0, 0, h),
                ClipsDescendants = true,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius })
            })
            local Stroke = FX.ApplyGlass(Holder, 0.35, theme.Border)

            local Video = FX.Create("VideoFrame", {
                Video = tostring(vidConfig.Video or ""),
                Looped = vidConfig.Looped ~= false,
                Playing = vidConfig.Playing ~= false,
                Volume = vidConfig.Volume or 0.5,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -12, 1, -12),
                Position = UDim2.new(0, 6, 0, 6),
                Parent = Holder
            })

            BindTheme(function(t)
                Holder.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
            end)

            return RegisterItem({
                Play = function() pcall(function() Video:Play() end) end,
                Pause = function() pcall(function() Video:Pause() end) end,
                Set = function(_, videoId) Video.Video = tostring(videoId) end,
                Get = function() return Video.Video end
            }, Holder, m)
        end

        function containerObj:AddContainer(cConfig)
            cConfig = cConfig or {}
            local m = Maid.new()
            tabMaid:GiveTask(m)
            local Box = FX.Create("Frame", {
                BackgroundColor3 = theme.Surface,
                BackgroundTransparency = 0.55,
                Size = UDim2.new(1, 0, 0, 40),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = targetScrollingFrame
            }, {
                FX.Create("UICorner", { CornerRadius = theme.CornerRadius }),
                FX.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
                FX.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
            })
            local Stroke = FX.ApplyGlass(Box, 0.55, theme.Border)

            if cConfig.Title then
                FX.Create("TextLabel", {
                    Text = tostring(cConfig.Title),
                    Font = theme.FontBold,
                    TextSize = 12,
                    TextColor3 = theme.Secondary,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundTransparency = 1,
                    Parent = Box
                })
            end

            BindTheme(function(t)
                Box.BackgroundColor3 = t.Surface
                Stroke.Color = t.Border
            end)

            local SubApi = {}
            AttachComponentBuilders(SubApi, Box, m, itemRegistryList)
            RegisterItem(SubApi, Box, m)
            return SubApi
        end

        function containerObj:AddCustom(compName, compConfig)
            local builder = PlowUI.CustomComponents[compName]
            assert(builder, "Componente personalizado no registrado: " .. tostring(compName))
            return builder(containerObj, targetScrollingFrame, theme, tabMaid, compConfig or {})
        end
    end

    -- ========================================================================
    -- 9. CREACIÓN DE PESTAÑAS (TABS) Y SUB-PESTAÑAS (SUBTABS)
    -- ========================================================================
    function Window:CreateTab(tabConfig)
        local tabName = type(tabConfig) == "string" and tabConfig or (tabConfig.Title or "Tab")
        local iconId = type(tabConfig) == "table" and tabConfig.Icon or nil
        local TabMaid = Maid.new()
        WindowMaid:GiveTask(TabMaid)

        local TabBtn = FX.Create("TextButton", {
            Text = "",
            BackgroundColor3 = theme.Primary,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -12, 0, isMobile and 38 or 34),
            AutoButtonColor = false,
            ClipsDescendants = true,
            Parent = Sidebar
        }, {
            FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) })
        })

        local hasIcon = iconId ~= nil
        local IconImg
        if hasIcon then
            IconImg = FX.Create("ImageLabel", {
                Image = tostring(iconId),
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 8, 0.5, -8),
                Size = UDim2.new(0, 16, 0, 16),
                ImageColor3 = theme.TextSecondary,
                Parent = TabBtn
            })
        end

        local TabLabel = FX.Create("TextLabel", {
            Text = tabName,
            Font = theme.FontMedium,
            TextSize = 12,
            TextColor3 = theme.TextSecondary,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, hasIcon and 28 or 10, 0, 0),
            Size = UDim2.new(1, hasIcon and -34 or -16, 1, 0),
            BackgroundTransparency = 1,
            Parent = TabBtn
        })

        local Indicator = FX.Create("Frame", {
            Size = UDim2.new(0, 3, 0, 0),
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = theme.Secondary,
            BorderSizePixel = 0,
            Parent = TabBtn
        }, {
            FX.Create("UICorner", { CornerRadius = UDim.new(1, 0) })
        })

        local PageWrapper = FX.Create("Frame", {
            Name = tabName .. "_Wrapper",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = PagesContainer
        })

        local Page = FX.Create("ScrollingFrame", {
            Name = tabName .. "_Page",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            ScrollBarThickness = isMobile and 4 or 3,
            ScrollBarImageColor3 = theme.Primary,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BorderSizePixel = 0,
            Parent = PageWrapper
        }, {
            FX.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
            FX.Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12) })
        })

        local TabObj = {
            Button = TabBtn,
            Page = Page,
            Wrapper = PageWrapper,
            Indicator = Indicator,
            _items = {},
            _subTabs = nil
        }

        BindTheme(function(t)
            TabBtn.BackgroundColor3 = t.Primary
            Indicator.BackgroundColor3 = t.Secondary
            Page.ScrollBarImageColor3 = t.Primary
            local isAct = (Window.ActiveTab == TabObj)
            TabLabel.TextColor3 = isAct and t.TextPrimary or t.TextSecondary
            if IconImg then IconImg.ImageColor3 = isAct and t.Secondary or t.TextSecondary end
        end)

        local function ActivateTab()
            if Window.ActiveTab == TabObj then return end
            if Window.ActiveTab then
                local prev = Window.ActiveTab
                Animator:Tween(prev.Button, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
                Animator:Spring(prev.Indicator, "Size", UDim2.new(0, 3, 0, 0), 0.8, 18)
                prev.Wrapper.Visible = false
                prev.Button:FindFirstChildOfClass("TextLabel").TextColor3 = theme.TextSecondary
            end

            Window.ActiveTab = TabObj
            PageWrapper.Visible = true
            PageWrapper.Position = UDim2.new(0, 14, 0, 0)
            Animator:Spring(PageWrapper, "Position", UDim2.new(0, 0, 0, 0), 0.78, 20)
            Animator:Tween(TabBtn, TweenInfo.new(0.25), { BackgroundTransparency = 0.82 })
            TabLabel.TextColor3 = theme.TextPrimary
            if IconImg then IconImg.ImageColor3 = theme.Secondary end
            Animator:Spring(Indicator, "Size", UDim2.new(0, 3, 0, 18), 0.65, 16)
        end

        TabMaid:GiveTask(TabBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                FX.Ripple(TabBtn, theme.Secondary, input.Position)
                ActivateTab()
            end
        end))

        if not Window.ActiveTab then
            ActivateTab()
        end

        function TabObj:CreateSubTab(subTitle)
            if not TabObj._subTabs then
                local SubBar = FX.Create("ScrollingFrame", {
                    Name = "SubTabBar",
                    Size = UDim2.new(1, -6, 0, 32),
                    BackgroundColor3 = theme.Surface,
                    BackgroundTransparency = 0.45,
                    ScrollBarThickness = 0,
                    ScrollingDirection = Enum.ScrollingDirection.X,
                    AutomaticCanvasSize = Enum.AutomaticSize.X,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    BorderSizePixel = 0,
                    Parent = PageWrapper
                }, {
                    FX.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
                    FX.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }),
                    FX.Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
                })

                Page.Visible = false
                TabObj._subTabs = {
                    Bar = SubBar,
                    ActiveSub = nil
                }
            end

            local subData = TabObj._subTabs
            local SubBtn = FX.Create("TextButton", {
                Text = tostring(subTitle or "SubTab"),
                Font = theme.FontBold,
                TextSize = 11,
                TextColor3 = theme.TextSecondary,
                BackgroundColor3 = theme.Primary,
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.X,
                Parent = subData.Bar
            }, {
                FX.Create("UICorner", { CornerRadius = UDim.new(0, 5) }),
                FX.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
            })

            local SubPage = FX.Create("ScrollingFrame", {
                Position = UDim2.new(0, 0, 0, 38),
                Size = UDim2.new(1, 0, 1, -38),
                BackgroundTransparency = 1,
                ScrollBarThickness = isMobile and 4 or 3,
                ScrollBarImageColor3 = theme.Primary,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                Visible = false,
                BorderSizePixel = 0,
                Parent = PageWrapper
            }, {
                FX.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
                FX.Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12) })
            })

            local SubObj = { _items = {} }
            AttachComponentBuilders(SubObj, SubPage, TabMaid, SubObj._items)

            local function ActivateSub()
                if subData.ActiveSub == SubObj then return end
                if subData.ActiveSub then
                    subData.ActiveSub._btn.BackgroundTransparency = 1
                    subData.ActiveSub._btn.TextColor3 = theme.TextSecondary
                    subData.ActiveSub._page.Visible = false
                end
                subData.ActiveSub = SubObj
                SubPage.Visible = true
                Animator:Tween(SubBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.78 })
                SubBtn.TextColor3 = theme.TextPrimary
            end

            SubObj._btn = SubBtn
            SubObj._page = SubPage

            TabMaid:GiveTask(SubBtn.MouseButton1Click:Connect(ActivateSub))
            if not subData.ActiveSub then
                ActivateSub()
            end

            return SubObj
        end

        AttachComponentBuilders(TabObj, Page, TabMaid, TabObj._items)
        table.insert(Window.Tabs, TabObj)
        return TabObj
    end

    function Window:UsePlugin(pluginName, pluginOpts)
        local pluginDef = PlowUI.Plugins[pluginName]
        assert(pluginDef, "Plugin no encontrado: " .. tostring(pluginName))
        if type(pluginDef.OnWindow) == "function" then
            local instance = pluginDef.OnWindow(Window, pluginOpts or {})
            WindowPlugins[pluginName] = instance
            return instance
        end
    end

    return Window
end

return PlowUI
