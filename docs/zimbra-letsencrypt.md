# 🔒 Zimbra Let's Encrypt Script

**Version:** 1.3.8  
**Last Updated:** 2026  
**Compatibility:** Ubuntu 22.04 LTS + Zimbra 10.1.x OSE/NE

---

## 📋 Deskripsi

Script `zimbra-letsencrypt.sh` adalah automation tool untuk menerbitkan, deploy, dan auto-renewal SSL certificate dari **Let's Encrypt** pada server Zimbra Collaboration Suite. Script ini menangani seluruh proses kompleks termasuk stop/start service, verifikasi domain, konversi format certificate, deployment ke semua layanan Zimbra, dan konfigurasi auto-renewal dengan custom cron job.

---

## ✨ Fitur Utama

| Fitur | Deskripsi |
|-------|-----------|
| **Auto Issue** | Request SSL certificate dari Let's Encrypt secara otomatis |
| **Standalone Mode** | Verifikasi via HTTP-01 challenge (port 80) |
| **Auto Deploy** | Deploy certificate ke semua layanan Zimbra (nginx, postfix, dovecot, ldap) |
| **Auto Renewal** | Custom cron job mingguan untuk renew certificate sebelum expired |
| **Certbot Timer Disable** | Otomatis disable `certbot.timer` bawaan untuk menghindari konflik |
| **Email Optional** | Tidak wajib input email untuk ACME account |
| **Root CA Included** | Otomatis tambahkan Root CA ISRG X1 untuk validasi Zimbra |
| **Dual Directory** | Copy certificate ke 2 lokasi (letsencrypt + zimbra/commercial) |
| **Logging** | Semua proses tercatat di log file untuk troubleshooting |

---

## 📥 Instalasi

### 1. Download Script
```bash
wget https://raw.githubusercontent.com/kudoluffi/zimbra-scripts/main/scripts/zimbra-letsencrypt.sh
chmod +x zimbra-letsencrypt.sh
```
### 2. Prasyarat Wajib
Sebelum menjalankan script, pastikan:
* ✅ Zimbra sudah terinstall & berjalan normal
* ✅ FQDN sudah memiliki A Record yang mengarah ke IP publik server
* ✅ Port 80 & 443 terbuka dari internet (untuk HTTP challenge)
* ✅ Script dijalankan sebagai root

### 3. Jalankan Script
```bash
sudo ./zimbra-letsencrypt.sh
```

### 4. Input Konfigurasi
Script akan meminta 2 informasi:
```bash
FQDN Zimbra (contoh: mail.example.com): mail.example.com
Email ACME recovery (opsional, tekan Enter untuk skip): admin@example.com
```
| Parameter | Deskripsi | Wajib? |
|-----------|-----------|--------|
| FQDN | Hostname lengkap Zimbra (harus sama dengan A record) | ✅ Ya |
| Email | Email untuk recovery ACME account | ❌ Opsional |
---

## 🔧 Cara Kerja Script
### Flow Proses
```
1. Install Certbot (jika belum ada)
2. Disable certbot.timer bawaan (untuk menghindari konflik)
3. Stop Zimbra web services (zmproxy, zmmailboxd)
4. Request certificate dari Let's Encrypt via port 80
5. Copy certificate ke /opt/zimbra/ssl/letsencrypt/ dan /opt/zimbra/ssl/zimbra/commercial/
6. Tambahkan Root CA ISRG X1 ke commercial_ca.crt
7. Verify certificate dengan zmcertmgr
8. Deploy certificate ke semua layanan Zimbra
9. Restart Zimbra services
10. Setup custom cron job untuk auto-renewal (Senin 03:00)
```

### File yang Dimodifikasi
| File | Perubahan |
|------|-----------|
| ```/opt/zimbra/ssl/letsencrypt/commercial.crt``` | Fullchain certificate (Leaf + Intermediate) |
| ```/opt/zimbra/ssl/letsencrypt/commercial.key``` | Private key |
| ```/opt/zimbra/ssl/letsencrypt/commercial_ca.crt``` | CA Bundle (Intermediate + Root ISRG X1) |
| ```/etc/cron.d/zimbra-le-renew``` | Cron job auto-renewal mingguan |
| ```/usr/local/bin/zimbra-le-renew.sh``` | Script renewal otomatis |
| ```/etc/systemd/system/certbot.timer``` | Disabled (oleh script) |
---

## ✅ Verifikasi Setelah Instalasi
### 1. Cek Certificate yang Terdeploy
```
sudo su - zimbra -c "/opt/zimbra/bin/zmcertmgr viewdeployedcrt"
```
Output yang diharapkan:
```
*** Certificate '/opt/zimbra/ssl/zimbra/commercial/commercial.crt' properties
  Subject: CN=mail.example.com
  Issuer: C=US, O=Let's Encrypt, CN=R12
  Validity: Not Before: Apr 18 00:00:00 2026 GMT
            Not After: Jul 18 00:00:00 2026 GMT
```
### 2. Cek via Browser
1. Buka https://mail.example.com
2. Klik icon gembok di address bar
3. Pilih Certificate is valid
4. Verifikasi:
   * ✅ Issued to: mail.example.com
   * ✅ Issued by: Let's Encrypt R12
   * ✅ Valid until: (tanggal 90 hari dari sekarang)

### 3. Cek via OpenSSL
```bash
echo | openssl s_client -connect nmail.newbienotes.my.id:443 -servername nmail.newbienotes.my.id 2>/dev/null | openssl x509 -noout -dates
```
Output:
```bash
notBefore=Apr 16 00:00:00 2026 GMT
notAfter=Jul 16 00:00:00 2026 GMT
```

### 4. Cek Auto-Renewal Cron
```bash
cat /etc/cron.d/zimbra-le-renew
```
Output:
```bash
0 3 * * 1 root /usr/local/bin/zimbra-le-renew.sh nmail.newbienotes.my.id >> /var/log/zimbra-le-renew.log 2>&1
```
### 5. Cek Certbot Timer (Harus Inactive)
```
systemctl status certbot.timer
```
Output yang diharapkan:
```bash
● certbot.timer - Run certbot twice daily
     Loaded: loaded (/lib/systemd/system/certbot.timer; enabled; vendor preset: enabled)
     Active: inactive (dead)
```

### 6. Test Manual Renewal
```bash
sudo bash /usr/local/bin/zimbra-le-renew.sh nmail.newbienotes.my.id
```

## 🔄 Auto-Renewal Mechanism
Mengapa Custom Cron (Bukan Certbot Timer)?
| Aspek | Certbot Timer Bawaan | Custom Cron (Script) | 
|-------|----------------------|----------------------|
| Frekuensi | 2x sehari | 1x seminggu (Senin 03:00) |
| Renew Certificate | ✅ Ya | ✅ Ya |
| Copy ke Zimbra | ❌ TIDAK | ✅ Ya |
| Append Root CA | ❌ TIDAK | ✅ Ya |
| Deploy via zmcertmgr | ❌ TIDAK | ✅ Ya |
| Restart Zimbra | ❌ TIDAK | ✅ Ya |

**Kesimpulan**: Certbot timer bawaan hanya renew certificate di /etc/letsencrypt/, tapi tidak deploy ke Zimbra. Script ini menggunakan custom cron untuk handle full workflow.

**Script Otomatis Disable Certbot Timer**
Saat menjalankan ```zimbra-letsencrypt.sh```, script akan otomatis:
```bash
systemctl disable --now certbot.timer
```
Ini memastikan tidak ada konflik antara Certbot timer bawaan dan custom cron.

**Timeline Renewal yang Aman**
| Hari | Status Certificate | Action |
|------|--------------------|--------|
| Day 1 | Cert issued (valid 90 hari) | - |
| Day 60 | Cert masih valid (30 hari lagi) | Certbot mulai bisa renew |
| Day 63-70 | Custom cron weekly check | ✅ Renew & deploy otomatis |
| Day 90 | Cert expired (jika gagal renew) | ❌ Hindari dengan monitoring |

Dengan custom cron 1x minggu, Anda punya minimal 4x kesempatan renew sebelum expired. Sangat aman!

## 🔗 Referensi
* [Zimbra Certificate Management](https://wiki.zimbra.com/wiki/Working_with_Certificates?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [Let's Encrypt Documentation](https://letsencrypt.org/docs/?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [Certbot User Guide](https://eff-certbot.readthedocs.io/?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)
* [ACME Protocol](https://github.com/ietf-wg-acme/acme?spm=a2ty_o01.29997173.0.0.48ea55fba8kSFe)

