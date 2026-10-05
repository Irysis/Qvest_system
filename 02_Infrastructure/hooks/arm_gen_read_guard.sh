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
#     ★(D-E-CATALOG-BASIS 2026-09-25) 위 "의미 정보" 파일은 **수치를 가린 사본으로** 연다 — 아래 R5.
#   (R2 적대 검증 수리 2026-09-25) 운영 실경로로 통과가 실증된 우회 넷을 닫는다 —
#     ① 좁힌 glob 디렉터리 Grep: 순회(_walk)가 이름만 봐서 R1_content 가 Read 에서 막는 파일을 통과시켰다 → 순회도 내용 판정(R2_walk_content)
#     ② 내용 층 확장자: 입력 형태 하나의 끝 확장자만 봐서 8.3 짧은 이름(.JSO)·백업 접미사(.json.bak_*)·BOM 머리가 비껴갔다 → 모든 형태·접미사 안쪽·BOM 제거
#     ③ 구역 밖 디렉터리 Grep: 순회 없이 통과 → 저장소 루트 아래 · 열린 경로 밖이면 범위 자체를 순회
#     ④ 같은 수치의 사본: 공리 distilled·candidates·review_log·deprecated · 설계 캐시 재료·프롬프트(.txt) · 스케줄러 로그 → STATS_RE ⑤.
#        열린 경로 qepm/memory/axioms/ → qepm/memory/axioms/active/ 로 좁힘(설정). 설계 산출 되읽기(design_r*.json·*.mechanism.json·
#        블록 설계 json)는 남은 위험 — 교차 entry 수치 사본이지만 레인이 제 산출을 되읽으므로 entry 식별 표식 없이는 가를 수 없다.
#        → (D-E-CATALOG-BASIS) R5 가 닫는다: entry 를 가를 필요 없이 **모든** 되읽기를 수치 가린 사본으로 돌린다.
#
# (D-E-CATALOG-BASIS 2026-09-25 · 도훈 결정 · pit.md C1 D-E) R5 카탈로그 사본 — "의미 정보" 파일의 basis·note 안 성과 수치.
#   왜: 위 "열어 두는 것" 파일들이 서술 필드에 전기간 측정값을 담고 있었다(09-25 운영 전수 — overlay_catalog basis "Calmar 중앙값 …
#     최악(0.160)" · weight_catalog prior_measured "IR·PORT_t·abs_CAGR" · factor_registry dedup.reason "port_t +0.194 vs -0.106" ·
#     격자 cells.basis "promo4 PORT_t · Calmar · OOS" · 설계 산출 design_r*/블록 설계/기전 json 의 rationale·why 전부 ·
#     증류 지식 색인 06_Registry/distilled_knowledge.json — 원천 distilled/ 는 R2 가 막았는데 같은 문장의 색인 사본이 열려 있었다).
#     transcript 전수(09-25 · 설계 레인 214세션 = B5 12·B1 27·기전 175 + 생성 레인 17세션): B5 설계가 overlay_catalog 를 Read 3·Grep 6(그중 Read 1건이 Calmar 0.160 수신) ·
#     형제·부모 entry 의 design_r*.json 13·블록 설계 json 8(PORT_t 3.592 수신) · 기전 레인이 남의 기전 json 3(전부 수치 수신) ·
#     생성 레인이 overlay_catalog Read 3(전부 Calmar 0.160 수신) · B1 설계가 factor_registry 를 팩터 id 로 Grep 8.
#   어떻게 — 방식 (b) 가린 사본(정본 무수정): 레인은 **파일을 직접 조회**한다(id·kind·status 로 Grep · 창 Read · 형제 설계 Read) —
#     재료 인라인(방식 a)은 이 조회를 대체하지 못한다(등록부 573KB · 설계 산출 수백 건 · B5 재료는 이미 basis 200자 절단판을 싣는다).
#     그래서 정본 조회를 막고 **같은 구조의 사본**을 그 자리에서 만들어 경로를 알려 준다 — 레인은 같은 pattern 으로 사본을 조회한다.
#     · 대상 = 설정 catalog_view.targets(저장소 루트 기준 · .claude/worktrees/<w>/ 사본 포함 · junction 실경로 → 저장소 경로로 되돌려 대조)
#     · 판정 = 대상 파일의 사본이 정본과 다를 때(= 가릴 수치가 있을 때)만 막는다 — 수치 없는 대상(arm json 20/24)은 정본 그대로 연다.
#       Read · 파일 Grep(내용 모드) → R5_catalog · 디렉터리 Grep(내용 모드)이 수치 있는 대상을 덮으면 → R5_catalog_scope.
#       files_with_matches·count 모드는 이름·개수만 돌려준다 — 막지 않는다(코드 위치 찾기 Grep 이 레인 Grep 의 대부분이다 · 남은 위험: 신탁).
#     · 가림 = 정본 규칙 rf_b1_design_lib.R 의 RF_B1_STAT_* 를 **이름으로** 싣는다(사본 없음 · B5M 과 같은 적재 양성 대조 카나리아).
#       JSON 문자열 = 전부 가림(keep_keys = 이름·정의·계열 등 정의 필드만 그대로) · JSON 수치 = 성과·통계 키(content_guard.keys ∪ stat_keys)만.
#       비 JSON(실행 출력 .out·.tsv) = 줄마다 가림. 가린 뒤 잔존 수치가 있으면 사본을 내지 않고 막는다(R5_catalog_residual).
#     · 사본 = <루트>/<view_dir>/<상대경로의 / → __> (머리 _design_view = 원본 경로·sha256·가린 곳 수) · 사본 디렉터리는 content_guard 열린 경로.
#   fail-closed: 설정 판독 불능 = 데이터 파일 Read·내용 Grep block(R5_catalog_policy) · 가림 규칙 적재 실패 = 대상 전부 block(R5_catalog_redactor) ·
#     사본 생성 실패 = block(R5_catalog_error) · 판정기(파이썬) 부재 = bash 거울 CATALOG_FALLBACK_RE 가 대상 이름으로 block.
#   적용 레인 = 설정 catalog_view.lanes(설계 레인 + 생성 레인 — 생성기도 "성과를 보지 않는다" 가 이 훅의 첫 약속이다).
#   (CATB 적대 검증 수리 09-25) 통과가 실증된 우회 셋을 닫았다 — ① 대상 밖 사본(.cache/factor_db/factor_registry.json = 정본과 바이트
#     동일 · rf_factor_arms.R 가 읽는 경로 · .cache/_dk_backup.json 증류 색인 백업) → 설정 targets ② 장치·루프백 UNC 표기(\\?\C:\ ·
#     \\.\C:\ · \\localhost\C$\ — Read 도구가 연다 · 루트 상대 대조를 비껴갔다) → forms() 의 _devform ③ 이 가드 자신의 파일(훅 머리 주석 ·
#     설정 근거 · 검사 픽스처가 누출 실례를 원문 인용 — 막힌 레인이 '왜 막혔나' 를 읽으면 그대로 받는다) → 설정 targets(사본으로).
#
# 발화 조건: QVEST_ARM_GEN=1 ∨ QVEST_DESIGN_LANE=1 일 때만. 평시에는 첫 줄에서 통과 — 소음 0.
# 검사: 08_Tests/hooks/test_arm_gen_read_guard.sh (위반 주입 · 평시 음성 · 정당 경로 · 우회 3종 · 돌연변이 · 레인 배선 ·
#       §N R2 순회 — 표본 밖 측정 파일 좁힌 glob · 코드 면제 · 디렉터리 glob · 예산 초과 · 설정 부재 ·
#       §O 전기간 통계(R2 2026-09-25) — 이름·구역·내용 3층 block · 의미 정보 pass · 설정 부재 fail-closed · 돌연변이 ·
#       §Q 카탈로그 사본(D-E-CATALOG-BASIS) — 수치 0 · 정의 보존 · 정본 sha 불변 · 비표식 무변화 · 파이썬↔R 가림 동치 · 돌연변이)
# 설정: 02_Infrastructure/hooks/policies/arm_gen_read_guard.json (R2 순회 상한·코드 확장자 · content_guard · catalog_view — 근거 병기)
#
# (FA-CLEAN-BASE-PATH 2026-09-26 · 도훈 결정 (나) 기존 레인 강화) 무인 충실구현 레인 **청정 모드** — 표식 QVEST_CLEAN_LANE=1.
#   왜: A 경로 청정 기저(F_A · rf_clean_base.R)는 "엔진을 쓴 에이전트가 성과를 보지 않았다" 를 전사에서 재도출한다. 충실구현 레인
#   (rf_replication_auto.sh)은 이 훅이 안 걸리는 레인이었다 — Read/Grep 경로 제한이 없어 원장·산출물·다른 전략 엔진(주석의 실측
#   PORT_t·Calmar — 09-26 전수: 결합 엔진 5건)·기억을 열 수 있었고, 청정 판정은 전사 사후 검사뿐이었다(막는 층 0).
#   무엇을: 청정 모드에서만 R6 을 기존 규칙(R1·R1_content·R2·R3·R5) **앞에** 건다 —
#     R6_target  대상 문자열(file_path·path·pattern·glob = 사후 검사와 같은 키)이 청정 규칙 설정의 성과 경로 정규식
#                (clean_base_rule.config.json exposure.transcript.perf_path_regex 사본 · 동기화 가드 = test_rf_clean_lane.sh)에 걸리면 block
#     R6_scope   Read·Grep 대상이 저장소 안인데 허용 목록(policies clean_lane.read_allow — 항목마다 근거) 밖이면 block. 작업 디렉터리
#                (QVEST_CLEAN_WDIR — 레인이 싣는다)는 항상 열린다. Grep 은 **검색 뿌리**가 허용 디렉터리 안이어야 한다(뿌리 = 루트·04_Research 등은 범위가 넓다)
#     R6_outside 저장소 밖 경로(~/.claude/plans · /tmp 등 — 계획서·로그에 실측 수치) Read·Grep·Glob → block
#     Glob 은 이름만 돌려준다 — 저장소 안이면 R6_target·R3(기억 카드)만 본다(내용은 Read/Grep 이 막는다)
#   증명(사후 검사가 전사에서 재도출): 청정 모드의 통과 출력은 '{}' 가 아니라 {"continue":true}(표준 필드 · 기본값 그대로 = 동작 무변화)다.
#     전사 hook_success(toolUseID 짝)의 stdout 이 이 값이면 "이 호출은 청정 가드가 판정했다" — 차단은 tool_result 의
#     'ARM_GEN_READ_BLOCKED[…clean_lane…]' 로 남는다. rf_clean_base.R 이 청정을 주장하는 실행의 Read/Grep/Glob 전부에 둘 중 하나를 요구한다.
#   fail-closed: 청정 모드에서 판정기(파이썬) 실패·설정 판독 불능 = 전부 block(R6_policy · bash _deny_const clean_lane).
#   알려진 경계(막지 않는다 · 결정문): CLI 가 cwd 에서 자동 주입하는 규칙 파일(CLAUDE.md · .claude/rules — pit.md 사고 수치 등)과
#     허용 목록 코드 주석의 과거 수치(설정 read_allow_boundary 에 실측 목록) — 기록만 한다(rf_clean_base.R 이 전사에서 지문을 재도출).
#==============================================================================
set -uo pipefail

# ★평시 무발화 — 생성·설계·청정 세션이 아니면 아무것도 하지 않는다.
if [ "${QVEST_ARM_GEN:-0}" != "1" ] && [ "${QVEST_DESIGN_LANE:-0}" != "1" ] && [ "${QVEST_CLEAN_LANE:-0}" != "1" ]; then echo '{}'; exit 0; fi
# (FA-CLEAN-BASE-PATH) 청정 모드 통과 출력 = 증명 표식(표준 필드 continue 의 기본값 — 동작 무변화). 사후 검사 정본 = clean_base_rule.config.json
#   exposure.transcript.guard_attestation.pass_stdout (동기화 가드 = test_rf_clean_lane.sh). 설계·생성 레인 통과는 구판 그대로 '{}'.
PASS_OUT='{}'
[ "${QVEST_CLEAN_LANE:-0}" = "1" ] && PASS_OUT='{"continue":true}'

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
#   ⑥ [제안 · 적대검증 PIT 10-03] O0a 결정 기록·시행 로그·유기체 상태 — O0a 생산자(rf_trial_producers.R)가 블록 승자·바닥 후보마다
#      전기간 선택 지표 값(features.value)·순위를 rf_decisions.jsonl 에, 기각 순서(= 전기간 순위)를 rf_trial_log.jsonl 에 남긴다 =
#      교차 entry 수치·순위(D-E-B5-MATERIALS '수치를 가리고 순위를 제거') · 구조 키가 value·rank 라 내용 층(R1_content)도 못 잡는다(실증).
#      06_Registry/organic/ 은 설계 §5 'LLM 권한'(scorecard 포함 — 기존 훅 확장)이 요구한 구역이다.
STATS_RE+='|rf_decisions\.jsonl|rf_trial_log\.jsonl|06_registry/organic/'
MEASURE_RE="${MEASURE_RE}|${STATS_RE}"
# ★(D-E-CATALOG-BASIS 2026-09-25) R5 의 fail-closed 거울 — 판정기(파이썬)가 죽으면 카탈로그 대상 이름을 막는다(정상 경로는 파이썬이
#   수치 가린 사본으로 돌린다). 정본 = policies/arm_gen_read_guard.json::catalog_view.targets — 검사 §Q(Q28)가 대상마다 이 식에
#   걸리는지 재도출한다(표류 방지). MEASURE_RE 에 넣지 않는다 — 넣으면 정상 경로에서도 R1_path 가 사본 안내 없이 막는다.
CATALOG_FALLBACK_RE='overlay_catalog\.json|weight_catalog\.json|reinforce_program\.json|reinforce_auto_config\.json|distilled_knowledge\.json|factor_registry\.json|\.arm\.json|rf_(b1_design|b5_design|block_design|lcode_mech)/|_dk_backup|arm_gen_read_guard\.(sh|json)'

_log() { echo "[$(date -Iseconds)] BLOCK ${1:0:400}" >> "$LOG" 2>/dev/null || true; }

# 판정기 없이 막을 때 — 사유는 고정 문자열(경로를 JSON 에 넣지 않는다 = 항상 유효 JSON)
_deny_const() {
  if [ "${QVEST_CLEAN_LANE:-0}" = "1" ]; then   # (FA-CLEAN-BASE-PATH) 청정 표식 — 사후 검사가 차단 결과를 청정 가드의 것으로 알아보게 레인 이름을 싣는다
    printf '{"decision":"block","reason":"ARM_GEN_READ_BLOCKED[clean_lane · fail_closed · %s]: 판정기(파이썬) 실패 — 청정 충실구현 레인은 판별 불능이면 전부 막는다(결정 FA-CLEAN-BASE-PATH). 작업 디렉터리 파일만 다시 시도하라."}\n' "$1"
  else
    printf '{"decision":"block","reason":"ARM_GEN_READ_BLOCKED[fail_closed · %s]: 판정기(파이썬) 실패 — 생성·설계 레인은 판별 불능이면 막는다. 측정 산출물이 아닌 파일을 Read 로 좁혀 다시 시도하라."}\n' "$1"
  fi
  _log "fail_closed $1"
  exit 0
}

INPUT=$(cat)

# ★fail-closed — 생성·설계 세션 안에서 판별 불능이면 막는다(평시엔 위에서 이미 빠져나갔다).
_fail_closed() {
  trap - ERR
  # (FA-CLEAN-BASE-PATH) 청정 모드는 판정기 없이는 아무것도 열지 않는다(허용 목록·작업 디렉터리 판정은 파이썬만 한다).
  if [ "${QVEST_CLEAN_LANE:-0}" = "1" ]; then _deny_const "clean_lane_judge"; fi
  local hay
  hay="$(printf '%s' "${INPUT:-}" | tr '\\' '/' | tr -s '/' | tr 'A-Z' 'a-z')"
  if printf '%s' "$hay" | grep -qE "$MEASURE_RE"; then _deny_const "path"; fi
  if printf '%s' "$hay" | grep -qE "$CATALOG_FALLBACK_RE"; then _deny_const "catalog"; fi
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
if [ "$RC" -eq 0 ] && [ "${AGRG_SELFTEST:-0}" = "1" ]; then case "$OUT" in '{"regions"'*|'{"redact_probe"'*) printf '%s\n' "$OUT"; exit 0 ;; esac; fi
if [ "$RC" -eq 0 ] && [ "$OUT" = "ALLOW" ]; then printf '%s\n' "$PASS_OUT"; exit 0; fi
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
import json, os, re, sys, posixpath, time, hashlib

raw = sys.stdin.buffer.read().decode('utf-8', 'replace')
D = json.loads(raw)
TOOL = str(D.get('tool_name') or '')
TI = D.get('tool_input') or {}
if not isinstance(TI, dict):
    TI = {}
MRE = re.compile(os.environ['AGRG_MEASURE_RE'], re.I)
_des = os.environ.get('QVEST_DESIGN_LANE') == '1'
_arm = os.environ.get('QVEST_ARM_GEN') == '1'
_cln = os.environ.get('QVEST_CLEAN_LANE') == '1'          # (FA-CLEAN-BASE-PATH 2026-09-26) 청정 충실구현 레인
LANE = 'arm_gen+design_lane' if (_des and _arm) else ('design_lane' if _des else ('arm_gen' if _arm else ''))
if _cln:
    LANE = (LANE + '+clean_lane') if LANE else 'clean_lane'   # 사후 검사가 차단 결과를 청정 가드의 것으로 알아보는 표식(대괄호 안 clean_lane)
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


_LOOPBACK = ('localhost', '0--1.ipv6-literal.net', (os.environ.get('COMPUTERNAME') or '').lower() or 'localhost')


def _devform(n):
    # (CATB 적대 검증 수리 2026-09-25) 장치·루프백 UNC 표기 → 드라이브 경로 — //?/c:/ · //./c:/ · //?/unc/<호스트>/c$/ · //<호스트>/c$/
    #   (호스트 = localhost · 127.x · ::1 · 이 PC 이름). Read 도구는 이 표기로 정본을 연다(09-25 실증). real() 은 '?' 를 글롭 문자로 보고
    #   건너뛰고 UNC 는 실경로로 안 바뀌어 저장소 루트 상대 대조(R5 대상 · 열린 경로)가 비껴갔다. 못 바꾸면 None(= 구판과 같다).
    m = re.match(r'^//(?:[?.]/)?unc/', n)
    if m:
        n = '//' + n[m.end():]
    m = re.match(r'^//(?:[?.]/)?([a-z]:)(/.*)?$', n)                    # norm 의 normpath 가 //./c:/ 의 '.' 을 접어 //c:/ 로 온다
    if m:
        return m.group(1) + (m.group(2) or '/')
    m = re.match(r'^//([^/]+)/([a-z])\$(/.*)?$', n)
    if m and (m.group(1) in _LOOPBACK or re.match(r'^127\.\d+\.\d+\.\d+$', m.group(1))):
        return m.group(2) + ':' + (m.group(3) or '/')
    m = re.match(r'^//(?:[?.]/)?(volume\{[0-9a-f-]+\}(?:/.*)?)$', n) or re.match(r'^//[?.]/(.+)$', n)
    if m:
        try:                                                    # 볼륨 GUID(\\?\Volume{…}\) 등 — 운영체제가 드라이브 경로로 푼다
            r = _slash(os.path.realpath(win('//?/' + m.group(1)))).lower()
            r = r[4:] if r.startswith('//?/') else r
            if re.match(r'^[a-z]:/', r):
                return r
        except Exception:
            pass
    return None


def forms(p, base):
    n = norm(p, base)
    if not n:
        return []
    d = _devform(n) if n.startswith('//') else None
    r = real(d or n)
    return [n] + ([d] if d and d != n else []) + ([r] if r and r not in (n, d) else [])


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


_JALIAS = None


def _junction_alias():
    # (D-E-CATALOG-BASIS) 저장소 루트 바로 아래의 junction·symlink 디렉터리 → (실경로, 저장소 경로) — 운영 .cache → C:/qm_cache.
    #   실경로로 들어온 입력을 저장소 상대경로로 되돌려 열린 경로(사본 디렉터리)·대상 대조에 쓴다. 못 읽으면 빈 목록(= 구판과 같다).
    global _JALIAS
    if _JALIAS is None:
        al = []
        for r in ROOTS:
            try:
                it = list(os.scandir(win(r.rstrip('/'))))
            except Exception:
                continue
            for e in it:
                try:
                    isd = e.is_dir()
                except Exception:
                    isd = False
                if isd:
                    p = r.rstrip('/') + '/' + e.name.lower()
                    rp = real(p)                       # 실경로가 다르면 junction·symlink(판별 API 판본 차이에 기대지 않는다)
                    if rp and not rp.startswith(r.rstrip('/') + '/') and (rp.rstrip('/'), p) not in al:
                        al.append((rp.rstrip('/'), p))
        _JALIAS = al
    return _JALIAS


def _canon(n):
    for rp, p in _junction_alias():
        if n == rp or n.startswith(rp + '/'):
            return p + n[len(rp):]
    return n


def _rel_any(n):
    # 루트 상대경로 — 실경로(junction 대상)로 들어와도 저장소 경로로 되돌려 잰다
    r = _root_rel(n)
    return r if r is not None else _root_rel(_canon(n))


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
        rel = _rel_any(f)                                        # (D-E-CATALOG-BASIS) junction 실경로도 저장소 경로로 되돌려 잰다
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


# ── (D-E-CATALOG-BASIS 2026-09-25) R5 카탈로그 사본 — 정본은 닫고 수치를 가린 사본을 연다 ─────────────────────────────
#   가림 규칙 = rf_b1_design_lib.R 의 RF_B1_STAT_* (R2 정본) 를 **이름으로** 싣는다 — 파이썬 사본 규칙을 두지 않는다(두 벌이 갈리면
#   한쪽만 새는 구멍이 된다 · B5M .b5_redactor 와 같은 원칙). 아래는 R 문자열 리터럴 해석기 + 같은 알고리즘(보호 → 규칙 → 지표 정수 → 복원)이고,
#   동치성은 검사 §Q(Q29 — 같은 문자열을 R rf_b1_redact_stats 와 이 판정기에 넣어 대조)가 잰다.
_RX_NAMES = ('RF_B1_STAT_PROTECT', 'RF_B1_STAT_RULES', 'RF_B1_STAT_METRIC', 'RF_B1_STAT_MASK')
#   적재 양성 대조 카나리아 — B5M(rf_b5_design_lib.R B5_RX_CANARY)과 같은 문자열·같은 조건(가림이 실제로 가리고 식별자를 보존한다)
_RX_CANARY = 'B5_22 xs_vol_gap_corr_brake Calmar 0.763 · MDD 0.287~0.615 · 폭 5.5%p · PORT_t 3 · arXiv 2002.06975 · v10.4'
_RX_CANARY_KEEP = ('B5_22 xs_vol_gap_corr_brake', '2002.06975', 'v10.4')
_RX_CANARY_GONE = '0.763'
_R_ESC = {'\\': '\\', '"': '"', "'": "'", 'n': '\n', 't': '\t', 'r': '\r', '0': '\0', 'a': '\a', 'b': '\b', 'f': '\f',
          'v': '\v', '`': '`', ' ': ' '}


def _r_unescape(body):
    out, i, n = [], 0, len(body)
    while i < n:
        c = body[i]
        if c != '\\':
            out.append(c)
            i += 1
            continue
        if i + 1 >= n:
            raise ValueError('dangling escape')
        e = body[i + 1]
        if e in _R_ESC:
            out.append(_R_ESC[e])
            i += 2
            continue
        if e in 'uUx':
            j = i + 2
            if j < n and body[j] == '{' and e != 'x':
                k = body.index('}', j)
                out.append(chr(int(body[j + 1:k], 16)))
                i = k + 1
                continue
            m = re.match(r'[0-9A-Fa-f]{1,%d}' % {'x': 2, 'u': 4, 'U': 8}[e], body[j:])
            if not m:
                raise ValueError('bad hex escape')
            out.append(chr(int(m.group(0), 16)))
            i = j + len(m.group(0))
            continue
        raise ValueError('unknown escape')
    return ''.join(out)


def _r_scan(src):
    # R 소스 → (주석을 지우고 문자열 리터럴을 \x00N\x00 로 바꾼 텍스트, 리터럴 값 목록) — 문자열 안의 # 은 주석이 아니다
    lits, out, i, n = [], [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '#':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            if j >= n:
                raise ValueError('unterminated string')
            lits.append(_r_unescape(src[i + 1:j]))
            out.append('\x00%d\x00' % (len(lits) - 1))
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out), lits


def _rx_redact(R, s):
    if not s:
        return s
    keep = []
    for rx in R['protect']:
        for h in [m.group(0) for m in rx.finditer(s)]:
            keep.append(h)
            s = s.replace(h, '⟦%d⟧' % len(keep), 1)
    for rx in R['rules']:
        s = rx.sub(R['mask'], s)
    s = R['metric'].sub(lambda m: m.group(1) + m.group(2) + R['mask'], s)
    for k in range(len(keep), 0, -1):
        s = s.replace('⟦%d⟧' % k, keep[k - 1], 1)
    return s


def _rx_has(R, s):
    if not s:
        return False
    for rx in R['protect']:
        s = rx.sub(' ', s)
    return any(rx.search(s) for rx in R['rules'] + [R['metric']])


def _rx_load(path):
    # 정본 파일에서 네 이름의 최상위 대입만 읽는다(평가 없음 · 부수효과 0). 이름이 없거나 둘이거나 리터럴이 아니면 예외(= 호출자 fail-closed).
    txt, lits = _r_scan(open(path, encoding='utf-8').read())
    got = {}
    for nm in _RX_NAMES:
        ms = list(re.finditer(r'(?m)^' + re.escape(nm) + r'[ \t]*(<-|=)[ \t]*', txt))
        if len(ms) != 1:
            raise ValueError('assignment count %s' % nm)
        k = ms[0].end()
        if txt.startswith('c(', k):
            dep, j = 0, k + 1
            while j < len(txt):
                if txt[j] == '(':
                    dep += 1
                elif txt[j] == ')':
                    dep -= 1
                    if dep == 0:
                        break
                j += 1
            vals = []
            for part in txt[k + 2:j].split(','):
                m = re.fullmatch(r'\s*(?:[A-Za-z_.][A-Za-z0-9_.]*\s*=\s*)?\x00(\d+)\x00\s*', part)
                if not m:
                    raise ValueError('non-literal element %s' % nm)
                vals.append(lits[int(m.group(1))])
            if not vals:
                raise ValueError('empty %s' % nm)
            got[nm] = vals
        else:
            m = re.match(r'\x00(\d+)\x00[ \t]*(\n|;|$)', txt[k:])
            if not m:
                raise ValueError('non-literal scalar %s' % nm)
            got[nm] = lits[int(m.group(1))]
    F = re.ASCII                                                # R perl=TRUE(UCP 없음) = \d·\s ASCII
    R = dict(protect=[re.compile(v, F) for v in got['RF_B1_STAT_PROTECT']],
             rules=[re.compile(v, F) for v in got['RF_B1_STAT_RULES']],
             metric=re.compile(got['RF_B1_STAT_METRIC'], F), mask=got['RF_B1_STAT_MASK'])
    if not isinstance(R['mask'], str) or not R['mask'] or re.search('[0-9]', R['mask']) or R['metric'].groups < 2:
        raise ValueError('bad mask/metric')
    rc = _rx_redact(R, _RX_CANARY)
    if not _rx_has(R, _RX_CANARY) or _rx_has(R, rc) or R['mask'] not in rc or _RX_CANARY_GONE in rc \
            or not all(x in rc for x in _RX_CANARY_KEEP):
        raise ValueError('canary')
    R['fp'] = hashlib.sha256(json.dumps(got, ensure_ascii=False, sort_keys=True).encode('utf-8')).hexdigest()
    return R


_CVP = None
# 설정 판독 불능일 때만 쓰는 보수적 기본(fail-closed) — 대상이 될 수 있는 텍스트 데이터 확장자. 정상 경로의 대상은 전부 설정에서 온다.
_CV_FAILCLOSED_EXT = ('.json', '.jsonl', '.csv', '.tsv', '.txt', '.out')


def _cvpolicy():
    # 설정 = policies/arm_gen_read_guard.json::catalog_view(+ content_guard.keys 를 성과 키로 재사용). 판독 불능 = False(호출자 fail-closed).
    #   가림 규칙 적재 실패는 설정 불능과 가른다: rx=None(= 대상만 fail-closed · 대상 아닌 파일은 영향 없음).
    global _CVP
    if _CVP is None:
        try:
            hd = os.path.dirname(os.path.abspath(sys.argv[1]))
            d = json.load(open(os.path.join(hd, 'policies', 'arm_gen_read_guard.json'), encoding='utf-8'))
            c = d['catalog_view']
            lanes = set(str(x) for x in c['lanes'])
            tg = [str(x).lower().replace(chr(92), '/').strip('/') for x in c['targets']]
            vdir = str(c['view_dir']).lower().replace(chr(92), '/').strip('/')
            keep = frozenset(str(x) for x in c['keep_keys'])
            sk = [str(x) for x in d['content_guard']['keys']] + [str(x) for x in c['stat_keys']]
            pol = dict(lanes=lanes, targets=[(t, _gre(t)) for t in tg], vdir=vdir, keep=keep,
                       prx=re.compile('^(?:' + '|'.join(sk) + ')$', re.I), wt=re.compile(str(c['worktree_prefix'])),
                       maxv=int(c['max_views_per_call']), maxb=int(c['max_source_bytes']), maxp=int(c['max_view_path']),
                       passes=int(c['redact_passes']),
                       rsrc=os.path.normpath(os.path.join(hd, str(c['redactor_source']))))
            if not lanes or not lanes <= {'design_lane', 'arm_gen', 'clean_lane'} or not tg or not vdir or any(ch in vdir for ch in GLOBCH) \
                    or pol['maxv'] <= 0 or pol['maxb'] <= 0 or pol['maxp'] <= 0 or pol['passes'] < 1 or not sk:
                raise ValueError('bad catalog_view')
            try:
                pol['rx'] = _rx_load(pol['rsrc'])
            except Exception:
                pol['rx'] = None
            pol['fp'] = hashlib.sha256(json.dumps([c, sk, (pol['rx'] or {}).get('fp')], ensure_ascii=False,
                                                  sort_keys=True, default=str).encode('utf-8')).hexdigest()
            _CVP = pol
        except Exception:
            _CVP = False
    return _CVP


def _cv_active():
    # None = 이 레인에는 적용 안 함 · False = 설정 불능(fail-closed) · dict = 적용
    cv = _cvpolicy()
    if cv is False:
        return False
    return cv if ((_des and 'design_lane' in cv['lanes']) or (_arm and 'arm_gen' in cv['lanes'])
                  or (_cln and 'clean_lane' in cv['lanes'])) else None


def _under_roots(n):
    return any(n.startswith(r.rstrip('/') + '/') for r in ROOTS)


def _cv_locate(n, cv):
    # 정규화 경로 → (저장소 루트, 루트 상대경로, 대상 대조용 상대경로 = .claude/worktrees/<w>/ 를 벗긴 것) | None
    #   루트 밖일 때만 junction 실경로를 되돌린다(_canon = 루트 최상위 디렉터리 실경로 조회 — 매 호출 비용을 피한다)
    n = n if _under_roots(n) else _canon(n)
    for r in ROOTS:
        rr = r.rstrip('/')
        if n.startswith(rr + '/'):
            rel = n[len(rr) + 1:]
            m = cv['wt'].match(rel)
            return rr, rel, (rel[m.end():] if m else rel)
    return None


def _cv_is_target(trel, cv):
    return any(rx.match(trel) for _, rx in cv['targets'])


class _CvErr(Exception):
    pass


def _cv_red(R, s, cv):
    # 정본 가림을 잔존이 없을 때까지(설정 redact_passes 회 이내) 거듭 — 한 번이면 세 마디 판본("2.1.170")이 "<stat>.170" 을 남긴다
    #   (09-25 운영 설정 6곳). B1·B5M 재료의 "절단 앞뒤 2회" 와 같은 멱등 반복이다. 그래도 남으면 호출자가 잔존으로 센다(fail-closed).
    r = _rx_redact(R, s)
    k = 1
    while k < cv['passes'] and _rx_has(R, r):
        r = _rx_redact(R, r)
        k += 1
    return r


def _cv_mask_obj(o, key, cv, R, st):
    if isinstance(o, dict):
        out = {}
        for k, v in o.items():
            if _rx_has(R, str(k)):
                st[1] += 1                                      # 키에 든 수치는 가리면 키가 바뀐다 — 사본을 내지 않는다(잔존)
            out[k] = _cv_mask_obj(v, k, cv, R, st)
        return out
    if isinstance(o, list):
        return [_cv_mask_obj(v, key, cv, R, st) for v in o]
    if isinstance(o, str):
        if key in cv['keep']:
            return o                                            # 정의 필드(이름·정의·계열) — 그대로
        r = _cv_red(R, o, cv)
        if r != o:
            st[0] += 1
        if _rx_has(R, r):
            st[1] += 1
        return r
    if isinstance(o, bool) or o is None:
        return o
    if isinstance(o, (int, float)) and key is not None and cv['prx'].match(str(key)):
        st[0] += 1
        return R['mask']                                        # 성과·통계 키의 수치(port_t · calmar · cor …)
    return o


def _cv_view(root, rel, src, cv):
    # 사본 계산 — 반환 dict(path, data, n) · 쓰기는 호출자(_cv_write). 크기 초과·잔존 = _CvErr(fail-closed)
    R = cv['rx']
    with open(win(src), 'rb') as fh:
        b = fh.read(cv['maxb'] + 1)
    if len(b) > cv['maxb']:
        raise _CvErr('R5_catalog_size', '%s — %d바이트 초과(설정 max_source_bytes)' % (src, cv['maxb']))
    ssha = hashlib.sha256(b).hexdigest()
    t = b.decode('utf-8', 'replace')
    if t.startswith('﻿'):
        t = t[1:]
    st = [0, 0]
    obj = None
    try:
        obj = json.loads(t)
    except Exception:
        obj = None
    note = ('D-E-CATALOG-BASIS: 수치는 %s 로 가렸다(정본 규칙 rf_b1_design_lib.R RF_B1_STAT_*). 이름·정의·계열(keep_keys)은 그대로. '
            '정본 경로는 설계·생성 레인에서 열리지 않는다 — 이 사본을 조회하라.') % R['mask']
    if obj is not None:
        body = _cv_mask_obj(obj, None, cv, R, st)
        mk = {'source': rel, 'source_sha256': ssha, 'masked': st[0], 'rule_fp': cv['fp'], 'note': note}
        body = dict([('_design_view', mk)] + list(body.items())) if isinstance(body, dict) else {'_design_view': mk, 'content': body}
        data = (json.dumps(body, ensure_ascii=False, indent=1) + '\n').encode('utf-8')
        ext = ''
    else:
        lines = []
        for ln in t.split('\n'):
            r = _cv_red(R, ln, cv)
            if r != ln:
                st[0] += 1
            if _rx_has(R, r):
                st[1] += 1
            lines.append(r)
        head = '#design_view source=%s source_sha256=%s masked=%d rule_fp=%s — %s\n' % (rel, ssha, st[0], cv['fp'], note)
        data = (head + '\n'.join(lines)).encode('utf-8')
        ext = '' if rel.endswith('.txt') else '.txt'
    if st[1]:
        raise _CvErr('R5_catalog_residual', '%s — 가린 뒤에도 수치 %d곳(키·문자열) — 사본을 내지 않는다' % (src, st[1]))
    vd = root + '/' + cv['vdir']
    nm = rel.replace('/', '__').lstrip('.') + ext
    vp = vd + '/' + nm
    if meas(vp) or len(win(vp)) > cv['maxp']:
        nm = 'v_' + hashlib.sha1(rel.encode('utf-8')).hexdigest()[:16] + ('.txt' if ext or obj is None else '.json')
        vp = vd + '/' + nm
    return dict(path=vp, data=data, n=st[0], src=src)


def _cv_write(v):
    p = win(v['path'])
    try:
        with open(p, 'rb') as fh:
            if fh.read() == v['data']:
                return
    except Exception:
        pass
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = '%s.tmp%d_%d' % (p, os.getpid(), time.perf_counter_ns())
    with open(tmp, 'wb') as fh:
        fh.write(v['data'])
    os.replace(tmp, p)


def catalog_file_hit(fs):
    # Read · 파일 Grep(내용 모드) — 대상이면서 가릴 수치가 있으면 사본을 쓰고 ('R5_catalog', 안내문) · 없으면 None(정본 그대로)
    if not fs:
        return None
    cv = _cv_active()
    if cv is None:
        return None
    if cv is False:
        return ('R5_catalog_policy', '%s — catalog_view 설정 판독 불능(fail-closed)' % fs[0]) \
            if any(_dext(f, _CV_FAILCLOSED_EXT) for f in fs) else None
    loc = None
    for f in fs:
        loc = _cv_locate(f, cv)
        if loc and _cv_is_target(loc[2], cv):
            break
        loc = None
    if not loc:
        return None
    src = next((f for f in fs if os.path.isfile(win(f))), None)
    if not src:
        return None                                             # 없는 파일은 도구도 못 연다
    if cv['rx'] is None:
        return ('R5_catalog_redactor', '%s — 가림 규칙(%s) 적재·양성 대조 실패(fail-closed)' % (src, cv['rsrc']))
    try:
        v = _cv_view(loc[0], loc[1], src, cv)
        if v['n'] == 0:
            return None
        _cv_write(v)
    except _CvErr as e:
        return (e.args[0], e.args[1])
    except Exception as e:
        return ('R5_catalog_error', '%s — 사본 생성 실패(%s · fail-closed)' % (src, type(e).__name__))
    return ('R5_catalog', dict(src=src, view=win(v['path']), n=v['n']))


def _cv_tick(n, k, cap):
    # 대상 목록 순회 예산(R2 순회와 같은 설정 r2_walk.max_entries) — 넘치면 _Budget(호출자 = R5_catalog_budget block)
    n[0] += k
    if n[0] > cap:
        raise _Budget()


def _cv_candidates(dirs, glob, typ, cv, cap):
    # 디렉터리 Grep 범위 ∩ 대상 — (루트, 루트 상대경로, 파일 경로) 목록. cap(설정 r2_walk.max_entries) 넘게 뒤지면 _Budget.
    #   대상 패턴마다 고정 접두 디렉터리만 뒤진다(마지막 성분만 와일드카드면 그 디렉터리 한 겹). 워크트리 사본 = 범위가 그 안일 때 뿌리를 더한다.
    cdirs = [(d if _under_roots(d) else _canon(d)).rstrip('/') for d in dirs]
    proots = []
    for r in ROOTS:
        rr = r.rstrip('/')
        if (rr, '') not in proots:
            proots.append((rr, ''))
        for d in cdirs:
            if d.startswith(rr + '/'):
                m = cv['wt'].match(d[len(rr) + 1:] + '/')
                if m:
                    pr = (rr, d[len(rr) + 1:][:m.end()].rstrip('/'))
                    if pr not in proots:
                        proots.append(pr)
    out, seen, n = [], set(), [0]

    def _consider(rr, wrel, f):
        f = f.rstrip('/')
        if f in seen:
            return
        seen.add(f)
        for d in cdirs:
            if f.startswith(d + '/'):
                rd = f[len(d) + 1:]
                parts = rd.split('/')
                inc = any(_dir_whitelisted('/'.join(parts[:k]), glob) for k in range(1, len(parts)))
                if _passes2(rd, glob, typ, inc):
                    out.append((rr, (wrel + '/' if wrel else '') + f[len((rr + '/' + wrel).rstrip('/')) + 1:], f))
                return
    for rr, wrel in proots:
        base_root = (rr + '/' + wrel).rstrip('/')
        if not any(base_root == d or base_root.startswith(d + '/') or d.startswith(base_root + '/') for d in cdirs):
            continue
        for pat, rx in cv['targets']:
            segs = pat.split('/')
            k = 0
            while k < len(segs) and not any(ch in segs[k] for ch in GLOBCH):
                k += 1
            sp = (base_root + '/' + '/'.join(segs[:k])).rstrip('/')
            if not any(sp == d or sp.startswith(d + '/') or d.startswith(sp + '/') for d in cdirs):
                continue
            if k == len(segs):
                if os.path.isfile(win(sp)):
                    _consider(rr, wrel, sp)
                continue
            if k == len(segs) - 1 and '**' not in pat:
                try:
                    it = list(os.scandir(win(sp)))
                except Exception:
                    continue
                for e in it:
                    _cv_tick(n, 1, cap)
                    nm = e.name.lower()
                    if rx.match('/'.join(segs[:k] + [nm])):
                        try:
                            if e.is_file():
                                _consider(rr, wrel, sp + '/' + nm)
                        except Exception:
                            pass
                continue
            for dp, dn, fn in os.walk(win(sp)):
                _cv_tick(n, len(dn) + len(fn), cap)
                dpn = _slash(dp).lower().rstrip('/')
                reldir = dpn[len(base_root) + 1:] if dpn.startswith(base_root + '/') else None
                if reldir is None:
                    continue
                for nm in fn:
                    nm = nm.lower()
                    if rx.match(reldir + '/' + nm):
                        _consider(rr, wrel, dpn + '/' + nm)
    return out


def catalog_scope_hit(dirs, glob, typ):
    # 디렉터리 Grep(내용 모드) — 범위가 수치 있는 대상을 덮으면 그 범위의 대상 사본을 **전부** 쓰고(사본 디렉터리 Grep 이 빠짐없게) block
    cv = _cv_active()
    if cv is None:
        return None
    pol = _policy()
    if cv is False or not pol:
        if pol and _code_only(glob, typ, pol['code_ext']):
            return None
        return ('R5_catalog_policy', 'catalog_view(또는 r2_walk) 설정 판독 불능 — 내용 Grep 범위 판정 불가(fail-closed)')
    if _code_only(glob, typ, pol['code_ext']):
        return None                                             # 코드만 통과시키는 필터 — 대상(데이터)을 못 덮는다
    try:
        cands = _cv_candidates([d for d in dirs if os.path.isdir(win(d))], glob, typ, cv, pol['max_entries'])
    except _Budget:
        return ('R5_catalog_budget', '범위 안 대상 목록 순회 %d항목 초과 — path 를 좁혀라' % pol['max_entries'])
    if not cands:
        return None
    if cv['rx'] is None:
        return ('R5_catalog_redactor', '범위 안 대상 %d건 — 가림 규칙(%s) 적재·양성 대조 실패(fail-closed)' % (len(cands), cv['rsrc']))
    if len(cands) > cv['maxv']:
        return ('R5_catalog_budget', '범위 안 대상 %d건 > 설정 max_views_per_call %d — path·glob 을 좁혀라' % (len(cands), cv['maxv']))
    views = []
    try:
        for rr, rel, f in cands:
            views.append(_cv_view(rr, rel, f, cv))
        numbered = [v for v in views if v['n'] > 0]
        if not numbered:
            return None
        for v in views:
            _cv_write(v)
    except _CvErr as e:
        return (e.args[0], e.args[1])
    except Exception as e:
        return ('R5_catalog_error', '범위 안 대상 사본 생성 실패(%s · fail-closed)' % type(e).__name__)
    vdirs = sorted(set(win(v['path'].rsplit('/', 1)[0]) for v in views))
    return ('R5_catalog_scope', dict(n=len(views), n_numbered=len(numbered), vdirs=vdirs,
                                     ex=[win(v['src']) for v in numbered[:3]]))


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


def block(rule, what, msg=None):
    if msg is None:
        msg = ('ARM_GEN_READ_BLOCKED[%s · %s]: %s — 생성·설계 레인은 성과를 직접 보지 않는다(측정 전 방출 · 설계는 재료만 본다). '
               '표적 칸·함수 계약·필요한 요약은 프롬프트(재료)에 이미 들어 있다. 코드·등록부를 찾으려면 범위를 좁혀라 '
               '(예: path=02_Infrastructure/… 또는 glob="*.R" · 원장·측정 산출물·기억 디렉터리는 제외).') % (LANE, rule, what)
    sys.stdout.buffer.write(json.dumps({'decision': 'block', 'reason': msg}, ensure_ascii=True, separators=(',', ':')).encode('ascii'))
    sys.exit(0)


def block_cv(h):
    # (D-E-CATALOG-BASIS) R5 안내 — 막되 **어디를 읽으면 되는지** 준다(사본 경로 · 같은 pattern 으로 조회)
    rule, what = h
    if rule == 'R5_catalog':
        block(rule, what['src'], ('ARM_GEN_READ_BLOCKED[%s · %s]: %s 는 서술 필드(basis·note·reason·rationale 등)에 성과 수치가 있다(%d곳). '
                                  '설계·생성 레인은 정본 대신 수치를 가린 사본을 읽는다 — 같은 도구·같은 pattern 으로 이 파일을 열어라: %s '
                                  '(구조·이름·정의·계열은 그대로 · 수치 = <stat> · 줄 번호는 원본과 다를 수 있다 · pit.md C1 D-E · D-E-CATALOG-BASIS).')
              % (LANE, rule, what['src'], what['n'], what['view']))
    if rule == 'R5_catalog_scope':
        block(rule, 'scope', ('ARM_GEN_READ_BLOCKED[%s · %s]: 이 Grep(내용 모드) 범위가 성과 수치가 든 카탈로그·설계 산출 %d건(예: %s)을 덮는다. '
                              '범위 안 대상 %d건의 수치 가린 사본을 만들었다 — 같은 pattern 으로 사본 디렉터리를 Grep 하라: %s '
                              '(사본 이름 = 원본 상대경로의 / → __ · glob 은 이름 끝으로 · 예 glob="*.arm.json"). 코드만 찾는다면 glob="*.R" 로 좁혀라 '
                              '(files_with_matches·count 모드는 막지 않는다 · pit.md C1 D-E · D-E-CATALOG-BASIS).')
              % (LANE, rule, what['n_numbered'], ' · '.join(what['ex']), what['n'], ' · '.join(what['vdirs'])))
    block(rule, what)


# ── (FA-CLEAN-BASE-PATH 2026-09-26) R6 청정 충실구현 레인 ────────────────────────────────────────────────────
#   설정 = policies/arm_gen_read_guard.json::clean_lane (대상 키·성과 경로 정규식 사본·허용 목록 + 항목별 근거). 판독 불능 = False(호출자 = 전부 block).
_CLP = None


def _clpolicy():
    global _CLP
    if _CLP is None:
        try:
            pth = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), 'policies', 'arm_gen_read_guard.json')
            c = json.load(open(pth, encoding='utf-8'))['clean_lane']
            keys = [str(k) for k in c['target_keys']]
            allow = []
            for it in c['read_allow']:
                p = str(it['path']).lower().replace(chr(92), '/').lstrip('/')
                if not p or '..' in p.split('/') or any(ch in p for ch in GLOBCH) or not str(it.get('why') or '').strip():
                    raise ValueError('bad read_allow entry')
                allow.append(p)
            pol = dict(keys=keys, trx=re.compile(str(c['target_regex'])), allow=tuple(allow),
                       wdir_env=str(c['wdir_env']), glob_names_in_repo=bool(c['glob_names_in_repo']))
            if not keys or not pol['wdir_env'] or not allow:
                raise ValueError('bad clean_lane')
            _CLP = pol
        except Exception:
            _CLP = False
    return _CLP


def _clean_rel(f):
    # 저장소 루트 상대경로 — 루트 자체 = '' · 루트 밖 = None (junction 실경로는 저장소 경로로 되돌려 잰다)
    f = (f or '').rstrip('/')
    if any(f == r.rstrip('/') for r in ROOTS):
        return ''
    return _rel_any(f)


def _clean_wdir():
    # 레인이 싣는 작업 디렉터리(정규화 형태 전부) — 저장소 루트 안이어야 인정한다(밖이면 없는 것으로 = 작업 디렉터리 예외 없음)
    cp = _clpolicy()
    if not cp:
        return []
    raw = os.environ.get(cp['wdir_env']) or ''
    out = []
    for f in (forms(raw, CWD) if raw.strip() else []):
        f = f.rstrip('/')
        if f and _clean_rel(f) not in (None, '') and f not in out:
            out.append(f)
    return out


def _clean_allowed(rel, is_dir):
    # 허용 목록 판정 — 디렉터리 항목(끝 '/')은 그 아래 전부, 파일 항목은 그 파일만. 디렉터리 검색(Grep 뿌리)은 허용 디렉터리 **안**이어야 한다.
    cp = _clpolicy()
    for a in cp['allow']:
        if a.endswith('/'):
            if (rel + '/').startswith(a) if is_dir else rel.startswith(a):
                return True
        elif not is_dir and rel == a:
            return True
    return False


def _glob_anchor(full):
    segs = full.split('/')
    k = 0
    while k < len(segs) and not any(ch in segs[k] for ch in GLOBCH):
        k += 1
    return '/'.join(segs[:k]).rstrip('/') or full


def clean_hit():
    # 반환 = (규칙, 무엇) | None. 기존 규칙보다 **먼저** 돈다(청정 모드는 허용 목록 밖을 아예 열지 않는다).
    cp = _clpolicy()
    if not cp:
        return ('R6_policy', 'clean_lane 설정 판독 불능(fail-closed)')
    tg = ' '.join(str(TI.get(k) or '') for k in cp['keys'])
    m = cp['trx'].search(tg)
    if m:
        return ('R6_target', m.group(0))                    # 사후 검사(rf_clean_base.R transcript_tool_reads)와 같은 키·같은 식
    own = _clean_wdir()
    if TOOL == 'Glob':
        pth = TI.get('path') or ''
        base = forms(pth, CWD) if pth else [CWD]
        for b in base:
            full = norm(str(TI.get('pattern') or ''), b)
            anc = _glob_anchor(full) if full else b
            if any(under(anc, w) for w in own):
                continue
            rel = _clean_rel(anc)
            if rel is None:
                return ('R6_outside', anc)                      # 저장소 밖 이름 열거(계획서·기억 디렉터리 등)
            if not cp['glob_names_in_repo'] and not _clean_allowed(rel, True):
                return ('R6_scope', rel or '/')
        return None
    if TOOL == 'Grep':
        pth = TI.get('path') or ''
        fs = forms(pth, CWD) if pth else ([CWD] + ([real(CWD)] if real(CWD) else []))
    else:
        fp = TI.get('file_path') or TI.get('path') or TI.get('notebook_path') or ''
        fs = forms(fp, CWD) if fp else []
    for f in fs:
        if any(under(f, w) for w in own):
            continue                                          # 작업 디렉터리 — 레인 자기 산출(엔진·FIDELITY·프롬프트)
        rel = _clean_rel(f)
        if rel is None:
            return ('R6_outside', f)
        isdir = TOOL == 'Grep' and os.path.isdir(win(f))
        if rel == '' or not _clean_allowed(rel, isdir):
            return ('R6_scope_wide' if isdir else 'R6_scope', rel or '/')
    return None


def block_clean(h):
    rule, what = h
    cp = _clpolicy() or {}
    own = _clean_wdir()
    allow = ' · '.join(cp.get('allow') or ()) or '(설정 판독 불능)'
    block(rule, what, ('ARM_GEN_READ_BLOCKED[%s · %s]: %s — 청정 충실구현 레인(결정 FA-CLEAN-BASE-PATH)은 성과·교차 entry 산출물과 허용 목록 밖 경로를 열지 않는다. '
                       '열 수 있는 것: 작업 디렉터리(%s) · 허용 목록 %s · 논문 원문은 WebFetch. Grep 은 path 를 허용 디렉터리 안으로 좁혀라. '
                       '필요한 규약은 프롬프트의 「청정 모드 — 열람 범위」 절에 있다.') % (LANE, rule, what, win(own[0]) if own else '(미지정)', allow))


if os.environ.get('AGRG_SELFTEST') == '1' and TOOL == 'AgrgRedactProbe':
    # 검사 전용(Q29) — 이 판정기가 싣는 가림 규칙으로 문자열 목록을 가린다(R rf_b1_redact_stats 와 동치 대조용). 실제 판정에는 영향 없음.
    _cp = _cvpolicy()
    _R = _cp['rx'] if _cp else None
    _xs = [str(x) for x in (TI.get('strings') or [])]
    sys.stdout.buffer.write(json.dumps({'redact_probe': bool(_R), 'rsrc': (_cp or {}).get('rsrc'),
                                        'redacted': [_rx_redact(_R, x) for x in _xs] if _R else None,
                                        'has': [_rx_has(_R, x) for x in _xs] if _R else None}, ensure_ascii=False).encode('utf-8'))
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


def _own_walk(dirs, glob, typ):
    # (FA-CLEAN-BASE-PATH) 청정 레인 작업 디렉터리 Grep — 구역 표본 대조(①)는 건너뛰고 이름+내용 순회(②)만 한다.
    #   작업 디렉터리는 04_Research/strategies(deep 구역) 아래라 표본 대조가 무필터 Grep 을 전부 막는다(자기 산출 열람 오차단).
    #   (10-03) 아래 두 문장은 scope_hit 머리와 뜻이 같지만 글자를 일부러 다르게 둔다 — 가드 검사(test_arm_gen_read_guard.sh §N)의 돌연변이가
    #   scope_hit 의 원문 1곳을 좌표로 잡는다(같은 글자가 둘이면 '치환 대상이 1곳이 아니다'). 이 함수의 예외는 test_rf_clean_lane.sh L4 가 잰다.
    pol = _policy()
    if not pol:   # 청정 작업 디렉터리 순회 — 설정 판독 불능 = fail-closed
        return ('R2_policy', 'policies/arm_gen_read_guard.json 판독 불능 — 범위 순회 불가(fail-closed)')
    if _code_only(glob, typ, pol['code_ext']):   # 코드만 통과시키는 필터 — 대상(데이터)을 못 덮는다
        return None
    st, seen = [0, time.perf_counter()], set()
    try:
        for d in dirs:
            if os.path.isdir(win(d)):
                h = _walk(d, '', glob, typ, pol, st, seen)
                if h:
                    return h
    except _Budget:
        return ('R2_scope_budget', '순회 %d항목 초과 — path 를 좁혀라' % (st[0] - 1))
    return None


def check():
    if _cln and TOOL not in _WRITE_TOOLS and TOOL not in ('Bash', 'PowerShell'):
        h = clean_hit()                                         # (FA-CLEAN-BASE-PATH) R6 — 기존 규칙보다 먼저
        if h:
            block_clean(h)
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
        if TOOL not in _WRITE_TOOLS:
            h = catalog_file_hit(fsr)                           # (D-E-CATALOG-BASIS) R5 — 수치 있는 카탈로그·설계 산출은 사본으로
            if h:
                block_cv(h)
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
        own = _clean_wdir() if _cln else []
        if own and fs and all(any(under(f, w) for w in own) for f in fs):
            h = _own_walk(fs, TI.get('glob') or '', TI.get('type') or '')   # (FA-CLEAN-BASE-PATH) 작업 디렉터리 = 순회만
        else:
            h = scope_hit(fs, TI.get('glob') or '', TI.get('type') or '')
        if h:
            block(h[0], h[1])
        # (D-E-CATALOG-BASIS) R5 — 내용 모드만(files_with_matches·count = 이름·개수만 돌려준다 · 도구 기본값 = files_with_matches)
        if str(TI.get('output_mode') or '') == 'content':
            if any(os.path.isfile(win(f)) for f in fs):
                h = catalog_file_hit(fs)
            else:
                h = catalog_scope_hit(fs, TI.get('glob') or '', TI.get('type') or '')
            if h:
                block_cv(h)
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
                if TOOL not in _WRITE_TOOLS:
                    h = catalog_file_hit(fso)                   # (D-E-CATALOG-BASIS) R5 — 그 밖의 읽기 도구도 사본으로
                    if h:
                        block_cv(h)


_WRITE_TOOLS = ('Write', 'Edit', 'MultiEdit', 'NotebookEdit')   # R5 는 읽기만 돌린다 — 레인이 제 설계 파일을 쓰는 것은 막지 않는다
check()
sys.stdout.buffer.write(b'ALLOW')
#<<AGRG_PY_END>>
AGRG_PY
