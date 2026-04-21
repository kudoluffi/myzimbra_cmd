#!/bin/bash
# zimbra-restore.sh v2.5
# FINAL: Fixed status filter for all modes + signature HTML extraction
# Usage: sudo bash zimbra-restore.sh --mode MODES [FILTERS] BACKUP_DATE

set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && { echo "Run as root: sudo bash $0"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
BACKUP_ROOT="/backup/zimbra"
ZIMBRA_USER="zimbra"
DEFAULT_STATUS="active,locked,lockout"
ZMPROV_TIMEOUT=30

# ─────────────────────────────────────────────────────────────────────────────
# PARSE OPTIONS
# ─────────────────────────────────────────────────────────────────────────────
MODES=""
STATUS_FILTER=""
SINGLE_USER=""
BACKUP_DATE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODES="$2"; shift 2 ;;
    --status) STATUS_FILTER="$2"; shift 2 ;;
    --user) SINGLE_USER="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: sudo bash zimbra-restore.sh --mode MODES [FILTERS] BACKUP_DATE"
      echo "MODES: passwords, mailboxes, preferences, distribution-lists, all"
      exit 0
      ;;
    *)
      if [ -z "$BACKUP_DATE" ]; then
        BACKUP_DATE="$1"
      else
        err "Unknown option or duplicate date: $1"
      fi
      shift
      ;;
  esac
done

[ -z "$BACKUP_DATE" ] && err "Backup date required"
[ -z "$MODES" ] && err "Mode required"
[ "$MODES" = "all" ] && MODES="passwords,mailboxes,preferences,distribution-lists"

# ─────────────────────────────────────────────────────────────────────────────
# GET DOMAIN
# ─────────────────────────────────────────────────────────────────────────────
get_backup_domain() {
  local domain_file="$BACKUP_ROOT/distribution-lists/domains-${BACKUP_DATE}.txt"
  if [ -f "$domain_file" ] && [ -s "$domain_file" ]; then
    local domain
    domain=$(grep -v '^$' "$domain_file" | head -1 | tr -d '[:space:]')
    if [ -n "$domain" ] && echo "$domain" | grep -q '\.'; then
      echo "$domain"
      return 0
    fi
  fi
  hostname -d 2>/dev/null || echo "newbienotes.my.id"
}

DOMAIN=$(get_backup_domain)

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  Zimbra Restore Script v2.5${NC}"
echo -e "${GREEN}========================================================${NC}\n"

log "Backup: $BACKUP_DATE | Domain: $DOMAIN | Modes: $MODES"
[ -n "$STATUS_FILTER" ] && log "Status Filter: $STATUS_FILTER"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# FILENAME PARSING
# ─────────────────────────────────────────────────────────────────────────────
password_filename_to_account() {
  echo "$1" | sed 's/_/@/'
}

mailbox_filename_to_account() {
  echo "${1}@${DOMAIN}"
}

pref_filename_to_account() {
  echo "${1}@${DOMAIN}"
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Get account status from preferences file
get_account_status_from_backup() {
  local acc="$1"
  local safe
  safe=$(echo "$acc" | tr '@' '_')
  local pref="$BACKUP_ROOT/mailboxes/$BACKUP_DATE/${safe}-preferences.txt"
  if [ -f "$pref" ]; then
    grep "^zimbraAccountStatus:" "$pref" 2>/dev/null | head -1 | sed 's/^zimbraAccountStatus:[[:space:]]*//' | sed 's/[[:space:]]*$//' || echo "active"
  else
    echo "active"
  fi
}

# Check if account should be restored (check status from backup preferences)
should_restore() {
  local acc="$1"
  
  # Single user mode: always restore
  if [ -n "${SINGLE_USER:-}" ]; then
    [ "$acc" = "$SINGLE_USER" ] && return 0 || return 1
  fi
  
  # Status filter = all: restore all
  if [ "${STATUS_FILTER:-}" = "all" ]; then
    return 0
  fi
  
  # Get status from backup preferences file
  local status
  status=$(get_account_status_from_backup "$acc")
  
  # If specific status filter, check match
  if [ -n "${STATUS_FILTER:-}" ]; then
    if echo ",$STATUS_FILTER," | grep -q ",$status,"; then
      return 0
    else
      log "   Skipping $acc (status in backup: $status, filter: $STATUS_FILTER)"
      return 1
    fi
  fi
  
  # Default filter: active, locked, lockout
  if echo ",$DEFAULT_STATUS," | grep -q ",$status,"; then
    return 0
  else
    log "   Skipping $acc (status in backup: $status)"
    return 1
  fi
}

account_exists() {
  timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov ga '$1' &>/dev/null" 2>/dev/null || return 1
}

create_account() {
  local acc="$1" pwd="$2"
  log "   Creating: $acc"
  timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov ca '$acc' '$pwd'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null || return 1
}

# Get attribute with timeout
get_zimbra_attr() {
  local acc="$1"
  local attr="$2"
  timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov ga '$acc' '$attr'" 2>/dev/null | grep "^${attr}:" | awk '{print $2}' | head -1 || true
}

# Set attribute with timeout
set_zimbra_attr() {
  local acc="$1"
  local attr="$2"
  local value="$3"
  timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov ma '$acc' '$attr' '$value'" 2>/dev/null || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# FIXED: Multi-line value extractor (read until next attribute)
# ─────────────────────────────────────────────────────────────────────────────
get_pref_value_multiline() {
  local file="$1"
  local attr="$2"
  
  # Use awk to extract multi-line values properly
  awk -v ATTR="$attr:" '
    BEGIN { found=0 }
    $0 ~ "^"ATTR {
      found=1
      sub(/^'"$ATTR"'[[:space:]]*/, "")
      if (length($0) > 0) printf "%s", $0
      next
    }
    found {
      if ($0 ~ /^[a-zA-Z][a-zA-Z0-9_-]*:/) exit
      printf " %s", $0
    }
  ' "$file" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 10000 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: PASSWORDS (FIXED: Check status BEFORE restore)
# ─────────────────────────────────────────────────────────────────────────────
restore_passwords() {
  log "Restoring passwords..."
  local dir="$BACKUP_ROOT/passwords/$BACKUP_DATE"
  if [ ! -d "$dir" ]; then
    warn "   Not found"
    return 1
  fi
  
  local ok=0 fail=0
  for f in "$dir"/*.shadow; do
    [ -f "$f" ] || continue
    local fn
    fn=$(basename "$f" .shadow)
    local acc
    acc=$(password_filename_to_account "$fn")
    
    # FIX: Check status from backup BEFORE restoring
    should_restore "$acc" || continue
    
    account_exists "$acc" || create_account "$acc" "TempRestore123!"
    
    local hash
    hash=$(cat "$f")
    if [ -n "$hash" ]; then
      log "   Setting password: $acc"
      if timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov ma '$acc' userPassword '$hash'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null; then
        ok=$((ok+1)); pass "      ✓ $acc"
      else
        fail=$((fail+1)); fail "      ✗ $acc"
      fi
    fi
  done
  echo ""; pass "   Passwords: $ok ok, $fail fail"
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: MAILBOXES (FIXED: Check status BEFORE restore)
# ─────────────────────────────────────────────────────────────────────────────
restore_mailboxes() {
  log "Restoring mailboxes (OSE mode: postRestURL)..."
  local dir="$BACKUP_ROOT/mailboxes/$BACKUP_DATE"
  if [ ! -d "$dir" ]; then
    warn "   Not found"
    return 1
  fi
  
  shopt -s nullglob
  local files=("$dir"/*.tgz)
  shopt -u nullglob
  log "   Found ${#files[@]} backup file(s)"
  if [ ${#files[@]} -eq 0 ]; then
    warn "   No .tgz files!"
    ls "$dir/"
    return 1
  fi
  
  local ok=0 fail=0
  for f in "${files[@]}"; do
    local fn
    fn=$(basename "$f" .tgz)
    local acc
    acc=$(mailbox_filename_to_account "$fn")
    
    log "   Processing: $fn → $acc"
    echo "$acc" | grep -q "@" || { warn "   Invalid: $acc"; continue; }
    
    # FIX: Check status from backup BEFORE restoring
    should_restore "$acc" || continue
    
    account_exists "$acc" || create_account "$acc" "TempRestore123!"
    
    log "   Restoring mailbox: $acc"
    
    local restore_output
    restore_output=$(timeout 120 su - "$ZIMBRA_USER" -c "zmmailbox -z -m '$acc' postRestURL '/?fmt=tgz&resolve=skip' '$f'" 2>&1) || true
    echo "$restore_output" >> /tmp/zimbra-restore.log
    
    if echo "$restore_output" | grep -qi "usage:\|error\|exception\|fail"; then
      fail=$((fail+1)); fail "      ✗ $acc"
      log "   Error: $(echo "$restore_output" | head -2)"
    else
      ok=$((ok+1)); pass "      ✓ $acc"
    fi
  done
  echo ""; pass "   Mailboxes: $ok ok, $fail fail"
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: PREFERENCES (FIXED: Better HTML extraction)
# ─────────────────────────────────────────────────────────────────────────────
restore_preferences() {
  log "Restoring user preferences (signatures, filters, forwarding, status)..."
  local dir="$BACKUP_ROOT/mailboxes/$BACKUP_DATE"
  if [ ! -d "$dir" ]; then
    warn "   Not found"
    return 1
  fi
  
  local ok=0 fail=0
  for pref_file in "$dir"/*-preferences.txt; do
    [ -f "$pref_file" ] || continue
    local fn
    fn=$(basename "$pref_file" -preferences.txt)
    local acc
    acc=$(pref_filename_to_account "$fn")
    
    echo "$acc" | grep -q "@" || continue
    should_restore "$acc" || continue
    account_exists "$acc" || continue
    
    log "   Restoring preferences: $acc"
    
    local applied=0
    local failed_list=""
    
    # ───────────────────────────────────────────────────────────────────────
    # 1. Restore Account Status
    # ───────────────────────────────────────────────────────────────────────
    local value
    value=$(get_pref_value_multiline "$pref_file" "zimbraAccountStatus")
    if [ -n "$value" ] && [ "$value" != "zimbraAccountStatus" ]; then
      log "     Setting zimbraAccountStatus: $value"
      if set_zimbra_attr "$acc" "zimbraAccountStatus" "$value"; then
        applied=$((applied+1))
        log "     ✓ Applied zimbraAccountStatus"
      else
        failed_list="${failed_list}zimbraAccountStatus,"
        log "     ✗ Failed zimbraAccountStatus"
      fi
    fi
    
    # ───────────────────────────────────────────────────────────────────────
    # 2. Restore Signature (FIXED: Better HTML extraction)
    # ───────────────────────────────────────────────────────────────────────
    local sig_name sig_html
    sig_name=$(get_pref_value_multiline "$pref_file" "zimbraSignatureName")
    sig_html=$(get_pref_value_multiline "$pref_file" "zimbraPrefMailSignatureHTML")
    
    # Debug: show what we extracted
    if [ -n "$sig_name" ]; then
      log "     Found signature name: $sig_name"
    fi
    if [ -n "$sig_html" ]; then
      log "     Found signature HTML: $(echo "$sig_html" | head -c 100)..."
    fi
    
    if [ -n "$sig_name" ] && [ -n "$sig_html" ]; then
      log "     Restoring signature: $sig_name"
      
      # Step 1: Set signature name
      if set_zimbra_attr "$acc" "zimbraSignatureName" "$sig_name"; then
        log "     ✓ Set signature name"
        
        # Small delay to let Zimbra index
        sleep 1
        
        # Step 2: Get signature ID
        local sig_id
        sig_id=$(get_zimbra_attr "$acc" "zimbraSignatureId")
        
        if [ -n "$sig_id" ]; then
          log "     ✓ Got signature ID: $sig_id"
          
          # Step 3: Set HTML content
          local escaped_html
          escaped_html=$(printf '%s' "$sig_html" | sed "s/'/\\\\'/g" | tr '\n' ' ' | head -c 5000)
          
          log "     Setting signature HTML (${#escaped_html} chars)"
          if set_zimbra_attr "$acc" "zimbraPrefMailSignatureHTML" "$escaped_html"; then
            log "     ✓ Set signature HTML"
            applied=$((applied+1))
            
            # Step 4: Set default signature ID
            if set_zimbra_attr "$acc" "zimbraPrefDefaultSignatureId" "$sig_id"; then
              log "     ✓ Set default signature ID"
              applied=$((applied+1))
            else
              log "     ⚠ Could not set default signature ID"
            fi
            
            # Step 5: Set forward/reply signature ID
            if set_zimbra_attr "$acc" "zimbraPrefForwardReplySignatureId" "$sig_id"; then
              log "     ✓ Set forward/reply signature ID"
              applied=$((applied+1))
            else
              log "     ⚠ Could not set forward/reply signature ID"
            fi
          else
            log "     ✗ Failed to set signature HTML (value too long?)"
            failed_list="${failed_list}signature_html,"
          fi
        else
          log "     ✗ Could not get signature ID (timeout or not found)"
          # Fallback: use ID from backup
          local backup_sig_id
          backup_sig_id=$(get_pref_value_multiline "$pref_file" "zimbraPrefDefaultSignatureId")
          if [ -n "$backup_sig_id" ] && [ "$backup_sig_id" != "zimbraPrefDefaultSignatureId" ]; then
            log "     ⚠ Using backup signature ID: $backup_sig_id"
            if set_zimbra_attr "$acc" "zimbraPrefDefaultSignatureId" "$backup_sig_id"; then
              applied=$((applied+1))
              log "     ✓ Set default signature ID from backup"
            fi
          fi
          failed_list="${failed_list}signature_id,"
        fi
      else
        log "     ✗ Failed to set signature name"
        failed_list="${failed_list}signature_name,"
      fi
    elif [ -n "$sig_name" ]; then
      log "     ⚠ Signature name found but no HTML content in backup"
    fi
    
    # ───────────────────────────────────────────────────────────────────────
    # 3. Restore Forwarding Address
    # ───────────────────────────────────────────────────────────────────────
    local fwd_addr
    fwd_addr=$(get_pref_value_multiline "$pref_file" "zimbraPrefMailForwardingAddress")
    if [ -n "$fwd_addr" ] && [ "$fwd_addr" != "zimbraPrefMailForwardingAddress" ]; then
      log "     Setting forwarding: $fwd_addr"
      if set_zimbra_attr "$acc" "zimbraPrefMailForwardingAddress" "$fwd_addr"; then
        applied=$((applied+1))
        log "     ✓ Applied forwarding"
      else
        failed_list="${failed_list}forwarding,"
        log "     ✗ Failed forwarding"
      fi
    fi
    
    # ───────────────────────────────────────────────────────────────────────
    # 4. Restore Filters (Sieve Script)
    # ───────────────────────────────────────────────────────────────────────
    local sieve_script
    sieve_script=$(get_pref_value_multiline "$pref_file" "zimbraMailSieveScript")
    if [ -n "$sieve_script" ] && [ "$sieve_script" != "zimbraMailSieveScript" ]; then
      log "     Restoring filters (Sieve script)..."
      
      if echo "$sieve_script" | grep -q "^require"; then
        local escaped_sieve
        escaped_sieve=$(printf '%s' "$sieve_script" | sed "s/'/\\\\'/g" | head -c 10000)
        
        if timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov ma '$acc' zimbraMailSieveScript '$escaped_sieve'" 2>/dev/null; then
          applied=$((applied+1))
          log "     ✓ Applied Sieve script"
        else
          log "     ✗ Failed to apply Sieve script"
          failed_list="${failed_list}filters,"
        fi
      else
        log "     ⚠ Invalid Sieve script"
      fi
    fi
    
    # Summary
    if [ "$applied" -gt 0 ]; then
      ok=$((ok+1))
      local msg="✓ $acc ($applied settings)"
      if [ -n "$failed_list" ]; then
        msg="${msg}, failed:$(echo "$failed_list" | sed 's/,$//')"
      fi
      pass "      $msg"
    else
      fail=$((fail+1)); warn "      ✗ $acc (no settings applied)"
    fi
  done
  echo ""; pass "   Preferences: $ok ok, $fail fail"
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: DISTRIBUTION LISTS
# ─────────────────────────────────────────────────────────────────────────────
restore_dls() {
  log "Restoring distribution lists..."
  local dl_file="$BACKUP_ROOT/distribution-lists/distribution-lists-${BACKUP_DATE}.txt"
  if [ ! -f "$dl_file" ]; then
    warn "   Not found"
    return 1
  fi
  
  local count
  count=$(wc -l < "$dl_file")
  log "   Found $count DL(s)"
  
  local dl_ok=0 member_ok=0
  while IFS= read -r dl; do
    [ -z "$dl" ] && continue
    log "   Restoring DL: $dl"
    timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov cdl '$dl'" 2>/dev/null || true
    
    local dl_safe
    dl_safe=$(echo "$dl" | tr '@' '_' | tr '.' '_')
    local member_file="$BACKUP_ROOT/distribution-lists/dl-members-${dl_safe}-${BACKUP_DATE}.txt"
    
    if [ -f "$member_file" ]; then
      local m_ok=0
      while IFS= read -r member; do
        [ -z "$member" ] && continue
        [[ "$member" =~ ^# ]] && continue
        [ "$member" = "members" ] && continue
        echo "$member" | grep -qE "^[^@]+@[^@]+\.[^@]+$" || continue
        
        if account_exists "$member"; then
          timeout "$ZMPROV_TIMEOUT" su - "$ZIMBRA_USER" -c "zmprov adlm '$dl' '$member'" 2>/dev/null && m_ok=$((m_ok+1))
        else
          log "      ⚠ Member not found: $member"
        fi
      done < "$member_file"
      member_ok=$((member_ok + m_ok))
      pass "      ✓ $dl ($m_ok members)"
      dl_ok=$((dl_ok+1))
    else
      warn "      ✗ $dl (no member file)"
    fi
  done < "$dl_file"
  
  echo ""; pass "   DLs: $dl_ok restored, $member_ok total members"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
log "Starting restore..."
echo ""

echo ",$MODES," | grep -q ",passwords," && { restore_passwords; echo ""; }
echo ",$MODES," | grep -q ",mailboxes," && { restore_mailboxes; echo ""; }
echo ",$MODES," | grep -q ",preferences," && { restore_preferences; echo ""; }
echo ",$MODES," | grep -q ",distribution-lists," && { restore_dls; echo ""; }

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  RESTORE COMPLETED${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Log: /tmp/zimbra-restore.log"
echo -e "${YELLOW}Verify:${NC}"
echo -e "  su - zimbra -c 'zmprov ga user@$DOMAIN zimbraPrefMailSignatureHTML' | head -3"
echo -e "  su - zimbra -c 'zmprov ga user@$DOMAIN zimbraAccountStatus'"
echo -e "${GREEN}========================================================${NC}\n"
