# my-hermes-docker | Hermes Agent — locked to one directory

Runs [`nousresearch/hermes-agent`](https://hub.docker.com/r/nousresearch/hermes-agent)
entirely inside one Docker container with a small, fixed set of bind mounts,
so Hermes can safely have every tool/ability turned on without ever seeing
the rest of your machine. Two mounts are the core of the sandbox (workspace +
Hermes' own state); two more, entirely optional, let you plug in your own
skills read-only — see [Configuration](#configuration).

## Installation

Requires Docker + Docker Compose.

```bash
git clone <this-repo> hermes-docker   # or just cd into it if you already have it
cd hermes-docker
cp .env.example .env
```

Edit `.env` — at minimum add a provider API key (`ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, …). See [Configuration](#configuration) below for every
variable.

Create the two mounted folders and make sure **you** own them (Docker
auto-creates missing bind-mount targets as root, which silently breaks writes
later — see [Sandbox policy actually enforced](#sandbox-policy-actually-enforced)):

```bash
mkdir -p "${HERMES_PROJECT_DIR:-project}" "${HERMES_HOME_DIR:-$HOME/.hermes}"
```

(Skip `HERMES_EXTERNAL_SKILLS_DIR`/`HERMES_AGENTS_SKILLS_DIR`/
`HERMES_WORKSPACE_DIR_RO`/`HERMES_WORKSPACE_DIR_RW` here — they're all optional and
only need a folder to exist if you actually set them; see
[Mounting your own skills and code](#mounting-your-own-skills-and-code).)

Start it:

```bash
make up
```

First `make up` builds the local image (`Dockerfile` extends
`nousresearch/hermes-agent` with a couple of Python packages needed by
skills — see [Mounting your own skills and code](#mounting-your-own-skills-and-code)),
then starts it. After that it walks you through Hermes' own setup wizard on
first CLI attach. Config is written into `HERMES_HOME_DIR` (a bind mount),
so it persists across restarts and image updates.

## Configuration

Everything lives in `.env` (see `.env.example` for the annotated template):

| Variable | Default | Purpose |
| --- | --- | --- |
| `UID` / `GID` | `1000` / `1000` | Host uid:gid the container's internal `hermes` user is remapped to, so files it writes land owned by you |
| `HERMES_PROJECT_DIR` | `./project` | The one folder Hermes can read/write — its `/workspace`. Point it at a fresh folder per task for clean separation |
| `HERMES_HOME_DIR` | `${HOME}/.hermes` | Hermes' config/session/auth/skills state — its `/opt/data`. Conventional path, see [Native vs. Dockerized Hermes](#native-vs-dockerized-hermes) for the tradeoff it accepts |
| `HERMES_EXTERNAL_SKILLS_DIR` | unset (mount not created) | Your own skill sources, mounted **read-only** at `/skills-src`. See [Mounting your own skills and code](#mounting-your-own-skills-and-code) |
| `HERMES_AGENTS_SKILLS_DIR` | unset (mount not created) | The `npx skills` canonical global store, mounted **read-only** at `/skills-src-agents`. See [Mounting your own skills and code](#mounting-your-own-skills-and-code) |
| `HERMES_WORKSPACE_DIR_RO` | unset (mount not created) | Your own code, mounted **read-only** at `/workspace/Programming/company-ro`. See [Mounting your own skills and code](#mounting-your-own-skills-and-code) |
| `HERMES_WORKSPACE_DIR_RW` | unset (mount not created) | Your own code, mounted **read-write** at `/workspace/Programming/company-rw` — Hermes can modify/commit/push here. See [Mounting your own skills and code](#mounting-your-own-skills-and-code) |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, … | unset | Provider credentials, referenced by `config.yaml` |
| `HERMES_DASHBOARD*` | off | Web dashboard — off by default, fails closed without a password |
| `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, … | unset | Third-party integration tokens — only add what you use |

## Everyday usage

**CLI** — attach to the running container (shares session/memory/config with
the dashboard and any messaging integrations, since they all point at the
same `HERMES_HOME_DIR`):

```bash
make cli
# equivalent to: docker compose exec hermes hermes
```

Optional shell alias for a plain `hermes` command:

```bash
# ~/.bashrc or ~/.zshrc
alias hermes='docker compose -f /path/to/hermes-docker/compose.yml exec hermes hermes'
```

**Dashboard** — off by default. Uncomment and set the `HERMES_DASHBOARD*`
block in `.env` (needs a real password), then:

```bash
make restart
make dashboard   # just prints the URL as a reminder
```

Open **http://127.0.0.1:8642** — bound to localhost only, never your LAN.

**Files Hermes produces** — nothing extra needed. `HERMES_PROJECT_DIR` is a
live bind mount: anything Hermes writes to `/workspace` appears at that host
path immediately, owned by you, and anything you drop there is visible to
Hermes.

**Other Makefile targets**: `make down` (stop/remove container — data stays
on disk), `make build` (rebuild the local image after editing `Dockerfile`),
`make logs` (tail logs), `make restart` (after editing `config.yaml`),
`make status` (check it's running), `make doctor` (Hermes' own health
check).

## Installing skills with `npx skills`

`.hermes` is the conventional per-user config directory across the
agent-skills ecosystem — it's what [`skills-cli`](https://github.com/antfu/skills-cli)
(`npx skills`) and a native `hermes-agent` binary both fall back to via the
`HERMES_HOME` env var when nothing else is specified. This repo's default,
`HERMES_HOME_DIR=${HOME}/.hermes`, matches that convention on purpose, so
this works with zero extra flags:

```bash
npx skills add <owner/repo> -g -a hermes-agent -y
```

It writes straight into `~/.hermes/skills`, which is bind-mounted into the
running container at `/opt/data/skills` — Hermes reads it live, no restart
needed.

**If you pointed `HERMES_HOME_DIR` somewhere else** (see the tradeoff in
[Native vs. Dockerized Hermes](#native-vs-dockerized-hermes) for why you
might), tell `skills-cli` explicitly:

```bash
HERMES_HOME="$(pwd)/hermes-home" npx skills add <owner/repo> -g -a hermes-agent -y
```

or use the Makefile wrappers, which read `HERMES_HOME_DIR` out of `.env` for
you regardless of which path you chose:

```bash
make skill-add REPO=owner/repo             # install every skill in a repo
make skill-add REPO=owner/repo SKILL=name  # install just one
make skill-list                            # see what's installed
make skill-update                          # update hub-installed skills
```

**Why no symlinks:** `skills-cli` normally dedups by symlinking each agent's
copy back to a shared canonical store (`~/.agents/skills`). For `hermes-agent`
it copies real files into `$HERMES_HOME/skills/<name>` instead — confirmed by
installing into a scratch `HERMES_HOME` and checking the CLI's own output
(`✓ skill-name (copied)`). That's the right behavior here regardless: a
symlink pointing outside the two bind mounts would dangle inside the
container, since nothing else on the host is visible there.

It's bidirectional, too — skills installed from inside the sandbox via
`hermes skills install` land in the same directory and show up to `npx
skills list` on the host.

Hermes also ships its own skill manager (`hermes skills`, plus `hermes sync`
for cross-device/team sync) if you'd rather not involve `npx` at all.

## Mounting your own skills and code

Four more bind mounts, all **genuinely optional**: unset, they add nothing
to the container at all — no placeholder, no empty folder, the sandbox
stays at exactly the two mounts in [Configuration](#configuration). Set the
matching `.env` var and `make` merges in the extra fragment automatically
(`compose.skills.yml` / `compose.agents-skills.yml` / `compose.workspace-ro.yml`
/ `compose.workspace-rw.yml`); plain `docker compose up` without `make` ignores
them.

Three of the four are always read-only. The fourth — `HERMES_WORKSPACE_DIR_RW`,
below — is not, on purpose: it's a genuinely different risk level, not a
variant of the others, so it gets its own explicit opt-in rather than a flag
on a shared one. Decide per repo which of the two code mounts it belongs
under; don't default to the writable one "just in case."

**Your own skills repo** — `HERMES_EXTERNAL_SKILLS_DIR`, mounted at
`/skills-src`:

```bash
HERMES_EXTERNAL_SKILLS_DIR=/path/to/your/skills-repo/skills
```

Point it at the folder that directly *contains* your skill folders (each
with its own `SKILL.md`), not the repo root — e.g. `~/dev/my-skills/skills`,
not `~/dev/my-skills`. That keeps `.git/`, a `venv/`, CI config, and anything
else living in that repo out of the sandbox; Hermes only ever sees the
skills themselves.

**The `npx skills` canonical store** — `HERMES_AGENTS_SKILLS_DIR`, mounted
at `/skills-src-agents`:

```bash
HERMES_AGENTS_SKILLS_DIR=${HOME}/.agents/skills
```

`skills-cli` dedups by symlinking every agent's copy back to this one shared
store (see [Installing skills](#installing-skills-with-npx-skills)). Mount
it and anything you `npx skills add <repo> -g` for *any* agent on this host
— Claude Code, Cursor, whatever — shows up in Hermes too, no per-agent
install needed.

**Your own code — two distinct mounts, by risk level.** Neither is wired
into `config.yaml`; both are just plain files Hermes can read/browse/`git
log`/`git diff` in its normal working directory. Both are nested *inside*
the workspace, not a separate top-level path, and the risk is visible
directly in the path — `-ro` vs. `-rw` — rather than hidden in a flag:

```bash
# Hermes can inspect and git-log here, but never modify, commit, or push.
HERMES_WORKSPACE_DIR_RO=/path/to/your/code    # -> /workspace/Programming/company-ro

# Hermes can edit files, commit, run any git command that changes state.
# Only point this at something you're genuinely fine with it modifying.
HERMES_WORKSPACE_DIR_RW=/path/to/your/code    # -> /workspace/Programming/company-rw
```

They're independent — set one, both, or neither, and put different repos
under each depending on how much you trust Hermes with them. If you keep
shortcuts to individual repos inside `HERMES_PROJECT_DIR` (e.g.
`Programming/datami-backend`), point them at whichever mount applies with a
*relative* symlink from inside `Programming/`:

```bash
cd "$HERMES_PROJECT_DIR/Programming" && ln -s company-ro/datami-backend datami-backend
```

One easy way to break this: an absolute symlink, or a relative one with the
wrong number of path segments, resolves differently on the host than inside
the container (nested mounts are container-only — the host's own
`Programming/company-ro/` stays empty on disk, populated only inside the
container's mount namespace). Check with `docker compose exec -u hermes
hermes sh -c "ls -L /workspace/Programming/<name>"`, not a host-side `ls`.

`make up` recreates the container with whichever new mount(s) you've set.
For the two skill mounts specifically, you also need to tell `config.yaml`
where to look — add whichever paths you've actually mounted to
`skills.external_dirs`:

```yaml
skills:
  external_dirs:
    - /skills-src
    - /skills-src-agents
```

Both mounts are read-only: `external_dirs` is a read source only — skill
creation always writes to `HERMES_HOME_DIR/skills`, never here — so there's
nothing to lose by not giving Hermes write access. One consequence: a
Python-based skill that expects to `pip install` its own `requirements.txt`
in place will fail (`Read-only file system`), and the base image ships no
`pip` in its venv anyway — only `uv`. Bake missing dependencies into the
image instead, in `Dockerfile`:

```dockerfile
RUN uv pip install --python /opt/hermes/.venv/bin/python3 "some-package>=1,<2"
```

then `make build` to rebuild and restart. Check what's already there first
(`docker compose exec -u hermes hermes /opt/hermes/.venv/bin/python3 -c
"import some_package"`) — common ones like `requests`/`urllib3` already ship
with the base image.

**Keep local dev venvs out of these directories entirely.** If a skill folder
has its own `.venv`/`venv` from local development (common if a skill's own
docs say "first-time setup: `pip install -r requirements.txt`"), it mounts
straight into the read-only skill source too — Hermes finds it, tries to
`pip install` into it per the skill's own setup instructions, hits
`Read-only file system`, and improvises broken workarounds instead of just
using the container's own Python. `make up` scrubs any `.venv`/`venv`
directory it finds inside `HERMES_EXTERNAL_SKILLS_DIR`/
`HERMES_AGENTS_SKILLS_DIR` before starting, precisely so this can't happen —
but it's a symptom worth recognizing on sight (an agent inventing venvs,
copying tool files to `/workspace`, and still failing) in case you ever
bypass `make` and run `docker compose` directly.

Verify any of this with `docker compose exec -u hermes hermes hermes skills
list` — your skills show up with `Source: local`, alongside anything
installed via `npx skills` or `hermes skills install`.

## Native vs. Dockerized Hermes

| | Native `hermes-agent` | This repo (dockerized) |
| --- | --- | --- |
| Filesystem access | Full host access by default — Hermes' own documented behavior | Two bind mounts only (`HERMES_PROJECT_DIR`, `HERMES_HOME_DIR`); nothing else exists inside the container |
| Enabling all tools (file/terminal/browser) | Every tool runs with your full user privileges | Same tools, but confined by the container boundary — `cap_drop`, the mount boundary, network isolation |
| Credentials (`auth.json`, sessions) | Sit in `~/.hermes`, readable by anything running as you | Same data, only reachable from inside the container — *unless* something else on the host also reads `~/.hermes` directly (see risk below) |
| Resource limits | None by default | `pids_limit` / `mem_limit` / `cpus` enforced by Compose |
| Setup | `pip`/`pipx install hermes-agent`, run directly | Docker + Compose, `make up` |
| `npx skills` | Works out of the box (`~/.hermes` is its default) | Works out of the box too, as long as `HERMES_HOME_DIR` stays at the conventional path (see below) |
| Best for | Quick, disposable, low-stakes local use where you already trust the process with full access | Anything you want confined — untrusted skills, autonomous/`--yolo` runs, a long-lived gateway/dashboard |

> **Risk this repo's defaults accept:** `HERMES_HOME_DIR` defaults to
> `~/.hermes` — the same path a *native* `hermes-agent` install would use.
> That's deliberate, so `npx skills` and other tooling that assumes the
> conventional path work with zero configuration. The tradeoff: if you ever
> install and run Hermes natively on this same host, that process has full
> filesystem access and will read/write this exact directory — this
> sandbox's session history, provider credentials, and installed skills —
> with none of the container's confinement. It doesn't weaken the
> container's own isolation (that's determined entirely by which two
> directories are bind-mounted in, never by what they're named); the risk is
> purely a second, non-containerized process later trusting the same path.
> If you never intend to run Hermes natively on this host, the default is
> fine. To rule the collision out entirely, set `HERMES_HOME_DIR` to a
> non-conventional path instead (e.g. `${HOME}/hermes-home`) — see
> [Installing skills](#installing-skills-with-npx-skills) for how `npx
> skills` still works with that.

## Why this approach

Hermes' own docs say plainly: *"The agent has the same filesystem access as
your user account"* by default. Hermes does have an internal "Docker
backend" mode for sandboxing individual tool calls, but that typically needs
access to the Docker socket to spin up nested containers — and anything with
access to `/var/run/docker.sock` can effectively get root on the host. Not
what we want for "safety-first."

The reliable fix is architectural, not a config flag: run the **whole**
Hermes process inside one container with a small, fixed set of bind mounts
(see [Configuration](#configuration)) and nothing else — workspace, Hermes'
own state, and optionally a read-only skills source. It doesn't matter which
Hermes abilities are turned on — the container's filesystem boundary is what
enforces the sandbox, not Hermes' own internal permission system.

## How the image actually boots

`nousresearch/hermes-agent` is an s6-overlay image with a specific,
non-negotiable boot contract — reverse-engineered from its own
`entrypoint-dispatch.sh` / `main-wrapper.sh` / `stage2-hook.sh` while getting
this compose file working, because the defaults you'd guess from a typical
container don't apply here:

1. **The container must start as root** (the image's default `USER`).
   `docker run/compose --user <uid>` is explicitly detected and rejected —
   s6-overlay's bootstrap (UID/GID remap, data-volume chown, config seeding)
   needs root and refuses to run any other way. This compose file does
   **not** set a `user:` override for that reason.
2. **Root only drives the bootstrap, then drops privileges internally.**
   `stage2-hook.sh` runs as root, remaps its baked-in `hermes` user to
   `HERMES_UID`/`HERMES_GID` (aliases: `PUID`/`PGID`) via `usermod`/
   `groupmod`, chowns the writable subtrees under `HERMES_HOME`, then every
   supervised service (`main-hermes`, `dashboard`) execs through
   `s6-setuidgid hermes` before running any Hermes code. The actual agent
   process never runs as root — verify with `docker compose exec hermes ps
   aux`: the `hermes gateway run` PID should show `USER=hermes`, not `root`.
3. **`HERMES_HOME` is `/opt/data`, not a path you'd guess.** It's baked into
   the image's `Dockerfile` and declared as a Docker `VOLUME`. Bind-mount
   your persistence dir anywhere else and the image still writes real state
   (config, sessions, auth tokens, logs) to `/opt/data` — Docker silently
   backs that with an anonymous volume instead, lost on `docker compose down
   -v`. `compose.yml` mounts `HERMES_HOME_DIR` to `/opt/data` for exactly
   this reason.
4. **The dashboard is off unless `HERMES_DASHBOARD` is truthy**, and even
   then fails closed without an auth provider. It binds `0.0.0.0` *inside*
   the container by default (required for Docker's own port publishing to
   reach it); actual internet/LAN exposure is controlled entirely by the
   `ports:` line in `compose.yml` (`127.0.0.1:8642:8642`), not by the
   in-container bind address.

## Sandbox policy actually enforced

The original design called for `read_only: true` + `cap_drop: ALL` with no
exceptions. That's incompatible with this image: root's own bootstrap needs
to rewrite `/etc/passwd`/`/etc/group` (the UID remap) and needs
`CAP_SETUID`/`CAP_SETGID` to drop to the `hermes` user afterward — both
require a writable root filesystem and specific capabilities the strict
version doesn't allow. What's actually applied, verified working:

- **Filesystem boundary is the real control** — only the mounts actually
  merged in are visible: `HERMES_PROJECT_DIR` → `/workspace` and
  `HERMES_HOME_DIR` → `/opt/data` always; `HERMES_EXTERNAL_SKILLS_DIR` →
  `/skills-src` and `HERMES_AGENTS_SKILLS_DIR` → `/skills-src-agents`, both
  read-only, only if you've set them (see [Mounting your own skills and
  code](#mounting-your-own-skills-and-code)) — nothing else, so there
  is no host path for Hermes to reach beyond those. Verified with `docker
  compose exec hermes sh -c "ls / && ls /workspace/.."` — no host filesystem
  visible outside the mounted paths.
- **Capabilities are trimmed, not fully dropped**: `cap_drop: ALL` plus a
  targeted `cap_add` for exactly what the boot sequence needs —
  `SETUID`/`SETGID` (privilege drop to `hermes`), `CHOWN`/`FOWNER`/
  `DAC_OVERRIDE` (chowning `HERMES_HOME` subdirs and the UID/GID remap).
  Nothing beyond that; verify with `docker compose exec hermes cat
  /proc/self/status | grep Cap`.
- **The agent process itself runs unprivileged** — root only drives the boot
  sequence, then hands off (confirmed via `ps aux`, point 2 above).
- **`no-new-privileges`** — blocks privilege escalation via setuid binaries
  even within the capabilities that are granted.
- **`pids_limit`, `mem_limit`, `cpus`** — a runaway process can't take down
  the host.
- **Dedicated bridge network**, dashboard port bound to `127.0.0.1` only.
- **`/tmp` is tmpfs** — nothing written there persists across a restart.
- **Host directory ownership matters**: `HERMES_PROJECT_DIR` and
  `HERMES_HOME_DIR` must actually be owned by the `UID`/`GID` in `.env`
  *before* the container's bootstrap chown logic can help — it only fixes
  ownership of subdirectories it creates itself under `HERMES_HOME`, not the
  top-level bind-mounted directories, and Docker auto-creates a missing
  bind-mount target as root. Check with `stat -c '%U:%G' project/`; fix with
  a throwaway root container if needed (`docker run --rm -v
  "$(pwd)/project:/w" alpine chown 1000:1000 /w`).

## Connecting third-party services (Telegram, Discord, etc.)

These work over the default bridge network without special config, **as
long as the integration only needs outbound connections** — the normal case
(a Telegram bot polling `api.telegram.org`, a Discord bot opening a gateway
websocket, calling a webhook URL). Outbound traffic from a bridged container
isn't blocked by default; you don't need `network_mode: host` for this, and
giving Hermes host networking would instead expose every service listening
on your laptop's `localhost` to it — a much bigger hole than the one you're
trying to open.

Add the relevant token(s) to `.env`, point `config.yaml` (in
`HERMES_HOME_DIR`) at that integration, and it should just work.

The one case that needs something extra: an integration that requires
Hermes to receive an **inbound** connection (a webhook target, rather than
polling out). Add another port to the `ports:` block in `compose.yml` and
bind it to `127.0.0.1:<port>` — not `0.0.0.0` — so it's reachable from your
machine but not your LAN or the open internet.

Only work you want Hermes to touch should live under `./project`. Anything
you drop into `./project` is fair game for Hermes to read/edit/execute —
treat it like handing someone a USB stick, not like giving it your laptop.

## Turning on all abilities safely

In `HERMES_HOME_DIR/config.yaml`, set `terminal.backend: local` (this means
"run in the same environment as the Hermes process" — already this
locked-down container, so it's the right choice here, *not* Hermes' Docker
backend, which would try to escape this container via the Docker socket).
Then enable whichever tools you want (file ops, terminal, web/browser,
etc.) — go ahead and turn all of them on. The container boundary, not the
tool toggles, is what keeps it off the rest of your laptop.

## Things to deliberately avoid

- **Never** mount `/var/run/docker.sock` into this container. That's the
  single most common way "sandboxed" agent setups quietly regain full host
  access.
- **Never** bind-mount your real `$HOME` or `/` "just in case." If Hermes
  needs a file, copy it into `./project`.
- Don't run with `--privileged`.
- Don't install `hermes-agent` natively on a host where `HERMES_HOME_DIR`
  points at the conventional `~/.hermes` path unless you've read and
  accepted the tradeoff in [Native vs. Dockerized Hermes](#native-vs-dockerized-hermes).
- If you eventually want network restrictions too (e.g. Hermes can only
  reach its LLM provider, nothing else), that's a further step — ask and I
  can help set up an egress-filtered network, since by default this setup
  still allows outbound internet access (needed for the model API and any
  web-browsing tool).

## Verifying the sandbox actually holds

With `make up` running, check the filesystem boundary — no trace of your
real home directory, other projects, dotfiles, browser profiles, SSH keys:

```bash
docker compose exec hermes sh -c "ls / && ls /workspace/.. 2>&1"
```

You should see a normal container filesystem with `/workspace` and
`/opt/data` (Hermes' actual `HERMES_HOME` — see [How the image actually
boots](#how-the-image-actually-boots)), plus `/skills-src` and/or
`/skills-src-agents` only if you set the matching env var, and
`/workspace/Programming/company-ro`/`-rw` likewise (see [Mounting your own
skills and code](#mounting-your-own-skills-and-code)) — nothing else
reachable above `/workspace`. If a read-only mount is present, confirm it's
actually read-only: `docker compose exec hermes sh -c "touch
/skills-src/x"` should fail with `Read-only file system`.

Then confirm the agent itself — not just an ad-hoc root shell — runs
unprivileged and can actually use its one writable directory. `docker
compose exec` without `-u` defaults to root (fine for admin/inspection
commands, but not what the supervised Hermes process runs as):

```bash
docker compose exec hermes ps aux | grep 'hermes gateway'   # USER column should read "hermes", not root
docker compose exec -u hermes hermes sh -c \
  'id; echo ok > /workspace/.sandbox_check && cat /workspace/.sandbox_check && rm /workspace/.sandbox_check'
```

If that write fails with `Permission denied`, the host `HERMES_PROJECT_DIR`
isn't owned by the `UID`/`GID` in `.env` — see the ownership note in
[Sandbox policy actually enforced](#sandbox-policy-actually-enforced).

Capabilities actually granted (should list only `SETUID`/`SETGID`/`CHOWN`/
`FOWNER`/`DAC_OVERRIDE`; decode at
[capsh](https://man7.org/linux/man-pages/man1/capsh.1.html) or compare the
hex to a fresh `cap_drop: ALL` container, which reads
`0000000000000000`):

```bash
docker compose exec hermes cat /proc/self/status | grep Cap
```
