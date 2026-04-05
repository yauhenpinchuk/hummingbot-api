# Hummingbot API

A REST API for managing Hummingbot trading bots across multiple exchanges, with AI assistant integration via MCP.

## Quick Start

```bash
git clone https://github.com/hummingbot/hummingbot-api.git
cd hummingbot-api
make setup    # Creates .env (prompts for passwords)
make deploy   # Starts all services
```

That's it! The API is now running at http://localhost:8000

## Available Commands

| Command | Description |
|---------|-------------|
| `make setup` | Create `.env` file with configuration |
| `make deploy` | Start all services (API, PostgreSQL, EMQX) |
| `make stop` | Stop all services |
| `make run` | Run API locally in dev mode |
| `make install` | Install conda environment for development |
| `make build` | Build Docker image |

## Services

After `make deploy`, these services are available:

| Service | URL | Description |
|---------|-----|-------------|
| **API** | http://localhost:8000 | REST API |
| **Swagger UI** | http://localhost:8000/docs | Interactive API documentation |
| **PostgreSQL** | localhost:55432 | Database (dedicated port; avoids clashing with other Postgres on 5432) |
| **EMQX** | localhost:1883 | MQTT broker |
| **EMQX Dashboard** | http://localhost:18083 | Broker admin (admin/public) |

## Connect AI Assistant (MCP)

### Claude Code (CLI)

```bash
claude mcp add --transport stdio hummingbot -- \
  docker run --rm -i \
  -e HUMMINGBOT_API_URL=http://host.docker.internal:8000 \
  -v hummingbot_mcp:/root/.hummingbot_mcp \
  hummingbot/hummingbot-mcp:latest
```

Then use natural language:
- "Show my portfolio balances"
- "Set up my Binance account"
- "Create a market making strategy for ETH-USDT"

### Claude Desktop

Add to your config file:
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "hummingbot": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "-e", "HUMMINGBOT_API_URL=http://host.docker.internal:8000", "-v", "hummingbot_mcp:/root/.hummingbot_mcp", "hummingbot/hummingbot-mcp:latest"]
    }
  }
}
```

Restart Claude Desktop after adding.

## Gateway (DEX Trading)

Gateway enables decentralized exchange trading. Start it via MCP:

> "Start Gateway in development mode with passphrase 'admin'"

Or via API at http://localhost:8000/docs using the Gateway endpoints.

Once running, Gateway is available at http://localhost:15888

## Production deployment (same pattern as the hummingbot + gateway stack)

This fork can deploy next to the hummingbot repo under **`/opt/hummingbot-stack/`**.

1. **Clone** next to hummingbot: `git clone <your-fork> /opt/hummingbot-stack/hummingbot-api` and check out `main`.
2. **Secrets file**: `mkdir -p /opt/hummingbot-stack/.secrets && cp hummingbot-api/.env.example /opt/hummingbot-stack/.secrets/env && chmod 600 /opt/hummingbot-stack/.secrets/env`. Edit the file: set strong passwords, and ensure `DATABASE_URL` uses the same `hbot` password as `POSTGRES_PASSWORD`. Keep `POSTGRES_USER=hbot` unless you change `init-db.sql`.
3. **GitHub Actions** (repository **Settings → Secrets**): reuse the same keys as the hummingbot deploy workflow — `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `GHCR_TOKEN` (PAT with `read:packages` for pulls, or classic token that can `docker login ghcr.io`). The workflow builds `ghcr.io/<owner>/hummingbot-api:latest` and SSHes to pull and run `docker-compose.prod.yml`.
4. **Package visibility**: if the image is private, grant the server’s GHCR login access or make the package public.
5. **PostgreSQL**: the API stack uses its own container and **host port `127.0.0.1:55432`**, so it does not bind to `5432` used by crypto-analytics or other stacks.
6. **Gateway**: `GATEWAY_URL` defaults to `http://host.docker.internal:15888` so the API container can reach the gateway service on the host.

Push to `main` or run the **Build and Deploy — Hummingbot API** workflow manually. To deploy by hand after a build:

```bash
export HUMMINGBOT_API_IMAGE=ghcr.io/<owner>/hummingbot-api:latest
cd /opt/hummingbot-stack/hummingbot-api
docker compose -f docker-compose.prod.yml --env-file ../.secrets/env pull
docker compose -f docker-compose.prod.yml --env-file ../.secrets/env up -d
```

## Configuration

The `.env` file contains all configuration. Key settings:

```bash
USERNAME=admin              # API username
PASSWORD=admin              # API password
CONFIG_PASSWORD=admin       # Encrypts bot credentials
DATABASE_URL=...            # PostgreSQL (with compose: localhost:55432 from host, postgres:5432 from API container)
GATEWAY_URL=...             # Gateway URL (for DEX)
```

Edit `.env` and restart with `make deploy` to apply changes.

## API Features

- **Portfolio**: Balances, positions, P&L across all exchanges
- **Trading**: Place orders, manage positions, track history
- **Bots**: Deploy, monitor, and control trading bots
- **Market Data**: Prices, orderbooks, candles, funding rates
- **Strategies**: Create and manage trading strategies

Full API documentation at http://localhost:8000/docs

## Development

```bash
make install              # Create conda environment
conda activate hummingbot-api
make run                  # Run with hot-reload
```

## Troubleshooting

**API won't start?**
```bash
docker compose logs hummingbot-api
```

**Database issues?**
```bash
docker compose down -v    # Reset all data
make deploy               # Fresh start
```

**Check service status:**
```bash
docker ps | grep hummingbot
```

## Support

- **API Docs**: http://localhost:8000/docs
- **Issues**: https://github.com/hummingbot/hummingbot-api/issues
