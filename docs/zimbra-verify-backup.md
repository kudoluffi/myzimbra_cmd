# 🔍 Zimbra Backup Verification Script

**Version:** 1.1  
**Last Updated:** 2026  
**Compatibility:** Ubuntu 22.04 LTS + Zimbra 10.1.x OSE

---

## 📋 Deskripsi

Script `zimbra-verify-backup.sh` memverifikasi integritas backup Zimbra yang dibuat oleh [`zimbra-backup.sh`](zimbra-backup.md). Script ini melakukan 10 comprehensive checks untuk memastikan backup dapat digunakan untuk disaster recovery.

**Fitur Utama:**
- ✅ Auto-detect latest backup atau specify manual
- ✅ 10 verification checks (config, accounts, passwords, mailboxes, etc.)
- ✅ **Telegram notification** untuk backup status (PASSED/FAILED/WARNING)
- ✅ Exit code untuk automation & monitoring integration
- ✅ Security check untuk password file permissions
- ✅ Backup age validation

---

## ✨ Verification Checks

| # | Check | Critical | Deskripsi |
|---|-------|----------|-----------|
| 1 | Backup Directory | ✅ Yes | Cek direktori backup exists |
| 2 | Config Files | ✅ Yes | Cek 4 config files ada & tidak kosong |
| 3 | Account List | ✅ Yes | Cek berisi email (bukan help menu) |
| 4 | Distribution Lists | ⚠️ Warning | Cek DL & domain files ada |
| 5 | Password Files | ✅ Yes | Cek exists + permission 600/700 |
| 6 | Mailbox Backups | ⚠️ Warning | Cek files ada & tidak kosong |
| 7 | User Preferences | ⚠️ Warning | Cek preference files ada |
| 8 | Backup Summary | ⚠️ Warning | Cek summary file ada |
| 9 | Backup Log | ⚠️ Warning | Cek log exists & check for errors |
| 10 | Backup Age | ✅ Yes | Cek backup tidak terlalu lama (<7 days) |

---

## 📥 Instalasi

### 1. Download Script
```bash
wget https://raw.githubusercontent.com/USERNAME/zimbra-scripts/main/scripts/zimbra-verify-backup.sh
chmod +x zimbra-verify-backup.sh
```
### 2. Setup Telegram (Optional but Recommended)
**Step 1: Buat Bot di Telegram**
  1. Buka Telegram → Cari `@BotFather`
  2. Kirim command: `/newbot`
  3. Ikuti instruksi:
  ```
  BotFather: Choose a name for your bot
  You: Zimbra Backup Monitor

  BotFather: Choose a username for your bot
  You: nmail_backup_bot

  BotFather: Success! Use this token: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
  ```
4. Simpan BOT TOKEN

**Step 2: Dapatkan Chat ID**
  1. Buka Telegram → Cari `@userinfobot`
  2. Kirim: `/start`
  3. Bot akan reply dengan:
  ```
  Your user ID: 987654321
  ```
  4. Simpan CHAT ID
   
**Step 3: Start Bot**
  1. Cari bot Anda di Telegram (contoh: @nmail_backup_bot)
  2. Klik START atau kirim /start
  3. PENTING: Bot tidak bisa kirim message jika belum di-start

**Step 4: Configure Environment Variables**
Edit script zimbra-verify-backup.sh:
```bash
TG_BOT_TOKEN="1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
TG_CHAT_ID="987654321"
TG_ENABLED="true"
```
### 3. Test Verification
```bash
# Auto-detect latest backup
sudo bash zimbra-verify-backup.sh

# Specify backup date
sudo bash zimbra-verify-backup.sh 20260419
```

---

## 📊 Output Interpretation
### ✅ Passed (No Failures, No Warnings)
```
========================================================
  VERIFICATION SUMMARY
========================================================
Backup Date : 20260419
Passed      : 15
Failed      : 0
Warnings    : 0
========================================================

✅ BACKUP VERIFICATION PASSED
   Backup is healthy and ready for disaster recovery
```
### Telegram Message:
```
🔐 Zimbra Backup Verification
✅ Status: PASSED

📅 Backup Date: 20260419
🖥️ Server: nmail.newbienotes.my.id

📊 Results:
✅ Passed: 15
❌ Failed: 0
⚠️ Warnings: 0

✅ Backup is healthy and ready for disaster recovery.
```
### ⚠️ Passed with Warnings
```
========================================================
  VERIFICATION SUMMARY
========================================================
Backup Date : 20260419
Passed      : 13
Failed      : 0
Warnings    : 2
========================================================

⚠️  BACKUP VERIFICATION PASSED WITH WARNINGS
   Backup is usable but review warnings above
```
### ❌ Failed
```
========================================================
  VERIFICATION SUMMARY
========================================================
Backup Date : 20260419
Passed      : 8
Failed      : 3
Warnings    : 2
========================================================

❌ BACKUP VERIFICATION FAILED
   3 critical issues found
   Review and fix before relying on this backup
```
### Telegram Message:
```
🔐 Zimbra Backup Verification
❌ Status: FAILED

📅 Backup Date: 20260419
🖥️ Server: nmail.newbienotes.my.id

📊 Results:
✅ Passed: 8
❌ Failed: 3
⚠️ Warnings: 2

🚨 ACTION REQUIRED! Backup verification failed!
Review logs and fix issues immediately.
```

---

## 🔧 Configuration
### Environment Variables
| Variable | Required | Default | Deskripsi |
|----------|----------|---------|-----------|
| TG_BOT_TOKEN | No | "" | Telegram Bot Token dari @BotFather |
| TG_CHAT_ID | No | "" | Telegram Chat ID dari @userinfobot |
| TG_ENABLED | No | true | Set false untuk disable notification |

### Disable Telegram Notification
```bash
# Option 1: Environment variable
export TG_ENABLED="false"
sudo bash zimbra-verify-backup.sh

# Option 2: Edit script
TG_ENABLED="false"  # Change at top of script

# Option 3: Remove from crontab
# Delete TG_BOT_TOKEN and TG_CHAT_ID lines
```

---

## 📅 Automated Verification (Cron)
### Setup Crontab
```
sudo crontab -e
```
### Full Configuration (Backup + Verify + Telegram)
```bash
# ─────────────────────────────────────────────────────────────────
# BACKUP SCHEDULE
# ─────────────────────────────────────────────────────────────────
# Daily incremental (Mon-Sat, 2 AM)
0 2 * * 1-6 /root/zimbra-backup.sh incremental >> /var/log/zimbra-backup-cron.log 2>&1

# Weekly full (Sunday, 2 AM)
0 2 * * 0 /root/zimbra-backup.sh full >> /var/log/zimbra-backup-cron.log 2>&1

# ─────────────────────────────────────────────────────────────────
# VERIFICATION SCHEDULE
# ─────────────────────────────────────────────────────────────────
# Daily verification (4 AM) - with Telegram notification
0 4 * * * /root/zimbra-verify-backup.sh >> /var/log/zimbra-backup-verify.log 2>&1

# Weekly verification report (Monday, 8 AM)
0 8 * * 1 /root/zimbra-verify-backup.sh >> /var/log/zimbra-backup-verify.log 2>&1
```
