#!/bin/bash
# Train V12 with TensorFlow 2.11 for iOS Compatibility
# =====================================================

set -e  # Exit on error

echo "════════════════════════════════════════════════════════════════"
echo "🔧 V12 iOS Compatible Training"
echo "════════════════════════════════════════════════════════════════"
echo ""

cd "$(dirname "$0")"

# Check if venv exists
if [ ! -d "venv_tf211" ]; then
    echo "📦 Creating Python 3.11 virtual environment with TF 2.11..."
    python3.11 -m venv venv_tf211

    echo "📥 Installing TensorFlow 2.11.1 (iOS compatible)..."
    ./venv_tf211/bin/pip install --upgrade pip
    ./venv_tf211/bin/pip install \
        tensorflow==2.11.1 \
        numpy==1.23.5 \
        pandas==2.0.3 \
        scikit-learn==1.3.0 \
        ccxt>=2.0.0 \
        tqdm==4.66.1

    echo "✅ Environment ready!"
else
    echo "✅ Using existing venv_tf211"
fi

echo ""
echo "🚀 Starting V12 training with TF 2.11..."
echo "   This will take ~2-3 minutes on M4 Pro"
echo ""

# Run training with TF 2.11
./venv_tf211/bin/python3 train_god_model.py

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ V12 iOS Compatible Training Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📁 Output files:"
ls -lh trained_models/GodModel_v12* trained_models/scaler_v12.json 2>/dev/null || echo "   ⚠️  Files not found"
echo ""
echo "🔄 Next steps:"
echo "   1. cp trained_models/GodModel_v12.tflite ../assets/ml/"
echo "   2. flutter run"
echo ""
