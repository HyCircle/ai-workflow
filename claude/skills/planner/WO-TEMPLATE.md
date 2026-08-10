# 工单 WO-<ADR>-<N> — <一句话目标>

<!--
用法:planner 复制本模板 → scratchpad/PL-<id>/WO-current.md 填好 → 用户放行
      → scripts/workflow/run_worker.sh scratchpad/PL-<id>/WO-current.md
编号:WO 跟决策走 —— WO-<ADR 四位号>-<序号>,如 WO-0002-1(全局唯一自解释;见 /planner skill)。

设计原则(为什么这么写,见 /planner skill):
1. 出单前自己 grep/read **核实所有 file:line 锚点和常量/函数名**,别信记忆(§0④)。
2. worker 已自动加载 AGENTS.md(§0 纪律)+ 全局准则;交付契约由派单脚本注入——这些**都别在工单里复述**。
3. 工单只写「worker 靠自己推不出来的东西」:可验证的成功判据、红线、陷阱、该读哪几节。
4. **成功判据尽量写成能跑到绿的测试**——让 worker 独立自循环,少来回。
5. **别逐行口述实现**:给足契约+陷阱,红线内的实现交给 worker。只在「非显然 / 有坑 / 有硬性措辞要求」处才写具体做法。
-->

## 抬头
- **本单服务 → ADR-NNNN 的意图:<抄那句意图>**(闸门3;缺此行 / 不指向 ADR-NNNN,派单 hook 会 deny)
- 承接 HEAD:<git short sha / 分支>
- 测试基线:<当前 `uv run pytest` 的数字,如 128 passed>
- SSOT:<本工单契约以哪个 ADR / architecture 节为准,如 ADR-0001、architecture §5.3>

## 目标(1 行,可验证)
<做成什么>

## 先读(动手前必读的锚点)
- ADR-NNNN 的「决策(契约)」 —— <这单要满足的 WHAT>
- <相关代码 file:line> —— <现状是什么>

## 明确不做(防越界)
- <本批不碰什么 / 留给哪个后续工单>
- 红线:一行不许碰 `decisions/`·`architecture.md`·`AGENTS.md`(著作类文件,只 Claude 层动,§2.5)

## ⚠️ 陷阱预判(planner 预判 worker 会怎么做错——最值钱的一节)
- <照直做会踩的坑。例:别原地覆盖旧数据;for…else 裸 break;某字段是字符串不是 epoch;
   有限已知集合上凭记忆写的映射必漏——从数据反推、判据配跑全集的恒真探针>

## 任务分解
### T1 — <子目标>
- 现状:<file:line>
- **成功判据(worker 要跑到绿)**:<具体测试文件+断言,或可判定的检查;这是本任务的规格>
- 红线:<哪些文件 / 函数一行都不许动>
- 做法提示(仅非显然/有坑处,显然的别写):<算法 / 边界 / 措辞>
### T2 — …

## 验收(planner 会亲自跑;worker 报告前也须自测绿)
- `uv run pytest <具体路径>` —— 期望 <基线+新增> 全绿
- ADR 结构/断链:`uv run python scripts/workflow/check_docs.py --changed`(canonical,用 python 不用 grep)
- <本批特定的功能验收点>
