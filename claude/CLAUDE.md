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

## 5. Priority

If a task pulls the writing standard in rule 1 against speed or brevity elsewhere in these instructions, rule 1 wins. Clear, correct STE output matters more than short output.
