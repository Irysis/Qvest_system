# =============================================================================
# driver_ls_generic.R — 단일 factor long-short(top−bottom decile) 스크리닝 batch
#   ★ SIMPLIFIED (2026-06-06): value_bm 상관/캐시 빌드 제거 → 첫 run 경량화.
#     이전 버전이 첫 factor run에서 value_bm LS(=두 번째 fe_single + 양 leg 재구성)를
#     인라인으로 얹어 peak RAM 약 2배 → AC07 첫 run OOM/hang. value(BM) 직교 상관은
#     OOS robust 후보만 *사후 별도 가벼운 스텝*으로 계산(이번 batch서 제외).
# =============================================================================
# 목적: 미검증 직교 후보 factor(회계/유동성/투자/발행 기반)를 단일 factor
#       long-short로 빠르게 스크리닝. 가격/밸류 축과 다른 메커니즘이라 1st
#       eigenmode 공유가 적을 가능성 = long-only서도 OOS robust할 진짜 직교 축 후보.
#
#   판정 2축(1차, 단순): ① OOS retention 양수(>=0.5) ② Carhart4 alpha t 유의(|t|>=1.96)
#                       → 통과 후보만 사후 value(BM) 상관 별도 계산.
#
# ★ 측정만(QEPM 이행 없음 / book_state·governor 미사용 / WT-id 금지).
# ★ 자체합성 금지: leg 수익 = Return.portfolio(PerformanceAnalytics), 월간 집계 =
#   apply.monthly(., Return.cumulative). prod(1+r)/cumprod 손계산 없음.
#
# ===== PIT (C1~C15) =====
#   - 시그널: fe_single.R FACTORS(Date=월말, Score=Z_Score_Aligned). C13/C14/C15 준수.
#   - 보유: 월말 시그널 d_i → *다음 달* 보유(execution = d_i 다음달 첫 거래일,
#     get_execution_date 정합). 동일시점 순환참조 없음(C2). leg 종목은 d_i 시점
#     decile로 확정 후 (d_i, d_{i+1}] 일간수익 적용 — forward 정보 무사용.
#   - 유동성/멤버십은 fe_single에서 과거 윈도우(t-1)로 처리.
#
# 환경변수:
#   FACTOR_NAME (필수) — fe_single.R가 사용. STRAT_NAME (선택, 로그/출력명).
# 출력: stage_artifacts/alpha_search/ls_screen/<FACTOR_NAME>.json
#       { LS Sharpe, long/short leg Sharpe, Carhart4 t, OOS retention }
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(xts); library(zoo)
  library(PerformanceAnalytics); library(jsonlite)
})

# 견고한 %||% — sourced 파일이 취약버전으로 덮을 수 있어 선정의 후 최종 복원(section 7).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                 # load_rawdata, get_execution_date
source(file.path(INFRA, "factor_portfolios.R"))                # run_multifactor_regression (Carhart4)

FACTOR_NAME <- Sys.getenv("FACTOR_NAME", "")
STRAT_NAME  <- Sys.getenv("STRAT_NAME", FACTOR_NAME)
if (!nzchar(FACTOR_NAME)) stop("[driver_ls] FACTOR_NAME 미설정.")
DECILE_FRAC <- 0.10
ANN <- sqrt(12)

cat(sprintf("\n=== [LS-screen] %s (factor=%s) ===\n", STRAT_NAME, FACTOR_NAME))

# ---- 1. RAWDATA ----
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
all_dates <- sort(unique(RAWDATA$Date))

# ---- 2. fe_single -> FACTORS (Date, Ticker, Score) ----
#   ★ OOM v2 (2026-06-06): fe_single은 RAWDATA를 universe(.mem) 산출에만 쓰고 직후
#     rm(RAWDATA)한다(회계 factor는 가격 driver 아님). 그 rm이 실효를 가지려면 fe_env가
#     RAWDATA의 *유일 참조*여야 하므로, 여기서 driver의 RAWDATA 바인딩을 먼저 해제하고
#     fe_env로 소유권을 넘긴다. fe_single이 .mem 산출 후 rm(RAWDATA) → 378MB가 factor
#     일괄로딩(254회 full-parquet read + align merge) 동안 *완전 해제*된 채로 돈다.
#     section 3(build_leg_daily)는 RAWDATA를 다시 쓰므로 fe_single 직후 재로딩한다.
fe_env <- new.env()
fe_env$RAWDATA <- RAWDATA
rm(RAWDATA); gc(verbose = FALSE)                               # ★ driver 바인딩 해제 → fe_env가 유일 참조
sys.source(file.path(INFRA, "alpha_search", "fe_single.R"), envir = fe_env)
FACTORS <- fe_env$FACTORS
rm(fe_env); gc(verbose = FALSE)                                # ★ fe 환경 즉시 해제(이미 fe 내부서 RAWDATA rm됨)
# section 3(forward 수익 구성)용 RAWDATA 재로딩 (factor 일괄로딩 peak 종료 후 — co-resident 회피)
res2 <- load_rawdata(use_cache = TRUE)
RAWDATA <- res2$RAWDATA; rm(res2); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
# 표준 백테 기간 고정(2005~, alpha-search 제1원칙: 비교 일관)
FACTORS <- FACTORS[Date >= as.Date("2005-01-01")]
sig_dates <- sort(unique(FACTORS$Date))
cat(sprintf("[driver_ls] signal months=%d (%s..%s)\n",
            length(sig_dates), as.character(min(sig_dates)), as.character(max(sig_dates))))

# ---- 3. 월별 long(top decile) / short(bottom decile) leg 일간 수익 구성 ----
#   PIT: 시그널 d → 보유 (exec_date, next_sig_date]. exec_date = get_execution_date(d).
#   leg 수익 = 그 달 보유종목 EW. Return.portfolio로 leg별 일간 포트수익 산출.
build_leg_daily <- function(side) {   # side: "long"|"short"
  daily_list <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    md <- FACTORS[Date == d & is.finite(Score)]
    n <- nrow(md); if (n < 20L) next
    k <- max(2L, as.integer(ceiling(n * DECILE_FRAC)))
    setorder(md, -Score)
    picks <- if (side == "long") head(md$Ticker, k) else tail(md$Ticker, k)
    exec_date <- get_execution_date(d, all_dates)
    if (is.na(exec_date)) next
    # 보유 종료: 다음 시그널의 exec_date 직전(=다음 시그널 월 보유로 롤). 마지막은 데이터 끝까지.
    next_exec <- if (i < length(sig_dates)) get_execution_date(sig_dates[i + 1L], all_dates) else NA_Date_
    hold_end  <- if (!is.na(next_exec)) all_dates[all_dates < next_exec] else all_dates
    hold_end  <- max(hold_end[hold_end >= exec_date], exec_date)
    sub <- RAWDATA[Ticker %in% picks & Date >= exec_date & Date <= hold_end & is.finite(Ret),
                   .(Date, Ticker, Ret)]
    if (!nrow(sub)) next
    # wide daily returns (Date x Ticker), missing -> 0 (해당일 데이터 없으면 무수익으로 EW 유지)
    w <- dcast(sub, Date ~ Ticker, value.var = "Ret")
    setorder(w, Date)
    rmat <- as.matrix(w[, -1, with = FALSE]); rmat[!is.finite(rmat)] <- 0
    rx <- xts(rmat, order.by = w$Date)
    ew <- rep(1 / ncol(rx), ncol(rx))           # equal-weight (decile EW)
    # Return.portfolio: EW, 월내 weight drift 표준 처리(자체합성 아님)
    pr <- tryCatch(Return.portfolio(rx, weights = ew, rebalance_on = NA),
                   error = function(e) NULL)
    if (is.null(pr)) next
    daily_list[[i]] <- data.table(Date = as.Date(index(pr)), Ret = as.numeric(pr[, 1]))
  }
  out <- rbindlist(Filter(Negate(is.null), daily_list), use.names = TRUE)
  if (!nrow(out)) return(NULL)
  setorder(out, Date)
  # 보유구간 경계 중복일 제거(드물게 exec_date 겹침) → 일자별 평균(연속 보유 정합)
  out <- out[, .(Ret = mean(Ret)), by = Date]
  out
}

long_d  <- build_leg_daily("long")
short_d <- build_leg_daily("short")
if (is.null(long_d) || is.null(short_d)) stop("[driver_ls] leg 구성 실패(데이터 부족).")

# ---- 4. LS = long − short (gross, dollar-neutral) 일간 → 월간 ----
ls_d <- merge(long_d[, .(Date, L = Ret)], short_d[, .(Date, S = Ret)], by = "Date", all = TRUE)
ls_d[!is.finite(L), L := 0]; ls_d[!is.finite(S), S := 0]
ls_d[, LS := L - S]
setorder(ls_d, Date)

to_monthly <- function(dt, col) {       # PerformanceAnalytics 표준: apply.monthly + Return.cumulative
  x <- xts(dt[[col]], order.by = dt$Date)
  m <- apply.monthly(x, Return.cumulative)
  data.table(ym = format(as.Date(index(m)), "%Y-%m"), ret = as.numeric(m[, 1]))
}
ls_m    <- to_monthly(ls_d, "LS"); setnames(ls_m, "ret", "ls")
long_m  <- to_monthly(ls_d, "L");  setnames(long_m, "ret", "lng")
short_m <- to_monthly(ls_d, "S");  setnames(short_m, "ret", "sht")

sharpe_ann <- function(x) { x <- x[is.finite(x)]; s <- sd(x); if (!is.finite(s) || s <= 0) return(NA_real_); mean(x)/s*ANN }
ls_sharpe    <- sharpe_ann(ls_m$ls)
long_sharpe  <- sharpe_ann(long_m$lng)
short_sharpe <- sharpe_ann(short_m$sht)

# ---- 5. OOS retention (IS<=2015 / OOS>=2016, LS monthly Sharpe). LS=dollar-neutral → LS자체가 'active' ----
ls_m[, yr := as.integer(substr(ym, 1, 4))]
sr_is  <- sharpe_ann(ls_m[yr <= 2015, ls])
sr_oos <- sharpe_ann(ls_m[yr >= 2016, ls])
oos_retention <- if (is.finite(sr_is) && abs(sr_is) > 1e-9) sr_oos / sr_is else NA_real_

# ---- 6. Carhart4 alpha t (run_multifactor_regression, NW HAC) ----
#   LS는 self-financing(dollar-neutral)이라 RF 차감이 엄밀히는 불요지만, infra 계약
#   (run_multifactor_regression: Excess=Strat-RF)을 재사용. RF 월간 미미 → 부호/유의성 영향 미소.
ls_xts <- xts(ls_d$LS, order.by = ls_d$Date)
mf <- tryCatch(run_multifactor_regression(ls_xts), error = function(e) NULL)
carhart4_t     <- tryCatch(mf$Carhart4$alpha_tstat, error = function(e) NA_real_) %||% NA_real_
carhart4_alpha_m <- tryCatch(mf$Carhart4$alpha, error = function(e) NA_real_) %||% NA_real_
ff3_t          <- tryCatch(mf$FF3$alpha_tstat, error = function(e) NA_real_) %||% NA_real_
if (is.null(carhart4_t) || length(carhart4_t)==0) carhart4_t <- NA_real_

# ---- 7. 판정(1차 단순) + 저장 ----
#   value(BM) 직교 상관은 이번 batch서 제외 → OOS robust 후보만 사후 별도 가벼운 스텝.
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
ax_oos     <- is.finite(oos_retention) && oos_retention >= 0.5
ax_carhart <- is.finite(carhart4_t) && abs(carhart4_t) >= 1.96
ortho_candidate <- ax_oos && ax_carhart      # 1차 통과 후보(value_bm 상관은 사후)

out <- list(
  strat_name = STRAT_NAME, factor_name = FACTOR_NAME,
  metric_type = "backtested_gross_Return.portfolio",
  universe = "K200_KQ150", start_date = "2005-01-01",
  signal_months = length(sig_dates), month_range = paste(min(ls_m$ym), max(ls_m$ym), sep=".."),
  ls_sharpe = round(ls_sharpe, 4), long_leg_sharpe = round(long_sharpe, 4), short_leg_sharpe = round(short_sharpe, 4),
  oos_active_sharpe_IS = round(sr_is, 4), oos_active_sharpe_OOS = round(sr_oos, 4),
  oos_retention = round(oos_retention, 4), oos_split = "IS<=2015 / OOS>=2016",
  carhart4_alpha_t = round(carhart4_t, 4), carhart4_alpha_monthly = round(carhart4_alpha_m, 6),
  ff3_alpha_t = round(ff3_t, 4),
  axes = list(oos_retention_ge_0p5 = ax_oos, carhart4_t_ge_1p96 = ax_carhart),
  ortho_candidate_1st = ortho_candidate,
  corr_vs_value_bm = "deferred: computed post-hoc only for 1st-pass ortho candidates",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
out_dir <- file.path(PROJ, "stage_artifacts", "alpha_search", "ls_screen")
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
out_path <- file.path(out_dir, sprintf("%s.json", FACTOR_NAME))
write_json(out, out_path, auto_unbox=TRUE, pretty=TRUE, digits=6)

cat(sprintf("\n[RESULT] %s | LS_SR=%.3f (L=%.3f S=%.3f) | OOS_ret=%.3f | Carhart4_t=%.2f | %s\n",
            FACTOR_NAME, ls_sharpe %||% NA, long_sharpe %||% NA, short_sharpe %||% NA,
            oos_retention %||% NA, carhart4_t %||% NA,
            if (ortho_candidate) "ORTHO_CANDIDATE_1ST" else "not-ortho"))
cat(sprintf("[saved] %s\n", out_path))
