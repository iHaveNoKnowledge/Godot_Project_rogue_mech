---
name: jev
description: "Calibrated, typed decisions from TypeSafe's Jev model through the `jev` CLI: a yes/no probability (noul), a pick-one classification with per-option probabilities and confidence (choice), or a position on a rubric you define (score). ~250 ms, $0.042 per million input tokens, same input gives the same answer. Use when a judgment REPEATS over many items you should not read into context (classify, filter, rank, dedupe, triage hundreds of notes, emails, transcript segments, log lines, RSS items, findings, PRs); when you need a CALIBRATED probability rather than your own vibe before acting; when a script or Cue needs a semantic if-statement that runs unattended; or to independently VERIFY your own output (does the source support this claim, does the draft break a stated rule, does this untrusted text carry an instruction aimed at an agent, is this tool call risky). Triggers: 'jev', 'typesafe', 'gut check', 'calibrated', 'second opinion', 'classify these', 'score these', 'rank these', 'filter these', 'which of these', 'triage', 'rerank', 'guardrail', 'prompt injection check', 'is this a ...', 'how severe', 'which team/category/bucket'. NOT for generation, math, counting, date arithmetic, multi-hop reasoning, or one small item you can judge in a glance."
metadata:
  short-description: Calibrated yes/no, pick-one and rubric-score decisions via the jev CLI
  cost: one shell call, ~250 ms and under $0.0001 per request; rank/batch cost cents per thousand items
  applies-when: the decision repeats over many items, must be a calibrated probability, runs unattended in a tool or cron job, or checks your own output with an independent model
  do-not-use-when: generating or rewriting text, arithmetic, counting, dates, chained reasoning, or a single item you can judge yourself faster than a shell call
  fallback: judge it yourself; use grep or a regex for exact-match questions
---

# Jev: Calibrated Decisions for Agents

Jev is TypeSafe's "System One" model. It does not write text. It takes a **state** (text
or JSON) and typed **questions**, and returns typed answers with calibrated probabilities.
It is a semantic `if` statement you can run ten thousand times: fast, cheap, repeatable,
and honest about uncertainty. You are the reasoning model; Jev is the gut check.

Install: put `jev.py` on PATH as `jev` (see the README beside this file) and copy this
skill folder into your agent's skills directory (`~/.claude/skills/jev/` for Claude Code,
`~/.agents/skills/jev/` for Codex, `~/.config/opencode/skills/jev/` for OpenCode). One
canonical copy symlinked into each keeps every agent on the same version. The key is per
machine (`~/.config/typesafe/api_key`); on a host without it, say plainly that Jev is
unavailable there rather than guessing.

## Reach for It When

| Situation | Why Jev beats doing it yourself |
|---|---|
| Hundreds of items to classify, filter, rank, dedupe | You should not read them all into context; `jev rank` / `jev batch` cost cents |
| You are about to act on your own confidence | Yours is not calibrated; Jev's is trained to be. Gate act / confirm / escalate on it |
| A tool or Cue needs a judgment unattended | No agent loop, ~250 ms, deterministic, `from jev import JevClient` |
| Checking your own output | Claim vs source, draft vs rules, tool call vs intent, untrusted text vs injection |

Not for: generation, math, counting, dates, numeric comparison, double negatives,
multi-hop reasoning, or one small item you can judge in a glance. Keep arithmetic in code.

## First Call in a Session

Run `jev guide` once (about 1,500 tokens) before your first real call. `jev doctor` if
anything fails. `jev guide --list` shows the deeper topics; `jev examples <name>` prints
copy-paste recipes for triage, rank, guardrail, verify, batch, python.

## The Commands

```bash
jev yes  'Does `text` ask for money back?' --field text=@msg.txt          # P(yes); exit 0 yes / 1 no
jev pick 'Which team handles `text`?' billing="Charges, refunds" tech="Bugs" other --field text=@msg.txt --min-confidence 0.6
jev rate 'How severe is the bug?' "Cosmetic" "Degraded, workaround exists" "Blocking" -s @report.txt
jev ask  --field msg=@t.txt --field policy=@p.md --noul refund '...' --noul covered '...' --choice team '...' a b c --score anger '...' L0 L1 L2 --json
jev rank --query "notes about the release timeline" --candidates-file titles.txt --top 10        # one request per ~250 items
jev batch --input rows.jsonl --state-key text --id-key id --noul relevant '...' --out out.jsonl
```

**Shell rule: single-quote any instruction that contains backticks**, or zsh executes
them. `--json` gives the raw API response.

**State is not just a sentence.** Assemble as much context as the judgment needs and
reference the pieces by name: `--field msg=@ticket.txt --field policy=@policy.md --field
orders=@orders.json --field tier='"gold"'` builds one object, and each `@x.json` is parsed
so nested structure survives (`Does \`policy\` cover the charge in \`orders[0]\`?`). Also
accepted: a whole document (`--state-file report.md`), an ordered array
(`--state-json '["turn 1","turn 2"]'`), piped stdin, or a hand-written `-f request.json`
carrying state and questions together. Ceiling measured 2026-09-20: **107,500 chars =
32,388 tokens**; above that the API returns `400 max_tokens_exceeded`. English runs 3.32
chars/token, so price it with `jev cost` rather than counting characters.

## Ask Everything in One Call

Questions in one request run in parallel and independently, so adding one is nearly
free. Put every question the workflow might need in one `jev ask`, including ones that
only matter on some branches, and let your code ignore the rest. Make a second request
only when you need the first answer to build the second state.

## Writing a Question That Works

Jev reads literally. It answers the words, not the intent.

- One judgment per question. Split anything that hides several.
- State the exact condition. If you would explain "what I really meant", put that in the instructions or criteria.
- Point at fields with backticked paths: `ticket.messages[0].text`. Question ids are not sent to the model.
- Never index into a long array (`items[137]`). Measured 2026-09-18: 27% wrong at 150 items per request, 9% at 25. Key the object (`items.k137`) or put the item inside the question; both 0 wrong of 320. `jev rank` embeds for you.
- Choice: describe each option so it is distinct from its neighbour; add `other` when the list may not cover the input; up to 255 options, give the full list.
- Score: 2 to 10 levels, low to high, each a concrete situation ("broken, workaround exists"), never a bare number or "moderate". One dimension per score.
- Noul: phrase so high means yes; add `--true/--false` when the boundary is subtle.
- Send only the state the questions need. Irrelevant context lowers accuracy.

## Reading the Answer

- **noul** is P(yes). 0.5 is undecided, not "medium". Pick the threshold by stakes.
- **choice** returns the argmax plus `confidence` (how peaked the distribution is). A runner-up with real mass is signal.
- **score** is a position that can fall between levels; round for one outcome, sort for ranking, divide by N-1 before weighting several together.
- Three bands: high confidence act; medium confirm or gather more; low do not act, escalate or ask. Thresholds scale with risk: read-only around 0.6, destructive around 0.9.
- Never carry a threshold from a noul to a choice, and never expect two separate questions to satisfy an arithmetic identity. Ask the question you want, one way.

## Build It In, Not Just Into a Chat Turn

```python
import sys; sys.path.insert(0, "/path/to/dir/containing/jev.py")
from jev import JevClient, noul, choice, score
QUESTIONS = {"receipt": noul("Is `email.body` a purchase receipt?")}   # questions + thresholds in ONE block, reviewable
r = JevClient(label="mail_triage").ask({"email": {"body": body}}, QUESTIONS)
if r["answers"]["receipt"]["noul"] >= 0.7: ...
```

`label` shows up in `jev usage`, which reports spend, tokens, latency, rate headroom, a
credits countdown and per-agent breakdowns; `jev cost --state-file f --questions N --items M`
prices a job before you run it. Pin `--model jev-1.13.0` in a pipeline whose thresholds
you tuned; `jev-latest` moves. Test a new question on a handful of known cases before
trusting it over a thousand.

## Building a Tool or Cron Job on Jev

`jev guide design` before writing the first line: shapes beyond classify, what stays in
code, the ship checklist. TypeSafe's own agent skill covers the same job from the
vendor's side with no executable; `jev guide vendor` fetches it live. It is not
installed as a second skill because it would overlap this one on every trigger.

## Your Context Is the Variable

The mechanism is identical everywhere. What differs is what you feed it and what you are
allowed to write, and that lives in your own agent's instruction file, not here. A
knowledge-base agent judges its notes, mail and transcripts; a project agent judges its
own tree. Same CLI, same rules.
