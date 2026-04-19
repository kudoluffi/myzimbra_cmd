#!/bin/bash
# zimbra-dkim-setup.sh v1.1
# Configure DKIM signing for Zimbra OSE (Simplified)
# Usage: sudo bash zimbra-dkim-setup.sh

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
  echo "Script must be run as root. Use: sudo bash $0"
  exit 1
fi

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  Zimbra DKIM Setup (OSE - Simplified)${NC}"
echo -e "${GREEN}========================================================${NC}\n"

# ─────────────────────────────────────────────────────────────────────────────
# USER INPUT
# ─────────────────────────────────────────────────────────────────────────────
read -rp "Masukkan domain email (contoh: example.com): " DOMAIN
read -rp "Masukkan selector DKIM (contoh: mail, default: mail): " SELECTOR

SELECTOR=${SELECTOR:-mail}

[ -z "$DOMAIN" ] && { echo "Domain wajib diisi."; exit 1; }

log "Domain: $DOMAIN"
log "Selector: $SELECTOR"
log ""
log "Note: Zimbra OSE akan otomatis apply DKIM setelah key di-generate"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Generate DKIM Keys (Auto-signed by Zimbra OSE)
# ─────────────────────────────────────────────────────────────────────────────
log "1. Generating DKIM keys..."

su - zimbra -c "/opt/zimbra/libexec/zmdkimkeyutil -a -d $DOMAIN" 2>&1 | tee /tmp/dkim_setup.log

if [ $? -eq 0 ]; then
  pass "DKIM keys generated successfully (auto-signed by Zimbra OSE)"
else
  fail "Failed to generate DKIM keys"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Find and Display Public Key
# ─────────────────────────────────────────────────────────────────────────────
log "2. Extracting public key for DNS record..."

# Find the DKIM file
DKIM_FILE=$(find /opt/zimbra/dkim/$DOMAIN -name "*.txt" 2>/dev/null | head -1)
if [ -z "$DKIM_FILE" ]; then
  DKIM_FILE=$(find /opt/zimbra/ssl/zimbra/dkim/$DOMAIN -name "*.txt" 2>/dev/null | head -1)
fi

if [ -n "$DKIM_FILE" ] && [ -f "$DKIM_FILE" ]; then
  pass "DKIM record file found: $DKIM_FILE"
  echo ""
  echo -e "${GREEN}=== COPY DNS RECORDS INI KE PROVIDER ANDA ===${NC}"
  echo ""
  echo -e "${BLUE}1. SPF Record (TXT)${NC}"
  echo "   Host/Name: @ (atau ${DOMAIN})"
  echo "   Type: TXT"
  echo "   Value: v=spf1 mx ip4:$(hostname -I | awk '{print $1}') -all"
  echo ""
  
  echo -e "${BLUE}2. DKIM Record (TXT)${NC}"
  echo "   Host/Name: ${SELECTOR}._domainkey.${DOMAIN}"
  echo "   Type: TXT"
  echo "   Value:"
  cat "$DKIM_FILE" | grep "k=rsa" | sed 's/.*"v=DKIM1/\"v=DKIM1/' | tr -d '\n'
  echo ""
  echo ""
  
  echo -e "${BLUE}3. DMARC Record (TXT)${NC}"
  echo "   Host/Name: _dmarc.${DOMAIN}"
  echo "   Type: TXT"
  echo "   Value: v=DMARC1; p=quarantine; rua=mailto:dmarc@${DOMAIN}; pct=100"
  echo ""
  
  echo -e "${GREEN}========================================${NC}"
  echo -e "${YELLOW}⚠️  PENTING:${NC}"
  echo "   1. Copy semua record di atas ke DNS provider"
  echo "   2. Tunggu 5-60 menit untuk propagasi DNS"
  echo "   3. Verifikasi dengan external tools (lihat bawah)"
  echo ""
else
  fail "DKIM record file not found"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Show Verification Tools
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=== CARA VERIFIKASI (PAKAI EXTERNAL TOOLS) ===${NC}"
echo ""
echo "Setelah DNS propagate (tunggu 5-60 menit), verifikasi di:"
echo ""
echo "1. SPF Checker:"
echo "   https://mxtoolbox.com/spf.aspx"
echo "   Masukkan: $DOMAIN"
echo ""
echo "2. DKIM Checker:"
echo "   https://mxtoolbox.com/dkim.aspx"
echo "   Masukkan: ${SELECTOR}._domainkey.${DOMAIN}"
echo ""
echo "3. DMARC Checker:"
echo "   https://mxtoolbox.com/dmarc.aspx"
echo "   Masukkan: $DOMAIN"
echo ""
echo "4. Mail Server Tester (All-in-One):"
echo "   https://www.mail-tester.com/"
echo "   Kirim email test ke address yang diberikan"
echo ""
echo "5. Gmail/Outlook Test:"
echo "   Kirim email dari server ke Gmail/Outlook"
echo "   Cek 'Show Original' untuk lihat SPF/DKIM/DMARC status"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  DKIM SETUP SELESAI${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Domain     : $DOMAIN"
echo -e "Selector   : $SELECTOR"
echo -e "DKIM Keys  : /opt/zimbra/dkim/$DOMAIN/"
echo -e "Log File   : /tmp/dkim_setup.log"
echo -e "${YELLOW}Langkah Selanjutnya:${NC}"
echo -e "1. Tambahkan SPF, DKIM, DMARC ke DNS provider"
echo -e "2. Tunggu DNS propagate (5-60 menit)"
echo -e "3. Verifikasi dengan external tools di atas"
echo -e "4. Setelah semua OK, lanjut ke STEP 3 (Security Hardening)"
echo -e "${GREEN}========================================================${NC}\n"
