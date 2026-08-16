#!/usr/bin/env bash
#==============================================================================
# hypothesis_precheck_gate.sh — 착수 전 사전지식 조회 **기계 게이트**
#   (PreToolUse[Write/Edit] on alpha_hypothesis.json)
#
# 배경 (2026-08-16 Axiom 폐쇄루프 감사, 구간 ⑫ BROKEN):
#   조회 의무는 4개 모드 프롬프트·SKILL 에 문서로 실려 있으나
#   **훅 63개 전수 grep 'prechecks|hypothesis_index' = 0 hit**, worktask/schema.json 에도 필드 없음.
#   ⇒ alpha-hypothesis 라운드 12/12 준수는 **강제의 산물이 아니라 규율의 산물**이고,
#      그 규율은 프롬프트 파일 한 곳(.claude/agents/alpha-hypothesis.md)에 얹혀 있다.
#      프롬프트가 바뀌거나 그 에이전트를 안 쓰면 8배 차이(인용밀도 median 8 vs 1)가 조용히 사라진다.
#   본 게이트가 그 규율을 배선으로 옮긴다. **새로 만드는 규약이 아니라 기존 규약의 강제**다.
#
# 규약 근거:
#   .claude/agents/alpha-hypothesis.md:28  "v8.3 착수 전 의무(선행 조건, 생략 금지):
#                                           hypothesis_index lookup + alpha_frontier_queue 확인"
#   .claude/skills/qvest-worktask/SKILL.md · docs/rules/axiom-engine.md (QEPM 모드 의무 lookup)
#
# 판정:
#   ① alpha_hypothesis 문서인데 prechecks.hypothesis_index_hits 부재/비배열       → block
#   ② hits 가 빈 배열이고 prechecks.empty_reason 도 없음                          → block
#      (★빈 결과 자체는 정당하다 — 인덱스에 선례가 없을 수 있다. 요구하는 것은
#        '조회했고 결과가 비었다'는 **선언**이지 히트 개수가 아니다.)
#   ③ hits 원소가 ref 필드를 안 가짐(형식 위반)                                    → block
#   ④ 그 외                                                                        → 통과
#
# ★비-목표: 히트 개수·품질 채점은 하지 않는다. 조회 **수행 여부**만 기계로 확인한다.
#           품질은 사람/판정 계층 소관 — 게이트가 내용을 채점하면 우회 유인이 생긴다.
#
# 작성 3의무 (harness.md 정합):
#   1) content 는 소스 보간 금지 — payload 전체를 stdin bytes 로 python 에 전달
#   2) raw-INPUT 조기-exit — 'alpha_hypothesis' 미포함 payload 는 python 스폰 0
#   3) advisory 는 additionalContext 로 실전달
#
# fail 정책: soft_fail true. 단 내부오류 시 payload 가 alpha_hypothesis 형상이면
#   fail-closed block (게이트 침묵 통과 금지 — discovery_graduation_gate 선례).
#==============================================================================
set -uo pipefail
export PYTHONUTF8=1

INPUT=$(cat)

_gate_fail_closed() {
  case "$INPUT" in
    *alpha_hypothesis*)
      echo '{"decision": "block", "reason": "hypothesis_precheck_gate: hook 내부 오류 — 사전지식 조회절 검증 불가 (fail-closed)"}' ;;
    *) echo '{}' ;;
  esac
  exit 0
}
trap '_gate_fail_closed' ERR

# ── 3의무-2: raw-INPUT 조기-exit ─────────────────────────────────────────────
case "$INPUT" in
  *alpha_hypothesis*) : ;;
  *) echo '{}'; exit 0 ;;
esac

QVEST_PY_BIN="${QVEST_PY:-python}"
command -v "$QVEST_PY_BIN" >/dev/null 2>&1 || QVEST_PY_BIN=python

printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c '
import json, sys

def out(o):
    print(json.dumps(o, ensure_ascii=False)); sys.exit(0)

raw = sys.stdin.buffer.read().decode("utf-8", "replace")
try:
    payload = json.loads(raw)
except Exception:
    out({})

ti = payload.get("tool_input") or {}
path = str(ti.get("file_path") or ti.get("path") or "")
# 대상 = alpha_hypothesis.json 쓰기만. 그 외(로그·문서 언급)는 무관.
if "alpha_hypothesis" not in path.replace("\\", "/").split("/")[-1]:
    out({})

content = ti.get("content")
if content is None:
    # Edit 계열 — 부분 수정이라 전체 문서를 못 본다. 조회절 판정 불가 ⇒ 통과 + advisory.
    out({"hookSpecificOutput": {"hookEventName": "PreToolUse",
         "additionalContext": "[hypothesis_precheck_gate] Edit 경로라 전체 문서 검증 생략 — "
                              "prechecks.hypothesis_index_hits 유지 여부를 직접 확인할 것."}})

try:
    doc = json.loads(content)
except Exception:
    # JSON 이 아니면 이 게이트의 대상이 아니다(부분 조각·템플릿 등).
    out({})
if not isinstance(doc, dict):
    out({})

pre = doc.get("prechecks")
BLOCK = lambda why: out({"decision": "block", "reason":
    "hypothesis_precheck_gate: " + why +
    "  근거 = alpha-hypothesis.md:28 착수 전 의무(hypothesis_index lookup + frontier queue 확인). "
    "조회 결과가 비어도 통과한다 — prechecks.empty_reason 에 사유 1줄을 적으면 된다. "
    "요구하는 것은 히트 개수가 아니라 **조회를 수행했다는 선언**이다."})

if not isinstance(pre, dict):
    BLOCK("prechecks 절이 없다(사전지식 조회 미선언).")

hits = pre.get("hypothesis_index_hits")
if not isinstance(hits, list):
    BLOCK("prechecks.hypothesis_index_hits 가 없거나 배열이 아니다.")

if len(hits) == 0:
    if not str(pre.get("empty_reason") or "").strip():
        BLOCK("hypothesis_index_hits 가 빈 배열인데 empty_reason 이 없다.")
    out({"hookSpecificOutput": {"hookEventName": "PreToolUse",
         "additionalContext": "[hypothesis_precheck_gate] 조회 결과 0건 — empty_reason 선언 확인, 통과."}})

# ★형상-불문 판정 — 원소가 **비어 있지만 않으면** 통과.
#   실측(2026-08-16 전수, 11 파일): 원소 키 분포 verdict 26 · id 22 · (비-dict 순수문자열) 20 ·
#   relation 12 · content 12 · ref 7. 즉 식별자 이름이 id/ref 로 갈리고 맨 문자열 인용도 흔하다.
#   초판이 `ref` 를 단일 예시에서 박제해 실제 산출물 12/13 을 오차단했다(회귀검사로 검출).
#   ⇒ 이 게이트의 계약은 "조회를 수행했다는 선언"이지 특정 스키마가 아니다(위 비-목표 절 정합).
def _nonempty(h):
    if isinstance(h, str):
        return bool(h.strip())
    if isinstance(h, dict):
        return any(str(v).strip() for v in h.values() if v is not None)
    if isinstance(h, (list, tuple)):
        return len(h) > 0
    return h is not None

bad = [i for i, h in enumerate(hits) if not _nonempty(h)]
if bad:
    BLOCK("hypothesis_index_hits 원소 %s 가 비어 있다(조회 결과 미기재)." % bad[:3])

out({"hookSpecificOutput": {"hookEventName": "PreToolUse",
     "additionalContext": "[hypothesis_precheck_gate] 사전지식 조회절 %d건 확인 — 통과." % len(hits)}})
'
