# AGENTS.md — 本项目 agent 指令(常驻)

> 本文件 = 项目工具约定 + 文档地图(留仓根,codex/cursor 直接读);`CLAUDE.md` = 一行 `@AGENTS.md`(CC 的 import,展开得本文全文)。保持短。
> **进项目先读 discipline,再读本文件**(discipline = 六条纪律 + 脊椎,见 `.workflow/kit/discipline.md`)。

## 项目工具约定

具体命令与模型档位是**单机 / 项目级配置**,唯一改 workflow.env(本地忽略,换项目 / 换模型只动那一处)。scripts 从它取默认值,skill 里的命令示例以它为准。**当前项目栈:`<填,如 Python + uv>`**——在 `.workflow/workflow.env` 填 `WF_TEST_CMD` / `WF_PY`。

**派单模型分档**(便宜劳力,写法「后端/模型」,后端 `cursor|codex`,省前缀=cursor):
- `WF_WORKER_MODEL` — 默认执行(量大最省)。
- `WF_REVIEW_MODEL` — 默认验收(**跨厂异构** worker,真独立第二双眼)。
- `WF_REVIEW_MODEL_STRONG` — 高危双验收的第二审 / 硬骨头。

换型号 / 换厂就改这三个别名的值,不要在脚本或 skill 里写死具体型号。

## 文档地图(冷启动读这张表;skills 正文用简写,以此为准)

| 简写 | 真路径 | 装什么 |
|---|---|---|
| discipline | `.workflow/kit/discipline.md` | 六条纪律 + 脊椎(kit 维护) |
| AGENTS | `AGENTS.md`(本页,仓根) | 工具约定 + 本文地图 |
| architecture | `.workflow/architecture.md` | 当前设计现状/地图(冲突时 ADR 赢) |
| decisions | `.workflow/decisions/` | 冻结 ADR;引用 `ADR-NNNN`(多了再加 `index.md`) |
| TODO | `.workflow/TODO.md` | 扁平「下一步」;设计债进 ADR |
| workflow.env | `.workflow/workflow.env` | 本机命令 / 模型档(忽略) |
| kit scripts | `.workflow/kit/scripts/` | 派单 / check_docs 等 |
| scratchpad | `.workflow/scratchpad/` | 临时产物(忽略) |

冷启动顺序:discipline → AGENTS → architecture → TODO → 相关 ADR。
