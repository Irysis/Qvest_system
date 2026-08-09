## FQ-181 P7 — 큐 상태 갱신 (정본 writer 경유: frontier_queue_io.R)
suppressPackageStartupMessages({ library(jsonlite) })
QM <- gsub("\\\\","/",Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(QM)
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
ix <- which(vapply(Q$entries, function(e) identical(e$id, "FQ-181"), logical(1)))
stopifnot(length(ix) == 1L)
cat(sprintf("[before] status=%s owner=%s\n", Q$entries[[ix]]$status, Q$entries[[ix]]$owner))

e <- Q$entries[[ix]]
e$status <- "resolved_pending_dohoon_decision"
e$resolved <- "2026-08-09"
e$resolved_by <- "alpha-research (FQ-181 수리 세션)"
e$artifacts <- "stage_artifacts/FQ181_liquidity_ruler/ (challenge_note.md · p0~p6 프로브 · census csv/json)"
e$repair <- paste0(
  "02_Infrastructure/ramp/factor_validation.R 교정 완료. adv = 20일 평균 거래대금, 창이 t-1 에서 끝남(당일 미포함). ",
  "신규 헬퍼 build_adv20_t1() 분리. **시그니처 불변**(rawdata, sig_dates) — FQ-173 등 병행 소비자 보호. ",
  "반환 list 에 liq_ruler 추가 + liq_dt attr 로 이중 도달. 자 라벨 기록 의무 1줄 규약을 함수 상단 주석에 명문화.")
e$test <- paste0(
  "08_Tests/ramp/test_liquidity_ruler.R — 17 pass / 0 fail. 배터리 등재(run_all_hooks.sh::SUITES). ",
  "위반 주입 B1(구판 1일치 산식 주입 → 36/36 검출) + 돌연변이 B2(shift 제거)/B3(창폭1)/B4(slim 20창) 전건 검거 확인. ",
  "--file= · source() · 외부 cwd 3방식 통과. 회귀: test_gate3_4 통과 · contract_regression 74/74 PASS.")
e$measured <- paste0(
  "[parity] 실데이터 2018-2026(104월말 4.9M행) 및 1999-2005(84월말 2.3M행) 양쪽에서 returns_dt·bench_dt·ret_firewall **bit-동일** — 자 교정이 수익·벤치 미침범. 비용 +10%(14.4s→15.9s). ",
  "[자 대조] K200∪KQ150 종-월 116,476 · pearson 0.9045 · spearman 0.9387 · 판정 불일치 5.449%. ",
  "★방향: 구판만통과 1,388(1.192%, 교정이 조임) vs 교정만통과 4,959(4.258%, 교정이 품) → **net looser +3,571건(+3.066%p)**. ",
  "기전 실측: 교정만통과분의 월말 당일 Vol==0 비율 6.0%(기저 0.59%의 10배) — '월말 하루 무거래'로 유동 종목이 배제되던 것의 해소. 1일치 자 변동계수 7.52 vs 20일-자 6.25. ",
  "[시대] ~2004 12.9% / 2005-09 5.3% / 2010-16 3.5% / 2017~ **0.42%** — 불일치는 초기표본 집중. 440개월 중 37개월 불일치 0(구조적 면역).")
e$census <- paste0(
  "호출부 149건 / 145파일 (fixed=TRUE 스캔, 양성대조 통과). ★**103건(69%)이 rawdata 를 월말-slim 으로 넘겨 20일 자를 원리적으로 계산 불가**. ",
  "교차표: 월말-slim ∧ liq_wired = **51건(34.2%)** ← 잘못 라벨된 1일치 자가 실제 필터로 작동하던 자리. 일간 ∧ liq_wired = 23건. ",
  "→ 함수가 입력 관측단위를 실측 분기하고 계산 불가 시 liq_ruler='adv1_sameday_DEGRADED' 로 warning+라벨 자백. ",
  "★즉 이 수리는 69% 사이트에서 결함을 *해소*한 게 아니라 *가시화*했다. 실질 교정 범위 = 일간 46 사이트.")
e$verdict_impact <- paste0(
  "④ 실측 앵커: WT-001 미필터 패널(86,942행·295개월) top-25 A/B(canonical_screen_bt) — 선별 변화 103/295개월(34.9%)·평균 0.61종목/월, ",
  "**PORT_t 자A 2.1969 → 자B 2.0684 (Δ −0.1285)** — 구판 자가 성과를 부풀리고 있었다. HARD 2.95 판정은 이 건 불변(둘 다 FAIL). ",
  "뒤집힘 후보 = 기록 PORT_t 353건 중 |t−2.95|<=0.30 인 **8건(2.27%)**, 나머지 345건 면역. ",
  "★8건 중 5건이 RAMP_R10/R11/R12/R14/R15 — 이 계약 함수 소비 경로에 정확히 집중(확증적 정합). 단 그 5건은 slim 경로라 교정만으로는 불변. ",
  "실무 위험은 PASS→FAIL 방향인 R28_FQ041_C06_FROZEN_PRUNING(3.058) 1건 + WT-D20260714_006(2.739). ",
  "★목록은 '뒤집힐 수 있다'이지 '뒤집혔다'가 아니다. 밴드 0.30 은 단일 A/B 관측(Δ0.1285)의 2.3배 — **하한이지 전수 아님**. 재판정 여부 = 도훈 결정. 소급 재작성 없음.")
e$production_spotcheck <- paste0(
  "⑤ STR_1715_on_M4gAE_R05_noLayer4_PG2 · as_of 2026-08-01 · 기준거래일 2026-07-31 (05_Production read-only). ",
  "보유 20종목 20일-자 min 2.94e9 · median 5.51e10 · **2e8 미달 0종목 → CLEAN(실측 확정)**. CASH 1행은 자 미산출(정상).")
e$dohoon_decision <- paste0(
  "★결정 요청 2건. ",
  "(1) **방향**: 교정이 net-looser 다(+3.066%p 순통과). 문턱 2e8·유니버스·비용·종목수 어느 제약도 불변이고 자만 헌법 정의로 바꿨으므로 '완화'는 아니나, ",
  "지시문의 명시적 기대(조이는 방향만)와 어긋나므로 단독 판단하지 않고 상신한다. ",
  "(2) **재판정**: 위 후보 8건(특히 PASS 쪽 R28_FQ041_C06) 재실행 여부.")
e$next_action <- paste0(
  "①호출부 전환(월말-slim 51건 liq_wired): 선행 조건 = asof_close() 의 sig_date 당 전체스캔 제거 — 그 비용이 slim 관용구의 원인이다. ",
  "②저장소 전역 자 통일: frollmean(.,20,align='right') 당일포함 관용구가 STR/alpha_search 다수 — shift 단독 효과는 0.369%(작지만 자가 셋으로 갈림). ",
  "③ppure_paper_track.R:137-153 이 결함 자(as-of 월말 Vol*Close)를 터미널월 보충용으로 **수기 복제**해 놓았다 — 정합 필요. ",
  "④canonical_screen_bt 의 `is.na(adv)|adv>=liq_min` 이 NA 를 통과시킨다(결손→완화 구조) — 라벨 기반 fail-closed 검토. ",
  "⑤워밍업 잔여 구멍: 교정 후에도 종목 첫 관측 2건은 adv=NA 로 통과.")
Q$entries[[ix]] <- e

write_frontier_queue(Q)
cat("[after] 기록 완료\n")

## 재읽기 검증
Q2 <- read_frontier_queue()
ix2 <- which(vapply(Q2$entries, function(e) identical(e$id, "FQ-181"), logical(1)))
cat(sprintf("[verify] status=%s · resolved=%s · 항목수 %d (before %d)\n",
            Q2$entries[[ix2]]$status, Q2$entries[[ix2]]$resolved,
            length(Q2$entries), length(Q$entries)))
