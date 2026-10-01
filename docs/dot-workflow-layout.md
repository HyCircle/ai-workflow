# .workflow 统一投影布局

> **定位**:消费仓全部工作流产物收进 `<gitroot>/.workflow/`,由 `wf init` 生成与升级。
> **路径简写**:消费仓运行时文档(skills / discipline)用短名;真路径见 **AGENTS 文档路由**。

## 意图(为什么)

1. **固定约定优于可变前缀**:一个 dot 目录,exclude 好写、升级可预期。
2. **机制与设计资产分层**:机制副本在 `.workflow/kit/`(本地忽略、按需重装);设计资产在 `.workflow/` 下固定位置。
3. **两种 exclude 粒度**:同一物理布局,track / no-track 只差「设计资产要不要进 git」。

## 决策(可测契约)

### 1. 安装一律复制进 `<gitroot>/.workflow/`

```
<gitroot>/
  .workflow/
    kit/                      # 机制副本(来自 wf 包内 kit/;每次 wf init 整体覆盖)
      skills/ discipline.md workflow.env.example
    decisions/                # 设计资产(ADR;含 0000-template)
    architecture.md  TODO.md
    patterns/                 # 按任务类型的手册
    workflow.env              # 本机配置(永远 exclude;首次 wf init 从模板生成)
    scratchpad/               # 临时产物(永远 exclude)
      runs/                   # wf run / review 的产物
      _archive/               # finishing 写的会话归档,本机长期保留,GC 不清
  AGENTS.md                   # 根指令(留仓根)
  .claude/ .agents/ .cursor/  # 按 --backends 建的后端入口
```

### 2. track / no-track:只差 exclude 粒度

- 设计资产(decisions / architecture / TODO / patterns)**位置永远在 `.workflow/`**;越界检查也指向这些路径。
- **no-track**:exclude 收 `/.workflow/` 与 `/AGENTS.md`。
- **track**:exclude 只收 `/.workflow/kit/`、`/.workflow/workflow.env`、`/.workflow/scratchpad/`;设计资产 tracked。
- exclude 块以 `ai-workflow BEGIN` / `END` 界定,每次 `wf init` 整块重写。

### 3. 复制按需升级

- 只复制、不 symlink 单源;每仓按需重跑 `wf init` 升级。装了哪版看 `wf --version`。

### 4. 后端入口:`--backends`

| harness | 认的目录 | 只认自己? |
|---|---|---|
| CC | `.claude` | 是 |
| codex | `.agents` | 是 |
| cursor | `.cursor` / `.claude` / `.codex` / `.agents` 全读 | 否 |

- skills 真源 = `.workflow/kit/skills`;CC → `.claude/skills`、codex → `.agents/skills`(仓内相对软链)。
- cursor 不单建入口;仅 cursor 时借 `.claude/skills`。
- 入口位置已有别的内容时不覆盖,只提示。
- `AGENTS.md` = 三后端共用根指令;CC 的 Project instructions 设置须允许加载它。

## 明确不做

- 可变 `--prefix` 前缀。
- no-track 的 `.workflow/` 独立 git 仓。
- cursor 单建 skills 入口。
- git 钩子、插件 / npm / Docker 包装。

## install 默认

- `--backends` 默认 `cc`;codex 需显式 `cc,codex`。
- track 默认开启;no-track 须显式 `--no-track`。
