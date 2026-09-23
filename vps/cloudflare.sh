#!/usr/bin/env bash
#
# Cloudflare cache and DNS for the zones this VPS serves, from the VPS.
#
# Usage: ./cloudflare.sh <command> [args]
#   whoami              verify the token and show what it can reach
#   zones               list the zones the token can see, with ids
#   dns [zone]          list DNS records; no zone = every zone in CF_ZONES
#   purge [zone]        purge everything; no zone = every zone in CF_ZONES
#   purge-url <url>...  purge specific URLs (Cloudflare caps each call at 30)
#
# Reads .env next to this script:
#   CF_API_TOKEN=...                          required
#   CF_ZONES="abdullah.run abdullah.diy"      optional, this is the default
#
# Create the token at dash.cloudflare.com > My Profile > API Tokens >
# Create Token > Create Custom Token, with these permissions:
#   Zone > Zone        > Read     (resolve a zone name to its id)
#   Zone > Cache Purge > Purge
#   Zone > DNS         > Read     (add Edit only if you want to write records)
# Under Zone Resources pick Include > Specific zone for each domain, so the
# token cannot touch anything else on the account.
#
# Use a scoped API Token, never the Global API Key — the Global key carries
# full account access, cannot be narrowed, and is the same secret your
# dashboard login protects.
#
# Writing DNS records is deliberately not here: `brew install flarectl` does
# that better than a wrapper would. This script covers the repeatable site
# operations, cache purge above all.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

CF_ZONES="${CF_ZONES:-abdullah.run abdullah.diy}"
API="https://api.cloudflare.com/client/v4"

# Checked here rather than at the top of the script so `help` still works
# with no token and no jq.
preflight() {
    command -v jq >/dev/null || { echo "ERROR: jq is not installed. brew install jq" >&2; exit 1; }
    if [[ -z "${CF_API_TOKEN:-}" ]]; then
        echo "ERROR: CF_API_TOKEN is not set. Put it in .env next to this script." >&2
        echo "       See the header of this file for the token scopes to request." >&2
        exit 1
    fi
}

# Every call goes through here so one place handles the envelope. Cloudflare
# answers 200 with success:false for permission errors, so the HTTP status
# alone is not enough to tell whether the call worked.
cf() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" "$API$path"
                -H "Authorization: Bearer $CF_API_TOKEN"
                -H "Content-Type: application/json")
    [[ -n "$body" ]] && args+=(--data "$body")

    local out
    out="$(curl "${args[@]}")"
    if [[ "$(jq -r '.success' <<<"$out")" != "true" ]]; then
        echo "ERROR: $method $path" >&2
        jq -r '.errors[]? | "  [\(.code)] \(.message)"' <<<"$out" >&2
        return 1
    fi
    printf '%s' "$out"
}

zone_id() {
    local name="$1" id
    id="$(cf GET "/zones?name=$name" | jq -r '.result[0].id // empty')"
    [[ -n "$id" ]] || { echo "ERROR: no zone '$name' visible to this token." >&2; return 1; }
    printf '%s' "$id"
}

# No zone argument means every zone in CF_ZONES.
target_zones() { [[ $# -gt 0 ]] && printf '%s\n' "$@" || printf '%s\n' $CF_ZONES; }

cmd_whoami() {
    cf GET "/user/tokens/verify" | jq -r '"token: \(.result.status)"'
    echo "zones visible to this token:"
    cf GET "/zones" | jq -r '.result[] | "  \(.name)  \(.id)  (\(.status))"'
}

cmd_zones() { cf GET "/zones" | jq -r '.result[] | "\(.name)\t\(.id)\t\(.status)"' | column -t -s $'\t'; }

cmd_dns() {
    local z
    while read -r z; do
        echo "== $z"
        cf GET "/zones/$(zone_id "$z")/dns_records?per_page=100" \
            | jq -r '.result[] | "  \(.type)\t\(.name)\t\(.content)\tproxied=\(.proxied)"' \
            | sort | column -t -s $'\t'
    done < <(target_zones "$@")
}

cmd_purge() {
    local z
    while read -r z; do
        cf POST "/zones/$(zone_id "$z")/purge_cache" '{"purge_everything":true}' >/dev/null
        echo "purged everything: $z"
    done < <(target_zones "$@")
}

# host -> zone name. Suffix match on a dot boundary, so "notabdullah.run"
# does not match the zone "abdullah.run". A plain loop with `return`, not a
# pipe into `head -1`: head closing the pipe early raises SIGPIPE in the
# loop, and under `set -o pipefail` that failed the whole call.
zone_for_host() {
    local host="$1" c
    for c in $CF_ZONES; do
        [[ "$host" == "$c" || "$host" == *".$c" ]] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

# Cloudflare matches files by exact URL, so a purge must name the scheme and
# host it was cached under — https://abdullah.run/style.css, not /style.css.
cmd_purge_url() {
    [[ $# -gt 0 ]] || { echo "ERROR: give at least one full URL." >&2; exit 1; }
    [[ $# -le 30 ]] || { echo "ERROR: Cloudflare caps a purge at 30 URLs per call." >&2; exit 1; }

    local host z id body n
    for host in $(printf '%s\n' "$@" | awk -F/ '{print $3}' | sort -u); do
        if ! z="$(zone_for_host "$host")"; then
            echo "ERROR: '$host' is not under any zone in CF_ZONES ($CF_ZONES)." >&2
            exit 1
        fi
        id="$(zone_id "$z")"
        body="$(printf '%s\n' "$@" | grep -F "//$host/" \
                | jq -Rsc 'split("\n") | map(select(length > 0)) | {files: .}')"
        n="$(jq -r '.files | length' <<<"$body")"
        cf POST "/zones/$id/purge_cache" "$body" >/dev/null
        echo "purged $n url(s) on $host"
    done
}

case "${1:-}" in
    whoami)    shift; preflight; cmd_whoami "$@" ;;
    zones)     shift; preflight; cmd_zones "$@" ;;
    dns)       shift; preflight; cmd_dns "$@" ;;
    purge)     shift; preflight; cmd_purge "$@" ;;
    purge-url) shift; preflight; cmd_purge_url "$@" ;;
    ""|-h|--help|help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "unknown command: $1" >&2; sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1 ;;
esac
