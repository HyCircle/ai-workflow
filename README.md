# ai-workflow

[English](README.en.md) | 中文

一套可以装进任何 git 项目的**半自动多 agent 开发工作流**。由你正在对话的主 agent（Claude Code、Codex 或 Cursor）当"负责人"，按需把施工派给便宜的外部模型，再交给另一家模型独立审查。长期设计记成 ADR，每次会话由亲历者写成归档，同类任务的经验沉淀进手册。

这个仓库是这套机制的**唯一源头**，以命令行工具 `wf` 的形式安装，再用 `wf init` 装进要开发的项目。

---

## 它解决什么问题

- **贵模型的时间花在判断上**：主 agent 负责理解目标、拆解问题、裁决结果；写代码、跑实验可以派给便宜模型。
- **不让同一个模型给自己打分**：审查默认交给和执行者不同家族的模型，比如 Cursor Composer 写、Grok 审，必要时再加 GPT 第二审。
- **上下文按需读取**：根指令 `AGENTS.md` 只是一张路由表，写明什么情况读什么文档，agent 不预读整套文档。
- **设计保持全局自洽**：ADR 每个主题一份，记录当前设计，是可以修改的慢层；项目变复杂时用 `/holistic` 整体审查、合并和删减。
- **结论经得起质疑**：实验类结论交 `/challenge` 找反证，施工审只看改动，不替代它。
- **经验有去处**：会话里学到的东西按性质归位——同类任务的做法进手册，你的协作要求进 `AGENTS.md`，项目事实进项目文档；都放在仓内，所有 agent 都读得到。

## 核心概念

### 六个角色（以 skill 形式提供，在主 agent 里用斜杠命令调用）

| 命令 | 角色 | 做什么 |
|---|---|---|
| `/bs` | 脑暴 | 先记下你的意图和原话，对设计问题提出 3 个以上真正不同的方案，和你讨论收敛；需要时请另一家模型红队，意见逐条裁决、经你确认后才改设计；写成或并入 ADR，定稿前由没参与讨论的模型冷读。不写代码。 |
| `/planner` | 负责人 | 对任务结果负责：读现状，判断不确定性、风险和委派是否划算，然后自己做或写短 brief 派出去，最后核实结果、裁决是否完成。 |
| `/finishing` | 收尾 | 本轮亲历者写一份会话归档（用户原话、决定与依据、已验证与未验证的结论、未完成项），把学到的东西分到各自去处（手册候选默认没有、最多两条），按格式更新 TODO，回复交棒和下次开场提示词。 |
| `/cleaning` | 清理 | 按需运行（攒几轮或文档明显过时时）：筛选近期归档的手册候选，巡检手册、协作约定和 agent 私有记忆，逐条理解并整理 TODO，在项目可写范围内全仓巡检，清理旧 scratch 和旧归档；机械项直接改，判断项出一份确认清单，你勾选后执行。 |
| `/holistic` | 整体审 | 项目变复杂或一个大阶段结束时用强模型执行：通读 architecture、全部 ADR 和关键代码，找跨 ADR 的冲突、重叠、接缝问题和多余复杂度，给出合并、删除、简化的整体方案，你确认后执行。 |
| `/challenge` | 结论质疑 | 实验、基准比较、性能或数值结论，以及「X 比 Y 好」「已验证完成」这类结论，交强模型专门找反证并亲自复现，最多两轮；你逐条结算，汇报分列已支持与未验证的结论。普通编码任务不用。 |

另外两类角色由 `wf` 外呼，你不直接和它们对话：

- **worker**：外部 CLI（`cursor-agent`、`codex` 或 `claude`）里的模型，按 brief 在当前工作树改代码，不 commit，最终回复就是报告。
- **reviewer**：只读的外部模型，读当前改动和 brief，输出问题清单。

### 文档各有其家

| 位置（安装后） | 放什么 | 是否进 git |
|---|---|---|
| `AGENTS.md`（仓根） | 项目工具约定、协作约定、文档路由（什么情况读什么）与手册清单，三种 harness 共用的根指令 | track 模式下进 |
| `.workflow/kit/discipline.md` | 六条常驻纪律（少即是多、别打补丁叠补丁、别乱加兜底……） | 否（机制副本） |
| `.workflow/decisions/NNNN-slug.md` | ADR：当前设计，每个主题一份；设计变了直接改正文，整体变了整篇重写 | track 模式下进 |
| `.workflow/architecture.md` | 系统现状的全局图；和 ADR 冲突时以 ADR 为准 | track 模式下进 |
| `.workflow/TODO.md` | 下一步、等别人的事和已知问题；每条最多两行，不写进展，做完即删 | track 模式下进 |
| `.workflow/patterns/` | 按任务类型的手册：步骤、坑、验证清单；清单列在 `AGENTS.md` | track 模式下进 |
| `.workflow/scratchpad/` | brief、run 产物等临时文件 | 否 |
| `.workflow/scratchpad/_archive/` | finishing 写的会话归档，本机长期保留，普通清理不删 | 否 |

---

## 前置依赖

| 依赖 | 用途 |
|---|---|
| Linux、macOS 或 WSL；git | 运行环境 |
| [uv](https://docs.astral.sh/uv/)（或 pipx）、Python 3.10+ | 安装 `wf`；`wf` 只用标准库 |
| 至少一个主 agent：Claude Code / Codex / Cursor | 运行 `/bs` `/planner` 等 skill |
| 派单 CLI：`cursor-agent`、`codex`、`claude` 任选，需已登录 | worker、reviewer 与红队外呼 |

> 不派单、不做红队时，可以不装派单 CLI。

---

## 快速上手

### 1. 安装 `wf` 并装进项目

```bash
uv tool install git+<本仓地址>        # 全局装上 wf 命令；升级用 uv tool upgrade ai-workflow
cd /path/to/your-project
wf init                               # 默认 track 模式、只建 Claude Code 入口
```

常用选项：

```bash
wf init --backends cc,codex           # 同时给 Claude Code 和 Codex 建入口
wf init --no-track                    # 工作流文件完全不进版本库
```

重跑 `wf init` 就是升级：只覆盖 `.workflow/kit/`，ADR、architecture、TODO、patterns、`workflow.env` 和已有的 `AGENTS.md` 都不动。

### 2. 填本机配置

`wf init` 首次运行会生成 `.workflow/workflow.env`，按项目编辑：

```bash
WF_TEST_CMD="uv run pytest"                      # 怎么跑测试，比如 "npm test"、"go test ./..."

# 派单模型，写法为「后端/模型」，后端 cursor | codex | claude，省略前缀时默认 cursor
WF_WORKER_MODEL="cursor/composer-2.5"            # 执行：量大，选最便宜的
WF_REVIEW_MODEL="cursor/cursor-grok-4.6-high"    # 默认审查：和 worker 不同家族
WF_REVIEW_MODEL_STRONG="codex/gpt-5.6-terra"     # 更强的审查 / 第二审
```

`cursor/`、`codex/`、`claude/` 指的是**用哪个 CLI 外呼**，和模型属于哪家无关。审查模型要和 worker 属于不同的模型家族。`wf` 命令里可以用 `worker`、`review`、`strong` 指代这三档。

### 3. 补项目信息

- 在 `AGENTS.md` 的「项目工具约定」里写清本项目技术栈。
- 按需新建 `.workflow/architecture.md` 和 `.workflow/TODO.md`。
- **Claude Code 用户**：根指令文件是 `AGENTS.md`，需要在 Claude Code 里开启能加载 `AGENTS.md` 的 Project instructions 设置，见[官方说明](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md)。

### 4. 跑第一轮

```text
/bs 我们的缓存层该用什么方案？          # 有设计问题：先发散，产出 ADR
/planner 按 ADR-0001 实现缓存层          # 落地：planner 自己做或派单
/finishing                               # 收尾：写归档、更新 TODO、交棒
```

下次会话把交棒里的「下 session 开场提示词」贴进去，继续干活。攒几轮后跑一次 `/cleaning`；项目变复杂时用强模型跑 `/holistic`。

---

## 一轮工作是怎么转的

```text
bs         记下意图 → 发散方案 → 讨论收敛 → （按需）红队 → 裁决表交用户
           → 写或并入 ADR → 冷读 → 用户拍板 accepted
planner    读目标和现状 → 分诊 → 自己做 或 写 brief 派单
           → 读结果、核实关键调用链 → 裁决 → 按需返工
worker     在 brief 目标和边界内实现，回报结果、偏离和矛盾
reviewer   只读审查实际改动，输出问题清单
finishing  写归档 → 学到的东西分去处 → 按格式更新 TODO → 交棒
cleaning   （按需）筛手册候选 → 知识层与 TODO → 全仓巡检 → 清旧 scratch 与归档
           → 直接修机械项、判断项出确认清单
holistic   （按需）通读全局 → 找跨 ADR 问题 → 整体方案 → 用户确认后执行
challenge  （实验类结论）结论清单 → 强模型找反证 → 逐条结算 → 分列已支持与未验证
```

不是每项任务都要走完整流程。简单的局部修改，planner 直接自己改；遇到设计问题才需要 `/bs`；审查和第二审只在风险值得时才加。

### planner 派单：写一份 brief

brief 放在 `.workflow/scratchpad/PL-<会话UUID>/WO-current.md`，模板见 `.workflow/kit/skills/planner/WO-TEMPLATE.md`：

```markdown
# 给缓存层加 TTL

目标：缓存条目在写入 10 分钟后自动过期，读到过期条目时回源

依据与边界：ADR-0003；只改 src/cache/，不动公共接口

交付与证据：单测覆盖过期与回源；一次真实调用的日志片段
```

### `wf` 命令

```bash
wf run <brief>                      # worker 施工，结果交回 planner 判断
wf run <brief> --review             # 施工 + 测试 + 独立审查
wf review <brief> [--model strong]  # 对当前工作树跑测试 + 独立审查；第二审就换模型再跑一次
wf ask <模型> <提示词文件...> [--out 文件] [--write]
                                    # 外呼原语，默认只读：红队、冷读、方案审、结论质疑都用它
wf init [--no-track] [--backends cc,codex,cursor]
```

模型参数可写 `worker` / `review` / `strong` 或「后端/模型」。worker 与 reviewer 的提示词开头都附上 discipline。

每次 `run` / `review` 在 `.workflow/scratchpad/runs/<时间戳>-<随机后缀>/` 下留档：

| 文件 | 内容 |
|---|---|
| `brief.md` | 本轮输入快照 |
| `report.md` | worker 报告（自述，需要 planner 核实） |
| `review.md` | 审查单 |
| `test.log` | 测试输出 |
| `*-prompt.md`、`*.log` | 实际发出的提示词与原始输出流（可 `tail -f`） |
| `summary.md` | 与命令输出相同的汇总：各外呼退出码与用量、越界检查、测试结果、报告、审查单、git status |
| `.done` | 产物已定、可以按时间清理 |

命令退出码：0 表示各外呼正常结束（不代表通过），2 表示有外呼失败。是否放行由 planner 判断：测试全绿只能说明跑过的断言成立。

**越界检查**：worker 施工前后对比负责人著作的文件（`.workflow/decisions/`、`architecture.md`、`patterns/`、`AGENTS.md`），worker 动过的会列在汇总里。派单前已有的改动不算。

**只读**：cursor 用它的只读模式；claude 禁用编辑类工具；codex 靠提示词约束。三者都不启用沙箱。

### 会话收尾与归档

`/finishing` 由本轮的主 agent 直接写归档：`.workflow/scratchpad/_archive/NN-YYYYMMDD-<slug>.md`，首行记录后端、会话 UUID、分支与 HEAD。写的人就是做事的人，看过工具输出和中途的失败，不需要事后再从日志提取和压缩。用户的约束、纠正和拍板按原句引用；结论分开写已验证和未验证。

归档是冷存档，平时不读，需要追溯时再看。下次做同类任务会被读到的经验，放在 `patterns/` 手册里。旧归档在 `/cleaning` 时列出可删的，由你确认。归档在本机长期保留，但被 git 忽略，**不等于备份**。

---

## 安装后的项目布局

```text
your-project/
├── AGENTS.md                    # 根指令：工具约定 + 文档路由
├── .workflow/
│   ├── kit/                     # 机制副本（每次 wf init 整体覆盖）
│   │   ├── discipline.md
│   │   ├── skills/{bs,planner,finishing,cleaning,holistic,challenge}/
│   │   └── workflow.env.example
│   ├── decisions/                   # ADR，bs 著作时创建
│   ├── architecture.md  TODO.md     # 自己建
│   ├── patterns/                    # 手册，cleaning 合入时创建
│   ├── workflow.env                 # 本机配置
│   └── scratchpad/                  # 临时产物（含 runs/、_archive/）
├── .claude/skills → ../.workflow/kit/skills   # --backends cc
└── .agents/skills → ../.workflow/kit/skills   # --backends codex
```

### track 和 no-track

两种模式的物理布局完全相同，区别只在写进 `.git/info/exclude` 的内容。不会动你已提交的 `.gitignore`。

| 模式 | 本地忽略 | 进 git |
|---|---|---|
| track（默认） | `.workflow/kit/`、`.workflow/workflow.env`、`.workflow/scratchpad/`、后端入口目录 | `AGENTS.md`、`decisions/`、`architecture.md`、`TODO.md`、`patterns/` |
| `--no-track` | 整个 `.workflow/`、`AGENTS.md`、后端入口目录 | 无 |

no-track 模式下 ADR 只存在本机，丢了就没了。换模式时重跑 `wf init`，exclude 块每次都会重写。

### 后端入口 `--backends`

| 值 | 建什么 |
|---|---|
| `cc`（默认） | `.claude/skills` 软链 |
| `codex` | `.agents/skills` 软链 |
| `cursor` | Cursor 能读 `.claude`/`.agents`，不单独建入口；只选 cursor 时借用 `.claude/skills` |

skill 真源只有一份（`.workflow/kit/skills`），各入口都是指向它的相对软链。入口位置已有别的内容时 `wf init` 不覆盖，只提示。

没有卸载命令。手动卸载：删 `.workflow/kit/`（或整个 `.workflow/`）、`.claude/skills`、`.agents/skills`，再删掉 `.git/info/exclude` 里 `ai-workflow BEGIN` 到 `END` 之间的内容。

---

## 本仓结构（维护者）

```text
ai-workflow/
├── pyproject.toml    # 包定义，命令入口 wf
├── wf/               # 命令行工具（纯标准库）
│   ├── cli.py        # 命令入口与配置读取
│   ├── agent.py      # 外呼原语：三个后端、超时杀进程树、提取最终回复
│   ├── dispatch.py   # run / review：施工、越界检查、测试、审查、汇总
│   ├── install.py    # init
│   ├── kit/          # 机制本体，wf init 整包复制成目标项目的 .workflow/kit/
│   │   ├── discipline.md
│   │   ├── skills/   # bs / planner / finishing / cleaning / holistic / challenge（含 brief 模板、worker/审查/质疑者开场白、红队与冷读提示词）
│   │   └── workflow.env.example
│   └── seed/         # 首次安装时放进目标项目：AGENTS.md
├── tests/            # 用假 CLI 替代模型的端到端测试
└── docs/             # 只给维护者看，不会装进目标项目
    ├── design.md             # 设计蓝图与取舍
    ├── failure-modes.md      # 已知失效模式（改机制前必读）
    ├── MAINTAINERS.md        # 维护流程
    └── history/              # 已实施提案的证据与推理，不是现行规范
```

### 修改机制

1. 只改本仓，不要在目标项目的 `.workflow/kit/` 副本上改。
2. 改 `wf/` 的代码之前，先读 `docs/failure-modes.md`。
3. 提交前跑测试：`uv run --group dev pytest tests -q`。
4. 本机更新：`uv tool install --reinstall .`，再在目标项目里重跑 `wf init`。
