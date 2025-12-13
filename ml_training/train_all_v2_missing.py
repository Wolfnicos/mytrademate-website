#!/usr/bin/env python3
"""
Train ALL missing V2 models (1h, 15m, 5m) for BTC, ETH, SOL, BNB.
Uses train_v2025_pro.py as base.

Run: python3 train_all_v2_missing.py
"""

import os
import sys
import subprocess
import time

# Models to train
COINS = ['BTC', 'ETH', 'SOL', 'BNB']
TIMEFRAMES = ['1h', '15m', '5m']  # Missing timeframes

# Check what we already have
def get_existing_models():
    assets_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'ml')
    existing = []
    for f in os.listdir(assets_dir):
        if f.endswith('_v2.tflite'):
            existing.append(f.replace('.tflite', ''))
    return existing

def main():
    print("=" * 60)
    print("TRAINING ALL MISSING V2 MODELS")
    print("=" * 60)

    existing = get_existing_models()
    print(f"\nExisting V2 models: {existing}")

    # Determine what to train
    to_train = []
    for coin in COINS:
        for tf in TIMEFRAMES:
            model_name = f"{coin.lower()}_{tf}_v2"
            if model_name not in existing:
                to_train.append((coin, tf))
            else:
                print(f"  Skip {model_name} - already exists")

    print(f"\nModels to train: {len(to_train)}")
    for coin, tf in to_train:
        print(f"  - {coin}_{tf}_v2")

    if not to_train:
        print("\nAll models already exist!")
        return

    # Train each model
    results = {}
    script_path = os.path.join(os.path.dirname(__file__), 'train_v2025_pro.py')

    for i, (coin, tf) in enumerate(to_train):
        print(f"\n{'='*60}")
        print(f"[{i+1}/{len(to_train)}] Training {coin}_{tf}_v2")
        print(f"{'='*60}")

        start_time = time.time()

        try:
            result = subprocess.run(
                [sys.executable, script_path, '--coin', coin, '--timeframe', tf, '--epochs', '300'],
                capture_output=False,
                text=True
            )

            elapsed = time.time() - start_time
            results[f"{coin}_{tf}"] = {
                'status': 'SUCCESS' if result.returncode == 0 else 'FAILED',
                'time': elapsed
            }

        except Exception as e:
            results[f"{coin}_{tf}"] = {'status': f'ERROR: {e}', 'time': 0}

    # Summary
    print("\n" + "=" * 60)
    print("TRAINING SUMMARY")
    print("=" * 60)

    for model, info in results.items():
        print(f"  {model}_v2: {info['status']} ({info['time']:.1f}s)")

    # List all V2 models now
    print("\n" + "=" * 60)
    print("ALL V2 MODELS")
    print("=" * 60)

    for model in sorted(get_existing_models()):
        print(f"  ✅ {model}.tflite")

if __name__ == '__main__':
    main()
