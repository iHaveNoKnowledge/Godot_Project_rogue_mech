"""Wrapper around the real Kimodo CLI (nv-tlabs/kimodo). Dry-run by default.

Real generation needs the kimodo checkout + models (auto-downloaded from
HuggingFace on first run) and ideally Docker on Windows:

  docker compose -f <kimodo>/docker-compose.yaml up
  docker exec -it kimodo kimodo_gen "a person walking stealthily" --duration 5

On <17GB VRAM cards (e.g. RTX 4070 Ti 12GB) force the text encoder to CPU:
  TEXT_ENCODER_DEVICE=cpu kimodo_gen "a person walking, tired" --duration 4

This wrapper only BUILDS the command (safe in CI); pass --run to execute.

Usage:
  python tools/kimodo/kimodo_generate.py --prompt "a person walking" --duration 4
  python tools/kimodo/kimodo_generate.py --prompt "..." --duration 4 --model Kimodo-SOMA-RP-v1.1 --run
  python tools/kimodo/kimodo_generate.py --prompt "..." --cpu-text-encoder --docker --run
"""
from __future__ import annotations

import argparse
import os
import shlex
import subprocess

DEFAULT_MODEL = "Kimodo-SOMA-RP-v1.1"


def build_command(prompt: str, duration: float, model: str, samples: int,
                  seed: int, docker: bool, cpu_text: bool) -> tuple:
    env = dict(os.environ)
    if cpu_text:
        env["TEXT_ENCODER_DEVICE"] = "cpu"
    cmd = ["kimodo_gen", prompt, "--model", model,
           "--duration", str(duration), "--num_samples", str(samples),
           "--seed", str(seed)]
    if docker:
        cmd = ["docker", "exec", "-it", "kimodo"] + cmd
    return cmd, env


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--duration", type=float, default=4.0)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--num-samples", type=int, default=1)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--docker", action="store_true")
    ap.add_argument("--cpu-text-encoder", action="store_true",
                    help="set TEXT_ENCODER_DEVICE=cpu (<17GB VRAM)")
    ap.add_argument("--run", action="store_true", help="execute (default: dry-run print)")
    args = ap.parse_args()
    cmd, env = build_command(args.prompt, args.duration, args.model,
                             args.num_samples, args.seed,
                             args.docker, args.cpu_text_encoder)
    print("KIMODO_CMD: %s" % " ".join(shlex.quote(c) for c in cmd))
    if args.cpu_text_encoder:
        print("KIMODO_ENV: TEXT_ENCODER_DEVICE=cpu")
    if not args.run:
        print("KIMODO_DRY_RUN_OK (pass --run to execute against real install)")
        return
    subprocess.run(cmd, env=env, check=True)


if __name__ == "__main__":
    main()
