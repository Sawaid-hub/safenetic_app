"""
SafeNetic Noise Model Training  (pandas-free)
==============================================
Trains a 2D CNN on [40, 87] FFT features from noise_dataset.npz.
Same architecture as original noise_detection.tflite:
  Input:  [1, 40, 87, 1]   (sigmoid)
  Output: [1, 1]

Run:
  python assets/Dataset/scripts/train_noise_model.py
"""

import sys
import numpy as np
from pathlib import Path

SCRIPT_DIR   = Path(__file__).parent
DATASET_DIR  = SCRIPT_DIR.parent
PROJECT_DIR  = DATASET_DIR.parent.parent   # safenetic_app root
INPUT_NPZ    = DATASET_DIR / "noise_dataset.npz"
MODEL_DIR    = PROJECT_DIR / "assets" / "models"
OUTPUT_TFLITE = MODEL_DIR / "noise_detection.tflite"

EPOCHS     = 30
BATCH_SIZE = 32
VAL_SPLIT  = 0.2
SEED       = 42


def build_model(input_shape=(40, 87, 1)):
    import tensorflow as tf
    keras = tf.keras
    model = keras.Sequential([
        keras.layers.Input(shape=input_shape),
        keras.layers.Conv2D(16, (3,3), padding='same', activation='relu'),
        keras.layers.BatchNormalization(),
        keras.layers.MaxPooling2D((2,2)),
        keras.layers.Dropout(0.25),
        keras.layers.Conv2D(32, (3,3), padding='same', activation='relu'),
        keras.layers.BatchNormalization(),
        keras.layers.MaxPooling2D((2,2)),
        keras.layers.Dropout(0.25),
        keras.layers.Conv2D(64, (3,3), padding='same', activation='relu'),
        keras.layers.BatchNormalization(),
        keras.layers.GlobalAveragePooling2D(),
        keras.layers.Dropout(0.5),
        keras.layers.Dense(64, activation='relu'),
        keras.layers.Dropout(0.3),
        keras.layers.Dense(1, activation='sigmoid'),
    ], name='noise_detector_v2')
    return model


def train():
    print("=" * 60)
    print("SafeNetic Noise Model Training")
    print("=" * 60)

    if not INPUT_NPZ.exists():
        print(f"ERROR: Dataset not found: {INPUT_NPZ}")
        print("Run prepare_noise_dataset.py first.")
        sys.exit(1)

    print(f"\nLoading dataset...")
    data = np.load(str(INPUT_NPZ))
    X = data['X_features'][..., np.newaxis].astype(np.float32)  # [N,40,87,1]
    y = data['y_labels'].astype(np.float32)

    # Normalize
    X_max = X.max()
    if X_max > 0:
        X /= X_max

    print(f"  X shape: {X.shape}  |  y shape: {y.shape}")
    print(f"  Distress: {int(np.sum(y==1))}  |  Normal: {int(np.sum(y==0))}")

    # Train/val split (manual, no pandas)
    import tensorflow as tf
    from sklearn.model_selection import train_test_split

    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=VAL_SPLIT, random_state=SEED, stratify=y
    )
    print(f"  Train: {len(X_train)}  |  Val: {len(X_val)}")

    model = build_model()
    model.summary()

    n_pos = int(np.sum(y_train == 1))
    n_neg = int(np.sum(y_train == 0))
    class_weight = {0: 1.0, 1: n_neg / max(n_pos, 1)}
    print(f"\nClass weights: {class_weight}")

    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss='binary_crossentropy',
        metrics=['accuracy', tf.keras.metrics.AUC(name='auc')],
    )

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_auc', patience=6,
            restore_best_weights=True, mode='max'
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss', patience=3, factor=0.5, min_lr=1e-6
        ),
    ]

    print(f"\nTraining (up to {EPOCHS} epochs)...")
    model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        class_weight=class_weight,
        callbacks=callbacks,
        verbose=1,
    )

    loss, acc, auc = model.evaluate(X_val, y_val, verbose=0)
    print(f"\nFinal Val -> Loss: {loss:.4f}  Acc: {acc*100:.1f}%  AUC: {auc:.4f}")

    # ── Convert to TFLite ─────────────────────────────────────────────────────
    print("\nConverting to TFLite (INT8 quantization)...")
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    def rep_data():
        for i in range(min(200, len(X_train))):
            yield [X_train[i:i+1]]

    converter.representative_dataset = rep_data
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
        tf.lite.OpsSet.TFLITE_BUILTINS,
    ]
    converter.inference_input_type  = tf.float32
    converter.inference_output_type = tf.float32

    tflite_bytes = converter.convert()
    with open(str(OUTPUT_TFLITE), 'wb') as f:
        f.write(tflite_bytes)

    kb = len(tflite_bytes) / 1024
    print(f"[OK] Saved: {OUTPUT_TFLITE}  ({kb:.1f} KB)")

    # ── Verify ────────────────────────────────────────────────────────────────
    interp = tf.lite.Interpreter(model_path=str(OUTPUT_TFLITE))
    interp.allocate_tensors()
    inp = interp.get_input_details()
    out = interp.get_output_details()
    print(f"\nTFLite input  shape: {inp[0]['shape']}")
    print(f"TFLite output shape: {out[0]['shape']}")

    # Quick sanity: 5 samples
    correct = 0
    for i in range(min(5, len(X_val))):
        interp.set_tensor(inp[0]['index'], X_val[i:i+1])
        interp.invoke()
        pred  = interp.get_tensor(out[0]['index'])[0][0]
        label = int(y_val[i])
        ok    = (pred > 0.5) == bool(label)
        correct += int(ok)
        name  = 'distress' if label == 1 else 'normal'
        print(f"  Sample {i+1}: {name} pred={pred:.3f} {'CORRECT' if ok else 'WRONG'}")

    print(f"  Quick check: {correct}/5")
    print(f"\n{'='*60}")
    print("MODEL READY — connect Android device and run: flutter run")
    print(f"{'='*60}")


if __name__ == "__main__":
    train()
