# Minca-AI-delivery

Shared CI/CD for Minca service repositories: reusable GitHub workflows, composite
actions, Taskfile fragments and the `minca-service` Helm chart. A fix to how we
build, check or deploy is made here once, released, and picked up by every
consumer through `@v1`.

This repository is **public**. It holds generic logic only: no account ids, ARNs,
client names or secrets. Those live in organization or repository variables and
secrets of the consumers. See [SECURITY.md](SECURITY.md).

```
.github/workflows/  ci.yml  quality-guards.yml  image.yml  promote.yml   (reusable)
                    self-test.yml  release.yml  chart-release.yml         (this repo)
actions/            setup-toolchain  ecr-login  build-smoke-push  bump-pin
taskfiles/          python-uv.yml  python-poetry.yml  go.yml  node.yml
charts/             minca-service
examples/           python-uv  go  node       (fixture consumers run by self-test)
tests/              bump-pin unit test
```

## Quick start: a service repository's whole workflow

```yaml
name: delivery
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  ci:
    uses: Minca-AI/Minca-AI-delivery/.github/workflows/ci.yml@v1
    with:
      toolchain: python-uv
  guards:
    uses: Minca-AI/Minca-AI-delivery/.github/workflows/quality-guards.yml@v1
    secrets: inherit
  image:
    needs: [ci]
    permissions:
      contents: read
      id-token: write
    uses: Minca-AI/Minca-AI-delivery/.github/workflows/image.yml@v1
    with:
      dockerfile: docker/Dockerfile
  promote-gnp-dev:
    if: github.ref == 'refs/heads/main'
    needs: [image]
    permissions:
      contents: read
      id-token: write          # promote checks ECR and moves the live tag
    uses: Minca-AI/Minca-AI-delivery/.github/workflows/promote.yml@v1
    with:
      deploy-repo: Minca-AI/Minca-AI-deploy-GNP
      environment: dev
      service: codifier
      tag: ${{ needs.image.outputs.tag }}
      digest: ${{ needs.image.outputs.digest }}
      mode: commit
    secrets: inherit
```

One `promote-*` job per client environment that runs the service. Secrets are
only ever passed with `secrets: inherit`, never as `${{ secrets.* }}` in `with:`.

## Contracts

Everything in this section is the published v1 API. Within v1 it only grows: an
input, output, target name or chart value is never removed or changes meaning.

### Task targets (every consuming repository)

| Target | Required | Meaning |
|---|---|---|
| `setup` | yes | Install dependencies, frozen to the lock file |
| `lint` | yes | Static style checks, no writes |
| `typecheck` | yes (may print `skipped`) | Type checking |
| `arch` | no | Architecture contracts (skipped when none are declared) |
| `test` | yes | Unit lane: no network, no Docker |
| `test:integration` | no | Lanes that need Docker; CI runs it on the `large` pool |
| `image:smoke` | when an image is built | Prove the built image starts; `IMAGE` is set in the environment |

A target exits non-zero on failure, never modifies tracked files, and runs the
same locally and in CI.

### `ci.yml`

| Input | Type | Default | Purpose |
|---|---|---|---|
| `toolchain` | `python-uv` \| `python-poetry` \| `go` \| `node` | required | What `setup-toolchain` installs |
| `toolchain-version` | string | from `.python-version`, `go.mod`, `.nvmrc` | Override |
| `working-directory` | string | `.` | For monorepos |
| `pool` | `ci` \| `large` | `ci` | `[self-hosted, ci]` or `[self-hosted, large]`; the only runner selector |
| `targets` | string | `lint typecheck arch test` | Targets to run, one job each. A missing optional target is skipped, a missing required one fails |
| `integration` | boolean | `false` | Also run `test:integration` on the `large` pool |
| `runs-on-override` | string | `""` | For this repository's self-test only |

No outputs. One job per target, so a pull request shows which check failed.

### `quality-guards.yml`

Runs the [minca-quality-hooks](https://github.com/Minca-AI/minca-quality-hooks)
ratchet on the pull request diff, using the hook ids and arguments the repository
declares in its `.pre-commit-config.yaml`. Skipped (with a notice) when the
repository declares none, and outside pull requests.

| Input | Default | Purpose |
|---|---|---|
| `working-directory` | `.` | Where `.pre-commit-config.yaml` lives |
| `pool` | `ci` | Runner pool |
| `hooks` | `cognitive-complexity function-length dup-literal` | Hook ids to run when declared |

Optional secrets (through `secrets: inherit`): `MINCA_CI_APP_ID`,
`MINCA_CI_APP_PRIVATE_KEY`, an App that can read the private hooks repository.

### `image.yml`

| Input | Type | Default | Purpose |
|---|---|---|---|
| `image-name` | string | repository name, lowercased | ECR repository under `minca/` |
| `dockerfile` | string | `Dockerfile` | Relative to `working-directory` |
| `context` | string | `.` | Relative to `working-directory` |
| `working-directory` | string | `.` | Holds the Taskfile |
| `smoke` | boolean | `true` | Run `task image:smoke` on the loaded image before pushing |
| `push` | boolean | `true` | Push after the smoke test. A `pull_request` run never pushes |
| `platforms` | string | `linux/amd64` | One platform (a loaded, smoke-tested image is single-platform) |
| `pool` | `ci` \| `large` | `ci` | Runner pool |

| Output | Example |
|---|---|
| `image` | `<registry>/minca/gnp-codifier` |
| `tag` | `sha-<40-char git sha>` |
| `digest` | `sha256:...` (empty when nothing was pushed) |

The calling job must grant `id-token: write`. The role's trust policy, not the
workflow, decides which refs may push (design: `refs/heads/main` only).

### `promote.yml`

| Input | Default | Purpose |
|---|---|---|
| `deploy-repo` | required | e.g. `Minca-AI/Minca-AI-deploy-GNP` |
| `environment` | required | e.g. `dev` |
| `service` | required | Key in `pins.yaml` |
| `tag`, `digest` | required | From `image.yml` outputs |
| `mode` | `commit` | `commit` for dev, `pull-request` for prod |
| `image-name` | repository name | ECR repository under `minca/` (same default as `image.yml`) |
| `client` | from `Minca-AI-deploy-<CLIENT>` | Client part of the live tag |
| `pins-path` | `environments/<environment>/pins.yaml` | |
| `base-branch` | `main` | Deploy repository branch |
| `pool` | `ci` | Runner pool |

Secrets (`secrets: inherit`): `DELIVERY_APP_ID`, `DELIVERY_APP_PRIVATE_KEY`.

Behaviour: checks that the tag exists in ECR and resolves to the digest; writes
`pins.yaml`; commits `chore(pins): <service> <tag> [<env>]` (or opens a pull
request); retries a lost race up to 5 times with rebase; in `commit` mode moves
`<client>-<env>-live` onto the digest. The calling job must grant `id-token: write`.

### Composite actions (`actions/<name>`)

| Action | Inputs | Does |
|---|---|---|
| `setup-toolchain` | `toolchain`, `version`, `working-directory` | uv / Poetry / Go / Node plus go-task, with caching |
| `ecr-login` | `role-arn`, `region` | OIDC assume-role and `docker login` to ECR; output `registry` |
| `build-smoke-push` | `image`, `tag`, `dockerfile`, `context`, `smoke`, `push`, `platforms` | Build and load, `task image:smoke`, push the same image; output `digest` |
| `bump-pin` | `repo`, `path`, `service`, `tag`, `digest`, `mode`, `token` | Edit `pins.yaml`, commit or open a PR, retry loop |

A repository whose needs the workflows do not cover uses these directly:
`Minca-AI/Minca-AI-delivery/actions/<name>@v1`.

### `pins.yaml` (deploy repository, per environment)

```yaml
chart: 1.0.0
services:
  codifier:
    image: minca/gnp-codifier
    tag: sha-0123456789abcdef0123456789abcdef01234567
    digest: sha256:...
```

The chart renders `image@digest`. The tag is for humans.

### `minca-service` chart

Values contract: [`charts/minca-service/values.yaml`](charts/minca-service/values.yaml),
enforced by `values.schema.json`. Defaults are hardened: image by digest,
`maxUnavailable: 0`, `runAsNonRoot`, read-only root filesystem with an emptyDir
`/tmp`, all capabilities dropped, HTTP startup/readiness/liveness probes. IRSA
annotation from `serviceAccount.roleArn`; optional migration Job, Ingress, HPA and PDB.

Environment (1.1.0+): `env` renders ConfigMap `<name>-env` and `secretEnv` renders
Secret `<name>-env`; the Deployment and the migration Job load both with `envFrom`
(on a duplicate key the Secret wins). The pod template carries a checksum of each,
so a value change rolls the pods. `secretEnv` is meant to come from a SOPS-encrypted
values file in the deploy repository, decrypted at render time (for example by an
ArgoCD config management plugin running `sops -d` then `helm template`); this chart
never sees the ciphertext. External Secrets Operator stays available but off by
default: one ExternalSecret per `secrets[]` entry, injected with `secretKeyRef`.

Persistence (1.2.0+): off by default. When enabled, the Deployment's container
mounts an existing PersistentVolumeClaim; the migration Job never does. The claim
and its PersistentVolume belong to the deploy repository (for example a static EFS
volume), so the chart creates no storage objects.

| Value | Type | Default | Purpose |
|---|---|---|---|
| `persistence.enabled` | boolean | `false` | Mount the claim into the Deployment |
| `persistence.existingClaim` | string | `""` | PVC name in the release namespace; required when enabled |
| `persistence.mountPath` | string | `""` | Absolute path in the container; required when enabled |
| `persistence.subPath` | string | `""` | Optional sub-directory of the volume to mount |

Sync ordering under ArgoCD: ServiceAccount, the env ConfigMap/Secret and any
ExternalSecrets at wave -2, the
migration Job (a `Sync` hook, `backoffLimit: 0`) at wave -1, everything else at
wave 0. A failed migration fails the sync before the Deployment is touched.

Published as `oci://<DELIVERY_ECR_REGISTRY>/minca/charts/minca-service` on a
`minca-service-X.Y.Z` tag.

## Taskfile fragments

Include one fragment flattened; the targets keep their contract names.

```yaml
# Taskfile.yml of a service repository
version: '3'
includes:
  delivery:
    taskfile: '{{.DELIVERY_TASKFILES | default "https://raw.githubusercontent.com/Minca-AI/Minca-AI-delivery/v1/taskfiles"}}/python-uv.yml'
    dir: .
    flatten: true
```

In CI the workflows set `DELIVERY_TASKFILES` to the fragments of the exact commit
being run, so CI never downloads a Taskfile. Locally the include falls back to the
published `v1` copy, which needs go-task 3.53 or newer (remote Taskfiles are GA
there); run `task --yes setup` once to trust it, or point `DELIVERY_TASKFILES` at a
local clone.

Tune a target with the include's `vars:` (`PYTEST_ARGS`, `PYTEST_MARKERS`,
`MYPY_ARGS`, `SMOKE_ARGS`, `GO_TEST_FLAGS`, ...). Replace one by excluding it and
defining your own, for example black instead of `ruff format`:

```yaml
includes:
  delivery:
    taskfile: '{{.DELIVERY_TASKFILES | default "https://raw.githubusercontent.com/Minca-AI/Minca-AI-delivery/v1/taskfiles"}}/python-uv.yml'
    dir: .
    flatten: true
    excludes: [lint]
    vars:
      PYTEST_MARKERS: not live and not integration and not parity
tasks:
  lint:
    cmds:
      - uv run --frozen ruff check .
      - uv run --frozen black --check .
```

## Onboarding a service repository

1. An org owner installs the runners GitHub App (`mincaai-actions-runners`, id
   4266919) on the repository. Without it every job queues forever.
2. Add `Taskfile.yml` including a fragment; check `task setup lint typecheck test`
   passes locally. Add `image:smoke` semantics that fit the image (default:
   `docker run --rm "$IMAGE" --help`). The image must declare a numeric `USER`.
3. Replace the repository's CI with the caller workflow above. Remove every
   `runs-on: ubuntu-latest`.
4. Confirm the organization variables below are visible to the repository.
5. For deployment: the ECR repository `minca/<name>` must exist, the Delivery App
   must be installed on the deploy repository, and the service must have an entry
   in the deploy repository's values and `pins.yaml`.

## Organization configuration

| Kind | Name | Value | Visibility |
|---|---|---|---|
| Variable | `DELIVERY_ECR_REGISTRY` | `<account>.dkr.ecr.<region>.amazonaws.com` | private repositories |
| Variable | `DELIVERY_ECR_ROLE_ARN` | the `delivery-ecr-push` role | private repositories |
| Variable | `DELIVERY_AWS_REGION` | `us-east-1` (the default when unset) | private repositories |
| Secret | `DELIVERY_APP_ID` | Minca Delivery App id | repositories that promote |
| Secret | `DELIVERY_APP_PRIVATE_KEY` | Minca Delivery App private key | repositories that promote |
| Secret (optional) | `MINCA_CI_APP_ID`, `MINCA_CI_APP_PRIVATE_KEY` | App that can read `minca-quality-hooks` | repositories that run guards |

This repository itself, for chart releases only: environment `release` (required
reviewers) holding the variable `DELIVERY_CHART_ROLE_ARN`, a role whose trust policy
accepts `repo:Minca-AI/Minca-AI-delivery:environment:release` and that can push to
`minca/charts/*`.

The **Minca Delivery** GitHub App: repository permissions Contents (read and
write) and Pull requests (read and write), installed on `Minca-AI-deploy-*` only.

## Versioning

Tags `vX.Y.Z`; `release.yml` moves the major tag `vX` onto each release, and
consumers pin `@v1`. A breaking change to an input, output, target name or chart
value is a new major. The chart versions separately (`minca-service-X.Y.Z`,
`Chart.yaml` `version`), pinned per environment in `pins.yaml`.

## Developing

Everything self-test runs, runnable locally:

```sh
actionlint
uvx zizmor --min-severity low .
shellcheck actions/*/*.sh .github/scripts/*.sh tests/*/*.sh
bash tests/bump-pin/test_bump_pin.sh           # needs yq v4
bash .github/scripts/chart-check.sh            # needs helm, helm-unittest, kubeconform
cd examples/python-uv && DELIVERY_TASKFILES=$PWD/../../taskfiles task setup lint typecheck arch test
```
