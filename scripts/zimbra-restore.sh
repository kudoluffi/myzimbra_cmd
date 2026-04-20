#!/bin/bash
# zimbra-restore.sh v1.2
# Redesigned: Single --mode option with comma-separated values
# Usage: sudo bash zimbra-restore.sh --mode MODES [FILTERS] BACKUP_DATE

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  echo "Script must be run as root. Use: sudo bash $0"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
BACKUP_ROOT="/backup/zimbra"
ZIMBRA_USER="zimbra"
DEFAULT_STATUS="active,locked,lockout"

# ─────────────────────────────────────────────────────────────────────────────
# PARSE OPTIONS
# ─────────────────────────────────────────────────────────────────────────────
MODES=""
STATUS_FILTER=""
EXCLUDE_FILTER=""
SINGLE_USER=""
BACKUP_DATE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode)
      MODES="$2"
      shift 2
      ;;
    --user)
      SINGLE_USER="$2"
      shift 2
      ;;
    --status)
      STATUS_FILTER="$2"
      shift 2
      ;;
    --exclude)
      EXCLUDE_FILTER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: sudo bash zimbra-restore.sh --mode MODES [FILTERS] BACKUP_DATE"
      echo ""
      echo "MODES (comma-separated, pick one or more):"
      echo "  config              Restore Zimbra configuration"
      echo "  passwords           Restore password hashes"
      echo "  mailboxes           Restore user mailboxes (with status filter)"
      echo "  distribution-lists  Restore distribution lists"
      echo "  all                 Restore everything (all modes above)"
      echo ""
      echo "FILTERS (Only valid when 'mailboxes' is in MODES):"
      echo "  --status LIST       Restore accounts with status in LIST"
      echo "                      Default: active,locked,lockout"
      echo "  --exclude LIST      Restore accounts NOT in LIST"
      echo ""
      echo "SINGLE USER MODE:"
      echo "  --user USER@DOMAIN  Restore single user (bypass all filters)"
      echo ""
      echo "EXAMPLES:"
      echo "  sudo bash zimbra-restore.sh --mode all 20260420"
      echo "  sudo bash zimbra-restore.sh --mode mailboxes --status active 20260420"
      echo "  sudo bash zimbra-restore.sh --mode passwords,mailboxes 20260420"
      echo "  sudo bash zimbra-restore.sh --mode mailboxes --exclude closed,disabled 20260420"
      echo "  sudo bash zimbra-restore.sh --mode mailboxes --user admin@example.com 20260420"
      exit 0
      ;;
    *)
      if [ -z "$BACKUP_DATE" ]; then
        BACKUP_DATE="$1"
      else
        err "Unknown option or duplicate backup date: $1"
      fi
      shift
      ;;
  esac
done

# Validate backup date
if [ -z "$BACKUP_DATE" ]; then
  err "Backup date required. Use: sudo bash zimbra-restore.sh --mode MODES BACKUP_DATE"
fi

# Validate modes
if [ -z "$MODES" ]; then
  err "Mode required. Use --mode with: config, passwords, mailboxes, distribution-lists, or all"
fi

# Expand 'all' to all modes
if [ "$MODES" = "all" ]; then
  MODES="config,passwords,mailboxes,distribution-lists"
fi

# Validate filters only work with mailboxes mode
if ! echo ",$MODES," | grep -q ",mailboxes,"; then
  if [ -n "$STATUS_FILTER" ] || [ -n "$EXCLUDE_FILTER" ]; then
    warn "--status and --exclude only work when 'mailboxes' is in --mode"
    STATUS_FILTER=""
    EXCLUDE_FILTER=""
  fi
fi

# Validate --user is exclusive with filters
if [ -n "$SINGLE_USER" ]; then
  if [ -n "$STATUS_FILTER" ] || [ -n "$EXCLUDE_FILTER" ]; then
    err "--user cannot be combined with --status or --exclude"
  fi
fi

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  Zimbra Restore Script${NC}"
echo -e "${GREEN}========================================================${NC}\n"

log "Backup Date: $BACKUP_DATE"
log "Restore Modes: $MODES"
[ -n "$STATUS_FILTER" ] && log "Status Filter: $STATUS_FILTER"
[ -n "$EXCLUDE_FILTER" ] && log "Exclude Filter: $EXCLUDE_FILTER"
[ -n "$SINGLE_USER" ] && log "Single User: $SINGLE_USER"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
get_account_status() {
  local account="$1"
  local safe_name=$(echo "$account" | tr '@' '_')
  local pref_file="$BACKUP_ROOT/mailboxes/$BACKUP_DATE/${safe_name}-preferences.txt"
  
  if [ -f "$pref_file" ]; then
    grep "^zimbraAccountStatus:" "$pref_file" 2>/dev/null | awk '{print $2}' || echo "active"
  else
    echo "active"
  fi
}

should_restore_account() {
  local account="$1"
  
  # Single user mode: always restore this user only
  if [ -n "$SINGLE_USER" ]; then
    if [ "$account" = "$SINGLE_USER" ]; then
      return 0
    else
      return 1
    fi
  fi
  
  # Get account status
  local status=$(get_account_status "$account")
  
  # Status filter mode
  if [ -n "$STATUS_FILTER" ]; then
    if echo ",$STATUS_FILTER," | grep -q ",$status,"; then
      return 0
    else
      log "   Skipping $account (status: $status, not in filter)"
      return 1
    fi
  fi
  
  # Exclude filter mode
  if [ -n "$EXCLUDE_FILTER" ]; then
    if echo ",$EXCLUDE_FILTER," | grep -q ",$status,"; then
      log "   Skipping $account (status: $status, in exclude list)"
      return 1
    else
      return 0
    fi
  fi
  
  # Default: restore active, locked, lockout
  if echo ",$DEFAULT_STATUS," | grep -q ",$status,"; then
    return 0
  else
    log "   Skipping $account (status: $status, not in default filter)"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
restore_config() {
  log "Restoring Zimbra configuration..."
  
  CONFIG_DIR="$BACKUP_ROOT/config"
  
  if [ -f "$CONFIG_DIR/global-config-${BACKUP_DATE}.txt" ]; then
    log "   Global config: $CONFIG_DIR/global-config-${BACKUP_DATE}.txt"
    pass "   ✓ Global config file ready for review"
  else
    warn "   ✗ Global config file not found"
  fi
  
  if [ -f "$CONFIG_DIR/server-config-${BACKUP_DATE}.txt" ]; then
    log "   Server config: $CONFIG_DIR/server-config-${BACKUP_DATE}.txt"
    pass "   ✓ Server config file ready for review"
  else
    warn "   ✗ Server config file not found"
  fi
  
  if [ -f "$CONFIG_DIR/local-config-${BACKUP_DATE}.txt" ]; then
    log "   Local config: $CONFIG_DIR/local-config-${BACKUP_DATE}.txt"
    pass "   ✓ Local config file ready for review"
  else
    warn "   ✗ Local config file not found"
  fi
  
  warn "   ⚠️  Config restore requires MANUAL REVIEW before applying!"
  pass "   Configuration restore completed (files ready for review)"
}

restore_passwords() {
  log "Restoring password hashes..."
  
  PASSWORD_DIR="$BACKUP_ROOT/passwords/$BACKUP_DATE"
  
  if [ ! -d "$PASSWORD_DIR" ]; then
    warn "   Password backup directory not found"
    return 1
  fi
  
  RESTORE_SUCCESS=0
  RESTORE_FAILED=0
  
  for shadow_file in "$PASSWORD_DIR"/*.shadow; do
    if [ -f "$shadow_file" ]; then
      local filename=$(basename "$shadow_file" .shadow)
      local account=$(echo "$filename" | tr '_' '@' | sed 's/@\([^.]*\)\./@\1./')
      
      if ! should_restore_account "$account"; then
        continue
      fi
      
      local password_hash=$(cat "$shadow_file")
      
      if [ -n "$password_hash" ] && [ -n "$account" ]; then
        log "   Restoring password: $account"
        
        su - $ZIMBRA_USER -c "zmprov ma '$account' userPassword '$password_hash'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null
        
        if [ $? -eq 0 ]; then
          RESTORE_SUCCESS=$((RESTORE_SUCCESS + 1))
          pass "      ✓ $account"
        else
          RESTORE_FAILED=$((RESTORE_FAILED + 1))
          fail "      ✗ $account"
        fi
      fi
    fi
  done
  
  echo ""
  pass "   Password restore: $RESTORE_SUCCESS success, $RESTORE_FAILED failed"
}

restore_mailboxes() {
  log "Restoring user mailboxes..."
  
  MAILBOX_DIR="$BACKUP_ROOT/mailboxes/$BACKUP_DATE"
  
  if [ ! -d "$MAILBOX_DIR" ]; then
    warn "   Mailbox backup directory not found"
    return 1
  fi
  
  RESTORE_SUCCESS=0
  RESTORE_FAILED=0
  SKIPPED_COUNT=0
  
  for tgz_file in "$MAILBOX_DIR"/*.tgz; do
    if [ -f "$tgz_file" ]; then
      local filename=$(basename "$tgz_file" .tgz)
      local account=$(echo "$filename" | tr '_' '@' | sed 's/@\([^.]*\)\./@\1./')
      
      if ! echo "$account" | grep -q "@"; then
        continue
      fi
      
      if ! should_restore_account "$account"; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
      fi
      
      log "   Restoring mailbox: $account"
      
      su - $ZIMBRA_USER -c "zmrestore -a '$account' '$tgz_file'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null
      
      if [ $? -eq 0 ]; then
        RESTORE_SUCCESS=$((RESTORE_SUCCESS + 1))
        pass "      ✓ $account"
      else
        RESTORE_FAILED=$((RESTORE_FAILED + 1))
        fail "      ✗ $account"
      fi
    fi
  done
  
  echo ""
  pass "   Mailbox restore: $RESTORE_SUCCESS success, $RESTORE_FAILED failed, $SKIPPED_COUNT skipped"
}

restore_distribution_lists() {
  log "Restoring distribution lists..."
  
  DL_LIST_FILE="$BACKUP_ROOT/distribution-lists/distribution-lists-${BACKUP_DATE}.txt"
  
  if [ ! -f "$DL_LIST_FILE" ]; then
    warn "   Distribution list file not found"
    return 1
  fi
  
  DL_COUNT=$(wc -l < "$DL_LIST_FILE")
  log "   Found $DL_COUNT distribution list(s) to restore"
  
  DL_RESTORED=0
  DL_FAILED=0
  DL_MEMBER_COUNT=0
  
  while IFS= read -r dl_email; do
    if [ -n "$dl_email" ] && echo "$dl_email" | grep -q "@"; then
      log "   Restoring DL: $dl_email"
      
      su - $ZIMBRA_USER -c "zmprov cdl '$dl_email'" 2>/dev/null || true
      
      DL_SAFE_NAME=$(echo "$dl_email" | tr '@' '_' | tr '.' '_')
      DL_MEMBER_FILE="$BACKUP_ROOT/distribution-lists/dl-members-${DL_SAFE_NAME}-${BACKUP_DATE}.txt"
      
      if [ -f "$DL_MEMBER_FILE" ]; then
        MEMBERS_ADDED=0
        while IFS= read -r member; do
          if [ -n "$member" ] && echo "$member" | grep -q "@"; then
            su - $ZIMBRA_USER -c "zmprov adlm '$dl_email' '$member'" 2>/dev/null && \
              MEMBERS_ADDED=$((MEMBERS_ADDED + 1))
          fi
        done < "$DL_MEMBER_FILE"
        
        DL_MEMBER_COUNT=$((DL_MEMBER_COUNT + MEMBERS_ADDED))
        DL_RESTORED=$((DL_RESTORED + 1))
        pass "      ✓ $dl_email ($MEMBERS_ADDED members)"
      else
        DL_FAILED=$((DL_FAILED + 1))
        warn "      ✗ $dl_email (member file not found)"
      fi
    fi
  done < "$DL_LIST_FILE"
  
  echo ""
  pass "   Distribution lists restored: $DL_RESTORED success, $DL_FAILED failed"
  log "   Total members restored: $DL_MEMBER_COUNT"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN RESTORE LOGIC
# ─────────────────────────────────────────────────────────────────────────────
log "Starting restore process..."
echo ""

# Parse modes and execute
if echo ",$MODES," | grep -q ",config,"; then
  restore_config
  echo ""
fi

if echo ",$MODES," | grep -q ",passwords,"; then
  restore_passwords
  echo ""
fi

if echo ",$MODES," | grep -q ",mailboxes,"; then
  restore_mailboxes
  echo ""
fi

if echo ",$MODES," | grep -q ",distribution-lists,"; then
  restore_distribution_lists
  echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  RESTORE COMPLETED${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Backup Date : $BACKUP_DATE"
echo -e "Restore Modes: $MODES"
echo -e "Log File    : /tmp/zimbra-restore.log"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Review restore log: cat /tmp/zimbra-restore.log"
echo -e "2. Test user login and mailbox access"
echo -e "3. Verify configuration settings"
echo -e "4. Test distribution list email delivery"
echo -e "${GREEN}========================================================${NC}\n"

exit 0
