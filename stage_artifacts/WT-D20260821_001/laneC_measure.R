## Lane C 성과 측정 + ML 대응 arm 대비 짝지은 검정 + F1~F3 기전 관측
## (WT_D20260821_001_LANEC)
##
## 사전등록 = stage_artifacts/WT-D20260821_001/PREREG_WT_D20260821_001.md
##   §3 basis(월간 total net) · §4 P1(paired NW3 t ±2.0 + 검정력 자격) · §5 P2(서열 ρ ≥ +0.5)
##   §6 F1(J̄_T − J̄_M ≥ +0.05 ∧ NW3 t ≥ +2.0) · F2(3쌍 |t| < 2.0) · F3(부호 일치 ∧ |Δρ| ≤ 0.25)
##   §7 (c) 국면 연속 상호작용 · §8 chain(DSR 진단)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260821_001/laneC_measure.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/essence_score.R")        # .essence_dsr (진단 DSR)
source("02_Infrastructure/contracts/required_effect_size.R") # required_effect / verdict_with_power

OUT  <- "stage_artifacts/WT-D20260821_001"
LANE <- "stage_artifacts/fq233_probe0_20260813"

## ── 입력: Lane A 프레임 자구 승계 (armA/armB/armC_measure.R 와 동일 경로) ─────────
inp <- readRDS(file.path(LANE, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                         Ret_1m = as.numeric(Ret_1m))]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(returns_dt[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
stopifnot(nrow(bench_dt) >= 0.95 * uniqueN(returns_dt$Date))

scL <- as.data.table(read_parquet(file.path(OUT, "laneC_scores.parquet")))[, Date := as.Date(Date)]
scA <- as.data.table(read_parquet(file.path(LANE, "armA_scores.parquet")))[, Date := as.Date(Date)]
scB <- as.data.table(read_parquet(file.path(LANE, "armB_scores.parquet")))[, Date := as.Date(Date)]
cat(sprintf("선형 스코어 %d행 · %d개월 (%s ~ %s)\n", nrow(scL), uniqueN(scL$Date),
            min(scL$Date), max(scL$Date)))

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }

run_one <- function(dt, col, tag) {
  s <- dt[, .(Date, Ticker = as.character(Ticker), score = as.numeric(get(col)))]
  r <- canonical_screen_bt(scores_dt = s, returns_dt = returns_dt, bench_dt = bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           strategy_id = paste0("LANEC_", tag), run_id = "WT_D20260821_001_LANEC")
  pr <- as.data.table(r$period_returns)
  px <- xts(pr$ret_net, order.by = as.Date(pr$date))
  list(tag = tag, res = r, pr = pr,
       sr_total = as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE)),
       cagr = as.numeric(Return.annualized(px, scale = 12, geometric = TRUE)),
       mdd  = as.numeric(maxDrawdown(px)),
       calmar = as.numeric(CalmarRatio(px, scale = 12)))
}

## ── 프레임 parity 검증: 내 측정 배관이 arm A 기록치를 재현하는가 ────────────────
##   (프레임 발명·드리프트의 유일한 직접 검사. 재현 실패 시 대조 전체가 무효)
##
## ★2026-08-22 재개 시 실측된 사실 — 벤치 캐시 vintage 이동 (measurement-graduation §7):
##   `.cache/benchmark.parquet` 가 08-22 00:03 재생성됐다(arm A 측정은 08-13). 실측 대조:
##     - ret_net(포트 자체 순수익) 198개월 **max|diff| = 0.000e+00 (비트 동일)**
##     - benchmark_ret 은 **단 1개월(2026-08, 진행 중 미완결 월)** 만 0.02717 → 0.04723
##   그 한 달의 일별 값이 **개정**돼 절단으로 08-13 vintage 재구성 불가(08-13 종가 컷 0.02334 ·
##   08-18 컷 0.03362 — 목표 0.02717 이 사이에 없다. 즉 연장이 아니라 개정).
## ⇒ parity 의 hard 축을 **사전등록 §3 이 1급으로 못박은 ret_net 계열의 비트 동일성**으로 둔다.
##   이는 완화가 아니라 **강화**다(스칼라 2개 tol 1e-6 → 198개월 전 계열 정확 일치).
##   벤치 의존 스칼라(PORT_t/active IR)는 vintage 표기와 함께 **진단으로 보고**하고 중단 축에서 뺀다.
##   근거: P1·P2·F1·F2·F3 는 전부 ret_net 또는 보유집합만 읽는다 — 벤치 vintage 에 불변.
Apar  <- run_one(scA, "score", "PARITY_armA")
A_rec <- readRDS(file.path(LANE, "armA_canonical_result.rds"))
.pm <- merge(as.data.table(Apar$res$period_returns)[, .(date = as.Date(date),
               ret_mine = ret_net, bm_mine = benchmark_ret)],
             as.data.table(A_rec$period_returns)[, .(date = as.Date(date),
               ret_rec = ret_net, bm_rec = benchmark_ret)], by = "date")
par_ret_maxdiff <- max(abs(.pm$ret_mine - .pm$ret_rec))
par_bm_ndiff    <- sum(abs(.pm$bm_mine - .pm$bm_rec) > 1e-12)
par_bm_months   <- as.character(.pm[abs(bm_mine - bm_rec) > 1e-12]$date)
par_nm <- c(mine = as.numeric(Apar$res$n_months), rec = as.numeric(A_rec$n_months))
parity_ok <- (par_ret_maxdiff == 0) && (nrow(.pm) == par_nm[["rec"]]) &&
             (par_nm[["mine"]] == par_nm[["rec"]])
par_pt <- c(mine = as.numeric(Apar$res$portfolio_alpha_t_nw_lag3),
            rec  = as.numeric(A_rec$portfolio_alpha_t_nw_lag3))
par_ir <- c(mine = as.numeric(Apar$res$net_sr), rec = as.numeric(A_rec$net_sr))
cat(sprintf("[frame parity] armA 재측정 vs 기록치 — ★ret_net max|diff| %.3e (%d개월 정합) → %s\n",
            par_ret_maxdiff, nrow(.pm), ifelse(parity_ok, "PARITY_OK(비트 동일)", "★PARITY_FAIL")))
cat(sprintf("   [진단·중단축 아님] 벤치 vintage 상이 월 %d개 (%s) → PORT_t %.6f/%.6f · active IR %.6f/%.6f\n",
            par_bm_ndiff, paste(par_bm_months, collapse = ","),
            par_pt[["mine"]], par_pt[["rec"]], par_ir[["mine"]], par_ir[["rec"]]))
if (!parity_ok) stop("frame parity 실패 — ret_net 계열이 Lane A 와 다르다. 측정 중단.")

cat("\n=== 선형 3-arm (사전등록 §2) ===\n")
LIN <- list(L_mean = run_one(scL, "s_mean", "L_mean"),
            L_q50  = run_one(scL, "s_q50",  "L_q50"),
            L_q90  = run_one(scL, "s_q90",  "L_q90"))
for (a in LIN) cat(sprintf("  %-7s total SR %+.4f · PORT_t %+.4f (p %.4f) · active IR %+.4f · CAGR %.2f%% · MDD %.2f%% · Calmar %.4f · TO %.2f · n=%d\n",
  a$tag, a$sr_total, as.numeric(a$res$portfolio_alpha_t_nw_lag3),
  as.numeric(a$res$portfolio_alpha_t_pvalue), as.numeric(a$res$net_sr),
  100*a$cagr, 100*a$mdd, a$calmar, as.numeric(a$res$turnover_annual),
  as.numeric(a$res$n_months)))
.exp_m <- uniqueN(scL$Date)
for (a in LIN) if (as.numeric(a$res$n_months) < 0.95 * .exp_m)
  warning(sprintf("★%s 백테 기간 손실 %d/%d — 축 조사 필요", a$tag, a$res$n_months, .exp_m), call. = FALSE)
cat(sprintf("  기간 대조: 스코어 %d개월 → 백테 %s개월\n", .exp_m, LIN$L_mean$res$n_months))

## ── ML 기록치 (재학습 없음 — challenge_flags 7항) ────────────────────────────────
A  <- readRDS(file.path(LANE, "armA_canonical_result.rds"))
Bf <- readRDS(file.path(LANE, "armB_full.rds"))
tagsB <- vapply(Bf$S, function(x) x$tag, "")
ML <- list(
  ML_mean = list(tag = "ML_mean", pr = as.data.table(A$period_returns)[, .(date = as.Date(date), ret_net)],
                 sr_total = NA_real_, port_t = as.numeric(A$portfolio_alpha_t_nw_lag3)),
  ML_q50  = list(tag = "ML_q50",  pr = as.data.table(Bf$B$pr)[, .(date = as.Date(date), ret_net)],
                 sr_total = NA_real_, port_t = NA_real_),
  ML_q90  = list(tag = "ML_q90",  pr = as.data.table(Bf$S[[which(tagsB == "q90")]]$pr)[, .(date = as.Date(date), ret_net)],
                 sr_total = NA_real_, port_t = NA_real_))
for (nm in names(ML)) {
  px <- xts(ML[[nm]]$pr$ret_net, order.by = ML[[nm]]$pr$date)
  ML[[nm]]$sr_total <- as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE))
  ML[[nm]]$mdd <- as.numeric(maxDrawdown(px))
}
cat("\n[ML 기록치 재확인] ")
cat(sprintf("mean SR %.4f · q50 SR %.4f · q90 SR %.4f\n",
            ML$ML_mean$sr_total, ML$ML_q50$sr_total, ML$ML_q90$sr_total))

## ── ML arm 을 **현 vintage** 로 재측정 (벤치 vintage 혼용 제거) ────────────────────
##   P1/P2/F1/F2/F3 는 위 기록치 ret_net 을 그대로 쓴다(사전등록 §3 — 재학습 없음).
##   여기서 만드는 건 **벤치 의존 스칼라 전용**: 8-arm 표의 PORT_t 가 선형 arm(현 vintage)과
##   ML arm(08-13 vintage)을 말없이 섞지 않게 하려는 것. 동시에 ret_net 비트 동일성도 재확인한다.
scC <- as.data.table(read_parquet(file.path(LANE, "armC_scores.parquet")))[, Date := as.Date(Date)]
ML_CUR_SPEC <- list(ML_q10 = list(scB, "q10"), ML_q50 = list(scB, "q50"),
                    ML_mean = list(scA, "score"), ML_q90 = list(scB, "q90"),
                    ML_tailprob = list(scC, "score"))
ML_CUR <- lapply(names(ML_CUR_SPEC), function(nm)
  run_one(ML_CUR_SPEC[[nm]][[1]], ML_CUR_SPEC[[nm]][[2]], paste0("CURVINT_", nm)))
names(ML_CUR) <- names(ML_CUR_SPEC)
cat("\n[ML 현-vintage 재측정 · ret_net 기록치 대조]\n")
ml_retnet_parity <- list()
for (nm in names(ML)) {
  jj <- merge(as.data.table(ML_CUR[[nm]]$pr)[, .(date = as.Date(date), a = ret_net)],
              ML[[nm]]$pr[, .(date = as.Date(date), b = ret_net)], by = "date")
  md <- max(abs(jj$a - jj$b))
  ml_retnet_parity[[nm]] <- list(n_months = nrow(jj), ret_net_max_abs_diff = md,
                                 bit_identical = (md == 0))
  cat(sprintf("  %-11s ret_net max|diff| %.3e (n=%d) → %s · PORT_t(현) %+.4f\n", nm, md, nrow(jj),
              ifelse(md == 0, "비트 동일", "★상이"),
              as.numeric(ML_CUR[[nm]]$res$portfolio_alpha_t_nw_lag3)))
}
stopifnot(all(vapply(ml_retnet_parity, function(x) isTRUE(x$bit_identical), TRUE)))

## ── §4 P1: 동일-표적 3쌍 paired NW3 t (d = ML − linear) + 검정력 자격 ────────────
cat("\n=== §4 P1 — 동일-표적 paired 검정 (d = ML − linear, NW lag-3) ===\n")
PAIRS <- list(c("mean","ML_mean","L_mean"), c("q50","ML_q50","L_q50"), c("q90","ML_q90","L_q90"))
p1 <- list()
for (pp in PAIRS) {
  key <- pp[1]; mlk <- pp[2]; lnk <- pp[3]
  j <- merge(ML[[mlk]]$pr[, .(date, m = ret_net)], LIN[[lnk]]$pr[, .(date = as.Date(date), l = ret_net)],
             by = "date")
  stopifnot(nrow(j) >= 0.95 * min(nrow(ML[[mlk]]$pr), nrow(LIN[[lnk]]$pr)))
  d <- j$m - j$l
  tt <- nw_t(d)
  ## 검정력 — (i) 계열 자신의 sd(해상도) (ii) 외부 기준 sd(계약 기본 = 무작위 top-25 EW 쌍 실측)
  own <- required_effect(n = length(d), t_threshold = 2.0, sd_monthly = stats::sd(d),
                         design = "full", series = d)
  ext <- required_effect(n = length(d), t_threshold = 2.0, design = "full", series = d)
  vw  <- verdict_with_power(observed_t = tt, observed_monthly = mean(d), n = length(d),
                            t_threshold = 2.0, sd_monthly = stats::sd(d), series = d)
  lab <- if (abs(tt) >= 2.0) (if (tt > 0) "CAPACITY_EFFECT_ML_SUPERIOR" else "LINEAR_SUPERIOR_GBM_OVERFIT")
         else if (abs(mean(d)*12) < own$required_annual) "UNDERPOWERED_미결" else "POWERED_NULL_종결"
  p1[[key]] <- list(pair = key, n_months = nrow(j), mean_diff_monthly = mean(d),
    mean_diff_ann_pct = 100*12*mean(d), nw3_t = tt, threshold = 2.0, label = lab,
    mde_own_sd_ann_pct = 100*own$required_annual, sd_monthly_paired = stats::sd(d),
    mde_ext_ref_ann_pct = 100*ext$required_annual, ext_ref_sd_monthly = SPREAD_SD_MONTHLY_25EW,
    nw_inflation = own$nw_inflation, nw_inflation_source = own$nw_inflation_source,
    power_contract_verdict = vw$verdict, implied_t_threshold = vw$implied_t_threshold,
    bar_restates_t = vw$bar_restates_t, d = d, dates = j$date)
  cat(sprintf("  %-4s n=%d · 월평균 %+.4f%%p · 연환산 %+.2f%%p · NW3 t %+.4f → %s\n",
              key, nrow(j), 100*mean(d), 100*12*mean(d), tt, lab))
  cat(sprintf("        MDE(계열 sd %.4f) 연 %.2f%%p · MDE(외부 기준 sd %.4f) 연 %.2f%%p · nw %.3f(%s) · 계약판정 %s (implied_t %.2f)\n",
              stats::sd(d), 100*own$required_annual, SPREAD_SD_MONTHLY_25EW,
              100*ext$required_annual, own$nw_inflation, own$nw_inflation_source,
              vw$verdict, vw$implied_t_threshold))
}
p1_all_inside <- all(vapply(p1, function(x) abs(x$nw3_t) < 2.0, TRUE))
p1_all_powered <- all(vapply(p1, function(x) x$label == "POWERED_NULL_종결", TRUE))
p1_verdict <- (if (!p1_all_inside) "P1_REJECTED"
               else if (p1_all_powered) "P1_SUPPORTED_POWERED"
               else "P1_INSIDE_BAND_BUT_UNDERPOWERED")
cat(sprintf("\n★§4 P1 판정: %s\n", p1_verdict))

## ── §5 P2: 표적 서열 concordance ────────────────────────────────────────────────
sr_lin <- c(mean = LIN$L_mean$sr_total, q50 = LIN$L_q50$sr_total, q90 = LIN$L_q90$sr_total)
sr_ml  <- c(mean = ML$ML_mean$sr_total, q50 = ML$ML_q50$sr_total, q90 = ML$ML_q90$sr_total)
rho_p2 <- stats::cor(rank(sr_lin), rank(sr_ml), method = "spearman")
p2_pass <- is.finite(rho_p2) && rho_p2 >= 0.5
cat(sprintf("\n=== §5 P2 — 서열 concordance ===\n  선형 SR: mean %.4f · q50 %.4f · q90 %.4f  → 서열 %s\n",
            sr_lin["mean"], sr_lin["q50"], sr_lin["q90"],
            paste(names(sort(sr_lin, decreasing = TRUE)), collapse = " > ")))
cat(sprintf("  ML  SR: mean %.4f · q50 %.4f · q90 %.4f  → 서열 %s\n",
            sr_ml["mean"], sr_ml["q50"], sr_ml["q90"],
            paste(names(sort(sr_ml, decreasing = TRUE)), collapse = " > ")))
cat(sprintf("  Spearman ρ = %+.2f (문턱 +0.5) → %s   ⚠n=3 · arm 비독립 — 관찰이지 검정 아님\n",
            rho_p2, ifelse(p2_pass, "PASS", "FAIL")))

## ── 보유집합 재구성 (계약과 **동일 규칙**) + 동률 검사 ───────────────────────────
pick_top <- function(dt, col, top_n = 25L) {
  S <- dt[, .(Date, Ticker = as.character(Ticker), score = as.numeric(get(col)))][!is.na(score)]
  setorder(S, Date, -score)
  S[, { n <- min(top_n, .N); .(Ticker = Ticker[seq_len(n)]) }, by = Date]
}
tie_check <- function(dt, col, top_n = 25L) {
  S <- dt[, .(Date, score = as.numeric(get(col)))][!is.na(score)]
  setorder(S, Date, -score)
  S[, .(tie = { n <- min(top_n, .N); if (.N > n) isTRUE(all.equal(score[n], score[n+1L])) else FALSE }), by = Date][, sum(tie)]
}
HOLD <- list(ML_mean = pick_top(scA, "score"), ML_q50 = pick_top(scB, "q50"),
             ML_q90  = pick_top(scB, "q90"),   L_mean = pick_top(scL, "s_mean"),
             L_q50   = pick_top(scL, "s_q50"), L_q90  = pick_top(scL, "s_q90"))
ties <- c(ML_mean = tie_check(scA, "score"), ML_q50 = tie_check(scB, "q50"),
          ML_q90 = tie_check(scB, "q90"), L_mean = tie_check(scL, "s_mean"),
          L_q50 = tie_check(scL, "s_q50"), L_q90 = tie_check(scL, "s_q90"))
cat(sprintf("\n[보유집합 재구성] 25/26위 동률 발생 월 = %s (0 이면 선택 결정적 — 계약 규칙과 동일 코드)\n",
            paste(sprintf("%s:%d", names(ties), ties), collapse = " · ")))
common_dates <- Reduce(intersect, lapply(HOLD, function(h) as.character(unique(h$Date))))
common_dates <- sort(as.Date(common_dates))
## ★2026-08-22 실측 결함 수리 — `r33_inputs.rds$frd` 의 마지막 앵커월 2026-09-01 은
##   347종 전부 Ret_1m == 0 (sd 0 · n_distinct 1) 인 **합성 패딩 월**이다. 계약
##   canonical_screen_bt 는 이 달을 이미 제외해 백테가 198개월인데, F1/F2 는 199개월을 써서
##   전 arm 에 hit=0 인 가짜 달을 하나씩 먹였다. ⇒ **측정 창을 백테 198개월로 통일**한다.
##   (사전등록 §1 "대조 구간 = 198개월" 에 오히려 정합. 영향은 4번째 소수점 — §결과에 실측 병기.)
bt_dates <- sort(as.Date(LIN$L_mean$pr$date))
pad_dropped <- setdiff(as.character(common_dates), as.character(bt_dates))
common_dates <- common_dates[as.character(common_dates) %in% as.character(bt_dates)]
cat(sprintf("  6 arm 공통 보유월 %d (합성 패딩월 제외: %s)\n", length(common_dates),
            ifelse(length(pad_dropped), paste(pad_dropped, collapse = ","), "없음")))

## ── §6 F1: Jaccard 군집 ─────────────────────────────────────────────────────────
jac <- function(a, b) { u <- length(union(a, b)); if (u == 0) NA_real_ else length(intersect(a, b))/u }
hl <- lapply(HOLD, function(h) split(h$Ticker, as.character(h$Date)))
T_PAIRS <- list(c("ML_mean","L_mean"), c("ML_q50","L_q50"), c("ML_q90","L_q90"))
M_PAIRS <- list(c("ML_mean","ML_q50"), c("ML_mean","ML_q90"), c("ML_q50","ML_q90"),
                c("L_mean","L_q50"),   c("L_mean","L_q90"),   c("L_q50","L_q90"))
jseries <- function(pairs) sapply(as.character(common_dates), function(dd)
  mean(vapply(pairs, function(p) jac(hl[[p[1]]][[dd]], hl[[p[2]]][[dd]]), 0.0)))
jT <- jseries(T_PAIRS); jM <- jseries(M_PAIRS); dJ <- jT - jM
f1_gap <- mean(jT) - mean(jM); f1_t <- nw_t(dJ)
f1_pass <- is.finite(f1_gap) && f1_gap >= 0.05 && is.finite(f1_t) && f1_t >= 2.0
per_pair <- c(sapply(T_PAIRS, function(p) mean(sapply(as.character(common_dates),
                function(dd) jac(hl[[p[1]]][[dd]], hl[[p[2]]][[dd]])))),
              sapply(M_PAIRS, function(p) mean(sapply(as.character(common_dates),
                function(dd) jac(hl[[p[1]]][[dd]], hl[[p[2]]][[dd]])))))
names(per_pair) <- c(sapply(T_PAIRS, paste, collapse = "~"), sapply(M_PAIRS, paste, collapse = "~"))
cat(sprintf("\n=== §6 F1 — 선택집합 Jaccard ===\n  J̄_T(동일표적·교차모델) %.4f · J̄_M(동일모델·교차표적) %.4f · 차 %+.4f (문턱 +0.05) · NW3 t %+.4f (문턱 +2.0) → %s\n",
            mean(jT), mean(jM), f1_gap, f1_t, ifelse(f1_pass, "PASS", "FAIL")))
print(round(per_pair, 4))

## ── §6 F2: tail-hit 등가 ────────────────────────────────────────────────────────
univ <- unique(scL[, .(Date, Ticker = as.character(Ticker))])[Date %in% bt_dates]  # 패딩월 제외
uret <- merge(univ, returns_dt, by = c("Date","Ticker"))
q90m <- uret[, .(q90 = stats::quantile(Ret_1m, 0.90, na.rm = TRUE, names = FALSE)), by = Date]
uret <- merge(uret, q90m, by = "Date")
hitrate <- function(h) {
  m <- merge(h, uret, by = c("Date","Ticker"))
  m[, .(hit = mean(Ret_1m > q90)), by = Date]
}
HR <- lapply(HOLD, hitrate)
cat("\n=== §6 F2 — 보유월 tail-hit rate (실현 > 월 횡단면 q90) ===\n")
for (nm in names(HR)) cat(sprintf("  %-8s 평균 hit %.4f (n=%d)\n", nm, mean(HR[[nm]]$hit), nrow(HR[[nm]])))
f2 <- list()
for (pp in PAIRS) {
  key <- pp[1]; mlk <- pp[2]; lnk <- pp[3]
  jj <- merge(HR[[mlk]][, .(Date, m = hit)], HR[[lnk]][, .(Date, l = hit)], by = "Date")
  dd <- jj$m - jj$l; tt <- nw_t(dd)
  req <- required_effect(n = length(dd), t_threshold = 2.0, sd_monthly = stats::sd(dd),
                         design = "full", series = dd)
  ## 사전등록 §6 F2 "MDE 병기 — 미결/종결 라벨 §4.1 규약 동일"
  lab2 <- if (abs(tt) >= 2.0) "NON_EQUIVALENT_ML_TAIL_EDGE"
          else if (abs(mean(dd)) < req$required_monthly) "UNDERPOWERED_미결" else "POWERED_NULL_종결"
  f2[[key]] <- list(pair = key, n_months = nrow(jj), mean_diff = mean(dd), nw3_t = tt,
                    mde_own_sd = req$required_monthly, sd_monthly = stats::sd(dd),
                    nw_inflation = req$nw_inflation, nw_inflation_source = req$nw_inflation_source,
                    equivalent = abs(tt) < 2.0, power_label = lab2)
  cat(sprintf("  paired %-4s Δhit %+.4f · NW3 t %+.4f → %s (MDE(계열 sd) %.4f) · %s\n",
              key, mean(dd), tt, ifelse(abs(tt) < 2.0, "등가", "★비등가"), req$required_monthly, lab2))
}
f2_pass <- all(vapply(f2, function(x) isTRUE(x$equivalent), TRUE))
cat(sprintf("  → F2 %s\n", ifelse(f2_pass, "PASS(등가)", "FAIL(비등가)")))

## ── §6 F3: 왜도-연결의 모델 불변성 ──────────────────────────────────────────────
skew_m <- uret[, .(skew = as.numeric(PerformanceAnalytics::skewness(Ret_1m))), by = Date]
gap_lin <- merge(LIN$L_q50$pr[, .(Date = as.Date(date), q = ret_net)],
                 LIN$L_mean$pr[, .(Date = as.Date(date), m = ret_net)], by = "Date")[, .(Date, gap = q - m)]
gap_ml  <- merge(ML$ML_q50$pr[, .(Date = date, q = ret_net)],
                 ML$ML_mean$pr[, .(Date = date, m = ret_net)], by = "Date")[, .(Date, gap = q - m)]
f3tab <- merge(merge(skew_m, gap_lin, by = "Date"), gap_ml, by = "Date", suffixes = c("_lin","_ml"))
rho_lin <- stats::cor(f3tab$skew, f3tab$gap_lin); rho_ml <- stats::cor(f3tab$skew, f3tab$gap_ml)
rs_lin <- stats::cor(f3tab$skew, f3tab$gap_lin, method = "spearman")
rs_ml  <- stats::cor(f3tab$skew, f3tab$gap_ml,  method = "spearman")
f3_pass <- is.finite(rho_lin) && is.finite(rho_ml) && sign(rho_lin) == sign(rho_ml) &&
           abs(rho_lin - rho_ml) <= 0.25
cat(sprintf("\n=== §6 F3 — 왜도 ↔ (q50−mean) gap 연결 ===\n  n=%d · rho_LIN %+.4f · rho_ML %+.4f · |Δ| %.4f (문턱 0.25) · 부호일치 %s → %s\n",
            nrow(f3tab), rho_lin, rho_ml, abs(rho_lin - rho_ml),
            sign(rho_lin) == sign(rho_ml), ifelse(f3_pass, "PASS", "FAIL")))
cat(sprintf("  (Spearman 병기: LIN %+.4f · ML %+.4f)\n", rs_lin, rs_ml))

## ── §7 (c) 국면 연속 상호작용 (E5_msm_crisis_prob · 이분 분할 금지) ─────────────
regime <- list(available = FALSE, note = "미산출")
msm_fp <- ".cache/msm_daily_latest.parquet"
if (file.exists(msm_fp)) {
  ms <- as.data.table(read_parquet(msm_fp))
  cn <- names(ms)
  dc <- cn[tolower(cn) %in% c("date")][1]; pc <- cn[grepl("crisis", cn, ignore.case = TRUE)][1]
  if (!is.na(dc) && !is.na(pc)) {
    ms <- ms[, .(Date = as.Date(get(dc)), cp = as.numeric(get(pc)))][is.finite(cp)]
    setorder(ms, Date)
    ## C5 — 보유월 **시작 직전** 마지막 일별 관측만
    rr <- lapply(p1, function(x) {
      z <- data.table(Date = x$dates, d = x$d)
      ## 보유월 시작(anchor) **직전** 마지막 일별 관측 — 인덱스 0(관측 이전)은 NA 로 떨군다
      ii <- findInterval(as.numeric(z$Date) - 1, as.numeric(ms$Date))
      z[, cp := ifelse(ii >= 1L, ms$cp[pmax(ii, 1L)], NA_real_)]
      z <- z[is.finite(cp)]
      if (nrow(z) < 24L) return(list(available = FALSE, note = "겹치는 월 <24"))
      z[, cpz := (cp - mean(cp))/stats::sd(cp)]
      fit <- stats::lm(d ~ cpz, data = z)
      s <- summary(fit)$coefficients
      list(available = TRUE, n = nrow(z), slope = unname(s["cpz","Estimate"]),
           slope_t = unname(s["cpz","t value"]), slope_p = unname(s["cpz","Pr(>|t|)"]),
           intercept = unname(s["(Intercept)","Estimate"]),
           cp_mean = mean(z$cp), cp_sd = stats::sd(z$cp))
    })
    regime <- list(available = TRUE, source = msm_fp, prob_col = pc,
                   cutoff = "보유월 시작 직전 마지막 일별 관측 (Date-1 findInterval) — C5 정합",
                   design = "연속 상호작용 회귀 d_t ~ z(crisis_prob) · 이분 분할 없음", by_pair = rr)
    cat("\n=== §7(c) 국면 연속 상호작용 (E5 crisis_prob) ===\n")
    for (nm in names(rr)) if (isTRUE(rr[[nm]]$available))
      cat(sprintf("  %-4s slope %+.5f · t %+.3f · p %.4f (n=%d)\n", nm,
                  rr[[nm]]$slope, rr[[nm]]$slope_t, rr[[nm]]$slope_p, rr[[nm]]$n))
  }
}

## ── §8 DSR 진단 (chain — 게이트 부적용) ─────────────────────────────────────────
dsr_of <- function(pr) {
  if (!all(c("ret_net","benchmark_ret") %in% names(pr))) return(NA_real_)
  act <- pr$ret_net - pr$benchmark_ret; act <- act[is.finite(act)]
  if (length(act) < 12 || stats::sd(act) <= 0) return(NA_real_)
  mu <- mean(act); s <- stats::sd(act)
  .essence_dsr(mu/s*sqrt(12), length(act), 1, mean(((act-mu)/s)^3), mean(((act-mu)/s)^4), A = 12)
}
dsr <- vapply(LIN, function(a) dsr_of(a$pr), 0.0)
cat(sprintf("\n[진단] DSR(n_trials=1, chain — 게이트 부적용): %s\n",
            paste(sprintf("%s %.4f", names(dsr), dsr), collapse = " · ")))

## ── 8-arm 서열표 (Lane A 5 + 선형 3) ────────────────────────────────────────────
metaA <- fromJSON(file.path(LANE, "armA_score_meta.json"))
metaB <- fromJSON(file.path(LANE, "armB_score_meta.json"))
metaL <- fromJSON(file.path(OUT,  "laneC_score_meta.json"))
armC  <- fromJSON(file.path(LANE, "armC_result.json"))
metaC <- fromJSON(file.path(LANE, "armC_score_meta.json"))
armB  <- fromJSON(file.path(LANE, "armB_result.json"))
tab <- data.table(
  arm = c("ML_q10","ML_q50","ML_mean","ML_q90","ML_tailprob","L_mean","L_q50","L_q90"),
  family = c(rep("ML(GBM)",5), rep("LINEAR",3)),
  rank_ic = c(metaB$diag$q10$rank_ic_mean, metaB$diag$q50$rank_ic_mean, metaA$diag_rank_ic_mean,
              metaB$diag$q90$rank_ic_mean, metaC$diag$score$rank_ic_mean,
              metaL$diag$s_mean$rank_ic_mean, metaL$diag$s_q50$rank_ic_mean, metaL$diag$s_q90$rank_ic_mean),
  ## total_sr = ret_net 기반(벤치 무관) — 기록치와 현 vintage 가 동일하다(위 비트 대조로 실증)
  total_sr = c(ML_CUR$ML_q10$sr_total, ML$ML_q50$sr_total,
               ML$ML_mean$sr_total, ML$ML_q90$sr_total, ML_CUR$ML_tailprob$sr_total,
               LIN$L_mean$sr_total, LIN$L_q50$sr_total, LIN$L_q90$sr_total),
  ## ★port_t = 벤치 의존 → **전 arm 현 vintage 단일 기준**(혼용 금지). 기록치는 아래 별도 열.
  port_t = c(as.numeric(ML_CUR$ML_q10$res$portfolio_alpha_t_nw_lag3),
             as.numeric(ML_CUR$ML_q50$res$portfolio_alpha_t_nw_lag3),
             as.numeric(ML_CUR$ML_mean$res$portfolio_alpha_t_nw_lag3),
             as.numeric(ML_CUR$ML_q90$res$portfolio_alpha_t_nw_lag3),
             as.numeric(ML_CUR$ML_tailprob$res$portfolio_alpha_t_nw_lag3),
             as.numeric(LIN$L_mean$res$portfolio_alpha_t_nw_lag3),
             as.numeric(LIN$L_q50$res$portfolio_alpha_t_nw_lag3),
             as.numeric(LIN$L_q90$res$portfolio_alpha_t_nw_lag3)),
  port_t_recorded = c(armB$secondary$port_t[armB$secondary$tag == "q10"],
             armB$primary_result$port_t, as.numeric(A$portfolio_alpha_t_nw_lag3),
             armB$secondary$port_t[armB$secondary$tag == "q90"], armC$primary_result$port_t,
             NA_real_, NA_real_, NA_real_))
setorder(tab, -rank_ic)
cat("\n=== 8-arm 서열표 (rank-IC 내림차순) ===\n"); print(tab)
rho8 <- stats::cor(rank(tab$rank_ic), rank(tab$total_sr), method = "spearman")
cat(sprintf("  rank-IC 순위 vs total SR 순위 Spearman = %+.4f (n=8 비독립 — 관찰이지 검정 아님)\n", rho8))

## ── 결과 JSON (수치 + 사전등록 규칙이 기계적으로 정하는 판정만. 서술은 alpha_package) ──
arm_block <- function(a) list(tag = a$tag, total_sr = a$sr_total,
  port_t = as.numeric(a$res$portfolio_alpha_t_nw_lag3),
  port_t_p = as.numeric(a$res$portfolio_alpha_t_pvalue),
  active_ir = as.numeric(a$res$net_sr), cagr = a$cagr, mdd = a$mdd, calmar = a$calmar,
  turnover = as.numeric(a$res$turnover_annual), n_months = as.numeric(a$res$n_months),
  alpha_annualized = as.numeric(a$res$alpha_annualized),
  selected_ret_coverage = as.numeric(a$res$selected_ret_coverage))

overall <- (if (p1_verdict == "P1_REJECTED") "HYPOTHESIS_REJECTED_CAPACITY_EFFECT"
            else if (!f1_pass) "PERF_EQUIVALENT_BUT_F1_VIOLATED__UNEXPLAINED_EQUIVALENCE"
            else if (p1_verdict == "P1_SUPPORTED_POWERED" && p2_pass)
              "SUPPORTED__TARGET_GEOMETRY_NEGATIVE_CONTROL_ESTABLISHED"
            else "PARTIAL__P1_INSIDE_BAND_UNDERPOWERED")

write_json(list(
  round_id = "WT_D20260821_001_LANEC", wt_id = "WT-D20260821_001", fq = "FQ-235 Lane C",
  prereg = "PREREG_WT_D20260821_001.md (측정 전 발행·고정)",
  measured_at = format(Sys.Date()),
  metric_type = "canonical_screen", selection_type = "chain",
  frame = list(universe = "K200∪KQ150", panel = "lane_a_feature_panel.parquet",
    n_features_input = 324, dropped_alias = 7,
    conditioning = metaL$conditioning, regularization = metaL$regularization,
    walkforward = "확장창·burn-in 60개월", top_n = 25, weighting = "EW long-only",
    cost_bps_oneway = 15, measurement = "canonical_screen_bt() · 벤치 apply.monthly+Return.cumulative",
    ml_side = "재학습 없음 — armA_canonical_result.rds / armB_full.rds 기록 계열",
    frame_parity = list(check = "armA 스코어를 본 배관으로 재측정해 기록치와 대조",
      hard_axis = "ret_net 198개월 계열의 비트 동일성 (사전등록 §3 의 1급 축)",
      ret_net_max_abs_diff = par_ret_maxdiff, ret_net_bit_identical = (par_ret_maxdiff == 0),
      n_months_mine = par_nm[["mine"]], n_months_recorded = par_nm[["rec"]],
      passed = parity_ok,
      port_t_mine = par_pt[["mine"]], port_t_recorded = par_pt[["rec"]],
      net_sr_mine = par_ir[["mine"]], net_sr_recorded = par_ir[["rec"]],
      ml_arms_ret_net_parity = ml_retnet_parity),
    benchmark_vintage_incident = list(
      detected_at = "2026-08-22 재개 시 frame parity 가 검출",
      file = ".cache/benchmark.parquet", regenerated_mtime = "2026-08-22 00:03",
      arm_a_measured = "2026-08-13 16:16",
      effect = "benchmark_ret 이 198개월 중 **1개월(2026-08, 진행 중 미완결 월)** 만 상이 (0.0271683 → 0.0472292)",
      port_ret_net_effect = "없음 — ret_net 198개월 max|diff| = 0 (비트 동일). armA/armB/armC 전 arm 확인",
      reconstruction = paste("08-13 vintage 는 절단으로 재구성 불가 — 일별 값이 개정됨",
                             "(08-13 종가 컷 0.0233376 · 08-18 컷 0.0336164, 목표 0.0271683 이 사이에 없음).",
                             "∴ 조작된 vintage 를 지어내지 않고 현 vintage 로 전 arm 을 통일 측정했다."),
      decision_axis_immunity = paste("P1(ret_net paired) · P2(ret_net SR) · F1(보유집합) ·",
                             "F2(실현수익) · F3(ret_net gap) 전부 벤치를 읽지 않는다 ⇒ 판정 축 불변."),
      affected_reported_quantities = "PORT_t · active IR · alpha_annualized · DSR (전부 현 vintage 단일 기준으로 재측정·표기)",
      rule_ref = "measurement-graduation §7 Vintage Pinning / [[project-cache-vintage-pinning]]")),
  linear_arms = lapply(LIN, arm_block),
  linear_diag_rank_ic = metaL$diag,
  ml_reference = lapply(ML, function(x) list(tag = x$tag, total_sr = x$sr_total, mdd = x$mdd,
                                             n_months = nrow(x$pr))),
  P1 = list(verdict = p1_verdict, rule = "d = ML − linear · NW lag-3 t · 문턱 ±2.0 · 3쌍 전부",
            pairs = lapply(p1, function(x) x[setdiff(names(x), c("d","dates"))])),
  P2 = list(pass = p2_pass, rho_spearman = rho_p2, threshold = 0.5,
            sr_linear = as.list(sr_lin), sr_ml = as.list(sr_ml),
            caution = "n=3 · arm 비독립 · 사후 서열의 재현 검사(신규 예측 아님) — secondary"),
  F1 = list(pass = f1_pass, j_bar_T = mean(jT), j_bar_M = mean(jM), gap = f1_gap,
            gap_threshold = 0.05, nw3_t = f1_t, t_threshold = 2.0,
            n_months = length(common_dates), per_pair_mean = as.list(per_pair),
            rule = "T=동일표적·교차모델 3쌍 / M=동일모델·교차표적 6쌍",
            tie_months = as.list(ties)),
  F2 = list(pass = f2_pass, mean_hit = as.list(sapply(HR, function(h) mean(h$hit))),
            pairs = f2,
            all_underpowered = all(vapply(f2, function(x) x$power_label == "UNDERPOWERED_미결", TRUE)),
            note = "등가 판정은 |t|<2.0 (사전등록). power_label 은 그 등가가 '종결'인지 '미결'인지 분리."),
  measurement_window_fix = list(
    issue = "r33_inputs.rds$frd 의 마지막 앵커월 2026-09-01 은 347종 전부 Ret_1m==0 인 합성 패딩 월",
    evidence = "sd = 0 · n_distinct = 1 · N = 347",
    contract_behavior = "canonical_screen_bt 는 이미 제외 (백테 198개월)",
    defect = "F1/F2 초회 산출이 199개월을 써서 전 arm 에 hit=0 가짜 달을 1개씩 포함했다",
    fix = "F1/F2 측정 창을 백테 198개월로 통일 (사전등록 §1 '대조 구간 198개월' 에 정합)",
    impact_measured = "F2 t: mean 1.3908→1.3912 · q50 -1.8159→-1.8163 · q90 1.4049→1.4060 (라벨 전환 없음)"),
  F3 = list(pass = f3_pass, n_months = nrow(f3tab), rho_linear = rho_lin, rho_ml = rho_ml,
            abs_diff = abs(rho_lin - rho_ml), diff_threshold = 0.25,
            spearman_linear = rs_lin, spearman_ml = rs_ml,
            def = "skew_t = 월 횡단면 실현수익 왜도(PerformanceAnalytics::skewness) · gap_t = ret_net(q50)−ret_net(mean)"),
  regime_interaction_c = regime,
  dsr_diag_n_trials_1 = as.list(dsr),
  ranking_8arm = list(table = tab, rank_ic_vs_sr_spearman = rho8,
    caution = "n=8 · 같은 패널·같은 피처·같은 워크포워드 공유로 **독립 아님**. 서열은 관찰이지 검정 아님."),
  overall_verdict = overall,
  basis_note = "1급 축 = total net SR + paired 월간 total net NW lag-3 t. 계약 net_sr(=active IR)과 혼용 금지(사전등록 §3).",
  capital_claim = "없음 — 대조군 확립 라운드. graduation HARD 3종 판정 대상 아님(사전등록 §9)."),
  file.path(OUT, "laneC_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

saveRDS(list(LIN = LIN, ML = ML, p1 = p1, HOLD = HOLD, jT = jT, jM = jM,
             HR = HR, f3tab = f3tab, tab = tab, regime = regime, dsr = dsr),
        file.path(OUT, "laneC_full.rds"))
cat(sprintf("\n★종합 판정: %s\n저장: laneC_result.json · laneC_full.rds\n", overall))
