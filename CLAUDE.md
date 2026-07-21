# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About

MijnBureau is a Kubernetes-based collaborative suite for civil servants (Dutch public sector). This repository manages infrastructure deployments using Helmfile, with Conftest/Rego policy validation.

## Commands

### Testing

```bash
# Run all tests (renders Helmfile templates and validates with Conftest policies)
./scripts/test.sh

# Test against a specific environment
./scripts/test.sh -e demo

# Test with a SOPS AGE key (for encrypted secrets)
./scripts/test.sh -s "<age-secret-key>"
```

The test script requires `MIJNBUREAU_MASTER_PASSWORD` to be set (the script sets it to `test` automatically for local runs). It runs tests in parallel: each `tests/*.yaml` file is a test case that replaces the environment config, renders templates, and runs the corresponding `tests/<name>/*.rego` policies.

### Linting

```bash
./scripts/lint.sh

# Lint helmfile for a specific environment
helmfile -e demo lint
```

### Rendering templates (without testing)

```bash
helmfile -e demo template --output-dir=./output --skip-deps
```

### Documentation

```bash
cd docs && npm install && npm start
```

## Architecture

### Helmfile Structure

The main entry point is `helmfile.yaml.gotmpl`, which composes two sections separated by `---`:

1. **Base helmfiles** (`helmfile/bases/environment.yaml.gotmpl`, `helmfile/bases/default.yaml.gotmpl`): declares the `default`, `demo`, and `production` environments and loads default config. There is no separate logic layer — OIDC/AI/LiveKit wiring lives directly in `helmfile/environments/default/{authentication,ai,livekit}.yaml.gotmpl`.
2. **App helmfiles**: 17 application sub-helmfiles under `helmfile/apps/`

### Values Inheritance

All app helmfiles receive two value sources:
- `helmfile/environments/default/*.yaml*` — always loaded base defaults
- Environment-specific overrides from `helmfile/environments/<env>/*.yaml.gotmpl`

This means `default/` contains the canonical schema for every configuration key. Environment overrides in `demo/` or `production/` only need to specify what differs.

### Configuration Files (`helmfile/environments/default/`)

Each file covers a distinct concern:
- `application.yaml.gotmpl` — per-app enable flags and app-specific settings; secrets derived from `MIJNBUREAU_MASTER_PASSWORD` using `derivePassword`
- `authentication.yaml` — OIDC client credentials and provider settings
- `container.yaml` — image registry, repository, and tag defaults
- `database.yaml` — database provider (`cnpg` or `bitnami`) and connection settings
- `global.yaml` — domain, hostnames, TLS settings
- `resource.yaml` — CPU/memory requests and limits per app
- `security.yaml` — security policies and network policies
- `pvc.yaml` — PersistentVolumeClaim configuration

### App Structure

Each app under `helmfile/apps/<name>/` has a `helmfile-child.yaml.gotmpl` that:
- Defines multiple Helm releases (e.g., `grist-postgresql`, `grist-redis`, `grist-minio`, `grist`)
- Uses `condition:` to conditionally install releases based on values (e.g., database provider, `enabled` flag)
- Uses `needs:` for intra-app release ordering

Shared Helm charts live in `helmfile/apps/common/charts/` and include: `cluster`, `cnpg-cluster-credentials`, `common`, `gateway`, `httproute`, `minio`, `nginx`, `opensearch`, `postgresql`, `redis`.

### Policy as Code

- `policy/` — global Rego policies applied to all rendered manifests
- `tests/<name>.yaml` — test environment config (replaces the demo environment config during test run)
- `tests/<name>/*.rego` — Rego policies specific to that test case

### Secrets

SOPS with AGE encryption is used for secrets matching `.*secrets.yaml$`. The AGE public key is in `.sops.yaml`. Most secrets are derived deterministically from `MIJNBUREAU_MASTER_PASSWORD` using Helmfile's `derivePassword` function rather than stored encrypted.

## Commit Conventions

Uses [gitmoji](https://gitmoji.dev/) with these scopes:
1. App folder names from `helmfile/apps/*` (e.g., `grist`, `keycloak`)
2. `settings` — cross-app settings changes
3. `deps` — dependency updates
4. `docs` — documentation
5. `tests` — test changes
6. `policies` — policy changes
7. `ci` — CI/CD changes
8. `other` — fallback

Example: `✨ (grist) add resource limits`

## Adding a New Application

Use `template/` as scaffolding. The template README lists required chart items (commonAnnotations, imagePullSecrets, resources, probes, etc.). New apps should use `helmfile/apps/common/charts/common` as the base chart for standardization.
