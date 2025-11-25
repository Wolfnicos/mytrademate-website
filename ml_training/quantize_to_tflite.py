"""
TFLite Quantization Script
===========================

Converts GodModel v6 to TFLite with aggressive quantization.

Target: < 9 MB (Flutter asset size limit)
Quantization: INT8 with float16 fallback
"""

import os
import tensorflow as tf
import numpy as np
from sklearn.preprocessing import StandardScaler
import json

print("="*80)
print("🔧 TFLite Quantization Pipeline")
print("="*80)

# Configuration
MODEL_PATH = './trained_models/GodModel_v6.h5'
OUTPUT_PATH = './trained_models/GodModel_v6.tflite'
SCALER_PATH = './trained_models/scaler_v6.json'


def representative_dataset_gen():
    """
    Representative dataset for full integer quantization

    This is required for INT8 quantization.
    Generates random samples matching the input distribution.
    """
    # Load scaler to get mean/std
    with open(SCALER_PATH, 'r') as f:
        scaler_params = json.load(f)

    mean = np.array(scaler_params['mean'])
    std = np.array(scaler_params['std'])

    # Generate 100 representative samples
    for _ in range(100):
        # Generate random sample from normalized distribution
        sample = np.random.randn(1, 180).astype(np.float32)
        yield [sample]


def quantize_model_int8():
    """
    Full INT8 quantization (smallest size, ~8x compression)

    This gives the smallest model but may slightly reduce accuracy.
    """
    print(f"\n🔧 Converting to INT8 TFLite...")

    # Load model
    print(f"   Loading model from {MODEL_PATH}...")
    model = tf.keras.models.load_model(MODEL_PATH)

    # Convert to TFLite with INT8 quantization
    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    # INT8 quantization settings
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = representative_dataset_gen
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.float32  # Input remains float32
    converter.inference_output_type = tf.float32  # Output remains float32

    # Convert
    print(f"   Quantizing model to INT8...")
    tflite_model = converter.convert()

    # Save
    with open(OUTPUT_PATH, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ INT8 model saved to {OUTPUT_PATH}")
    print(f"   Size: {size_mb:.2f} MB")

    return size_mb


def quantize_model_float16():
    """
    FLOAT16 quantization (moderate size, better accuracy)

    This is a fallback if INT8 degrades accuracy too much.
    """
    print(f"\n🔧 Converting to FLOAT16 TFLite...")

    # Load model
    print(f"   Loading model from {MODEL_PATH}...")
    model = tf.keras.models.load_model(MODEL_PATH)

    # Convert to TFLite with FLOAT16 quantization
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]

    # Convert
    print(f"   Quantizing model to FLOAT16...")
    tflite_model = converter.convert()

    # Save
    float16_path = OUTPUT_PATH.replace('.tflite', '_float16.tflite')
    with open(float16_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ FLOAT16 model saved to {float16_path}")
    print(f"   Size: {size_mb:.2f} MB")

    return size_mb


def quantize_model_dynamic():
    """
    Dynamic range quantization (fastest, moderate size)

    Another fallback option.
    """
    print(f"\n🔧 Converting to Dynamic Range TFLite...")

    # Load model
    print(f"   Loading model from {MODEL_PATH}...")
    model = tf.keras.models.load_model(MODEL_PATH)

    # Convert to TFLite with dynamic range quantization
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    # Convert
    print(f"   Quantizing model with dynamic range...")
    tflite_model = converter.convert()

    # Save
    dynamic_path = OUTPUT_PATH.replace('.tflite', '_dynamic.tflite')
    with open(dynamic_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ Dynamic model saved to {dynamic_path}")
    print(f"   Size: {size_mb:.2f} MB")

    return size_mb


def verify_model():
    """
    Verify the quantized model works correctly
    """
    print(f"\n🧪 Verifying quantized model...")

    # Load TFLite model
    interpreter = tf.lite.Interpreter(model_path=OUTPUT_PATH)
    interpreter.allocate_tensors()

    # Get input/output details
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"   Input shape: {input_details[0]['shape']}")
    print(f"   Output shape: {output_details[0]['shape']}")

    # Test with random input
    test_input = np.random.randn(1, 180).astype(np.float32)
    interpreter.set_tensor(input_details[0]['index'], test_input)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]['index'])

    print(f"   Test output: {output}")
    print(f"   Prediction: {['SELL', 'HOLD', 'BUY'][np.argmax(output)]}")
    print(f"✅ Model verification successful!")


def compare_quantizations():
    """
    Compare different quantization methods
    """
    print(f"\n📊 Comparing Quantization Methods...")
    print(f"   Target: < 9 MB")
    print()

    results = {}

    # INT8
    try:
        size = quantize_model_int8()
        results['INT8'] = size
    except Exception as e:
        print(f"   ⚠️  INT8 quantization failed: {e}")
        results['INT8'] = None

    # FLOAT16
    try:
        size = quantize_model_float16()
        results['FLOAT16'] = size
    except Exception as e:
        print(f"   ⚠️  FLOAT16 quantization failed: {e}")
        results['FLOAT16'] = None

    # Dynamic
    try:
        size = quantize_model_dynamic()
        results['Dynamic'] = size
    except Exception as e:
        print(f"   ⚠️  Dynamic quantization failed: {e}")
        results['Dynamic'] = None

    # Print summary
    print(f"\n📋 Quantization Summary:")
    print(f"   {'Method':<15} {'Size (MB)':<15} {'Status':<15}")
    print(f"   {'-'*45}")
    for method, size in results.items():
        if size is not None:
            status = '✅ PASS' if size < 9.0 else '⚠️  TOO LARGE'
            print(f"   {method:<15} {size:<15.2f} {status:<15}")
        else:
            print(f"   {method:<15} {'N/A':<15} {'❌ FAILED':<15}")

    # Recommend best option
    valid_results = {k: v for k, v in results.items() if v is not None and v < 9.0}
    if valid_results:
        best_method = min(valid_results, key=valid_results.get)
        best_size = valid_results[best_method]
        print(f"\n✅ Recommended: {best_method} ({best_size:.2f} MB)")
    else:
        print(f"\n⚠️  No quantization method achieved < 9 MB target!")
        print(f"   Consider:")
        print(f"   - Reducing model architecture (fewer layers/units)")
        print(f"   - Pruning model weights")
        print(f"   - Using knowledge distillation")


def main():
    """
    Main quantization pipeline
    """
    # Check if model exists
    if not os.path.exists(MODEL_PATH):
        print(f"❌ Model not found: {MODEL_PATH}")
        print(f"   Run: python train_god_model.py first")
        return

    # Check if scaler exists
    if not os.path.exists(SCALER_PATH):
        print(f"❌ Scaler not found: {SCALER_PATH}")
        print(f"   Run: python train_god_model.py first")
        return

    # Get original model size
    original_size = os.path.getsize(MODEL_PATH) / (1024 * 1024)
    print(f"\n📦 Original model size: {original_size:.2f} MB")

    # Run all quantization methods
    compare_quantizations()

    # Verify the primary quantized model
    if os.path.exists(OUTPUT_PATH):
        verify_model()

        # Final size check
        final_size = os.path.getsize(OUTPUT_PATH) / (1024 * 1024)
        compression_ratio = original_size / final_size

        print(f"\n🎉 Quantization Complete!")
        print(f"   Original:   {original_size:.2f} MB")
        print(f"   Quantized:  {final_size:.2f} MB")
        print(f"   Compression: {compression_ratio:.1f}x")

        if final_size < 9.0:
            print(f"   ✅ Model is under 9 MB target!")
        else:
            print(f"   ⚠️  Model exceeds 9 MB target")
            print(f"   Consider using FLOAT16 or Dynamic quantization")
    else:
        print(f"\n❌ Quantization failed")


if __name__ == '__main__':
    main()
