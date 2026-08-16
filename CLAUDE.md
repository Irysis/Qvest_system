# Quant Module Moltbot — Claude Code Instructions

## Active Version

**Qvest v8.4 — Opus 5-Native · 4-Mode 헌법 · 실측 거버넌스 · 비대칭 알파 중심 재편(ML·수리통계 주력)** (세션 모델 정본 `claude-opus-5`. 2026-07-10 / **2026-08-08 QEPM 모델 라우팅 재핀 — 가설설계(`alpha-hypothesis`)만 `model: fable`, QEPM 나머지 전 구간 `model: opus`(현행 Opus 5)**. 구 2026-07-24 "핀 제거·세션 상속" 정책 대체. 폴백 = 한도 시 opus 재시도. SOT `02_Infrastructure/docs/rules/caching.md` 모델 라우팅 절)

> **★모델 표기 단일 출처**: 위 줄이 세션 모델의 **유일한 정본**이다(`boot_currency_check.sh` C0가 여기서 파생해 배너·상태라인 C1~C3를 대조). 다른 문서·룰은 모델명을 재기입하지 말고 "메인 세션 모델(정본 = 본 절)"로 위임할 것 — 재기입 지점이 2026-07-24 Fable 5 패치 후 3곳에서 동시 낙후된 전례.

**계보**: **v8.4** (현재 active) — 전체 계보(v6.4.0~)·릴리스 상세·검증 이력 = `02_Infrastructure/docs/CHANGELOG_constitution.md` (2026-07-24 C5 이관)
**Branch**: `main` (Qvest active — GitHub default)

**v8.4 핵심 (비대칭 알파 중심 재편, 도훈 mandate 2026-08-13)** — SOT `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md`:
- **주력 교체**: v8.3 도달 경로 ①(비-return 신규 원천)을 **주력에서 해제** → **기존 데이터풀 총동원 + ML·수리통계로 시장 비대칭 알파 도출**이 주력. 근거 = 비-return 5레인 중 **2건 데이터 게이트 폐쇄(도훈 08-09)** + 3건 실측 negative(insider 3-프레임 삼각-null · 계약 두 소비면 닫힘 · 담보/감사의견 SPARSITY_WALL). ★구조 판결 아님 — 부활 조건은 SOT §1
- **재편의 실측 근거 = ML 트랙이 자본 게이트를 하나도 못 통과했다** (`ml_complexity` 126건 원장 재판독 2026-08-13, `metric_type=registry_record`): sharpe 보유 84건에서 **MDD ≤25% 충족 0/84** · **PORT_t 기록 10건 중 ≥2.95 = 0건**(범위 −1.377~2.362) · **oos_retention 17건 중 게이트(≥0.7) 충족 2건**(음수 10건·중앙 −0.481). sharpe p25 0.492 / median 0.493 / max 0.756. 죽은 자리 = ①결합기(동일 3짝 metric 클러스터 16+9건 = 84 중 30% — 다른 결합 규칙이 같은 점을 낸다) ②사이징/selection(DPL 06-26 · uncertainty 07-05 2세션) ③평균 예측기
- ⚠**자기정정 2026-08-13**: 초판이 쓴 *"126건 전부가 평균 표적 · 분포 표적 0건"* 은 **근거 없음** — `key_metrics` 에 표적 필드가 없어 셀 수 없고(자유 형식 패턴 감사), metric 보유도 84/126 이다. 정직 서술 = **"분포를 표적으로 명시한 라운드를 찾지 못했다"(미발견이지 부재 증명 아님)**. 재편은 위 게이트-통과-0 이 지탱하고, 표적 가설의 첫 시험은 Lane A 의 arm A(평균-표적 대조군) 재현이다
- **동기 서술(약)**: D03 Q5−Q1 평균 −5.10% vs 중앙값 +12.01% "부호 반대" — ⚠**중앙값·왜도 수치는 산문 기록뿐이고 구조화 출처 미확인**(08-13 재탐색에서 해당 WT 산출물에 `12.01` 부재). **Lane A 착수 0항 = 이 두 수치 재산출**, 미재현 시 이 동기 서술은 철회(재편 방향은 불변)
- **미소비 표면 = 일별 축**: 알파 리서치는 전부 월간 횡단면인데 데이터는 **9,005 거래일**(RAWDATA 14.06M행) + **flow_features_daily 1.25GB**(9.36M행 22피처, ⚠lag 43d 정체). 월간으로 접는 순간 분포 정보가 소멸 — 비대칭은 접히기 전에만 관측된다. ⚠factor DB 331 전수는 이미 소진(book-marginal 통과 0·계열 15종이 구속 해상도), 증분은 일별 원천에 있다
- **4 lane**: A 분포-표적 학습(1순위, 평균-표적 대조군 동반 의무) · **D 매크로 상태 조건부 비대칭**(2순위, 도훈 2026-08-13 추가 — 매크로는 **이미 적재 중**(오늘 07:04~07:07 갱신, lag 1d) 신규 수집 불요. 단 착수 전 4확인: `fred_macro_wide` 파생 5일 정체 · 계열별 시차 7~73일 불균질 · `macro_regime` 월말스탬프 마지막 행이 **진행 중인 달**이라 월중 조회 시 동월 look-ahead · flow 패널 43일 정체) · B 일별 축 정보 회수(PIT 최우선) · C 수리통계 구조 추정(ML의 음성 대조)
- **금지 4종(경로-scoped, INV-7)**: ML 결합기 · ML 사이징/selection · **표적이 "다음 달 평균 수익률"인 ML 라운드**(대조군으로만) · sweep 의 DSR 회피
- **불변**: Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent · Production Constraints(INV-7) · governor 수동 · v8.3 골격(dual-basis·프론티어 큐·지식 환류)

**v8.3 핵심 (알파 발굴 중심 재편, 도훈 mandate 2026-07-10)** — SOT `02_Infrastructure/docs/qvest_v8_3_alpha_discovery_sot.md`:
- **벽-정합 측정**: alpha 단계 선별 1급 지표 = canonical PORT_t(실측, IC는 advisory) — IC→PORT_t 전이 벽 정합. **dual-basis 진단**: cap-w HARD 판정 불변 + 기각 전 EW-유니버스 대비·cap-tier(MEGA/MID) 분해 확인 의무(post-2017 감쇠의 상당부분 = mega-cap 벤치 아티팩트 실측)
- **상설 프론티어 큐**: `06_Registry/alpha_frontier_queue.json` = "다음에 뭘 시도할지" SOT. 발굴 착수 전 hypothesis_index lookup + 큐 확인·owner 표기 의무. `dohoon_decision` 항목 세션 임의 착수 금지
- **지식 환류 수리**: hypothesis_index in-flight WT 인덱싱(병렬 중복실행 방지) · 주입면 frontier 현행화(settled-negative 광고 제거) · revival 발화 세션 도달 · screen-tier 회수 배관(dead 라벨 정리)
- **불변**: Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent(슬림화 재제안 금지) · Production Constraints(INV-7) · governor 수동
- **텔레그램 v7 동반**: 비전공자 가독 3장치(쉬운 설명 섹션 + 판정 평문 + 자동 용어풀이 footer), 전문용어 유지

**v8.1 핵심 (흡수 — 8불릿 상세는 CHANGELOG_constitution.md 이관 아카이브 + `qvest_v8_1_sot.md`)**: 3-Mode 헌법(alpha-search **논문 완전 복제** + 유니버스 K200∪KQ150 고정 + 기간 2005~ 고정 · FR Lane3 · Axiom r7 복원) + 실측-only 거버넌스(measurement-graduation) + `register_module` 표준화·자동흐름(자본게이트 book confirm+실주문 2버튼만 수동).
**KR 데이터 한계 reference**: value/BM 2002-08~ · M08_ResidMom 1995~ · factor DB 1990~ (`feedback-alpha-search-paper-replication`)

**★ Active SOT (단일 진실)**: `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md` (**v8.4 비대칭 재편 SOT** — 주력 레인 정본) + `qvest_v8_1_sot.md` (v8.1 설계 SOT) + `qvest_v8_3_alpha_discovery_sot.md` (v8.3 발굴 재편 SOT — 골격 승계, 도달 경로 ①만 해제) + `qvest_ast_v1_1_sot.md` (**AST 계층 v1.1** — 2026-07-25 도훈 승인: alpha 3층 스펙(AST-우선+escape 리프 4종)·PIT 3중 구조 예방·구조특징 사전분포. field_dictionary = `06_Registry/ast_field_map_v0.json`. C4 연간=3/31 확정) + `qvest_v8_0_upgrade_plan.md` (v8.0 base 흡수, retain)
**전임 SOT (흡수됨)**: `02_Infrastructure/docs/qvest_v6_4_sot.md` (v6.4 base 흡수, read-only retain)
**Legacy boundary**: `02_Infrastructure/docs/qvest_legacy_boundary.md` (v55 / S0~S7 격리)

본 CLAUDE.md는 헌법만. 절차는 `.claude/skills/`, 룰은 2단(`코어 6 = .claude/rules/ autoload` + `확장 11 = 02_Infrastructure/docs/rules/ on-demand` — 아래 Rules 절), 강제는 `02_Infrastructure/hooks/`, 역할은 `.claude/agents/`.

---

## Active Modes (4-Mode — 각자 평가·자가발전, 도훈 mandate 2026-06-05 / RAMP 추가 2026-06-17)

Qvest = 독립 리서치 모드 4개 (lifecycle ①②생산 → ③④소비; 진입점은 아래 `## Active Entrypoints`).
**각 모드 = 자기 평가체계 + 자기 자가발전** (L-code → mode-local axiom `AX-<MODE>-*`, `02_Infrastructure/docs/rules/axiom-engine.md` v8.0 E2E 검증). **평가체계(산출물 채점)는 모드별 자율 — 통일 금지.** 공유하는 건 *평가가 아니라 토대*: ① 정직 라벨 (`metric_type` proxy/backtested) ② 자본 게이트 (`book_state` = governor 수동+도훈) ③ **교차검증 global 공리** (자가발전 결과 중 backtested + r7 5축 + AX-008 + 도훈 confirm 통과분만 `AX-NNN`; 공유 *사실*이지 평가 통일 아님 — proxy·한 모드 loose 평가는 INV-1로 global 차단). SOT: `02_Infrastructure/docs/qvest_modes_sot.md`.

**① QEPM 모드 경로** (신호-only 알파 정밀 검증·편입):
```
WorkTask → [alpha-hypothesis] → alpha-research → risk-research → optimizer-research → forge → judge → governor
             └ 가설설계 구간(fable)  └────────────── 이하 전부 opus (Opus 5) ──────────────┘
```
**모델 라우팅 (2026-08-08 도훈 지시)**: `alpha-hypothesis`(Step 0 발굴 + ①메커니즘→②가설→③반증→④국면 경계) **만 `model: fable`**, QEPM 나머지 전 에이전트 `model: opus`. alpha-hypothesis 는 alpha-research의 *내부 구간 분리*이지 7번째 심사 단계가 아니다(6-agent 구조 불변 — 슬림화/확장 재제안 아님). 핸드오프 = `alpha_hypothesis.json`(alpha-research 가 승계, 재작성 금지). 상세 SOT: `02_Infrastructure/docs/rules/caching.md` 모델 라우팅 절.
각 agent spawn 시 **Self-Adversarial Challenge 의무** (v8.2 — Codex Round 제거, 메인 세션 모델(정본 = Active Version 절) 자체 적대검증: finalize 직전 약점 자가제기 → `challenge_note.md` 기록 → final. AX-008 3-source 중 1개).
**② alpha-search · ③ factor-rotation**: 각자 경량 경로 (각 skill + `## Active Entrypoints`).
**④ RAMP** (K-RAMP, 2026-06-17): 기존 전략풀 *소비* → 순수팩터 추출(통계 잠재팩터+FWL) → 팩터군 → M-code(역할 분업) → 리스크매니저 → 인베스터 에이전트 팩터배분. 거버넌스-우선 Gate 0~11 + CCS 13-score. 재귀 자가발전=Axiom 엔진 4번째 모드(modecode RAMP, backtested). 룰 `02_Infrastructure/docs/rules/ramp.md`, SOT `00_Lawbook/K_RAMP/`. governor 정지(자본 수동).

---

## Session Startup (MANDATORY)

새 세션 시작 시:
```
/qvest
```
Qvest 시스템 전체 구동. bootstrap.sh 실행 → 플러그인 리로드 → gap 확인.

## Session End (MANDATORY)

세션 종료 시:
- 메모리 파일 modified 시 `# 최종 업데이트:` date 갱신
- 새 L-code 추가 시 **아티팩트 emit → harvester 재수확** + MEMORY.md 헤더 갱신 (2026-07-25 도훈 승인 정정 — 구 표기 `methodology_active.md 등재`는 **부재 파일** 지시였음. 해당 md는 `methodology_archive.md`·`qepm/memory/methodology_memory.md`와 함께 저장소·메모리 어디에도 없으며, 현행 적립 경로는 `l_code*.json` 아티팩트 → `02_Infrastructure/axiom/lcode_harvester.py` → `.cache/lcode_corpus.json` → `02_Infrastructure/ops/build_knowledge_index.R` → `06_Registry/knowledge_index.json`. harvester 스캔범위 = 루트 `stage_artifacts/` + `04_Research/strategies/*/stage_artifacts/`. **2026-08-13 경로 정정** — 구 표기 `ops/build_knowledge_index.R` 은 **최상위 `ops/` 자체가 부재**라 실행되지 않는다(07-25 정정이 고친 것과 같은 계통의 경로 오기). ★**검색면(`hypothesis_index`)은 별개 빌더**다: `Rscript 02_Infrastructure/tools/hypothesis_index.R build` — **`build` 서브커맨드 필수**. 인자 없이 부르면 usage 만 찍고 **exit 0** 이라 호출자가 재빌드된 줄 오인한다(2026-08-13 실측: L-code 3건이 corpus 492 에는 들어갔는데 index 1204 에는 없었고, 인자 부여 후 1213 으로 회복). 적립은 **corpus 수확 + index build 둘 다** 해야 다음 라운드 Step 0 lookup 에 도달한다)
- infra 변경 시 관련 SOT/rules 문서 갱신 + 메모리 적립 (구 `infrastructure_state.md` 참조는 파일 부재 확인으로 2026-07-18 정정 — 도훈 승인)

---

## Core Rules

- **R + Python 공히 1급 허용** (v8.0, 2026-05-29 도훈 mandate — 기존 "R only" 폐지). 언어 선택은 도구적: R(tidyverse + data.table) / Python(venv `qvest_ml`). **PIT C1~C15 / Backtest Contract v1.0 / Production Constraints / lockbox-scope는 언어 무관 동일 적용.** Python backtest는 검증된 표준함수만(자체합성 금지) + 10-component `bt_result`는 R `build_bt_result` bridge 경유. 상세: `.claude/rules/python-policy.md`
- **NEVER modify** `05_Production/`, `01_Literature/`
- All output to `04_Research/` and `06_Registry/`
- Korean semi-formal tone (존댓말). User = Dohoon Kim (도훈), calls me "Q"

## 병렬 에이전트 실행 규칙

- 독립적 작업 2건+ → Agent tool 병렬 spawn 필수
- RAM 80% 이하 시 추가 spawn
- 코드 작성과 실행 분리 (메인 작성 → background spawn → 즉시 다음)
- Stage Gate artifact 작성은 메인 직접 (서브 위임 금지)

---

## Active Entrypoints

**4 리서치 모드** (도훈 mandate): ① **QEPM**(6-에이전트 풀파이프라인, `/worktask`) — 모듈 생산 · ② **alpha-search**(논문 1편 경량 검증, `/alpha-search`) — 모듈 생산 · ③ **factor-rotation**(국면조건부 모듈 배합 meta-layer, `/factor-rotation`) — 모듈 *소비* · ④ **RAMP**(K-RAMP, 기존 전략풀에서 순수팩터→팩터군→M-code→인베스터 에이전트 팩터배분, `/ramp`) — 풀 *소비* + 거버넌스-우선 Gate 0~11. ②③ 산출물은 `register_module()` 경유 표준화되며, 계약 floor 통과분만 ③④가 소비한다.

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask 생성 + 상태 + 전이 + admission (QEPM 모드) |
| `/alpha-search` | 논문/가설 경량 백테 검증 (alpha-search 모드) |
| `/factor-rotation <track>` | 국면조건부 모듈 배합 FR_XXXX (factor-rotation 모드. track∈{regime-engine, allocation}) |
| `/ramp <stage>` | K-RAMP 팩터배분 운용체계 RAMP_XXXX (RAMP 모드. Gate 0~11·CCS 13-score·실측-only·governor 정지. 룰 `docs/rules/ramp.md`) |

---

## Absolute Rules (1줄 reference)

- **PIT C1~C15**: `.claude/rules/pit.md`
- **Lockbox / Frozen Alpha Scope**: `02_Infrastructure/docs/rules/lockbox-scope.md` (정규 리서치 alpha/risk/optimizer만 적용. forge/monitoring/Q-Lead/execution = 폐기. 도훈 mandate 2026-05-09)
- **Self-Adversarial Challenge (Codex Round 대체)**: `02_Infrastructure/docs/rules/codex-round.md` (v8.2 — 외부 Codex Round 제거, 메인 세션 모델(정본 = Active Version 절) 자체 적대검증으로 finalize 직전 약점 자가제기 + `challenge_note.md` 기록. AX-008 3-source 중 1개)
- **Backtest Result Contract v1.0**: `.claude/rules/backtest-contract.md` (PerformanceAnalytics 표준 함수만)
- **Measurement Integrity + Graduation 허들 (v8.x)**: `.claude/rules/measurement-graduation.md` ⭐ (위반 = AX-002 동급. 실측 처리(canonical_screen_bt/build_bt_result + metric_type 라벨, proxy 손계산 금지) / portfolio-alpha t = forge-authoritative(NW lag-3) / graduation severity: PORT_t 2.95·DSR hard, rank-IC계열 advisory / admission = book-marginal ΔIR≥0.05 / DPL 구성레이어. E2E: FLOW proxy 3.55→forge 2.35)
- **Axiom Engine 2-Tier (v8.0)**: `02_Infrastructure/docs/rules/axiom-engine.md` ⭐ (원전 r7 복원 + 3-mode 2-tier(AS proxy→mode-local / QPM·FR backtested→global) + INV-1~7. mode-local AX-&lt;MODE&gt;-NNN / global AX-NNN. negative=provisional failure-ledger. 자동승격=documented·hook block은 주간 confirm. E2E 10/10. 위반=AX-002 동급)
- **Qvest 답변 원칙 (8원칙 + 5금지)**: `.claude/rules/answer-principles.md` (위반 = AX-002 동급)
- **Continuity Firewall (포기 원천차단, 2026-07-15 도훈 mandate)**: `02_Infrastructure/docs/rules/continuity-firewall.md` ⭐ (누적 실패 후 '끝남 표현'으로 라운드 마감 = Stop 훅 **block 강제속행**. 4레이어: L1 차단 실효 + L2 독립 semantic 판정(`continuity_gate.py`) + L3 건설적 종료계약(`close_round()` — next_probe≥2·소비면·부활조건 강제) + L4 자가발전(`continuity_cases.json`). ★어휘가 아니라 계약이 게이트 — 종결 단어를 지워도 통과 못 함, 계속을 *생산*해야 함. 판정 자체는 불차단(AX-000·INV-7 정합). 위반 = AX-002 동급)
- **Telegram v7 SOT**: `.claude/skills/qvest-telegram/SKILL.md` (단일 규칙. `tg_agent_brief()` 진입점, 약어 풀이 + **비전공자 3장치**(쉬운 설명 섹션·판정 평문·자동 용어풀이 footer — 전문용어 유지) 자동, 표준 5섹션 권장)
- **Caching + Model Routing Discipline**: `02_Infrastructure/docs/rules/caching.md` (2026-07-24 Fable 5 개정 — 1h TTL 실측·모델 핀 제거/상속·폴백 opus·wakeup은 대상-기반, 구 ≤270s 규칙 폐기)
- **Harness Engineering (Hooks Tier 1~6)**: `02_Infrastructure/docs/rules/harness.md`
- **Factor DB + Forge 자원**: `02_Infrastructure/docs/rules/factor-db.md` (C13~C15 + load_month_factors 경유)
- **Axioms (AX-000~008)**: `.claude/rules/axioms.md`
- **R 측 Windows 이식성 계약**: `02_Infrastructure/docs/rules/r-portability.md` ⭐ (2026-07-25 도훈 "승격해". 금칙 6종 — ①`system2(env=)`(환경변수 아닌 **인자 주입**) ②스크립트 최상위 `on.exit()`(**미발화** → cleanup dead code) ③선행 `/` 경로 하드코딩·`startsWith(p,"/")` 절대경로 판정·루트를 `dir.exists()`로 신뢰 ④resolver 우선순위는 `CLAUDE_PROJECT_DIR` 먼저 ⑤`system()/system2()` 문자열에 쉘 리다이렉션·`&&` 주입(**셸 미경유 → 리터럴 argv**. 2026-08-02 추가 — 빈 출력이 '변경 없음'으로 읽혀 `git_dirty` 79건 위장) ⑥`regmatches`를 **TRE 색인** 위에서 사용(2026-08-02 추가 — Windows TRE는 매치 위치를 **UTF-16 코드유닛**으로 보고하는데 `regmatches`/`substr`은 **코드포인트**로 자름 → 매치 **앞**의 이모지 1개당 추출 창 1칸 밀림. **길이는 맞아 오류가 아니라 그럴듯한 쓰레기**가 나옴. `perl=`/`fixed=`/`useBytes=TRUE`로 회피. ★**count-only는 위반 아님** — 밀리는 건 위치이지 개수가 아님). 공통 기전 = **존재 검사로 정체성 검사 대체 / 결손을 정상값으로 내려앉힘**(⑥만 반대 방향 = **정상값 모양의 오답**). 강제 = `08_Tests/hooks/test_r_portability.R`(baseline 래칫 69건 + 금칙⑥ 개수 래칫 44 site/19 파일 + 위반 주입 12종, suite 22/22) + `08_Tests/hooks/test_lineage_git_state.R`(행동 수준 11/11, 돌연변이로 검출력 실증), 둘 다 배터리 편입. 위반 = AX-002 동급)
- **Research Philosophy (7 QEPM Modern Trends)**: `02_Infrastructure/docs/rules/research_philosophy.md` ⭐ (Charter-level SOT `02_Infrastructure/docs/qvest_research_philosophy.md` v1.0 2026-05-14. Factor Zoo 축소 / Cost-aware / Uncertainty-aware / Direct Portfolio / Crowding / Implementation / Attribution. 분기별 review + trigger-based 보강. 위반 = AX-002 동급)

---

## Project Goals

### 존재의의: 이 시스템은 알파시킹 기계다 (도훈 mandate 2026-08-02)

프로세스·하네스·게이트·거버넌스는 **알파 발굴을 신뢰할 수 있게 만드는 수단**이지 목적이 아니다. 세션 자원 배분의 기본값은 **알파 라운드 전진**(FQ 큐 소비·가설 실측·판정)이며, 인프라 작업은 ① 알파 라운드를 실제로 막는 결함 ② 측정 신뢰를 훼손하는 결함(PIT/proxy/침묵 실패)에 한정해 즉시 수리하고, 그 외 위생성 개선은 태스크 분리(chip)로 넘긴다. 가용 사이클이 생기면 "인프라를 더 다듬을까"가 아니라 "다음 알파 가설이 무엇인가"를 먼저 묻는다.

### 제1목표: 미래참조 없는 전략 설계 (PIT 완전 준수) — 성과보다 우선

### 제2목표: SR 2.5+ / CAGR 16%+ / MDD <25% (SR 2.0→2.5 상향, 2026-05-29 도훈 mandate — KR 구조적 상승 반영)

도달 경로 (**2026-08-13 v8.4 재편 — 도훈 mandate**. 구 2026-07-10 v8.3 순위 대체): ① **비대칭 알파 도출**(기존 데이터풀 총동원 + ML·수리통계·**매크로**. 표적을 **평균 → 분포**로 교체 — 조건부 분위·왜도·꼬리초과확률. 4 lane = A 분포-표적 학습 / D 매크로 상태 조건부 / B 일별 축 회수 / C 수리통계 구조추정. SOT `qvest_v8_4_asymmetry_ml_sot.md`) ② **screen-tier 재고 회수 + EW-대비/cap-tier 재분류**(overlay 큐 드레인 · 벤치-아티팩트 기각 후보 재라우팅, FQ-006~008) ③ overlay 잔여 정교화(실증 유일 β 레버이나 clean 잔여폭 좁음 — 07-05/06 양방향 negative 실측).
**주력에서 해제 (2026-08-13 도훈 지시, 구 ①)**: 비-return 신규 원천 FQ-001~005 — 2건은 **도훈이 데이터 게이트를 닫았고**(08-09 공매도/신용대차), 3건은 실측 negative. ★구조 판결 아님, 부활 조건은 SOT §1(INV-7).
잔차-직교 sleeve 스태킹은 07-05 RAMP R1 config-scoped 미달(survivors 0, §6) — 구조판결 아님·frontier 조건부. 신규 standalone **평균-표적** return-파생 팩터 사냥은 16/16 FAIL posterior + factor DB 331 전수 book-marginal 통과 0으로 최후순위(계열 15종이 구속 해상도).

### 제약 (방침)

- 기존 인프라 극한 활용 (Factor DB / DART / FRED / ECOS / QuantiWise)
- 크로스마켓 / 대체데이터 금지
- 확장 허용: ML / 수리통계 / 물리학 / 카오스이론

---

## Production Constraints

> **★이것은 배포 현실이 정의한 문제의 고정 축이다 — 최적화로 없앨 변수가 아니다.** AX-000 따름정리: 이 봉투 *안에서* 풀어라; 제약 완화(>25종·short 허용·유동성 하향 등)를 레버로 제시하는 것은 게임을 이기는 게 아니라 바꾸는 것이다(실패지식 제약 방화벽 — `02_Infrastructure/docs/rules/axiom-engine.md` INV-7). 조건-안 레버만 프론티어 — 현행(**2026-08-13 v8.4 갱신**): ① **비대칭 표적**(분포-표적 학습 · 일별 축 정보 회수 · 수리통계 구조 추정 — 주력) ② screen-tier 재고 회수(overlay 큐) ③ EW-대비/cap-tier 재분류 ④ overlay 잔여·잔차sleeve(조건부)·multi-sleeve·composite. **DPL(06-26)·regime-conditional 교차결합(07-05)·ML/uncertainty sizing(07-05 2세션)은 settled-negative 실측 — 레버 아님**(부활신호 발화 시에만 재검토, INV-7).
⚠**①이 과거 ML 실패의 부활이 아님을 구분할 것**: 죽은 것은 ML 을 **결합기·사이징·평균 예측기**로 쓴 경로(126건 실측)이고, ①은 **표적 자체를 분포로 바꾸는** 미측정 축이다. 표적이 "다음 달 평균 수익률"인 ML 라운드는 **금지**(대조군으로만 등장) — SOT §6 금지 4종.

| 제약 | 값 |
|---|---|
| 종목수 | max 25 (hook 강제, 도훈 mandate 2026-05-29 20→25) |
| 유동성 | 20일 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD) |
| Long-only | weights ≥ 0 |
| Weight bounds | [0, 0.20] |
| Σw | = 1 (absolute) |
| Universe | KOSPI200 ∪ KOSDAQ150 |
| Transaction cost | 15bps one-way (cost_model_version v2.4_kr_retail_15bps — delta-based, 종목별 Δ보유명목 절대값에 레그당 과금. 2026-06-11 도훈 confirm. 구 v2.3 flat 기록과 비교 시 라벨 확인) |
| PIT | C1~C15 전체 (`.claude/rules/pit.md`) |

---

## Key Paths

- Project root: `C:/Users/99922/OneDrive/Quant_Module_Moltbot/` (OneDrive canonical, 도훈 mandate 2026-06-10. Git Bash: `/c/Users/99922/OneDrive/Quant_Module_Moltbot`)
- Infrastructure: `02_Infrastructure/` (config.R + 12 subdirs: data/ factor_db/ regime/ validation/ hooks/ agents/ telegram/ reports/ memory/ portfolio/ ops/ docs/ worktask/ contracts/ tools/ axiom/ prompts/)
- Strategies: `04_Research/strategies/STR_XXX_name/` (legacy retain)
- WT mailbox: `qepm/mailbox/worktask/{WT_ID}/`
- Stage artifacts: `stage_artifacts/WT_{ID}/`
- Memory: `C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/MEMORY.md`
- Env (User scope 영구): `QM_ROOT` + `QVEST_PY` + `~/.Renviron` 동일값 (경로 이전 시 이 3곳 + config.R 후보만 갱신)
- 산출물 저장 위치 규칙 (저장 4원칙 + 루트 13항목 고정 + retention): `02_Infrastructure/docs/rules/artifact-storage.md`

---

## R Execution Pattern

- `source('run_all.R')` pattern only (한글 path encoding 회피, NOT `--file=`)
- `cd` to strategy directory first, then `Rscript -e 'source("run_all.R")'`

---

## Multi-Agent Summary (v8.1 active 6 + 4 ondemand)

| Agent | 위치 | 역할 |
|---|---|---|
| **Q-Lead** | 메인 Claude 세션 (유일) | 오케스트레이션, agent spawn, memory commit, telegram 보고 |
| **alpha-hypothesis** ⭐fable | Agent tool | **가설설계 전담** (Step 0 발굴 + ①메커니즘 →②가설 →③반증 →④국면 경계) → `alpha_hypothesis.json`. ⑤AST·팩터 소싱·실측 금지 |
| **alpha-research** | Agent tool | α̂ 생성 (⑤AST 구성 + factor specs + ICIR + Harvey-t). 가설 승계(재작성 금지). Σ/weight 절대 금지 |
| **risk-research** | Agent tool | Σ + tail + stress + crowding + style. alpha 수정 금지 |
| **optimizer-research** | Agent tool | weights 결정 (MVO/HRP/CVaR/etc 자율). alpha/risk 재해석 금지 |
| **forge** | Agent tool | run_all.R + backtest 통합 (Pure function). target_weights/cov 수정 금지 |
| **judge** | Agent tool | Gate 0~18 + PIT 검증 |
| **governor** | Agent tool | PG0~PG3 admission + book_state |
| architect | Agent tool (ondemand) | 인프라 진단 |
| blender | Agent tool (ondemand) | 국면 배분 (Grade A 4건+ 시) |
| execution | Agent tool (ondemand) | TWAP/VWAP schedule (deployment 시) |
| monitoring | Agent tool (ondemand / cron) | live drift 월간 |

상세 절차: `.claude/skills/qvest-worktask/SKILL.md`

---

## Axioms (Level 0 — 요약)

전체: `.claude/rules/axioms.md` 또는 `_shared_prefix.md`

```
계층: AX-code (Lv0) > PIT C1-C15 (Lv1) > L-code (Lv2) > Signals (Lv3)
```

- **AX-000** [IMMUTABLE]: 한계는 법칙 아닌 방법의 한계 — 모든 목표는 엄밀함·창의성·반복으로 달성 가능. **3~4회 실패로 한계/dead-end 단정 금지**; 모든 수단 소진 또는 도훈 중단 지시까지 탐색 계속. 실측·PIT 결과는 정직 보고하되 탐색 중단 근거 아님 (2026-06-21 개정)
  - **따름정리(제약=고정 축, 2026-07-04)**: Production Constraints(고정 제약 7종+PIT)는 **문제의 고정 축이지 실패의 원인/레버가 아니다** — 실패를 제약에 귀속하거나 제약 완화를 레버로 제시 금지(실패지식 제약 방화벽, axiom-engine INV-7). 창의 부담은 봉투-안 방법에.
- **AX-001 v2** [IMMUTABLE]: 방어형 팩터 조건부 평가 (crisis_alpha + Core 대비 MDD + bad/normal IC ratio)
- **AX-002** [IMMUTABLE]: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조
- **AX-003 / AX-004 / AX-005 / AX-007** [Distilled 강등 2026-07-05 — active Law 아님]: negative 공리 4종은 Distilled 탐색지도 이관(INV-7 재도전 대상, enforcement 대상 아님). 상세: `.claude/rules/axioms.md` Demoted 절 (DIST-QPM-006 / QPM-003 / AR-001 / AR-003)
- **AX-008** [process]: Verification Triangulation (Forge + Self-Adversarial + Architect 2/3 PASS)

위반 시 즉시 중단. Hook `axiom_enforcement_hook.sh` 자동 차단.

---

## Q-Lead 역할 경계 (Level 0)

- ✅ 진단 / 지시 / 모니터링 / 결과 수집 / telegram 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ❌ 직접 Rscript 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (역할경계·lockbox 훅은 agent marker 존재 시에만 발화 — marker 자동 기록 메커니즘 부재. 실제 방어선 = R 계약(essence_score/registry_writer) + 게이트급 훅 + 수동 confirm. 2026-07-03 도훈 confirm, 아키텍처 감사)

---

## qepm 하이브리드 모드 (Q-Lead 전용)

```bash
cd qepm && Rscript -e 'source("scripts/hybrid_mode.R")'
```

주요 함수: `hybrid_commit()` / `hybrid_status()` / `hybrid_queue()` / `hybrid_daily_digest()`

---

## Slash Commands (`.claude/commands/`)

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask CRUD |
| `/alpha-search` · `/factor-rotation` · `/ramp` | 모드 진입 (Active Entrypoints 표 참조) |
| `/qlead` | Q-Lead session dashboard |
| (삭제 이력) | 커맨드 래퍼 8종 삭제(2026-07-05 `/forge` 등 7종 · 2026-06-10 `/scout`) — **동명 AGENT(.claude/agents/)·HOOK·SKILL은 현역 유지**. 상세 = DEPRECATION.md·CHANGELOG_constitution.md |

---

## Skills + Rules

### Skills (`.claude/skills/`) — domain-scoped

| Skill | 용도 |
|---|---|
| `qvest-worktask` | WorkTask lifecycle 절차 (CLAUDE.md에서 이동) |
| `qvest-telegram` | 텔레그램 단일 SOT (v6) — 양식 / 약어 풀이 / Hook 정책 / caller 예시 통합 |
| (Phase 9 추가 예정) | qvest-hook-debug / qvest-cert-paths |

### Rules — 2단 구조 (2026-06-10 P2 다이어트: autoload 16→6)

**코어 6 (`.claude/rules/` — 매 세션 autoload)**: `pit.md` (C1~C15) · `axioms.md` (AX-000~008) · `answer-principles.md` (8원칙+5금지) · `backtest-contract.md` (bt_result 10-component) · `measurement-graduation.md` (게이트 2계층+HARD) · `python-policy.md` (R/Python 1급)

**확장 11 (`02_Infrastructure/docs/rules/` — 해당 작업 시 on-demand Read, 효력 동일. v8.2 codex-round.md = DEPRECATED 스텁)**:

| Rule | 로드 시점 |
|---|---|
| `harness.md` | hook 디버깅 시 (qvest-hook-debug skill) |
| `axiom-engine.md` | axiom 승격/주간 파이프라인 작업 시 |
| `factor-rotation.md` | factor-rotation 모드 진입 시 (SKILL이 참조) |
| `lockbox-scope.md` | lockbox 판단 시 (pit.md에 요약 잔존) |
| `factor-db.md` | factor DB 직접 작업 시 |
| `data_table_shift_convention.md` | shift/forward label 작성 시 (pit.md C-체크 연계) |
| `artifact-naming.md` | WT 핸드오프 파일 생성 시 |
| `artifact-storage.md` | 산출물 저장 위치 판단 시 |
| `caching.md` | 토큰/캐시 운영 판단 시 |
| `research_philosophy.md` | 분기 review 시 (본문 SOT는 docs/qvest_research_philosophy.md) |
| `r-portability.md` | R에서 `system2`/`system` 호출 · cleanup 등록 · 프로젝트 루트 해석 코드를 쓸 때 |

---

## Safety Rules

- NEVER modify `05_Production/` (promote_to_production() 만 예외)
- `01_Literature/` read-only
- All output to `04_Research/` and `06_Registry/`
- 기존 stage_artifacts/ + 178+ STR 결과 보존
- legacy v55/S0-S7 **파이프라인 데이터·전략 결과** 격리 (삭제 X) — `qvest_legacy_boundary.md`. (단 s0-s7 stage *스킬* 8종 + v53/v55 커맨드 래퍼는 2026-07-05 미사용 확인 후 삭제 — 역사는 git·legacy_boundary 보존. 격리는 산출물/데이터 대상이지 dead 코드파일 대상 아님)

---

## Release Status + 변경 이력

**SOT 분리 (2026-06-10 P2 다이어트)**: 버전 연혁·릴리스 상세는 `02_Infrastructure/docs/CHANGELOG_constitution.md` — CLAUDE.md는 현행 헌법만 담는다.
- 현행: **v8.4** (2026-08-13 비대칭 알파 중심 재편 — 도훈 mandate, SOT `qvest_v8_4_asymmetry_ml_sot.md`. 비-return 주력 해제 + ML·수리통계 분포-표적 3 lane 신설, 큐 FQ-233/234/235). base = **v8.3** (2026-07-10 알파 발굴 중심 재편, SOT `qvest_v8_3_alpha_discovery_sot.md` — 골격 승계, 도달 경로 ①만 해제) + **2026-07-24 Fable 5 정합 패치**(도훈 승인 C1/C5/C6 포함). 이전 버전·검증 이력 상세 = `CHANGELOG_constitution.md`.
- **현행 hook 등록 = settings.json 47 distinct .sh** (직접 29 + 라우터 dispatch 19 − 중복 `safety_guard` 1 = 47, **2026-08-16 실측 재산출** — `hypothesis_precheck_gate.sh` 라우터 dispatch 등재로 46→47. ★이 드리프트는 등재 2분 만에 `boot_currency_check.sh` C6 가 잡았다(선언 46 vs 실측 47) — 훅을 늘리면 이 줄도 함께 고칠 것. 구 46 분해는 2026-07-26 실측 — 2026-07-24 Fable 5 감사·C1~C10 실행(주입취약 4훅 env-경유·전달0 6종 복원·조기-exit·axiom주입 복원·dead 4건 해제) + **2026-07-25 `ast_spec_gate.sh` 등재**(AST v1.1 Step 3 기계 게이트). 배터리 15/15 PASS. 상세 `harness.md` 정합 절)
