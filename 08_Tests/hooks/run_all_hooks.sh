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
  # 2026-08-01 추가: 운용 슬롯/보유파일 해석기 위반 주입 (라이브 추적이 배포된 북을 보는지의 가드)
  "08_Tests/portfolio/test_resolve_admitted_slot.R"
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
  # 2026-08-02 추가: FQ-002 계약 패널 빌더 로직(합성 픽스처, API 무호출).
  #   크롤 1시간 태우기 전에 정정 제외·parse실패 제외·trailing 창·빈입력 거부를 확정한다.
  "08_Tests/data/test_contract_panel.R"
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
  #   검사 대상은 사본이 아니라 원본 .sh 의 heredoc 추출 — 마커가 깨지면 FATAL(exit 2)로
  #     중단한다("조용히 0건 검사"가 초록으로 보이는 것을 막는다).
  "08_Tests/ops/test_alpha_queue_pending.py"
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
