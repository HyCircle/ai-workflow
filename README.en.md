# ai-workflow

English | [中文](README.md)

A **semi-automated multi-agent development workflow** that you install into any git project. The agent you are chatting with (Claude Code, Codex, or Cursor) acts as the *owner*. It hands implementation work to cheaper external models and sends the result to a model from a different family for independent review. Design decisions are recorded as ADRs, and each session's conversation is compacted and archived.

This repository is the **single source** of the mechanism. You don't work in it directly. You run `install.sh` to install it into the project you are developing.

> The skills, prompts, and runtime docs are written in Chinese. The agents follow them regardless of the language you chat in.

---

## What it's for

- **Expensive models spend their time on judgment.** The main agent understands the goal, breaks down the problem, and rules on the results. Writing code and running experiments can go to cheaper models.
- **No model grades its own work.** By default, review goes to a model from a different family than the worker (for example, Cursor Composer writes and Grok reviews). A second GPT review can be added when it's worth it.
- **Scripts do the key checks.** A script or git hook checks whether a work order states a goal, whether the worker edited docs it shouldn't touch, and whether ADR structure and references are intact at commit time. None of this relies on the agent remembering to check.
- **Long-lived knowledge and scratch work live apart.** Design decisions (ADRs), the architecture overview, and the TODO list go into git. Work orders, logs, and review sheets stay in a local scratchpad and are cleaned up after use. Conversations are compacted and archived long-term on your machine.

## Core concepts

### Four roles (skills you run as slash commands in the main agent)

| Command | Role | What it does |
|---|---|---|
| `/bs` | Brainstorm | Takes a design question and produces at least 3 genuinely different options. A model from another family red-teams them. The chosen option is written up as an ADR, which gets red-teamed again before it's frozen. No code. |
| `/planner` | Owner | Owns the outcome of the task. Reads the current state and weighs uncertainty, risk, and whether delegating pays off. Then either does the work itself or writes a short brief and dispatches it. Finally it verifies the result and decides whether the task is done. |
| `/finishing` | Wrap-up | Writes a short handoff (results, open items, an opening prompt for the next session) and uses a local script to extract a denoised transcript of the session. |
| `/cleaning` | Cleanup | Best run at the start of the next session on a cheap model. Compacts and archives the transcript, updates architecture/TODO, checks ADR links, and prunes old scratch directories. |

Two more roles are dispatched by scripts. You don't talk to them directly:

- **worker**: a model running in an external CLI (`cursor-agent` or `codex`). It edits code according to the brief and never commits. Its final reply is its report.
- **reviewer**: an external model running read-only. It reads `git diff` and the brief and outputs structured findings.

### Every kind of document has one home

| Location (after install) | Contents | In git? |
|---|---|---|
| `AGENTS.md` (repo root) | Project tool conventions and the doc map. The root instructions shared by all three harnesses. | Yes, in track mode |
| `.workflow/kit/discipline.md` | Six standing rules: less is more, no patch-on-patch, no silent fallbacks, … | No (installed copy) |
| `.workflow/decisions/NNNN-slug.md` | ADRs: stable, long-lived decisions. Never edited in place; a new ADR supersedes an old one. | Yes, in track mode |
| `.workflow/architecture.md` | Map of the current design. When it conflicts with an ADR, the ADR wins. | Yes, in track mode |
| `.workflow/TODO.md` | Flat "next steps" list. Items are deleted when done. | Yes, in track mode |
| `.workflow/scratchpad/` | Work orders, run logs, review sheets, transcripts | No |
| `.workflow/scratchpad/_archive/` | Compacted past conversations, kept long-term on this machine and skipped by routine cleanup | No |

---

## Requirements

| Dependency | Used for |
|---|---|
| bash, git, coreutils (`timeout`, `sha256sum`) | All scripts |
| `jq` | Token-usage parsing in `run_worker.sh` |
| Python 3 (standard library only) | Doc checks, transcript extraction, and archiving. Called via `uv run python` by default; set `WF_PY="python3"` if you don't use uv. |
| At least one main agent: Claude Code / Codex / Cursor | Running the `/bs`, `/planner`, … skills |
| At least one dispatch CLI: `cursor-agent` and/or `codex`, logged in | Calling the worker and reviewer |

> If you only use `/bs`, `/finishing`, and `/cleaning`, or if the planner does all the work itself, you can skip the dispatch CLIs.

---

## Quick start

### 1. Install into your project

```bash
git clone <this-repo-url> ~/tools/ai-workflow

# Defaults: --track --backends cc
~/tools/ai-workflow/install.sh /path/to/your-project
```

Common options:

```bash
# Create entry points for both Claude Code and Codex
install.sh --backends cc,codex /path/to/your-project

# Keep all workflow files out of version control
install.sh --no-track /path/to/your-project
```

### 2. Set up local config

```bash
cd /path/to/your-project
cp .workflow/kit/workflow.env.example .workflow/workflow.env
```

Edit `.workflow/workflow.env`:

```bash
WF_TEST_CMD="uv run pytest"      # how your project runs tests, e.g. "npm test", "go test ./..."
WF_PY="uv run python"            # how to run python; "python3" if you don't use uv

# Dispatch models, written as "backend/model". The backend is cursor | codex;
# with no prefix it defaults to cursor.
WF_WORKER_MODEL="cursor/composer-2.5"            # worker: high volume, pick the cheapest
WF_REVIEW_MODEL="cursor/cursor-grok-4.6-high"    # default reviewer: a different model family
WF_REVIEW_MODEL_STRONG="codex/gpt-5.6-terra"     # stronger / second reviewer
```

Note that `cursor/` and `codex/` say **which CLI dispatches the call**. They don't tell you which family the model belongs to. The reviewer should come from a different model family than the worker.

Optional timeouts, in seconds (defaults in parentheses): `WF_TIMEOUT_WORKER` (1800), `WF_TIMEOUT_REVIEW` (1200), `WF_TIMEOUT_TEST` (600), `WF_TIMEOUT_CHECK_DOCS` (120).

### 3. Fill in project details

- Describe your tech stack under "项目工具约定" (project tool conventions) in `AGENTS.md`.
- Create empty `.workflow/architecture.md` and `.workflow/TODO.md` if you want them.
- **Claude Code users**: the root instruction file is `AGENTS.md`, and the installer does not create a `CLAUDE.md`. Turn on the Claude Code Project instructions setting that loads `AGENTS.md`; see the [official note](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md).

### 4. Run your first cycle

Open your main agent in the project:

```text
/bs What caching approach should we use?     # design question: explore, produce ADR-0001
/planner Implement the cache per ADR-0001    # delivery: planner does it or dispatches
/finishing                                   # wrap-up: handoff + extract transcript
```

At the start of the next session (ideally on a cheaper model):

```text
/cleaning .workflow/scratchpad/PL-<session-UUID>/transcript.md
```

Then paste the "opening prompt for the next session" from the last handoff and carry on.

---

## How a cycle works

```text
bs         explore options → cross-family red team → write ADR → red team again → user accepts
planner    read goal and current state → triage → do it yourself OR write a brief and dispatch
           → read results, verify the key call paths → rule → rework if needed
worker     implement within the brief's goal and boundaries; report results, deviations, contradictions
reviewer   read-only review of the actual changes; structured findings
finishing  handoff → extract this session's transcript
cleaning   (next session) compact and archive → update architecture/TODO → check links → prune scratch
```

Not every task needs the full cycle. The planner makes small local fixes itself. `/bs` is only for design questions. Reviews, and especially second reviews, are added only when the risk justifies them.

### Dispatching: write a brief

Save the brief to `.workflow/scratchpad/PL-<session-UUID>/WO-current.md`. The template is at `.workflow/kit/skills/planner/WO-TEMPLATE.md`. The field labels are in Chinese: 目标 = goal, 依据与边界 = basis and boundaries, 交付与证据 = deliverables and evidence.

```markdown
# Add TTL to the cache

目标：cache entries expire 10 minutes after write; reading an expired entry falls through to the source

依据与边界：ADR-0003; only touch src/cache/, keep the public interface unchanged

交付与证据：unit tests for expiry and fallthrough; a log excerpt from one real call
```

The entry gate checks one thing only: there must be a `目标：…` (goal) line whose text is non-empty and not a bare `<placeholder>`. The legacy form `本单服务 → ADR-NNNN 的意图: …` is also accepted.

### Four ways to run `run_worker.sh`

```bash
# Default: worker runs + tests + doc check + overreach check + independent review
.workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md

# Exploration / small tasks: run only and hand the result back to the planner
# (the overreach check still runs; tests and review don't)
SKIP_REVIEW=1 .workflow/kit/scripts/run_worker.sh <brief>

# Code already exists: review and machine checks only
REVIEW_ONLY=1 .workflow/kit/scripts/run_worker.sh <brief>

# Targeted design review before building: reviews the brief only; nothing runs
WO_REVIEW=1 .workflow/kit/scripts/run_worker.sh <brief>

# Positional args override models: <brief> [worker] [reviewer] [second reviewer]
# Passing a 4th arg gives a dual review (both reviewers run in parallel)
.workflow/kit/scripts/run_worker.sh <brief> "" "" "$WF_REVIEW_MODEL_STRONG"
```

Each run writes to `.workflow/scratchpad/runs/<timestamp>-<pid>/`:

| File | Contents |
|---|---|
| `brief.md` | Snapshot of this run's input. The worker and every reviewer see the same copy. |
| `report.md` | Worker report. It's the worker's own account; the planner has to verify it. |
| `review.md` / `review2.md` | Review sheets |
| `run.log` | Full raw stream and token usage |
| `.done` | Outputs are final and can be pruned by age. **This does not mean approved.** |

### STATUS

| STATUS | Meaning | Next step |
|---|---|---|
| `review_complete` | No blocking findings, and every applicable machine check passed | The planner checks against the real results whether the goal was actually met |
| `review_blocked` | Blocking findings, or the tests / doc check / overreach check failed | Verify each issue. Fix the code, change the plan, or reject the finding with a reason. |
| `review_skipped` | No independent review this run (`SKIP_REVIEW=1`) | Arrange verification that matches the risk |
| `infra_failed` | Call failed, timed out, or the review sheet couldn't be parsed (exit code 2) | Check the log and the working tree. If only a reviewer failed, re-run with `REVIEW_ONLY=1`; the worker doesn't need to run again. |

STATUS is information only and never blocks a commit. The planner makes the final call: green tests only prove that the assertions that ran hold.

### Wrap-up and archiving

```bash
# Run by /finishing: extract the conversation from local CC / Codex / Cursor logs
# (user and assistant text only; common credentials are masked)
$WF_PY .workflow/kit/scripts/transcribe_session.py --backend cc \
  --session <full-UUID> --out .workflow/scratchpad/PL-<UUID>/transcript.md
#   Not found, or several matches: use --input <jsonl path> instead of --session.
#   --tools keeps a skeleton of the tool calls.

# Run by /cleaning: the model writes transcript.compact.md, then it's archived with a source hash
$WF_PY .workflow/kit/scripts/archive_transcript.py \
  --source <transcript.md> --compact <transcript.compact.md> --slug add-cache-ttl
#   → .workflow/scratchpad/_archive/NN-YYYYMMDD-add-cache-ttl.transcript.compact.md

# Before deleting the source directory, verify the archive is intact and matches its source
$WF_PY .workflow/kit/scripts/archive_transcript.py --source <transcript.md> --verify <archive-file>
```

Archives are kept long-term on your machine, but git ignores them. **They are not a backup.**

---

## Gates and boundaries

| Gate | When it runs | What it checks |
|---|---|---|
| Goal gate | Entry to `run_worker.sh` | The brief has a non-empty `目标：` line |
| Overreach check | After the worker runs | Whether the worker touched `.workflow/decisions/`, `.workflow/architecture.md`, or `AGENTS.md`. Only the owner writes those; if they were touched, STATUS is `review_blocked`. |
| Doc check | During review (`--changed`) and on `git commit` (pre-commit hook, `--staged`) | ADR frontmatter, file name matches its id, no broken `ADR-NNNN` references |

To check the whole repo by hand: `$WF_PY .workflow/kit/scripts/check_docs.py`.

Other rules: the worker never commits, and the main agent commits only when you explicitly allow it. `run_worker.sh` reviews **all** changes relative to HEAD, untracked files included. Any changes already in the working tree before you dispatch should either be named as part of the task or be moved out of the way first.

---

## Layout after install

```text
your-project/
├── AGENTS.md                    # root instructions: tool conventions + doc map
├── .workflow/
│   ├── kit/                     # installed copy of the mechanism (overwritten on every install)
│   │   ├── discipline.md
│   │   ├── skills/{bs,planner,finishing,cleaning}/
│   │   ├── scripts/             # run_worker / call_agent / check_docs / transcribe / archive …
│   │   ├── git-hooks/pre-commit
│   │   ├── settings.json
│   │   └── workflow.env.example
│   ├── decisions/0000-template.md   # ADR template
│   ├── architecture.md  TODO.md     # you create these
│   ├── workflow.env                 # local config
│   ├── scratchpad/                  # scratch outputs (including _archive/)
│   └── VERSION                      # which tag / commit was installed
├── .claude/skills → ../.workflow/kit/skills   # --backends cc
├── .agents/skills → ../.workflow/kit/skills   # --backends codex
└── .git/hooks/pre-commit
```

### track vs. no-track

Both modes produce the same files. The only difference is what's written to `.git/info/exclude`. Your committed `.gitignore` is never touched.

| Mode | Ignored locally | Committed |
|---|---|---|
| `--track` (default) | `.workflow/kit/`, `.workflow/workflow.env`, `.workflow/scratchpad/`, backend entry dirs | `AGENTS.md`, `decisions/`, `architecture.md`, `TODO.md`, `VERSION` |
| `--no-track` | All of `.workflow/`, `AGENTS.md`, backend entry dirs | Nothing |

In no-track mode your ADRs exist only on your machine; if you lose them, they're gone. To switch modes, re-run the installer. The exclude block is rewritten every time.

### Backend entry points (`--backends`)

| Value | What gets created |
|---|---|
| `cc` (default) | `.claude/skills` symlink, plus a `.claude/settings.json` on first install |
| `codex` | `.agents/skills` symlink |
| `cursor` | Nothing of its own, since Cursor reads `.claude`/`.agents`. If cursor is the only backend, it borrows `.claude/skills`. |

There is only one copy of the skills (`.workflow/kit/skills`). Every entry point is a relative symlink to it.

### Upgrading and reinstalling

After changing this repo, re-run the same `install.sh` command on the target project. Only `.workflow/kit/` and `VERSION` are overwritten. ADRs, architecture, TODO, `workflow.env`, the scratchpad, and an existing `AGENTS.md` are left alone.

Things the installer may tell you:

- The target already has `.git/hooks/pre-commit`: it isn't overwritten. Merge in `.workflow/kit/git-hooks/pre-commit` by hand.
- There's an existing `CLAUDE.md`: if it's only the `@AGENTS.md` stub or symlink that older versions of this workflow created, it's removed. Content your project wrote is kept, and you're told to merge it into `AGENTS.md`.
- The target isn't a git repo yet: the exclude and hook steps are skipped. Run `git init` and install again.

There's no uninstall script. To remove it by hand, delete `.workflow/kit/` (or all of `.workflow/`), `.claude/skills`, `.agents/skills`, and `.git/hooks/pre-commit`. Then remove the lines from `ai-workflow BEGIN` to `END` in `.git/info/exclude`.

---

## Repository layout (for maintainers)

```text
ai-workflow/
├── install.sh        # install / upgrade into a target project
├── kit/              # the mechanism; copied as-is to the target's .workflow/kit/
│   ├── discipline.md
│   ├── skills/       # bs / planner / finishing / cleaning (brief template, worker/review preambles, red-team prompts)
│   ├── scripts/      # run_worker.sh  call_agent.sh  derive_status.sh  lib_timeout.sh
│   │                 # check_docs.py  transcribe_session.py  archive_transcript.py
│   │   └── tests/    # run-all.sh and the test suites
│   ├── git-hooks/pre-commit
│   ├── settings.json
│   └── workflow.env.example
├── seed/             # placed in the target on first install: AGENTS.md, decisions/0000-template.md
└── docs/             # for maintainers only; never installed into targets
    ├── design.md             # design rationale and trade-offs
    ├── dot-workflow-layout.md# the .workflow/ layout contract
    ├── failure-modes.md      # known failure modes (read before changing the mechanism)
    ├── MAINTAINERS.md        # maintenance process
    └── history/              # archived diagnoses and plans, not current policy
```

What each script does:

- `run_worker.sh`: orchestration. It runs the goal gate, snapshots the brief, runs the worker, runs the overreach check, the tests, and the doc check, runs the reviews in parallel, derives STATUS, and prints the summary.
- `call_agent.sh`: the single way to call `cursor-agent` / `codex`. It streams to the log, applies per-role timeouts, and kills the whole process tree on timeout. Exit codes: 0 OK, 124 timeout, 3 agent error, 4 truncated stream.
- `derive_status.sh`: derives STATUS purely from the machine-check results and the review sheets.
- `check_docs.py`: checks ADR structure and broken links, over the whole repo, `--changed` files, or `--staged` files.
- `transcribe_session.py` / `archive_transcript.py`: extract conversations from all three backends, and archive them with source hashes plus a verify step.

### Changing the mechanism

1. Only edit `kit/` (or `install.sh`) in this repo. Never edit the `.workflow/kit/` copy inside a target project.
2. Before touching scripts, hooks, or install logic, read `docs/failure-modes.md`.
3. Run the full test suite locally before pushing (there's no CI):

   ```bash
   bash kit/scripts/tests/run-all.sh      # WF_PY overrides the python interpreter
   ```

4. Re-run `install.sh` on target projects to roll out the update.

For the full design rationale see [docs/design.md](docs/design.md); for maintenance conventions see [docs/MAINTAINERS.md](docs/MAINTAINERS.md). Both are in Chinese.
