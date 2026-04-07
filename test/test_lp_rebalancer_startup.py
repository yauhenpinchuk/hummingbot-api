"""
Unit tests for lp_rebalancer startup recovery:
1. on_start() warms up _pool_price with retry
2. update_processed_data uses get_connector_with_fallback (no ValueError)
3. determine_executor_actions warns visibly when _pool_price is missing
"""
import asyncio
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch

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
        ctrl, call_count = _make_controller([None, None, Decimal("48000")])
        sleep_calls = []
        async def fake_sleep(n):
            sleep_calls.append(n)
        with patch("asyncio.sleep", side_effect=fake_sleep):
            await ctrl.on_start()
        assert ctrl._pool_price == Decimal("48000")
        assert call_count[0] == 3
        assert len(sleep_calls) == 2

    @pytest.mark.asyncio
    async def test_on_start_gives_up_after_timeout(self):
        ctrl, call_count = _make_controller([None] * 20)
        with patch("asyncio.sleep", new_callable=AsyncMock):
            await ctrl.on_start()
        assert ctrl._pool_price is None
        assert call_count[0] == 12  # max_wait=120, interval=10 → 12 attempts

    @pytest.mark.asyncio
    async def test_on_start_logs_warning_on_each_retry(self):
        ctrl, _ = _make_controller([None, Decimal("47000")])
        log_calls = []
        mock_logger = MagicMock()
        mock_logger.warning.side_effect = lambda msg: log_calls.append(("warning", msg))
        mock_logger.info.side_effect = lambda msg: log_calls.append(("info", msg))
        mock_logger.error.side_effect = lambda msg: log_calls.append(("error", msg))
        ctrl.logger = lambda: mock_logger
        with patch("asyncio.sleep", new_callable=AsyncMock):
            await ctrl.on_start()
        warnings = [msg for level, msg in log_calls if level == "warning"]
        assert len(warnings) == 1


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
        ctrl.executors_info = []
        ctrl._initial_base_balance = Decimal("1")
        ctrl._initial_quote_balance = Decimal("1000")
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
        # ticks 1 and 6 trigger warnings (when (N-1) % 5 == 0)
        assert len(warning_calls) == 2
