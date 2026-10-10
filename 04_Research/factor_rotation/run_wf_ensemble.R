#!/usr/bin/env Rscript
# =============================================================================
# run_wf_ensemble.R — Factor Rotation Mode 핵심: anchored walk-forward 앙상블 백테 → FR.
# 모듈 NAV(sim_result) → 국면 조건부 배분(module_dispatcher) → 합성 → build_bt_result(실측)
#   → essence_score(DSR HARD) → FR_XXXX 등재 → OOS retention + placebo 게이트.
#
# ★ FIX #1 (도훈 수용, 2026-06-05): 포트 수익률 자체합성 폐기 → PerformanceAnalytics::Return.portfolio.
#   모듈=asset, 월별 regime weights=월초 적용·월중 frozen(=monthly rebalance), 일간 모듈수익=R.
#   prod(1+r)/cumprod/손Σ 전부 제거. 월 집계는 apply.monthly/Return.cumulative(계약 표준).
#   15bps 국면전환 turnover 비용은 Return.portfolio weight 전이로 산정 후 리밸 시점 차감(정직).
#
# ★ FIX #2 (도훈 a안, 2026-06-05): RCMA를 walk-forward로. compute_rcma(asof)를 연 1회(직전 기간말)
#   재호출 → 그 시점 admitted_by_regime로 풀/국면 후보 제한. 멤버십 시간가변(미래정보 無).
#   정적 module_regime_admission.json은 진단용 — 실측 권위는 본 스크립트의 WF compute_rcma 호출.
#
# PIT: 가중은 IS(t 이전)로만, 모듈 frozen. 실측-only(자체합성 없음, 계약 경유).
#   ★C11(2026-09-24 · 판정서 V-06 · ② 규약 b/c): 국면 라벨은 날짜 라벨·1행 lag 가 아니라 **가용일**로 붙인다 —
#   월 배분 = 직전(+추가지연) 월말 RM 종가 결정(c) · IS 국면 IR = 일간 수익 창 시작(RM 직전 행)까지 가용(b).
#   가용일 열 없는 legacy 패널 = 기본 중단 · QVEST_C11_LEGACY_REGIME=label = 구판 재현(등재·L-code 끔 · _c11legacy).
#
# ★v4 측정 수리(2026-09-24 · 결정 CALMAR-FREQ-DAILY · FR-REMEASURE-PREREG · FR 시리즈 감사 wf_d1890719-231):
#   ① 등급 = **일간** bt_result(Return.portfolio 일간 net = 일간 모듈 수익 × 월초 비중·월중 드리프트) → essence.
#      월간 bt_result 의 essence 는 diagnostic_monthly 로 병기만(판정 인용 금지). 1계층(run_paper_replication 일간)과 같은 축.
#   ② 배분 결정일 = 직전 월말 RM 날짜를 **한국 거래일(trading_calendar)로 내린 날** → 그 날까지 가용한 라벨(as-of).
#      구판 = 월말 날짜 정확 일치 병합이라 월말이 일요일(주말 라벨 모듈 행)이면 NA → NEUTRAL 강제. 평가 월 NEUTRAL 강제 = 중단.
#   ③ 사망 모듈(r1 · 2026-09-25 적대 검증 BLOCKING 수리 — PIT C1/C6): **결정 시점에 이미 끝난** 모듈만 편입 제외
#      (데이터 종료일 < 결정일 = 직전 월말 RM 날짜를 한국 거래일로 내린 날). r0 는 '홀딩월 마지막 평가일'로 걸러 결정 시점에
#      살아 있던 모듈을 그 달 시작부터 뺐다(월중 사망 선견). 월중 사망 = 관측일(데이터 종료 뒤 첫 한국 거래일 — 그 날 종가에
#      '수익 없음'이 관측된다) 종가에 그 모듈의 드리프트 비중을 생존 보유 모듈로 비례 재배분하는 리밸 행(15bps 회전 비용 반영).
#      종료일~관측일(포함) 현금은 관측 지연이라 불가피(기록). HARD 사후검사 = 관측일 **뒤** 비중 > 0 모듈·일 0건(Return.portfolio
#      BOP 비중 기준) + 재배분 행 = Return.portfolio EOP 재도출 일치. EW 기준선도 같은 규칙.
#   ④ 단일 창: 평가 창 = [max(포트 시작, 벤치 시작), min(RM 끝, 벤치 끝)] — 벤치를 포트 날짜 격자로 옮겨(같은 달 안에서만,
#      뒤로 누적) SR·Calmar·CAGR·MDD·PORT_t·OOS 가 **같은 날짜 집합**을 쓴다(구판 = 성과 219월 · 벤치 병합 213월).
#   ⑤ FR_REGISTER 기본 = 0(등재는 FR_REGISTER=1 명시 때만 — 사전등록 재측정 전 정본 덮어쓰기 방지).
#   분해 대조 = FR_V4_ABLATE=<daily_grade,dispatch_kr_floor,dead_exclude,single_window,canonical_bench|all> (진단 전용 — 등재·L-code 끔 · _v4ablate 태그).
#
# ★v4r2 정본 벤치 + 격자 감사 HARD(2026-10-10 · 감사 2026-10-08 I7 · 설계 l2_role_rotation_redesign_20261010 §4-2):
#   벤치 = .cache/benchmark.parquet BM_Ret(정본) — 1계층 하네스와 같은 규약(replication_harness.R:317 = 수익일과 **같은 날짜**의
#   정본 BM_Ret). 구판(2026-06-05 '가장 긴 bm_xts')은 그 모듈의 날짜 라벨을 벤치에 그대로 들였다 — 실측 10-10: 원천 STR_943 의
#   bm_xts 는 정본 대비 +1일(라벨 d = 정본 d+1 의 수익 · 상관 0.961 · 0일 상관 ≈0) · 레거시 QEPM 7개 전부 +1일. GRID_LAG 는 기록만 했다.
#   격자 감사 = HARD(fail-closed): 풀 모듈 bm_xts 의 정본 대비 시차(−1/0/+1일 상관 최대)가 0 이 아니거나 판독 불가(NA)면 중단하고,
#   일간 격자(한국 거래일)에 정본 벤치 관측이 옮겨져야 놓인다면(격자 불일치) 중단한다. 분해 대조 canonical_bench = 구판 재현.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
CD <- file.path(PROJ, "02_Infrastructure/contracts")
source(file.path(PROJ, "02_Infrastructure/portfolio/module_dispatcher.R"))
.RCMA_FUNC_ONLY <- TRUE                                   # ★ admission 스크립트 = 함수만(정적 JSON 재작성 안 함)
source(file.path(PROJ, "02_Infrastructure/portfolio/regime_module_admission.R"))
source(file.path(CD, "backtest_result_contract.R")); source(file.path(CD, "audit_bt_result.R")); source(file.path(CD, "essence_score.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
sr <- function(r){ r<-r[is.finite(r)]; if(sd(r)==0) return(NA); mean(r)/sd(r)*sqrt(12) }
MIN_IS_MONTHS <- 60L; MIN_MODULES <- 3L; RCMA_REFIT_MONTHS <- 12L   # RCMA 멤버십 연 1회 재호출
# ★ FIX (breadth sanity, 2026-06-05): OOS 시작점은 임의(2016 절단)도 무근거(1995)도 아닌,
#   모듈 breadth(그 달 가용 모듈 수)가 충분치 이상인 첫 달로 근거 있게 잡는다.
#   1990~2001 KR 구간은 backfill 모듈 4~7개뿐(thin) → 앙상블 비대표적(MDD·oos_retention 폭주 원인).
#   진단(2026-06-05): breadth≥10 첫 달 = 200203, ≥15 = 200307, full ~78모듈 = 2005-06+.
MIN_BREADTH_OOS <- 10L   # OOS 평가 시작 = 그 달 가용 모듈 ≥ 이 값인 첫 달 (근거: avail_by_m 진단)

# ── ★2026-09-12 (2계층 FR_003 라운드) 최소 파라미터화 — 기본값은 전부 구동작 보존 ───────────
#   왜: 러너가 fr_id 를 "FR_001" 로 못박고 있어 새 리서치 1단위를 돌리면 이전 등재를 덮는다.
#       또 대조군(arm_C)·PIT 스트레스(arm_S)를 같은 러너로 돌리려면 등재를 꺼야 한다.
#   원칙: 하나도 기본값을 바꾸지 않는다(FR_RUN_ID 미설정 = FR_001, 등재 ON, 추가지연 0).
FR_RUN_ID   <- Sys.getenv("FR_RUN_ID", "FR_001")                      # 등재/산출 파일 식별자
# ★v4 ⑤(2026-09-24 · FR-REMEASURE-PREREG): 기본 = 등재 안 함. "1" 일 때만 등재(2계층 레인 T arm 은 명시 "1" 을 넘긴다 —
#   rf_l2_lib.R::l2_run_arm). 구판 기본 ON 은 FR_RUN_ID 기본 FR_001 과 겹쳐 수동 실행 1회가 정본 FR_001 등재를 덮었다.
FR_REGISTER <- identical(Sys.getenv("FR_REGISTER", "0"), "1")         # 1 = 레지스트리 등재(명시 때만) · 그 밖 = 생략
FR_ARM_TAG  <- Sys.getenv("FR_ARM_TAG", "")                            # 진단 산출물 라벨
# ★v4 분해 대조(진단 전용): 켜진 수리를 하나씩 끈 판을 같은 러너로 재 **구판·신판 차이를 항목별로 분해**한다.
#   빈 값 = 수리 전부 켬(정본). 알 수 없는 토큰 = 중단(조용한 통과 금지). 끈 판은 등재·L-code 끔 + FR_ID 에 _v4ablate 표식.
FR_V4_FIXES <- c("daily_grade", "dispatch_kr_floor", "dead_exclude", "single_window", "canonical_bench")
.v4_ab <- trimws(strsplit(Sys.getenv("FR_V4_ABLATE", ""), ",", fixed = TRUE)[[1]]); .v4_ab <- .v4_ab[nzchar(.v4_ab)]
if (identical(.v4_ab, "all")) .v4_ab <- FR_V4_FIXES
if (length(setdiff(.v4_ab, FR_V4_FIXES)))
  stop(sprintf("[FR v4] FR_V4_ABLATE 알 수 없는 토큰: %s — 허용 = %s | all", paste(setdiff(.v4_ab, FR_V4_FIXES), collapse = ","),
               paste(FR_V4_FIXES, collapse = ",")))
FIX <- setNames(as.list(!(FR_V4_FIXES %in% .v4_ab)), FR_V4_FIXES)       # TRUE = 수리 켬
FR_V4_ABLATED <- length(.v4_ab) > 0L
if (FR_V4_ABLATED) {
  FR_REGISTER <- FALSE
  ## 태그 = 끈 수리의 한 글자 코드(D 일간등급 · K 결정일 한국거래일 · X 사망모듈 · W 단일창 · B 정본 벤치) — 경로 길이(Windows 260자) 안.
  .v4_code <- c(daily_grade = "D", dispatch_kr_floor = "K", dead_exclude = "X", single_window = "W", canonical_bench = "B")
  FR_ARM_TAG <- paste0(if (nzchar(FR_ARM_TAG)) paste0(FR_ARM_TAG, "_") else "", "v4ablate-", paste(sort(.v4_code[.v4_ab]), collapse = ""))
  cat(sprintf("[FR v4] ★분해 대조(진단 전용) — 끈 수리: %s · 등재·L-code 끔 · FR_ARM_TAG=%s\n", paste(sort(.v4_ab), collapse = ","), FR_ARM_TAG))
}
# 국면신호 추가 지연(개월). 0 = 기본(전월말 Category). 1 = lag-1 스트레스(전전월말) — C5 동월누출 판별.
FR_EXTRA_REGIME_LAG <- suppressWarnings(as.integer(Sys.getenv("FR_EXTRA_REGIME_LAG", "0"))); if (is.na(FR_EXTRA_REGIME_LAG)) FR_EXTRA_REGIME_LAG <- 0L
FR_DIAG_DIR <- Sys.getenv("FR_DIAG_DIR", "")                           # 비면 진단 덤프 생략

# 1. 모듈 풀 + 일간 수익 매트릭스 -----------------------------------------------
# ★2026-09-21 (2계층 무인 레인 · 플랜 Part 3 D2) FR_MODULE_PERF — 대조 arm(floor-only)·잘린 풀을 **정본 파일을 바꿔치기하지 않고** 재는 통로.
#   미설정 = 정본 경로(구동작). regime_module_admission.R::.rcma_load 도 같은 env 를 읽는다(두 경로가 같은 풀을 봐야 한다).
FR_MODULE_PERF <- Sys.getenv("FR_MODULE_PERF", "")
MP <- fromJSON(if (nzchar(FR_MODULE_PERF)) FR_MODULE_PERF else file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules)
# RCMA context (active 일간 시계열 1회 로드 — compute_rcma(asof)가 슬라이스). WF 멤버십 = PIT.
RCMA_CTX <- tryCatch(.rcma_load(PROJ), error=function(e){ cat("[RCMA] load 실패:", conditionMessage(e), "\n"); NULL })
rets <- list(); bmref <- NULL; bmref_src <- NA_character_; bmref_n <- 0L
# ★v4 격자 감사: 일간 등급은 모듈 간 날짜 격자가 어긋나면(주말 라벨 모듈 — STR_944 계열) 월간보다 민감하다.
#   모듈 bm_xts 를 정본 벤치(.cache/benchmark.parquet BM_Ret)와 −1/0/+1일 시차로 상관 → 최대 시차 = 그 모듈 날짜 라벨의 어긋남.
#   ★v4r2(2026-10-10 · I7): 기록만 하던 감사를 **중단**으로 올렸다(아래 [FR bench ★격자]) — 분해 대조 canonical_bench 만 구판(기록만).
#   (bm_xts 를 쓰는 이유: 순수 벤치 계열이라 맞는 시차에서 상관 ≈1 · 틀린 시차 ≈0 으로 갈린다. 수익 계열 상관은 음(−)베타
#    모듈(방어형 · 실측 RP_20260902_122546_22268 0일 −0.38)에서 부호 argmax 가 틀린 시차를 고른다.)
.CANON_BM_PATH <- file.path(PROJ, ".cache/benchmark.parquet")
.CANON_BM <- tryCatch({ x <- as.data.table(read_parquet(.CANON_BM_PATH, col_select = c("Date", "BM_Ret"), mmap = FALSE))
  x[, Date := as.Date(Date)]; x <- x[is.finite(BM_Ret)]; setorder(x, Date); x }, error = function(e) NULL)
if (isTRUE(FIX$canonical_bench) && (is.null(.CANON_BM) || !nrow(.CANON_BM) || anyDuplicated(.CANON_BM$Date)))
  stop(sprintf("[FR bench] 정본 벤치 %s 판독 불가·빈 파일·중복 날짜 — 모듈 bm_xts 로 대체하지 않는다(fail-closed · 감사 I7)", .CANON_BM_PATH))
.grid_lag <- function(bx) {
  if (is.null(.CANON_BM) || is.null(bx) || !NROW(bx)) return(NA_integer_)
  b <- data.table(Date = as.Date(index(bx)), v = as.numeric(bx[, 1]))[is.finite(v) & v != 0]
  cs <- vapply(c(-1L, 0L, 1L), function(L) { m <- merge(b[, .(Date = Date + L, v)], .CANON_BM, by = "Date")
    if (nrow(m) < 3L) NA_real_ else suppressWarnings(cor(m$v, m$BM_Ret)) }, numeric(1))
  if (!any(is.finite(cs))) NA_integer_ else c(-1L, 0L, 1L)[which.max(cs)]
}
GRID_LAG <- integer(0)
for(sid in mod_ids){
  p <- file.path(PROJ, MP$modules[[sid]]$sim_result_path)
  s <- tryCatch(readRDS(p), error=function(e) NULL); if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  rets[[sid]] <- d
  GRID_LAG[[sid]] <- tryCatch(.grid_lag(s$bm_xts), error = function(e) NA_integer_)
  # (구판 · 분해 대조 canonical_bench 전용) ★ FIX (benchmark 절단 방지, 2026-06-05): 모든 모듈의 bm_xts = 동일 KOSPI200 지수(span만 상이).
  #   "첫 모듈" 휴리스틱은 단기 bm(2016~)을 잡아 FR 평가를 60개월로 silent 절단 → *가장 긴* bm_xts 채택.
  #   ★v4r2: 이 경로는 그 모듈의 날짜 라벨까지 벤치로 들였다(I7) — 정본 경로는 아래에서 .CANON_BM 을 쓴다.
  if(!isTRUE(FIX$canonical_bench) && !is.null(s$bm_xts) && nrow(s$bm_xts) > bmref_n){
    bmref <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
    bmref_n <- nrow(s$bm_xts); bmref_src <- sid }
}
mod_ids <- names(rets)
if (isTRUE(FIX$canonical_bench)) {
  ## ★v4r2 정본 벤치: 1계층 하네스 규약 그대로 — 수익일 d 의 벤치 = 정본 BM_Ret(d). 일간 격자 배치는 §5 (.to_grid · 이동 0 이어야 한다).
  bmref <- .CANON_BM[, .(Date, bm = BM_Ret)]
  bmref_n <- nrow(bmref); bmref_src <- "canonical:.cache/benchmark.parquet"
  ## ★격자 감사 HARD(fail-closed): 풀의 모든 모듈이 정본 격자(시차 0)여야 한다. 판독 불가(bm_xts 없음·상수·겹침 부족 = NA)도 중단 —
  ##   확인하지 못한 정렬은 정렬이 아니다. 시차 +1 = 라벨 d 가 정본 d+1 의 수익(레거시 QEPM 7개 실측) → 일간 결합·등급이 하루 밀린다.
  .gl_pool <- GRID_LAG[mod_ids]; names(.gl_pool) <- mod_ids
  .gl_bad <- mod_ids[is.na(.gl_pool) | .gl_pool != 0L]
  if (length(.gl_bad))
    stop(sprintf(paste0("[FR bench ★격자] 풀 모듈 %d/%d개의 날짜 라벨이 정본 벤치 격자와 어긋나거나 확인 불가 — %s%s ",
                        "(시차 = 모듈 bm_xts 의 정본 BM_Ret 대비 −1/0/+1일 상관 최대 · NA = bm_xts 없음/상수/겹침 부족). ",
                        "수리 = 풀을 close_t1 단일 규약으로 재조립(build_module_performance.R) · 구판 재현(진단) = FR_V4_ABLATE=canonical_bench"),
                 length(.gl_bad), length(mod_ids),
                 paste(sprintf("%s(%s)", head(.gl_bad, 10L), ifelse(is.na(.gl_pool[head(.gl_bad, 10L)]), "NA",
                                                                     sprintf("%+d일", .gl_pool[head(.gl_bad, 10L)]))), collapse = ", "),
                 if (length(.gl_bad) > 10L) sprintf(" 외 %d개", length(.gl_bad) - 10L) else ""))
  cat(sprintf("[bm] benchmark source=%s (정본 · 1계층 하네스 규약 = 같은 날짜 BM_Ret) span %s..%s n=%d · 격자 감사 HARD 통과(풀 모듈 %d개 시차 0)\n",
              bmref_src, as.character(min(bmref$Date)), as.character(max(bmref$Date)), bmref_n, length(mod_ids)))
} else if(!is.null(bmref)) cat(sprintf("[bm] ★분해 대조(canonical_bench 끔) benchmark source=%s (longest bm_xts — 구판 · I7 결함 재현) span %s..%s n=%d\n",
  bmref_src, as.character(min(bmref$Date)), as.character(max(bmref$Date)), bmref_n))
if(is.null(bmref)) stop("benchmark 부재")
# ★v4 ③ 모듈 데이터 종료일 = 0 이 아닌 유한 수익이 기록된 마지막 날 — 이 날 뒤로는 그 모듈의 수익이 없다
#   (구판은 데이터 끝 뒤 NA 를 0 = 현금으로 채웠다). 끝에 붙은 정확히 0 인 연속 행도 같은 채움으로 본다(생산자가 0 으로 덧댄 판 방어 —
#   2026-09-24 실측 풀 654모듈 중 끝 0 행 보유 1모듈·1행).
MOD_END <- as.Date(vapply(mod_ids, function(s) { d <- rets[[s]]; k <- is.finite(d$r) & d$r != 0
  if (any(k)) as.numeric(max(d$Date[k])) else NA_real_ }, numeric(1)), origin = "1970-01-01")
names(MOD_END) <- mod_ids
MOD_END_FINITE <- as.Date(vapply(mod_ids, function(s) { d <- rets[[s]]; as.numeric(max(d$Date[is.finite(d$r)])) }, numeric(1)), origin = "1970-01-01")
N_TRAILING_ZERO_MODULES <- sum(MOD_END < MOD_END_FINITE, na.rm = TRUE)
MODS_NO_RETURN <- mod_ids[is.na(MOD_END)]                            # 0 이 아닌 수익이 한 번도 없는 모듈 = 수익 없음 → 풀에서 뺀다(기록)
# ★v4 ③ r1: 모듈 사망 규칙의 시간축 — 결정일(편입 제외 판단)·관측일(월중 재배분 시점)은 한국 거래일 달력으로 잡는다.
#   (국면 결정일 dec_date 와 별개 — 국면 추가지연 스트레스는 국면 라벨만 늦추고 편입 판단 시점은 그대로 직전 월말 종가다.)
.KR_CAL_I <- tryCatch(sort(unique(as.integer(as.Date(read_parquet(file.path(PROJ, ".cache/trading_calendar.parquet"), col_select = "Date",
                                                                   mmap = FALSE)$Date)))), error = function(e) integer(0))
.mod_decision_date <- function(d) {                                   # 결정일 = d 이하 마지막 한국 거래일(달력 없으면 d)
  if (!length(.KR_CAL_I) || is.na(d)) return(as.Date(d))
  k <- findInterval(as.integer(d), .KR_CAL_I); if (k > 0L) as.Date(.KR_CAL_I[k], origin = "1970-01-01") else as.Date(d)
}
.mod_obs_day <- function(d) {                                         # 관측일 = 데이터 종료일 뒤 첫 한국 거래일(달력 끝 뒤 = NA)
  if (!length(.KR_CAL_I) || is.na(d)) return(as.Date(NA))
  k <- findInterval(as.integer(d), .KR_CAL_I) + 1L; if (k <= length(.KR_CAL_I)) as.Date(.KR_CAL_I[k], origin = "1970-01-01") else as.Date(NA)
}
if (length(MODS_NO_RETURN) && !isTRUE(FIX$dead_exclude)) {
  MOD_END[MODS_NO_RETURN] <- MOD_END_FINITE[MODS_NO_RETURN]              # (분해 대조 = 구판처럼 풀에 남김)
} else if (length(MODS_NO_RETURN)) {
  cat(sprintf("[v4 ③] ★수익 기록 없는 모듈 %d개 풀 제외: %s\n", length(MODS_NO_RETURN), paste(MODS_NO_RETURN, collapse = ",")))
  rets[MODS_NO_RETURN] <- NULL; mod_ids <- names(rets); MOD_END <- MOD_END[mod_ids]
  if (!length(mod_ids)) stop("[FR v4 ③] 수익이 있는 모듈이 없다")
}
MOD_OBS <- as.Date(vapply(mod_ids, function(s) as.numeric(.mod_obs_day(MOD_END[[s]])), numeric(1)), origin = "1970-01-01")
names(MOD_OBS) <- mod_ids
if (isTRUE(FIX$dead_exclude) && !length(.KR_CAL_I)) stop("[FR v4 ③] trading_calendar 판독 불가 — 사망 모듈 결정일·관측일을 한국 거래일로 잡을 수 없다")
# wide daily matrix
RM <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE), lapply(names(rets), function(s){ x<-copy(rets[[s]]); setnames(x,"r",s); x }))
setorder(RM, Date)
# ★v4 ④ 평가 창 끝 = min(RM 끝, 벤치 끝). 벤치가 끝난 뒤의 달은 PORT_t·OOS 에 못 들어가므로 SR·Calmar 에서도 뺀다
#   (구판: 성과 계열은 벤치 끝 뒤 3개월을 더 담아 두 지표군이 다른 창을 썼다). 창 시작은 포트 계열이 선 뒤 정한다(§5).
RM_END_RAW <- max(RM$Date); EVAL_END <- if (isTRUE(FIX$single_window)) min(RM_END_RAW, max(bmref$Date)) else RM_END_RAW
if (EVAL_END < RM_END_RAW) {
  cat(sprintf("[v4 창] 평가 창 끝 = 벤치 끝 %s (RM 끝 %s — 그 뒤 %d일 제외)\n", as.character(EVAL_END), as.character(RM_END_RAW),
              RM[Date > EVAL_END, .N]))
  RM <- RM[Date <= EVAL_END]
}
# 공통 기간: 월별 ≥MIN_MODULES 모듈 가용
RM[, ym := format(Date,"%Y%m")]
avail_by_m <- RM[, .(navail = sum(sapply(.SD, function(c) any(is.finite(c))))), by=ym, .SDcols=mod_ids]
setorder(avail_by_m, ym)
good_ym <- avail_by_m[navail >= MIN_MODULES, ym]
RM <- RM[ym %in% good_ym]
# ★ breadth gate: OOS 평가는 breadth ≥ MIN_BREADTH_OOS 인 첫 달부터 (근거 있는 시작점). thin 초기구간 배제.
breadth_ok_ym <- avail_by_m[navail >= MIN_BREADTH_OOS, ym]
OOS_START_YM  <- if(length(breadth_ok_ym)) min(breadth_ok_ym) else min(good_ym)
OOS_START_BREADTH <- avail_by_m[ym==OOS_START_YM, navail]
cat(sprintf("[1] modules=%d  daily rows=%d  months=%d (%s..%s)\n", length(mod_ids), nrow(RM), uniqueN(RM$ym), min(RM$ym), max(RM$ym)))
cat(sprintf("[1b] breadth gate: OOS 시작 = %s (그 달 모듈 %d개 ≥ MIN_BREADTH_OOS=%d) — thin 초기구간(4~7모듈) 배제\n", OOS_START_YM, OOS_START_BREADTH, MIN_BREADTH_OOS))

# 2. 월간 regime + 월말 인덱스 — ★C11 규약 (c)·(b)(2026-09-24 · 판정서 V-06) -------------
#   구판: 전월말 날짜 라벨의 Category(미국 같은 날 세션·미공표 주간값을 담은 행 — V-05)를 그대로 쓰고,
#         IS 국면 IR 은 Category 1행 lag 을 일간 수익에 붙였다(미국 t-1 세션 약 14시간 누출).
#   현행: 배분 결정일 dec_date = 직전(+추가지연) 월말 RM 날짜 종가(규약 c — 이 배분의 수익 창은 그 뒤에 시작).
#         그 날까지 가용한(avail_date <= dec_date) 최신 Category. IS 국면 IR = 규약 (b)(RG_EXPO).
.WF_C11 <- local({
  gp <- file.path(PROJ, "02_Infrastructure/validation/overlay_pit_guard.R")
  if (!file.exists(gp)) stop("[C11] overlay_pit_guard.R 부재 — 가용시점 관문 없이 국면 배분을 돌릴 수 없음")
  e <- new.env(parent = globalenv()); sys.source(gp, envir = e)
  if (!exists("c11_asof_align", envir = e, inherits = FALSE)) stop("[C11] overlay_pit_guard.R 에 C11 층 없음(구판)")
  e
})
RG0 <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[!is.na(Category)]
RG0[, Date := as.Date(Date)]
C11G <- .WF_C11$c11_legacy_gate(RG0, "Category", site = "run_wf_ensemble",
                                source_desc = ".cache/unified_regime_signal_daily.parquet")
C11_LEGACY_RUN <- isTRUE(C11G$legacy)
.c11_mark_legacy_run <- function() {
  FR_REGISTER <<- FALSE
  if (!grepl("c11legacy", FR_ARM_TAG, fixed = TRUE))
    FR_ARM_TAG <<- if (nzchar(FR_ARM_TAG)) paste0(FR_ARM_TAG, "_c11legacy") else "c11legacy"
  cat("[C11] ★legacy 재현(label 정책) — 등재·L-code 발행 끔 · 산출 파일명 _c11legacy · 결과는 C11 미해소\n")
}
if (C11_LEGACY_RUN) .c11_mark_legacy_run()
RG <- RG0[, .(Date, Category)]
me <- RM[, .(me_date=max(Date)), by=ym]; setorder(me, me_date)
RG_EXPO <- NULL
if (C11_LEGACY_RUN) {
  mreg <- merge(me, RG, by.x="me_date", by.y="Date", all.x=TRUE)
  setorder(mreg, me_date)
  mreg[, regime_lag := shift(Category, 1L + FR_EXTRA_REGIME_LAG)]       # (구판) 전월말 날짜 라벨 → 이번달
  mreg[, sig_cutoff := shift(me_date, 1L + FR_EXTRA_REGIME_LAG)]
  mreg[, `:=`(dec_date = sig_cutoff, sig_avail = as.Date(NA))]
  mreg[, dec_date_raw := dec_date]
} else {
  .kr_cal <- as.Date(read_parquet(file.path(PROJ, ".cache/trading_calendar.parquet"), col_select = "Date", mmap = FALSE)$Date)
  mreg <- copy(me); setorder(mreg, me_date)
  mreg[, dec_date := shift(me_date, 1L + FR_EXTRA_REGIME_LAG)]         # 결정일(규약 c) · +추가지연 = lag 스트레스
  mreg[, dec_date_raw := dec_date]
  # ★v4 ② 결정일을 그 날 이하 마지막 **한국 거래일**로 내린다. 월말 RM 날짜는 주말 라벨 모듈(STR_944 계열 일요일 행) 때문에
  #   일요일일 수 있다 — 구판(월말 날짜 정확 일치 병합)은 그 달 라벨을 못 찾아 NA → NEUTRAL 로 강제했다(FR 감사).
  #   as-of 결합만으로도 NA 는 사라지지만 '결정 = 한국 종가' 규약(c)을 날짜 자체로 못박는다. 달력 밖(달력 끝 뒤) = 중단.
  if (isTRUE(FIX$dispatch_kr_floor)) {
    .cal_i <- sort(unique(as.integer(.kr_cal)))
    if (!length(.cal_i)) stop("[FR v4 ②] trading_calendar 가 비었다 — 결정일을 한국 거래일로 내릴 수 없음")
    .dd <- as.integer(mreg$dec_date); .ix <- findInterval(.dd, .cal_i)
    if (any(!is.na(.dd) & .dd > max(.cal_i)))
      stop(sprintf("[FR v4 ②] 결정일 %s 이 trading_calendar 끝(%s) 뒤 — 달력 갱신 후 재실행(낡은 달력으로 내리면 결정일이 조용히 앞당겨진다)",
                   as.character(max(mreg$dec_date, na.rm = TRUE)), as.character(as.Date(max(.cal_i), origin = "1970-01-01"))))
    .fl <- rep(NA_integer_, length(.dd)); .okf <- !is.na(.dd) & .ix > 0L; .fl[.okf] <- .cal_i[.ix[.okf]]
    mreg[, dec_date := as.Date(.fl, origin = "1970-01-01")]
    cat(sprintf("[v4 ②] 배분 결정일 한국 거래일 내림: %d개월 이동(주말·비거래 월말)\n", sum(mreg$dec_date != mreg$dec_date_raw, na.rm = TRUE)))
  }
  .lab_m <- .WF_C11$c11_asof_align(mreg$dec_date, RG0, "Category")
  mreg[, `:=`(regime_lag = .lab_m$value, sig_cutoff = .lab_m$src_date, sig_avail = .lab_m$avail_date)]  # ★C5: 실제로 쓴 라벨 날짜 · 가용일
  # ★r1(2026-09-24 · V4 B1): 규약 (b) 창 시작 = **모듈 자기 계열**의 직전 행. 구판(r0)은 RM 합집합의 직전 행을 썼다 —
  #   모듈에 결측 공백이 있으면 합집합 직전 행이 자기 직전 행보다 늦어 수익 창 안의 정보가 라벨에 들어갔다
  #   (V4 실측: 654모듈 3,415,047 모듈·일 중 767,545행에서 자기 직전 행이 더 이르고, 1,427행은 라벨이 달라짐).
  #   주말 행(STR_944 일요일 등)은 한국 거래일 달력으로 내린다(c11_window_start kr_calendar — 토요일 가용 행의
  #   미국 금 세션이 월요일 수익 창에 들어가지 않게). RCMA·module_performance 와 같은 모듈별 방식.
  RM_DATES <- RM$Date
  RG_EXPO <- data.table(Date = RM_DATES)
  .dump_is <- nzchar(FR_DIAG_DIR) && identical(Sys.getenv("FR_DIAG_IS_LABELS", ""), "1")   # 검사용 진단(모듈·일 단위라 크다)
  .is_dump <- list()
  for (.sid in mod_ids) {
    .ds <- sort(unique(rets[[.sid]]$Date[!is.na(rets[[.sid]]$Date)]))
    .dec_s <- .WF_C11$c11_window_start(.ds, kr_calendar = .kr_cal)
    .lab_s <- .WF_C11$c11_asof_align(.dec_s, RG0, "Category")
    .WF_C11$assert_overlay_pit_avail(.lab_s$avail_date, .dec_s, sprintf("FR IS regime IR (일간 · 규약 b · %s)", .sid))
    set(RG_EXPO, j = paste0("reg_lag__", .sid), value = .lab_s$value[match(RM_DATES, .ds)])
    if (.dump_is) .is_dump[[.sid]] <- data.table(module = .sid, Date = .ds, dec_date = .dec_s, label = .lab_s$value,
                                                 label_src = .lab_s$src_date, label_avail = .lab_s$avail_date)
  }
  if (.dump_is) { dir.create(FR_DIAG_DIR, showWarnings = FALSE, recursive = TRUE)
    fwrite(rbindlist(.is_dump), file.path(FR_DIAG_DIR, paste0(FR_RUN_ID, "_is_regime_labels.csv"))) }
  cat(sprintf("[C11] IS 국면 IR 라벨 = 모듈별 자기 직전 행(한국 거래일로 내림) · 모듈 %d개
", length(mod_ids)))
}
# ★v4 ② 라벨 부재 → NEUTRAL 채움을 **표식**한다. 평가 월(IS 60개월 뒤 · breadth 게이트 뒤)에서 가용일 경로가 NEUTRAL 을 지어내면 중단 —
#   구판은 일요일 월말의 정확 일치 병합 실패를 조용히 NEUTRAL 로 덮어 그 달 배분 국면을 바꿨다.
mreg[, neutral_forced := is.na(regime_lag)]
mreg[, eval_month := seq_len(.N) > MIN_IS_MONTHS & ym >= OOS_START_YM]
N_NEUTRAL_FORCED_EVAL <- mreg[neutral_forced & eval_month, .N]
if (!C11_LEGACY_RUN && isTRUE(FIX$dispatch_kr_floor) && N_NEUTRAL_FORCED_EVAL > 0L)
  stop(sprintf("[FR v4 ②] 평가 월 %d개에서 가용 국면 라벨 없음(예 %s · 결정일 %s) — NEUTRAL 로 지어내지 않는다(패널 가용일·결정일 점검)",
               N_NEUTRAL_FORCED_EVAL, mreg[neutral_forced & eval_month]$ym[1], as.character(mreg[neutral_forced & eval_month]$dec_date[1])))
if (N_NEUTRAL_FORCED_EVAL > 0L) cat(sprintf("[v4 ②] ★평가 월 NEUTRAL 강제 %d개월(%s — 진단 재현 경로라 중단하지 않음)\n", N_NEUTRAL_FORCED_EVAL,
                                           if (C11_LEGACY_RUN) "C11 legacy 재현" else "FR_V4_ABLATE dispatch_kr_floor"))
mreg[is.na(regime_lag), regime_lag := "NEUTRAL"]
# ── ★C5 오버레이 신호 타이밍 HARD 검사 (pit.md §오버레이 신호 타이밍) ────────────────
#   컷오프(신호가 본 마지막 날) < 홀딩월 첫 거래일 이어야 한다. 홀딩월 = 수익이 벌리는 달 = ym.
local({
  src <- file.path(PROJ, "02_Infrastructure/validation/overlay_pit_guard.R")
  if (!file.exists(src)) stop("[C5] overlay_pit_guard.R 부재 — 관문 없이 국면 오버레이를 돌릴 수 없음")
  source(src, local = TRUE)
  ok <- !is.na(mreg$sig_cutoff)
  ## ym 은 "YYYYMM" — overlay_signal_cutoff 는 "YYYY-MM" 을 기대한다(paste0(ym,"-01")).
  hold_start <- overlay_signal_cutoff(sub("^(\\d{4})(\\d{2})$", "\\1-\\2", mreg$ym[ok]))   # 홀딩월 1일
  if (any(is.na(hold_start))) stop("[C5] 홀딩월 시작일 파싱 실패 — ym 포맷 확인")
  assert_overlay_pit(as.Date(mreg$sig_cutoff[ok]), hold_start, label = "FR regime dispatch")
  ## ★C11(2026-09-24): 라벨 날짜만이 아니라 가용일도 결정일 이하인지 HARD 검사(legacy 재현은 가용일 없음 = 표식만)
  if (!C11_LEGACY_RUN) assert_overlay_pit_avail(mreg$sig_avail, mreg$dec_date, label = "FR regime dispatch (C11 가용일)")
  cat(sprintf("[C5] assert_overlay_pit PASS — n=%d 월, extra_lag=%d, 최대 컷오프-홀딩월시작 간격 %d일\n",
              sum(ok), FR_EXTRA_REGIME_LAG,
              as.integer(max(hold_start - as.Date(mreg$sig_cutoff[ok])))))
})
# ★ Track1-B proactive dispatch (env FR_REGIME_SOURCE=forecast): contemporaneous regime_lag 대신
#   regime_forecaster의 *다음국면 예측*을 dispatch에 사용(reactive→proactive). 예측 NA 월은 regime_lag fallback.
#   forecaster beats_baseline=TRUE 일 때만 의미(아니면 과적합). baseline(category)은 default — FR_001 불변.
REGIME_SOURCE <- Sys.getenv("FR_REGIME_SOURCE", "category")
mreg[, regime_dispatch := regime_lag]                                # default = contemporaneous (baseline)
if(REGIME_SOURCE == "forecast"){
  fcp <- file.path(PROJ,".cache/regime_forecast_series.parquet")
  if(!file.exists(fcp)) stop("FR_REGIME_SOURCE=forecast 인데 regime_forecast_series.parquet 부재 — regime_forecaster.R 먼저 실행")
  FS <- as.data.table(read_parquet(fcp))
  ## ★C11: 예측 계열도 가용일 없으면 legacy(입력 = regime_daily_v2·unified — V-10·V-05) → 정책대로
  .g_fs <- .WF_C11$c11_legacy_gate(FS, "forecast_regime", site = "run_wf_ensemble(forecast)",
                                   source_desc = ".cache/regime_forecast_series.parquet")
  if (isTRUE(.g_fs$legacy) && !C11_LEGACY_RUN) { C11_LEGACY_RUN <- TRUE; .c11_mark_legacy_run() }
  mreg <- merge(mreg, FS, by="ym", all.x=TRUE)
  if (!isTRUE(.g_fs$legacy)) { .fs_ok <- !is.na(mreg$forecast_regime)
    .WF_C11$assert_overlay_pit_avail(as.Date(mreg[[.g_fs$avail_col]])[.fs_ok], mreg$dec_date[.fs_ok], "FR forecast dispatch (C11 가용일)") }
  mreg[!is.na(forecast_regime), regime_dispatch := forecast_regime]  # 예측 가용 월만 override
  setorder(mreg, me_date)                                            # ★ merge 후 순서 복원 (months 인덱스 정합)
  cat(sprintf("[regime] ★ proactive dispatch: forecast %d/%d 월 override (나머지 category fallback)\n",
              mreg[!is.na(forecast_regime), .N], nrow(mreg)))
} else cat("[regime] dispatch source = category (contemporaneous, baseline)\n")

# 3. anchored walk-forward: 월별 가중(IS-only) → 다음달 적용 -------------------
#    weights는 월초(첫 거래일)에 적용·월중 frozen → Return.portfolio가 monthly rebalance로 합성.
months <- mreg$ym
W_rows <- list(); wlog <- list()           # W_rows: rebalance-date별 모듈 weight (Return.portfolio 입력)
diaglog <- list(); admlog <- list()        # ★MC1/MC2 진단 로그
## 방어형 경로로 편입된 모듈 id (module_performance.json 의 admission_route 라벨 — 자체 판정 아님)
DEFENSIVE_IDS <- names(Filter(function(x) identical(as.character(x$admission_route %||% ""),
                                                    "defensive_specialist"), MP$modules))
cat(sprintf("[pool] 풀 %d · 방어형 경로 편입 %d · grade_floor %d · legacy %d\n",
            length(MP$modules), length(DEFENSIVE_IDS),
            sum(vapply(MP$modules, function(x) identical(as.character(x$admission_route %||% ""), "grade_floor"), logical(1))),
            length(MP$modules) - length(DEFENSIVE_IDS) -
              sum(vapply(MP$modules, function(x) identical(as.character(x$admission_route %||% ""), "grade_floor"), logical(1)))))
adm_cache <- NULL; adm_cache_asof <- NULL   # WF RCMA 멤버십 캐시(연 1회 갱신)
months_used <- character(0)
for(i in seq_along(months)){
  if(i <= MIN_IS_MONTHS) next
  m <- months[i]; reg_now <- mreg$regime_dispatch[i]
  if(m < OOS_START_YM) next                                      # ★ breadth gate: 대표성 충분한 첫 달 전 구간은 OOS 미평가
  is_end <- mreg$me_date[i-1]                                    # IS = 이전월말까지
  IS <- RM[Date <= is_end]
  # ── ★ FIX #2: WF RCMA — asof=직전 월말, 연 1회 재호출 → admitted_by_regime(시간가변) ──
  refit_now <- is.null(adm_cache) || is.null(adm_cache_asof) ||
               as.integer((as.Date(is_end)-as.Date(adm_cache_asof))) >= (RCMA_REFIT_MONTHS*30L)
  if(!is.null(RCMA_CTX) && refit_now){
    adm_cache <- tryCatch(compute_rcma(is_end, RCMA_CTX, PROJ), error=function(e){ cat("[RCMA wf] asof",as.character(is_end),"실패:",conditionMessage(e),"\n"); NULL })
    adm_cache_asof <- is_end
  }
  admitted_by_regime <- if(!is.null(adm_cache)) adm_cache$admitted_by_regime else NULL
  admitted_union <- if(!is.null(adm_cache)) adm_cache$admitted_modules else character(0)

  # IS에서 국면조건부 IR + vol (실측, expanding)
  ## ★C11: 가용일 패널 = RG_EXPO(각 일간 수익 창 시작까지 가용한 라벨 · 규약 b) · legacy 재현 = 구판 1행 lag
  if (is.null(RG_EXPO)) { ISr <- merge(IS, RG, by="Date", all.x=TRUE); setorder(ISr, Date); ISr[, reg_lag := shift(Category,1L)]; ISL <- NULL
  } else { ISr <- IS; ISL <- RG_EXPO[match(IS$Date, RG_EXPO$Date)] }                 # r1: 모듈별 라벨 열(reg_lag__<모듈>)
  .reglab <- function(s) if (is.null(ISL)) ISr$reg_lag else ISL[[paste0("reg_lag__", s)]]
  avail <- mod_ids[sapply(mod_ids, function(s) sum(is.finite(ISr[[s]])) >= 250)]   # 최소 1년
  # ★v4 ③ r1 사망 모듈 편입 제외 = **결정 시점에 이미 끝난** 모듈만(데이터 종료일 < 결정일 = 직전 월말 RM 날짜의 한국 거래일 내림).
  #   r0(hold_end 기준)는 결정 시점에 살아 있던 월중 사망 모듈을 그 달 시작부터 뺐다 = 홀딩월 정보로 배분(C1/C6 선견 · 적대 검증 BLOCKING).
  #   월중 사망은 §3b 가 관측일 종가 재배분으로 처리한다. 뒤의 풀 제한·MIN_MODULES 폴백도 결정 시점 생존 모듈 기준.
  hold_end <- RM[ym==m, max(Date)]
  excl_date <- .mod_decision_date(is_end)
  n_dead_excl <- 0L
  if (isTRUE(FIX$dead_exclude)) {
    .dead <- avail[MOD_END[avail] < excl_date]
    n_dead_excl <- length(.dead); avail <- setdiff(avail, .dead)
  }
  # ★ FIX #2: admitted union으로 풀 제한(≥MIN_MODULES일 때만 — cold-start 정직: 부족 시 broad pool)
  if(length(admitted_union) >= MIN_MODULES){ pool_u <- intersect(avail, admitted_union); if(length(pool_u) >= MIN_MODULES) avail <- pool_u }
  # 이 국면 admitted 모듈로 추가 제한 (≥MIN_MODULES일 때만; 아니면 specialist 부재 → broad pool fallback)
  adm_L <- if(!is.null(admitted_by_regime)) admitted_by_regime[[reg_now]] else NULL
  if(!is.null(adm_L)){ pool_L <- intersect(avail, adm_L); if(length(pool_L) >= MIN_MODULES) avail <- pool_L }
  if(length(avail) < MIN_MODULES) next
  regime_ir <- setNames(sapply(avail, function(s){ lab <- .reglab(s); x<-ISr[[s]][!is.na(lab) & lab==reg_now]; x<-x[is.finite(x)]; if(length(x)<20||sd(x)==0) 0 else mean(x)/sd(x)*sqrt(252) }), avail)
  n_reg     <- setNames(sapply(avail, function(s){ lab <- .reglab(s); sum(is.finite(ISr[[s]][!is.na(lab) & lab==reg_now]))/21 }), avail)
  vols      <- setNames(sapply(avail, function(s){ x<-ISr[[s]]; x<-x[is.finite(x)]; sd(tail(x,252)) }), avail)
  w <- suppressWarnings(compute_regime_module_weights(regime_ir, vols, n_reg))
  wlog[[m]] <- data.table(ym=m, regime=reg_now, t(w))
  ## ★MC1/MC2 조작 확인 로그(2026-09-12): 처치가 어느 채널로 전달됐는지 사후에 재도출 가능하게.
  ##   R54 교훈 — 헤드라인만 보고 '국면층 기각' 이라 쓸 뻔했으나 그 셀엔 처치가 전달된 적이 없었다.
  .fd <- fr_weight_expressiveness(w)
  diaglog[[m]] <- data.table(ym = m, regime = reg_now,
    n_avail = length(avail), n_adm_union = length(admitted_union),
    n_adm_regime = if (is.null(adm_L)) NA_integer_ else length(adm_L),
    retention = .fd$retention %||% NA_real_, intended_dev = .fd$intended_dev %||% NA_real_,
    actual_dev = .fd$actual_dev %||% NA_real_, dev_from_ew = .fd$dev_from_ew %||% NA_real_,
    w_max = max(w), w_defensive = sum(w[intersect(names(w), DEFENSIVE_IDS)]),
    n_defensive_avail = length(intersect(avail, DEFENSIVE_IDS)),
    n_dead_excluded = n_dead_excl, hold_end = as.character(hold_end), dead_excl_date = as.character(excl_date),
    dec_date = as.character(mreg$dec_date[i]), dec_date_raw = as.character(mreg$dec_date_raw[i]))
  admlog[[m]] <- list(ym = m, regime = reg_now, admitted = as.character(avail))
  months_used <- c(months_used, m)
  # rebalance 행: 이번달 첫 거래일에 weight 적용 (월중 frozen은 Return.portfolio가 처리)
  rb_date <- RM[ym==m, min(Date)]
  W_rows[[m]] <- data.table(Date=rb_date, t(w))
}
if(length(W_rows) < 12) stop("walk-forward 월 부족 — RCMA/데이터 점검")

# 4. ★ Return.portfolio 합성 (자체합성 폐기) -----------------------------------
#    asset = 모듈, R = 일간 모듈수익(OOS 구간), weights = rebalance행(월초). 월중 drift+monthly rebalance.
oos_ym <- months_used
RM_oos <- RM[ym %in% oos_ym]; setorder(RM_oos, Date)
# weights wide (모든 사용 모듈 union 컬럼). 미보유 모듈은 0.
all_used_mods <- sort(unique(unlist(lapply(W_rows, function(d) setdiff(names(d),"Date")))))
Wdt <- rbindlist(lapply(W_rows, function(d){ x<-copy(d); miss<-setdiff(all_used_mods, names(x)); for(c in miss) x[, (c):=0]; x[, c("Date", all_used_mods), with=FALSE] }), use.names=TRUE)
setorder(Wdt, Date)
# R 매트릭스: 동일 모듈 컬럼, OOS 일자. NA(모듈 미존재 시점)는 0 — 해당 시점 weight도 0이라 영향 없음.
#   ★v4 ③ r1: 사망 뒤 NA 는 아래 §3b 재배분 + HARD 사후검사로 관측일 뒤 비중 0 이 보장된다(관측 지연 구간만 현금 · 기록).
Rdt <- RM_oos[, c("Date", all_used_mods), with=FALSE]
for(c in all_used_mods) Rdt[!is.finite(get(c)), (c):=0]
R_xts <- xts(as.matrix(Rdt[, ..all_used_mods]), order.by=Rdt$Date)

# 3b. ★v4 ③ r1 월중 사망 재배분 — 보유(비중>0) 모듈의 관측일(데이터 종료 뒤 첫 한국 거래일 · 그 날 종가에 '수익 없음'이 관측된다)이
#   그 행의 적용 구간 안에 오면, 관측일 종가에 그 모듈의 드리프트 비중을 생존 보유 모듈로 비례 재배분하는 리밸 행을 넣는다.
#   드리프트 = 행 비중 × Π(1+r) (행 다음 날 ~ 관측일 · NA→0 — Return.portfolio 와 같은 산술 · 아래 HARD 대조로 재도출).
#   관측일이 행 날짜 자체면(월초 리밸일 종가에 이미 관측) 그 행에서 바로 뺀다. 생존 보유 모듈 0개 = 중단(현금 지어내기 금지).
#   회전 비용은 §4 BOP/EOP 전이 turnover 로 자동 차감(15bps). 분해 대조(dead_exclude 끔) = 구판(재배분 없음).
.renorm_midmonth <- function(W, Rd, mods, label) {
  W <- copy(W); setorder(W, Date); ev <- list(); RD <- Rd$Date
  og_of <- function(s) { o <- MOD_OBS[[s]]; if (is.na(o)) return(NA_real_); g <- RD[RD >= o]; if (length(g)) as.numeric(min(g)) else NA_real_ }
  OG <- vapply(mods, og_of, numeric(1))
  repeat {
    nxt <- NULL
    for (k in seq_len(nrow(W))) {
      d0 <- as.numeric(W$Date[k]); d1 <- if (k < nrow(W)) as.numeric(W$Date[k + 1L]) else as.numeric(max(RD)) + 1
      wk <- unlist(W[k, ..mods]); held <- mods[is.finite(wk) & wk > 0]
      if (!length(held)) next
      og <- OG[held]; hit <- held[is.finite(og) & og >= d0 & og < d1]
      if (length(hit)) { o <- min(og[hit]); nxt <- list(k = k, o = o, dead = hit[og[hit] == o]); break }
    }
    if (is.null(nxt)) break
    k <- nxt$k; o <- nxt$o; dead <- nxt$dead; same_day <- (o == as.numeric(W$Date[k]))
    v <- unlist(W[k, ..mods])
    if (!same_day) {
      seg <- as.matrix(Rd[as.numeric(Date) > as.numeric(W$Date[k]) & as.numeric(Date) <= o, ..mods]); seg[!is.finite(seg)] <- 0
      v <- v * apply(1 + seg, 2, prod)
    }
    moved <- sum(v[dead]) / sum(v); v[dead] <- 0
    if (!(sum(v) > 0)) stop(sprintf("[FR v4 ③] %s: 관측일 %s 에 생존 보유 모듈 0개(사망 %s) — 재배분 불가(현금 지어내기 금지 · 중단)",
                                    label, as.character(as.Date(o, origin = "1970-01-01")), paste(dead, collapse = ",")))
    v <- v / sum(v)
    if (same_day) { for (cc in mods) set(W, k, cc, unname(v[[cc]])) } else {
      nr <- as.data.table(as.list(v)); nr[, Date := as.Date(o, origin = "1970-01-01")]
      W <- rbind(W, nr[, c("Date", mods), with = FALSE]); setorder(W, Date) }
    ev[[length(ev) + 1L]] <- list(date = as.character(as.Date(o, origin = "1970-01-01")), modules = as.list(dead),
                                  moved_weight = round(moved, 10), same_day_as_row = same_day)
  }
  list(W = W, events = ev)
}
## 관측일의 격자 날짜 = 관측일 이상 첫 RM 날짜(재배분 행이 놓이는 날 · 사후검사 경계)
MOD_OG <- as.Date(vapply(all_used_mods, function(s) { o <- MOD_OBS[[s]]; if (is.na(o)) return(NA_real_)
  g <- Rdt$Date[Rdt$Date >= o]; if (length(g)) as.numeric(min(g)) else NA_real_ }, numeric(1)), origin = "1970-01-01")
names(MOD_OG) <- all_used_mods
RENORM <- list(W = Wdt, events = list())
if (isTRUE(FIX$dead_exclude)) {
  RENORM <- .renorm_midmonth(Wdt, Rdt, all_used_mods, "앙상블")
  Wdt <- RENORM$W
  cat(sprintf("[v4 ③] 월중 사망 재배분 리밸 %d건%s\n", length(RENORM$events),
              if (length(RENORM$events)) paste0(" — ", paste(vapply(RENORM$events, function(e) sprintf("%s(%s · %.4f)", e$date,
                paste(unlist(e$modules), collapse = ","), e$moved_weight), ""), collapse = " · ")) else ""))
}
W_xts <- xts(as.matrix(Wdt[, ..all_used_mods]), order.by=Wdt$Date)
# Return.portfolio: weights 각 행=rebalance, 다음 rebalance까지 drift 후 재설정(=monthly rebalance, 월중 frozen · 월중 사망 재배분 행 포함).
rp <- Return.portfolio(R = R_xts, weights = W_xts, rebalance_on = NA, verbose = TRUE)
port_gross <- rp$returns                                  # 일간 gross 앙상블 수익 (표준함수 합성)
# ★v4 ③ r1 HARD 사후검사(실제 일간 BOP 비중 기준) + NA→0 채움 분해(기록): 비중 > 0 인 모듈·일을
#   (a) 관측일 뒤(= 재배분 실패 · 수리판 0 이어야 한다) · (b) 관측 지연(종료일 < 날짜 ≤ 관측일 — 불가피한 현금 · 기록) ·
#   (c) 생존 중 공백(모듈 간 날짜 격자 불일치 — P0-05/06 rebase 소관)으로 가른다.
.dead_cells <- function(bopm, idx, Rd, mods) {
  out <- list()
  for (s in mods) {
    w <- bopm[, s]; on <- which(is.finite(w) & w > 1e-12); if (!length(on)) next
    dd <- idx[on]; v <- Rd[[s]][match(dd, Rd$Date)]; me <- MOD_END[[s]]; ob <- MOD_OG[[s]]   # 관측일의 격자 날짜(재배분 행 날짜)
    post <- if (is.na(me)) rep(FALSE, length(dd)) else dd > me
    out[[s]] <- data.table(module = s, Date = dd, post_death = post,
                           after_obs = post & (is.na(ob) | dd > ob), lag = post & !is.na(ob) & dd <= ob, gap = !post & !is.finite(v))
  }
  x <- rbindlist(out)
  if (!nrow(x)) x <- data.table(module = character(0), Date = as.Date(character(0)), post_death = logical(0), after_obs = logical(0), lag = logical(0), gap = logical(0))
  x
}
.bop_m <- as.matrix(rp$BOP.Weight); .bop_i <- as.Date(index(rp$BOP.Weight))
.RDraw <- RM_oos[, c("Date", all_used_mods), with = FALSE]
.DC <- .dead_cells(.bop_m, .bop_i, .RDraw, all_used_mods)
NA_FILL <- list(n_post_death = .DC[after_obs == TRUE, .N], n_obs_lag = .DC[lag == TRUE, .N], n_alive_gap = .DC[gap == TRUE, .N],
                n_modules_post_death = uniqueN(.DC[after_obs == TRUE, module]),
                post_death_first = if (.DC[after_obs == TRUE, .N]) as.character(min(.DC[after_obs == TRUE, Date])) else NA_character_)
if (isTRUE(FIX$dead_exclude) && NA_FILL$n_post_death > 0L)
  stop(sprintf("[FR v4 ③] 사망 모듈 현금화 %d 모듈·일(모듈 %d개 · 첫 날 %s) — 관측일 뒤 날짜에 비중 > 0(편입 제외·재배분 규칙 실패)",
               NA_FILL$n_post_death, NA_FILL$n_modules_post_death, NA_FILL$post_death_first))
## 재배분 행 = Return.portfolio 가 산정한 관측일 EOP 비중에서 사망 모듈을 빼고 재정규화한 값(자기 산술 재도출 · 1e-9)
if (isTRUE(FIX$dead_exclude) && length(RENORM$events)) {
  .eop_m <- as.matrix(rp$EOP.Weight); .eop_i <- as.Date(index(rp$EOP.Weight))
  for (e in RENORM$events) if (!isTRUE(e$same_day_as_row)) {
    d <- as.Date(e$date); j <- match(d, .eop_i); wr <- unlist(Wdt[Date == d, ..all_used_mods])
    if (is.na(j) || length(wr) != length(all_used_mods)) stop(sprintf("[FR v4 ③] 재배분 행 %s 대조 불가(EOP 행 부재)", e$date))
    ev <- .eop_m[j, all_used_mods]; ev[unlist(e$modules)] <- 0; ev <- ev / sum(ev)
    if (max(abs(ev - wr)) > 1e-9) stop(sprintf("[FR v4 ③] 재배분 행 %s ≠ Return.portfolio EOP 재도출(최대 차 %.3g)", e$date, max(abs(ev - wr))))
  }
}
cat(sprintf("[v4 ③] NA→0 채움(비중>0 모듈·일): 관측일 뒤 %d · 관측 지연(종료일~관측일) %d · 생존 중 공백(날짜 격자 불일치) %d\n",
            NA_FILL$n_post_death, NA_FILL$n_obs_lag, NA_FILL$n_alive_gap))

# 15bps 국면전환 turnover 비용: Return.portfolio가 산정한 BOP/EOP weight 전이로 turnover 계산 후 리밸일 차감.
#   turnover_t = Σ|target_w(BOP_t) − drifted_w(EOP_{t-1})|. BOP≠직전 EOP 인 날 = rebalance(초기배분 포함).
#   손Σ 아님 — Return.portfolio가 산정한 weight 벡터의 차이(정직). 비용은 known cost 차감.
bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
bop_m <- as.matrix(bop); eop_m <- as.matrix(eop); idx <- as.Date(index(bop))
to_by_date <- data.table(Date=idx, to=0)
prev_eop <- rep(0, ncol(bop_m))                           # 시작 = 현금(0). 첫 BOP=초기배분 → 첫 리밸 비용 정직 반영.
for(j in seq_len(nrow(bop_m))){
  tgt <- bop_m[j, ]; tgt[!is.finite(tgt)] <- 0
  diffw <- sum(abs(tgt - prev_eop), na.rm=TRUE)
  if(diffw > 1e-8) to_by_date[j, to := diffw]             # BOP≠직전 EOP → rebalance 발생
  prev_eop <- eop_m[j, ]; prev_eop[!is.finite(prev_eop)] <- 0
}
port_dt <- data.table(Date=as.Date(index(port_gross)), r_gross=as.numeric(port_gross))
port_dt <- merge(port_dt, to_by_date, by="Date", all.x=TRUE); port_dt[is.na(to), to:=0]
port_dt[, r_net := r_gross - to*(15/1e4)]                 # 비용 차감(정직) — 자체 *구성*이 아니라 known cost 차감
setorder(port_dt, Date)
cat(sprintf("[3] ensemble OOS daily=%d months=%d (%s..%s) | 총 turnover(연환산 proxy)=%.2f\n",
  nrow(port_dt), uniqueN(format(port_dt$Date,"%Y%m")), as.character(min(port_dt$Date)), as.character(max(port_dt$Date)),
  sum(port_dt$to)/(nrow(port_dt)/252)))

# 5. 계약 측정 (실측-only, 표준함수 경유) --------------------------------------
#    ★v4 ①: 등급 = 일간 bt_result. 일간 격자 = **한국 거래일(trading_calendar)** — RM 합집합 날짜는 주말 라벨 모듈
#       (STR_944 계열 일요일 행) 때문에 연 ~300행이라, 그대로 두면 연율(252) CAGR·Sharpe 가 날짜 수로 왜곡된다.
#       포트·벤치 일간 수익을 같은 달 안에서 첫 한국 거래일 >= 날짜(없으면 같은 달 마지막 한국 거래일 <= 날짜)로 옮겨 누적
#       — 월 복리값 불변 · 측정 집계일 뿐 결정 경로 무관(배분·비중은 §3·§4 에서 이미 확정). 관측 없는 거래일 = 0.
#       월간 bt_result 는 같은 계열의 월 집계 = 진단 병기(판정 인용 금지).
#    ★v4 ④: 평가 창 [max(포트 시작, 벤치 시작), EVAL_END] · 포트·벤치 같은 날짜 집합(벤치 관측 없는 격자일 = 0)
#       — SR·Calmar·CAGR·MDD 와 PORT_t·OOS 가 같은 창을 쓴다.
PORT_START_RAW <- min(port_dt$Date); PORT_END_RAW <- max(port_dt$Date)
N_BENCH_UNPLACED <- 0L; N_PORT_DAYS_NO_BENCH <- NA_integer_; n_moved <- 0L
GRID_STATS <- list(grid = "rm_union_raw")
## 날짜 d 의 수익 → 격자: 같은 달 안의 첫 격자일 >= d, 없으면 같은 달 마지막 격자일 <= d. 같은 달에 격자일이 없으면 버림(수 기록).
.to_grid <- function(d, r, grid) {
  g <- as.integer(grid); di <- as.integer(d); ymd <- format(d, "%Y%m")
  fi <- findInterval(di - 1L, g) + 1L; bi <- findInterval(di, g)
  tgt <- rep(NA_integer_, length(di))
  okf <- fi <= length(g); okf[okf] <- format(grid[fi[okf]], "%Y%m") == ymd[okf]; tgt[okf] <- fi[okf]
  okb <- is.na(tgt) & bi > 0L; okb[okb] <- format(grid[bi[okb]], "%Y%m") == ymd[okb]; tgt[okb] <- bi[okb]
  keep <- !is.na(tgt) & is.finite(r)
  agg <- data.table(i = tgt[keep], r = r[keep])[, .(r = prod(1 + r) - 1), by = i]
  list(dt = data.table(Date = grid[agg$i], r = agg$r),
       n_moved_fwd = sum(keep & okf & (g[pmax(tgt, 1L)] != di)), n_moved_back = sum(keep & okb), n_dropped = sum(is.finite(r) & is.na(tgt)))
}
EVAL_START <- if (isTRUE(FIX$single_window)) max(PORT_START_RAW, min(bmref$Date)) else PORT_START_RAW
if (isTRUE(FIX$single_window)) port_dt <- port_dt[Date >= EVAL_START & Date <= EVAL_END]
if (isTRUE(FIX$daily_grade)) {
  .KR_CAL_G <- sort(unique(as.Date(read_parquet(file.path(PROJ, ".cache/trading_calendar.parquet"), col_select = "Date", mmap = FALSE)$Date)))
  GRID <- .KR_CAL_G[.KR_CAL_G >= min(port_dt$Date) & .KR_CAL_G <= max(port_dt$Date) & format(.KR_CAL_G, "%Y%m") %in% months_used]
  if (!length(GRID)) stop("[FR v4 ①] 평가 창 안에 한국 거래일이 없다 — trading_calendar 점검")
  .pn <- .to_grid(port_dt$Date, port_dt$r_net, GRID); .pg <- .to_grid(port_dt$Date, port_dt$r_gross, GRID)
  .pt <- merge(data.table(Date = GRID), .pn$dt, by = "Date", all.x = TRUE)
  .pt <- merge(.pt, setnames(copy(.pg$dt), "r", "r_gross"), by = "Date", all.x = TRUE); setorder(.pt, Date)
  GRID_STATS <- list(grid = "kr_trading_calendar", n_grid_days = length(GRID), n_port_rows_raw = nrow(port_dt),
                     n_port_moved_fwd = .pn$n_moved_fwd, n_port_moved_back = .pn$n_moved_back, n_port_dropped = .pn$n_dropped,
                     n_grid_days_no_port = sum(is.na(.pt$r)))
  if (.pn$n_dropped > 0L) stop(sprintf("[FR v4 ①] 포트 일간 수익 %d행이 같은 달 한국 거래일에 놓이지 못했다 — 달력 점검", .pn$n_dropped))
  .pt[is.na(r), r := 0]; .pt[is.na(r_gross), r_gross := 0]
  port_eval <- .pt[, .(Date, r_net = r, r_gross)]
  cat(sprintf("[v4 ①] 일간 격자 = 한국 거래일 %d일(원 포트 %d행 · 앞으로 %d · 뒤로 %d 이동 누적 · 관측 없는 거래일 %d = 0)\n",
              length(GRID), nrow(port_dt), .pn$n_moved_fwd, .pn$n_moved_back, GRID_STATS$n_grid_days_no_port))
} else {
  GRID <- port_dt$Date                                     # (구판 — FR_V4_ABLATE daily_grade 재현) RM 합집합 날짜 그대로
  port_eval <- port_dt[, .(Date, r_net, r_gross)]
}
if (isTRUE(FIX$single_window)) {
  .b <- bmref[Date >= EVAL_START & Date <= EVAL_END & is.finite(bm)]
  .bg <- .to_grid(.b$Date, .b$bm, port_eval$Date)
  N_BENCH_UNPLACED <- .bg$n_dropped; n_moved <- .bg$n_moved_fwd + .bg$n_moved_back
  ## ★v4r2 격자 불일치 = 중단: 정본 벤치는 한국 거래일 위의 계열이라 일간 격자(한국 거래일)에 **제 날짜 그대로** 놓여야 한다.
  ##   한 관측이라도 다른 날로 옮겨져야 놓인다면 달력·벤치 판본이 어긋난 것 — 옮겨 누적하면 그 날 포트 수익과 다른 날 벤치를 짝짓는다.
  if (isTRUE(FIX$canonical_bench) && isTRUE(FIX$daily_grade) && n_moved > 0L)
    stop(sprintf("[FR bench ★격자] 정본 벤치 %d관측이 한국 거래일 격자에 제 날짜로 놓이지 않는다(앞으로 %d · 뒤로 %d 이동 필요) — trading_calendar·benchmark 판본 점검",
                 n_moved, .bg$n_moved_fwd, .bg$n_moved_back))
  bm_eval <- merge(data.table(Date = port_eval$Date), setnames(copy(.bg$dt), "r", "bm"), by = "Date", all.x = TRUE); setorder(bm_eval, Date)
  N_PORT_DAYS_NO_BENCH <- sum(is.na(bm_eval$bm)); bm_eval[is.na(bm), bm := 0]
  ## 0 채움은 벤치 기간 **안**의 세션 없는 날만 — 벤치가 끝난 뒤 날짜를 0 으로 지어내면 PORT_t·OOS 창이 다시 갈린다.
  if (max(port_eval$Date) > max(bmref$Date) || min(port_eval$Date) < min(bmref$Date))
    stop(sprintf("[FR v4 ④] 평가 격자(%s..%s)가 벤치 기간(%s..%s) 밖 — 벤치 0 채움으로 창을 늘리지 않는다",
                 as.character(min(port_eval$Date)), as.character(max(port_eval$Date)), as.character(min(bmref$Date)), as.character(max(bmref$Date))))
  bm_xts_d <- bm_xts_m <- xts(bm_eval$bm, order.by = bm_eval$Date)
  cat(sprintf("[v4 ④] 평가 창 %s..%s (포트 %s..%s · 벤치 %s..%s) · 벤치 %d관측 이동 누적 · %d관측 버림 · 벤치 관측 없는 격자일 %d(=0)\n",
              as.character(min(port_eval$Date)), as.character(max(port_eval$Date)), as.character(PORT_START_RAW), as.character(PORT_END_RAW),
              as.character(min(bmref$Date)), as.character(max(bmref$Date)), n_moved, N_BENCH_UNPLACED, N_PORT_DAYS_NO_BENCH))
} else {
  ## (구판 — FR_V4_ABLATE=single_window 재현 전용) 벤치 = 자기 날짜(포트 날짜의 부분집합) · 월간만 월말 라벨 정렬.
  bmref_oos <- copy(bmref[Date %in% port_dt$Date]); setorder(bmref_oos, Date)
  bm_xts_d <- if (isTRUE(FIX$daily_grade)) { .bg <- .to_grid(bmref_oos$Date, bmref_oos$bm, port_eval$Date); xts(.bg$dt$r, order.by = .bg$dt$Date) }
              else xts(bmref_oos$bm, order.by=bmref_oos$Date)
  ## ★2026-09-12 측정 정합 수리 (침묵 실패) — 라벨 정렬만, 값 불변.
  ##   증상: contract 는 period_returns 와 benchmark_returns 를 **정확 날짜**로 merge 한다
  ##         (essence_score / 본 러너의 MM 둘 다). 그런데 두 월간 계열의 월말 라벨은
  ##         apply.monthly 가 각자의 마지막 관측일로 찍으므로, 벤치 일간 계열에 구멍이 있는 달은
  ##         라벨이 하루 어긋나 그 달이 통째로 빠진다.
  ##   실측(2026-09-12 arm_C): pr 216월 · br 213월인데 교집합 **110월** — 표본 49%가 조용히 소실.
  ##   수리: 각 달의 **마지막 벤치 관측 날짜**를 같은 달 전략 월말 날짜로 옮긴다(값 불변).
  ##   (v4 ④ 는 이 정렬을 벤치의 격자 이동으로 대체 — 일간·월간 모두 같은 날짜 집합)
  local({
    .pm <- port_eval[, .(pm = max(Date)), by = .(ym = format(Date, "%Y%m"))]
    .bd <- data.table(Date = bmref_oos$Date, ym = format(bmref_oos$Date, "%Y%m"))
    .bd[, is_last := Date == max(Date), by = ym]
    .bd <- merge(.bd, .pm, by = "ym", all.x = TRUE); setorder(.bd, Date)
    nd <- .bd$Date; sel <- .bd$is_last & !is.na(.bd$pm); nd[sel] <- .bd$pm[sel]
    if (anyDuplicated(nd)) stop("[bm align] 라벨 정렬 후 중복 날짜 — 가정(bm ⊆ port) 위반")
    n_moved <<- sum(nd != .bd$Date)
    bmref_oos[, Date := nd]
  })
  cat(sprintf("[bm align] 월말 라벨 정렬: %d개 관측일 이동(값 불변) — 정확날짜 merge 로 인한 월 소실 방지\n", n_moved))
  bm_xts_m <- xts(bmref_oos$bm, order.by=bmref_oos$Date)
}
ED_xts  <- xts(port_eval$r_net,   order.by=port_eval$Date)
EDg_xts <- xts(port_eval$r_gross, order.by=port_eval$Date)
# ★ FIX (CAGR/Calmar 정합, 2026-06-05): frequency="monthly" 선언 → DAILY_NAV_DT도 *월간* 그래뉼래리티여야 함.
#   contract build_metrics의 CAGR = (final/init)^(annualization_factor/length(nav)) − 1. 일간 NAV(7336행)에
#   월간 annualization_factor=12를 적용하면 지수가 ~21배 과소(12/7336) → CAGR 0.6%로 붕괴(실제 ~16%).
#   해결: 일간 net/gross 수익을 표준함수 apply.monthly(Return.cumulative)로 월집계 후 월간 NAV path 구성
#   (NAV는 수익률 *구성*이 아니라 net 월수익 시계열의 누적가치 — answer-principles 정합). length(nav)≈n_months.
mret_net   <- apply.monthly(ED_xts,  Return.cumulative)
mret_gross <- apply.monthly(EDg_xts, Return.cumulative)
mdates    <- as.Date(index(mret_net))
nav_net   <- as.numeric(cumprod(1 + as.numeric(mret_net)))    # 월간 NAV path (월수익 누적가치)
nav_gross <- as.numeric(cumprod(1 + as.numeric(mret_gross)))
sim_result <- list(
  DAILY_NAV_DT  = data.table(Date=mdates, NAV=nav_net, NAV_gross=nav_gross),  # ★ 월간 NAV (frequency 정합)
  strategy_xts  = ED_xts, bm_xts = bm_xts_m,                                  # strategy_xts/bm_xts는 일간 — contract가 apply.monthly로 집계
  HOLDINGS_LOG  = list(), PORTFOLIO_LOG = data.table(Exec_Date=as.Date(Wdt$Date)))  # ★ rb_dates 미정의 fix: rebalance 날짜 = W_rows 집계행(Wdt)의 Date
# ★v4 ① 일간 판: DAILY_NAV_DT = 일간 net 수익의 누적가치(월간 판과 같은 규약 — 수익 *구성* 아님) · strategy_gross_xts = 비용 전
#   (계약 P0-03: 생산자가 gross 계열을 주면 그것을 쓴다) · bm_xts = 같은 창·같은 날짜의 일간 벤치. frequency="daily" → 연율 252(계약 유도).
sim_result_d <- list(
  DAILY_NAV_DT  = data.table(Date=port_eval$Date, NAV=as.numeric(cumprod(1 + port_eval$r_net)), NAV_gross=as.numeric(cumprod(1 + port_eval$r_gross))),
  strategy_xts  = ED_xts, strategy_gross_xts = EDg_xts, bm_xts = bm_xts_d,
  HOLDINGS_LOG  = list(), PORTFOLIO_LOG = data.table(Exec_Date=as.Date(Wdt$Date)))
FR_ID    <- if(REGIME_SOURCE=="forecast") paste0(FR_RUN_ID, "_fc") else FR_RUN_ID
if (nzchar(FR_ARM_TAG)) FR_ID <- paste0(FR_ID, "_", FR_ARM_TAG)
OUT_JSON <- paste0(FR_ID, "_result.json"); OUT_RDS <- paste0(FR_ID, "_bt_result.rds")
GRADE_FREQ <- if (isTRUE(FIX$daily_grade)) "daily" else "monthly"
DIAG_FREQ  <- if (GRADE_FREQ == "daily") "monthly" else "daily"
OUT_RDS_DIAG <- paste0(FR_ID, "_bt_result_", DIAG_FREQ, "_diag.rds")
FR_CODE_VERSION <- paste0("run_wf_ensemble_v4r2_dailygrade_singlewindow_deadasof_krfloor_canonbench",
                          if (FR_V4_ABLATED) paste0("+ablate:", paste(sort(.v4_ab), collapse = ",")) else "")
spec <- list(strategy_name=paste0(FR_ID, if(REGIME_SOURCE=="forecast") "_fc_proactive_rotation" else "_regime_rotation"),
             signal="regime-conditional module rotation",
             module_pool=all_used_mods,
             regime_source=if(REGIME_SOURCE=="forecast") "regime_forecaster predicted-next-regime (proactive, PIT trailing-only)" else if (C11_LEGACY_RUN) "unified_regime_signal_daily Category (t-1 · ★C11 미해소 legacy 재현)" else "unified_regime_signal_daily Category (C11 avail-join: prior month-end close decision)",
             weighting="module_dispatcher rp+IR shrink (λ/τ/k0 fixed); Return.portfolio monthly rebalance",
             rebalance="monthly",
             lookahead_prevention=paste0(if (C11_LEGACY_RUN) "regime t-1 lag (C11 unresolved legacy replay)" else "regime C11 avail-join (dispatch: prior month-end close decision; IS IR: return-window start)",
                                         if (isTRUE(FIX$dispatch_kr_floor) && !C11_LEGACY_RUN) " (dispatch decision floored to KR trading day)" else "",
                                         "; module frozen; IS-only weights; walk-forward RCMA admission (compute_rcma asof=prior month-end, annual refit); Return.portfolio (no self-synthesis)",
                                         if (isTRUE(FIX$dead_exclude)) "; dead modules excluded only if ended before the decision close (as-of), mid-month deaths re-weighted at observation-day close" else "",
                                         if (isTRUE(FIX$single_window)) "; single evaluation window (bench on portfolio date grid)" else "",
                                         if (isTRUE(FIX$canonical_bench)) "; benchmark = canonical .cache/benchmark.parquet BM_Ret on the return date (L1 harness convention), module date-grid lag 0 enforced (fail-closed)" else ""))
.bt_args <- list(spec, run_id=FR_ID, strategy_id=FR_ID, strategy_version="v2",
        benchmark_id="KOSPI200", benchmark_name="KOSPI 200", transaction_cost_bps=15, slippage_bps=0,
        risk_free_rate=0, universe_id="KR_modules",
        code_version=FR_CODE_VERSION, created_by_agent="dispatch-orchestrator")
bt_m <- audit_bt_result(do.call(build_bt_result, c(list(sim_result), .bt_args, list(frequency="monthly", annualization_factor=12))))
bt_d <- audit_bt_result(do.call(build_bt_result, c(list(sim_result_d), .bt_args, list(frequency="daily", annualization_factor=252))))
bt      <- if (GRADE_FREQ == "daily") bt_d else bt_m          # ★권위 = 등급 판(v4 기본 일간)
bt_diag <- if (GRADE_FREQ == "daily") bt_m else bt_d          # 진단 병기(판정 인용 금지)
cat(sprintf("[v4 ①] 등급 = %s bt_result · 진단 병기 = %s\n", GRADE_FREQ, DIAG_FREQ))
# n_trials: 앙상블 = 다중검정 (모듈조합 + hyper) — 보수적 상향
N_TRIALS <- length(all_used_mods) + 5L
# ★2026-09-21 (R1 · 플랜 Part 3 §6) FR_SELECTION_TYPE — 미설정 = 구동작(selection_type 미전달 → essence 의 legacy n_trials>1 = sweep 판정).
#   "chain" 은 config l2_auto.selection_type 에 decided_by/at 과 함께 기록됐을 때만 레인이 넘긴다 — 여기서 기본값을 바꾸지 않는다.
FR_SELECTION_TYPE <- Sys.getenv("FR_SELECTION_TYPE", "")
es <- if (nzchar(FR_SELECTION_TYPE)) essence_score(bt, n_trials_cumulative = N_TRIALS, selection_type = FR_SELECTION_TYPE) else essence_score(bt, n_trials_cumulative = N_TRIALS)
## 진단 판 essence — 같은 계약·같은 인자. AST 사이드카 적재 끔(같은 실행을 두 번 적재하지 않는다). 실패해도 등급 무관.
es_diag <- tryCatch(if (nzchar(FR_SELECTION_TYPE)) essence_score(bt_diag, n_trials_cumulative = N_TRIALS, selection_type = FR_SELECTION_TYPE, sidecar_log = FALSE)
                    else essence_score(bt_diag, n_trials_cumulative = N_TRIALS, sidecar_log = FALSE),
                    error = function(e) list(grade = NA_character_, essence = list(), error = conditionMessage(e)))

# 6. OOS retention + placebo (등급 판 active 시계열 = 계약 period_returns/benchmark_returns) ----
PRm <- as.data.table(bt$period_returns)[, .(date, ret_net)]
BRm <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
MM  <- merge(PRm, BRm, by="date"); setorder(MM, date)
AF_GRADE <- suppressWarnings(as.numeric(as.data.table(bt$metrics)$annualization_factor[1]))   # 계약이 frequency 에서 유도한 값
if (!is.finite(AF_GRADE)) stop("[FR v4] 등급 판 metrics 에 annualization_factor 없음")
n<-nrow(MM); k<-floor(n*0.65); shp<-function(x){x<-x[is.finite(x)];if(length(x)<2||sd(x)==0)return(NA);mean(x)/sd(x)*sqrt(AF_GRADE)}
act <- MM$ret_net - MM$benchmark_ret
# ★ FIX (oos_retention 폭주 가드, 2026-06-05): IS active Sharpe(분모) abs<0.1면 비율 불안정 → null/"unstable".
#   essence_score는 동일 65/35 분할 + is_ir>0.05 가드로 oos_retention 산출 → 그 값을 권위로 채택(이중소스 불일치 제거).
is_sr_active <- shp(act[1:k]); oos_sr_active <- shp(act[(k+1):n])
OOS_RET_UNSTABLE_THRESH <- 0.1
oos_local <- if(is.finite(is_sr_active) && abs(is_sr_active) >= OOS_RET_UNSTABLE_THRESH && is.finite(oos_sr_active)) oos_sr_active/is_sr_active else NA_real_
# 권위 = essence_score의 oos_retention(가드 내장). 미산출(NA) 시 local 가드값으로 보강, 둘 다 불안정이면 NA.
oos_ret <- es$essence$oos_retention %||% oos_local
oos_ret_label <- if(is.finite(oos_ret)) "ok" else "unstable"
# ★v4 ④ 창 정합 사후검사: 등급 판의 성과 계열 날짜 = 벤치 병합 날짜(SR·Calmar 와 PORT_t·OOS 가 같은 집합).
N_PR <- nrow(PRm); N_MM <- n
if (isTRUE(FIX$single_window) && N_PR != N_MM)
  stop(sprintf("[FR v4 ④] 단일 창 위반: period_returns %d행 ≠ 벤치 병합 %d행", N_PR, N_MM))
# placebo proxy: 동일 OOS 구간 EW(equal-weight) 앙상블 SR (Return.portfolio, 월말 리밸). 손합성 아님.
#   ★v4 ③: 그 달 생존 모듈만 균등(사망 모듈 현금화 금지) · ④: 같은 평가 창 · ①: SR 은 등급 판 빈도(월간 SR 은 병기).
ew_rb <- RM_oos[, .(Date=min(Date), hold_end=max(Date)), by=ym]
ew_W  <- data.table(Date=ew_rb$Date)
EW_RENORM_N <- 0L
if (isTRUE(FIX$dead_exclude)) {
  ## r1: 결정 시점(직전 월말 RM 날짜의 한국 거래일 내림) 생존 모듈만 균등 · 월중 사망 = 관측일 재배분(앙상블과 같은 규칙)
  .me_prev <- setNames(c(NA_real_, head(as.numeric(me$me_date), -1L)), me$ym)
  .ew_excl <- as.Date(vapply(ew_rb$ym, function(y) as.numeric(.mod_decision_date(as.Date(.me_prev[[y]], origin = "1970-01-01"))), numeric(1)),
                      origin = "1970-01-01")
  for (c in all_used_mods) ew_W[, (c) := as.numeric(is.na(.ew_excl) | !(MOD_END[[c]] < .ew_excl))]
  .rs <- rowSums(as.matrix(ew_W[, ..all_used_mods]))
  if (any(.rs <= 0)) stop("[FR v4 ③] EW 기준선: 결정 시점 생존 모듈 0개인 달")
  for (c in all_used_mods) set(ew_W, j = c, value = ew_W[[c]] / .rs)
  .ewr <- .renorm_midmonth(ew_W, Rdt, all_used_mods, "EW 기준선"); ew_W <- .ewr$W; EW_RENORM_N <- length(.ewr$events)
} else for(c in all_used_mods) ew_W[, (c) := 1/length(all_used_mods)]
ewW_xts <- xts(as.matrix(ew_W[, ..all_used_mods]), order.by=ew_W$Date)
ew_rp <- tryCatch(Return.portfolio(R = R_xts, weights = ewW_xts, rebalance_on = NA), error=function(e) NULL)
ew_sr <- NA_real_; ew_sr_m <- NA_real_; ew_sr_d <- NA_real_
if (!is.null(ew_rp)) {
  ewd <- data.table(Date=as.Date(index(ew_rp)), r=as.numeric(ew_rp))
  if (isTRUE(FIX$single_window)) ewd <- ewd[Date >= EVAL_START & Date <= EVAL_END]
  if (isTRUE(FIX$daily_grade)) {                                   # 등급 판과 같은 한국 거래일 격자(연율 정합)
    .eg <- .to_grid(ewd$Date, ewd$r, GRID)
    ewd <- merge(data.table(Date = GRID), .eg$dt, by = "Date", all.x = TRUE); ewd[is.na(r), r := 0]; setorder(ewd, Date)
  }
  ewm <- apply.monthly(xts(ewd$r, order.by=ewd$Date), Return.cumulative); ew_sr_m <- sr(as.numeric(ewm))
  AF_D <- suppressWarnings(as.numeric(as.data.table(bt_d$metrics)$annualization_factor[1]))
  ew_sr_d <- { x <- ewd$r[is.finite(ewd$r)]; if (length(x) < 2 || sd(x) == 0 || !is.finite(AF_D)) NA_real_ else mean(x)/sd(x)*sqrt(AF_D) }
  ew_sr <- if (GRADE_FREQ == "daily") ew_sr_d else ew_sr_m
}

dir.create(file.path(PROJ,"04_Research/factor_rotation/output"), showWarnings=FALSE, recursive=TRUE)
# ★ A/B 출력 게이트: forecast 변형·대조 arm 은 별도 파일·등재 생략(baseline 보존). FR_ID/OUT_* 는 위에서 확정.
N_MONTHS_WIN <- uniqueN(format(MM$date, "%Y%m"))
.gl_used <- GRID_LAG[intersect(all_used_mods, names(GRID_LAG))]
## 정본 벤치 = 정의상 시차 0(정본 자신) · 분해 대조(구판) = 최장 bm_xts 모듈의 시차
.bm_lag <- if (isTRUE(FIX$canonical_bench)) 0L else if (!is.na(bmref_src) && bmref_src %in% names(GRID_LAG)) GRID_LAG[[bmref_src]] else NA_integer_
GRID_AUDIT <- list(method = if (isTRUE(FIX$canonical_bench))
                     "모듈 bm_xts vs .cache/benchmark.parquet BM_Ret 상관 최대 시차(−1/0/+1일) — HARD(풀 모듈 시차 ≠0·NA = 중단 · v4r2 I7) · 벤치 = 정본(같은 날짜 BM_Ret)"
                   else "모듈 bm_xts vs .cache/benchmark.parquet BM_Ret 상관 최대 시차(−1/0/+1일) — ★분해 대조(canonical_bench 끔): 진단 기록만 · 벤치 = 최장 bm_xts(구판)",
                   enforced = isTRUE(FIX$canonical_bench),
                   canonical_available = !is.null(.CANON_BM), bmref_module = bmref_src, bmref_lag = .bm_lag,
                   used_lag_counts = list(minus1 = sum(.gl_used == -1L, na.rm = TRUE), zero = sum(.gl_used == 0L, na.rm = TRUE),
                                          plus1 = sum(.gl_used == 1L, na.rm = TRUE), na = sum(is.na(.gl_used))),
                   misaligned_used = as.list(names(.gl_used)[!is.na(.gl_used) & .gl_used != 0L]))
if (length(GRID_AUDIT$misaligned_used) || (!is.na(.bm_lag) && .bm_lag != 0L))
  cat(sprintf("[v4 격자] ★일간 등급 해석 주의 — 쓰인 모듈 %d개 · 벤치 원천(%s) 시차 %s 가 정본 벤치 날짜와 어긋난다(분해 대조 canonical_bench 끔 = 구판 재현 · 기록만)\n",
              length(GRID_AUDIT$misaligned_used), bmref_src, as.character(.bm_lag)))
.es_pick <- function(e) { x <- e$essence %||% list()
  list(net_sharpe = x$net_sharpe %||% NA_real_, portfolio_alpha_t_nw_lag3 = x$portfolio_alpha_t_nw_lag3 %||% NA_real_,
       oos_retention = x$oos_retention %||% NA_real_, dsr = x$dsr %||% NA_real_, calmar = x$calmar %||% NA_real_,
       cagr = x$cagr %||% NA_real_, mdd = x$mdd %||% NA_real_, net_ir = x$net_ir %||% NA_real_) }
fr <- list(fr_id=FR_ID, grade=es$grade, metric_type=es$metric_type, essence=es$essence,
  grade_frequency=GRADE_FREQ,
  grade_basis=if (GRADE_FREQ == "daily") "essence_score(일간 bt_result) — CALMAR-FREQ-DAILY(등급용 Calmar 전 계층 일간)" else "essence_score(월간 bt_result) — ★FR_V4_ABLATE daily_grade 진단 재현(정본 아님)",
  n_modules=length(all_used_mods), module_pool=all_used_mods, n_months=N_MONTHS_WIN, n_obs=n, n_trials_cumulative=N_TRIALS,
  oos_retention=if(is.finite(oos_ret)) round(oos_ret,3) else NA_real_, oos_retention_status=oos_ret_label,
  oos_is_active_sharpe=round(is_sr_active,3), oos_oos_active_sharpe=round(oos_sr_active,3),
  ew_baseline_SR=round(ew_sr,3), ew_baseline_SR_frequency=GRADE_FREQ,
  ew_baseline_SR_daily=round(ew_sr_d,3), ew_baseline_SR_monthly=round(ew_sr_m,3),
  net_sharpe=es$essence$net_sharpe, port_t=es$essence$portfolio_alpha_t_nw_lag3, dsr=es$essence$dsr,
  diagnostic_other_frequency=c(list(frequency=DIAG_FREQ, note="진단 병기 — 판정·등급 인용 금지(권위 = 위 grade/essence)",
                                    grade=es_diag$grade %||% NA_character_, error=es_diag$error %||% NA_character_,
                                    n_obs=nrow(as.data.table(bt_diag$period_returns))),
                               .es_pick(es_diag)),
  eval_window=list(single_window=isTRUE(FIX$single_window), start=as.character(EVAL_START), end=as.character(max(port_dt$Date)),
                   eval_end_cap=as.character(EVAL_END), rm_end_raw=as.character(RM_END_RAW),
                   port_raw=c(as.character(PORT_START_RAW), as.character(PORT_END_RAW)),
                   bench_span=c(as.character(min(bmref$Date)), as.character(max(bmref$Date))), bench_source=bmref_src,
                   n_period_returns=N_PR, n_bench_merged=N_MM, n_bench_moved=n_moved, n_bench_unplaced=N_BENCH_UNPLACED,
                   n_port_days_no_bench=N_PORT_DAYS_NO_BENCH, daily_grid=GRID_STATS),
  dead_modules=list(rule=if (isTRUE(FIX$dead_exclude)) "r1 as-of: 데이터 종료일 < 결정일(직전 월말 RM 날짜의 한국 거래일 내림) → 편입 제외 · 월중 사망 = 관측일(종료 뒤 첫 한국 거래일) 종가 생존 보유 모듈 비례 재배분" else "★ablate: 구판(편입 후 NA→0)",
                    n_module_months_excluded=sum(vapply(diaglog, function(x) as.integer(x$n_dead_excluded), integer(1))),
                    n_post_death_zero_filled=NA_FILL$n_post_death, n_obs_lag_cash_days=NA_FILL$n_obs_lag, n_alive_gap_zero_filled=NA_FILL$n_alive_gap,
                    n_midmonth_renorm_rows=length(RENORM$events), renorm_events=RENORM$events, n_ew_renorm_rows=EW_RENORM_N,
                    n_modules_trailing_zero=N_TRAILING_ZERO_MODULES, modules_no_return=as.list(MODS_NO_RETURN),
                    ended_in_window=as.list(vapply(names(MOD_END)[MOD_END < max(port_dt$Date) & names(MOD_END) %in% all_used_mods],
                                                   function(s) as.character(MOD_END[[s]]), character(1)))),
  dispatch=list(kr_floor=isTRUE(FIX$dispatch_kr_floor) && !C11_LEGACY_RUN,
                n_decision_floored=sum(mreg$dec_date != mreg$dec_date_raw, na.rm = TRUE),
                n_neutral_forced_eval=N_NEUTRAL_FORCED_EVAL, n_neutral_forced_total=sum(mreg$neutral_forced)),
  grid_audit=GRID_AUDIT,
  v4_ablate=if (FR_V4_ABLATED) as.list(sort(.v4_ab)) else list(),
  oos_start_ym=OOS_START_YM, oos_start_breadth=OOS_START_BREADTH, min_breadth_oos=MIN_BREADTH_OOS,
  breadth_rationale="OOS 시작점 = 가용 모듈 breadth ≥ MIN_BREADTH_OOS 인 첫 달(avail_by_m 진단). thin 초기구간(1990~2001 4~7모듈) 배제 — 임의 2016 절단·무근거 1995 시작 모두 회피.",
  code_version=FR_CODE_VERSION,
  lookahead_prevention=spec$lookahead_prevention,
  rcma_mode="walk-forward (compute_rcma asof=prior month-end, annual refit)",
  return_synthesis="PerformanceAnalytics::Return.portfolio (monthly rebalance; no prod/cumprod/Sigma-w self-synthesis)",
  date_range=c(as.character(min(MM$date)), as.character(max(MM$date))),
  pit_c11=c(.WF_C11$c11_consumption_record(C11G, site = "run_wf_ensemble",
              mode = "dispatch: decision_close(c) at prior month-end RM close · IS IR: window_start(b)",
              extra_lag = FR_EXTRA_REGIME_LAG, n_rows = nrow(mreg), n_aligned = sum(!is.na(mreg$sig_cutoff)), root = PROJ),
            list(legacy_run = C11_LEGACY_RUN)))
write_json(fr, file.path(PROJ,"04_Research/factor_rotation/output", OUT_JSON), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
saveRDS(bt, file.path(PROJ,"04_Research/factor_rotation/output", OUT_RDS))
saveRDS(bt_diag, file.path(PROJ,"04_Research/factor_rotation/output", OUT_RDS_DIAG))   # ★v4 진단 판(판정 인용 금지)
# FR 운용체계 레지스트리 등재 (실측-only; metric_type=backtested 아니면 거부). forecast 변형은 A/B 실험 → 등재 생략.
if(REGIME_SOURCE != "forecast" && FR_REGISTER){
  tryCatch({ source(file.path(CD, "factor_rotation_registry.R"))
    register_fr_result(fr, regime_engine_version=sprintf("unified_regime_signal_daily Category(C11 avail-join, dispatch decision = month-end -%d%s) + walk-forward RCMA · grade %s",
                                                          1L+FR_EXTRA_REGIME_LAG, if (isTRUE(FIX$dispatch_kr_floor)) " floored to KR trading day" else "", GRADE_FREQ)) },
    error=function(e) cat("[run_wf_ensemble] FR registry 생략:", conditionMessage(e), "\n"))
} else cat("[run_wf_ensemble] 등재 생략 —", if(REGIME_SOURCE=="forecast") "forecast A/B 변형" else if (FR_V4_ABLATED) "FR_V4_ABLATE 분해 대조(진단 전용)" else "FR_REGISTER≠1 (기본 · 대조/스트레스 arm — 등재는 FR_REGISTER=1 명시)", "\n")

# ── ★진단 덤프 (MC1/MC2/MC3 재도출용). FR_DIAG_DIR 미설정이면 생략 ─────────────────
if (nzchar(FR_DIAG_DIR)) {
  dir.create(FR_DIAG_DIR, showWarnings=FALSE, recursive=TRUE)
  DG <- rbindlist(diaglog, fill=TRUE)
  fwrite(DG, file.path(FR_DIAG_DIR, paste0(FR_ID, "_dispatch_diag.csv")))
  saveRDS(admlog, file.path(FR_DIAG_DIR, paste0(FR_ID, "_admitted_by_month.rds")))
  fwrite(Wdt, file.path(FR_DIAG_DIR, paste0(FR_ID, "_rebalance_weights.csv")))       # ★v4 ③ r1: 월초 행 + 월중 사망 재배분 행(검사 재도출용)
  ## ★v4 ② 월 배분 결정 기록(전 월): 월말 RM 날짜 · 원 결정일 · 한국 거래일로 내린 결정일 · 쓴 라벨(관측일·가용일) · NEUTRAL 강제 여부
  fwrite(mreg[, .(ym, me_date, dec_date_raw, dec_date, regime_lag, regime_dispatch, sig_cutoff, sig_avail, neutral_forced, eval_month)],
         file.path(FR_DIAG_DIR, paste0(FR_ID, "_dispatch_decisions.csv")))
  ## 국면별 admitted 집합 Jaccard (MC1) — 같은 해 안에서 국면만 다른 달끼리 비교되도록 연도 통제.
  .jac <- function(a,b){ u<-length(union(a,b)); if(u==0) NA_real_ else length(intersect(a,b))/u }
  am <- rbindlist(lapply(admlog, function(x) data.table(ym=x$ym, regime=x$regime, k=paste(sort(x$admitted), collapse="|"))))
  am[, yr := substr(ym,1,4)]
  pairs <- list()
  for (y in unique(am$yr)) { s <- am[yr==y]; if (uniqueN(s$regime) < 2L) next
    rg <- unique(s$regime)
    for (i in seq_along(rg)) for (j in seq_along(rg)) if (i<j) {
      a <- strsplit(s[regime==rg[i]][1]$k, "\\|")[[1]]; b <- strsplit(s[regime==rg[j]][1]$k, "\\|")[[1]]
      pairs[[length(pairs)+1]] <- data.table(yr=y, r1=rg[i], r2=rg[j], jaccard=.jac(a,b)) } }
  JP <- if (length(pairs)) rbindlist(pairs) else data.table()
  if (nrow(JP)) fwrite(JP, file.path(FR_DIAG_DIR, paste0(FR_ID, "_regime_jaccard.csv")))
  mc <- list(fr_id=FR_ID, arm=FR_ARM_TAG, extra_regime_lag=FR_EXTRA_REGIME_LAG,
    n_pool=length(MP$modules), n_defensive_pool=length(DEFENSIVE_IDS),
    MC1_membership=list(n_pairs=nrow(JP), jaccard_median=if(nrow(JP)) round(median(JP$jaccard, na.rm=TRUE),4) else NA,
                        jaccard_min=if(nrow(JP)) round(min(JP$jaccard, na.rm=TRUE),4) else NA,
                        delivered=if(nrow(JP)) (median(JP$jaccard, na.rm=TRUE) < 0.9) else NA),
    MC2_weights=list(retention_median=round(median(DG$retention, na.rm=TRUE),4),
                     retention_p90=round(as.numeric(quantile(DG$retention, .9, na.rm=TRUE)),4),
                     n_avail_median=median(DG$n_avail, na.rm=TRUE),
                     delivered=isTRUE(median(DG$retention, na.rm=TRUE) >= 0.25)),
    MC3_defensive=as.list(DG[, .(w_def_mean=round(mean(w_defensive, na.rm=TRUE),4),
                                 n_months=.N), by=regime]))
  write_json(mc, file.path(FR_DIAG_DIR, paste0(FR_ID, "_manipulation_check.json")), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
  cat(sprintf("[MC] retention median=%.3f (n_avail median=%.0f) · Jaccard median=%s · 방어형 비중 국면별 기록 → %s\n",
              median(DG$retention, na.rm=TRUE), median(DG$n_avail, na.rm=TRUE),
              if(nrow(JP)) sprintf("%.3f", median(JP$jaccard, na.rm=TRUE)) else "NA", FR_DIAG_DIR))
}
# ── FR L-code 발행 (2026-07-04 G-mode-wiring — FR 모드 emit 1지점, 레지스트리 등재 직후) ──
#   es 객체 스코프 내 실측치만 전달(metric_type=backtested). fail-soft — emit 실패가 러너를 죽이지 않음.
#   forecast A/B 변형도 strategy_id=FR_ID로 구분 적립 (실험 교훈도 지식 — 레지스트리 미등재와 별개).
if (C11_LEGACY_RUN) cat("[run_wf_ensemble] ★C11 legacy 재현 — FR L-code 발행 생략(미해소 측정은 교훈으로 적립하지 않는다)\n") else
if (FR_V4_ABLATED) cat("[run_wf_ensemble] ★FR_V4_ABLATE 분해 대조 — FR L-code 발행 생략(수리를 끈 측정은 교훈으로 적립하지 않는다)\n") else
tryCatch({
  source(file.path(PROJ,"02_Infrastructure/axiom/lcode_emit.R"))
  .fr_edge_ew <- if(is.finite(es$essence$net_sharpe%||%NA) && is.finite(ew_sr)) (es$essence$net_sharpe - ew_sr) else NA_real_
  # falsification 구조체 [{test,result,effect_retained}] — 이미 산출된 반증형 검증의 전달만 (신규 계산 금지)
  .fr_fals <- list()
  if(is.finite(oos_ret))
    .fr_fals[[length(.fr_fals)+1]] <- list(test="OOS retention (essence 3-split, 과적합 반증)",
      result=if(oos_ret >= 0.5) "survived" else "falsified",   # §3 하한 0.5 (measurement-graduation — 창작 아님)
      effect_retained=round(oos_ret,3), detail=sprintf("retention %.3f (gate 0.7, 하한 0.5)", oos_ret))
  if(is.finite(.fr_edge_ew))
    .fr_fals[[length(.fr_fals)+1]] <- list(test="EW baseline 대비 edge (placebo proxy)",
      result="diagnostic", effect_retained=NA,
      detail=sprintf("net_SR %.3f vs EW %.3f (edge %+.3f) — 유의검정 아님(진단)", es$essence$net_sharpe%||%NA, ew_sr, .fr_edge_ew))
  emit_fr_lcode(
    strategy_id = FR_ID, grade = es$grade,
    lesson_text = sprintf(
      "%s regime rotation 앙상블 실측(essence %s · %s 등급 판 · v4 단일 창·사망 모듈 제외): net_SR=%.3f PORT_t(NW lag-3)=%.2f DSR=%s Calmar=%.2f CAGR=%.1f%% MDD=%.1f%% | oos_retention=%s | admitted pool %d모듈(%s) | edge_vs_ew=%s (EW baseline SR %.3f).",
      FR_ID, es$grade, GRADE_FREQ, es$essence$net_sharpe%||%NA, es$essence$portfolio_alpha_t_nw_lag3%||%NA,
      as.character(round(es$essence$dsr,3)), es$essence$calmar%||%NA,
      (es$essence$cagr%||%NA)*100, (es$essence$mdd%||%NA)*100,
      if(is.finite(oos_ret)) sprintf("%.3f", oos_ret) else "unstable",
      length(all_used_mods), paste(head(all_used_mods,8), collapse=","),
      if(is.finite(.fr_edge_ew)) sprintf("%+.3f", .fr_edge_ew) else "NA", ew_sr),
    track = "factor_rotation",
    construction_type = "regime_rotation",
    mechanism_hypothesis = "국면조건부 모듈 배분(RCMA admitted union + rp/IR shrink dispatcher) — 모듈별 약점 국면 회피로 앙상블 위험조정수익 개선 가설",
    core_reference = "run_wf_ensemble.R (walk-forward RCMA + Return.portfolio)",
    # emit v2 1급 인자 (승격축)
    portfolio_alpha_t = es$essence$portfolio_alpha_t_nw_lag3%||%NA,
    oos_retention = if(is.finite(oos_ret)) round(oos_ret,3) else NULL,
    falsification_attempts = if(length(.fr_fals)) .fr_fals else NULL,
    selection_type = if (nzchar(FR_SELECTION_TYPE)) FR_SELECTION_TYPE else "chain",   # 단일 config 러너(baseline/forecast A/B) — sweep argmax-pick 아님 (§3). ★FR_SELECTION_TYPE 이 있으면 essence 와 같은 값(두 경로 불일치 해소 · 2026-09-21)
    metrics = list(
      cagr_pct = round((es$essence$cagr%||%NA)*100,2), sharpe = es$essence$net_sharpe%||%NA,
      mdd_pct = round(abs(es$essence$mdd%||%NA)*100,2),
      calmar = es$essence$calmar%||%NA, dsr = es$essence$dsr%||%NA,
      ew_baseline_sr = round(ew_sr,3), edge_vs_ew = if(is.finite(.fr_edge_ew)) round(.fr_edge_ew,3) else NA_real_,
      n_modules = length(all_used_mods), n_trials = N_TRIALS))
}, error=function(e) cat("[run_wf_ensemble] FR L-code emit 생략(fail-soft):", conditionMessage(e), "\n"))

cat(sprintf("\n==== %s (regime rotation 앙상블) — 실측 [v4: %s 등급%s | Return.portfolio + WF RCMA + breadth gate] ====\n", FR_ID, GRADE_FREQ,
  paste0(if (isTRUE(FIX$single_window)) " · 단일 창" else "", if (isTRUE(FIX$dead_exclude)) " · 사망 모듈 제외" else "",
         if (isTRUE(FIX$dispatch_kr_floor)) " · 결정일 한국 거래일" else "", if (FR_V4_ABLATED) " · ★분해 대조(진단)" else "")))
cat(sprintf("grade=%s  net_Sharpe=%.3f  PORT_t=%.3f  DSR=%s  Calmar=%.2f  CAGR=%.1f%%  MDD=%.1f%%\n",
  es$grade, es$essence$net_sharpe%||%NA, es$essence$portfolio_alpha_t_nw_lag3%||%NA,
  as.character(round(es$essence$dsr,3)), es$essence$calmar%||%NA, (es$essence$cagr%||%NA)*100, (es$essence$mdd%||%NA)*100))
cat(sprintf("OOS_retention=%s (gate 0.7; IS active SR=%.3f)  |  EW baseline SR=%.3f  |  n_modules=%d  |  n_trials=%d\n",
  if(is.finite(oos_ret)) sprintf("%.3f", oos_ret) else paste0("unstable(", oos_ret_label, ")"), is_sr_active%||%NA, ew_sr, length(all_used_mods), N_TRIALS))
cat(sprintf("OOS window: %s start (breadth %d ≥ %d) | n_months=%d · n_obs=%d (%s..%s)\n",
  OOS_START_YM, OOS_START_BREADTH, MIN_BREADTH_OOS, N_MONTHS_WIN, n, as.character(min(MM$date)), as.character(max(MM$date))))
.ed <- es_diag$essence %||% list()
cat(sprintf("[진단 병기 · %s] grade=%s  net_Sharpe=%.3f  PORT_t=%.3f  Calmar=%.2f  CAGR=%.1f%%  MDD=%.1f%%  OOS_ret=%s — 판정 인용 금지\n",
  DIAG_FREQ, as.character(es_diag$grade %||% NA), .ed$net_sharpe %||% NA, .ed$portfolio_alpha_t_nw_lag3 %||% NA,
  .ed$calmar %||% NA, (.ed$cagr %||% NA)*100, (.ed$mdd %||% NA)*100, as.character(round(.ed$oos_retention %||% NA, 3))))
cat(sprintf("vs SR 2.5 target: %s\n", if(is.finite(es$essence$net_sharpe)&&es$essence$net_sharpe>=2.5) "달성" else sprintf("미달 (gap %.2f) — 정직 보고", 2.5-(es$essence$net_sharpe%||%0))))
