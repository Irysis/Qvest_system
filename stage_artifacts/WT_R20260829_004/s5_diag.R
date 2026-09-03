# S5 — 진단 배터리(advisory) + 중복성 + alpha_scores.parquet + 국면/변동성 신호 시계열 파일
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(arrow)
  library(sandwich); library(lmtest); library(future.apply)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")
P <- readRDS(file.path(OUT, "panel.rds")); O2 <- readRDS(file.path(OUT, "s2_objects.rds"))
O4 <- readRDS(file.path(OUT, "s4_objects.rds"))
E <- O4$E_cand; M_cand <- O4$M_cand; M_base <- O4$M_base
SIG <- O2$SIG; SIZE <- P$SIZE
R <- as.data.table(P$fwd$returns_dt)[!is.na(Ret_1m)]
PPY <- 12L

## ── DSR (Bailey-Lopez de Prado) — 기존 구현 재사용(자체합성 아님) ────────────
DSR_SRC <- file.path(ROOT, "02_Infrastructure/ml_pipeline/dpl_ens_eval_contract.R")
eval(parse(text = paste(readLines(DSR_SRC, warn = FALSE)[58:71], collapse = "\n")))

## ── rank-IC 배터리 (advisory) ────────────────────────────────────────────────
D <- merge(E[, .(Date, Ticker, score_final, z_mom, vol126_ann, panic_use, pool)],
           R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
ic_dt <- D[, .(ic = suppressWarnings(stats::cor(score_final, Ret_1m, method = "spearman")),
               ic_base = suppressWarnings(stats::cor(z_mom, Ret_1m, method = "spearman")),
               n = .N), by = Date][is.finite(ic)][order(Date)]
nw_t1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
rank_ic <- mean(ic_dt$ic); icir <- mean(ic_dt$ic)/stats::sd(ic_dt$ic)
harvey_t <- nw_t1(ic_dt$ic)

## 단조성 (십분위 forward 수익 단조성 — Spearman(십분위, 평균수익))
D[, dec := cut(frank(-score_final, ties.method="first"), breaks = 10, labels = FALSE), by = Date]
mono_tbl <- D[, .(r = mean(Ret_1m)), by = .(Date, dec)][, .(r = mean(r)), by = dec][order(dec)]
monotonicity <- suppressWarnings(stats::cor(mono_tbl$dec, mono_tbl$r, method = "spearman"))

## 부분기간 안정성 (활성 SR 3분할)
pr <- M_cand$pr; act <- pr$ret_net - pr$BM_Ret
g <- cut(seq_along(act), 3, labels = FALSE)
sub_sr <- vapply(1:3, function(k) { a <- act[g == k]; mean(a)/stats::sd(a)*sqrt(PPY) }, numeric(1))
subperiod_stability <- mean(sign(sub_sr) == sign(mean(act)))

## 크기-중립화 후 IC (섹터 패널 부재 → log(Size) 중립화)
DS <- merge(D, SIZE, by = c("Date","Ticker"))
DS[, lsz := log(pmax(Size, 1))]
DS[, score_res := { f <- stats::lm.fit(cbind(1, lsz), score_final); f$residuals }, by = Date]
ic_pn <- DS[, .(ic = suppressWarnings(stats::cor(score_res, Ret_1m, method="spearman"))), by = Date][is.finite(ic)]
post_neutral_ic <- mean(ic_pn$ic)

## ── DSR / 비용 커버리지 ──────────────────────────────────────────────────────
sk <- { a <- act; mean((a-mean(a))^3)/stats::sd(a)^3 }
ku <- { a <- act; mean((a-mean(a))^4)/stats::sd(a)^4 }
net_active_sr <- mean(act)/stats::sd(act)*sqrt(PPY)
N_TRIALS_CUM <- 4L   # 강화 원장 attempt 1~4 (본 라운드 포함) — chain 이므로 게이트 아님
dsr <- deflated_sharpe_ratio(net_active_sr, length(act), N_TRIALS_CUM, sk, ku)
cost_ann <- M_cand$turnover_annual * 15/1e4
gross_active_ann <- 12*mean(act) + cost_ann
cost_coverage_ratio <- gross_active_ann / cost_ann

## ── 중복성 (Factor Zoo 축소) ─────────────────────────────────────────────────
# (a) 저변동 축과의 직접 중복 — 본 후보의 패닉 가지가 곧 저변동 틸트인지
red_vol <- D[is.finite(vol126_ann), .(cor_negvol = suppressWarnings(stats::cor(score_final, -vol126_ann,
            method="spearman"))), by = .(Date, panic_use)][is.finite(cor_negvol),
            .(mean_cor = mean(cor_negvol), n = .N), by = panic_use]
# (b) Factor DB 등재 팩터와의 상관
ME <- sort(unique(E$Date)); samp <- ME[seq(1, length(ME), length.out = 24L)]
plan(multisession, workers = min(6L, max(1L, parallel::detectCores()-1L)))
db <- rbindlist(future_lapply(samp, function(d) {
  suppressWarnings(suppressMessages(library(data.table)))
  source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/factor_db/factor_db_connector.R"))
  fn <- c("M02_Mom_6_1","L26_Log_MktCap","L02_Turnover","L05_Dollar_Volume","L15_Turnover_252d")
  x <- tryCatch(as.data.table(load_month_factors(d, factor_names = fn)), error=function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  w <- dcast(x[Factor_Name %in% fn], Ticker ~ Factor_Name, value.var="Z_Score_Aligned",
             fun.aggregate = function(v) v[1])
  w[, Date := d][] }, future.seed = TRUE), fill = TRUE)
plan(sequential)
redundancy <- list()
if (!is.null(db) && nrow(db)) {
  RD <- merge(E[Date %in% samp, .(Date, Ticker, score_final)], db, by = c("Date","Ticker"))
  for (cc in setdiff(names(db), c("Date","Ticker"))) {
    v <- RD[, .(rho = suppressWarnings(stats::cor(score_final, get(cc), method="spearman",
                use="pairwise.complete.obs"))), by = Date][is.finite(rho)]
    redundancy[[cc]] <- list(mean_spearman = mean(v$rho), max_abs = max(abs(v$rho)), n_months = nrow(v))
  }
}

## ── 산출물: alpha_scores.parquet ─────────────────────────────────────────────
AS <- E[, .(Date, Ticker, score = score_final, score_base_momentum = z_mom,
            momentum_raw = score, vol126_ann, pool_indicator = pool,
            panic = panic_use, signal_ym)]
AS[, holding_ym := substr(format(as.Date(format(Date, "%Y-%m-01")) + 32L, "%Y-%m"), 1, 7)]
write_parquet(AS, file.path(OUT, "alpha_scores.parquet"))

## ── 산출물: 국면/변동성 신호 시계열 (적용 아님 — 하류 소비용) ────────────────
SIGOUT <- SIG[is.finite(panic), .(signal_ym, signal_month_end, holding_ym, holding_month_start,
                                  used_cutoff, cum24_bm, I_B, mkt_vol126_ann, vol_hi, panic)]
fwrite(SIGOUT, file.path(OUT, "regime_signal_timeseries.csv"))
write_parquet(SIGOUT, file.path(OUT, "regime_signal_timeseries.parquet"))
# 종목단 예측 변동성(단변량) 패널 — optimizer/forge 가 구성 교체를 적용할 때 쓰는 입력
write_parquet(O2$sv[, .(Date, Ticker, vol126_ann, n_days = n_i)],
              file.path(OUT, "stock_pred_vol_panel.parquet"))
# 슬리브 실현분산 성분 분해 (F1/F2 근거 시계열)
write_parquet(O2$RV[, .(ym, rv_sleeve = rv, rv_bm, beta, mkt_comp, idio, mkt_share)],
              file.path(OUT, "sleeve_realized_variance.parquet"))

res <- list(
  meta = list(wt_id="WT-R20260829_004", metric_type="canonical_screen",
              note="rank-IC 계열은 advisory — 선택 권위는 canonical PORT_t"),
  rank_ic = rank_ic, rank_ic_base_momentum = mean(ic_dt$ic_base), icir = icir,
  harvey_t_stat = harvey_t,
  harvey_t_note = "rank-IC 시계열 NW lag-3 t — portfolio-alpha t 와 다른 양(measurement-graduation §2)",
  monotonicity = monotonicity, subperiod_active_sr = as.numeric(sub_sr),
  subperiod_stability = subperiod_stability, post_neutralization_ic = post_neutral_ic,
  post_neutralization_note = "섹터 패널 부재 — log(Size) 중립화만 적용",
  net_active_sr = net_active_sr, turnover_annual = M_cand$turnover_annual,
  deflated_sharpe_ratio = dsr, n_trials_cumulative = N_TRIALS_CUM,
  dsr_gate_note = "selection_type=chain (가설주도 순차) — DSR 게이트 부적용, 진단 산출·기록만(measurement-graduation §3)",
  cost_feasibility = list(cost_annual = cost_ann, gross_active_annual = gross_active_ann,
                          ratio = cost_coverage_ratio,
                          rule = "failure_rules Rule1: 비용 대비 기대 alpha ratio < 2 이면 실패",
                          note = "AX-001 v2 ratio 의 정본 정의를 레지스트리에서 찾지 못해 비용 타당성 비율로 대체 산출 — 라벨 정직 표기"),
  redundancy = list(
    low_vol_axis = list(mean_spearman_vs_neg_vol126_by_panic =
                          setNames(as.list(red_vol$mean_cor), paste0("panic_", red_vol$panic_use)),
                        reading = "패닉월 상관이 1 에 가까우면 그 달의 후보는 사실상 저변동 팩터다"),
    factor_db = redundancy,
    threshold = "cor vs 기존 등재 < 0.95"),
  artifacts = list(alpha_scores = "stage_artifacts/WT_R20260829_004/alpha_scores.parquet",
                   regime_signal = "stage_artifacts/WT_R20260829_004/regime_signal_timeseries.parquet",
                   stock_pred_vol = "stage_artifacts/WT_R20260829_004/stock_pred_vol_panel.parquet",
                   sleeve_rv = "stage_artifacts/WT_R20260829_004/sleeve_realized_variance.parquet",
                   period_returns_production = "stage_artifacts/WT_R20260829_004/period_returns_production.csv"))
write_json(res, file.path(OUT, "s5_diag.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")

cat(sprintf("\nrank_ic=%+.4f (base mom %+.4f) icir=%+.3f harvey_t=%+.3f mono=%+.3f\n",
            rank_ic, mean(ic_dt$ic_base), icir, harvey_t, monotonicity))
cat(sprintf("sub active SR = [%s] stability=%.2f | post-neutral IC=%+.4f\n",
            paste(sprintf("%+.3f", sub_sr), collapse=","), subperiod_stability, post_neutral_ic))
cat(sprintf("net_active_SR=%+.3f DSR=%.3f (n_trials=%d, chain) TO=%.2f cost_ratio=%.2f\n",
            net_active_sr, dsr, N_TRIALS_CUM, M_cand$turnover_annual, cost_coverage_ratio))
print(red_vol)
cat("factor_db redundancy:\n"); for (nm in names(redundancy))
  cat(sprintf("  %-20s mean rho=%+.3f max|rho|=%.3f (n=%d)\n", nm,
              redundancy[[nm]]$mean_spearman, redundancy[[nm]]$max_abs, redundancy[[nm]]$n_months))
