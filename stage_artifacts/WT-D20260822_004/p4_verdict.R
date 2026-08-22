## WT-D20260822_004 · P4 — 사전등록 판정 (paired) + basis 3종 + 통제 + 강건성 + advisory
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_004"; SRC <- "stage_artifacts/fq233_probe0_20260813"
W002 <- "stage_artifacts/WT-D20260822_002"
B  <- readRDS(file.path(OUT, "p1_arms.rds")); P2 <- readRDS(file.path(OUT, "p2_power.rds"))
sel_rank <- B$sel_rank; K <- B$K; TOPN <- B$TOPN; CLIP <- B$CLIP; MATERIAL <- P2$MATERIAL
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
ALLA <- sort(unique(pan$anchor)); months <- names(sel_rank)
panh <- pan[anchor %in% B$anchors & is.finite(fwd_ret_1m)]
fwd  <- panh[, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)]
returns_dt <- B$returns_dt; bench_iks <- B$bench_dt
p0 <- readRDS(file.path(W002, "p0_returns.rds"))
bench_parent <- as.data.table(p0$bench)[, .(Date, BM_Ret)]
liq_dt <- as.data.table(p0$liq)

pctrank <- function(v) { ok <- is.finite(v); r <- rep(NA_real_, length(v))
  if (sum(ok) >= 2L) r[ok] <- (frank(v[ok], ties.method = "average") - 0.5)/sum(ok); r }
CF <- list(
  C0 = function(Z) rowMeans(Z, na.rm = TRUE),
  C1 = function(Z) rowMeans(apply(Z, 2L, pctrank), na.rm = TRUE),
  C2 = function(Z) rowMeans(pmax(pmin(Z, CLIP), -CLIP), na.rm = TRUE),
  C3 = function(Z) apply(Z, 1L, function(x) if (all(!is.finite(x))) NA_real_ else max(x, na.rm = TRUE)))

## 통제 arm = 결합 **입력 z** 의 vintage 이동 (선별 궤적·결합 규칙 불변)
build_from <- function(fn, shift = 0L) rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- sel_rank[[nm]]
  i <- match(as.Date(nm), ALLA); j <- i + shift
  if (is.na(j) || j < 1L || j > length(ALLA)) return(NULL)
  src <- pan[anchor == ALLA[j]]; tgt <- panh[anchor == as.Date(nm)]
  Z <- as.matrix(src[match(as.character(tgt$Ticker), as.character(src$Ticker)), ..fs])
  nv <- rowSums(is.finite(Z)); sc <- fn(Z)
  data.table(Date = as.Date(nm), Ticker = as.character(tgt$Ticker),
             score = ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)] }))

SCA <- lapply(CF, function(f) build_from(f, 0L))
SCA$LEAK1  <- build_from(CF$C0, +1L)
SCA$LAG1   <- build_from(CF$C0, -1L)
## ORACLE = 창-도달가능성 상한. ★홀딩월 221개로 정렬 (fwd 는 257개월 — 미정렬 시 paired 재활용 오류)
SCA$ORACLE <- fwd[Date %in% as.Date(months), .(Date, Ticker, score = fwd)]
## ORACLE_K = ★사후 진단(사전등록 arm 아님, 판정 대상 아님) — 결합 마디 자체의 여유폭 상한.
##   매월 선별 K=5 중 **실현** 차월 rank-IC 가 최대인 팩터 하나를 완전예지로 채택.
##   {K 개 중 고르기} 족(族)의 상한이므로, 이 값이 낮으면 어떤 결합기(ML 포함)도 이 마디에서 못 넘긴다.
SCA$ORACLE_K <- rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  ic <- vapply(fs, function(f) { v <- d[[f]]; ok <- is.finite(v) & is.finite(d$fwd_ret_1m)
    if (sum(ok) < 30L) return(-Inf); cor(rank(v[ok]), rank(d$fwd_ret_1m[ok])) }, 0)
  best <- fs[which.max(ic)]
  data.table(Date = as.Date(nm), Ticker = as.character(d$Ticker), score = d[[best]])[is.finite(score)] }))

run <- function(s, bench, id, liq = NULL) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[, .(Date, Ticker, score)], returns_dt, bench, top_n = TOPN,
    cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
    run_id = id, strategy_id = id, diag_dual_basis = TRUE) }

cat("=== 1) 전 arm 측정 (primary basis = IKS200) ===\n")
RES <- lapply(setNames(names(SCA), names(SCA)),
              function(a) { cat("  ", a, "\n"); run(SCA[[a]], bench_iks, paste0("FQ244_", a)) })
act <- lapply(RES, function(b) { pr <- as.data.table(b$period_returns)
  pr[, .(Date = as.Date(date), act = ret_net - benchmark_ret)] })
c0 <- act$C0$act; n <- length(c0)

pairedstat <- function(x, y, lab) { d <- x - y; t <- .nw_t_mean(d, lag = 3L)
  se_m <- abs(mean(d)/t); ann <- mean(d)*12*100; se_a <- se_m*12*100
  data.table(contrast = lab, n = length(d), ann_pct = ann, t_nw3 = t, se_ann_pct = se_a,
             ci95_lo = ann - 1.96*se_a, ci95_hi = ann + 1.96*se_a) }

cat("\n=== 2) 사전등록 primary — paired (arm - C0), NW lag-3, n=", n, " ===\n", sep = "")
PRI <- rbindlist(lapply(c("C1","C2","C3","LEAK1","LAG1","ORACLE","ORACLE_K"),
                        function(a) pairedstat(act[[a]]$act, c0, a)))
PRI[, label := fifelse(t_nw3 >= 2, "EFFECT_POSITIVE",
              fifelse(t_nw3 <= -2, "EFFECT_NEGATIVE",
              fifelse(ci95_hi < MATERIAL, "POWERED_NULL_NO_MATERIAL_EFFECT",
                      "UNDERPOWERED_UNRESOLVED")))]
print(PRI[, .(contrast, ann_pct = round(ann_pct, 4), t_nw3 = round(t_nw3, 4),
              ci95 = paste0("[", round(ci95_lo, 2), ", ", round(ci95_hi, 2), "]"), label)])
cat(sprintf("\n  MATERIAL 문턱 = %.4f %%p/yr (사전등록 고정)\n", MATERIAL))

cat("\n=== 3) basis 3종 ===\n")
RESP <- lapply(setNames(names(SCA), names(SCA)),
               function(a) run(SCA[[a]], bench_parent, paste0("FQ244p_", a)))
BAS <- rbindlist(lapply(names(RES), function(a) {
  d <- RES[[a]]$diag_ew_universe
  data.table(arm = a, port_t_IKS200 = RES[[a]]$portfolio_alpha_t_nw_lag3,
             port_t_parent_capw = RESP[[a]]$portfolio_alpha_t_nw_lag3,
             port_t_EW_universe = d$portfolio_alpha_t_nw_lag3,
             ir_IKS200 = RES[[a]]$information_ratio, ir_parent = RESP[[a]]$information_ratio,
             post2017_t_EWuni = d$post2017_t_nw_lag3,
             oos_ret_approx = d$oos_retention_approx, turnover = RES[[a]]$turnover_annual) }))
print(BAS[, .(arm, IKS200 = round(port_t_IKS200,4), parent = round(port_t_parent_capw,4),
              EWuni = round(port_t_EW_universe,4), ir = round(ir_IKS200,4),
              post2017_EWuni = round(post2017_t_EWuni,3), TO = round(turnover,2))])
cat("  benchmark_id 하드코딩 주의 — 실제 넘긴 계열: primary = .cache/benchmark.parquet(IKS200)")
cat(" / parent = WT-D20260822_002 p0_returns.rds bench (build_monthly_forward_returns cap-w)\n")

cat("\n=== 4) basis-불변성 (paired dt) ===\n")
actp <- lapply(setNames(names(SCA), names(SCA)), function(a) {
  pr <- as.data.table(RESP[[a]]$period_returns)
  pr[, .(Date = as.Date(date), act = ret_net - benchmark_ret)] })
for (a in c("C1","C2","C3")) {
  t1 <- pairedstat(act[[a]]$act, c0, a)$t_nw3
  t2 <- pairedstat(actp[[a]]$act, actp$C0$act, a)$t_nw3
  cat(sprintf("  %-3s IKS200 t %+.8f vs parent t %+.8f  delta = %.3e\n", a, t1, t2, t1 - t2)) }

cat("\n=== 5) 강건성 ===\n")
LIQ <- lapply(setNames(c("C0","C1","C2","C3"), c("C0","C1","C2","C3")), function(a)
  run(SCA[[a]], bench_iks, paste0("FQ244L_", a), liq = liq_dt))
cat("  R_LIQ (2e8):\n")
for (a in names(LIQ)) cat(sprintf("    %-3s PORT_t %+.4f (n=%d)\n", a,
  LIQ[[a]]$portfolio_alpha_t_nw_lag3, LIQ[[a]]$n_months))
actl <- lapply(LIQ, function(r) { pr <- as.data.table(r$period_returns); pr$ret_net - pr$benchmark_ret })
for (a in c("C1","C2","C3")) { d <- actl[[a]] - actl$C0
  cat(sprintf("    paired %-3s t %+.4f (연 %+.3f%%p)\n", a, .nw_t_mean(d, lag = 3L), mean(d)*12*100)) }

cut <- as.Date("2015-07-01"); idx <- act$C0$Date < cut
cat("\n  R_SUB (진단 병기만 — era 교락 + universe_exit_unrecorded_pre201512, 편향 하방/중립):\n")
for (a in c("C1","C2","C3")) { d <- act[[a]]$act - c0
  cat(sprintf("    %-3s pre (n=%d) t %+.4f 연 %+.3f%%p | post (n=%d) t %+.4f 연 %+.3f%%p\n", a,
    sum(idx), .nw_t_mean(d[idx], lag = 3L), mean(d[idx])*12*100,
    sum(!idx), .nw_t_mean(d[!idx], lag = 3L), mean(d[!idx])*12*100)) }
cat("\n  R_TOP5 (|diff| 상위 5개월 제외):\n")
for (a in c("C1","C2","C3")) { d <- act[[a]]$act - c0; k <- order(abs(d), decreasing = TRUE)[1:5]
  cat(sprintf("    %-3s t %+.4f -> %+.4f  (연 %+.3f -> %+.3f %%p)\n", a,
    .nw_t_mean(d, lag = 3L), .nw_t_mean(d[-k], lag = 3L), mean(d)*12*100, mean(d[-k])*12*100)) }

cat("\n=== 6) advisory 배터리 (선택 권위 아님 — rank-IC t 와 portfolio-alpha t 는 다른 것) ===\n")
ADV <- rbindlist(lapply(c("C0","C1","C2","C3"), function(a) {
  j <- merge(SCA[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ric = if (.N >= 30 && sd(score) > 0) cor(rank(score), rank(fwd)) else NA_real_,
              pic = if (.N >= 30 && sd(score) > 0) cor(score, fwd) else NA_real_,
              mono = if (.N >= 50) { q <- ceiling(10 * frank(score, ties.method="first") / .N)
                                     mm <- tapply(fwd, q, mean)
                                     if (length(mm) < 3L) NA_real_ else cor(as.integer(names(mm)), as.numeric(mm), method = "spearman") } else NA_real_),
           by = Date]
  data.table(arm = a, rank_ic = mean(ic$ric, na.rm = TRUE), rank_ic_sd = sd(ic$ric, na.rm = TRUE),
    icir_monthly = mean(ic$ric, na.rm = TRUE)/sd(ic$ric, na.rm = TRUE),
    harvey_t_rankic_nw3 = .nw_t_mean(ic$ric[is.finite(ic$ric)], lag = 3L),
    pearson_ic = mean(ic$pic, na.rm = TRUE),
    pearson_t_nw3 = .nw_t_mean(ic$pic[is.finite(ic$pic)], lag = 3L),
    monotonicity = mean(ic$mono, na.rm = TRUE)) }))
print(ADV[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 5) else x)])

cat("\n=== 7) 성과표 + DSR 진단 (게이트 아님, selection_type = preregistered_arms_no_champion) ===\n")
PERF <- rbindlist(lapply(names(RES), function(a) { r <- RES[[a]]; pr <- as.data.table(r$period_returns)
  nav <- cumprod(1 + pr$ret_net); cg <- nav[length(nav)]^(12/length(nav)) - 1
  mdd <- max(1 - nav/cummax(nav))
  data.table(arm = a, cagr = cg, mdd = mdd, calmar = cg/mdd, net_sr = r$net_sr,
             active_ir = r$information_ratio, alpha_ann = r$alpha_annualized,
             port_t = r$portfolio_alpha_t_nw_lag3, turnover = r$turnover_annual) }))
print(PERF[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 4) else x)])
gam <- 0.5772156649
dsr_fun <- function(sr, nobs, trials) { if (!is.finite(sr)) return(NA_real_)
  z <- if (trials <= 1) 0 else (1 - gam)*qnorm(1 - 1/trials) + gam*qnorm(1 - 1/(trials*exp(1)))
  pnorm((sr - z) * sqrt(nobs - 1)) }
DSR <- PERF[, .(arm, active_sr_ann = active_ir,
                dsr_trials1 = vapply(active_ir, function(s) dsr_fun(s, n, 1), 0),
                dsr_trials3 = vapply(active_ir, function(s) dsr_fun(s, n, 3), 0))]
print(DSR[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 4) else x)])

saveRDS(list(PRI = PRI, BAS = BAS, ADV = ADV, PERF = PERF, DSR = DSR, act = act,
             SCA = SCA, RES = RES, LIQ = LIQ, MATERIAL = MATERIAL, n = n),
        file.path(OUT, "p4_verdict.rds"))
cat("\n[saved] p4_verdict.rds\n")
