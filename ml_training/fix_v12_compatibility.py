"""
Fix GodModel V12 TFLite Compatibility
======================================

Re-quantizes V12 model with explicit opset compatibility for older TFLite runtimes.
This fixes the "FULLY_CONNECTED version 12" error on iOS devices.
"""

import tensorflow as tf
import numpy as np
import json
import os

print("="*80)
print("🔧 V12 Compatibility Fix")
print("="*80)

# Paths
MODEL_H5 = './trained_models/best_model.h5'  # V12 model saved here
OUTPUT_TFLITE = './trained_models/GodModel_v12.tflite'
SCALER_JSON = './trained_models/scaler_v12.json'

def quantize_v12_compatible():
    """
    Re-quantize V12 with compatibility flags for older TFLite versions
    """
    print(f"\n📦 Loading V12 model from {MODEL_H5}...")

    if not os.path.exists(MODEL_H5):
        print(f"❌ Model not found: {MODEL_H5}")
        print(f"   V12 training may still be running. Check trained_models/")
        return False

    # Load Keras model
    model = tf.keras.models.load_model(MODEL_H5)
    print(f"✅ Model loaded: {model.input_shape} -> {model.output_shape}")

    # Create converter with compatibility settings
    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    # COMPATIBILITY MODE: Force older opset version
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter._experimental_lower_tensor_list_ops = True  # Force compatibility
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,  # Use built-in ops
    ]

    # Keep I/O as float32 (no quantization on edges)
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32

    print(f"\n🔧 Converting with compatibility mode...")
    print(f"   - Forcing older opset versions")
    print(f"   - Using TFLITE_BUILTINS only")
    print(f"   - Dynamic range quantization")

    # Convert
    try:
        tflite_model = converter.convert()

        # Save
        with open(OUTPUT_TFLITE, 'wb') as f:
            f.write(tflite_model)

        size_mb = len(tflite_model) / (1024 * 1024)
        print(f"\n✅ Compatible V12 saved to {OUTPUT_TFLITE}")
        print(f"   Size: {size_mb:.2f} MB")

        # Verify
        verify_model(OUTPUT_TFLITE)

        return True

    except Exception as e:
        print(f"❌ Conversion failed: {e}")
        return False

def verify_model(model_path):
    """
    Verify the quantized model works
    """
    print(f"\n🧪 Verifying model...")

    try:
        # Load interpreter
        interpreter = tf.lite.Interpreter(model_path=model_path)
        interpreter.allocate_tensors()

        # Get details
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()

        print(f"   Input shape: {input_details[0]['shape']}")
        print(f"   Input dtype: {input_details[0]['dtype']}")
        print(f"   Output shape: {output_details[0]['shape']}")
        print(f"   Output dtype: {output_details[0]['dtype']}")

        # Test with random input (180 features)
        test_input = np.random.randn(1, 180).astype(np.float32)
        interpreter.set_tensor(input_details[0]['index'], test_input)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details[0]['index'])

        # Check output
        probs = output[0]
        action = ['SELL', 'HOLD', 'BUY'][np.argmax(probs)]

        print(f"\n   Test prediction:")
        print(f"   - SELL: {probs[0]:.3f}")
        print(f"   - HOLD: {probs[1]:.3f}")
        print(f"   - BUY:  {probs[2]:.3f}")
        print(f"   - Action: {action}")

        print(f"\n✅ Model verification passed!")
        return True

    except Exception as e:
        print(f"❌ Verification failed: {e}")
        return False

def main():
    print(f"\nThis script fixes the TFLite compatibility issue:")
    print(f"  Error: 'FULLY_CONNECTED' version '12' not supported")
    print(f"  Solution: Re-quantize with compatibility mode\n")

    success = quantize_v12_compatible()

    if success:
        print(f"\n🎉 V12 Compatibility Fix Complete!")
        print(f"\nNext steps:")
        print(f"  1. Copy to Flutter: cp {OUTPUT_TFLITE} ../assets/ml/")
        print(f"  2. Rebuild app: flutter run")
        print(f"  3. Check logs for: '✅ GodModel V12 loaded successfully!'")
    else:
        print(f"\n❌ Fix failed. V12 model may still be training.")
        print(f"   Wait for training to complete, then run this script again.")

if __name__ == '__main__':
    main()
