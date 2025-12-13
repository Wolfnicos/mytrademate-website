#!/bin/bash
# GodModel v6 Training Script
# ============================
# One-command training with Docker

set -e  # Exit on error

echo "==============================================="
echo "🚀 GodModel v6 Training Pipeline"
echo "==============================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    echo "   Install from: https://www.docker.com/get-started"
    exit 1
fi

echo "📦 Building Docker image..."
docker build -t godmodel-v6-trainer .

echo ""
echo "🎯 Starting training..."
echo "   This may take several hours depending on your GPU"
echo ""

# Run training with GPU support (if available)
if docker run --gpus all --rm hello-world &> /dev/null; then
    echo "   ✅ GPU detected, using GPU acceleration"
    docker run --gpus all \
        -v "$(pwd)/trained_models:/training/trained_models" \
        godmodel-v6-trainer
else
    echo "   ⚠️  No GPU detected, using CPU (will be slower)"
    docker run \
        -v "$(pwd)/trained_models:/training/trained_models" \
        godmodel-v6-trainer
fi

echo ""
echo "==============================================="
echo "✅ Training Complete!"
echo "==============================================="
echo ""
echo "📦 Output files:"
echo "   ./trained_models/GodModel_v6.tflite"
echo "   ./trained_models/scaler_v6.json"
echo ""
echo "📋 Next steps:"
echo "   1. Copy GodModel_v6.tflite to Flutter: assets/ml/"
echo "   2. Copy scaler_v6.json to Flutter: assets/ml/"
echo "   3. Update ensemble_weights_v2.dart"
echo "   4. Test the app!"
echo ""
