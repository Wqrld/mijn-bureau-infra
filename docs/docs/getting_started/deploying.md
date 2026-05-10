---
sidebar_position: 6
---

# Deploying

MijnBureau supports two deployment modes: a **full deployment** that applies every application at once, and a **targeted deployment** that applies one or more specific applications. Use targeted deployments when iterating on specific applications to avoid waiting for unrelated components.

---

## Full Deployment

To deploy all enabled applications to your cluster, run:

```bash
helmfile -e <environment> apply
```

Replace `<environment>` with `demo` or `production`. Helmfile will process all applications in dependency order.

To preview changes without applying them:

```bash
helmfile -e <environment> diff
```

---

## Targeted Deployment

When you only want to deploy a single application — for example after changing its configuration or upgrading its image — use `scripts/deploy-app.sh` instead of the full `helmfile apply`.

### App-only (fast path)

Use this when the application's infrastructure (database, cache, object storage) is already running:

```bash
./scripts/deploy-app.sh <app> [<app2> ...]
```

For example, deploying a single app:

```bash
./scripts/deploy-app.sh drive
```

Or deploying several apps in sequence:

```bash
./scripts/deploy-app.sh drive nextcloud grist
```

This applies only the applications and their proxies, skipping database and cache releases entirely. Apps are deployed one after the other in the order given.

### Full app deploy (with infrastructure)

Use this for an initial deploy, or when infrastructure needs to be (re)created. Pass `--with-infra` to first apply infrastructure (PostgreSQL, Redis, MinIO), wait for it to become ready, then apply the application:

```bash
./scripts/deploy-app.sh <app> --with-infra
./scripts/deploy-app.sh drive nextcloud --with-infra
```

### Targeting a specific environment

Pass `-e <environment>` to target a specific environment:

```bash
./scripts/deploy-app.sh drive nextcloud -e production
```

### Previewing changes

Pass `--diff` to preview what would change without applying:

```bash
./scripts/deploy-app.sh drive nextcloud --diff
```

### Updating chart dependencies

By default the script skips `helm dependency build`, since chart downloads are already on disk and re-downloading them on every deploy adds ~30 seconds of repository sync overhead. Pass `--update-deps` when you have bumped a chart version and need the downloads refreshed:

```bash
./scripts/deploy-app.sh drive --update-deps
```

---

## Available Applications

The following application names can be passed to `deploy-app.sh`:

| Name | Description |
|------|-------------|
| `bureaublad` | Dashboard |
| `clamav` | Antivirus |
| `collabora` | Office editing |
| `conversations` | Messaging |
| `docs` | Document collaboration |
| `drive` | File storage |
| `element` | Matrix/Element chat |
| `find` | Search indexer |
| `grist` | Spreadsheets |
| `keycloak` | Identity provider |
| `livekit` | Real-time audio/video |
| `meet` | Video conferencing |
| `nextcloud` | File sharing |
| `ollama` | Local AI models |
| `openproject` | Project management |

---

## Advanced: Direct Helmfile Targeting

For more control you can invoke the per-app helmfiles directly with the `-f` flag, bypassing `deploy-app.sh`:

```bash
# Infrastructure only
helmfile -e demo -f helmfile/apps/drive/helmfile-infra.yaml.gotmpl apply

# Application only
helmfile -e demo -f helmfile/apps/drive/helmfile-app.yaml.gotmpl apply

# Both (full child helmfile, same as the monolithic path but only for drive)
helmfile -e demo -f helmfile/apps/drive/helmfile-child.yaml.gotmpl apply
```

This is useful when you want to pass additional Helmfile flags not exposed by the wrapper script.
