#!/bin/bash
# ============================================================================
# Train Missing BTC Models (4h and 1d)
# ============================================================================
# This script trains the btc_4h and btc_1d models that are missing.
# Uses the V14 Flutter-compatible training pipeline.
# ============================================================================

set -e

echo "============================================================================"
echo "🚀 Training Missing BTC Models"
echo "   - btc_4h (missing metadata)"
echo "   - btc_1d (missing metadata)"
echo "============================================================================"

# Install dependencies if needed
pip install -q ccxt pandas numpy scikit-learn tensorflow

# Train BTC 4h
echo ""
echo "📊 Training BTC 4h..."
python train_v14_flutter_compatible.py --coin BTC --timeframe 4h --epochs 50 --output trained_models

# Train BTC 1d
echo ""
echo "📊 Training BTC 1d..."
python train_v14_flutter_compatible.py --coin BTC --timeframe 1d --epochs 50 --output trained_models

echo ""
echo "============================================================================"
echo "✅ Training complete!"
echo "   Models saved to trained_models/"
echo ""
echo "📋 Copy to assets:"
echo "   cp trained_models/btc_4h_model.tflite ../assets/ml/"
echo "   cp trained_models/btc_4h_scaler.json ../assets/ml/"
echo "   cp trained_models/btc_4h_metadata.json ../assets/ml/"
echo "   cp trained_models/btc_1d_model.tflite ../assets/ml/"
echo "   cp trained_models/btc_1d_scaler.json ../assets/ml/"
echo "   cp trained_models/btc_1d_metadata.json ../assets/ml/"
echo "============================================================================"
