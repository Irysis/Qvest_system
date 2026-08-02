# run_wt019_emit.R — WT-019 lineage + status/governance + 차트 생성
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_019")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_019")
res <- readRDS(file.path(OUT, "wt019_results.rds"))

# 1. lineage (alpha_package.json write 이후 — L-194 순서)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_019",
  package_type = "alpha_package",
  method_selected = "ddstate_10pct_252d_g40 (트레일링 낙폭 상태 nowcast x M4xR05, 사전등록 단일 규칙 — NEGATIVE, 라벨 사전 검정 단계 결론)",
  input_file_paths = c(
    "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
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
  summary = paste0("FQ-118 실현-하락 nowcast 대체 라벨 — 라벨 품질 사전 검정 FAIL(recall 0.351<=base 0.413, ",
    "fisher p=0.795)로 성과 전 결론. 진단 변형 4종(DD5/DD15/VOL80/단월음수) 전부 비유의 — 트레일링 ",
    "가격-상태 라벨은 KR 월간 실현-하락 판별 불가. 참고 성과도 유해: paired t -3.77 (-7.35%/yr), ",
    "dIR -0.439, 회수율 return축 -343%. PIT: assert HARD + 위반 주입 발화 + lag/strict clean. 자본 주장 없음"))))
write_json(gl, file.path(MB, "governance_log.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[emit] status=ALPHA_DONE + governance_log append\n")

# 3. 차트 — 누적 active (BOOK vs CAND vs ORACLE) + DD_STATE 음영
d  <- as.data.table(res$bt$BOOK$period_returns)[, .(date, a_book = ret_net - benchmark_ret)]
d2 <- as.data.table(res$bt$CAND$period_returns)[, .(date, a_cand = ret_net - benchmark_ret)]
d3 <- as.data.table(res$bt$ORACLE$period_returns)[, .(date, a_orc = ret_net - benchmark_ret)]
d <- Reduce(function(a, b) merge(a, b, by = "date"), list(d, d2, d3))
setorder(d, date)
per <- res$per
png(file.path(OUT, "wt019_chart_marginal.png"), width = 1400, height = 900, res = 130)
par(mfrow = c(2, 1), mar = c(2.5, 4, 2.5, 1))
cb <- cumprod(1 + d$a_book); cc <- cumprod(1 + d$a_cand); co <- cumprod(1 + d$a_orc)
ylim <- range(c(cb, cc, co))
plot(d$date, cb, type = "n", log = "y", ylim = ylim, ylab = "누적 active (로그)", xlab = "",
     main = "WT-019 낙폭 nowcast 라벨 overlay — BOOK(M4xR05) vs 후보 vs 오라클(진단)")
gm <- per[dd_state == TRUE, eval_date]
for (dd in gm) rect(dd - 15, ylim[1], dd + 15, ylim[2], col = rgb(1, 0, 0, 0.10), border = NA)
lines(d$date, cb, col = "black", lwd = 2)
lines(d$date, cc, col = "red", lwd = 2)
lines(d$date, co, col = "grey55", lwd = 1.5, lty = 2)
legend("topleft", c("BOOK 현행 M4xR05 (t=6.18)", "후보 = BOOK x 낙폭상태 g=0.40 (t=4.18, 한계 t=-3.77)",
                    "오라클 BM<0 예지 (진단 전용, t=7.87)", "음영 = DD_STATE 발화월 (92/269)"),
       col = c("black", "red", "grey55", rgb(1, 0, 0, 0.3)), lwd = c(2, 2, 1.5, 8),
       lty = c(1, 1, 2, 1), bty = "n", cex = 0.8)
dm <- d[, .(date, dd = a_cand - a_book)]
plot(dm$date, cumsum(dm$dd) * 100, type = "l", col = "red", lwd = 2,
     ylab = "누적 한계기여 (%p, active)", xlab = "",
     main = "한계기여 누적 (후보 - BOOK): -7.35%/yr, paired t=-3.77 | 라벨 recall 0.351 <= base 0.413 (p=0.795)")
abline(h = 0, col = "grey70")
for (dd in gm) abline(v = dd, col = rgb(1, 0, 0, 0.15))
dev.off()
cat("[emit] chart 저장: wt019_chart_marginal.png\n")
