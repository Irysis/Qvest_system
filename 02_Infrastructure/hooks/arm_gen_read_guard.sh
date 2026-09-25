#!/usr/bin/env bash
#==============================================================================
# arm_gen_read_guard.sh — arm 생성·설계 세션의 **성과 열람 차단** (v10.2 2026-09-03 · P0-M2 2026-09-25)
#
# ★왜: 생성기의 핵심 안전 속성은 "성과를 보지 않는다" 다. 그래야 방출이 선언 축의
#   결정론적 함수가 되고, argmax 를 사후에 취해도 selection_type 이 정직하게 남는다
#   (generate_weight_variants.R 이 시그니처에서 ir/measured 를 빼는 것과 같은 규율).
#   그런데 `--add-dir` 는 워크스페이스를 넓힐 뿐 **읽기를 가두지 않는다**. Read 가 허용
#   목록에 있는 한 생성 세션은 원장을 그냥 열어 셀별 등급·Calmar 를 전부 볼 수 있다.
#   그러면 "구조적으로 불가" 라는 주장이 거짓이 된다 — 존재하지 않는 방어선을 세는 것이
#   이 저장소가 가장 자주 죽는 방식이다.
#
# (P0-M2 2026-09-25 · D9-04) 설계 레인까지 넓힌다 — 발화 = QVEST_ARM_GEN=1 ∨ QVEST_DESIGN_LANE=1.
#   설계 레인 = B1 설계(rf_b1_design.sh) · B5 설계(rf_b5_design.sh) · 블록 기전(rf_lcode_mechanism.sh).
#   세 셸이 claude 호출에 QVEST_DESIGN_LANE=1 을 싣는다(호출 한 번에만 — 뒤따르는 감사·등재 자식에는 안 샌다).
#   왜: transcript 전수(09-25) — B1·B5 설계 세션이 재료(날짜 제거·요약)를 건너뛰고 reinforce_ledger_l1.json 을
#   Read/Grep 으로 직접 읽었고(셀별 port_t·calmar·oos_retention), 기억 카드를 Read 로 읽었다.
#   설계자가 형제 entry 원장을 직접 읽던 경로는 **의도적으로** 막힌다(P3-02 교훈 검색이 대체 — 그 사이 정보 손실은 의도).
#   측정 경로 추가(좁게): stage_artifacts/replication/<run>/0[2-9]_*.csv (+같은 디렉터리 analysis_* · 성과 차트 png) ·
#     Claude 기억 디렉터리(.claude/projects/<slug>/memory — 02_Infrastructure/memory · qepm/memory/axioms 는 해당 없음) · MEMORY.md
#   판정(입력 경로는 전부 구분자·대소문자·.·..·~ 정규화 + 실경로 해소 — junction(.cache→C:/qm_cache)·8.3 이름):
#     R1 경로 — Read.file_path · Grep.path · Glob.path 가 측정 경로에 걸리면 block
#     R2 범위 — Grep 이 디렉터리를 뒤지면(재귀 = find 와 같다) glob·type 필터를 반영한 검색 범위가
#               측정 산출물 구역(06_Registry · stage_artifacts · 04_Research/{strategies,korea_research} ·
#               qepm/{research,mailbox} · .cache(+실경로) · 05_Production · .claude/worktrees · 기억 디렉터리)의
#               산출물을 덮는지 본다 — 덮으면 block (구역 = 측정 이름 파일의 09-25 실측 분포)
#     R3 열거 — Glob 패턴(path 결합)이 **기억 디렉터리** 카드와 일치하면 block(기억 카드는 파일 이름이 곧 요약이다).
#               원장·산출물 이름 열거는 막지 않는다 — 이름은 성과가 아니고 내용은 R1 이 Read 에서 막는다(09-25 드라이런 오차단 교정)
#     구역은 deep(임의 하위 run·전략 디렉터리) / shallow(06_Registry·.cache — 표본 경로 아래만) 로 가른다 —
#               설계 레인 자신의 작업 디렉터리(.cache/rf_b1_design 등)를 뒤지는 Grep 은 통과(09-25 드라이런 오차단 교정)
#        ★R2 2단(P0-M2 수리 2026-09-25 · B-2): 표본 대조는 **빠른 길**일 뿐이다 — 표본에 없는 이름의 실제 측정 파일은
#               glob 을 그 이름으로 좁히면 통과했다(적대 검증: 운영 대표 251건 중 137건 — 원장 .bak_2*·rf_parallel/result_B1_*·
#               analysis_fmb*.csv 등). 그래서 표본이 안 걸리면 검색 범위 ∩ 구역을 **실제로 순회**해, glob·type 필터를 통과하는
#               파일 중 R1 정규식에 걸리는 것이 하나라도 있으면 block(R2_walk). 필터를 통과하는 디렉터리 이름 아래는 전부 통과로 본다(보수적).
#               코드 파일(확장자 = 설정 code_ext)은 성과를 담지 않으므로 순회 적중에서 뺀다 — 필터가 코드만 통과시키면(*.R · type=r)
#               순회 자체를 생략(구판 통과 유지: 생성 레인 Grep 루트 *.R). R1(Read)의 이름 차단은 그대로다.
#               순회 상한 = 설정 02_Infrastructure/hooks/policies/arm_gen_read_guard.json(r2_walk · 근거 병기) — 넘으면 block(R2_scope_budget ·
#               범위를 좁히라는 안내). 설정 판독 불능 = 순회가 필요한 Grep 만 block(R2_policy · fail-closed).
#     R4 셸 — Bash/PowerShell 명령(문자열 결합 제거 · 글롭 토큰 · 재귀 탐색 시작점 · cd 추적)
#        ★R4 는 현재 **방어선이 아니다**: 이 훅의 등록 matcher 는 Read|Grep|Glob 이다(settings.json — 확장은 도훈 결정).
#        셸 우회의 실제 방어선 = 레인 CLI `--disallowed-tools "Bash,PowerShell,…"`(검사 test_arm_gen_read_guard.sh §J).
#        (09-25 실측: 설계·생성 레인 4종이 PowerShell 을 168회 시도, 그중 findstr 로 원장 calmar 를 읽은 호출이 통과했다 —
#         Bash 만 막고 PowerShell 을 열어 둔 것이 실제 구멍이었다.) R4 는 matcher 가 넓어지면 바로 유효하도록 판정만 준비한다.
#   출력 JSON 은 파이썬 json.dumps 가 만든다 — 구판은 원 경로를 JSON 문자열에 그대로 넣어 윈도 경로(C:\Users…)에서
#     무효 이스케이프(\U)가 났다 = CLI 가 판정을 못 읽는다(실제 레인 입력은 전부 역슬래시 절대경로다).
#   fail-closed: 판정기(파이썬) 실패 시 Read 는 원문 정규식으로 · Grep/Glob/셸은 범위 판정 불능으로 block.
#
# (R2 2026-09-25 · pit.md C1 D-E) 전기간 성과·IC 통계 산출물까지 넓힌다.
#   왜: C1 D-E(2026-09-23 도훈 확정) — 평가 창 결과를 소비하는 **자동 선정**은 C1/C14 다. 설계 레인(B1 팩터 · B5 arm ·
#   블록 기전 → 다음 블록 설계)은 무인 LLM = 자동 선정기다(사람이 문헌으로 고르는 것만 예외). P0-08(B08)은 규칙 폴백
#   (rf_factor_pool·rf_ic_cormat)과 B7(rf_sleeve)만 as-of 로 고쳤고, 설계 레인은 06_Registry/factor_evidence.json
#   (전기간 ic_all·ic_bad·ic_good·recent_3y_icir·ic_screen_tier)을 그냥 Read 할 수 있었다. 09-23 B1 설계 세션(70778752)은
#   06_Registry 를 팩터 id 로 Grep 해 ast_structure_log.jsonl 의 팩터별 전기간 canonical_screen port_t 를 실제로 받았다.
#   두 층으로 막는다:
#     STATS_RE(이름) — 운영 트리 09-25 전수 목록에서 도출: 팩터 IC·수익률 패널(파케이·rds 는 내용 판독 불가라 이름이 유일한 수단)
#       · 팩터별 스크린 로그 · 전략·모듈·arm 성과 원장 · 교훈 코퍼스 · L-code · 원장 사본. MEASURE_RE 에 합친다(= 셸 fail-closed 경로도 잡는다).
#       R2 구역에 04_Research(전체) · outputs · qepm/memory(evidence 만 표본) 를 더했다 — 통계 산출물이 거기에도 산다.
#     R1_content(내용) — 이름이 목록에 없는 새 산출물: Read(와 파일 경로 Grep)가 데이터 파일(.json/.jsonl/.csv/.tsv)을 가리키면
#       앞부분을 읽어 **구조 키**(JSON 키 `"port_t":` · CSV 머리 열)가 서로 다른 것 ≥ 설정 min_distinct_keys 면 block.
#       값으로 든 이름("select_winner_by": "port_t")은 키가 아니라 안 센다. 설정 = policies/arm_gen_read_guard.json::content_guard
#       (키 목록·문턱·열어 두는 경로 = 코드·설정 트리 02_Infrastructure · 공리 원천 qepm/memory/axioms · .claude 규칙 문서 — 근거 병기).
#       설정 판독 불능 = 데이터 파일 Read 는 block(R1_content_policy · fail-closed).
#   열어 두는 것(설계 레인이 정당하게 쓰는 의미 정보): factor_registry.json(이름·정의·계열) · 카탈로그(overlay·weight) ·
#     격자(reinforce_program) · 설정 · 공리 · 설계 레인 자기 작업 디렉터리 · 코드. 교차 entry 교훈의 수치는 재료 쪽(rf_b1_design_lib)이 가린다.
#   (R2 적대 검증 수리 2026-09-25) 운영 실경로로 통과가 실증된 우회 넷을 닫는다 —
#     ① 좁힌 glob 디렉터리 Grep: 순회(_walk)가 이름만 봐서 R1_content 가 Read 에서 막는 파일을 통과시켰다 → 순회도 내용 판정(R2_walk_content)
#     ② 내용 층 확장자: 입력 형태 하나의 끝 확장자만 봐서 8.3 짧은 이름(.JSO)·백업 접미사(.json.bak_*)·BOM 머리가 비껴갔다 → 모든 형태·접미사 안쪽·BOM 제거
#     ③ 구역 밖 디렉터리 Grep: 순회 없이 통과 → 저장소 루트 아래 · 열린 경로 밖이면 범위 자체를 순회
#     ④ 같은 수치의 사본: 공리 distilled·candidates·review_log·deprecated · 설계 캐시 재료·프롬프트(.txt) · 스케줄러 로그 → STATS_RE ⑤.
#        열린 경로 qepm/memory/axioms/ → qepm/memory/axioms/active/ 로 좁힘(설정). 설계 산출 되읽기(design_r*.json·*.mechanism.json·
#        블록 설계 json)는 남은 위험 — 교차 entry 수치 사본이지만 레인이 제 산출을 되읽으므로 entry 식별 표식 없이는 가를 수 없다.
#
# 발화 조건: QVEST_ARM_GEN=1 ∨ QVEST_DESIGN_LANE=1 일 때만. 평시에는 첫 줄에서 통과 — 소음 0.
# 검사: 08_Tests/hooks/test_arm_gen_read_guard.sh (위반 주입 · 평시 음성 · 정당 경로 · 우회 3종 · 돌연변이 · 레인 배선 ·
#       §N R2 순회 — 표본 밖 측정 파일 좁힌 glob · 코드 면제 · 디렉터리 glob · 예산 초과 · 설정 부재 ·
#       §O 전기간 통계(R2 2026-09-25) — 이름·구역·내용 3층 block · 의미 정보 pass · 설정 부재 fail-closed · 돌연변이)
# 설정: 02_Infrastructure/hooks/policies/arm_gen_read_guard.json (R2 순회 상한·코드 확장자 · content_guard — 근거 병기)
#==============================================================================
set -uo pipefail

# ★평시 무발화 — 생성·설계 세션이 아니면 아무것도 하지 않는다.
if [ "${QVEST_ARM_GEN:-0}" != "1" ] && [ "${QVEST_DESIGN_LANE:-0}" != "1" ]; then echo '{}'; exit 0; fi

LOG="${QVEST_ARM_GEN_GUARD_LOG:-/tmp/arm_gen_read_guard.log}"
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || \
    QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
fi

# 측정 산출물 경로 — 등급·성과가 들어 있는 것들. 비교 대상은 **정규화된 소문자 경로**(구분자 '/')다.
MEASURE_RE='reinforce_ledger_l[0-9]+\.json|authoritative_remeasure\.json|bt_result|rf_parallel/result_|overlay_ab_results|overlay_mechanism_map\.json|reinforce_auto_log\.jsonl|overlay_arm_ledger\.jsonl|essence_score|hurdle_result|stage_artifacts/replication/[^/]+/(0[2-9]_[a-z_]+\.csv|analysis_[a-z_]+\.(csv|md)|(equity_curve|drawdown|annual_returns)\.png)|\.claud(e|~[0-9])/projects/[^/]+/memory(/|"|$)|memory\.md'
# ★(R2 2026-09-25 · pit.md C1 D-E) 전기간 성과·IC 통계 산출물 — 이름 정본(도출 = 운영 트리 전수 목록 + 내용 키 스캔, 근거 = 이 파일 머리 주석).
#   ERE·파이썬 공용 문법만 쓴다(셸 fail-closed 경로의 grep -E 와 판정기 re 가 같은 식을 읽는다 — \d·(?:)·전후방탐색 금지).
#   ① 팩터 IC·수익률·스크린 — IC 행렬·패널(생산자 factor_db_connector.R compute_all_factor_ic_monthly → stage_gate_engine.R:889
#      sg_compute_conditional_ic → build_factor_evidence.py) · 팩터 수익률 패널 · 팩터별 canonical_screen 로그
STATS_RE='factor_evidence\.json|conditional_ic_matrix[^/" ]*\.(csv|json|parquet|rds)|ic_matrix_expanding[^/" ]*\.(parquet|csv|rds)|factor_ic_monthly[^/" ]*\.(parquet|csv|rds)|factor_returns[^/" ]*\.(parquet|csv|rds|json)|ast_structure_log[^/" ]*\.jsonl|fama_macbeth[^/" ]*\.(csv|json|rds|parquet)'
#   ② 토큰 규칙 — 경로 성분에 ic·icir·fmb·result(s) 가 구분자로 떨어져 있고 데이터 확장자로 끝나는 파일(analysis_ic.csv ·
#      ic_history.parquet · rank_ic.csv · *_icir_ranking.parquet · ic_direction_cache_v1/* · analysis_fmb*.csv · *_screen_results.csv …).
#      코드 확장자(.R 등)는 끝이 달라 안 걸린다.
STATS_RE+='|(^|[/_.-])(ic|icir|fmb|results?)([_.-][^/" ]*)?(/[^/" ]*)*\.(csv|tsv|json|jsonl|parquet|rds|rda|rdata|feather|arrow|fst|qs|pkl|npz|npy|xlsx)([^a-z0-9_]|$)'
#   ③ 교훈·원장 사본 — 계열 증거(ff5 t) · L-code(교차 entry 수치 — 재료는 가린 판을 준다) · 원장 사본(04_Research/01_reports/*/ledger_l1_<접미>.json — 접미 필수: 맨 이름 ledger_l1.json 조각은 구 규칙 몫이고, 문자열 결합 우회 판별(F03·m10)을 가리지 않게)
STATS_RE+='|qepm/memory/evidence(_summary)?/|stage_artifacts/l_code/|ledger_l[0-9]+_[^/" ]*\.json'
#   ④ 전략·모듈·arm 전기간 성과 원장(06_Registry·.cache) — 내용 키 스캔 09-25 적중분 중 파일명이 곧 성과 원장인 것
STATS_RE+='|hypothesis_index\.json|knowledge_index\.(json|md)|lcode_corpus\.json|module_catalog\.json|module_performance[^/" ]*\.json|strategy_registry\.json|strategy_grades\.json|rolling_grade\.json|essence_regrade[^/" ]*\.json'
STATS_RE+='|module_regime_admission\.json|module_quarantine\.json|combination_candidates\.json|overlay_candidate_queue[^/" ]*\.json|_ocq_json_backup[^/" ]*\.json|harvest_[0-9]+\.json|replication_request\.json|reinforce_ladder_ledger\.json'
STATS_RE+='|rf_director_(latest|context)\.json|rf_direction_score[^/" ]*\.json|alpha_frontier_queue[^/" ]*\.json|_fq_backup[^/" ]*\.json|lcode_distill_(execution|manifest|plan)[^/" ]*\.json|production_candidates\.json|auto_spawn_queue\.json|_asqj_backup[^/" ]*\.json'
STATS_RE+='|factor_rotation_registry\.json|portfolio_gap_vector\.json|round_closures[^/" ]*\.(json|jsonl|md)|standalone_track_(queue|dispositions)\.json|continuity_(pending_)?cases\.json|rule_axis_map_seed[^/" ]*\.json|mutation_tracker\.json|_ki_backup[^/" ]*\.json'
STATS_RE+='|mfro_[a-z0-9_]+\.csv|no_signal_[a-z0-9_]+\.(csv|json)|06_registry/(ramp|live_track|book|book_carrier)/|rf_overlay_adversary/'
#   ⑤ (R2 적대 검증 수리 2026-09-25) 같은 수치의 **다른 사본** — 이름 층이 원본만 막고 사본을 열어 두었다(운영 실경로로 통과 실증):
#      · 공리 후보·증류·검토·퇴역(qepm/memory/axioms/{distilled,candidates,review_log,deprecated}) — L-code 수치를 그대로 옮긴 사본
#        (DIST-QPM-014 "L-160 IC 0.22·ICIR 1.88·FM t 16.9" — L-code 는 ③ 이 막는데 사본은 열린 경로였다). 프롬프트 공리 주입은
#        active/ 만 쓰고 그것도 셸(rf_axiom_brief.sh)이 읽는다 — 설계 레인 표본 663건 중 이 디렉터리 열람 0건.
#      · 설계 레인 캐시의 재료·프롬프트 사본(rf_{b1_design,b5_design,lcode_mech,block_design}/ 아래 *materials*·*prompt* .txt) —
#        R2 이전 발송본은 가리지 않은 교차 entry 수치를 담는다(예 "L19_Price_Delay … PORT_t 4.349"). 세 레인 모두 재료를 프롬프트에
#        인라인으로 싣는다(cat "$MAT") = 에이전트가 파일을 열 이유가 없다(표본 663건 중 열람 0건). .txt 끝 고정 — 크기 메타
#        (materials_r1.txt.sizes.json)는 재료가 아니다(좁힌 glob=*.json 이 막히지 않게). 설계 산출(design_r*.json ·
#        *.mechanism.json · 블록 설계 json)은 레인이 제 산출을 되읽는 경로라 여기 넣지 않았다(남은 위험 — entry 식별 표식이 필요하다).
#      · 스케줄러 로그(scheduler_logs/) — reinforce_auto_*.log 가 셀별 grade·port_t·calmar 를 적는다(= 이미 막힌 reinforce_auto_log.jsonl 의 사본)
#      · 병렬 셀 사양(rf_parallel/spec_*) — recent_attempts 에 앞 칸의 등급·PORT_t 를 팩터 구성과 함께 싣는다(= rf_parallel/result_ 사본 · 표본 663건 중 열람 0건)
#      · 전략 성과 등록부 backtest_registry.csv(.bak_* 포함 — 백업 접미사는 내용 층 확장자 판정을 비껴간다)
STATS_RE+='|qepm/memory/axioms/(distilled|candidates|review_log|deprecated)/|rf_(b1_design|b5_design|lcode_mech|block_design)/([^/" ]*/)*[^/" ]*(materials|prompt)[^/" ]*\.txt([^a-z0-9_.]|$)|scheduler_logs/|rf_parallel/spec_|backtest_registry\.csv'
MEASURE_RE="${MEASURE_RE}|${STATS_RE}"

_log() { echo "[$(date -Iseconds)] BLOCK ${1:0:400}" >> "$LOG" 2>/dev/null || true; }

# 판정기 없이 막을 때 — 사유는 고정 문자열(경로를 JSON 에 넣지 않는다 = 항상 유효 JSON)
_deny_const() {
  printf '{"decision":"block","reason":"ARM_GEN_READ_BLOCKED[fail_closed · %s]: 판정기(파이썬) 실패 — 생성·설계 레인은 판별 불능이면 막는다. 측정 산출물이 아닌 파일을 Read 로 좁혀 다시 시도하라."}\n' "$1"
  _log "fail_closed $1"
  exit 0
}

INPUT=$(cat)

# ★fail-closed — 생성·설계 세션 안에서 판별 불능이면 막는다(평시엔 위에서 이미 빠져나갔다).
_fail_closed() {
  trap - ERR
  local hay
  hay="$(printf '%s' "${INPUT:-}" | tr '\\' '/' | tr -s '/' | tr 'A-Z' 'a-z')"
  if printf '%s' "$hay" | grep -qE "$MEASURE_RE"; then _deny_const "path"; fi
  if printf '%s' "$hay" | grep -qE '"tool_name" *: *"(grep|glob|bash|powershell)"'; then _deny_const "scope"; fi
  echo '{}'; exit 0
}
trap '_fail_closed' ERR

# 판정기 = 이 파일 끝의 파이썬 블록(파일에서 읽어 실행 — argv 로 한글 코드를 넘기지 않는다: 셸 인코딩 사고 방지)
SELF="${BASH_SOURCE[0]:-$0}"
SELFW="$(cygpath -m "$SELF" 2>/dev/null || printf '%s' "$SELF")"
RC=0
OUT=$(printf '%s' "$INPUT" | AGRG_MEASURE_RE="$MEASURE_RE" MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 PYTHONUTF8=1 \
  "$QVEST_PY_BIN" -c 'import sys
s = open(sys.argv[1], encoding="utf-8").read()
m = "#<<AGRG_" + "PY>>"
e = "#<<AGRG_" + "PY_END>>"
exec(compile(s.split(m, 1)[1].split(e, 1)[0], "arm_gen_read_guard.py", "exec"))' "$SELFW" 2>/dev/null) || RC=$?

# 검사 전용 자기진단(구역 표본 목록) — 가짜 도구 이름 AgrgSelftest 일 때만 나온다(실제 Read/Grep 판정에는 영향 없음)
if [ "$RC" -eq 0 ] && [ "${AGRG_SELFTEST:-0}" = "1" ]; then case "$OUT" in '{"regions"'*) printf '%s\n' "$OUT"; exit 0 ;; esac; fi
if [ "$RC" -eq 0 ] && [ "$OUT" = "ALLOW" ]; then echo '{}'; exit 0; fi
if [ "$RC" -eq 0 ]; then
  case "$OUT" in
    '{"decision":"block"'*) printf '%s\n' "$OUT"; _log "$OUT"; exit 0 ;;
  esac
fi
_fail_closed
exit 0

# ── 판정기(파이썬) — 위의 bash 가 이 블록만 잘라 실행한다. bash 는 여기까지 오지 않는다(위에서 exit). ──────────
: <<'AGRG_PY'
#<<AGRG_PY>>
import json, os, re, sys, posixpath, time

raw = sys.stdin.buffer.read().decode('utf-8', 'replace')
D = json.loads(raw)
TOOL = str(D.get('tool_name') or '')
TI = D.get('tool_input') or {}
if not isinstance(TI, dict):
    TI = {}
MRE = re.compile(os.environ['AGRG_MEASURE_RE'], re.I)
_des = os.environ.get('QVEST_DESIGN_LANE') == '1'
_arm = os.environ.get('QVEST_ARM_GEN') == '1'
LANE = 'arm_gen+design_lane' if (_des and _arm) else ('design_lane' if _des else 'arm_gen')
GLOBCH = set('*?[{')


def _slash(s):
    s = s.replace('\\', '/')
    m = re.match(r'^/cygdrive/([a-zA-Z])(/|$)', s) or re.match(r'^/([a-zA-Z])(/|$)', s)
    if m:
        s = m.group(1) + ':/' + s[m.end():]
    return s


HOME = _slash(os.environ.get('USERPROFILE') or os.environ.get('HOME') or os.path.expanduser('~')).rstrip('/')
_HOMEKEYS = ('${env:userprofile}', '$env:userprofile', '%userprofile%', '${userprofile}', '$userprofile', '${home}', '$home')


def _homesub(s):
    if s == '~' or s.startswith('~/'):
        s = HOME + s[1:]
    low = s.lower()
    for k in _HOMEKEYS:
        i = low.find(k)
        while i >= 0:
            s = s[:i] + HOME + s[i + len(k):]
            low = s.lower()
            i = low.find(k)
    return s


def _isabs(s):
    return bool(re.match(r'^[a-zA-Z]:/', s)) or s.startswith('/')


def norm(p, base):
    s = str(p or '').strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in '"\'':
        s = s[1:-1]
    if not s:
        return ''
    s = _homesub(_slash(s))
    if not _isabs(s):
        s = (base or '').rstrip('/') + '/' + s
    unc = s.startswith('//')
    s = re.sub(r'/+', '/', s)
    m = re.match(r'^([a-zA-Z]:)(/.*)?$', s)
    drive, rest = (m.group(1), m.group(2) or '/') if m else ('', s)
    rest = posixpath.normpath(rest)
    if rest in ('.', ''):
        rest = '/'
    out = (drive + rest) if drive else (('/' + rest) if unc else rest)
    return out.lower()


def win(n):
    return n[0].upper() + n[1:] if re.match(r'^[a-z]:/', n) else n


def real(n):
    try:
        if not n or any(c in n for c in GLOBCH):
            return None
        r = _slash(os.path.realpath(win(n)))
        if r.startswith('//?/'):
            r = r[4:]
        r = r.lower()
        return r if r != n else None
    except Exception:
        return None


def forms(p, base):
    n = norm(p, base)
    if not n:
        return []
    r = real(n)
    return [n] + ([r] if r else [])


def under(child, parent):
    p = parent.rstrip('/')
    return child == p or child == parent or child.startswith(p + '/')


CWD = norm(D.get('cwd') or os.getcwd(), '/')
CFG = norm(os.environ.get('CLAUDE_CONFIG_DIR') or '', '/')


def meas(s):
    if not s:
        return None
    m = MRE.search(s)
    if m:
        return m.group(0)
    if CFG and re.search(re.escape(CFG.rstrip('/')) + r'/projects/[^/]+/memory(/|$)', s):
        return 'claude_config_dir/memory'
    return None


# 측정 산출물 구역 — (구역 뿌리, 그 아래 표본 상대경로). 표본은 R1 정규식에 걸려야 한다(AGRG_SELFTEST 가 잰다).
_REP = ['replication/r/%s' % x for x in (
    'authoritative_remeasure.json', 'bt_result.rds', '02_nav.csv', '03_period_returns.csv', '04_holdings.csv',
    '05_benchmark_returns.csv', '06_metrics.csv', '07_benchmark_compare.csv', '08_rolling_metrics.csv', '09_drawdowns.csv',
    'analysis_report.md', 'analysis_ic.csv', 'equity_curve.png', 'drawdown.png', 'annual_returns.png')]
# deep = 측정 산출물이 **임의 하위 디렉터리**(run·전략·WT id)에 산다 — 구역 안 어느 디렉터리를 뒤져도 닿을 수 있다.
# shallow = 표본 상대경로에만 산다 — 구역 안 다른 하위 디렉터리(.cache/rf_b1_design · 06_Registry/memory_inbox 등
#   설계 레인 자신의 작업 디렉터리)는 구역이 아니다(09-25 드라이런: B1 설계가 자기 .cache/rf_b1_design 을 Grep 한 것을 막았다 — 오차단).
REG_SAMPLES = {
    '06_registry': (['reinforce_ledger_l1.json', 'reinforce_ledger_l2.json', 'reinforce_ledger_l1.json.bak_b5reset_1',
                     'overlay_mechanism_map.json', 'overlay_arm_ledger.jsonl'], False),
    '.cache': (['reinforce_auto_log.jsonl', 'rf_parallel/result_b5_1_1.json', 'overlay_ab_results.csv'], False),
    'stage_artifacts': (_REP + ['alpha_search/r/hurdle_result.json', 'alpha_search/r/bt_result.rds',
                                'alpha_search/r/authoritative_remeasure.json', 'wt/bt_result_s1.rds',
                                'reinforce_ladder/r/hurdle_result.json'], True),
    # 04_Research·qepm 은 측정 산출물이 사는 하위 디렉터리만(09-25 실측 분포) — qepm/memory/axioms(공리 원천)는 구역이 아니다
    '04_research/strategies': (['s/hurdle_result.json', 's/hurdle_result.rds', 's/bt_result.rds',
                                's/stage_artifacts/authoritative_remeasure.json'], True),
    '04_research/korea_research': (['k/hurdle_result.json'], True),
    'qepm/research': (['x/hurdle_result.json'], True),
    'qepm/mailbox': (['x/bt_result.rds', 'x/hurdle_result.csv'], True),
    '05_production': (['x/bt_result.rds'], True),
    '.claude/worktrees': (['w/06_registry/reinforce_ledger_l1.json',
                           'w/stage_artifacts/replication/r/authoritative_remeasure.json',
                           'w/stage_artifacts/replication/r/04_holdings.csv'], True),
}
# (R2 2026-09-25 · C1 D-E) 전기간 통계 표본 — 기존 구역에 덧붙이고 새 구역 셋을 더한다(기존 줄은 검사 돌연변이 좌표라 그대로 둔다).
#   표본은 전부 STATS_RE 에 걸려야 한다(AGRG_SELFTEST 가 잰다). 새 구역 = 운영 트리 09-25 전수 목록에서 통계 파일이 사는 곳:
#   04_Research 전체(01_reports 원장 사본 · factor_rotation IC · decision_framework 팩터 수익률 · method_frontier 등 — strategies·
#   korea_research 만 구역이던 구판은 그 밖을 Grep 이 무필터로 뒤져도 통과시켰다) · outputs(ramp IC·팩터 수익률) ·
#   qepm/memory(shallow — evidence·evidence_summary 만 · axioms 는 공리 원천이라 구역 아님).
for _k, _extra in (('06_registry', ['factor_evidence.json', 'ast_structure_log.jsonl', 'hypothesis_index.json', 'module_catalog.json',
                                    'mfro_rotation_signal_ic_by_year_20260822.csv', 'book/book_registry.json']),
                   ('.cache', ['conditional_ic_matrix.csv', 'factor_db/factor_ic_monthly.parquet', 'lcode_corpus.json',
                               'rf_overlay_adversary/b5_18.json']),
                   ('stage_artifacts', ['l_code/reinforcement/l_code_x_b1.json', 'alpha_search/r/analysis_ic.csv'])):
    REG_SAMPLES[_k] = (REG_SAMPLES[_k][0] + _extra, REG_SAMPLES[_k][1])
REG_SAMPLES.update({
    '04_research': (['x/analysis_ic.csv', 'x/factor_returns.parquet', 'x/ledger_l1_post_epoch.json', 'x/analysis_fmb.csv'], True),
    'outputs': (['ramp/latent_factor_returns.parquet', 'ramp/dfa_ic_calmar_ladder.csv'], True),
    'qepm/memory': (['evidence/ev_x.json', 'evidence_summary/fam_x.json'], False),
})
MEM_SAMPLES =['memory.md', 'project-card-20260925.md', 'feedback-card-20260925.md']
REGIONS = []   # (뿌리, 표본, deep, 기억 디렉터리 여부)
_seen = set()


def _add_region(p, samples, deep, mem=False):
    for f in [p] + ([real(p)] if real(p) else []):
        if f and (f, id(samples)) not in _seen and os.path.isdir(win(f)):
            _seen.add((f, id(samples)))
            REGIONS.append((f.rstrip('/'), samples, deep, mem))


ROOTS = []
for v in (os.environ.get('CLAUDE_PROJECT_DIR'), os.environ.get('QM_ROOT'), os.environ.get('QVEST_RF_ROOT'), D.get('cwd') or os.getcwd()):
    if v:
        for f in forms(v, CWD):
            if f not in ROOTS:
                ROOTS.append(f)
for r in ROOTS:
    for sub, (smp, deep) in REG_SAMPLES.items():
        _add_region(r.rstrip('/') + '/' + sub, smp, deep)
for pd in [HOME + '/.claude/projects'] + ([CFG.rstrip('/') + '/projects'] if CFG else []):
    pdn = norm(pd, '/')
    try:
        names = os.listdir(win(pdn))
    except Exception:
        names = []
    for nm in names:
        md = pdn + '/' + nm.lower() + '/memory'
        if os.path.isdir(win(md)):
            _add_region(md, MEM_SAMPLES, True, True)   # 기억: 하위 보관 디렉터리(_archive_*)에도 카드가 있다 = deep


def _gre(pat):
    out, i, n, dep = '', 0, len(pat), 0
    while i < n:
        c = pat[i]
        if c == '*':
            if i + 1 < n and pat[i + 1] == '*':
                if i + 2 < n and pat[i + 2] == '/':
                    out += '(?:.*/)?'
                    i += 3
                    continue
                out += '.*'
                i += 2
                continue
            out += '[^/]*'
        elif c == '?':
            out += '[^/]'
        elif c == '[':
            j = pat.find(']', i + 1)
            if j < 0:
                out += re.escape(c)
            else:
                body = pat[i + 1:j]
                if body.startswith('!'):
                    body = '^' + body[1:]
                out += '[' + body.replace('\\', '\\\\') + ']'
                i = j + 1
                continue
        elif c == '{':
            out += '(?:'
            dep += 1
        elif c == '}' and dep:
            out += ')'
            dep -= 1
        elif c == ',' and dep:
            out += '|'
        else:
            out += re.escape(c)
        i += 1
    out += ')' * dep
    try:
        return re.compile('^' + out + '$', re.I)
    except re.error:
        return re.compile('^' + re.escape(pat) + '$', re.I)


TYPES = {'json': ('.json', '.jsonl'), 'jsonl': ('.jsonl',), 'csv': ('.csv',), 'md': ('.md', '.markdown', '.mdx'),
         'markdown': ('.md', '.markdown', '.mdx'), 'r': ('.r', '.rmd', '.rd', '.rprofile'), 'py': ('.py', '.pyi'),
         'python': ('.py', '.pyi'), 'sh': ('.sh', '.bash', '.zsh'), 'txt': ('.txt',), 'js': ('.js', '.jsx', '.mjs', '.cjs'),
         'ts': ('.ts', '.tsx'), 'yaml': ('.yaml', '.yml'), 'toml': ('.toml',), 'html': ('.html', '.htm'), 'css': ('.css',),
         'cpp': ('.cpp', '.cc', '.cxx', '.h', '.hpp'), 'c': ('.c', '.h'), 'rust': ('.rs',), 'go': ('.go',),
         'java': ('.java',), 'sql': ('.sql',), 'ps': ('.ps1', '.psm1'), 'powershell': ('.ps1', '.psm1')}


def _split_globs(g):
    parts, cur, dep = [], '', 0
    for ch in g:
        if ch == '{':
            dep += 1
        elif ch == '}':
            dep = max(0, dep - 1)
        if dep == 0 and (ch == ',' or ch.isspace()):
            if cur:
                parts.append(cur)
            cur = ''
            continue
        cur += ch
    if cur:
        parts.append(cur)
    return parts


def _gmatch(pat, rel):
    p = pat.replace('\\', '/').lstrip('/')
    if '/' not in p.rstrip('/'):
        return bool(_gre(p).match(rel.rsplit('/', 1)[-1]))
    rx, segs = _gre(p), rel.split('/')
    return any(rx.match('/'.join(segs[k:])) for k in range(len(segs)))   # 보수적: 어느 깊이든


def _passes(rel, glob, typ):
    if typ:
        ex = TYPES.get(str(typ).lower())
        if ex is not None and not rel.lower().endswith(ex):
            return False
    if glob:
        pats = _split_globs(str(glob))
        pos = [x for x in pats if not x.startswith('!')]
        neg = [x[1:] for x in pats if x.startswith('!')]
        if any(_gmatch(x, rel) for x in neg):
            return False
        if pos and not any(_gmatch(x, rel) for x in pos):
            return False
    return True


_POL = None


def _policy():
    # R2 순회 설정 — 이 훅 옆 policies/arm_gen_read_guard.json(수치 근거는 설정 파일에). 판독 불능 = False(호출자가 block).
    global _POL
    if _POL is None:
        try:
            pth = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), 'policies', 'arm_gen_read_guard.json')
            d = json.load(open(pth, encoding='utf-8'))
            w = d['r2_walk']
            pol = dict(max_entries=int(w['max_entries']), max_seconds=float(w['max_seconds']),
                       code_ext=tuple(str(x).lower() for x in d['code_ext']))
            if pol['max_entries'] <= 0 or pol['max_seconds'] <= 0 or not pol['code_ext'] \
                    or not all(x.startswith('.') and len(x) > 1 for x in pol['code_ext']):
                raise ValueError('bad policy')
            _POL = pol
        except Exception:
            _POL = False
    return _POL


_CPOL = None
# 설정 판독 불능일 때만 쓰는 보수적 기본(fail-closed) — 흔한 텍스트 데이터 확장자. 정상 경로의 확장자·키·문턱은 전부 설정에서 온다.
_CPOL_FAILCLOSED_EXT = ('.json', '.jsonl', '.csv', '.tsv')


def _cpolicy():
    # (R2 2026-09-25) R1_content 설정 — 같은 policies/arm_gen_read_guard.json::content_guard. 판독 불능 = False(호출자가 block).
    #   R2 순회 설정(_policy)과 따로 읽는다 — 한쪽이 깨져도 다른 쪽 판정은 제 설정대로 돈다.
    global _CPOL
    if _CPOL is None:
        try:
            pth = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), 'policies', 'arm_gen_read_guard.json')
            c = json.load(open(pth, encoding='utf-8'))['content_guard']
            keys = [str(k) for k in c['keys']]
            pol = dict(ext=tuple(str(x).lower() for x in c['ext']), max_bytes=int(c['max_bytes']),
                       min_distinct=int(c['min_distinct_keys']),
                       open=tuple(str(x).lower().replace(chr(92), '/') for x in c['open_prefixes']),
                       krx=re.compile(r'"(' + '|'.join(keys) + r')"\s*:', re.I),
                       hrx=[re.compile('^(?:' + k + ')$', re.I) for k in keys])
            if not pol['ext'] or not all(x.startswith('.') and len(x) > 1 for x in pol['ext']) or pol['max_bytes'] <= 0 \
                    or pol['min_distinct'] < 1 or not keys or not all(isinstance(x, str) and x.endswith('/') for x in pol['open']):
                raise ValueError('bad content_guard')
            _CPOL = pol
        except Exception:
            _CPOL = False
    return _CPOL


def _root_rel(n):
    for r in ROOTS:
        rr = r.rstrip('/')
        if n.startswith(rr + '/'):
            return n[len(rr) + 1:]
    return None


def _dext(n, exts):
    # (R2 적대 검증 수리) 데이터 확장자 — 끝 확장자 또는 백업·스트림 접미사 안쪽(x.json.bak_1 · x.csv.orig · x.json::$data · x.json.)
    b = (n or '').rsplit('/', 1)[-1]
    for e in exts:
        if b.endswith(e) or any((e + c) in b for c in '._~:-'):
            return e
    return None


def content_hit(fs):
    # (R2 2026-09-25) R1_content — 이름이 목록에 없는 전기간 통계 산출물을 **내용**으로 재도출한다.
    #   fs = forms(p) (정규화 경로 + 실경로). 데이터 파일(설정 ext)만 · 열어 두는 경로(설정 open_prefixes — 저장소 루트 기준) 제외.
    #   구조 키 = JSON 키(`"port_t":`) + CSV/TSV 머리 열. 값으로 든 이름("select_winner_by": "port_t")은 세지 않는다.
    #   서로 다른 키(정규화 — 키 목록의 어느 항목에 걸렸나) 수 ≥ min_distinct_keys → ('R1_content', …). 설정 판독 불능 → ('R1_content_policy', …).
    #   (R2 적대 검증 수리 2026-09-25) 확장자는 **모든 형태**(입력 · 실경로)에서 · 백업 접미사 안쪽까지 본다 — 입력 형태 하나만 보던 판은
    #   8.3 짧은 이름(METHOD~1.JSO — 실경로는 method_registry.json)과 백업 접미사(governance_log.json.bak.2026…) 로 통과했다(운영 실증).
    if not fs:
        return None
    n0 = fs[0]
    try:
        if not os.path.isfile(win(n0)):
            return None
    except Exception:
        return None
    cp = _cpolicy()
    if not cp:
        return ('R1_content_policy', n0 + ' — content_guard 설정 판독 불능(fail-closed)') \
            if any(_dext(f, _CPOL_FAILCLOSED_EXT) for f in fs) else None
    de = None
    for f in fs:
        de = _dext(f, cp['ext'])
        if de:
            break
    if not de:
        return None
    for f in fs:
        rel = _root_rel(f)
        if rel is not None and rel.startswith(cp['open']):
            return None
    try:
        with open(win(n0), 'rb') as fh:
            s = fh.read(cp['max_bytes']).decode('utf-8', 'replace')
    except Exception:
        return None                                              # 못 여는 파일은 도구도 못 연다
    hit = set()

    def _canon(k):
        for i, rx in enumerate(cp['hrx']):
            if rx.match(k):
                return i
        return None
    if de in ('.csv', '.tsv'):
        for k in re.split(r'[,\t;]', s.lstrip('\ufeff').split('\n', 1)[0]):
            c = _canon(k.strip().strip('"').strip("'").strip())
            if c is not None:
                hit.add(c)
    for m in cp['krx'].finditer(s):
        c = _canon(m.group(1))
        if c is not None:
            hit.add(c)
    if len(hit) >= cp['min_distinct']:
        return ('R1_content', '%s (구조 키 %d종)' % (n0, len(hit)))
    return None


def _brace(p, cap=64):
    # 중괄호 전개 — 전개 수가 cap 을 넘거나 짝이 안 맞으면 None(호출자 = '코드만' 판정 포기 → 순회)
    i = p.find('{')
    if i < 0:
        return [p]
    dep = 0
    for j in range(i, len(p)):
        if p[j] == '{':
            dep += 1
        elif p[j] == '}':
            dep -= 1
            if dep == 0:
                alts, cur, d2 = [], '', 0
                for ch in p[i + 1:j]:
                    if ch == '{':
                        d2 += 1
                    elif ch == '}':
                        d2 -= 1
                    if ch == ',' and d2 == 0:
                        alts.append(cur)
                        cur = ''
                        continue
                    cur += ch
                alts.append(cur)
                out = []
                for a in alts:
                    sub = _brace(p[:i] + a + p[j + 1:], cap)
                    if sub is None:
                        return None
                    out.extend(sub)
                    if len(out) > cap:
                        return None
                return out
    return None


def _code_only(glob, typ, cx):
    # 필터가 **코드 확장자 파일만** 통과시키는가 — 참이면 R2 순회 생략(코드는 성과를 담지 않는다). 모르면 False(= 순회).
    if typ:
        ex = TYPES.get(str(typ).lower())
        if ex is not None and all(e in cx for e in ex):
            return True
    if not glob:
        return False
    pos = [x for x in _split_globs(str(glob)) if not x.startswith('!')]
    if not pos:
        return False
    for x in pos:
        alts = _brace(x)
        if alts is None:
            return False
        for a in alts:
            base = a.replace('\\', '/').rstrip('/').rsplit('/', 1)[-1]
            m = re.search(r'\.[A-Za-z0-9_+-]+$', base)
            if not m or m.group(0).lower() not in cx:
                return False
    return True


def _dir_whitelisted(rel, glob):
    # rg 는 양성 glob 에 걸린 **디렉터리** 아래를 통째로 뒤질 수 있다 — 보수적으로 그 아래 파일은 glob 통과로 본다
    if not glob:
        return False
    pos = [x for x in _split_globs(str(glob)) if not x.startswith('!')]
    return any(_gmatch(x, rel) for x in pos)


def _passes2(rel, glob, typ, inc):
    if not inc:
        return _passes(rel, glob, typ)
    if typ:
        ex = TYPES.get(str(typ).lower())
        if ex is not None and not rel.lower().endswith(ex):
            return False
    if glob:
        neg = [x[1:] for x in _split_globs(str(glob)) if x.startswith('!')]
        if any(_gmatch(x, rel) for x in neg):
            return False
    return True


class _Budget(Exception):
    pass


def _walk(root, pre, glob, typ, pol, st, seen):
    # root 아래를 실제로 순회 — glob·type 을 통과하는 비코드 파일 중 R1 정규식(meas)에 걸리는 첫 파일을 돌려준다.
    # st = [순회 항목 수, 시작 시각] (호출 전체 공유 예산) · seen = 실경로(junction·symlink 순환·중복 방지)
    cx = pol['code_ext']
    stack = [(root.rstrip('/'), pre, False)]
    while stack:
        d, rp, inc = stack.pop()
        try:
            it = os.scandir(win(d))
        except Exception:
            continue                                            # 못 여는 디렉터리는 rg 도 못 연다
        with it:
            for e in it:
                st[0] += 1
                if st[0] > pol['max_entries'] or time.perf_counter() - st[1] > pol['max_seconds']:
                    raise _Budget()
                nm = e.name.lower()
                full = d + '/' + nm
                rel = (rp + '/' + nm) if rp else nm
                try:
                    isdir = e.is_dir()
                except Exception:
                    isdir = False
                if isdir:
                    try:
                        lk = e.is_symlink() or e.is_junction()
                    except Exception:
                        lk = True
                    if lk:
                        k = real(full) or full
                        if k in seen:
                            continue
                        seen.add(k)
                    stack.append((full, rel, inc or _dir_whitelisted(rel, glob)))
                    continue
                if nm.endswith(cx):
                    continue
                if _passes2(rel, glob, typ, inc):
                    if meas(full):
                        return ('R2_walk', full)
                    # (R2 적대 검증 수리 2026-09-25) 순회도 **내용**으로 재도출한다 — 이름만 보던 판은 R1_content 가 Read 에서 막는 파일을
                    #   glob 으로 좁힌 디렉터리 Grep 이 그대로 통과시켰다(B-2 와 같은 꼴 · 운영 실증: 04_Research/90_legacy
                    #   glob=residual_alpha_ranking.csv = ic_all·ic_bad·ic_good·recent_3y_icir 열 · strategies glob=s5_research_slate_*.json).
                    ch = content_hit([full])                     # scandir 이름 = 긴 이름(8.3 아님) — 실경로 해소 불요
                    if ch:
                        return ('R2_walk_' + ch[0][3:], ch[1])      # R2_walk_content | R2_walk_content_policy
    return None


def scope_hit(dirs, glob, typ):
    # 반환 = (규칙, 무엇) | None.  ① 표본 대조(빠른 길) → ② 검색 범위 ∩ 구역 실제 순회(표본에 없는 측정 파일)
    for p in dirs:
        if not os.path.isdir(win(p)):
            continue
        pp = p.rstrip('/')
        for rr, smp, deep, _mem in REGIONS:
            if under(rr, pp):                                   # 검색 범위가 구역 전체를 덮는다
                pre = rr[len(pp) + 1:] if rr != pp else ''
                for s in smp:
                    rel = (pre + '/' + s) if pre else s
                    if _passes(rel, glob, typ):
                        return ('R2_scope', rr + '/' + s)
            elif under(pp, rr):                                 # 검색 범위가 구역 안
                sub = pp[len(rr) + 1:]
                for s in smp:
                    if deep:                                    # 임의 하위 디렉터리에 산다 — 이름(과 필터)만으로 판정
                        if _passes(s, glob, typ):
                            return ('R2_scope', pp + '/**/' + s.rsplit('/', 1)[-1])
                    elif s.startswith(sub + '/') and _passes(s[len(sub) + 1:], glob, typ):   # shallow — 표본 경로 아래일 때만
                        return ('R2_scope', rr + '/' + s)
    # ② 순회 — 뒤질 (뿌리, glob 기준 상대 접두) 쌍: 범위가 구역을 덮으면 구역 전체 · 범위가 구역 안이면 범위만
    pairs = []
    cpo = _cpolicy()
    for p in dirs:
        if not os.path.isdir(win(p)):
            continue
        pp = p.rstrip('/')
        # (R2 적대 검증 수리 2026-09-25) 구역 밖 디렉터리도 순회한다 — 저장소 루트 아래 · 열린 경로(content_guard open_prefixes) 밖이면
        #   범위 자체를 이름+내용으로 뒤진다(구역 목록 밖 통계 파일: qepm/registry/backtest_registry.csv · qepm/stage_artifacts/*/alpha_validation.json ·
        #   qepm/observability — 구판은 구역에 안 걸리면 순회 없이 통과). 루트 자체는 제외(구역 순회 = 예산 판정 그대로).
        rel = _root_rel(pp)
        if rel is not None and cpo and not (rel + '/').startswith(cpo['open']):
            if (pp, '') not in pairs:
                pairs.append((pp, ''))
            continue
        for rr, _smp, _deep, _mem in REGIONS:
            if under(rr, pp):
                pr = (rr, rr[len(pp) + 1:] if rr != pp else '')
            elif under(pp, rr):
                pr = (pp, '')
            else:
                continue
            if pr not in pairs:
                pairs.append(pr)
    if not pairs:
        return None
    pol = _policy()
    if not pol:
        return ('R2_policy', 'policies/arm_gen_read_guard.json 판독 불능 — 범위 순회 불가(fail-closed)')
    if _code_only(glob, typ, pol['code_ext']):
        return None
    st, seen = [0, time.perf_counter()], set()
    try:
        for root, pre in pairs:
            k = real(root) or root
            if k in seen:
                continue
            seen.add(k)
            h = _walk(root, pre, glob, typ, pol, st, seen)
            if h:
                return h                                        # ('R2_walk' | 'R2_walk_content' | 'R2_walk_content_policy', 무엇)
    except _Budget:
        return ('R2_scope_budget', '순회 %d항목 · %.1f초 초과 — 범위가 너무 넓다(path 를 좁혀라)' % (st[0] - 1, time.perf_counter() - st[1]))
    return None


def glob_hit(full, dirs=False, mem_only=False):
    # dirs=True(셸 판) = 구역 뿌리·표본의 상위 디렉터리도 후보 — `ls ~/.c*/p*/*/m*/` 는 디렉터리를 가리켜 안을 연다.
    # mem_only=True(Glob 도구 R3) = 기억 디렉터리만 — Glob 은 파일 **이름**만 돌려준다. 원장·산출물 이름 열거는 성과가 아니고
    #   (내용은 R1 이 Read 에서 막는다) 기억 카드 이름만 요약(등급·판정)을 담는다(09-25 드라이런: B5 설계의
    #   Glob 06_Registry/*overlay* 를 막은 것은 오차단이었다).
    rx = _gre(full)
    for rr, smp, _deep, mem in REGIONS:
        if mem_only and not mem:
            continue
        cands = [rr + '/' + s for s in smp]
        if dirs:
            cands.append(rr)
            for s in smp:
                parts = s.split('/')[:-1]
                cands.extend(rr + '/' + '/'.join(parts[:k]) for k in range(1, len(parts) + 1))
        for c in cands:
            if rx.match(c):
                return c
    return None


def block(rule, what):
    msg = ('ARM_GEN_READ_BLOCKED[%s · %s]: %s — 생성·설계 레인은 성과를 직접 보지 않는다(측정 전 방출 · 설계는 재료만 본다). '
           '표적 칸·함수 계약·필요한 요약은 프롬프트(재료)에 이미 들어 있다. 코드·등록부를 찾으려면 범위를 좁혀라 '
           '(예: path=02_Infrastructure/… 또는 glob="*.R" · 원장·측정 산출물·기억 디렉터리는 제외).') % (LANE, rule, what)
    sys.stdout.buffer.write(json.dumps({'decision': 'block', 'reason': msg}, ensure_ascii=True, separators=(',', ':')).encode('ascii'))
    sys.exit(0)


if os.environ.get('AGRG_SELFTEST') == '1' and TOOL == 'AgrgSelftest':
    bad = [rr + '/' + s for rr, smp, _d, _m in REGIONS for s in smp if not meas(rr + '/' + s)]
    sys.stdout.buffer.write(json.dumps({'regions': [r[0] for r in REGIONS], 'n_samples': sum(len(r[1]) for r in REGIONS),
                                        'unmatched_samples': bad, 'roots': ROOTS, 'cwd': CWD}).encode('utf-8'))
    sys.exit(0)

_RECUR_ALWAYS = {'find', 'find.exe', 'rg', 'rg.exe', 'ag', 'ack', 'tree', 'du', 'robocopy', 'xcopy'}
_RECUR_OPT = {'grep', 'egrep', 'fgrep', 'zgrep', 'ls', 'dir', 'gci', 'get-childitem', 'childitem', 'select-string', 'sls',
              'cp', 'copy-item', 'cpi', 'copy', 'findstr', 'rm', 'remove-item'}
_RECUR_TXT = ('os.walk', 'rglob', 'recursive=true', 'recursive = true', '-recurse')


def _is_opt(t):
    return t.startswith('-') or bool(re.match(r'^/[a-z?]$', t))


def _recursive_opt(t):
    return (bool(re.match(r'^-[a-z]*r[a-z]*$', t)) or t in ('--recursive', '--dereference-recursive', '/s', '-s')
            or t.startswith('-rec') or t == '-depth')


def shell_hit(cmd):
    raw = str(cmd or '')
    joined = re.sub(r'''(['"])\s*[+.,]?\s*(['"])''', '', raw)          # 'a' + 'b' · "a","b" · 'a' 'b' → ab (문자열 결합 제거)
    variants = []
    for b in (raw, joined):
        for v in (b.replace('\\', '/'), b.replace('\\', '')):
            v = re.sub(r'''['"`]''', '', v)
            v = re.sub(r'/+', '/', _homesub(v)).lower()
            if v not in variants:
                variants.append(v)
    for v in variants:
        hit = meas(v)
        if hit:
            return 'shell_text', hit
    for v in variants:
        toks = [t for t in re.split(r'[;|&()<>=,{}\s]+', v) if t]
        ecwd, rec_txt = CWD, any(x in v for x in _RECUR_TXT)
        for k, t in enumerate(toks):
            if t in ('cd', 'pushd', 'set-location', 'sl', 'chdir'):
                nx = toks[k + 1] if k + 1 < len(toks) else '~'
                if nx in ('-path', '-literalpath', '-lp') and k + 2 < len(toks):
                    nx = toks[k + 2]
                elif _is_opt(nx):
                    nx = '~'
                ecwd = norm(nx, ecwd) or ecwd
                continue
            if any(c in t for c in '*?['):
                f = norm(t, ecwd)
                hit = glob_hit(f, dirs=True) if f else None
                if hit:
                    return 'shell_glob', t
            base = t.rsplit('/', 1)[-1]
            rec = base in _RECUR_ALWAYS or (base in _RECUR_OPT and any(_recursive_opt(x) for x in toks[k + 1:])) \
                or (rec_txt and base in ('python', 'python.exe', 'python3', 'py', 'rscript', 'rscript.exe', 'r', 'pwsh', 'powershell'))
            if not rec:
                continue
            starts = []
            for a in toks[k + 1:]:
                if _is_opt(a):
                    continue
                for f in forms(a, ecwd):
                    if os.path.isdir(win(f)):
                        starts.append(f)
            for st in (starts or [ecwd]):
                st = st.rstrip('/')
                for rr, smp, deep, _m in REGIONS:
                    if under(rr, st):
                        return 'shell_find', st
                    if under(st, rr) and (deep or any(s.startswith(st[len(rr) + 1:] + '/') for s in smp)):
                        return 'shell_find', st
    return None


def check():
    if TOOL in ('Bash', 'PowerShell'):
        h = shell_hit(TI.get('command'))
        if h:
            block('R4_' + h[0], h[1])
        return
    if TOOL == 'Read' or ('file_path' in TI and TOOL not in ('Grep', 'Glob')):
        fp = TI.get('file_path') or TI.get('path') or TI.get('notebook_path') or ''
        fsr = forms(fp, CWD)
        for f in fsr:
            h = meas(f)
            if h:
                block('R1_path', f)
        h = content_hit(fsr)                                    # (R2) 이름 밖 통계 산출물 — 내용 재도출
        if h:
            block(h[0], h[1])
        return
    if TOOL == 'Grep':
        pth = TI.get('path') or ''
        fs = forms(pth, CWD) if pth else ([CWD] + ([real(CWD)] if real(CWD) else []))
        for f in fs:
            h = meas(f)
            if h:
                block('R1_path', f)
        if pth:
            h = content_hit(fs)                                 # (R2) 파일 하나를 Grep = 그 파일을 읽는다
            if h:
                block(h[0], h[1])
        h = scope_hit(fs, TI.get('glob') or '', TI.get('type') or '')
        if h:
            block(h[0], h[1])
        return
    if TOOL == 'Glob':
        pth = TI.get('path') or ''
        base = forms(pth, CWD) if pth else [CWD]
        for f in base:
            h = meas(f)
            if h:
                block('R1_path', f)
        pat = str(TI.get('pattern') or '')
        for b in base:
            full = norm(pat, b)
            if not full:
                continue
            if not any(c in full for c in GLOBCH):
                for f in [full] + ([real(full)] if real(full) else []):
                    if meas(f):
                        block('R1_path', f)
                continue
            h = glob_hit(full, mem_only=True)
            if h:
                block('R3_glob', h)
        return
    # 그 밖의 도구: 입력 안의 경로성 값 전부를 R1 로(보수적)
    for k in ('file_path', 'path', 'notebook_path', 'pattern'):
        if TI.get(k):
            fso = forms(TI.get(k), CWD)
            for f in fso:
                if meas(f):
                    block('R1_path', f)
            if k != 'pattern':
                h = content_hit(fso)                            # (R2) 그 밖의 읽기 도구도 같은 내용 재도출
                if h:
                    block(h[0], h[1])


check()
sys.stdout.buffer.write(b'ALLOW')
#<<AGRG_PY_END>>
AGRG_PY
