# .workflow 统一投影布局(已定;已落地)

> **定位**:消费仓全部工作流产物收进 `<gitroot>/.workflow/`。取代根级散落投影(`.claude` / `scripts/workflow` /
> `agent-discipline.md` 散落根级)及已废弃的 `install.sh --prefix`(见 `docs/history/extraction-plan.md` 第五节,**勿再采用**)。
> **路径简写**:消费仓运行时文档(skills / discipline)用短名;真路径见 **AGENTS 文档地图**。

## 意图(为什么)

1. **固定约定优于可变前缀**:一个 dot 目录,exclude 好写、升级可预期。
2. **机制与设计资产分层**:机制 copy 在 `.workflow/kit/`(本地忽略、按需重装);设计资产在 `.workflow/` 下固定位置。
3. **两种 exclude 粒度**:同一物理布局,track / no-track 只差「设计资产要不要进 git」。

## 决策(可测契约)

### 1. 安装一律 copy 进 `<gitroot>/.workflow/`

```
<gitroot>/
  .workflow/
    kit/                      # 机制 copy(SOT = ai-workflow 快照;track 下 exclude)
      skills/ scripts/ discipline.md settings.json workflow.env.example
      git-hooks/pre-commit    # 源(install 装进 .git/hooks/)
    decisions/                # 设计资产(ADR;含 0000-template)
    architecture.md  TODO.md
    workflow.env              # 本机配置(永远 exclude)
    scratchpad/               # 临时产物(永远 exclude)
      _archive/               # 精炼对话，本机长期保留，GC 不清
    VERSION                   # ai-workflow 的 tag + commit
  AGENTS.md                   # 根发现文档(留仓根)
  .claude/ .agents/ .cursor/  # 按 --backends 建的后端入口
  .git/hooks/pre-commit
```

### 2. track / no-track:只差 exclude 粒度

- 设计资产(decisions / architecture / TODO)**位置永远在 `.workflow/`**。
- `check_docs` 指 `.workflow/decisions`;越界校验的 durable 锚也指 `.workflow/` 下对应文件。
- **no-track**:exclude 收 `/.workflow/`(+ 根发现文档若干)。
- **track**:exclude 只收 `/.workflow/kit/`、`/.workflow/workflow.env`、`/.workflow/scratchpad/`;设计资产 tracked。

### 3. copy 按需升级 + VERSION 印记

- 只 copy、不 symlink 单源;每仓按需 re-run `install.sh` 升级。
- `.workflow/VERSION` 记装了哪版 ai-workflow。

### 4. 后端入口:`--backends`

| harness | 认的目录 | 只认自己? |
|---|---|---|
| CC | `.claude` | 是 |
| codex | `.agents` | 是 |
| cursor | `.cursor` / `.claude` / `.codex` / `.agents` 全读 | 否 |

- skills 真源 = `.workflow/kit/skills`;CC → `.claude/skills`、codex → `.agents/skills`(仓内相对软链)。
- cursor 不单建入口;仅 cursor 时借 `.claude/skills`。
- `AGENTS.md` = 共用根指令入口。安装器仅移除工作流生成的旧 `CLAUDE.md` 导入入口，保留项目自有内容。

## 明确不做

- 可变 `--prefix` 前缀。
- no-track 的 `.workflow/` 独立 git 仓。
- cursor 单建 skills 入口。
- 插件 / npm / Docker 包装。

## 备选与失效模式(已拍板)

- **skills:cursor 不双读** — `.claude/skills` + `.agents/skills` 各一份安全。
- **根文档**：三后端共用 `AGENTS.md`；CC 的 Project instructions 设置须允许加载它。
- **skills 软链**:harness 不认仓内软链时,install 可退 `cp -r`(在 exclude 内,升级覆盖)。

## install 默认

- `--backends` 默认 `cc`;codex 需显式 `cc,codex`。
- `--track` 默认开启;no-track 须显式声明。
- track 模式 `VERSION` tracked。
