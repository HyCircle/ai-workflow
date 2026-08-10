# workflow-kit —— 半自动多 agent 工作流(可移植机制)

把「bs / planner / finishing / cleaning 四角色 + 跨家族异构派单 / 验收 + 闸门 hooks + ADR 文档系统」
从 hubpage 提出来的**机制副本**,是将来独立成 repo、装进各项目的雏形。

## 为什么单独一份
`.claude/` 与 `scripts/workflow/` 在每个项目里是**已安装副本(gitignored)**,不在原地进版本库。
机制的版本管理**只在这里**;各项目经 `install.sh` 装入,live 改动经 `snapshot-from.sh` 回抓再提交。

## 结构
- `claude/` → 装进项目 `.claude/`:`skills/`(bs·planner·finishing·cleaning + 子文件)、`hooks/`(doc_guard·check_wo_intent)、`settings.json`(hooks 注册)、`workflow.env.example`。
- `workflow-scripts/` → 装进项目 `scripts/workflow/`:`run_worker.sh`(两阶段派单)、`check_docs.py`(ADR frontmatter + 断链)、`transcribe_session.py`(会话转写)。
- `seed/` → 新项目首次 seed:`decisions/0000-template.md`(ADR 模板)、`docs/workflow.md`(设计蓝图 / 权威)。
- `install.sh` / `snapshot-from.sh` —— 装入 / 回抓。

## 用法
```bash
# 装进某项目
/path/to/workflow-kit/install.sh /path/to/target-project
cd /path/to/target-project
cp .claude/workflow.env.example .claude/workflow.env    # 填模型/命令档
# 目标 .gitignore 需忽略 .claude/ 与 scripts/workflow/;重启 Claude Code 让 hooks 生效

# trial 期在某项目直接改了 live 机制后,回抓进本 kit 再提交
/path/to/workflow-kit/snapshot-from.sh /path/to/that-project
```

## 现状(transition)
- **source of truth 暂时是各项目的 live 文件**(正在 hubpage 里试用);本 kit 是 tracked 快照。
- 稳定后再真正抽成独立 repo(见 `seed/docs/workflow.md` §5「远期」)。届时命令泛化(WF_TEST_CMD / WF_PY tokenize)、中英兼容一并做。
