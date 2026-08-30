# run_08_performance.R — 최종 판단: 오버레이를 켜면 전략 성과가 좋아지는가
#
# 도훈 지시(2026-08-30): "실제 전략 성과 개선이 있는지 확인해보고 판단하는게 가장 정확할꺼 같아."
# p 값이 아니라 **NAV·Calmar·최악구간**으로 판정한다.
#
# 대상: 일별 BOCPD(재현검사 통과) 를 월 결정으로 접어 Case D(현금 8%) 를 적용.
#       비교군 = 오버레이 미적용(현행). 문턱은 기존 코드값 0.60 하나만 — 스윕 금지.
#       참고로 월간판 BOCPD 도 같이 올려 세 판을 나란히 본다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_08_performance.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(arrow) })

OUT <- "04_Research/method_frontier/bocpd_direction_repair"
D <- as.data.table(read_parquet(file.path(OUT, "daily_bocpd.parquet")))
D[, Date := as.Date(Date)]; setorder(D, Date)
p <- as.data.table(read_parquet(
  "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
p[, Date := as.Date(Date)]; p <- unique(p, by = "Date")[order(Date)]

mon <- D[, .(mass_d = last(mass_d)), by = period_end][order(period_end)]
mon[, mass_lag_d := shift(mass_d)]
J <- merge(mon, p[, .(period_end = Date, ret = ret_net, cash = Cash_Pct_lag,
                      mass_m = bocpd_short_run_mass_lag)], by = "period_end")
J <- J[!is.na(ret)][order(period_end)]
J[, obs := seq_len(.N)]
J[, clean := is.na(cash) | cash == 0]

TH <- 0.60; WARM <- 12L; DOSE <- 0.08          # 전부 기존 코드값
J[, fire_daily  := as.integer(clean & !is.na(mass_lag_d) & mass_lag_d >= TH & obs > WARM)]
J[, fire_monthly := as.integer(clean & !is.na(mass_m)     & mass_m     >= TH & obs > WARM)]

perf <- function(r, label) {
  nav <- cumprod(1 + r)
  n <- length(r); yrs <- n / 12
  cagr <- nav[n]^(1 / yrs) - 1
  dd <- nav / cummax(nav) - 1; mdd <- min(dd)
  sr <- mean(r) / sd(r) * sqrt(12)
  calmar <- cagr / abs(mdd)
  w10 <- mean(sort(r)[1:round(n * 0.10)])
  data.table(판 = label, CAGR = cagr, MDD = mdd, Calmar = calmar, SR = sr,
             최악10평균 = w10, 최종NAV = nav[n])
}

r0 <- J$ret
r_d <- ifelse(J$fire_daily   == 1L, r0 * (1 - DOSE), r0)
r_m <- ifelse(J$fire_monthly == 1L, r0 * (1 - DOSE), r0)

res <- rbindlist(list(
  perf(r0,  "① 현행 (BOCPD 미적용)"),
  perf(r_m, sprintf("② 월간 BOCPD 적용 (발화 %d개월)", sum(J$fire_monthly))),
  perf(r_d, sprintf("③ 일별 BOCPD 적용 (발화 %d개월)", sum(J$fire_daily)))))

cat(sprintf("=== 성과 대조 (n=%d개월, %s ~ %s · 문턱 %.2f · 용량 %.0f%% · warm-up %d) ===\n",
            nrow(J), min(J$period_end), max(J$period_end), TH, DOSE * 100, WARM))
print(res[, .(판, CAGR = sprintf("%.2f%%", CAGR * 100),
              MDD = sprintf("%.2f%%", MDD * 100),
              Calmar = round(Calmar, 4), SR = round(SR, 4),
              최악10평균 = sprintf("%.2f%%", 최악10평균 * 100),
              최종NAV = round(최종NAV, 1))])

cat("\n=== 변화폭 (현행 대비) ===\n")
for (i in 2:3) {
  cat(sprintf("  %s\n    Calmar %+.4f · SR %+.4f · CAGR %+.3f%%p · MDD %+.3f%%p · 최악10 %+.3f%%p · NAV %+.1f%%\n",
              res$판[i], res$Calmar[i] - res$Calmar[1], res$SR[i] - res$SR[1],
              (res$CAGR[i] - res$CAGR[1]) * 100, (res$MDD[i] - res$MDD[1]) * 100,
              (res$최악10평균[i] - res$최악10평균[1]) * 100,
              (res$최종NAV[i] / res$최종NAV[1] - 1) * 100))
}

fwrite(res, file.path(OUT, "performance.csv"))
cat(sprintf("\n[out] %s/performance.csv\n", OUT))
