#!/bin/bash
# zimbra-verify-dns.sh v1.0
# Verify SPF, DKIM, DMARC DNS records
# Usage: sudo bash zimbra-verify-dns.sh

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
echo -e "${GREEN}  Zimbra DNS Records Verification${NC}"
echo -e "${GREEN}========================================================${NC}\n"

DOMAIN=$(hostname -d)
SELECTOR="mail"
PASS_COUNT=0
FAIL_COUNT=0

log "Domain: $DOMAIN"
log "Using selector: $SELECTOR"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. Check SPF Record
# ─────────────────────────────────────────────────────────────────────────────
log "1. Checking SPF Record..."
SPF_RECORD=$(dig +short TXT $DOMAIN | grep "v=spf1" | head -1)

if [ -n "$SPF_RECORD" ]; then
  pass "SPF record found"
  log "   $SPF_RECORD"
  PASS_COUNT=$((PASS_COUNT + 1))
  
  # Check for common issues
  if echo "$SPF_RECORD" | grep -q "\-all"; then
    pass "SPF policy is strict (-all)"
  elif echo "$SPF_RECORD" | grep -q "~all"; then
    warn "SPF policy is soft (~all) - consider using -all for production"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "SPF record NOT found!"
  log "   Create TXT record for $DOMAIN with value: v=spf1 mx ip4:$(hostname -I | awk '{print $1}') -all"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. Check DKIM Record
# ─────────────────────────────────────────────────────────────────────────────
log "2. Checking DKIM Record..."
DKIM_RECORD=$(dig +short TXT ${SELECTOR}._domainkey.$DOMAIN | grep "v=DKIM1" | head -1)

if [ -n "$DKIM_RECORD" ]; then
  pass "DKIM record found"
  log "   ${SELECTOR}._domainkey.$DOMAIN"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "DKIM record NOT found!"
  log "   Create TXT record for ${SELECTOR}._domainkey.$DOMAIN"
  log "   Get public key from: /opt/zimbra/dkim/$DOMAIN/${SELECTOR}.txt"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. Check DMARC Record
# ─────────────────────────────────────────────────────────────────────────────
log "3. Checking DMARC Record..."
DMARC_RECORD=$(dig +short TXT _dmarc.$DOMAIN | grep "v=DMARC1" | head -1)

if [ -n "$DMARC_RECORD" ]; then
  pass "DMARC record found"
  log "   $DMARC_RECORD"
  PASS_COUNT=$((PASS_COUNT + 1))
  
  # Check DMARC policy
  if echo "$DMARC_RECORD" | grep -q "p=reject"; then
    pass "DMARC policy is strict (reject)"
  elif echo "$DMARC_RECORD" | grep -q "p=quarantine"; then
    warn "DMARC policy is quarantine - consider reject for production"
  elif echo "$DMARC_RECORD" | grep -q "p=none"; then
    warn "DMARC policy is none (monitoring only)"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "DMARC record NOT found!"
  log "   Create TXT record for _dmarc.$DOMAIN"
  log "   Value: v=DMARC1; p=quarantine; rua=mailto:dmarc@$DOMAIN; pct=100"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 4. Check MX Record
# ─────────────────────────────────────────────────────────────────────────────
log "4. Checking MX Record..."
MX_RECORD=$(dig +short MX $DOMAIN | head -1)

if [ -n "$MX_RECORD" ]; then
  pass "MX record found"
  log "   $MX_RECORD"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "MX record NOT found!"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 5. Check PTR (Reverse DNS)
# ─────────────────────────────────────────────────────────────────────────────
log "5. Checking PTR (Reverse DNS)..."
SERVER_IP=$(hostname -I | awk '{print $1}')
PTR_RECORD=$(dig +short -x $SERVER_IP | head -1)

if [ -n "$PTR_RECORD" ]; then
  pass "PTR record found: $PTR_RECORD"
  
  # Check if PTR matches FQDN
  FQDN=$(hostname -f)
  if [ "$PTR_RECORD" = "$FQDN." ] || [ "$PTR_RECORD" = "$FQDN" ]; then
    pass "PTR matches FQDN ($FQDN)"
    PASS_COUNT=$((PASS_COUNT + 2))
  else
    warn "PTR does not match FQDN. Expected: $FQDN, Got: $PTR_RECORD"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
else
  fail "PTR record NOT found!"
  log "   Contact your VPS provider to set PTR for $SERVER_IP"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  VERIFICATION SUMMARY${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo -e "${GREEN}========================================================${NC}\n"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✅ All DNS records configured correctly!${NC}\n"
  echo -e "${YELLOW}Next Step: Run zimbra-security-hardening.sh (STEP 3)${NC}\n"
  exit 0
else
  echo -e "${RED}❌ Some DNS records missing. Please add them in your DNS provider.${NC}\n"
  echo -e "${YELLOW}After adding DNS records, run this script again to verify.${NC}\n"
  exit 1
fi
