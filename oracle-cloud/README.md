# oracle-cloud

OCI CLI setup and scripts for this tenancy (home region `me-dubai-1`, account
owning `oracle-dxb`).

## One-time setup

Install the CLI via brew — **never** Oracle's `curl | bash` installer (it
self-manages a Python venv under `~/lib/oracle-cli` and rewrites `~/.bashrc`;
brew keeps it inside the same package-managed toolchain as everything else on
this box):

```
brew install oci-cli
```

Create an API signing key and write the config:

```
oci setup config
```

It'll prompt for:
- **user OCID** / **tenancy OCID** — Console → Profile menu (top right) →
  Tenancy / User Settings
- **region** — `me-dubai-1`
- whether to generate a new RSA key pair — yes, unless you already have one

This writes `~/.oci/config` and drops a key pair in `~/.oci/`. Then go to
Console → Profile → **API Keys** → Add API Key, and paste the contents of the
generated `*_public.pem`.

Verify:

```
oci iam region list >/dev/null && echo OK
```

Lock down the private key (the installer doesn't always do this):

```
chmod 600 ~/.oci/oci_api_key.pem
```

## `.env`

Every script in this directory sources `.env` (gitignored — copy it from
`.env.example`) for the OCIDs: tenancy, user, compartment, region, and the
subnet/image `request_a1_instance.sh` launches into. Fill it in once after
`oci setup config`; scripts fail fast with a clear error if a value is
missing.

Scripts source `.env` on their own — nothing to do there. For running the
ad-hoc `oci` commands below by hand in your shell, export the same variables
first:

```
cd oracle-cloud
set -a; source .env; set +a
```

`set -a` marks every variable sourced afterward for export, so `$TENANCY_OCID`,
`$COMPARTMENT_OCID`, etc. are visible to `oci` without prefixing each command.
`set +a` turns that back off so it doesn't leak into unrelated exports for the
rest of the shell session.

## Scripts

- **`request_a1_instance.sh`** — loops `oci compute instance launch` for a
  free `VM.Standard.A1.Flex` until Oracle has capacity (chronically
  "Out of host capacity" in most regions). Run under `tmux` — see the
  script's header for full usage and the make-before-break migration steps
  once it succeeds.

## Checking Always Free usage

The free A1 allowance is OCPU-hours and GB-hours per tenancy per month —
`shape × uptime`, not something that needs polling (2 OCPUs running 24/7
deterministically burns ~1,488 of 1,500 hours every month). What's actually
worth checking:

**Provisioned cores vs. the hard limit** — the number that determines whether
a launch will even succeed:

```
oci limits resource-availability get \
  --compartment-id "$COMPARTMENT_OCID" --service-name compute \
  --limit-name standard-a1-core-count \
  --availability-domain "$(oci iam availability-domain list --query 'data[0].name' --raw-output)"
```

Or Console → Governance & Administration → Tenancy Management → **Limits,
Quotas and Usage** → Service = Compute → search `standard-a1`.

**Usage quantities for the month** (free line items show $0 cost but report
real OCPU-hour / GB-hour quantities; command is `usage-summary
request-summarized-usages`, not `request-summarized-usages` at the top level
— the CLI nests it under a `usage-summary` group):

```
oci usage-api usage-summary request-summarized-usages \
  --tenant-id "$TENANCY_OCID" \
  --time-usage-started "$(date -u +%Y-%m-01T00:00:00Z)" \
  --time-usage-ended "$(date -u -d 'next month' +%Y-%m-01T00:00:00Z)" \
  --granularity MONTHLY --query-type USAGE \
  --group-by '["skuName"]' \
  --query "data.items[?contains(\"sku-name\", 'A1')].{sku:\"sku-name\",qty:\"computed-quantity\",unit:unit}"
```

Without the `--query` filter it returns every SKU used this month (block
storage, monitoring, etc.) — the filter narrows to just the two A1 lines:
`Standard - A1` (OCPU-hours) and `Standard - A1 - Memory` (GB-hours).

Or Console → Billing & Cost Management → **Cost Analysis** → filter
Service = Compute, toggle the metric from Cost to Usage.

**Billing tripwire** — a $1 budget with an alert at 1% (Console → Billing &
Cost Management → Budgets). Doesn't track the free pool, but fires the moment
anything actually starts costing money.

**What OCI's usage tools *can't* see**: idle-reclamation risk (Oracle
reclaims Always Free A1 instances idling under 20% CPU/network/memory over a
7-day window) and cumulative egress against the 10 TB/month cap. Both are
better watched with Beszel (CPU/mem/network history) and `vnstat -m`
(per-month egress counter) running on the instance itself.
