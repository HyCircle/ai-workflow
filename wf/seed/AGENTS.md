# AGENTS.md — 本项目 agent 指令(常驻)

> 本文件 = 项目工具约定 + 文档路由，CC / Codex / Cursor 共用的根指令入口。只放指向，不放状态与设计内容。
> **进项目先读 discipline**(`.workflow/kit/discipline.md`,六条纪律 + 脊椎)。其余文档按下表在任务需要时读，不预读。

## 项目工具约定

具体命令与模型档位是**单机 / 项目级配置**,唯一改 workflow.env(本地忽略,换项目 / 换模型只动那一处)。`wf` 命令从它取默认值。**当前项目栈:`<填,如 Python + uv>`**——在 `.workflow/workflow.env` 填 `WF_TEST_CMD`。

**派单模型分档**(便宜劳力,写法「后端/模型」,后端 `cursor|codex|claude`,省前缀=cursor;`wf` 命令里可用 `worker` / `review` / `strong` 指代):
- `WF_WORKER_MODEL` — 默认执行(量大最省)。
- `WF_REVIEW_MODEL` — 独立审查默认档，选择与 worker 不同的模型家族。
- `WF_REVIEW_MODEL_STRONG` — 需要更强判断或第二审有明确收益时使用。

换型号 / 换厂就改这三个别名的值,不要在 skill 里写死具体型号。

## 文档路由(skills 正文用简写,以此为准)

| 简写 | 真路径 | 装什么 | 什么时候读 |
|---|---|---|---|
| discipline | `.workflow/kit/discipline.md` | 六条纪律 + 脊椎(kit 维护) | 每次 |
| architecture | `.workflow/architecture.md` | 系统现状全局图：模块边界、数据模型、关键不变量、已能用的功能 | 跨模块改动、改设计、需要全局判断时 |
| decisions | `.workflow/decisions/` | ADR：每个主题一份现行长期决定，引用 `ADR-NNNN` | 动到某个决定涉及的边界或契约时，按文件名挑相关的读 |
| TODO | `.workflow/TODO.md` | 下一步、未完成项、已知问题 | 接续之前的工作、找下一步时 |
| patterns | `.workflow/patterns/` | 按任务类型的手册：步骤、坑、验证清单 | 当前任务属于某份手册的类型时(看文件名与文件头) |
| 会话归档 | `.workflow/scratchpad/_archive/` | finishing 写的历史会话记录(本机保留、忽略) | 用户要求或需要追溯某次会话时 |
| workflow.env | `.workflow/workflow.env` | 本机命令 / 模型档(忽略) | 跑命令、派单时 |
| scratchpad | `.workflow/scratchpad/` | 临时产物(忽略) | — |

局部修改直接读相关代码、测试和数据。
