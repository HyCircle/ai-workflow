# AGENTS.md — 本项目 agent 指令(常驻)

> 所有 agent(Claude Code / Cursor / Codex / 无头 worker)进项目**第一份读**的东西。
> `CLAUDE.md` 软链接到本文件,一份内容三家共读。保持短。
>
> **常驻工作纪律(六条 + 脊椎)= 工作流内核,在 `agent-discipline.md`**(kit 维护、投影进来、勿改)。
> **进项目先读 `agent-discipline.md`,再读本文件**(项目专属的工具约定 + 文档地图)。

## 项目工具约定

具体命令与模型档位是**单机 / 项目级配置**,唯一改 `.claude/workflow.env`(gitignored,换项目 / 换模型只动那一处)。scripts 从它取默认值,skill 里的命令示例以它为准。**当前项目栈:`<填,如 Python + uv>`**——在 `.claude/workflow.env` 填 `WF_TEST_CMD` / `WF_PY`。

**派单模型分档**(便宜劳力,写法「后端/模型」,后端 `cursor|codex`,省前缀=cursor):
- `WF_WORKER_MODEL` — 默认执行(量大最省)。
- `WF_REVIEW_MODEL` — 默认验收(**跨厂异构** worker,真独立第二双眼)。
- `WF_REVIEW_MODEL_STRONG` — 高危双验收的第二审 / 硬骨头。

换型号 / 换厂就改这三个别名的值,不要在脚本或 skill 里写死具体型号。

## 文档系统(冷启动读这张地图)

一类信息一个家:
- **agent-discipline.md** = 常驻六条纪律(工作流内核,kit 维护)。
- **AGENTS.md**(本文件)= 项目工具约定 + 本地图。
- **architecture.md** = 当前设计现状/地图(各 ADR 的合成视图,冲突时 ADR 赢)。
- **decisions/**(ADR)= 冻结决策(why + 可测契约 + 证据),`ADR-NNNN` 引用(ADR 多了再加 `index.md`)。
- **TODO.md** = 扁平的"下一步";设计债不进这、进 ADR。
- **scratchpad/** = 临时产物(gitignored)。

冷启动顺序:agent-discipline(纪律)→ AGENTS(本页)→ architecture(现状)→ TODO(下一步)→ 相关 ADR。
