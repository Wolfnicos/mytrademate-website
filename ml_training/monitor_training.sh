#!/bin/bash
# Monitor GodModel v6 Training Progress
# =======================================

echo "=============================================="
echo "🔍 GodModel v6 Training Monitor"
echo "=============================================="
echo ""

# Check if Docker container is running
CONTAINER_ID=$(docker ps | grep godmodel-v6-trainer | awk '{print $1}')

if [ -z "$CONTAINER_ID" ]; then
    echo "❌ No training container found"
    echo ""
    echo "Check if training has:"
    echo "  1. Not started yet (still building image)"
    echo "  2. Already completed"
    echo "  3. Failed (check: docker ps -a)"
    echo ""

    # Check for completed containers
    STOPPED=$(docker ps -a | grep godmodel-v6-trainer | grep Exited)
    if [ ! -z "$STOPPED" ]; then
        echo "✅ Training container found (stopped)"
        echo "   Check if training completed successfully:"
        echo ""
        docker ps -a | grep godmodel-v6-trainer
    fi

    echo ""
    echo "📁 Check output files:"
    ls -lh trained_models/ 2>/dev/null || echo "   No trained_models directory yet"
    exit 0
fi

echo "✅ Training container found: $CONTAINER_ID"
echo ""

# Show live logs
echo "📊 Live Training Logs:"
echo "   (Press Ctrl+C to stop monitoring, training will continue)"
echo ""
echo "=============================================="
echo ""

# Follow logs with filtering for important messages
docker logs -f $CONTAINER_ID 2>&1 | grep -E "(Epoch|accuracy|loss|Fetched|Training|GodModel|SUCCESS|FAILED|Test Accuracy|✅|❌|🎉)" --line-buffered

# If logs stopped, check if training completed
echo ""
echo "=============================================="
echo "📁 Checking output files..."
echo ""

cd "$(dirname "$0")"
if [ -d "trained_models" ]; then
    echo "✅ Output directory exists:"
    ls -lh trained_models/
    echo ""

    if [ -f "trained_models/GodModel_v6.tflite" ]; then
        echo "🎉 GodModel_v6.tflite found!"
        echo "   Size: $(du -h trained_models/GodModel_v6.tflite | awk '{print $1}')"
        echo ""
        echo "✅ TRAINING COMPLETE!"
        echo ""
        echo "📋 Next steps:"
        echo "   1. Copy to Flutter:"
        echo "      cp trained_models/GodModel_v6.tflite ../assets/ml/"
        echo "      cp trained_models/scaler_v6.json ../assets/ml/"
        echo ""
        echo "   2. Update pubspec.yaml to include new assets"
        echo ""
        echo "   3. Test in Flutter:"
        echo "      flutter run"
        echo ""
    else
        echo "⏳ GodModel_v6.tflite not found yet"
        echo "   Training may still be in progress..."
    fi
else
    echo "⚠️  trained_models directory not found"
    echo "   Training may not have started yet"
fi

echo "=============================================="
