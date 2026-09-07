#!/usr/bin/env python3
"""Thin CLI wrapper around SadTalker's inference.py.

Not run as part of this project's default flow -- see README.md in this
folder for prerequisites (GPU, checkpoints). This script only shells out to
an existing SadTalker checkout; it does not implement any inference itself.
"""
import argparse
import pathlib
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, help="Front-facing portrait image")
    parser.add_argument("--audio", required=True, help="Speech audio (wav/mp3)")
    parser.add_argument("--sadtalker-dir", required=True, help="Path to a cloned SadTalker checkout")
    parser.add_argument("--out", default="output.mp4", help="Output video path")
    parser.add_argument("--still", action="store_true", default=True,
                         help="Use SadTalker's --still mode (less head motion, steadier for mascots)")
    args = parser.parse_args()

    sadtalker_dir = pathlib.Path(args.sadtalker_dir).resolve()
    inference_script = sadtalker_dir / "inference.py"
    if not inference_script.exists():
        print(f"error: {inference_script} not found -- is --sadtalker-dir a real SadTalker checkout?",
              file=sys.stderr)
        return 1

    out_dir = pathlib.Path(args.out).resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        sys.executable, str(inference_script),
        "--driven_audio", str(pathlib.Path(args.audio).resolve()),
        "--source_image", str(pathlib.Path(args.image).resolve()),
        "--result_dir", str(out_dir),
    ]
    if args.still:
        cmd.append("--still")

    print("running:", " ".join(cmd))
    return subprocess.call(cmd, cwd=str(sadtalker_dir))


if __name__ == "__main__":
    raise SystemExit(main())
