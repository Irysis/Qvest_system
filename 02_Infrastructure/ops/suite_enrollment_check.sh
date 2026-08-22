#!/usr/bin/env bash
#==============================================================================
# suite_enrollment_check.sh — 테스트 편입 드리프트 검사 (2026-08-16 신설)
#
# 배경: 2026-08-16 측정에서 `08_Tests/` 의 test_*.{R,sh} 119건 중 **37건이 배터리에서
#   한 번도 실행되지 않고** 있었다. 그중 15건이 `contract_regression/` — essence_score
#   (등급 권위) · hurdle_gate(게이트 2계층) · canonical_screen_bt(실측 진입점) ·
#   register_module(모듈 계약) 처럼 **알파 판정을 지탱하는 계약**의 회귀 테스트다.
#   원인은 `run_all_hooks.sh` 의 SUITES 가 하드코딩 열거라 새 테스트가 자동 편입되지
#   않는 것 — 같은 형태를 2026-08-16 하루에만 3번 만났다(00_Lawbook/INDEX.md 낙후 ·
#   boot_currency 감시 대상 · 이 SUITES).
#
# 판정 규칙 (파일시스템 + SUITES 에서 계산 — 기대값 하드코딩 없음):
#   테스트 파일이 "커버됨" = ① SUITES 에 직접 등재됐거나
#                            ② 같은 디렉터리에 **SUITES 에 등재된 집계 러너**(run_*.R)가 있다
#   ★제외 1종: `08_Tests/lib/` — 공용 헬퍼 디렉터리다. 2026-08-20 실측에서
#     lib/test_prereq.R 이 미편입으로 잡혔는데, 이 파일은 tp_require/tp_summary_json 을
#     **정의만** 하고 최상위 실행 코드가 없으며 다른 테스트 4곳이 source 한다(테스트가
#     아니라 라이브러리). ⚠제외는 디렉터리 단위라 lib/ 에 진짜 스위트를 두면 놓친다 —
#     lib/ 는 헬퍼 전용이라는 규약을 지킬 것(위반 주입 V6 가 이 경계를 지킨다).
#   ★②의 가정: 등재된 집계 러너는 자기 디렉터리의 test_*.R 을 자동 탐색한다.
#     2026-08-16 실측 기준 참이다 — regime/run_all.R 은 list.files(pattern="^test_.*\\.R$"),
#     contract_regression/run_contract_regression.R 도 같은 날 자동 탐색으로 전환했다.
#     ⚠ 자동 탐색하지 않는 run_*.R 을 등재하면 이 검사가 커버리지를 **과대평가**한다.
#     새 집계 러너를 만들 때는 반드시 자동 탐색으로 쓸 것.
#
# 원칙: 부재/파싱실패 = UNKNOWN(FAIL 계상) — 0이나 통과로 위장 금지.
# 출력: 상세 + 마지막 줄 JSON {"test":"suite_enrollment","pass":N,"fail":N,"total":N}
# 테스트 오버라이드: QVEST_SEC_RUNNER / QVEST_SEC_TESTS_DIR
#                    (08_Tests/hooks/test_suite_enrollment.sh 전용)
#==============================================================================
set -u

_MARKER="02_Infrastructure/ops/suite_enrollment_check.sh"
PROJECT=""
for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"; do
  if [ -n "$c" ] && [ -f "$c/$_MARKER" ]; then PROJECT="$c"; break; fi
done
if [ -z "$PROJECT" ]; then
  echo "[suite-enroll] FATAL: PROJECT 해석 실패"
  echo '{"test":"suite_enrollment","pass":0,"fail":1,"total":1}'; exit 1
fi

RUNNER="${QVEST_SEC_RUNNER:-$PROJECT/08_Tests/hooks/run_all_hooks.sh}"
TESTS_DIR="${QVEST_SEC_TESTS_DIR:-$PROJECT/08_Tests}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

if [ ! -f "$RUNNER" ]; then
  bad "E0 UNKNOWN — 러너 부재 ($RUNNER)"
  echo ""; echo "suite-enrollment: PASS=$PASS FAIL=$FAIL"
  echo "{\"test\":\"suite_enrollment\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
  exit 1
fi
if [ ! -d "$TESTS_DIR" ]; then
  bad "E0 UNKNOWN — 테스트 디렉터리 부재 ($TESTS_DIR)"
  echo ""; echo "suite-enrollment: PASS=$PASS FAIL=$FAIL"
  echo "{\"test\":\"suite_enrollment\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
  exit 1
fi

# ── SUITES 배열 추출 (배열 끝까지 — 앞부분만 자르면 과대 보고, 08-16 실측 함정①) ──
S_LINE=$(grep -n '^SUITES=(' "$RUNNER" | head -1 | cut -d: -f1)
if [ -z "$S_LINE" ]; then
  bad "E1 UNKNOWN — 러너에서 'SUITES=(' 를 못 찾음 (배열 선언 포맷 변경 시 파서 갱신)"
else
  E_LINE=$(awk -v s="$S_LINE" 'NR>s && /^\)/{print NR; exit}' "$RUNNER")
  if [ -z "$E_LINE" ]; then
    bad "E1 UNKNOWN — SUITES 배열의 닫는 괄호를 못 찾음"
  else
    ENROLLED=$(sed -n "${S_LINE},${E_LINE}p" "$RUNNER" | grep -oE '"[^"]*\.(R|sh|py)"' | tr -d '"' | sed 's|.*/||' | sort -u)
    n_enrolled=$(printf '%s\n' "$ENROLLED" | grep -c . || true)
    if [ "$n_enrolled" -eq 0 ]; then
      bad "E1 UNKNOWN — SUITES 배열에서 항목 0건 추출 (통과로 위장 금지)"
    else
      ok "E1 SUITES 파싱 = ${n_enrolled}건 (${S_LINE}~${E_LINE}행)"

      # ── 집계 러너가 등재된 디렉터리 집합 ─────────────────────────────────
      AGG_DIRS=""
      while IFS= read -r rp; do
        case "$(basename "$rp")" in run_*.R|run_*.sh) ;; *) continue ;; esac
        printf '%s\n' "$ENROLLED" | grep -qxF "$(basename "$rp")" || continue
        AGG_DIRS="$AGG_DIRS$(dirname "$rp")\n"
      done < <(find "$TESTS_DIR" -type f \( -name 'run_*.R' -o -name 'run_*.sh' \) -not -path '*/_archive*/*' 2>/dev/null)
      # ★`grep -c .` 은 0건이어도 "0" 을 **출력하고** exit 1 이다. `|| echo 0` 를 붙이면
      #   "0\n0" 이 되어 산술 비교가 깨지고 검사가 **무조건 FAIL** 로 굳는다(2026-08-16
      #   실측 — 양성 대조 T0 가 아니었으면 "FAIL 기대" 축들이 공허하게 통과했다).
      AGG_DIRS=$(printf '%b' "$AGG_DIRS" | grep -c . || true)

      # ── 커버리지 판정 ────────────────────────────────────────────────────
      UNCOVERED=""; n_files=0
      while IFS= read -r f; do
        n_files=$((n_files+1))
        b=$(basename "$f")
        printf '%s\n' "$ENROLLED" | grep -qxF "$b" && continue
        d=$(dirname "$f")
        _agg=$(find "$d" -maxdepth 1 -type f \( -name 'run_*.R' -o -name 'run_*.sh' \) 2>/dev/null | while IFS= read -r r; do
                 printf '%s\n' "$ENROLLED" | grep -qxF "$(basename "$r")" && echo hit; done | head -1)
        [ -n "$_agg" ] && continue
        # ★sed 로 접두 제거 금지 — PROJECT 가 Windows 경로(C:\Users\99922\...)면
        #   `\99922` 가 **백레퍼런스로 해석**돼 "Invalid back reference" 로 죽는다
        #   (r-portability 계통, 2026-08-16 실측). 쉘 파라미터 확장으로 자른다.
        _rel="${f#"$PROJECT"/}"
        UNCOVERED="$UNCOVERED  ${_rel}\n"
      done < <(find "$TESTS_DIR" -type f \( -name 'test_*.R' -o -name 'test_*.sh' -o -name 'test_*.py' \) -not -path '*/_archive*/*' -not -path '*/lib/*' 2>/dev/null | sort)

      n_unc=$(printf '%b' "$UNCOVERED" | grep -c . || true)
      if [ "$n_files" -eq 0 ]; then
        bad "E2 UNKNOWN — test_* 파일 0건 발견 (스캔 실패로 위장 금지)"
      elif [ "$n_unc" -eq 0 ]; then
        ok "E2 편입 커버리지 = ${n_files}건 전부 (직접 등재 ∪ 집계 러너 ${AGG_DIRS}개 디렉터리)"
      else
        bad "E2 미편입 테스트 ${n_unc}/${n_files}건 — 배터리가 이 파일들을 한 번도 돌리지 않는다. SUITES 에 등재하거나, 해당 디렉터리에 자동 탐색 집계 러너를 두고 그 러너를 등재할 것:"
        printf '%b' "$UNCOVERED"
      fi
    fi
  fi
fi

echo ""
echo "suite-enrollment: PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"suite_enrollment\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
