"""
GodModel v6 Training Script
===========================

Trains ultra-powerful universal model for ALL coins and ALL timeframes.

Target: ≥85% accuracy on BTC 4h (2022-2025)
Architecture: TabNet (proven for tabular data)
Features: 180 (76 legacy + 104 advanced)
Output Size: < 9 MB (quantized TFLite)
"""

import os
import json
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight
import ccxt
from datetime import datetime, timedelta
from feature_engineering_v6 import FeatureEngineerV6
import warnings
warnings.filterwarnings('ignore')

print("="*80)
print("🚀 GodModel v6 Training Pipeline")
print("="*80)

# ===== CONFIGURATION =====

CONFIG = {
    # Data Collection
    'symbol': 'BTC/USDT',
    'timeframe': '4h',
    'start_date': '2022-01-01',
    'end_date': '2025-12-31',
    'exchanges': ['binance', 'coinbase', 'kraken'],  # Multi-exchange for robustness

    # Feature Engineering
    'n_features': 180,
    'lookback_window': 100,  # Number of candles for context

    # Model Architecture
    'model_type': 'transformer',  # V10: FT-Transformer for better feature learning
    'hidden_units': [512, 256, 128, 64],
    'dropout_rate': 0.3,
    'batch_size': 32,
    'epochs': 40,
    'early_stopping_patience': 12,  # Increased patience for stable learning
    'learning_rate': 2e-5,           # Slightly reduced for stability
    'clipnorm': 1.0,

    # Target Labels
    # 0 = SELL (price drops > 2%)
    # 1 = HOLD (price change -2% to +2%)
    # 2 = BUY (price rises > 2%)
    'label_threshold': 0.02,  # 2% price change threshold
    'prediction_horizon': 4,  # Predict 4 candles ahead (16h for 4h candles)

    # Output
    'output_dir': './trained_models',
    'model_name': 'GodModel_v6',
}

print(f"\n📋 Configuration:")
for key, value in CONFIG.items():
    print(f"   {key:30s}: {value}")


# ===== DATA COLLECTION =====

def fetch_ohlcv_data(symbol: str, timeframe: str, start_date: str, end_date: str) -> pd.DataFrame:
    """
    Fetch OHLCV data from exchange

    Returns DataFrame with columns: timestamp, open, high, low, close, volume
    """
    print(f"\n📊 Fetching {symbol} {timeframe} data from {start_date} to {end_date}...")

    # Initialize exchange (Binance has good historical data)
    exchange = ccxt.binance({
        'enableRateLimit': True,
        'options': {'defaultType': 'spot'}
    })

    # Convert dates to timestamps
    start_ts = int(pd.Timestamp(start_date).timestamp() * 1000)
    end_ts = int(pd.Timestamp(end_date).timestamp() * 1000)

    # Fetch data in chunks
    all_candles = []
    current_ts = start_ts

    while current_ts < end_ts:
        try:
            candles = exchange.fetch_ohlcv(symbol, timeframe, since=current_ts, limit=1000)
            if not candles:
                break

            all_candles.extend(candles)
            current_ts = candles[-1][0] + 1  # Move to next timestamp

            print(f"   Fetched {len(all_candles)} candles... (latest: {pd.Timestamp(candles[-1][0], unit='ms')})")

        except Exception as e:
            print(f"   ⚠️  Error fetching data: {e}")
            break

    # Convert to DataFrame
    df = pd.DataFrame(all_candles, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
    df.set_index('timestamp', inplace=True)

    print(f"✅ Fetched {len(df)} candles ({df.index[0]} to {df.index[-1]})")

    return df


# ===== LABEL GENERATION =====

def generate_labels(df: pd.DataFrame, threshold: float = 0.02, horizon: int = 4) -> np.ndarray:
    """
    SIMPLE FIXED THRESHOLDS - Most stable and proven method

    Uses classic fixed thresholds with slight asymmetry for crypto markets.
    No complex confirmations - let the model learn the patterns.

    0 = SELL (price drops > 2%)
    1 = HOLD (price change between -2% and +2.2%)
    2 = BUY (price rises > 2.2%)
    """
    print(f"\n🏷️  Generating labels with SIMPLE FIXED thresholds...")

    current_price = df['close'].values
    future_price = df['close'].shift(-horizon).values

    # Calculate 4h returns
    returns_4h = (future_price - current_price) / current_price

    # Fixed thresholds (slightly asymmetric - crypto pumps slower than dumps)
    sell_threshold = -0.020   # -2.0%
    buy_threshold = +0.022    # +2.2%

    print(f"   📊 Fixed thresholds:")
    print(f"      SELL threshold: {sell_threshold*100:.1f}%")
    print(f"      BUY threshold:  {buy_threshold*100:.1f}%")

    # Generate labels
    labels = np.ones(len(df), dtype=int)  # Default = HOLD (1)
    labels[returns_4h <= sell_threshold] = 0  # SELL
    labels[returns_4h >= buy_threshold] = 2   # BUY

    # Remove last `horizon` samples (no future data)
    labels[-horizon:] = -1

    # Print label distribution
    valid_labels = labels[labels != -1]
    sell_pct = (valid_labels == 0).sum() / len(valid_labels) * 100
    hold_pct = (valid_labels == 1).sum() / len(valid_labels) * 100
    buy_pct = (valid_labels == 2).sum() / len(valid_labels) * 100

    sell_count = (valid_labels == 0).sum()
    hold_count = (valid_labels == 1).sum()
    buy_count = (valid_labels == 2).sum()

    print(f"   Label distribution BEFORE undersampling:")
    print(f"      SELL: {sell_pct:.1f}% ({sell_count} signals)")
    print(f"      HOLD: {hold_pct:.1f}% ({hold_count} signals)")
    print(f"      BUY:  {buy_pct:.1f}% ({buy_count} signals)")

    return labels


# ===== TRIPLE LOSS (STATE-OF-THE-ART FOR CRYPTO) =====

def triple_loss(margin_sell=0.4, margin_buy=0.4):
    """
    TRIPLE LOSS - Most powerful loss for crypto in 2025

    Combines 3 components:
    1. Focal Loss - handles class imbalance
    2. Hinge Loss - forces distance between SELL and BUY predictions
    3. Confidence Penalty - punishes HOLD when signal is clear

    This eliminates the lazy classifier problem completely.
    """
    def loss(y_true, y_pred):
        # Flatten y_true and convert to int32
        y_true = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        y_true = tf.one_hot(y_true, 3)

        # 1. Focal component for imbalanced classification
        focal = tf.keras.losses.categorical_crossentropy(y_true, y_pred, from_logits=False)

        # 2. Force distance between SELL and BUY (prevent model from hedging)
        prob_sell = y_pred[:, 0]
        prob_buy = y_pred[:, 2]
        hinge = tf.maximum(0.0, margin_sell + margin_buy - prob_buy + prob_sell)

        # 3. Penalize HOLD when signal is clear
        prob_hold = y_pred[:, 1]
        confidence_penalty = tf.maximum(0.0, 0.7 - tf.maximum(prob_sell, prob_buy))

        return focal + 0.8 * hinge + 0.5 * confidence_penalty

    return loss


def clean_features(X_train, X_val, X_test):
    """
    Remove constant or near-constant features (std < 1e-8)
    """
    print("\n🧹 Cleaning features (removing constants)...")
    valid_features = []
    for i in range(X_train.shape[1]):
        if X_train[:, i].std() > 1e-8:
            valid_features.append(i)

    print(f"   Features remaining: {len(valid_features)}/{X_train.shape[1]}")

    return (X_train[:, valid_features],
            X_val[:, valid_features],
            X_test[:, valid_features],
            valid_features)


# ===== MODEL ARCHITECTURE =====

def build_tabnet_model(input_dim: int, output_dim: int = 3) -> tf.keras.Model:
    """
    Build TabNet-inspired model (attention-based tabular)

    TabNet is specifically designed for tabular data and achieves
    state-of-the-art results on structured datasets.
    """
    print(f"\n🏗️  Building TabNet model (input_dim={input_dim}, output_dim={output_dim})...")

    # Input layer
    inputs = tf.keras.Input(shape=(input_dim,), name='input')

    # Feature embedding
    x = tf.keras.layers.Dense(256, activation='relu', name='embed_1')(inputs)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.Dropout(0.2)(x)

    # Attention mechanism (TabNet-style)
    # This allows the model to learn which features are important
    attention = tf.keras.layers.Dense(input_dim, activation='softmax', name='attention')(x)
    attended_features = tf.keras.layers.Multiply()([inputs, attention])

    # Feature processing steps (3 decision steps)
    for i in range(3):
        # Dense block
        x = tf.keras.layers.Dense(512, activation='relu', name=f'dense_{i}_1')(attended_features)
        x = tf.keras.layers.BatchNormalization()(x)
        x = tf.keras.layers.Dropout(0.3)(x)

        x = tf.keras.layers.Dense(256, activation='relu', name=f'dense_{i}_2')(x)
        x = tf.keras.layers.BatchNormalization()(x)
        x = tf.keras.layers.Dropout(0.3)(x)

    # Final dense layers
    x = tf.keras.layers.Dense(128, activation='relu', name='dense_final_1')(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.Dropout(0.2)(x)

    x = tf.keras.layers.Dense(64, activation='relu', name='dense_final_2')(x)
    x = tf.keras.layers.BatchNormalization()(x)

    # Output layer (3-class classification: SELL, HOLD, BUY)
    outputs = tf.keras.layers.Dense(output_dim, activation='softmax', name='output')(x)

    # Build model
    model = tf.keras.Model(inputs=inputs, outputs=outputs, name='GodModel_v6_TabNet')

    # Compile with optimizer + SIMPLE LOSS (no tricks, let undersampling handle balance)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(
            learning_rate=CONFIG['learning_rate'],
            clipnorm=CONFIG['clipnorm']
        ),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(),
        metrics=['accuracy']
    )

    print(f"✅ Model built successfully!")
    print(f"   Total parameters: {model.count_params():,}")

    return model


def build_transformer_model(input_dim: int, output_dim: int = 3) -> tf.keras.Model:
    """
    Build Compact Transformer V12 - NATURAL DATA + CLASS WEIGHTS + THRESHOLD MOVING

    Key changes from V11:
    - NO undersampling (use natural ~80% HOLD distribution)
    - Gentle class weights (SELL: 1.8x, HOLD: 0.4x, BUY: 2.2x)
    - Lower learning rate 3e-5 (vs 5e-5)
    - Threshold moving at inference (sell_thresh=0.38, buy_thresh=0.42)
    """
    print(f"\n🏗️  Building Compact Transformer V12 (input_dim={input_dim}, output_dim={output_dim})...")

    # Input layer - flat features
    inputs = tf.keras.Input(shape=(input_dim,), name='input')

    # Feature tokenization: Create 60-token sequence
    seq_len = 60
    embed_dim = 192

    # Project flat features into sequence space
    x = tf.keras.layers.Dense(seq_len * embed_dim)(inputs)
    x = tf.keras.layers.Reshape((seq_len, embed_dim))(x)

    # Layer normalization before attention
    x = tf.keras.layers.LayerNormalization(epsilon=1e-6)(x)

    # Single Multi-Head Attention layer (8 heads, key_dim=24)
    attn_output = tf.keras.layers.MultiHeadAttention(
        num_heads=8,
        key_dim=24,
        dropout=0.1
    )(x, x)

    # Residual connection - CRITICAL for training stability
    x = tf.keras.layers.Add()([x, attn_output])

    # Layer normalization after residual
    x = tf.keras.layers.LayerNormalization(epsilon=1e-6)(x)

    # Global average pooling to aggregate sequence
    x = tf.keras.layers.GlobalAveragePooling1D()(x)

    # Classification head
    x = tf.keras.layers.Dense(128, activation='gelu')(x)
    x = tf.keras.layers.Dropout(0.2)(x)
    outputs = tf.keras.layers.Dense(output_dim, activation='softmax', name='output')(x)

    # Build model
    model = tf.keras.Model(inputs=inputs, outputs=outputs, name='GodModel_v12_ClassWeights')

    # Compile with AdamW - learning_rate=3e-5 (gentler for class weights)
    model.compile(
        optimizer=tf.keras.optimizers.AdamW(
            learning_rate=3e-5,
            weight_decay=1e-5
        ),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )

    print(f"✅ Compact Transformer V12 built successfully!")
    print(f"   Architecture: 1 attention layer, 8 heads, residual connections")
    print(f"   Embedding dim: {embed_dim}, Sequence length: {seq_len}")
    print(f"   Learning rate: 3e-5 (GENTLE for class weights)")
    print(f"   Total parameters: {model.count_params():,}")

    return model


# ===== TRAINING =====

def train_model(model, X_train, y_train, X_val, y_val, class_weight_dict=None):
    """
    Train the model with early stopping and learning rate scheduling
    V12: Uses gentle class weights instead of undersampling!
    """
    print(f"\n🎯 Training GodModel V12...")
    print(f"   Training samples: {len(X_train):,}")
    print(f"   Validation samples: {len(X_val):,}")

    if class_weight_dict:
        print(f"   Using class weights: {class_weight_dict}")

    # Callbacks - Classic and proven
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_accuracy',
            patience=CONFIG['early_stopping_patience'],
            restore_best_weights=True,
            verbose=1
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,  # Increased patience for stable learning
            min_lr=1e-7,
            verbose=1
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=os.path.join(CONFIG['output_dir'], 'best_model.h5'),
            monitor='val_accuracy',
            save_best_only=True,
            verbose=1
        )
    ]

    # Train with class weights (V12: natural data + gentle penalties)
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        batch_size=CONFIG['batch_size'],
        epochs=CONFIG['epochs'],
        callbacks=callbacks,
        class_weight=class_weight_dict,  # Use class weights instead of undersampling
        verbose=1
    )

    return history


# ===== EVALUATION =====

def predict_with_threshold_moving(probs, sell_thresh=0.38, buy_thresh=0.42):
    """
    V12: Threshold moving - the most powerful weapon against lazy classifiers!

    Instead of taking argmax, we require higher confidence for SELL/BUY predictions.
    This forces the model to be more conservative and reduces HOLD bias.

    Args:
        probs: Probability matrix (N, 3) with columns [SELL, HOLD, BUY]
        sell_thresh: Minimum confidence required to predict SELL (default: 0.38)
        buy_thresh: Minimum confidence required to predict BUY (default: 0.42)

    Returns:
        pred: Predicted labels (0=SELL, 1=HOLD, 2=BUY)
    """
    pred = np.ones(len(probs), dtype=int)  # Default: HOLD
    pred[probs[:, 0] > sell_thresh] = 0     # SELL only if very confident
    pred[probs[:, 2] > buy_thresh] = 2      # BUY only if very confident
    return pred


def evaluate_model(model, X_test, y_test):
    """
    Evaluate model performance with threshold moving (V12)
    """
    print(f"\n📊 Evaluating GodModel V12...")

    # Predict probabilities
    y_pred_proba = model.predict(X_test)

    # Standard argmax prediction
    y_pred_argmax = np.argmax(y_pred_proba, axis=1)

    # V12: Threshold moving prediction
    y_pred = predict_with_threshold_moving(
        y_pred_proba,
        sell_thresh=0.38,
        buy_thresh=0.42
    )

    # Compare argmax vs threshold moving
    print(f"\n" + "="*70)
    print(f"COMPARISON: Argmax vs Threshold Moving")
    print(f"="*70)

    # Argmax results
    acc_argmax = accuracy_score(y_test, y_pred_argmax)
    print(f"\n1️⃣  ARGMAX (standard prediction):")
    print(f"   Accuracy: {acc_argmax*100:.2f}%")
    cm_argmax = confusion_matrix(y_test, y_pred_argmax)
    for i, label in enumerate(['SELL', 'HOLD', 'BUY']):
        recall = cm_argmax[i, i] / cm_argmax[i, :].sum()
        print(f"   {label:5s} recall: {recall*100:.2f}%")

    # Threshold moving results (FINAL)
    accuracy = accuracy_score(y_test, y_pred)
    print(f"\n2️⃣  THRESHOLD MOVING (sell=0.38, buy=0.42) - FINAL:")
    print(f"   Accuracy: {accuracy*100:.2f}%")

    # Classification report
    print(f"\n📋 Classification Report (THRESHOLD MOVING):")
    print(classification_report(y_test, y_pred, target_names=['SELL', 'HOLD', 'BUY']))

    # Confusion matrix
    print(f"\n🔢 Confusion Matrix (THRESHOLD MOVING):")
    cm = confusion_matrix(y_test, y_pred)
    print(cm)

    # Per-class accuracy
    print(f"\n📈 Per-Class Recall (THRESHOLD MOVING):")
    for i, label in enumerate(['SELL', 'HOLD', 'BUY']):
        recall = cm[i, i] / cm[i, :].sum()
        print(f"   {label:5s}: {recall*100:.2f}%")

    return accuracy


# ===== SCALER EXPORT =====

def export_scaler(scaler, output_dir: str):
    """
    Export StandardScaler parameters to JSON for Flutter
    """
    print(f"\n💾 Exporting scaler to JSON...")

    scaler_params = {
        'mean': scaler.mean_.tolist(),
        'std': scaler.scale_.tolist(),
        'n_features': len(scaler.mean_),
        'version': 'v6',
        'created_at': datetime.now().isoformat()
    }

    scaler_path = os.path.join(output_dir, 'scaler_v6.json')
    with open(scaler_path, 'w') as f:
        json.dump(scaler_params, f, indent=2)

    print(f"✅ Scaler exported to: {scaler_path}")


# ===== MAIN PIPELINE =====

def main():
    """
    Main training pipeline
    """
    # Create output directory
    os.makedirs(CONFIG['output_dir'], exist_ok=True)

    # Step 1: Fetch data
    df = fetch_ohlcv_data(
        CONFIG['symbol'],
        CONFIG['timeframe'],
        CONFIG['start_date'],
        CONFIG['end_date']
    )

    # Step 2: Generate labels
    labels = generate_labels(
        df,
        threshold=CONFIG['label_threshold'],
        horizon=CONFIG['prediction_horizon']
    )

    # Step 3: Extract features
    print(f"\n🔧 Extracting 180 features...")
    engineer = FeatureEngineerV6()
    features = engineer.extract_features(df, CONFIG['symbol'], CONFIG['timeframe'])
    print(f"✅ Features extracted: {features.shape}")

    # Step 4: Remove samples without labels
    valid_mask = labels != -1
    features = features[valid_mask]
    labels = labels[valid_mask]
    print(f"   Valid samples: {len(features):,}")

    # Step 5: WALK-FORWARD VALIDATION (chronological split, NOT random!)
    # This is critical for time-series data - we NEVER train on future data
    print(f"\n📦 Walk-Forward Validation Split:")
    print(f"   Train: 2022-2023 data")
    print(f"   Val/Test: 2024-2025 data")

    # Find split point (end of 2023)
    split_date = pd.Timestamp('2024-01-01')
    df_valid = df[df.index < df.index[-1]]  # Remove last samples without labels
    train_mask = df_valid.index < split_date
    test_mask = df_valid.index >= split_date

    # Split chronologically
    n_train = train_mask.sum()
    n_test = test_mask.sum()

    X_train = features[:n_train]
    y_train = labels[:n_train]

    X_temp = features[n_train:n_train+n_test]
    y_temp = labels[n_train:n_train+n_test]

    # Split val/test from 2024-2025 data (50/50)
    val_split = len(X_temp) // 2
    X_val = X_temp[:val_split]
    y_val = y_temp[:val_split]
    X_test = X_temp[val_split:]
    y_test = y_temp[val_split:]

    print(f"   Train: {len(X_train):,} samples")
    print(f"   Val:   {len(X_val):,} samples")
    print(f"   Test:  {len(X_test):,} samples")

    # Step 6: Normalize features
    print(f"\n🔢 Normalizing features...")
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_val = scaler.transform(X_val)
    X_test = scaler.transform(X_test)
    print(f"✅ Features normalized (mean=0, std=1)")

    # Step 6.5: Clean features (remove constants) - DISABLED for iOS compatibility
    # X_train, X_val, X_test, valid_features = clean_features(X_train, X_val, X_test)
    # CONFIG['n_features'] = len(valid_features)  # Update feature count
    # Keep all 180 features for compatibility with scaler

    # Step 6.6: V12 - CLASS WEIGHTS instead of undersampling
    # Use NATURAL data distribution (~80% HOLD) with gentle penalties
    print(f"\n⚖️  V12: Computing gentle class weights (NO undersampling)...")
    print(f"   Training distribution (NATURAL):")
    print(f"      SELL: {(y_train == 0).sum():,} samples ({(y_train == 0).sum() / len(y_train) * 100:.1f}%)")
    print(f"      HOLD: {(y_train == 1).sum():,} samples ({(y_train == 1).sum() / len(y_train) * 100:.1f}%)")
    print(f"      BUY:  {(y_train == 2).sum():,} samples ({(y_train == 2).sum() / len(y_train) * 100:.1f}%)")
    print(f"   Total training samples: {len(X_train):,}")

    # Compute balanced class weights
    from sklearn.utils.class_weight import compute_class_weight
    class_weights = compute_class_weight('balanced', classes=np.array([0, 1, 2]), y=y_train)

    # Apply gentle multipliers (user-specified)
    # SELL: 1.8x (slightly boost minority class)
    # HOLD: 0.4x (heavily penalize majority class)
    # BUY:  2.2x (boost minority class more)
    class_weight_dict = {
        0: class_weights[0] * 1.8,  # SELL
        1: class_weights[1] * 0.4,  # HOLD (reduce penalty on majority)
        2: class_weights[2] * 2.2   # BUY
    }

    print(f"\n   Computed class weights (GENTLE):")
    print(f"      SELL (0): {class_weight_dict[0]:.3f}")
    print(f"      HOLD (1): {class_weight_dict[1]:.3f}")
    print(f"      BUY  (2): {class_weight_dict[2]:.3f}")

    # Step 7: Build model
    if CONFIG['model_type'] == 'tabnet':
        model = build_tabnet_model(input_dim=CONFIG['n_features'])
    elif CONFIG['model_type'] == 'transformer':
        model = build_transformer_model(input_dim=CONFIG['n_features'])
    else:
        raise ValueError(f"Unknown model_type: {CONFIG['model_type']}")

    model.summary()

    # Step 8: Train model with class weights (V12: natural data + gentle penalties)
    history = train_model(model, X_train, y_train, X_val, y_val, class_weight_dict=class_weight_dict)

    # Step 9: Evaluate model
    accuracy = evaluate_model(model, X_test, y_test)

    # Step 10: Export scaler
    export_scaler(scaler, CONFIG['output_dir'])

    # Step 11: Save model (will be quantized in next script)
    model_path = os.path.join(CONFIG['output_dir'], 'GodModel_v6.h5')
    model.save(model_path)
    print(f"\n✅ Model saved to: {model_path}")

    # Check if target accuracy achieved
    if accuracy >= 0.85:
        print(f"\n🎉 SUCCESS! Target accuracy ≥85% achieved: {accuracy*100:.2f}%")
    else:
        print(f"\n⚠️  Target accuracy not achieved. Got {accuracy*100:.2f}%, need ≥85%")
        print(f"   Consider:")
        print(f"   - Training longer (increase epochs)")
        print(f"   - Adding more data")
        print(f"   - Tuning hyperparameters")

    print(f"\n✅ Training complete! Next step: quantize to TFLite")
    print(f"   Run: python quantize_to_tflite.py")


if __name__ == '__main__':
    main()
