#!/usr/bin/env python3
"""
Advanced Model Training Script v2025
=====================================
- 76 features (compatible with Flutter FullFeatureBuilder)
- Much more training data (5000+ candles)
- Better label generation with multiple lookahead windows
- Early stopping + regularization
- iOS TFLite compatible (Conv1D architecture)

Usage:
    python train_v2025.py --coin BTC --timeframe 4h --epochs 100
    python train_v2025.py --coin BTC --timeframe 1d --epochs 150
    python train_v2025.py --all-coins --timeframe 4h --epochs 100
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

# TensorFlow 2.x
import tensorflow as tf
from tensorflow import keras
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight

print(f"TensorFlow version: {tf.__version__}")

# =============================================================================
# FEATURE BUILDER - 76 features, exact match with Flutter
# =============================================================================

class FlutterFeatureBuilder:
    """Generates 76 features in EXACT same order as Flutter's FullFeatureBuilder."""

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
        self.n_features = 76
        self.seq_length = 60

    def build_features(self, df: pd.DataFrame) -> np.ndarray:
        """Build 76 features from OHLCV DataFrame."""
        n = len(df)
        features = np.zeros((n, 76), dtype=np.float32)

        o = df['open'].values.astype(np.float64)
        h = df['high'].values.astype(np.float64)
        l = df['low'].values.astype(np.float64)
        c = df['close'].values.astype(np.float64)
        v = df['volume'].values.astype(np.float64)

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
        features[:, 69] = (sma50 > sma200).astype(np.float32)
        features[:, 70] = self._cross_above(sma50, sma200)
        features[:, 71] = self._cross_below(sma50, sma200)
        features[:, 72] = (ema12 - ema26) / (c + 1e-10)

        # [73-75] Trend
        features[:, 73] = self._higher_high(h)
        features[:, 74] = self._lower_low(l)
        features[:, 75] = (features[:, 73] > features[:, 74]).astype(np.float32)

        return features

    # --- Helper methods ---
    def _detect_patterns(self, o, h, l, c):
        n = len(c)
        patterns = {name: np.zeros(n) for name in self.PATTERN_NAMES}

        body = np.abs(c - o)
        upper_shadow = h - np.maximum(c, o)
        lower_shadow = np.minimum(c, o) - l
        full_range = h - l + 1e-10

        # Doji patterns
        patterns['doji'] = (body / full_range < 0.1).astype(np.float32)
        patterns['dragonfly_doji'] = ((body / full_range < 0.1) & (lower_shadow > body * 2) & (upper_shadow < body)).astype(np.float32)
        patterns['gravestone_doji'] = ((body / full_range < 0.1) & (upper_shadow > body * 2) & (lower_shadow < body)).astype(np.float32)
        patterns['long_legged_doji'] = ((body / full_range < 0.1) & (lower_shadow > body) & (upper_shadow > body)).astype(np.float32)

        # Single candle patterns
        patterns['hammer'] = ((lower_shadow > body * 2) & (upper_shadow < body * 0.5) & (c > o)).astype(np.float32)
        patterns['inverted_hammer'] = ((upper_shadow > body * 2) & (lower_shadow < body * 0.5) & (c > o)).astype(np.float32)
        patterns['shooting_star'] = ((upper_shadow > body * 2) & (lower_shadow < body * 0.5) & (c < o)).astype(np.float32)
        patterns['hanging_man'] = ((lower_shadow > body * 2) & (upper_shadow < body * 0.5) & (c < o)).astype(np.float32)
        patterns['spinning_top'] = ((body / full_range < 0.3) & (upper_shadow > body * 0.5) & (lower_shadow > body * 0.5)).astype(np.float32)
        patterns['marubozu_bullish'] = ((body / full_range > 0.9) & (c > o)).astype(np.float32)
        patterns['marubozu_bearish'] = ((body / full_range > 0.9) & (c < o)).astype(np.float32)

        # Multi-candle patterns
        for i in range(1, n):
            prev_body = abs(c[i-1] - o[i-1])
            curr_body = body[i]

            # Engulfing
            if c[i] > o[i] and c[i-1] < o[i-1] and o[i] < c[i-1] and c[i] > o[i-1]:
                patterns['bullish_engulfing'][i] = 1.0
            if c[i] < o[i] and c[i-1] > o[i-1] and o[i] > c[i-1] and c[i] < o[i-1]:
                patterns['bearish_engulfing'][i] = 1.0

            # Harami
            if c[i-1] < o[i-1] and c[i] > o[i] and o[i] > c[i-1] and c[i] < o[i-1]:
                patterns['bullish_harami'][i] = 1.0
            if c[i-1] > o[i-1] and c[i] < o[i] and o[i] < c[i-1] and c[i] > o[i-1]:
                patterns['bearish_harami'][i] = 1.0

            # Piercing/Dark Cloud
            if c[i-1] < o[i-1] and c[i] > o[i] and o[i] < c[i-1] and c[i] > (o[i-1] + c[i-1]) / 2:
                patterns['piercing_line'][i] = 1.0
            if c[i-1] > o[i-1] and c[i] < o[i] and o[i] > c[i-1] and c[i] < (o[i-1] + c[i-1]) / 2:
                patterns['dark_cloud_cover'][i] = 1.0

            # Tweezer
            if abs(l[i] - l[i-1]) / full_range[i] < 0.05:
                patterns['tweezer_bottom'][i] = 1.0
            if abs(h[i] - h[i-1]) / full_range[i] < 0.05:
                patterns['tweezer_top'][i] = 1.0

        # 3-candle patterns
        for i in range(2, n):
            # Morning Star
            if c[i-2] < o[i-2] and body[i-1] / full_range[i-1] < 0.3 and c[i] > o[i] and c[i] > (o[i-2] + c[i-2]) / 2:
                patterns['morning_star'][i] = 1.0
            # Evening Star
            if c[i-2] > o[i-2] and body[i-1] / full_range[i-1] < 0.3 and c[i] < o[i] and c[i] < (o[i-2] + c[i-2]) / 2:
                patterns['evening_star'][i] = 1.0

            # Three White Soldiers
            if c[i-2] > o[i-2] and c[i-1] > o[i-1] and c[i] > o[i] and c[i-1] > c[i-2] and c[i] > c[i-1]:
                patterns['three_white_soldiers'][i] = 1.0
            # Three Black Crows
            if c[i-2] < o[i-2] and c[i-1] < o[i-1] and c[i] < o[i] and c[i-1] < c[i-2] and c[i] < c[i-1]:
                patterns['three_black_crows'][i] = 1.0

        return patterns

    def _sma(self, arr, period):
        result = np.zeros_like(arr)
        for i in range(period - 1, len(arr)):
            result[i] = np.mean(arr[i-period+1:i+1])
        result[:period-1] = arr[:period-1]
        return result

    def _ema(self, arr, period):
        result = np.zeros_like(arr)
        multiplier = 2 / (period + 1)
        result[0] = arr[0]
        for i in range(1, len(arr)):
            result[i] = (arr[i] - result[i-1]) * multiplier + result[i-1]
        return result

    def _returns(self, c):
        ret = np.zeros_like(c)
        ret[1:] = (c[1:] - c[:-1]) / (c[:-1] + 1e-10)
        return ret

    def _log_returns(self, c):
        ret = np.zeros_like(c)
        ret[1:] = np.log(c[1:] / (c[:-1] + 1e-10) + 1e-10)
        return ret

    def _volatility(self, returns, period):
        vol = np.zeros_like(returns)
        for i in range(period, len(returns)):
            vol[i] = np.std(returns[i-period:i])
        return vol

    def _rsi(self, c, period=14):
        delta = np.diff(c, prepend=c[0])
        gain = np.where(delta > 0, delta, 0)
        loss = np.where(delta < 0, -delta, 0)

        avg_gain = self._sma(gain, period)
        avg_loss = self._sma(loss, period)

        rs = avg_gain / (avg_loss + 1e-10)
        rsi = 100 - (100 / (1 + rs))
        return rsi

    def _macd(self, c):
        ema12 = self._ema(c, 12)
        ema26 = self._ema(c, 26)
        macd = ema12 - ema26
        signal = self._ema(macd, 9)
        hist = macd - signal
        return macd, signal, hist

    def _bollinger(self, c, period=20, std_dev=2.0):
        mid = self._sma(c, period)
        std = np.zeros_like(c)
        for i in range(period, len(c)):
            std[i] = np.std(c[i-period:i])
        upper = mid + std_dev * std
        lower = mid - std_dev * std
        return upper, mid, lower

    def _atr(self, h, l, c, period=14):
        tr = np.zeros_like(c)
        tr[0] = h[0] - l[0]
        for i in range(1, len(c)):
            tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
        return self._sma(tr, period)

    def _adx(self, h, l, c, period=14):
        n = len(c)
        adx = np.full(n, 25.0)
        plus_dm = np.zeros(n)
        minus_dm = np.zeros(n)
        tr = np.zeros(n)

        for i in range(1, n):
            up = h[i] - h[i-1]
            down = l[i-1] - l[i]
            plus_dm[i] = up if up > down and up > 0 else 0
            minus_dm[i] = down if down > up and down > 0 else 0
            tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))

        atr = self._sma(tr, period)
        plus_di = 100 * self._sma(plus_dm, period) / (atr + 1e-10)
        minus_di = 100 * self._sma(minus_dm, period) / (atr + 1e-10)
        dx = 100 * np.abs(plus_di - minus_di) / (plus_di + minus_di + 1e-10)
        adx = self._sma(dx, period)
        return adx

    def _stochastic(self, h, l, c, period=14):
        k = np.full(len(c), 50.0)
        for i in range(period - 1, len(c)):
            highest = np.max(h[i-period+1:i+1])
            lowest = np.min(l[i-period+1:i+1])
            k[i] = 100 * (c[i] - lowest) / (highest - lowest + 1e-10)
        d = self._sma(k, 3)
        return k, d

    def _ichimoku(self, h, l, c):
        n = len(c)
        tenkan = np.zeros(n)
        kijun = np.zeros(n)
        senkou_a = np.zeros(n)
        senkou_b = np.zeros(n)

        for i in range(9, n):
            tenkan[i] = (np.max(h[i-9:i]) + np.min(l[i-9:i])) / 2
        for i in range(26, n):
            kijun[i] = (np.max(h[i-26:i]) + np.min(l[i-26:i])) / 2

        senkou_a = (tenkan + kijun) / 2

        for i in range(52, n):
            senkou_b[i] = (np.max(h[i-52:i]) + np.min(l[i-52:i])) / 2

        tenkan[:10] = c[:10]
        kijun[:27] = c[:27]
        senkou_a[:27] = c[:27]
        senkou_b[:53] = c[:53]

        return tenkan, kijun, senkou_a, senkou_b

    def _obv(self, c, v):
        obv = np.zeros(len(c))
        for i in range(1, len(c)):
            if c[i] > c[i-1]:
                obv[i] = obv[i-1] + v[i]
            elif c[i] < c[i-1]:
                obv[i] = obv[i-1] - v[i]
            else:
                obv[i] = obv[i-1]
        return obv

    def _normalize_obv(self, obv):
        obv_min = np.min(obv)
        obv_max = np.max(obv)
        if obv_max - obv_min < 1e-10:
            return np.zeros_like(obv)
        return 2 * (obv - obv_min) / (obv_max - obv_min) - 1

    def _cross_above(self, fast, slow):
        cross = np.zeros(len(fast))
        for i in range(1, len(fast)):
            if fast[i] > slow[i] and fast[i-1] <= slow[i-1]:
                cross[i] = 1.0
        return cross

    def _cross_below(self, fast, slow):
        cross = np.zeros(len(fast))
        for i in range(1, len(fast)):
            if fast[i] < slow[i] and fast[i-1] >= slow[i-1]:
                cross[i] = 1.0
        return cross

    def _higher_high(self, h):
        hh = np.zeros(len(h))
        hh[1:] = (h[1:] > h[:-1]).astype(np.float32)
        return hh

    def _lower_low(self, l):
        ll = np.zeros(len(l))
        ll[1:] = (l[1:] < l[:-1]).astype(np.float32)
        return ll


# =============================================================================
# DATA FETCHING - MORE DATA
# =============================================================================

def fetch_binance_data_extended(symbol: str, timeframe: str, days: int = 365) -> pd.DataFrame:
    """Fetch extended OHLCV data from Binance (up to 1 year)."""
    print(f"Fetching {symbol} {timeframe} from Binance ({days} days)...")

    exchange = ccxt.binance({'enableRateLimit': True})

    # Calculate how many candles we need
    tf_minutes = {'5m': 5, '15m': 15, '1h': 60, '4h': 240, '1d': 1440}
    minutes_per_tf = tf_minutes.get(timeframe, 60)
    candles_per_day = 1440 // minutes_per_tf
    total_candles_needed = candles_per_day * days

    all_ohlcv = []
    since = exchange.parse8601((datetime.now() - timedelta(days=days)).isoformat())

    while len(all_ohlcv) < total_candles_needed:
        try:
            ohlcv = exchange.fetch_ohlcv(symbol, timeframe, since=since, limit=1000)
            if not ohlcv:
                break
            all_ohlcv.extend(ohlcv)
            since = ohlcv[-1][0] + 1  # Next timestamp after last candle
            print(f"  Fetched {len(all_ohlcv)} candles...")
            time.sleep(0.5)  # Rate limit
        except Exception as e:
            print(f"  Error: {e}")
            break

    df = pd.DataFrame(all_ohlcv, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
    df.drop_duplicates(subset='timestamp', keep='first', inplace=True)
    df.set_index('timestamp', inplace=True)
    df.sort_index(inplace=True)

    print(f"  Total: {len(df)} candles")
    print(f"  Date range: {df.index[0]} to {df.index[-1]}")
    print(f"  Price range: ${df['close'].min():.2f} - ${df['close'].max():.2f}")

    return df


# =============================================================================
# IMPROVED LABEL GENERATION
# =============================================================================

def generate_labels_v2(df: pd.DataFrame, timeframe: str) -> np.ndarray:
    """
    Generate SELL/HOLD/BUY labels with timeframe-specific thresholds.
    Uses multiple lookahead windows and majority voting.

    0 = SELL (price drops significantly)
    1 = HOLD (price within threshold)
    2 = BUY (price rises significantly)
    """
    # Timeframe-specific parameters
    params = {
        '5m':  {'lookahead': [3, 5, 8], 'threshold': 0.003},      # 0.3%
        '15m': {'lookahead': [4, 6, 10], 'threshold': 0.005},     # 0.5%
        '1h':  {'lookahead': [3, 5, 8], 'threshold': 0.01},       # 1.0%
        '4h':  {'lookahead': [3, 5, 8], 'threshold': 0.015},      # 1.5%
        '1d':  {'lookahead': [3, 5, 7], 'threshold': 0.02},       # 2.0%
    }

    config = params.get(timeframe, params['1h'])
    lookaheads = config['lookahead']
    threshold = config['threshold']

    n = len(df)
    closes = df['close'].values

    # Collect votes from multiple lookahead windows
    all_labels = []

    for lookahead in lookaheads:
        labels = np.ones(n, dtype=np.int32)  # Default HOLD

        for i in range(n - lookahead):
            future = closes[i + lookahead]
            current = closes[i]
            pct_change = (future - current) / current

            if pct_change > threshold:
                labels[i] = 2  # BUY
            elif pct_change < -threshold:
                labels[i] = 0  # SELL

        all_labels.append(labels)

    # Majority voting
    final_labels = np.ones(n, dtype=np.int32)
    for i in range(n):
        votes = [lab[i] for lab in all_labels]
        # If majority says BUY
        if votes.count(2) >= 2:
            final_labels[i] = 2
        # If majority says SELL
        elif votes.count(0) >= 2:
            final_labels[i] = 0
        # Otherwise HOLD

    # Print distribution
    unique, counts = np.unique(final_labels, return_counts=True)
    print(f"Label distribution: {dict(zip(['SELL', 'HOLD', 'BUY'], counts))}")

    return final_labels


# =============================================================================
# MODEL ARCHITECTURE - Conv1D (iOS TFLite compatible)
# =============================================================================

def create_model(seq_length: int = 60, n_features: int = 76, n_classes: int = 3):
    """Create Conv1D + Dense model with regularization."""
    inputs = keras.layers.Input(shape=(seq_length, n_features))

    # Conv1D blocks
    x = keras.layers.Conv1D(64, 3, padding='same', activation='relu')(inputs)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.MaxPooling1D(2)(x)
    x = keras.layers.Dropout(0.3)(x)

    x = keras.layers.Conv1D(128, 3, padding='same', activation='relu')(x)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.MaxPooling1D(2)(x)
    x = keras.layers.Dropout(0.3)(x)

    x = keras.layers.Conv1D(64, 3, padding='same', activation='relu')(x)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.GlobalAveragePooling1D()(x)

    # Dense layers
    x = keras.layers.Dense(64, activation='relu', kernel_regularizer=keras.regularizers.l2(0.01))(x)
    x = keras.layers.Dropout(0.4)(x)
    x = keras.layers.Dense(32, activation='relu', kernel_regularizer=keras.regularizers.l2(0.01))(x)
    x = keras.layers.Dropout(0.3)(x)

    outputs = keras.layers.Dense(n_classes, activation='softmax')(x)

    model = keras.Model(inputs=inputs, outputs=outputs)

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )

    return model


# =============================================================================
# TRAINING
# =============================================================================

def train_model(coin: str, timeframe: str, epochs: int = 100, days: int = 365, output_dir: str = None):
    """Train a single model."""
    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(__file__)) + '/../assets/ml'

    # Fetch data
    symbol = f"{coin}/USDT"
    df = fetch_binance_data_extended(symbol, timeframe, days=days)

    if len(df) < 500:
        print(f"Not enough data for {coin} {timeframe}: {len(df)} candles")
        return None

    # Build features
    print("Building features...")
    builder = FlutterFeatureBuilder()
    features = builder.build_features(df)

    # Generate labels
    print("Generating labels...")
    labels = generate_labels_v2(df, timeframe)

    # Create sequences
    print("Creating sequences...")
    seq_length = 60
    X, y = [], []
    for i in range(seq_length, len(features) - 10):  # Leave buffer at end
        X.append(features[i-seq_length:i])
        y.append(labels[i])

    X = np.array(X, dtype=np.float32)
    y = np.array(y, dtype=np.int32)

    print(f"Dataset: {X.shape[0]} sequences, {X.shape[1]} timesteps, {X.shape[2]} features")

    # Normalize features
    print("Normalizing features...")
    scaler = StandardScaler()
    X_reshaped = X.reshape(-1, X.shape[-1])
    scaler.fit(X_reshaped)
    X_normalized = scaler.transform(X_reshaped).reshape(X.shape)

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X_normalized, y, test_size=0.2, random_state=42, shuffle=True
    )

    # Class weights for imbalanced data
    class_weights = compute_class_weight('balanced', classes=np.unique(y_train), y=y_train)
    class_weight_dict = dict(enumerate(class_weights))
    print(f"Class weights: {class_weight_dict}")

    # Create model
    print("Creating model...")
    model = create_model(seq_length=seq_length, n_features=76, n_classes=3)
    model.summary()

    # Callbacks
    early_stopping = keras.callbacks.EarlyStopping(
        monitor='val_loss',
        patience=15,
        restore_best_weights=True
    )

    reduce_lr = keras.callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=5,
        min_lr=1e-6
    )

    # Train
    print(f"Training for {epochs} epochs...")
    history = model.fit(
        X_train, y_train,
        validation_data=(X_test, y_test),
        epochs=epochs,
        batch_size=32,
        class_weight=class_weight_dict,
        callbacks=[early_stopping, reduce_lr],
        verbose=1
    )

    # Evaluate
    loss, accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"Test accuracy: {accuracy*100:.1f}%")

    # Save model
    model_name = f"{coin.lower()}_{timeframe}_model"
    model_path = os.path.join(output_dir, f"{model_name}.tflite")
    scaler_path = os.path.join(output_dir, f"{coin.lower()}_{timeframe}_scaler.json")

    # Convert to TFLite
    print("Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    with open(model_path, 'wb') as f:
        f.write(tflite_model)
    print(f"Saved: {model_path} ({len(tflite_model)/1024:.1f} KB)")

    # Save scaler
    scaler_data = {
        'mean': scaler.mean_.tolist(),
        'std': scaler.scale_.tolist(),
        'accuracy': float(accuracy),
        'trained_date': datetime.now().isoformat(),
        'candles_used': len(df),
        'timeframe': timeframe,
        'coin': coin
    }
    with open(scaler_path, 'w') as f:
        json.dump(scaler_data, f, indent=2)
    print(f"Saved: {scaler_path}")

    return accuracy


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Train crypto ML models v2025')
    parser.add_argument('--coin', type=str, help='Coin to train (e.g., BTC, ETH)')
    parser.add_argument('--timeframe', type=str, default='4h', help='Timeframe (5m, 15m, 1h, 4h, 1d)')
    parser.add_argument('--epochs', type=int, default=100, help='Training epochs')
    parser.add_argument('--days', type=int, default=365, help='Days of historical data')
    parser.add_argument('--all-coins', action='store_true', help='Train all major coins')
    parser.add_argument('--all-timeframes', action='store_true', help='Train all timeframes')

    args = parser.parse_args()

    coins = ['BTC', 'ETH', 'BNB', 'SOL', 'ADA', 'XRP', 'DOGE', 'AVAX']
    timeframes = ['5m', '15m', '1h', '4h', '1d']

    if args.all_coins:
        target_coins = coins
    elif args.coin:
        target_coins = [args.coin.upper()]
    else:
        target_coins = ['BTC']

    if args.all_timeframes:
        target_tfs = timeframes
    else:
        target_tfs = [args.timeframe]

    results = {}

    for coin in target_coins:
        for tf in target_tfs:
            print(f"\n{'='*60}")
            print(f"Training {coin} {tf}")
            print(f"{'='*60}\n")

            try:
                acc = train_model(coin, tf, epochs=args.epochs, days=args.days)
                results[f"{coin}_{tf}"] = acc
            except Exception as e:
                print(f"Error training {coin} {tf}: {e}")
                results[f"{coin}_{tf}"] = None

    print(f"\n{'='*60}")
    print("TRAINING SUMMARY")
    print(f"{'='*60}")
    for key, acc in results.items():
        status = f"{acc*100:.1f}%" if acc else "FAILED"
        print(f"  {key}: {status}")


if __name__ == '__main__':
    main()
