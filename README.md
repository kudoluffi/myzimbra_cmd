# 🐧 Zimbra Automation Scripts

Kumpulan script otomatisasi untuk instalasi, konfigurasi, dan maintenance **Zimbra Collaboration Suite** (OSE & Network Edition). Script ini dirancang untuk memudahkan deployment server email production-ready dengan keamanan dan best practice yang terintegrasi.

![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-orange?style=flat-square&logo=ubuntu)
![Zimbra](https://img.shields.io/badge/Zimbra-10.x-green?style=flat-square&logo=zimbra)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)
![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen?style=flat-square)

---

## 📋 Daftar Script

| Script | Deskripsi | Status |
|--------|-----------|--------|
| [`zimbra_preinstall.sh`](docs/zimbra_preinstall.md) | Persiapan sistem sebelum instalasi Zimbra (DNS, Firewall, Fail2Ban, Dependencies) | ✅ Stable v14.7 |
| [`zimbra_letsencrypt.sh`](docs/zimbra_letsencrypt.md) | Otomatisasi SSL Let's Encrypt untuk Zimbra + Auto Renewal | ✅ Stable v1.2 |
| _zimbra_backup.sh_ | Backup otomatis Zimbra (Coming Soon) | 🚧 Development |
| _zimbra_migration.sh_ | Migrasi Zimbra ke server baru (Coming Soon) | 🚧 Development |

---

## 🚀 Quick Start

### 1. Clone Repositori
```bash
git clone https://github.com/kudoluffi/zimbra-scripts.git
cd zimbra-scripts
