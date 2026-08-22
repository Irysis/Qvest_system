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
  # 2026-08-22 추가(DFA R42): 무신호 대조군 계약. 제약형 롱온리 전략이 "제약을 지키며 벤치를
  #   이겼다" 는 것만으로 신호 기여를 증명하지 못한다 — 롱온리 top-N cap-w 는 그 자체로
  #   대형주 노출을 담는다. 실측(R41): 게이트0 준수 생존팔이 무신호 대조와 구별 불가
  #   (clean 차이 +0.46%/yr NW-t 0.201). 검사기는 위반 주입 3방향 + beta 오염 분리 포함.
  "08_Tests/contracts/test_no_signal_control.R"
  # 2026-08-22 추가(DFA R49): 배선 "도달" 검사. 같은 날 4회 겪은 계통 —
  #   "붙였다" 와 "도달한다" 가 갈린다: ①감사 산출만 있고 읽는 쪽 0 ②module_dispatcher 는
  #   풀을 안 고름(실 결정자는 에이전트) ③신규 엔트리만 배선해 이월분이 우회 ④최상위 on.exit 로
  #   사본 선삭제. 5축(신규/부재/이월+순서/에이전트 지시/규범) + 정본 보호 검사.
  "08_Tests/contracts/test_nosignal_wiring_reach.R"
  # 2026-08-22 추가(DFA R53): census 3규약. 같은 날 6회 "0 을 관측했다" 를 "0 이다" 로 읽었다 —
  #   ①KQ150 퇴출0(편입 미측정) ②screen 필드0(잘못된 레지스트리) ③verdict=None(이월 우회)
  #   ④사본 선삭제 ⑤NOT_AUDITED 넘김(통과 후보 유실 직전) ⑥형식 census 표본이 기지 반례 누락.
  #   규약 = (A)기지사례 범위 검증 (B)작으면 전수·기지사례 강제포함 (C)0건에 신뢰상한 병기.
  #   검사기는 "강제포함 없으면 20중 18 놓침" 대조로 도구 필요성 자체를 실증한다.
  "08_Tests/contracts/test_census_helper.R"
  # 2026-08-22 추가(DFA R54): FR 배분 규칙 표현력 진단. compute_regime_module_weights 는
  #   *비중*(합=1)에 softmax(tau=0.6)를 걸어서 모듈 수 n 이 커지면 score 가 1/n 근처로 몰려
  #   출력이 rp 앵커로 수렴한다 — n=21 실측 retention 0.0796(신호 92% 압축), 정적 EW 와
  #   대응표본 구분 불가(NW-t +0.225). 그런데 산출물은 계속 "국면조건부 비중" 으로 라벨된다
  #   = 침묵 실패. 검사기는 양방향(퇴화 발화 / 표현 미발화) + 문턱 돌연변이로 게이트를 실증한다.
  "08_Tests/contracts/test_fr_weight_expressiveness.R"
  # 2026-07-26 추가(T3): IC 월-프론티어 감시(ic_frontier_check) 위반 주입 테스트.
  #   감시기는 07-26 신설되며 ic_max_date_override 를 "주입용"으로 노출해 놓고도 케이스가
  #   0건이었다 — 4트랙 중 유일하게 상설 검사가 없던 갭. 검사 없는 가드는 무력화돼도
  #   "경보 0건"으로만 보인다.
  "08_Tests/factor_db/test_ic_frontier_check.R"
  "08_Tests/factor_db/test_build_hash_provenance.R"
  # 2026-08-08 추가(FQ-163): factor DB 배출 감시 + compute_consensus 도달성.
  #   compute_consensus 의 7개 블록이 `%in% names(cons)` 게이트가 영구 거짓이 되면서
  #   440개월 전 구간 0행이었는데 **아무 경보도 없었다** — 빌더가 "등재된 팩터가
  #   실제로 나왔는가"를 묻지 않았기 때문. 수리만 하면 같은 계통이 다시 생기므로
  #   감시(emission_guard)를 놓았고, 이 검사가 그 감시의 차단 실효를 지킨다.
  #   ★핵심 축은 Class S(구조적 침묵) — 전 구간 0행은 **델타 감시로는 원리적으로
  #    못 잡는다**(사라진 적이 없으니 델타가 없다). B4 가 돌연변이로 검출력을 실증.
  "08_Tests/factor_db/test_emission_guard.R"
  # 2026-08-09 추가(FQ-210): emission_guard 정체 검사 3축(D 무분산 / T 동률 / I 중복).
  #   위 emission_guard 는 `n_rows > 0` 만 본다 — **존재**를 확인했을 뿐 **정체**를
  #   확인하지 않으므로 두 계통을 원리적으로 못 본다:
  #     · 값이 다른 팩터와 같은 배출 — 실측 5쌍 미선언(C01≡C10 · C04≡C13 · C11≡M25 ·
  #       C01≡C09 · C09≡C10). ★C09 = sign(sue)*sue^2 는 **순증가 단조변환**이라
  #       값 차이(maxdiff 1.85)로는 안 잡히고 **랭크로만** 잡힌다.
  #     · 행은 나오는데 횡단면 상수라 소비면 도달 0인 배출 — C15 50/50월 ·
  #       D60_Leverage·Q16_Debt_to_Assets 각 22/53월(2015-06~2025-12 연속 11년 동안
  #       월 2,753~2,968행을 내면서 소비자에겐 0행).
  #   ★이 검사가 지키는 1차 계통은 **계측 사망**이다: FQ-210 초판이 판별통계로
  #    sd(Z_Score) 를 썼는데 Z 는 표준화 산물이라 331종 전부 정확히 1.0000 —
  #    판별력이 원리적으로 0인데 산출물은 "죽은 배출 0종"이라는 결론처럼 생겼다.
  #    축 Z 가 그 항등을 매 실행 실측하고, 가드가 거기 의존하지 않음을 돌연변이로 실증한다.
  #    축 U 는 "경보 0"과 "측정 불가"(UNMEASURED)를 갈라 못 재는 상태가 합격으로
  #    내려앉는 것을 막는다.
  #   ★전면 stop 금지가 설계다 — 시장레벨 상수 15종(RE*/MA05~07/M31/CR03)은 정당한
  #    무분산 배출이라 차단하면 매 빌드가 죽는다. X 축이 그 면제를 **양방향**으로 잰다
  #    (선언 시 침묵 / 선언 제거 시 15종 전부 발화 = 침묵의 원인이 선언임을 실증).
  #   ★축 C 는 **빌린 판별력**을 못박는다: 축 D 는 sd 를 직접 재지 않고 빌더가
  #    `sd<1e-12 → Z=NA → Coverage=FALSE` 로 번역해 둔 것을 읽는다. 그 상류 계약이
  #    2026-06-10 이전 형태(`Coverage = !is.na(Raw_Value)` 단독)로 되돌아가면 축 D 는
  #    실데이터에서 침묵하는데 **Coverage=FALSE 를 직접 심는 위반 주입은 계속 통과한다**
  #    — 검사가 살아 있는 채로 눈이 머는 자리. 그래서 정적 형태 + .standardize_factors
  #    격리 실행(횡단면 상수 → Coverage FALSE) + end-to-end 로 행동을 잰다.
  #   돌연변이 8종 전부 검출 확인(kill_D 5건 · kill_T 2건 · kill_I_rank 2건 ·
  #   kill_I_decl 2건 · kill_exempt 1건 · kill_unmeasured 1건 · kill_liveness 1건 ·
  #   빌더 Coverage 구정의 복귀 2건[C1/C2] — 이때 주입 테스트는 전부 초록으로 남는다).
  "08_Tests/factor_db/test_emission_identity_axes.R"
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
  # 2026-08-16 추가: 편입 드리프트 검사(suite_enrollment_check) 위반 주입.
  #   ★이 SUITES 배열이 하드코딩 열거라 새 테스트가 자동 편입되지 않는다 — 실측에서
  #   test_*.{R,sh} 121건 중 40건이 배터리에서 **한 번도 실행되지 않고** 있었고, 그중
  #   contract_regression 15건은 essence_score(등급 권위)·hurdle_gate·canonical_screen_bt
  #   같은 알파 판정 계약을 지키는 테스트였다. 이 축이 그 드리프트를 매 배터리에 노출한다.
  "08_Tests/hooks/test_suite_enrollment.sh"
  # 2026-07-26 추가: cache_freshness worse-of lag 위반 주입 (CFA-02 수리 가드).
  #   forward-dated / 파일명-추정 캐시는 생성기가 죽어 파일이 동결돼도 data_lag 가 낮아
  #   FRESH 로 보고됐다 — 동결을 보는 유일 축(mtime)이 폐기되던 구조.
  #   caches_override/today/persist 주입 파라미터의 첫 소비자(노출만 돼 있고 케이스 0건이었음).
  "08_Tests/data/test_cache_freshness_worse_of.R"
  # 2026-08-16 추가: 텔레그램 발송 계약 위반 주입 (TG-01/CFA-05/CFA-06 수리 가드).
  #   실사고: cache_freshness 경보가 07-03~08-15 최소 20건 전부 HTTP 400("can't parse
  #   entities")으로 거부됐는데 **어느 표면도 그것을 드러내지 못했다** — 구 tg_send 가
  #   400 을 cat 으로만 흘리고 R 에러를 안 냈으므로 ①호출부 tryCatch(error=) 미발화
  #   ②CFA-04 의 alert_delivery 미기록 ③last_sent_at 은 배달된 듯 갱신, 셋이 동시에.
  #   즉 **경보 시스템 자신의 실패가 무감시**였다(위 worse-of 축과 같은 계통: 감시기 사망).
  #   ★주입(살아있는 _ 홀수)이 실제로 400 을 유발하는지까지 본다 — 주입이 위반이 아니면
  #     검사는 아무것도 시험하지 않는다(초판이 _ 2개를 써서 200 으로 통과한 실측 함정).
  #   네트워크 단절 시 라이브 축은 SKIP 으로 계상해 드러낸다(거짓 FAIL 방지, 초록 위장 방지).
  "08_Tests/data/test_telegram_send_contract.R"
  # 2026-08-20 추가: 거래일 지평선 단일점 감시 (BMG-01 가드의 위반 주입).
  #   실사고 2026-08-14~20 — .cache/benchmark.parquet 은 naver_benchmark_update.py 가
  #   유일하게 쓰는 파일이고(그 스크립트가 스스로 "저장 단일점"이라 선언),
  #   trading_calendar 는 RAWDATA 순환참조를 끊으려고 **이 파일만** 거래일 권위로 삼는다.
  #   venv 소실로 갱신기가 죽자 벤치마크가 08-14 에 얼었고 → 캘린더가 얼고 → Naver 는
  #   "already >= target", KRX 는 "gap 0 days" 를 **정직하게** 보고했다. 거래일 3일이
  #   비었는데 리프레시는 6일 내내 "실패 0" 으로 마감 — fail-soft 가 지평선을 삼킨 것.
  #   ★검사는 A축(갱신기 rc)과 B축(파일 정체)을 따로 주입한다. 실사고 lag=6 은 B축
  #     문턱(7)으로 **통과**하므로 B 를 방어선으로 읽으면 안 된다는 사실 자체를 케이스로
  #     박제했다(I1/I2) — 문턱을 바꾸면 그 테스트가 먼저 빨개져서 주석 갱신을 강제한다.
  "08_Tests/data/test_benchmark_currency_gate.R"
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
  # 2026-08-20 추가: 정합 감시기의 **방향 판정 축** 위반 주입 (증거축 (c) 동반 신설).
  #   이 판정기가 틀리면 수리기가 **정상 소스를 오염값으로 덮어쓴다** — 경보는 맞는데
  #   처방이 거꾸로인 상태(08-08 주석의 실사고). 그래서 축 자체를 시험한다.
  #   ★박제하는 불변식 = **축 순서**: (c) close_reproducible 은 "benchmark 의 BM_Ret 이
  #     자기 BM_Close 로 재현되는가"를 보는데, benchmark 가 스케일 단절로 오염된 경우
  #     close 에도 같은 단절이 있어 **재현은 된다** → (c) 단독이면 "RAWDATA 오염"으로
  #     뒤집힌다. (a) value_plausibility 가 먼저여야 막힌다(T4b/T4c).
  #   축 도입 계기: 2026-08-20 KRX 백필이 08-18/19 의 BM_Ret 을 자체계산으로 써서
  #     benchmark 와 갈렸는데, (a)(b) 만으로는 08-18(-0.2806)이 문턱 0.30 을 간발로
  #     밑돌아 **undetermined** 로 남아 수리가 막혔다.
  "08_Tests/data/test_parity_direction_axes.R"
  # 2026-08-20 추가: 배터리 총계 추출 앵커 (계측 감시기 자신의 계측을 지킨다).
  #   실사고 당일 — 러너 총계 1563 -> 기록 7. 러너가 죽은 게 아니라 **파서**가 틀렸다:
  #   러너 총계는 `N pass / N fail / N skipped / N total`, 개별 테스트 일부는 skipped 없는
  #   같은 모양을 찍는데, 08-03 수리가 skipped 를 선택적으로 만든 뒤 head -1 이
  #   **먼저 나온 테스트**를 집었다(4891행의 7). fail=0 이라 초록으로 보였다.
  #   ★검사는 정본 함수(st_pick_hooks_final)를 직접 태운다 — 파싱을 복제하면 갈린다.
  #   ★X1 돌연변이 축: head -1 로 되돌리면 7 을 집는 것을 실증(검사 효력 증명).
  "08_Tests/ops/test_suite_totals_anchor.sh"
  # 2026-08-09 추가: RAWDATA `Size` 스케일 정합 + writer 추적성.
  #   원 결함 = naver_data_collector.R:88 이 시가총액 단위를 억원 대신 백만원으로 오해해
  #   `* 1e6` 적용 → **정확히 100배 축소**된 Size 를 2026-07~08 에 43,013행(시장 전체
  #   ~2,690 티커) 기록. 삼성전자가 연속 거래일에 1534.65조 ↔ 14.00조 로 진동하는데
  #   Close 는 3% 내 변동 = 물리적 불가. 시총 팩터·cap-weight·유니버스 필터가 전부 오염.
  #   ★검거 축 = **스케일 불변 정체 검사**(shares = Size/Close). 크기 문턱(Size>1e15)은
  #     종목마다 정상 범위가 달라 못 쓴다 — 이 검사가 그 구분을 픽스처로 못박는다
  #     (주가 4배 급등 시 미발화 vs 100배 축소 시 발화).
  #   ★둘째 축 = source 스탬프. 구판이 source 를 안 찍어 NA 였고 그 NA 가 역설적으로
  #     검거 지문이 됐다 — 이제 지문이 아니라 선언으로 강제한다.
  #   벤치 parity(위 줄)와 **같은 계통**(두 writer·다른 스케일·정합 없는 접합)이라 나란히 둔다.
  "08_Tests/data/test_size_scale_integrity.R"
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
  # 2026-08-13 추가: 큐 항목 **식별자 필드 관용 읽기**. 실측 173건 중 **132건(76%)이 구판 `id`**,
  #   41건이 신판 `arxiv_id` 이고 스키마가 시간순도 아니다(두 생산자가 동시에 쓴다).
  #   `arxiv_id` 만 읽으면 대다수가 **식별자 없이** 에이전트에 도달해 `paper_pdf()` 로 원문을
  #   못 연다 — 원문 없이 memo 만 보고 구현하는 것이 이 레인의 **날조 시작점**이다.
  #   ★본체는 T5(실제 큐 전수 결측 0) + T5b(두 스키마 공존 확인 = 검사가 공허하지 않음)
  #     + T6(해석된 식별자로 원문 실제 도달 89/89). 단위 테스트만으로는 새 스키마 등장을 못 잡는다.
  "08_Tests/ops/test_queue_id_schema_tolerance.R"
  # 2026-08-13 추가: 논문 레인 → hypothesis_index **소비면**. 도훈 지시로 레인의 종착이 확정됐다
  #   — 라우팅은 가능성을 보는 단계이고, 모드가 조회할 수 있는 형태로 인덱스에 올려두는 것까지가
  #   레인의 일이다. 그 전까지 인덱스 원천 6종에 method_registry 가 없어 등재 어댑터 16건이
  #   **모드에게 보이지 않았다**(큐를 드레인해도 소비면이 닫힌 상태).
  #   ★본체는 T4/T5: 콜렉터만으로는 부족하고 **stale 원천 목록**에 들어가야 lookup 이 갱신본을
  #     본다. "만들었다"와 "다음 칸이 읽는다"는 다른 칸이고 결함은 그 사이에서 난다.
  #     T5 는 검출→자동재빌드→조회노출까지 주입으로 관통 확인(원상복구 포함).
  #   T6b = 교란 경고가 수치와 **같은 자리에** 있는지(delta_ir 옆 caveat + avg_exposure).
  "08_Tests/ops/test_hypothesis_index_paper_lane.R"
  # 2026-08-02 추가: worktree 좌초 판정축. ★이 축이 **하루에 세 번 뒤집혔다** —
  #   연차 단독(무해 3건 오강조 + 진짜 좌초 미검출) → main부재 단독(진행 중 작업 오인)
  #   → main부재 AND 무활동(정본). 검사 없이 두면 또 뒤집힌다.
  #   E5 는 성능 회귀 가드(전트리 find = 부팅 5분+ 지연, 변경파일 mtime 만 봐야 함).
  "08_Tests/ops/test_worktree_stranded_axis.sh"
  # 2026-08-16 추가: hygiene 감사 (b5) 워크트리 누적·정리후보 / (b6) MAX_PATH 축.
  #   ★실사고 = 워크트리 43개가 3주간 5.3GB(저장소 파일의 88%)를 점유했는데 감사는 **무경고**.
  #     삭제를 막은 건 MAX_PATH(260) 초과이고, 초과는 오류가 아니라 **조용한 건너뜀**으로 난다
  #     (.NET/R 재귀삭제가 첫 초과 파일에서 트리를 포기하며 성공처럼 보임) ⇒ 계수 감지가 유일한 신호.
  #   위 test_worktree_stranded_axis.sh 와 대상이 다르다: 그쪽 = bootstrap §4h '좌초'(미커밋 방치),
  #     이쪽 = hygiene '누적·껍데기·stale admin·경로길이'.
  #   ★T5b/T6 이 본체 — 한계를 올리면 같은 픽스처가 조용해져야 하고(한계가 실제로 판정을 움직임),
  #     잠복은 초과 0 인 상태에서만 잡혀야 한다. T7 = 오버헤드 상수 낙후 드리프트 대조
  #     (관측치로 산정하면 워크트리가 뜨고 질 때마다 지표가 출렁여 추세를 못 읽는다).
  #   ★run_audit 에 '픽스처 밖 감사' 가드가 있다 — env 주입이 실패하면 테스트가 **실제 저장소**를
  #     재고 조용히 통과한다(실측으로 겪음). 가드 없이는 이 검사가 공허해진다.
  "08_Tests/ops/test_hygiene_worktree_maxpath_axes.R"
  # 2026-08-16 추가: weekly_cleaner_sweep [2c] 워크트리 **무인 자동 prune**.
  #   ★토 09:00 스케줄러가 사람 없이 지운다 — 판정이 한 칸 틀리면 진행 중 작업이 사라진다.
  #     그래서 '지운다'(T1~T3)보다 **'안 지운다'(T4~T6)를 더 많이** 시험한다:
  #     활동 중(무활동<24h) · 미병합 커밋 · main 에 없는 미커밋 내용 = 전부 KEEP.
  #   ★T2 = churn 제외. 이게 없으면 prune 대상이 사실상 0 이 된다(실측: 병합완료 31건 중
  #     28건에서 events.jsonl 이 유일한 차이). 픽스처는 churn 을 **추적 파일**로 만든다 —
  #     untracked 로 두면 git status 가 상위 디렉토리로 접어 보고해 경로 매칭이 성립하지 않는다.
  #   ★T8(DRY 는 실제로 안 지움) / T9(prune 돼도 브랜치 ref 보존) = 설계의 안전 근거 자체를 검증.
  "08_Tests/ops/test_weekly_worktree_prune.R"
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
  # 2026-08-09 추가: 무인 스케줄러 실패 **분류기**의 행동 계약.
  #   ★등재 사유 = 이 검사가 고정하는 결함이 정확히 "진단 경로가 존재하는데 죽어 있다" 계통이다.
  #   · exit 124: `timeout 3000 claude -p` 가 벽시계로 죽이면 claude 는 최종 메시지를 런 끝에
  #     1회만 flush 하므로 **로그 증가분이 0바이트**다. 그런데 분류기는 로그 문구로만 판정해
  #     전건 generic `exit_124` → 안내가 "로그 확인 필요"인데 그 로그가 구조적으로 비어 있었다.
  #     07-27~08-09 6회를 그렇게 흘렸다. 수리 = 종료코드로 판정(한도·인증은 kill *이전* 문구라
  #     여전히 우선 — 그 순서를 C 절이 고정한다).
  #   · 간헐 재발: sched_mark_resolved 의 성공-아카이브와 streak 의 연속-일수 계산이 결합해
  #     14일 6회가 매번 "연속=1" 로 보고돼 격상 문턱(3)에 **구조적으로 도달 불가**였다.
  #     recent_count(후행 창·_resolved 포함·사유 별칭)를 별도 축으로 둔다.
  #   ★두 축이 서로 다른 것을 잰다는 사실 자체를 단언한다(streak 은 _resolved 를 안 세고
  #     recent 는 센다) — 한쪽으로 통일하면 해소 의미가 죽거나 재발이 안 보인다.
  #   위반 주입 2종: rc=124 분기 제거 → `exit_124` 회귀 / 별칭표 제거 → streak 0 계측 단절.
  "08_Tests/ops/test_sched_failure_classify.sh"
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
  # 2026-08-09 추가: de-dup **소비 배선**. 위 test_factor_dup_scan 은 registry 의
  #   *선언 구조*(role/cluster/양방향)를 지키는데, 선언이 행동으로 이어지는지는
  #   아무도 안 봤다. 실측이 그 대가를 보여줬다 — drop_alias_factors()/
  #   resolve_factor_canonical()/report_redundant_clusters() 의 **실코드 소비자가 0**
  #   이라, 선언된 224쌍이 표본 6월 전건에서 같은 풀에 동시 출현하며 그대로 이중
  #   투표했다(초과 표 82~83 = 풀의 ~25%). 이 저장소의 "존재 = 배선 완료" 계통
  #   ([[project-wiring-map-standards-unconsumed-20260808]])의 factor_db 판본이다.
  #   ★이 검사의 본체는 **위반 주입 2종**이다: ① alias 를 안 접는 돌연변이(role 강등)
  #   ② 정본↔alias 를 반대로 매핑하는 돌연변이. 후자가 결과를 안 바꾸면 배선이
  #   registry 를 실제로 읽지 않는다는 뜻이므로, 정상 경로만으로는 구별이 안 된다.
  #   ★기본 동작 무변경(dedup=FALSE)도 여기서 회귀 방화벽으로 잠근다 — 이 배선의
  #   전제가 "인자 없이 부르면 값이 같다"이므로 그게 깨지면 수백 개 기존 caller 가
  #   조용히 다른 값을 받는다. 대상 0(접을 alias 없음)은 PASS 가 아니라 SKIP 으로
  #   내보내 "0건"을 청결로 오독하지 않는다.
  "08_Tests/factor_db/test_factor_dedup_consumption.R"
  # 2026-08-02 추가: distilled 재등재 supersede(부분집합 구 카드 자동 회수) 위반 주입.
  #   원 갭 = 같은 클러스터가 supporting L-code 성장 시 새 dist_id 로 재등재되는데 구 카드가
  #   회수되지 않아 pending_5axis 가 07-17 49 → 08-02 89건(완전 중복 0, **부분집합 쌍 30**).
  #   07-18 forward-migration 은 조상이 refined(status=distilled)인 경우만 다뤄 pending
  #   조상은 CAND superset dedup 으로 고아가 된 뒤 main loop 가 영영 지나가지 않는다.
  #   ★이 검사는 **돌연변이 축(M1~M5)이 본체**다: 08-02 수동 드레인 이후 저장소의 추가 회수
  #   대상이 0건이라, 정상 경로만 돌리면 로직이 죽어 있어도 초록으로 보인다. 각 게이트
  #   (정체성·지식손실·status·저술지식)를 하나씩 끄고 판정이 실제로 뒤집히는지 매 실행 실측.
  "08_Tests/axiom/test_distilled_supersede.py"
  # 2026-08-09 추가: 논문 라우트 디스패치 4종 일괄 편입.
  #   ★등재 사유가 세 suite 는 "지연된 배선"이다 — freshness_gate·screen_axes·
  #     method_adapter_contract 는 2026-08-08 에 만들어졌는데 **이 배열에 들어온 적이 없어**
  #     누가 손으로 부를 때만 돌았다. 이 저장소가 반복해 온 "존재 = 배선 완료" 계통
  #     ([[project-gate-cd-not-on-scheduled-path-20260808]])의 검사기 판본이다.
  #   ① Σ-A/B 신선도 게이트 — 구판 `ov_csv>=carrier` 단독이 **영구 참**이라 7주간 캐시
  #      1벌을 매일 "오늘의 optimizer 판정"으로 재발송했다(book_ir 1.209 고정).
  "08_Tests/ops/test_sigma_ab_freshness_gate.R"
  #   ② STEP 1-b 2축(shrinkage_builtin/statistic_order/screen_priority) 존재 **및 enum** 검사.
  #      존재만 보면 enum 밖 값이 통과해 소비단이 우선순위를 못 매긴다(= 없는 것과 같다).
  "08_Tests/ops/test_screen_axes_check.R"
  #   ③ 논문 어댑터 계약 — 08-08 실사고: normalize_long_only 가 cap 을 정규화 **전**에 걸어
  #      minvar/MVO 3종이 정확히 1/25 = EW 로 붕괴했는데 제약 검사 5종은 전부 통과했다
  #      (EW 도 유효 비중이므로). 검거 축은 "EW 와 구별되는가" 하나뿐이다.
  "08_Tests/ops/test_method_adapter_contract.R"
  #   ④ 2026-08-09 신설: risk 레인 판정. 실사고 = 배터리가 risk method 2건을 **실제로 쟀는데**
  #      (overlay CSV: minvar@ProperScoreGASFilter 0.920 · PreferenceRobustDistortion 0.658)
  #      산출물·텔레그램이 하드코딩 문자열로 "하네스 미배선 · 자동 측정 아직 없음" 을 보고했다.
  #      ★등재≠처분 계통의 **반대 방향**(과소보고) 판본 — 뿌리는 "상태를 선언으로 적음".
  #      돌연변이 축(구 하드코딩 판)이 본체: 실측이 4가지로 갈리는 픽스처에서 구판은
  #      상태 1종만 낸다 — 그게 원 결함의 정의이자 이 검사의 검출력 실증이다.
  "08_Tests/ops/test_risk_lane_verdict.R"
  #   ⑤ 2026-08-09 신설: regime 레인 노출 어댑터 계약. regime 을 자동 배선하면서 논문 유래
  #      **노출 스케줄**이 배터리에 합류할 수 있게 됐는데, 노출 어댑터가 틀리면 두 방향으로
  #      조용히 망가진다: ①홀딩월 *말* 정보로 그 홀딩월 노출을 정하는 동월 look-ahead
  #      (2026-07-06 BearProb 실사고 — placebo/OOS/DSR/subperiod 를 **전부 통과**했고 판별한 건
  #      lag1 스트레스와 strict-PIT A/B 뿐) ②노출 >1(레버) · <0(숏) = Production Constraints 밖.
  #      ★계약은 어댑터가 `used_cutoff` 를 **신고하게** 만들고 무신고는 **로드 거부**한다 —
  #        부재를 '아마 괜찮음'으로 내려앉히는 것이 이 저장소의 반복 결함이다.
  #      ★K축(PIT 검사 없는 구판 래퍼)이 무신고·동월누출·레버리지 3종을 통과시키는지 매 실행 확인.
  "08_Tests/ops/test_exposure_adapter_contract.R"
  #   ⑥ 2026-08-09 신설(FQ-181): 유동성 자(ruler) 계약. 실사고 = 계약 함수
  #      build_monthly_forward_returns() 가 주석에 "20d ADV at t-1" 이라 써 놓고
  #      `adv = Vol0*Close0`(월말 **1일치**)를 계산했다 — 주석 자신이 자백하고 있었다.
  #      헌법(Production Constraints · pit.md C10)은 20일 평균 거래대금 >= 2e8 이다.
  #      두 자 상관 0.929 · 판정 불일치 2.61% · 실선별 top-25 중 3.04%가 20일-자 미달.
  #      ★검거 축은 두 개다: ①구판 1일치 산식을 **주입**해 검사가 두 자를 구별하는가(B1)
  #        ②월말-slim 입력(호출부 149건 중 103건이 그렇게 넘긴다)에 20창을 걸면 20 *개월*
  #        평균이 나오는데 — 오류가 아니라 **그럴듯한 쓰레기** — 함수가 입력 관측단위를
  #        실측해 분기하고 라벨로 자백하는가(C2/B4). 라벨이 없으면 두 자가 병존한 채
  #        서로 다른 자로 잰 수치가 나란히 인용된다.
  #      ★NA 금지 축(A4/C3): canonical_screen_bt 는 `is.na(adv) | adv >= liq_min` 이라
  #        NA 가 **통과**한다. 결손을 NA 로 비우는 수리는 조용한 제약 완화다.
  "08_Tests/ramp/test_liquidity_ruler.R"
  # 2026-08-10 신설(FQ-218): 컨센서스 롤링 창의 **단위**. 실사고 = .cons_history() 가
  #   관측 **행**을 최신순으로 주는데 원천 sue/esbr 이 **일간 캐리포워드**여서
  #   `mean(sue[1:4])` 가 4분기가 아니라 3~5일을 평균했다. 창 안 고유값이 1개뿐이라
  #   이동평균이 **항등변환**이 됐고, 그 결과 C10 ≡ C01 · C13 ≡ C04 **비트동일**,
  #   C15 는 전 종목 0 → 횡단면 sd 0 → 소비면 도달 0행(50/50월 죽은 배출, FQ-210 축3a).
  #   ★행수도 정상, NA 도 없고, 오류도 없다 — 결함이 **정상값 모양의 항등변환**이라
  #     기존 emission_guard 의 n_rows>0 축으로는 원리적으로 안 잡힌다. 그래서 이 검사는
  #     **mean==latest 비율 1.0 자체**를 고정 축으로 삼는다(값이 아니라 창의 사망 서명).
  #   ★본체는 위반 주입이다: 수리를 되돌리는 돌연변이(최신 N개 **행**)를 같은 실행에서
  #     돌려 12/12 검거(mut frac_eq 1.0000)를 매번 실증한다. 정상 경로만 보면 수리가
  #     죽어도 초록으로 보인다. 부수 돌연변이 = 전역 unique() 구현(0.5,0.6,0.5 를 2런으로
  #     접어 한 분기 더 소급 — 값이 그럴듯해 눈으로 안 보인다).
  #   ★PIT 축을 함께 잠근다: 이 수리의 정당성은 "값 변경일 = 월초 가용일(4/6/9/12월
  #     첫 영업일, 한국 분기 법정기한 **이후**)"이라는 실측에 걸려 있다. 변경일이 분기말로
  #     바뀌면 분기 리샘플이 곧 미래참조가 되므로 월초/월말/주말 비율을 매 실행 재측정한다.
  #   ★양성 대조는 git 판본이 아니라 **원천 독립 재계산**과 맞춘다(영구 대조) — 수리가
  #     C10/C13/C15 밖으로 새면 C01/C04/C09 가 즉시 빨개진다. 원천 부재는 PASS 아닌 SKIP.
  "08_Tests/factor_db/test_cons_window_quarterly.R"

  # (2026-08-10) streak 팩터 단위 검사 — FQ-219. FQ-218 의 **같은 뿌리, 다른 증상**.
  #   C11_Earnings_Streak / M25_Earnings_Mom_Streak 는 "연속 양수 SUE 의 개수"인데
  #   일간 캐리포워드 원천의 **행**을 세어 영업일을 카운트하고 있었다(실측 행/분기 비 21~70).
  #   ★판별식을 FQ-218 에서 베낄 수 없다 — `mean==latest` 는 **평균** 팩터의 사망 서명이다.
  #     평균은 창이 붕괴하면 항등변환이 되어 정보가 사라지지만, 카운트는 정보가 남고
  #     **단위만 바뀐다**. 그래서 축이 다르다: ①단위(streak == 분기 수인가)
  #     ②연속성(관측 안 된 분기를 가로지르지 않는가 — 구 구현은 양수 streak 종목의
  #     10.7~13.7% 에서 교량) ③릴리스 의존(릴리스 없는 달에 값이 커지지 않는가).
  #   ★세 축 모두 "값이 그럴듯한" 상태에서 참이다 — 행수 정상·NA 0·오류 0인 채
  #     단위만 21~70배 틀려 있었으므로 기존 n_rows/NA 축으로는 원리적으로 안 잡힌다.
  #   ★복제 강제: 빌더가 모듈을 각각 별도 env 에 source 해(factor_db_builder.R:543-544)
  #     헬퍼를 공유할 수 없다. 2026-08-08 에 "C11 과 M25 는 식·원천·정렬이 동일"이라고
  #     **기록만** 하고 강제가 없어 두 곳이 같이 틀린 채 남았다 — 그래서 이 검사는
  #     두 파일 함수 **본문 일치**(deparse)와 상수 일치를 매 실행 강제한다.
  #   ★위반 주입 4종을 같은 실행에서 돌린다: 행-카운트 복귀 / 결번 교량 / stale 미차단 /
  #     epoch 경계 밀기. 경계 밀기는 내가 처음 넣었다가 **기준값 대조로 반증된 설계**로,
  #     밀면 분기 값이 다음 분기 관측에서 온다(기준값 일치 0.9998 → 0.1652).
  "08_Tests/factor_db/test_streak_quarter_unit.R"

  # (2026-08-10) 유동성 자 **복원 경로** — FQ-232. FQ-181 의 후속 절반.
  #   FQ-181 은 자를 이원화하고 라벨을 **발행**했다. 그런데 그 라벨을 **읽는 소비자가
  #   0** 이었다 — canonical_screen_bt 는 attr('liq_ruler') 를 보지 않았고, 산출물 어디에도
  #   자가 기록되지 않았다. 발행과 소비는 별개의 배선이며, 읽히지 않는 라벨은 없는 라벨이다.
  #   ★그 결과 호출부 149건 중 slim∧liq배선 51건이 헌법 자(20일 평균)가 아니라 월말
  #     **1일치** Vol*Close 로 걸린 채, 그 PORT_t 가 자 표기 없이 유통됐다(FQ-161 +1.544 포함).
  #   ★본체는 축 C3(라벨 위조 주입)다. 이 결함의 원형이 "주석은 20d, 코드는 1일치" 였으므로
  #     라벨만 보고 통과시키면 같은 계통을 재생산한다 — 라벨이 주장하는 자로 **실제 계산됐는지**를
  #     값으로 검증하고, 라벨만 바꾼 위조판을 같은 실행에서 주입해 검출을 실증한다.
  #   ★기본 동작 무변경도 계약이다(B1/B3): liq_daily 인자 없이 부르면 DEGRADED 그대로 —
  #     조용히 자가 바뀌면 과거 판정과의 비교가 깨진다. 값 parity 는 실데이터에서
  #     max|Δadv|=0 으로 확인됐고(stage_artifacts/infra/fq232_.../p2_log.txt), 여기선
  #     "1일치 자구 일치"로 상시 고정한다.
  #   ★A3 축(당일 미포함)의 교란은 **마지막 앵커 하루에만** 준다 — 모든 월말에 주면
  #     20 거래일 창이 직전 월말을 포함해(월 ≈ 21 거래일) 창 안의 정당한 관측을 함께
  #     바꾸게 되고, 그러면 정상 코드가 FAIL 한다(초판이 실제로 그렇게 틀렸다).
  #   ★E1 양성 대조는 문턱을 90분위로 올린다. 1e15 로 올리면 선정이 0행이 되어 무관축(E3)이
  #     잴 대상을 잃는다 — 그건 "제약 준수"가 아니라 대상 0 이다(SKIP 이지 PASS 아님).
  "08_Tests/contracts/test_liquidity_ruler_restore.R"
  # 2026-08-22 추가: 분포-표적 측정 계약(distribution_target_screen.R) + 라우트 발급
  #   (hurdle_gate DISTRIBUTION_TARGET) + 소비 배관(distribution_target_queue.R) 3층.
  #   ★이 라우트가 존재하는 이유 자체가 "신호는 분포에 있는데 소비면이 평균을 읽는다"이고,
  #    그래서 발급 조건이 **screen_pass 와 독립**이다(H2). 평균 지표에 종속시키는 회귀가
  #    들어오면 라우트가 자기 동기 사례에서 발급 0 이 되는데 그건 조용하다 — H2 가 그 자리.
  #   ★E 절(자본 필드 주입 차단)은 헌법 §3 "분포 통계로 HARD 3종 대체 금지"의 기계 집행이다.
  #   ★B4/B5 = 선형 통제의 한계: score=-log(vol) 가 **선형 통제를 통과**한다(오통과).
  #    "vol 로 통제했다"는 진술이 강도를 보증하지 않음을 양방향으로 못박는다.
  "08_Tests/contracts/test_distribution_target_screen.R"

  # (2026-08-13) ctx 특성 확장 계약 — 어댑터 ctx 에 characteristics 접근자를 붙여
  #   특성 기반 방법(CD-DFM 계열)을 열었다. ★확장은 선언만으로 살지 않는다 —
  #   "존재 = 배선 완료" 착각(screen_route 소비자 0 계통)을 여기서 막는다.
  #   본체는 T3(특성 sig_date 가 홀딩월 시작 전인가 — 당월이면 동월 look-ahead)와
  #   T4(패널 NULL 일 때 죽는 어댑터가 검출되는가).
  #   ★T4 는 축을 한 번 다시 설계했다: NULL 상황에서 등재검증으로 재면 정상 어댑터도
  #     중립(EW)을 내서 비-퇴화 게이트에 걸린다 — 정상과 고장이 **둘 다 EW** 로 수렴해
  #     구분이 안 됐다. 그래서 생존(예외 없이 유효 길이)만 묻는 축으로 바꿨다.
  "08_Tests/methods/test_ctx_characteristics.R"

  # (2026-08-13) 어댑터 골격 생성기 계약. 등재 병목이 **노동량**임이 실측돼(표본 12편,
  #   도달 가능 10/12) 기계적 부분을 new_adapter() 가 깐다.
  #   ★본체는 T4: **빈 골격은 등재를 통과하면 안 된다** — 통과 가능한 골격을 내는 생성기는
  #     노동 절감이 아니라 **날조 보조 도구**다. 거부되어야 "사람이 원문을 읽어야 통과"가 선다.
  "08_Tests/methods/test_new_adapter_scaffold.R"

  # (2026-08-13) 등재 게이트 **구별성 축**. 비-퇴화는 기준선(EW·표본공분산·상수1)과만 비교하므로
  #   **기등재 arm 과 사실상 동일한 어댑터**를 통과시킨다 → 배터리가 같은 것을 두 이름으로 재고
  #   결과표엔 독립 arm 두 개로 보인다. 계기 TailConformalBand ↔ ConformalKelly (max|Δw| 1.4e-03).
  #   ★두 방향을 다 잡아야 한다. 초판은 weight 에만 붙어(사각 2/3) 다음 exposure 등재에서
  #     조용히 안 돌았고, 3 kind 로 넓히자 이번엔 **비발화끼리 거리 0** 을 중복으로 오경보했다
  #     (VolRateMatched ↔ HurstRateMatched, 둘 다 0/60 발화). 못 잡는 것과 헛잡는 것은
  #     같은 병의 양면 — 결손을 정상값 모양으로 내려앉히는 계통이다.
  #   T2 = 완전 복제본 주입(3 kind 전부 거리 0·원본 지목) · T6 = 비발화는 "비교 불가"라고 **말한다**
  #     (초판 T6 은 빈 문자열을 받아 공허 통과했다 — 축의 조기반환으로 자기-침묵 검사가 도달 불가였음).
  "08_Tests/methods/test_nearest_arm_axis.R"

  # ── 2026-08-13 좌초 수리 회수: 아래 8건은 병렬 세션 worktree 에 커밋된 채 main 에
  #    도달하지 못했던 검사다(agitated-jones 2 · jovial-mcnulty 6). 감사기가 '유실' 로
  #    세지 못한 구간 — 미커밋만 triage 하고 **커밋된 미병합분은 안 봤다**. 원 주석 보존.
  # 2026-08-08 추가: 위 관문의 **배선** 위반 주입 (FQ-119 WIRE).
  #   ★위 suite 는 관문 *함수*가 옳게 판정하는지만 재고, 그 관문이 **호출되는지**는 안 잰다.
  #     실제로 08-08 시점 관문은 17/17 통과였는데 **호출부가 0** 이었다 — 계약과 검사가 다
  #     있으면서 소비자가 없는 상태가 "관문 신설 완료"로 적힐 뻔했다(WIRE-1 과 동형 계통).
  #   본 검사의 축: ①배선 존재(production 원본 파싱 — 사본 검사는 원본 사망을 못 잡는다)
  #     ②★배선 검출력(호출부를 지운 돌연변이에서 ①이 실제로 뒤집히는가 — 없으면 ①은 장식)
  #     ③동작 실효(warn 발화 / block 중단 / 자격 라벨 무경고 = 항상경고·항상차단 구별)
  #     ④현장(사이트별 basis 가 그 사이트가 *실제로 쓰는* 라벨을 재는가 — 두 구성 일치율
  #        0.804 실측이라 basis 를 한 값으로 굳히면 대용품 검사가 된다)
  #     ⑤배포 경로 경고 고정(라이브 리밸을 관문이 멈추지 않는다 — mode="warn" 인자 고정 +
  #        tryCatch. 차단 승격은 도훈 confirm 사안).
  "08_Tests/hooks/test_label_gate_wiring.R"
  # 2026-08-08 추가: 관문의 **스키마·훅 표면** 위반 주입 (FQ-119 WIRE ②).
  #   ★이 저장소엔 JSON-Schema 실행 엔진이 배선돼 있지 않다(R jsonvalidate 미설치 ·
  #     wt_validate_package 호출부 0). 그래서 schema.json 만 고치면 그것도 dead 계약이다.
  #     실제로 발화하는 표면은 worktask_artifact_validator.sh(PostToolUse warn) 이고,
  #     본 검사가 **두 표면을 함께** 건다: 스키마 조건부 required + 훅 실발화 로그.
  #   비파괴 축: 실물 alpha_package 213건에 대해 개정 전후 유효성이 바뀌지 않아야 한다
  #     (opt-in 설계 — 진행 중 라운드 emit 을 깨뜨리지 않기 위함).
  "08_Tests/hooks/test_label_gate_schema_hook.py"
  # 2026-08-09 추가: artifact lineage 의 **cwd 독립성** 계약(금칙 ③④).
  #   lineage_utils.R 의 읽기/쓰기가 전부 상대경로라 cwd=프로젝트 루트일 때만 동작했다.
  #   그런데 이 저장소의 문서화된 R 실행 패턴은 "전략/스테이지 디렉토리로 cd 후 Rscript" —
  #   자연스러운 호출 규약이 계보 기록을 정확히 깨뜨렸다(WT-D20260809_002 실측).
  #   ★자매 suite(test_lineage_git_state.R)는 setwd(PROJ) 로 시작하므로 이 표면을
  #    구조적으로 못 본다. 구판 대비 12/16 축 반전으로 검출력 실증.
  "08_Tests/hooks/test_lineage_cwd_root.R"
  # 2026-08-09 추가: 검정력 바의 NW 인자 계약.
  #   NW_INFLATION_DEFAULT=1.25 는 **가정치**인데 월간 횡단면 스프레드 10계열(266개월) 실측이
  #   중앙값 0.986(1.25 초과 0건, AR(1) 거의 0)이었다 → 바가 중앙값 27% 과대 = 과잉 기각.
  #   ★상수를 갈아끼우는 대신 "계열이 있으면 재고, 무엇을 썼는지 신고한다" 로 수리했고,
  #    이 suite 는 그 실측 경로가 살아 있는지를 잰다(진짜 자기상관 검출 × 백색잡음 오검출 통제).
  "08_Tests/hooks/test_power_bar_nw_factor.R"
  # 2026-08-10 추가: 군집-상관 설계의 착수 전 검정력 계약.
  #   원 결함 = 하루에 같은 설계 실패 4회(FQ-170 P9c/P17a/P19b/P20a). 매번 팩터 수(n=40~52)로
  #   검정력을 생각했는데 묶는 건 **계열 수**(15~19)였다. 같은 rho 가 관측 기준으론 통과하고
  #   계열 기준으론 미달한다 — 판정이 군집 선택에 달렸고 그 선택은 착수 전에 고정돼야 한다.
  #   ★수리 과정에서 **선행 라운드의 상수가 틀린 것**도 잡혔다: P8d 의 근사식이 낸
  #    "rho 0.45 → 필요 23" 이 메모리·close_round 로 전파됐는데 t-기반 정확해는 **20** 이다
  #    (n=19 → 0.4555 · n=20 → 0.4437). B1b 가 경계 양쪽을 확인해 근사식 재도입을 차단한다.
  #   ★E1 돌연변이 = 군집 구분을 없애면 P20a 가 GO 로 뒤집힘(C2 의 PASS 가 어디서 오는지 실증).
  "08_Tests/hooks/test_cluster_power.R"
  # 2026-08-10 추가: close_round 의 `baseline` 선언 필드(FQ-127 F1).
  #   원 결함 = 비교·개선 주장은 base 없이 해석 불가한데(FQ-170 순열 통제 4/4: 같은 규칙이
  #   base 에 따라 +0.845/+0.264/**-0.293**), 판정문이 산문이라 **사후에 기계로 못 묻는다**
  #   (FQ-127 C1 의 정규식 census 가 표본 5/5 오분류로 무효 — 인컴번트·book IR·plain·EW→ERC 는
  #    못 덮고 `+5.22` 는 개선 패턴에 안 걸림 = 양방향 오류). ⇒ **탐지 말고 발행 때 선언받는다.**
  #   감사가 "본문에 base 가 적혔나"(불가) → "필드가 선언됐나"(가능) 로 바뀐다.
  #   ★비파괴: 인자 선택·미지정 시 stop 없음(기존 호출부 무영향), `baseline_declared=FALSE` 로 기록.
  #   ★F 축은 이 검사를 쓰다가 나온 별건: 요약 마지막 줄이 `write_marker` 와 무관하게 항상
  #    "마커 발행 → Stop 게이트 자동 통과" 를 주장해 **드라이런에서 일어나지 않은 일을 보고**했다.
  "08_Tests/hooks/test_close_round_baseline.R"
  # 2026-08-10 추가: 억제 플래그의 **행동 검사** 픽스처(FQ-127 F7).
  #   원 결함 = 자유 형식 패턴 감사가 하루 **3/3 실패**(Q2 '즉시가능 49건' 과다 · C1 '24.9%' 표본
  #   5/5 오분류 · F5 '8건' 중 3/4가 '갱신 **생략**' 을 부정어째 잡은 오탐). 어휘가 한/영 혼재이고
  #   부정·문맥이 있어 **넓히면 오탐·좁히면 누락**, 확장으로 못 고친다.
  #   ⇒ 대안 = **문구를 읽지 않고 결과를 본다**. `assert_no_side_effects(expr, paths)` 가
  #    감시 경로의 (존재·크기·mtime·줄수) 스냅샷을 전후 비교한다. 다른 dry_run 계약에 이식용.
  #   ★위반 주입 = 플래그를 무시하고 쓰는 함수(신규 생성 B · 기존 append C) 둘 다 검거.
  #   ★D2 = **공허 방지 가드**. 초판이 검사 파일 위치로 경로를 잡아 없는 경로를 보고 통과했고
  #    (`.cache` 는 main 루트의 심볼릭 링크라 worktree 엔 없음) D2 가 그 공허한 PASS 를 잡았다.
  "08_Tests/hooks/test_dryrun_no_side_effects.R"
  # 2026-08-10 추가: 선별 오버레이의 착수 전 판정(q1 비중).
  #   근거 = 세 경로가 독립적으로 같은 원리에 도달했고 실제 PORT_t 4점이 확인했다:
  #   **선별 오버레이는 base 의 선호를 되돌린다** — base 가 이미 선호하는 것을 자르면 손해.
  #   FAM_L q1 0.148→Δ**+0.736** · FAM_CR 0.150→+0.210 · FAM_S 0.195→+0.116 vs **PG2 0.308→−0.846**
  #   (2-arm canonical_screen_bt · 커버리지 전건 1.0). q1 순서와 Δ 부호가 정확히 갈린다.
  #   ★D 축 = **표↔계약 배선** 확인(오늘 '계약은 있는데 호출부 0' 계통을 여러 번 봤다).
  #   ★미측정은 **NA**(0 위장 금지) · 표는 '자본 후보 아님' 경고를 함께 담는다(수치만 옮겨가는 것 방지).
  #   ⚠이 레버는 약한 재료를 덜 나쁘게 할 뿐 — 오버레이 후 최고 PORT_t +0.538.
  "08_Tests/hooks/test_overlay_precheck.R"
  # 2026-08-16 추가: P0 루프 닫기 수리 4건 (L1 자동 스폰 설계, 도훈 승인) 위반 주입.
  #   ①hypothesis_index 원천 (g) overlay_ab_results 파서/스테일 감시 ②drain_verdict dv_v1
  #   판정 코드화 + **양성 대조**(07-10 실측 16건 재판정 = 세션 수기 INFERIOR 전건 일치)
  #   ③close_round frontier 선언↔실기록 대조(부재 FQ-id 경고 + 구조 필드) ④처분 기록 배관.
  #   ★T3b 가 도입 당일 실결함 검거 — id 추출 정규식 상한 {1,4} 이 긴 id 를 절단해
  #    "쓴 id ≠ 대조한 id" 를 만들었다(수리: FQ-[0-9]+). 주입이 빨개지는 것까지가 한 축.
  "08_Tests/hooks/test_p0_loop_closure.R"
  # 2026-08-16 추가: Layer 1~3 (L1 자동 스폰 — 도훈 승인) 위반 주입.
  #   L1 ip_per_regime(ip_v1 — 표본 미달 시 판정 없음) · L2 build_auto_spawn_queue
  #   (kind 4종 + kill switch + capacity + 상태 이월 + D2 FR_RCMA 재정의 소비) ·
  #   claim 프로토콜(선점/중복 거부/done 보존) · 내구 로그·상태라인.
  "08_Tests/hooks/test_auto_spawn_layers.R"
  # 2026-08-17 추가: 주입 훅 프론티어 줄의 CLAUDE.md 정본 파생(폐쇄루프 감사 Rank2).
  #   구 하드코딩(M7 07-10)이 v8.4 재편(08-13) 후 38일 낙후 → 매 spawn 마다 도훈이 08-09 에
  #   닫은 lane 을 ①순위 레버로 광고했다(주입문 v8.4 키워드 5종 실측 0건).
  #   양방향: [A/D] 정본 파생 + v8.4 키워드 실적재 · [B] 마커 제거 시 폴백 실효(위반 주입) ·
  #   [C] CLAUDE.md 부재 내성 · [E] 정본 settled lane 변경의 주입문 전파.
  #   ★temp root 는 native Windows 경로 필수 — MSYS 형(/tmp)을 쓰면 훅의 native python glob 이
  #    0건 매치 → CACHE_BODY regen 실패 → '{}' 조기종료라 **수리 실패로 오독**된다(초판 5 FAIL 의 정체).
  "08_Tests/hooks/test_frontier_axes_derive.sh"
  # 2026-08-17 추가: Step 0 조준기(gap_vector_steering) priority 의 CLAUDE.md 정본 파생.
  #   같은 낙후가 조준면에도 있었다 — v8.4(08-13)가 비-return 을 주력 해제했는데 표는
  #   priority 1L '주력' 을 38일 유지해 sleeve_needs → Gap-Directed Step 0 가 폐쇄 lane 을
  #   1순위로 겨눴다. [A]정본 순서 반영 [B]미열거 open 자동 강등 [C]마커 부재 시 정적 유지+경고
  #   [D]정본 순서 변경 전파 [E]closed 불변.
  #   ★[D]는 **조작 선행검증**을 먼저 한다 — 초판이 bold(**) 마커를 뺀 패턴으로 치환에 실패해
  #    "치환 실패"를 "전파 실패(박제)"로 오귀속했다. 음성 대조는 자기 조작의 유효성을 먼저 증명해야 한다.
  "08_Tests/hooks/test_gvs_constitution_order.R"
  # 2026-08-20 추가: 주입 사본(failure_revival_flags) 동기화 2층.
  #   실사고 — DIST 카드 frontier 를 고쳤는데 주입면에는 구 문장이 그대로 나갔다.
  #   .cache/failure_revival_flags.json 이 frontier *사본*을 들고 있고 부활 발화 블록이 그걸 주입하는데,
  #   그 갱신자(morning_briefing.sh:99)를 morning_run.sh:195 가 **주말엔 skip** 해 3~4일 지연이 났다.
  #   [예방] refine_distilled 동기 갱신(0.82초) + [관측] WARN_11 mtime 역전 — 한 층만으론 부족하다
  #   (예방만이면 approve_proposed·수동편집 경로가 남고, 관측만이면 매번 사람이 고쳐야 한다).
  #   ★[D] 축은 주석이 아니라 **본문 호출**을 확인한다(주석만 남고 배선이 빠지는 회귀 방지).
  "08_Tests/hooks/test_revival_flags_sync.R"
  # ── 2026-08-20 추가: 대리 지표 검사기 4종 → 내용 기반 교체 (폐쇄루프 감사 Rank3/7/9 + knowledge_index) ──
  #   뿌리 = "정정 역전파 부재 — 그 정체를 재는 검사기가 전부 대리 지표를 본다".
  #   대리 지표는 append 만으로 초록이 되므로 갱신 없이 헤더만 쌓는 행위가 계기를 끄는 스위치가 된다.
  #   실사고: 계층지도 표 9행이 13일·48커밋 바이트 동일인데 mtime 은 갱신돼 두 감시기 모두 초록.
  #   ★4건 전부 독립 재현자가 power=True regress=True 확인(검출력 사망 아님).
  #   ① 지도 신선도: mtime → 표 본문 sha. [위반] 30일 표-정체 + touch 에서 lag 719.5h 발화,
  #      같은 상태에서 구 mtime 판정은 초록 = 이 교체의 존재 이유가 실측으로 증명됨.
  "08_Tests/hooks/test_map_freshness_content.R"
  #   ② promote crash: stdout grep → exit status. exit!=0 인데 PASS/FAIL 을 찍는 후보를 검거
  #      (구 로직은 crash 0 으로 집계 — MAX_PATH 로 죽은 1건이 그렇게 새어나갔다).
  "08_Tests/hooks/test_promote_crash_exit.R"
  #   ③ [초안] 마커: 정제 여부(statement_refined 존재) → 승인 여부(status).
  #      proposed 는 정제문을 갖지만 미승인이라 주입 대상이 아니다(INV-6). 무차별 마킹은 오탐 15건으로 잡힘.
  "08_Tests/hooks/test_draft_marker_approval.R"
  #   ④ knowledge_index 신선도: 검사가 아예 0줄이었음 → 카운트 대조 신설(mtime 아닌 내용).
  #      트리거 비대칭(빌더는 bootstrap 말미에서만 호출)이라 부팅 없는 세션의 적립이 조용히 뒤처졌다.
  "08_Tests/hooks/test_knowledge_index_stale.R"
  # ── 2026-08-20 추가: 정본 소비경로 AST 추출기 (같은 질문에 토큰 grep 이 6번 실패한 뒤 도구 교체) ──
  #   실패 6종은 전부 **표기 형태 가정**: CRLF·bold 마커·모듈명·로드 리터럴 위치·os.path.join·별칭.
  #   파서는 d[["a"]][["b"]] 와 d$a$b 를 같은 경로로 정규화한다 — grep 이 원리적으로 못 하는 것.
  #   축: 양성(정본 실재) · 음성(가짜 뿌리 0) · 위반주입 · 별칭 ON/OFF · 재할당 무효화 · 과잉교정 아님.
  #   ★[F] 재할당 축은 도입 당일 R 판의 잠복 과잉교정을 검거했다(python 만 고치고 R 은 안 고쳤던 것).
  "08_Tests/hooks/test_sot_access_paths.R"
  "08_Tests/hooks/test_sot_access_paths_py.py"
  # ── 2026-08-20 추가: mvo 주석↔서명 기본값 정합 (문서 드리프트 금지) ──
  #   주석은 산문이라 파생할 수 없으므로 **드리프트를 금지**한다. 값은 정규식이 아니라
  #   R 파서 formals() 에서 읽어 서명 형식 변경에 안 깨진다. 4필드가 실제로 갈려 있었다
  #   (bounds 0.10 vs 0.15 · max_names 20 vs 25 · min_names 15 vs 20 · hhi_cap 0.10 vs 0.15).
  "08_Tests/hooks/test_mvo_doc_default_parity.R"
  # ── 2026-08-20 추가: contract_regression 15건 (측정 권위 계약의 회귀 보호) ──
  #   이 15건은 essence_score(Grade 산정 권위) · hurdle_gate(게이트 2계층) ·
  #   canonical_screen_bt(실측 진입점) · register_module(모듈 계약 floor) ·
  #   book_marginal_ci / required_effect_size / subsample_null(자본 게이트 통계) 을
  #   지키는데, SUITES 가 하드코딩 열거라 **한 번도 배터리에서 돌지 않고** 있었다.
  #   등재를 막고 있던 건 목록이 아니라 출력 계약이었다 — 5건은 helpers.R 의
  #   TESTSUMMARY 만, 10건은 자체 형식만 내서 배터리가 읽지 못했다(→ 2026-08-20
  #   t_summary 에 배터리 JSON 동시 발행 + 10건에 요약 줄 추가로 해소).
  "08_Tests/contract_regression/test_essence_score.R"
  "08_Tests/contract_regression/test_hurdle_gate.R"
  "08_Tests/contract_regression/test_canonical_screen_bt.R"
  "08_Tests/contract_regression/test_register_module.R"
  "08_Tests/contract_regression/test_required_effect_size.R"
  "08_Tests/contract_regression/test_proxy_axis.R"
  "08_Tests/contract_regression/test_basis_channels.R"
  "08_Tests/contract_regression/test_subsample_null.R"
  "08_Tests/contract_regression/test_book_marginal_ci.R"
  "08_Tests/contract_regression/test_governor_dir_resolution.R"
  "08_Tests/contract_regression/test_report_guard.R"
  "08_Tests/contract_regression/test_harness_compliance.R"
  "08_Tests/contract_regression/test_moment_fragility.R"
  "08_Tests/contract_regression/test_claim_state.R"
  "08_Tests/contract_regression/test_bm_park.R"
  # ── 2026-08-20 추가: 미편입 15건 (요약 계약 정합 후 등재) ──────────────────
  #   3건은 이미 배터리 JSON 을 내고 있었는데 SUITES 에 없어서 안 돌았고(순수 열거 누락),
  #   12건은 요약 줄이 없어 등재해도 UNREPORTED 가 될 상태였다 → 요약 줄 추가 후 등재.
  #   ★test_c15_load_path_scan 은 카운터가 main() 지역변수라 최상위 발행이 죽었다 —
  #     스코프 안에서 발행하도록 고쳤다(같은 형태를 만들면 'object not found' 로 죽는다).
  "08_Tests/ops/test_frontier_queue_io.R"
  "08_Tests/ops/test_paper_dispatch_backfill.sh"
  "08_Tests/worktask/test_wt_inflight_lock.R"
  "08_Tests/regime/test_briefing_partial.R"
  "08_Tests/regime/test_fred_robust.R"
  "08_Tests/regime/test_ktri_v3_builder.R"
  "08_Tests/regime/test_msm_daily_refit.R"
  "08_Tests/regime/test_regime_signal_merge.R"
  "08_Tests/portfolio/test_mvo_turnover_penalty.R"
  "08_Tests/portfolio/test_optimizer_breadth.R"
  "08_Tests/portfolio/test_pg2_coherence_check.R"
  "08_Tests/data/test_dart_account_id_fallback.R"
  "08_Tests/ops/test_frontier_citation_scan.R"
  "08_Tests/ops/test_paper_intake_resolvers.R"
  "08_Tests/hooks/test_c15_load_path_scan.R"
  # ── 2026-08-20 추가: integration 3 + hooks 셸 3 (요약 계약 정합 후 등재) ────
  #   test_weight_bound_basis 는 08-16 분류에서 "PASS 1 / FAIL 2" 였는데 venv 복구 후
  #   3/0 으로 회복 — 그 실패는 결함이 아니라 **환경 결손의 하류**였다(오진 방지 기록).
  "08_Tests/integration/test_execution_path_unified.R"
  "08_Tests/integration/test_v8_readiness_gate.R"
  "08_Tests/integration/test_wt_lifecycle_e2e.R"
  "08_Tests/hooks/test_hypothesis_precheck_gate.sh"
  "08_Tests/hooks/test_inject_usage_ranking.sh"
  "08_Tests/hooks/test_weight_bound_basis.sh"
  # ── 2026-08-20 추가: 잔여 3건 — 편입 드리프트 0 달성 ──────────────────────
  #   test_gate3_4 는 testthat 계열이라 카운터가 없다 → 파일 단위 입도(완주=통과,
  #   실패는 예외로 죽어 러너 UNREPORTED 가 +1 FAIL 로 잡는다). 단언별 수치가
  #   필요하면 카운터 도입이 선행 과제.
  "08_Tests/hooks/test_benchmark_values_plausible.R"
  "08_Tests/hooks/test_blunt_anchor_failclosed.R"
  "08_Tests/ramp/test_gate3_4.R"
  # 2026-08-16 추가: 연속성 마커의 **정체 검사** 차단 실효 (교차-세션 누수).
  #   원 결함 = `marker_fresh` 가 `.cache/last_round_closure.json` 의 **mtime 만** 봤다.
  #   그 파일은 루트 단일 파일이고(main 의 `.cache` 는 `/c/qm_cache` 심볼릭 링크 = 머신 공유)
  #   훅이 `DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 로 서는데 CLAUDE_PROJECT_DIR 이
  #   Bash/훅 환경에 없어 **모든 워크트리 세션이 main 의 같은 마커**를 읽고 쓴다 ⇒ 병렬
  #   세션이 내 프롬프트 이후 아무 라운드나 닫으면 **남이 생산한 계속으로 내 턴이 통과**.
  #   실측(실훅 경로·user_ts 존재): 같은 종결 텍스트가 user_ts=07:25Z→PASS
  #   (marker_round_id=INFRA-WT-PURGE-20260816-P2, 이 세션 것 아님) / 07:35Z→BLOCK.
  #   갈린 것은 서술이 아니라 **남의 mtime** — 방화벽의 핵심 속성("계속을 *생산*해야 한다")이
  #   병렬 세션 수만큼 무력화된다.
  #   ★기존 continuity 배터리는 이 결함을 **구조적으로 못 본다**: 판정 root 를 빈 임시
  #     디렉토리로 격리하고 포장도로는 `marker_override=True` 로 주입해 marker_fresh 의
  #     본문이 한 번도 실행되지 않았다(무커버 축). 그래서 별도 suite 다.
  #   ★수리가 정체 검사 **단독**이면 역방향 회귀가 난다 — 병렬 세션이 공유 파일을 덮어써
  #     내가 정당히 닫은 턴이 차단된다. 그래서 세션별 마커를 함께 발행하고 F 축이 그걸 잰다.
  #   ★I 축(돌연변이) = 구 mtime-only 복원 시 B 가 PASS 로 뒤집히는지. B 의 BLOCK 이
  #     정체 검사에서 온 것임을 매 실행 실증(오탐 제거와 검사 사망은 겉보기가 같다).
  #   ★L 축(루트 갈림) = 수리 중 나온 **반대 방향 동반 결함**. close_round 는 Bash 툴
  #     (CLAUDE_PROJECT_DIR 부재)에서 QM_ROOT=main 에 쓰는데 훅은 CLAUDE_PROJECT_DIR 이
  #     설정돼 **워크트리 루트**에서 읽는다 ⇒ 워크트리 세션은 제 마커를 원리적으로 못 찾는다
  #     (포장도로 사망 = 상시 오차단). 실측: 워크트리 .cache 에 게이트 산출물은 있는데
  #     closure 파일 0건, 종료 기록 468건 전부 main. L1 이 복구를, L2 가 "공유 루트를 훑어도
  #     남의 마커는 여전히 차단" 을 확인한다(루트 확장이 누수를 되열지 않는지).
  "08_Tests/hooks/test_continuity_marker_identity.py"
  # 2026-08-17 추가: C1 '판정 산출물' 판별(turn_verdict_artifacts)의 정체 검사.
  #   원 결함 = marker_fresh 와 **같은 뿌리**의 두 번째 누수. 종료 기록 2종을 mtime 만 보고
  #   "이번 턴에 판정을 냈다" 고 판정했는데, 그 파일들은 프로젝트 루트 단일 파일이고 main 의
  #   `.cache` 는 `/c/qm_cache` 심볼릭 링크라 **병렬 세션의 라운드 종료가 내 턴을 판정 턴으로
  #   만들었다** → 과거 판정 어휘를 인용만 한 운영/브리핑 턴이 차단(FP).
  #   ★이 축이 marker 수리에서 범위 밖이었던 건 방향이 반대라서다(우회가 아니라 과차단).
  #    그런데 그 전제를 실측이 뒤집었다 — 같은 남의 종료가 va=True 로 탐지를 살리는 **동시에**
  #    구 marker_fresh 를 True 로 만들어 계약을 충족시켜 통과시켰다. **두 누수가 서로를 가렸고**,
  #    marker 축만 고치면 가림막이 걷혀 FP 가 무장된다(1,282턴 재판정: 차단 276→302, 그중 5건).
  #   ★기존 continuity 배터리(02_Infrastructure/tests/test_continuity_gate.py)는 이 표면을
  #    **구조적으로 못 본다**: `verdict_artifact_override` 로 축을 절연해 함수 본문이 한 번도
  #    실행되지 않는다(31/31 초록이 결함을 못 본 이유). 옳은 격리가 만든 무커버 표면.
  #   ★I 축 돌연변이 = mtime-only 복원 시 B 가 차단으로 뒤집힘(통과가 어디서 오는지 실증).
  #   ★K0 양성 대조 = 초판 E2E 가 케이스 사전 없는 샌드박스에서 fail-open `{}` 을 뱉어
  #    '통과' 축이 게이트를 돌리지도 않고 초록이었다. 차단 능력을 먼저 보인 뒤 통과를 주장한다.
  "08_Tests/hooks/test_continuity_verdict_artifact_identity.py"
  # 2026-08-16~20 L1 자동 스폰 아크 (도훈 승인): test_p0_loop_closure.R ·
  #   test_auto_spawn_layers.R 은 **위 :875/:880 에 이미 등재**돼 있다. 2026-08-20 병합
  #   충돌 해소 때 여기 한 벌이 더 붙어 141 suite 를 143 회 돌렸고 FINAL 합계에 44 pass 가
  #   이중계상됐다(2026-08-22 감사 HLT-5). 편입 검사기는 고유화 후 세므로 원리적으로
  #   이 중복을 못 본다 ⇒ 중복 행 제거로 정정.
  # ── 2026-08-22 무인 리서치 배선 아크 (도훈 지시: "리서치까지 이어지는 배선이 제일 중요").
  #   10건 전부 이 세션 신설이고, 등재 전까지 **배터리가 한 번도 안 돌렸다** — 08-20 카드가
  #   기록한 "편입 드리프트 40건" 과 같은 계통이 즉시 재발한 것(검사기를 만드는 일과 배터리에
  #   거는 일은 별개 사건이다). 여기 등재로 회귀 방어에 편입한다.
  "08_Tests/ops/test_paper_router_backlog_axis.sh"
  "08_Tests/ops/test_mode_queue_research_run.sh"
  "08_Tests/ops/test_morning_run_live_pid_guard.sh"
  "08_Tests/ops/test_scheduler_alert_surface.sh"
  "08_Tests/ops/test_credential_scope_wiring.sh"
  "08_Tests/ops/test_failure_classify_window.sh"
  "08_Tests/ops/test_effect_signature_progress.sh"
  "08_Tests/ops/test_factor_evidence_backfill.py"
  "08_Tests/ops/test_research_queue_lanes.py"
  # 완주 알림 — 1급 축은 알림기 내부가 아니라 **호출 배선**이다(만들고 안 부르면 조용하다).
  "08_Tests/ops/test_run_completion_notify.sh"
  # 2026-08-22: 편입 검사기가 .py 를 탐색하지 않아 **08-09 신설분이 2주간 배터리 밖**이었다.
  #   (배터리는 .py 를 실행할 수 있는데 검사기의 분모에만 없었다 — 능력이 아니라 시야의 결손.)
  "08_Tests/hooks/test_benchmark_scale_seam.py"
  # 2026-08-22 논문 라우터 감사 후속 — 상태라인 정직성 + 정체 경보(내 timeout 제거 회귀).
  "08_Tests/ops/test_scheduler_status_line_honesty.sh"
  "08_Tests/ops/test_stall_lock_alert.sh"
  "08_Tests/ops/test_orchestrator_stage_gate.sh"
  # 무인 판정 게이트의 계층(ADOPT/SCREEN_TIER/QUARANTINE)·입력계약 2갈래·권위 서명.
  #   구판 대조 실증: 같은 검사가 구판에서 FAIL 10건.
  "08_Tests/ops/test_auto_alpha_gate_tiers.sh"
  # 무음 사망 탐지 — 정체 경보(살아 매달림)와 다른 축(죽어 증발). 실사고 18:30 검거.
  "08_Tests/ops/test_orphan_run_scan.py"
  # 논문 id 정규화 정본 — 같은 대상 수치가 셋이던 문제(좌초 154/62/61)의 수리.
  #   1급 축은 과잉 정규화 방지(내부 id 훼손) + 소비자 존재.
  "08_Tests/ops/test_paper_id_norm.py"
  # 좌초 회수 3축 — 1급 축은 회수가 아니라 **기본 동작 불변**(env 미지정 시 종전과 동일).
  "08_Tests/ops/test_router_backfill_paths.sh"
  # 스테이지 상한 + recharge 정체 경보 — 실측 51분 점유가 그날 파이프라인을 통째로 먹었다.
  #   ★1급 축은 "정상 소요를 자르지 않는가"(도훈의 리서치 런 상한 제거 지시와 다른 층).
  "08_Tests/ops/test_stage_timeout_and_recharge_stall.sh"
  # curated 결손이 arXiv 축까지 죽이던 결합 해소 + git 추적. 08-15/16/17 3일 연속 crash 전례.
  #   ★1급 축은 "죽지 않는가" 가 아니라 "조용히 넘기지도 않는가".
  "08_Tests/ops/test_curated_sources_isolation.sh"
  # β-통제 α 계약 (measurement-graduation.md §2). ★1급 축은 **양방향** —
  #   β>1 과대(α=0 인데 PORT_t 유의) · β<1 과소(진짜 α 를 버릴 위험). 합성 대조로 둘 다 실증.
  "08_Tests/contracts/test_beta_controlled_alpha.R"
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

# ★생산 원장 격리 가드 (2026-08-22 신설 — 감사 HLT-1/HLT-2)
#   검사가 생산 조회면을 변조하면 **같은 배터리의 후속 스위트가 그 가짜를 실물로 소비한다**
#   (실측: test_hypothesis_index_paper_lane 이 주입한 ZZ_PROBE_PAPER_LANE 를
#    risk_lane_verdict · nearest_arm_axis · Σ 어댑터 3 스위트가 등재 항목으로 읽었다).
#   더 나쁜 건 크래시 시 오염이 잔존해 **다음 회차의 시작 상태**가 되는 것 — 그러면
#   자기청소 검사가 '내가 안 지웠다'가 아니라 '이미 더러웠다'로 참양성 FAIL 을 내는데
#   겉보기는 flake 와 같다. ⇒ 스위트마다 보호 집합 지문을 재고, 바뀌면 이름과 함께 계상한다.
#   ★대상은 알파 라운드가 실제로 조회하는 면 + ②Distilled 카드(provenance 오염 포함).
# ★정책 2단 (2026-08-22 개정 — 병렬 세션 claude/nifty-lalande-ad9186 의 실측 반영)
#   (a) **md5 만으론 눈이 먼다**: 백업→변형→**완전 복원**은 바이트가 같아 내용 검사가 전부
#       초록인데 중간 상태는 이미 노출됐다 — 그게 실제 사고 경로였다. 실측: auto-commit 이
#       주입 상태를 blob 으로 캡처한 커밋이 **8건**(method_registry 5 + hypothesis_index 3,
#       최초 2026-08-16 16:30). ⇒ **쓰기 자체를 보는 축(mtime)** 을 지문에 포함한다.
#   (b) **정본마다 정당한 변경 빈도가 다르다**: method_registry 는 등재 이벤트에만 바뀌지만
#       hypothesis_index/knowledge_index/distilled_knowledge 는 **남의 세션 lookup·emit·
#       refine 이 상시 재빌드**한다(실측: 한 감사 세션 안에서 3회 값이 달라졌고, 배터리에서
#       test_revival_flags_sync 가 카드는 복원하고도 파생 인덱스 generated_at 만으로 걸렸다).
#       후자에 바이트 동치를 걸면 남의 정당한 작업에 빨개진다 ⇒ STRICT / ADVISORY 로 가른다.
REGISTRY_GUARD_STRICT=(     # 저빈도 정본 — 변하면 실패로 계상
  "06_Registry/method_registry.json"
  "06_Registry/alpha_frontier_queue.json"
)
REGISTRY_GUARD_ADVISORY=(   # 파생 조회면 — 병렬 세션이 정당하게 갱신, 보고만
  "06_Registry/hypothesis_index.json"
  "06_Registry/knowledge_index.json"
  "06_Registry/distilled_knowledge.json"
)
REGISTRY_DIRTY=()           # 실패 계상 대상
REGISTRY_ADVISORY=()        # 보고만
_fp_one() {                 # md5 + mtime 둘 다 (복원-성공 쓰기까지 검출)
  local f="$1"
  [[ -f "$PROJ_DIR/$f" ]] || { printf '%s ABSENT ABSENT\n' "$f"; return 0; }
  printf '%s %s %s\n' "$f" \
    "$(md5sum "$PROJ_DIR/$f" 2>/dev/null | cut -d' ' -f1)" \
    "$(date -r "$PROJ_DIR/$f" +%s 2>/dev/null || echo 0)" 
}
_reg_fp_strict() {
  local f
  for f in "${REGISTRY_GUARD_STRICT[@]}"; do _fp_one "$f"; done
  # ②Distilled 카드 = provenance 오염 표면. 재정제/추출 외엔 안 바뀌므로 STRICT.
  if [[ -d "$PROJ_DIR/qepm/memory/axioms/distilled" ]]; then
    printf 'qepm/memory/axioms/distilled/ %s -\n' \
      "$(find "$PROJ_DIR/qepm/memory/axioms/distilled" -name '*.json' -type f \
           -exec md5sum {} + 2>/dev/null | sort | md5sum | cut -d' ' -f1)" 
  fi
  return 0
}
_reg_fp_adv() {
  local f
  for f in "${REGISTRY_GUARD_ADVISORY[@]}"; do _fp_one "$f"; done
  return 0
}
# 변경된 **파일명**만 뽑는다. 양쪽(`<`·`>`) 을 다 집는다 — `>` 만 보면 **삭제**가 지문
#   불일치는 만들되 목록이 비어 계상이 0 이 되는 fail-open 이 된다(초판 가드가 실제로 그랬다).
_reg_diff_names() {
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") \
    | sed -n 's/^[<>] //p' | cut -d' ' -f1 | sort -u
}
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
  _rg0="$(_reg_fp_strict)"; _ra0="$(_reg_fp_adv)"
  if [[ "$test_script" == *.R ]]; then
    OUT=$(Rscript "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  elif [[ "$test_script" == *.py ]]; then
    OUT=$("$QVEST_PY_BIN" "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  else
    OUT=$(bash "$PROJ_DIR/$test_script" 2>&1 | _last_summary_json)
  fi
  _rg1="$(_reg_fp_strict)"; _ra1="$(_reg_fp_adv)"
  if [[ "$_rg0" != "$_rg1" ]]; then
    while IFS= read -r _dl; do
      [[ -n "$_dl" ]] && REGISTRY_DIRTY+=("$(basename "$test_script") :: $_dl")
    done < <(_reg_diff_names "$_rg0" "$_rg1")
  fi
  if [[ "$_ra0" != "$_ra1" ]]; then
    while IFS= read -r _dl; do
      [[ -n "$_dl" ]] && REGISTRY_ADVISORY+=("$(basename "$test_script") :: $_dl")
    done < <(_reg_diff_names "$_ra0" "$_ra1")
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
  "registry_dirty": [$(_j=""; for _l in ${REGISTRY_DIRTY[@]+"${REGISTRY_DIRTY[@]}"}; do
                 _e="${_l//\/\\}"; _e="${_e//\"/\\\"}"
                 if [[ -n "$_j" ]]; then _j+=","; fi; _j+="\"$_e\""
               done; printf '%s' "$_j")],
  "skips": [$(_j=""; for _l in ${SKIP_LINES[@]+"${SKIP_LINES[@]}"}; do
                 _e="${_l//\\/\\\\}"; _e="${_e//\"/\\\"}"
                 if [[ -n "$_j" ]]; then _j+=","; fi; _j+="\"$_e\""
               done; printf '%s' "$_j")],
  "tests": [$TESTS_JSON]
}
EOF

# 격리 위반은 **실패로 계상**한다 — 보고만 하면 무시되고, 무시된 오염은 다음 회차의
#   시작 상태가 된다(HLT-2 실측). 정당한 예외가 생기면 그때 명시 allowlist 를 만든다.
if (( ${#REGISTRY_DIRTY[@]} > 0 )); then
  TOTAL_FAIL=$((TOTAL_FAIL + ${#REGISTRY_DIRTY[@]}))
fi

echo ""
echo "════════════════════════════════════════"
if (( ${#REGISTRY_DIRTY[@]} > 0 )); then
  echo "⚠ REGISTRY DIRTY ${#REGISTRY_DIRTY[@]}건 — 검사가 저빈도 정본을 변조했다(격리 계약 위반):"
  for _l in "${REGISTRY_DIRTY[@]}"; do echo "    $_l"; done
  echo "────────────────────────────────────────"
fi
if (( ${#REGISTRY_ADVISORY[@]} > 0 )); then
  echo "ⓘ REGISTRY ADVISORY ${#REGISTRY_ADVISORY[@]}건 — 파생 조회면 변화(병렬 세션의 정당한"
  echo "   재빌드일 수 있어 실패로 계상하지 않는다. 탐침·가짜 항목이 보이면 그때가 위반):"
  for _l in "${REGISTRY_ADVISORY[@]}"; do echo "    $_l"; done
  echo "────────────────────────────────────────"
fi
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
