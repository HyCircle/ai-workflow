# 工单 WO-<ADR>-<N> — <一句话目标>

<!--
用法:复制 → .workflow/scratchpad/PL-<id>/WO-current.md 填好 → 用户放行 → .workflow/kit/scripts/run_worker.sh。
编号:WO-<ADR 四位号>-<序号>(如 WO-0002-1;跟决策走,全局唯一)。
怎么写工单见 /planner skill;两条最易忘:① 出单前 grep/read 核实所有 file:line/常量名(纪律④);② worker 派单时已附六条纪律 + 交付契约,别在工单里复述。
-->

## 抬头
- **本单服务 → ADR-NNNN 的意图:<抄那句意图>**(闸门3;缺此行 / 不指向 ADR-NNNN,`run_worker.sh` 入口会拒派)
- 承接 HEAD:<git short sha / 分支>
- SSOT:<本工单契约以哪个 ADR / architecture 节为准,如 ADR-0001、architecture §5.3>

## 目标(1 行,可验证)
<做成什么>

## 先读(动手前必读的锚点)
- ADR-NNNN 的「决策」 —— <这单要满足的 WHAT>
- <相关代码 file:line> —— <现状是什么>

## 明确不做(防越界)
- <本批不碰什么 / 留给哪个后续工单>
- 红线:一行不许碰 `.workflow/decisions/`·`.workflow/architecture.md`·`AGENTS.md`(著作类文件;worker 只写代码 + scratchpad)

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
- `$WF_TEST_CMD <具体路径>` —— 期望 <基线+新增> 全绿
- ADR 结构/断链:`$WF_PY .workflow/kit/scripts/check_docs.py --changed`(canonical,用 python 不用 grep;`$WF_PY` 读 `.workflow/workflow.env`)
- <本批特定的功能验收点>
