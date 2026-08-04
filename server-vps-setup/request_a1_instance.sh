#!/usr/bin/env bash
#
# request_a1_instance.sh — keep trying to launch a free Ampere A1 instance until
# Oracle actually has capacity. Free A1 is chronically "Out of host capacity";
# the reliable way to grab one is to retry the launch on a loop and catch that
# specific error. When a slot frees up, the launch succeeds and the loop stops.
#
# ── WHERE TO RUN ─────────────────────────────────────────────────────────────
# Run this ON the free OCI instance (VPS): it's always-on, in-region (me-dubai-1)
# and already lives in the same Oracle account/tenancy that will own the new A1.
#
# ── One-time prep on oracle-dxb ──────────────────────────────────────────────
#   1) Install OCI CLI:
#        bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
#   2) Create an API key (Console → Profile → API Keys → Add), then configure
#      (paste tenancy/user OCID + fingerprint + key; region = me-dubai-1):
#        oci setup config
#      Verify:  oci iam region list >/dev/null && echo OK
#   3) BILLING BACKSTOP (do once): confirm the account shows "Always Free", and
#      set a low budget alert as a safety net — Console → Billing & Cost
#      Management → Budgets → Create Budget (e.g. $1, email alert at 100%).
#      Failed launches create no resource, so the loop is $0; a 4-OCPU/24GB A1 +
#      100GB boot volume is within Always Free (200GB total), so a *successful*
#      launch is $0 too.
#      The alert only ever matters if the account was upgraded to Pay-As-You-Go.
#   4) Fill the OCIDs in the CONFIG block below (helper commands are in comments).
#
# ── Run it under tmux (so it survives SSH disconnects) ───────────────────────
#        tmux new -s a1                 # start a named session
#        ./request_a1_instance.sh       # start the loop inside it
#        #   detach & leave running:    press  Ctrl-b  then  d
#        tmux attach -t a1              # re-attach later to watch progress
#        tmux ls                        # list running sessions
#   The loop stops itself the instant it grabs an instance (prints the OCID), or
#   on a real error (quota/auth/misconfig). Capacity misses just keep retrying.
#
# ── When it SUCCEEDS: migrate make-before-break (no downtime, no charges) ─────
#   The old E2.1.Micro and the new A1 are SEPARATE free quotas, so running both
#   at once is fine and free. Do NOT kill the micro until the A1 is proven:
#     1) SSH to the new A1 and run:   ./setup_vps_relay.sh 100.125.140.11 32400
#                                     ./setup_bbr.sh
#     2) Open TCP 32400 (0.0.0.0/0) in the A1's VCN Security List / NSG.
#     3) From home:  curl http://<NEW_A1_PUBLIC_IP>:32400/identity   → expect 200
#     4) In Plex, put the new IP FIRST, old dxb as fallback:
#          customConnections = http://<NEW_A1_IP>:32400,http://141.145.152.160:32400
#     5) Test remote playback. After a day or two of confidence:
#     6) Drop the old dxb entry from customConnections, remove its node in the
#        Tailscale admin, and TERMINATE the old micro (let it delete its boot
#        volume). Stopping or terminating a free micro costs nothing.
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail   # deliberately NOT -e: launch failures are expected and handled

### ── CONFIG — fill these in ──────────────────────────────────────────────────
# Compartment (root tenancy OCID is fine):        oci iam compartment list --query 'data[].{name:name,id:id}' --output table
COMPARTMENT_OCID="ocid1.tenancy.oc1..aaaaaaaasvluh5nx5hlkysoknn2vvkjswfsvhuy7vnholttpys2obtkrlcza"
# Reuse oracle-dxb's existing subnet:              oci network subnet list -c "$COMPARTMENT_OCID" --query 'data[].{name:"display-name",id:id}' --output table
SUBNET_OCID="ocid1.subnet.oc1.me-dubai-1.aaaaaaaafvknrh22ubfvr6pli7vrv7ef3wy7m5llev3lcsdo2344gdzexg6a"
# Ubuntu ARM (aarch64) image for A1:
#   oci compute image list -c "$COMPARTMENT_OCID" --operating-system "Canonical Ubuntu" \
#       --operating-system-version "22.04" --shape VM.Standard.A1.Flex \
#       --query 'data[0].id' --raw-output
IMAGE_OCID="ocid1.image.oc1.me-dubai-1.aaaaaaaadw6c22i47hgflxqqd7yle7hxrtl4bh34z6jglirfvrsys55z2b2a"  # Canonical-Ubuntu-24.04-aarch64 (ARM — required for A1.Flex)
SSH_PUBKEY_FILE="$HOME/.ssh/a1_authorized.pub"  # SSH public key(s) to log into the new VM — NOT the OCI API key. One key per line.
DISPLAY_NAME="dxb-a1-relay"
OCPUS=4
MEM_GB=24
# Always Free = 200GB TOTAL block storage across ALL volumes. oracle-dxb's micro
# ALREADY uses a 100GB boot volume, so during the migration overlap keep this at
# 100 (100 + 100 = 200, exactly the cap — a larger value can make the launch fail
# on the storage limit, or bill overage on PAYG). After you TERMINATE the micro
# you can expand the A1 up to 200GB (Console → Boot Volume → Edit → resize, then
# grow the partition on the VM). Min boot volume is 50GB.
BOOT_VOL_GB=100
# Availability domain(s) to try. me-dubai-1 usually has one; list them with:
#   oci iam availability-domain list --query 'data[].name' --raw-output
ADS=( "PXZC:ME-DUBAI-1-AD-1" )
SLEEP_SECONDS=60                                 # wait between rounds; be gentle, OCI throttles
NOTIFY_CMD='curl -s -d "A1 landed in me-dubai-1" ntfy.sh/abdullah-a1-9f3k2x'   # runs on success (must be a full command)
### ───────────────────────────────────────────────────────────────────────────

command -v oci >/dev/null 2>&1 || { echo "ERROR: OCI CLI not installed (see prep in header)."; exit 1; }
[[ -f "$SSH_PUBKEY_FILE" ]] || { echo "ERROR: SSH public key not found: $SSH_PUBKEY_FILE"; exit 1; }
[[ "$COMPARTMENT_OCID" == *CHANGE_ME* ]] && { echo "ERROR: fill in the CONFIG block first."; exit 1; }

echo "Hunting for VM.Standard.A1.Flex ($OCPUS OCPU / ${MEM_GB}GB) — Ctrl-C to stop."
attempt=0
while true; do
    attempt=$((attempt + 1))
    for AD in "${ADS[@]}"; do
        printf '[%s] attempt #%d in %s ... ' "$(date '+%F %T')" "$attempt" "$AD"
        OUT="$(oci compute instance launch \
            --compartment-id "$COMPARTMENT_OCID" \
            --availability-domain "$AD" \
            --shape "VM.Standard.A1.Flex" \
            --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM_GB}" \
            --subnet-id "$SUBNET_OCID" \
            --assign-public-ip true \
            --image-id "$IMAGE_OCID" \
            --boot-volume-size-in-gbs "$BOOT_VOL_GB" \
            --display-name "$DISPLAY_NAME" \
            --ssh-authorized-keys-file "$SSH_PUBKEY_FILE" 2>&1)"
        rc=$?

        if [[ $rc -eq 0 ]]; then
            OCID="$(printf '%s' "$OUT" | grep -oE 'ocid1\.instance\.[a-z0-9._-]+' | head -1)"
            echo "SUCCESS"
            echo "Launched instance: $OCID"
            [[ -n "$NOTIFY_CMD" ]] && eval "$NOTIFY_CMD"
            exit 0
        fi

        # Classify the failure so we retry ONLY on capacity, not on real errors.
        if printf '%s' "$OUT" | grep -qiE 'Out of host capacity|Out of capacity|InternalError|500'; then
            echo "no capacity yet"
        elif printf '%s' "$OUT" | grep -qiE 'TooManyRequests|429'; then
            echo "rate-limited (TooManyRequests) — backing off, will retry"
        elif printf '%s' "$OUT" | grep -qiE 'RequestException|connection to endpoint timed out|ConnectTimeout|ReadTimeout|Read timed out|timed out|ConnectionError|Max retries exceeded|ServiceUnavailable|503|Temporary failure|Could not connect|Name or service not known'; then
            echo "transient network/timeout — will retry"
        elif printf '%s' "$OUT" | grep -qiE 'LimitExceeded|quota|exceed'; then
            echo "LIMIT/QUOTA — you may already hold your free A1 allotment. Stopping."
            echo "$OUT"; exit 2
        elif printf '%s' "$OUT" | grep -qiE 'NotAuthenticated|NotAuthorized|401|403'; then
            echo "AUTH error — check ~/.oci/config / API key. Stopping."
            echo "$OUT"; exit 3
        else
            echo "unexpected error — check the CONFIG OCIDs. Stopping."
            echo "$OUT"; exit 4
        fi
    done
    sleep "$SLEEP_SECONDS"
done
