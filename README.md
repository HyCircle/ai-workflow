# ai-workflow —— 半自动多 agent 工作流(可移植机制)

「bs / planner / finishing / cleaning 四角色 + 跨家族异构派单 / 验收 + 闸门(脚本 + git pre-commit) + ADR 文档系统」的**独立机制仓**:机制的单一事实源在此,经 `install.sh` 装进各项目。

## 为什么这么设计(极简)

- **按收益分工**:负责人自主选择自做或委派，按结果质量、交接、返工与外呼的总成本判断收益。
- **著作,不追加**:长期知识各归其家(ADR / architecture / AGENTS / discipline);worker 只写代码 + scratchpad,不往中央池堆。
- **durable / ephemeral 分离**:决策与证据进 git;工单 / brief 快照 / 验收单 / run 日志进 scratchpad,消费完 GC。精炼对话留 `_archive/`，本机长期保留，普通 GC 不清。
- **闸门在脚本**:目标行、越界、文档结构由 `run_worker.sh` + `pre-commit` 单点强制,不靠各 harness 自觉。
- **按任务分诊**:planner 分别判断不确定性、风险和委派收益，再选择自做、短 brief 委派、定向审查或双审。
- **对结果负责**:先取得与当前不确定性对应的反馈；worker 提交结果、偏离和矛盾的短报告，planner 自主核实整体与关键调用链。

完整 rationale、文档五家、闭环与 derive 语义见 **[docs/design.md](docs/design.md)**(给人 / 维护者读,不 seed 进消费项目、agent 不引用)。

## 结构(SOT 与消费仓 `.workflow/kit/` 同构)

- `kit/` —— 机制层,整包 copy 进消费仓 `.workflow/kit/`:
  - `kit/discipline.md`:常驻**六条纪律 + 脊椎**(全固化核)。worker/验收由 `run_worker.sh` 注进 prompt;交互 harness 经 AGENTS(文档地图)+ skills「开工先读」引到 discipline。
  - `kit/skills/`:bs·planner·finishing·cleaning(**真源一份**;install 给后端建软链 `.claude/skills`、`.agents/skills`)。
  - `kit/scripts/`:派单、外呼、文档守护、三后端转写(`transcribe_session.py`)、归档与完整性校验(`archive_transcript.py`) + `tests/`。
  - `kit/settings.json`、`kit/workflow.env.example`、`kit/git-hooks/pre-commit`。
- `seed/` —— 新仓 seed:`AGENTS.md`(仓根)、`decisions/0000-template.md`(→ `.workflow/decisions/`)。
- `docs/design.md` —— 设计蓝图;`docs/dot-workflow-layout.md` —— 投影布局契约。
- `install.sh` —— 装进 / 更新消费项目。

## 用法

```bash
# --track(默认)/ --no-track; --backends cc,codex,cursor(默认 cc)
/path/to/ai-workflow/install.sh [--track|--no-track] [--backends cc,codex] /path/to/target-project
cd /path/to/target-project
cp .workflow/kit/workflow.env.example .workflow/workflow.env    # 填模型/命令档
```

两种 track 模式只差 exclude 粒度(物理位置永在 `.workflow/`):
- **track**:设计资产(`.workflow/decisions/`、`architecture.md`、`TODO.md`、`VERSION`) tracked;机制层 + `workflow.env` + `scratchpad` 本地忽略。
- **no-track**:整个 `.workflow/` + 根 `AGENTS.md` 不版本化。

根指令统一使用 `AGENTS.md`。安装器不生成 `CLAUDE.md`；升级只移除旧的一行 `@AGENTS.md` 或指向 `AGENTS.md` 的软链，保留项目自写内容。CC 需启用能加载 AGENTS.md 的 Project instructions 设置，参见 [官方说明](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md)。已有消费仓的 AGENTS 正文不被覆盖，旧文档地图需同步本次入口与归档约定。

收尾使用 `/finishing` 生成去噪 transcript；下一轮用低成本模型执行 `/cleaning <transcript路径>`，每份对话都先压缩归档，再维护文档和清理。提取与压缩规则分别在对应技能内。归档仍属本机忽略文件，不等于 git 备份。

## 新项目 bootstrap

`install.sh` seed 出 `AGENTS.md` 与 `.workflow/decisions/0000-template.md`。补空 `architecture.md` / `TODO.md`、填 `workflow.env`;第一个架构选择走 `/bs` 著作 ADR-0001。

## 维护

- 改机制只动 `kit/` → 消费项目重跑 `install.sh`。见 `docs/MAINTAINERS.md`。
- 改机制前扫 `docs/failure-modes.md`。
