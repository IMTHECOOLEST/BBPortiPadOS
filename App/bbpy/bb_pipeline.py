"""Prepares the game on iPadOS: run.sh's steps, in-process (no bash, no subprocesses).

Called by App/Native/BBRuntime.c with the embedded CPython. It runs the runtime's own scripts
(scripts/prepare.py, link_libc.py, link_modules.py, content_profile.py, patches.py; copied into
the app by scripts/setup_deps.sh) and returns the argument list for the runtime's main.
"""
import contextlib
import io
import os
import runpy
import sys
import traceback
from pathlib import Path


def _run(scripts, name, args):
    """Runs one script as __main__; returns (exit code, its output)."""
    path = str(Path(scripts) / name)
    old_argv = sys.argv
    sys.argv = [path] + [str(a) for a in args]
    buf = io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            try:
                runpy.run_path(path, run_name="__main__")
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    except Exception:
        buf.write(traceback.format_exc())
        code = 1
    finally:
        sys.argv = old_argv
    return code, buf.getvalue()


def _step(scripts, log, name, args):
    code, text = _run(scripts, name, args)
    log.write(f"$ {name} {' '.join(str(a) for a in args)}\n{text}\n")
    log.flush()
    if code != 0:
        tail = "\n".join(text.strip().splitlines()[-6:])
        raise RuntimeError(f"{name} failed (exit {code}).\n{tail}")
    return text


def prepare(scripts, game, data, fps):
    """Returns the argv (without argv[0]) for the runtime's main."""
    scripts, game, data = Path(scripts), Path(game), Path(data)
    out = data / "out"
    user = Path(os.environ.get("BB_USER_DIR", data / "user"))
    ini = Path(os.environ.get("BB_CONFIG", data / "bbport.ini"))
    out.mkdir(parents=True, exist_ok=True)
    user.mkdir(parents=True, exist_ok=True)

    # Defaults run.sh exports for the Metal/MoltenVK builds.
    for key, value in {
        "BB_COPY_GPU_BUFFERS": "1",
        "BB_GPU_WRITE_TWINS": "1",
        "BB_GPU_WRITE_TWINS_MAX": "65536",
        "BB_UFFD": "0",
        "BB_PC_MODEL": "0",
        "BB_GUEST_IN_PLACE": "0",
    }.items():
        os.environ.setdefault(key, value)

    with open(data / "prepare.log", "w", encoding="utf-8") as log:
        _step(scripts, log, "prepare.py", [game, "--out", out])
        _step(scripts, log, "link_libc.py", [game, "--out", out])
        _step(scripts, log, "link_modules.py", [game, "--out", out])
        _step(scripts, log, "content_profile.py", [game, "--out", out, "--sku", "full"])

        # The render and output sizes for the chosen output_res (run.sh: --print-scaled).
        render = output = ""
        if not os.environ.get("BB_RENDER_RES"):
            text = _step(scripts, log, "patches.py", ["--print-scaled", "--settings", ini])
            words = text.split()
            if len(words) >= 2:
                render, output = words[0], words[1]
        else:
            render = os.environ["BB_RENDER_RES"]
            output = os.environ.get("BB_OUTPUT_RES", "")
        if render:
            os.environ["BB_RENDER_RES"] = render
            os.environ["BB_OUTPUT_RES"] = output
            os.environ["BB_AUTO_RENDER_RES"] = "1"
            w, h = (int(v) for v in render.lower().split("x"))
            extra = (w * h - 1920 * 1080) * 448   # direct memory for scenes above 1080p
            if extra > 0:
                os.environ.setdefault("BB_DMEM_MB", str(5056 + (extra + (64 << 20) - 1) // (64 << 20) * 64))

        _step(scripts, log, "patches.py", [
            "--out", out, "--fps", fps, "--extra", "", "--settings", ini, "--game-dir", game,
            "--render-res", render, "--output-res", output,
            "--patches-dir", data / "patches", "--patches-config", data / "patches.json",
            "--xml", scripts.parent / "patches" / "Bloodborne.xml",
        ])

    return [
        str(out / "boot-linked.bin"),
        "--content-profile", str(out / "content.bin"),
        "--patches", str(out / "patches.bin"),
        "--app0", str(game),
        "--user", str(user),
        "--timeout", os.environ.get("BB_TIMEOUT", "0"),
    ]
