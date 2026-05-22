-- ╔══════════════════════════════════════════════════════════════╗
-- ║           CUSTOM CHAT SYSTEM - MODULE SCRIPT                ║
-- ║     Simpan di: StarterPlayerScripts > ChatModule            ║
-- ╚══════════════════════════════════════════════════════════════╝

local ChatModule = {}

-- ══════════════════════════════════════════
-- KONFIGURASI UTAMA
-- ══════════════════════════════════════════
ChatModule.Config = {
	MaxMessageLength  = 200,
	MaxMessagesShown  = 50,
	BubbleChatDuration = 6,
	GlobalChatChannel = "GLOBAL_CHAT_V1",

	-- Badge IDs - ISI SESUAI BADGE DI GAME KAMU
	Badges = {
		JoinGame     = 0000000001, -- Ganti dengan Badge ID asli
		Play5Hours   = 0000000002,
		AFK24Hours   = 0000000003,
		Play48Hours  = 0000000004,
		MeetOwner    = 0000000005,
	},

	-- Owner UserID game kamu
	OwnerUserId = 0, -- Ganti dengan UserID kamu

	-- Warna tema UI
	Theme = {
		Background    = Color3.fromRGB(8, 10, 18),
		Surface       = Color3.fromRGB(14, 17, 28),
		SurfaceAlt    = Color3.fromRGB(20, 24, 40),
		Accent        = Color3.fromRGB(99, 102, 241),
		AccentGlow    = Color3.fromRGB(139, 92, 246),
		AccentHot     = Color3.fromRGB(236, 72, 153),
		Text          = Color3.fromRGB(240, 240, 255),
		TextMuted     = Color3.fromRGB(120, 120, 160),
		TextDim       = Color3.fromRGB(70, 70, 100),
		Success       = Color3.fromRGB(52, 211, 153),
		Warning       = Color3.fromRGB(251, 191, 36),
		Danger        = Color3.fromRGB(248, 113, 113),
		Border        = Color3.fromRGB(35, 40, 65),
		BorderGlow    = Color3.fromRGB(99, 102, 241),
	},
}

-- ══════════════════════════════════════════
-- FILTER KATA-KATA BERBAHAYA
-- ══════════════════════════════════════════
-- Hanya menandai (tag), tidak menghapus semua teks
ChatModule.FilterPatterns = {
	-- Rasisme (contoh pola, sesuaikan)
	racist = {
		"anjing%s*lo", "monyet%s*lo", "b[o0]d[o0]h", "tol[o0]l",
		"idiot", "goblok", "babi%s*lo", "negro", "nigga", "chink",
	},
	-- Ancaman / psikopat
	psycho = {
		"aku%s*akan%s*bunuh", "gue%s*bunuh", "mati%s*lo", "gue%s*habisin",
		"tak%s*bunuh", "nyawa%s*lo", "kubunuh", "i%s*will%s*kill",
		"die%s*now", "you%s*die",
	},
	-- Paksaan
	force = {
		"harus%s*nurut", "wajib%s*ikut", "gak%s*boleh%s*pergi",
		"paksa", "kamu%s*harus", "lu%s*wajib", "you%s*must%s*do",
	},
	-- Pemerasan
	extort = {
		"bayar%s*atau", "kasih%s*robux%s*atau", "kasih%s*password",
		"kasih%s*akun", "transfer%s*robux", "blackmail", "peras",
		"ancam", "share%s*account",
	},
}

ChatModule.TagLabels = {
	racist = "⚠ RASIS",
	psycho = "⚠ ANCAMAN",
	force  = "⚠ PAKSAAN",
	extort = "⚠ PEMERASAN",
}

ChatModule.TagColors = {
	racist = Color3.fromRGB(248, 113, 113),
	psycho = Color3.fromRGB(239, 68, 68),
	force  = Color3.fromRGB(251, 191, 36),
	extort = Color3.fromRGB(249, 115, 22),
}

-- ══════════════════════════════════════════
-- FUNGSI FILTER - Hanya tag bagian bermasalah
-- ══════════════════════════════════════════
function ChatModule.FilterMessage(text)
	local tags = {}
	local lowerText = text:lower()

	for category, patterns in pairs(ChatModule.FilterPatterns) do
		for _, pattern in ipairs(patterns) do
			if lowerText:match(pattern) then
				-- Cek sudah ada tag kategori ini belum
				local found = false
				for _, t in ipairs(tags) do
					if t.category == category then found = true break end
				end
				if not found then
					table.insert(tags, {
						category = category,
						label    = ChatModule.TagLabels[category],
						color    = ChatModule.TagColors[category],
						pattern  = pattern,
					})
				end
			end
		end
	end

	return tags -- Kembalikan list tag, teks ASLI tidak diubah
end

-- ══════════════════════════════════════════
-- UTILITAS UI
-- ══════════════════════════════════════════
function ChatModule.CreateCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

function ChatModule.CreateStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(99, 102, 241)
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.5
	stroke.Parent = parent
	return stroke
end

function ChatModule.CreateGradient(parent, colorList, rotation)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(colorList)
	grad.Rotation = rotation or 90
	grad.Parent = parent
	return grad
end

function ChatModule.Tween(obj, props, duration, style, direction)
	local TweenService = game:GetService("TweenService")
	local info = TweenInfo.new(
		duration or 0.25,
		style or Enum.EasingStyle.Quart,
		direction or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

-- ══════════════════════════════════════════
-- FORMAT WAKTU
-- ══════════════════════════════════════════
function ChatModule.FormatTime(t)
	local h = math.floor(t / 3600)
	local m = math.floor((t % 3600) / 60)
	local s = math.floor(t % 60)
	if h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	else
		return string.format("%02d:%02d", m, s)
	end
end

function ChatModule.TimeStamp()
	local now = os.time and os.time() or 0
	-- Roblox tidak punya os.time di client, pakai tick()
	local t   = math.floor(tick())
	local h   = math.floor((t % 86400) / 3600)
	local m   = math.floor((t % 3600) / 60)
	return string.format("%02d:%02d", h, m)
end

-- ══════════════════════════════════════════
-- WARNA NAMA PEMAIN (hash sederhana)
-- ══════════════════════════════════════════
local nameColorPalette = {
	Color3.fromRGB(129, 200, 255),
	Color3.fromRGB(167, 243, 208),
	Color3.fromRGB(253, 186, 116),
	Color3.fromRGB(216, 180, 254),
	Color3.fromRGB(252, 165, 165),
	Color3.fromRGB(103, 232, 249),
	Color3.fromRGB(134, 239, 172),
	Color3.fromRGB(251, 207, 232),
}

function ChatModule.GetNameColor(name)
	local hash = 0
	for i = 1, #name do
		hash = (hash + string.byte(name, i) * i) % #nameColorPalette
	end
	return nameColorPalette[hash + 1]
end

-- ══════════════════════════════════════════
-- DETEKSI CMD
-- ══════════════════════════════════════════
function ChatModule.ParseCommand(text, displayName)
	local cmd = text:match("^/create%-room%s*(.*)")
	if cmd ~= nil then
		local roomName = cmd:match("^%s*(.-)%s*$") -- trim
		if roomName == "" or roomName == nil then
			roomName = (displayName or "Player") .. " Room Chat"
		end
		return "create-room", roomName
	end
	return nil, nil
end

-- ══════════════════════════════════════════
-- GENERATE ID ROOM
-- ══════════════════════════════════════════
function ChatModule.GenerateRoomID()
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local id = "RM-"
	for i = 1, 8 do
		local idx = math.random(1, #chars)
		id = id .. chars:sub(idx, idx)
	end
	return id
end

return ChatModule
