# ai-workflow

[English](README.en.md) | 中文

一套可以装进任何 git 项目的**半自动多 agent 开发工作流**。它的做法是：由你正在对话的主 agent（Claude Code、Codex 或 Cursor）当"负责人"，把具体施工派给便宜的外部模型，再交给另一家模型独立验收。设计决策记成 ADR，每次会话的对话压缩后归档留存。

这个仓库是这套机制的**唯一源头**。你不直接在这里干活，而是用 `install.sh` 把它装进要开发的项目。

---

## 它解决什么问题

- **贵模型的时间花在判断上**：主 agent 负责理解目标、拆解问题、裁决结果；写代码、跑实验可以派给便宜模型。
- **不让同一个模型给自己打分**：验收默认交给和执行者不同家族的模型，比如 Cursor Composer 写、Grok 审，必要时再加 GPT 第二审。
- **关键检查交给脚本**：派单入口是否写了目标、worker 是否改了不该改的文档、提交时 ADR 结构和引用是否完好，这些都由脚本和 git hook 检查，不依赖 agent 自觉。
- **长期知识和临时产物分开放**：设计决策（ADR）、架构现状、待办进 git；工单、日志、验收单放在本地 scratchpad，用完即清；每次会话的对话压缩后长期归档在本机。

## 核心概念

### 四个角色（以 skill 形式提供，在主 agent 里用斜杠命令调用）

| 命令 | 角色 | 做什么 |
|---|---|---|
| `/bs` | 脑暴 | 对一个设计问题提出 3 个以上真正不同的方案，交另一家模型红队，收敛后写成 ADR，冻结前再红队一次。不写代码。 |
| `/planner` | 负责人 | 对任务结果负责：读现状，判断不确定性、风险和委派是否划算，然后自己做或写短 brief 派出去，最后核实结果、裁决是否完成。 |
| `/finishing` | 收尾 | 给出简短交棒（结果、未完成项、下次开场提示词），并用本地脚本把本次会话提取成去噪 transcript。 |
| `/cleaning` | 清理 | 建议下一次会话用便宜模型执行：把 transcript 压缩归档，同步 architecture / TODO，检查 ADR 死链，清理旧 scratch。 |

另外还有两类被派出去的角色，由脚本调用，你不直接和它们对话：

- **worker**：外部 CLI（`cursor-agent` 或 `codex`）里的模型，按 brief 改代码，不 commit，最终回复就是报告。
- **reviewer**：只读模式的外部模型，读 `git diff` 和 brief，输出结构化 findings。

### 文档各有其家

| 位置（安装后） | 放什么 | 是否进 git |
|---|---|---|
| `AGENTS.md`（仓根） | 项目工具约定 + 文档地图，三种 harness 共用的根指令 | track 模式下进 |
| `.workflow/kit/discipline.md` | 六条常驻纪律（少即是多、别打补丁叠补丁、别乱加兜底……） | 否（机制副本） |
| `.workflow/decisions/NNNN-slug.md` | ADR：稳定的长期决策，不可原地改，只能用新 ADR 取代 | track 模式下进 |
| `.workflow/architecture.md` | 当前设计现状的地图；和 ADR 冲突时以 ADR 为准 | track 模式下进 |
| `.workflow/TODO.md` | 扁平的"下一步"清单，做完即删 | track 模式下进 |
| `.workflow/scratchpad/` | 工单、run 日志、验收单、transcript 等临时产物 | 否 |
| `.workflow/scratchpad/_archive/` | 压缩后的历史对话，本机长期保留，普通清理不删 | 否 |

---

## 前置依赖

| 依赖 | 用途 |
|---|---|
| bash、git、coreutils（`timeout`、`sha256sum`） | 所有脚本 |
| `jq` | `run_worker.sh` 解析 token 用量 |
| Python 3（只用标准库） | 文档检查、transcript 提取与归档。默认通过 `uv run python` 调用，没有 uv 就把 `WF_PY` 改成 `python3` |
| 至少一个主 agent：Claude Code / Codex / Cursor | 运行 `/bs` `/planner` 等 skill |
| 至少一个派单 CLI：`cursor-agent` 和/或 `codex` | worker 和 reviewer 外呼；需已登录 |

> 只用 `/bs`、`/finishing`、`/cleaning`，或者 planner 全部自己动手时，可以不装派单 CLI。

---

## 快速上手

### 1. 装进你的项目

```bash
git clone <本仓地址> ~/tools/ai-workflow

# 在目标项目里执行（默认 --track --backends cc）
~/tools/ai-workflow/install.sh /path/to/your-project
```

常用选项：

```bash
# 同时给 Claude Code 和 Codex 建入口
install.sh --backends cc,codex /path/to/your-project

# 工作流文件完全不进版本库（适合不想让团队看到这些文件的仓库）
install.sh --no-track /path/to/your-project
```

### 2. 填本机配置

```bash
cd /path/to/your-project
cp .workflow/kit/workflow.env.example .workflow/workflow.env
```

编辑 `.workflow/workflow.env`：

```bash
WF_TEST_CMD="uv run pytest"      # 你的项目怎么跑测试，比如 "npm test"、"go test ./..."
WF_PY="uv run python"            # 怎么跑 python；没有 uv 就写 "python3"

# 派单模型，写法为「后端/模型」，后端只有 cursor | codex，省略前缀时默认 cursor
WF_WORKER_MODEL="cursor/composer-2.5"            # 执行：量大，选最便宜的
WF_REVIEW_MODEL="cursor/cursor-grok-4.6-high"    # 默认审查：和 worker 不同家族
WF_REVIEW_MODEL_STRONG="codex/gpt-5.6-terra"     # 更强的审查 / 第二审
```

注意：`cursor/`、`codex/` 指的是**派单用哪个 CLI**，和模型属于哪家无关。审查模型要和 worker 属于不同的模型家族。

可选的超时变量（单位秒，括号里是默认值）：`WF_TIMEOUT_WORKER`（1800）、`WF_TIMEOUT_REVIEW`（1200）、`WF_TIMEOUT_TEST`（600）、`WF_TIMEOUT_CHECK_DOCS`（120）。

### 3. 补项目信息

- 在 `AGENTS.md` 的「项目工具约定」里写清本项目技术栈。
- 按需新建空的 `.workflow/architecture.md` 和 `.workflow/TODO.md`。
- **Claude Code 用户**：根指令文件是 `AGENTS.md`，安装器不会生成 `CLAUDE.md`。需要在 Claude Code 里开启能加载 `AGENTS.md` 的 Project instructions 设置，见[官方说明](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md)。

### 4. 跑第一轮

在项目里打开主 agent：

```text
/bs 我们的缓存层该用什么方案？          # 有设计问题：先发散，产出 ADR-0001
/planner 按 ADR-0001 实现缓存层          # 落地：planner 自己做或派单
/finishing                               # 收尾：交棒 + 提取 transcript
```

下次会话开头（建议切到便宜模型）：

```text
/cleaning .workflow/scratchpad/PL-<会话UUID>/transcript.md
```

然后把上次交棒里的「下 session 开场提示词」贴进去，继续干活。

---

## 一轮工作是怎么转的

```text
bs         发散方案 → 异构模型红队 → 写 ADR → 再红队 → 用户拍板 accepted
planner    读目标和现状 → 分诊 → 自己做 或 写 brief 派单
           → 读结果、核实关键调用链 → 裁决 → 按需返工
worker     在 brief 目标和边界内实现，回报结果、偏离和矛盾
reviewer   只读审查实际改动，输出结构化 findings
finishing  交棒 → 提取本次会话的 transcript
cleaning   （下次会话）压缩归档 → 同步 architecture/TODO → 查死链 → 清旧 scratch
```

不是每项任务都要走完整流程。简单的局部修改，planner 直接自己改就行；遇到设计问题才需要 `/bs`；审查和第二审只在风险值得时才加。

### planner 派单：写一份 brief

brief 放在 `.workflow/scratchpad/PL-<会话UUID>/WO-current.md`，模板见 `.workflow/kit/skills/planner/WO-TEMPLATE.md`：

```markdown
# 给缓存层加 TTL

目标：缓存条目在写入 10 分钟后自动过期，读到过期条目时回源

依据与边界：ADR-0003；只改 src/cache/，不动公共接口

交付与证据：单测覆盖过期与回源；一次真实调用的日志片段
```

入口闸门只检查一件事：必须有一行内容非空、且不是 `<占位符>` 的 `目标：…`（兼容旧格式 `本单服务 → ADR-NNNN 的意图: …`）。

### run_worker.sh 的四种用法

```bash
# 默认：worker 执行 + 测试 + 文档检查 + 越界检查 + 独立施工审
.workflow/kit/scripts/run_worker.sh .workflow/scratchpad/PL-<id>/WO-current.md

# 探索 / 局部任务：只执行，结果交回 planner 判断（仍做越界检查，不跑测试和审查）
SKIP_REVIEW=1 .workflow/kit/scripts/run_worker.sh <brief>

# 已经有实现，只要独立审查和机器检查
REVIEW_ONLY=1 .workflow/kit/scripts/run_worker.sh <brief>

# 动工前的定向方案审：只审 brief 本身，不执行、不跑检查
WO_REVIEW=1 .workflow/kit/scripts/run_worker.sh <brief>

# 位置参数可覆盖模型：<brief> [执行模型] [审查模型] [第二审模型]
# 给第 4 个参数就是双审（两个审查员并行跑）
.workflow/kit/scripts/run_worker.sh <brief> "" "" "$WF_REVIEW_MODEL_STRONG"
```

每次运行在 `.workflow/scratchpad/runs/<时间戳>-<pid>/` 下留档：

| 文件 | 内容 |
|---|---|
| `brief.md` | 本轮输入快照（worker 和所有 reviewer 用的是同一份） |
| `report.md` | worker 报告（自述，需要 planner 核实） |
| `review.md` / `review2.md` | 审查单 |
| `run.log` | 完整原始流与 token 用量 |
| `.done` | 产物已定、可以按时间清理。**不代表放行** |

### 结果状态 STATUS

| STATUS | 含义 | 下一步 |
|---|---|---|
| `review_complete` | 没有 blocking finding，适用的机器检查都通过 | planner 结合实际结果判断目标是否真的达成 |
| `review_blocked` | 有 blocking finding，或测试 / 文档检查 / 越界检查失败 | 核实问题；修实现、改方案，或给出理由不采纳 |
| `review_skipped` | 这轮没有独立审查（`SKIP_REVIEW=1`） | 自己安排与风险相称的验证 |
| `infra_failed` | 外呼失败、超时、审查单无法解析（脚本退出码 2） | 看日志和工作树；只是审查员失败时，用 `REVIEW_ONLY=1` 重派，不用重跑 worker |

STATUS 只是信息，不会拦住 commit。最终是否放行由 planner 判断：测试全绿只能说明跑过的断言成立。

### 会话收尾与归档

```bash
# /finishing 内部执行：从本机 CC / Codex / Cursor 日志提取对话（只保留用户和助手的正文，常见凭证打码）
$WF_PY .workflow/kit/scripts/transcribe_session.py --backend cc \
  --session <完整UUID> --out .workflow/scratchpad/PL-<UUID>/transcript.md
#   找不到或有多个匹配时：用 --input <jsonl 路径> 代替 --session；--tools 保留工具调用骨架

# /cleaning 内部执行：模型先写 transcript.compact.md，再归档（带来源哈希）
$WF_PY .workflow/kit/scripts/archive_transcript.py \
  --source <transcript.md> --compact <transcript.compact.md> --slug add-cache-ttl
#   → .workflow/scratchpad/_archive/NN-YYYYMMDD-add-cache-ttl.transcript.compact.md

# 删源目录前先校验归档完整、来源一致
$WF_PY .workflow/kit/scripts/archive_transcript.py --source <transcript.md> --verify <归档文件>
```

归档在本机长期保留，但被 git 忽略，**不等于备份**。

---

## 闸门与边界

| 闸门 | 什么时候触发 | 检查什么 |
|---|---|---|
| 目标闸门 | `run_worker.sh` 入口 | brief 里有没有非空的 `目标：` 行 |
| 越界检查 | worker 执行后 | worker 是否改了 `.workflow/decisions/`、`.workflow/architecture.md`、`AGENTS.md`（这些只由负责人写）。改了就是 `review_blocked` |
| 文档检查 | 施工审时（`--changed`）、`git commit` 时（pre-commit，`--staged`） | ADR frontmatter、文件名与 id 一致、`ADR-NNNN` 引用没有断链 |

也可以手动全仓检查：`$WF_PY .workflow/kit/scripts/check_docs.py`。

其他约定：worker 不 commit；主 agent 只在用户明确授权时 commit；`run_worker.sh` 审查的是相对 HEAD 的**全部**改动（包括 untracked 文件），所以派单前工作树里已有的改动，要么明确纳入本次范围，要么先隔离。

---

## 安装后的项目布局

```text
your-project/
├── AGENTS.md                    # 根指令：工具约定 + 文档地图
├── .workflow/
│   ├── kit/                     # 机制副本（每次 install 整体覆盖）
│   │   ├── discipline.md
│   │   ├── skills/{bs,planner,finishing,cleaning}/
│   │   ├── scripts/             # run_worker / call_agent / check_docs / transcribe / archive …
│   │   ├── git-hooks/pre-commit
│   │   ├── settings.json
│   │   └── workflow.env.example
│   ├── decisions/0000-template.md   # ADR 模板
│   ├── architecture.md  TODO.md     # 自己建
│   ├── workflow.env                 # 本机配置
│   ├── scratchpad/                  # 临时产物（含 _archive/）
│   └── VERSION                      # 装的是哪个 tag / commit
├── .claude/skills → ../.workflow/kit/skills   # --backends cc
├── .agents/skills → ../.workflow/kit/skills   # --backends codex
└── .git/hooks/pre-commit
```

### track 和 no-track

两种模式的物理布局完全相同，区别只在写进 `.git/info/exclude` 的内容。安装器不会动你已提交的 `.gitignore`。

| 模式 | 本地忽略 | 进 git |
|---|---|---|
| `--track`（默认） | `.workflow/kit/`、`.workflow/workflow.env`、`.workflow/scratchpad/`、后端入口目录 | `AGENTS.md`、`decisions/`、`architecture.md`、`TODO.md`、`VERSION` |
| `--no-track` | 整个 `.workflow/`、`AGENTS.md`、后端入口目录 | 无 |

no-track 模式下 ADR 只存在本机，丢了就没了。换模式时重跑 install 即可，exclude 块每次都会重写。

### 后端入口 `--backends`

| 值 | 建什么 |
|---|---|
| `cc`（默认） | `.claude/skills` 软链，首次安装时额外放一份 `.claude/settings.json` |
| `codex` | `.agents/skills` 软链 |
| `cursor` | Cursor 能读 `.claude`/`.agents`，不单独建入口；只选 cursor 时借用 `.claude/skills` |

skill 真源只有一份（`.workflow/kit/skills`），各入口都是指向它的相对软链。

### 升级与重装

改了本仓以后，在目标项目上重跑同一条 `install.sh` 命令。只有 `.workflow/kit/` 和 `VERSION` 会被覆盖；ADR、architecture、TODO、`workflow.env`、scratchpad 和已有的 `AGENTS.md` 都不会动。

安装时的几个提示：

- 目标项目已有 `.git/hooks/pre-commit`：不会覆盖，需要手动并入 `.workflow/kit/git-hooks/pre-commit`。
- 已有 `CLAUDE.md`：如果只是本工作流旧版生成的 `@AGENTS.md` 入口或软链，会被移除；项目自己写的内容保留，并提示你合入 `AGENTS.md`。
- 目标还不是 git 仓：跳过 exclude 和 hook，`git init` 后重跑即可。

没有卸载脚本。手动卸载的步骤：删 `.workflow/kit/`（或整个 `.workflow/`）、`.claude/skills`、`.agents/skills`、`.git/hooks/pre-commit`，再删掉 `.git/info/exclude` 里 `ai-workflow BEGIN` 到 `END` 之间的内容。

---

## 本仓结构（维护者）

```text
ai-workflow/
├── install.sh        # 安装 / 升级到目标项目
├── kit/              # 机制本体，整包 copy 成目标项目的 .workflow/kit/
│   ├── discipline.md
│   ├── skills/       # bs / planner / finishing / cleaning（含 brief 模板、worker/审查 preamble、红队提示词）
│   ├── scripts/      # run_worker.sh  call_agent.sh  derive_status.sh  lib_timeout.sh
│   │                 # check_docs.py  transcribe_session.py  archive_transcript.py
│   │   └── tests/    # run-all.sh 及各测试
│   ├── git-hooks/pre-commit
│   ├── settings.json
│   └── workflow.env.example
├── seed/             # 首次安装时放进目标项目：AGENTS.md、decisions/0000-template.md
└── docs/             # 只给维护者看，不会装进目标项目
    ├── design.md             # 设计蓝图与取舍
    ├── dot-workflow-layout.md# .workflow/ 布局契约
    ├── failure-modes.md      # 已知失效模式（改机制前必读）
    ├── MAINTAINERS.md        # 维护流程
    └── history/              # 历史诊断与计划归档，不是现行规范
```

脚本分工：

- `run_worker.sh`：编排。负责目标闸门、brief 快照、执行、越界检查、测试和文档检查、并行审查、派生 STATUS、汇总回显。
- `call_agent.sh`：统一外呼 `cursor-agent` / `codex`，流式写日志，按角色超时并回收整棵进程树。退出码：0 正常，124 超时，3 agent 报错，4 流截断。
- `derive_status.sh`：用机器检查结果和审查单纯派生 STATUS。
- `check_docs.py`：检查 ADR 结构与断链，支持全仓、`--changed`、`--staged` 三种范围。
- `transcribe_session.py` / `archive_transcript.py`：提取三种后端的对话；归档时附带来源哈希，并提供校验。

### 修改机制

1. 只改本仓的 `kit/`（或 `install.sh`），不要在目标项目的 `.workflow/kit/` 副本上改。
2. 改脚本、hook 或安装逻辑之前，先读 `docs/failure-modes.md`。
3. push 前在本地跑全部测试（不上 CI）：

   ```bash
   bash kit/scripts/tests/run-all.sh      # WF_PY 可覆盖 python 解释器
   ```

4. 在目标项目上重跑 `install.sh` 推送更新。

更完整的设计理由见 [docs/design.md](docs/design.md)，维护约定见 [docs/MAINTAINERS.md](docs/MAINTAINERS.md)。
