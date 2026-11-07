-- Saved Notepad (for songs, notes, etc.)
-- Saves to your executor's workspace folder: NotepadSaves.json
-- Persists after rejoining / re-executing.

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local FILE = "NotepadSaves.json"
local GUI_NAME = "SavedNotepadGui"

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
    if ok and type(data) == "table" then
        notes = data
    end
end

local function save()
    pcall(function()
        if writefile then
            writefile(FILE, HttpService:JSONEncode(notes))
        end
    end)
end

local function copyText(text)
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if fn then
        pcall(fn, text)
        return true
    end
    return false
end

load()

----------------------------------------------------------------
-- GUI setup
----------------------------------------------------------------
local parent
pcall(function() parent = gethui and gethui() end)
parent = parent or game:GetService("CoreGui")
if not pcall(function() return parent.Name end) then
    parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local old = parent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = obj
end

local function make(class, props, par)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = par
    return o
end

-- Main window
local main = make("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 380, 0, 470),
    Position = UDim2.new(0.5, -190, 0.5, -235),
    BackgroundColor3 = Color3.fromRGB(15, 15, 20),
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
}, gui)
corner(main, 10)

-- Top bar
local bar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
}, main)
corner(bar, 10)

make("TextLabel", {
    Size = UDim2.new(1, -50, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "Notepad",
    Font = FONT_BOLD,
    TextSize = 16,
    TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
}, bar)

local closeBtn = make("TextButton", {
    Size = UDim2.new(0, 28, 0, 24),
    Position = UDim2.new(1, -34, 0, 5),
    BackgroundColor3 = Color3.fromRGB(200, 60, 60),
    BackgroundTransparency = 0.2,
    Text = "X",
    Font = FONT_BOLD,
    TextSize = 14,
    TextColor3 = Color3.new(1, 1, 1),
    AutoButtonColor = true,
}, bar)
corner(closeBtn, 6)

-- Dragging (mouse + touch)
do
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- Title input
local titleBox = make("TextBox", {
    Size = UDim2.new(1, -20, 0, 30),
    Position = UDim2.new(0, 10, 0, 42),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.5,
    PlaceholderText = "Title...",
    PlaceholderColor3 = Color3.fromRGB(170, 170, 170),
    Text = "",
    Font = FONT_BOLD,
    TextSize = 15,
    TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    BorderSizePixel = 0,
}, main)
corner(titleBox, 6)
make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, titleBox)

-- Text input (multiline)
local textBox = make("TextBox", {
    Size = UDim2.new(1, -20, 0, 120),
    Position = UDim2.new(0, 10, 0, 78),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.5,
    PlaceholderText = "Paste or type your text here...",
    PlaceholderColor3 = Color3.fromRGB(170, 170, 170),
    Text = "",
    Font = FONT,
    TextSize = 14,
    TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    MultiLine = true,
    ClearTextOnFocus = false,
    BorderSizePixel = 0,
}, main)
corner(textBox, 6)
make("UIPadding", {
    PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6),
}, textBox)

-- Save + Clear buttons
local saveBtn = make("TextButton", {
    Size = UDim2.new(0.62, -14, 0, 30),
    Position = UDim2.new(0, 10, 0, 204),
    BackgroundColor3 = Color3.fromRGB(60, 150, 90),
    BackgroundTransparency = 0.2,
    Text = "Save",
    Font = FONT_BOLD,
    TextSize = 14,
    TextColor3 = Color3.new(1, 1, 1),
}, main)
corner(saveBtn, 6)

local clearBtn = make("TextButton", {
    Size = UDim2.new(0.38, -14, 0, 30),
    Position = UDim2.new(0.62, 4, 0, 204),
    BackgroundColor3 = Color3.fromRGB(90, 90, 100),
    BackgroundTransparency = 0.2,
    Text = "Clear",
    Font = FONT_BOLD,
    TextSize = 14,
    TextColor3 = Color3.new(1, 1, 1),
}, main)
corner(clearBtn, 6)

-- Saved list
make("TextLabel", {
    Size = UDim2.new(1, -20, 0, 18),
    Position = UDim2.new(0, 10, 0, 242),
    BackgroundTransparency = 1,
    Text = "Saved",
    Font = FONT_BOLD,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(200, 200, 200),
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local list = make("ScrollingFrame", {
    Size = UDim2.new(1, -20, 1, -272),
    Position = UDim2.new(0, 10, 0, 262),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, main)
make("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, list)
make("UIPadding", { PaddingRight = UDim.new(0, 6) }, list)

-- Show button (bottom-left corner)
local showBtn = make("TextButton", {
    Size = UDim2.new(0, 36, 0, 14),
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 6, 1, -6),
    BackgroundTransparency = 1,
    Text = "show",
    Font = FONT,
    TextSize = 10,
    TextColor3 = Color3.new(1, 1, 1),
    TextTransparency = 0.35,
    TextStrokeTransparency = 0.6,
    Visible = false,
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
-- Logic
----------------------------------------------------------------
local editingIndex = nil

local function setEditing(i)
    editingIndex = i
    saveBtn.Text = i and "Update" or "Save"
end

local function flash(btn, text, resetText, secs)
    btn.Text = text
    task.delay(secs or 1, function()
        if btn and btn.Parent then btn.Text = resetText end
    end)
end

local render

local function makeCardButton(card, text, xScale, color)
    local b = make("TextButton", {
        Size = UDim2.new(0.333, -6, 0, 24),
        Position = UDim2.new(xScale, 4, 1, -30),
        BackgroundColor3 = color,
        BackgroundTransparency = 0.2,
        Text = text,
        Font = FONT_BOLD,
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
    }, card)
    corner(b, 5)
    return b
end

render = function()
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    for i, note in ipairs(notes) do
        local card = make("Frame", {
            Size = UDim2.new(1, 0, 0, 96),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            LayoutOrder = i,
        }, list)
        corner(card, 8)

        make("TextLabel", {
            Size = UDim2.new(1, -16, 0, 18),
            Position = UDim2.new(0, 8, 0, 4),
            BackgroundTransparency = 1,
            Text = note.title ~= "" and note.title or "(no title)",
            Font = FONT_BOLD,
            TextSize = 14,
            TextColor3 = Color3.new(1, 1, 1),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)

        local preview = (note.text or ""):gsub("%s+", " ")
        make("TextLabel", {
            Size = UDim2.new(1, -16, 0, 30),
            Position = UDim2.new(0, 8, 0, 22),
            BackgroundTransparency = 1,
            Text = preview,
            Font = FONT,
            TextSize = 12,
            TextColor3 = Color3.fromRGB(210, 210, 210),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)

        local copyB = makeCardButton(card, "Copy", 0, Color3.fromRGB(60, 120, 200))
        local editB = makeCardButton(card, "Edit", 0.333, Color3.fromRGB(190, 140, 40))
        local delB = makeCardButton(card, "Delete", 0.666, Color3.fromRGB(200, 60, 60))

        -- Copies ONLY the text, not the title
        copyB.MouseButton1Click:Connect(function()
            if copyText(note.text or "") then
                flash(copyB, "Copied!", "Copy")
            else
                flash(copyB, "No clipboard", "Copy", 1.5)
            end
        end)

        editB.MouseButton1Click:Connect(function()
            titleBox.Text = note.title
            textBox.Text = note.text
            setEditing(i)
        end)

        -- Press twice to confirm
        local armed = false
        delB.MouseButton1Click:Connect(function()
            if not armed then
                armed = true
                delB.Text = "Sure?"
                task.delay(2, function()
                    if delB and delB.Parent then
                        armed = false
                        delB.Text = "Delete"
                    end
                end)
                return
            end
            table.remove(notes, i)
            if editingIndex == i then
                setEditing(nil)
            elseif editingIndex and editingIndex > i then
                editingIndex = editingIndex - 1
            end
            save()
            render()
        end)
    end
end

saveBtn.MouseButton1Click:Connect(function()
    local title, text = titleBox.Text, textBox.Text
    if title == "" and text == "" then
        flash(saveBtn, "Nothing to save", editingIndex and "Update" or "Save")
        return
    end
    if editingIndex and notes[editingIndex] then
        notes[editingIndex].title = title
        notes[editingIndex].text = text
    else
        table.insert(notes, 1, { title = title, text = text })
    end
    save()
    titleBox.Text = ""
    textBox.Text = ""
    setEditing(nil)
    render()
    flash(saveBtn, "Saved!", "Save")
end)

clearBtn.MouseButton1Click:Connect(function()
    titleBox.Text = ""
    textBox.Text = ""
    setEditing(nil)
end)

render()
