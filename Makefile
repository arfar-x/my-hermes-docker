.PHONY: up down build cli dashboard logs restart status doctor skill-add skill-list skill-update alias-install alias-remove

# Host path for HERMES_HOME_DIR, with ${HOME} etc. resolved from .env — this is
# what's bind-mounted into the container as /opt/data. `npx skills` needs it fed
# in via HERMES_HOME, otherwise it defaults to ~/.hermes, which the sandboxed
# Hermes never reads (see README: "Installing skills from the host").
HERMES_HOME_HOST := $(shell v=$$(grep -E '^HERMES_HOME_DIR=' .env 2>/dev/null | tail -1 | cut -d= -f2-); if [ -n "$$v" ]; then eval echo "$$v"; else echo "$$HOME/hermes-home"; fi)

ALIAS_BEGIN := \# >>> hermes-docker alias >>>
ALIAS_END   := \# <<< hermes-docker alias <<<

# Optional skill-source mounts (see compose.skills.yml / compose.agents-skills.yml)
# are merged in only when their .env var is actually set and non-empty — so the
# sandbox stays at exactly two bind mounts unless you opt in. Every `docker
# compose` call below goes through this so they're never accidentally skipped
# or accidentally left out.
COMPOSE_FILES := -f compose.yml
ifneq ($(strip $(shell grep -E '^HERMES_EXTERNAL_SKILLS_DIR=' .env 2>/dev/null | cut -d= -f2-)),)
COMPOSE_FILES += -f compose.skills.yml
endif
ifneq ($(strip $(shell grep -E '^HERMES_AGENTS_SKILLS_DIR=' .env 2>/dev/null | cut -d= -f2-)),)
COMPOSE_FILES += -f compose.agents-skills.yml
endif

## Start the gateway (dashboard + keeps container warm for `make cli`), and
## make sure the `hermes` shell alias is set up. Never touches HERMES_HOME_DIR
## or HERMES_PROJECT_DIR — nothing here can lose data.
up:
	docker compose $(COMPOSE_FILES) up -d
	@$(MAKE) --no-print-directory alias-install

## Rebuild the local image after editing Dockerfile (e.g. adding a Python
## dependency for an external skill). `make up` reuses the existing image
## and won't pick up Dockerfile changes on its own.
build:
	docker compose $(COMPOSE_FILES) build
	@$(MAKE) --no-print-directory up

## Stop and remove the container — data (HERMES_HOME_DIR, HERMES_PROJECT_DIR)
## is on bind-mounted host directories, not Docker volumes (there are none in
## compose.yml), so it's untouched by this. Also reverts the `hermes` alias
## added by `make up`.
down:
	docker compose $(COMPOSE_FILES) down
	@$(MAKE) --no-print-directory alias-remove

## Add a `hermes` shell alias (bash + zsh) for `docker exec -it hermes hermes`.
## Idempotent — safe to run repeatedly. Runs automatically from `make up`.
alias-install:
	@for rc in "$$HOME/.bashrc" "$$HOME/.zshrc"; do \
		[ -f "$$rc" ] || continue; \
		if grep -qF '$(ALIAS_BEGIN)' "$$rc" 2>/dev/null; then \
			echo "[hermes-docker] alias already present in $$rc"; \
		else \
			{ echo ""; echo "$(ALIAS_BEGIN)"; echo "alias hermes='docker exec -it hermes hermes'"; echo "$(ALIAS_END)"; } >> "$$rc"; \
			echo "[hermes-docker] alias added to $$rc (open a new shell, or: source $$rc)"; \
		fi; \
	done

## Remove the `hermes` shell alias added by alias-install. Runs automatically
## from `make down`.
alias-remove:
	@for rc in "$$HOME/.bashrc" "$$HOME/.zshrc"; do \
		[ -f "$$rc" ] || continue; \
		if grep -qF '$(ALIAS_BEGIN)' "$$rc" 2>/dev/null; then \
			sed -i '/$(ALIAS_BEGIN)/,/$(ALIAS_END)/d' "$$rc"; \
			sed -i -e :a -e '/^\n*$$/{$$d;N;ba' -e '}' "$$rc"; \
			echo "[hermes-docker] alias removed from $$rc"; \
		fi; \
	done

## Open an interactive Hermes CLI session inside the running container
cli:
	docker compose $(COMPOSE_FILES) exec hermes hermes

## Print the dashboard URL (container must be up)
dashboard:
	@echo "Dashboard: http://127.0.0.1:8642"

## Tail container logs
logs:
	docker compose $(COMPOSE_FILES) logs -f hermes

## Restart the container (e.g. after editing config.yaml)
restart:
	docker compose $(COMPOSE_FILES) restart hermes

## Check the container is up and Hermes is healthy
status:
	docker compose $(COMPOSE_FILES) ps

doctor:
	docker compose $(COMPOSE_FILES) exec hermes hermes doctor

## Install a skill from the host straight into the sandboxed Hermes' skills dir.
## Usage: make skill-add REPO=owner/repo [SKILL=skill-name]
skill-add:
	HERMES_HOME=$(HERMES_HOME_HOST) npx skills add $(REPO) -g -a hermes-agent -y $(if $(SKILL),-s $(SKILL),)

## List skills currently installed for the sandboxed Hermes (host-side view)
skill-list:
	HERMES_HOME=$(HERMES_HOME_HOST) npx skills list -g -a hermes-agent

## Update all hub-installed skills for the sandboxed Hermes
skill-update:
	HERMES_HOME=$(HERMES_HOME_HOST) npx skills update -g -a hermes-agent
