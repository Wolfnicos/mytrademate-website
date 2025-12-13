#!/usr/bin/env python3
"""
iOS-Compatible Model Training Script
=====================================
TensorFlow 2.12 + Conv1D architecture = TFLite BUILTIN ops only

This script trains models that are 100% compatible with iOS tflite_flutter.

Feature Order (76 total) - Matches Flutter's FullFeatureBuilder:
  [0-24]   Candlestick patterns (25 features)
  [25-29]  Price action (5 features)
  [30-32]  RSI (3 features)
  [33-37]  MACD (5 features)
  [38-43]  Bollinger Bands (6 features)
  [44-45]  ATR (2 features)
  [46-47]  ADX (2 features)
  [48-51]  Stochastic (4 features)
  [52-58]  Ichimoku (7 features)
  [59-63]  Volume (5 features)
  [64-72]  Moving Averages (9 features)
  [73-75]  Trend (3 features)

Usage:
    python train_ios_compatible.py --coin BTC --timeframe 4h
    python train_ios_compatible.py --coin BTC --timeframe 1d
    python train_ios_compatible.py --general --timeframe 4h
"""

import os
import json
import argparse
import numpy as np
import pandas as pd
from datetime import datetime
from typing import Dict, Tuple, List
import ccxt

# TensorFlow 2.12
import tensorflow as tf
from tensorflow import keras
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split

print(f"TensorFlow version: {tf.__version__}")
assert tf.__version__.startswith('2.12'), f"Need TF 2.12, got {tf.__version__}"


# =============================================================================
# FEATURE BUILDER - Exact match with Flutter's FullFeatureBuilder
# =============================================================================

class FlutterFeatureBuilder:
    """
    Generates 76 features in EXACT same order as Flutter's FullFeatureBuilder.
    """

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
        features[:, 28] = (h - l) / (c + 1e-10)  # HL range
        features[:, 29] = (c - l) / (h - l + 1e-10)  # Close position

        # [30-32] RSI
        rsi = self._rsi(c, 14)
        features[:, 30] = rsi / 100.0  # Normalize to 0-1
        features[:, 31] = (rsi < 30).astype(np.float32)
        features[:, 32] = (rsi > 70).astype(np.float32)

        # [33-37] MACD
        macd, signal, hist = self._macd(c)
        features[:, 33] = macd / (c + 1e-10)  # Normalize by price
        features[:, 34] = signal / (c + 1e-10)
        features[:, 35] = hist / (c + 1e-10)
        features[:, 36] = self._cross_above(macd, signal)
        features[:, 37] = self._cross_below(macd, signal)

        # [38-43] Bollinger Bands
        bb_upper, bb_mid, bb_lower = self._bollinger(c, 20, 2.0)
        features[:, 38] = (bb_upper - c) / (c + 1e-10)  # Normalized distance
        features[:, 39] = 0.0  # Middle is reference
        features[:, 40] = (c - bb_lower) / (c + 1e-10)
        bb_width = (bb_upper - bb_lower) / (bb_mid + 1e-10)
        features[:, 41] = bb_width
        features[:, 42] = (c - bb_lower) / (bb_upper - bb_lower + 1e-10)  # Position
        features[:, 43] = (bb_width < 0.04).astype(np.float32)  # Squeeze

        # [44-45] ATR
        atr = self._atr(h, l, c, 14)
        features[:, 44] = atr / (c + 1e-10)  # ATR as % of price
        features[:, 45] = atr / (c + 1e-10)  # Same for compatibility

        # [46-47] ADX
        adx = self._adx(h, l, c, 14)
        features[:, 46] = adx / 100.0  # Normalize to 0-1
        features[:, 47] = (adx > 25).astype(np.float32)  # Trending

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
        features[:, 56] = (senkou_a > senkou_b).astype(np.float32)  # Green cloud
        features[:, 57] = ((c > senkou_a) & (c > senkou_b)).astype(np.float32)
        features[:, 58] = ((c < senkou_a) & (c < senkou_b)).astype(np.float32)

        # [59-63] Volume
        vol_sma = self._sma(v, 20)
        obv = self._obv(c, v)
        features[:, 59] = v / (vol_sma + 1e-10)  # Volume ratio
        features[:, 60] = 1.0  # Reference
        features[:, 61] = v / (vol_sma + 1e-10)  # Same ratio
        features[:, 62] = self._normalize_obv(obv)  # Normalized OBV
        features[:, 63] = (v > vol_sma * 1.5).astype(np.float32)  # High volume

        # [64-72] Moving Averages
        sma20 = self._sma(c, 20)
        sma50 = self._sma(c, 50)
        sma200 = self._sma(c, 200)
        features[:, 64] = (c - sma20) / (sma20 + 1e-10)  # Distance from SMA
        features[:, 65] = (c - sma50) / (sma50 + 1e-10)
        features[:, 66] = (c - sma200) / (sma200 + 1e-10)
        features[:, 67] = (c > sma20).astype(np.float32)
        features[:, 68] = (c > sma50).astype(np.float32)
        features[:, 69] = (c > sma200).astype(np.float32)
        features[:, 70] = self._cross_above(sma50, sma200)  # Golden cross
        features[:, 71] = self._cross_below(sma50, sma200)  # Death cross
        features[:, 72] = ((c > sma20) & (sma20 > sma50)).astype(np.float32)

        # [73-75] Trend
        features[:, 73] = self._higher_high(h)
        features[:, 74] = self._lower_low(l)
        features[:, 75] = ((c > sma20) & (sma20 > sma50)).astype(np.float32)

        # Clean NaN/Inf
        features = np.nan_to_num(features, nan=0.0, posinf=1.0, neginf=-1.0)

        return features

    # === Pattern Detection ===
    def _detect_patterns(self, o, h, l, c) -> Dict[str, np.ndarray]:
        n = len(c)
        patterns = {name: np.zeros(n, dtype=np.float32) for name in self.PATTERN_NAMES}

        for i in range(n):
            body = abs(c[i] - o[i])
            rng = h[i] - l[i] + 1e-10
            upper = h[i] - max(o[i], c[i])
            lower = min(o[i], c[i]) - l[i]
            body_ratio = body / rng

            # Doji patterns
            if body_ratio < 0.1:
                patterns['doji'][i] = 1.0
                if lower > body * 2 and upper < body:
                    patterns['dragonfly_doji'][i] = 1.0
                if upper > body * 2 and lower < body:
                    patterns['gravestone_doji'][i] = 1.0
                if lower > body * 2 and upper > body * 2:
                    patterns['long_legged_doji'][i] = 1.0

            # Hammer patterns
            if lower > body * 2 and upper < body * 0.5:
                if c[i] > o[i]:
                    patterns['hammer'][i] = 1.0
                else:
                    patterns['hanging_man'][i] = 1.0

            if upper > body * 2 and lower < body * 0.5:
                if c[i] > o[i]:
                    patterns['inverted_hammer'][i] = 1.0
                else:
                    patterns['shooting_star'][i] = 1.0

            # Body patterns
            if 0.1 < body_ratio < 0.3:
                patterns['spinning_top'][i] = 1.0
            if body_ratio > 0.8:
                if c[i] > o[i]:
                    patterns['marubozu_bullish'][i] = 1.0
                else:
                    patterns['marubozu_bearish'][i] = 1.0

            # Two-candle patterns
            if i > 0:
                prev_body = abs(c[i-1] - o[i-1])

                if c[i] > o[i] and c[i-1] < o[i-1] and body > prev_body * 1.2:
                    patterns['bullish_engulfing'][i] = 1.0
                if c[i] < o[i] and c[i-1] > o[i-1] and body > prev_body * 1.2:
                    patterns['bearish_engulfing'][i] = 1.0

                if c[i] > o[i] and c[i-1] < o[i-1] and c[i] > (o[i-1] + c[i-1]) / 2:
                    patterns['piercing_line'][i] = 1.0
                if c[i] < o[i] and c[i-1] > o[i-1] and c[i] < (o[i-1] + c[i-1]) / 2:
                    patterns['dark_cloud_cover'][i] = 1.0

                if body < prev_body * 0.5:
                    if c[i] > o[i] and c[i-1] < o[i-1]:
                        patterns['bullish_harami'][i] = 1.0
                    if c[i] < o[i] and c[i-1] > o[i-1]:
                        patterns['bearish_harami'][i] = 1.0

                if abs(l[i] - l[i-1]) / rng < 0.05:
                    patterns['tweezer_bottom'][i] = 1.0
                if abs(h[i] - h[i-1]) / rng < 0.05:
                    patterns['tweezer_top'][i] = 1.0

            # Three-candle patterns
            if i > 1:
                prev2_body = abs(c[i-2] - o[i-2])
                prev_body = abs(c[i-1] - o[i-1])

                if c[i-2] < o[i-2] and prev_body < prev2_body * 0.3 and c[i] > o[i]:
                    patterns['morning_star'][i] = 1.0
                if c[i-2] > o[i-2] and prev_body < prev2_body * 0.3 and c[i] < o[i]:
                    patterns['evening_star'][i] = 1.0

                if (c[i] > o[i] and c[i-1] > o[i-1] and c[i-2] > o[i-2] and
                    c[i] > c[i-1] > c[i-2]):
                    patterns['three_white_soldiers'][i] = 1.0
                if (c[i] < o[i] and c[i-1] < o[i-1] and c[i-2] < o[i-2] and
                    c[i] < c[i-1] < c[i-2]):
                    patterns['three_black_crows'][i] = 1.0

            # Rising/Falling three
            if i > 3:
                if c[i] > c[i-4] and c[i-1] < c[i-4]:
                    patterns['rising_three'][i] = 1.0
                if c[i] < c[i-4] and c[i-1] > c[i-4]:
                    patterns['falling_three'][i] = 1.0

        return patterns

    # === Technical Indicators ===
    def _returns(self, c):
        ret = np.zeros(len(c))
        ret[1:] = (c[1:] - c[:-1]) / (c[:-1] + 1e-10)
        return ret

    def _log_returns(self, c):
        ret = np.zeros(len(c))
        ret[1:] = np.log(c[1:] / (c[:-1] + 1e-10))
        return np.nan_to_num(ret)

    def _volatility(self, returns, window=20):
        vol = np.zeros(len(returns))
        for i in range(window, len(returns)):
            vol[i] = np.std(returns[i-window:i])
        return vol

    def _sma(self, data, period):
        sma = np.zeros(len(data))
        for i in range(period - 1, len(data)):
            sma[i] = np.mean(data[i-period+1:i+1])
        sma[:period-1] = sma[period-1] if period < len(data) else data[0]
        return sma

    def _ema(self, data, period):
        ema = np.zeros(len(data))
        mult = 2.0 / (period + 1)
        ema[0] = data[0]
        for i in range(1, len(data)):
            ema[i] = (data[i] - ema[i-1]) * mult + ema[i-1]
        return ema

    def _rsi(self, c, period=14):
        rsi = np.full(len(c), 50.0)
        deltas = np.diff(c)
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)

        if len(gains) >= period:
            avg_gain = np.zeros(len(c))
            avg_loss = np.zeros(len(c))
            avg_gain[period] = np.mean(gains[:period])
            avg_loss[period] = np.mean(losses[:period])

            for i in range(period + 1, len(c)):
                avg_gain[i] = (avg_gain[i-1] * (period-1) + gains[i-1]) / period
                avg_loss[i] = (avg_loss[i-1] * (period-1) + losses[i-1]) / period

            for i in range(period, len(c)):
                if avg_loss[i] == 0:
                    rsi[i] = 100
                else:
                    rs = avg_gain[i] / avg_loss[i]
                    rsi[i] = 100 - (100 / (1 + rs))

        return rsi

    def _macd(self, c):
        ema12 = self._ema(c, 12)
        ema26 = self._ema(c, 26)
        macd = ema12 - ema26
        signal = self._ema(macd, 9)
        hist = macd - signal
        return macd, signal, hist

    def _bollinger(self, c, period=20, std_dev=2.0):
        sma = self._sma(c, period)
        std = np.zeros(len(c))
        for i in range(period - 1, len(c)):
            std[i] = np.std(c[i-period+1:i+1])
        std[:period-1] = std[period-1] if period < len(c) else 0
        upper = sma + std * std_dev
        lower = sma - std * std_dev
        return upper, sma, lower

    def _atr(self, h, l, c, period=14):
        tr = np.zeros(len(c))
        for i in range(1, len(c)):
            tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
        return self._sma(tr, period)

    def _adx(self, h, l, c, period=14):
        # Simplified ADX
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

        # Fill early values
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
        """Normalize OBV to [-1, 1] range."""
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
# DATA FETCHING
# =============================================================================

def fetch_binance_data(symbol: str, timeframe: str, limit: int = 1000) -> pd.DataFrame:
    """Fetch OHLCV data from Binance."""
    print(f"Fetching {symbol} {timeframe} from Binance (limit={limit})...")

    exchange = ccxt.binance({'enableRateLimit': True})
    tf_map = {'5m': '5m', '15m': '15m', '1h': '1h', '4h': '4h', '1d': '1d'}

    ohlcv = exchange.fetch_ohlcv(symbol, tf_map.get(timeframe, timeframe), limit=limit)

    df = pd.DataFrame(ohlcv, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
    df.set_index('timestamp', inplace=True)

    print(f"  Fetched {len(df)} candles")
    print(f"  Date range: {df.index[0]} to {df.index[-1]}")
    print(f"  Price range: ${df['close'].min():.2f} - ${df['close'].max():.2f}")

    return df


def fetch_multiple_coins(coins: List[str], timeframe: str, limit: int = 1000) -> pd.DataFrame:
    """Fetch data for multiple coins and combine."""
    all_data = []

    for coin in coins:
        try:
            symbol = f"{coin}/USDT"
            df = fetch_binance_data(symbol, timeframe, limit)
            df['coin'] = coin
            all_data.append(df)
            print(f"  {coin}: {len(df)} candles")
        except Exception as e:
            print(f"  {coin}: Failed - {e}")

    if not all_data:
        raise ValueError("No data fetched")

    combined = pd.concat(all_data, ignore_index=False)
    print(f"Total: {len(combined)} candles from {len(all_data)} coins")

    return combined


# =============================================================================
# LABELS
# =============================================================================

def generate_labels(df: pd.DataFrame, lookahead: int = 5, threshold: float = 0.015) -> np.ndarray:
    """
    Generate SELL/HOLD/BUY labels.

    0 = SELL (price drops > threshold)
    1 = HOLD (price within threshold)
    2 = BUY (price rises > threshold)
    """
    n = len(df)
    labels = np.ones(n, dtype=np.int32)  # Default HOLD
    closes = df['close'].values

    for i in range(n - lookahead):
        future = closes[i + lookahead]
        current = closes[i]
        pct_change = (future - current) / current

        if pct_change > threshold:
            labels[i] = 2  # BUY
        elif pct_change < -threshold:
            labels[i] = 0  # SELL

    return labels


# =============================================================================
# MODEL ARCHITECTURE - Conv1D + Dense (TFLite BUILTIN ops only)
# =============================================================================

def create_model(seq_length: int = 60, n_features: int = 76, n_classes: int = 3):
    """
    Create Conv1D + Dense model.

    This architecture uses ONLY TFLite BUILTIN ops - no LSTM, no SELECT_TF_OPS.
    Compatible with iOS tflite_flutter 0.11.0.
    """
    inputs = keras.layers.Input(shape=(seq_length, n_features))

    # Conv1D blocks for temporal patterns
    x = keras.layers.Conv1D(64, 3, padding='same', activation='relu')(inputs)
    x = keras.layers.MaxPooling1D(2)(x)
    x = keras.layers.Dropout(0.2)(x)

    x = keras.layers.Conv1D(128, 3, padding='same', activation='relu')(x)
    x = keras.layers.MaxPooling1D(2)(x)
    x = keras.layers.Dropout(0.2)(x)

    x = keras.layers.Conv1D(64, 3, padding='same', activation='relu')(x)
    x = keras.layers.GlobalAveragePooling1D()(x)

    # Dense classification
    x = keras.layers.Dense(64, activation='relu')(x)
    x = keras.layers.Dropout(0.3)(x)
    x = keras.layers.Dense(32, activation='relu')(x)

    outputs = keras.layers.Dense(n_classes, activation='softmax')(x)

    model = keras.Model(inputs=inputs, outputs=outputs)

    model.compile(
        optimizer=keras.optimizers.Adam(0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )

    return model


# =============================================================================
# SEQUENCES
# =============================================================================

def create_sequences(features: np.ndarray, labels: np.ndarray, seq_length: int = 60):
    """Create sequences for training."""
    X, y = [], []
    for i in range(seq_length, len(features)):
        X.append(features[i-seq_length:i])
        y.append(labels[i])
    return np.array(X), np.array(y)


# =============================================================================
# TRAINING
# =============================================================================

def train_model(
    coin: str = 'BTC',
    timeframe: str = '4h',
    epochs: int = 50,
    batch_size: int = 32,
    output_dir: str = 'output',
    general: bool = False
):
    """Full training pipeline."""

    print("=" * 70)
    if general:
        print(f"Training GENERAL model for {timeframe}")
        coins = ['BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'ADA', 'AVAX', 'DOT']
    else:
        print(f"Training {coin} model for {timeframe}")
        coins = [coin]
    print("=" * 70)

    os.makedirs(output_dir, exist_ok=True)

    # 1. Fetch data
    if general:
        all_features = []
        all_labels = []

        for c in coins:
            try:
                symbol = f"{c}/USDT"
                df = fetch_binance_data(symbol, timeframe, limit=1000)

                builder = FlutterFeatureBuilder()
                features = builder.build_features(df)
                labels = generate_labels(df, lookahead=5, threshold=0.015)

                all_features.append(features)
                all_labels.append(labels)
                print(f"  {c}: {len(features)} samples")
            except Exception as e:
                print(f"  {c}: Skipped - {e}")

        features = np.vstack(all_features)
        labels = np.hstack(all_labels)
        print(f"Total: {len(features)} samples")
    else:
        symbol = f"{coin}/USDT"
        df = fetch_binance_data(symbol, timeframe, limit=1000)

        builder = FlutterFeatureBuilder()
        features = builder.build_features(df)
        labels = generate_labels(df, lookahead=5, threshold=0.015)

    # 2. Create sequences
    print("Creating sequences...")
    X, y = create_sequences(features, labels, seq_length=60)
    print(f"  Sequences: {X.shape}")

    # 3. Normalize with StandardScaler
    print("Normalizing features...")
    scaler = StandardScaler()
    n_samples, seq_len, n_features = X.shape
    X_flat = X.reshape(-1, n_features)
    X_scaled = scaler.fit_transform(X_flat)
    X = X_scaled.reshape(n_samples, seq_len, n_features).astype(np.float32)

    # 4. Split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    label_counts = np.bincount(y_train)
    print(f"  Labels: SELL={label_counts[0]}, HOLD={label_counts[1]}, BUY={label_counts[2]}")

    # 5. Create and train model
    print("Creating model...")
    model = create_model(seq_length=60, n_features=76, n_classes=3)
    model.summary()

    print("Training...")
    history = model.fit(
        X_train, y_train,
        epochs=epochs,
        batch_size=batch_size,
        validation_data=(X_test, y_test),
        callbacks=[
            keras.callbacks.EarlyStopping(patience=10, restore_best_weights=True),
            keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=5),
        ],
        verbose=1
    )

    # 6. Evaluate
    loss, accuracy = model.evaluate(X_test, y_test, verbose=0)
    print(f"Test Loss: {loss:.4f}")
    print(f"Test Accuracy: {accuracy:.4f}")

    # 7. Convert to TFLite - BUILTIN OPS ONLY
    print("Converting to TFLite (BUILTIN ops only)...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]

    tflite_model = converter.convert()

    # 8. Save files
    if general:
        prefix = f"general_{timeframe}"
    else:
        prefix = f"{coin.lower()}_{timeframe}"

    # Model
    model_path = os.path.join(output_dir, f"{prefix}_model.tflite")
    with open(model_path, 'wb') as f:
        f.write(tflite_model)
    print(f"Saved: {model_path} ({len(tflite_model)/1024:.1f} KB)")

    # Scaler
    scaler_data = {
        'mean': scaler.mean_.tolist(),
        'std': scaler.scale_.tolist()
    }
    scaler_path = os.path.join(output_dir, f"{prefix}_scaler.json")
    with open(scaler_path, 'w') as f:
        json.dump(scaler_data, f, indent=2)
    print(f"Saved: {scaler_path}")

    # Metadata
    metadata = {
        'coin': 'GENERAL' if general else coin,
        'timeframe': timeframe,
        'num_features': 76,
        'sequence_length': 60,
        'num_classes': 3,
        'test_accuracy': float(accuracy),
        'train_samples': len(X_train),
        'test_samples': len(X_test),
        'model_size_kb': len(tflite_model) / 1024,
        'date': datetime.now().isoformat(),
        'architecture': 'Conv1D+Dense',
        'tflite_ops': 'BUILTIN only',
        'tensorflow_version': tf.__version__,
        'compatible': 'iOS/Android'
    }
    if general:
        metadata['trained_on'] = coins

    metadata_path = os.path.join(output_dir, f"{prefix}_metadata.json")
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"Saved: {metadata_path}")

    print("=" * 70)
    print(f"DONE! Accuracy: {accuracy*100:.1f}%")
    print("=" * 70)

    return model, scaler


# =============================================================================
# MAIN
# =============================================================================

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Train iOS-compatible ML model')
    parser.add_argument('--coin', type=str, default='BTC', help='Coin (BTC, ETH, etc.)')
    parser.add_argument('--timeframe', type=str, default='4h', help='Timeframe (4h, 1d)')
    parser.add_argument('--epochs', type=int, default=50, help='Training epochs')
    parser.add_argument('--batch-size', type=int, default=32, help='Batch size')
    parser.add_argument('--output', type=str, default='output', help='Output directory')
    parser.add_argument('--general', action='store_true', help='Train general model')

    args = parser.parse_args()

    train_model(
        coin=args.coin,
        timeframe=args.timeframe,
        epochs=args.epochs,
        batch_size=args.batch_size,
        output_dir=args.output,
        general=args.general
    )
