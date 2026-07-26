#!/usr/bin/env bash
#==============================================================================
# run_all_hooks.sh — Phase 8 dry-run test runner
# 모든 hook test 실행 + results.json 생성.
#==============================================================================

set -uo pipefail

#──────────────────────────────────────────────────────────────────────────────
# (2026-07-25) bare python3 → $QVEST_PY_BIN. PATH의 python3는 Windows Store 스텁이라
# "Python"만 찍고 스크립트를 실행하지 않는다 → 각 suite의 JSON 요약 라인 파싱이 전량
# 실패 → 집계 총계 0이 "✅ ALL PASS"로 위장된다(계측 사망). 정본 해석기 경유.
# (reference-python3-windows-stub-use-qvest-py / _shared_parse.sh HOOK-P0-1)
#
# ★ QVEST_PARSE_TRAP=caller 필수: 미지정 시 _shared_parse.sh가 fail-open ERR trap
#   ('{}' 출력 후 exit 0)을 이 셸에 설치한다 → 이후 아무 명령이나 실패하면 러너가
#   조용히 성공 종료. 바로 이 버그를 고치는 중이므로 trap 설치를 거부한다.
# ★ 앵커는 PROJ_DIR이 아니라 BASH_SOURCE — PROJ_DIR 오설정이야말로 이 suite가
#   보고해야 할 실패라, 그 경우에도 해석기는 살아 있어야 한다.
#──────────────────────────────────────────────────────────────────────────────
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_PARSE="$_SELF_DIR/../../02_Infrastructure/hooks/_shared_parse.sh"
if [[ -f "$_SHARED_PARSE" ]]; then
  QVEST_PARSE_TRAP=caller
  QVEST_PARSE_RESOLVE_ONLY=1
  # shellcheck source=/dev/null
  source "$_SHARED_PARSE"
  unset QVEST_PARSE_RESOLVE_ONLY QVEST_PARSE_TRAP
else
  _QP="${QVEST_PY:-}"          # set -u 대비 기본값
  QVEST_PY_BIN="${_QP//\\//}"  # 백슬래시 → 슬래시 (Git Bash 실행 호환)
  [[ -x "$QVEST_PY_BIN" ]] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi

# PROJ_DIR 해석 (2026-07-25 수리): 구 폴백은 WSL 전용 glob 이라 이 머신에선 빈 문자열이
# 되고 TEST_DIR="/08_Tests/hooks" 로 전 suite 가 죽었다. 후보를 **표지 검증**으로 확인한다
# ("있다"가 "그것이다"를 뜻하지 않는다 — dir.exists 신뢰 사고와 같은 기전).
_MARKER="08_Tests/hooks/run_all_hooks.sh"
_pick_proj_dir() {
  local c
  for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$_SELF_DIR/../.." "$PWD"; do
    if [[ -n "$c" && -f "$c/$_MARKER" ]]; then (cd "$c" && pwd); return 0; fi
  done
  return 1
}
if ! PROJ_DIR="$(_pick_proj_dir)"; then
  echo "❌ PROJECT_ROOT 해석 실패 — 표지 '$_MARKER' 를 가진 후보 없음" >&2
  echo "   CLAUDE_PROJECT_DIR='${CLAUDE_PROJECT_DIR:-}' QM_ROOT='${QM_ROOT:-}' PWD='$PWD'" >&2
  exit 2
fi
TEST_DIR="$PROJ_DIR/08_Tests/hooks"
# 결과는 재생성 가능한 산출물 → 코드 존(08_Tests) 밖 캐시에 쓴다
# (artifact-storage.md §1·§3, 2026-07-25 도훈 confirm).
RESULTS_DIR="$PROJ_DIR/.cache/test_results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/hook_dryrun_results.json"

echo "=== Qvest v6.4 Hook Test Suite ==="
echo "Project: $PROJ_DIR"
echo "Tests dir: $TEST_DIR"
echo "Started: $(date -Iseconds)"
echo ""

ALL_RESULTS=()
TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
  local name="$1"
  local cmd="$2"
  echo "─── Running: $name ───"
  RESULT=$(eval "$cmd" 2>&1)
  echo "$RESULT"
  echo ""
  # Extract last JSON line
  JSON=$(echo "$RESULT" | tail -1)
  echo "$JSON" | "$QVEST_PY_BIN" -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print("PARSED|" + str(d.get("test","?")) + "|" + str(d.get("pass",0)) + "|" + str(d.get("fail",0)) + "|" + str(d.get("total",0)))
except Exception as e:
    print("PARSE_ERROR|" + str(e))
' | while IFS='|' read -r marker test_name pass fail total; do
    if [[ "$marker" == "PARSED" ]]; then
      ALL_RESULTS+=("{\"test\":\"$test_name\",\"pass\":$pass,\"fail\":$fail,\"total\":$total}")
      TOTAL_PASS=$((TOTAL_PASS + pass))
      TOTAL_FAIL=$((TOTAL_FAIL + fail))
    fi
  done
}

# ─── 스위트 목록 = 단일 정본 (2026-07-26) ───────────────────────────────────
# 구현은 "실행 목록"과 "집계 목록"을 각각 하드코딩해 두 벌로 갖고 있었다 —
# 한쪽에만 추가하면 실행은 되는데 총계에 안 잡히거나(침묵 결손) 그 반대가 된다.
# 배열 하나로 합친다. 경로는 PROJ_DIR 기준 상대경로.
# 훅 밖의 R 계약 검사도 여기서 상설로 돈다 (선례: test_r_portability.R,
# 2026-07-26 추가: factor_db IC month-pair 완결성 가드 위반 주입 테스트).
SUITES=(
  "08_Tests/hooks/test_worktask_sequence_gate.sh"
  "08_Tests/hooks/test_agent_role_guard.sh"
  "08_Tests/hooks/test_cert_rules.R"
  "08_Tests/hooks/test_r_portability.R"
  "08_Tests/factor_db/test_ic_completion_guard.R"
  # 2026-07-26 추가(T3): IC 월-프론티어 감시(ic_frontier_check) 위반 주입 테스트.
  #   감시기는 07-26 신설되며 ic_max_date_override 를 "주입용"으로 노출해 놓고도 케이스가
  #   0건이었다 — 4트랙 중 유일하게 상설 검사가 없던 갭. 검사 없는 가드는 무력화돼도
  #   "경보 0건"으로만 보인다.
  "08_Tests/factor_db/test_ic_frontier_check.R"
  "08_Tests/factor_db/test_build_hash_provenance.R"
  # 2026-07-26 추가: auto-commit 밸브 v2(디렉터리-단위 A-only 격리 — v1 영구개방 사고 재발 방지)
  "08_Tests/hooks/test_auto_commit_valve.sh"
  # 2026-07-26 추가: measurement_basis_audit v1.12 계보 resolver (worktree 좌초 회수분의 정본 회귀 가드)
  "08_Tests/portfolio/test_lineage_resolver.R"
  # 2026-07-26 추가: 부팅 자기-정합 검사(boot_currency_check) 위반 주입 — 부팅 최신화 자동 배선의 가드
  "08_Tests/hooks/test_boot_currency.sh"
  # 2026-07-26 추가: cache_freshness worse-of lag 위반 주입 (CFA-02 수리 가드).
  #   forward-dated / 파일명-추정 캐시는 생성기가 죽어 파일이 동결돼도 data_lag 가 낮아
  #   FRESH 로 보고됐다 — 동결을 보는 유일 축(mtime)이 폐기되던 구조.
  #   caches_override/today/persist 주입 파라미터의 첫 소비자(노출만 돼 있고 케이스 0건이었음).
  "08_Tests/data/test_cache_freshness_worse_of.R"
  # 2026-07-26 추가(T4): readiness gate 의 hook_dryrun 체크 위반 주입.
  #   그 체크는 이 러너의 산출을 읽는다 — 즉 여기가 **자기 소비자를 감시하는 자리**다.
  #   원 결함이 정확히 "러너가 산출 경로를 옮겼는데 게이트가 못 따라옴"이었으므로
  #   E 축(배선 대조)이 이 러너의 RESULTS_FILE 과 게이트 상수를 매 실행 대조한다.
  "08_Tests/validation/test_v8_readiness_hook_dryrun.R"
  # 2026-07-26 추가(T1): DART 수집 후보집합(제출창+커버리지) 위반 주입 테스트.
  #   원 결함 P2-01 = 후보집합을 **달력**으로 생성 → FY2025 사업보고서(2026-03 제출)가
  #   2025년엔 존재하지 않고 2026년엔 요청되지 않아 50/714 corps 로 영구 결손.
  #   D축이 구 규칙(달력연도)·존재-검사와 신 규칙을 대조해 케이스 공허화를 막는다.
  "08_Tests/data/test_dart_candidate_years.R"
  # 2026-07-26 추가(T2): 캐시 내용-도달 감시(P2-02/P2-03) 위반 주입.
  #   수리 전 두 감시가 **동시에** 침묵해 DART FY2025 결손(corps 50 vs 정상 714)이 4개월
  #   무보고였다: 디렉토리형은 파일명 월말로 lag=0(내용 미열람), 단일파일은 mtime 만.
  #   A축이 동결·코호트 결손을 주입하고, D축이 판정부를 무력화해 A가 통과로 뒤집히는지
  #   대조한다 — "경보 0건"이 건강인지 계측 사망인지는 그렇게만 갈린다.
  "08_Tests/data/test_cache_content_reach.R"
)

_suite_cmd() {
  local rel="$1"
  if [[ "$rel" == *.R ]]; then
    printf 'Rscript "%s/%s"' "$PROJ_DIR" "$rel"
  else
    printf 'bash "%s/%s"' "$PROJ_DIR" "$rel"
  fi
}

for _s in "${SUITES[@]}"; do
  _name="$(basename "$_s")"; _name="${_name%.*}"
  run_test "$_name" "$(_suite_cmd "$_s")"
done

# Aggregate (re-extract since subshells don't propagate)
TOTAL_PASS=0
TOTAL_FAIL=0
TESTS_JSON=""
UNREPORTED=()
# [fix 2026-07-25] 구현은 요약을 `tail -1`로 집었는데, 마지막 줄이 경고·stderr
# 인터리브로 밀리면 그 suite 전체가 UNREPORTED(=1 fail)로 계상되고 통과 건수가
# 통째로 사라진다 — 실측 1/7 빈도로 27/0/27 ↔ 17/1/18 (드롭분 = seq_gate 10건).
# → 마지막 줄이 아니라 **뒤에서부터 첫 유효 요약 JSON 라인**을 집는다.
_last_summary_json() {
  "$QVEST_PY_BIN" -c '
import json,sys
pick=""
for line in sys.stdin.read().splitlines():
    s=line.strip()
    if not (s.startswith("{") and s.endswith("}")): continue
    try:
        d=json.loads(s)
    except Exception:
        continue
    if isinstance(d,dict) and "test" in d: pick=s
print(pick)
' 2>/dev/null
}

for test_script in "${SUITES[@]}"; do
  if [[ "$test_script" == *.R ]]; then
    OUT=$(Rscript "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  else
    OUT=$(bash "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  fi
  if echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.loads(sys.stdin.read()); exit(0 if "test" in d else 1)' 2>/dev/null; then
    PASS=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("pass",0))')
    FAIL=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("fail",0))')
    TOTAL_PASS=$((TOTAL_PASS + PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
    if [[ -n "$TESTS_JSON" ]]; then TESTS_JSON+=","; fi
    TESTS_JSON+="$OUT"
  else
    # 계측 사망 방어 (2026-07-25): 요약 JSON을 못 낸 suite는 "0건 실행"이지 "통과"가
    # 아니다. 종전엔 조용히 skip → 3 suite 전부 누락 시 FINAL 0/0/0이 "✅ ALL PASS"로
    # 보고됐다(이 파일이 고치는 원 버그). 미보고 = 실패로 계상한다.
    UNREPORTED+=("$test_script")
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo "⚠ UNREPORTED: $test_script — 요약 JSON 파싱 실패 (마지막 줄: ${OUT:0:120})" >&2
  fi
done

if (( ${#UNREPORTED[@]} > 0 )); then
  echo "⚠ 요약 JSON 미발행 suite ${#UNREPORTED[@]}건: ${UNREPORTED[*]}" >&2
fi

# Final results JSON
cat > "$RESULTS_FILE" <<EOF
{
  "suite": "qvest_v6_4_hook_dryrun",
  "version": "1.0",
  "ran_at": "$(date -Iseconds)",
  "total_pass": $TOTAL_PASS,
  "total_fail": $TOTAL_FAIL,
  "total": $((TOTAL_PASS + TOTAL_FAIL)),
  "status": "$(if [[ $TOTAL_FAIL -eq 0 ]]; then echo PASS; else echo FAIL; fi)",
  "tests": [$TESTS_JSON]
}
EOF

echo ""
echo "════════════════════════════════════════"
echo "FINAL: $TOTAL_PASS pass / $TOTAL_FAIL fail / $((TOTAL_PASS + TOTAL_FAIL)) total"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "STATUS: ✅ ALL PASS"
else
  echo "STATUS: ❌ FAIL ($TOTAL_FAIL test failures)"
fi
echo "Results: $RESULTS_FILE"
echo "════════════════════════════════════════"

exit $TOTAL_FAIL
