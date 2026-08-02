# run_wt017_emit.R — WT-017 lineage + status/governance + 차트 생성
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_017")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_017")
res <- readRDS(file.path(OUT, "wt017_results.rds"))
cat("[emit] sidecar:", toJSON(res$sidecar, auto_unbox = TRUE), "\n")

# 1. lineage (alpha_package.json write 이후 — L-194 순서)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_017",
  package_type = "alpha_package",
  method_selected = "regime_x_book_multiplicative_g40_70 (unified Category m-1 x M4xR05, 사전등록 단일 규칙 — NEGATIVE 판정)",
  input_file_paths = c(
    "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
    ".cache/unified_regime_signal.parquet",
    ".cache/benchmark.parquet"
  ))

# 2. status + governance_log
st <- fromJSON(file.path(MB, "status.json"), simplifyVector = FALSE)
st$current_phase <- "ALPHA_DONE"
st$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900")
write_json(st, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE)
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_DONE_NEGATIVE",
  summary = paste0("FQ-115 국면 라벨 overlay 소비 — 한계기여 없음(점추정 유해): paired t -1.85 / ΔIR -0.22 / ",
    "EW기저 -2.04 / lag2 -2.57. 라벨→실현하락 판별력 0 (recall 0.10, fisher p=1.0). ",
    "WT-015 CRISIS +4.98% = 라벨 우연(CRISIS 라벨월 벤치 연율 +90%). ",
    "오라클 진단: 소비면 자체는 유효(MDD -23.3%→-9.2%) — 병목은 라벨 품질. 자본 주장 없음"))))
write_json(gl, file.path(MB, "governance_log.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[emit] status=ALPHA_DONE + governance_log append\n")

# 3. 차트 — 누적 active (BOOK vs CAND vs ORACLE) + CRISIS/CAUTION 음영
d  <- as.data.table(res$bt$BOOK$period_returns)[, .(date, a_book = ret_net - benchmark_ret)]
d2 <- as.data.table(res$bt$CAND$period_returns)[, .(date, a_cand = ret_net - benchmark_ret)]
d3 <- as.data.table(res$bt$ORACLE$period_returns)[, .(date, a_orc = ret_net - benchmark_ret)]
d <- Reduce(function(a, b) merge(a, b, by = "date"), list(d, d2, d3))
setorder(d, date)
per <- res$per
png(file.path(OUT, "wt017_chart_marginal.png"), width = 1400, height = 900, res = 130)
par(mfrow = c(2, 1), mar = c(2.5, 4, 2.5, 1))
cb <- cumprod(1 + d$a_book); cc <- cumprod(1 + d$a_cand); co <- cumprod(1 + d$a_orc)
ylim <- range(c(cb, cc, co))
plot(d$date, cb, type = "n", log = "y", ylim = ylim, ylab = "누적 active (로그)", xlab = "",
     main = "WT-017 국면 라벨 overlay 한계기여 — BOOK(M4xR05) vs 후보 vs 오라클(진단)")
gm <- per[g < 1, eval_date]
for (dd in gm) rect(dd - 15, ylim[1], dd + 15, ylim[2], col = rgb(1, 0, 0, 0.12), border = NA)
lines(d$date, cb, col = "black", lwd = 2)
lines(d$date, cc, col = "red", lwd = 2)
lines(d$date, co, col = "grey55", lwd = 1.5, lty = 2)
legend("topleft", c("BOOK 현행 M4xR05 (t=6.18)", "후보 = BOOK x 국면라벨 g (t=5.08, 한계 t=-1.85)",
                    "오라클 BM<0 예지 (진단 전용, t=7.87)", "음영 = 라벨 발화월(g<1)"),
       col = c("black", "red", "grey55", rgb(1, 0, 0, 0.3)), lwd = c(2, 2, 1.5, 8),
       lty = c(1, 1, 2, 1), bty = "n", cex = 0.8)
# 하단: 한계 기여 누적 (cand - book) — 라벨 발화월 표시
dm <- d[, .(date, dd = a_cand - a_book)]
plot(dm$date, cumsum(dm$dd) * 100, type = "l", col = "red", lwd = 2,
     ylab = "누적 한계기여 (%p, active)", xlab = "",
     main = "한계기여 누적 (후보 - BOOK): -2.38%/yr, paired t = -1.85 | 라벨의 실현-하락 recall 0.10 (p=1.0)")
abline(h = 0, col = "grey70")
for (dd in gm) abline(v = dd, col = rgb(1, 0, 0, 0.25))
dev.off()
cat("[emit] chart 저장: wt017_chart_marginal.png\n")
