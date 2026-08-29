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
