"""
SafeNetic Noise Pipeline - Model Inspection & TFLite Conversion
================================================================
Loads car_crash_detector_iphim.keras (MobileNetV2-based),
inspects its architecture, runs test inference,
and converts to TFLite with INT8 quantization.
"""

import sys
import os

os.environ['PYTHONIOENCODING'] = 'utf-8'
sys.stdout.reconfigure(encoding='utf-8')

import tensorflow as tf
import numpy as np
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).parent
KERAS_MODEL = SCRIPT_DIR / 'car_crash_detector_iphim.keras'
OUTPUT_TFLITE = SCRIPT_DIR / 'car_crash_detector.tflite'
APP_MODELS_DIR = SCRIPT_DIR.parent.parent / 'assets' / 'models'

def inspect_model(model):
    """Print detailed model info."""
    print("=" * 60)
    print("MODEL INSPECTION")
    print("=" * 60)
    print(f"  Name:       {model.name}")
    print(f"  Type:       {type(model).__name__}")
    print(f"  Input:      {model.input_shape}")
    print(f"  Output:     {model.output_shape}")
    print(f"  Params:     {model.count_params():,}")
    print()
    model.summary()


def test_inference(model):
    """Run test inference with random data matching model's expected input."""
    print("\n" + "=" * 60)
    print("TEST INFERENCE")
    print("=" * 60)

    input_shape = model.input_shape
    test_input = tf.random.uniform([1] + list(input_shape[1:]))
    output = model(test_input)

    print(f"  Input shape:  {test_input.shape}")
    print(f"  Output shape: {output.shape}")
    print(f"  Output value: {output.numpy()}")
    pred = output.numpy().flatten()[0]
    print(f"  Prediction:   {'DISTRESS' if pred > 0.5 else 'NORMAL'} ({pred:.4f})")
    return True


def convert_to_tflite(model):
    """Convert Keras model to TFLite with INT8 quantization."""
    print("\n" + "=" * 60)
    print("TFLITE CONVERSION")
    print("=" * 60)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    # Representative dataset for INT8 quantization
    input_shape = model.input_shape
    def rep_data():
        for _ in range(100):
            yield [np.random.uniform(0, 1, size=[1] + list(input_shape[1:])).astype(np.float32)]

    converter.representative_dataset = rep_data
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
        tf.lite.OpsSet.TFLITE_BUILTINS,
    ]
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32

    print("  Converting (this may take a minute)...")
    tflite_bytes = converter.convert()

    # Save to Noise model dir
    with open(str(OUTPUT_TFLITE), 'wb') as f:
        f.write(tflite_bytes)
    kb = len(tflite_bytes) / 1024
    print(f"  [OK] Saved: {OUTPUT_TFLITE}")
    print(f"  Size: {kb:.1f} KB ({kb/1024:.2f} MB)")

    # Verify TFLite model
    print("\n  Verifying TFLite model...")
    interp = tf.lite.Interpreter(model_path=str(OUTPUT_TFLITE))
    interp.allocate_tensors()
    inp = interp.get_input_details()
    out = interp.get_output_details()
    print(f"  TFLite input:  shape={inp[0]['shape']}, dtype={inp[0]['dtype']}")
    print(f"  TFLite output: shape={out[0]['shape']}, dtype={out[0]['dtype']}")

    # Quick inference test
    test_data = np.random.uniform(0, 1, size=inp[0]['shape']).astype(np.float32)
    interp.set_tensor(inp[0]['index'], test_data)
    interp.invoke()
    result = interp.get_tensor(out[0]['index'])
    print(f"  Test output:   {result.flatten()[0]:.4f}")

    return len(tflite_bytes)


def compare_with_existing():
    """Compare with the current noise_detection.tflite in the app."""
    print("\n" + "=" * 60)
    print("COMPARISON WITH EXISTING APP MODEL")
    print("=" * 60)

    existing = APP_MODELS_DIR / 'noise_detection.tflite'
    if not existing.exists():
        print(f"  Existing model not found at: {existing}")
        return

    existing_size = existing.stat().st_size
    print(f"  Existing model: {existing}")
    print(f"  Existing size:  {existing_size / 1024:.1f} KB")

    # Load existing model
    interp = tf.lite.Interpreter(model_path=str(existing))
    interp.allocate_tensors()
    inp = interp.get_input_details()
    out = interp.get_output_details()

    print(f"  Existing input:  shape={inp[0]['shape']}, dtype={inp[0]['dtype']}")
    print(f"  Existing output: shape={out[0]['shape']}, dtype={out[0]['dtype']}")

    # Load new model
    if OUTPUT_TFLITE.exists():
        new_size = OUTPUT_TFLITE.stat().st_size
        interp2 = tf.lite.Interpreter(model_path=str(OUTPUT_TFLITE))
        interp2.allocate_tensors()
        inp2 = interp2.get_input_details()
        out2 = interp2.get_output_details()

        print(f"\n  New model:      {OUTPUT_TFLITE}")
        print(f"  New size:       {new_size / 1024:.1f} KB")
        print(f"  New input:      shape={inp2[0]['shape']}, dtype={inp2[0]['dtype']}")
        print(f"  New output:     shape={out2[0]['shape']}, dtype={out2[0]['dtype']}")

        print("\n  --- COMPATIBILITY VERDICT ---")
        existing_in = tuple(inp[0]['shape'])
        new_in = tuple(inp2[0]['shape'])
        if existing_in == new_in:
            print("  [COMPATIBLE] Same input shape - can be a drop-in replacement!")
        else:
            print(f"  [INCOMPATIBLE] Input shapes differ:")
            print(f"    Existing: {existing_in}")
            print(f"    New:      {new_in}")
            print("  The app's AudioService extracts [40, 87, 1] FFT features.")
            print("  The new model expects [256, 256, 3] RGB spectrogram images.")
            print("  AudioService must be rewritten to use this model.")
    else:
        print("  New TFLite not yet created - run conversion first.")


def main():
    print("SafeNetic Noise Pipeline")
    print("=" * 60)

    if not KERAS_MODEL.exists():
        print(f"ERROR: Keras model not found: {KERAS_MODEL}")
        sys.exit(1)

    print(f"Loading: {KERAS_MODEL.name} ({KERAS_MODEL.stat().st_size / 1024 / 1024:.1f} MB)")
    model = tf.keras.models.load_model(str(KERAS_MODEL))

    # Step 1: Inspect
    inspect_model(model)

    # Step 2: Test inference
    test_inference(model)

    # Step 3: Convert to TFLite
    convert_to_tflite(model)

    # Step 4: Compare with existing app model
    compare_with_existing()

    print("\n" + "=" * 60)
    print("PIPELINE COMPLETE")
    print("=" * 60)


if __name__ == "__main__":
    main()
