# LP Rebalancer Startup Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix lp_rebalancer controller so it reliably adopts existing on-chain LP positions after a bot restart, even when Gateway/Helius is slow to respond at startup.

**Architecture:** Add `on_start()` hook to `LPRebalancer` that retries fetching pool price (up to 120s) before the first tick runs. Fix `update_processed_data` to use `get_connector_with_fallback` (no ValueError on unregistered connector) and log at WARNING instead of DEBUG. Add a tick counter in `determine_executor_actions` so silence is visible. No changes to `lp_executor.py` — its `_adopt_existing_position_if_any()` already works correctly once an executor is created.

**Tech Stack:** Python 3.12, asyncio, hummingbot strategy_v2 framework, `market_data_provider.get_connector_with_fallback()`

---

## File Map

| File | Change |
|---|---|
| `bots/controllers/generic/lp_rebalancer/lp_rebalancer.py` | Add `on_start()`, fix `update_processed_data`, add no-price counter |
| `test/test_lp_rebalancer_startup.py` | New — unit tests for all three changes |

---

### Task 1: Add failing tests for `on_start` retry logic

**Files:**
- Create: `test/test_lp_rebalancer_startup.py`

- [ ] **Step 1: Write the test file**

```python
"""
Unit tests for lp_rebalancer startup recovery:
1. on_start() warms up _pool_price with retry
2. update_processed_data uses get_connector_with_fallback (no ValueError)
3. determine_executor_actions warns visibly when _pool_price is missing
"""
import asyncio
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock

import pytest

pytest.importorskip("hummingbot")

from bots.controllers.generic.lp_rebalancer.lp_rebalancer import LPRebalancer, LPRebalancerConfig


def _make_config(**kwargs):
    defaults = dict(
        id="test_ctrl",
        connector_name="raydium/clmm",
        network="mainnet-beta",
        trading_pair="SOL-PUMP",
        pool_address="45ssPkUQs1ssbeDqxD2mZrMdJYAXF7GyQyhS5xDXuWC5",
        total_amount_quote=Decimal("100"),
        side=0,
        position_width_pct=Decimal("5"),
        position_offset_pct=Decimal("0.4"),
        rebalance_seconds=300,
        rebalance_threshold_pct=Decimal("0.5"),
    )
    defaults.update(kwargs)
    return LPRebalancerConfig(**defaults)


def _make_controller(pool_price_responses):
    """
    pool_price_responses: list of values get_pool_info_by_address returns in order.
    Use None to simulate failure, Decimal to simulate success.
    """
    config = _make_config()
    market_data_provider = MagicMock()
    actions_queue = MagicMock()

    # Build connector mock
    connector = MagicMock()
    call_count = [0]

    async def fake_pool_info(pool_address):
        idx = min(call_count[0], len(pool_price_responses) - 1)
        call_count[0] += 1
        val = pool_price_responses[idx]
        if val is None:
            raise RuntimeError("Gateway not ready")
        info = MagicMock()
        info.price = float(val)
        return info

    connector.get_pool_info_by_address = fake_pool_info
    market_data_provider.get_connector_with_fallback.return_value = connector

    ctrl = LPRebalancer.__new__(LPRebalancer)
    ctrl.config = config
    ctrl.market_data_provider = market_data_provider
    ctrl.actions_queue = actions_queue
    ctrl._base_token = "SOL"
    ctrl._quote_token = "PUMP"
    ctrl._pool_price = None
    ctrl._no_price_ticks = 0
    ctrl._current_executor_id = None
    ctrl._pending_rebalance = False
    ctrl._pending_rebalance_side = None
    ctrl._last_closed_base_amount = None
    ctrl._last_closed_quote_amount = None
    ctrl._last_closed_base_fee = None
    ctrl._last_closed_quote_fee = None
    ctrl._initial_base_balance = None
    ctrl._initial_quote_balance = None
    ctrl._pending_balance_update = False
    ctrl.executors_info = []
    return ctrl, call_count


class TestOnStartRetry:
    """on_start() should populate _pool_price, retrying until success or timeout."""

    @pytest.mark.asyncio
    async def test_on_start_succeeds_first_attempt(self):
        ctrl, call_count = _make_controller([Decimal("47500")])
        with patch("asyncio.sleep", new_callable=AsyncMock):
            await ctrl.on_start()
        assert ctrl._pool_price == Decimal("47500")
        assert call_count[0] == 1

    @pytest.mark.asyncio
    async def test_on_start_retries_on_failure_then_succeeds(self):
        # Fail twice, succeed on third attempt
        ctrl, call_count = _make_controller([None, None, Decimal("48000")])
        sleep_calls = []
        async def fake_sleep(n):
            sleep_calls.append(n)
        with patch("asyncio.sleep", side_effect=fake_sleep):
            await ctrl.on_start()
        assert ctrl._pool_price == Decimal("48000")
        assert call_count[0] == 3
        assert len(sleep_calls) == 2  # slept between failures

    @pytest.mark.asyncio
    async def test_on_start_gives_up_after_timeout(self):
        # Always fail
        ctrl, call_count = _make_controller([None] * 20)
        with patch("asyncio.sleep", new_callable=AsyncMock):
            await ctrl.on_start()
        assert ctrl._pool_price is None  # gave up, no crash

    @pytest.mark.asyncio
    async def test_on_start_logs_warning_on_each_retry(self):
        ctrl, _ = _make_controller([None, Decimal("47000")])
        log_calls = []
        ctrl.logger = lambda: MagicMock(
            warning=lambda msg: log_calls.append(("warning", msg)),
            info=lambda msg: log_calls.append(("info", msg)),
            error=lambda msg: log_calls.append(("error", msg)),
        )
        with patch("asyncio.sleep", new_callable=AsyncMock):
            await ctrl.on_start()
        warnings = [msg for level, msg in log_calls if level == "warning"]
        assert len(warnings) == 1  # one failure before success


class TestUpdateProcessedDataFallback:
    """update_processed_data should use get_connector_with_fallback, not get_connector."""

    @pytest.mark.asyncio
    async def test_uses_get_connector_with_fallback(self):
        ctrl, _ = _make_controller([Decimal("50000")])
        await ctrl.update_processed_data()
        ctrl.market_data_provider.get_connector_with_fallback.assert_called_once_with(
            "raydium/clmm"
        )

    @pytest.mark.asyncio
    async def test_get_connector_not_called(self):
        ctrl, _ = _make_controller([Decimal("50000")])
        await ctrl.update_processed_data()
        ctrl.market_data_provider.get_connector.assert_not_called()

    @pytest.mark.asyncio
    async def test_pool_price_updated_on_success(self):
        ctrl, _ = _make_controller([Decimal("47600")])
        await ctrl.update_processed_data()
        assert ctrl._pool_price == Decimal("47600")

    @pytest.mark.asyncio
    async def test_failure_logs_warning_not_debug(self):
        ctrl, _ = _make_controller([None])
        debug_calls = []
        warning_calls = []
        mock_logger = MagicMock()
        mock_logger.debug.side_effect = lambda msg, **kw: debug_calls.append(msg)
        mock_logger.warning.side_effect = lambda msg, **kw: warning_calls.append(msg)
        ctrl.logger = lambda: mock_logger
        await ctrl.update_processed_data()
        assert len(warning_calls) == 1
        assert len(debug_calls) == 0


class TestNoPriceTickCounter:
    """determine_executor_actions should warn visibly when _pool_price is missing."""

    def test_first_tick_without_price_logs_warning(self):
        ctrl, _ = _make_controller([])
        ctrl._pool_price = None
        ctrl._no_price_ticks = 0
        warning_calls = []
        mock_logger = MagicMock()
        mock_logger.warning.side_effect = lambda msg: warning_calls.append(msg)
        ctrl.logger = lambda: mock_logger
        ctrl.determine_executor_actions()
        assert ctrl._no_price_ticks == 1
        assert len(warning_calls) == 1

    def test_counter_increments_each_tick(self):
        ctrl, _ = _make_controller([])
        ctrl._pool_price = None
        ctrl._no_price_ticks = 0
        with patch.object(ctrl, 'logger', return_value=MagicMock()):
            ctrl.determine_executor_actions()
            ctrl.determine_executor_actions()
            ctrl.determine_executor_actions()
        assert ctrl._no_price_ticks == 3

    def test_counter_resets_when_price_available(self):
        ctrl, _ = _make_controller([])
        ctrl._pool_price = Decimal("47000")
        ctrl._no_price_ticks = 10
        # With price available, counter should reset (no warning)
        with patch.object(ctrl, 'logger', return_value=MagicMock()):
            ctrl.determine_executor_actions()
        assert ctrl._no_price_ticks == 0

    def test_warning_every_5_ticks(self):
        ctrl, _ = _make_controller([])
        ctrl._pool_price = None
        ctrl._no_price_ticks = 0
        warning_calls = []
        mock_logger = MagicMock()
        mock_logger.warning.side_effect = lambda msg: warning_calls.append(msg)
        ctrl.logger = lambda: mock_logger
        for _ in range(10):
            ctrl.determine_executor_actions()
        # ticks 1,6 → 2 warnings (tick N where (N-1) % 5 == 0)
        assert len(warning_calls) == 2
```

- [ ] **Step 2: Run tests — expect ImportError or AttributeError (methods not yet added)**

```bash
cd /home/yauhen/crypto/hummingbot-api
conda run -n hummingbot pytest test/test_lp_rebalancer_startup.py -v 2>&1 | tail -30
```

Expected: tests fail with `AttributeError` on `on_start` or missing `_no_price_ticks`.

---

### Task 2: Add `on_start()` to `LPRebalancer`

**Files:**
- Modify: `bots/controllers/generic/lp_rebalancer/lp_rebalancer.py`

- [ ] **Step 1: Add `import asyncio` at top of file**

In [lp_rebalancer.py](bots/controllers/generic/lp_rebalancer/lp_rebalancer.py), after line 1 (`import logging`):

```python
import asyncio
import logging
```

- [ ] **Step 2: Add `_no_price_ticks` to `__init__`**

In `__init__` (around line 142, after `self._pending_balance_update: bool = False`), add:

```python
        # Track consecutive ticks without pool price for visible diagnostics
        self._no_price_ticks: int = 0
```

- [ ] **Step 3: Add `on_start()` method after `__init__`**

After `__init__` ends (before `def active_executor`), insert:

```python
    async def on_start(self):
        """
        Warm up pool price before the first control_task tick.
        Retries up to max_wait seconds to handle Gateway/Helius startup latency.
        After timeout, returns without price — update_processed_data continues retrying each tick.
        """
        max_wait = 120
        interval = 10
        attempts = max_wait // interval
        for attempt in range(1, attempts + 1):
            try:
                connector = self.market_data_provider.get_connector_with_fallback(
                    self.config.connector_name
                )
                pool_info = await connector.get_pool_info_by_address(self.config.pool_address)
                if pool_info and pool_info.price:
                    self._pool_price = Decimal(str(pool_info.price))
                    self.logger().info(
                        f"on_start: pool price ready ({self._pool_price}) on attempt {attempt}"
                    )
                    return
            except Exception as e:
                self.logger().warning(
                    f"on_start: pool price not available (attempt {attempt}/{attempts}): {e}"
                )
            await asyncio.sleep(interval)
        self.logger().error(
            f"on_start: pool price unavailable after {max_wait}s — "
            f"starting anyway, will retry each tick"
        )
```

- [ ] **Step 4: Run on_start tests — expect them to pass**

```bash
cd /home/yauhen/crypto/hummingbot-api
conda run -n hummingbot pytest test/test_lp_rebalancer_startup.py::TestOnStartRetry -v 2>&1 | tail -20
```

Expected: all 4 `TestOnStartRetry` tests PASS.

---

### Task 3: Fix `update_processed_data`

**Files:**
- Modify: `bots/controllers/generic/lp_rebalancer/lp_rebalancer.py:573-582`

- [ ] **Step 1: Replace the method body**

Current code at line ~573:
```python
    async def update_processed_data(self):
        """Called every tick - always fetch fresh pool price for accurate position creation."""
        try:
            connector = self.market_data_provider.get_connector(self.config.connector_name)
            if hasattr(connector, 'get_pool_info_by_address'):
                pool_info = await connector.get_pool_info_by_address(self.config.pool_address)
                if pool_info and pool_info.price:
                    self._pool_price = Decimal(str(pool_info.price))
        except Exception as e:
            self.logger().debug(f"Could not fetch pool price: {e}")
```

Replace with:
```python
    async def update_processed_data(self):
        """Called every tick - always fetch fresh pool price for accurate position creation."""
        try:
            connector = self.market_data_provider.get_connector_with_fallback(
                self.config.connector_name
            )
            if hasattr(connector, 'get_pool_info_by_address'):
                pool_info = await connector.get_pool_info_by_address(self.config.pool_address)
                if pool_info and pool_info.price:
                    self._pool_price = Decimal(str(pool_info.price))
        except Exception as e:
            self.logger().warning(f"Could not fetch pool price: {e}")
```

- [ ] **Step 2: Run update_processed_data tests**

```bash
cd /home/yauhen/crypto/hummingbot-api
conda run -n hummingbot pytest test/test_lp_rebalancer_startup.py::TestUpdateProcessedDataFallback -v 2>&1 | tail -20
```

Expected: all 4 `TestUpdateProcessedDataFallback` tests PASS.

---

### Task 4: Add no-price tick counter to `determine_executor_actions`

**Files:**
- Modify: `bots/controllers/generic/lp_rebalancer/lp_rebalancer.py:193-260`

- [ ] **Step 1: Add counter guard at the top of `determine_executor_actions`**

After line `actions = []` (around line 207), before `executor = self.active_executor()`, insert:

```python
        # Guard: no pool price yet — log visibly and wait
        if self._pool_price is None:
            self._no_price_ticks += 1
            if (self._no_price_ticks - 1) % 5 == 0:
                self.logger().warning(
                    f"No pool price available after {self._no_price_ticks} tick(s) — "
                    f"skipping executor creation (connector={self.config.connector_name}, "
                    f"pool={self.config.pool_address})"
                )
            return actions
        self._no_price_ticks = 0
```

- [ ] **Step 2: Run tick counter tests**

```bash
cd /home/yauhen/crypto/hummingbot-api
conda run -n hummingbot pytest test/test_lp_rebalancer_startup.py::TestNoPriceTickCounter -v 2>&1 | tail -20
```

Expected: all 4 `TestNoPriceTickCounter` tests PASS.

---

### Task 5: Run full test suite and verify no regressions

- [ ] **Step 1: Run all startup tests**

```bash
cd /home/yauhen/crypto/hummingbot-api
conda run -n hummingbot pytest test/test_lp_rebalancer_startup.py -v 2>&1 | tail -30
```

Expected: all 13 tests PASS, 0 failures.

- [ ] **Step 2: Run existing test suite**

```bash
cd /home/yauhen/crypto/hummingbot-api
conda run -n hummingbot pytest test/ -v 2>&1 | tail -30
```

Expected: all previously passing tests still PASS.

---

### Task 6: Sync controller to running bot and commit

- [ ] **Step 1: Verify the running bot container mounts the file**

```bash
docker inspect my-bot-1-20260405-180143 \
  --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' \
  | grep controllers
```

Expected output includes:
```
/home/yauhen/crypto/hummingbot-api/bots/controllers -> /home/hummingbot/controllers
```

The file is already live-mounted — no container restart needed for the code change.

- [ ] **Step 2: Restart the strategy inside the running container to pick up the new code**

```bash
curl -s -X POST http://localhost:8000/bot-orchestration/stop-bot \
  -u admin:change_me_api_password \
  -H "Content-Type: application/json" \
  -d '{"bot_name":"my-bot-1-20260405-180143"}' && sleep 5 && \
curl -s -X POST http://localhost:8000/bot-orchestration/start-bot \
  -u admin:change_me_api_password \
  -H "Content-Type: application/json" \
  -d '{"bot_name":"my-bot-1-20260405-180143","script":"v2_with_controllers","conf":"sol_pump_lp"}'
```

- [ ] **Step 3: Watch logs for on_start output**

```bash
docker logs my-bot-1-20260405-180143 --follow 2>&1 | grep -E "on_start|pool price|Adopting|Tracking|No pool"
```

Expected within 30 seconds:
```
on_start: pool price ready (47XXX) on attempt 1
Adopting existing position <address> ...
Tracking executor: <id>
```

- [ ] **Step 4: Commit**

```bash
cd /home/yauhen/crypto/hummingbot-api
git add bots/controllers/generic/lp_rebalancer/lp_rebalancer.py \
        test/test_lp_rebalancer_startup.py \
        docs/superpowers/plans/2026-04-06-lp-rebalancer-startup-recovery.md
git commit -m "$(cat <<'EOF'
fix(lp_rebalancer): adopt existing positions on restart, handle Gateway latency

- Add on_start() retry loop (up to 120s) to warm up pool price before
  first tick — handles Helius API slow starts and rate limits
- Fix update_processed_data to use get_connector_with_fallback instead of
  get_connector (no silent ValueError when connector unregistered)
- Escalate pool price failure log from debug to warning for visibility
- Add _no_price_ticks counter: warns every 5 ticks when price unavailable

The existing _adopt_existing_position_if_any() in lp_executor is unchanged
and now reliably runs once an executor is created on first tick.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** all three design changes covered (on_start, update_processed_data, counter)
- [x] **No placeholders:** all code is complete and runnable
- [x] **Type consistency:** `_no_price_ticks: int`, `_pool_price: Optional[Decimal]` — consistent across all tasks
- [x] **lp_executor not touched:** adoption logic there is unchanged
- [x] **asyncio import added:** required for `asyncio.sleep()` in `on_start()`
- [x] **Test helper `_make_controller` bypasses `__init__`** with `__new__` — avoids needing full hummingbot connector setup
