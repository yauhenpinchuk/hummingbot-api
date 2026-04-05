.PHONY: setup run deploy deploy-docker stop install uninstall build install-pre-commit install-sol-pump-config sync-credentials-from-hummingbot ensure-hummingbot-trading-db

# Directory containing this Makefile (recipes work even if `make -f path/Makefile` is run from elsewhere)
MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

SETUP_SENTINEL := .setup-complete

setup: $(SETUP_SENTINEL)

$(SETUP_SENTINEL):
	chmod +x setup.sh
	./setup.sh

# Run locally (dev mode)
run:
	docker compose up emqx postgres -d
	conda run --no-capture-output -n hummingbot-api uvicorn main:app --reload

# Deploy with Docker (builds API image from Dockerfile if needed)
deploy: $(SETUP_SENTINEL)
	docker compose up -d --build

# Same as deploy but skips setup (no `.env` required; optional env_file — app defaults apply)
deploy-docker:
	docker compose up -d --build

# Stop all services
stop:
	docker compose down

# Install conda environment
install:
	@if ! command -v conda >/dev/null 2>&1; then \
		echo "Error: Conda is not found in PATH. Please install Conda or add it to your PATH."; \
		exit 1; \
	fi
	@if conda env list | grep -q '^hummingbot-api '; then \
		echo "Environment already exists."; \
	else \
		conda env create -f environment.yml; \
	fi
	$(MAKE) install-pre-commit
	$(MAKE) setup

uninstall:
	conda env remove -n hummingbot-api -y
	rm -f $(SETUP_SENTINEL)

install-pre-commit:
	conda run -n hummingbot-api pip install pre-commit
	conda run -n hummingbot-api pre-commit install

# Build Docker image
build:
	docker build -t local/hummingbot-api:latest .

# Copy committed sol-pump YAML into bots/conf/scripts|controllers (required before deploy-v2-script for sol-pump)
install-sol-pump-config:
	"$(MAKEFILE_DIR)/scripts/install-sol-pump-config.sh"

# Create DB `hummingbot_sol_pump` on API Postgres if missing (for bot MarketsRecorder; same instance as hummingbot_api)
ensure-hummingbot-trading-db:
	"$(MAKEFILE_DIR)/scripts/ensure-hummingbot-trading-db.sh"

# Copy Hummingbot repo conf/ -> bots/credentials/<profile>/ (default: sol_pump). Usage: make sync-credentials-from-hummingbot HUMMINGBOT_ROOT=../hummingbot PROFILE=sol_pump
sync-credentials-from-hummingbot:
	@if [ -z "$(HUMMINGBOT_ROOT)" ]; then echo "Set HUMMINGBOT_ROOT=path/to/hummingbot"; exit 1; fi
	"$(MAKEFILE_DIR)/scripts/sync-credentials-from-hummingbot.sh" "$(HUMMINGBOT_ROOT)" "$(or $(PROFILE),sol_pump)"