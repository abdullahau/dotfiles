# Global instructions

## 1. Writing style

Write all output in Simplified Technical English (ASD-STE100). Follow Orwell's six rules too. If the two conflict, follow STE.

STE rules:
- Use short sentences. Keep instructions under 20 words. Keep other sentences under 25 words.
- Put one idea in each sentence.
- Use active voice. Name the actor: "Run the script," not "The script should be run."
- Use simple, common words. Avoid jargon and rare words.
- Use the same word for the same thing every time. Do not swap synonyms for variety.
- Use present tense where you can.
- Use articles (a, an, the). Do not drop them to sound terse.

Orwell's six rules:
1. Do not use a metaphor or other figure of speech you have seen in print before.
2. Do not use a long word where a short word will do.
3. Cut a word if you can cut it.
4. Use active voice, not passive voice.
5. Do not use a foreign phrase, a scientific word, or a jargon word if a common word says the same thing.
6. Break any of these rules before you write something absurd.

This standard applies to all written output: chat responses, explanations, commit messages, docs, and comments. It does not override correct code syntax.

Lists, bullet points, and nested lists are fine. Use them when they help. Each line in a list must still follow the rules above: short, clear, one idea.

### Overriding the writing style

STE and Orwell's rules are the default, not a fixed rule. If a project or a request needs another style, use that style instead.

Examples: consulting-style prose, academic writing, personal creative writing.

- If I ask for a style by name, switch to it for that output.
- If the project already has a clear style (a paper, a proposal, a story), match it.
- If you are not sure which style fits, ask me or state which style you picked and why.

## 2. Python and related tools

I have `uv` installed. Use `uv` to run and manage Python, not `pip`, `python`, `venv`, or `poetry` directly.

- Run scripts: `uv run script.py`
- Run tools: `uv run quarto ...`, `uv run marimo ...`
- Add packages: `uv add <package>`
- Manage Python versions: `uv python install ...`

Use `uv` for Quarto and marimo commands too, when they run Python underneath.

## 3. Installing packages

I use Homebrew (`brew`) as my main package manager. Use `apt` only when `brew` cannot install the package.

- Before you install anything, run `brew list` to check what I already have.
- Prefer `brew install <package>` for new tools.
- Use `apt install` only as a last resort, and tell me why `brew` did not work.

## 4. Code comments

Keep comments short and clear. A comment should explain why the code does something, not what it does. Skip comments that just restate the code. Do not write long comment blocks.

## 5. GitHub CLI (gh)

I have `gh` installed through Homebrew. Use it for repo work: pull requests, issues, releases, and other GitHub tasks.

- Always ask me first before you run a `gh` command that changes a repo. This includes pushes, pull requests, merges, issue edits, and releases.
- Read-only commands, like status checks or listing issues, do not need my permission first.

## 6. Token efficiency

Context is the scarce resource. Follow these rules on every task.

### Read narrowly, not whole

Do not read a whole file to find one thing. Search first, then read only the
match and what it touches.

- Find the symbol: `grep -rn "def build_cohort" src/`
- Read the region: `sed -n '340,420p' file.py`
- Trace callers and callees with `grep -n`, not with more full reads.
- Use `rg`, `grep`, `glob`, or `ctags` for structure. Use `Read` for detail.

Read a whole file or a whole repo only when I ask you to study it in full.
If you must read a large file, state why first.

### Compress every image before you look at it

Never analyse a raw screenshot or photo. Shrink it first with ImageMagick:

```bash
magick shot.png -resize 1200x -quality 82 /tmp/shot-small.png
```

Read the small copy. A full-size screenshot costs many times more than the
resized one, and the resized one shows the same layout.

### Other habits

- Never re-read a file after you edit it. A failed edit reports an error.
- Run long commands with `run_in_background`. Do not stream output into context.
- Pipe noisy commands through `tail -20`, `head`, or `grep`.
- Batch independent tool calls into one block. Fewer round trips, fewer resends.
- Send a wide search to a subagent when you only need the answer, not the files.

## 7. Priority

If a task pulls the writing standard in rule 1 against speed or brevity elsewhere in these instructions, rule 1 wins. Clear, correct STE output matters more than short output.
