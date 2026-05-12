local AdminUI = {}
AdminUI._VERSION = "1.0.0"
local OvertimeUI = AdminUI  -- backwards-compatibility alias

-- =========================================================================
-- Services & locals
-- =========================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP         = Players.LocalPlayer

local FONT      = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local FONT_SEMI = Enum.Font.GothamMedium

-- =========================================================================
-- Theme system
-- =========================================================================

local function defaultTheme()
    return {
        bg        = Color3.fromRGB(14,  16,  22),
        bgAlt     = Color3.fromRGB(18,  21,  28),
        surface   = Color3.fromRGB(28,  32,  42),
        surfaceHi = Color3.fromRGB(36,  41,  54),
        border    = Color3.fromRGB(48,  54,  68),
        accent    = Color3.fromRGB(90,  180, 255),
        text      = Color3.fromRGB(232, 234, 242),
        textDim   = Color3.fromRGB(150, 156, 170),
        muted     = Color3.fromRGB(100, 106, 120),
        danger    = Color3.fromRGB(220, 80,  80),
        success   = Color3.fromRGB(80,  200, 100),
        warning   = Color3.fromRGB(230, 180, 60),
        disabled  = Color3.fromRGB(55,  60,  74),
    }
end

local _globalThemeOverrides = {}

function AdminUI:SetTheme(overrides)
    if type(overrides) ~= "table" then return end
    for k, v in pairs(overrides) do
        _globalThemeOverrides[k] = v
    end
end

local function makeTheme(accent)
    local t = defaultTheme()
    for k, v in pairs(_globalThemeOverrides) do t[k] = v end
    if typeof(accent) == "Color3" then t.accent = accent end
    return t
end

local function stateColor(theme, state)
    if state == "success" then return theme.success end
    if state == "warning" then return theme.warning end
    if state == "error"   then return theme.danger  end
    if state == "loading" then return theme.textDim end
    return theme.accent  -- "info" and default
end

local function stateIcon(state)
    if state == "success" then return "OK" end
    if state == "warning" then return "!!" end
    if state == "error"   then return "X" end
    if state == "loading" then return "..." end
    return "i"
end

-- =========================================================================
-- Safe callback execution -- every user callback runs through this
-- =========================================================================

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[AdminUI] callback error:", tostring(err))
    end
end

-- =========================================================================
-- UI primitives
-- =========================================================================

local function Create(class, props)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then inst[k] = v end
        end
        if props.Parent then inst.Parent = props.Parent end
    end
    return inst
end

local function corner(parent, radius)
    return Create("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function stroke(parent, color, thickness)
    return Create("UIStroke", { Color = color, Thickness = thickness or 1, Parent = parent })
end

-- Clamp a popup frame to stay inside the viewport after positioning.
local function clampPopupPosition(frame)
    task.defer(function()
        if not frame or not frame.Parent then return end
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
                   or Vector2.new(1920, 1080)
        local ax = frame.AbsolutePosition.X
        local ay = frame.AbsolutePosition.Y
        local aw = frame.AbsoluteSize.X
        local ah = frame.AbsoluteSize.Y
        local nx = math.clamp(ax, 4, vp.X - aw - 4)
        local ny = math.clamp(ay, 4, vp.Y - ah - 4)
        if nx ~= ax or ny ~= ay then
            frame.Position = UDim2.fromOffset(nx, ny)
        end
    end)
end

-- =========================================================================
-- Keybind helpers (kept for Toggle:AddKeybind and CreateKeybind)
-- =========================================================================

local mouseExCache = { t = 0, m4 = false, m5 = false }
local function pollMouseEx()
    local now = tick()
    if now - mouseExCache.t < 0.05 then return end
    mouseExCache.t = now
    local m4, m5 = false, false
    pcall(function()
        if isMouse4Down then m4 = isMouse4Down() end
        if isMouse5Down then m5 = isMouse5Down() end
    end)
    mouseExCache.m4 = m4
    mouseExCache.m5 = m5
end

local function isKeybindHeld(keyStr)
    if not keyStr or keyStr == "" or keyStr == "None" or keyStr == "Unknown" then return false end
    if keyStr == "MouseButton1" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
    if keyStr == "MouseButton2" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
    if keyStr == "MouseButton3" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) end
    if keyStr == "Mouse4" then pollMouseEx(); return mouseExCache.m4 end
    if keyStr == "Mouse5" then pollMouseEx(); return mouseExCache.m5 end
    local kc = Enum.KeyCode[keyStr]
    return kc and UIS:IsKeyDown(kc) or false
end

local function keybindLabel(keyStr)
    if not keyStr or keyStr == "" or keyStr == "None" or keyStr == "Unknown" then return "None" end
    if keyStr == "MouseButton1" then return "LMB" end
    if keyStr == "MouseButton2" then return "RMB" end
    if keyStr == "MouseButton3" then return "MMB" end
    if keyStr == "Mouse4"       then return "MB4" end
    if keyStr == "Mouse5"       then return "MB5" end
    return keyStr
end

local function inputObjectToKeybind(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
    if t == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
    if t == Enum.UserInputType.MouseButton3 then return "MouseButton3" end
    if t == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
        return input.KeyCode.Name
    end
    return nil
end

local function normalizeReturnType(returnType)
    return tostring(returnType or "Name"):lower()
end

local function playerNameFromValue(value)
    if value == nil then return "" end
    if typeof(value) == "Instance" and value:IsA("Player") then return value.Name end
    if type(value) == "number" then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == value then return player.Name end
        end
        return tostring(value)
    end
    return tostring(value)
end

local function playerValueFromName(name, returnType)
    if name == nil or name == "" then return nil end
    if name == "All" then return "All" end
    local player = Players:FindFirstChild(tostring(name))
    local normalized = normalizeReturnType(returnType)
    if normalized == "userid" then
        return player and player.UserId or tonumber(name)
    elseif normalized == "player" then
        return player
    end
    return player and player.Name or tostring(name)
end

local function convertPlayerSelection(raw, returnType, isMulti)
    if isMulti then
        local converted = {}
        if type(raw) == "table" then
            for _, item in ipairs(raw) do
                local convertedValue = playerValueFromName(playerNameFromValue(item), returnType)
                if convertedValue ~= nil then table.insert(converted, convertedValue) end
            end
        end
        return converted
    end
    return playerValueFromName(playerNameFromValue(raw), returnType)
end

local function durationToSeconds(value, unit)
    local n = tonumber(value)
    if not n then return nil end
    if unit == "permanent" then return math.huge end
    if unit == "minutes" then return n * 60 end
    if unit == "hours" then return n * 3600 end
    if unit == "days" then return n * 86400 end
    return n
end

local function buildKeybindControl(theme, parent, initialKey, position, size, onKeyChanged)
    local keyStr = initialKey or "None"
    local rebinding = false
    local rebindOpened = 0
    local rebindConns = {}

    local btn = Create("TextButton", {
        Size = size or UDim2.fromOffset(56, 18),
        Position = position or UDim2.new(1, -60, 0.5, -9),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = keybindLabel(keyStr),
        TextColor3 = theme.accent,
        Font = FONT_SEMI,
        TextSize = 11,
        AutoButtonColor = false,
        Parent = parent,
    })
    corner(btn, 3)
    stroke(btn, theme.border, 1)

    local function stopRebind()
        rebinding = false
        for _, c in ipairs(rebindConns) do c:Disconnect() end
        table.clear(rebindConns)
    end

    local function applyKey(newKey, fireCallback)
        keyStr = newKey or "None"
        btn.Text = keybindLabel(keyStr)
        btn.TextColor3 = theme.accent
        if fireCallback and onKeyChanged then
            task.spawn(safeCall, onKeyChanged, keyStr)
        end
    end

    local function startRebind()
        if rebinding then return end
        rebinding = true
        rebindOpened = tick()
        btn.Text = "..."
        btn.TextColor3 = theme.danger

        table.insert(rebindConns, UIS.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if tick() - rebindOpened < 0.1 then return end
            local captured = inputObjectToKeybind(input)
            if captured then stopRebind(); applyKey(captured, true) end
        end))

        table.insert(rebindConns, RunService.Heartbeat:Connect(function()
            if not rebinding then return end
            if tick() - rebindOpened < 0.1 then return end
            pollMouseEx()
            if mouseExCache.m4 then stopRebind(); applyKey("Mouse4", true)
            elseif mouseExCache.m5 then stopRebind(); applyKey("Mouse5", true) end
        end))
    end

    btn.MouseButton1Click:Connect(startRebind)

    return {
        button  = btn,
        get     = function() return keyStr end,
        set     = function(v, fire) applyKey(v, fire) end,
        isHeld  = function() return isKeybindHeld(keyStr) end,
        cleanup = stopRebind,
    }
end

-- =========================================================================
-- Section - all controls live here
-- =========================================================================

local Section = {}
Section.__index = Section

function Section:_next()
    self._order = (self._order or 0) + 1
    return self._order
end

-- -- Toggle ------------------------------------------------------------------

function Section:CreateToggle(cfg)
    cfg = cfg or {}
    local window = self.tab.window
    local theme  = window.theme
    local state  = cfg.CurrentValue == true
    local handle = { Type = "Toggle", Name = cfg.Name or "Toggle" }

    local row = Create("TextButton", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    local box = Create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = state and theme.accent or theme.surface,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(box, 3); stroke(box, theme.border, 1)

    local check = Create("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "OK",
        TextColor3 = Color3.new(1, 1, 1),
        Font = FONT_BOLD,
        TextSize = 11,
        Visible = state,
        Parent = box,
    })

    local label = Create("TextLabel", {
        Size = UDim2.new(1, -26, 1, 0),
        Position = UDim2.new(0, 26, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Toggle",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local function setState(v, fireCallback)
        v = not not v
        if v == state then return end
        state = v
        box.BackgroundColor3 = state and theme.accent or theme.surface
        check.Visible = state
        if fireCallback then task.spawn(safeCall, cfg.Callback, state) end
    end

    row.MouseButton1Click:Connect(function() setState(not state, true) end)

    function handle:Get()       return state end
    function handle:Set(v)      setState(v, true) end
    function handle:SetSilent(v) setState(v, false) end
    function handle:Destroy()   row:Destroy() end

    local kbCtrl
    function handle:AddKeybind(kbCfg)
        if kbCtrl then
            warn("[AdminUI] AddKeybind called twice on toggle '"..tostring(cfg.Name).."'")
            return self
        end
        kbCfg = kbCfg or {}
        label.Size = UDim2.new(1, -26 - 64, 1, 0)
        kbCtrl = buildKeybindControl(theme, row, kbCfg.CurrentKeybind or "None",
            UDim2.new(1, -60, 0.5, -9), UDim2.fromOffset(56, 18), kbCfg.Callback)
        table.insert(window._cleanup, kbCtrl.cleanup)
        function self:GetKeybind()        return kbCtrl.get() end
        function self:SetKeybind(v)       kbCtrl.set(v, true) end
        function self:SetKeybindSilent(v) kbCtrl.set(v, false) end
        function self:IsKeybindHeld()     return kbCtrl.isHeld() end
        return self
    end

    return handle
end

-- -- Keybind -----------------------------------------------------------------

function Section:CreateKeybind(cfg)
    cfg = cfg or {}
    local window = self.tab.window
    local theme  = window.theme
    local handle = { Type = "Keybind", Name = cfg.Name or "Keybind" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -64, 1, 0),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Keybind",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local ctrl = buildKeybindControl(theme, row, cfg.CurrentKeybind or "None",
        UDim2.new(1, -60, 0.5, -9), UDim2.fromOffset(56, 18), cfg.Callback)
    table.insert(window._cleanup, ctrl.cleanup)

    function handle:Get()        return ctrl.get() end
    function handle:Set(v)       ctrl.set(v, true) end
    function handle:SetSilent(v) ctrl.set(v, false) end
    function handle:IsHeld()     return ctrl.isHeld() end
    function handle:Destroy()    row:Destroy() end

    return handle
end

-- -- Slider ------------------------------------------------------------------

function Section:CreateSlider(cfg)
    cfg = cfg or {}
    local window = self.tab.window
    local theme  = window.theme
    local minVal = (cfg.Range and cfg.Range[1]) or 0
    local maxVal = (cfg.Range and cfg.Range[2]) or 100
    local step   = cfg.Increment or 1
    local value  = cfg.CurrentValue or minVal
    local suffix = cfg.Suffix or ""
    local handle = { Type = "Slider", Name = cfg.Name or "Slider" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -84, 0, 14),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Slider",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local valLbl = Create("TextLabel", {
        Size = UDim2.new(0, 80, 0, 14),
        Position = UDim2.new(1, -82, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = theme.accent,
        Font = FONT_SEMI,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })

    local track = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 6),
        Position = UDim2.new(0, 2, 0, 22),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Active = true,
        Parent = row,
    })
    corner(track, 3)

    local fill = Create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = theme.accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, 3)

    local function formatValue(v)
        if step >= 1 then return string.format("%d%s", math.floor(v + 0.5), suffix) end
        return string.format("%.2f%s", v, suffix)
    end

    local function setValue(v, fireCallback)
        v = math.clamp(v, minVal, maxVal)
        if step > 0 then
            v = math.floor((v - minVal) / step + 0.5) * step + minVal
            v = math.clamp(v, minVal, maxVal)
        end
        if v == value and valLbl.Text ~= "" then return end
        value = v
        local pct = (maxVal > minVal) and ((v - minVal) / (maxVal - minVal)) or 0
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valLbl.Text = formatValue(v)
        if fireCallback then task.spawn(safeCall, cfg.Callback, v) end
    end
    setValue(value, false)

    local dragging = false
    local function updateFromInput(input)
        local relX = input.Position.X - track.AbsolutePosition.X
        local pct  = math.clamp(relX / math.max(track.AbsoluteSize.X, 1), 0, 1)
        setValue(minVal + pct * (maxVal - minVal), true)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; updateFromInput(input)
        end
    end)
    track.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    local moveConn = UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                      or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)
    local releaseConn = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    table.insert(window._cleanup, function()
        dragging = false
        moveConn:Disconnect()
        releaseConn:Disconnect()
    end)

    function handle:Get()        return value end
    function handle:Set(v)       setValue(v, true) end
    function handle:SetSilent(v) setValue(v, false) end
    function handle:Destroy()    moveConn:Disconnect(); releaseConn:Disconnect(); row:Destroy() end

    return handle
end

-- -- Dropdown (single-select) ------------------------------------------------

function Section:CreateDropdown(cfg)
    cfg = cfg or {}
    local window  = self.tab.window
    local theme   = window.theme
    local gui     = window.gui
    local options = cfg.Options or {}
    local current = cfg.CurrentOption or options[1] or ""
    local handle  = { Type = "Dropdown", Name = cfg.Name or "Dropdown" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 14),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Dropdown",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local btn = Create("TextButton", {
        Size = UDim2.new(1, -4, 0, 20),
        Position = UDim2.new(0, 2, 0, 16),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = " " .. tostring(current) .. "   v",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AutoButtonColor = false,
        Parent = row,
    })
    corner(btn, 4); stroke(btn, theme.border, 1)

    local popupOpen = false
    local popupBackdrop, popupFrame
    local ddConns = {}

    local function closePopup()
        popupOpen = false
        if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil; popupFrame = nil end
        for _, c in ipairs(ddConns) do c:Disconnect() end
        table.clear(ddConns)
    end

    local function rebuildLabel()
        btn.Text = " " .. tostring(current) .. "   v"
    end

    local function setOption(v, fire)
        current = v; rebuildLabel()
        if fire then task.spawn(safeCall, cfg.Callback, v) end
    end

    local function openPopup()
        if popupOpen then return end
        popupOpen = true

        popupBackdrop = Create("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 50,
            Parent = gui,
        })
        table.insert(ddConns, popupBackdrop.MouseButton1Click:Connect(closePopup))

        local optH  = 22
        local totalH = math.min(#options, 8) * optH + 4
        local px    = btn.AbsolutePosition.X
        local py    = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 2
        popupFrame = Create("Frame", {
            Size = UDim2.fromOffset(btn.AbsoluteSize.X, totalH),
            Position = UDim2.fromOffset(px, py),
            BackgroundColor3 = theme.bgAlt,
            BorderSizePixel = 0,
            ZIndex = 51,
            Parent = popupBackdrop,
        })
        corner(popupFrame, 4); stroke(popupFrame, theme.border, 1)
        clampPopupPosition(popupFrame)

        local scroll = Create("ScrollingFrame", {
            Size = UDim2.new(1, -4, 1, -4),
            Position = UDim2.fromOffset(2, 2),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = theme.border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 52,
            Parent = popupFrame,
        })
        Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = scroll,
        })

        for i, opt in ipairs(options) do
            local display = cfg.FormatOption and cfg.FormatOption(opt) or tostring(opt)
            local optBtn = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = (opt == current) and theme.surfaceHi or theme.surface,
                BorderSizePixel = 0,
                Text = " " .. display,
                TextColor3 = (opt == current) and theme.accent or theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                AutoButtonColor = false,
                LayoutOrder = i,
                ZIndex = 53,
                Parent = scroll,
            })
            corner(optBtn, 3)
            table.insert(ddConns, optBtn.MouseButton1Click:Connect(function()
                setOption(opt, true); closePopup()
            end))
        end
    end

    table.insert(window._connections, btn.MouseButton1Click:Connect(function()
        if popupOpen then closePopup() else openPopup() end
    end))
    table.insert(window._cleanup, closePopup)

    function handle:Get()        return current end
    function handle:Set(v)       setOption(v, true) end
    function handle:SetSilent(v) setOption(v, false) end
    function handle:Open()       openPopup() end
    function handle:Close()      closePopup() end
    function handle:Refresh(newOpts, newCur)
        options = newOpts or {}
        current = (newCur ~= nil) and newCur
                  or (table.find(options, current) and current or (options[1] or ""))
        rebuildLabel(); closePopup()
    end
    function handle:Destroy() closePopup(); row:Destroy() end

    return handle
end

-- -- Searchable Dropdown -----------------------------------------------------

function Section:CreateSearchDropdown(cfg)
    cfg = cfg or {}
    local window  = self.tab.window
    local theme   = window.theme
    local gui     = window.gui
    local options = cfg.Options or {}
    local current = cfg.CurrentOption or ""
    local handle  = { Type = "SearchDropdown", Name = cfg.Name or "Dropdown" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 14),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Dropdown",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local btn = Create("TextButton", {
        Size = UDim2.new(1, -4, 0, 20),
        Position = UDim2.new(0, 2, 0, 16),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = (current ~= "") and (" " .. current .. "   v")
               or (" " .. (cfg.Placeholder or "Select...") .. "   v"),
        TextColor3 = (current ~= "") and theme.text or theme.muted,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AutoButtonColor = false,
        Parent = row,
    })
    corner(btn, 4); stroke(btn, theme.border, 1)

    local popupOpen = false
    local popupBackdrop, popupFrame, searchBox, scrollFrame
    local searchConns = {}

    local function closePopup()
        popupOpen = false
        if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end
        popupFrame = nil; searchBox = nil; scrollFrame = nil
        for _, c in ipairs(searchConns) do c:Disconnect() end
        table.clear(searchConns)
    end

    local function rebuildLabel()
        if current ~= "" then
            local display = cfg.FormatOption and cfg.FormatOption(current) or current
            btn.Text = " " .. display .. "   v"
            btn.TextColor3 = theme.text
        else
            btn.Text = " " .. (cfg.Placeholder or "Select...") .. "   v"
            btn.TextColor3 = theme.muted
        end
    end

    local function setOption(v, fire)
        current = v; rebuildLabel()
        if fire then task.spawn(safeCall, cfg.Callback, v) end
    end

    local function rebuildList(query)
        if not scrollFrame then return end
        for _, c in ipairs(scrollFrame:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local filtered = {}
        local q = query and query:lower() or ""
        for _, opt in ipairs(options) do
            local display = cfg.FormatOption and cfg.FormatOption(opt) or tostring(opt)
            if q == "" or display:lower():find(q, 1, true) then
                table.insert(filtered, { opt = opt, display = display })
            end
        end
        for i, item in ipairs(filtered) do
            local optBtn = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = (item.opt == current) and theme.surfaceHi or theme.surface,
                BorderSizePixel = 0,
                Text = " " .. item.display,
                TextColor3 = (item.opt == current) and theme.accent or theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                AutoButtonColor = false,
                LayoutOrder = i,
                ZIndex = 53,
                Parent = scrollFrame,
            })
            corner(optBtn, 3)
            table.insert(searchConns, optBtn.MouseButton1Click:Connect(function()
                setOption(item.opt, true); closePopup()
            end))
        end
        if #filtered == 0 then
            Create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                Text = "  No results",
                TextColor3 = theme.muted,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = 1,
                ZIndex = 53,
                Parent = scrollFrame,
            })
        end
    end

    local function openPopup()
        if popupOpen then return end
        popupOpen = true

        popupBackdrop = Create("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 50,
            Parent = gui,
        })
        table.insert(searchConns, popupBackdrop.MouseButton1Click:Connect(closePopup))

        local popupW = btn.AbsoluteSize.X
        local popupH = math.min(#options, 6) * 22 + 30 + 4
        local px = btn.AbsolutePosition.X
        local py = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 2

        popupFrame = Create("Frame", {
            Size = UDim2.fromOffset(popupW, popupH),
            Position = UDim2.fromOffset(px, py),
            BackgroundColor3 = theme.bgAlt,
            BorderSizePixel = 0,
            ZIndex = 51,
            Parent = popupBackdrop,
        })
        corner(popupFrame, 4); stroke(popupFrame, theme.border, 1)
        clampPopupPosition(popupFrame)

        -- Search box
        searchBox = Create("TextBox", {
            Size = UDim2.new(1, -8, 0, 24),
            Position = UDim2.fromOffset(4, 3),
            BackgroundColor3 = theme.surface,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = cfg.SearchPlaceholder or "Search...",
            PlaceholderColor3 = theme.muted,
            TextColor3 = theme.text,
            Font = FONT,
            TextSize = 11,
            ClearTextOnFocus = false,
            ZIndex = 52,
            Parent = popupFrame,
        })
        corner(searchBox, 3); stroke(searchBox, theme.border, 1)

        scrollFrame = Create("ScrollingFrame", {
            Size = UDim2.new(1, -4, 1, -32),
            Position = UDim2.fromOffset(2, 30),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = theme.border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 52,
            Parent = popupFrame,
        })
        Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = scrollFrame,
        })

        rebuildList("")
        table.insert(searchConns, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            rebuildList(searchBox.Text)
        end))
    end

    table.insert(window._connections, btn.MouseButton1Click:Connect(function()
        if popupOpen then closePopup() else openPopup() end
    end))
    table.insert(window._cleanup, closePopup)

    function handle:Get()        return current end
    function handle:Set(v)       setOption(v, true) end
    function handle:SetSilent(v) setOption(v, false) end
    function handle:Open()       openPopup() end
    function handle:Close()      closePopup() end
    function handle:Refresh(newOpts, newCur)
        options = newOpts or {}
        current = (newCur ~= nil) and newCur
                  or (table.find(options, current) and current or "")
        rebuildLabel(); closePopup()
    end
    function handle:Destroy() closePopup(); row:Destroy() end

    return handle
end

-- -- Multi-Select Dropdown ---------------------------------------------------

function Section:CreateMultiDropdown(cfg)
    cfg = cfg or {}
    local window   = self.tab.window
    local theme    = window.theme
    local gui      = window.gui
    local options  = cfg.Options or {}
    local selected = {}
    if cfg.CurrentOptions then
        for _, v in ipairs(cfg.CurrentOptions) do selected[v] = true end
    end
    local maxSel = cfg.MaxSelected or math.huge
    local handle = { Type = "MultiDropdown", Name = cfg.Name or "MultiDropdown" }

    local function getSelected()
        local t = {}
        for k in pairs(selected) do table.insert(t, k) end
        return t
    end

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 14),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "MultiDropdown",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local btn = Create("TextButton", {
        Size = UDim2.new(1, -4, 0, 20),
        Position = UDim2.new(0, 2, 0, 16),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AutoButtonColor = false,
        Parent = row,
    })
    corner(btn, 4); stroke(btn, theme.border, 1)

    local function rebuildLabel()
        local sel = getSelected()
        if #sel == 0 then
            btn.Text = " " .. (cfg.Placeholder or "Select...") .. "   v"
            btn.TextColor3 = theme.muted
        else
            btn.Text = " " .. table.concat(sel, ", ") .. "   v"
            btn.TextColor3 = theme.text
        end
    end
    rebuildLabel()

    local popupOpen = false
    local popupBackdrop
    local multiConns = {}

    local function closePopup()
        popupOpen = false
        if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end
        for _, c in ipairs(multiConns) do c:Disconnect() end
        table.clear(multiConns)
    end

    local function openPopup()
        if popupOpen then return end
        popupOpen = true

        popupBackdrop = Create("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 50,
            Parent = gui,
        })
        table.insert(multiConns, popupBackdrop.MouseButton1Click:Connect(closePopup))

        local optH  = 24
        local totalH = math.min(#options, 7) * optH + 4
        local px = btn.AbsolutePosition.X
        local py = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 2

        local popupFrame = Create("Frame", {
            Size = UDim2.fromOffset(btn.AbsoluteSize.X, totalH),
            Position = UDim2.fromOffset(px, py),
            BackgroundColor3 = theme.bgAlt,
            BorderSizePixel = 0,
            ZIndex = 51,
            Parent = popupBackdrop,
        })
        corner(popupFrame, 4); stroke(popupFrame, theme.border, 1)
        clampPopupPosition(popupFrame)

        local scroll = Create("ScrollingFrame", {
            Size = UDim2.new(1, -4, 1, -4),
            Position = UDim2.fromOffset(2, 2),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = theme.border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 52,
            Parent = popupFrame,
        })
        Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = scroll,
        })

        local optBtns = {}
        for i, opt in ipairs(options) do
            local isOn = selected[opt] == true
            local optRow = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = isOn and theme.surfaceHi or theme.surface,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = i,
                ZIndex = 53,
                Parent = scroll,
            })
            corner(optRow, 3)

            local chk = Create("Frame", {
                Size = UDim2.fromOffset(12, 12),
                Position = UDim2.new(0, 5, 0.5, -6),
                BackgroundColor3 = isOn and theme.accent or theme.surface,
                BorderSizePixel = 0,
                ZIndex = 54,
                Parent = optRow,
            })
            corner(chk, 2); stroke(chk, theme.border, 1)
            Create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "OK",
                TextColor3 = Color3.new(1, 1, 1),
                Font = FONT_BOLD,
                TextSize = 9,
                Visible = isOn,
                ZIndex = 55,
                Parent = chk,
            })

            Create("TextLabel", {
                Size = UDim2.new(1, -22, 1, 0),
                Position = UDim2.new(0, 22, 0, 0),
                BackgroundTransparency = 1,
                Text = tostring(opt),
                TextColor3 = isOn and theme.accent or theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 54,
                Parent = optRow,
            })

            optBtns[opt] = { row = optRow, chk = chk }

            table.insert(multiConns, optRow.MouseButton1Click:Connect(function()
                local nowOn = not (selected[opt] == true)
                local sel = getSelected()
                if nowOn and #sel >= maxSel then return end
                selected[opt] = nowOn or nil
                chk.BackgroundColor3 = nowOn and theme.accent or theme.surface
                chk:FindFirstChildWhichIsA("TextLabel").Visible = nowOn
                optRow.BackgroundColor3 = nowOn and theme.surfaceHi or theme.surface
                optRow:FindFirstChildWhichIsA("TextLabel").TextColor3 = nowOn and theme.accent or theme.text
                rebuildLabel()
                task.spawn(safeCall, cfg.Callback, getSelected())
            end))
        end
    end

    table.insert(window._connections, btn.MouseButton1Click:Connect(function()
        if popupOpen then closePopup() else openPopup() end
    end))
    table.insert(window._cleanup, closePopup)

    function handle:Get()        return getSelected() end
    function handle:Set(opts)
        selected = {}
        if opts then for _, v in ipairs(opts) do selected[v] = true end end
        rebuildLabel(); task.spawn(safeCall, cfg.Callback, getSelected())
    end
    function handle:SetSilent(opts)
        selected = {}
        if opts then for _, v in ipairs(opts) do selected[v] = true end end
        rebuildLabel()
    end
    function handle:Clear()
        selected = {}; rebuildLabel()
        task.spawn(safeCall, cfg.Callback, {})
    end
    function handle:Refresh(newOpts, newSel)
        options = newOpts or {}
        selected = {}
        if newSel then for _, v in ipairs(newSel) do selected[v] = true end end
        rebuildLabel(); closePopup()
    end
    function handle:Destroy() closePopup(); row:Destroy() end

    return handle
end

-- -- Player Selector ---------------------------------------------------------
-- Builds on top of SearchDropdown but auto-populates from Players service.

function Section:CreatePlayerSelector(cfg)
    cfg = cfg or {}
    local window = self.tab.window

    local allowSelf = cfg.AllowSelf ~= false
    local allowAll  = cfg.AllowAll  == true
    local isMulti   = cfg.Multi     == true
    local returnType = cfg.ReturnType or "Name"
    local handle    = { Type = "PlayerSelector", Name = cfg.Name or "Player" }
    local subHandle

    -- Build option list from current players
    local function buildOptions()
        local opts = {}
        if allowAll then table.insert(opts, "All") end
        for _, p in ipairs(Players:GetPlayers()) do
            if allowSelf or p ~= LP then
                table.insert(opts, p.Name)
            end
        end
        return opts
    end

    local function normalizeSetValue(value)
        if isMulti then
            local normalized = {}
            if type(value) == "table" then
                for _, item in ipairs(value) do
                    table.insert(normalized, playerNameFromValue(item))
                end
            end
            return normalized
        end
        return playerNameFromValue(value)
    end

    local function currentValue()
        return convertPlayerSelection(subHandle:Get(), returnType, isMulti)
    end

    if isMulti then
        subHandle = self:CreateMultiDropdown({
            Name           = cfg.Name or "Players",
            Options        = buildOptions(),
            CurrentOptions = normalizeSetValue(cfg.CurrentOptions or cfg.Default),
            Placeholder    = cfg.Placeholder or "Select players...",
            MaxSelected    = cfg.MaxSelected,
            Callback       = function(selected)
                task.spawn(safeCall, cfg.Callback, convertPlayerSelection(selected, returnType, true))
            end,
        })
    else
        subHandle = self:CreateSearchDropdown({
            Name           = cfg.Name or "Player",
            Options        = buildOptions(),
            CurrentOption  = normalizeSetValue(cfg.CurrentOption or cfg.Default),
            Placeholder    = cfg.Placeholder or "Select player...",
            SearchPlaceholder = "Search players...",
            Callback       = function(opt)
                task.spawn(safeCall, cfg.Callback, convertPlayerSelection(opt, returnType, false))
            end,
        })
    end

    -- Auto-refresh on player join/leave
    local joinConn = Players.PlayerAdded:Connect(function()
        subHandle:Refresh(buildOptions())
    end)
    local leaveConn = Players.PlayerRemoving:Connect(function()
        subHandle:Refresh(buildOptions())
    end)
    table.insert(window._cleanup, function()
        joinConn:Disconnect(); leaveConn:Disconnect()
    end)

    function handle:Get()         return currentValue() end
    function handle:GetRaw()      return subHandle:Get() end
    function handle:Set(v)        subHandle:Set(normalizeSetValue(v)) end
    function handle:SetSilent(v)  subHandle:SetSilent(normalizeSetValue(v)) end
    function handle:Refresh()     subHandle:Refresh(buildOptions()) end
    function handle:Destroy()
        joinConn:Disconnect(); leaveConn:Disconnect()
        subHandle:Destroy()
    end

    return handle
end

-- -- Number Input / Stepper --------------------------------------------------

function Section:CreateNumberInput(cfg)
    cfg = cfg or {}
    local window  = self.tab.window
    local theme   = window.theme
    local minVal  = cfg.Min or -math.huge
    local maxVal  = cfg.Max or  math.huge
    local step    = cfg.Increment or 1
    local suffix  = cfg.Suffix or ""
    local value   = cfg.CurrentValue or 0
    local handle  = { Type = "NumberInput", Name = cfg.Name or "Number" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 14),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Number",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local inputRow = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 22),
        Position = UDim2.new(0, 2, 0, 16),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(inputRow, 4); stroke(inputRow, theme.border, 1)

    local decBtn = Create("TextButton", {
        Size = UDim2.fromOffset(22, 22),
        Position = UDim2.fromOffset(0, 0),
        BackgroundColor3 = theme.surfaceHi,
        BorderSizePixel = 0,
        Text = "-",
        TextColor3 = theme.textDim,
        Font = FONT_BOLD,
        TextSize = 14,
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = inputRow,
    })
    corner(decBtn, 4)

    local incBtn = Create("TextButton", {
        Size = UDim2.fromOffset(22, 22),
        Position = UDim2.new(1, -22, 0, 0),
        BackgroundColor3 = theme.surfaceHi,
        BorderSizePixel = 0,
        Text = "+",
        TextColor3 = theme.textDim,
        Font = FONT_BOLD,
        TextSize = 14,
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = inputRow,
    })
    corner(incBtn, 4)

    local textBox = Create("TextBox", {
        Size = UDim2.new(1, -48, 1, 0),
        Position = UDim2.fromOffset(24, 0),
        BackgroundTransparency = 1,
        Text = tostring(value) .. suffix,
        TextColor3 = theme.text,
        Font = FONT_SEMI,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = true,
        ZIndex = 2,
        Parent = inputRow,
    })

    local function snap(v)
        v = math.clamp(v, minVal, maxVal)
        if step > 0 then
            v = math.floor((v - (cfg.Min or 0)) / step + 0.5) * step + (cfg.Min or 0)
            v = math.clamp(v, minVal, maxVal)
        end
        return v
    end

    local function setValue(v, fire)
        v = snap(v)
        if v == value and textBox.Text ~= "" then return end
        value = v
        textBox.Text = tostring(value) .. suffix
        if fire then task.spawn(safeCall, cfg.Callback, value) end
    end
    setValue(value, false)

    decBtn.MouseButton1Click:Connect(function() setValue(value - step, true) end)
    incBtn.MouseButton1Click:Connect(function() setValue(value + step, true) end)

    textBox.FocusLost:Connect(function(enter)
        local n = tonumber(textBox.Text:gsub("[^%d%.-]", ""))
        if n then setValue(n, true)
        else textBox.Text = tostring(value) .. suffix end
    end)

    function handle:Get()         return value end
    function handle:Set(v)        setValue(v, true) end
    function handle:SetSilent(v)  setValue(v, false) end
    function handle:Increment()   setValue(value + step, true) end
    function handle:Decrement()   setValue(value - step, true) end
    function handle:Destroy()     row:Destroy() end

    return handle
end

-- -- Text Input --------------------------------------------------------------

function Section:CreateInput(cfg)
    cfg = cfg or {}
    local window   = self.tab.window
    local theme    = window.theme
    local value    = cfg.CurrentValue or ""
    local handle   = { Type = "Input", Name = cfg.Name or "Input" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 14),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Input",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local box = Create("TextBox", {
        Size = UDim2.new(1, -4, 0, 22),
        Position = UDim2.new(0, 2, 0, 16),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = value,
        PlaceholderText = cfg.Placeholder or "",
        PlaceholderColor3 = theme.muted,
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = row,
    })
    corner(box, 4)
    local boxStroke = stroke(box, theme.border, 1)
    Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box })

    -- Filter non-numeric input when NumbersOnly is set
    if cfg.NumbersOnly then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local cleaned = box.Text:gsub("[^%d%.-]", "")
            if cleaned ~= box.Text then
                local cur = box.CursorPosition
                box.Text = cleaned
                box.CursorPosition = cur - 1
            end
        end)
    end

    box:GetPropertyChangedSignal("Text"):Connect(function()
        value = box.Text
        if cfg.OnChanged then task.spawn(safeCall, cfg.OnChanged, value) end
    end)

    box.FocusLost:Connect(function(enterPressed)
        value = box.Text
        if cfg.OnFocusLost then task.spawn(safeCall, cfg.OnFocusLost, value, enterPressed) end
        if cfg.Callback and (enterPressed or not cfg.OnFocusLost) then
            task.spawn(safeCall, cfg.Callback, value)
        end
        if cfg.ClearOnSubmit and enterPressed then
            box.Text = ""; value = ""
        end
    end)

    -- Focus highlight: reuse the existing UIStroke instead of creating duplicates
    box.Focused:Connect(function()
        if boxStroke and boxStroke.Parent then
            boxStroke.Color = theme.accent
            boxStroke.Thickness = 1.5
        end
    end)
    box.FocusLost:Connect(function()
        if boxStroke and boxStroke.Parent then
            boxStroke.Color = theme.border
            boxStroke.Thickness = 1
        end
    end)

    function handle:Get()                return value end
    function handle:Set(v)               box.Text = tostring(v or ""); value = box.Text end
    function handle:SetSilent(v)         box.Text = tostring(v or ""); value = box.Text end
    function handle:Clear()              box.Text = ""; value = "" end
    function handle:SetPlaceholder(txt)  box.PlaceholderText = txt or "" end
    function handle:Destroy()            row:Destroy() end

    return handle
end

-- -- Color Picker ------------------------------------------------------------

function Section:CreateColorPicker(cfg)
    cfg = cfg or {}
    local window = self.tab.window
    local theme  = window.theme
    local gui    = window.gui

    local currentColor = cfg.CurrentColor or Color3.fromRGB(255, 255, 255)
    local h, s, v = currentColor:ToHSV()
    local handle = { Type = "ColorPicker", Name = cfg.Name or "Color" }

    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    Create("TextLabel", {
        Size = UDim2.new(1, -64, 1, 0),
        Position = UDim2.new(0, 2, 0, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Color",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    local swatch = Create("TextButton", {
        Size = UDim2.fromOffset(56, 18),
        Position = UDim2.new(1, -60, 0.5, -9),
        BackgroundColor3 = currentColor,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    corner(swatch, 3); stroke(swatch, theme.border, 1)

    local popupOpen = false
    local popupBackdrop, svBox, hueBar, svCursor, hueCursor, hexLabel
    local draggingSV, draggingHue = false, false
    local svMoveConn, hueMoveConn, releaseConn

    local function formatHex(c)
        return string.format("#%02X%02X%02X",
            math.floor(c.R * 255 + 0.5),
            math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5))
    end

    local function applyHSV(fire)
        local c = Color3.fromHSV(h, s, v)
        currentColor = c; swatch.BackgroundColor3 = c
        if svBox   then svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1) end
        if svCursor  then svCursor.Position  = UDim2.new(s, -4, 1-v, -4) end
        if hueCursor then hueCursor.Position = UDim2.new(0, -2, h,  -1)  end
        if hexLabel  then hexLabel.Text = formatHex(c) end
        if fire then task.spawn(safeCall, cfg.Callback, c) end
    end

    local function setColor(c, fire)
        if typeof(c) ~= "Color3" then return end
        h, s, v = c:ToHSV(); applyHSV(fire)
    end

    local function closePopup()
        popupOpen = false; draggingSV = false; draggingHue = false
        if svMoveConn  then svMoveConn:Disconnect();  svMoveConn  = nil end
        if hueMoveConn then hueMoveConn:Disconnect(); hueMoveConn = nil end
        if releaseConn then releaseConn:Disconnect(); releaseConn = nil end
        if popupBackdrop then
            popupBackdrop:Destroy(); popupBackdrop = nil
            svBox = nil; hueBar = nil; svCursor = nil; hueCursor = nil; hexLabel = nil
        end
    end

    local function openPopup()
        if popupOpen then return end
        popupOpen = true

        popupBackdrop = Create("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 50,
            Parent = gui,
        })
        popupBackdrop.MouseButton1Click:Connect(closePopup)

        local pW, pH = 192, 160
        local px = swatch.AbsolutePosition.X + swatch.AbsoluteSize.X - pW
        local py = swatch.AbsolutePosition.Y + swatch.AbsoluteSize.Y + 4

        local popupFrame = Create("Frame", {
            Size = UDim2.fromOffset(pW, pH),
            Position = UDim2.fromOffset(px, py),
            BackgroundColor3 = theme.bgAlt,
            BorderSizePixel = 0,
            ZIndex = 51,
            Parent = popupBackdrop,
        })
        corner(popupFrame, 4); stroke(popupFrame, theme.border, 1)
        clampPopupPosition(popupFrame)

        svBox = Create("Frame", {
            Size = UDim2.fromOffset(150, 120),
            Position = UDim2.fromOffset(8, 8),
            BackgroundColor3 = Color3.fromHSV(h, 1, 1),
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 52,
            Parent = popupFrame,
        })
        corner(svBox, 3)

        local function makeGrad(parent, cs, rot)
            local g = Create("UIGradient", { Color = cs, Rotation = rot, Parent = parent })
            return g
        end

        local wOv = Create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 53,
            Parent = svBox,
        })
        corner(wOv, 3)
        makeGrad(wOv, ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
        }), 0)
        wOv.BackgroundTransparency = 0
        Create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = wOv,
        })

        local bOv = Create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            ZIndex = 54,
            Parent = svBox,
        })
        corner(bOv, 3)
        Create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
            Rotation = 90,
            Parent = bOv,
        })

        svCursor = Create("Frame", {
            Size = UDim2.fromOffset(8, 8),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(s, 0, 1-v, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 55,
            Parent = svBox,
        })
        corner(svCursor, 4); stroke(svCursor, Color3.new(0, 0, 0), 1)

        hueBar = Create("Frame", {
            Size = UDim2.fromOffset(16, 120),
            Position = UDim2.fromOffset(166, 8),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 52,
            Parent = popupFrame,
        })
        corner(hueBar, 3)
        Create("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,     Color3.fromRGB(255, 0,   0)),
                ColorSequenceKeypoint.new(0.166, Color3.fromRGB(255, 255, 0)),
                ColorSequenceKeypoint.new(0.333, Color3.fromRGB(0,   255, 0)),
                ColorSequenceKeypoint.new(0.500, Color3.fromRGB(0,   255, 255)),
                ColorSequenceKeypoint.new(0.666, Color3.fromRGB(0,   0,   255)),
                ColorSequenceKeypoint.new(0.833, Color3.fromRGB(255, 0,   255)),
                ColorSequenceKeypoint.new(1.000, Color3.fromRGB(255, 0,   0)),
            }),
            Rotation = 90,
            Parent = hueBar,
        })

        hueCursor = Create("Frame", {
            Size = UDim2.new(1, 4, 0, 2),
            Position = UDim2.new(0, -2, h, -1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 53,
            Parent = hueBar,
        })
        stroke(hueCursor, Color3.new(0, 0, 0), 1)

        hexLabel = Create("TextLabel", {
            Size = UDim2.new(1, -16, 0, 16),
            Position = UDim2.fromOffset(8, 136),
            BackgroundTransparency = 1,
            Text = formatHex(currentColor),
            TextColor3 = theme.textDim,
            Font = FONT_SEMI,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 52,
            Parent = popupFrame,
        })

        local function updateSV(input)
            local rx = input.Position.X - svBox.AbsolutePosition.X
            local ry = input.Position.Y - svBox.AbsolutePosition.Y
            s = math.clamp(rx / math.max(svBox.AbsoluteSize.X, 1), 0, 1)
            v = 1 - math.clamp(ry / math.max(svBox.AbsoluteSize.Y, 1), 0, 1)
            applyHSV(true)
        end

        local function updateHue(input)
            local ry = input.Position.Y - hueBar.AbsolutePosition.Y
            h = math.clamp(ry / math.max(hueBar.AbsoluteSize.Y, 1), 0, 1)
            applyHSV(true)
        end

        svBox.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                draggingSV = true; updateSV(input)
            end
        end)
        hueBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                draggingHue = true; updateHue(input)
            end
        end)

        svMoveConn = UIS.InputChanged:Connect(function(input)
            if draggingSV and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                updateSV(input)
            end
        end)
        hueMoveConn = UIS.InputChanged:Connect(function(input)
            if draggingHue and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                updateHue(input)
            end
        end)
        releaseConn = UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                draggingSV = false; draggingHue = false
            end
        end)
    end

    swatch.MouseButton1Click:Connect(function()
        if popupOpen then closePopup() else openPopup() end
    end)
    table.insert(window._cleanup, closePopup)

    function handle:Get()        return currentColor end
    function handle:Set(c)       setColor(c, true) end
    function handle:SetSilent(c) setColor(c, false) end
    function handle:Destroy()    closePopup(); row:Destroy() end

    return handle
end

-- -- Button (with state machine) ---------------------------------------------

function Section:CreateButton(cfg)
    cfg = cfg or {}
    local theme    = self.tab.window.theme
    local handle   = { Type = "Button", Name = cfg.Name or "Button" }
    local baseName = cfg.Name or "Button"
    local disabled = false
    local loading  = false
    local resetTask = nil

    local btn = Create("TextButton", {
        Size = UDim2.new(1, -4, 0, 26),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = baseName,
        TextColor3 = theme.text,
        Font = FONT_SEMI,
        TextSize = 12,
        AutoButtonColor = false,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    corner(btn, 4); stroke(btn, theme.border, 1)

    local function resetToBase()
        btn.Text = baseName
        btn.BackgroundColor3 = theme.surface
        btn.TextColor3 = theme.text
        stroke(btn, theme.border, 1)
        disabled = false; loading = false
    end

    local armedForConfirm = false
    local armedUntil = 0
    local confirmTimeout = cfg.ConfirmTimeout or 0.5

    btn.MouseEnter:Connect(function()
        if not disabled and not loading then btn.BackgroundColor3 = theme.surfaceHi end
    end)
    btn.MouseLeave:Connect(function()
        if not disabled and not loading and not armedForConfirm then
            btn.BackgroundColor3 = theme.surface
        end
    end)

    btn.MouseButton1Click:Connect(function()
        if disabled or loading then return end
        if cfg.Confirm then
            if armedForConfirm and tick() < armedUntil then
                armedForConfirm = false
                btn.Text = baseName
                btn.BackgroundColor3 = theme.surface
                task.spawn(safeCall, cfg.Callback)
                return
            end
            armedForConfirm = true
            armedUntil = tick() + confirmTimeout
            btn.Text = "! Confirm?"
            btn.BackgroundColor3 = theme.danger
            btn.TextColor3 = Color3.new(1, 1, 1)
            task.delay(confirmTimeout, function()
                if armedForConfirm and tick() >= armedUntil then
                    armedForConfirm = false
                    btn.Text = baseName
                    btn.BackgroundColor3 = theme.surface
                    btn.TextColor3 = theme.text
                end
            end)
            return
        end
        task.spawn(safeCall, cfg.Callback)
    end)

    function handle:SetText(text)
        baseName = text
        if not disabled and not loading and not armedForConfirm then
            btn.Text = text
        end
    end

    function handle:SetDisabled(v)
        disabled = v == true
        btn.BackgroundColor3 = disabled and theme.disabled or theme.surface
        btn.TextColor3 = disabled and theme.muted or theme.text
        btn.Active = not disabled
    end

    function handle:SetLoading(v, text)
        loading = v == true
        if loading then
            btn.Text = text or "... Loading"
            btn.BackgroundColor3 = theme.bgAlt
            btn.TextColor3 = theme.muted
            disabled = true
        else
            resetToBase()
        end
    end

    function handle:SetSuccess(text, duration)
        if resetTask then task.cancel(resetTask) end
        btn.Text = "OK " .. (text or "Success")
        btn.BackgroundColor3 = theme.success
        btn.TextColor3 = Color3.new(1, 1, 1)
        disabled = false; loading = false
        resetTask = task.delay(duration or 2, resetToBase)
    end

    function handle:SetError(text, duration)
        if resetTask then task.cancel(resetTask) end
        btn.Text = "X " .. (text or "Error")
        btn.BackgroundColor3 = theme.danger
        btn.TextColor3 = Color3.new(1, 1, 1)
        disabled = false; loading = false
        resetTask = task.delay(duration or 2, resetToBase)
    end

    function handle:Destroy() btn:Destroy() end

    return handle
end

-- -- Label -------------------------------------------------------------------

function Section:CreateLabel(cfg)
    cfg = cfg or {}
    local theme = self.tab.window.theme
    local lbl = Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 16),
        BackgroundTransparency = 1,
        Text = cfg.Text or "",
        TextColor3 = cfg.Color or theme.textDim,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = false,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    local handle = { Type = "Label" }
    function handle:SetText(t)  lbl.Text = t end
    function handle:SetColor(c) lbl.TextColor3 = c end
    function handle:Destroy()   lbl:Destroy() end
    return handle
end

-- -- Paragraph ---------------------------------------------------------------

function Section:CreateParagraph(cfg)
    cfg = cfg or {}
    local theme = self.tab.window.theme
    local container = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    corner(container, 5); stroke(container, theme.border, 1)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        Parent = container,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = container,
    })
    local title = Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Text = cfg.Title or "",
        TextColor3 = theme.accent,
        Font = FONT_BOLD,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        Parent = container,
    })
    local body = Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = cfg.Content or "",
        TextColor3 = theme.text,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        LayoutOrder = 2,
        Parent = container,
    })
    local handle = { Type = "Paragraph" }
    function handle:SetTitle(t)   title.Text = t end
    function handle:SetContent(c) body.Text  = c end
    function handle:Destroy()     container:Destroy() end
    return handle
end

-- -- Status / Result display -------------------------------------------------

function Section:CreateStatus(cfg)
    cfg = cfg or {}
    local theme  = self.tab.window.theme
    local state  = cfg.State or "info"
    local handle = { Type = "Status" }

    local container = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    corner(container, 5)

    local stripe = Create("Frame", {
        Size = UDim2.fromOffset(3, 0),
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = stateColor(theme, state),
        BorderSizePixel = 0,
        Parent = container,
    })
    -- stripe height will auto-match container via UIListLayout + padding below
    Create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = stripe })

    local inner = Create("Frame", {
        Size = UDim2.new(1, -7, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(7, 0),
        BackgroundTransparency = 1,
        Parent = container,
    })
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        Parent = inner,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = inner,
    })

    local titleRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = inner,
    })
    local iconLbl = Create("TextLabel", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        Text = stateIcon(state),
        TextColor3 = stateColor(theme, state),
        Font = FONT_BOLD,
        TextSize = 12,
        Parent = titleRow,
    })
    local titleLbl = Create("TextLabel", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(16, 0),
        BackgroundTransparency = 1,
        Text = cfg.Title or "",
        TextColor3 = stateColor(theme, state),
        Font = FONT_BOLD,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleRow,
    })

    local bodyLbl
    if cfg.Text and cfg.Text ~= "" then
        bodyLbl = Create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = cfg.Text,
            TextColor3 = theme.text,
            Font = FONT,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            LayoutOrder = 2,
            Parent = inner,
        })
    end

    local function applyState(newState)
        state = newState
        local c = stateColor(theme, state)
        stripe.BackgroundColor3 = c
        iconLbl.Text = stateIcon(state)
        iconLbl.TextColor3 = c
        titleLbl.TextColor3 = c
    end

    function handle:SetText(text)
        if not bodyLbl then
            bodyLbl = Create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Text = text,
                TextColor3 = theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextWrapped = true,
                LayoutOrder = 2,
                Parent = inner,
            })
        else
            bodyLbl.Text = text
        end
    end
    function handle:SetState(s)      applyState(s) end
    function handle:Set(title, text, s)
        titleLbl.Text = title or ""
        handle:SetText(text or "")
        if s then applyState(s) end
    end
    function handle:Clear()
        titleLbl.Text = ""
        if bodyLbl then bodyLbl.Text = "" end
    end
    function handle:Destroy() container:Destroy() end

    return handle
end

-- -- Data List ---------------------------------------------------------------

function Section:CreateList(cfg)
    cfg = cfg or {}
    local theme  = self.tab.window.theme
    local items  = cfg.Items or {}
    local handle = { Type = "List" }

    local header = Create("TextLabel", {
        Size = UDim2.new(1, -4, 0, 14),
        BackgroundTransparency = 1,
        Text = cfg.Name or "",
        TextColor3 = theme.textDim,
        Font = FONT_SEMI,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })

    local outer = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    corner(outer, 5); stroke(outer, theme.border, 1)

    local scroll = Create("ScrollingFrame", {
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        MaxSize = Vector2.new(math.huge, 160),
        Position = UDim2.fromOffset(2, 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme.border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = outer,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
        Parent = scroll,
    })

    local emptyLbl = Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Text = cfg.EmptyText or "No items",
        TextColor3 = theme.muted,
        Font = FONT,
        TextSize = 11,
        Visible = #items == 0,
        LayoutOrder = 0,
        Parent = scroll,
    })

    local rowOrder = 0
    local rowInstances = {}

    local function addRowUI(item, order)
        rowOrder = rowOrder + 1
        local lo = order or rowOrder
        local icon   = type(item) == "table" and item.Icon    or nil
        local text   = type(item) == "table" and (item.Name or item.Text or tostring(item)) or tostring(item)
        local subtext = type(item) == "table" and item.SubText or nil
        local color  = type(item) == "table" and item.Color   or nil

        local rowH = subtext and 36 or 24
        local rowBtn = Create("TextButton", {
            Size = UDim2.new(1, 0, 0, rowH),
            BackgroundColor3 = theme.bgAlt,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = lo,
            Parent = scroll,
        })
        corner(rowBtn, 3)
        rowBtn.MouseEnter:Connect(function() rowBtn.BackgroundColor3 = theme.surfaceHi end)
        rowBtn.MouseLeave:Connect(function() rowBtn.BackgroundColor3 = theme.bgAlt end)

        if icon then
            Create("TextLabel", {
                Size = UDim2.fromOffset(20, rowH),
                BackgroundTransparency = 1,
                Text = icon,
                TextColor3 = color or theme.accent,
                Font = FONT_SEMI,
                TextSize = 13,
                Parent = rowBtn,
            })
        end

        local textX = icon and 24 or 8
        Create("TextLabel", {
            Size = UDim2.new(1, -(textX + 4), 0, 16),
            Position = UDim2.fromOffset(textX, subtext and 4 or (rowH/2 - 6)),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = color or theme.text,
            Font = FONT_SEMI,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = rowBtn,
        })
        if subtext then
            Create("TextLabel", {
                Size = UDim2.new(1, -(textX + 4), 0, 12),
                Position = UDim2.fromOffset(textX, 20),
                BackgroundTransparency = 1,
                Text = subtext,
                TextColor3 = theme.muted,
                Font = FONT,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = rowBtn,
            })
        end

        if cfg.Callback then
            rowBtn.MouseButton1Click:Connect(function()
                task.spawn(safeCall, cfg.Callback, item)
            end)
        end

        return rowBtn
    end

    local function refreshEmpty()
        emptyLbl.Visible = #rowInstances == 0
    end

    for _, item in ipairs(items) do
        table.insert(rowInstances, addRowUI(item))
    end
    refreshEmpty()

    function handle:SetItems(newItems)
        for _, r in ipairs(rowInstances) do r:Destroy() end
        rowInstances = {}; rowOrder = 0
        items = newItems or {}
        for _, item in ipairs(items) do
            table.insert(rowInstances, addRowUI(item))
        end
        refreshEmpty()
    end

    function handle:AddItem(item)
        table.insert(items, item)
        table.insert(rowInstances, addRowUI(item))
        refreshEmpty()
    end

    function handle:RemoveItem(pred)
        if type(pred) == "number" then
            if rowInstances[pred] then
                rowInstances[pred]:Destroy()
                table.remove(rowInstances, pred)
                table.remove(items, pred)
            end
        elseif type(pred) == "function" then
            for i = #items, 1, -1 do
                if pred(items[i]) then
                    if rowInstances[i] then rowInstances[i]:Destroy() end
                    table.remove(rowInstances, i)
                    table.remove(items, i)
                end
            end
        end
        refreshEmpty()
    end

    function handle:Clear()
        for _, r in ipairs(rowInstances) do r:Destroy() end
        rowInstances = {}; items = {}; rowOrder = 0
        refreshEmpty()
    end

    function handle:Destroy() outer:Destroy(); header:Destroy() end

    return handle
end

-- -- Separator ---------------------------------------------------------------

function Section:CreateSeparator()
    local theme = self.tab.window.theme
    local sep = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = theme.border,
        BorderSizePixel = 0,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    return { Type = "Separator", Destroy = function() sep:Destroy() end }
end

-- -- Log Viewer --------------------------------------------------------------

function Section:CreateLogViewer(cfg)
    cfg = cfg or {}
    local theme   = self.tab.window.theme
    local maxEntries = cfg.MaxEntries or 200
    local handle  = { Type = "LogViewer" }
    local entries = {}

    local header = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 22),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -44, 1, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Logs",
        TextColor3 = theme.textDim,
        Font = FONT_SEMI,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })
    local clearBtn = Create("TextButton", {
        Size = UDim2.fromOffset(40, 18),
        Position = UDim2.new(1, -42, 0.5, -9),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = "Clear",
        TextColor3 = theme.muted,
        Font = FONT,
        TextSize = 10,
        AutoButtonColor = false,
        Parent = header,
    })
    corner(clearBtn, 3)

    local outer = Create("Frame", {
        Size = UDim2.new(1, -4, 0, cfg.Height or 140),
        BackgroundColor3 = theme.bgAlt,
        BorderSizePixel = 0,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    corner(outer, 5); stroke(outer, theme.border, 1)

    local scroll = Create("ScrollingFrame", {
        Size = UDim2.new(1, -6, 1, -6),
        Position = UDim2.fromOffset(3, 3),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme.border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = outer,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
        Parent = scroll,
    })

    local logOrder = 0

    local function addEntry(entry, noScroll)
        logOrder = logOrder + 1
        local ts  = entry.Timestamp or os.date("%H:%M:%S")
        local msg = entry.Text or entry.Message or ""
        local lvl = entry.Type or entry.Level or "info"
        local player = entry.Player or ""

        local color = stateColor(theme, lvl == "warn" and "warning" or lvl)

        local row = Create("Frame", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            LayoutOrder = logOrder,
            Parent = scroll,
        })

        Create("TextLabel", {
            Size = UDim2.fromOffset(52, 18),
            BackgroundTransparency = 1,
            Text = ts,
            TextColor3 = theme.muted,
            Font = FONT,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        local textX = 56
        if player ~= "" then
            Create("TextLabel", {
                Size = UDim2.fromOffset(70, 18),
                Position = UDim2.fromOffset(54, 0),
                BackgroundTransparency = 1,
                Text = "[" .. player .. "]",
                TextColor3 = theme.textDim,
                Font = FONT_SEMI,
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })
            textX = 128
        end
        Create("TextLabel", {
            Size = UDim2.new(1, -(textX + 2), 1, 0),
            Position = UDim2.fromOffset(textX, 0),
            BackgroundTransparency = 1,
            Text = msg,
            TextColor3 = color,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
        })

        table.insert(entries, { ui = row, data = entry })

        -- Trim excess
        while #entries > maxEntries do
            entries[1].ui:Destroy()
            table.remove(entries, 1)
        end

        -- Auto-scroll to bottom
        if not noScroll then
            task.defer(function()
                if scroll and scroll.Parent then
                    scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
                end
            end)
        end
    end

    clearBtn.MouseButton1Click:Connect(function()
        for _, e in ipairs(entries) do e.ui:Destroy() end
        entries = {}; logOrder = 0
    end)

    if cfg.Items then
        for _, item in ipairs(cfg.Items) do addEntry(item, true) end
    end

    function handle:Append(entry)
        if type(entry) == "string" then entry = { Text = entry } end
        entry.Timestamp = entry.Timestamp or os.date("%H:%M:%S")
        addEntry(entry)
    end
    function handle:Clear()
        for _, e in ipairs(entries) do e.ui:Destroy() end
        entries = {}; logOrder = 0
    end
    function handle:Destroy() outer:Destroy(); header:Destroy() end

    return handle
end

-- -- Command Form ------------------------------------------------------------
-- The centrepiece admin-panel abstraction: declare a command with typed
-- fields and get a complete form with loading/success/error feedback.

function Section:CreateCommand(cfg)
    cfg = cfg or {}
    local window = self.tab.window
    local theme  = window.theme
    local handle = { Type = "Command" }

    -- Card wrapper
    local card = Create("Frame", {
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        LayoutOrder = self:_next(),
        Parent = self.container,
    })
    corner(card, 6); stroke(card, theme.border, 1)

    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        Parent = card,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = card,
    })

    -- Header
    local headerRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    Create("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = cfg.Name or "Command",
        TextColor3 = theme.accent,
        Font = FONT_BOLD,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = headerRow,
    })

    if cfg.Description and cfg.Description ~= "" then
        Create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = cfg.Description,
            TextColor3 = theme.muted,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 2,
            Parent = card,
        })
    end

    -- Build a mini-section proxy so field constructors target the card
    local fieldOrder = 3
    local function nextFieldOrder()
        fieldOrder = fieldOrder + 1
        return fieldOrder
    end

    -- We'll collect field value getters here
    local fieldGetters = {}
    local fieldMeta = {}

    local proxySection = {
        tab = self.tab,
        container = card,
        _next = function()
            return nextFieldOrder()
        end,
    }

    local function displayFieldName(field, key, label)
        return label .. (field.Required and "  *" or "")
    end

    local function registerField(key, field, label, ftype, getter)
        if key == "" then return end
        fieldGetters[key] = getter
        fieldMeta[key] = {
            Field = field,
            Label = label,
            Type = ftype,
        }
    end

    local function isEmptyValue(value)
        if value == nil then return true end
        if type(value) == "string" then return value:gsub("%s+", "") == "" end
        if type(value) == "table" then return next(value) == nil end
        return false
    end

    local fields = cfg.Fields or {}
    for _, field in ipairs(fields) do
        local key  = field.Key  or field.Name or ""
        local ftype = field.Type or "text"
        local normalizedType = tostring(ftype):lower()
        local label = field.Label or field.Key or field.Name or key

        -- Create a proxy row-group (not a real Section, just parent + order)
        local function makeFieldLabel()
            if label ~= "" then
                Create("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 12),
                    BackgroundTransparency = 1,
                    Text = displayFieldName(field, key, label),
                    TextColor3 = field.Required and theme.text or theme.textDim,
                    Font = FONT,
                    TextSize = 10,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = nextFieldOrder(),
                    Parent = card,
                })
            end
        end

        if normalizedType == "text" or normalizedType == "textarea" or normalizedType == "userid" then
            makeFieldLabel()
            local isArea = (normalizedType == "textarea")
            local isNum = (normalizedType == "userid")
            local box = Create("TextBox", {
                Size = UDim2.new(1, 0, 0, isArea and 60 or 22),
                BackgroundColor3 = theme.bgAlt,
                BorderSizePixel = 0,
                Text = field.Default or "",
                PlaceholderText = field.Placeholder or "",
                PlaceholderColor3 = theme.muted,
                TextColor3 = theme.text,
                Font = FONT,
                TextSize = 11,
                ClearTextOnFocus = false,
                TextWrapped = isArea,
                MultiLine = isArea,
                TextYAlignment = isArea and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
                LayoutOrder = nextFieldOrder(),
                Parent = card,
            })
            corner(box, 3)
            local boxStr = stroke(box, theme.border, 1)
            Create("UIPadding", { 
                PaddingTop = isArea and UDim.new(0, 6) or UDim.new(0, 0),
                PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = box 
            })
            table.insert(window._connections, box.Focused:Connect(function()
                if boxStr and boxStr.Parent then boxStr.Color = theme.accent; boxStr.Thickness = 1.5 end
            end))
            table.insert(window._connections, box.FocusLost:Connect(function()
                if boxStr and boxStr.Parent then boxStr.Color = theme.border; boxStr.Thickness = 1 end
                if isNum then
                    box.Text = tostring(tonumber(box.Text) or box.Text)
                end
            end))
            fieldGetters[key] = {
                field = field,
                get = function() 
                    if isNum then return tonumber(box.Text) end
                    return box.Text 
                end
            }

        elseif normalizedType == "number" then
            makeFieldLabel()
            local nRow = Create("Frame", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = theme.bgAlt,
                BorderSizePixel = 0,
                LayoutOrder = nextFieldOrder(),
                Parent = card,
            })
            corner(nRow, 3); stroke(nRow, theme.border, 1)
            local decB = Create("TextButton", {
                Size = UDim2.fromOffset(20, 22),
                BackgroundColor3 = theme.surfaceHi,
                BorderSizePixel = 0,
                Text = "-",
                TextColor3 = theme.textDim,
                Font = FONT_BOLD,
                TextSize = 13,
                AutoButtonColor = false,
                ZIndex = 2,
                Parent = nRow,
            })
            corner(decB, 3)
            local incB = Create("TextButton", {
                Size = UDim2.fromOffset(20, 22),
                Position = UDim2.new(1, -20, 0, 0),
                BackgroundColor3 = theme.surfaceHi,
                BorderSizePixel = 0,
                Text = "+",
                TextColor3 = theme.textDim,
                Font = FONT_BOLD,
                TextSize = 13,
                AutoButtonColor = false,
                ZIndex = 2,
                Parent = nRow,
            })
            corner(incB, 3)
            local nBox = Create("TextBox", {
                Size = UDim2.new(1, -44, 1, 0),
                Position = UDim2.fromOffset(22, 0),
                BackgroundTransparency = 1,
                Text = tostring(field.Default or 0),
                TextColor3 = theme.text,
                Font = FONT_SEMI,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Center,
                ClearTextOnFocus = true,
                ZIndex = 2,
                Parent = nRow,
            })
            local step = tonumber(field.Increment) or 1
            local nVal = tonumber(field.Default) or 0
            local minNumber = tonumber(field.Min)
            local maxNumber = tonumber(field.Max)
            local function setN(v)
                nVal = tonumber(v) or nVal or 0
                if minNumber then nVal = math.max(nVal, minNumber) end
                if maxNumber then nVal = math.min(nVal, maxNumber) end
                nBox.Text = tostring(nVal)
            end
            table.insert(window._connections, decB.MouseButton1Click:Connect(function() setN(nVal - step) end))
            table.insert(window._connections, incB.MouseButton1Click:Connect(function() setN(nVal + step) end))
            table.insert(window._connections, nBox.FocusLost:Connect(function()
                local n = tonumber(nBox.Text)
                if n then setN(n) else nBox.Text = tostring(nVal) end
            end))
            fieldGetters[key] = { field = field, get = function() return nVal end }

        elseif normalizedType == "toggle" then
            local togVal = field.Default == true
            local togRow = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                LayoutOrder = nextFieldOrder(),
                Parent = card,
            })
            local togBox = Create("Frame", {
                Size = UDim2.fromOffset(13, 13),
                Position = UDim2.new(0, 0, 0.5, -6),
                BackgroundColor3 = togVal and theme.accent or theme.surface,
                BorderSizePixel = 0,
                Parent = togRow,
            })
            corner(togBox, 3); stroke(togBox, theme.border, 1)
            local togCheck = Create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "OK",
                TextColor3 = Color3.new(1, 1, 1),
                Font = FONT_BOLD,
                TextSize = 10,
                Visible = togVal,
                Parent = togBox,
            })
            Create("TextLabel", {
                Size = UDim2.new(1, -20, 1, 0),
                Position = UDim2.fromOffset(18, 0),
                BackgroundTransparency = 1,
                Text = label,
                TextColor3 = theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = togRow,
            })
            table.insert(window._connections, togRow.MouseButton1Click:Connect(function()
                togVal = not togVal
                togBox.BackgroundColor3 = togVal and theme.accent or theme.surface
                togCheck.Visible = togVal
            end))
            fieldGetters[key] = { field = field, get = function() return togVal end }

        elseif normalizedType == "player" or normalizedType == "players" then
            makeFieldLabel()
            local isMulti = (normalizedType == "players")
            local returnType = normalizeReturnType(field.ReturnType) -- name, userid, player
            local selectedMap = {}
            if field.Default then
                if type(field.Default) == "table" then
                    for _, v in ipairs(field.Default) do selectedMap[playerNameFromValue(v)] = true end
                else
                    selectedMap[playerNameFromValue(field.Default)] = true
                end
            end
            local function getSelected()
                local t = {}
                for k in pairs(selectedMap) do table.insert(t, k) end
                return t
            end
            local pBtn = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = theme.bgAlt,
                BorderSizePixel = 0,
                Text = "",
                TextColor3 = theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                AutoButtonColor = false,
                LayoutOrder = nextFieldOrder(),
                Parent = card,
            })
            corner(pBtn, 3); stroke(pBtn, theme.border, 1)
            local function rebuildLabel()
                local sel = getSelected()
                if #sel == 0 then
                    pBtn.Text = " " .. (field.Placeholder or "Select player" .. (isMulti and "s..." or "...")) .. "   v"
                    pBtn.TextColor3 = theme.muted
                else
                    pBtn.Text = " " .. table.concat(sel, ", ") .. "   v"
                    pBtn.TextColor3 = theme.text
                end
            end
            rebuildLabel()
            
            local pOpen = false
            local pBackdrop
            local pConns = {}
            local function closePPopup()
                pOpen = false
                if pBackdrop then pBackdrop:Destroy(); pBackdrop = nil end
                for _, c in ipairs(pConns) do c:Disconnect() end
                table.clear(pConns)
            end
            
            table.insert(window._connections, pBtn.MouseButton1Click:Connect(function()
                if pOpen then closePPopup(); return end
                pOpen = true
                pBackdrop = Create("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 60, Parent = window.gui })
                table.insert(pConns, pBackdrop.MouseButton1Click:Connect(closePPopup))
                
                local opts = {}
                if field.AllowAll then table.insert(opts, "All") end
                for _, p in ipairs(Players:GetPlayers()) do
                    if field.AllowSelf == false and p == Players.LocalPlayer then continue end
                    table.insert(opts, p.Name)
                end
                
                local ph = math.min(#opts, 6) * 22 + 34
                local pf = Create("Frame", { Size = UDim2.fromOffset(pBtn.AbsoluteSize.X, ph), Position = UDim2.fromOffset(pBtn.AbsolutePosition.X, pBtn.AbsolutePosition.Y + pBtn.AbsoluteSize.Y + 2), BackgroundColor3 = theme.bgAlt, BorderSizePixel = 0, ZIndex = 61, Parent = pBackdrop })
                corner(pf, 4); stroke(pf, theme.border, 1); clampPopupPosition(pf)
                
                local searchBox = Create("TextBox", { Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 3), BackgroundColor3 = theme.surface, BorderSizePixel = 0, Text = "", PlaceholderText = "Search...", PlaceholderColor3 = theme.muted, TextColor3 = theme.text, Font = FONT, TextSize = 11, ZIndex = 62, Parent = pf })
                corner(searchBox, 3); stroke(searchBox, theme.border, 1)
                
                local sc = Create("ScrollingFrame", { Size = UDim2.new(1, -4, 1, -32), Position = UDim2.fromOffset(2, 30), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 62, Parent = pf })
                Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = sc })
                
                local function rebuildList(query)
                    for _, c in ipairs(sc:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
                    local q = query and query:lower() or ""
                    local filtered = {}
                    for _, o in ipairs(opts) do
                        if q == "" or o:lower():find(q, 1, true) then table.insert(filtered, o) end
                    end
                    for i, o in ipairs(filtered) do
                        local isOn = selectedMap[o] == true
                        local ob = Create("TextButton", { Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = isOn and theme.surfaceHi or theme.surface, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 63, Parent = sc })
                        corner(ob, 3)
                        
                        if isMulti then
                            local chk = Create("Frame", { Size = UDim2.fromOffset(12, 12), Position = UDim2.new(0, 5, 0.5, -6), BackgroundColor3 = isOn and theme.accent or theme.surface, BorderSizePixel = 0, ZIndex = 64, Parent = ob })
                            corner(chk, 2); stroke(chk, theme.border, 1)
                            Create("TextLabel", { Size = UDim2.fromScale(1,1), BackgroundTransparency=1, Text="OK", TextColor3=Color3.new(1,1,1), Font=FONT_BOLD, TextSize=9, Visible=isOn, ZIndex=65, Parent=chk })
                            Create("TextLabel", { Size=UDim2.new(1,-22,1,0), Position=UDim2.fromOffset(22,0), BackgroundTransparency=1, Text=o, TextColor3=isOn and theme.accent or theme.text, Font=FONT, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=64, Parent=ob })
                            
                            table.insert(pConns, ob.MouseButton1Click:Connect(function()
                                local nowOn = not selectedMap[o]
                                if nowOn and field.MaxSelected and #getSelected() >= field.MaxSelected then return end
                                selectedMap[o] = nowOn or nil
                                chk.BackgroundColor3 = nowOn and theme.accent or theme.surface
                                chk:FindFirstChildWhichIsA("TextLabel").Visible = nowOn
                                ob.BackgroundColor3 = nowOn and theme.surfaceHi or theme.surface
                                ob:FindFirstChildWhichIsA("TextLabel").TextColor3 = nowOn and theme.accent or theme.text
                                rebuildLabel()
                            end))
                        else
                            ob.Text = " " .. o; ob.TextColor3 = isOn and theme.accent or theme.text; ob.TextXAlignment = Enum.TextXAlignment.Left; ob.TextTruncate = Enum.TextTruncate.AtEnd
                            table.insert(pConns, ob.MouseButton1Click:Connect(function()
                                for k in pairs(selectedMap) do selectedMap[k] = nil end
                                selectedMap[o] = true
                                rebuildLabel(); closePPopup()
                            end))
                        end
                    end
                end
                table.insert(pConns, searchBox:GetPropertyChangedSignal("Text"):Connect(function() rebuildList(searchBox.Text) end))
                rebuildList()
            end))
            
            fieldGetters[key] = {
                field = field,
                get = function()
                    local sel = getSelected()
                    local res = {}
                    for _, name in ipairs(sel) do
                        if name == "All" then
                            table.insert(res, "All")
                        else
                            local p = Players:FindFirstChild(name)
                            if p then
                                if returnType == "userid" then table.insert(res, p.UserId)
                                elseif returnType == "player" then table.insert(res, p)
                                else table.insert(res, p.Name) end
                            end
                        end
                    end
                    if not isMulti then return res[1] end
                    return res
                end
            }

        elseif normalizedType == "dropdown" or normalizedType == "searchdropdown" or normalizedType == "multidropdown" then
            makeFieldLabel()
            local isMulti = (normalizedType == "multidropdown")
            local isSearch = (normalizedType == "searchdropdown") or field.Search
            local selectedMap = {}
            if field.Default then
                if type(field.Default) == "table" then
                    for _, v in ipairs(field.Default) do selectedMap[v] = true end
                else
                    selectedMap[field.Default] = true
                end
            elseif not isMulti and field.Options and field.Options[1] then
                selectedMap[field.Options[1]] = true
            end
            
            local function getSelected()
                local t = {}
                for k in pairs(selectedMap) do table.insert(t, k) end
                return t
            end
            
            local ddBtn = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = theme.bgAlt,
                BorderSizePixel = 0,
                Text = "",
                TextColor3 = theme.text,
                Font = FONT,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                AutoButtonColor = false,
                LayoutOrder = nextFieldOrder(),
                Parent = card,
            })
            corner(ddBtn, 3); stroke(ddBtn, theme.border, 1)
            
            local function rebuildLabel()
                local sel = getSelected()
                if #sel == 0 then
                    ddBtn.Text = " " .. (field.Placeholder or "Select...") .. "   v"
                    ddBtn.TextColor3 = theme.muted
                else
                    local displays = {}
                    for _, v in ipairs(sel) do
                        table.insert(displays, field.FormatOption and field.FormatOption(v) or tostring(v))
                    end
                    ddBtn.Text = " " .. table.concat(displays, ", ") .. "   v"
                    ddBtn.TextColor3 = theme.text
                end
            end
            rebuildLabel()
            
            local ddOpen = false
            local ddBackdrop
            local ddConns = {}
            local function closeDd()
                ddOpen = false
                if ddBackdrop then ddBackdrop:Destroy(); ddBackdrop = nil end
                for _, c in ipairs(ddConns) do c:Disconnect() end
                table.clear(ddConns)
            end
            
            table.insert(window._connections, ddBtn.MouseButton1Click:Connect(function()
                if ddOpen then closeDd(); return end
                ddOpen = true
                ddBackdrop = Create("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 60, Parent = window.gui })
                table.insert(ddConns, ddBackdrop.MouseButton1Click:Connect(closeDd))
                
                local opts = field.Options or {}
                local ph = math.min(#opts, 6) * 22 + (isSearch and 34 or 4)
                local pf = Create("Frame", { Size = UDim2.fromOffset(ddBtn.AbsoluteSize.X, ph), Position = UDim2.fromOffset(ddBtn.AbsolutePosition.X, ddBtn.AbsolutePosition.Y + ddBtn.AbsoluteSize.Y + 2), BackgroundColor3 = theme.bgAlt, BorderSizePixel = 0, ZIndex = 61, Parent = ddBackdrop })
                corner(pf, 4); stroke(pf, theme.border, 1); clampPopupPosition(pf)
                
                local searchBox
                if isSearch then
                    searchBox = Create("TextBox", { Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 3), BackgroundColor3 = theme.surface, BorderSizePixel = 0, Text = "", PlaceholderText = field.SearchPlaceholder or "Search...", PlaceholderColor3 = theme.muted, TextColor3 = theme.text, Font = FONT, TextSize = 11, ZIndex = 62, Parent = pf })
                    corner(searchBox, 3); stroke(searchBox, theme.border, 1)
                end
                
                local sc = Create("ScrollingFrame", { Size = UDim2.new(1, -4, 1, isSearch and -32 or -4), Position = UDim2.fromOffset(2, isSearch and 30 or 2), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 62, Parent = pf })
                Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = sc })
                
                local function rebuildList(query)
                    for _, c in ipairs(sc:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
                    local q = query and query:lower() or ""
                    local filtered = {}
                    for _, o in ipairs(opts) do
                        local disp = field.FormatOption and field.FormatOption(o) or tostring(o)
                        if q == "" or disp:lower():find(q, 1, true) then table.insert(filtered, { val = o, disp = disp }) end
                    end
                    for i, item in ipairs(filtered) do
                        local isOn = selectedMap[item.val] == true
                        local ob = Create("TextButton", { Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = isOn and theme.surfaceHi or theme.surface, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 63, Parent = sc })
                        corner(ob, 3)
                        
                        if isMulti then
                            local chk = Create("Frame", { Size = UDim2.fromOffset(12, 12), Position = UDim2.new(0, 5, 0.5, -6), BackgroundColor3 = isOn and theme.accent or theme.surface, BorderSizePixel = 0, ZIndex = 64, Parent = ob })
                            corner(chk, 2); stroke(chk, theme.border, 1)
                            Create("TextLabel", { Size = UDim2.fromScale(1,1), BackgroundTransparency=1, Text="OK", TextColor3=Color3.new(1,1,1), Font=FONT_BOLD, TextSize=9, Visible=isOn, ZIndex=65, Parent=chk })
                            Create("TextLabel", { Size=UDim2.new(1,-22,1,0), Position=UDim2.fromOffset(22,0), BackgroundTransparency=1, Text=item.disp, TextColor3=isOn and theme.accent or theme.text, Font=FONT, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=64, Parent=ob })
                            
                            table.insert(ddConns, ob.MouseButton1Click:Connect(function()
                                local nowOn = not selectedMap[item.val]
                                if nowOn and field.MaxSelected and #getSelected() >= field.MaxSelected then return end
                                selectedMap[item.val] = nowOn or nil
                                chk.BackgroundColor3 = nowOn and theme.accent or theme.surface
                                chk:FindFirstChildWhichIsA("TextLabel").Visible = nowOn
                                ob.BackgroundColor3 = nowOn and theme.surfaceHi or theme.surface
                                ob:FindFirstChildWhichIsA("TextLabel").TextColor3 = nowOn and theme.accent or theme.text
                                rebuildLabel()
                            end))
                        else
                            ob.Text = " " .. item.disp; ob.TextColor3 = isOn and theme.accent or theme.text; ob.TextXAlignment = Enum.TextXAlignment.Left; ob.TextTruncate = Enum.TextTruncate.AtEnd
                            table.insert(ddConns, ob.MouseButton1Click:Connect(function()
                                for k in pairs(selectedMap) do selectedMap[k] = nil end
                                selectedMap[item.val] = true
                                rebuildLabel(); closeDd()
                            end))
                        end
                    end
                end
                if isSearch then table.insert(ddConns, searchBox:GetPropertyChangedSignal("Text"):Connect(function() rebuildList(searchBox.Text) end)) end
                rebuildList()
            end))
            
            fieldGetters[key] = {
                field = field,
                get = function()
                    local sel = getSelected()
                    if not isMulti then return sel[1] end
                    return sel
                end
            }

        elseif normalizedType == "duration" then
            makeFieldLabel()
            local durVal = tonumber(field.Default) or 0
            local allowPermanent = field.AllowPermanent ~= false
            local minDuration = tonumber(field.Min)
            local maxDuration = tonumber(field.Max)
            local durRow = Create("Frame", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = theme.bgAlt,
                BorderSizePixel = 0,
                LayoutOrder = nextFieldOrder(),
                Parent = card,
            })
            corner(durRow, 3); stroke(durRow, theme.border, 1)
            local durBox = Create("TextBox", {
                Size = UDim2.new(0.6, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = tostring(durVal),
                PlaceholderText = "0",
                PlaceholderColor3 = theme.muted,
                TextColor3 = theme.text,
                Font = FONT_SEMI,
                TextSize = 11,
                ClearTextOnFocus = true,
                Parent = durRow,
            })
            Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = durBox })
            local durUnit = field.Unit or "seconds"
            if durUnit == "permanent" and not allowPermanent then
                durUnit = "seconds"
            end
            local unitBtn = Create("TextButton", {
                Size = UDim2.new(0.4, 0, 1, 0),
                Position = UDim2.new(0.6, 0, 0, 0),
                BackgroundColor3 = theme.surfaceHi,
                BorderSizePixel = 0,
                Text = durUnit == "minutes" and "min"
                    or durUnit == "hours" and "hr"
                    or durUnit == "days" and "days"
                    or durUnit == "permanent" and "perm"
                    or "sec",
                TextColor3 = theme.textDim,
                Font = FONT,
                TextSize = 10,
                AutoButtonColor = false,
                Parent = durRow,
            })
            corner(unitBtn, 3)
            local units = { { label = "sec", value = "seconds" }, { label = "min", value = "minutes" }, { label = "hr", value = "hours" }, { label = "days", value = "days" } }
            if allowPermanent then
                table.insert(units, { label = "perm", value = "permanent" })
            end
            local unitIdx = 1
            for i, item in ipairs(units) do
                if item.value == durUnit then
                    unitIdx = i
                    break
                end
            end
            table.insert(window._connections, unitBtn.MouseButton1Click:Connect(function()
                unitIdx = (unitIdx % #units) + 1
                unitBtn.Text = units[unitIdx].label
                durUnit = units[unitIdx].value
            end))
            table.insert(window._connections, durBox.FocusLost:Connect(function()
                durVal = tonumber(durBox.Text) or 0
                if minDuration then durVal = math.max(durVal, minDuration) end
                if maxDuration then durVal = math.min(durVal, maxDuration) end
                durBox.Text = tostring(durVal)
            end))
            fieldGetters[key] = {
                field = field,
                get = function()
                    durVal = tonumber(durBox.Text) or durVal or 0
                    if minDuration then durVal = math.max(durVal, minDuration) end
                    if maxDuration then durVal = math.min(durVal, maxDuration) end
                    if durUnit == "permanent" then
                        if field.ReturnSeconds then return math.huge end
                        return { value = durVal, unit = durUnit, seconds = math.huge }
                    end
                    local seconds = durationToSeconds(durVal, durUnit)
                    if field.ReturnSeconds then return seconds end
                    return { value = durVal, unit = durUnit, seconds = seconds }
                end
            }

        elseif normalizedType == "color" then
            local picker = Section.CreateColorPicker(proxySection, {
                Name = displayFieldName(field, key, label),
                CurrentColor = field.Default or field.CurrentColor or Color3.new(1, 1, 1),
            })
            fieldGetters[key] = { field = field, get = function() return picker:Get() end }
        end
    end

    -- Spacer
    Create("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundTransparency = 1,
        LayoutOrder = nextFieldOrder(),
        Parent = card,
    })

    -- Status row for feedback
    local statusRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = nextFieldOrder(),
        Parent = card,
    })
    local statusLbl = Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = theme.accent,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = statusRow,
    })

    local function setStatus(state, msg)
        statusRow.Visible = true
        statusLbl.Text = stateIcon(state) .. "  " .. (msg or "")
        statusLbl.TextColor3 = stateColor(theme, state)
    end

    -- Submit button
    local submitBtn = Create("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = theme.accent,
        BorderSizePixel = 0,
        Text = cfg.ButtonText or cfg.Name or "Execute",
        TextColor3 = Color3.new(1, 1, 1),
        Font = FONT_SEMI,
        TextSize = 12,
        AutoButtonColor = false,
        LayoutOrder = nextFieldOrder(),
        Parent = card,
    })
    corner(submitBtn, 4)

    local executing = false
    submitBtn.MouseEnter:Connect(function()
        if not executing then submitBtn.BackgroundColor3 = theme.surfaceHi end
    end)
    submitBtn.MouseLeave:Connect(function()
        if not executing then submitBtn.BackgroundColor3 = theme.accent end
    end)

    -- Confirm gate
    local confirmArmed = false
    local confirmUntil = 0

    table.insert(window._connections, submitBtn.MouseButton1Click:Connect(function()
        if executing then return end

        if cfg.Confirm then
            if confirmArmed and tick() < confirmUntil then
                confirmArmed = false
                -- proceed to execution
            else
                confirmArmed = true
                confirmUntil = tick() + (cfg.ConfirmTimeout or 1.5)
                submitBtn.Text = "! Confirm?"
                submitBtn.BackgroundColor3 = theme.danger
                task.delay(cfg.ConfirmTimeout or 1.5, function()
                    if confirmArmed then
                        confirmArmed = false
                        submitBtn.Text = cfg.ButtonText or cfg.Name or "Execute"
                        submitBtn.BackgroundColor3 = theme.accent
                    end
                end)
                return
            end
        end

        -- Collect values and validate
        local values = {}
        for _, field in ipairs(fields) do
            local k = field.Key or field.Name or ""
            local getterInfo = fieldGetters[k]
            if getterInfo then
                local val = type(getterInfo) == "function" and getterInfo() or getterInfo.get()
                local fieldType = tostring(field.Type or "text")
                local normalizedFieldType = fieldType:lower()
                
                -- Required validation
                if field.Required then
                    local valid = true
                    local t = type(val)
                    if t == "string" and val:match("^%s*$") then valid = false end
                    if t == "table" then
                        if val.value ~= nil and val.unit ~= nil then
                            if val.value == 0 and val.unit ~= "permanent" then valid = false end
                        else
                            if #val == 0 then valid = false end
                        end
                    end
                    if normalizedFieldType == "duration" and t == "number" and val <= 0 then
                        valid = false
                    end
                    if val == nil then valid = false end
                    if normalizedFieldType == "number" or normalizedFieldType == "userid" then
                        if not tonumber(val) then valid = false end
                    end
                    
                    if not valid then
                        setStatus("error", "Missing required field: " .. (field.Label or field.Name or k))
                        confirmArmed = false
                        submitBtn.Text = cfg.ButtonText or cfg.Name or "Execute"
                        submitBtn.BackgroundColor3 = theme.accent
                        return
                    end
                end
                
                -- Format output
                if normalizedFieldType == "duration" and field.ReturnSeconds and type(val) == "table" then
                    val = val.seconds or durationToSeconds(val.value, val.unit)
                end
                
                values[k] = val
            end
        end

        executing = true
        submitBtn.Text = "... Running..."
        submitBtn.BackgroundColor3 = theme.bgAlt
        setStatus("loading", "Executing...")

        -- Provide a status function to the callback
        local function statusFn(state, msg)
            setStatus(state, msg)
            if state == "success" or state == "error" then
                executing = false
                submitBtn.BackgroundColor3 = theme.accent
                submitBtn.Text = cfg.ButtonText or cfg.Name or "Execute"
            end
        end

        task.spawn(function()
            local remote = cfg.Remote or window._commandRemote
            if cfg.Callback then
                local ok, err = pcall(cfg.Callback, values, statusFn)
                if not ok then
                    warn("[AdminUI] command callback error:", tostring(err))
                    statusFn("error", tostring(err))
                end
            elseif remote then
                local runner = AdminUI:CreateRemoteCommandRunner(remote, cfg.CommandName or cfg.Name)
                runner(values, statusFn)
            else
                statusFn("success", "Ready")
            end
            
            -- Auto-reset if callback didn't call statusFn to complete
            task.delay(0.1, function()
                if executing then
                    executing = false
                    submitBtn.BackgroundColor3 = theme.accent
                    submitBtn.Text = cfg.ButtonText or cfg.Name or "Execute"
                end
            end)
        end)
    end))

    function handle:Destroy() card:Destroy() end

    return handle
end

-- =========================================================================
-- Section layout helpers
-- =========================================================================

function Section:_next()
    self._order = (self._order or 0) + 1
    return self._order
end

-- =========================================================================
-- Tab
-- =========================================================================

local Tab = {}
Tab.__index = Tab

function Tab:CreateSection(name)
    local window = self.window
    local theme  = window.theme
    local sectionOrder = self:_next()

    if sectionOrder > 1 then
        Create("Frame", {
            Size = UDim2.new(1, 0, 0, 8),
            BackgroundTransparency = 1,
            LayoutOrder = sectionOrder * 1000,
            Parent = self.page,
        })
    end

    local headerRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder = sectionOrder * 1000 + 1,
        Parent = self.page,
    })

    local headerLbl = Create("TextLabel", {
        Size = UDim2.new(1, -24, 1, 0),
        BackgroundTransparency = 1,
        Text = string.upper(name or "Section"),
        TextColor3 = theme.accent,
        Font = FONT_BOLD,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = headerRow,
    })

    -- Collapse/expand toggle
    local collapsed = false
    local collapseBtn = Create("TextButton", {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.new(1, -18, 0, 0),
        BackgroundTransparency = 1,
        Text = "v",
        TextColor3 = theme.textDim,
        Font = FONT_SEMI,
        TextSize = 9,
        AutoButtonColor = false,
        Parent = headerRow,
    })

    local container = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = sectionOrder * 1000 + 2,
        Parent = self.page,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = container,
    })

    collapseBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        container.Visible = not collapsed
        collapseBtn.Text = collapsed and ">" or "v"
    end)

    local section = setmetatable({
        tab       = self,
        name      = name,
        header    = headerLbl,
        container = container,
    }, Section)

    table.insert(self.sections, section)
    return section
end

function Tab:_next()
    self._order = (self._order or 0) + 1
    return self._order
end

-- =========================================================================
-- Window
-- =========================================================================

local Window = {}
Window.__index = Window

function Window:CreateTab(name, icon)
    local theme = self.theme
    local tab = setmetatable({
        window   = self,
        name     = name,
        sections = {},
    }, Tab)

    local labelText = icon and (icon .. "  " .. name) or ("  " .. name)
    local button = Create("TextButton", {
        Size = UDim2.new(1, -8, 0, 28),
        BackgroundColor3 = theme.bgAlt,
        BorderSizePixel = 0,
        Text = labelText,
        TextColor3 = theme.textDim,
        Font = FONT_SEMI,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AutoButtonColor = false,
        LayoutOrder = #self.tabs + 1,
        Parent = self._tabStrip,
    })
    corner(button, 5)
    tab.button = button

    local page = Create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
        Parent = self._tabBody,
    })
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 16),
        Parent = page,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = page,
    })
    tab.page = page

    button.MouseButton1Click:Connect(function() self:SwitchTab(tab) end)
    table.insert(self.tabs, tab)
    if not self.activeTab then self:SwitchTab(tab) end

    return tab
end

function Window:SwitchTab(tab)
    local theme = self.theme
    for _, t in ipairs(self.tabs) do
        local active = (t == tab)
        t.page.Visible = active
        t.button.BackgroundColor3 = active and theme.surface or theme.bgAlt
        t.button.TextColor3 = active and theme.accent or theme.textDim
    end
    self.activeTab = tab
end

-- Window-level control methods

function Window:SetTitle(text)
    if self._titleLbl then self._titleLbl.Text = text end
end

function Window:SetSubtitle(text)
    if self._subtitleLbl then
        self._subtitleLbl.Visible = (text ~= nil and text ~= "")
        self._subtitleLbl.Text = text or ""
    end
end

function Window:SetFooter(text)
    if self._footerLbl then
        self._footerLbl.Visible = (text ~= nil and text ~= "")
        self._footerLbl.Text = text or ""
    end
end

function Window:SetAccent(color)
    if typeof(color) ~= "Color3" then return end
    self.theme.accent = color
    if self._accentStripe then self._accentStripe.BackgroundColor3 = color end
end

function Window:SetTheme(overrides)
    if type(overrides) ~= "table" then return end
    for k, v in pairs(overrides) do self.theme[k] = v end
end

function Window:SetVisible(v)
    if self.panel then self.panel.Visible = v ~= false end
end

function Window:Toggle()
    if self.panel then self.panel.Visible = not self.panel.Visible end
end

function Window:SetSize(size)
    if typeof(size) ~= "UDim2" then return end
    if self.panel then self.panel.Size = size end
end

function Window:SetPosition(pos)
    if typeof(pos) ~= "UDim2" then return end
    if self.panel then self.panel.Position = pos end
end

function Window:Center()
    if not self.panel then return end
    local s = self.panel.Size
    self.panel.Position = UDim2.new(0.5, -s.X.Offset / 2, 0.5, -s.Y.Offset / 2)
end

function AdminUI:CreateRemoteCommandRunner(remote, commandName)
    return function(values, statusFn)
        if typeof(remote) ~= "Instance" or not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
            if statusFn then statusFn("error", "Invalid command remote") end
            return nil
        end

        local payload = {
            Command = commandName,
            Values = values or {},
        }

        local ok, result
        if remote:IsA("RemoteFunction") then
            ok, result = pcall(function()
                return remote:InvokeServer(payload)
            end)
        else
            ok, result = pcall(function()
                remote:FireServer(payload)
                return true
            end)
        end

        if not ok then
            if statusFn then statusFn("error", tostring(result)) end
            return nil
        end

        if statusFn then
            if type(result) == "table" and result.Success == false then
                statusFn("error", result.Message or "Command failed")
            elseif type(result) == "table" and result.Message then
                statusFn("success", result.Message)
            else
                statusFn("success", remote:IsA("RemoteFunction") and "Completed" or "Sent")
            end
        end

        return result
    end
end

function Window:SetCommandRemote(remote)
    if remote == nil then
        self._commandRemote = nil
        return self
    end
    if typeof(remote) == "Instance" and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
        self._commandRemote = remote
    else
        warn("[AdminUI] SetCommandRemote expected RemoteEvent or RemoteFunction")
    end
    return self
end

function Window:OnClose(cb)
    if type(cb) == "function" then table.insert(self.onCloseCallbacks, cb) end
end

function Window:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    for _, cb in ipairs(self.onCloseCallbacks) do
        local ok, err = pcall(cb)
        if not ok then warn("[AdminUI] OnClose callback error:", tostring(err)) end
    end
    for _, connection in ipairs(self._connections) do
        if typeof(connection) == "RBXScriptConnection" then
            connection:Disconnect()
        end
    end
    self._connections = {}
    for _, cleanup in ipairs(self._cleanup) do pcall(cleanup) end
    pcall(function() self.gui:Destroy() end)
    pcall(function()
        if self.marker and self.marker.Parent then self.marker:Destroy() end
    end)
end

-- =========================================================================
-- Modal dialog
-- =========================================================================

function AdminUI:CreateModal(cfg)
    cfg = cfg or {}
    local theme = makeTheme()

    local playerGui = LP:WaitForChild("PlayerGui")
    local modalGui = Create("ScreenGui", {
        Name = "AdminUI_Modal",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 200,
        Parent = playerGui,
    })

    -- Scrim
    local scrim = Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5,
        Text = "",
        AutoButtonColor = false,
        Parent = modalGui,
    })

    local isDanger = cfg.Danger == true
    local dialog = Create("Frame", {
        Size = UDim2.fromOffset(340, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = theme.bg,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = scrim,
    })
    corner(dialog, 10)
    stroke(dialog, theme.border, 1)

    Create("UIPadding", {
        PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20),
        PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
        Parent = dialog,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = dialog,
    })

    local titleColor = isDanger and theme.danger or theme.accent
    Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = cfg.Title or "Confirm",
        TextColor3 = titleColor,
        Font = FONT_BOLD,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = 2,
        Parent = dialog,
    })

    if cfg.Content and cfg.Content ~= "" then
        Create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = cfg.Content,
            TextColor3 = theme.text,
            Font = FONT,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            LayoutOrder = 2,
            ZIndex = 2,
            Parent = dialog,
        })
    end

    local btnRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        ZIndex = 2,
        Parent = dialog,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        Parent = btnRow,
    })

    local function closeModal()
        modalGui:Destroy()
    end

    local cancelBtn = Create("TextButton", {
        Size = UDim2.fromOffset(80, 28),
        BackgroundColor3 = theme.surface,
        BorderSizePixel = 0,
        Text = cfg.CancelText or "Cancel",
        TextColor3 = theme.text,
        Font = FONT_SEMI,
        TextSize = 12,
        AutoButtonColor = false,
        LayoutOrder = 1,
        ZIndex = 3,
        Parent = btnRow,
    })
    corner(cancelBtn, 5)
    cancelBtn.MouseButton1Click:Connect(function()
        closeModal()
        task.spawn(safeCall, cfg.OnCancel)
    end)

    local confirmBtn = Create("TextButton", {
        Size = UDim2.fromOffset(90, 28),
        BackgroundColor3 = isDanger and theme.danger or theme.accent,
        BorderSizePixel = 0,
        Text = cfg.ConfirmText or "Confirm",
        TextColor3 = Color3.new(1, 1, 1),
        Font = FONT_SEMI,
        TextSize = 12,
        AutoButtonColor = false,
        LayoutOrder = 2,
        ZIndex = 3,
        Parent = btnRow,
    })
    corner(confirmBtn, 5)
    confirmBtn.MouseButton1Click:Connect(function()
        closeModal()
        task.spawn(safeCall, cfg.OnConfirm)
    end)

    -- Slide-in animation
    dialog.Position = UDim2.new(0.5, 0, 0.6, 0)
    dialog.BackgroundTransparency = 1
    TweenService:Create(dialog, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 0,
    }):Play()

    return {
        Close   = closeModal,
        Destroy = closeModal,
    }
end

-- =========================================================================
-- CreateWindow - public entry point
-- =========================================================================

function AdminUI:CreateWindow(cfg)
    cfg = cfg or {}
    local name = cfg.Name or "AdminUI"
    local markerName = "_AdminUI_" .. name:gsub("[^%w]", "_")

    -- Toggle-off: re-running destroys the old window and returns nil
    local existing = LP:FindFirstChild(markerName)
    if existing then existing:Destroy(); return nil end

    local self = setmetatable({}, Window)
    self.name             = name
    self.theme            = makeTheme(cfg.Accent)
    self.tabs             = {}
    self.activeTab        = nil
    self.onCloseCallbacks = {}
    self._cleanup         = {}
    self._connections     = {}
    self._destroyed       = false

    -- Marker (for toggle-off detection)
    local marker = Instance.new("BoolValue")
    marker.Name = markerName
    marker.Parent = LP
    self.marker = marker
    marker.Destroying:Connect(function() self:Destroy() end)

    -- ScreenGui - always PlayerGui, never CoreGui
    local playerGui = LP:WaitForChild("PlayerGui")
    local gui = Create("ScreenGui", {
        Name = "AdminUI_" .. name,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        Parent = playerGui,
    })
    self.gui = gui

    local size = (typeof(cfg.Size) == "UDim2") and cfg.Size or UDim2.fromOffset(620, 420)
    local pos  = (typeof(cfg.Position) == "UDim2") and cfg.Position
                 or UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2)

    local panel = Create("Frame", {
        Name = "Panel",
        Size = size,
        Position = pos,
        BackgroundColor3 = self.theme.bg,
        BorderSizePixel = 0,
        Active = true,
        Parent = gui,
    })
    corner(panel, 10)
    stroke(panel, self.theme.border, 1)
    self.panel = panel

    -- Title bar
    local titleBarH = cfg.Subtitle and 46 or 36
    local titleBar = Create("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, titleBarH),
        BackgroundTransparency = 1,
        Active = true,
        Parent = panel,
    })

    local accentStripe = Create("Frame", {
        Size = UDim2.fromOffset(3, titleBarH - 12),
        Position = UDim2.new(0, 10, 0, 6),
        BackgroundColor3 = self.theme.accent,
        BorderSizePixel = 0,
        Parent = titleBar,
    })
    corner(accentStripe, 2)
    self._accentStripe = accentStripe

    local titleLbl = Create("TextLabel", {
        Size = UDim2.new(1, -100, 0, 18),
        Position = UDim2.new(0, 20, 0, cfg.Subtitle and 6 or 9),
        BackgroundTransparency = 1,
        Text = name,
        TextColor3 = self.theme.text,
        Font = FONT_BOLD,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })
    self._titleLbl = titleLbl

    if cfg.Subtitle then
        self._subtitleLbl = Create("TextLabel", {
            Size = UDim2.new(1, -100, 0, 12),
            Position = UDim2.new(0, 20, 0, 26),
            BackgroundTransparency = 1,
            Text = cfg.Subtitle,
            TextColor3 = self.theme.textDim,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = titleBar,
        })
    end

    local function makeIconBtn(icon, color, xOff)
        local b = Create("TextButton", {
            Size = UDim2.fromOffset(22, 22),
            Position = UDim2.new(1, xOff, 0, 7),
            BackgroundColor3 = self.theme.surface,
            BorderSizePixel = 0,
            Text = icon,
            TextColor3 = color,
            Font = FONT_BOLD,
            TextSize = 14,
            AutoButtonColor = false,
            Parent = titleBar,
        })
        corner(b, 4)
        return b
    end
    local closeBtn = makeIconBtn("x", self.theme.danger, -30)
    local minBtn   = makeIconBtn("-", self.theme.text,   -56)

    closeBtn.MouseButton1Click:Connect(function() self:Destroy() end)

    -- Separator line
    Create("Frame", {
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 0, titleBarH),
        BackgroundColor3 = self.theme.border,
        BorderSizePixel = 0,
        Parent = panel,
    })

    -- Footer (optional)
    local footerH = 0
    if cfg.Footer then
        footerH = 22
        self._footerLbl = Create("TextLabel", {
            Size = UDim2.new(1, -20, 0, footerH),
            Position = UDim2.new(0, 10, 1, -footerH),
            BackgroundTransparency = 1,
            Text = cfg.Footer,
            TextColor3 = self.theme.muted,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = panel,
        })
    end

    -- Content area
    local contentY = titleBarH + 2
    local contentH = -(titleBarH + 10 + footerH)
    local content = Create("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -16, 1, contentH),
        Position = UDim2.new(0, 8, 0, contentY + 2),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    self.content = content

    -- Tab strip (left sidebar, wider for admin panels)
    local stripW = cfg.TabWidth or 130
    local tabStrip = Create("Frame", {
        Name = "TabStrip",
        Size = UDim2.new(0, stripW, 1, 0),
        BackgroundColor3 = self.theme.bgAlt,
        BorderSizePixel = 0,
        Parent = content,
    })
    corner(tabStrip, 8)

    local tabScroll = Create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -16),
        Position = UDim2.fromOffset(0, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = self.theme.border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = tabStrip,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 3),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Parent = tabScroll,
    })
    self._tabStrip = tabScroll

    local tabBody = Create("Frame", {
        Name = "TabBody",
        Size = UDim2.new(1, -(stripW + 8), 1, 0),
        Position = UDim2.new(0, stripW + 8, 0, 0),
        BackgroundColor3 = self.theme.bgAlt,
        BorderSizePixel = 0,
        Parent = content,
    })
    corner(tabBody, 8)
    self._tabBody = tabBody

    -- Minimize
    local minimized = false
    local fullSize = size
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        content.Visible = not minimized
        panel.Size = minimized and UDim2.fromOffset(fullSize.X.Offset, titleBarH + 2) or fullSize
        minBtn.Text = minimized and "+" or "-"
    end)

    -- Drag
    do
        local dragging, dragStart, startPos = false, nil, nil
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos  = panel.Position
            end
        end)
        titleBar.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        local dragConn = UIS.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                          or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
                           or Vector2.new(1920, 1080)
                local newX = math.clamp(startPos.X.Offset + delta.X, 0, vp.X - panel.AbsoluteSize.X)
                local newY = math.clamp(startPos.Y.Offset + delta.Y, 0, vp.Y - panel.AbsoluteSize.Y)
                panel.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
            end
        end)
        table.insert(self._cleanup, function()
            dragging = false; dragConn:Disconnect()
        end)
    end

    return self
end

-- =========================================================================
-- Notifications (upgraded)
-- =========================================================================

local notifyGui, notifyStack
local notifyOrder    = 0
local notifyMap      = {}  -- id -> toast frame (for replacement)
local notifyQueue    = 0
local MAX_TOASTS     = 6

local function ensureNotifyContainer()
    if notifyGui and notifyGui.Parent then return end
    local playerGui = LP:WaitForChild("PlayerGui")
    notifyGui = Create("ScreenGui", {
        Name = "AdminUI_Notifications",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 150,
        Parent = playerGui,
    })
    notifyStack = Create("Frame", {
        Name = "Stack",
        Size = UDim2.new(0, 300, 1, -40),
        Position = UDim2.new(1, -316, 0, 20),
        BackgroundTransparency = 1,
        Parent = notifyGui,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Parent = notifyStack,
    })
end

function AdminUI:Notify(cfg)
    cfg = cfg or {}
    ensureNotifyContainer()

    -- Queue cap
    notifyQueue = notifyQueue + 1
    if notifyQueue > MAX_TOASTS then
        -- Remove oldest
        local children = notifyStack:GetChildren()
        for _, c in ipairs(children) do
            if c:IsA("Frame") then c:Destroy(); break end
        end
        notifyQueue = MAX_TOASTS
    end

    -- Replace existing by Id
    if cfg.Id and notifyMap[cfg.Id] then
        local old = notifyMap[cfg.Id]
        if old.Parent then old:Destroy() end
        notifyMap[cfg.Id] = nil
        notifyQueue = math.max(0, notifyQueue - 1)
    end

    local theme = makeTheme()
    if typeof(cfg.Accent) == "Color3" then theme.accent = cfg.Accent end

    local notifType = cfg.Type or "info"
    local accentColor = stateColor(theme, notifType)
    local duration  = cfg.Duration or 4
    local persistent = cfg.Persistent == true

    notifyOrder = notifyOrder + 1

    local toast = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(1.2, 0, 0, 0),
        BackgroundColor3 = theme.bg,
        BorderSizePixel = 0,
        LayoutOrder = notifyOrder,
        Parent = notifyStack,
    })
    corner(toast, 8); stroke(toast, theme.border, 1)

    if cfg.Id then notifyMap[cfg.Id] = toast end

    local stripe = Create("Frame", {
        Size = UDim2.new(0, 3, 1, -14),
        Position = UDim2.new(0, 8, 0, 7),
        BackgroundColor3 = accentColor,
        BorderSizePixel = 0,
        Parent = toast,
    })
    corner(stripe, 2)

    local contentBox = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = toast,
    })
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, persistent and 30 or 12),
        Parent = contentBox,
    })
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = contentBox,
    })

    -- Icon + Title row
    local titleRowFrame = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = contentBox,
    })
    Create("TextLabel", {
        Size = UDim2.fromOffset(16, 14),
        BackgroundTransparency = 1,
        Text = stateIcon(notifType),
        TextColor3 = accentColor,
        Font = FONT_BOLD,
        TextSize = 12,
        Parent = titleRowFrame,
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -18, 1, 0),
        Position = UDim2.fromOffset(18, 0),
        BackgroundTransparency = 1,
        Text = cfg.Title or "",
        TextColor3 = accentColor,
        Font = FONT_BOLD,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleRowFrame,
    })

    if cfg.Content and cfg.Content ~= "" then
        Create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = cfg.Content,
            TextColor3 = theme.text,
            Font = FONT,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            LayoutOrder = 2,
            Parent = contentBox,
        })
    end

    -- Action buttons
    if cfg.Actions and #cfg.Actions > 0 then
        local actRow = Create("Frame", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            LayoutOrder = 3,
            Parent = contentBox,
        })
        Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Parent = actRow,
        })
        for _, action in ipairs(cfg.Actions) do
            local actBtn = Create("TextButton", {
                Size = UDim2.fromOffset(0, 20),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = accentColor,
                BorderSizePixel = 0,
                Text = (action.Text or "Action"),
                TextColor3 = Color3.new(1, 1, 1),
                Font = FONT_SEMI,
                TextSize = 11,
                AutoButtonColor = false,
                Parent = actRow,
            })
            corner(actBtn, 4)
            Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = actBtn })
            actBtn.MouseButton1Click:Connect(function()
                task.spawn(safeCall, action.Callback)
                if action.CloseOnClick ~= false then toast:Destroy() end
            end)
        end
    end

    -- Close button for persistent
    if persistent then
        local closeX = Create("TextButton", {
            Size = UDim2.fromOffset(18, 18),
            Position = UDim2.new(1, -22, 0, 8),
            BackgroundTransparency = 1,
            Text = "x",
            TextColor3 = theme.textDim,
            Font = FONT_BOLD,
            TextSize = 14,
            AutoButtonColor = false,
            ZIndex = 2,
            Parent = toast,
        })
        closeX.MouseButton1Click:Connect(function()
            toast:Destroy()
            notifyQueue = math.max(0, notifyQueue - 1)
        end)
    end

    local slideIn  = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local slideOut = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

    TweenService:Create(toast, slideIn, { Position = UDim2.new(0, 0, 0, 0) }):Play()

    if not persistent then
        task.delay(duration, function()
            if not toast or not toast.Parent then return end
            local t = TweenService:Create(toast, slideOut, { Position = UDim2.new(1.2, 0, 0, 0) })
            t:Play()
            t.Completed:Connect(function()
                toast:Destroy()
                notifyQueue = math.max(0, notifyQueue - 1)
            end)
        end)
    end
end

-- =========================================================================
-- Backwards-compatible alias
-- =========================================================================

OvertimeUI.CreateWindow  = AdminUI.CreateWindow
OvertimeUI.Notify        = AdminUI.Notify
OvertimeUI.CreateModal   = AdminUI.CreateModal
OvertimeUI.SetTheme      = AdminUI.SetTheme
OvertimeUI.CreateRemoteCommandRunner = AdminUI.CreateRemoteCommandRunner

return AdminUI
