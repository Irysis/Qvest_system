#!/usr/bin/env Rscript
# =============================================================================
# run_fr002_scrap_pool.R — FR_002: 폐지 풀(grade C/F) 배분정책 리서치 (Track2 allocation)
#
# 위치: factor-rotation 모드 Lane3 (모듈 *소비* meta-layer). 신규 모듈 생산 없음.
#
# FR_001 과의 차별점 (Step 0 지식 대조 결과, 2026-08-09):
#   FR_001 = 우량 12모듈(grade A/B) x RCMA 국면조건부 배분 → grade C
#   FR_002 = **폐지 85모듈(grade C/F)** x **무조건부 대 국면조건부 직접 대결**
#   재료(등급 미달 풀)와 질문(국면조건부가 정말 이기는가) 둘 다 다르다.
#
# 라운드 실측 요지 (stage_artifacts/scrap_ensemble_20260809/):
#   · 명목 195 → corr>=0.999 병합 유효 독립 85 (축소 55.5%, 최대 중복그룹 49)
#   · 국면조건부 축의 정체 = beta (spearman -0.975/+0.985, 잔차화 시 지속성 음수 붕괴)
#     ⇒ 멤버십 아닌 노출 스케일 축, WT-D20260809_002 소관으로 이관
#   · 국면 라벨 무판별: P(DOWN|DOWN_t-1)=0.133 vs base rate 0.122
#   · 잔차-직교 선택은 무조건부에 열등 (paired t 전 K 음수)
#   · 살아남은 축 = **무조건부 trailing 평균 top-K** (paired t_NW3 2.596~2.856)
#
# ★ selection_type = "sweep" (규칙 3종 x K 격자 5점) → DSR HARD 적용 대상.
#   K=10 은 격자 최소값이며 사전등록 없이 사후 선택되었으므로 argmax 편의가 남아 있다.
#   그 보정을 DSR 에 맡기고 n_trials 를 보수적으로 계상한다(풀 크기 + config 격자).
#
# 거버넌스: governor 정지. book_state 자동 쓰기 없음. 실편입은 Q-Lead+도훈 수동.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
CD  <- file.path(PROJ, "02_Infrastructure/contracts")
OUTD <- file.path(PROJ, "04_Research/factor_rotation/output")
dir.create(OUTD, showWarnings = FALSE, recursive = TRUE)
source(file.path(CD, "backtest_result_contract.R")); source(file.path(CD, "audit_bt_result.R"))
source(file.path(CD, "essence_score.R"))
`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || all(is.na(a))) b else a
sink(file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809/fr002_run.log"), split = TRUE)

## ── 1. 폐지 풀 정의 + dedup ───────────────────────────────────────────
MP <- fromJSON(file.path(PROJ, "06_Registry/module_performance.json"), simplifyVector = FALSE)
mods <- MP$modules
grades <- vapply(mods, function(m) if (is.null(m$grade)) NA_character_ else as.character(m$grade), character(1))
scrap_ids <- names(mods)[grades %in% c("C","F")]
cat(sprintf("[1] 폐지 풀 후보 (grade C|F) = %d / %d\n", length(scrap_ids), length(mods)))

P <- readRDS(file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809/p0_panel.rds"))
PAN <- P$PAN
# [2026-08-09 수리] module_performance ⊄ PAN 을 가정하지 않는다.
#   패널은 스냅샷이고 module_performance 는 계속 갱신되므로, 패널 이후 등재된 모듈이
#   scrap_ids 에 들어오면 `subm[, ..scrap_ids]` 가 "columns not found" 로 죽는다
#   (실측: 벤치 이음매 재실행분 2건 등재 직후 재빌드 실패). 교집합으로 좁히고 **드롭을 로그**한다
#   — 조용히 줄이면 "풀이 원래 그만큼"으로 읽히므로 개수와 사유를 남긴다.
.missing <- setdiff(scrap_ids, names(PAN))
if (length(.missing)) {
  cat(sprintf("[1b] ★패널 미수록 %d건 제외 (p0_panel 스냅샷 이후 등재): %s\n",
              length(.missing), paste(utils::head(.missing, 5), collapse=", ")))
  scrap_ids <- intersect(scrap_ids, names(PAN))
}
cat(sprintf("[1c] 패널 정합 후 풀 = %d\n", length(scrap_ids)))
subm <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(subm, ym)
Mall <- as.matrix(subm[, ..scrap_ids]); keepc <- which(colSums(is.finite(Mall)) >= 253)
rowsc <- complete.cases(Mall[, keepc, drop = FALSE])
Mm <- Mall[rowsc, keepc, drop = FALSE]; ids_full <- scrap_ids[keepc]
Cc <- cor(Mm); diag(Cc) <- 0; hi <- which(Cc >= 0.999, arr.ind = TRUE); hi <- hi[hi[,1] < hi[,2], , drop=FALSE]
comp <- local({ par <- seq_len(ncol(Mm)); f <- function(x){while(par[x]!=x) x<-par[x]; x}
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a<-f(hi[r,1]); b<-f(hi[r,2]); if (a!=b) par[b]<-a }
  vapply(seq_len(ncol(Mm)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
POOL <- ids_full[reps]
cat(sprintf("[1b] dedup(corr>=0.999 union-find): %d → **%d** (축소 %.1f%%, 최대 중복그룹 %d)\n",
            ncol(Mm), length(POOL), 100*(1-length(POOL)/ncol(Mm)), max(table(comp))))

## ── 2. 일간 수익 매트릭스 + 벤치 (계약 경로: 일간 → contract 가 월집계) ──
rets <- list(); bmref <- NULL; bmn <- 0L
for (sid in POOL) {
  s <- tryCatch(readRDS(file.path(PROJ, mods[[sid]]$sim_result_path)), error=function(e) NULL)
  if (is.null(s) || is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=as.numeric(Strategy_Ret))]
  rets[[sid]] <- d
  if (!is.null(s$bm_xts) && nrow(s$bm_xts) > bmn) {
    bmref <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])); bmn <- nrow(s$bm_xts) }
}
POOL <- names(rets)
RM <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE),
             lapply(POOL, function(s){ x<-copy(rets[[s]]); setnames(x,"r",s); x }))
setorder(RM, Date); RM[, ym := format(Date, "%Y%m")]
cat(sprintf("[2] 일간 매트릭스: %d rows x %d modules (%s..%s) | bm n=%d\n",
            nrow(RM), length(POOL), as.character(min(RM$Date)), as.character(max(RM$Date)), bmn))

## ── 3. 배분정책: 무조건부 trailing 평균 top-K (walk-forward, IS-only) ──
##    PIT: t 월말까지의 active 평균으로 t+1 보유 종목 결정. 모듈 frozen.
ym_all <- sort(unique(RM$ym))
mret <- copy(subm[rowsc]); mdates_m <- ym_all
Am <- Mm[, reps, drop=FALSE] - matrix(subm$bm[rowsc], nrow(Mm), length(reps))   # 월간 active
ym_m <- subm$ym[rowsc]
IS0 <- 60L
KGRID <- c(10, 20, 30, 40, 50); K_PRIMARY <- 10L
cat(sprintf("[3] 배분정책 = 무조건부 trailing 평균 top-K · IS 최초 %d개월 · K 격자 %s (primary %d)\n",
            IS0, paste(KGRID, collapse="/"), K_PRIMARY))

## 리밸 날짜 = 각 월 첫 거래일. 가중은 직전 월말까지 정보로 산출.
rb <- RM[, .(Date = min(Date)), by = ym]; setorder(rb, ym)
mk_weights <- function(kk) {
  W <- data.table(Date = rb$Date)
  for (cn in POOL) W[, (cn) := 0]
  for (j in seq_len(nrow(rb))) {
    tgt <- rb$ym[j]; i_m <- match(tgt, ym_m)
    if (is.na(i_m) || i_m <= IS0) next
    sc <- colMeans(Am[1:(i_m-1), , drop=FALSE], na.rm=TRUE)     # ★ t-1 까지만
    pick <- POOL[order(sc, decreasing=TRUE)[1:kk]]
    for (cn in pick) set(W, j, cn, 1/kk)
  }
  W
}
run_policy <- function(kk) {
  W <- mk_weights(kk)
  keep <- rowSums(as.matrix(W[, ..POOL])) > 0
  W <- W[keep]
  first_d <- min(W$Date)
  RMo <- RM[Date >= first_d]
  Rx <- xts(as.matrix(RMo[, ..POOL]), order.by = RMo$Date)
  Rx[is.na(Rx)] <- 0
  Wx <- xts(as.matrix(W[, ..POOL]), order.by = W$Date)
  pr <- Return.portfolio(R = Rx, weights = Wx, rebalance_on = NA, verbose = TRUE)
  gross <- pr$returns
  # 모듈 교체 회전 비용: 리밸 시점 |Δw| 합 / 2 × 15bps (delta-based, 레그당 과금)
  Wm <- as.matrix(W[, ..POOL]); dW <- abs(Wm - rbind(rep(0, ncol(Wm)), Wm[-nrow(Wm), , drop=FALSE]))
  to_by_rb <- rowSums(dW)
  cost <- data.table(Date = W$Date, c = to_by_rb * 0.0015)
  gd <- data.table(Date = as.Date(index(gross)), r = as.numeric(gross))
  gd <- merge(gd, cost, by = "Date", all.x = TRUE); gd[is.na(c), c := 0]
  gd[, r_net := r - c]
  list(dt = gd, turn_ann = 12 * mean(to_by_rb) / 2, W = W, first_d = first_d)
}

cat("\n[3b] K 격자 전량 진단 (argmax 아님 — 전량 보고) ---------------------------\n")
grid_rows <- list()
for (kk in KGRID) {
  z <- run_policy(kk)
  mx <- apply.monthly(xts(z$dt$r_net, order.by = z$dt$Date), Return.cumulative)
  bmx <- apply.monthly(xts(bmref[Date %in% z$dt$Date]$bm,
                           order.by = bmref[Date %in% z$dt$Date]$Date), Return.cumulative)
  L <- min(length(mx), length(bmx)); a <- as.numeric(mx)[1:L] - as.numeric(bmx)[1:L]
  m <- lm(a ~ 1); tt <- as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1])
  ar <- table.AnnualizedReturns(mx, scale=12); md <- as.numeric(maxDrawdown(mx))
  cat(sprintf("   K=%-3d CAGR=%6.2f%% SR=%5.3f MDD=%5.1f%% Calmar=%5.3f active=%+.3f%%/m t_NW3=%+.3f TO=%3.0f%%\n",
              kk, 100*ar[1,1], ar[3,1], 100*md, ar[1,1]/md, 100*mean(a), tt, 100*z$turn_ann))
  grid_rows[[as.character(kk)]] <- list(K=kk, cagr=as.numeric(ar[1,1]), sharpe=as.numeric(ar[3,1]),
    mdd=md, calmar=as.numeric(ar[1,1])/md, active_pm=mean(a), active_t_nw3=tt, turnover=z$turn_ann)
}

## ── 4. primary 정책 계약 측정 ─────────────────────────────────────────
z <- run_policy(K_PRIMARY)
ED_xts <- xts(z$dt$r_net, order.by = z$dt$Date)
bmo <- bmref[Date %in% z$dt$Date]; setorder(bmo, Date)
bm_xts <- xts(bmo$bm, order.by = bmo$Date)
mret_net <- apply.monthly(ED_xts, Return.cumulative)
nav_net  <- as.numeric(cumprod(1 + as.numeric(mret_net)))
sim_result <- list(
  DAILY_NAV_DT = data.table(Date = as.Date(index(mret_net)), NAV = nav_net),
  strategy_xts = ED_xts, bm_xts = bm_xts,
  HOLDINGS_LOG = list(), PORTFOLIO_LOG = data.table(Exec_Date = as.Date(z$W$Date)))
spec <- list(
  strategy_name = "FR_002_scrap_pool_unconditional_topK",
  signal = "unconditional trailing-mean active top-K over grade C/F module pool",
  module_pool = POOL,
  regime_source = "none (무조건부) — 국면조건부 변형은 동일 라운드에서 열세로 실측",
  weighting = sprintf("equal-weight top-%d, monthly rebalance; Return.portfolio (자체합성 없음)", K_PRIMARY),
  rebalance = "monthly",
  lookahead_prevention = paste0(
    "선택 점수는 직전 월말까지 active 평균만 사용(t-1) · 모듈 frozen · anchored walk-forward IS 60개월 · ",
    "Return.portfolio 경유(prod/cumprod/Sigma-w 손합성 없음) · dedup 은 수익벡터 상관 기준으로 성과와 무관"))
bt <- build_bt_result(sim_result, spec, run_id = "FR_002", strategy_id = "FR_002", strategy_version = "v1",
        benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200", transaction_cost_bps = 15, slippage_bps = 0,
        risk_free_rate = 0, frequency = "monthly", annualization_factor = 12, universe_id = "KR_modules_scrap",
        code_version = "run_fr002_scrap_pool_v1", created_by_agent = "Q-Lead")
bt <- audit_bt_result(bt)
N_TRIALS <- length(POOL) + length(KGRID) * 3L      # 풀 크기 + 규칙 3종 x K 격자 5점 (보수적)
es <- essence_score(bt, n_trials_cumulative = N_TRIALS)
cat(sprintf("\n[4] 계약 측정: grade=%s metric_type=%s | audit=%s | n_trials=%d\n",
            es$grade, es$metric_type, bt$audit$integrity %||% "NA", N_TRIALS))
print(unlist(es$essence))

## ── 5. OOS retention + placebo(EW 동일구간) ───────────────────────────
PRm <- as.data.table(bt$period_returns)[, .(date, ret_net)]
BRm <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
MM <- merge(PRm, BRm, by="date"); setorder(MM, date); nmo <- nrow(MM)
shp <- function(x){ x<-x[is.finite(x)]; if(length(x)<2||sd(x)==0) return(NA); mean(x)/sd(x)*sqrt(12) }
act <- MM$ret_net - MM$benchmark_ret; k65 <- floor(nmo*0.65)
is_sr <- shp(act[1:k65]); oos_sr <- shp(act[(k65+1):nmo])
oos_local <- if (is.finite(is_sr) && abs(is_sr) >= 0.1 && is.finite(oos_sr)) oos_sr/is_sr else NA_real_
oos_ret <- es$essence$oos_retention %||% oos_local
# placebo = 동일 구간 폐지 풀 EW (선택 없음)
Wew <- data.table(Date = z$W$Date); for (cn in POOL) Wew[, (cn) := 1/length(POOL)]
RMo <- RM[Date >= z$first_d]; Rx <- xts(as.matrix(RMo[, ..POOL]), order.by=RMo$Date); Rx[is.na(Rx)] <- 0
ew_pr <- Return.portfolio(R=Rx, weights=xts(as.matrix(Wew[, ..POOL]), order.by=Wew$Date), rebalance_on=NA)
ew_m <- apply.monthly(ew_pr, Return.cumulative); ew_sr <- shp(as.numeric(ew_m))
cat(sprintf("[5] oos_retention=%s (IS active SR %.3f → OOS %.3f) | placebo EW SR=%.3f | edge_vs_ew=%+.3f\n",
            ifelse(is.finite(oos_ret), sprintf("%.3f", oos_ret), "unstable"), is_sr, oos_sr, ew_sr,
            (es$essence$net_sharpe %||% NA) - ew_sr))

## ── 6. HARD 게이트 판정 (정직 표기) ───────────────────────────────────
hard <- list(
  port_t   = list(v = es$essence$portfolio_alpha_t_nw_lag3 %||% NA, thr = 2.95),
  oos_ret  = list(v = oos_ret, thr = 0.70),
  calmar   = list(v = es$essence$calmar %||% NA, thr = 0.64),
  dsr      = list(v = es$essence$dsr %||% NA, thr = 0.50))
cat("\n[6] HARD 게이트 (selection_type=sweep → DSR 적용):\n")
for (nm in names(hard)) {
  h <- hard[[nm]]
  cat(sprintf("   %-9s %8s  vs %.2f  → %s\n", nm,
              ifelse(is.finite(h$v), sprintf("%.3f", h$v), "NA"), h$thr,
              ifelse(is.finite(h$v) && h$v >= h$thr, "PASS", "FAIL")))
}

## ── 7. FR 등재 (실측-only. governor 정지 — book_state 쓰기 없음) ──────
fr <- list(
  fr_id = "FR_002", grade = es$grade, metric_type = es$metric_type, essence = es$essence,
  n_modules = length(POOL), module_pool = POOL, n_months = nmo, n_trials_cumulative = N_TRIALS,
  selection_type = "sweep",
  oos_retention = if (is.finite(oos_ret)) round(oos_ret,3) else NA_real_,
  oos_is_active_sharpe = round(is_sr,3), oos_oos_active_sharpe = round(oos_sr,3),
  ew_baseline_SR = round(ew_sr,3),
  net_sharpe = es$essence$net_sharpe, port_t = es$essence$portfolio_alpha_t_nw_lag3, dsr = es$essence$dsr,
  K_primary = K_PRIMARY, K_grid = grid_rows,
  pool_definition = "module_performance grade C|F, 완전커버 191 → corr>=0.999 union-find dedup → 85",
  differentiation_vs_FR001 = paste0(
    "FR_001 = 우량 12모듈(A/B) x RCMA 국면조건부. FR_002 = 폐지 85모듈(C/F) x 무조건부. ",
    "동일 라운드에서 국면조건부 변형을 직접 대결시켜 열세를 실측(라벨 무판별 P(DOWN|DOWN_t-1)=0.133 vs base 0.122, ",
    "상태-조건부 순위의 정체 = beta spearman -0.975/+0.985)."),
  code_version = "run_fr002_scrap_pool_v1",
  lookahead_prevention = spec$lookahead_prevention,
  return_synthesis = "PerformanceAnalytics::Return.portfolio (monthly rebalance; no prod/cumprod/Sigma-w self-synthesis)",
  governor_status = "정지 — book_state 자동 쓰기 없음. 실편입은 Q-Lead+도훈 수동 confirm.",
  date_range = c(as.character(min(MM$date)), as.character(max(MM$date))))
write_json(fr, file.path(OUTD, "FR_002_result.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
saveRDS(bt, file.path(OUTD, "FR_002_bt_result.rds"))
tryCatch({ source(file.path(CD, "factor_rotation_registry.R"))
  register_fr_result(fr, regime_engine_version = "none (무조건부 배분 — 국면조건부 변형은 동일 라운드 실측 열세)",
                     allocation_policy = sprintf("unconditional trailing-mean active top-%d EW, monthly rebalance, walk-forward IS-only", K_PRIMARY)) },
  error = function(e) cat("[FR_002] registry 실패:", conditionMessage(e), "\n"))

## ── 8. L-code 발행 (FR 모드 emit 1지점) ───────────────────────────────
tryCatch({
  source(file.path(PROJ, "02_Infrastructure/axiom/lcode_emit.R"))
  edge <- (es$essence$net_sharpe %||% NA) - ew_sr
  emit_fr_lcode(strategy_id = "FR_002", grade = es$grade,
                sharpe = es$essence$net_sharpe, port_t = es$essence$portfolio_alpha_t_nw_lag3,
                oos_retention = oos_ret, calmar = es$essence$calmar, dsr = es$essence$dsr,
                admitted_pool = POOL, edge_vs_ew = edge)
}, error = function(e) cat("[FR_002] L-code emit 생략:", conditionMessage(e), "\n"))

cat("\n[done] FR_002 → 04_Research/factor_rotation/output/FR_002_result.json\n")
sink()
