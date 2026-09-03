#==============================================================================
# WT-R20260829_007 — forge 진단
#  (1) 벤치 basis 귀속: 상류 PORT_t 0.929 vs forge 권위 PORT_t — 2x2 분해
#  (2) OOS retention 방향 확인 (optimizer 관측: 회전 제어가 proxy 를 악화시킴)
#  (3) 부기간/국면 분해
#  (4) 표준 차트 4종
#==============================================================================
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })
STAGE <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
OUT   <- file.path(STAGE, "output"); dir.create(OUT, showWarnings = FALSE)

bt  <- readRDS(file.path(STAGE, "bt_result.rds"))
sim <- readRDS(file.path(STAGE, "forge_sim.rds"))
D   <- as.data.table(bt$nav)[, .(Date = as.Date(date), nav = nav_net)]
PR  <- as.data.table(bt$period_returns)[, .(Date = as.Date(date), ret_net, ret_gross, cost_ret)]
BR  <- as.data.table(bt$benchmark_returns)[, .(Date = as.Date(date), bm = benchmark_ret)]
DD  <- merge(PR, BR, by = "Date")

#--- NW lag3 t of mean(active) ------------------------------------------------
.nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 12L) return(NA_real_)
  m <- mean(x); e <- x - m
  g0 <- sum(e^2) / n; s <- g0
  for (l in seq_len(min(lag, n - 1L))) {
    gl <- sum(e[(l + 1L):n] * e[1:(n - l)]) / n
    s <- s + 2 * (1 - l / (lag + 1)) * gl
  }
  if (!is.finite(s) || s <= 0) return(NA_real_)
  m / sqrt(s / n)
}
.to_monthly <- function(dt, valcol) {
  x <- copy(dt); x[, ym := format(Date, "%Y-%m")]
  x[, .(r = prod(1 + get(valcol)) - 1), by = ym]
}

#=============================================================================
# (1) 벤치 basis 귀속 — 2x2 {전략 계열} x {벤치 계열}
#     전략: S_forge = M2_buffer50 forge 실측(일별->월) / S_alpha = alpha 발행 M1 월별 ret_net
#     벤치: B_prod  = KOSPI200 production BM  / B_alpha = period_returns_production benchmark_ret
#=============================================================================
PP  <- fread(file.path(STAGE, "period_returns_production.csv"))
PP[, hym := holding_ym]

Sf <- .to_monthly(DD, "ret_net");  setnames(Sf, "r", "S_forge")
Bp <- .to_monthly(DD, "bm");       setnames(Bp, "r", "B_prod")
M  <- merge(Sf, Bp, by = "ym")
M  <- merge(M, PP[, .(ym = hym, S_alpha = ret_net, B_alpha = benchmark_ret)], by = "ym", all.x = TRUE)
MC <- M[is.finite(S_alpha) & is.finite(B_alpha)]   # 공통창

cells <- CJ(S = c("S_forge", "S_alpha"), B = c("B_prod", "B_alpha"))
cells[, `:=`(port_t = NA_real_, active_ann = NA_real_, n = NA_integer_)]
for (i in seq_len(nrow(cells))) {
  a <- MC[[cells$S[i]]] - MC[[cells$B[i]]]
  cells$port_t[i]     <- .nw_t(a, 3L)
  cells$active_ann[i] <- mean(a) * 12
  cells$n[i]          <- length(a)
}

bench_cum <- data.table(
  basis = c("B_prod (KOSPI200 production BM)", "B_alpha (alpha 발행 cap-w 적격 유니버스 프록시)"),
  cum   = c(prod(1 + MC$B_prod) - 1, prod(1 + MC$B_alpha) - 1),
  cagr  = c((prod(1 + MC$B_prod))^(12 / nrow(MC)) - 1, (prod(1 + MC$B_alpha))^(12 / nrow(MC)) - 1))

strat_cum <- data.table(
  series = c("S_forge (M2_buffer50, forge share-based)", "S_alpha (M1 EW25 base, alpha 발행 월별)"),
  cum    = c(prod(1 + MC$S_forge) - 1, prod(1 + MC$S_alpha) - 1),
  cagr   = c((prod(1 + MC$S_forge))^(12 / nrow(MC)) - 1, (prod(1 + MC$S_alpha))^(12 / nrow(MC)) - 1))

gt <- function(s, b) cells[S == s & B == b, port_t]
attrib <- list(
  upstream_alpha_reported_port_t = 0.92857549,
  forge_authoritative_port_t = as.numeric(as.data.table(bt$benchmark_compare)[
    metric_name == "Portfolio_Alpha_t_NW_lag3", active_value][1]),
  cell_S_alpha_B_alpha = gt("S_alpha", "B_alpha"),
  cell_S_alpha_B_prod  = gt("S_alpha", "B_prod"),
  cell_S_forge_B_alpha = gt("S_forge", "B_alpha"),
  cell_S_forge_B_prod  = gt("S_forge", "B_prod"),
  delta_bench_only_at_alpha_strategy = gt("S_alpha", "B_prod") - gt("S_alpha", "B_alpha"),
  delta_strategy_only_at_alpha_bench = gt("S_forge", "B_alpha") - gt("S_alpha", "B_alpha"),
  delta_total = gt("S_forge", "B_prod") - gt("S_alpha", "B_alpha"))
attrib$dominant_term <- if (abs(attrib$delta_bench_only_at_alpha_strategy) >
                            abs(attrib$delta_strategy_only_at_alpha_bench)) "benchmark_basis" else "strategy_series"

#=============================================================================
# (2) OOS retention — anchored split 로 IS/OOS 활성 SR 비율
#     optimizer proxy: M1 -0.384 -> M2_B50 -0.425 (회전 제어가 오히려 악화)
#=============================================================================
.act_sr <- function(a) if (length(a) < 12 || sd(a) == 0) NA_real_ else mean(a) / sd(a) * sqrt(12)
.retention <- function(act, fracs = c(0.55, 0.65, 0.75)) {
  n <- length(act)
  v <- vapply(fracs, function(f) {
    k <- floor(n * f); if (k < 24 || n - k < 12) return(NA_real_)
    is_sr <- .act_sr(act[1:k]); oos_sr <- .act_sr(act[(k + 1):n])
    if (!is.finite(is_sr) || is_sr == 0) return(NA_real_)
    oos_sr / is_sr
  }, 0)
  list(per_frac = setNames(as.list(v), paste0("f", fracs * 100)), median = median(v, na.rm = TRUE))
}
act_forge <- MC$S_forge - MC$B_prod
act_forge_alphabench <- MC$S_forge - MC$B_alpha
act_alpha <- MC$S_alpha - MC$B_alpha
ret_forge <- .retention(act_forge)
ret_forge_ab <- .retention(act_forge_alphabench)
ret_alpha <- .retention(act_alpha)

es <- readRDS(file.path(STAGE, "forge_essence.rds"))
oos_essence <- as.numeric(es$sweep$essence$oos_retention)

#=============================================================================
# (3) 부기간 / 국면 분해
#=============================================================================
MC[, yr := as.integer(substr(ym, 1, 4))]
MC[, sub := fifelse(yr <= 2014, "2005-14", fifelse(yr <= 2019, "2015-19", "2020-26"))]
subp <- MC[, .(n = .N,
               forge_net_ann = prod(1 + S_forge)^(12 / .N) - 1,
               bm_ann        = prod(1 + B_prod)^(12 / .N) - 1,
               active_forge_ann = mean(S_forge - B_prod) * 12,
               active_alpha_ann = mean(S_alpha - B_alpha) * 12,
               active_sr_forge  = .act_sr(S_forge - B_prod)), by = sub][order(sub)]

# 국면: BM 12M 누적 부호 (t-1 기준, PIT 준수)
MC[, bm_12 := frollapply(B_prod, 12, function(z) prod(1 + z) - 1, align = "right")]
MC[, regime := fifelse(is.na(shift(bm_12)), NA_character_,
                fifelse(shift(bm_12) >= 0, "BULL(t-1 12M BM>=0)", "BEAR(t-1 12M BM<0)"))]
reg <- MC[!is.na(regime), .(n = .N,
             forge_ann = prod(1 + S_forge)^(12 / .N) - 1,
             bm_ann    = prod(1 + B_prod)^(12 / .N) - 1,
             active_ann = mean(S_forge - B_prod) * 12,
             sr = .act_sr(S_forge - B_prod)), by = regime][order(regime)]

#=============================================================================
# (4) 차트
#=============================================================================
DAILY <- merge(as.data.table(bt$nav)[, .(Date = as.Date(date), nav = nav_net)],
               as.data.table(bt$benchmark_returns)[, .(Date = as.Date(date), bm = benchmark_ret)],
               by = "Date")
DAILY[, bm_nav := cumprod(1 + bm)]
DAILY[, str_idx := nav / nav[1]]
DAILY[, bm_idx := bm_nav / bm_nav[1]]

png(file.path(OUT, "equity_curve.png"), width = 1400, height = 800, res = 120)
par(mar = c(4, 4.5, 3.5, 1))
plot(DAILY$Date, DAILY$str_idx, type = "l", log = "y", col = "#1a5fb4", lwd = 2,
     xlab = "", ylab = "누적 (log, 초기=1)",
     main = "WT-R20260829_007 GH2004 52w-high top25 EW + buffer50 — 누적수익 vs KOSPI200",
     ylim = range(c(DAILY$str_idx, DAILY$bm_idx)))
lines(DAILY$Date, DAILY$bm_idx, col = "#c01c28", lwd = 1.8, lty = 2)
grid(col = "gray85")
legend("topleft", c(sprintf("Strategy (net 15bps)  CAGR %.2f%% / SR %.3f / MDD %.1f%%",
                            100 * as.numeric(as.data.table(bt$metrics)[metric_name == "CAGR", metric_value][1]),
                            as.numeric(as.data.table(bt$metrics)[metric_name == "Sharpe", metric_value][1]),
                            100 * as.numeric(as.data.table(bt$metrics)[metric_name == "MDD", metric_value][1])),
                    "KOSPI200 (production BM)"),
       col = c("#1a5fb4", "#c01c28"), lwd = c(2, 1.8), lty = c(1, 2), bty = "n", cex = 0.85)
dev.off()

ann <- MC[, .(yr = yr, S = S_forge, B = B_prod)][, .(str = prod(1 + S) - 1, bm = prod(1 + B) - 1), by = yr][order(yr)]
png(file.path(OUT, "annual_returns.png"), width = 1400, height = 750, res = 120)
par(mar = c(4, 4.5, 3.5, 1))
bp <- barplot(rbind(ann$str, ann$bm) * 100, beside = TRUE, names.arg = ann$yr,
              col = c("#1a5fb4", "#c01c28"), border = NA, las = 2,
              ylab = "연간 수익률 (%)",
              main = "WT-R20260829_007 — 연간수익률 vs KOSPI200 (net 15bps)")
abline(h = 0, col = "gray40"); grid(nx = NA, ny = NULL, col = "gray85")
legend("topright", c("Strategy", "KOSPI200"), fill = c("#1a5fb4", "#c01c28"), border = NA, bty = "n")
dev.off()

# 최근 5Y zoom
z0 <- max(DAILY$Date) - 365 * 5
Z <- DAILY[Date >= z0]
Z[, s := nav / nav[1]]; Z[, b := cumprod(1 + bm)]
png(file.path(OUT, "oos_zoom_chart.png"), width = 1400, height = 750, res = 120)
par(mar = c(4, 4.5, 3.5, 1))
plot(Z$Date, Z$s, type = "l", col = "#1a5fb4", lwd = 2, xlab = "", ylab = "누적 (초기=1)",
     main = sprintf("최근 5Y zoom (%s ~ %s) — 후반부 신호 붕괴 구간",
                    as.character(min(Z$Date)), as.character(max(Z$Date))),
     ylim = range(c(Z$s, Z$b)))
lines(Z$Date, Z$b, col = "#c01c28", lwd = 1.8, lty = 2); grid(col = "gray85")
legend("topleft", c(sprintf("Strategy (5Y CAGR %.2f%%)", 100 * (tail(Z$s, 1)^(252 / nrow(Z)) - 1)),
                    sprintf("KOSPI200 (5Y CAGR %.2f%%)", 100 * (tail(Z$b, 1)^(252 / nrow(Z)) - 1))),
       col = c("#1a5fb4", "#c01c28"), lwd = c(2, 1.8), lty = c(1, 2), bty = "n", cex = 0.85)
dev.off()

png(file.path(OUT, "regime_decomposition.png"), width = 1400, height = 750, res = 120)
par(mfrow = c(1, 2), mar = c(6, 4.5, 3.5, 1))
barplot(subp$active_forge_ann * 100, names.arg = subp$sub, col = "#1a5fb4", border = NA,
        ylab = "활성수익 (%/yr)", main = "부기간별 활성수익 (vs KOSPI200)", las = 2)
abline(h = 0, col = "gray40")
barplot(reg$active_ann * 100, names.arg = gsub("\\(.*", "", reg$regime), col = "#26a269", border = NA,
        ylab = "활성수익 (%/yr)", main = "국면별 활성수익 (t-1 12M BM 부호)", las = 2)
abline(h = 0, col = "gray40")
dev.off()

#=============================================================================
diag <- list(
  wt_id = "WT-R20260829_007",
  benchmark_basis_attribution = list(
    note = paste("상류 PORT_t 와 forge 권위 PORT_t 는 **다른 양**이다.",
                 "상류는 alpha 발행 월별 M1(EW25 base) 계열을 alpha 자체 cap-w 벤치 프록시에 댄 값이고,",
                 "forge 권위는 optimizer 채택 M2_buffer50 을 일별 share-based 로 재구성해 production KOSPI200 BM 에 댄 값이다."),
    cells_2x2 = cells,
    bench_cumulative_common_window = bench_cum,
    strategy_cumulative_common_window = strat_cum,
    attribution = attrib,
    common_months = nrow(MC)),
  oos_retention = list(
    essence_authoritative = oos_essence,
    forge_vs_prodBM_median = ret_forge$median,
    forge_vs_alphaBM_median = ret_forge_ab$median,
    alpha_M1_vs_alphaBM_median = ret_alpha$median,
    optimizer_proxy_M1 = -0.38305051,
    optimizer_proxy_M2_B50 = -0.425,
    per_frac_forge = ret_forge$per_frac,
    per_frac_alpha = ret_alpha$per_frac,
    confirms_optimizer_direction = NA),
  subperiod = subp,
  regime = reg,
  charts = file.path("output", c("equity_curve.png", "annual_returns.png",
                                 "oos_zoom_chart.png", "regime_decomposition.png")))
diag$oos_retention$confirms_optimizer_direction <-
  (is.finite(ret_forge$median) && ret_forge$median < 0) && (oos_essence < 0)

writeLines(toJSON(diag, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null"),
           file.path(STAGE, "forge_diag.json"))

cat("=== 2x2 bench basis ===\n"); print(cells)
cat("\n=== bench cumulative (common window) ===\n"); print(bench_cum)
cat("\n=== strategy cumulative ===\n"); print(strat_cum)
cat("\n=== attribution ===\n"); print(unlist(attrib))
cat("\n=== OOS retention ===\n")
cat(sprintf(" essence(권위) = %.4f | forge vs prodBM = %.4f | forge vs alphaBM = %.4f | alphaM1 vs alphaBM = %.4f\n",
            oos_essence, ret_forge$median, ret_forge_ab$median, ret_alpha$median))
cat("\n=== subperiod ===\n"); print(subp)
cat("\n=== regime ===\n"); print(reg)
cat("=== forge_diag.R done ===\n")
