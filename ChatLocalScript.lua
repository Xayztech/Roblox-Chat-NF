-- ╔══════════════════════════════════════════════════════════════╗
-- ║         CUSTOM CHAT - LOCAL SCRIPT (CLIENT SIDE)            ║
-- ║    Simpan di: StarterPlayerScripts > ChatLocalScript        ║
-- ╚══════════════════════════════════════════════════════════════╝

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterGui         = game:GetService("StarterGui")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local TextService        = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local ChatModule  = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ChatModule"))
local Cfg         = ChatModule.Config
local Theme       = Cfg.Theme

-- ══════════════════════════════════════════
-- MATIKAN CHAT BAWAAN ROBLOX
-- ══════════════════════════════════════════
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)

-- ══════════════════════════════════════════
-- TUNGGU REMOTE EVENTS DARI SERVER
-- ══════════════════════════════════════════
local RE = ReplicatedStorage:WaitForChild("ChatRemotes", 10)
if not RE then
	warn("[ChatSystem] ChatRemotes tidak ditemukan di ReplicatedStorage!")
	return
end

local SendMessage      = RE:WaitForChild("SendMessage")
local ReceiveMessage   = RE:WaitForChild("ReceiveMessage")
local SendGlobal       = RE:WaitForChild("SendGlobal")
local ReceiveGlobal    = RE:WaitForChild("ReceiveGlobal")
local CreateRoom       = RE:WaitForChild("CreateRoom")
local InviteToRoom     = RE:WaitForChild("InviteToRoom")
local ReceiveInvite    = RE:WaitForChild("ReceiveInvite")
local RespondInvite    = RE:WaitForChild("RespondInvite")
local InviteResponse   = RE:WaitForChild("InviteResponse")
local SendRoomMessage  = RE:WaitForChild("SendRoomMessage")
local ReceiveRoomMsg   = RE:WaitForChild("ReceiveRoomMsg")
local RoomUpdated      = RE:WaitForChild("RoomUpdated")
local GetPlayers       = RE:WaitForChild("GetPlayers")

-- ══════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════
local chatMode       = "server"   -- "server" | "global" | "room"
local currentRoom    = nil        -- {id, name}
local myRooms        = {}         -- {[id] = {name, members}}
local isChatOpen     = false
local isSettingsOpen = false
local isDragging     = false
local dragOffset     = Vector2.new()
local bubbleFrames   = {}         -- {[player] = BillboardGui}

-- ══════════════════════════════════════════
-- BUAT SCREENGU UTAMA
-- ══════════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "CustomChatGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder   = 10
ScreenGui.Parent         = PlayerGui

-- ══════════════════════════════════════════
-- HELPER: BUAT FRAME MODERN
-- ══════════════════════════════════════════
local function mkFrame(parent, props)
	local f = Instance.new("Frame")
	for k, v in pairs(props or {}) do f[k] = v end
	f.Parent = parent
	return f
end

local function mkText(class, parent, props)
	local t = Instance.new(class)
	t.Font             = Enum.Font.GothamBold
	t.TextColor3       = Theme.Text
	t.BackgroundTransparency = 1
	for k, v in pairs(props or {}) do t[k] = v end
	t.Parent = parent
	return t
end

local function mkBtn(parent, props)
	local b = Instance.new("TextButton")
	b.Font             = Enum.Font.GothamBold
	b.TextColor3       = Theme.Text
	b.AutoButtonColor  = false
	b.BorderSizePixel  = 0
	for k, v in pairs(props or {}) do b[k] = v end
	b.Parent = parent
	return b
end

local function addGlow(frame, color, spread)
	-- Simulasi glow dengan shadow bertingkat
	for i = 1, 2 do
		local shadow = Instance.new("Frame")
		shadow.Size              = UDim2.new(1, i*4, 1, i*4)
		shadow.Position          = UDim2.new(0, -i*2, 0, -i*2)
		shadow.BackgroundColor3  = color or Theme.Accent
		shadow.BackgroundTransparency = 0.7 + (i * 0.1)
		shadow.ZIndex            = frame.ZIndex - 1
		shadow.BorderSizePixel   = 0
		shadow.Parent            = frame.Parent
		ChatModule.CreateCorner(shadow, 12)
	end
end

-- ══════════════════════════════════════════
-- TOMBOL CHAT DI POJOK KIRI (dekat VoiceChat)
-- ══════════════════════════════════════════
local ChatToggleBtn = mkBtn(ScreenGui, {
	Name            = "ChatToggle",
	Size            = UDim2.new(0, 52, 0, 52),
	Position        = UDim2.new(0, 12, 1, -148),
	BackgroundColor3 = Theme.Surface,
	Text            = "",
	ZIndex          = 20,
})
ChatModule.CreateCorner(ChatToggleBtn, 16)
ChatModule.CreateStroke(ChatToggleBtn, Theme.Accent, 1.5, 0.3)

-- Icon chat (SVG-style pakai teks unicode)
local ChatIcon = mkText("TextLabel", ChatToggleBtn, {
	Size     = UDim2.new(1, 0, 1, 0),
	Text     = "💬",
	TextSize = 26,
	ZIndex   = 21,
})

-- Badge notif (jumlah pesan baru)
local NotifBadge = mkFrame(ChatToggleBtn, {
	Name             = "NotifBadge",
	Size             = UDim2.new(0, 18, 0, 18),
	Position         = UDim2.new(1, -4, 0, -4),
	BackgroundColor3 = Theme.AccentHot,
	Visible          = false,
	ZIndex           = 22,
})
ChatModule.CreateCorner(NotifBadge, 9)
local NotifNum = mkText("TextLabel", NotifBadge, {
	Size     = UDim2.new(1, 0, 1, 0),
	Text     = "0",
	TextSize = 10,
	ZIndex   = 23,
})

local unreadCount = 0
local function addUnread()
	unreadCount = unreadCount + 1
	NotifNum.Text   = tostring(unreadCount)
	NotifBadge.Visible = true
end
local function clearUnread()
	unreadCount = 0
	NotifBadge.Visible = false
end

-- ══════════════════════════════════════════
-- PANEL CHAT UTAMA
-- ══════════════════════════════════════════
local ChatPanel = mkFrame(ScreenGui, {
	Name             = "ChatPanel",
	Size             = UDim2.new(0, 360, 0, 520),
	Position         = UDim2.new(0, 12, 1, -680),
	BackgroundColor3 = Theme.Background,
	BackgroundTransparency = 0.05,
	Visible          = false,
	ZIndex           = 15,
})
ChatModule.CreateCorner(ChatPanel, 16)
ChatModule.CreateStroke(ChatPanel, Theme.Accent, 1.5, 0.4)

-- Gradient background panel
local panelGrad = Instance.new("UIGradient")
panelGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Background),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 8, 25)),
})
panelGrad.Rotation = 135
panelGrad.Parent = ChatPanel

-- ── HEADER ──
local Header = mkFrame(ChatPanel, {
	Name             = "Header",
	Size             = UDim2.new(1, 0, 0, 52),
	BackgroundColor3 = Theme.SurfaceAlt,
	ZIndex           = 16,
})
ChatModule.CreateCorner(Header, 16)
-- Potong sudut bawah header agar seamless
local headerFix = mkFrame(Header, {
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = Theme.SurfaceAlt,
	ZIndex           = 15,
})

-- Gradient header
ChatModule.CreateGradient(Header, {
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 20, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 15, 45)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 10, 35)),
}, 90)

local HeaderTitle = mkText("TextLabel", Header, {
	Size     = UDim2.new(1, -110, 1, 0),
	Position = UDim2.new(0, 14, 0, 0),
	Text     = "✦ CHAT",
	TextSize = 15,
	Font     = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex   = 17,
})

-- Dot status
local StatusDot = mkFrame(Header, {
	Size             = UDim2.new(0, 8, 0, 8),
	Position         = UDim2.new(0, 14, 0.5, 4),
	BackgroundColor3 = Theme.Success,
	ZIndex           = 17,
})
ChatModule.CreateCorner(StatusDot, 4)

-- Tombol close
local CloseBtn = mkBtn(Header, {
	Size             = UDim2.new(0, 32, 0, 32),
	Position         = UDim2.new(1, -40, 0.5, -16),
	BackgroundColor3 = Color3.fromRGB(40, 20, 30),
	Text             = "✕",
	TextSize         = 14,
	ZIndex           = 17,
})
ChatModule.CreateCorner(CloseBtn, 8)

-- ── MODE SELECTOR ──
local ModeBar = mkFrame(ChatPanel, {
	Name             = "ModeBar",
	Size             = UDim2.new(1, -16, 0, 36),
	Position         = UDim2.new(0, 8, 0, 56),
	BackgroundColor3 = Theme.SurfaceAlt,
	ZIndex           = 16,
})
ChatModule.CreateCorner(ModeBar, 10)

local modeButtons = {}
local modes = {
	{id = "server", label = "Server"},
	{id = "global", label = "Global"},
	{id = "room",   label = "Room"},
}

for i, m in ipairs(modes) do
	local btn = mkBtn(ModeBar, {
		Name             = m.id,
		Size             = UDim2.new(1/#modes, -4, 1, -6),
		Position         = UDim2.new((i-1)/#modes, 3, 0, 3),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = (m.id == chatMode) and 0 or 0.5,
		Text             = m.label,
		TextSize         = 13,
		Font             = Enum.Font.GothamBold,
		ZIndex           = 17,
	})
	ChatModule.CreateCorner(btn, 8)
	modeButtons[m.id] = btn
end

-- Indikator mode aktif
local ModeIndicator = mkFrame(ModeBar, {
	Size             = UDim2.new(1/#modes, -4, 1, -6),
	Position         = UDim2.new(0, 3, 0, 3),
	BackgroundColor3 = Theme.Accent,
	BackgroundTransparency = 0,
	ZIndex           = 16,
})
ChatModule.CreateCorner(ModeIndicator, 8)

-- Room selector bar (muncul saat mode room)
local RoomBar = mkFrame(ChatPanel, {
	Name             = "RoomBar",
	Size             = UDim2.new(1, -16, 0, 30),
	Position         = UDim2.new(0, 8, 0, 96),
	BackgroundColor3 = Theme.SurfaceAlt,
	Visible          = false,
	ZIndex           = 16,
})
ChatModule.CreateCorner(RoomBar, 8)

local RoomLabel = mkText("TextLabel", RoomBar, {
	Size     = UDim2.new(1, -36, 1, 0),
	Position = UDim2.new(0, 10, 0, 0),
	Text     = "Pilih room...",
	TextSize = 12,
	TextColor3 = Theme.TextMuted,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex   = 17,
})

local NewRoomBtn = mkBtn(RoomBar, {
	Size             = UDim2.new(0, 28, 0, 22),
	Position         = UDim2.new(1, -32, 0.5, -11),
	BackgroundColor3 = Theme.Accent,
	Text             = "+",
	TextSize         = 16,
	ZIndex           = 17,
})
ChatModule.CreateCorner(NewRoomBtn, 6)

-- ── AREA PESAN ──
local msgAreaOffY = 98
local msgAreaH    = 282

local MsgContainer = mkFrame(ChatPanel, {
	Name             = "MsgContainer",
	Size             = UDim2.new(1, -16, 0, msgAreaH),
	Position         = UDim2.new(0, 8, 0, msgAreaOffY),
	BackgroundColor3 = Theme.Surface,
	BackgroundTransparency = 0.3,
	ZIndex           = 16,
	ClipsDescendants = true,
})
ChatModule.CreateCorner(MsgContainer, 12)
ChatModule.CreateStroke(MsgContainer, Theme.Border, 1, 0.3)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size               = UDim2.new(1, -4, 1, -4)
ScrollFrame.Position           = UDim2.new(0, 2, 0, 2)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel    = 0
ScrollFrame.ScrollBarThickness = 3
ScrollFrame.ScrollBarImageColor3 = Theme.Accent
ScrollFrame.ScrollBarImageTransparency = 0.4
ScrollFrame.CanvasSize         = UDim2.new(0, 0, 0, 0)
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollFrame.ZIndex             = 17
ScrollFrame.Parent             = MsgContainer

local MsgLayout = Instance.new("UIListLayout")
MsgLayout.SortOrder    = Enum.SortOrder.LayoutOrder
MsgLayout.Padding      = UDim.new(0, 3)
MsgLayout.Parent       = ScrollFrame

local MsgPadding = Instance.new("UIPadding")
MsgPadding.PaddingLeft   = UDim.new(0, 6)
MsgPadding.PaddingRight  = UDim.new(0, 6)
MsgPadding.PaddingTop    = UDim.new(0, 6)
MsgPadding.PaddingBottom = UDim.new(0, 6)
MsgPadding.Parent        = ScrollFrame

-- ── INPUT BAR ──
local InputBar = mkFrame(ChatPanel, {
	Name             = "InputBar",
	Size             = UDim2.new(1, -16, 0, 44),
	Position         = UDim2.new(0, 8, 1, -52),
	BackgroundColor3 = Theme.SurfaceAlt,
	ZIndex           = 16,
})
ChatModule.CreateCorner(InputBar, 12)
ChatModule.CreateStroke(InputBar, Theme.Border, 1, 0.4)

local ChatInput = Instance.new("TextBox")
ChatInput.Size                = UDim2.new(1, -56, 1, -10)
ChatInput.Position            = UDim2.new(0, 10, 0, 5)
ChatInput.BackgroundTransparency = 1
ChatInput.BorderSizePixel     = 0
ChatInput.Font                = Enum.Font.Gotham
ChatInput.TextColor3          = Theme.Text
ChatInput.PlaceholderText     = "Tulis pesan... (/create-room <nama>)"
ChatInput.PlaceholderColor3   = Theme.TextDim
ChatInput.TextSize            = 13
ChatInput.TextXAlignment      = Enum.TextXAlignment.Left
ChatInput.ClearTextOnFocus    = false
ChatInput.ZIndex              = 17
ChatInput.Parent              = InputBar

local SendBtn = mkBtn(InputBar, {
	Size             = UDim2.new(0, 38, 0, 30),
	Position         = UDim2.new(1, -44, 0.5, -15),
	BackgroundColor3 = Theme.Accent,
	Text             = "▶",
	TextSize         = 14,
	ZIndex           = 17,
})
ChatModule.CreateCorner(SendBtn, 8)

-- ══════════════════════════════════════════
-- FUNGSI TAMBAH PESAN KE SCROLL
-- ══════════════════════════════════════════
local msgCount = 0

local function addMessage(data)
	-- data: {sender, displayName, text, tags, isOwn, isSystem, timestamp, mode}
	msgCount = msgCount + 1
	if msgCount > Cfg.MaxMessagesShown then
		local first = ScrollFrame:FindFirstChildOfClass("Frame")
		if first then first:Destroy() end
		msgCount = msgCount - 1
	end

	local isOwn    = data.isOwn or false
	local isSystem = data.isSystem or false

	-- Bubble container
	local bubble = mkFrame(ScrollFrame, {
		Name             = "Msg_" .. msgCount,
		Size             = UDim2.new(1, 0, 0, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder      = msgCount,
		ZIndex           = 17,
	})

	if isSystem then
		-- Pesan sistem
		local sysLbl = mkText("TextLabel", bubble, {
			Size             = UDim2.new(1, 0, 0, 0),
			AutomaticSize    = Enum.AutomaticSize.Y,
			Text             = "— " .. (data.text or "") .. " —",
			TextSize         = 11,
			TextColor3       = Theme.TextMuted,
			TextXAlignment   = Enum.TextXAlignment.Center,
			TextWrapped      = true,
			ZIndex           = 18,
		})
		bubble.Parent = ScrollFrame
		return
	end

	-- Header baris: nama + waktu
	local rowH = mkFrame(bubble, {
		Size             = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		ZIndex           = 17,
	})

	-- Badge mode
	local modeBadge = mkFrame(rowH, {
		Size             = UDim2.new(0, 0, 0, 14),
		AutomaticSize    = Enum.AutomaticSize.X,
		Position         = UDim2.new(0, 0, 0.5, -7),
		BackgroundColor3 = (data.mode == "global") and Theme.AccentHot
			or (data.mode == "room") and Theme.AccentGlow
			or Theme.Accent,
		ZIndex           = 18,
	})
	ChatModule.CreateCorner(modeBadge, 4)
	local modePad = Instance.new("UIPadding")
	modePad.PaddingLeft  = UDim.new(0, 4)
	modePad.PaddingRight = UDim.new(0, 4)
	modePad.Parent       = modeBadge
	local modeLbl = mkText("TextLabel", modeBadge, {
		Size     = UDim2.new(1, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Text     = (data.mode == "global") and "GLOBAL"
			or (data.mode == "room") and "ROOM"
			or "SVR",
		TextSize = 9,
		Font     = Enum.Font.GothamBold,
		ZIndex   = 19,
	})

	local nameColor = isOwn and Theme.AccentGlow
		or ChatModule.GetNameColor(data.sender or "?")
	local nameLbl = mkText("TextLabel", rowH, {
		Size     = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, 36, 0, 0),
		Text     = data.displayName or data.sender or "?",
		TextSize = 12,
		Font     = Enum.Font.GothamBold,
		TextColor3 = nameColor,
		ZIndex   = 18,
	})

	local tsLbl = mkText("TextLabel", rowH, {
		Size     = UDim2.new(0, 50, 1, 0),
		Position = UDim2.new(1, -50, 0, 0),
		Text     = data.timestamp or "",
		TextSize = 10,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex   = 18,
	})

	-- Teks pesan + tag filter
	local msgBg = mkFrame(bubble, {
		Size             = UDim2.new(1, 0, 0, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		BackgroundColor3 = isOwn and Color3.fromRGB(30, 22, 60)
			or Theme.SurfaceAlt,
		BackgroundTransparency = 0.2,
		ZIndex           = 17,
	})
	ChatModule.CreateCorner(msgBg, 8)
	if isOwn then
		ChatModule.CreateStroke(msgBg, Theme.AccentGlow, 1, 0.6)
	end

	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingLeft   = UDim.new(0, 8)
	msgPad.PaddingRight  = UDim.new(0, 8)
	msgPad.PaddingTop    = UDim.new(0, 5)
	msgPad.PaddingBottom = UDim.new(0, 5)
	msgPad.Parent        = msgBg

	local msgLayout2 = Instance.new("UIListLayout")
	msgLayout2.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout2.Padding   = UDim.new(0, 3)
	msgLayout2.Parent    = msgBg

	-- Teks utama
	local txtLbl = mkText("TextLabel", msgBg, {
		Size         = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text         = data.text or "",
		TextSize     = 13,
		TextWrapped  = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3   = Theme.Text,
		LayoutOrder  = 1,
		ZIndex       = 18,
	})

	-- Tag filter (hanya tampilkan label, teks asli tidak berubah)
	if data.tags and #data.tags > 0 then
		for _, tag in ipairs(data.tags) do
			local tagRow = mkFrame(msgBg, {
				Size             = UDim2.new(0, 0, 0, 18),
				AutomaticSize    = Enum.AutomaticSize.X,
				BackgroundColor3 = tag.color,
				BackgroundTransparency = 0.3,
				LayoutOrder      = 99,
				ZIndex           = 18,
			})
			ChatModule.CreateCorner(tagRow, 5)
			local tagPad = Instance.new("UIPadding")
			tagPad.PaddingLeft  = UDim.new(0, 6)
			tagPad.PaddingRight = UDim.new(0, 6)
			tagPad.Parent       = tagRow
			mkText("TextLabel", tagRow, {
				Size     = UDim2.new(1, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				Text     = tag.label,
				TextSize = 10,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				ZIndex   = 19,
			})
		end
	end

	-- Scroll ke bawah otomatis
	wait()
	ScrollFrame.CanvasPosition = Vector2.new(0, ScrollFrame.AbsoluteCanvasSize.Y)

	if not isChatOpen then addUnread() end
end

-- ══════════════════════════════════════════
-- BUBBLE CHAT DI ATAS KEPALA PEMAIN
-- ══════════════════════════════════════════
local function showBubble(player, text)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	-- Hapus bubble lama
	if bubbleFrames[player] then
		bubbleFrames[player]:Destroy()
		bubbleFrames[player] = nil
	end

	local bb = Instance.new("BillboardGui")
	bb.Size             = UDim2.new(0, 200, 0, 50)
	bb.StudsOffset      = Vector3.new(0, 2.8, 0)
	bb.AlwaysOnTop      = false
	bb.LightInfluence   = 0
	bb.ResetOnSpawn     = false
	bb.Adornee          = head
	bb.Parent           = head

	local bubbleBg = mkFrame(bb, {
		Size             = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(8, 8, 18),
		BackgroundTransparency = 0.15,
		ZIndex           = 5,
	})
	ChatModule.CreateCorner(bubbleBg, 10)
	ChatModule.CreateStroke(bubbleBg, Theme.Accent, 1, 0.4)

	local bpad = Instance.new("UIPadding")
	bpad.PaddingLeft  = UDim.new(0, 8)
	bpad.PaddingRight = UDim.new(0, 8)
	bpad.PaddingTop   = UDim.new(0, 4)
	bpad.PaddingBottom = UDim.new(0, 4)
	bpad.Parent       = bubbleBg

	local displayN = player.DisplayName
	local nameLbl  = mkText("TextLabel", bubbleBg, {
		Size     = UDim2.new(1, 0, 0, 14),
		Text     = displayN,
		TextSize = 10,
		TextColor3 = ChatModule.GetNameColor(player.Name),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex   = 6,
	})

	local msgLbl = mkText("TextLabel", bubbleBg, {
		Size     = UDim2.new(1, 0, 1, -16),
		Position = UDim2.new(0, 0, 0, 16),
		Text     = text,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex   = 6,
	})

	bubbleFrames[player] = bb

	-- Animasi masuk
	bubbleBg.BackgroundTransparency = 1
	ChatModule.Tween(bubbleBg, {BackgroundTransparency = 0.15}, 0.3)

	-- Auto destroy
	spawn(function()
		wait(Cfg.BubbleChatDuration)
		if bb and bb.Parent then
			ChatModule.Tween(bubbleBg, {BackgroundTransparency = 1}, 0.4)
			wait(0.45)
			bb:Destroy()
			if bubbleFrames[player] == bb then
				bubbleFrames[player] = nil
			end
		end
	end)
end

-- ══════════════════════════════════════════
-- PANEL SETTINGS
-- ══════════════════════════════════════════
local SettingsPanel = mkFrame(ScreenGui, {
	Name             = "SettingsPanel",
	Size             = UDim2.new(0, 300, 0, 420),
	Position         = UDim2.new(0, 380, 1, -680),
	BackgroundColor3 = Theme.Background,
	BackgroundTransparency = 0.05,
	Visible          = false,
	ZIndex           = 18,
})
ChatModule.CreateCorner(SettingsPanel, 16)
ChatModule.CreateStroke(SettingsPanel, Theme.AccentGlow, 1.5, 0.4)

local SHeader = mkFrame(SettingsPanel, {
	Size             = UDim2.new(1, 0, 0, 48),
	BackgroundColor3 = Color3.fromRGB(20, 12, 45),
	ZIndex           = 19,
})
ChatModule.CreateCorner(SHeader, 16)
mkFrame(SHeader, {
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 12, 45),
	ZIndex           = 18,
})
mkText("TextLabel", SHeader, {
	Size     = UDim2.new(1, -50, 1, 0),
	Position = UDim2.new(0, 14, 0, 0),
	Text     = "⚙ SETTINGS",
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex   = 20,
})
local SCloseBtn = mkBtn(SHeader, {
	Size             = UDim2.new(0, 30, 0, 30),
	Position         = UDim2.new(1, -38, 0.5, -15),
	BackgroundColor3 = Color3.fromRGB(40, 20, 30),
	Text             = "✕",
	TextSize         = 13,
	ZIndex           = 20,
})
ChatModule.CreateCorner(SCloseBtn, 8)

local SScrollFrame = Instance.new("ScrollingFrame")
SScrollFrame.Size               = UDim2.new(1, -16, 1, -60)
SScrollFrame.Position           = UDim2.new(0, 8, 0, 52)
SScrollFrame.BackgroundTransparency = 1
SScrollFrame.BorderSizePixel    = 0
SScrollFrame.ScrollBarThickness = 3
SScrollFrame.ScrollBarImageColor3 = Theme.AccentGlow
SScrollFrame.CanvasSize         = UDim2.new(0, 0, 0, 0)
SScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
SScrollFrame.ZIndex             = 19
SScrollFrame.Parent             = SettingsPanel

local SLayout = Instance.new("UIListLayout")
SLayout.SortOrder = Enum.SortOrder.LayoutOrder
SLayout.Padding   = UDim.new(0, 8)
SLayout.Parent    = SScrollFrame

local SPadding = Instance.new("UIPadding")
SPadding.PaddingTop    = UDim.new(0, 8)
SPadding.PaddingBottom = UDim.new(0, 8)
SPadding.Parent        = SScrollFrame

-- Helper buat section settings
local function mkSettingsSection(title, order)
	local sec = mkFrame(SScrollFrame, {
		Size             = UDim2.new(1, 0, 0, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.SurfaceAlt,
		LayoutOrder      = order,
		ZIndex           = 19,
	})
	ChatModule.CreateCorner(sec, 10)
	local secPad = Instance.new("UIPadding")
	secPad.PaddingLeft  = UDim.new(0, 10)
	secPad.PaddingRight = UDim.new(0, 10)
	secPad.PaddingTop   = UDim.new(0, 8)
	secPad.PaddingBottom = UDim.new(0, 8)
	secPad.Parent       = sec
	local secLayout = Instance.new("UIListLayout")
	secLayout.SortOrder = Enum.SortOrder.LayoutOrder
	secLayout.Padding   = UDim.new(0, 6)
	secLayout.Parent    = sec

	mkText("TextLabel", sec, {
		Size     = UDim2.new(1, 0, 0, 18),
		Text     = title,
		TextSize = 12,
		Font     = Enum.Font.GothamBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		ZIndex   = 20,
	})
	return sec
end

local function mkToggleRow(parent, label, order, defaultOn)
	local row = mkFrame(parent, {
		Size             = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Theme.Surface,
		LayoutOrder      = order,
		ZIndex           = 20,
	})
	ChatModule.CreateCorner(row, 7)
	mkText("TextLabel", row, {
		Size     = UDim2.new(1, -50, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		Text     = label,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex   = 21,
	})
	local tog = mkFrame(row, {
		Size             = UDim2.new(0, 38, 0, 20),
		Position         = UDim2.new(1, -46, 0.5, -10),
		BackgroundColor3 = defaultOn and Theme.Success or Theme.TextDim,
		ZIndex           = 21,
	})
	ChatModule.CreateCorner(tog, 10)
	local knob = mkFrame(tog, {
		Size             = UDim2.new(0, 16, 0, 16),
		Position         = defaultOn and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex           = 22,
	})
	ChatModule.CreateCorner(knob, 8)

	local isOn = defaultOn or false
	local togBtn = mkBtn(row, {
		Size             = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text             = "",
		ZIndex           = 23,
	})
	togBtn.MouseButton1Click:Connect(function()
		isOn = not isOn
		ChatModule.Tween(tog,  {BackgroundColor3 = isOn and Theme.Success or Theme.TextDim}, 0.2)
		ChatModule.Tween(knob, {Position = isOn and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}, 0.2)
	end)
	return row, function() return isOn end
end

local function mkInputRow(parent, label, placeholder, order)
	local row = mkFrame(parent, {
		Size             = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Theme.Surface,
		LayoutOrder      = order,
		ZIndex           = 20,
	})
	ChatModule.CreateCorner(row, 7)
	mkText("TextLabel", row, {
		Size     = UDim2.new(1, -10, 0, 18),
		Position = UDim2.new(0, 10, 0, 4),
		Text     = label,
		TextSize = 11,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex   = 21,
	})
	local inp = Instance.new("TextBox")
	inp.Size                = UDim2.new(1, -20, 0, 22)
	inp.Position            = UDim2.new(0, 10, 0, 24)
	inp.BackgroundColor3    = Theme.SurfaceAlt
	inp.BorderSizePixel     = 0
	inp.Font                = Enum.Font.Gotham
	inp.TextColor3          = Theme.Text
	inp.PlaceholderText     = placeholder
	inp.PlaceholderColor3   = Theme.TextDim
	inp.TextSize            = 12
	inp.TextXAlignment      = Enum.TextXAlignment.Left
	inp.ClearTextOnFocus    = false
	inp.ZIndex              = 21
	inp.Parent              = row
	ChatModule.CreateCorner(inp, 6)
	local inpPad = Instance.new("UIPadding")
	inpPad.PaddingLeft  = UDim.new(0, 6)
	inpPad.Parent       = inp
	return row, inp
end

-- == USER SETTINGS ==
local userSec = mkSettingsSection("👤  USER SETTINGS", 1)
local showChatRow, getShowChat = mkToggleRow(userSec, "Tampilkan Chat Saya", 1, true)
local whoInviteRow, _ = mkToggleRow(userSec, "Siapa Yang Bisa Invite Saya", 2, true)
local hidePlrRow, getHidePlr = mkToggleRow(userSec, "Sembunyikan Player Lain (Lokal)", 3, false)
local cloneRow, cloneInp = mkInputRow(userSec, "Clone Avatar (Username/ID/DisplayName)", "Masukkan target...", 4)

local cloneBtn = mkBtn(userSec, {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Theme.Accent,
	Text             = "🎭  Clone Avatar",
	TextSize         = 13,
	LayoutOrder      = 5,
	ZIndex           = 21,
})
ChatModule.CreateCorner(cloneBtn, 8)

-- == ROOM SETTINGS ==
local roomSec = mkSettingsSection("🚪  ROOM SETTINGS", 2)
local roomIdLabel = mkText("TextLabel", roomSec, {
	Size     = UDim2.new(1, 0, 0, 20),
	Text     = "Room ID: —",
	TextSize = 11,
	TextColor3 = Theme.TextMuted,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 1,
	ZIndex   = 21,
})

local listPlrBtn = mkBtn(roomSec, {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Theme.SurfaceAlt,
	Text             = "👥  List Player di Room",
	TextSize         = 13,
	LayoutOrder      = 2,
	ZIndex           = 21,
})
ChatModule.CreateCorner(listPlrBtn, 8)

local inviteRoomBtn = mkBtn(roomSec, {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Theme.SurfaceAlt,
	Text             = "➕  Invite ke Room",
	TextSize         = 13,
	LayoutOrder      = 3,
	ZIndex           = 21,
})
ChatModule.CreateCorner(inviteRoomBtn, 8)

local deleteRoomBtn = mkBtn(roomSec, {
	Size             = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Color3.fromRGB(40, 15, 15),
	Text             = "🗑  Delete Room",
	TextSize         = 13,
	LayoutOrder      = 4,
	ZIndex           = 21,
})
ChatModule.CreateCorner(deleteRoomBtn, 8)

-- ══════════════════════════════════════════
-- TOMBOL SETTINGS DI POJOK KIRI BAWAH
-- ══════════════════════════════════════════
local SettingsToggle = mkBtn(ScreenGui, {
	Name             = "SettingsToggle",
	Size             = UDim2.new(0, 52, 0, 52),
	Position         = UDim2.new(0, 12, 1, -88),  -- Di bawah tombol chat
	BackgroundColor3 = Theme.Surface,
	Text             = "⚙",
	TextSize         = 22,
	ZIndex           = 20,
})
ChatModule.CreateCorner(SettingsToggle, 16)
ChatModule.CreateStroke(SettingsToggle, Theme.AccentGlow, 1.5, 0.4)

-- ══════════════════════════════════════════
-- PANEL PLAYER LIST (INVITE / ROOM LIST)
-- ══════════════════════════════════════════
local PlayerListPanel = mkFrame(ScreenGui, {
	Name             = "PlayerListPanel",
	Size             = UDim2.new(0, 280, 0, 380),
	Position         = UDim2.new(0.5, -140, 0.5, -190),
	BackgroundColor3 = Theme.Background,
	Visible          = false,
	ZIndex           = 25,
})
ChatModule.CreateCorner(PlayerListPanel, 14)
ChatModule.CreateStroke(PlayerListPanel, Theme.AccentGlow, 1.5, 0.3)

local PLHeader = mkFrame(PlayerListPanel, {
	Size             = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = Color3.fromRGB(18, 12, 38),
	ZIndex           = 26,
})
ChatModule.CreateCorner(PLHeader, 14)
mkFrame(PLHeader, {
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 12, 38),
	ZIndex           = 25,
})
local PLTitle = mkText("TextLabel", PLHeader, {
	Size     = UDim2.new(1, -50, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	Text     = "Pilih Pemain",
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex   = 27,
})
local PLClose = mkBtn(PLHeader, {
	Size             = UDim2.new(0, 28, 0, 28),
	Position         = UDim2.new(1, -36, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(40, 20, 30),
	Text             = "✕",
	TextSize         = 12,
	ZIndex           = 27,
})
ChatModule.CreateCorner(PLClose, 7)

-- Search bar
local PLSearch = Instance.new("TextBox")
PLSearch.Size               = UDim2.new(1, -16, 0, 32)
PLSearch.Position           = UDim2.new(0, 8, 0, 50)
PLSearch.BackgroundColor3   = Theme.SurfaceAlt
PLSearch.BorderSizePixel    = 0
PLSearch.Font               = Enum.Font.Gotham
PLSearch.TextColor3         = Theme.Text
PLSearch.PlaceholderText    = "Cari pemain..."
PLSearch.PlaceholderColor3  = Theme.TextDim
PLSearch.TextSize           = 13
PLSearch.ClearTextOnFocus   = false
PLSearch.ZIndex             = 26
PLSearch.Parent             = PlayerListPanel
ChatModule.CreateCorner(PLSearch, 8)
local plspad = Instance.new("UIPadding")
plspad.PaddingLeft = UDim.new(0, 8)
plspad.Parent      = PLSearch

local PLScrollFrame = Instance.new("ScrollingFrame")
PLScrollFrame.Size               = UDim2.new(1, -16, 1, -96)
PLScrollFrame.Position           = UDim2.new(0, 8, 0, 88)
PLScrollFrame.BackgroundTransparency = 1
PLScrollFrame.BorderSizePixel    = 0
PLScrollFrame.ScrollBarThickness = 3
PLScrollFrame.ScrollBarImageColor3 = Theme.Accent
PLScrollFrame.CanvasSize         = UDim2.new(0, 0, 0, 0)
PLScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
PLScrollFrame.ZIndex             = 26
PLScrollFrame.Parent             = PlayerListPanel

local PLLayout = Instance.new("UIListLayout")
PLLayout.SortOrder = Enum.SortOrder.LayoutOrder
PLLayout.Padding   = UDim.new(0, 4)
PLLayout.Parent    = PLScrollFrame

PLClose.MouseButton1Click:Connect(function()
	PlayerListPanel.Visible = false
end)

-- ══════════════════════════════════════════
-- PANEL INVITE (menerima invite)
-- ══════════════════════════════════════════
local InvitePanel = mkFrame(ScreenGui, {
	Name             = "InvitePanel",
	Size             = UDim2.new(0, 300, 0, 130),
	Position         = UDim2.new(0.5, -150, 0, 20),
	BackgroundColor3 = Theme.Background,
	Visible          = false,
	ZIndex           = 30,
})
ChatModule.CreateCorner(InvitePanel, 14)
ChatModule.CreateStroke(InvitePanel, Theme.AccentGlow, 2, 0.2)

local IPTitle = mkText("TextLabel", InvitePanel, {
	Size     = UDim2.new(1, -20, 0, 30),
	Position = UDim2.new(0, 10, 0, 8),
	Text     = "📩 Invite ke Room",
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex   = 31,
})
local IPMsg = mkText("TextLabel", InvitePanel, {
	Size     = UDim2.new(1, -20, 0, 28),
	Position = UDim2.new(0, 10, 0, 36),
	Text     = "",
	TextSize = 12,
	TextColor3 = Theme.TextMuted,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	ZIndex   = 31,
})
local IPAccept = mkBtn(InvitePanel, {
	Size             = UDim2.new(0, 110, 0, 30),
	Position         = UDim2.new(0, 10, 1, -40),
	BackgroundColor3 = Theme.Success,
	Text             = "✓  Terima",
	TextSize         = 13,
	ZIndex           = 31,
})
ChatModule.CreateCorner(IPAccept, 8)
local IPDecline = mkBtn(InvitePanel, {
	Size             = UDim2.new(0, 110, 0, 30),
	Position         = UDim2.new(1, -120, 1, -40),
	BackgroundColor3 = Theme.Danger,
	Text             = "✕  Tolak",
	TextSize         = 13,
	ZIndex           = 31,
})
ChatModule.CreateCorner(IPDecline, 8)

local pendingInvite = nil  -- {fromPlayer, roomId, roomName}

-- ══════════════════════════════════════════
-- PANEL ROOM MELAYANG (bisa digeser)
-- ══════════════════════════════════════════
local RoomPanel = mkFrame(ScreenGui, {
	Name             = "RoomPanel",
	Size             = UDim2.new(0, 290, 0, 350),
	Position         = UDim2.new(0.5, 20, 0.5, -175),
	BackgroundColor3 = Theme.Background,
	BackgroundTransparency = 0.05,
	Visible          = false,
	ZIndex           = 22,
	Active           = true,
})
ChatModule.CreateCorner(RoomPanel, 14)
ChatModule.CreateStroke(RoomPanel, Theme.AccentGlow, 1.5, 0.3)

local RPHeader = mkFrame(RoomPanel, {
	Size             = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = Color3.fromRGB(18, 10, 40),
	ZIndex           = 23,
	Active           = true,
})
ChatModule.CreateCorner(RPHeader, 14)
mkFrame(RPHeader, {
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 10, 40),
	ZIndex           = 22,
})

local DragHandle = mkText("TextLabel", RPHeader, {
	Size     = UDim2.new(1, -80, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	Text     = "⠿  ROOM CHAT",
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex   = 24,
})
local RPClose = mkBtn(RPHeader, {
	Size             = UDim2.new(0, 28, 0, 28),
	Position         = UDim2.new(1, -36, 0.5, -14),
	BackgroundColor3 = Color3.fromRGB(40, 20, 30),
	Text             = "✕",
	TextSize         = 12,
	ZIndex           = 24,
})
ChatModule.CreateCorner(RPClose, 7)

-- Room list di dalam panel
local RPScroll = Instance.new("ScrollingFrame")
RPScroll.Size               = UDim2.new(1, -12, 1, -50)
RPScroll.Position           = UDim2.new(0, 6, 0, 47)
RPScroll.BackgroundTransparency = 1
RPScroll.BorderSizePixel    = 0
RPScroll.ScrollBarThickness = 3
RPScroll.ScrollBarImageColor3 = Theme.AccentGlow
RPScroll.CanvasSize         = UDim2.new(0, 0, 0, 0)
RPScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
RPScroll.ZIndex             = 23
RPScroll.Parent             = RoomPanel

local RPLayout = Instance.new("UIListLayout")
RPLayout.SortOrder = Enum.SortOrder.LayoutOrder
RPLayout.Padding   = UDim.new(0, 4)
RPLayout.Parent    = RPScroll

-- Drag RoomPanel
local rpDragging    = false
local rpDragStart   = nil
local rpStartPos    = nil

RPHeader.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or
	   input.UserInputType == Enum.UserInputType.Touch then
		rpDragging  = true
		rpDragStart = input.Position
		rpStartPos  = RoomPanel.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if rpDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or
	                   input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - rpDragStart
		RoomPanel.Position = UDim2.new(
			rpStartPos.X.Scale, rpStartPos.X.Offset + delta.X,
			rpStartPos.Y.Scale, rpStartPos.Y.Offset + delta.Y
		)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or
	   input.UserInputType == Enum.UserInputType.Touch then
		rpDragging = false
	end
end)

RPClose.MouseButton1Click:Connect(function()
	RoomPanel.Visible = false
end)

-- ══════════════════════════════════════════
-- UPDATE ROOM LIST DI PANEL
-- ══════════════════════════════════════════
local function refreshRoomPanel()
	for _, c in ipairs(RPScroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	if next(myRooms) == nil then
		local noRoom = mkText("TextLabel", RPScroll, {
			Size     = UDim2.new(1, 0, 0, 40),
			Text     = "Belum ada room. Ketik /create-room",
			TextSize = 12,
			TextColor3 = Theme.TextMuted,
			TextWrapped = true,
			ZIndex   = 24,
		})
		return
	end

	local ord = 0
	for id, room in pairs(myRooms) do
		ord = ord + 1
		local item = mkFrame(RPScroll, {
			Size             = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = (currentRoom and currentRoom.id == id)
				and Color3.fromRGB(30, 18, 65) or Theme.SurfaceAlt,
			LayoutOrder      = ord,
			ZIndex           = 24,
		})
		ChatModule.CreateCorner(item, 9)
		if currentRoom and currentRoom.id == id then
			ChatModule.CreateStroke(item, Theme.AccentGlow, 1.5, 0.3)
		end

		mkText("TextLabel", item, {
			Size     = UDim2.new(1, -10, 0, 20),
			Position = UDim2.new(0, 10, 0, 7),
			Text     = room.name,
			TextSize = 13,
			Font     = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex   = 25,
		})
		mkText("TextLabel", item, {
			Size     = UDim2.new(1, -10, 0, 16),
			Position = UDim2.new(0, 10, 0, 28),
			Text     = "ID: " .. id .. "  •  " .. (#room.members or 0) .. " anggota",
			TextSize = 10,
			TextColor3 = Theme.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex   = 25,
		})

		local selBtn = mkBtn(item, {
			Size             = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text             = "",
			ZIndex           = 26,
		})
		selBtn.MouseButton1Click:Connect(function()
			currentRoom = {id = id, name = room.name}
			chatMode    = "room"
			RoomLabel.Text = "🚪 " .. room.name
			-- Update mode bar
			for mid, mb in pairs(modeButtons) do
				ChatModule.Tween(mb, {BackgroundTransparency = (mid == "room") and 0 or 0.5}, 0.2)
			end
			ChatModule.Tween(ModeIndicator, {
				Position = UDim2.new(2/#modes, 3, 0, 3)
			}, 0.25)
			RoomBar.Visible = true
			roomIdLabel.Text = "Room ID: " .. id
			refreshRoomPanel()
			addMessage({
				isSystem = true,
				text     = "Berpindah ke room: " .. room.name,
			})
		end)
	end
end

-- ══════════════════════════════════════════
-- KIRIM PESAN
-- ══════════════════════════════════════════
local function sendChat()
	local text = ChatInput.Text:match("^%s*(.-)%s*$")
	if text == "" then return end
	ChatInput.Text = ""

	-- Cek CMD
	local cmd, arg = ChatModule.ParseCommand(text, LocalPlayer.DisplayName)
	if cmd == "create-room" then
		local roomId = ChatModule.GenerateRoomID()
		CreateRoom:FireServer(roomId, arg)
		myRooms[roomId] = {name = arg, members = {LocalPlayer.Name}}
		RoomPanel.Visible = true
		refreshRoomPanel()
		addMessage({isSystem = true, text = "Room '" .. arg .. "' dibuat! ID: " .. roomId})
		return
	end

	-- Filter
	local tags = ChatModule.FilterMessage(text)

	if chatMode == "server" then
		SendMessage:FireServer(text, tags)
	elseif chatMode == "global" then
		SendGlobal:FireServer(text, tags)
	elseif chatMode == "room" then
		if currentRoom then
			SendRoomMessage:FireServer(currentRoom.id, text, tags)
		else
			addMessage({isSystem = true, text = "Pilih room terlebih dahulu!"})
		end
	end
end

SendBtn.MouseButton1Click:Connect(sendChat)
ChatInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then sendChat() end
end)

-- ══════════════════════════════════════════
-- TOGGLE CHAT PANEL
-- ══════════════════════════════════════════
local function setChatOpen(open)
	isChatOpen = open
	ChatPanel.Visible = open
	if open then
		clearUnread()
		ChatModule.Tween(ChatPanel, {
			Position = UDim2.new(0, 12, 1, -680),
			BackgroundTransparency = 0.05,
		}, 0.3)
	end
end

ChatToggleBtn.MouseButton1Click:Connect(function()
	setChatOpen(not isChatOpen)
end)
CloseBtn.MouseButton1Click:Connect(function()
	setChatOpen(false)
end)

-- ══════════════════════════════════════════
-- TOGGLE SETTINGS
-- ══════════════════════════════════════════
SettingsToggle.MouseButton1Click:Connect(function()
	isSettingsOpen = not isSettingsOpen
	SettingsPanel.Visible = isSettingsOpen
end)
SCloseBtn.MouseButton1Click:Connect(function()
	isSettingsOpen = false
	SettingsPanel.Visible = false
end)

-- ══════════════════════════════════════════
-- SWITCH MODE CHAT
-- ══════════════════════════════════════════
local modePositions = {
	server = UDim2.new(0,       3, 0, 3),
	global = UDim2.new(1/3,    3, 0, 3),
	room   = UDim2.new(2/3,    3, 0, 3),
}

for mid, btn in pairs(modeButtons) do
	btn.MouseButton1Click:Connect(function()
		chatMode = mid
		for m2, b2 in pairs(modeButtons) do
			ChatModule.Tween(b2, {
				BackgroundTransparency = (m2 == mid) and 0 or 0.5
			}, 0.2)
		end
		ChatModule.Tween(ModeIndicator, {Position = modePositions[mid]}, 0.25)
		RoomBar.Visible = (mid == "room")

		if mid == "room" and next(myRooms) ~= nil then
			RoomPanel.Visible = true
			refreshRoomPanel()
		end

		addMessage({isSystem = true, text = "Mode: " .. mid:upper()})
	end)
end

-- ══════════════════════════════════════════
-- TERIMA PESAN DARI SERVER
-- ══════════════════════════════════════════
ReceiveMessage.OnClientEvent:Connect(function(data)
	-- data: {sender, displayName, text, tags, timestamp}
	data.mode  = "server"
	data.isOwn = (data.sender == LocalPlayer.Name)
	addMessage(data)
	if data.isOwn == false then
		local p = Players:FindFirstChild(data.sender)
		if p then showBubble(p, data.text) end
	end
end)

ReceiveGlobal.OnClientEvent:Connect(function(data)
	if chatMode ~= "global" and not isChatOpen then addUnread() end
	data.mode  = "global"
	data.isOwn = (data.sender == LocalPlayer.Name)
	addMessage(data)
end)

ReceiveRoomMsg.OnClientEvent:Connect(function(data)
	-- data: {roomId, sender, displayName, text, tags, timestamp}
	if chatMode ~= "room" then addUnread() end
	data.mode  = "room"
	data.isOwn = (data.sender == LocalPlayer.Name)
	addMessage(data)
	local p = Players:FindFirstChild(data.sender)
	if p then showBubble(p, data.text) end
end)

-- ══════════════════════════════════════════
-- INVITE DITERIMA DARI SERVER
-- ══════════════════════════════════════════
ReceiveInvite.OnClientEvent:Connect(function(fromName, roomId, roomName)
	pendingInvite = {fromName = fromName, roomId = roomId, roomName = roomName}
	IPMsg.Text    = fromName .. " mengundang kamu ke room:\n\"" .. roomName .. "\""
	InvitePanel.Visible = true
end)

IPAccept.MouseButton1Click:Connect(function()
	if not pendingInvite then return end
	RespondInvite:FireServer(pendingInvite.fromName, pendingInvite.roomId, true)
	-- Masuk room
	if not myRooms[pendingInvite.roomId] then
		myRooms[pendingInvite.roomId] = {name = pendingInvite.roomName, members = {}}
	end
	currentRoom = {id = pendingInvite.roomId, name = pendingInvite.roomName}
	chatMode    = "room"
	RoomLabel.Text = "🚪 " .. pendingInvite.roomName
	RoomBar.Visible = true
	RoomPanel.Visible = true
	refreshRoomPanel()
	addMessage({isSystem = true, text = "Bergabung ke room: " .. pendingInvite.roomName})
	pendingInvite = nil
	InvitePanel.Visible = false
end)

IPDecline.MouseButton1Click:Connect(function()
	if not pendingInvite then return end
	RespondInvite:FireServer(pendingInvite.fromName, pendingInvite.roomId, false)
	pendingInvite = nil
	InvitePanel.Visible = false
end)

-- Respon invite dari server (yg invite dapat notif)
InviteResponse.OnClientEvent:Connect(function(targetName, roomId, accepted)
	if accepted then
		addMessage({isSystem = true, text = targetName .. " menerima invite ke room!"})
	else
		addMessage({isSystem = true, text = targetName .. " menolak invite."})
	end
	-- Reset tombol invite jika ada
	for _, c in ipairs(PLScrollFrame:GetChildren()) do
		if c:IsA("Frame") and c.Name == "PLRow_" .. targetName then
			local invBtn = c:FindFirstChild("InviteBtn")
			if invBtn then
				invBtn.Text             = "Invite"
				invBtn.BackgroundColor3 = Theme.Accent
			end
		end
	end
end)

RoomUpdated.OnClientEvent:Connect(function(roomId, members)
	if myRooms[roomId] then
		myRooms[roomId].members = members
		if RoomPanel.Visible then refreshRoomPanel() end
	end
end)

-- ══════════════════════════════════════════
-- TAMPILKAN PLAYER LIST (INVITE)
-- ══════════════════════════════════════════
local function openPlayerList(title, onSelect)
	PLTitle.Text = title
	PLSearch.Text = ""
	for _, c in ipairs(PLScrollFrame:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	local allPlayers = Players:GetPlayers()
	local function renderList(filter)
		for _, c in ipairs(PLScrollFrame:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local ord = 0
		for _, p in ipairs(allPlayers) do
			if p == LocalPlayer then continue end
			local lf    = filter and filter:lower() or ""
			local match = lf == ""
				or p.Name:lower():find(lf, 1, true)
				or p.DisplayName:lower():find(lf, 1, true)
			if not match then continue end
			ord = ord + 1

			local row = mkFrame(PLScrollFrame, {
				Name             = "PLRow_" .. p.Name,
				Size             = UDim2.new(1, 0, 0, 52),
				BackgroundColor3 = Theme.SurfaceAlt,
				LayoutOrder      = ord,
				ZIndex           = 27,
			})
			ChatModule.CreateCorner(row, 9)

			-- Avatar thumb
			local thumb = Instance.new("ImageLabel")
			thumb.Size              = UDim2.new(0, 36, 0, 36)
			thumb.Position          = UDim2.new(0, 8, 0.5, -18)
			thumb.BackgroundColor3  = Theme.Surface
			thumb.Image             = "rbxthumb://type=AvatarHeadShot&id=" .. p.UserId .. "&w=48&h=48"
			thumb.ZIndex            = 28
			thumb.Parent            = row
			ChatModule.CreateCorner(thumb, 18)

			mkText("TextLabel", row, {
				Size     = UDim2.new(1, -130, 0, 18),
				Position = UDim2.new(0, 52, 0, 8),
				Text     = p.DisplayName,
				TextSize = 13,
				Font     = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex   = 28,
			})
			mkText("TextLabel", row, {
				Size     = UDim2.new(1, -130, 0, 14),
				Position = UDim2.new(0, 52, 0, 28),
				Text     = "@" .. p.Name,
				TextSize = 11,
				TextColor3 = Theme.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex   = 28,
			})

			local invBtn = mkBtn(row, {
				Name             = "InviteBtn",
				Size             = UDim2.new(0, 64, 0, 28),
				Position         = UDim2.new(1, -72, 0.5, -14),
				BackgroundColor3 = Theme.Accent,
				Text             = "Invite",
				TextSize         = 12,
				ZIndex           = 28,
			})
			ChatModule.CreateCorner(invBtn, 7)
			invBtn.MouseButton1Click:Connect(function()
				invBtn.Text             = "Menunggu..."
				invBtn.BackgroundColor3 = Theme.TextDim
				onSelect(p, invBtn)
			end)
		end
	end

	renderList("")
	PLSearch:GetPropertyChangedSignal("Text"):Connect(function()
		renderList(PLSearch.Text)
	end)
	PlayerListPanel.Visible = true
end

-- Tombol invite di room settings
inviteRoomBtn.MouseButton1Click:Connect(function()
	if not currentRoom then
		addMessage({isSystem = true, text = "Pilih room dulu!"})
		return
	end
	openPlayerList("Invite ke Room: " .. currentRoom.name, function(p, btn)
		InviteToRoom:FireServer(p.UserId, currentRoom.id, currentRoom.name)
	end)
end)

-- Tombol list player room
listPlrBtn.MouseButton1Click:Connect(function()
	if not currentRoom then return end
	local room = myRooms[currentRoom.id]
	if not room then return end
	local memberStr = table.concat(room.members or {}, ", ")
	addMessage({isSystem = true, text = "Anggota room: " .. (memberStr ~= "" and memberStr or "-")})
end)

-- Delete room
deleteRoomBtn.MouseButton1Click:Connect(function()
	if not currentRoom then return end
	myRooms[currentRoom.id] = nil
	addMessage({isSystem = true, text = "Room '" .. currentRoom.name .. "' dihapus."})
	currentRoom = nil
	chatMode    = "server"
	RoomBar.Visible = false
	RoomLabel.Text  = "Pilih room..."
	RoomPanel.Visible = false
	refreshRoomPanel()
end)

-- Clone avatar
cloneBtn.MouseButton1Click:Connect(function()
	local target = cloneInp.Text:match("^%s*(.-)%s*$")
	if target == "" then return end
	-- Kirim ke server untuk clone
	ReplicatedStorage.ChatRemotes:FindFirstChild("CloneAvatar"):FireServer(target)
end)

-- Sembunyikan player lokal
hidePlrRow:GetPropertyChangedSignal("Visible"):Connect(function() end)
local function applyHidePlayers(hide)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Character then
			for _, part in ipairs(p.Character:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("Decal") then
					part.LocalTransparencyModifier = hide and 1 or 0
				end
			end
		end
	end
end

-- ══════════════════════════════════════════
-- HOVER EFFECT BUTTONS
-- ══════════════════════════════════════════
local function addHover(btn, normalColor, hoverColor)
	btn.MouseEnter:Connect(function()
		ChatModule.Tween(btn, {BackgroundColor3 = hoverColor}, 0.15)
	end)
	btn.MouseLeave:Connect(function()
		ChatModule.Tween(btn, {BackgroundColor3 = normalColor}, 0.15)
	end)
end

addHover(ChatToggleBtn, Theme.Surface, Color3.fromRGB(30, 25, 55))
addHover(SettingsToggle, Theme.Surface, Color3.fromRGB(30, 25, 55))
addHover(SendBtn, Theme.Accent, Color3.fromRGB(120, 120, 255))
addHover(CloseBtn, Color3.fromRGB(40, 20, 30), Color3.fromRGB(60, 20, 30))
addHover(NewRoomBtn, Theme.Accent, Color3.fromRGB(120, 120, 255))

-- ══════════════════════════════════════════
-- PESAN SELAMAT DATANG
-- ══════════════════════════════════════════
wait(1.5)
addMessage({
	isSystem = true,
	text     = "Selamat datang, " .. LocalPlayer.DisplayName .. "! Chat aktif.",
})
addMessage({
	isSystem = true,
	text     = "Tip: Ketik /create-room <nama> untuk membuat room private.",
})
