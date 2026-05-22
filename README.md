# 🎮 Custom Chat System - Roblox Studio
## Dokumentasi Lengkap Setup & Penggunaan

---

## 📁 STRUKTUR FILE

```
3 File yang perlu dibuat:

1. ChatModule.lua       → ModuleScript
2. ChatLocalScript.lua  → LocalScript  
3. ChatServer.lua       → Script (Server)
```

---

## 📌 CARA INSTALL DI ROBLOX STUDIO

### Step 1 — ChatModule (ModuleScript)
```
Explorer:
└── StarterPlayer
    └── StarterPlayerScripts
        └── ChatModule  ← Buat ModuleScript, paste isi ChatModule.lua
```

### Step 2 — ChatLocalScript (LocalScript)
```
Explorer:
└── StarterPlayer
    └── StarterPlayerScripts
        └── ChatLocalScript  ← Buat LocalScript, paste isi ChatLocalScript.lua
```

### Step 3 — ChatServer (Script biasa/Server Script)
```
Explorer:
└── ServerScriptService
    └── ChatServer  ← Buat Script, paste isi ChatServer.lua
```

---

## ⚙️ KONFIGURASI WAJIB

### Di ChatServer.lua, ubah bagian CFG:

```lua
local CFG = {
    OwnerUserId = 1234567890,  -- ← GANTI dengan UserID Roblox kamu
                               --   Cara cari: buka profile Roblox, lihat URL

    Badges = {
        JoinGame  = 111111111, -- ← ID Badge "Bergabung"
        Play5Hrs  = 222222222, -- ← ID Badge "Main 5 Jam"
        AFK24Hrs  = 333333333, -- ← ID Badge "AFK 24 Jam"
        Play48Hrs = 444444444, -- ← ID Badge "Main 48 Jam Non-stop"
        MeetOwner = 555555555, -- ← ID Badge "Bertemu Pemilik"
    },
}
```

### Di ChatModule.lua, ubah juga bagian yang sama (untuk konsistensi)

---

## 🏅 CARA BUAT BADGE DI ROBLOX

1. Buka game kamu di Roblox Studio
2. Klik **File → Game Settings → Monetization**  
   atau buka **Creator Dashboard** → pilih game → **Badges**
3. Klik **Create Badge**, upload gambar, beri nama
4. Setelah dibuat, klik badge → lihat URL: `.../badges/XXXXXXXX`
5. Angka `XXXXXXXX` = **Badge ID** → masukkan ke `CFG.Badges`

---

## 🎛️ FITUR LENGKAP

### 💬 Chat System
| Fitur | Keterangan |
|-------|-----------|
| Server Chat | Chat sesama player di 1 server |
| Global Chat | Chat ke SEMUA server game kamu (via MessagingService) |
| Room Chat | Chat private dengan player yang diundang |
| Bubble Chat | Muncul di atas kepala, desain mirip Roblox |
| Filter Tag | Menandai teks rasis/ancaman/paksaan/pemerasan (teks asli tidak diubah) |
| Timestamp | Waktu pesan ditampilkan |
| Notifikasi | Badge merah di tombol chat jika ada pesan baru |

### 🚪 Room System
| Fitur | Keterangan |
|-------|-----------|
| /create-room [nama] | Buat room private, panel melayang muncul otomatis |
| /create-room | (tanpa nama) → otomatis pakai DisplayName + "Room Chat" |
| Invite Player | Cari player by DisplayName/Username, tombol jadi "Menunggu..." |
| Terima/Tolak | Player yang diundang dapat notifikasi dengan tombol |
| Panel Bisa Digeser | Drag & drop panel room ke mana saja |

### ⚙️ Settings
| Kategori | Fitur |
|----------|-------|
| User Settings | Toggle tampilkan chat sendiri |
| User Settings | Atur siapa yang bisa invite |
| User Settings | Sembunyikan player lain (hanya tampilan lokal) |
| User Settings | Clone avatar dari Username/ID/DisplayName player lain |
| Room Settings | Lihat list anggota room |
| Room Settings | Invite player ke room |
| Room Settings | Hapus room |
| Room Settings | Tampilkan Room ID |

### 🛡️ Anti-Exploit
| Proteksi | Cara Kerja |
|----------|-----------|
| Speed Hack | Deteksi pergerakan > 120 stud/detik |
| Noclip | Deteksi posisi di bawah map |
| Remote Flooding | Deteksi > 40 remote call dalam 5 detik |
| Warning System | 3 kali peringatan → auto BAN permanen |
| Ban Datastore | Ban tersimpan permanen via DataStore |
| Chat Cooldown | Minimal 0.8 detik antar pesan |

### 🏅 Badge Otomatis
| Badge | Syarat |
|-------|--------|
| Bergabung | Setiap kali player join (pertama kali) |
| Main 5 Jam | Akumulasi playtime 5 jam |
| AFK 24 Jam | AFK (tidak gerak) selama 24 jam nonstop |
| Main 48 Jam | Playtime 48 jam nonstop tanpa keluar |
| Bertemu Pemilik | Player join saat Owner (kamu) sedang online |

---

## 🎨 TAMPILAN UI

```
Layar kiri bawah:
┌─────────────────────────────────────────┐
│  [💬] ← Tombol Chat (dekat voice chat)  │
│  [⚙]  ← Tombol Settings                │
└─────────────────────────────────────────┘

Panel Chat (360×520px):
┌────────────────────────────────────────┐
│  ✦ CHAT                           [✕] │  ← Header gradient ungu
├──────┬──────┬──────────────────────────┤
│ SVR  │ GLOBAL │ ROOM │                 │  ← Mode selector
├────────────────────────────────────────┤
│                                        │
│  [SVR] PlayerA  12:34                 │
│  ┌─────────────────────────┐          │
│  │ Halo semuanya!          │          │
│  └─────────────────────────┘          │
│                                        │
│  [GLOBAL] PlayerB  12:35              │
│  ┌─────────────────────────┐          │
│  │ Pesan global dari server│          │
│  │ lain                    │          │
│  │ ⚠ ANCAMAN               │  ← Tag  │
│  └─────────────────────────┘          │
│                                        │
├────────────────────────────────────────┤
│  [Tulis pesan...          ] [▶]       │  ← Input bar
└────────────────────────────────────────┘
```

---

## ❓ TROUBLESHOOTING

**Q: Global Chat tidak berfungsi di Studio?**  
A: Normal! MessagingService hanya aktif di live game (bukan Studio test). Di Studio akan fallback ke server chat biasa.

**Q: Badge tidak diberikan?**  
A: Pastikan Badge ID sudah benar dan game sudah di-publish. Badge tidak bisa diberikan di game yang belum publish.

**Q: Clone Avatar tidak bekerja?**  
A: Pastikan game sudah publish dan `HttpService` tidak diblokir. Fitur ini butuh koneksi ke Roblox API.

**Q: Anti-exploit terlalu sensitif?**  
A: Ubah threshold di `ChatServer.lua`:  
```lua
if speed > 120 then  -- Naikkan angkanya jika terlalu sensitif
```

**Q: Error "ChatRemotes tidak ditemukan"?**  
A: Pastikan `ChatServer.lua` ada di `ServerScriptService` dan sudah jalan sebelum LocalScript.

---

## 📝 CATATAN PENTING

- **Roblox Studio Lite**: Semua kode menggunakan `spawn()` dan `wait()` (bukan `task.*`) untuk kompatibilitas maksimal
- **Tidak perlu rbxassets**: Semua UI dibuat manual dengan Instance, tidak ada asset eksternal
- **Semua umur**: Tidak ada verifikasi umur di sistem chat ini
- **Teks asli tidak diubah**: Filter hanya menambahkan label tag, teks asli tetap tampil
- **DataStore**: Playtime dan ban tersimpan permanen

---

*Custom Chat System v1.0 | Dibuat untuk Roblox Studio*
