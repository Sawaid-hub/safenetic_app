import sys, os
os.environ['PYTHONIOENCODING'] = 'utf-8'
sys.stdout.reconfigure(encoding='utf-8')

import tensorflow as tf

print("=" * 60)
print("MODEL COMPARISON")
print("=" * 60)

# Existing model
existing_path = r'E:\New folder\safenetic_app\assets\models\noise_detection.tflite'
interp = tf.lite.Interpreter(model_path=existing_path)
interp.allocate_tensors()
inp = interp.get_input_details()
out = interp.get_output_details()
size_kb = os.path.getsize(existing_path) / 1024

print(f"\nEXISTING (noise_detection.tflite):")
print(f"  Input:  shape={inp[0]['shape']}, dtype={inp[0]['dtype']}")
print(f"  Output: shape={out[0]['shape']}, dtype={out[0]['dtype']}")
print(f"  Size:   {size_kb:.1f} KB")

# New model
new_path = r'E:\New folder\safenetic_app\assets\Dataset\Noise model\car_crash_detector.tflite'
interp2 = tf.lite.Interpreter(model_path=new_path)
interp2.allocate_tensors()
inp2 = interp2.get_input_details()
out2 = interp2.get_output_details()
size_kb2 = os.path.getsize(new_path) / 1024

print(f"\nNEW (car_crash_detector.tflite):")
print(f"  Input:  shape={inp2[0]['shape']}, dtype={inp2[0]['dtype']}")
print(f"  Output: shape={out2[0]['shape']}, dtype={out2[0]['dtype']}")
print(f"  Size:   {size_kb2:.1f} KB ({size_kb2/1024:.2f} MB)")

print(f"\n--- VERDICT ---")
if tuple(inp[0]['shape']) == tuple(inp2[0]['shape']):
    print("COMPATIBLE - Same input shape, can drop-in replace!")
else:
    print("INCOMPATIBLE - Different input shapes")
    print(f"  Existing expects: {tuple(inp[0]['shape'])}")
    print(f"  New expects:      {tuple(inp2[0]['shape'])}")
    print(f"  Size diff:        {size_kb2/size_kb:.0f}x larger")
    print(f"\n  The app's AudioService extracts [40, 87] FFT features (mono).")
    print(f"  The new MobileNetV2 model expects [256, 256, 3] RGB spectrogram images.")
    print(f"  To use the new model, AudioService must be rewritten to produce")
    print(f"  spectrogram images instead of raw FFT feature matrices.")
