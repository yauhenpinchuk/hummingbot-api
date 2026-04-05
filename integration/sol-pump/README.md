# Sol-pump LP configs (v2_with_controllers)

YAML committed here is copied into gitignored `bots/conf/` by:

```bash
make install-sol-pump-config
```

Then sync your live Hummingbot `conf/` (keys, `conf_client.yml`) into `bots/credentials/<profile>/` — see the main [README](../../README.md#integrate-an-existing-hummingbot-sol-pump-lp-stack).

## Postgres for bot trade DB (same instance as hummingbot-api)

To store Hummingbot native tables in database **`hummingbot`** on the API Postgres (not `crypto_analytics`):

1. `make ensure-hummingbot-trading-db` (or fresh volume: `init-db.sql` creates it).
2. Merge `db_mode.postgres-hummingbot-api.yml` into each bot’s `conf_client.yml` (set `db_password` = `POSTGRES_PASSWORD`). Bots use `network_mode: host` → `127.0.0.1:55432`.
