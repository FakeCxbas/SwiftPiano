# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

"""Local audio-to-MIDI trial; retains raw inference for editable regrouping.

Run with .venv-transcribe/bin/python. No audio is uploaded.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

os.environ.setdefault("OMP_NUM_THREADS", "2")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "2")
os.environ.setdefault("NUMBA_NUM_THREADS", "2")

def main():
    args = argparse.ArgumentParser()
    args.add_argument("source", type=Path)
    args.add_argument("output", type=Path)
    opts = args.parse_args()
    opts.output.mkdir(parents=True, exist_ok=True)
    wav = opts.output / "source-mono.wav"
    cache = opts.output / "raw-notes.json"
    if cache.exists():
        print("Raw transcription already exists; preserving it.", flush=True)
        return
    subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-threads", "2",
                    "-i", str(opts.source), "-vn", "-ac", "1", "-ar", "22050", str(wav)], check=True)
    import onnxruntime as ort
    from basic_pitch import ICASSP_2022_MODEL_PATH
    from basic_pitch.inference import Model, predict
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    model = Model.__new__(Model)
    model.model_type = Model.MODEL_TYPES.ONNX
    model.model = ort.InferenceSession(str(ICASSP_2022_MODEL_PATH), sess_options=options,
                                      providers=["CPUExecutionProvider"])
    print("Transcribing locally with two inference threads...", flush=True)
    _, midi, notes = predict(wav, model, onset_threshold=0.45, frame_threshold=0.30,
                             minimum_note_length=95, minimum_frequency=27.5,
                             maximum_frequency=4186, melodia_trick=False)
    raw = [dict(start=float(s), end=float(e), pitch=int(p), confidence=float(a))
           for s, e, p, a, _ in notes]
    raw.sort(key=lambda n: (n["start"], n["pitch"]))
    cache.write_text(json.dumps(raw, indent=2), encoding="utf-8")
    midi.write(str(opts.output / "original-transcription.mid"))
    print(f"Saved {len(raw)} raw notes; final onset {raw[-1]['start']:.2f}s", flush=True)

if __name__ == "__main__":
    main()
