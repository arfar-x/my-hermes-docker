# Restores the image's own PATH prefix after /etc/profile's unconditional
# reset (Debian's /etc/profile hardcodes PATH for non-root logins, dropping
# whatever the container's own PATH env was). Sourced by every *login* shell
# via /etc/profile's run-parts loop over /etc/profile.d/*.sh — this is what
# Hermes' local terminal backend spawns (`bash -l`) for every command it
# runs, so without this, /opt/hermes/.venv/bin (skill deps — see
# docker/cont-init.d/05-skill-deps) and /opt/hermes/bin silently vanish from
# PATH for any skill/tool invocation, even though `docker exec` (no -l) never
# hits the problem — which is why it's easy to miss testing this way.
export PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:$PATH"
