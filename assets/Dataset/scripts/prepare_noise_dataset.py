"""
SafeNetic Noise Dataset Preparation (Audiomentations Optimized)
=============================================================
This script prepares the dataset for the SafeNetic noise detection model.
Following user requirements:
1. Uses audiomentations for all data augmentation.
2. Marks ONLY "Car Crash" audios as distress (Label 1).
3. All other environmental sounds from ESC-50 are marked as normal (Label 0).

Training Pipeline:
1. Scans 'assets/Dataset/car_crash/' for custom car crash samples.
2. Uses ESC-50 'glass_breaking' (ID 39) as supplementary car crash data.
3. Applies aggressive audiomentations (Gaussian Noise, Pitch, Time, Shift) to create a robust dataset.
"""

import os
import csv
import sys
import numpy as np
import librosa
import random
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR   = Path(__file__).parent
DATASET_ROOT = SCRIPT_DIR.parent
# Custom crash folder (user provides these)
CRASH_AUDIO_DIR = DATASET_ROOT / "car_crash"
# ESC-50 as base (for normal sounds and glass-based crashes)
ESC50_DIR    = DATASET_ROOT / "ESC-50-master"
AUDIO_DIR    = ESC50_DIR / "audio"
META_CSV     = ESC50_DIR / "meta" / "esc50.csv"

OUTPUT_NPZ   = DATASET_ROOT / "noise_dataset.npz"
OUTPUT_CSV   = DATASET_ROOT / "dataset_manifest.csv"

# ── Audio / Feature Parameters (must match AudioService.dart) ─────────────────
SAMPLE_RATE   = 16000
CLIP_DURATION = 2.0
N_SAMPLES     = int(SAMPLE_RATE * CLIP_DURATION)  # 32000
FRAME_LEN     = 512
FRAME_STEP    = 256
N_FFT_BINS    = 40
MAX_FRAMES    = 87

# ── Dataset Config ────────────────────────────────────────────────────────────
# Only glass_breaking (39) is kept as a "crash" proxy from ESC-50. 
# Others (sirens 42, fireworks 48, thunderstorm 19) are now NORMAL.
DISTRESS_CLASS_IDS = {39} 
AUGMENTATIONS_PER_CLIP = 10  # Increased for limited crash samples
SEED = 42
random.seed(SEED)
np.random.seed(SEED)

# ── Audiomentations Pipeline ──────────────────────────────────────────────────

def build_augment_pipeline():
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

# ── Audio Utilities ───────────────────────────────────────────────────────────

def load_audio(wav_path: Path) -> np.ndarray:
    try:
        audio, _ = librosa.load(str(wav_path), sr=SAMPLE_RATE, mono=True)
        if len(audio) < N_SAMPLES:
            audio = np.pad(audio, (0, N_SAMPLES - len(audio)))
        else:
            audio = audio[:N_SAMPLES]
        return audio.astype(np.float32)
    except Exception as e:
        print(f"Error loading {wav_path}: {e}")
        return None

def extract_features(audio: np.ndarray) -> np.ndarray:
    """Extract [40, 87] FFT feature matrix matching AudioService.dart."""
    features = []
    hamming  = np.hamming(FRAME_LEN)
    for start in range(0, N_SAMPLES - FRAME_LEN + 1, FRAME_STEP):
        frame    = audio[start:start + FRAME_LEN] * hamming
        spectrum = np.abs(np.fft.rfft(frame))
        bins     = np.log1p(spectrum[:N_FFT_BINS])
        features.append(bins)
    feat = np.array(features).T
    if feat.shape[1] < MAX_FRAMES:
        feat = np.pad(feat, ((0, 0), (0, MAX_FRAMES - feat.shape[1])))
    else:
        feat = feat[:, :MAX_FRAMES]
    return feat

# ── Main Pipeline ─────────────────────────────────────────────────────────────

def main():
    print("=" * 65)
    print("SafeNetic: CRASH-ONLY Noise Dataset Preparation")
    print("=" * 65)

    augment = build_augment_pipeline()
    X_all, y_all, manifest = [], [], []

    # 1. Process Custom Car Crash Audios (First Priority)
    custom_crashes = []
    if CRASH_AUDIO_DIR.exists():
        custom_crashes = list(CRASH_AUDIO_DIR.glob("*.wav"))
        print(f"\n[CRASH] Found {len(custom_crashes)} custom crash samples in {CRASH_AUDIO_DIR}")
        
        for wav in custom_crashes:
            audio = load_audio(wav)
            if audio is None: continue
            
            # Original
            X_all.append(extract_features(audio))
            y_all.append(1)
            manifest.append({'filename': wav.name, 'category': 'car_crash_custom', 'target': 99, 'label': 1, 'augmentation': 'original'})
            
            # Augmented (Aggressive)
            for i in range(AUGMENTATIONS_PER_CLIP * 2): # 20x for custom crashes
                aug_audio = augment(samples=audio.copy(), sample_rate=SAMPLE_RATE)
                X_all.append(extract_features(aug_audio))
                y_all.append(1)
                manifest.append({'filename': wav.name, 'category': 'car_crash_custom', 'target': 99, 'label': 1, 'augmentation': f'aug_{i+1}'})
    else:
        print(f"\n[INFO] No custom 'car_crash' folder found at {CRASH_AUDIO_DIR}. Skipping custom samples.")

    # 2. Process ESC-50 Glass Breaking as Crash Proxy
    if META_CSV.exists() and AUDIO_DIR.exists():
        rows = []
        with open(META_CSV, newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                target = int(row['target'])
                wav = AUDIO_DIR / row['filename']
                if not wav.exists(): continue
                
                audio = load_audio(wav)
                if audio is None: continue
                
                if target in DISTRESS_CLASS_IDS:
                    # Mark as Distress (Label 1)
                    X_all.append(extract_features(audio))
                    y_all.append(1)
                    manifest.append({'filename': row['filename'], 'category': row['category'], 'target': target, 'label': 1, 'augmentation': 'original'})
                    
                    for i in range(AUGMENTATIONS_PER_CLIP):
                        aug_audio = augment(samples=audio.copy(), sample_rate=SAMPLE_RATE)
                        X_all.append(extract_features(aug_audio))
                        y_all.append(1)
                        manifest.append({'filename': row['filename'], 'category': row['category'], 'target': target, 'label': 1, 'augmentation': f'aug_{i+1}'})
                else:
                    # Mark as Normal (Label 0) - including previously distress sounds like sirens
                    # We will sample these later to balance the dataset
                    rows.append(row)
        
        # Balance Normal samples (2x the number of distress samples)
        n_distress = len(y_all)
        n_normal_target = n_distress * 2
        random.shuffle(rows)
        normal_subset = rows[:n_normal_target]
        
        print(f"[NORMAL] Adding {len(normal_subset)} environmental sounds as Label 0 (Normal).")
        for row in normal_subset:
            wav = AUDIO_DIR / row['filename']
            audio = load_audio(wav)
            if audio is None: continue
            X_all.append(extract_features(audio))
            y_all.append(0)
            manifest.append({'filename': row['filename'], 'category': row['category'], 'target': row['target'], 'label': 0, 'augmentation': 'original'})

    # 3. Save Dataset
    if not X_all:
        print("ERROR: No data collected. Please ensure 'car_crash' folder or ESC-50 dataset is available.")
        return

    X = np.array(X_all, dtype=np.float32)
    y = np.array(y_all, dtype=np.int32)
    
    # Shuffle
    idx = np.random.permutation(len(X))
    X, y = X[idx], y[idx]
    manifest = [manifest[i] for i in idx]

    np.savez_compressed(
        str(OUTPUT_NPZ),
        X_features=X, y_labels=y,
        sample_rate=SAMPLE_RATE, frame_len=FRAME_LEN,
        frame_step=FRAME_STEP, n_fft_bins=N_FFT_BINS, max_frames=MAX_FRAMES,
    )
    
    with open(str(OUTPUT_CSV), 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['filename','category','target','label','augmentation'])
        writer.writeheader()
        writer.writerows(manifest)

    print(f"\n[OK] Dataset ready: {len(X)} samples total.")
    print(f"     Distress (Crash): {np.sum(y==1)}")
    print(f"     Normal:           {np.sum(y==0)}")
    print(f"     File saved to: {OUTPUT_NPZ}")

if __name__ == "__main__":
    main()
