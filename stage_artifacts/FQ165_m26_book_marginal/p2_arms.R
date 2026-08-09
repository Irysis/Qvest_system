## ============================================================================
## FQ-165 P2 — 사전등록 3형태 + 통제 arm 실측. 설계는 preregistration.json 에 고정됨.
## 판정 = ΔIR(net_active_recon_v1) + paired NW3 t. arm 나열은 판정이 아니다.
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)
                  library(PerformanceAnalytics); library(xts)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
source("02_Infrastructure/contracts/required_effect_size.R")

P1 <- readRDS(file.path(OUT, "p1_base.rds"))
MO <- P1$MO; BASE <- P1$BASE; eval_dates <- P1$eval_dates; bmv <- P1$bmv
TOPN <- 20L; MINN <- 15L; LAM <- 1.5; UB <- 0.20; UBCR <- 0.10; BPS <- 0.0015
n_m <- length(MO)

## MO 에 lag1 M26 주입 (스트레스 arm 용). 정본 정렬은 base ymi = m26 ymi + 1 이므로
## lag1 = base ymi − 2 의 신호. P0d 실측 정렬을 한 칸 더 묵힌 것.
{ m26 <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_002/alpha_scores.parquet"))
  m26[, Date := as.Date(Date)]
  ymf <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
  m26[, ymi := ymf(Date)]
  for (k in seq_len(n_m)) {
    r <- m26[ymi == ymf(MO[[k]]$dd) - 2L & is.finite(M26_Revenue_Mom)]
    MO[[k]]$m26_lag1 <- setNames(r$M26_Revenue_Mom, r$Ticker)
  }
  cat(sprintf("[P2-0] lag1 M26 주입 완료 · 커버 중앙 %.3f\n",
    median(sapply(seq_len(n_m), function(k) mean(names(MO[[k]]$score) %in% names(MO[[k]]$m26_lag1))))))
}

.apply_tophi <- function(w_tilt, w_prev, phi, ub) {
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev)); wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  b <- phi/(1+phi)
  normalize_long_only(b*wp + (1-b)*w_tilt, lb = 0, ub = ub, target_sum = 1)
}
canon_w <- function(a, w_prev, ub) { wt <- linear_tilt_qd(a, lambda=LAM, lb=0, ub=ub)
  names(wt) <- names(a); .apply_tophi(wt, w_prev, 3, ub) }
dnot <- function(cur, prv) { u <- union(names(cur), names(prv))
  x <- setNames(rep(0,length(u)),u); x[names(cur)] <- cur
  y <- setNames(rep(0,length(u)),u); y[names(prv)] <- prv; sum(abs(x-y)) }
zcs <- function(v) { s <- sd(v, na.rm=TRUE); if (!is.finite(s)||s<1e-12) return(rep(0,length(v)))
  z <- (v - mean(v, na.rm=TRUE))/s; z[!is.finite(z)] <- 0; z }
elig_scores <- function(m) { sc <- m$score
  tk <- intersect(names(sc), m$elig); if (length(tk) < 5L) tk <- names(sc); sc[tk] }

run_arm <- function(select_fn, wgt_fn = function(a,wp,ub,m) canon_w(a,wp,ub)) {
  wp <- NULL; npv <- NULL
  gb <- nb <- go <- no <- tno <- numeric(n_m); nm <- integer(n_m); nchg <- integer(n_m)
  base_pick <- NULL
  for (k in seq_len(n_m)) {
    m <- MO[[k]]; ub <- if (identical(m$regime,"CRISIS")) UBCR else UB
    a <- select_fn(m); if (!length(a)) a <- { s <- elig_scores(m); s[order(-s)][seq_len(min(TOPN,length(s)))] }
    w <- wgt_fn(a, wp, ub, m)
    rv <- m$ret[names(w)]; rv[is.na(rv)] <- 0
    gb[k] <- sum(w*rv); nm[k] <- length(w)
    nb[k] <- gb[k] - BPS*(if (is.null(wp)) sum(abs(w)) else dnot(w, wp))
    nw <- w * m$inv; go[k] <- gb[k]*m$inv
    tno[k] <- (if (is.null(npv)) sum(abs(nw)) else dnot(nw, npv))
    no[k] <- go[k] - BPS*tno[k]
    wp <- w; npv <- nw
  }
  list(ret_net = no, ret_gross = go, bare_net = nb, turn = tno, n_names = nm)
}

nw_t <- function(x, L=3){ x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x-m; s <- sum(e^2)/n
  for (l in 1:L){ ga <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/(L+1))*ga }
  m/sqrt(s/n) }
IRf <- function(r) { a <- r - bmv; mean(a)/sd(a)*sqrt(12) }

summ <- function(A, label, type_lab) {
  x <- xts(A$ret_net, order.by = eval_dates)
  tab <- table.AnnualizedReturns(x, scale=12, Rf=0)
  act <- A$ret_net - bmv; act_b <- BASE$ret_net - bmv
  d <- A$ret_net - BASE$ret_net
  data.table(arm = label, intervention_type = type_lab,
    IR = IRf(A$ret_net), IR_base = IRf(BASE$ret_net),
    delta_IR = IRf(A$ret_net) - IRf(BASE$ret_net),
    paired_mean_monthly = mean(d), paired_ann_pct = mean(d)*12*100,
    paired_t_nw3 = nw_t(d), paired_t_iid = mean(d)/(sd(d)/sqrt(length(d))),
    paired_sd = sd(d),
    SR_geo = as.numeric(tab[3,1]), CAGR = as.numeric(tab[1,1]),
    MDD = as.numeric(maxDrawdown(x)),
    Calmar = as.numeric(tab[1,1])/as.numeric(maxDrawdown(x)),
    TE = sd(act)*sqrt(12), turnover_ann = mean(A$turn)*12,
    cor_active_vs_base = cor(act, act_b), n_names_mean = mean(A$n_names))
}

## ── 형태 A: rerank z-blend w=0.30 ────────────────────────────────────────────
sel_blend <- function(w_m26, m26_get = function(m) m$m26) function(m) {
  sc <- elig_scores(m); tk <- names(sc)
  mv <- m26_get(m)[tk]
  b <- zcs(sc) + w_m26 * zcs(mv); names(b) <- tk
  o <- order(-b); b[o][seq_len(min(TOPN, length(o)))]
}
## ── 형태 B: filter — M26 하위 1분위 제외 ─────────────────────────────────────
sel_filterD1 <- function(m) {
  sc <- elig_scores(m); tk <- names(sc); mv <- m$m26[tk]
  ok <- rep(TRUE, length(tk)); names(ok) <- tk
  fin <- is.finite(mv)
  if (sum(fin) >= 20) { thr <- quantile(mv[fin], 0.10, na.rm=TRUE, names=FALSE)
                        ok[fin & mv <= thr] <- FALSE }
  sc2 <- sc[ok]
  N <- min(TOPN, length(sc2)); if (N < MINN && length(sc2) >= MINN) N <- MINN
  sc2[order(-sc2)][seq_len(N)]
}
## ── 형태 C: slot-carve k=4 ───────────────────────────────────────────────────
sel_carve <- function(m) {           # 선별만 반환, 가중은 wgt_carve 가 담당
  sc <- elig_scores(m); tk <- names(sc); mv <- m$m26[tk]
  base16 <- names(sort(sc, decreasing=TRUE))[seq_len(min(16L, length(sc)))]
  rest <- setdiff(tk, base16); mvr <- mv[rest]; mvr <- mvr[is.finite(mvr)]
  carve <- if (length(mvr)) names(sort(mvr, decreasing=TRUE))[seq_len(min(4L, length(mvr)))] else character(0)
  c(sc[base16], setNames(rep(NA_real_, length(carve)), carve))   # NA = carve 표식
}
wgt_carve <- function(a, wp, ub, m) {
  is_carve <- is.na(a); b16 <- a[!is_carve]; cv <- names(a)[is_carve]
  wt <- linear_tilt_qd(b16, lambda=LAM, lb=0, ub=ub); names(wt) <- names(b16)
  if (length(cv)) { wt <- wt * 0.80; wt <- c(wt, setNames(rep(0.20/length(cv), length(cv)), cv)) }
  .apply_tophi(wt, wp, 3, ub)
}

cat("=== [P2] arm 실행 ===\n")
A_A <- run_arm(sel_blend(0.30))
A_B <- run_arm(sel_filterD1)
A_C <- run_arm(sel_carve, wgt_carve)
A_L <- run_arm(sel_blend(0.30, function(m) m$m26_lag1))

## placebo 12 seed
set.seed(20260809)
PL <- lapply(1:12, function(s) run_arm(sel_blend(0.30, function(m) {
  v <- m$m26; if (!length(v)) return(setNames(numeric(0), character(0)))
  setNames(sample(unname(v)), names(v)) })))

RES <- rbindlist(list(
  summ(BASE, "BASE_incumbent", "base"),
  summ(A_A, "F_A_blend030", "rerank"),
  summ(A_B, "F_B_filterD1", "filter"),
  summ(A_C, "F_C_carve4",   "slot_carve"),
  summ(A_L, "F_A_lag1",     "rerank_stress"),
  rbindlist(lapply(seq_along(PL), function(i) summ(PL[[i]], sprintf("F_P_placebo_s%02d", i), "placebo")))
))
plc_rows <- RES[intervention_type == "placebo"]
RES_PL <- data.table(arm = "F_P_placebo030_MEDIAN", intervention_type = "placebo_summary",
  IR = median(plc_rows$IR), IR_base = RES[arm=="BASE_incumbent"]$IR,
  delta_IR = median(plc_rows$delta_IR),
  paired_mean_monthly = median(plc_rows$paired_mean_monthly),
  paired_ann_pct = median(plc_rows$paired_ann_pct),
  paired_t_nw3 = median(plc_rows$paired_t_nw3), paired_t_iid = median(plc_rows$paired_t_iid),
  paired_sd = median(plc_rows$paired_sd),
  SR_geo = median(plc_rows$SR_geo), CAGR = median(plc_rows$CAGR), MDD = median(plc_rows$MDD),
  Calmar = median(plc_rows$Calmar), TE = median(plc_rows$TE),
  turnover_ann = median(plc_rows$turnover_ann),
  cor_active_vs_base = median(plc_rows$cor_active_vs_base),
  n_names_mean = median(plc_rows$n_names_mean))
RES <- rbind(RES, RES_PL)

main <- RES[arm %in% c("BASE_incumbent","F_A_blend030","F_B_filterD1","F_C_carve4",
                       "F_A_lag1","F_P_placebo030_MEDIAN")]
cat("\n===== 주요 arm (ΔIR = IR − IR_base, net_active_recon_v1) =====\n")
print(main[, .(arm, intervention_type, IR = round(IR,4), delta_IR = round(delta_IR,4),
               paired_ann_pct = round(paired_ann_pct,3), paired_t_nw3 = round(paired_t_nw3,3),
               SR_geo = round(SR_geo,3), MDD = round(MDD,4), Calmar = round(Calmar,3),
               TO = round(turnover_ann,2), cor_act = round(cor_active_vs_base,4))])
cat("\n[placebo 12 draw 분포] ΔIR 중앙 %.4f · 범위 [%.4f, %.4f] · paired 연효과 중앙 %+.3f%%\n" |>
    sprintf(median(plc_rows$delta_IR), min(plc_rows$delta_IR), max(plc_rows$delta_IR),
            median(plc_rows$paired_ann_pct)))

## ── 실제 vs placebo 직접 대조 (정보 유무의 올바른 대조군) ────────────────────
pl_mat <- sapply(PL, function(A) A$ret_net)
pl_med <- apply(pl_mat, 1, median)
d_vs_pl <- A_A$ret_net - pl_med
cat(sprintf("\n[정보 대조] F_A(실제 M26) − placebo 중앙계열 : 연 %+.3f%% · NW3 t %+.3f · ΔIR %+.4f\n",
            mean(d_vs_pl)*12*100, nw_t(d_vs_pl), IRf(A_A$ret_net) - IRf(pl_med)))

## ── ACF 확인 (겹침 없음 실증) ────────────────────────────────────────────────
acf_d <- acf(A_A$ret_net - BASE$ret_net, plot = FALSE, lag.max = 4)$acf[2:5]
cat(sprintf("[ACF] paired 차이 계열 r1..r4 = %s  → 비중첩 월간, lag-3 적정\n",
            paste(sprintf("%+.3f", acf_d), collapse = " ")))

## ── 검정력 판정 ──────────────────────────────────────────────────────────────
pw <- rbindlist(lapply(c("F_A_blend030","F_B_filterD1","F_C_carve4","F_A_lag1"), function(nmx) {
  r <- RES[arm == nmx]
  v <- verdict_with_power(observed_t = r$paired_t_nw3, observed_monthly = r$paired_mean_monthly,
                          n = n_m, t_threshold = 2.0, sd_monthly = P1$placebo_sd)
  data.table(arm = nmx, observed_ann_pct = r$paired_ann_pct, observed_t = r$paired_t_nw3,
             required_ann_pct = v$required$required_annual*100,
             implied_t_threshold = v$implied_t_threshold, verdict = v$verdict)
}))
cat("\n===== 검정력 판정 (외부기준 = placebo sd, arm 자신 sd 아님) =====\n"); print(pw)

## ── w-curve (declared diagnostic_no_argmax) ─────────────────────────────────
WC <- rbindlist(lapply(c(0.10,0.20,0.30,0.50,1.00), function(w) {
  A <- run_arm(sel_blend(w)); s <- summ(A, sprintf("wcurve_%.2f", w), "diagnostic")
  s[, w := w][] }))
cat("\n===== w-curve (diagnostic_no_argmax — 챔피언 승격 금지) =====\n")
print(WC[, .(w, IR = round(IR,4), delta_IR = round(delta_IR,4),
             paired_ann_pct = round(paired_ann_pct,3), paired_t_nw3 = round(paired_t_nw3,3),
             SR_geo = round(SR_geo,3), MDD = round(MDD,4), TO = round(turnover_ann,2))])

## ── 개입 규모 기술통계 ───────────────────────────────────────────────────────
chg <- sapply(seq_len(n_m), function(k) {
  m <- MO[[k]]
  b <- names(sel_base_pick <- { s <- elig_scores(m); n <- min(TOPN,length(s)); s[order(-s)][seq_len(n)] })
  a <- names(sel_blend(0.30)(m)); f <- names(sel_filterD1(m)); cc <- names(sel_carve(m))
  c(A = length(setdiff(a,b)), B = length(setdiff(b,f)), C = length(setdiff(cc,b)))
})
cat(sprintf("\n[개입 규모] 월평균 교체 종목수 — F_A %.2f / 20 · F_B(제외되어 빠진 base 종목) %.2f · F_C %.2f\n",
            mean(chg["A",]), mean(chg["B",]), mean(chg["C",])))

fwrite(RES, file.path(OUT, "p2_arms.csv"))
fwrite(WC,  file.path(OUT, "p2_wcurve.csv"))
fwrite(pw,  file.path(OUT, "p2_power.csv"))
saveRDS(list(RES=RES, WC=WC, pw=pw, A_A=A_A, A_B=A_B, A_C=A_C, A_L=A_L, PL=PL,
             pl_med=pl_med, d_vs_pl=d_vs_pl, acf=acf_d, chg=chg),
        file.path(OUT, "p2_arms.rds"))
cat("\n[saved] p2_arms.csv / p2_wcurve.csv / p2_power.csv / p2_arms.rds\n")
