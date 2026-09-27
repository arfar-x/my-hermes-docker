FROM nousresearch/hermes-agent:latest

# Hermes' local terminal backend runs every command in a *login* shell
# (`bash -l`), and Debian's /etc/profile unconditionally resets PATH for
# non-root users on login, silently dropping /opt/hermes/.venv/bin (and
# /opt/hermes/bin) — so skills relying on venv-installed deps (see
# docker/cont-init.d/05-skill-deps below) fail with the base system Python
# instead, hitting PEP 668. `docker exec` (no `-l`) never hits this, which
# is why it's easy to miss testing that way. See docker/profile.d for the
# full explanation.
COPY docker/profile.d/10-hermes-path.sh /etc/profile.d/10-hermes-path.sh
RUN chmod +x /etc/profile.d/10-hermes-path.sh

# Skills mounted read-only via HERMES_EXTERNAL_SKILLS_DIR /
# HERMES_AGENTS_SKILLS_DIR (see README -> "Mounting your own skills
# directory") bring their own requirements.txt. Installing those by hand
# here drifts out of sync the moment a skill's deps change — instead,
# docker/cont-init.d/05-skill-deps installs every mounted skill's
# requirements.txt into the venv automatically on each container start.
# See that file for the full explanation.
COPY docker/cont-init.d/05-skill-deps /etc/cont-init.d/05-skill-deps
RUN chmod +x /etc/cont-init.d/05-skill-deps

# Claude Code CLI — `hermes model` -> "Claude Pro/Max subscription (OAuth)"
# shells out to `claude setup-token`, so subscription auth (no API key)
# needs the real binary on PATH. Its login state lands in ~/.claude, i.e.
# /opt/data/.claude on the persistent HERMES_HOME volume.
RUN npm install -g @anthropic-ai/claude-code && claude --version

# Codex CLI — same idea for ChatGPT-subscription auth; login state lands in
# ~/.codex, i.e. /opt/data/.codex on the persistent HERMES_HOME volume.
RUN npm install -g @openai/codex && codex --version
