# 📜 Zimbra Pre-Install Script

**Version:** 14.7  
**Last Updated:** 2026  
**Compatibility:** Ubuntu 22.04 LTS + Zimbra 10.1.x OSE/NE

---

## 📋 Deskripsi

Script `zimbra_preinstall.sh` adalah automation tool untuk mempersiapkan server Ubuntu 22.04 sebelum instalasi Zimbra Collaboration Suite. Script ini menangani konfigurasi sistem yang kompleks dan rawan error jika dilakukan manual, sehingga instalasi Zimbra dapat berjalan lancar tanpa hambatan DNS, firewall, atau dependency.

---

## ✨ Fitur Utama

| Fitur | Deskripsi |
|-------|-----------|
| **Auto Dependencies** | Install semua package yang dibutuhkan Zimbra |
| **Split-DNS (dnsmasq)** | DNS lokal dengan MX record otomatis untuk server internal/NAT |
| **Firewall (UFW)** | Rule otomatis untuk port Zimbra (25,80,443,587,993,995,7071) |
| **Fail2Ban** | Proteksi brute-force untuk Webmail, IMAP, POP3, SMTP |
| **Time Sync** | Chrony/systemd-timesyncd untuk sinkronisasi waktu akurat |
| **Sysctl Tuning** | Optimasi kernel untuk performa mail server |
| **systemd-resolved Fix** | Disable konflik DNS resolver bawaan Ubuntu |
| **MX Record Auto** | Otomatis generate MX record untuk domain |

---

## 📥 Instalasi

### 1. Download Script
```bash
wget https://raw.githubusercontent.com/kudoluffi/zimbra-scripts/main/scripts/zimbra_preinstall.sh
chmod +x zimbra_preinstall.sh

