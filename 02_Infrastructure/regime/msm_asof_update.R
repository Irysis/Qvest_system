## msm_asof_update.R — as-of MSM 생산자 실행(결정 PIT-C1-MSM-PARAMS 안 A · 라이브러리 = msm_asof.R)
##   원장(06_Registry/msm_param_schedule.json)에 없는 완료 연도를 적합해 append 하고 일별 경로(.cache/msm_asof_daily.parquet)를 쓴다.
##   처음 실행(원장 없음) = 2003~직전 해 이력 적합(병렬) · 그 뒤 = 해가 바뀐 첫 실행에 1행만 붙는다(연 1회).
##   --pc3 = 양성 대조 PC3(같은 전기간 자료 2026-01-16 까지에서 우리 최적점 음의 우도 ≤ 운영 핀 모수 음의 우도) 기록 — 원장과 무관.
##   ★이 단계(S1)는 소비자를 바꾸지 않는다 — 운영 국면 경로(msm_daily_latest → regime_signal)는 S2 재발행에서 바꾼다.
## 실행: Rscript 02_Infrastructure/regime/msm_asof_update.R [--cores=N] [--pc3=<결과 json 경로>]
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/regime/msm_asof.R"))
a <- commandArgs(trailingOnly = TRUE)
arg <- function(k, d) { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), a, value = TRUE)); if (length(v)) v[1] else d }
cores <- as.integer(arg("cores", "1"))
t0 <- Sys.time()
res <- msma_update(ROOT, cores = cores)
pc3p <- arg("pc3", "")
if (nzchar(pc3p)) {
  bm <- msma_load_bm(ROOT); RT <- msma_returns(bm); x <- RT[Date <= as.Date("2026-01-16")]
  pin <- unlist(fromJSON(file.path(ROOT, "02_Infrastructure/ops/msm_param_pin.json"))$params)[c("m0", "sigma", "b", "gamma_1")]
  f <- msma_fit(x$r, root = ROOT); v <- vapply(f$inits, function(z) z$negloglik, 1); best <- f$inits[[which.min(v)]]
  nl_pin <- msma_kernel(ROOT)$msm_fast_filter(x$r, MSMA_K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]], FALSE)$negloglik
  out <- list(control = "PC3 전기간 MLE ≤ 핀 음의 우도", data = c(format(min(x$Date)), format(max(x$Date))), n = nrow(x), fitted = best$par,
              negloglik_fitted = best$negloglik, negloglik_at_pin = nl_pin, pass = best$negloglik <= nl_pin + 1e-6, secs = f$secs,
              note = "PIT 대조가 아니라 추정기 품질 대조 — 운영 NM maxit 1000 은 핀보다 나쁜 점에서 멈췄다(원형 v0). 우리 추정기가 같은 자료에서 핀 이상이어야 한다")
  dir.create(dirname(pc3p), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, digits = NA), pc3p, useBytes = TRUE)
  cat(sprintf("[msm_asof] PC3 %s — 적합 %.4f vs 핀 %.4f(음의 우도) · %.0f초\n", if (out$pass) "통과" else "실패", best$negloglik, nl_pin, f$secs))
}
cat(sprintf("[msm_asof] 끝 — %.1f분\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
