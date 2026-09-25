#!/usr/bin/env python3
"""Check every text-on-chip pair in the p10k palettes against WCAG AA.

Sources each palette in a real zsh, reads the resulting POWERLEVEL9K_*
variables, and reports any pair under 4.5:1. Run it after a colour edit:

    uv run zsh/p10k/contrast.py
"""
import subprocess, sys, pathlib

HERE = pathlib.Path(__file__).resolve().parent
DISPATCH = HERE.parent / "p10k.zsh"

# Segments whose FOREGROUND sits on their own BACKGROUND.
PAIRS = [
    "OS_ICON", "DIR", "DIR_WORK",
    "VCS_CLEAN", "VCS_MODIFIED", "VCS_UNTRACKED", "VCS_CONFLICTED", "VCS_LOADING",
    "STATUS_OK", "STATUS_ERROR", "COMMAND_EXECUTION_TIME", "CONTEXT", "CONTEXT_ROOT",
    "TIME", "VIRTUALENV", "RUST_VERSION", "GO_VERSION", "NODE_VERSION",
]
# Extra foregrounds drawn on another segment's background.
EXTRA = [("DIR_SHORTENED", "DIR"), ("DIR_ANCHOR", "DIR")]


def luminance(h):
    h = h.lstrip("#")
    if len(h) != 6:
        return None
    ch = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in ch)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg, bg):
    lf, lb = luminance(fg), luminance(bg)
    if lf is None or lb is None:
        return None
    hi, lo = max(lf, lb), min(lf, lb)
    return (hi + 0.05) / (lo + 0.05)


def dump(theme):
    names = [f"POWERLEVEL9K_{s}_{k}" for s in PAIRS for k in ("FOREGROUND", "BACKGROUND")]
    names += [f"POWERLEVEL9K_{s}_FOREGROUND" for s, _ in EXTRA]
    script = (
        f'_p10k_state=/nonexistent; source {DISPATCH}; '
        f'source {HERE}/{theme}.zsh; '
        + "; ".join(f'print -r -- "{n}=${{{n}}}"' for n in names)
    )
    out = subprocess.run(["zsh", "-c", script], capture_output=True, text=True).stdout
    return dict(
        line.split("=", 1) for line in out.splitlines() if line.startswith("POWERLEVEL9K_")
    )


def main():
    bad = 0
    for theme in sorted(p.stem for p in HERE.glob("*.zsh") if p.stem != "base"):
        v = dump(theme)
        print(f"\n{theme}")
        checks = [(s, f"POWERLEVEL9K_{s}_FOREGROUND", f"POWERLEVEL9K_{s}_BACKGROUND")
                  for s in PAIRS]
        checks += [(s, f"POWERLEVEL9K_{s}_FOREGROUND", f"POWERLEVEL9K_{b}_BACKGROUND")
                   for s, b in EXTRA]
        for label, fk, bk in checks:
            fg, bg = v.get(fk, ""), v.get(bk, "")
            if not (fg.startswith("#") and bg.startswith("#")):
                continue
            r = ratio(fg, bg)
            ok = r >= 4.5
            bad += not ok
            print(f"  {'ok  ' if ok else 'FAIL'} {r:5.2f}:1  {label:<22} {fg} on {bg}")
    print(f"\n{bad} pair(s) below 4.5:1")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
