#!/bin/bash
# zimbra-restore-passwords.sh v1.0
# Restore password hashes from backup
# Usage: sudo bash zimbra-restore-passwords.sh <BACKUP_DATE>

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

if [ -z "${1:-}" ]; then
  echo "Usage: sudo bash zimbra-restore-passwords.sh <BACKUP_DATE>"
  echo "Example: sudo bash zimbra-restore-passwords.sh 20260419-184934"
  echo ""
  echo "Available password backups:"
  ls -la /backup/zimbra/passwords/ 2>/dev/null | grep "^d" | awk '{print $9}'
  exit 1
fi

BACKUP_DATE="$1"
BACKUP_ROOT="/backup/zimbra"
PASSWORD_DIR="$BACKUP_ROOT/passwords/$BACKUP_DATE"
ZIMBRA_USER="zimbra"

if [ ! -d "$PASSWORD_DIR" ]; then
  fail "Password backup directory not found: $PASSWORD_DIR"
  exit 1
fi

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  Zimbra Password Restore - $BACKUP_DATE${NC}"
echo -e "${GREEN}========================================================${NC}\n"

log "Password Directory: $PASSWORD_DIR"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRMATION
# ─────────────────────────────────────────────────────────────────────────────
warn "⚠️  WARNING: This will restore password hashes from backup!"
warn "⚠️  Current passwords will be OVERWRITTEN!"
echo ""
read -rp "Are you sure you want to continue? Type 'YES' to confirm: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  log "Password restore cancelled by user"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE PASSWORDS
# ─────────────────────────────────────────────────────────────────────────────
log "Starting password restore..."

RESTORE_SUCCESS=0
RESTORE_FAILED=0

for shadow_file in "$PASSWORD_DIR"/*.shadow; do
  if [ -f "$shadow_file" ]; then
    # Extract account name from filename (user_domain_com.shadow -> user@domain.com)
    FILENAME=$(basename "$shadow_file" .shadow)
    ACCOUNT_EMAIL=$(echo "$FILENAME" | tr '_' '@' | sed 's/@\([^.]*\)\./@\1./')
    
    # Read password hash
    PASSWORD_HASH=$(cat "$shadow_file")
    
    if [ -n "$PASSWORD_HASH" ] && [ -n "$ACCOUNT_EMAIL" ]; then
      log "   Restoring password for: $ACCOUNT_EMAIL"
      
      # Set password hash using zmprov
      su - $ZIMBRA_USER -c "zmprov ma '$ACCOUNT_EMAIL' userPassword '$PASSWORD_HASH'" 2>&1 | tee -a "$PASSWORD_DIR/restore.log"
      
      if [ $? -eq 0 ]; then
        RESTORE_SUCCESS=$((RESTORE_SUCCESS + 1))
        pass "      ✓ $ACCOUNT_EMAIL"
      else
        RESTORE_FAILED=$((RESTORE_FAILED + 1))
        fail "      ✗ $ACCOUNT_EMAIL (failed)"
      fi
    fi
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  PASSWORD RESTORE SELESAI${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Success: $RESTORE_SUCCESS"
echo -e "Failed:  $RESTORE_FAILED"
echo -e "Log File: $PASSWORD_DIR/restore.log"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Test login with restored passwords"
echo -e "2. Review restore log: cat $PASSWORD_DIR/restore.log"
echo -e "${GREEN}========================================================${NC}\n"

exit 0
