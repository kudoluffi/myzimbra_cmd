# 📧 Zimbra DKIM Setup Script

**Version:** 1.6  
**Last Updated:** 2026  
**Compatibility:** Ubuntu 22.04 LTS + Zimbra 10.1.x OSE/NE

---

## 📋 Deskripsi

Script `zimbra-dkim-setup.sh` adalah automation tool untuk mengkonfigurasi **DKIM (DomainKeys Identified Mail)** pada server Zimbra Collaboration Suite. Script ini menangani generation DKIM keys, extraction public key untuk DNS, dan menyediakan panduan lengkap untuk setup SPF, DKIM, dan DMARC.

DKIM adalah metode email authentication yang menambahkan tanda tangan digital pada email outgoing, sehingga receiver dapat memverifikasi bahwa email benar-benar dikirim dari domain Anda dan tidak dimodifikasi di tengah jalan.

---

## ✨ Fitur Utama

| Fitur | Deskripsi |
|-------|-----------|
| **Custom Selector** | Support custom DKIM selector (contoh: `mail`, `nmail`, dll) |
| **Auto Detection** | Deteksi DKIM keys yang sudah ada |
| **Safe Override** | Opsi untuk keep/remove/regenerate existing keys |
| **DNS Records Generator** | Generate SPF, DKIM, DMARC records siap copy |
| **External Verification** | Panduan verifikasi dengan MXToolbox, Gmail, dll |
| **LDAP Storage** | Keys disimpan di LDAP Zimbra (tidak ada file .txt) |
| **Logging** | Semua proses tercatat di `/tmp/dkim_setup.log` |

---

## 📥 Instalasi

### 1. Download Script
```bash
wget https://raw.githubusercontent.com/kudoluffi/zimbra-scripts/main/scripts/zimbra-dkim-setup.sh
chmod +x zimbra-dkim-setup.sh
```

### 2. Prasyarat
Sebelum menjalankan script, pastikan:
* ✅ Zimbra sudah terinstall & berjalan normal
* ✅ Domain sudah memiliki A record yang mengarah ke IP server
* ✅ Anda memiliki akses ke DNS provider (Cloudflare, Namecheap, dll)
* ✅ Script dijalankan sebagai root

## 3. Jalankan Script
```bash
sudo ./zimbra-dkim-setup.sh
```

### 4. Input Konfigurasi
Script akan meminta 2 informasi:
```bash
Masukkan domain email (contoh: newbienotes.my.id): newbienotes.my.id
Masukkan selector DKIM (contoh: mail, default: mail): nmail
```
| Parameter | Deskripsi | Wajib? | Default |
|-----------|-----------|--------|---------|
| Domain | Domain email utama Anda | ✅ Ya | - |
| Selector | Nama selector DKIM (bebas) | ❌ Opsional | mail |

---

## 🔧 Cara Kerja Script
**Flow Proses**
```
1. Query DKIM keys yang sudah ada di Zimbra
2. Jika ada existing keys:
   - Tampilkan selector yang ada
   - Tawarkan opsi: Keep / Remove & Regenerate / Cancel
3. Generate DKIM keys dengan selector yang ditentukan
4. Query public key dari LDAP Zimbra
5. Tampilkan DNS records (SPF, DKIM, DMARC) siap copy
6. Berikan panduan verifikasi dengan external tools
```
**DNS Records yang Dihasilkan**
| Record | Host/Name | Type | Value |
|--------|-----------|------|-------|
| SPF | @ (atau domain) | TXT | v=spf1 mx ip4:<IP_SERVER> -all |
| DKIM | <selector>._domainkey | TXT | v=DKIM1; k=rsa; p=<PUBLIC_KEY> |
| DMARC | _dmarc | TXT | v=DMARC1; p=quarantine; rua=mailto:dmarc@<domain>; pct=100 |

---

## ✅ Verifikasi Setelah Setup
1. Tambahkan DNS Records
   Copy DNS records dari output script ke DNS provider Anda (Cloudflare, Namecheap, dll).
2. Tunggu DNS Propagate
   * Minimum: 5 menit
   * Rata-rata: 15-30 menit
   * Maksimal: 24-48 jam (jarang)
3. Verifikasi dengan External Tools
**DKIM Checker**
```
URL: https://mxtoolbox.com/dkim.aspx
Input: nmail._domainkey.newbienotes.my.id
Expected: ✅ Valid DKIM record found
```
**SPF Checker**
```
URL: https://mxtoolbox.com/spf.aspx
Input: newbienotes.my.id
Expected: ✅ Valid SPF record found
```
**DMARC Checker**
```
URL: https://mxtoolbox.com/dmarc.aspx
Input: newbienotes.my.id
Expected: ✅ Valid DMARC record found
```
**Mail Server Tester (All-in-One)**
```
URL: https://www.mail-tester.com/
1. Buka website, dapatkan email address unik
2. Kirim email dari server Zimbra ke address tersebut
3. Check score (target: 10/10)
```
**Gmail Test (Manual)**
```
1. Kirim email dari user@newbienotes.my.id ke gmail.com
2. Di Gmail, buka email → klik ⋮ (3 titik) → "Show original"
3. Cari baris:
   - PASS: SPF dengan IP <IP_SERVER>
   - PASS: DKIM signature verified
   - PASS: DMARC verified
```

---

## 🛡️ Best Practice
### 1. Selector Naming
| Nama Selector | Keterangan | 
|---------------|------------|
| mail | Standard, mudah diingat | 
| zimbra | Eksplisit |
| 202604 | Date-based (untuk rotation) |

Rekomendasi: Gunakan nama yang mudah diingat dan konsisten.

### 2. DMARC Policy Progression
Mulai dengan policy ringan, naikkan secara bertahap:
| Tahap | Policy | Keterangan |
|-------|--------|------------|
| 1 | p=none | Monitoring only (tidak ada action) |
| 2 | p=quarantine | Email gagal masuk spam folder |
| 3 | p=reject | Email gagal ditolak (production) |

Rekomendasi: Mulai dengan p=quarantine, setelah 2-4 minggu tanpa issue, upgrade ke p=reject.

### 3. SPF Record Best Practice
```
# Basic (hanya server sendiri)
v=spf1 mx ip4:<IP_SERVER> -all

# Dengan include (jika pakai third-party)
v=spf1 mx ip4:<IP_SERVER> include:_spf.google.com -all

# Strict mode (recommended untuk production)
v=spf1 mx ip4:<IP_SERVER> -all
```
Catatan: -all = hard fail (email dari IP lain ditolak), ~all = soft fail (masuk spam).

---

## 🔗 Referensi
* [Zimbra DKIM Documentation](https://wiki.zimbra.com/wiki/Configuring_DKIM?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [DKIM.org](https://wiki.zimbra.com/wiki/Configuring_DKIM?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [MXToolbox DKIM Check](https://mxtoolbox.com/dkim.aspx?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [DMARC.org](https://dmarc.org/?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [Mail-Tester.com](https://www.mail-tester.com/?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
