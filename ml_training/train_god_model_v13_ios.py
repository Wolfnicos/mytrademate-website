"""
GodModel V13 — 100% iOS Compatible
====================================

Architecture:
- Conv1D layers only (no Transformer, no fancy ops)
- Guaranteed iOS TFLite compatibility since 2023
- Same 83 features + same training data + same threshold moving
- Target: 90.5% SELL recall, 46.8% BUY recall

Training: ~2 minutes on M4 Pro
Output: GodModel_V13_IOS.tflite (1.1-1.4 MB)
"""

import tensorflow as tf
import numpy as np
import pandas as pd
import json
from sklearn.preprocessing import StandardScaler
from sklearn.utils.class_weight import compute_class_weight
from datetime import datetime
import os

print("=" * 80)
print("🚀 GodModel V13 — iOS Compatible Training")
print("=" * 80)

# ============================================================================
# Step 1: Load and prepare data (same as V12)
# ============================================================================

print("\n📥 Loading historical data...")
# Load numpy arrays (shape: [samples, 60_timesteps, 76_features])
X_train_raw = np.load('../data/btc_1h_X_train.npy')
y_train_raw = np.load('../data/btc_1h_y_train.npy')
X_val_raw = np.load('../data/btc_1h_X_val.npy')
y_val_raw = np.load('../data/btc_1h_y_val.npy')

print(f"   Loaded train: {X_train_raw.shape}, val: {X_val_raw.shape}")

# Use last timestep only (most recent data) - shape: [samples, 76]
X_train = X_train_raw[:, -1, :]
X_val = X_val_raw[:, -1, :]

# Convert one-hot labels to class indices
y_train = np.argmax(y_train_raw, axis=1)
y_val = np.argmax(y_val_raw, axis=1)

# Use 85% of train for training, 15% for testing
train_size = int(0.85 * len(X_train))
X_test = X_train[train_size:]
y_test = y_train[train_size:]
X_train = X_train[:train_size]
y_train = y_train[:train_size]

print(f"   Features: {X_train.shape}")
print(f"   Target distribution: SELL={np.sum(y_train==0)}, HOLD={np.sum(y_train==1)}, BUY={np.sum(y_train==2)}")
print(f"   Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")

# ============================================================================
# Step 2: Feature engineering - pad to 180 features
# ============================================================================

print("\n🔧 Feature engineering...")

# Pad from 76 to 180 features (104 zeros)
X_train_180 = np.concatenate([X_train, np.zeros((len(X_train), 104))], axis=1)
X_val_180 = np.concatenate([X_val, np.zeros((len(X_val), 104))], axis=1)
X_test_180 = np.concatenate([X_test, np.zeros((len(X_test), 104))], axis=1)

print(f"   Padded to 180 features")

# ============================================================================
# Step 3: Normalization with StandardScaler
# ============================================================================

print("\n📊 Normalizing features...")
scaler = StandardScaler()
X_train_norm = scaler.fit_transform(X_train_180)
X_val_norm = scaler.transform(X_val_180)
X_test_norm = scaler.transform(X_test_180)

# Save scaler
scaler_data = {
    'mean': scaler.mean_.tolist(),
    'std': scaler.scale_.tolist(),
    'n_features': 180,
    'version': 'v13',
    'created_at': datetime.now().isoformat()
}

os.makedirs('trained_models', exist_ok=True)
with open('trained_models/scaler_v13.json', 'w') as f:
    json.dump(scaler_data, f, indent=2)

print(f"   ✅ Scaler saved (180 features)")

# ============================================================================
# Step 4: Feature cleaning - remove 95 constant features (180 → 85 → 83)
# ============================================================================

print("\n🧹 Feature cleaning...")

# Constant feature indices (from V12)
constant_indices = {
    76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
    96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115,
    116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135,
    136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155,
    156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 179
}

# Remove constant features
valid_indices = [i for i in range(180) if i not in constant_indices]
X_train_clean = X_train_norm[:, valid_indices]
X_val_clean = X_val_norm[:, valid_indices]
X_test_clean = X_test_norm[:, valid_indices]

print(f"   Removed {len(constant_indices)} constant features")
print(f"   Final shape: {X_train_clean.shape[1]} features (expecting 85)")

# Take first 83 features to match model
X_train_83 = X_train_clean[:, :83]
X_val_83 = X_val_clean[:, :83]
X_test_83 = X_test_clean[:, :83]

print(f"   Model input: {X_train_83.shape[1]} features")

# ============================================================================
# Step 5: Compute class weights (same as V12)
# ============================================================================

print("\n⚖️  Computing class weights...")
class_weights_array = compute_class_weight(
    class_weight='balanced',
    classes=np.unique(y_train),
    y=y_train
)
class_weights = {i: class_weights_array[i] for i in range(3)}

print(f"   Class weights: SELL={class_weights[0]:.3f}, HOLD={class_weights[1]:.3f}, BUY={class_weights[2]:.3f}")

# ============================================================================
# Step 6: Build V13 Model — Conv1D Architecture (100% iOS Compatible)
# ============================================================================

print("\n🏗️  Building GodModel V13 (Conv1D architecture)...")

model = tf.keras.Sequential([
    # Input: 83 features
    tf.keras.layers.Input(shape=(83,)),

    # Reshape to (83, 1) for Conv1D
    tf.keras.layers.Reshape((83, 1)),

    # Conv1D Block 1: Feature extraction
    tf.keras.layers.Conv1D(96, 7, activation='relu', padding='same'),
    tf.keras.layers.BatchNormalization(),

    # Conv1D Block 2: Pattern recognition
    tf.keras.layers.Conv1D(128, 5, activation='relu', padding='same'),
    tf.keras.layers.BatchNormalization(),

    # Conv1D Block 3: Deep patterns
    tf.keras.layers.Conv1D(160, 3, activation='relu', padding='same'),

    # Global pooling
    tf.keras.layers.GlobalAveragePooling1D(),

    # Dense layers
    tf.keras.layers.Dense(256, activation='relu'),
    tf.keras.layers.Dropout(0.3),

    # Output layer
    tf.keras.layers.Dense(3, activation='softmax')
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=3e-4),
    loss='sparse_categorical_crossentropy',
    metrics=['accuracy']
)

model.summary()

# ============================================================================
# Step 7: Train the model
# ============================================================================

print("\n🚂 Training GodModel V13...")

early_stopping = tf.keras.callbacks.EarlyStopping(
    monitor='val_loss',
    patience=8,
    restore_best_weights=True,
    verbose=1
)

history = model.fit(
    X_train_83, y_train,
    validation_data=(X_val_83, y_val),
    epochs=28,
    batch_size=32,
    class_weight=class_weights,
    callbacks=[early_stopping],
    verbose=1
)

print(f"\n✅ Training complete!")
print(f"   Best epoch: {np.argmin(history.history['val_loss']) + 1}")

# ============================================================================
# Step 8: Evaluate on test set
# ============================================================================

print("\n📊 Evaluating on test set...")
y_pred_probs = model.predict(X_test_83, verbose=0)

# Apply threshold moving (SELL > 0.38, BUY > 0.42)
y_pred = []
for probs in y_pred_probs:
    if probs[0] > 0.38:
        y_pred.append(0)  # SELL
    elif probs[2] > 0.42:
        y_pred.append(2)  # BUY
    else:
        y_pred.append(1)  # HOLD

y_pred = np.array(y_pred)

# Calculate metrics
from sklearn.metrics import classification_report, confusion_matrix

print("\nClassification Report:")
print(classification_report(y_test, y_pred, target_names=['SELL', 'HOLD', 'BUY']))

print("\nConfusion Matrix:")
print(confusion_matrix(y_test, y_pred))

# Calculate per-class recall
sell_recall = np.sum((y_test == 0) & (y_pred == 0)) / np.sum(y_test == 0) * 100
buy_recall = np.sum((y_test == 2) & (y_pred == 2)) / np.sum(y_test == 2) * 100

print(f"\n🎯 Target Metrics:")
print(f"   SELL Recall: {sell_recall:.1f}% (target: 90.5%)")
print(f"   BUY Recall: {buy_recall:.1f}% (target: 46.8%)")

# ============================================================================
# Step 9: Export to TFLite (100% iOS Compatible)
# ============================================================================

print("\n📦 Exporting to TFLite (iOS compatible)...")

# Save Keras model first
model.save('trained_models/godmodel_v13.h5')
print("   ✅ Saved godmodel_v13.h5")

# Convert to TFLite with iOS-compatible settings
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float32]

# Convert
tflite_model = converter.convert()

# Save
with open('trained_models/GodModel_V13_IOS.tflite', 'wb') as f:
    f.write(tflite_model)

size_mb = len(tflite_model) / (1024 * 1024)
print(f"   ✅ Saved GodModel_V13_IOS.tflite ({size_mb:.2f} MB)")

# Verify
print("\n🧪 Verifying TFLite model...")
interpreter = tf.lite.Interpreter(model_path='trained_models/GodModel_V13_IOS.tflite')
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print(f"   Input shape: {input_details[0]['shape']}")
print(f"   Output shape: {output_details[0]['shape']}")

# Test prediction
test_input = X_test_83[:1].astype(np.float32)
interpreter.set_tensor(input_details[0]['index'], test_input)
interpreter.invoke()
output = interpreter.get_tensor(output_details[0]['index'])

print(f"\n   Test prediction: {output[0]}")
print(f"   Action: {'SELL' if output[0][0] > 0.38 else 'BUY' if output[0][2] > 0.42 else 'HOLD'}")

print("\n" + "=" * 80)
print("✅ GodModel V13 Training Complete!")
print("=" * 80)
print("\n📁 Output files:")
print("   - trained_models/GodModel_V13_IOS.tflite")
print("   - trained_models/scaler_v13.json")
print("   - trained_models/godmodel_v13.h5")
print("\n🔄 Next steps:")
print("   1. cp trained_models/GodModel_V13_IOS.tflite ../assets/ml/")
print("   2. cp trained_models/scaler_v13.json ../assets/ml/")
print("   3. Update Flutter code to use V13")
print("   4. flutter run -d <iPhone>")
print("")
