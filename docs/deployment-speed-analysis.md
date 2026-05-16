# Deployment Speed Analysis

## Root Cause Analysis

### Why a single-app selective apply still takes 8 minutes

There are two distinct cost buckets:

**Bucket 1 — Helmfile processing overhead (can be eliminated)**

When you run `helmfile -e demo -l name=drive apply`, helmfile has no way to short-circuit. It must:

1. Parse and execute `helmfile.yaml.gotmpl` (three `---` sections)
2. Load ALL 16 `helmfile-child.yaml.gotmpl` files via the `helmfiles:` list
3. For each child, evaluate every `installed:`, `condition:`, and `needs:` gotmpl expression while loading all 23 `default/*.yaml*` value files
4. Build the full 70-release DAG across all apps
5. **Then** filter to the `drive` releases

Every app's templates are fully rendered before the selector is applied. The selector is a post-processing filter, not a pre-load filter. With 16 apps × ~6 releases × multiple values files each, this is substantial unavoidable I/O and CPU.

**Bucket 2 — Sequential release chain (Kubernetes wait)**

Within drive, the release dependency graph forces three sequential waits:

```
drive-postgresql ─┐
drive-redis      ─┼─→ drive ─→ drive-nginx
drive-minio      ─┘
```

The first tier (postgresql/redis/minio) can run in parallel, but helmfile still waits for ALL of them before starting `drive`, then waits for `drive` before starting `drive-nginx`. With a 600s timeout and Kubernetes readiness probes, this is 2–5 min of sequential blocking even after the DB is up.

There is also no `concurrency` set in `helmDefaults`, which means helmfile's default (unlimited) applies — but this is implicit and not verified. More importantly, there is no `wait: false` option for infra releases that are already running.

---

## Implemented Changes

### Change 1 — Make each app helmfile a standalone entry point (biggest win)

**The problem:** The monolithic `helmfile.yaml.gotmpl` is the only entry point. You cannot target a single app without loading all 16.

**The fix:** A shared `helmfile/bases/child-environments.yaml` is prepended as the first `---` section of each `helmfile-child.yaml.gotmpl`. It declares all environments with the correct value file globs. Since helmfile sub-helmfiles inherit the parent environment when invoked from the parent, this is fully backward-compatible. When invoked directly with `-f`, the child's own environment definitions are used.

Each child now starts with:
```yaml
bases:
  - "../../bases/child-environments.yaml"

---

bases:
  - "../../bases/default.yaml.gotmpl"

releases:
  ...
```

This enables:
```bash
# Instead of (processes all 16 apps before filtering):
helmfile -e demo -l name=drive apply

# Use (processes ONLY drive):
helmfile -e demo -f helmfile/apps/drive/helmfile-child.yaml.gotmpl apply
```

**Savings:** Eliminates ~50–70% of template processing time by loading only one child's releases and values instead of all 16.

---

### Change 2 — Tier labels to skip infra on iterative deploys

**The problem:** Database and cache initialization is paid on every deploy, even when the infra hasn't changed (which is the common case for iterating on application code).

**The fix:** Rather than splitting each child into separate files, all releases in `helmfile-child.yaml.gotmpl` are labelled with their tier:

```yaml
releases:
  - name: drive-postgresql
    labels:
      tier: infra
    ...

  - name: drive-redis
    labels:
      tier: infra
    ...

  - name: drive
    labels:
      tier: app
    ...

  - name: drive-nginx
    labels:
      tier: app
    ...
```

The `scripts/deploy-app.sh` wrapper then exposes two usage patterns:

```bash
# App only — fast path (infra already running):
./scripts/deploy-app.sh drive
# Runs: helmfile -f helmfile/apps/drive/helmfile-child.yaml.gotmpl -l tier=app apply

# Full deploy — infra + app in one invocation, needs: DAG handles ordering:
./scripts/deploy-app.sh drive --with-infra
# Runs: helmfile -f helmfile/apps/drive/helmfile-child.yaml.gotmpl apply
```

For `--with-infra`, a single helmfile invocation without a label filter is used. The existing `needs:` dependencies (e.g. `drive` needs `drive-postgresql`, `drive-redis`, `drive-minio`) already encode the correct ordering within the DAG — there is no need for two sequential shell commands.

**Savings:** For the common case (app redeployment with existing infra), eliminates the 2–4 min DB/Redis/MinIO readiness wait entirely.

---

## Remaining Proposals

### Change 3 — Explicit concurrency and `wait: false` for infra in full deploys

**The problem:** `helmDefaults` does not set `concurrency` or `wait` explicitly. For full deploys where infra needs to come up, the current 3-level chain (infra → app → nginx) means three sequential blocking waits.

**The fix (in `helmfile/bases/default.yaml.gotmpl`):**

```yaml
helmDefaults:
  createNamespace: {{ env "MIJNBUREAU_CREATE_NAMESPACES" | default false }}
  timeout: 600
  insecureSkipTLSVerify: false
  plainHttp: false
  concurrency: 0   # explicit unlimited parallelism
```

Additionally, for infra releases that are expected to take time but don't need to block other apps from starting, set `wait: false` on the infra releases and rely on the app chart's init containers/connection retry. Most Bitnami app charts already retry database connections for 60–120 seconds on startup.

This converts the release graph from strictly sequential to:
```
All apps' infra releases start simultaneously
All apps' app releases start as soon as their own infra is done
All apps' nginx releases start as soon as their own app is done
```

**Expected savings for full deploy:** ~15 min → ~7–9 min (parallelism across apps). Single app path is already addressed by Changes 1 + 2.

---

### Change 4 — Replace `installed:` gotmpl expressions with `condition:` where possible

**The problem:** Every `installed:` with a gotmpl expression is evaluated during template rendering even for unrelated apps:

```yaml
installed: {{ and (eq .Environment.Name "demo") (.Values.application.drive.enabled) (ne (.Values.database.default.provider | default "bitnami") "cnpg") | toYaml }}
```

`condition:` is a lightweight values lookup, not a template evaluation:

```yaml
condition: application.drive.enabled
```

The `eq .Environment.Name "demo"` check is the hard part — it's used to install Bitnami postgresql only in demo, not production (where CNPG is assumed). This logic belongs in values, not templates. Add a per-environment values key:

```yaml
# helmfile/environments/demo/mijnbureau.yaml.gotmpl
database:
  default:
    installBitnamiInEnvironment: true

# helmfile/environments/production/*.yaml.gotmpl (omit or set false)
database:
  default:
    installBitnamiInEnvironment: false
```

Then:
```yaml
# In each app helmfile
condition: database.default.installBitnamiInEnvironment
```

This reduces gotmpl template complexity and makes intent more explicit. Minor savings per invocation but significant when multiplied across 70 releases.

---

## Summary

| Change | Status | Impact on single-app deploy | Impact on full deploy |
|--------|--------|-----------------------------|-----------------------|
| 1. Per-app entry points via `child-environments.yaml` | Implemented | ~8 min → ~5 min | None (keeps monolithic path) |
| 2. Tier labels + `deploy-app.sh` | Implemented | ~5 min → ~35s (app-only fast path) | Single invocation, `needs:` DAG handles ordering |
| 3. Explicit concurrency + `wait: false` | Proposed | Minor | ~15 min → ~8 min |
| 4. `condition:` over `installed:` | Proposed | Minor template speedup | Minor template speedup |

**Changes 1 + 2 together** get a single application iterative deploy from 8 minutes to ~35 seconds for the common case (app code change, infra already running). For full deploys with `--with-infra`, a single helmfile invocation resolves the complete DAG — no orchestration needed in the script.
