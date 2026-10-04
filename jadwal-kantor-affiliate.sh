#!/usr/bin/env bash
# Memasang jadwal harian 8 agen + protokol keputusan lewat Telegram.
# Jalankan SETELAH setup-kantor-affiliate.sh dan setelah gateway Telegram kepala-staf diuji.
#
# Contoh:
#   export TG_CHAT=-1001234567890        # id grup Telegram (dengan -100 di depan)
#   export TG_TH_PERSETUJUAN=17          # id topik "Persetujuan"
#   export TG_TH_DISKUSI=18              # id topik "Diskusi"
#   export TG_TH_LAPORAN=19              # id topik "Laporan"
#   bash jadwal-kantor-affiliate.sh
#
# Jika TG_CHAT kosong, pesan dikirim ke home channel Telegram bawaan (obrolan pribadi dengan bot).
# Skrip ini hanya boleh dijalankan sekali (ada penanda agar jadwal tidak ganda).
set -euo pipefail

command -v hermes >/dev/null || { echo "Hermes tidak ditemukan di PATH"; exit 1; }

OFFICE="${OFFICE:-$HOME/kantor-affiliate}"
KB="$OFFICE/kb"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
MARK="$OFFICE/.jadwal-terpasang"
POSTS="${POSTS_PER_DAY:-2}"   # jumlah postingan carousel per hari (tiap postingan 5-7 produk)

[ -d "$KB" ] || { echo "Folder $KB belum ada. Jalankan setup-kantor-affiliate.sh dulu."; exit 1; }
[ ! -f "$MARK" ] || { echo "Jadwal sudah pernah dipasang ($MARK). Hapus penanda hanya jika Anda sudah menghapus jadwal lama (hermes cron list / remove)."; exit 1; }

tgt() {
  if [ -n "${TG_CHAT:-}" ] && [ -n "${1:-}" ]; then echo "telegram:${TG_CHAT}:${1}"
  elif [ -n "${TG_CHAT:-}" ]; then echo "telegram:${TG_CHAT}"
  else echo "telegram"; fi
}
T_SETUJU="$(tgt "${TG_TH_PERSETUJUAN:-}")"
T_DISKUSI="$(tgt "${TG_TH_DISKUSI:-}")"
T_LAPORAN="$(tgt "${TG_TH_LAPORAN:-}")"

# job <profil> <jadwal-cron> <deliver> <prompt>
job() { hermes -p "$1" cron create "$2" "$4" --deliver "$3"; }

# ---------- Protokol keputusan Telegram (dibaca kepala-staf) ----------
cat > "$KB/antrian-persetujuan/protokol-telegram.md" <<'EOF'
# Protokol keputusan lewat Telegram
Pesan persetujuan dikirim per postingan (carousel) dengan nomor urut. User membalas dengan SATU perintah per baris:
- SETUJU 1 HOOK B   -> postingan 1 disetujui dengan hook pilihan B
- SETUJU 1 3        -> postingan 1 dan 3 disetujui (hook pertama/A jika tidak disebut)
- GANTI 2 KARTU 4: <catatan> -> ganti satu kartu dalam postingan 2
- REVISI 2: <catatan>  -> kembalikan ke konten-copy/konten-visual dengan catatan
- TOLAK 4        -> buang produk (alasan opsional)
- TUNDA 5        -> simpan untuk besok

Aturan tegas:
1. Hanya kata SETUJU yang eksplisit dari user yang berarti disetujui. Diam, emoji, "ok", atau "mantap" BUKAN persetujuan; tanyakan ulang.
2. Catat setiap keputusan di kb/antrian-persetujuan/keputusan-TANGGAL.md (nomor, status, catatan, jam).
3. Hanya paket berstatus SETUJU yang boleh diproses agen distribusi.
4. Di topik Diskusi, user boleh bertanya atau menawar ide; kepala-staf menjawab, tapi diskusi tidak mengubah status paket tanpa perintah di atas.
5. Jangan pernah meminta atau menampilkan password/token/API key di Telegram.
EOF

[ -f "$KB/laporan/data-input.md" ] || cat > "$KB/laporan/data-input.md" <<'EOF'
# Data performa (diisi user tiap hari sebelum 16:00)
Format per baris: tanggal | platform | nomor link | klik | pesanan | komisi (Rp)
EOF

# Tambahkan protokol ke SOUL kepala-staf (sekali saja)
SOUL="$HERMES_HOME/profiles/kepala-staf/SOUL.md"
if [ -f "$SOUL" ] && ! grep -q "## Protokol Telegram" "$SOUL"; then
  cat >> "$SOUL" <<EOF

## Protokol Telegram
Kamu satu-satunya agen yang berbicara dengan user lewat Telegram. Ikuti $KB/antrian-persetujuan/protokol-telegram.md.
Topik: Persetujuan (paket siap putus), Diskusi (tanya jawab dan ide), Laporan (ringkasan harian).
Pesan ke user singkat, bahasa Indonesia, satu postingan per pesan beserta nomor, tema, 3 pilihan hook, daftar 5-7 item (nama, harga dengan tanggal cek, status izin foto), pratinjau caption, dan hasil QA.
EOF
  echo "Protokol ditambahkan ke SOUL kepala-staf."
fi

# ---------- Jadwal harian (zona waktu mengikuti VPS; atur ke WITA: Asia/Makassar) ----------
D='Gunakan tanggal hari ini (format YYYYMMDD) pada nama file.'

job kepala-staf "0 8 * * *" "$T_DISKUSI" \
"Brief pagi. Baca laporan analitik terbaru di $KB/laporan/ dan keputusan kemarin di $KB/antrian-persetujuan/. Tulis brief harian (fokus kategori pria/wanita/couple yang diulang atau dihentikan, target $POSTS postingan carousel lolos QA) ke $KB/laporan/brief-TANGGAL.md. $D Kirim ringkasan maksimal 8 baris."

job riset-tren "30 8 * * *" "local" \
"Baca $KB/laporan/ (brief terbaru) lalu riset tren fashion pria, wanita, dan couple. Simpan kandidat berikut alasan, sumber, dan tanggal ke $KB/produk/tren-TANGGAL.md. $D Jangan menyebut viral tanpa bukti."

job riset-produk "0 10 * * *" "local" \
"Baca $KB/produk/tren-TANGGAL.md hari ini. Nilai komisi, harga, rating, reputasi penjual, tautan foto produk, kategori, dan status izin foto. Simpan shortlist 16-20 produk ke $KB/produk/shortlist-TANGGAL.md, dikelompokkan per tema carousel (tiap tema 5-7 produk, beri nama tema; kebutuhan hari ini: $POSTS tema ditambah cadangan). $D Setiap angka wajib berisi sumber dan tanggal cek; tulis 'belum terverifikasi' jika tidak ada sumber."

job konten-copy "0 11 * * *" "local" \
"Baca $KB/produk/shortlist-TANGGAL.md, $KB/format-mixmatch.md, dan $KB/brand.md. Buat $POSTS postingan carousel, satu per tema. Tiap postingan: 3 pilihan hook cover (A/B/C) yang menjanjikan jumlah kartu yang benar-benar ada, 5-7 kartu (tiap kartu: nama item, teks label Atasan/Bawahan + harga), caption berisi daftar item, versi Pinterest, label afiliasi. Simpan satu file per postingan: $KB/konten/paket-TANGGAL-NN.md. $D Klaim hanya dari data analis produk."

job konten-visual "30 12 * * *" "local" \
"Untuk tiap $KB/konten/paket-TANGGAL-NN.md hari ini, tulis brief visual untuk cover dan SETIAP kartu (5-7 foto per postingan) serta prompt gambar mengikuti $KB/format-mixmatch.md bagian Sumber foto. Tambahkan ke file paket yang sama pada bagian 'Visual'. $D Foto AI wajib sesuai produk asli dan diberi keterangan ilustrasi AI."

job qa "0 14 * * *" "local" \
"Periksa semua postingan hari ini di $KB/konten/, termasuk setiap kartunya (jumlah kartu 5-7, hook sesuai isi, tema seragam). Untuk tiap postingan putuskan LOLOS atau TOLAK dengan alasan (sebut nomor kartu yang bermasalah; klaim, label afiliasi, aturan platform di $KB/aturan-platform/aturan.md, orisinalitas, hak foto, kesesuaian foto AI). Salin paket LOLOS ke $KB/antrian-persetujuan/. Simpan ringkasan ke $KB/laporan/qa-TANGGAL.md. $D Tolak maksimal 2 kali per postingan; kartu bermasalah diganti dari cadangan shortlist."

job kepala-staf "0 15 * * *" "$T_SETUJU" \
"Kirim postingan yang lolos QA hari ini dari $KB/antrian-persetujuan/ ke user, satu pesan per postingan dengan nomor urut: tema, 3 pilihan hook cover (A/B/C), daftar 5-7 item (nama, harga dengan tanggal cek, status izin foto), pratinjau caption. Ikuti $KB/antrian-persetujuan/protokol-telegram.md. Akhiri dengan format balasan (SETUJU/REVISI/TOLAK/TUNDA). Jangan menandai apa pun disetujui sebelum user membalas. $D"

job distribusi "30 15 * * *" "local" \
"Baca $KB/antrian-persetujuan/keputusan-TANGGAL.md. Untuk postingan berstatus SETUJU (dengan hook yang dipilih user): beri nomor link baru untuk SETIAP kartu, catat di $KB/konten/link-log.md, dan susun jadwal posting jam ramai ke $KB/konten/jadwal-TANGGAL.md. Jika berkas keputusan tidak ada atau kosong, tulis 'belum ada persetujuan' dan berhenti. $D Jangan menerbitkan apa pun ke platform."

job analitik "0 16 * * *" "local" \
"Baca data performa yang dimasukkan user di $KB/laporan/data-input.md (jika kosong, tulis 'data belum diisi' dan berhenti). Susun laporan harian: produk dan konten yang menghasilkan atau rugi, rekomendasi ulang/hentikan. Simpan ke $KB/laporan/analitik-TANGGAL.md. $D Jangan memperkirakan angka yang tidak ada datanya."

job kepala-staf "15 16 * * *" "$T_LAPORAN" \
"Baca $KB/laporan/analitik-TANGGAL.md dan keputusan hari ini. Kirim ringkasan akhir hari (maksimal 8 baris): jumlah postingan lolos QA, disetujui, ditolak, dijadwalkan, dan satu rekomendasi untuk besok. $D"

touch "$MARK"
echo
echo "Jadwal terpasang. Cek dengan:  hermes -p <profil> cron list"
echo "Uji satu tugas sekarang:        hermes -p riset-tren cron run <job_id>"
echo "Hentikan sementara:             hermes -p <profil> cron pause <job_id>"
