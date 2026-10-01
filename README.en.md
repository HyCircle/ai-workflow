# ai-workflow

English | [中文](README.md)

A **semi-automated multi-agent development workflow** you can install into any git project. The agent you are chatting with (Claude Code, Codex, or Cursor) acts as the *owner*. When it pays off, it hands implementation to cheaper external models and sends the result to a model from another family for independent review. Long-lived design goes into ADRs, each session is archived by the agent that did the work, and lessons for recurring kinds of tasks go into playbooks.

This repository is the **single source** of the workflow. It installs as a command-line tool, `wf`, and `wf init` sets it up in the project you want to work on.

---

## What it's for

- **Spend expensive-model time on judgment.** The main agent understands the goal, breaks down the problem, and rules on results. Writing code and running experiments can go to cheaper models.
- **No model grades its own work.** Reviews go by default to a different model family from the one that did the work: for example, Cursor Composer writes and Grok reviews, with an optional second review from GPT.
- **Context on demand.** The root instructions in `AGENTS.md` are a router that says what to read when; agents don't preload the whole doc set.
- **Design stays coherent.** ADRs are one per topic and edited in place. When the project grows complex, `/holistic` reviews the whole design and merges or removes what's redundant.
- **Claims hold up under challenge.** Experimental claims go through `/challenge`; reviewing the diff doesn't replace it.
- **Lessons have a home.** Pitfalls and practices learned in a session go into task-type playbooks that are read the next time you do the same kind of task.

## Core concepts

### Six roles (skills you run as slash commands in the main agent)

| Command | Role | What it does |
|---|---|---|
| `/bs` | Brainstorm | Takes a design question and produces at least 3 genuinely different options. A model from another family red-teams them. The chosen option is written up as a new ADR or merged into an existing one, which gets red-teamed again before it's frozen. No code. |
| `/planner` | Owner | Owns the outcome of the task. Reads the current state and weighs uncertainty, risk, and whether delegating pays off. Then either does the work itself or writes a short brief and dispatches it. Finally it verifies the result and decides whether the task is done. |
| `/finishing` | Wrap-up | The agent that did the work writes a session archive (the user's own words, decisions and reasons, verified vs. unverified conclusions, open items), updates TODO, lists playbook candidates, and replies with a handoff and an opening prompt for the next session. |
| `/cleaning` | Cleanup | Run on demand (every few sessions, or when docs look stale), on a cheap model. Merges playbook candidates from recent archives into `patterns/`, then sweeps everything inside the project's writable scope: docs vs. code, dead files and duplication, architecture/TODO, ADR references, old scratch. Mechanical fixes are applied directly; deleting or rewriting tracked files goes through a candidate list you confirm. |
| `/holistic` | Overall review | Run on a strong model when the project grows complex or a major phase ends. Reads architecture, every ADR, and the key code; finds cross-ADR conflicts, overlap, seam bugs, and needless complexity; proposes an overall plan to merge, delete, and simplify, then executes what you confirm. |
| `/challenge` | Claim challenge | For experiments, benchmarks, performance or numerical results, and claims like "X beats Y" or "verified done": a strong model looks only for counter-evidence and reproduces it itself, for at most two rounds; you settle each objection, and the report separates supported from unverified claims. Not for ordinary coding tasks. |

Two more roles are called by `wf`. You don't talk to them directly:

- **worker**: a model in an external CLI (`cursor-agent`, `codex`, or `claude`). It edits code in the current working tree according to the brief, never commits, and its final reply is its report.
- **reviewer**: a read-only external model. It reads the current changes and the brief and outputs a list of problems.

### Where each kind of document lives

| Location (after install) | Contents | Committed? |
|---|---|---|
| `AGENTS.md` (repo root) | Project tool conventions and the doc router (what to read when). The root instructions shared by all three harnesses. | Yes, in track mode |
| `.workflow/kit/discipline.md` | Six standing rules (less is more, no patch-on-patch, no reflexive fallbacks, …) | No (copy of the kit) |
| `.workflow/decisions/NNNN-slug.md` | ADRs: long-lived decisions, one per topic. When a decision changes, edit it in place; git history keeps old versions. | Yes, in track mode |
| `.workflow/architecture.md` | Global map of the current system. When it conflicts with an ADR, the ADR wins. | Yes, in track mode |
| `.workflow/TODO.md` | Flat list of next steps, open items, and known issues. Items are deleted when done. | Yes, in track mode |
| `.workflow/patterns/` | Playbooks per task type: steps, pitfalls, verification checklist | Yes, in track mode |
| `.workflow/scratchpad/` | Briefs, run outputs, and other temporary files | No |
| `.workflow/scratchpad/_archive/` | Session archives written by finishing, kept long-term on this machine and skipped by routine cleanup | No |

---

## Prerequisites

| Dependency | Used for |
|---|---|
| Linux, macOS, or WSL; git | Runtime environment |
| [uv](https://docs.astral.sh/uv/) (or pipx), Python 3.10+ | Installing `wf`; `wf` uses only the standard library |
| At least one main agent: Claude Code / Codex / Cursor | Running the `/bs`, `/planner`, … skills |
| Dispatch CLIs: any of `cursor-agent`, `codex`, `claude`, logged in | Calling workers, reviewers, and red teams |

> If you don't dispatch work or run red teams, you can skip the dispatch CLIs.

---

## Quick start

### 1. Install `wf` and set up your project

```bash
uv tool install git+<this-repo-url>   # installs the wf command; upgrade with: uv tool upgrade ai-workflow
cd /path/to/your-project
wf init                               # track mode, Claude Code entry only, by default
```

Common options:

```bash
wf init --backends cc,codex           # entries for both Claude Code and Codex
wf init --no-track                    # keep all workflow files out of version control
```

Re-running `wf init` is how you upgrade: it overwrites only `.workflow/kit/`. ADRs, architecture, TODO, patterns, `workflow.env`, and an existing `AGENTS.md` are left alone.

### 2. Fill in local config

The first `wf init` creates `.workflow/workflow.env`. Edit it for your project:

```bash
WF_TEST_CMD="uv run pytest"                      # how to run tests, e.g. "npm test", "go test ./..."

# Dispatch models, written as "backend/model". Backend is cursor | codex | claude; cursor if omitted.
WF_WORKER_MODEL="cursor/composer-2.5"            # worker: high volume, pick the cheapest
WF_REVIEW_MODEL="cursor/cursor-grok-4.6-high"    # default reviewer: a different family from the worker
WF_REVIEW_MODEL_STRONG="codex/gpt-5.6-terra"     # stronger reviewer / second review
```

`cursor/`, `codex/`, and `claude/` name **which CLI makes the call**, not which company the model comes from. The reviewer must be from a different model family than the worker. In `wf` commands, `worker`, `review`, and `strong` refer to these three settings.

### 3. Add project info

- In `AGENTS.md`, under the project tool conventions, describe this project's stack.
- Create `.workflow/architecture.md` and `.workflow/TODO.md` as needed.
- **Claude Code users**: the root instructions file is `AGENTS.md`. Turn on the Claude Code Project instructions setting that loads `AGENTS.md`; see the [official notes](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md).

### 4. Run a first cycle

```text
/bs What caching approach should we use?     # design question: explore, produce an ADR
/planner Implement the cache per ADR-0001    # delivery: planner does it or dispatches
/finishing                                   # wrap-up: archive, update TODO, hand off
```

In the next session, paste the "opening prompt for the next session" from the handoff and carry on. Every few sessions, run `/cleaning` on a cheap model; when the project grows complex, run `/holistic` on a strong one.

---

## How a cycle works

```text
bs         explore options → cross-family red team → write or merge ADR → red team again → user accepts
planner    read goal and current state → triage → do it yourself OR write a brief and dispatch
           → read results, verify the key call paths → rule → rework if needed
worker     implement within the brief's goal and boundaries; report results, deviations, contradictions
reviewer   read-only review of the actual changes; list of problems
finishing  write archive → update TODO → list playbook candidates → hand off
cleaning   (on demand) merge playbooks → repo-wide sweep → fix mechanical items, list judgment calls → prune scratch
holistic   (on demand) read the whole design → find cross-ADR problems → overall plan → execute after user confirms
challenge  (experimental claims) claim list → strong model seeks counter-evidence → settle each → separate supported from unverified
```

Not every task needs the full cycle. The planner makes small local fixes itself. `/bs` is only for design questions. Reviews, and especially second reviews, are added only when the risk justifies them.

### Dispatching: write a brief

Briefs go in `.workflow/scratchpad/PL-<session-UUID>/WO-current.md`. The template is `.workflow/kit/skills/planner/WO-TEMPLATE.md`:

```markdown
# Add a TTL to the cache layer

Goal: cache entries expire 10 minutes after they are written; reading an expired entry falls through to the source

Basis and boundaries: ADR-0003; only touch src/cache/, leave the public interface alone

Deliverables and evidence: unit tests for expiry and fall-through; a log excerpt from one real call
```

### `wf` commands

```bash
wf run <brief>                      # the worker implements; results go back to the planner
wf run <brief> --review             # implement + tests + independent review
wf review <brief> [--model strong]  # tests + independent review of the current tree; rerun with another model for a second review
wf ask <model> <prompt-files...> [--out FILE] [--write]
                                    # the call primitive, read-only by default: red teams, plan reviews, and claim challenges use it
wf init [--no-track] [--backends cc,codex,cursor]
```

Model arguments are `worker` / `review` / `strong` or `backend/model`. Worker and reviewer prompts start with the discipline file.

Each `run` / `review` keeps its outputs in `.workflow/scratchpad/runs/<timestamp>-<random-suffix>/`:

| File | Contents |
|---|---|
| `brief.md` | Snapshot of this round's input |
| `report.md` | The worker's report (its own account; the planner verifies it) |
| `review.md` | The review sheet |
| `test.log` | Test output |
| `*-prompt.md`, `*.log` | The prompts actually sent and the raw output streams (you can `tail -f` them) |
| `summary.md` | Same as the command output: exit codes and usage of each call, overreach check, test result, report, review, git status |
| `.done` | Outputs are final and can be cleaned up by age |

Exit codes: 0 means every call finished normally (not that the work passed); 2 means a call failed. The planner makes the final call: green tests only prove that the assertions that ran hold.

**Overreach check**: before and after the worker runs, `wf` compares the owner-authored files (`.workflow/decisions/`, `architecture.md`, `patterns/`, `AGENTS.md`); anything the worker changed is listed in the summary. Changes that existed before dispatch don't count.

**Read-only**: cursor uses its read-only mode; claude has editing tools disabled; codex is constrained by the prompt. None of them run in a sandbox.

### Wrap-up and archiving

`/finishing` has the main agent of the session write the archive itself: `.workflow/scratchpad/_archive/NN-YYYYMMDD-<slug>.md`, whose first line records the backend, session UUID, branch, and HEAD. The writer is the agent that did the work and saw the tool output and the failed attempts, so nothing has to be extracted and compacted afterwards. The user's constraints, corrections, and decisions are quoted verbatim; verified and unverified conclusions are listed separately.

Archives are cold storage: not read by default, only when you need to trace something back. Experience that should be picked up next time you do the same kind of task belongs in the `patterns/` playbooks. Archives are kept long-term on your machine, but git ignores them. **They are not a backup.**

---

## Project layout after install

```text
your-project/
├── AGENTS.md                    # root instructions: tool conventions + doc router
├── .workflow/
│   ├── kit/                     # copy of the kit (overwritten on every wf init)
│   │   ├── discipline.md
│   │   ├── skills/{bs,planner,finishing,cleaning,holistic,challenge}/
│   │   └── workflow.env.example
│   ├── decisions/0000-template.md   # ADR template
│   ├── architecture.md  TODO.md     # you create these
│   ├── patterns/                    # playbooks, created when cleaning merges the first one
│   ├── workflow.env                 # local config
│   └── scratchpad/                  # scratch outputs (including runs/ and _archive/)
├── .claude/skills → ../.workflow/kit/skills   # --backends cc
└── .agents/skills → ../.workflow/kit/skills   # --backends codex
```

### track vs. no-track

Both modes produce the same files. The only difference is what's written to `.git/info/exclude`. Your committed `.gitignore` is never touched.

| Mode | Ignored locally | Committed |
|---|---|---|
| track (default) | `.workflow/kit/`, `.workflow/workflow.env`, `.workflow/scratchpad/`, backend entry dirs | `AGENTS.md`, `decisions/`, `architecture.md`, `TODO.md`, `patterns/` |
| `--no-track` | All of `.workflow/`, `AGENTS.md`, backend entry dirs | Nothing |

In no-track mode your ADRs exist only on your machine; if you lose them, they're gone. To switch modes, re-run `wf init`. The exclude block is rewritten every time.

### Backend entries (`--backends`)

| Value | What it creates |
|---|---|
| `cc` (default) | `.claude/skills` symlink |
| `codex` | `.agents/skills` symlink |
| `cursor` | Cursor reads `.claude`/`.agents`, so no entry of its own; if cursor is the only backend, it borrows `.claude/skills` |

There is one source for the skills (`.workflow/kit/skills`), and every entry is a relative symlink to it. If something else already sits where an entry would go, `wf init` leaves it alone and tells you.

There's no uninstall command. To remove it by hand, delete `.workflow/kit/` (or all of `.workflow/`), `.claude/skills`, and `.agents/skills`. Then remove the lines from `ai-workflow BEGIN` to `END` in `.git/info/exclude`.

---

## Repository layout (for maintainers)

```text
ai-workflow/
├── pyproject.toml    # package definition; wf entry point
├── wf/               # the command-line tool (standard library only)
│   ├── cli.py        # command entry and config loading
│   ├── agent.py      # call primitive: three backends, timeout kills the process tree, extracts the final reply
│   ├── dispatch.py   # run / review: implement, overreach check, tests, review, summary
│   ├── install.py    # init
│   ├── kit/          # the workflow itself; wf init copies it into the project's .workflow/kit/
│   │   ├── discipline.md
│   │   ├── skills/   # bs / planner / finishing / cleaning / holistic / challenge (with brief template, worker/review/challenger preambles, red-team prompts)
│   │   └── workflow.env.example
│   └── seed/         # placed in the project on first install: AGENTS.md, decisions/0000-template.md
├── tests/            # end-to-end tests with fake CLIs in place of models
└── docs/             # for maintainers only; not installed into projects
    ├── design.md             # design blueprint and trade-offs
    ├── failure-modes.md      # known failure modes (read before changing the mechanism)
    ├── MAINTAINERS.md        # maintenance process
    └── history/              # evidence and reasoning behind implemented proposals, not current policy
```

### Changing the workflow

1. Change this repo only, never the `.workflow/kit/` copy inside a project.
2. Before changing code in `wf/`, read `docs/failure-modes.md`.
3. Run the tests before committing: `uv run --group dev pytest tests -q`.
4. To update your machine: `uv tool install --reinstall .`, then re-run `wf init` in each project.
