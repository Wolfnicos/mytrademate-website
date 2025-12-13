#!/usr/bin/env python3
"""
PRO Model Training Script v2025
================================
- 150 features (76 original + 74 advanced)
- LSTM + Attention architecture
- 5 years of data
- 500 epochs with early stopping
- iOS TFLite compatible

Usage:
    python train_v2025_pro.py --coin BTC --timeframe 4h
    python train_v2025_pro.py --coin ETH --timeframe 1d
"""

import os
import json
import argparse
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Dict, Tuple, List
import ccxt
import time

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras.layers import (
    Input, Dense, Dropout, GlobalAveragePooling1D, BatchNormalization,
    Conv1D, MaxPooling1D, Flatten, Concatenate
)
from tensorflow.keras.models import Model
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau, ModelCheckpoint
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight

print(f"TensorFlow version: {tf.__version__}")

# =============================================================================
# ADVANCED FEATURE BUILDER - 150 features
# =============================================================================

class AdvancedFeatureBuilder:
    """Generates 150 features for PRO models."""

    PATTERN_NAMES = [
        'doji', 'dragonfly_doji', 'gravestone_doji', 'long_legged_doji',
        'hammer', 'inverted_hammer', 'shooting_star', 'hanging_man',
        'spinning_top', 'marubozu_bullish', 'marubozu_bearish',
        'bullish_engulfing', 'bearish_engulfing', 'piercing_line',
        'dark_cloud_cover', 'bullish_harami', 'bearish_harami',
        'tweezer_bottom', 'tweezer_top', 'morning_star', 'evening_star',
        'three_white_soldiers', 'three_black_crows', 'rising_three', 'falling_three'
    ]

    def __init__(self):
        self.n_features = 150
        self.seq_length = 60

    def build_features(self, df: pd.DataFrame) -> np.ndarray:
        """Build 150 features from OHLCV DataFrame."""
        n = len(df)
        features = np.zeros((n, 150), dtype=np.float32)

        o = df['open'].values.astype(np.float64)
        h = df['high'].values.astype(np.float64)
        l = df['low'].values.astype(np.float64)
        c = df['close'].values.astype(np.float64)
        v = df['volume'].values.astype(np.float64)

        # =====================================================================
        # ORIGINAL 76 FEATURES [0-75]
        # =====================================================================

        # [0-24] Candlestick Patterns
        patterns = self._detect_patterns(o, h, l, c)
        for i, name in enumerate(self.PATTERN_NAMES):
            features[:, i] = patterns[name]

        # [25-29] Price Action
        features[:, 25] = self._returns(c)
        features[:, 26] = self._log_returns(c)
        features[:, 27] = self._volatility(self._returns(c), 20)
        features[:, 28] = (h - l) / (c + 1e-10)
        features[:, 29] = (c - l) / (h - l + 1e-10)

        # [30-32] RSI
        rsi = self._rsi(c, 14)
        features[:, 30] = rsi / 100.0
        features[:, 31] = (rsi < 30).astype(np.float32)
        features[:, 32] = (rsi > 70).astype(np.float32)

        # [33-37] MACD
        macd, signal, hist = self._macd(c)
        features[:, 33] = macd / (c + 1e-10)
        features[:, 34] = signal / (c + 1e-10)
        features[:, 35] = hist / (c + 1e-10)
        features[:, 36] = self._cross_above(macd, signal)
        features[:, 37] = self._cross_below(macd, signal)

        # [38-43] Bollinger Bands
        bb_upper, bb_mid, bb_lower = self._bollinger(c, 20, 2.0)
        features[:, 38] = (bb_upper - c) / (c + 1e-10)
        features[:, 39] = 0.0
        features[:, 40] = (c - bb_lower) / (c + 1e-10)
        bb_width = (bb_upper - bb_lower) / (bb_mid + 1e-10)
        features[:, 41] = bb_width
        features[:, 42] = (c - bb_lower) / (bb_upper - bb_lower + 1e-10)
        features[:, 43] = (bb_width < 0.04).astype(np.float32)

        # [44-45] ATR
        atr = self._atr(h, l, c, 14)
        features[:, 44] = atr / (c + 1e-10)
        features[:, 45] = atr / (c + 1e-10)

        # [46-47] ADX
        adx = self._adx(h, l, c, 14)
        features[:, 46] = adx / 100.0
        features[:, 47] = (adx > 25).astype(np.float32)

        # [48-51] Stochastic
        stoch_k, stoch_d = self._stochastic(h, l, c, 14)
        features[:, 48] = stoch_k / 100.0
        features[:, 49] = stoch_d / 100.0
        features[:, 50] = (stoch_k < 20).astype(np.float32)
        features[:, 51] = (stoch_k > 80).astype(np.float32)

        # [52-58] Ichimoku
        tenkan, kijun, senkou_a, senkou_b = self._ichimoku(h, l, c)
        features[:, 52] = (tenkan - c) / (c + 1e-10)
        features[:, 53] = (kijun - c) / (c + 1e-10)
        features[:, 54] = (senkou_a - c) / (c + 1e-10)
        features[:, 55] = (senkou_b - c) / (c + 1e-10)
        features[:, 56] = (senkou_a > senkou_b).astype(np.float32)
        features[:, 57] = ((c > senkou_a) & (c > senkou_b)).astype(np.float32)
        features[:, 58] = ((c < senkou_a) & (c < senkou_b)).astype(np.float32)

        # [59-63] Volume
        vol_sma = self._sma(v, 20)
        obv = self._obv(c, v)
        features[:, 59] = v / (vol_sma + 1e-10)
        features[:, 60] = 1.0
        features[:, 61] = v / (vol_sma + 1e-10)
        features[:, 62] = self._normalize_obv(obv)
        features[:, 63] = (v > vol_sma * 1.5).astype(np.float32)

        # [64-72] Moving Averages
        sma10 = self._sma(c, 10)
        sma20 = self._sma(c, 20)
        sma50 = self._sma(c, 50)
        sma100 = self._sma(c, 100)
        sma200 = self._sma(c, 200)
        ema12 = self._ema(c, 12)
        ema26 = self._ema(c, 26)

        features[:, 64] = (c - sma10) / (sma10 + 1e-10)
        features[:, 65] = (c - sma20) / (sma20 + 1e-10)
        features[:, 66] = (c - sma50) / (sma50 + 1e-10)
        features[:, 67] = (c - sma100) / (sma100 + 1e-10)
        features[:, 68] = (c - sma200) / (sma200 + 1e-10)
        features[:, 69] = (c - ema12) / (ema12 + 1e-10)
        features[:, 70] = (c - ema26) / (ema26 + 1e-10)
        features[:, 71] = (sma10 > sma20).astype(np.float32)
        features[:, 72] = (sma50 > sma200).astype(np.float32)

        # [73-75] Trend
        features[:, 73] = self._trend_strength(c, 20)
        features[:, 74] = self._momentum(c, 10)
        features[:, 75] = self._momentum(c, 20)

        # =====================================================================
        # NEW ADVANCED FEATURES [76-149]
        # =====================================================================

        # [76-81] Fibonacci Retracements
        fib_levels = self._fibonacci_retracements(h, l, c, 50)
        features[:, 76] = fib_levels['fib_236']
        features[:, 77] = fib_levels['fib_382']
        features[:, 78] = fib_levels['fib_500']
        features[:, 79] = fib_levels['fib_618']
        features[:, 80] = fib_levels['fib_786']
        features[:, 81] = fib_levels['near_fib_level']

        # [82-88] Pivot Points
        pivot, s1, s2, s3, r1, r2, r3 = self._pivot_points(h, l, c)
        features[:, 82] = (c - pivot) / (c + 1e-10)
        features[:, 83] = (c - s1) / (c + 1e-10)
        features[:, 84] = (c - s2) / (c + 1e-10)
        features[:, 85] = (c - s3) / (c + 1e-10)
        features[:, 86] = (c - r1) / (c + 1e-10)
        features[:, 87] = (c - r2) / (c + 1e-10)
        features[:, 88] = (c - r3) / (c + 1e-10)

        # [89-92] VWAP
        vwap = self._vwap(h, l, c, v)
        vwap_std = self._vwap_bands(h, l, c, v)
        features[:, 89] = (c - vwap) / (c + 1e-10)
        features[:, 90] = vwap_std['upper_band']
        features[:, 91] = vwap_std['lower_band']
        features[:, 92] = ((c > vwap) & (c < vwap_std['upper_raw'])).astype(np.float32)

        # [93-95] SuperTrend
        supertrend, direction = self._supertrend(h, l, c, 10, 3.0)
        features[:, 93] = (c - supertrend) / (c + 1e-10)
        features[:, 94] = direction
        features[:, 95] = self._supertrend_flip(direction)

        # [96-99] Keltner Channels
        kc_upper, kc_mid, kc_lower = self._keltner_channels(h, l, c, 20, 2.0)
        features[:, 96] = (c - kc_upper) / (c + 1e-10)
        features[:, 97] = (c - kc_mid) / (c + 1e-10)
        features[:, 98] = (c - kc_lower) / (c + 1e-10)
        features[:, 99] = ((c > kc_upper) | (c < kc_lower)).astype(np.float32)

        # [100-103] Donchian Channels
        dc_upper, dc_mid, dc_lower = self._donchian_channels(h, l, 20)
        features[:, 100] = (c - dc_upper) / (c + 1e-10)
        features[:, 101] = (c - dc_mid) / (c + 1e-10)
        features[:, 102] = (c - dc_lower) / (c + 1e-10)
        features[:, 103] = (dc_upper - dc_lower) / (c + 1e-10)

        # [104-106] Chaikin Money Flow
        cmf = self._chaikin_money_flow(h, l, c, v, 20)
        features[:, 104] = cmf
        features[:, 105] = (cmf > 0.05).astype(np.float32)
        features[:, 106] = (cmf < -0.05).astype(np.float32)

        # [107-109] Williams %R
        williams_r = self._williams_r(h, l, c, 14)
        features[:, 107] = williams_r / 100.0
        features[:, 108] = (williams_r < -80).astype(np.float32)
        features[:, 109] = (williams_r > -20).astype(np.float32)

        # [110-112] CCI
        cci = self._cci(h, l, c, 20)
        features[:, 110] = cci / 200.0
        features[:, 111] = (cci < -100).astype(np.float32)
        features[:, 112] = (cci > 100).astype(np.float32)

        # [113-115] MFI
        mfi = self._mfi(h, l, c, v, 14)
        features[:, 113] = mfi / 100.0
        features[:, 114] = (mfi < 20).astype(np.float32)
        features[:, 115] = (mfi > 80).astype(np.float32)

        # [116-119] ROC (Rate of Change)
        features[:, 116] = self._roc(c, 5)
        features[:, 117] = self._roc(c, 10)
        features[:, 118] = self._roc(c, 20)
        features[:, 119] = self._roc(c, 50)

        # [120-121] TRIX
        trix = self._trix(c, 15)
        features[:, 120] = trix
        features[:, 121] = self._trix_signal(trix, 9)

        # [122-124] Ultimate Oscillator
        uo = self._ultimate_oscillator(h, l, c, 7, 14, 28)
        features[:, 122] = uo / 100.0
        features[:, 123] = (uo < 30).astype(np.float32)
        features[:, 124] = (uo > 70).astype(np.float32)

        # [125-126] Parabolic SAR
        psar, psar_direction = self._parabolic_sar(h, l, c)
        features[:, 125] = (c - psar) / (c + 1e-10)
        features[:, 126] = psar_direction

        # [127-129] Elder Ray
        bull_power, bear_power = self._elder_ray(h, l, c, 13)
        features[:, 127] = bull_power / (c + 1e-10)
        features[:, 128] = bear_power / (c + 1e-10)
        features[:, 129] = ((bull_power > 0) & (bear_power > bear_power)).astype(np.float32)

        # [130-132] Aroon
        aroon_up, aroon_down = self._aroon(h, l, 25)
        features[:, 130] = aroon_up / 100.0
        features[:, 131] = aroon_down / 100.0
        features[:, 132] = (aroon_up - aroon_down) / 100.0

        # [133-134] Chande Momentum
        cmo = self._chande_momentum(c, 14)
        features[:, 133] = cmo / 100.0
        features[:, 134] = np.abs(cmo) / 100.0

        # [135-136] DPO (Detrended Price Oscillator)
        dpo = self._dpo(c, 20)
        features[:, 135] = dpo / (c + 1e-10)
        features[:, 136] = (dpo > 0).astype(np.float32)

        # [137-138] KAMA
        kama = self._kama(c, 10, 2, 30)
        features[:, 137] = (c - kama) / (c + 1e-10)
        features[:, 138] = self._cross_above(c, kama)

        # [139-140] Hull MA
        hma = self._hull_ma(c, 20)
        features[:, 139] = (c - hma) / (c + 1e-10)
        features[:, 140] = self._hma_direction(hma)

        # [141-143] Market Regime
        features[:, 141] = self._market_regime(c, atr, 20)
        features[:, 142] = self._volatility_regime(c, 20)
        features[:, 143] = self._trend_regime(c, sma50, sma200)

        # [144-146] Multi-timeframe Momentum
        features[:, 144] = self._momentum(c, 5)
        features[:, 145] = self._momentum(c, 14)
        features[:, 146] = self._momentum(c, 30)

        # [147-149] Volume Analysis
        features[:, 147] = self._volume_trend(v, 20)
        features[:, 148] = self._price_volume_trend(c, v)
        features[:, 149] = self._accumulation_distribution(h, l, c, v)

        # Replace NaN/Inf
        features = np.nan_to_num(features, nan=0.0, posinf=1.0, neginf=-1.0)

        return features

    # =========================================================================
    # ORIGINAL INDICATOR METHODS
    # =========================================================================

    def _detect_patterns(self, o, h, l, c) -> Dict[str, np.ndarray]:
        """Detect candlestick patterns."""
        n = len(c)
        patterns = {name: np.zeros(n, dtype=np.float32) for name in self.PATTERN_NAMES}

        body = c - o
        body_abs = np.abs(body)
        upper_shadow = h - np.maximum(o, c)
        lower_shadow = np.minimum(o, c) - l
        total_range = h - l + 1e-10

        # Doji patterns
        patterns['doji'] = (body_abs / total_range < 0.1).astype(np.float32)
        patterns['dragonfly_doji'] = ((body_abs / total_range < 0.1) &
                                       (lower_shadow > 2 * body_abs) &
                                       (upper_shadow < body_abs)).astype(np.float32)
        patterns['gravestone_doji'] = ((body_abs / total_range < 0.1) &
                                        (upper_shadow > 2 * body_abs) &
                                        (lower_shadow < body_abs)).astype(np.float32)
        patterns['long_legged_doji'] = ((body_abs / total_range < 0.1) &
                                         (upper_shadow > body_abs) &
                                         (lower_shadow > body_abs)).astype(np.float32)

        # Hammer patterns
        patterns['hammer'] = ((body > 0) &
                              (lower_shadow > 2 * body_abs) &
                              (upper_shadow < 0.3 * body_abs)).astype(np.float32)
        patterns['inverted_hammer'] = ((body > 0) &
                                        (upper_shadow > 2 * body_abs) &
                                        (lower_shadow < 0.3 * body_abs)).astype(np.float32)
        patterns['shooting_star'] = ((body < 0) &
                                      (upper_shadow > 2 * body_abs) &
                                      (lower_shadow < 0.3 * body_abs)).astype(np.float32)
        patterns['hanging_man'] = ((body < 0) &
                                    (lower_shadow > 2 * body_abs) &
                                    (upper_shadow < 0.3 * body_abs)).astype(np.float32)

        # Other patterns
        patterns['spinning_top'] = ((body_abs / total_range < 0.3) &
                                     (upper_shadow > body_abs) &
                                     (lower_shadow > body_abs)).astype(np.float32)
        patterns['marubozu_bullish'] = ((body > 0) &
                                         (body_abs / total_range > 0.9)).astype(np.float32)
        patterns['marubozu_bearish'] = ((body < 0) &
                                         (body_abs / total_range > 0.9)).astype(np.float32)

        # Multi-candle patterns
        for i in range(1, n):
            prev_body = c[i-1] - o[i-1]
            curr_body = body[i]

            # Engulfing
            if prev_body < 0 and curr_body > 0 and o[i] < c[i-1] and c[i] > o[i-1]:
                patterns['bullish_engulfing'][i] = 1.0
            if prev_body > 0 and curr_body < 0 and o[i] > c[i-1] and c[i] < o[i-1]:
                patterns['bearish_engulfing'][i] = 1.0

            # Harami
            if prev_body < 0 and curr_body > 0 and o[i] > c[i-1] and c[i] < o[i-1]:
                patterns['bullish_harami'][i] = 1.0
            if prev_body > 0 and curr_body < 0 and o[i] < c[i-1] and c[i] > o[i-1]:
                patterns['bearish_harami'][i] = 1.0

        return patterns

    def _returns(self, c: np.ndarray) -> np.ndarray:
        ret = np.zeros_like(c)
        ret[1:] = (c[1:] - c[:-1]) / (c[:-1] + 1e-10)
        return ret

    def _log_returns(self, c: np.ndarray) -> np.ndarray:
        ret = np.zeros_like(c)
        ret[1:] = np.log(c[1:] / (c[:-1] + 1e-10))
        return ret

    def _volatility(self, returns: np.ndarray, period: int) -> np.ndarray:
        vol = np.zeros_like(returns)
        for i in range(period, len(returns)):
            vol[i] = np.std(returns[i-period:i])
        return vol

    def _sma(self, data: np.ndarray, period: int) -> np.ndarray:
        sma = np.zeros_like(data)
        for i in range(period - 1, len(data)):
            sma[i] = np.mean(data[i-period+1:i+1])
        sma[:period-1] = sma[period-1]
        return sma

    def _ema(self, data: np.ndarray, period: int) -> np.ndarray:
        ema = np.zeros_like(data)
        multiplier = 2.0 / (period + 1)
        ema[0] = data[0]
        for i in range(1, len(data)):
            ema[i] = (data[i] - ema[i-1]) * multiplier + ema[i-1]
        return ema

    def _rsi(self, c: np.ndarray, period: int = 14) -> np.ndarray:
        delta = np.diff(c, prepend=c[0])
        gain = np.where(delta > 0, delta, 0)
        loss = np.where(delta < 0, -delta, 0)

        avg_gain = self._ema(gain, period)
        avg_loss = self._ema(loss, period)

        rs = avg_gain / (avg_loss + 1e-10)
        rsi = 100 - (100 / (1 + rs))
        return rsi

    def _macd(self, c: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        ema12 = self._ema(c, 12)
        ema26 = self._ema(c, 26)
        macd = ema12 - ema26
        signal = self._ema(macd, 9)
        hist = macd - signal
        return macd, signal, hist

    def _bollinger(self, c: np.ndarray, period: int, std_dev: float) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        mid = self._sma(c, period)
        std = np.zeros_like(c)
        for i in range(period - 1, len(c)):
            std[i] = np.std(c[i-period+1:i+1])
        upper = mid + std_dev * std
        lower = mid - std_dev * std
        return upper, mid, lower

    def _atr(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> np.ndarray:
        tr = np.zeros_like(c)
        tr[0] = h[0] - l[0]
        for i in range(1, len(c)):
            tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
        return self._ema(tr, period)

    def _adx(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> np.ndarray:
        plus_dm = np.zeros_like(c)
        minus_dm = np.zeros_like(c)

        for i in range(1, len(c)):
            up = h[i] - h[i-1]
            down = l[i-1] - l[i]
            plus_dm[i] = up if up > down and up > 0 else 0
            minus_dm[i] = down if down > up and down > 0 else 0

        atr = self._atr(h, l, c, period)
        plus_di = 100 * self._ema(plus_dm, period) / (atr + 1e-10)
        minus_di = 100 * self._ema(minus_dm, period) / (atr + 1e-10)

        dx = 100 * np.abs(plus_di - minus_di) / (plus_di + minus_di + 1e-10)
        adx = self._ema(dx, period)
        return adx

    def _stochastic(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> Tuple[np.ndarray, np.ndarray]:
        k = np.zeros_like(c)
        for i in range(period - 1, len(c)):
            lowest = np.min(l[i-period+1:i+1])
            highest = np.max(h[i-period+1:i+1])
            k[i] = 100 * (c[i] - lowest) / (highest - lowest + 1e-10)
        d = self._sma(k, 3)
        return k, d

    def _ichimoku(self, h: np.ndarray, l: np.ndarray, c: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        def donchian_mid(high, low, period):
            mid = np.zeros_like(high)
            for i in range(period - 1, len(high)):
                mid[i] = (np.max(high[i-period+1:i+1]) + np.min(low[i-period+1:i+1])) / 2
            return mid

        tenkan = donchian_mid(h, l, 9)
        kijun = donchian_mid(h, l, 26)
        senkou_a = (tenkan + kijun) / 2
        senkou_b = donchian_mid(h, l, 52)
        return tenkan, kijun, senkou_a, senkou_b

    def _obv(self, c: np.ndarray, v: np.ndarray) -> np.ndarray:
        obv = np.zeros_like(c)
        for i in range(1, len(c)):
            if c[i] > c[i-1]:
                obv[i] = obv[i-1] + v[i]
            elif c[i] < c[i-1]:
                obv[i] = obv[i-1] - v[i]
            else:
                obv[i] = obv[i-1]
        return obv

    def _normalize_obv(self, obv: np.ndarray) -> np.ndarray:
        obv_min = np.min(obv)
        obv_max = np.max(obv)
        if obv_max - obv_min > 0:
            return (obv - obv_min) / (obv_max - obv_min)
        return np.zeros_like(obv)

    def _cross_above(self, a: np.ndarray, b: np.ndarray) -> np.ndarray:
        cross = np.zeros_like(a)
        for i in range(1, len(a)):
            if a[i] > b[i] and a[i-1] <= b[i-1]:
                cross[i] = 1.0
        return cross

    def _cross_below(self, a: np.ndarray, b: np.ndarray) -> np.ndarray:
        cross = np.zeros_like(a)
        for i in range(1, len(a)):
            if a[i] < b[i] and a[i-1] >= b[i-1]:
                cross[i] = 1.0
        return cross

    def _trend_strength(self, c: np.ndarray, period: int) -> np.ndarray:
        strength = np.zeros_like(c)
        for i in range(period, len(c)):
            up_moves = sum(1 for j in range(i-period, i) if c[j+1] > c[j])
            strength[i] = (up_moves / period - 0.5) * 2
        return strength

    def _momentum(self, c: np.ndarray, period: int) -> np.ndarray:
        mom = np.zeros_like(c)
        mom[period:] = (c[period:] - c[:-period]) / (c[:-period] + 1e-10)
        return mom

    # =========================================================================
    # NEW ADVANCED INDICATOR METHODS
    # =========================================================================

    def _fibonacci_retracements(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> Dict[str, np.ndarray]:
        n = len(c)
        fib = {
            'fib_236': np.zeros(n, dtype=np.float32),
            'fib_382': np.zeros(n, dtype=np.float32),
            'fib_500': np.zeros(n, dtype=np.float32),
            'fib_618': np.zeros(n, dtype=np.float32),
            'fib_786': np.zeros(n, dtype=np.float32),
            'near_fib_level': np.zeros(n, dtype=np.float32)
        }

        for i in range(period, n):
            high = np.max(h[i-period:i])
            low = np.min(l[i-period:i])
            diff = high - low

            fib_236 = high - diff * 0.236
            fib_382 = high - diff * 0.382
            fib_500 = high - diff * 0.500
            fib_618 = high - diff * 0.618
            fib_786 = high - diff * 0.786

            fib['fib_236'][i] = (c[i] - fib_236) / (c[i] + 1e-10)
            fib['fib_382'][i] = (c[i] - fib_382) / (c[i] + 1e-10)
            fib['fib_500'][i] = (c[i] - fib_500) / (c[i] + 1e-10)
            fib['fib_618'][i] = (c[i] - fib_618) / (c[i] + 1e-10)
            fib['fib_786'][i] = (c[i] - fib_786) / (c[i] + 1e-10)

            # Check if near any fib level (within 1%)
            levels = [fib_236, fib_382, fib_500, fib_618, fib_786]
            for level in levels:
                if abs(c[i] - level) / (c[i] + 1e-10) < 0.01:
                    fib['near_fib_level'][i] = 1.0
                    break

        return fib

    def _pivot_points(self, h: np.ndarray, l: np.ndarray, c: np.ndarray) -> Tuple:
        pivot = (h + l + c) / 3
        s1 = 2 * pivot - h
        s2 = pivot - (h - l)
        s3 = l - 2 * (h - pivot)
        r1 = 2 * pivot - l
        r2 = pivot + (h - l)
        r3 = h + 2 * (pivot - l)
        return pivot, s1, s2, s3, r1, r2, r3

    def _vwap(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, v: np.ndarray) -> np.ndarray:
        typical_price = (h + l + c) / 3
        cumulative_tpv = np.cumsum(typical_price * v)
        cumulative_vol = np.cumsum(v)
        vwap = cumulative_tpv / (cumulative_vol + 1e-10)
        return vwap

    def _vwap_bands(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, v: np.ndarray) -> Dict[str, np.ndarray]:
        vwap = self._vwap(h, l, c, v)
        typical_price = (h + l + c) / 3

        # Calculate rolling std
        std = np.zeros_like(c)
        for i in range(20, len(c)):
            std[i] = np.std(typical_price[i-20:i])

        upper = vwap + 2 * std
        lower = vwap - 2 * std

        return {
            'upper_band': (upper - c) / (c + 1e-10),
            'lower_band': (c - lower) / (c + 1e-10),
            'upper_raw': upper,
            'lower_raw': lower
        }

    def _supertrend(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int, multiplier: float) -> Tuple[np.ndarray, np.ndarray]:
        atr = self._atr(h, l, c, period)
        hl2 = (h + l) / 2

        upper_band = hl2 + multiplier * atr
        lower_band = hl2 - multiplier * atr

        supertrend = np.zeros_like(c)
        direction = np.ones_like(c)  # 1 = uptrend, -1 = downtrend

        for i in range(1, len(c)):
            if c[i] > upper_band[i-1]:
                direction[i] = 1
            elif c[i] < lower_band[i-1]:
                direction[i] = -1
            else:
                direction[i] = direction[i-1]

            if direction[i] == 1:
                supertrend[i] = lower_band[i]
            else:
                supertrend[i] = upper_band[i]

        return supertrend, direction

    def _supertrend_flip(self, direction: np.ndarray) -> np.ndarray:
        flip = np.zeros_like(direction)
        for i in range(1, len(direction)):
            if direction[i] != direction[i-1]:
                flip[i] = 1.0
        return flip

    def _keltner_channels(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int, multiplier: float) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        mid = self._ema(c, period)
        atr = self._atr(h, l, c, period)
        upper = mid + multiplier * atr
        lower = mid - multiplier * atr
        return upper, mid, lower

    def _donchian_channels(self, h: np.ndarray, l: np.ndarray, period: int) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        upper = np.zeros_like(h)
        lower = np.zeros_like(l)

        for i in range(period - 1, len(h)):
            upper[i] = np.max(h[i-period+1:i+1])
            lower[i] = np.min(l[i-period+1:i+1])

        mid = (upper + lower) / 2
        return upper, mid, lower

    def _chaikin_money_flow(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, v: np.ndarray, period: int) -> np.ndarray:
        mfm = ((c - l) - (h - c)) / (h - l + 1e-10)
        mfv = mfm * v

        cmf = np.zeros_like(c)
        for i in range(period - 1, len(c)):
            cmf[i] = np.sum(mfv[i-period+1:i+1]) / (np.sum(v[i-period+1:i+1]) + 1e-10)

        return cmf

    def _williams_r(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> np.ndarray:
        wr = np.zeros_like(c)
        for i in range(period - 1, len(c)):
            highest = np.max(h[i-period+1:i+1])
            lowest = np.min(l[i-period+1:i+1])
            wr[i] = -100 * (highest - c[i]) / (highest - lowest + 1e-10)
        return wr

    def _cci(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> np.ndarray:
        tp = (h + l + c) / 3
        sma_tp = self._sma(tp, period)

        mad = np.zeros_like(c)
        for i in range(period - 1, len(c)):
            mad[i] = np.mean(np.abs(tp[i-period+1:i+1] - sma_tp[i]))

        cci = (tp - sma_tp) / (0.015 * mad + 1e-10)
        return cci

    def _mfi(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, v: np.ndarray, period: int) -> np.ndarray:
        tp = (h + l + c) / 3
        mf = tp * v

        pos_mf = np.zeros_like(c)
        neg_mf = np.zeros_like(c)

        for i in range(1, len(c)):
            if tp[i] > tp[i-1]:
                pos_mf[i] = mf[i]
            elif tp[i] < tp[i-1]:
                neg_mf[i] = mf[i]

        mfi = np.zeros_like(c)
        for i in range(period - 1, len(c)):
            pos_sum = np.sum(pos_mf[i-period+1:i+1])
            neg_sum = np.sum(neg_mf[i-period+1:i+1])
            mfi[i] = 100 * pos_sum / (pos_sum + neg_sum + 1e-10)

        return mfi

    def _roc(self, c: np.ndarray, period: int) -> np.ndarray:
        roc = np.zeros_like(c)
        roc[period:] = (c[period:] - c[:-period]) / (c[:-period] + 1e-10) * 100
        return roc / 100  # Normalize

    def _trix(self, c: np.ndarray, period: int) -> np.ndarray:
        ema1 = self._ema(c, period)
        ema2 = self._ema(ema1, period)
        ema3 = self._ema(ema2, period)

        trix = np.zeros_like(c)
        trix[1:] = (ema3[1:] - ema3[:-1]) / (ema3[:-1] + 1e-10) * 100
        return trix

    def _trix_signal(self, trix: np.ndarray, period: int) -> np.ndarray:
        return self._sma(trix, period)

    def _ultimate_oscillator(self, h: np.ndarray, l: np.ndarray, c: np.ndarray,
                              period1: int, period2: int, period3: int) -> np.ndarray:
        bp = c - np.minimum(l, np.roll(c, 1))
        bp[0] = 0

        tr = np.maximum(h, np.roll(c, 1)) - np.minimum(l, np.roll(c, 1))
        tr[0] = h[0] - l[0]

        avg1 = self._sma(bp, period1) / (self._sma(tr, period1) + 1e-10)
        avg2 = self._sma(bp, period2) / (self._sma(tr, period2) + 1e-10)
        avg3 = self._sma(bp, period3) / (self._sma(tr, period3) + 1e-10)

        uo = 100 * (4 * avg1 + 2 * avg2 + avg3) / 7
        return uo

    def _parabolic_sar(self, h: np.ndarray, l: np.ndarray, c: np.ndarray,
                        af_start: float = 0.02, af_max: float = 0.2) -> Tuple[np.ndarray, np.ndarray]:
        n = len(c)
        psar = np.zeros(n)
        direction = np.ones(n)  # 1 = long, -1 = short

        psar[0] = l[0]
        ep = h[0]
        af = af_start

        for i in range(1, n):
            if direction[i-1] == 1:  # Long
                psar[i] = psar[i-1] + af * (ep - psar[i-1])
                psar[i] = min(psar[i], l[i-1], l[i-2] if i > 1 else l[i-1])

                if l[i] < psar[i]:
                    direction[i] = -1
                    psar[i] = ep
                    ep = l[i]
                    af = af_start
                else:
                    direction[i] = 1
                    if h[i] > ep:
                        ep = h[i]
                        af = min(af + af_start, af_max)
            else:  # Short
                psar[i] = psar[i-1] - af * (psar[i-1] - ep)
                psar[i] = max(psar[i], h[i-1], h[i-2] if i > 1 else h[i-1])

                if h[i] > psar[i]:
                    direction[i] = 1
                    psar[i] = ep
                    ep = h[i]
                    af = af_start
                else:
                    direction[i] = -1
                    if l[i] < ep:
                        ep = l[i]
                        af = min(af + af_start, af_max)

        return psar, direction

    def _elder_ray(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, period: int) -> Tuple[np.ndarray, np.ndarray]:
        ema = self._ema(c, period)
        bull_power = h - ema
        bear_power = l - ema
        return bull_power, bear_power

    def _aroon(self, h: np.ndarray, l: np.ndarray, period: int) -> Tuple[np.ndarray, np.ndarray]:
        aroon_up = np.zeros_like(h)
        aroon_down = np.zeros_like(l)

        for i in range(period, len(h)):
            high_idx = np.argmax(h[i-period:i+1])
            low_idx = np.argmin(l[i-period:i+1])
            aroon_up[i] = 100 * (period - (period - high_idx)) / period
            aroon_down[i] = 100 * (period - (period - low_idx)) / period

        return aroon_up, aroon_down

    def _chande_momentum(self, c: np.ndarray, period: int) -> np.ndarray:
        delta = np.diff(c, prepend=c[0])
        gains = np.where(delta > 0, delta, 0)
        losses = np.where(delta < 0, -delta, 0)

        sum_gains = np.zeros_like(c)
        sum_losses = np.zeros_like(c)

        for i in range(period, len(c)):
            sum_gains[i] = np.sum(gains[i-period+1:i+1])
            sum_losses[i] = np.sum(losses[i-period+1:i+1])

        cmo = 100 * (sum_gains - sum_losses) / (sum_gains + sum_losses + 1e-10)
        return cmo

    def _dpo(self, c: np.ndarray, period: int) -> np.ndarray:
        shift = period // 2 + 1
        sma = self._sma(c, period)
        dpo = np.zeros_like(c)
        dpo[shift:] = c[shift:] - sma[:-shift]
        return dpo

    def _kama(self, c: np.ndarray, period: int, fast: int, slow: int) -> np.ndarray:
        change = np.abs(c - np.roll(c, period))
        change[:period] = 0

        volatility = np.zeros_like(c)
        for i in range(period, len(c)):
            volatility[i] = np.sum(np.abs(np.diff(c[i-period:i+1])))

        er = change / (volatility + 1e-10)

        fast_sc = 2 / (fast + 1)
        slow_sc = 2 / (slow + 1)
        sc = (er * (fast_sc - slow_sc) + slow_sc) ** 2

        kama = np.zeros_like(c)
        kama[period-1] = c[period-1]

        for i in range(period, len(c)):
            kama[i] = kama[i-1] + sc[i] * (c[i] - kama[i-1])

        return kama

    def _hull_ma(self, c: np.ndarray, period: int) -> np.ndarray:
        half_period = period // 2
        sqrt_period = int(np.sqrt(period))

        wma_half = self._wma(c, half_period)
        wma_full = self._wma(c, period)

        raw_hma = 2 * wma_half - wma_full
        hma = self._wma(raw_hma, sqrt_period)

        return hma

    def _wma(self, data: np.ndarray, period: int) -> np.ndarray:
        weights = np.arange(1, period + 1)
        wma = np.zeros_like(data)

        for i in range(period - 1, len(data)):
            wma[i] = np.sum(data[i-period+1:i+1] * weights) / np.sum(weights)

        return wma

    def _hma_direction(self, hma: np.ndarray) -> np.ndarray:
        direction = np.zeros_like(hma)
        direction[1:] = np.sign(hma[1:] - hma[:-1])
        return direction

    def _market_regime(self, c: np.ndarray, atr: np.ndarray, period: int) -> np.ndarray:
        """0 = ranging, 1 = trending up, -1 = trending down"""
        regime = np.zeros_like(c)

        for i in range(period, len(c)):
            price_change = (c[i] - c[i-period]) / c[i-period]
            avg_atr = np.mean(atr[i-period:i]) / c[i]

            if abs(price_change) > 2 * avg_atr * period:
                regime[i] = 1 if price_change > 0 else -1

        return regime

    def _volatility_regime(self, c: np.ndarray, period: int) -> np.ndarray:
        """0 = low vol, 0.5 = normal, 1 = high vol"""
        returns = self._returns(c)

        regime = np.zeros_like(c)
        for i in range(period * 2, len(c)):
            current_vol = np.std(returns[i-period:i])
            historical_vol = np.std(returns[i-period*2:i-period])

            if historical_vol > 0:
                ratio = current_vol / historical_vol
                regime[i] = min(1.0, max(0.0, (ratio - 0.5) / 1.5))

        return regime

    def _trend_regime(self, c: np.ndarray, sma50: np.ndarray, sma200: np.ndarray) -> np.ndarray:
        """1 = bull market, 0 = transition, -1 = bear market"""
        regime = np.zeros_like(c)

        bull = (c > sma50) & (sma50 > sma200)
        bear = (c < sma50) & (sma50 < sma200)

        regime[bull] = 1.0
        regime[bear] = -1.0

        return regime

    def _volume_trend(self, v: np.ndarray, period: int) -> np.ndarray:
        sma_vol = self._sma(v, period)
        return (v - sma_vol) / (sma_vol + 1e-10)

    def _price_volume_trend(self, c: np.ndarray, v: np.ndarray) -> np.ndarray:
        pvt = np.zeros_like(c)
        for i in range(1, len(c)):
            pvt[i] = pvt[i-1] + v[i] * (c[i] - c[i-1]) / (c[i-1] + 1e-10)

        # Normalize
        pvt_min = np.min(pvt)
        pvt_max = np.max(pvt)
        if pvt_max - pvt_min > 0:
            return (pvt - pvt_min) / (pvt_max - pvt_min)
        return np.zeros_like(c)

    def _accumulation_distribution(self, h: np.ndarray, l: np.ndarray, c: np.ndarray, v: np.ndarray) -> np.ndarray:
        mfm = ((c - l) - (h - c)) / (h - l + 1e-10)
        ad = np.cumsum(mfm * v)

        # Normalize
        ad_min = np.min(ad)
        ad_max = np.max(ad)
        if ad_max - ad_min > 0:
            return (ad - ad_min) / (ad_max - ad_min)
        return np.zeros_like(c)


# =============================================================================
# DATA FETCHING
# =============================================================================

def fetch_data(symbol: str, timeframe: str, days: int = 1825) -> pd.DataFrame:
    """Fetch 5 years of OHLCV data from Binance."""
    print(f"\nFetching {symbol} {timeframe} from Binance ({days} days)...")

    exchange = ccxt.binance({'enableRateLimit': True})

    # Calculate timestamps
    now = datetime.now()
    since = int((now - timedelta(days=days)).timestamp() * 1000)

    all_candles = []

    while True:
        try:
            candles = exchange.fetch_ohlcv(symbol, timeframe, since=since, limit=1000)
            if not candles:
                break

            all_candles.extend(candles)
            print(f"  Fetched {len(all_candles)} candles...")

            since = candles[-1][0] + 1

            if candles[-1][0] >= int(now.timestamp() * 1000):
                break

            time.sleep(0.5)

        except Exception as e:
            print(f"  Error: {e}")
            break

    if not all_candles:
        raise ValueError(f"No data fetched for {symbol}")

    df = pd.DataFrame(all_candles, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
    df = df.drop_duplicates(subset=['timestamp']).sort_values('timestamp').reset_index(drop=True)

    print(f"  Total: {len(df)} candles")
    print(f"  Date range: {df['timestamp'].iloc[0]} to {df['timestamp'].iloc[-1]}")
    print(f"  Price range: ${df['close'].min():.2f} - ${df['close'].max():.2f}")

    return df


# =============================================================================
# LABEL GENERATION
# =============================================================================

def generate_labels(df: pd.DataFrame, timeframe: str) -> np.ndarray:
    """Generate SELL(0), HOLD(1), BUY(2) labels."""

    # Timeframe-specific thresholds
    thresholds = {
        '5m':  {'buy': 0.005, 'sell': -0.005},   # 0.5% for scalping
        '15m': {'buy': 0.008, 'sell': -0.008},   # 0.8%
        '1h':  {'buy': 0.012, 'sell': -0.012},   # 1.2%
        '4h':  {'buy': 0.015, 'sell': -0.015},   # 1.5%
        '1d':  {'buy': 0.025, 'sell': -0.025},   # 2.5%
    }

    thresh = thresholds.get(timeframe, {'buy': 0.02, 'sell': -0.02})

    # Multiple lookahead windows (candles to look ahead)
    windows = {
        '5m':  [12, 24, 48],    # 1h, 2h, 4h ahead
        '15m': [8, 16, 32],     # 2h, 4h, 8h ahead
        '1h':  [6, 12, 24],     # 6h, 12h, 24h ahead
        '4h':  [6, 12, 24],     # 1 day, 2 days, 4 days
        '1d':  [3, 7, 14],      # 3 days, 1 week, 2 weeks
    }

    lookforward = windows.get(timeframe, [5, 10, 20])

    labels = np.ones(len(df), dtype=np.int32)  # Default HOLD
    close = df['close'].values

    for i in range(len(df) - max(lookforward)):
        votes = []

        for window in lookforward:
            future_price = close[i + window]
            change = (future_price - close[i]) / close[i]

            if change > thresh['buy']:
                votes.append(2)  # BUY
            elif change < thresh['sell']:
                votes.append(0)  # SELL
            else:
                votes.append(1)  # HOLD

        # Majority voting
        labels[i] = max(set(votes), key=votes.count)

    # Distribution
    unique, counts = np.unique(labels, return_counts=True)
    dist = dict(zip(['SELL', 'HOLD', 'BUY'], [0, 0, 0]))
    for u, c in zip(unique, counts):
        dist[['SELL', 'HOLD', 'BUY'][u]] = c

    print(f"Label distribution: {dist}")

    return labels


# =============================================================================
# MODEL ARCHITECTURE - DEEP CONV1D (iOS TFLite Compatible)
# =============================================================================

def create_pro_model(seq_length: int = 60, n_features: int = 150) -> Model:
    """
    Deep Conv1D architecture - 100% iOS TFLite compatible.
    NO LSTM = No conversion errors.
    Uses dilated convolutions to capture long-range dependencies (like LSTM).
    """

    inputs = Input(shape=(seq_length, n_features), name='input')

    # =========================================================================
    # CONV BLOCK 1 - Local feature extraction
    # =========================================================================
    x = Conv1D(128, 3, padding='same', activation='relu')(inputs)
    x = BatchNormalization()(x)
    x = Conv1D(128, 3, padding='same', activation='relu')(x)
    x = BatchNormalization()(x)
    x = MaxPooling1D(2)(x)  # 60 -> 30
    x = Dropout(0.2)(x)

    # =========================================================================
    # CONV BLOCK 2 - Deeper features
    # =========================================================================
    x = Conv1D(256, 3, padding='same', activation='relu')(x)
    x = BatchNormalization()(x)
    x = Conv1D(256, 3, padding='same', activation='relu')(x)
    x = BatchNormalization()(x)
    x = MaxPooling1D(2)(x)  # 30 -> 15
    x = Dropout(0.25)(x)

    # =========================================================================
    # DILATED CONV BLOCK - Captures long-range temporal dependencies (like LSTM)
    # Dilation rates: 1, 2, 4, 8 = receptive field of 15 timesteps each layer
    # =========================================================================
    # Dilated conv 1
    d1 = Conv1D(128, 3, padding='same', dilation_rate=1, activation='relu')(x)
    d1 = BatchNormalization()(d1)

    # Dilated conv 2 (wider view)
    d2 = Conv1D(128, 3, padding='same', dilation_rate=2, activation='relu')(x)
    d2 = BatchNormalization()(d2)

    # Dilated conv 4 (even wider)
    d4 = Conv1D(128, 3, padding='same', dilation_rate=4, activation='relu')(x)
    d4 = BatchNormalization()(d4)

    # Concatenate all dilated outputs for multi-scale features
    x = Concatenate()([d1, d2, d4])  # 128*3 = 384 channels
    x = Dropout(0.3)(x)

    # =========================================================================
    # CONV BLOCK 3 - Combine multi-scale features
    # =========================================================================
    x = Conv1D(512, 3, padding='same', activation='relu')(x)
    x = BatchNormalization()(x)
    x = Conv1D(256, 3, padding='same', activation='relu')(x)
    x = BatchNormalization()(x)
    x = MaxPooling1D(3)(x)  # 15 -> 5
    x = Dropout(0.3)(x)

    # =========================================================================
    # GLOBAL POOLING + DENSE HEAD
    # =========================================================================
    # Global Average Pooling - captures overall sequence representation
    gap = GlobalAveragePooling1D()(x)

    # Also use flattening for detailed features
    flat = Flatten()(x)

    # Combine both
    x = Concatenate()([gap, flat])

    # Dense layers
    x = Dense(512, activation='relu')(x)
    x = BatchNormalization()(x)
    x = Dropout(0.4)(x)

    x = Dense(256, activation='relu')(x)
    x = BatchNormalization()(x)
    x = Dropout(0.35)(x)

    x = Dense(128, activation='relu')(x)
    x = BatchNormalization()(x)
    x = Dropout(0.3)(x)

    x = Dense(64, activation='relu')(x)
    x = Dropout(0.25)(x)

    # Output with temperature scaling for calibrated confidence
    outputs = Dense(3, activation='softmax', name='output')(x)

    model = Model(inputs=inputs, outputs=outputs)

    model.compile(
        optimizer=Adam(learning_rate=0.001),  # Higher LR for Conv1D
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )

    return model


# =============================================================================
# TRAINING
# =============================================================================

def train_model(coin: str, timeframe: str, epochs: int = 500):
    """Train a PRO model for a specific coin and timeframe."""

    print(f"\n{'='*60}")
    print(f"Training {coin} {timeframe} PRO Model")
    print(f"{'='*60}")

    # Fetch data
    symbol = f"{coin}/USDT"
    df = fetch_data(symbol, timeframe, days=1825)  # 5 years

    # Build features
    print("Building 150 features...")
    builder = AdvancedFeatureBuilder()
    features = builder.build_features(df)

    # Generate labels
    print("Generating labels...")
    labels = generate_labels(df, timeframe)

    # Create sequences
    print("Creating sequences...")
    seq_length = 60
    X, y = [], []

    for i in range(seq_length, len(features) - 1):
        X.append(features[i-seq_length:i])
        y.append(labels[i])

    X = np.array(X, dtype=np.float32)
    y = np.array(y, dtype=np.int32)

    print(f"Dataset: {X.shape[0]} sequences, {X.shape[1]} timesteps, {X.shape[2]} features")

    # Normalize
    print("Normalizing features...")
    scaler = StandardScaler()
    X_reshaped = X.reshape(-1, X.shape[-1])
    X_reshaped = scaler.fit_transform(X_reshaped)
    X = X_reshaped.reshape(X.shape)

    # Train/test split
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, shuffle=False)

    # Class weights
    class_weights = compute_class_weight('balanced', classes=np.unique(y_train), y=y_train)
    class_weight_dict = dict(enumerate(class_weights))
    print(f"Class weights: {class_weight_dict}")

    # Create model
    print("Creating PRO model...")
    model = create_pro_model(seq_length=60, n_features=150)
    model.summary()

    # Callbacks
    callbacks = [
        EarlyStopping(
            monitor='val_loss',
            patience=50,
            restore_best_weights=True,
            verbose=1
        ),
        ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=15,
            min_lr=1e-6,
            verbose=1
        )
    ]

    # Train
    print(f"\nTraining for {epochs} epochs...")
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=epochs,
        batch_size=64,
        class_weight=class_weight_dict,
        callbacks=callbacks,
        verbose=1
    )

    # Evaluate
    val_loss, val_acc = model.evaluate(X_val, y_val, verbose=0)
    print(f"\nValidation accuracy: {val_acc*100:.1f}%")

    # Save model
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'ml')
    os.makedirs(output_dir, exist_ok=True)

    model_name = f"{coin.lower()}_{timeframe}_v2"

    # Convert to TFLite
    print("\nConverting to TFLite...")

    # Use concrete function for conversion
    @tf.function(input_signature=[tf.TensorSpec(shape=[None, 60, 150], dtype=tf.float32)])
    def model_fn(x):
        return model(x)

    concrete_func = model_fn.get_concrete_function()
    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func])
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float32]

    tflite_model = converter.convert()

    tflite_path = os.path.join(output_dir, f"{model_name}.tflite")
    with open(tflite_path, 'wb') as f:
        f.write(tflite_model)

    size_kb = os.path.getsize(tflite_path) / 1024
    print(f"Saved: {tflite_path} ({size_kb:.1f} KB)")

    # Save scaler
    scaler_path = os.path.join(output_dir, f"{model_name}_scaler.json")
    scaler_data = {
        'mean': scaler.mean_.tolist(),
        'scale': scaler.scale_.tolist(),
        'n_features': 150
    }
    with open(scaler_path, 'w') as f:
        json.dump(scaler_data, f)
    print(f"Saved: {scaler_path}")

    return val_acc


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Train PRO ML models')
    parser.add_argument('--coin', type=str, required=True, help='Coin symbol (BTC, ETH, SOL, BNB)')
    parser.add_argument('--timeframe', type=str, required=True, help='Timeframe (4h, 1d)')
    parser.add_argument('--epochs', type=int, default=500, help='Number of epochs')

    args = parser.parse_args()

    accuracy = train_model(args.coin.upper(), args.timeframe, args.epochs)

    print(f"\n{'='*60}")
    print(f"TRAINING COMPLETE")
    print(f"{'='*60}")
    print(f"  {args.coin.upper()}_{args.timeframe}_v2: {accuracy*100:.1f}%")


if __name__ == '__main__':
    main()
