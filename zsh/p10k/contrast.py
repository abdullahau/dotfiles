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
    "OS_ICON", "DIR", "DIR_WORK", "DIR_WORK_NOT_WRITABLE",
    "VCS_CLEAN", "VCS_MODIFIED", "VCS_UNTRACKED", "VCS_CONFLICTED", "VCS_LOADING",
    "STATUS_OK", "STATUS_OK_PIPE", "STATUS_ERROR", "STATUS_ERROR_PIPE",
    "STATUS_ERROR_SIGNAL", "COMMAND_EXECUTION_TIME", "BACKGROUND_JOBS",
    # Every context state. Over SSH p10k uses CONTEXT_REMOTE, not CONTEXT.
    "CONTEXT", "CONTEXT_DEFAULT", "CONTEXT_REMOTE", "CONTEXT_REMOTE_SUDO",
    "CONTEXT_SUDO", "CONTEXT_ROOT",
    "TIME", "VIRTUALENV", "RUST_VERSION", "GO_VERSION", "NODE_VERSION", "DIRENV",
]

# Neighbours on the right bar. Sharing a background makes p10k draw a thin
# subsegment arc instead of a solid head, which reads as a stray outline.
ADJACENT = [
    ("COMMAND_EXECUTION_TIME", "CONTEXT_REMOTE"),
    ("CONTEXT_REMOTE", "TIME"),
]
# Extra foregrounds drawn on another segment's background.
EXTRA = [("DIR_SHORTENED", "DIR"), ("DIR_ANCHOR", "DIR")]

# p10k does not take the git chip's text colour from VCS_*_FOREGROUND. The
# palettes set these globals and base.zsh reads them. Missing this is what
# left the branch name grey on the yellow chip, so check them here too.
GIT = ["meta", "clean", "modified", "untracked", "conflicted"]


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
    names += [f"_p10k_git_{g}" for g in GIT]
    script = (
        f'_p10k_state=/nonexistent; source {DISPATCH}; '
        f'source {HERE}/{theme}.zsh; '
        + "; ".join(f'print -r -- "{n}=${{{n}}}"' for n in names)
    )
    out = subprocess.run(["zsh", "-c", script], capture_output=True, text=True).stdout
    v = dict(
        line.split("=", 1)
        for line in out.splitlines()
        if line.startswith(("POWERLEVEL9K_", "_p10k_git_"))
    )
    # Unwrap the %F{#rrggbb} prompt escape the git colours are stored in.
    for k, val in list(v.items()):
        if k.startswith("_p10k_git_"):
            v[k] = val[3:-1] if val.startswith("%F{") and val.endswith("}") else ""
    return v


def main():
    bad = 0
    for theme in sorted(p.stem for p in HERE.glob("*.zsh") if p.stem != "base"):
        v = dump(theme)
        print(f"\n{theme}")
        checks = [(s, f"POWERLEVEL9K_{s}_FOREGROUND", f"POWERLEVEL9K_{s}_BACKGROUND")
                  for s in PAIRS]
        checks += [(s, f"POWERLEVEL9K_{s}_FOREGROUND", f"POWERLEVEL9K_{b}_BACKGROUND")
                   for s, b in EXTRA]
        checks += [(f"git text: {g}", f"_p10k_git_{g}",
                    "POWERLEVEL9K_VCS_CLEAN_BACKGROUND") for g in GIT]
        for label, fk, bk in checks:
            fg, bg = v.get(fk, ""), v.get(bk, "")
            if not (fg.startswith("#") and bg.startswith("#")):
                continue
            r = ratio(fg, bg)
            ok = r >= 4.5
            bad += not ok
            print(f"  {'ok  ' if ok else 'FAIL'} {r:5.2f}:1  {label:<22} {fg} on {bg}")
        for a, b in ADJACENT:
            ba = v.get(f"POWERLEVEL9K_{a}_BACKGROUND", "")
            bb = v.get(f"POWERLEVEL9K_{b}_BACKGROUND", "")
            if ba and ba == bb:
                bad += 1
                print(f"  FAIL  same bg    {a} and {b} are both {ba} -> stray arc")
    print(f"\n{bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
