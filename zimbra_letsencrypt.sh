# ─────────────────────────────────────────────────────────────────────────────
# USER INPUT (Email Optional)
# ─────────────────────────────────────────────────────────────────────────────
read -rp "Masukkan FQDN Zimbra (contoh: mail.example.com): " FQDN
read -rp "Email untuk recovery account ACME (opsional, tekan Enter untuk skip): " LE_EMAIL

[[ -z "$FQDN" ]] && err "FQDN wajib diisi."

# ─────────────────────────────────────────────────────────────────────────────
# INSTALL DEPENDENCIES
# ─────────────────────────────────────────────────────────────────────────────
log "Installing Certbot & dependencies..."
apt-get update -y
apt-get install -y certbot python3-certbot-standalone

# ─────────────────────────────────────────────────────────────────────────────
# PREPARE ZIMBRA SSL DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────
SSL_DIR="/opt/zimbra/ssl/letsencrypt"
log "Preparing Zimbra SSL directory..."
mkdir -p "$SSL_DIR"
chown -R zimbra:zimbra "$SSL_DIR"
chmod 700 "$SSL_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# ISSUE CERTIFICATE (Standalone Mode, Email Optional)
# ─────────────────────────────────────────────────────────────────────────────
log "Stopping Zimbra web services to free port 80..."
su - zimbra -c "zmproxyctl stop; zmmailboxdctl stop" 2>/dev/null || warn "Some Zimbra services already stopped."

log "Requesting Let's Encrypt certificate for $FQDN..."

if [[ -n "$LE_EMAIL" ]]; then
  # Dengan email (untuk account recovery)
  certbot certonly \
    --standalone \
    --preferred-challenges http \
    -d "$FQDN" \
    --email "$LE_EMAIL" \
    --agree-tos \
    --non-interactive \
    --expand \
    --keep-until-expiring \
    --cert-name "$FQDN" \
    2>&1 | tee -a "$LOG_FILE"
else
  # Tanpa email (mode unsafely, tapi aman untuk auto-renewal)
  warn "Tidak ada email yang diberikan. Account recovery akan terbatas."
  certbot certonly \
    --standalone \
    --preferred-challenges http \
    -d "$FQDN" \
    --register-unsafely-without-email \
    --agree-tos \
    --non-interactive \
    --expand \
    --keep-until-expiring \
    --cert-name "$FQDN" \
    2>&1 | tee -a "$LOG_FILE"
fi

if [[ ! -d "/etc/letsencrypt/live/$FQDN" ]]; then
  err "Certificate issuance failed. Check log: $LOG_FILE"
fi
log "Certificate issued successfully."
