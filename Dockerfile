FROM nousresearch/hermes-agent:latest

# Extra Python deps needed by skills mounted read-only via
# HERMES_EXTERNAL_SKILLS_DIR (see README -> "Mounting your own skills
# directory"). That mount is read-only by design, and the base image's own
# venv ships with no `pip` at all — only `uv`, which is already on PATH —
# so installing straight into the venv at build time is the clean fix,
# rather than fighting a writable venv into a read-only skill source at
# runtime. Only list what's actually missing: requests/urllib3 (jira skill)
# already ship with the base image; add more `uv pip install` lines here as
# your skills' requirements.txt files grow.
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    "telethon>=1.36,<2"
