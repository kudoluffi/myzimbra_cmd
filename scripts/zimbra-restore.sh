#!/bin/bash
# zimbra-restore.sh v1.5
# FIXED: Double domain bug + Efficient preferences restore (only important settings)
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

# Attributes to restore (only important ones - FAST!)
PREF_ATTRIBUTES_TO_RESTORE=(
  "zimbraPrefSignature"
  "zimbraPrefMailForwardingAddress"
  "zimbraPrefMailLocalDeliveryDisabled"
  "zimbraPrefMailReplyTo"
  "zimbraPrefTimeZoneId"
  "zimbraPrefLocale"
  "zimbraPrefSkin"
)

# Attributes to skip (deprecated, read-only, system)
PREF_ATTRIBUTES_TO_SKIP=(
  "zimbraId"
  "createTimestamp"
  "modifyTimestamp"
  "zimbraMailHost"
  "zimbraAccountStatus"
  "zimbraCOSId"
  "zimbraDomainId"
  "zimbraDataSourceId"
  "uid"
  "cn"
  "sn"
  "givenName"
  "displayName"
  "mail"
  "userPassword"
  "zimbraPasswordModifiedTime"
  "zimbraLastLogonTimestamp"
)

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
      echo "MODES (comma-separated):"
      echo "  config              Restore Zimbra configuration"
      echo "  passwords           Restore password hashes"
      echo "  mailboxes           Restore user mailboxes (TGZ files) - includes preferences"
      echo "  preferences         Restore user preferences (signatures, forwarding only)"
      echo "  distribution-lists  Restore distribution lists and members"
      echo "  all                 Restore everything"
      echo ""
      echo "FILTERS (only for 'mailboxes' or 'preferences' mode):"
      echo "  --status LIST       Restore accounts with status in LIST"
      echo "                      Use 'all' to restore all accounts"
      echo "                      Default: active,locked,lockout"
      echo "  --exclude LIST      Restore accounts NOT in LIST"
      echo ""
      echo "SINGLE USER:"
      echo "  --user USER@DOMAIN  Restore single user (bypass filters)"
      echo ""
      echo "EXAMPLES:"
      echo "  sudo bash zimbra-restore.sh --mode all 20260420"
      echo "  sudo bash zimbra-restore.sh --mode mailboxes --status all 20260420"
      echo "  sudo bash zimbra-restore.sh --mode passwords,mailboxes 20260420"
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

if [ -z "$BACKUP_DATE" ]; then
  err "Backup date required"
fi

if [ -z "$MODES" ]; then
  err "Mode required"
fi

if [ "$MODES" = "all" ]; then
  MODES="config,passwords,mailboxes,preferences,distribution-lists"
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
  
  if [ -n "$SINGLE_USER" ]; then
    [ "$account" = "$SINGLE_USER" ]
    return $?
  fi
  
  if [ "$STATUS_FILTER" = "all" ]; then
    return 0
  fi
  
  local status=$(get_account_status "$account")
  
  if [ -n "$STATUS_FILTER" ]; then
    echo ",$STATUS_FILTER," | grep -q ",$status," && return 0
    log "   Skipping $account (status: $status)"
    return 1
  fi
  
  if [ -n "$EXCLUDE_FILTER" ]; then
    echo ",$EXCLUDE_FILTER," | grep -q ",$status," && { log "   Skipping $account (status: $status, excluded)"; return 1; }
    return 0
  fi
  
  echo ",$DEFAULT_STATUS," | grep -q ",$status," && return 0
  log "   Skipping $account (status: $status)"
  return 1
}

account_exists() {
  local account="$1"
  su - $ZIMBRA_USER -c "zmprov ga '$account' &>/dev/null" 2>/dev/null
  return $?
}

create_account_if_needed() {
  local account="$1"
  
  account_exists "$account" && return 0
  
  log "   Account not found, creating: $account"
  
  local safe_name=$(echo "$account" | tr '@' '_')
  local password_file="$BACKUP_ROOT/passwords/$BACKUP_DATE/${safe_name}.shadow"
  local temp_password="TempRestore123!"
  
  if [ -f "$password_file" ]; then
    local password_hash=$(cat "$password_file")
    if [ -n "$password_hash" ]; then
      su - $ZIMBRA_USER -c "zmprov ca '$account' '$password_hash' &>/dev/null" 2>/dev/null && {
        log "   ✓ Account created with restored password"
        return 0
      }
    fi
  fi
  
  su - $ZIMBRA_USER -c "zmprov ca '$account' '$temp_password' &>/dev/null" 2>/dev/null && {
    warn "   ⚠ Account created with temp password: $temp_password"
    return 0
  } || {
    fail "   ✗ Failed to create account"
    return 1
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# FIXED: Proper filename to account conversion
# ─────────────────────────────────────────────────────────────────────────────
filename_to_account() {
  local filename="$1"
  local domain_file="$BACKUP_ROOT/distribution-lists/domains-${BACKUP_DATE}.txt"
  local domain=""
  
  # Get domain from backup
  if [ -f "$domain_file" ]; then
    domain=$(head -1 "$domain_file" | tr -d '\r\n')
  fi
  
  # Check if filename already contains @ (e.g., admin.noob from admin.noob.tgz)
  if echo "$filename" | grep -q "@"; then
    # Already has domain, return as-is
    echo "$filename"
  elif [ -n "$domain" ]; then
    # Add domain
    echo "${filename}@${domain}"
  else
    # Fallback to hostname
    echo "${filename}@$(hostname -d)"
  fi
}

should_skip_attribute() {
  local attr="$1"
  
  # Check skip list
  for skip in "${PREF_ATTRIBUTES_TO_SKIP[@]}"; do
    [ "$attr" = "$skip" ] && return 0
  done
  
  # Check if attribute is in restore list (if list is not empty)
  if [ ${#PREF_ATTRIBUTES_TO_RESTORE[@]} -gt 0 ]; then
    local found=0
    for restore in "${PREF_ATTRIBUTES_TO_RESTORE[@]}"; do
      [ "$attr" = "$restore" ] && { found=1; break; }
    done
    [ $found -eq 0 ] && return 0
  fi
  
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
restore_config() {
  log "Restoring Zimbra configuration..."
  log "   ℹ️  Config restore requires MANUAL REVIEW before applying!"
  
  CONFIG_DIR="$BACKUP_ROOT/config"
  [ -f "$CONFIG_DIR/global-config-${BACKUP_DATE}.txt" ] && log "   • Global config: $CONFIG_DIR/global-config-${BACKUP_DATE}.txt"
  [ -f "$CONFIG_DIR/server-config-${BACKUP_DATE}.txt" ] && log "   • Server config: $CONFIG_DIR/server-config-${BACKUP_DATE}.txt"
  [ -f "$CONFIG_DIR/local-config-${BACKUP_DATE}.txt" ] && log "   • Local config: $CONFIG_DIR/local-config-${BACKUP_DATE}.txt"
  
  echo ""
  warn "   ⚠️  Apply config manually after review!"
  pass "   Configuration files ready for review"
}

restore_passwords() {
  log "Restoring password hashes..."
  
  PASSWORD_DIR="$BACKUP_ROOT/passwords/$BACKUP_DATE"
  [ ! -d "$PASSWORD_DIR" ] && { warn "   Password backup directory not found"; return 1; }
  
  RESTORE_SUCCESS=0
  RESTORE_FAILED=0
  
  for shadow_file in "$PASSWORD_DIR"/*.shadow; do
    [ -f "$shadow_file" ] || continue
    
    local filename=$(basename "$shadow_file" .shadow)
    local account=$(filename_to_account "$filename")
    
    should_restore_account "$account" || continue
    
    if ! create_account_if_needed "$account"; then
      RESTORE_FAILED=$((RESTORE_FAILED + 1))
      continue
    fi
    
    local password_hash=$(cat "$shadow_file")
    if [ -n "$password_hash" ] && [ -n "$account" ]; then
      log "   Restoring password: $account"
      su - $ZIMBRA_USER -c "zmprov ma '$account' userPassword '$password_hash'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null
      [ $? -eq 0 ] && { RESTORE_SUCCESS=$((RESTORE_SUCCESS + 1)); pass "      ✓ $account"; } || { RESTORE_FAILED=$((RESTORE_FAILED + 1)); fail "      ✗ $account"; }
    fi
  done
  
  echo ""
  pass "   Password restore: $RESTORE_SUCCESS success, $RESTORE_FAILED failed"
}

restore_mailboxes() {
  log "Restoring user mailboxes..."
  
  MAILBOX_DIR="$BACKUP_ROOT/mailboxes/$BACKUP_DATE"
  [ ! -d "$MAILBOX_DIR" ] && { warn "   Mailbox backup directory not found"; return 1; }
  
  TGZ_COUNT=$(ls "$MAILBOX_DIR"/*.tgz 2>/dev/null | wc -l)
  log "   Found $TGZ_COUNT mailbox backup file(s)"
  
  [ "$TGZ_COUNT" -eq 0 ] && { warn "   No .tgz files found!"; ls -la "$MAILBOX_DIR/" 2>&1 | head -10; return 1; }
  
  RESTORE_SUCCESS=0
  RESTORE_FAILED=0
  SKIPPED_COUNT=0
  
  for tgz_file in "$MAILBOX_DIR"/*.tgz; do
    [ -f "$tgz_file" ] || continue
    
    local filename=$(basename "$tgz_file" .tgz)
    local account=$(filename_to_account "$filename")
    
    echo "$account" | grep -q "@" || { warn "   Invalid account format: $account"; continue; }
    
    should_restore_account "$account" || { SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); continue; }
    
    if ! account_exists "$account"; then
      log "   Creating account: $account"
      create_account_if_needed "$account" || { SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); continue; }
    fi
    
    log "   Restoring mailbox: $account"
    su - $ZIMBRA_USER -c "zmrestore -a '$account' '$tgz_file'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null
    [ $? -eq 0 ] && { RESTORE_SUCCESS=$((RESTORE_SUCCESS + 1)); pass "      ✓ $account"; } || { RESTORE_FAILED=$((RESTORE_FAILED + 1)); fail "      ✗ $account"; }
  done
  
  echo ""
  pass "   Mailbox restore: $RESTORE_SUCCESS success, $RESTORE_FAILED failed, $SKIPPED_COUNT skipped"
  log "   ℹ️  Mailbox restore (TGZ) already includes preferences, signatures, and filters!"
}

# ─────────────────────────────────────────────────────────────────────────────
# FIXED: Fast preferences restore (only important settings)
# ─────────────────────────────────────────────────────────────────────────────
restore_preferences() {
  log "Restoring user preferences (FAST mode - signatures, forwarding only)..."
  log "   ℹ️  Only restoring important settings to avoid deprecated attributes"
  log "   ℹ️  Mailbox TGZ restore already includes most preferences"
  
  MAILBOX_DIR="$BACKUP_ROOT/mailboxes/$BACKUP_DATE"
  [ ! -d "$MAILBOX_DIR" ] && { warn "   Mailbox backup directory not found"; return 1; }
  
  RESTORE_SUCCESS=0
  RESTORE_FAILED=0
  SKIPPED_COUNT=0
  
  for pref_file in "$MAILBOX_DIR"/*-preferences.txt; do
    [ -f "$pref_file" ] || continue
    
    local filename=$(basename "$pref_file" -preferences.txt)
    local account=$(filename_to_account "$filename")
    
    echo "$account" | grep -q "@" || continue
    
    should_restore_account "$account" || { SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); continue; }
    
    if ! account_exists "$account"; then
      log "   Creating account: $account"
      create_account_if_needed "$account" || { SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); continue; }
    fi
    
    log "   Restoring preferences: $account"
    
    local applied_count=0
    local skipped_count=0
    
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      
      if echo "$line" | grep -q ":"; then
        local attr=$(echo "$line" | cut -d: -f1 | xargs)
        local value=$(echo "$line" | cut -d: -f2- | sed 's/^ *//')
        
        # Skip if attribute is in skip list
        if should_skip_attribute "$attr"; then
          skipped_count=$((skipped_count + 1))
          continue
        fi
        
        # Skip empty values or very long values (likely multi-line)
        [ -z "$value" ] && continue
        [ ${#value} -gt 500 ] && { skipped_count=$((skipped_count + 1)); continue; }
        
        # Apply attribute (suppress deprecated warnings)
        su - $ZIMBRA_USER -c "zmprov ma '$account' '$attr' '$value'" 2>/dev/null && \
          applied_count=$((applied_count + 1))
      fi
    done < "$pref_file"
    
    if [ "$applied_count" -gt 0 ]; then
      RESTORE_SUCCESS=$((RESTORE_SUCCESS + 1))
      pass "      ✓ $account ($applied_count settings, $skipped_count skipped)"
    else
      RESTORE_FAILED=$((RESTORE_FAILED + 1))
      warn "      ✗ $account (no settings applied)"
    fi
  done
  
  echo ""
  pass "   Preferences restore: $RESTORE_SUCCESS success, $RESTORE_FAILED failed, $SKIPPED_COUNT skipped"
  log "   ℹ️  For complete preferences, use mailbox restore (includes all settings)"
}

restore_distribution_lists() {
  log "Restoring distribution lists..."
  
  DL_LIST_FILE="$BACKUP_ROOT/distribution-lists/distribution-lists-${BACKUP_DATE}.txt"
  [ ! -f "$DL_LIST_FILE" ] && { warn "   Distribution list file not found"; return 1; }
  
  DL_COUNT=$(wc -l < "$DL_LIST_FILE")
  log "   Found $DL_COUNT distribution list(s)"
  
  DL_RESTORED=0
  DL_FAILED=0
  DL_MEMBER_COUNT=0
  
  while IFS= read -r dl_email; do
    [ -n "$dl_email" ] && echo "$dl_email" | grep -q "@" || continue
    
    log "   Restoring DL: $dl_email"
    su - $ZIMBRA_USER -c "zmprov cdl '$dl_email'" 2>/dev/null || true
    
    DL_SAFE_NAME=$(echo "$dl_email" | tr '@' '_' | tr '.' '_')
    DL_MEMBER_FILE="$BACKUP_ROOT/distribution-lists/dl-members-${DL_SAFE_NAME}-${BACKUP_DATE}.txt"
    
    if [ -f "$DL_MEMBER_FILE" ]; then
      MEMBERS_ADDED=0
      while IFS= read -r member; do
        [ -z "$member" ] && continue
        echo "$member" | grep -q "^#" && continue
        [ "$member" = "members" ] && continue
        
        if echo "$member" | grep -qE "^[^@]+@[^@]+\.[^@]+$"; then
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

echo ",$MODES," | grep -q ",config," && { restore_config; echo ""; }
echo ",$MODES," | grep -q ",passwords," && { restore_passwords; echo ""; }
echo ",$MODES," | grep -q ",mailboxes," && { restore_mailboxes; echo ""; }
echo ",$MODES," | grep -q ",preferences," && { restore_preferences; echo ""; }
echo ",$MODES," | grep -q ",distribution-lists," && { restore_distribution_lists; echo ""; }

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  RESTORE COMPLETED${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Backup Date : $BACKUP_DATE"
echo -e "Restore Modes: $MODES"
echo -e "Log File    : /tmp/zimbra-restore.log"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Review restore log: cat /tmp/zimbra-restore.log"
echo -e "2. Test user login with restored passwords"
echo -e "3. Verify mailbox content and signatures"
echo -e "4. Test distribution list email delivery"
echo -e "${GREEN}========================================================${NC}\n"

exit 0
