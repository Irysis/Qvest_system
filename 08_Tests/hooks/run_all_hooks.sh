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
#
# ★후보 순서 = self 최우선 (2026-08-02 수리). 위 헤더가 "앵커는 PROJ_DIR 이 아니라
#   BASH_SOURCE" 라고 선언해 놓고 정작 이 함수는 env 를 먼저 봤다(선언↔구현 불일치).
#   실측 결함: Bash 툴 환경엔 CLAUDE_PROJECT_DIR 이 없고(훅 안에서만 설정됨 —
#   reference-cpd-set-in-hooks-unset-in-bash-tool) QM_ROOT 는 **main** 을 가리킨다.
#   그래서 worktree 에서 `bash 08_Tests/hooks/run_all_hooks.sh` 를 돌리면
#     SUITES 목록은 worktree 사본에서 오는데 PROJ_DIR 은 main 으로 해석돼
#     **전 suite 가 main 의 코드에 대해 실행**됐다.
#   실측(2026-08-02, worktree distracted-greider-f54a99):
#     `Project: /c/Users/99922/OneDrive/Quant_Module_Moltbot` (cwd 는 worktree)
#   결과 두 가지가 전부 오독을 낳는다:
#     (1) worktree 에서 난 초록이 worktree 의 변경을 하나도 검증하지 않는다(main 을 잼).
#     (2) worktree 에서 **신설**한 suite 는 main 에 파일이 없어 UNREPORTED=1 fail 로
#         계상된다 → "테스트 실패" 로 읽히지만 실제로는 앵커 오설정이다
#         (실측: test_sample_alignment_empty.R, FINAL 569 pass / 1 fail).
#   ★표지 검증은 이 갈림을 **판별하지 못한다** — main 도 worktree 도 표지를 갖고 있다.
#     오직 후보 *순서* 만이 결정한다. 그래서 순서가 계약이고, 검사기가 못박는다
#     (08_Tests/hooks/test_resolve_project_marker.sh 축 I/J/K — 위반 주입 + 돌연변이).
#   ★테스트 러너는 **자기가 실린 트리**를 검사해야 한다. 이 규율은 이미 같은 저장소의
#     test_resolve_project_marker.sh:40-45 가 선례로 쓰고 있었다(그 파일만 고쳐지고
#     러너는 누락). 공유 resolver 2벌(hooks=CPD-first / ops=QM_ROOT-first)은 **소비자
#     계층이 다르므로 무변경** — 그쪽은 훅·스케줄러의 데이터 루트 해석이고, 순서는
#     2026-08-01 도훈 결정이며 같은 검사기 축 G 가 양방향으로 고정한다.
#     계약 본문: 02_Infrastructure/docs/rules/r-portability.md ④-b.
#   ★정규화(역슬래시→슬래시)는 검사 **전에** 한다 — QM_ROOT(User scope)가 `C:\...`
#     형식이라, 검사 뒤로 미루면 형식 오류가 존재 검사를 그냥 통과한다(2026-08-01 실사고).
_MARKER="08_Tests/hooks/run_all_hooks.sh"
_SELF_ROOT="$(cd "$_SELF_DIR/../.." 2>/dev/null && pwd)"
_pick_proj_dir() {
  local c n
  # ★앵커 순서 정본 = 이 줄. 위반 주입 테스트가 이 줄을 갈아끼워 검출력을 실증한다
  #   (test_resolve_project_marker.sh 축 J). 순서를 바꾸려면 그 검사기부터 통과시킬 것.
  for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
    [[ -n "$c" ]] || continue
    n="${c//\\//}"
    if [[ -f "$n/$_MARKER" ]]; then (cd "$n" && pwd); return 0; fi
  done
  return 1
}
if ! PROJ_DIR="$(_pick_proj_dir)"; then
  echo "❌ PROJECT_ROOT 해석 실패 — 표지 '$_MARKER' 를 가진 후보 없음" >&2
  echo "   self='$_SELF_ROOT' CLAUDE_PROJECT_DIR='${CLAUDE_PROJECT_DIR:-}' QM_ROOT='${QM_ROOT:-}' PWD='$PWD'" >&2
  exit 2
fi
# 앵커가 자기 트리와 갈리는 경우(= 러너 사본이 표지 없는 위치에 있어 env 로 낙하한 경우)는
# **보이게** 만든다. 침묵 낙하가 바로 이 계통의 재발 기전이다 — 의도적 override 라면
# 로그에 남고, 사고라면 즉시 눈에 띈다.
if [[ -n "$_SELF_ROOT" && "$PROJ_DIR" != "$_SELF_ROOT" ]]; then
  echo "⚠ ANCHOR OVERRIDE: 러너 위치='$_SELF_ROOT' 이나 검사 대상='$PROJ_DIR'" >&2
  echo "   → 이 실행의 초록은 러너가 실린 트리가 아니라 위 대상 트리를 검증합니다." >&2
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

#──────────────────────────────────────────────────────────────────────────────
# 제3상태 `skipped` (2026-08-02 신설)
#
# 왜: 어떤 축은 이 트리에 없는 산출물(.cache/*, venv 등 gitignore 대상)을 전제한다.
#   worktree 에서 그 전제가 없을 때 종전엔 두 갈래로만 갈렸다 —
#     ① 실패로 계상  → "계약 위반"과 "전제 부재"가 같은 빨강이 된다(오진단).
#     ② 조용히 통과  → 이 저장소가 12회 수리한 "빈 결과 = 합격" 계통 그대로다.
#   둘 다 틀렸다. 전제 부재는 **판정 없음**이고, 판정 없음은 그 자체로 보고돼야 한다.
#
# 계약: suite 요약 JSON 은 pass/fail 외에 다음을 낼 수 있다.
#   "skipped": <미실행 검사 수>,
#   "skips": [{"axis":"...","reason":"...","missing":"<없는 절대경로>"}]
#   ★ total = pass + fail (실제로 판정한 수). skipped 는 total 에 포함하지 않는다 —
#     포함하면 "몇 건을 실제로 쟀나"가 다시 흐려진다.
#   ★ skipped 는 종료코드에 영향을 주지 않는다(전제 부재는 회귀가 아니다). 대신
#     FINAL 줄과 결과 JSON 양쪽에 항상 드러나 pass/fail 어느 쪽으로도 흡수되지 않는다.
#──────────────────────────────────────────────────────────────────────────────
TOTAL_SKIP=0
SKIP_LINES=()

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
    print("PARSED|" + str(d.get("test","?")) + "|" + str(d.get("pass",0)) + "|" + str(d.get("fail",0)) + "|" + str(d.get("total",0)) + "|" + str(d.get("skipped",0)))
except Exception as e:
    print("PARSE_ERROR|" + str(e))
' | while IFS='|' read -r marker test_name pass fail total skipped; do
    if [[ "$marker" == "PARSED" ]]; then
      ALL_RESULTS+=("{\"test\":\"$test_name\",\"pass\":$pass,\"fail\":$fail,\"total\":$total,\"skipped\":$skipped}")
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
  # 2026-08-01 추가: 운용 슬롯/보유파일 해석기 위반 주입 (라이브 추적이 배포된 북을 보는지의 가드)
  "08_Tests/portfolio/test_resolve_admitted_slot.R"
  # 2026-08-02 추가: screening tier 라벨(screen_route) 소비 배관의 차단 실효.
  #   hurdle_gate 가 STANDALONE_TRACK 을 발급했는데 소비자 코드가 0건이라
  #   Chen-Welch(STR_AS_20260709_074129_30048, proxy Grade A)가 3주+ 판정 없이 방치됐다.
  #   ★배관을 놓는 것만으로는 재발이 안 막힌다 — 배관이 조용히 죽으면 미처분이 0 으로
  #    떨어지고 그 0 이 "밀린 후보 없음"으로 읽힌다. 위반 주입 + 오발화 확인 양쪽을 잰다.
  "08_Tests/portfolio/test_standalone_track_queue.R"
  # 2026-08-02 추가: artifact lineage 의 git 상태 기록 계약.
  #   구 capture_git_state() 가 셸 리다이렉션을 argv 로 주입해 git status 가 통째로 실패했고,
  #   `length(out) > 0` 이 **항상 FALSE** → "clean tree" 로 위장했다(2026-06~08 79건 전량 FALSE).
  #   금칙 ⑤ 의 정적 검출(test_r_portability.R)만으로는 "라벨이 JSON 까지 도달하는가"를 못 본다.
  "08_Tests/hooks/test_lineage_git_state.R"
  # 2026-08-02 추가: PIT lookahead 검출기의 "미스캔 ≠ 통과" 계약.
  #   detect_lookahead 가 파일 부재 시 clean=TRUE 를, dir/gate15 가 대상 0개일 때
  #   "ALL CLEAN: 0 files scanned"·"INFRA_PIT_SCAN PASS: 0 files" 를 냈다 —
  #   스캔 0회가 PIT 통과 판정이 되는 자리(AX-002 동급). 돌연변이로 검출력 실증(3축 반전).
  "08_Tests/hooks/test_lookahead_unscanned.R"
  # 2026-08-02 추가: 전제 부재 제3상태(skipped) 계약.
  #   worktree 에 자기-앵커로 배터리를 돌리면 17건이 붉었는데 전부 gitignore 산출물
  #   (.cache/*, venv) 전제였다 — 그중 deployed_holdings_check 는 14건 **전부 exit 49**,
  #   즉 검사기 미실행인데 "배포 제약 위반 14건 미검거"로 읽혔다(양성 대조 T0 도 같은 49).
  #   전제 부재를 fail 로 세면 오진단, pass 로 세면 "빈 결과 = 합격" 재발 —
  #   그래서 제3상태를 뒀고, 이 검사가 그 제3상태의 차단 실효를 잰다
  #   (전제 있을 때 위반 검거 / 없을 때 사유+경로와 함께 skip / 러너 FINAL 노출).
  "08_Tests/hooks/test_prereq_skip_contract.sh"
  # 2026-08-02 추가: FQ-002 계약 패널 빌더 로직(합성 픽스처, API 무호출).
  #   크롤 1시간 태우기 전에 정정 제외·parse실패 제외·trailing 창·빈입력 거부를 확정한다.
  "08_Tests/data/test_contract_panel.R"
  # 2026-08-02 추가: 원장 3종(큐·EV지도·Distilled) 정합 스크린.
  #   같은 날 3회 근접 사고(FQ-095 D2 / FQ-004 카드 추월 / R4 임의착수금지)를 기계화.
  #   ★스크린 초판이 카드 축에서 0건을 반환하고 그 0 이 '충돌 없음'으로 읽혔다 —
  #    도구 자신이 "빈 결과 = 합격"을 재현. 그 차단 실효를 이 검사기가 실측한다.
  "08_Tests/data/test_frontier_coherence.R"
  # 2026-07-26 추가: 부팅 자기-정합 검사(boot_currency_check) 위반 주입 — 부팅 최신화 자동 배선의 가드
  "08_Tests/hooks/test_boot_currency.sh"
  # 2026-07-26 추가: cache_freshness worse-of lag 위반 주입 (CFA-02 수리 가드).
  #   forward-dated / 파일명-추정 캐시는 생성기가 죽어 파일이 동결돼도 data_lag 가 낮아
  #   FRESH 로 보고됐다 — 동결을 보는 유일 축(mtime)이 폐기되던 구조.
  #   caches_override/today/persist 주입 파라미터의 첫 소비자(노출만 돼 있고 케이스 0건이었음).
  "08_Tests/data/test_cache_freshness_worse_of.R"
  # 2026-08-02 추가: 무인 일일 체인(daily_refresh.sh)에 내장된 run_r 'R 코드' 블록의
  #   **구문 사전검사**. 실사고: r18(완료/부분실패 통보) 블록의 최상위 if/else 가 두 줄로
  #   쪼개져 "unexpected 'else'" 로 죽었고 — 하필 그 블록이 실패를 알리는 스텝이라
  #   DailyRefresh rc=1 만 남고 실패 요약은 텔레그램에 도달하지 못했다.
  #   내장 R 을 실행 전에 보는 장치가 저장소에 0건이었다(구문 오류는 새벽 로그에만 드러남).
  "08_Tests/data/test_daily_refresh_r_blocks.R"
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
  # 2026-07-26 추가(R1): DART reprt_code ↔ 분기 매핑 위반 주입.
  #   원 결함 = REPRT_MAP 이 11014→q1 / 11013→q3 로 뒤집혀 3분기(11월 접수) 보고서가
  #   Factor_Date 5/15 를 받음 → 중앙 시차 −183일 · look-ahead 99.8%(PIT C4).
  #   ★ 매핑이 **두 파일**(제출창 dart_submission_window.R / 분기라벨 REPRT_MAP)에
  #     나뉘어 있어 한쪽만 고치면 각자 자기 안에서는 일관돼 보인다 — 그래서 A2 가
  #     단일 파일 검증이 아니라 두 파일 **교차 합치**를 건다.
  #   D축이 구 매핑을 같은 데이터에 주입해 −183일·99.8% 를 재현하므로 케이스가 공허하지 않다.
  "08_Tests/data/test_dart_reprt_quarter_map.R"
  # 2026-07-26 추가(1단 수리 가드): 침묵 실패 3종 위반 주입 —
  #   WCS-06 dry_run 라벨↔실제 부작용 1:1(구판은 DRY 에서 정본 인덱스 재작성+텔레그램 실발송) /
  #   CBA-04 파손 governance_log 덮어쓰기 중단·사이드카 격리(비가역 이력 소실 방지) /
  #   WTL-1·5 join 키 2세대 확장 + 매치0 WARN + save 성공만 계상.
  #   ※ 등재가 늦은 이유: 병렬 세션의 [TEMP-VIOLATION-INJECTION 임무V]가 총계-감소 경보를
  #     실측하는 동안 suite 추가는 총계를 올려 그 측정을 가린다 — 원복 확인 후 등재.
  "08_Tests/ops/test_tier1_silent_failures.R"
  # 2026-07-26 추가: events.jsonl 원장 소비면(발화0 감지) 위반 주입 —
  #   관측창 가드(2분 된 원장으로 "7일 발화 0" WARN 하던 오탐)·미측정≠0·회전·미커버 게이트
  #   이름 노출. 이 감시기가 침묵하면 "발화 0" 지문 자체를 놓친다.
  "08_Tests/ops/test_hook_fire_coverage.sh"
  # 2026-08-01 추가: resolve_project.sh 루트 marker 게이트 위반 주입 (r-portability 금칙 ③).
  #   원 결함 = QM_ROOT 분기가 `[ -d ]` 만 봐서 역슬래시 루트(`C:\Users\...`)를 수락 →
  #   daily_refresh 의 setwd("$BASE") 6지점이 R 소스문자열 `\U` 파싱으로 halt,
  #   5개 스텝(KTRI v3·MSM·regime_daily_v2·SJM·cache_freshness_audit)이 **침묵 실패**.
  #   ★ ops/ 판과 hooks/ 판 **두 벌 모두**에 게이트를 요구한다 — 동명 2벌은 주석이 아니라
  #     이 검사기가 동기화를 강제한다. 돌연변이(게이트를 -d 로 되돌린 사본) 축 포함.
  #   [2026-08-02 병합] 08-01 worktree(serene-liskov-598614)에 미커밋 좌초해 main 미반영
  #     상태였다 — 메모리는 "검사기 11/11 완료"로 기록했으나 main marker 참조는 0건이었다.
  #     '수리했는데 main에 없음' 실사고 계통(date32 writer·lcode harvester 전례) 재발.
  "08_Tests/hooks/test_resolve_project_marker.sh"
  # 2026-08-01 추가: 배포 홀딩 제약 검사기 위반 주입 —
  #   월간 리밸 Gate C 는 "CSV 생성 + 5행"만 봐서 전월 재출력·제약 위반이 통과했다
  #   (감사 실측: 하드 제약 4종이 배포 체인 어디서도 산출물에 대해 검증되지 않음).
  #   deployed_holdings_check.py 가 그 마지막 방어선이므로, 이 검사기가 죽으면
  #   "전부 OK" 와 "아무것도 안 잼" 이 겉보기에 같아진다. T13 음성 통제 포함.
  "08_Tests/portfolio/test_deployed_holdings_check.sh"
  # 2026-08-02 추가: AST v1.1 계층 2종 (Step 3 게이트 + Step 4 사이드카).
  #   ★등재 사유 = 실사고: Step 4 사이드카는 07-25 배선 후 8일간 정기검사를 통과하면서
  #   실전 레코드가 0건이었다(399행 전부 테스트 배터리 산물. essence_score 가 proxy 사다리
  #   통과분만 경유 = 생존편향 + canonical_screen 미배선). 게이트 전용 위반 주입 테스트도
  #   부재해 "조건부 훅이라 트리거 미도달"과 "차단 실효 사망"을 판별할 수단이 없었다.
  #   두 검사 다 양성 대조 + 위반 주입 양방향이라, 죽으면 총계가 떨어져 드러난다.
  "08_Tests/hooks/test_ast_spec_gate.sh"
  "08_Tests/contract_regression/test_ast_sidecar.R"
  # 2026-08-08 추가: 관측 경보 2종의 **판정 계약**. 둘 다 경보를 *줄이는* 수리를 담고 있어
  #   "조용해진 것"과 "판정이 죽은 것"이 겉보기에 같다 — 그 구분이 이 검사기들의 존재 이유다.
  #   · task_health: 08-08 00:03 보고 "실패 4"가 4건 전부 허위였다(실행 중 rc 를 완료 판정으로
  #     읽음 2건 + 같은 실패 1건을 7일간 매 폴링 재보고 2건). state 권위·(작업,실행시각) dedup 도입.
  #   · stranded: 유실 36건 중 진짜 미도달 7건, 나머지는 append-only 원장 분기(26)와
  #     main 이 이미 앞서 나간 구판(19). 방향 개념이 없어 **통합이 성공할수록 경보가 커졌다**.
  #   양쪽 다 양성 대조 + 돌연변이(면제 규칙 무력화 시 뒤집힘)를 포함 — 죽으면 총계가 떨어진다.
  "08_Tests/hooks/test_scheduler_task_health_verdict.sh"
  "08_Tests/hooks/test_stranded_triage.sh"
  # 2026-08-08 추가: 배선 지도 생성기(wiring_map_build.R) 계수 규칙 고정.
  #   ★등재 사유 = 생성기가 개발 중 **네 번 틀렸고 네 번 다 양성 대조가 잡았다**
  #   (일반명 심볼 과대계상 16 / 자기참조로 orphan 3→0 / 문서 언급을 배선으로 계상 /
  #    재구현 축 미재현→발행 보류). 지도가 틀리면 "배선 완료"라는 **거짓 초록**이 되므로
  #   계수 규칙을 픽스처로 못박고, 드리프트 감지는 양방향(끊으면 exit 2 · 그대로면 exit 0)으로 실증한다.
  "08_Tests/hooks/test_wiring_map.R"
  # 2026-08-02 추가: 벤치마크 2소스 정합 감시 위반 주입.
  #   ★등재 사유 = 실사고: RAWDATA.parquet::BM_Ret 과 benchmark.parquet::BM_Ret 은
  #   독립 생성 경로(krx_build_rawdata.R:223 자체계산 vs incremental_update_file.R:181 조인)인데
  #   정합 검사가 없어 2026-07 에 8일이 갈렸다. 4일은 RAWDATA 가 정확히 0 —
  #   07-28 폭락 -11.55% 가 0으로 소실됐고, 값이 0이면 "그날 안 움직였다"로 읽혀
  #   결손이 정상 데이터로 위장된다(월 누적 -17.70% vs 정본 -23.63%, 5.93%p).
  #   07-25 date32 writer 불일치(조인 silent all-NA·7일 방치·감지장치 0)와 같은 계통.
  "08_Tests/data/test_benchmark_source_parity.R"
  # 2026-08-02 추가: ast_verify 방언 수용 + 빈 순회 차단 (ALB-007 CRITICAL 수리 고정).
  #   원 결함 = 정적검증기가 컴파일러 방언(args/type:leaf/params)을 순회 못 해
  #   **leaf_count=0 으로 PASS 를 발행** — 실행되는 트리의 PIT 검증이 사실상 사망.
  #   "위반 0"과 "검사 0"이 같은 출력이라 단일 실행으로는 판별 불가였다.
  #   수리 후 동일 패키지 leaf_count 0→4 · op_count 1→12. B1(빈 순회 ≠ PASS)이
  #   근본 방어이고, C1(실제 look-ahead 검거)이 검증 본체의 생존 지문이다.
  "08_Tests/hooks/test_ast_verify_dialect.sh"
  # 2026-08-02 추가: 논문 라우터 트리거 축. 실사고 = recharge 가 mcp_candidates=38 로 정상
  #   수집했는데 후보가 전부 이미 registry 에 있어 downloaded=0 이 됐고, 라우터는 downloaded
  #   만 봐서 38편이 좌초했다. downloaded 는 "PDF 를 새로 받았나"이지 "라우팅할 재료가
  #   있나"가 아니다. 무인 스케줄러 경로라 검사가 없으면 조용히 되돌아간다.
  "08_Tests/ops/test_paper_router_trigger.sh"
  # 2026-08-02 추가: worktree 좌초 판정축. ★이 축이 **하루에 세 번 뒤집혔다** —
  #   연차 단독(무해 3건 오강조 + 진짜 좌초 미검출) → main부재 단독(진행 중 작업 오인)
  #   → main부재 AND 무활동(정본). 검사 없이 두면 또 뒤집힌다.
  #   E5 는 성능 회귀 가드(전트리 find = 부팅 5분+ 지연, 변경파일 mtime 만 봐야 함).
  "08_Tests/ops/test_worktree_stranded_axis.sh"
  # 2026-08-02 추가: alpha_search_queue pending 산정 위반 주입 (키 불일치 2건 수리 고정).
  #   원 결함 = 양방향 오계수인데 **둘 다 오류 없이 조용히**, 그리고 **서로를 상쇄**했다 —
  #     ① route_20260727 의 id 는 "arxiv:2607.19497", done 원장은 bare → 접두 붙은 건이
  #        `pid not in done` 항상 참 → 이미 소비·QUARANTINE 판정난 2건이 영구 pending(부풀림).
  #     ② queue_20260726/27 의 candidates 키는 `paper_id` 인데 카운터는 id/arxiv_id 만
  #        읽음 → pid='' → 전건 침묵 미계수(①과 반대 방향).
  #   ★상쇄형이라 총계가 "그럴듯한 숫자"로 착지한다 — 총계 감시(0=계측 사망 가드)로는 못 잡는다.
  #   ★"N 이 줄었다"도 증거가 아니다(검사기를 죽여도 N 은 준다). 그래서 done-hit 제외(A축)와
  #     신규 testable 검거(B축)를 **양방향**으로 걸고, 수리 전 블록을 음성 기준으로 함께
  #     돌려 이 검사가 결함을 실제로 구별하는지 매 실행 확인한다(구별 8건).
  #   검사 대상은 사본이 아니라 원본 술어 — 2026-08-02 공용 모듈 승격 이후 원본 =
  #     02_Infrastructure/ops/research_pool_predicates.py (구판은 .sh 의 heredoc 추출).
  #     소비자가 정본을 경유하는지는 W축(배선 단언)이 함께 확인한다.
  "08_Tests/ops/test_alpha_queue_pending.py"
  # 2026-08-02 추가: insider tripwire 도달가능성 라벨 (WIRE-1 / R43-F1 수리 고정).
  #   원 결함 = SAFE tripwire 가 253개월 중 126개월(49.8%) 침묵인데 리포트가
  #   **'자격자 부재'와 '문턱 도달 불가'를 구별하지 못했다** — 침묵월 max z 중앙값 0.862,
  #   최대 0.99968 로 문턱 1.0 에 도달 자체가 불가(INS02 가 [-1,1] 유계·상한에 질량 집중).
  #   ★배선 당일 실측: 현 홀딩월 max z 0.912 → 'NET_BUY_SAFE 0' 은 안전 신호가 없는 게
  #   아니라 측정이 침묵한 것이었다. "발화 0 = 안전"으로 읽히는 침묵 실패 계통.
  #   검사는 사본이 아니라 production 파일에서 정의를 직접 파싱해 평가하고(사본은 원본
  #   사망을 못 잡는다), 라벨이 실제로 뒤집히는지·빈 입력이 REACHABLE 로 새지 않는지·
  #   호출부와 출력 노출이 살아있는지(정의만 남은 dead code = '배선 완료' 위장)를 함께 본다.
  "08_Tests/hooks/test_tripwire_reachability.R"
  # 2026-08-08 추가: 라벨 자격 관문 (FQ-119).
  #   원 결함 = **판별력 없는 라벨로 소비면을 측정하는 라운드가 반복**됐다. 08-03 실측 3건:
  #   ① 국면 CRISIS 라벨 recall 0.096 < base 0.457(fisher p 0.388) ② 독립 음성대조 0.3669
  #   ③ 무판별 라벨을 소비면에 강행하면 **발화 월수에 비례해 유해**(WT-019 paired -3.77).
  #   "틀려도 보험"이 반증됐다 — 판별력 없는 라벨은 중립이 아니라 손실이다.
  #   관문이 죽으면 그 라운드들이 다시 통과하고, 결과가 양수든 음수든 해석 불가가 된다.
  #   검사는 양방향(자격 라벨 통과 · 무작위/역방향 차단)이라 항상-차단/항상-통과를 구별한다.
  "08_Tests/contract_regression/test_label_eligibility_gate.R"
  # 2026-08-02 추가: factor_deep_recheck 큐 산정 위반 주입 — 위 alpha_queue 수리 직후
  #   **동형 스캔이 같은 결함을 실행 트리거에서** 찾아낸 자리다(형제 파일 미전파 계통).
  #   실측: route 는 "arxiv:2607.16450", done 원장은 bare → 08-02 큐가 **3/3 전량
  #   이미 처리분**(참값 0). 표시 버그가 아니라 morning_run [0.55/3] 이 이 큐로
  #   `claude -p` 심층 재검을 돌리므로 끝난 논문에 매일 토큰을 태우고 있었다.
  #   W축(산출 큐에 적히는 id 가 정규화형인가)이 하류 재오염 차단 지문이다.
  "08_Tests/ops/test_factor_recheck_pending.py"
  # 2026-08-02 추가: mode_queue 라우트 해석기 위반 주입 — 위 두 건과 같은 스캔에서 나온
  #   **확정 유실 사고**다(잠복 아님). mode_queue_20260727.json 이 3키를 queue{} 안에 넣었고
  #   paper_research_dispatch.R 은 최상위만 봐서 0/0/0 → research_status_20260727.json
  #   actions=[] = **14편(opt 7·risk 4·regime 3) 전량 드롭**, optimizer 7편의 Σ-가중 A/B 미실행.
  #   ★schema_version 으로 분기 불가(07-27="mode_queue_v1" / 08-02="paper_router_v2"=생산자 이름).
  #   D축(미해석 키 경고)이 "0편"과 "못 읽음"을 가르는 유일 지문이고,
  #   E축이 생산자 프롬프트 계약까지 걸어 소비자만 고치고 끝나는 것을 막는다.
  "08_Tests/ops/test_mode_queue_dispatch_schema.R"
  # 2026-08-02 추가: 부팅 리더(research_pool_status.py) 3축 위반 주입 + 술어 공용화 배선.
  #   ★위 세 suite 가 지키는 술어를 **리더는 자기 안에 얕게 재구현**하고 있었다 — 그래서
  #     소비자 3종은 수리됐는데 리더만 틀린 채로 매일 부팅 라인에 광고했다:
  #       축1 "testable route 2"(그날 QUARANTINE 완료분) — done 미차감 + `_latest` 한 파일만.
  #            진짜 미소비분은 과거 파일에 있어 아예 안 잡혔다(정본 술어 참값 1).
  #       축2 "recheck잔여 3" — 참값 0. 큐 'arxiv:' 접두를 done bare 와 raw 비교.
  #       축3 mode_queue 최상위-only — 07-27 queue{} 중첩 판을 재생하면 0/0/0.
  #   ★수리 형태 = 술어를 02_Infrastructure/ops/research_pool_predicates.py 로 승격(도훈
  #     사전등록 조건 "세 번째 소비자가 나타나면 공용 모듈 승격 재판정" 발효 — 리더가 3번째).
  #     그래서 이 suite 의 W축은 **배선 단언**이다: 리더가 정본을 경유하는가 + 술어를 다시
  #     적지 않았는가(정규화 정규식 재출현 감시). 모듈만 초록이고 소비자가 자기 술어를
  #     되살리면 승격이 무효화되는데, 그 상태는 다른 어떤 검사에도 안 보인다.
  "08_Tests/ops/test_research_pool_status_axes.py"
  # 2026-08-02 추가: 테스트 러너 앵커 순서(self-first) 위반 주입 — 바로 위 이 러너가
  #   고친 것과 **같은 결함이 남아 있던 러너 2종**(08_Tests/regime/run_all.R ·
  #   02_Infrastructure/tests/test_continuity_gate.py)의 회귀 가드다.
  #   실측(수리 전): regime 러너는 worktree 6파일 / main 5파일 상태에서 worktree 실행 시
  #   "Test files found: 5" (main 것을 발견) · continuity 배터리는 cwd=worktree 인데
  #   ROOT=main 으로 **main 의 continuity_gate.py 를 검사**했다(게다가 표지 검증 없이
  #   하드코딩 main 경로가 최종 폴백이었다).
  #   ★표지 검증으로는 못 가른다(두 트리 다 표지 보유) — 가르는 것은 후보 **순서**뿐이라,
  #     순서를 계약으로 못박고 돌연변이(env-first 복원)로 검출력을 매 실행 실증한다.
  #   ★가드 needle 을 *수리된 순서 줄* 로 잡지 않는다 — 그러면 결함 상태가 "needle 갱신
  #     필요" 라는 정비 메시지로 나타나 다음 사람이 needle 을 고치는 것으로 env-first 를
  #     조용히 재수용한다(run_all_hooks 앵커 수리 중 실제로 저지르고 정정한 실수).
  #   ★분담: 이 러너 자신의 앵커는 test_resolve_project_marker.sh 축 I/J/K 가 본다
  #     (.sh 표면). 이 파일은 그 검사기가 구조적으로 못 보는 **.R 러너와 .py 배터리**를 덮는다.
  #     계약 본문 = 02_Infrastructure/docs/rules/r-portability.md ④-b.
  "08_Tests/hooks/test_runner_anchor_selffirst.sh"
  # 2026-08-02 추가: AST factor_db_monthly 리프의 행 라벨 = 커넥터 as-of 계약.
  #   실사고 = provider 가 월 팩터 행을 **캘린더 월말**로 합성 라벨했는데 eval 그리드는
  #   **거래일 월말**(RAWDATA 기준)이라, 거래말<캘린더말 인 94/259 월(36.3%)에서
  #   AS_OF 조인이 전월 값을 당겼다 — 1개월 stale(lag 방향이라 look-ahead 아님, 측정 감쇠).
  #   ★8일간 안 잡힌 이유가 이 검사의 존재 이유다: 기존 parity 검사가 EVAL_DATES 를
  #   provider 와 **같은 좌표계**(캘린더 월말)로 잡아 결함이 상쇄돼 rho=1.0 이 나왔다
  #   (검사가 옳은 값을 재는데 잘못된 좌표계에 서 있던 경우). 그래서 본 검사는 eval
  #   그리드를 factor DB 와 무관한 RAWDATA 거래일에서 만든다.
  #   C축(구판 라벨 재현 → 검사가 실제 FAIL 하나)이 검출력 실증, B축이 fail-closed
  #   (as-of 미보고 시 요청일 라벨로 되돌리지 않음 — 되돌림이 곧 원 결함).
  "08_Tests/contract_regression/test_ast_monthly_asof_label.R"
  # 2026-08-03 추가: 커밋/푸시 훅 3종의 **트리 표적 계약**. 08-02 작업 유실의 근본 자리다 —
  #   auto_commit_on_stop.sh 는 하드코딩 glob 으로 첫 존재 후보(항상 main)를 집고
  #   CLAUDE_PROJECT_DIR 을 아예 읽지 않았다. worktree 세션의 Stop 훅이 main 을 커밋하고
  #   worktree 는 정지시킨 뒤 "[OK] N files committed" 를 보고 → **하지 않은 일에 대한
  #   성공 보고**(유실 + 유실의 은폐). 실측 4회, 수리본이 어느 트리에도 없어 수동 회수했다.
  #   ★형제 파일 미전파: 같은 glob 이 milestone_commit.sh(PostToolUse[Write]) ·
  #     auto_push_on_stop.sh 에 복사돼 있었고, 후자는 origin 으로 **밀어낸다**(외부 공개).
  #   ★F축(구조)이 A/B/C/D·G·H(행동)의 실행 가드다 — 구 glob 이 남아 있으면 행동 축은
  #     실 저장소를 집으므로 아예 돌리지 않는다(검사가 main 을 커밋하는 사고 방지).
  #   ★E축(위반 주입)이 검출력 본체. 주입은 해석 블록만 sentinel 로 들어내므로,
  #     `AC_ROOT_SRC` 류 기본 바인딩을 블록 **안**에 두면 변종이 구 결함을 재현하기 전에
  #     `set -u` unbound 로 죽고 나머지 주입 축이 **공허하게 초록**이 된다(실제로 그
  #     상태였고 2026-08-03 정정). 기본 바인딩은 블록 밖에 있어야 한다.
  "08_Tests/hooks/test_auto_commit_worktree_target.sh"
  # 2026-08-02 추가: AX-001(방어 조건부 평가) 차단 실효.
  #   구 규칙은 defense 를 **상시 필드명**(statistical_defense/defense_metrics)이,
  #   면제어 stress 를 **상시 채점항목명**(score_breakdown.stress)이 각각 100% 충족시켜
  #   실제 산출물 559/559 에서 발화 불능이었다 — 규칙은 살아 있는데 입력이 조건을
  #   만족시킬 수 없는 형태의 검사 사망. 위반 주입 + 과차단 + 동적/legacy 2경로 분리 검증.
  "08_Tests/hooks/test_ax001_defense_scope.R"
  # 2026-08-02 추가: P2 Data Separation 감사의 **차단 실효**.
  #   v61_compliance_audit.R 이 lockbox 접근기록을 C:/tmp 에서 찾는데 훅은 MSYS /tmp 에 썼다
  #   → 237/237 WT 가 "no_lockbox_access (clean)" 로 구조적 PASS. **P2 는 실패할 수 없었다.**
  #   경로 리터럴 동기화만 보는 정적 검사로는 부족하다 — 실제로 훅을 돌려 위반을 주입하고
  #   FAIL 이 나오는지, 그리고 구판 로직 재현본이 같은 주입에서 PASS 로 뒤집히는지까지 본다.
  "08_Tests/hooks/test_lockbox_audit_path.R"
  # 2026-08-02 추가: tg_send_rich 미지원-entity 스캔 오프셋 계약.
  #   원 결함 = TRE(기본 엔진)가 위치를 **UTF-16 코드유닛**으로 세는데 regmatches/substr 은
  #   **코드포인트**로 잘라, 매치 앞 non-BMP(이모지) N개마다 추출 창이 N칸 밀렸다.
  #   tg_agent_brief 는 섹션마다 이모지를 넣으므로 이 경로 메시지 전부가 대상 —
  #   07-26~08-02 경보 20건이 전량 유령이었다(정상 escape 된 &lt; 를 '턱 1.' 로 오보).
  #   ★소음보다 반대 방향이 본체다: 밀린 창은 진짜 &le;/&nbsp; 를 **결코 지목하지 못하고**,
  #     우연히 &lt;/&gt;/&amp; 위에 떨어지면 setdiff 가 걸러낸다 = 발화해야 할 때 침묵.
  #   C축이 구 로직을 같은 픽스처에 나란히 돌려 이 검사가 결함을 실제로 구별하는지
  #     매 실행 확인하고(공허화 방지), D축이 "추출물은 entity 모양이어야 한다"는
  #     자기검증 계약을 건다 — 색인 붕괴가 '위반 없음'으로 읽히던 자리.
  "08_Tests/hooks/test_telegram_entity_scan.R"
  # 2026-08-02 추가: strategy_analyzer §7-G 날짜축 정합 판정의 "빈 결과 ≠ 합격" 계약.
  #   원 결함 = `Sample_Aligned <- length(strat_only)==0 && length(bm_only)==0` —
  #   전략·벤치 시계열이 **둘 다 비면** 양쪽 setdiff 가 비어 TRUE("완벽 정렬")가 됐다.
  #   같은 리포트의 Sample_Overlap 은 0 인데 하류가 읽는 건 불리언이라 자기모순이 안 보이고,
  #   감싸는 tryCatch 도 못 잡는다(빈 xts 는 오류가 아니라 warning 만 낸다).
  #   ★C축(구 한 줄 재주입)이 픽스처가 결함을 실제로 건드리는지 매 실행 대조하고,
  #     B축(양성 통제)이 과잉교정("항상 NA")을 잡는다 — 판정 사망과 위반 부재는 겉보기가 같다.
  #   돌연변이 3종으로 검출력 실증(구판복원 1fail / 항상NA 3fail / 함수개명 FATAL).
  "08_Tests/contract_regression/test_sample_alignment_empty.R"
  # 2026-08-03 추가: DART 계약공시 파서 v3 (FQ-125 크롤 선행조건).
  #   ★등재 사유 = 실사고: 구판이 `readLines(encoding="UTF-8")` 로 인코딩을 **하드코딩**했다.
  #   2023-08+ 문서가 우연히 UTF-8 이라 동작했을 뿐, 2019-05 이전은 본문 바이트가 EUC-KR 이라
  #   regex 가 throw → 드라이버 tryCatch 가 삼켜 `PARSER_ERROR`(parse_note **공란**)로 기록됐다.
  #   실측 634건 전량. 즉 **"성공"이 우연이었고, 실패는 사유 없이 기록됐다.**
  #   ★B축(돌연변이)이 핵심: CP949 분기를 죽였을 때 실제로 빨개지는지를 매 실행 확인한다.
  #     안 하면 UTF-8 분기 하나로 구서식 축까지 초록이 되어 축이 공허해진다.
  #   ★E축 = 상태 라벨 분리. 구판은 정정공시 원문부재(DART 014)·**일한도 소진(020)**·진짜 zip
  #     손상을 전부 `UNZIP_FAIL` 로 뭉갰다 — 한도 소진이 '원문 없음'으로 체크포인트에
  #     영구 동결되는 자리(이 저장소 "빈 결과 = 합격" 계통과 동형).
  #   ★C축 = 금액 훼손 검거(공시 동봉 `매출액대비(%)` 대조). 구판엔 대조가 없어 오값이
  #     조용히 OK 로 기록됐다(실측 20230809800003: 라벨 뒤 첫 숫자가 "2. 계약내역"의 2 → amt=2).
  #   G축은 .cache 실문서 전제라 부재 시 **skipped**(전제 부재를 fail 로 세면 오진단).
  "08_Tests/data/test_contract_parser_v3.R"
  # 2026-08-02 추가: 모듈 원장 상호배타(catalog ↔ quarantine) 위반 주입.
  #   원 결함 = register_module 의 .upsert_registry() 가 catalog 승격 시 기존 quarantine
  #   행을 회수하지 않았다. run_alpha_search 는 같은 전략을 **두 번** 등록한다 —
  #   6c(재측정 전 proxy → quarantine) → 6e(권위 재측정 후 backtested → catalog).
  #   ★두 행이 공존하면 quarantine 만 읽는 소비자가 최종상태를 **정반대로** 읽는다:
  #   Chen-Welch(STR_AS_20260709_074129_30048)는 quarantine 상 fr_eligible=FALSE 라
  #   기각처럼 보이지만 실제 최종은 catalog 의 FR_ELIGIBLE 이다. 2026-08-02
  #   STANDALONE_TRACK 배관 수리의 "quarantine 에 유실" 오진단이 정확히 이것이었다.
  #   ★거울상까지 닫는다 — 한 방향(승격)만 고치면 강등 방향에 같은 모호성이 남는다.
  #   B축이 수리를 **되돌린 돌연변이**를 주입해 중복 재현 + 상시 스크린(reconcile) 발화를
  #   실증하므로 케이스가 공허하지 않다(needle 매치 건수도 실측 단언 — 안 잡히면 거짓 초록).
  #   ※ 2026-08-03 통합 시 실원장 소급분 9건을 reconcile --apply 로 정리
  #     (quarantine.modules 32→23 · superseded 9). 이후 dry-run 잔존 0건.
  "08_Tests/contract_regression/test_module_registry_exclusivity.R"
  # 2026-08-02 추가: EV 항이 살아 있는지. 저장 DB 에서 V13_EV_Sales 가 V08_PSR 과
  #   258/258 개월 cor=1.000000 이었다 — `MarketCap := Close * Size` 로 시총이 종목별
  #   ~5e3 배 부풀어 더해지는 재무 항이 수치적으로 소멸했다. ★결함이 **중복으로 위장**해
  #   dedup 라벨로 접히면 라벨 뒤로 사라진다. 순위-동일 자체를 지문으로 상설 감시한다.
  "08_Tests/factor_db/test_ev_term_not_inert.R"
  # 2026-08-02 추가: factor DB 중복 팩터 스캐너 + registry de-dup 계약.
  #   ★등재 사유 = 실사고: WT-D20260802_003 risk 라운드에서 Ω(팩터 공분산) 추정이
  #   전소했는데 원인이 추정기가 아니라 **입력 중복**이었다 —
  #   D01_IdioVol 과 R12_Idiosyncratic_Risk 가 258/258 개월 bit-identical
  #   (factor_db_daily_phase6.R:286 `R12 <- D01_IdioVol` 리터럴 복사).
  #   전수 스캔 결과 approved 102 에 EXACT 10쌍 / registry 373 에 59쌍 = 계통.
  #   중복은 ICIR 선별에서 이중 투표한다(top-20 중 3슬롯 여분, 변동성 신호 하나가
  #   EW 합성의 20%). ★"중복 0건"이 스캐너 사망 때문인지 청결 때문인지는
  #   주입 없이 구별 불가 — 그래서 완전/근사/부호반전 3종 주입 + rho~0.80 판별
  #   대조 + 대조쌍 생존 확인까지 검사한다.
  "08_Tests/hooks/test_factor_dup_scan.R"
  # 2026-08-02 추가: distilled 재등재 supersede(부분집합 구 카드 자동 회수) 위반 주입.
  #   원 갭 = 같은 클러스터가 supporting L-code 성장 시 새 dist_id 로 재등재되는데 구 카드가
  #   회수되지 않아 pending_5axis 가 07-17 49 → 08-02 89건(완전 중복 0, **부분집합 쌍 30**).
  #   07-18 forward-migration 은 조상이 refined(status=distilled)인 경우만 다뤄 pending
  #   조상은 CAND superset dedup 으로 고아가 된 뒤 main loop 가 영영 지나가지 않는다.
  #   ★이 검사는 **돌연변이 축(M1~M5)이 본체**다: 08-02 수동 드레인 이후 저장소의 추가 회수
  #   대상이 0건이라, 정상 경로만 돌리면 로직이 죽어 있어도 초록으로 보인다. 각 게이트
  #   (정체성·지식손실·status·저술지식)를 하나씩 끄고 판정이 실제로 뒤집히는지 매 실행 실측.
  "08_Tests/axiom/test_distilled_supersede.py"
)

# (2026-08-02) .py 분기 추가 — 종전엔 확장자 무관 `bash` 로 던져 파이썬 suite 가
#   구문오류로 죽고 UNREPORTED(=1 fail)로만 나타났다(무엇이 잘못됐는지는 안 보임).
#   해석기는 bare python3 금지 — Windows Store 스텁이라 스크립트를 실행하지 않는다
#   ([[reference-python3-windows-stub-use-qvest-py]]). 위 헤더가 세운 QVEST_PY_BIN 경유.
_suite_cmd() {
  local rel="$1"
  if [[ "$rel" == *.R ]]; then
    printf 'Rscript "%s/%s"' "$PROJ_DIR" "$rel"
  elif [[ "$rel" == *.py ]]; then
    printf '"%s" "%s/%s"' "$QVEST_PY_BIN" "$PROJ_DIR" "$rel"
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
  elif [[ "$test_script" == *.py ]]; then
    OUT=$("$QVEST_PY_BIN" "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  else
    OUT=$(bash "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  fi
  if echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.loads(sys.stdin.read()); exit(0 if "test" in d else 1)' 2>/dev/null; then
    PASS=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("pass",0))')
    FAIL=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("fail",0))')
    SKIP=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("skipped",0))')
    TOTAL_PASS=$((TOTAL_PASS + PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
    TOTAL_SKIP=$((TOTAL_SKIP + SKIP))
    # 전제 부재 사유는 **경로까지** 보존한다. "무언가 없어서 건너뜀"은 조치 불가능한
    # 보고이고, 조치 불가능한 보고는 결국 무시된다(= 조용한 통과와 같아진다).
    if [[ "$SKIP" -gt 0 ]]; then
      # ★ Windows 파이썬 stdout 은 CRLF — `read -r` 은 CR 을 값에 남긴다. 그 CR 이
      #   결과 JSON 문자열 안으로 들어가면 "Invalid control character" 로 **파일 전체가
      #   파싱 불가**가 된다(소비자 입장에선 결과가 통째로 사라진다).
      #   [[reference-rscript-stdout-crlf-bash-compare]] 계통 — 여기서 잘라낸다.
      while IFS= read -r _sl; do
        _sl="${_sl%$'\r'}"
        [[ -n "$_sl" ]] && SKIP_LINES+=("$(basename "$test_script") :: $_sl")
      done < <(echo "$OUT" | "$QVEST_PY_BIN" -c '
import json,sys
d = json.load(sys.stdin)
sk = d.get("skips") or []
if not sk:
    print("(사유 미기재 — suite 가 skips[] 를 안 냈다)")
for s in sk:
    print("%s — %s [missing: %s]" % (s.get("axis","?"), s.get("reason","?"), s.get("missing","?")))
' 2>/dev/null)
    fi
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
  "total_skipped": $TOTAL_SKIP,
  "total": $((TOTAL_PASS + TOTAL_FAIL)),
  "status": "$(if [[ $TOTAL_FAIL -eq 0 ]]; then echo PASS; else echo FAIL; fi)",
  "skips": [$(_j=""; for _l in ${SKIP_LINES[@]+"${SKIP_LINES[@]}"}; do
                 _e="${_l//\\/\\\\}"; _e="${_e//\"/\\\"}"
                 if [[ -n "$_j" ]]; then _j+=","; fi; _j+="\"$_e\""
               done; printf '%s' "$_j")],
  "tests": [$TESTS_JSON]
}
EOF

echo ""
echo "════════════════════════════════════════"
# 건너뛴 축은 FINAL 위에 **먼저** 나열한다 — 숫자만 남으면 다음 사람은 그 숫자가
# 무엇의 부재인지 알 수 없고, 알 수 없는 항목은 무시된다.
if (( TOTAL_SKIP > 0 )); then
  echo "⊘ SKIPPED $TOTAL_SKIP건 — 이 트리에 전제 산출물이 없어 판정하지 않음(통과 아님·실패 아님):"
  for _l in ${SKIP_LINES[@]+"${SKIP_LINES[@]}"}; do echo "    $_l"; done
  echo "────────────────────────────────────────"
fi
echo "FINAL: $TOTAL_PASS pass / $TOTAL_FAIL fail / $TOTAL_SKIP skipped / $((TOTAL_PASS + TOTAL_FAIL)) total"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  if (( TOTAL_SKIP > 0 )); then
    echo "STATUS: ✅ ALL PASS (단, $TOTAL_SKIP건 미판정 — 위 SKIPPED 목록)"
  else
    echo "STATUS: ✅ ALL PASS"
  fi
else
  echo "STATUS: ❌ FAIL ($TOTAL_FAIL test failures)"
fi
echo "Results: $RESULTS_FILE"
echo "════════════════════════════════════════"

exit $TOTAL_FAIL
