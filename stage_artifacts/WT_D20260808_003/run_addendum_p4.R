# =============================================================================
# run_addendum_p4.R — WT-D20260808_003 상단-측 분해 + 소비면 수치
#   ⑦ d1/d2 충돌 해소: Q5−Q1 스프레드 차(−1.37%)와 top-25 Δmean(+2.34%)의 부호가 다르다.
#      long-only 슬롯은 상단만 산다 — 상단/하단을 분리해 어느 쪽에서 왔는지 실측.
#   ⑧ post-2015 상단 관측 (ADVISORY)
#   ⑨ 필터면(B5) paired 수치 + 검정력 라벨 (판정 아님, 기술 기록)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/run_addendum_p4.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[m4] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/required_effect_size.R")
M2 <- readRDS(file.path(OUT, "measure_p2.rds")); P0 <- readRDS(file.path(OUT, "p0_panels.rds"))
X <- M2$X; cs <- M2$cs; bench_dt <- P0$bench_dt
say("INPUT X nrow=%d n_month=%d · canonical arms=%s", nrow(X), uniqueN(X$Date), paste(names(cs), collapse=","))
B <- list()
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
nw_ci <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  f <- lm(x ~ 1); se <- tryCatch(sqrt(sandwich::NeweyWest(f, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_)
  mean(x) + c(-1,1)*qt(0.975, df = length(x)-1L)*se }

# ── ⑦ 상단/하단 분리 ────────────────────────────────────────────────────────
say("=== ⑦ 상단·하단 분리 (long-only 슬롯은 상단만 산다) ===")
side <- function(zc, kind, n_top = 25L) X[is.finite(get(zc)) & is.finite(act), {
  o <- order(-get(zc)); qr <- frank(get(zc))/.N
  switch(kind,
    top25 = .(v = mean(act[o[seq_len(min(n_top, .N))]])),
    top50 = .(v = mean(act[o[seq_len(min(50L, .N))]])),
    topq  = .(v = mean(act[qr > 0.8])),
    botq  = .(v = mean(act[qr <= 0.2]))) }, by = Date]
tab <- rbindlist(lapply(c("top25","top50","topq","botq"), function(kd) {
  a <- side("q01", kd); b <- side("q01_n", kd)
  m <- merge(a[, .(Date, r = v)], b[, .(Date, n = v)], by = "Date")[, d := n - r]
  ci <- nw_ci(m$d)
  data.table(bucket = kd, raw_ann = 100*12*mean(m$r), raw_t = nw_t(m$r),
             neu_ann = 100*12*mean(m$n), neu_t = nw_t(m$n),
             diff_ann = 100*12*mean(m$d), diff_t = nw_t(m$d),
             ci_lo = 100*12*ci[1], ci_hi = 100*12*ci[2], n = nrow(m)) }))
print(tab)
B$side_decomposition <- as.list(tab)
say("  ★ 상단(top-25) Δ %+.2f%% (t %+.2f) vs 하단분위 Δ %+.2f%% (t %+.2f) — d1 스프레드 차의 부호는 %s 에서 온다",
    tab[bucket=="top25", diff_ann], tab[bucket=="top25", diff_t],
    tab[bucket=="botq", diff_ann], tab[bucket=="botq", diff_t],
    if (abs(tab[bucket=="botq", diff_ann]) > abs(tab[bucket=="topq", diff_ann])) "하단" else "상단")

# ── ⑧ post-2015 상단 관측 (ADVISORY) ────────────────────────────────────────
say("=== ⑧ post-2015 상단 관측 (ADVISORY — 하위기간 서술, 판정 아님) ===")
p15 <- rbindlist(lapply(c("top25","topq"), function(kd) {
  a <- side("q01", kd)[Date >= as.Date("2015-01-01")]; b <- side("q01_n", kd)[Date >= as.Date("2015-01-01")]
  m <- merge(a[, .(Date, r = v)], b[, .(Date, n = v)], by = "Date")[, d := n - r]
  data.table(bucket = kd, raw_ann = 100*12*mean(m$r), raw_t = nw_t(m$r),
             neu_ann = 100*12*mean(m$n), neu_t = nw_t(m$n),
             diff_ann = 100*12*mean(m$d), diff_t = nw_t(m$d), n = nrow(m)) }))
print(p15)
B$post2015_side <- as.list(p15)

# ── ⑨ 필터면(B5) paired — 기술 기록 (판정 아님) ─────────────────────────────
say("=== ⑨ 필터면 paired (기술 기록 — P0 에서 형태 폐기, 판정 아님) ===")
act_of <- function(x) { p <- as.data.table(x$period_returns)
  merge(p[, .(Date = as.Date(date), ret_net)], bench_dt, by = "Date")[, .(Date, a = ret_net - BM_Ret)] }
aB <- act_of(cs$BASE); aF <- act_of(cs$FILT_NEU)
mf <- merge(aB[, .(Date, b = a)], aF[, .(Date, f = a)], by = "Date")[, d := f - b]
ci <- nw_ci(mf$d)
vp <- verdict_with_power(observed_t = nw_t(mf$d), observed_monthly = mean(mf$d), n = nrow(mf), sd_monthly = 0.01610)
say("  중립 q20 제외 − base: 연 %+.2f%%  NW t %+.2f  CI[%+.2f,%+.2f]  n=%d → %s (필요 연 %+.2f%%)",
    100*12*mean(mf$d), nw_t(mf$d), 100*12*ci[1], 100*12*ci[2], nrow(mf), vp$verdict, 100*vp$required$required_annual)
say("  PORT_t: base %+.3f → 필터 %+.3f (Δ %+.3f) | HARD 2.95 미달 — 자본 자격 주장 없음",
    cs$BASE$portfolio_alpha_t_nw_lag3, cs$FILT_NEU$portfolio_alpha_t_nw_lag3,
    cs$FILT_NEU$portfolio_alpha_t_nw_lag3 - cs$BASE$portfolio_alpha_t_nw_lag3)
B$filter_face <- list(delta_ann_pct = 100*12*mean(mf$d), t_nw = nw_t(mf$d), ci_ann_pct = 100*12*ci,
  n = nrow(mf), power_verdict = vp$verdict, required_annual_pct = 100*vp$required$required_annual,
  base_port_t = cs$BASE$portfolio_alpha_t_nw_lag3, filter_port_t = cs$FILT_NEU$portfolio_alpha_t_nw_lag3,
  note = "P0 에서 paired 형태 폐기 — 판정 아닌 기술 기록. HARD 2.95 미달")

write_json(B, file.path(OUT, "alpha_validation_addendum2.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== 부록2 완료 ===")
