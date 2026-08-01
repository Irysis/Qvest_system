#==============================================================================
# paired_test.R — Self-Adversarial Challenge C1 해소용 paired NW t-검정
#   "회전율 평활이 PORT_t를 0.219→1.048로 올렸다"는 주장은 유의하지 않은 두 t값의
#   비율이므로 그 자체로 효과 근거가 못 된다. 두 arm의 월간 순수익 차이 시계열에
#   직접 NW(lag-3) t-검정을 걸어 차이가 0과 구분되는지 본다.
#   벤치는 두 arm이 동일(같은 bench_dt)이므로 active 차이 = ret_net 차이.
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts", "alpha_search_dualbasis_20260802")
source(file.path(ROOT, "02_Infrastructure", "contracts", "backtest_result_contract.R"))  # .nw_t_mean
source(file.path(ROOT, "02_Infrastructure", "contracts", "canonical_screen_bt.R"))
stopifnot(exists(".canon_nw_t"), exists(".nw_t_mean", mode = "function"))

rd <- function(l) fread(file.path(OUT, sprintf("period_returns_%s.csv", l)))

pair <- function(a, b, tag) {
  A <- rd(a); B <- rd(b)
  M <- merge(A[, .(date, ra = ret_net, bm = benchmark_ret)],
             B[, .(date, rb = ret_net)], by = "date")
  stopifnot(nrow(M) > 100)
  # 벤치 동일 확인 (같은 bench_dt에서 왔는지 실증 — 가정 아닌 검사)
  bm_b <- B[, .(date)]; # B의 벤치는 CSV에 있음
  M2 <- merge(M, rd(b)[, .(date, bmb = benchmark_ret)], by = "date")
  bench_identical <- isTRUE(all.equal(M2$bm, M2$bmb, tolerance = 1e-12))
  d <- M$rb - M$ra                      # b − a (개선 방향이면 양수)
  t_nw <- .canon_nw_t(d)
  t_iid <- mean(d) / (sd(d) / sqrt(length(d)))
  cat(sprintf("\n[%s]  b=%s  −  a=%s\n", tag, b, a))
  cat(sprintf("  벤치 동일: %s | n=%d개월\n", bench_identical, length(d)))
  cat(sprintf("  월평균 차이 = %+.4f%%p (연 %+.2f%%p 단순환산)\n", 100*mean(d), 100*mean(d)*12))
  cat(sprintf("  NW lag-3 t = %.3f | iid t = %.3f | 유의(|t|>=1.96): %s\n",
              t_nw, t_iid, abs(t_nw) >= 1.96))
  data.table(tag = tag, arm_b = b, arm_a = a, n = length(d),
             bench_identical = bench_identical,
             mean_diff_monthly = mean(d), t_nw_lag3 = t_nw, t_iid = t_iid,
             significant = abs(t_nw) >= 1.96)
}

res <- rbindlist(list(
  pair("resid_info_vol_BASE", "resid_info_vol_M60", "잔차거래량: 60일평활 − 원논문"),
  pair("spec_mass_lowfreq_60d_BASE", "spec_mass_lowvol", "추세-저주파: 저변동성조건부 − 원논문")
))
fwrite(res, file.path(OUT, "paired_test_20260802.csv"))
cat("\n[paired_test] saved:", file.path(OUT, "paired_test_20260802.csv"), "\n")
print(res)
