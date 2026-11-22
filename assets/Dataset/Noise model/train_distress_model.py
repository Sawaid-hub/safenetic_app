"""
SafeNetic Distress Sound Detector — Full Training Pipeline
==========================================================
Trains a MobileNetV2 on mel-spectrogram images (256×256×3) for binary
distress sound detection.

Distress classes (Label 1): car_crash, gun_shot, scream
Normal  class   (Label 0): Synthetic ambient / noise / silence

Audio → Mel Spectrogram Image → MobileNetV2 (transfer learning) → TFLite

Run:
  python "assets/Dataset/Noise model/train_distress_model.py"
"""

import sys
import os

os.environ['PYTHONIOENCODING'] = 'utf-8'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
sys.stdout.reconfigure(encoding='utf-8')

import numpy as np
import random
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR    = Path(__file__).parent
DATASET_DIR   = SCRIPT_DIR.parent
ASSETS_DIR    = DATASET_DIR.parent

# Distress audio folders
DISTRESS_DIRS = {
    'car_crash': SCRIPT_DIR / 'car_crash',
    'gun_shot':  SCRIPT_DIR / 'gun_shot',
    'scream':    SCRIPT_DIR / 'scream',
}

# Output
MODEL_DIR     = ASSETS_DIR / 'models'
OUTPUT_KERAS  = SCRIPT_DIR / 'distress_detector.keras'
OUTPUT_TFLITE = MODEL_DIR / 'noise_detection.tflite'

# ── Audio Parameters (must match AudioService.dart) ───────────────────────────
SAMPLE_RATE    = 16000
CLIP_DURATION  = 2.0
N_SAMPLES      = int(SAMPLE_RATE * CLIP_DURATION)  # 32000
N_FFT          = 1024
HOP_LENGTH     = 125
N_MELS         = 256
IMG_SIZE       = 256  # 256×256 spectrogram images

# ── Training Config ───────────────────────────────────────────────────────────
EPOCHS         = 15
BATCH_SIZE     = 16
VAL_SPLIT      = 0.2
SEED           = 42
AUGMENTATIONS  = 3  # Augmented copies per distress clip

random.seed(SEED)
np.random.seed(SEED)


# ===========================================================================
# AUDIO LOADING
# ===========================================================================

def load_audio_librosa(wav_path, sr=SAMPLE_RATE, duration=CLIP_DURATION):
    """Load audio, resample, pad/truncate to fixed length."""
    import librosa
    try:
        audio, _ = librosa.load(str(wav_path), sr=sr, mono=True)
        if len(audio) < N_SAMPLES:
            audio = np.pad(audio, (0, N_SAMPLES - len(audio)))
        elif len(audio) > N_SAMPLES:
            # Random crop for variety
            start = random.randint(0, len(audio) - N_SAMPLES)
            audio = audio[start:start + N_SAMPLES]
        return audio.astype(np.float32)
    except Exception as e:
        print(f"  [SKIP] {wav_path.name}: {e}")
        return None


# ===========================================================================
# MEL SPECTROGRAM (matches AudioService.dart pipeline exactly)
# ===========================================================================

def audio_to_spectrogram_image(audio, sr=SAMPLE_RATE):
    """
    Convert audio → mel spectrogram image [IMG_SIZE, IMG_SIZE, 3].
    Exactly replicates Flutter AudioService.dart logic so inference matches training.
    """
    # Time parameters
    n_fft = N_FFT
    hop_length = HOP_LENGTH
    n_mels = N_MELS
    n_bins = n_fft // 2 + 1
    
    # 1. Hamming window logic exactly matching Dart
    i = np.arange(n_fft)
    window = 0.54 - 0.46 * np.cos(2 * np.pi * i / (n_fft - 1))
    
    # 2. Mel filterbank (HTK formula, no area normalization)
    def hz_to_mel(hz): return 2595.0 * np.log10(1.0 + hz / 700.0)
    def mel_to_hz(mel): return 700.0 * (10.0**(mel / 2595.0) - 1.0)
    
    mel_pts = np.linspace(hz_to_mel(0.0), hz_to_mel(sr / 2.0), n_mels + 2)
    hz_pts = mel_to_hz(mel_pts)
    bins = np.floor((n_fft + 1) * hz_pts / sr).astype(int)
    
    filterbank = np.zeros((n_mels, n_bins))
    for m in range(n_mels):
        low, center, high = bins[m], bins[m+1], bins[m+2]
        if center > low:
            filterbank[m, low:center] = (np.arange(low, center) - low) / (center - low)
        if high > center:
            filterbank[m, center:high] = (high - np.arange(center, high)) / (high - center)
            
    # 3. Process frames (no padding, match Dart exactly)
    mel_frames = []
    for i in range(0, len(audio) - n_fft + 1, hop_length):
        w_audio = audio[i:i+n_fft] * window
        sp = np.fft.rfft(w_audio)
        power = np.real(sp)**2 + np.imag(sp)**2
        mel_frames.append(np.dot(filterbank, power))
        
    if not mel_frames:
        return np.zeros((IMG_SIZE, IMG_SIZE, 3), dtype=np.float32)
        
    # 4. Log-dB scale
    mel_frames = np.array(mel_frames).T  # shape [n_mels, n_frames]
    spectrogram = np.full_like(mel_frames, -100.0)
    mask = mel_frames > 1e-10
    spectrogram[mask] = 10.0 * np.log10(mel_frames[mask])
    
    # 5. Min-Max normalization
    min_val = spectrogram.min()
    max_val = spectrogram.max()
    range_val = max_val - min_val
    
    if range_val > 0:
        s_norm = (spectrogram - min_val) / range_val
    else:
        s_norm = np.zeros_like(spectrogram)
        
    s_norm = np.clip(s_norm, 0.0, 1.0)
    
    # 6. Resize nearest-neighbor & RGB
    s_norm = s_norm[::-1, :]  # Highest freq on top
    
    from PIL import Image
    img = Image.fromarray((s_norm * 255).astype(np.uint8), mode='L')
    img = img.resize((IMG_SIZE, IMG_SIZE), Image.NEAREST)
    img_arr = np.array(img).astype(np.float32) / 255.0
    
    img_3ch = np.stack([img_arr, img_arr, img_arr], axis=-1)
    return img_3ch


# ===========================================================================
# AUGMENTATION
# ===========================================================================

def build_augment_pipeline():
    """Build audiomentations pipeline for data augmentation."""
    try:
        from audiomentations import (
            Compose, OneOf,
            AddGaussianNoise, TimeStretch, PitchShift,
            Shift, Gain, LowPassFilter, HighPassFilter,
            ClippingDistortion,
        )
        return Compose([
            AddGaussianNoise(min_amplitude=0.001, max_amplitude=0.015, p=0.7),
            PitchShift(min_semitones=-4, max_semitones=4, p=0.6),
            TimeStretch(min_rate=0.8, max_rate=1.2, p=0.5),
            Shift(min_shift=-0.5, max_shift=0.5, p=0.5),
            Gain(min_gain_db=-6, max_gain_db=6, p=0.7),
            OneOf([
                LowPassFilter(min_cutoff_freq=2000.0, max_cutoff_freq=8000.0, p=1.0),
                HighPassFilter(min_cutoff_freq=100.0, max_cutoff_freq=1500.0, p=1.0),
            ], p=0.4),
            ClippingDistortion(min_percentile_threshold=0, max_percentile_threshold=15, p=0.3),
        ])
    except ImportError:
        print("  [WARN] audiomentations not installed. Using basic augmentation.")
        return None


def basic_augment(audio, sr=SAMPLE_RATE):
    """Basic augmentation fallback when audiomentations is not available."""
    aug = audio.copy()
    # Random noise
    if random.random() > 0.3:
        noise = np.random.normal(0, random.uniform(0.001, 0.01), len(aug))
        aug = aug + noise.astype(np.float32)
    # Random gain
    if random.random() > 0.3:
        gain = random.uniform(0.5, 1.5)
        aug = aug * gain
    # Random shift
    if random.random() > 0.5:
        shift = random.randint(-int(sr * 0.3), int(sr * 0.3))
        aug = np.roll(aug, shift)
    return np.clip(aug, -1.0, 1.0).astype(np.float32)


# ===========================================================================
# SYNTHETIC NEGATIVE SAMPLES
# ===========================================================================

def generate_synthetic_negatives(n_samples):
    """
    Generate synthetic 'normal' audio samples:
    - Silence with low background noise
    - Pink/brown noise (simulates ambient environments)
    - Random sine waves (machinery hum, traffic drone)
    - Mixed ambient (wind-like broadband noise)
    """
    print(f"\n[NEGATIVE] Generating {n_samples} synthetic normal samples...")
    negatives = []

    for i in range(n_samples):
        choice = random.choice(['silence', 'pink', 'brown', 'hum', 'ambient'])

        if choice == 'silence':
            # Near-silence with faint noise
            audio = np.random.normal(0, random.uniform(0.0005, 0.005), N_SAMPLES).astype(np.float32)

        elif choice == 'pink':
            # Pink noise (1/f)
            white = np.random.randn(N_SAMPLES)
            # Simple pink noise approximation via cumulative filter
            from scipy.signal import lfilter
            b = [0.049922035, -0.095993537, 0.050612699, -0.004709510]
            a = [1.0, -2.494956002, 2.017265875, -0.522189400]
            pink = lfilter(b, a, white).astype(np.float32)
            pink = pink / (np.abs(pink).max() + 1e-8) * random.uniform(0.1, 0.4)
            audio = pink

        elif choice == 'brown':
            # Brown noise (random walk)
            audio = np.cumsum(np.random.randn(N_SAMPLES)).astype(np.float32)
            audio = audio / (np.abs(audio).max() + 1e-8) * random.uniform(0.1, 0.3)

        elif choice == 'hum':
            # Low frequency hum (like machinery or electrical)
            t = np.linspace(0, CLIP_DURATION, N_SAMPLES, endpoint=False)
            freq = random.uniform(50, 200)
            audio = np.sin(2 * np.pi * freq * t).astype(np.float32) * random.uniform(0.05, 0.2)
            # Add harmonics
            for h in range(2, random.randint(3, 6)):
                audio += np.sin(2 * np.pi * freq * h * t).astype(np.float32) * random.uniform(0.01, 0.05)
            # Add noise floor
            audio += np.random.normal(0, 0.005, N_SAMPLES).astype(np.float32)

        else:  # ambient
            # Broadband ambient noise (wind-like)
            audio = np.random.randn(N_SAMPLES).astype(np.float32)
            # Low-pass filter to sound like wind
            from scipy.signal import butter, filtfilt
            cutoff = random.uniform(500, 3000)
            nyq = SAMPLE_RATE / 2
            b, a = butter(4, cutoff / nyq, btype='low')
            audio = filtfilt(b, a, audio).astype(np.float32)
            audio = audio / (np.abs(audio).max() + 1e-8) * random.uniform(0.1, 0.4)

        audio = np.clip(audio, -1.0, 1.0).astype(np.float32)
        negatives.append(audio)

    return negatives


# ===========================================================================
# TRAINING
# ===========================================================================

def build_model():
    """Build MobileNetV2-based binary classifier for spectrogram images."""
    import tensorflow as tf

    base_model = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights='imagenet',
    )

    # Freeze base layers initially
    base_model.trainable = False

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(IMG_SIZE, IMG_SIZE, 3)),
        base_model,
        tf.keras.layers.GlobalAveragePooling2D(),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(1, activation='sigmoid'),
    ], name='DistressDetector_MobileNetV2')

    return model, base_model


def train():
    import tensorflow as tf

    print("=" * 65)
    print("SafeNetic Distress Sound Detector — Training Pipeline")
    print("=" * 65)
    print(f"  Model:      MobileNetV2 (transfer learning)")
    print(f"  Input:      {IMG_SIZE}x{IMG_SIZE}x3 mel-spectrogram images")
    print(f"  Audio:      {SAMPLE_RATE}Hz, {CLIP_DURATION}s clips")
    print(f"  Mel params: nFft={N_FFT}, hop={HOP_LENGTH}, nMels={N_MELS}")

    # ── 1. Load distress audio ────────────────────────────────────────────────
    print("\n" + "=" * 65)
    print("PHASE 1: Loading Distress Audio")
    print("=" * 65)

    augment_pipeline = build_augment_pipeline()
    distress_audios = []
    distress_labels = []

    for category, folder in DISTRESS_DIRS.items():
        if not folder.exists():
            print(f"  [SKIP] {category}: folder not found at {folder}")
            continue

        wav_files = list(folder.glob("*.wav"))
        print(f"  [{category}] Found {len(wav_files)} wav files")

        loaded = 0
        for wav in wav_files:
            audio = load_audio_librosa(wav)
            if audio is None:
                continue

            # Original
            distress_audios.append(audio)
            distress_labels.append(category)
            loaded += 1

            # Augmented copies
            for _ in range(AUGMENTATIONS):
                if augment_pipeline:
                    aug = augment_pipeline(samples=audio.copy(), sample_rate=SAMPLE_RATE)
                else:
                    aug = basic_augment(audio)
                distress_audios.append(aug)
                distress_labels.append(category)

        print(f"    Loaded {loaded} originals + {loaded * AUGMENTATIONS} augmented = {loaded * (AUGMENTATIONS + 1)} total")

    n_distress = len(distress_audios)
    print(f"\n  Total distress samples: {n_distress}")

    if n_distress == 0:
        print("ERROR: No distress audio found. Exiting.")
        sys.exit(1)

    # ── 2. Generate normal/negative samples ───────────────────────────────────
    print("\n" + "=" * 65)
    print("PHASE 2: Generating Normal (Negative) Samples")
    print("=" * 65)

    # Generate enough negatives for a balanced dataset
    n_negatives = n_distress  # 1:1 ratio
    normal_audios = generate_synthetic_negatives(n_negatives)

    print(f"  Generated {len(normal_audios)} normal samples")

    # ── 3. Convert all audio → spectrogram images ─────────────────────────────
    print("\n" + "=" * 65)
    print("PHASE 3: Converting Audio to Spectrogram Images")
    print("=" * 65)

    X_all = []
    y_all = []

    # Process distress
    print(f"  Processing {n_distress} distress samples...")
    for i, audio in enumerate(distress_audios):
        img = audio_to_spectrogram_image(audio)
        X_all.append(img)
        y_all.append(1)
        if (i + 1) % 200 == 0:
            print(f"    Distress: {i + 1}/{n_distress}")

    # Process normal
    print(f"  Processing {len(normal_audios)} normal samples...")
    for i, audio in enumerate(normal_audios):
        img = audio_to_spectrogram_image(audio)
        X_all.append(img)
        y_all.append(0)
        if (i + 1) % 200 == 0:
            print(f"    Normal: {i + 1}/{len(normal_audios)}")

    X = np.array(X_all, dtype=np.float32)
    y = np.array(y_all, dtype=np.float32)

    print(f"\n  Dataset shape: X={X.shape}, y={y.shape}")
    print(f"  Distress: {int(np.sum(y == 1))}  |  Normal: {int(np.sum(y == 0))}")

    # ── 4. Train/Val Split ────────────────────────────────────────────────────
    print("\n" + "=" * 65)
    print("PHASE 4: Training MobileNetV2")
    print("=" * 65)

    from sklearn.model_selection import train_test_split

    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=VAL_SPLIT, random_state=SEED, stratify=y
    )
    print(f"  Train: {len(X_train)}  |  Val: {len(X_val)}")

    # Build model
    model, base_model = build_model()
    model.summary()

    # Phase A: Train top layers (frozen base)
    print("\n--- Phase A: Training top layers (base frozen) ---")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss='binary_crossentropy',
        metrics=['accuracy', tf.keras.metrics.AUC(name='auc')],
    )

    callbacks_a = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_auc', patience=5,
            restore_best_weights=True, mode='max'
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss', patience=3, factor=0.5, min_lr=1e-6
        ),
    ]

    model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        callbacks=callbacks_a,
        verbose=1,
    )

    # Phase B: Fine-tune top layers of base model
    print("\n--- Phase B: Fine-tuning (unfreezing top 30 layers) ---")
    base_model.trainable = True
    for layer in base_model.layers[:-30]:
        layer.trainable = False

    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-5),  # Lower LR for fine-tuning
        loss='binary_crossentropy',
        metrics=['accuracy', tf.keras.metrics.AUC(name='auc')],
    )

    callbacks_b = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_auc', patience=5,
            restore_best_weights=True, mode='max'
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss', patience=3, factor=0.5, min_lr=1e-7
        ),
    ]

    model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=10,
        batch_size=BATCH_SIZE,
        callbacks=callbacks_b,
        verbose=1,
    )

    # Evaluate
    loss, acc, auc = model.evaluate(X_val, y_val, verbose=0)
    print(f"\n  Final Val -> Loss: {loss:.4f}  Acc: {acc*100:.1f}%  AUC: {auc:.4f}")

    # Save Keras model
    model.save(str(OUTPUT_KERAS))
    print(f"  [OK] Keras model saved: {OUTPUT_KERAS}")

    # ── 5. Convert to TFLite ──────────────────────────────────────────────────
    print("\n" + "=" * 65)
    print("PHASE 5: Converting to TFLite (INT8 quantization)")
    print("=" * 65)

    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    def rep_data():
        indices = np.random.choice(len(X_train), min(200, len(X_train)), replace=False)
        for i in indices:
            yield [X_train[i:i+1]]

    converter.representative_dataset = rep_data
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
        tf.lite.OpsSet.TFLITE_BUILTINS,
    ]
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32

    print("  Converting...")
    tflite_bytes = converter.convert()

    with open(str(OUTPUT_TFLITE), 'wb') as f:
        f.write(tflite_bytes)

    kb = len(tflite_bytes) / 1024
    print(f"  [OK] Saved: {OUTPUT_TFLITE}")
    print(f"  Size: {kb:.1f} KB ({kb/1024:.2f} MB)")

    # ── 6. Verify TFLite ──────────────────────────────────────────────────────
    print("\n" + "=" * 65)
    print("PHASE 6: Verification")
    print("=" * 65)

    interp = tf.lite.Interpreter(model_path=str(OUTPUT_TFLITE))
    interp.allocate_tensors()
    inp = interp.get_input_details()
    out = interp.get_output_details()
    print(f"  TFLite input:  shape={inp[0]['shape']}, dtype={inp[0]['dtype']}")
    print(f"  TFLite output: shape={out[0]['shape']}, dtype={out[0]['dtype']}")

    # Quick sanity check on validation samples
    correct = 0
    n_check = min(20, len(X_val))
    for i in range(n_check):
        interp.set_tensor(inp[0]['index'], X_val[i:i+1])
        interp.invoke()
        pred = interp.get_tensor(out[0]['index'])[0][0]
        label = int(y_val[i])
        ok = (pred > 0.5) == bool(label)
        correct += int(ok)
        name = 'DISTRESS' if label == 1 else 'NORMAL'
        tag = 'OK' if ok else 'WRONG'
        print(f"    Sample {i+1}: {name:8s} pred={pred:.3f} [{tag}]")

    print(f"\n  Quick check: {correct}/{n_check} correct ({correct/n_check*100:.0f}%)")

    # ── Done ──────────────────────────────────────────────────────────────────
    print(f"\n{'=' * 65}")
    print("TRAINING COMPLETE")
    print(f"{'=' * 65}")
    print(f"  Keras model:  {OUTPUT_KERAS}")
    print(f"  TFLite model: {OUTPUT_TFLITE}")
    print(f"  Val Accuracy: {acc*100:.1f}%")
    print(f"  Val AUC:      {auc:.4f}")
    print(f"\n  Connect your Android device and run:  flutter run")
    print(f"{'=' * 65}")


if __name__ == "__main__":
    train()
