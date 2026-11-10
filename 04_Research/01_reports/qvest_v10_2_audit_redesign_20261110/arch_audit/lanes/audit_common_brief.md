# Qvest v10.2 전체 아키텍처 감사 — 공통 지침 (모든 감사 레인이 먼저 읽는다)

작업 폴더 = `G:/OneDrive/Quant_Module_Moltbot` (Windows 11 · Git Bash + PowerShell). 응답 · 보고는 한국어 존댓말, 표준 기술 용어.
스크래치 = `C:/Users/User/AppData/Local/Temp/claude/bded445ba19315c7/9fe22a2f-3836-40d8-8087-87fddf9c12ec/scratchpad/` (아래 `<SCR>`).

## 1. 사용자(도훈) 지시 원문 — 2026-11-10

> Qvest 시스템 아키텍처 전체에 대한 감사(데이터 리프레시, DB관리, 모닝브리핑, 논문수집, 1계층리서치, 1계층리서치 강화체인, 2계층 리서치, 2계층 리서치 강화체인, 전략리서치 결과에 기반한 사후 지식축적 및 해당 지식 활용을 통한 재귀적 개선루프, BOOK(실운용 승격전략) 관리, 사용자 지시 리서치 프로세스, 텔레그램 규칙, 각종 테스트) 실시해서 v10.2 실운용 시 오류(텔레그램에 오류창 뜨는 이슈 해결포함)/업데이트 누락이 발생하지 않게 시나리오 기반으로 테스트해서 조치해주고, 실제로 쓰지 않는 프로세스와 배선을 모두 삭제해서 실행 속도를 최적화해줘(특히 과거 아키텍처에서 만든 현재는 쓰지 않는 테스트들 모두 삭제요망, 현재 쓰는 테스트들도 최적화 요망). 특히 현재 Qvest 시스템의 핵심인 리서치 테스크의 QEPM 프로세스와 1계층 리서치의 스타팅 포인트인 논문/페이퍼 수집과 해당 논문의 충실구현 파트, 그리고 강화체인을 심도 있게 감사해줘. 난 이 시스템으로 P/L 그래프가 꾸준히 우상향하는 투자전략을 만들고 싶어.

최종 목적 = **P/L 곡선이 꾸준히 우상향하는 전략을 이 시스템이 실제로 만들어 내는 것**(투자철학: 남들 다 깨질 때 덜 잃고 강세를 충분히 따라가 복리를 지킨다). 결함 사냥만 하지 말고, 맡은 영역이 그 목적을 어디서 가장 크게 막는지를 증거로 답한다.

## 2. 먼저 읽을 것 (다시 조사하지 말 것 — 이미 확인된 사실)

- 헌법 · 루프: `CLAUDE.md` · `.claude/rules/lean-loop.md` · `.claude/rules/pit.md`
- v10.2 설계와 오늘까지의 수리 목록: `04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md` (같은 폴더 `findings_ledger.md` · `factor_db_wiring_audit.md` · `l1_reinforce_map.md`)
- 투자철학 헌장: `00_Lawbook/specs/investment_philosophy_charter.md`
- 결정 기록: `06_Registry/decision_register.json` (열린 결정 0건 — 도훈 권한 사항은 여기 기록된다)
- 오늘(11-10) 13시 예약 작업 상태: DailyRefresh 마지막 결과 1 · FundV2Update 결과 1(11-09) · MorningBrief 결과 267014(실행 중 종료됨) · WeeklyCleaner/MonthlyDistill 은 이 PC 에서 한 번도 안 돎(267011) · ReinforceAutoLoop(충실구현 레인) Disabled · AuditWatch/AxiomActivate/WeightCatalogGrow Disabled.
- 오늘 아침 신선도 감사가 `.cache/RAWDATA.parquet` 를 STALE_CRITICAL 로 표시했다(재확인 전).

## 3. 방법 (레인 공통 5단계)

1. **배선 지도** — 진입점(예약 작업 · 훅 · 스킬 · 명령 · 레인 스크립트)에서 시작해 단계 → 산출물 → 소비자까지. 코드와 로그로 확인한 것만 적는다(문서 서술은 증거가 아니다 — 문서와 코드가 다르면 그것이 발견이다).
2. **운영 시나리오 시험** — "실운용 중 이 일이 생기면 시스템이 어떻게 되는가"를 실제 코드에 격리 환경(임시 루트 · 합성 자료)으로 돌린다. 반드시 포함: (a) 정상 흐름 (b) 중간 단계 실패(조용히 넘어가는가 · 한 번만 알리는가 · 다음 단계가 낡은 자료로 계속 가는가) (c) 업데이트 누락(안 돌았을 때 누가 언제 알아채는가) (d) 동시 실행 · 재실행(잠금 · 멱등성) (e) 그 영역 고유의 사고(레인별 지시서). 시험 파일은 `08_Tests/scenarios/test_scn_<레인>_<주제>.R|sh` 로 남긴다.
3. **수리** — 자기 소유 경로 안의 결함은 고치고 시험으로 고정한다(가드라면 위반 주입 · 소스 텍스트 치환 돌연변이로 발화 실증). 소유 밖 결함은 고치지 말고 패치 제안(파일:행 · 바꿀 내용)으로 보고한다.
4. **안 쓰는 것 목록** — 자기 영역에서 실운용 경로가 닿지 않는 파일(스크립트 · 시험 · 설정 · 등록부 · 문서)을 `<SCR>/dead_<레인>.tsv` 에 적는다. 열 = `path` · `kind` · `evidence`(호출처 0 을 확인한 grep 패턴 · 예약 작업 없음 · 퇴역 결정 id · 마지막 수정일) · `confidence`(certain|probable) · `refs`(이 파일을 참조하는 시험 · 문서) · `action`(delete|keep|decide). **지우지는 않는다** — 삭제는 총괄(Q)이 목록을 교차 확인한 뒤 한 번에 한다.
5. **속도** — 그 영역 임계 경로의 실측 시간(로그 · 직접 측정)과 상위 3개 시간 소모처, 판정을 바꾸지 않는 단축안.

## 4. 시험 작성 규칙

- 마지막 줄에 `{"test":"<이름>","pass":N,"fail":N,"total":N}` 한 줄 · 실패면 종료 코드 1. 한 파일 60초 안쪽을 목표.
- 격리: 임시 루트(`tempfile()` / `mktemp -d`)에 필요한 등록부 사본만 둔다. 운영 등록부 · `.cache` · 원장에 쓰지 않는다. 네트워크 · 실제 텔레그램 발송 · 실제 측정 러너 호출 없음.
- R 샌드박스 함정: `~/.Renviron` 의 QM_ROOT 가 임시 루트를 덮는다 → 자식 R 은 `R_ENVIRON_USER=<빈 파일>` 로 띄우고 첫 줄에서 루트를 단정한다.
- 루트 찾기는 `dirname()` 반복이나 환경변수로. **base R 의 경로 정규화 함수(normalize + Path)는 쓰지 않는다**(한글 경로를 깨고, 그 낱말이 든 셸 명령은 훅이 차단한다 — grep 패턴에도 넣지 말 것).
- 돌연변이 사본은 `deparse` 가 아니라 소스 텍스트 치환으로 만들고, 치환이 실제로 1곳 이상 성사됐는지 단정한다.
- `Rscript -e` 에 한글 · 중괄호가 든 긴 코드를 넣지 않는다(Windows 에서 깨진다) — 스크립트 파일로. Bash heredoc 은 이중 백슬래시를 접는다 — 이스케이프가 든 스크립트는 파일로 쓴 뒤 실행.
- `08_Tests/hooks/run_all_hooks.sh`(SUITES 목록)는 고치지 않는다 — 새 시험 경로를 보고서에 적으면 총괄이 등록한다.

## 5. 절대 규칙

- 커밋 · 스테이징 · 푸시 금지. 텔레그램 실제 발송 금지(모의 발송기 · dry-run 만). 다른 세션에 메시지 금지. 하위 에이전트 스폰 금지.
- `05_Production/` · `01_Literature/` 수정 금지. `.env` 읽기 금지, 토큰 · 키 · 비밀번호 값 출력 금지(있음/없음 · 경로만).
- Quantiwise(qwMain) · Excel 창과 그 구동 스크립트의 실행에 손대지 않는다. 수집기 · 리프레시 · 측정 러너 · 충실구현 레인을 실제로 돌리지 않는다(로그 · 산출물 읽기와 합성 자료 시험만). 외부 API(DART · ECOS · FRED · 텔레그램) 호출 금지.
- PIT C1~C15 · 정보 경계 τ_D = 2022-12-31 · 고정 축(롱온리 · ≤25종 · 15bps · LIQ 2e8 · 측정 축 epoch) · 등급 문턱은 **완화 금지**. 감사 · 가드를 약하게 만드는 수정 금지. 2023년 이후 성과 수치로 무엇도 조정하지 않는다.
- BOOK_0001 재측정 금지(도훈 11-06).
- 수치를 새로 정할 때는 근거(등록부 · 논문 · 실측)를 함께 적는다. 근거 없는 숫자 금지.
- 편집 전 `git status --short -- <경로>` 로 확인: 내가 고치지 않았는데 수정 상태인 파일은 다른 세션 · 총괄의 진행 중 작업이다 → 고치지 말고 패치 제안으로.
  - 지금 총괄이 통합 중이라 손대면 안 되는 경로: `04_Research/programs/_lib/round_core/**` · `02_Infrastructure/programs/round_candidate_gate.R` · `02_Infrastructure/programs/superfan_watch.py` · `.claude/agents/superfan*.md` · `00_Lawbook/specs/superfan_protocol.md` · `02_Infrastructure/axiom/**` · `02_Infrastructure/ops/weekly_cleaner_sweep.R` · `ops/cleaner_distill_lib.R` · `ops/axiom_quarterly.sh` · `ops/rf_axiom_activate.R` · `ops/morning_steps/axiom_approval_queue.R` · `02_Infrastructure/memory/{monthly,weekly}_distill.R` · `02_Infrastructure/data/build_kr_factor_returns.R` · `02_Infrastructure/contracts/{essence_score,grade_v3,selection_reality_check,factor_db_vintage}.R` · `02_Infrastructure/reinforcement/{rf_cell_engine,rf_runner_gates}.R` · `06_Registry/*.json`(등록부 자료는 writer 경유만 · 감사 레인은 읽기 전용).
  - 팩터 DB 는 다른 세션이 수리 중이다 — `02_Infrastructure/factor_db/` 의 빌더 · 등록부(`custom_factors.json` · `factor_registry.json`)는 읽기 전용.
- 실행 중인 bash 스크립트를 제자리에서 덮어쓰지 않는다(레인이 돌고 있으면 후보판으로).

## 6. 보고 형식 (최종 답 = 90줄 이내 · 상세는 `<SCR>/audit_<레인>.md`)

1. 배선 지도(10줄 이내)
2. 시나리오 표 — 시나리오 | 기대 | 수리 전 실제 | 조치 | 시험 파일
3. 수리한 결함(파일:행 · 원인 · 검증) / 못 고친 결함(패치 제안)
4. 업데이트 누락 감지 표 — 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 동작
5. 안 쓰는 것 — `<SCR>/dead_<레인>.tsv` 건수 요약(certain / probable / decide)
6. 속도 — 임계 경로 실측 · 상위 3 · 조치
7. P/L 우상향 관점에서 이 영역의 최대 제약 3가지(증거와 함께)
8. 도훈 결정이 필요한 것(선택지 · 권고)
9. 바꾼 파일 전체 목록 · 새 시험 경로 · 돌린 시험과 결과(개수) · 확인 못 한 것

확인하지 못한 것은 '미확인'이라고 적는다. 추정을 사실처럼 쓰지 않는다.
