-- Saved Notepad (mobile friendly) + Boombox Play
-- Saves to workspace folder: NotepadSaves.json (persists after re-executing)
-- Boombox: MM2 radio supported directly (Remotes.Inventory.PlaySong). Learn = fallback for other games

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer

local FILE = "NotepadSaves.json"
local GUI_NAME = "SavedNotepadGui"

-- Boombox settings (edit if a game uses different names)
local BOOMBOX_NAME_MATCH = "boom"          -- tool name contains this (case-insensitive)
local REMOTE_ARGS = {                      -- tried in order; ID is inserted where {ID} is
    { "PlaySong", "{ID}" },
    { "{ID}" },
}
local LOCAL_FALLBACK = false               -- true = play locally (only YOU hear it) if no boombox

----------------------------------------------------------------
-- Storage
----------------------------------------------------------------
local notes = {}

local function load()
    local ok, data = pcall(function()
        if isfile and isfile(FILE) then
            return HttpService:JSONDecode(readfile(FILE))
        end
    end)
    if ok and type(data) == "table" then notes = data end
end

local function save()
    pcall(function()
        if writefile then writefile(FILE, HttpService:JSONEncode(notes)) end
    end)
end

local function copyText(text)
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if fn then pcall(fn, text) return true end
    return false
end

load()

----------------------------------------------------------------
-- Boombox
-- Play tries, in order:
--   1) the remote you "Learn"ed (works with MM2's inventory boombox)
--   2) a boombox Tool in your backpack/hand
--   3) the boombox UI (types the ID into its box and presses its Play button)
----------------------------------------------------------------
local LEARN_FILE = "NotepadBoomboxRemote.json"
local learned = nil
pcall(function()
    if isfile and isfile(LEARN_FILE) then
        learned = HttpService:JSONDecode(readfile(LEARN_FILE))
    end
end)

local function getId(text)
    return (text or ""):match("%d%d%d%d%d+")
end

local function pathOf(inst)
    local p, cur = {}, inst
    while cur and cur ~= game do
        table.insert(p, 1, cur.Name)
        cur = cur.Parent
    end
    return p
end

local function resolvePath(path)
    local obj = game
    for _, name in ipairs(path) do
        obj = obj and obj:FindFirstChild(name)
    end
    return obj
end

-- 1) Learned remote ------------------------------------------------
local function playLearned(id)
    if not learned then return nil end
    local remote = resolvePath(learned.path)
    if not remote then return nil end
    local args = {}
    for i = 1, learned.n do
        if i == learned.idIndex then
            if learned.idKind == "number" then
                args[i] = tonumber(id)
            else
                args[i] = learned.prefix .. id .. learned.suffix
            end
        else
            args[i] = learned.args[i]
        end
    end
    if learned.method == "InvokeServer" then
        task.spawn(function() pcall(function() remote:InvokeServer(table.unpack(args, 1, learned.n)) end) end)
    else
        pcall(function() remote:FireServer(table.unpack(args, 1, learned.n)) end)
    end
    return "Sent (learned remote)"
end

-- Learn mode: captures the next boombox remote call you make by hand
local learning, hooked, learnCb, learnStamp = false, false, nil, 0

local function capture(remote, method, n, args)
    local idIndex, kind, prefix, suffix
    local clean = {}
    for i = 1, n do
        local v = args[i]
        local tv = type(v)
        if not idIndex and tv == "number" and v % 1 == 0 and v >= 10000 then
            idIndex, kind, clean[i] = i, "number", 0
        elseif not idIndex and tv == "string" and v:find("%d%d%d%d%d+") then
            local s, e = v:find("%d%d%d%d%d+")
            idIndex, kind = i, "string"
            prefix, suffix = v:sub(1, s - 1), v:sub(e + 1)
            clean[i] = ""
        elseif tv == "string" or tv == "number" or tv == "boolean" then
            clean[i] = v
        else
            return -- has an argument type we can't store (table/instance)
        end
    end
    if not idIndex then return end

    learned = {
        path = pathOf(remote), method = method, n = n, args = clean,
        idIndex = idIndex, idKind = kind, prefix = prefix or "", suffix = suffix or "",
    }
    pcall(function()
        if writefile then writefile(LEARN_FILE, HttpService:JSONEncode(learned)) end
    end)
    learning = false
    if learnCb then task.defer(learnCb, remote.Name) end
end

local function installHook()
    if hooked then return true end
    if not (hookmetamethod and getnamecallmethod) then return false end
    local old
    old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
        if learning then
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer")
                and not (checkcaller and checkcaller()) then
                local n = select("#", ...)
                local args = { ... }
                pcall(function()
                    if typeof(self) == "Instance"
                        and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                        capture(self, method, n, args)
                    end
                end)
            end
        end
        return old(self, ...)
    end))
    hooked = true
    return true
end

local function startLearn(cb)
    if not installHook() then return false end
    learning, learnCb = true, cb
    local my = os.clock()
    learnStamp = my
    task.delay(45, function()
        if learning and learnStamp == my then
            learning = false
            cb(nil)
        end
    end)
    return true
end

-- 2) Boombox Tool (backpack / hand) --------------------------------
local function findBoombox()
    local char = LocalPlayer.Character
    local pack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ char, pack }) do
        if container then
            for _, t in ipairs(container:GetChildren()) do
                if t:IsA("Tool") and t.Name:lower():find(BOOMBOX_NAME_MATCH) then
                    return t
                end
            end
        end
    end
end

local function playViaTool(id)
    local tool = findBoombox()
    if not tool then return nil end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and tool.Parent ~= char then
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.35)
    end
    local remote = tool:FindFirstChildWhichIsA("RemoteEvent", true)
    local remoteFn = tool:FindFirstChildWhichIsA("RemoteFunction", true)
    if not remote and not remoteFn then return nil end
    for _, pattern in ipairs(REMOTE_ARGS) do
        local args = {}
        for i, v in ipairs(pattern) do
            args[i] = (v == "{ID}") and (tonumber(id) or id) or v
        end
        if remote then
            pcall(function() remote:FireServer(unpack(args)) end)
        else
            task.spawn(function() pcall(function() remoteFn:InvokeServer(unpack(args)) end) end)
        end
    end
    return "Sent to boombox tool"
end

-- 3) Boombox UI (type the ID + press its Play button) ---------------
local function isShown(inst)
    local cur = inst
    while cur and not cur:IsA("PlayerGui") do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function clickButton(btn)
    local fired = false
    if firesignal then
        for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated }) do
            if pcall(firesignal, sig) then fired = true end
        end
    end
    if not fired and getconnections then
        for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated }) do
            for _, c in ipairs(getconnections(sig)) do
                pcall(function() c:Fire() end)
                fired = true
            end
        end
    end
    return fired
end

local function playViaGui(id)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    for _, tb in ipairs(pg:GetDescendants()) do
        if tb:IsA("TextBox") and tb:IsDescendantOf(pg) and not tb:FindFirstAncestor(GUI_NAME) and isShown(tb) then
            -- is this inside something boombox-ish?
            local isBoom, anc = false, tb.Parent
            for _ = 1, 6 do
                if anc and anc ~= pg then
                    if anc.Name:lower():find("boom") then isBoom = true end
                    anc = anc.Parent
                end
            end
            if isBoom then
                local btn
                local container = tb.Parent
                for _ = 1, 3 do
                    if container and container ~= pg then
                        for _, d in ipairs(container:GetDescendants()) do
                            if (d:IsA("TextButton") or d:IsA("ImageButton"))
                                and (d.Name:lower():find("play")
                                    or (d:IsA("TextButton") and d.Text:lower():find("play"))) then
                                btn = d
                                break
                            end
                        end
                        if btn then break end
                        container = container.Parent
                    end
                end
                if btn then
                    tb.Text = id
                    task.wait(0.1)
                    if clickButton(btn) then return "Pressed boombox UI Play" end
                end
            end
        end
    end
    return nil
end

-- 0) MM2 radio: found by the diagnostic.
-- The game's own Radio UI fires ReplicatedStorage.Remotes.Inventory.PlaySong
-- with the full asset URL; the sound then plays from Workspace.<you>.Radio.Sound
local function playMM2(id)
    local rs = game:GetService("ReplicatedStorage")
    local remotes = rs:FindFirstChild("Remotes")
    local inv = remotes and remotes:FindFirstChild("Inventory")
    local ps = inv and inv:FindFirstChild("PlaySong")
    if not (ps and ps:IsA("RemoteEvent")) then return nil end

    local char = workspace:FindFirstChild(LocalPlayer.Name)
    local hasRadio = char and char:FindFirstChild("Radio")

    ps:FireServer("https://www.roblox.com/asset/?id=" .. id)
    if hasRadio then
        return "Sent to your radio"
    end
    return "Sent, but no radio equipped? Equip one in Inventory > Radios"
end

local function playId(id)
    local msg = playMM2(id) or playLearned(id) or playViaTool(id) or playViaGui(id)
    if msg then return msg end
    if LOCAL_FALLBACK then
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://" .. id
        s.Volume = 1
        s.Parent = SoundService
        s:Play()
        return "Playing locally"
    end
    return "Not found: tap Learn, then play a song by hand"
end

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local parent
pcall(function() parent = gethui and gethui() end)
parent = parent or game:GetService("CoreGui")
if not pcall(function() return parent.Name end) then
    parent = LocalPlayer:WaitForChild("PlayerGui")
end
local old = parent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local FONT, FONT_BOLD = Enum.Font.Gotham, Enum.Font.GothamBold
local WHITE = Color3.new(1, 1, 1)

local function make(class, props, par)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = par
    return o
end
local function corner(o, r) make("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

local function button(par, text, color, size, pos, textSize)
    local b = make("TextButton", {
        Size = size, Position = pos,
        BackgroundColor3 = color, BackgroundTransparency = 0.2,
        Text = text, Font = FONT_BOLD, TextSize = textSize or 11,
        TextColor3 = WHITE, AutoButtonColor = true,
    }, par)
    corner(b, 5)
    return b
end

-- Small window for phones
local main = make("Frame", {
    Size = UDim2.new(0, 270, 0, 230),
    Position = UDim2.new(0, 10, 0.5, -115),
    BackgroundColor3 = Color3.fromRGB(15, 15, 20),
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
}, gui)
corner(main, 8)

-- Top bar
local bar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
}, main)
corner(bar, 8)

local barTitle = make("TextLabel", {
    Size = UDim2.new(1, -140, 1, 0), Position = UDim2.new(0, 34, 0, 0),
    BackgroundTransparency = 1, Text = "Notes", Font = FONT_BOLD, TextSize = 13,
    TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left,
}, bar)

local backBtn = button(bar, "<", Color3.fromRGB(90, 90, 100), UDim2.new(0, 24, 0, 20), UDim2.new(0, 5, 0, 4), 13)
backBtn.Visible = false
local plusBtn = button(bar, "+", Color3.fromRGB(60, 150, 90), UDim2.new(0, 24, 0, 20), UDim2.new(1, -58, 0, 4), 15)
local closeBtn = button(bar, "X", Color3.fromRGB(200, 60, 60), UDim2.new(0, 24, 0, 20), UDim2.new(1, -29, 0, 4), 12)
local learnBtn = button(bar, "Learn", Color3.fromRGB(120, 90, 190), UDim2.new(0, 40, 0, 20), UDim2.new(1, -102, 0, 4), 10)

-- Drag (mouse + touch)
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

-- Toast (small status message)
local toastLbl = make("TextLabel", {
    Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 1, -34),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3,
    Text = "", Font = FONT, TextSize = 10, TextColor3 = WHITE, TextWrapped = true,
    Visible = false, ZIndex = 10,
}, main)
corner(toastLbl, 5)
local toastId = 0
local function toast(msg, secs)
    toastId += 1
    local my = toastId
    toastLbl.Text = msg
    toastLbl.Visible = true
    task.delay(secs or 1.6, function()
        if my == toastId then toastLbl.Visible = false end
    end)
end

-- Views
local listView = make("Frame", {
    Size = UDim2.new(1, 0, 1, -28), Position = UDim2.new(0, 0, 0, 28),
    BackgroundTransparency = 1,
}, main)

local editView = make("Frame", {
    Size = UDim2.new(1, 0, 1, -28), Position = UDim2.new(0, 0, 0, 28),
    BackgroundTransparency = 1, Visible = false,
}, main)

-- List view
local list = make("ScrollingFrame", {
    Size = UDim2.new(1, -12, 1, -10), Position = UDim2.new(0, 6, 0, 5),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, listView)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
make("UIPadding", { PaddingRight = UDim.new(0, 4) }, list)

local emptyLbl = make("TextLabel", {
    Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0.5, -20),
    BackgroundTransparency = 1, Text = "No notes yet.\nTap + to add one.",
    Font = FONT, TextSize = 12, TextColor3 = Color3.fromRGB(200, 200, 200),
}, listView)

-- Edit view
local titleBox = make("TextBox", {
    Size = UDim2.new(1, -12, 0, 26), Position = UDim2.new(0, 6, 0, 6),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
    PlaceholderText = "Title...", PlaceholderColor3 = Color3.fromRGB(170, 170, 170),
    Text = "", Font = FONT_BOLD, TextSize = 13, TextColor3 = WHITE,
    TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, BorderSizePixel = 0,
}, editView)
corner(titleBox, 5)
make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, titleBox)

local textBox = make("TextBox", {
    Size = UDim2.new(1, -12, 1, -78), Position = UDim2.new(0, 6, 0, 38),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
    PlaceholderText = "Text / song / boombox ID...", PlaceholderColor3 = Color3.fromRGB(170, 170, 170),
    Text = "", Font = FONT, TextSize = 12, TextColor3 = WHITE,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true, MultiLine = true, ClearTextOnFocus = false, BorderSizePixel = 0,
}, editView)
corner(textBox, 5)
make("UIPadding", {
    PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
    PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
}, textBox)

local saveBtn = button(editView, "Save", Color3.fromRGB(60, 150, 90),
    UDim2.new(0.65, -9, 0, 28), UDim2.new(0, 6, 1, -34), 13)
local clearBtn = button(editView, "Clear", Color3.fromRGB(90, 90, 100),
    UDim2.new(0.35, -9, 0, 28), UDim2.new(0.65, 3, 1, -34), 13)

----------------------------------------------------------------
-- Logic
----------------------------------------------------------------
local editingIndex = nil
local render

local function showList()
    editView.Visible = false
    listView.Visible = true
    backBtn.Visible = false
    plusBtn.Visible = true
    learnBtn.Visible = true
    barTitle.Text = "Notes"
    barTitle.Position = UDim2.new(0, 8, 0, 0)
end

local function showEditor(index)
    editingIndex = index
    if index and notes[index] then
        titleBox.Text = notes[index].title
        textBox.Text = notes[index].text
        saveBtn.Text = "Update"
        barTitle.Text = "Edit"
    else
        titleBox.Text, textBox.Text = "", ""
        saveBtn.Text = "Save"
        barTitle.Text = "New note"
    end
    listView.Visible = false
    editView.Visible = true
    backBtn.Visible = true
    plusBtn.Visible = false
    learnBtn.Visible = false
    barTitle.Position = UDim2.new(0, 34, 0, 0)
end

render = function()
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    emptyLbl.Visible = (#notes == 0)

    for i, note in ipairs(notes) do
        local id = getId(note.text)
        local card = make("Frame", {
            Size = UDim2.new(1, 0, 0, 44),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
            BorderSizePixel = 0, LayoutOrder = i,
        }, list)
        corner(card, 6)

        -- tap the card body to edit
        local tap = make("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "",
        }, card)
        tap.MouseButton1Click:Connect(function() showEditor(i) end)

        make("TextLabel", {
            Size = UDim2.new(1, -108, 0, 18), Position = UDim2.new(0, 8, 0, 4),
            BackgroundTransparency = 1,
            Text = note.title ~= "" and note.title or "(no title)",
            Font = FONT_BOLD, TextSize = 12, TextColor3 = WHITE,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
        make("TextLabel", {
            Size = UDim2.new(1, -108, 0, 16), Position = UDim2.new(0, 8, 0, 23),
            BackgroundTransparency = 1,
            Text = (note.text or ""):gsub("%s+", " "),
            Font = FONT, TextSize = 10, TextColor3 = Color3.fromRGB(200, 200, 200),
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)

        local playB = button(card, "▶", Color3.fromRGB(60, 120, 200),
            UDim2.new(0, 28, 0, 24), UDim2.new(1, -100, 0, 10), 11)
        playB.Visible = id ~= nil
        local copyB = button(card, "Copy", Color3.fromRGB(190, 140, 40),
            UDim2.new(0, 34, 0, 24), UDim2.new(1, -68, 0, 10), 10)
        local delB = button(card, "Del", Color3.fromRGB(200, 60, 60),
            UDim2.new(0, 28, 0, 24), UDim2.new(1, -32, 0, 10), 10)

        playB.MouseButton1Click:Connect(function()
            toast(playId(id))
        end)

        -- Copies ONLY the text (not the title)
        copyB.MouseButton1Click:Connect(function()
            toast(copyText(note.text or "") and "Copied" or "No clipboard support")
        end)

        local armed = false
        delB.MouseButton1Click:Connect(function()
            if not armed then
                armed = true
                delB.Text = "?"
                task.delay(2, function()
                    if delB and delB.Parent then armed = false delB.Text = "Del" end
                end)
                return
            end
            table.remove(notes, i)
            save()
            render()
            toast("Deleted")
        end)
    end
end

plusBtn.MouseButton1Click:Connect(function() showEditor(nil) end)

learnBtn.MouseButton1Click:Connect(function()
    local ok = startLearn(function(name)
        toast(name and ("Learned: " .. name .. " - Play should work now") or "Learn timed out, try again", 3)
    end)
    if ok then
        toast("Equip your boombox and play any song by hand now (45s)", 5)
    else
        toast("Your executor can't hook remotes (no hookmetamethod)", 3)
    end
end)
backBtn.MouseButton1Click:Connect(showList)

saveBtn.MouseButton1Click:Connect(function()
    local title, text = titleBox.Text, textBox.Text
    if title == "" and text == "" then
        toast("Nothing to save")
        return
    end
    if editingIndex and notes[editingIndex] then
        notes[editingIndex].title = title
        notes[editingIndex].text = text
    else
        table.insert(notes, 1, { title = title, text = text })
    end
    save()
    render()
    showList()
    toast("Saved")
end)

clearBtn.MouseButton1Click:Connect(function()
    titleBox.Text, textBox.Text = "", ""
end)

-- Hide / show
local showBtn = make("TextButton", {
    Size = UDim2.new(0, 34, 0, 14), AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 6, 1, -6), BackgroundTransparency = 1,
    Text = "show", Font = FONT, TextSize = 9, TextColor3 = WHITE,
    TextTransparency = 0.35, TextStrokeTransparency = 0.6, Visible = false,
}, gui)

closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
    showBtn.Visible = true
end)
showBtn.MouseButton1Click:Connect(function()
    main.Visible = true
    showBtn.Visible = false
end)

render()
showList()
