#!/bin/bash
# secret-deny-patterns.sh - THE single shared list of secret-shaped path
# patterns. Sourced by both the triage claim hard-stop and the push gate's
# outbound scan, so the two can never drift. Edit the list HERE only.
#
# Principle: high-precision patterns only. A false-positive hard-stop trains
# users to override the protection, which defeats it. Match key MATERIAL by
# extension or exact basename - never a substring like *key* (which would
# hard-stop keyboard.ts, key-utils.sh, monkey.png).

# Deny patterns (basename globs)
SECRET_DENY_PATTERNS=(
  ".env" ".env.*"
  "*.pem"
  "*.key" "*.keystore" "*.jks"
  "*.p12" "*.pfx"
  "id_rsa" "id_dsa" "id_ecdsa" "id_ed25519"
  "*.ppk"
  "credentials.json" "*-credentials.json"
)

# Negations: conventional safe-to-commit templates that .env.* would catch.
# Applied before the deny list - a negation match always wins.
SECRET_ALLOW_PATTERNS=(
  ".env.example" ".env.sample" ".env.template"
)

# matches_secret_pattern <path> - exit 0 if the path is secret-shaped,
# exit 1 otherwise. Matches against the basename only.
matches_secret_pattern() {
  local base pat
  base="$(basename "$1")"
  for pat in "${SECRET_ALLOW_PATTERNS[@]}"; do
    case "$base" in
      $pat) return 1 ;;
    esac
  done
  for pat in "${SECRET_DENY_PATTERNS[@]}"; do
    case "$base" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# CLI convenience when executed directly: secret-deny-patterns.sh <path>
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if matches_secret_pattern "${1:?usage: secret-deny-patterns.sh <path>}"; then
    echo "match"
    exit 0
  else
    exit 1
  fi
fi
