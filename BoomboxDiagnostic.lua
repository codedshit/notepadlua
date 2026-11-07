-- Boombox Diagnostic
-- Reports how the game's boombox is handled (UI, remotes, sounds) so the
-- notepad's Play button can be built the right way.
--
-- HOW TO USE
-- 1) Execute this in the game.
-- 2) Use the boombox BY HAND: open it from your inventory/UI, type an ID, press play.
-- 3) Tap "Copy" and paste the output back to Claude.
--
-- It only OBSERVES: it does not fire any remotes or change anything in the game.
-- A copy of the report is also saved to your workspace folder: BoomboxDiagnostic.txt

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local FILE = "BoomboxDiagnostic.txt"
local GUI_NAME = "BoomboxDiagGui"
local MAX_PER_REMOTE = 8        -- log at most this many calls per remote (stops spam)
local MAX_LABEL_CHARS = 12000   -- on-screen limit (full report still copies)

local KEYWORDS = { "boom", "radio", "music", "song", "audio", "jukebox", "speaker", "sound" }
local REMOTE_KEYWORDS = { "boom", "radio", "music", "song", "audio", "jukebox", "speaker",
    "sound", "play", "equip", "inventory", "gear", "item" }

----------------------------------------------------------------
-- Log buffer
----------------------------------------------------------------
local lines = {}
local t0 = os.clock()
local flushQueued = false
local logLabel, logScroll

local function flush()
    flushQueued = false
    local text = table.concat(lines, "\n")
    pcall(function() if writefile then writefile(FILE, text) end end)
    if logLabel then
        local shown = text
        if #shown > MAX_LABEL_CHARS then
            shown = "...(older lines hidden, Copy gets everything)\n" .. shown:sub(-MAX_LABEL_CHARS)
        end
        logLabel.Text = shown
        if logScroll then logScroll.CanvasPosition = Vector2.new(0, 1e7) end
    end
end

local function log(s)
    table.insert(lines, string.format("[%5.1f] %s", os.clock() - t0, s))
    if not flushQueued then
        flushQueued = true
        task.delay(0.4, flush)
    end
end

local function section(title)
    table.insert(lines, "")
    table.insert(lines, "===== " .. title .. " =====")
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function lower(s) return tostring(s):lower() end

local function hasKeyword(s, list)
    s = lower(s)
    for _, k in ipairs(list or KEYWORDS) do
        if s:find(k, 1, true) then return true end
    end
    return false
end

local function path(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or tostring(inst)
end

local function ser(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        local s = v
        if #s > 100 then s = s:sub(1, 100) .. "..." end
        return string.format("%q", s)
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Instance" then
        return "<" .. v.ClassName .. " " .. path(v) .. ">"
    elseif t == "table" then
        if depth >= 2 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 8 then table.insert(parts, "...") break end
            table.insert(parts, "[" .. ser(k, depth + 1) .. "]=" .. ser(val, depth + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return t .. ":" .. tostring(v)
    end
end

local function serArgs(n, args)
    local out = {}
    for i = 1, n do out[i] = ser(args[i]) end
    return table.concat(out, ", ")
end

local function isShown(inst)
    local cur = inst
    while cur and not cur:IsA("PlayerGui") do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function describeGui(o)
    local extra = ""
    if o:IsA("TextButton") or o:IsA("TextLabel") then
        extra = " text=" .. ser(o.Text)
    elseif o:IsA("TextBox") then
        extra = " text=" .. ser(o.Text) .. " placeholder=" .. ser(o.PlaceholderText)
    end
    return string.format("%s [%s] shown=%s%s", path(o), o.ClassName, tostring(isShown(o)), extra)
end

-- Which script(s) handle a button's clicks (if the executor supports getconnections)
local function connectionInfo(btn)
    if not getconnections then return "getconnections unavailable" end
    local out = {}
    for _, sigName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down" }) do
        local ok, conns = pcall(function() return getconnections(btn[sigName]) end)
        if ok and conns then
            for i, c in ipairs(conns) do
                if i > 4 then break end
                local scriptPath = "?"
                pcall(function()
                    local f = c.Function
                    local env = getfenv(f)
                    if env and env.script then scriptPath = path(env.script) end
                end)
                table.insert(out, sigName .. " -> " .. scriptPath)
            end
        end
    end
    return #out > 0 and table.concat(out, "; ") or "no connections found"
end

----------------------------------------------------------------
-- Static scan
----------------------------------------------------------------
local function scanStatic()
    section("EXECUTOR / GAME")
    local exec = "unknown"
    pcall(function() exec = table.concat({ identifyexecutor() }, " ") end)
    log("executor: " .. exec)
    log("PlaceId: " .. tostring(game.PlaceId) .. "  GameId: " .. tostring(game.GameId))
    log("hookmetamethod=" .. tostring(hookmetamethod ~= nil)
        .. " getconnections=" .. tostring(getconnections ~= nil)
        .. " firesignal=" .. tostring(firesignal ~= nil)
        .. " getcallingscript=" .. tostring(getcallingscript ~= nil))

    section("TOOLS (backpack / character)")
    local found = false
    for _, c in ipairs({ LocalPlayer:FindFirstChildOfClass("Backpack"), LocalPlayer.Character }) do
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") then
                    found = true
                    log("Tool: " .. path(t))
                end
            end
        end
    end
    if not found then log("no Tools in backpack/hand") end

    section("SCREENGUIS")
    for _, g in ipairs(PlayerGui:GetChildren()) do
        if g:IsA("ScreenGui") and g.Name ~= GUI_NAME then
            log(string.format("%s enabled=%s descendants=%d", g.Name, tostring(g.Enabled), #g:GetDescendants()))
        end
    end

    section("BOOMBOX-LIKE GUI OBJECTS")
    local count = 0
    for _, o in ipairs(PlayerGui:GetDescendants()) do
        if not o:FindFirstAncestor(GUI_NAME) and o:IsA("GuiObject") then
            local match = hasKeyword(o.Name)
            if not match and (o:IsA("TextButton") or o:IsA("TextLabel")) and #o.Text < 40 then
                match = hasKeyword(o.Text) or lower(o.Text):match("^%s*play%s*$") ~= nil
            end
            if not match and o:IsA("TextBox") then
                match = hasKeyword(o.PlaceholderText)
            end
            if match then
                count += 1
                if count <= 120 then
                    log(describeGui(o))
                    if o:IsA("TextButton") or o:IsA("ImageButton") then
                        log("    handlers: " .. connectionInfo(o))
                    end
                end
            end
        end
    end
    log("matches: " .. count .. (count > 120 and " (showing first 120)" or ""))

    section("REMOTES (matching boombox/music/inventory words)")
    local total, shown = 0, 0
    for _, o in ipairs(game:GetDescendants()) do
        if (o:IsA("RemoteEvent") or o:IsA("RemoteFunction"))
            and not o:IsDescendantOf(game:GetService("CoreGui")) then
            total += 1
            local p = path(o)
            if hasKeyword(p, REMOTE_KEYWORDS) and shown < 80 then
                shown += 1
                log(o.ClassName .. ": " .. p)
            end
        end
    end
    log("total remotes in game: " .. total .. " (listed " .. shown .. " matching)")
end

----------------------------------------------------------------
-- Live watchers
----------------------------------------------------------------
local active = true
local counts, suppressed = {}, {}

local function onRemote(remote, method, n, args, caller)
    if not active then return end
    if typeof(remote) ~= "Instance" then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then return end
    local p = path(remote)
    counts[p] = (counts[p] or 0) + 1
    if counts[p] > MAX_PER_REMOTE then
        suppressed[p] = (suppressed[p] or 0) + 1
        return
    end
    local who = caller and path(caller) or "?"
    log(string.format("REMOTE %s:%s(%s)  from=%s", p, method, serArgs(n, args), who))
end

local function installHook()
    if not (hookmetamethod and getnamecallmethod) then
        log("!! hookmetamethod missing: cannot log remote calls (UI + sound info still works)")
        return
    end
    local old
    old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
        local method = getnamecallmethod()
        if active and (method == "FireServer" or method == "InvokeServer")
            and not (checkcaller and checkcaller()) then
            local n = select("#", ...)
            local args = { ... }
            local okc, caller = pcall(function() return getcallingscript and getcallingscript() end)
            task.defer(onRemote, self, method, n, args, okc and caller or nil)
            if method == "InvokeServer" then
                local res = table.pack(old(self, ...))
                task.defer(function()
                    if typeof(self) == "Instance" and (counts[path(self)] or 0) <= MAX_PER_REMOTE then
                        log("   RETURNED from " .. path(self) .. ": " .. serArgs(res.n, res))
                    end
                end)
                return table.unpack(res, 1, res.n)
            end
        end
        return old(self, ...)
    end))
    log("remote logging active")
end

-- Taps/clicks: what UI element did you press?
UserInputService.InputBegan:Connect(function(input)
    if not active then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local ok, objs = pcall(function()
        return PlayerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
    end)
    if not ok then return end
    local shownCount = 0
    for _, o in ipairs(objs) do
        if not o:FindFirstAncestor(GUI_NAME) then
            shownCount += 1
            if shownCount <= 3 then
                log("TAP " .. describeGui(o))
                if o:IsA("TextButton") or o:IsA("ImageButton") then
                    log("    handlers: " .. connectionInfo(o))
                end
            end
        end
    end
end)

-- Typed text (e.g. the ID you enter)
local boxConns = {}
local function watchBox(tb)
    if boxConns[tb] or tb:FindFirstAncestor(GUI_NAME) then return end
    boxConns[tb] = tb.FocusLost:Connect(function(enter)
        log("TEXTBOX " .. path(tb) .. " text=" .. ser(tb.Text) .. " enterPressed=" .. tostring(enter))
    end)
end
for _, o in ipairs(PlayerGui:GetDescendants()) do
    if o:IsA("TextBox") then watchBox(o) end
end
PlayerGui.DescendantAdded:Connect(function(o)
    if o:IsA("TextBox") then watchBox(o) end
    if active and o:IsA("GuiObject") and not o:FindFirstAncestor(GUI_NAME) and hasKeyword(o.Name) then
        log("GUI APPEARED " .. path(o) .. " [" .. o.ClassName .. "]")
    end
end)

-- New Sound objects (where does the song actually play from?)
game.DescendantAdded:Connect(function(o)
    if active and o:IsA("Sound") and not o:IsDescendantOf(game:GetService("CoreGui")) then
        task.defer(function()
            log("NEW SOUND " .. path(o) .. " id=" .. ser(o.SoundId) .. " playing=" .. tostring(o.Playing))
        end)
    end
end)

local function snapshotSounds()
    section("SOUNDS CURRENTLY PLAYING")
    local n = 0
    for _, o in ipairs(game:GetDescendants()) do
        if o:IsA("Sound") and o.Playing and not o:IsDescendantOf(game:GetService("CoreGui")) then
            n += 1
            if n <= 30 then
                log(string.format("%s id=%s volume=%.2f", path(o), ser(o.SoundId), o.Volume))
            end
        end
    end
    log("playing sounds: " .. n)
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
pcall(function()
    local p = (gethui and gethui()) or game:GetService("CoreGui")
    local old = p:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)
local old2 = PlayerGui:FindFirstChild(GUI_NAME)
if old2 then old2:Destroy() end

local guiParent
pcall(function() guiParent = gethui and gethui() end)
guiParent = guiParent or game:GetService("CoreGui")
if not pcall(function() return guiParent.Name end) then guiParent = PlayerGui end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = guiParent

local function make(class, props, par)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = par
    return o
end
local function corner(o, r) make("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

local main = make("Frame", {
    Size = UDim2.new(0, 300, 0, 230),
    Position = UDim2.new(0, 10, 0.5, -115),
    BackgroundColor3 = Color3.fromRGB(15, 15, 20),
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
}, gui)
corner(main, 8)

local bar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
}, main)
corner(bar, 8)
make("TextLabel", {
    Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 8, 0, 0),
    BackgroundTransparency = 1, Text = "Boombox Diagnostic",
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
}, bar)

local function btn(text, color, size, pos, par)
    local b = make("TextButton", {
        Size = size, Position = pos, BackgroundColor3 = color, BackgroundTransparency = 0.15,
        Text = text, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
    }, par)
    corner(b, 5)
    return b
end

local closeBtn = btn("X", Color3.fromRGB(200, 60, 60), UDim2.new(0, 24, 0, 18), UDim2.new(1, -28, 0, 4), bar)

-- drag
do
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

logScroll = make("ScrollingFrame", {
    Size = UDim2.new(1, -12, 1, -66), Position = UDim2.new(0, 6, 0, 30),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
    BorderSizePixel = 0, ScrollBarThickness = 4,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)
corner(logScroll, 5)

logLabel = make("TextLabel", {
    Size = UDim2.new(1, -8, 0, 0), Position = UDim2.new(0, 4, 0, 2),
    AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
    Text = "", Font = Enum.Font.Code, TextSize = 10, TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
}, logScroll)

local copyBtn = btn("Copy", Color3.fromRGB(60, 120, 200), UDim2.new(0.34, -8, 0, 26), UDim2.new(0, 6, 1, -32), main)
local snapBtn = btn("Sounds", Color3.fromRGB(60, 150, 90), UDim2.new(0.33, -4, 0, 26), UDim2.new(0.34, 0, 1, -32), main)
local rescanBtn = btn("Rescan", Color3.fromRGB(120, 90, 190), UDim2.new(0.33, -8, 0, 26), UDim2.new(0.67, 2, 1, -32), main)

local function fullReport()
    local extra = {}
    local any = false
    for p, n in pairs(suppressed) do
        if not any then
            table.insert(extra, "")
            table.insert(extra, "===== SPAMMY REMOTES (extra calls hidden) =====")
            any = true
        end
        table.insert(extra, p .. "  (+" .. n .. " more calls)")
    end
    return table.concat(lines, "\n") .. "\n" .. table.concat(extra, "\n")
end

copyBtn.MouseButton1Click:Connect(function()
    flush()
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if fn then
        pcall(fn, fullReport())
        copyBtn.Text = "Copied!"
    else
        copyBtn.Text = "No clipboard"
    end
    task.delay(1.2, function() copyBtn.Text = "Copy" end)
end)

snapBtn.MouseButton1Click:Connect(snapshotSounds)
rescanBtn.MouseButton1Click:Connect(function()
    section("RESCAN")
    scanStatic()
end)

local showBtn = make("TextButton", {
    Size = UDim2.new(0, 34, 0, 14), AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 6, 1, -6), BackgroundTransparency = 1,
    Text = "diag", Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = Color3.new(1, 1, 1),
    TextTransparency = 0.35, Visible = false,
}, gui)
closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
    showBtn.Visible = true
end)
showBtn.MouseButton1Click:Connect(function()
    main.Visible = true
    showBtn.Visible = false
end)

----------------------------------------------------------------
-- Go
----------------------------------------------------------------
installHook()
scanStatic()
section("LIVE LOG (now use the boombox by hand: open it, type an ID, press play)")
log("watching taps, typed text, remote calls and new sounds...")
flush()
