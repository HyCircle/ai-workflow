#!/usr/bin/env bash
# derive_status.sh — 从不可变输入纯派生 STATUS 四态(D2)。
# 用法:
#   derive_status.sh [--review <file> ...] \
#     --skip-review <0|1> --pytest-rc <n> --overreach <0|1> --check-docs-rc <n> [--cli-failed <0|1>]
# 输出( stdout ): STATUS 行 + findings 摘要 + 自曝行;退出码仅 infra_failed=2,其余=0。
set -uo pipefail

REVIEW_FILES=()
SKIP_REVIEW=0
PYTEST_RC=0
OVERREACH=0
CHECK_DOCS_RC=0
CLI_FAILED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --review) REVIEW_FILES+=("${2:-}"); shift 2 ;;
    --skip-review) SKIP_REVIEW="${2:-0}"; shift 2 ;;
    --pytest-rc) PYTEST_RC="${2:-0}"; shift 2 ;;
    --overreach) OVERREACH="${2:-0}"; shift 2 ;;
    --check-docs-rc) CHECK_DOCS_RC="${2:-0}"; shift 2 ;;
    --cli-failed) CLI_FAILED="${2:-0}"; shift 2 ;;
    *) echo "✗ derive_status: 未知参数 $1" >&2; exit 2 ;;
  esac
done

# shellcheck disable=SC2034
BLOCKING_COUNT=0
NIT_COUNT=0
NIT_LIST=()
SELF_EXPOSE=()
DEAD_FILES=()
PARSE_OK=1

_field_val () {
  local line="$1"
  case "$line" in
    *": "*) printf '%s' "${line#*: }" ;;
    *) printf '%s' "" ;;
  esac
}

_parse_one_review () {
  local file="$1"
  local -a blocks=()
  local in_block=0 block_lines=()
  local has_none=0 has_finding_marker=0

  [ -f "$file" ] || { PARSE_OK=0; echo "自曝: 验收单不存在: $file" >&2; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "<<<FINDINGS-NONE>>>" ]; then
      has_none=1
      continue
    fi
    if [ "$line" = "<<<FINDING" ]; then
      in_block=1
      block_lines=()
      has_finding_marker=1
      continue
    fi
    if [ "$in_block" = "1" ] && [ "$line" = "FINDING>>>" ]; then
      in_block=0
      blocks+=("$(printf '%s\n' "${block_lines[@]}")")
      block_lines=()
      continue
    fi
    if [ "$in_block" = "1" ]; then
      block_lines+=("$line")
    fi
  done < "$file"

  # 未闭合块(报告被截断)→ infra_failed(§0.2)
  if [ "$in_block" = "1" ]; then
    PARSE_OK=0
    echo "自曝: $file 有未闭合的 <<<FINDING 块(报告可能被截断)" >&2
    return 1
  fi

  if [ "$has_none" = "1" ] && [ "$has_finding_marker" = "1" ]; then
    PARSE_OK=0
    echo "自曝: $file 同时含 <<<FINDINGS-NONE>>> 与 FINDING 块" >&2
    return 1
  fi
  if [ "$has_none" = "1" ]; then
    return 0
  fi
  if [ "$has_finding_marker" != "1" ]; then
    PARSE_OK=0
    echo "自曝: $file 不可解析(无 FINDING 块且无 <<<FINDINGS-NONE>>>)" >&2
    return 1
  fi

  local blk sev where claim
  for blk in "${blocks[@]}"; do
    sev=""
    where=""
    claim=""
    while IFS= read -r ln || [ -n "$ln" ]; do
      case "$ln" in
        severity:\ *) sev="$(_field_val "$ln")" ;;
        where:\ *) where="$(_field_val "$ln")" ;;
        claim:\ *) claim="$(_field_val "$ln")" ;;
      esac
    done <<< "$blk"

    if [ -z "$sev" ]; then
      sev="blocking"
      SELF_EXPOSE+=("$file: finding 缺 severity: 行,安全降级按 blocking 计(where=${where:-?} claim=${claim:-?})")
      BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
    elif [ "$sev" = "blocking" ]; then
      BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
    elif [ "$sev" = "nit" ]; then
      NIT_COUNT=$((NIT_COUNT + 1))
      NIT_LIST+=("$file: ${where:-?} — ${claim:-?}")
    else
      SELF_EXPOSE+=("$file: 未知 severity='$sev',安全降级按 blocking 计")
      BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
    fi
  done
}

if [ "$CLI_FAILED" != "0" ]; then
  echo "STATUS: infra_failed"
  echo "原因: CLI/超时失败"
  exit 2
fi

if [ "$SKIP_REVIEW" != "1" ]; then
  if [ "${#REVIEW_FILES[@]}" -eq 0 ]; then
    PARSE_OK=0
    echo "自曝: 未跳过验收但无验收单路径" >&2
  else
    for rf in "${REVIEW_FILES[@]}"; do
      # dead = 缺文件 或 空/纯空白(验收员超时被杀 → call_agent 落空文件)。dead ≠ unparseable:
      # 有其他存活验收员时按存活者派生 + 自曝;**全 dead** 才 infra_failed(无结论)。
      # 有内容但无标记/未闭合 = unparseable(可能藏 blocking)→ 仍 PARSE_OK=0 硬 infra_failed(§0.2)。
      if [ ! -f "$rf" ] || ! grep -q '[^[:space:]]' "$rf" 2>/dev/null; then
        DEAD_FILES+=("$rf")
        SELF_EXPOSE+=("验收单 $rf 空/缺失(验收员疑超时被杀);有存活验收员则仅按存活者派生")
        continue
      fi
      _parse_one_review "$rf" || true
    done
    if [ "$PARSE_OK" = "1" ] && [ "${#DEAD_FILES[@]}" -eq "${#REVIEW_FILES[@]}" ]; then
      PARSE_OK=0
      SELF_EXPOSE+=("全部验收员均无有效产出 → 无验收结论")
    fi
  fi
fi

if [ "$PARSE_OK" != "1" ]; then
  echo "STATUS: infra_failed"
  echo "原因: 验收报告不可解析"
  for msg in "${SELF_EXPOSE[@]}"; do echo "自曝: $msg"; done
  exit 2
fi

STATUS=""
if [ "$PYTEST_RC" != "0" ] || [ "$OVERREACH" != "0" ] || [ "$CHECK_DOCS_RC" != "0" ] || [ "$BLOCKING_COUNT" -gt 0 ]; then
  STATUS="review_blocked"
elif [ "$SKIP_REVIEW" = "1" ]; then
  STATUS="review_skipped"
else
  STATUS="review_complete"
fi

echo "STATUS: $STATUS"
echo "findings: blocking=$BLOCKING_COUNT nit=$NIT_COUNT"
if [ "${#NIT_LIST[@]}" -gt 0 ]; then
  echo "nit 自曝清单(不挡放行,planner 可选采纳):"
  for n in "${NIT_LIST[@]}"; do echo "  · $n"; done
fi
echo "机器事实: pytest_rc=$PYTEST_RC overreach=$OVERREACH check_docs_rc=$CHECK_DOCS_RC skip_review=$SKIP_REVIEW"
for msg in "${SELF_EXPOSE[@]}"; do echo "自曝: $msg"; done
exit 0
