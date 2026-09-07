# Optional: SadTalker photoreal animation

The default app (`../index.html`) animates the mascot entirely in the
browser (SVG + Web Speech API) and needs no server or GPU. This folder is
an optional, separate path for anyone who wants actual SadTalker-generated
talking-head video instead of the SVG mouth-flap animation.

It is **not wired into the web app** and was not run in this environment —
SadTalker needs a CUDA GPU (CPU inference is impractically slow) and several
GB of model checkpoints, neither of which this sandbox has. Treat this as a
starting point to run on your own machine.

## Prerequisites

- NVIDIA GPU with recent drivers + CUDA
- Python 3.9/3.10
- ~10 GB disk for the SadTalker repo, checkpoints, and Python deps

## Setup

```sh
git clone https://github.com/OpenTalker/SadTalker.git
cd SadTalker
pip install -r requirements.txt
bash scripts/download_models.sh   # fetches the checkpoints (several GB)
```

## Producing the portrait image

SadTalker needs a still image with a clearly detectable, front-facing face
(its preprocessing runs a face-landmark detector). A flat vector mascot like
the SVG one in this project generally will **not** be detected reliably —
export or draw a portrait-style character image instead (a front-facing
illustrated face works better than a full-body flat icon).

## Producing the audio

Any WAV/MP3 works. One option: record the browser's Web Speech output, or
generate audio with any TTS engine you have access to (offline `pyttsx3`,
a licensed cloud TTS, etc.) — this repo does not bundle a server-side TTS
call because the sandboxed dev environment used to build this project had
the common cloud TTS endpoints blocked by its egress policy.

## Running

```sh
python generate_video.py \
  --image path/to/portrait.png \
  --audio path/to/speech.wav \
  --sadtalker-dir path/to/SadTalker \
  --out output.mp4
```

`generate_video.py` in this folder is a thin CLI wrapper around SadTalker's
own `inference.py`; read it before running so you know exactly what it
invokes.
