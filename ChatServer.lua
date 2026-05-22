-- ╔══════════════════════════════════════════════════════════════╗
-- ║         CUSTOM CHAT - SERVER SCRIPT                         ║
-- ║    Simpan di: ServerScriptService > ChatServer              ║
-- ╚══════════════════════════════════════════════════════════════╝

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BadgeService      = game:GetService("BadgeService")
local MessagingService  = game:GetService("MessagingService")
local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")

-- ══════════════════════════════════════════
-- KONFIGURASI
-- ══════════════════════════════════════════
local CFG = {
	OwnerUserId = 0,  -- !! GANTI DENGAN USER ID KAMU !!

	Badges = {
		JoinGame  = 000000001, -- !! GANTI DENGAN BADGE ID ASLI !!
		Play5Hrs  = 000000002,
		AFK24Hrs  = 000000003,
		Play48Hrs = 000000004,
		MeetOwner = 000000005,
	},

	-- Anti-exploit: jumlah peringatan sebelum ban
	MaxWarnings    = 3,
	-- Interval minimum antar pesan (detik) - anti spam
	ChatCooldown   = 0.8,
	-- Panjang maksimum pesan
	MaxMsgLen      = 200,
	-- Channel MessagingService untuk global chat
	GlobalChannel  = "GLOBALCHAT_V1",
}

local BanStore      = DataStoreService:GetDataStore("ChatBanStore_V1")
local PlaytimeStore = DataStoreService:GetDataStore("PlaytimeStore_V1")

-- ══════════════════════════════════════════
-- BUAT REMOTE EVENTS
-- ══════════════════════════════════════════
local RE = Instance.new("Folder")
RE.Name   = "ChatRemotes"
RE.Parent = ReplicatedStorage

local function mkRemote(name, isFunc)
	local r
	if isFunc then
		r = Instance.new("RemoteFunction")
	else
		r = Instance.new("RemoteEvent")
	end
	r.Name   = name
	r.Parent = RE
	return r
end

local SendMessage     = mkRemote("SendMessage")
local ReceiveMessage  = mkRemote("ReceiveMessage")
local SendGlobal      = mkRemote("SendGlobal")
local ReceiveGlobal   = mkRemote("ReceiveGlobal")
local CreateRoom      = mkRemote("CreateRoom")
local InviteToRoom    = mkRemote("InviteToRoom")
local ReceiveInvite   = mkRemote("ReceiveInvite")
local RespondInvite   = mkRemote("RespondInvite")
local InviteResponse  = mkRemote("InviteResponse")
local SendRoomMsg     = mkRemote("SendRoomMessage")
local ReceiveRoomMsg  = mkRemote("ReceiveRoomMsg")
local RoomUpdated     = mkRemote("RoomUpdated")
local GetPlayers      = mkRemote("GetPlayers")
local CloneAvatar     = mkRemote("CloneAvatar")

-- ══════════════════════════════════════════
-- STATE SERVER
-- ══════════════════════════════════════════
local warnings    = {}  -- [userId] = count
local banned      = {}  -- [userId] = true
local lastChat    = {}  -- [userId] = tick()
local joinTimes   = {}  -- [userId] = tick()
local afkTimers   = {}  -- [userId] = tick() terakhir bergerak
local rooms       = {}  -- [roomId] = {name, owner, members={[userId]=true}}
local isOwnerHere = false

-- ══════════════════════════════════════════
-- UTILITAS
-- ══════════════════════════════════════════
local function log(...)
	print("[ChatServer]", ...)
end

local function safeDS(fn)
	local ok, err = pcall(fn)
	if not ok then warn("[DataStore]", err) end
end

local function timestamp()
	local t = math.floor(tick())
	local h = math.floor((t % 86400) / 3600)
	local m = math.floor((t % 3600) / 60)
	return string.format("%02d:%02d", h, m)
end

-- ══════════════════════════════════════════
-- ANTI-EXPLOIT: KICK & BAN SYSTEM
-- ══════════════════════════════════════════
local function warnPlayer(player, reason)
	local uid = player.UserId
	warnings[uid] = (warnings[uid] or 0) + 1
	local count = warnings[uid]

	if count >= CFG.MaxWarnings then
		-- BAN
		banned[uid] = true
		safeDS(function()
			BanStore:SetAsync("ban_" .. uid, true)
		end)
		player:Kick("🚫 Kamu telah di-BAN dari game ini karena: " .. reason)
		log("BANNED:", player.Name, "Alasan:", reason)
	else
		local sisa = CFG.MaxWarnings - count
		player:Kick(
			"⚠ PERINGATAN " .. count .. "/" .. CFG.MaxWarnings ..
			"\nAlasan: " .. reason ..
			"\nSisa kesempatan: " .. sisa ..
			"\nKamu dapat bergabung kembali."
		)
		log("WARNING", count, player.Name, reason)
	end
end

local function isBanned(userId)
	if banned[userId] then return true end
	local ok, result = pcall(function()
		return BanStore:GetAsync("ban_" .. userId)
	end)
	if ok and result then
		banned[userId] = true
		return true
	end
	return false
end

-- ══════════════════════════════════════════
-- ANTI-EXPLOIT: MONITORING
-- ══════════════════════════════════════════
-- Deteksi script inject / exploit sederhana via sanity check
-- (Roblox Server-side tidak bisa langsung deteksi client exploit,
--  tapi kita bisa deteksi anomali dari behavior)

local function monitorPlayer(player)
	local char = player.Character or player.CharacterAdded:Wait()

	-- Deteksi speed hack (posisi berubah terlalu cepat)
	spawn(function()
		local lastPos  = nil
		local lastTick = tick()
		while player and player.Parent do
			wait(1)
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local pos = hrp.Position
					local dt  = tick() - lastTick
					if lastPos and dt > 0 then
						local speed = (pos - lastPos).Magnitude / dt
						if speed > 120 then  -- threshold speed hack (stud/detik)
							warnPlayer(player, "Terdeteksi speed anomali (kemungkinan exploit)")
							return
						end
					end
					lastPos  = pos
					lastTick = tick()
				end
			end
		end
	end)

	-- Deteksi noclip (menembus dinding) - simplified check
	spawn(function()
		while player and player.Parent do
			wait(3)
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					-- Cek apakah player berada di bawah tanah/baseplate
					if hrp.Position.Y < -500 then
						warnPlayer(player, "Posisi tidak valid (kemungkinan noclip/teleport exploit)")
						return
					end
				end
			end
		end
	end)
end

-- Remote function call rate limiter (anti exploit remotes)
local remoteCalls = {}  -- [userId] = {count, resetTick}
local function checkRateLimit(player)
	local uid = player.UserId
	local now = tick()
	if not remoteCalls[uid] then
		remoteCalls[uid] = {count = 0, resetTick = now + 5}
	end
	if now > remoteCalls[uid].resetTick then
		remoteCalls[uid] = {count = 0, resetTick = now + 5}
	end
	remoteCalls[uid].count = remoteCalls[uid].count + 1
	if remoteCalls[uid].count > 40 then  -- >40 remote call dalam 5 detik = exploit
		warnPlayer(player, "Remote flooding terdeteksi (kemungkinan exploit/inject)")
		return false
	end
	return true
end

-- ══════════════════════════════════════════
-- BADGE SYSTEM
-- ══════════════════════════════════════════
local function awardBadge(player, badgeId)
	if not badgeId or badgeId == 0 then return end
	spawn(function()
		local ok, hasBadge = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if ok and not hasBadge then
			local ok2, err = pcall(function()
				BadgeService:AwardBadge(player.UserId, badgeId)
			end)
			if ok2 then
				log("Badge diberikan:", badgeId, "->", player.Name)
			else
				warn("Gagal beri badge:", err)
			end
		end
	end)
end

local function checkPlaytimeBadges(player)
	local uid      = player.UserId
	local joinTime = joinTimes[uid]
	if not joinTime then return end
	local elapsed = tick() - joinTime  -- detik

	if elapsed >= 5 * 3600 then  -- 5 jam
		awardBadge(player, CFG.Badges.Play5Hrs)
	end
	if elapsed >= 48 * 3600 then -- 48 jam
		awardBadge(player, CFG.Badges.Play48Hrs)
	end
end

local function checkAFK(player)
	local uid = player.UserId
	local afkStart = afkTimers[uid]
	if not afkStart then return end
	local elapsed = tick() - afkStart
	if elapsed >= 24 * 3600 then
		awardBadge(player, CFG.Badges.AFK24Hrs)
	end
end

-- Cek gerakan untuk AFK timer
local function trackMovement(player)
	spawn(function()
		while player and player.Parent do
			wait(5)
			local char = player.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					-- Jika pemain bergerak (MoveDirection bukan zero), reset AFK timer
					if hum.MoveDirection.Magnitude > 0.01 then
						afkTimers[player.UserId] = tick()
					end
					checkAFK(player)
				end
			end
		end
	end)
end

-- ══════════════════════════════════════════
-- FILTER SEDERHANA (server-side validation)
-- ══════════════════════════════════════════
local filterPatterns = {
	racist = {"anjing%s*lo","monyet%s*lo","b[o0]d[o0]h","tol[o0]l","idiot","goblok","negro","nigga","chink"},
	psycho = {"aku%s*akan%s*bunuh","gue%s*bunuh","mati%s*lo","kubunuh","i%s*will%s*kill","die%s*now"},
	force  = {"harus%s*nurut","paksa","kamu%s*harus","you%s*must%s*do"},
	extort = {"bayar%s*atau","kasih%s*robux%s*atau","kasih%s*password","kasih%s*akun","blackmail","peras"},
}

local tagLabels = {
	racist = "⚠ RASIS",
	psycho = "⚠ ANCAMAN",
	force  = "⚠ PAKSAAN",
	extort = "⚠ PEMERASAN",
}

local tagColors = {
	racist = {r=248,g=113,b=113},
	psycho = {r=239,g=68,b=68},
	force  = {r=251,g=191,b=36},
	extort = {r=249,g=115,b=22},
}

local function serverFilter(text)
	local tags = {}
	local lower = text:lower()
	for cat, pats in pairs(filterPatterns) do
		for _, p in ipairs(pats) do
			if lower:match(p) then
				local found = false
				for _, t in ipairs(tags) do
					if t.category == cat then found = true break end
				end
				if not found then
					table.insert(tags, {
						category = cat,
						label    = tagLabels[cat],
						color    = Color3.fromRGB(
							tagColors[cat].r,
							tagColors[cat].g,
							tagColors[cat].b
						),
					})
				end
				break
			end
		end
	end
	return tags
end

-- ══════════════════════════════════════════
-- HANDLE PESAN SERVER CHAT
-- ══════════════════════════════════════════
SendMessage.OnServerEvent:Connect(function(player, text, clientTags)
	if not checkRateLimit(player) then return end

	-- Validasi
	if type(text) ~= "string" then return end
	text = text:sub(1, CFG.MaxMsgLen)
	text = text:match("^%s*(.-)%s*$")
	if text == "" then return end

	-- Cooldown chat
	local uid = player.UserId
	local now = tick()
	if lastChat[uid] and (now - lastChat[uid]) < CFG.ChatCooldown then return end
	lastChat[uid] = now

	-- Filter server-side (lebih aman)
	local tags = serverFilter(text)

	local data = {
		sender      = player.Name,
		displayName = player.DisplayName,
		text        = text,
		tags        = tags,
		timestamp   = timestamp(),
	}

	-- Broadcast ke semua pemain di server
	for _, p in ipairs(Players:GetPlayers()) do
		ReceiveMessage:FireClient(p, data)
	end

	log("[SERVER]", player.DisplayName, ":", text)
end)

-- ══════════════════════════════════════════
-- HANDLE GLOBAL CHAT (MessagingService)
-- ══════════════════════════════════════════
SendGlobal.OnServerEvent:Connect(function(player, text, clientTags)
	if not checkRateLimit(player) then return end

	if type(text) ~= "string" then return end
	text = text:sub(1, CFG.MaxMsgLen)
	text = text:match("^%s*(.-)%s*$")
	if text == "" then return end

	local uid = player.UserId
	local now = tick()
	if lastChat[uid] and (now - lastChat[uid]) < CFG.ChatCooldown then return end
	lastChat[uid] = now

	local tags = serverFilter(text)

	local payload = {
		sender      = player.Name,
		displayName = player.DisplayName,
		text        = text,
		tags        = tags,
		timestamp   = timestamp(),
	}

	-- Publish ke channel global
	local ok, err = pcall(function()
		MessagingService:PublishAsync(CFG.GlobalChannel, HttpService:JSONEncode(payload))
	end)
	if not ok then
		warn("[GlobalChat] Gagal publish:", err)
		-- Fallback: broadcast ke server ini saja
		for _, p in ipairs(Players:GetPlayers()) do
			ReceiveGlobal:FireClient(p, payload)
		end
	end
end)

-- Langganan global chat
local ok, _ = pcall(function()
	MessagingService:SubscribeAsync(CFG.GlobalChannel, function(msg)
		local ok2, data = pcall(function()
			return HttpService:JSONDecode(msg.Data)
		end)
		if not ok2 or type(data) ~= "table" then return end
		-- Broadcast ke semua pemain di server ini
		for _, p in ipairs(Players:GetPlayers()) do
			ReceiveGlobal:FireClient(p, data)
		end
	end)
end)
if not ok then
	warn("[GlobalChat] MessagingService tidak tersedia (hanya di live game, bukan Studio test)")
end

-- ══════════════════════════════════════════
-- ROOM CHAT
-- ══════════════════════════════════════════
CreateRoom.OnServerEvent:Connect(function(player, roomId, roomName)
	if not checkRateLimit(player) then return end
	if type(roomId) ~= "string" or type(roomName) ~= "string" then return end
	roomId   = roomId:sub(1, 20)
	roomName = roomName:sub(1, 40)

	rooms[roomId] = {
		name    = roomName,
		owner   = player.UserId,
		members = {[player.UserId] = true},
	}
	log("Room dibuat:", roomName, "ID:", roomId, "by", player.Name)
end)

InviteToRoom.OnServerEvent:Connect(function(player, targetUserId, roomId, roomName)
	if not checkRateLimit(player) then return end

	-- Validasi room
	if not rooms[roomId] then return end
	if rooms[roomId].owner ~= player.UserId then return end  -- Hanya owner yg bisa invite

	-- Cari target player
	local target = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == targetUserId then
			target = p
			break
		end
	end
	if not target then return end

	ReceiveInvite:FireClient(target, player.DisplayName, roomId, roomName)
	log("Invite dikirim:", player.Name, "->", target.Name, "Room:", roomId)
end)

RespondInvite.OnServerEvent:Connect(function(player, fromDisplayName, roomId, accepted)
	if not checkRateLimit(player) then return end

	-- Cari si pengundang berdasarkan displayName
	local fromPlayer = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p.DisplayName == fromDisplayName then
			fromPlayer = p
			break
		end
	end

	if accepted then
		-- Tambahkan ke room
		if rooms[roomId] then
			rooms[roomId].members[player.UserId] = true
			-- Beritahu semua anggota room
			local memberList = {}
			for uid, _ in pairs(rooms[roomId].members) do
				for _, p in ipairs(Players:GetPlayers()) do
					if p.UserId == uid then
						table.insert(memberList, p.Name)
						break
					end
				end
			end
			for uid, _ in pairs(rooms[roomId].members) do
				for _, p in ipairs(Players:GetPlayers()) do
					if p.UserId == uid then
						RoomUpdated:FireClient(p, roomId, memberList)
					end
				end
			end
		end
	end

	if fromPlayer then
		InviteResponse:FireClient(fromPlayer, player.DisplayName, roomId, accepted)
	end
	log("Invite response:", player.Name, accepted and "TERIMA" or "TOLAK", "Room:", roomId)
end)

SendRoomMsg.OnServerEvent:Connect(function(player, roomId, text, clientTags)
	if not checkRateLimit(player) then return end

	if not rooms[roomId] then return end
	if not rooms[roomId].members[player.UserId] then return end  -- Hanya anggota

	if type(text) ~= "string" then return end
	text = text:sub(1, CFG.MaxMsgLen)
	text = text:match("^%s*(.-)%s*$")
	if text == "" then return end

	local uid = player.UserId
	local now = tick()
	if lastChat[uid] and (now - lastChat[uid]) < CFG.ChatCooldown then return end
	lastChat[uid] = now

	local tags = serverFilter(text)
	local data = {
		roomId      = roomId,
		sender      = player.Name,
		displayName = player.DisplayName,
		text        = text,
		tags        = tags,
		timestamp   = timestamp(),
	}

	-- Broadcast ke anggota room saja
	for uid2, _ in pairs(rooms[roomId].members) do
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == uid2 then
				ReceiveRoomMsg:FireClient(p, data)
				break
			end
		end
	end
end)

-- ══════════════════════════════════════════
-- CLONE AVATAR
-- ══════════════════════════════════════════
CloneAvatar.OnServerEvent:Connect(function(player, targetInput)
	if not checkRateLimit(player) then return end
	if type(targetInput) ~= "string" then return end
	targetInput = targetInput:match("^%s*(.-)%s*$")
	if targetInput == "" then return end

	-- Cari target: bisa Username, DisplayName, atau UserId
	local targetPlayer = nil
	local targetId     = nil

	-- Coba parse sebagai UserId angka
	local numId = tonumber(targetInput)
	if numId then
		targetId = numId
	else
		-- Cari di pemain aktif dulu
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Name:lower() == targetInput:lower() or
			   p.DisplayName:lower() == targetInput:lower() then
				targetId = p.UserId
				break
			end
		end
		-- Jika tidak ketemu, coba lewat API (hanya bisa di production)
		if not targetId then
			local ok, result = pcall(function()
				return Players:GetUserIdFromNameAsync(targetInput)
			end)
			if ok and result then
				targetId = result
			end
		end
	end

	if not targetId then
		-- Tidak ketemu, tidak ada feedback (silent fail)
		return
	end

	-- Terapkan appearance target ke player
	local ok, err = pcall(function()
		local humanoidDesc = Players:GetHumanoidDescriptionFromUserId(targetId)
		if player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:ApplyDescription(humanoidDesc)
			end
		end
	end)
	if not ok then
		warn("[CloneAvatar] Gagal clone:", err)
	else
		log("Avatar cloned:", player.Name, "->", targetId)
	end
end)

-- ══════════════════════════════════════════
-- PLAYER JOIN
-- ══════════════════════════════════════════
local function onPlayerJoin(player)
	local uid = player.UserId

	-- Cek ban
	if isBanned(uid) then
		player:Kick("🚫 Kamu telah di-BAN dari game ini secara permanen.")
		return
	end

	-- Inisialisasi
	warnings[uid]  = 0
	joinTimes[uid] = tick()
	afkTimers[uid] = tick()
	lastChat[uid]  = 0

	-- Load saved playtime
	local savedTime = 0
	safeDS(function()
		savedTime = PlaytimeStore:GetAsync("pt_" .. uid) or 0
	end)

	-- Badge join game
	spawn(function()
		wait(3)  -- Beri waktu load
		awardBadge(player, CFG.Badges.JoinGame)

		-- Cek apakah owner sedang online
		if isOwnerHere then
			awardBadge(player, CFG.Badges.MeetOwner)
		end
	end)

	-- Jika ini adalah owner game
	if uid == CFG.OwnerUserId then
		isOwnerHere = true
		-- Beri badge MeetOwner ke semua pemain yang ada di server
		spawn(function()
			wait(2)
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId ~= uid then
					awardBadge(p, CFG.Badges.MeetOwner)
				end
			end
		end)
	end

	-- Monitor anti-exploit
	spawn(function()
		player.CharacterAdded:Connect(function(char)
			wait(1)
			monitorPlayer(player)
		end)
		if player.Character then
			monitorPlayer(player)
		end
	end)

	-- Track AFK & playtime
	trackMovement(player)

	-- Cek badge playtime berkala (setiap 10 menit)
	spawn(function()
		while player and player.Parent do
			wait(600)
			checkPlaytimeBadges(player)
		end
	end)

	log("Player joined:", player.Name, "(UID:", uid .. ")")
end

-- ══════════════════════════════════════════
-- PLAYER LEAVE
-- ══════════════════════════════════════════
local function onPlayerLeave(player)
	local uid = player.UserId

	-- Simpan playtime
	local elapsed = tick() - (joinTimes[uid] or tick())
	safeDS(function()
		local prev = PlaytimeStore:GetAsync("pt_" .. uid) or 0
		PlaytimeStore:SetAsync("pt_" .. uid, prev + elapsed)
	end)

	-- Cek badge playtime saat keluar
	checkPlaytimeBadges(player)
	checkAFK(player)

	-- Hapus dari semua room
	for rid, room in pairs(rooms) do
		if room.members[uid] then
			room.members[uid] = nil
			-- Jika owner pergi, hapus room
			if room.owner == uid then
				rooms[rid] = nil
			end
		end
	end

	-- Bersihkan state
	warnings[uid]   = nil
	joinTimes[uid]  = nil
	afkTimers[uid]  = nil
	lastChat[uid]   = nil
	remoteCalls[uid] = nil

	if uid == CFG.OwnerUserId then
		isOwnerHere = false
	end

	log("Player left:", player.Name)
end

-- ══════════════════════════════════════════
-- KONEKSI EVENT
-- ══════════════════════════════════════════
Players.PlayerAdded:Connect(onPlayerJoin)
Players.PlayerRemoving:Connect(onPlayerLeave)

-- Handle pemain yang sudah ada saat script jalan
for _, player in ipairs(Players:GetPlayers()) do
	spawn(function()
		onPlayerJoin(player)
	end)
end

-- ══════════════════════════════════════════
-- BADGE TIMER LOOP (cek setiap jam)
-- ══════════════════════════════════════════
spawn(function()
	while true do
		wait(3600)  -- setiap jam
		for _, player in ipairs(Players:GetPlayers()) do
			checkPlaytimeBadges(player)
			checkAFK(player)
		end
	end
end)

log("=== Custom Chat Server aktif ===")
log("Global Chat Channel:", CFG.GlobalChannel)
log("Max Warnings sebelum ban:", CFG.MaxWarnings)
