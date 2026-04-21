#!/bin/bash
# zimbra-restore.sh v1.7
# FINAL: Fixed domain parsing + separate handlers for password/mailbox filename formats
# Usage: sudo bash zimbra-restore.sh --mode MODES [FILTERS] BACKUP_DATE

set -u

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

# ─────────────────────────────────────────────────────────────────────────────
# GET DOMAIN FROM BACKUP (FIXED)
# ─────────────────────────────────────────────────────────────────────────────
get_backup_domain() {
  local domain_file="$BACKUP_ROOT/distribution-lists/domains-${BACKUP_DATE}.txt"
  if [ -f "$domain_file" ]; then
    # Read first non-empty line, remove all whitespace
    local domain=$(grep -v '^$' "$domain_file" | head -1 | tr -d '[:space:]')
    if [ -n "$domain" ] && echo "$domain" | grep -q '\.'; then
      echo "$domain"
      return 0
    fi
  fi
  # Fallback
  echo "$(hostname -d)"
}

DOMAIN=$(get_backup_domain)
log "Using domain: $DOMAIN"

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
      echo "MODES: passwords, mailboxes, distribution-lists, all"
      echo "Example: sudo bash zimbra-restore.sh --mode all 20260420"
      exit 0
      ;;
    *) [ -z "$BACKUP_DATE" ] && BACKUP_DATE="$1" || err "Unknown: $1"; shift ;;
  esac
done

[ -z "$BACKUP_DATE" ] && err "Backup date required"
[ -z "$MODES" ] && err "Mode required"
[ "$MODES" = "all" ] && MODES="passwords,mailboxes,distribution-lists"

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}  Zimbra Restore Script v1.7${NC}"
echo -e "${GREEN}========================================================${NC}\n"

log "Backup: $BACKUP_DATE | Domain: $DOMAIN | Modes: $MODES"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# FILENAME PARSING (FIXED for your format)
# ─────────────────────────────────────────────────────────────────────────────

# Password file: admin.noob_newbienotes.my.id.shadow → admin.noob@newbienotes.my.id
password_filename_to_account() {
  local filename="$1"  # e.g., "admin.noob_newbienotes.my.id"
  # Replace FIRST underscore with @
  echo "$filename" | sed 's/_/@/'
}

# Mailbox file: admin.noob.tgz → admin.noob@newbienotes.my.id (using $DOMAIN)
mailbox_filename_to_account() {
  local filename="$1"  # e.g., "admin.noob"
  echo "${filename}@${DOMAIN}"
}

# DL member file: dl-members-officer_newbienotes_my_id-DATE.txt → officer@newbienotes.my.id
dl_filename_to_email() {
  local filename="$1"  # e.g., "dl-members-officer_newbienotes_my_id-20260420.txt"
  # Extract: officer_newbienotes_my_id → officer@newbienotes.my.id
  local dl_part=$(echo "$filename" | sed 's/^dl-members-//' | sed 's/-[0-9]\{8\}\.txt$//')
  echo "$dl_part" | sed 's/_/@/' | sed 's/@\([^.]*\)_/\1./'
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
get_account_status() {
  local account="$1"
  local safe=$(echo "$account" | tr '@' '_')
  local pref="$BACKUP_ROOT/mailboxes/$BACKUP_DATE/${safe}-preferences.txt"
  [ -f "$pref" ] && grep "^zimbraAccountStatus:" "$pref" 2>/dev/null | awk '{print $2}' || echo "active"
}

should_restore() {
  local acc="$1"
  [ -n "$SINGLE_USER" ] && { [ "$acc" = "$SINGLE_USER" ]; return $?; }
  [ "$STATUS_FILTER" = "all" ] && return 0
  local status=$(get_account_status "$acc")
  [ -n "$STATUS_FILTER" ] && { echo ",$STATUS_FILTER," | grep -q ",$status,"; return $?; }
  echo ",$DEFAULT_STATUS," | grep -q ",$status,"
}

account_exists() {
  su - $ZIMBRA_USER -c "zmprov ga '$1' &>/dev/null" 2>/dev/null
}

create_account() {
  local acc="$1" pwd="$2"
  log "   Creating: $acc"
  su - $ZIMBRA_USER -c "zmprov ca '$acc' '$pwd'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: PASSWORDS
# ─────────────────────────────────────────────────────────────────────────────
restore_passwords() {
  log "Restoring passwords..."
  local dir="$BACKUP_ROOT/passwords/$BACKUP_DATE"
  [ ! -d "$dir" ] && { warn "   Not found"; return 1; }
  
  local ok=0 fail=0
  for f in "$dir"/*.shadow; do
    [ -f "$f" ] || continue
    local fn=$(basename "$f" .shadow)
    local acc=$(password_filename_to_account "$fn")
    
    should_restore "$acc" || continue
    account_exists "$acc" || create_account "$acc" "TempRestore123!"
    
    local hash=$(cat "$f")
    [ -n "$hash" ] && {
      log "   Setting password: $acc"
      su - $ZIMBRA_USER -c "zmprov ma '$acc' userPassword '$hash'" 2>&1 | tee -a /tmp/zimbra-restore.log >/dev/null
      [ $? -eq 0 ] && { ok=$((ok+1)); pass "      ✓ $acc"; } || { fail=$((fail+1)); fail "      ✗ $acc"; }
    }
  done
  echo ""; pass "   Passwords: $ok ok, $fail fail"
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: MAILBOXES (FIXED filename parsing)
# ─────────────────────────────────────────────────────────────────────────────
restore_mailboxes() {
  log "Restoring mailboxes..."
  local dir="$BACKUP_ROOT/mailboxes/$BACKUP_DATE"
  [ ! -d "$dir" ] && { warn "   Not found"; return 1; }
  
  shopt -s nullglob
  local files=("$dir"/*.tgz)
  shopt -u nullglob
  log "   Found ${#files[@]} backup file(s)"
  [ ${#files[@]} -eq 0 ] && { warn "   No .tgz files!"; ls "$dir/"; return 1; }
  
  local ok=0 fail=0
  for f in "${files[@]}"; do
    local fn=$(basename "$f" .tgz)
    local acc=$(mailbox_filename_to_account "$fn")  # Uses $DOMAIN
    
    log "   Processing: $fn → $acc"
    echo "$acc" | grep -q "@" || { warn "   Invalid: $acc"; continue; }
    should_restore "$acc" || continue
    
    account_exists "$acc" || create_account "$acc" "TempRestore123!"
    
    log "   Restoring mailbox: $acc"
    local out=$(su - $ZIMBRA_USER -c "zmrestore -a '$acc' '$f'" 2>&1)
    echo "$out" >> /tmp/zimbra-restore.log
    [ $? -eq 0 ] && { ok=$((ok+1)); pass "      ✓ $acc"; } || { fail=$((fail+1)); fail "      ✗ $acc ($out)"; }
  done
  echo ""; pass "   Mailboxes: $ok ok, $fail fail"
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE: DISTRIBUTION LISTS
# ─────────────────────────────────────────────────────────────────────────────
restore_dls() {
  log "Restoring distribution lists..."
  local dl_file="$BACKUP_ROOT/distribution-lists/distribution-lists-${BACKUP_DATE}.txt"
  [ ! -f "$dl_file" ] && { warn "   Not found"; return 1; }
  
  local count=$(wc -l < "$dl_file")
  log "   Found $count DL(s)"
  
  local dl_ok=0 member_ok=0
  while IFS= read -r dl; do
    [ -z "$dl" ] && continue
    log "   Restoring DL: $dl"
    su - $ZIMBRA_USER -c "zmprov cdl '$dl'" 2>/dev/null || true
    
    # Build member filename: officer@newbienotes.my.id → dl-members-officer_newbienotes_my_id-DATE.txt
    local dl_safe=$(echo "$dl" | tr '@' '_' | tr '.' '_')
    local member_file="$BACKUP_ROOT/distribution-lists/dl-members-${dl_safe}-${BACKUP_DATE}.txt"
    
    if [ -f "$member_file" ]; then
      local m_ok=0
      while IFS= read -r member; do
        [ -z "$member" ] && continue
        [[ "$member" =~ ^# ]] && continue
        [ "$member" = "members" ] && continue
        echo "$member" | grep -qE "^[^@]+@[^@]+\.[^@]+$" || continue
        
        # Only add if member account exists
        if account_exists "$member"; then
          su - $ZIMBRA_USER -c "zmprov adlm '$dl' '$member'" 2>/dev/null && m_ok=$((m_ok+1))
        else
          log "      ⚠ Member not found: $member"
        fi
      done < "$member_file"
      member_ok=$((member_ok + m_ok))
      pass "      ✓ $dl ($m_ok members)"
      dl_ok=$((dl_ok+1))
    else
      warn "      ✗ $dl (no member file: $member_file)"
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
echo ",$MODES," | grep -q ",distribution-lists," && { restore_dls; echo ""; }

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  RESTORE COMPLETED${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "Log: /tmp/zimbra-restore.log"
echo -e "${YELLOW}Verify:${NC}"
echo -e "  su - zimbra -c 'zmprov gaa | grep $DOMAIN'"
echo -e "  su - zimbra -c 'zmprov gdlm officer@$DOMAIN'"
echo -e "${GREEN}========================================================${NC}\n"
