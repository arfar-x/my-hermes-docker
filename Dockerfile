FROM nousresearch/hermes-agent:latest

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
