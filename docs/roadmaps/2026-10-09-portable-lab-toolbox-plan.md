# Portable lab toolbox: plan

> **Status: Revision 3 (2026-10-09), conditional approval pending the Phase 0 spike.** Author:
> Claude. Next steps: owner sign-off, the Phase 0 spike, then `implemented-NN` records and an
> independent `validated-NN`. The author does not validate this plan's implementation.

## Review history

| Date | Reviewer | Verdict | Changes in this revision |
| --- | --- | --- | --- |
| 2026-10-09 | Antigravity (executive summary relayed by the owner; full findings not on file) | **Conditional approval pending Phase 0.** Missing: the macOS UID 501 `$HOME` trap, Docker socket path and group, dev container `.venv-notebook` pollution, Prometheus API exposure. Option B is far less invasive with an internal port proxy. | All five points addressed in revision 2: user and `$HOME` mapping, socket group detection, notebook environment baked into the image, Prometheus and Loki access through the Kubernetes API only, option B redesigned as a port proxy and now preferred. |
| 2026-10-09 | Owner | Revision 3 requested; dev container dropped | Notebooks open in **JupyterLab in the browser** served by the toolbox (`lab notebook`), so learners need no VS Code. The VS Code dev container is dropped (owner: not necessary). Same as `make notebook` on the WSL2 host today. |

## Owner decisions

| Date | Decision |
| --- | --- |
| 2026-10-09 | **Mac engine: Docker Desktop.** Revision 2 prefers networking option B (port proxy), which needs no Docker Desktop setting; option A, the fallback, uses Docker Desktop's host networking (off by default). The Phase 0 spike records the Docker Desktop version and settings. OrbStack and Colima are not supported. |
| 2026-10-09 | **Apple Silicon only.** Macs with Intel CPUs are not supported or tested. Images are still built for `linux/amd64` and `linux/arm64`: amd64 for the current Windows + WSL2 host and Linux, arm64 for Apple Silicon. |
| 2026-10-09 | **Notebook server authentication: the Jupyter token, not Keycloak.** Single-user server on `127.0.0.1`; the notebook must keep working when the hub (and its Keycloak) is down. Revisit only for a multi-user JupyterHub. |
| 2026-10-09 | **Toolbox image: published, with a local build option.** CI publishes a signed image to GHCR (public), and `lab` uses it by default; `lab --build` (or `make toolbox-build`) builds the same image locally from `toolbox/Dockerfile` and `toolbox/versions.env`, for offline use or to try a tool change before CI. |

## Goal

Run this lab on another computer, macOS in particular, with the same results as on the current
Windows + WSL2 host: `make setup`, `make test` (Bats), the doc tests and the notebooks. To do that:

- **Toolbox image:** package every command-line tool the lab needs, at pinned versions, in one
  container image.
- **One entry point:** run it through a single `lab` command (and a Compose file), so that nothing
  except Docker, Git and a browser has to be installed on the host.

## Non-goals

- **Moving the clusters into the toolbox:** k3d keeps running the clusters on the host's Docker
  engine. The toolbox only drives them.
- **Windows without WSL2.**
- **Replacing the native setup:** the WSL2 host keeps working without the toolbox; the toolbox is an
  alternative, not a migration.
- **Running Keycloak SSO logins in the container:** the browser stays on the host.

## What was measured (2026-10-09, on the current host)

| Fact | Evidence | Consequence |
| --- | --- | --- |
| The lab uses about **11 GiB of RAM** | `docker stats`: hub server 4.4 GiB, each spoke 2.3 GiB plus agent 0.6–0.8 GiB, Moto 0.4 GiB | A Mac needs **at least 16 GB**, with about 12 GB given to the Docker VM. An 8 GB Mac cannot run the full lab. |
| **39 of 41 images** support amd64 and arm64 | `docker buildx imagetools inspect` on every running image | Apple Silicon runs them natively. |
| **The lab's own two images are amd64-only** | `ghcr.io/brunobml/orders-processor:v1.5.0` and `ghcr.io/brunobml/bats-test-reporter` | On Apple Silicon they run emulated (slow) or not at all. This blocks macOS **regardless of the toolbox**. |
| The scripts need GNU bash 4+ and GNU tools | `declare -A` in 3 files, `mapfile` in 2, `date -d` in 5, `timeout` in 7 (36 scripts in `scripts/`) | macOS ships bash 3.2 and BSD tools, so the scripts fail natively. **This is what the toolbox fixes best.** |
| The lab is reached through ports on `127.0.0.1` | kubeconfig `https://127.0.0.1:6550-6552`; hub on `:80/:443`; spokes on `:8081/:8082`; Moto on `:5000` | Inside a container, `127.0.0.1` is the container itself. **Networking is the main design question** (below). |
| Scripts drive Docker directly | `k3d` in 10 scripts, `docker` in 11 (e.g. `docker exec … nginx -s reload`) | The toolbox needs the host's Docker socket. |
| Tool versions on the host | kubectl 1.36.1, argocd 3.5.0, helm 3.19.0, aws-cli 2.7.22, jq 1.7, yq 4.47.2, k3d 5.9.0, bats 1.14.0, cosign 3.1.3, gh 2.45.0, krew plugins (tree, who-can, access-matrix, neat), Python 3.12 | Pin these in one versions file; `aws-cli` 2.7.22 is old and is a good first upgrade candidate. |

## Opinion: is the toolbox worth it?

Yes, as long as two expectations are clear.

1. **It solves tool and script portability:** the same versions everywhere, a Linux userland on
   macOS, and a much shorter setup. That alone removes most "works on my machine" failures.
2. **It does not solve the hard macOS problems:** the amd64-only images, the RAM requirement, and
   reaching the lab from inside a container. Those need their own work (phases 0 and 1 below), and
   the image fix helps the lab even without the toolbox.

A single `lab` wrapper is better than an alias per tool (`alias kubectl=…`):

- **Scripts:** aliases don't apply inside scripts.
- **Interactive use:** they break shell completion and every pipe that needs a TTY.
- **Speed:** each call starts a container, which is slow for the 40 `kubectl` calls a script makes.

So the design is `lab <command>` for one-off commands, and `lab shell` for an interactive session in
the toolbox.

## Design

### Image `ghcr.io/brunobml/lab-toolbox`

- **Base:** Debian slim; multi-arch (`linux/amd64`, `linux/arm64`).
- **Contents:** the tools in the table above, plus bash 5, GNU coreutils, curl, openssl, git, make,
  Python 3.12 with the notebook requirements, kubeconform and shellcheck (for `make ci`).
- **Versions:** one file, `toolbox/versions.env`. Both the image build and a host check
  (`make doctor`) read it, so native setups and the toolbox never drift apart.
- **Releases:** built and pushed to GHCR (public) by GitHub Actions, signed with cosign like the other
  images, pinned by digest in `compose.yaml`.
- **Local build:** `compose.yaml` has both `image:` (the published digest) and `build:` (the local
  Dockerfile). `lab --build` or `make toolbox-build` builds it for the host's architecture and tags it
  `lab-toolbox:local`, and `lab` then uses that tag until `lab --published` switches back. Same
  Dockerfile and versions file as CI, so a local build and the published image only differ by
  build date.

### Running it: `compose.yaml` and the `lab` wrapper

| Mount or setting | Why |
| --- | --- |
| Repos (`~/repos`) at the same path | The scripts expect the sibling repos (`../platform-catalog`, …), and absolute paths in the kubeconfig, `kernel.json` and logs then mean the same thing inside and outside. |
| `~/.config/gitops-lab` read-write | Secrets and state the scripts create; never copied into the image. |
| `~/.kube` | The k3d contexts (see networking). |
| Host UID/GID **and `HOME`** | Files created in the repos belong to the user, not root. On macOS that is UID 501 and GID 20 (`staff`), which have no account in a Debian image: `HOME` would be unset or `/`, and tools would write `~/.kube`, `~/.config/helm` and `~/.aws` to the wrong place. The entrypoint therefore creates an account for the host UID/GID with `HOME` set to the host's path (`/Users/<name>` or `/home/<name>`, also mounted at that path), and does not depend on the numeric GID's name in the image (GID 20 is `dialout` in Debian). |
| Docker socket and its group | `k3d` and `docker exec`. The wrapper mounts the socket the engine exposes (`/var/run/docker.sock`; on Docker Desktop that is the VM-side socket, not the macOS path `~/.docker/run/docker.sock`), detects the socket's group ID with a throwaway container (`stat -c %g`), and passes it with `--group-add`. The ID differs between a Linux host (the `docker` group) and Docker Desktop's VM. No `chmod 666` on the socket. |
| Git identity and SSH agent socket | `git push` and signed commits from inside the toolbox (`make promote-blueprints`). Only the agent socket is mounted, not the keys (Docker Desktop provides it as `/run/host-services/ssh-auth.sock`). |

`scripts/lab` (put on PATH, or used as `./lab`) runs `docker compose run --rm toolbox "$@"`; `lab`
with no arguments opens a shell. `lab --build` and `lab --published` choose between the local and the
published image (above).

### Networking: the decision this plan hinges on

| Option | How | Pros | Cons |
| --- | --- | --- | --- |
| **A. Host network** | `network_mode: host`. On Linux this is native. On macOS it uses Docker Desktop's host networking (4.34+, enabled in its settings). | Every `127.0.0.1` URL, kubeconfig and script works unchanged. | It depends on a Docker Desktop feature that is off by default, and behaves differently on Linux and macOS. |
| **B. Join `k3d-cloud-net` + port proxy** (revision 2) | The toolbox joins the lab's Docker network, and its entrypoint starts a small TCP proxy (`socat`, one listener per port) on the toolbox's own `127.0.0.1`: `6550-6552` → `k3d-<cluster>-serverlb:6443`, `80`/`443` → the hub's serverlb, `8081`/`8082` → the spokes' serverlb on port 80, `5000` → `moto-cloud:5000`. | Scripts, kubeconfig, URLs and notebooks stay unchanged, because inside the toolbox `127.0.0.1:<port>` reaches the same service as on the host. Works on any engine, the same way on Linux and macOS. TLS to the API servers still validates (the certificates already cover `127.0.0.1`), and HTTP `Host:` headers pass through untouched (plain TCP forwarding). | Ports below 1024 need `--sysctl net.ipv4.ip_unprivileged_port_start=0` for the non-root user. The network has to exist before the toolbox starts (the wrapper creates `k3d-cloud-net` if `make setup` has not yet). The proxy resolves names per connection, so clusters created later still work. |

**Proposal: B with the port proxy** (revision 2, following the review). It avoids the Docker Desktop
setting, behaves identically on both hosts, and changes no script. Option A remains the fallback if
the spike shows a problem with the proxy (for example, a protocol that does not survive TCP
forwarding). The Docker Desktop decision stands, for the engine itself.

### Notebooks: JupyterLab in the browser (revision 3)

`lab notebook` starts JupyterLab **inside the toolbox**, so a learner needs only Docker and a browser:
no VS Code, no Python on the host. It is the toolbox version of `make notebook`, which already serves
JupyterLab from the WSL2 host on `127.0.0.1`.

- **Tools and lab access:** the kernel runs in the toolbox, so it has every pinned tool, the Bash
  kernel, the kubeconfig, `~/.config/gitops-lab` and the port proxy. A generic Jupyter image
  (`quay.io/jupyter/scipy-notebook`) has none of these, and its `127.0.0.1` is the container itself:
  it cannot replace the toolbox.
- **Only the Bash kernel is offered** (`KernelSpecManager.allowed_kernelspecs=bash`, as `make notebook`
  does). A server that offers Python rewrites the notebook's kernel to `python3` when it saves, and
  the Bash cells then fail with `SyntaxError`. This happened on 2026-10-09 with a generic Jupyter
  container that had the repo mounted; `make notebook-check` now fails on any kernel but `bash`.
- **Published on `127.0.0.1` only, token required:** `-p 127.0.0.1:8888:8888`, never the default
  `0.0.0.0`. The server is a web shell holding cluster-admin credentials, the lab secrets and the
  Docker socket (root-equivalent on the host), so it must not be reachable from the network, and the
  token must not be disabled. The wrapper prints the URL with its token; the README tells learners
  not to paste it anywhere.
- **Authentication: the token, not Keycloak** (owner decision, 2026-10-09). A single-user server on `127.0.0.1` gains little from
  SSO, and the notebook is a troubleshooting tool: logging in through the lab's own Keycloak would make
  it unusable exactly when the hub is down. Keycloak becomes the right answer only for a multi-user
  setup (JupyterHub on the hub with Keycloak OIDC), which is a different design and out of scope here.
- **Jupyter and the port proxy share the toolbox:** Jupyter listens on port 8888, which is not one
  of the lab's proxied ports.
- **No `.venv-notebook` inside the container.** The repo is bind-mounted, so a venv created in the
  container would overwrite the host's (different OS and paths) and its user kernel registration. The
  image ships the notebook environment at `/opt/lab-notebook` with its own Bash kernelspec, and
  `scripts/setup-notebook.sh` detects the container (`LAB_TOOLBOX=1`) and stops with a message instead
  of creating a venv. The host's `.venv-notebook/` stays untouched and git-ignored.
- **Prometheus and Loki through the Kubernetes API only.** The notebooks query them with
  `kubectl exec` (today) or `kubectl port-forward` (for the planned Python notebooks), which works the
  same from the toolbox and needs no new Ingress. Exposing the Prometheus or Loki HTTP APIs on an
  Ingress is out of scope: it would publish unauthenticated query APIs on the host.
- **No VS Code dev container:** the owner dropped it (2026-10-09); the browser covers the need. Keycloak
  logins for the lab's web UIs stay in the host's browser.

## Phases and exit criteria

| Phase | Work | Exit criterion |
| --- | --- | --- |
| **0. macOS spike** (time-boxed, 1–2 days) | On a Mac with Docker Desktop (memory set to at least 12 GB), run `make setup` with natively installed tools, and record what fails. Run a throwaway toolbox with option B (port proxy), then with A (host networking enabled). Check the user and `HOME` mapping (UID 501), the socket group, and the SSH agent socket. Measure RAM. | A written spike report: the failure list, the networking option that works, the Docker Desktop version and settings, and the RAM figure. **Go/no-go for the rest.** |
| **1. Multi-arch images** | Build `orders-processor` and `bats-test-reporter` for amd64 and arm64 (`docker buildx`), and sign the image index. Kyverno's `tenant-images-signed` checks the index digest, so confirm a signed multi-arch image passes admission. | Both images list `linux/arm64`. Admission passes on the current host. The smoke suite stays green. |
| **2. Toolbox image** | `toolbox/Dockerfile`, `toolbox/versions.env`, the CI build, push to GHCR and signing, `make toolbox-build` for the local build, and `make doctor` (compares host tools with the versions file). | The published image exists for both architectures and its signature verifies. `make toolbox-build` produces a working local image on both the WSL2 host and an Apple Silicon Mac. `make doctor` passes in both. |
| **3. `lab` wrapper and Compose** | `compose.yaml`, `scripts/lab`, the mounts above, and the README section "Run the lab from the toolbox". | On the current host, `lab make test` and `lab make ci` give the same results as native. |
| **4. Notebooks in the toolbox** | `lab notebook` (JupyterLab on `127.0.0.1:8888` with token), the notebook environment at `/opt/lab-notebook`, `make notebook-check` in the toolbox (it also fails if the notebook's kernel is not `bash`). | On Linux and macOS, `lab notebook` opens `lab-commands.ipynb` in the browser and every cell runs; the port is bound to `127.0.0.1` only (`docker port` shows it) and requests without the token are refused. |
| **5. macOS acceptance** | A full run on a Mac from a fresh clone, following only the README. | `make setup`, `make test` (all gates), `make test-docs` and `make notebook-check` pass. Any time or RAM differences are recorded. |

## Risks and accepted residual risk

| Risk | Treatment |
| --- | --- |
| The Docker socket gives the toolbox root-equivalent control of the host's Docker | Accepted for this single-user lab (lab security preferences: keep low-friction controls, record residual risk). The image is pinned and signed, and nothing else gets the socket. |
| The port proxy breaks a protocol, or the network is missing when the toolbox starts | Phase 0 tests every listener (kubectl, argocd gRPC-web, Moto, the `*.localhost` routes). The wrapper creates `k3d-cloud-net` when it is missing. `make doctor` checks that every lab port answers from inside the toolbox. Fallback: option A. |
| Wrong user, `HOME` or group inside the container (macOS UID 501 / GID 20) | The entrypoint creates the account from the host's UID, GID and `HOME`. Phase 0 checks that `~/.kube`, the Helm cache and `~/.config/gitops-lab` are written as the user, at the host path. |
| The toolbox cannot use the Docker socket (group mismatch) | The socket's group ID is detected at start and added with `--group-add`; never `chmod 666`. |
| The notebook server is reachable from the network, or its token leaks | Published on `127.0.0.1` only, token always on (Phase 4 exit criterion checks both). The token changes on every start. |
| The toolbox overwrites the host's notebook venv or kernel (the repo is bind-mounted) | The notebook environment lives in the image (`/opt/lab-notebook`); `setup-notebook.sh` refuses to run inside the toolbox. |
| Emulated amd64 images make the lab unusable on Apple Silicon | Phase 1 comes before anything that depends on it. |
| The toolbox and native tool versions drift | One `versions.env`, plus `make doctor` in both places. |
| Startup cost of `docker compose run` for each command | Use `lab shell` for interactive work. Scripts run entirely inside one container (`lab make …`), not one container per call. |

## Decisions for the owner

1. ~~Mac engine~~: decided 2026-10-09, Docker Desktop (see *Owner decisions*). Its licence is free
   for personal use; check its terms if the lab is used inside a larger company.
2. ~~Intel Macs~~: decided 2026-10-09, Apple Silicon only.
3. ~~Toolbox image~~: decided 2026-10-09, published to GHCR with a local build option.
4. **Where the Phase 0 spike runs:** whose Mac, and when. Nothing after Phase 0 starts without its
   report.
