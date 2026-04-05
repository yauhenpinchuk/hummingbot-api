# Sol-pump LP configs (v2_with_controllers)

YAML committed here is copied into gitignored `bots/conf/` by:

```bash
make install-sol-pump-config
```

Then sync your live Hummingbot `conf/` (keys, `conf_client.yml`) into `bots/credentials/<profile>/` — see the main [README](../../README.md#integrate-an-existing-hummingbot-sol-pump-lp-stack).

## Postgres for bot trade DB (same instance as hummingbot-api)

To store Hummingbot native tables in database `**hummingbot_sol_pump**` on the API Postgres (not `crypto_analytics`):

1. **New Postgres volume:** `init-db.sql` creates `hummingbot_sol_pump` on first container init (no action).
2. **Existing volume / prod:** run `make ensure-hummingbot-trading-db` locally, or on server  
   `COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=../.secrets/env ./scripts/ensure-hummingbot-trading-db.sh`  
   (also runs automatically after each deploy in `.github/workflows/deploy.yml`).
3. Merge `db_mode.postgres-hummingbot-api.yml` into each bot’s `conf_client.yml` (`db_password` = `POSTGRES_PASSWORD`). Bots use `network_mode: host` → `127.0.0.1:55432`.

