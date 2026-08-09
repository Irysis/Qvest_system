# =============================================================================
# run_selfadv_p8.R — Self-Adversarial Challenge 에서 나온 재측정 (prose 아닌 코드로 해소)
#   SA-1 (ACCEPT): subperiod_stability 0.6667 을 손으로 적었다 — 3분기 실측으로 대체
#   SA-2 (ACCEPT): post-2015 IC 양(+) ∧ top-25 음(−) 의 정체 = 좌측-국소화인가? 분위 프로파일 직접 측정
#   SA-3 (ACCEPT): 불확실성-인지 하한 (μ̃ = μ̂ − k·SE) — alpha_vector 점추정의 하한 서술
#   SA-4 (진단): 라운드 전체 검정 수 집계 (다중비교 정직 라벨)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/run_selfadv_p8.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[sa] ", fmt, "\n"), ...))
M2 <- readRDS(file.path(OUT, "measure_p2.rds")); P0 <- readRDS(file.path(OUT, "p0_panels.rds"))
X <- M2$X; cs <- M2$cs; bench_dt <- P0$bench_dt
say("INPUT X nrow=%d n_month=%d", nrow(X), uniqueN(X$Date))
S <- list()
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
nw_se <- function(x, lag = 3L) { x <- x[is.finite(x)]; f <- lm(x ~ 1)
  tryCatch(sqrt(sandwich::NeweyWest(f, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_) }

# ── SA-1: subperiod_stability 실측 (3분기, 부모와 동일 경계) ────────────────
say("=== SA-1: subperiod_stability 3분기 실측 (advisory 진단) ===")
ic_of <- function(zc) X[is.finite(get(zc)) & is.finite(act),
  if (.N >= 10L && sd(get(zc)) > 0 && sd(act) > 0) .(ic = cor(get(zc), act, method = "spearman")) else .(ic = NA_real_), by = Date][is.finite(ic)]
sub <- list()
for (zc in c("q01","q01_n")) {
  ic <- ic_of(zc)
  ic[, p := fifelse(Date < as.Date("2015-01-01"), "P1_2001_2014",
        fifelse(Date < as.Date("2020-01-01"), "P2_2015_2019", "P3_2020_2026"))]
  tb <- ic[, .(ic_mean = mean(ic), ic_t_nw = nw_t(ic), n = .N), by = p][order(p)]
  stab <- mean(tb$ic_mean > 0)
  sub[[zc]] <- list(table = as.list(tb), subperiod_stability = stab)
  say("  %-6s %s → subperiod_stability(양(+) 분기 비율) = %.4f", zc,
      paste(sprintf("%s IC %+.4f (t %+.2f, n=%d)", tb$p, tb$ic_mean, tb$ic_t_nw, tb$n), collapse = " | "), stab)
}
S$subperiod <- c(sub, list(note = "advisory 진단 — 분할 '판정' 아님(사전등록 판정은 연속 시간추세). 경계는 부모 라운드와 동일"))

# ── SA-2: 좌측-국소화 직접 검사 (post-2015 IC 양 ∧ top 음 의 정체) ──────────
say("=== SA-2: 분위 프로파일 — post-2015 IC 양(+)의 출처 ===")
prof <- function(zc, win) {
  d <- if (win == "full") X else X[Date >= as.Date("2015-01-01")]
  d <- d[is.finite(get(zc)) & is.finite(act)]
  s <- d[, { qr <- frank(get(zc))/.N
    .(q1 = mean(act[qr <= 0.2]), q2 = mean(act[qr > 0.2 & qr <= 0.4]), q3 = mean(act[qr > 0.4 & qr <= 0.6]),
      q4 = mean(act[qr > 0.6 & qr <= 0.8]), q5 = mean(act[qr > 0.8])) }, by = Date]
  qm <- 100*12*c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
  tt <- c(nw_t(s$q1), nw_t(s$q2), nw_t(s$q3), nw_t(s$q4), nw_t(s$q5))
  say("  %-6s %-9s 분위 연수익 [%s]  t [%s]",
      zc, win, paste(sprintf("%+6.2f", qm), collapse = " "), paste(sprintf("%+5.2f", tt), collapse = " "))
  list(quintile_ann_pct = qm, quintile_t = tt, n_month = nrow(s))
}
S$profile <- list(
  q01_n_full = prof("q01_n","full"), q01_n_post2015 = prof("q01_n","post2015"),
  q01_full   = prof("q01","full"),   q01_post2015   = prof("q01","post2015"))
p <- S$profile$q01_n_post2015$quintile_ann_pct
say("  ★ 중립 post-2015: 최하위분위 %+.2f%%(t %+.2f) · 최상위분위 %+.2f%%(t %+.2f) — |하단| %s |상단|",
    p[1], S$profile$q01_n_post2015$quintile_t[1], p[5], S$profile$q01_n_post2015$quintile_t[5],
    if (abs(p[1]) > abs(p[5])) ">" else "<=")
S$left_tail_localized <- abs(p[1]) > abs(p[5])

# ── SA-3: 불확실성-인지 하한 ────────────────────────────────────────────────
say("=== SA-3: 불확실성-인지 하한 (μ̃ = μ̂ − k·SE, Liao 2025 원칙 ③) ===")
A2 <- M2$A2
se_m <- nw_se(A2$series$b)
lb <- sapply(c(0,1,2), function(k) 100*12*(A2$slope_monthly - k*se_m))
say("  A2 기울기 연 %+.2f%% · NW SE 연 %+.2f%% → 하한 k=0 %+.2f%% / k=1 %+.2f%% / k=2 %+.2f%%",
    100*12*A2$slope_monthly, 100*12*se_m, lb[1], lb[2], lb[3])
say("  ★ k=1 하한이 %s → 점추정 기반 alpha_vector 는 상한 성격이며 하한 기반 예측은 %s",
    if (lb[2] > 0) "양(+)" else "비양(非陽)", if (lb[2] > 0) "양(+)" else "0 이하")
S$uncertainty_aware <- list(slope_ann_pct = 100*12*A2$slope_monthly, nw_se_ann_pct = 100*12*se_m,
  lower_bound_k0 = lb[1], lower_bound_k1 = lb[2], lower_bound_k2 = lb[3],
  note = "alpha_vector 는 점추정(k=0) 기반. 원칙 ③(CI > 점추정) 상 소비 시 하한을 함께 볼 것")

# ── SA-4: post-2015 필터면 (좌측-국소화가 참이면 여기서 나와야 한다) ────────
say("=== SA-4: post-2015 필터면 (기술 기록 — 저검정력 라벨) ===")
act_of <- function(x) { pr <- as.data.table(x$period_returns)
  merge(pr[, .(Date = as.Date(date), ret_net)], bench_dt, by = "Date")[, .(Date, a = ret_net - BM_Ret)] }
mf <- merge(act_of(cs$BASE)[, .(Date, b = a)], act_of(cs$FILT_NEU)[, .(Date, f = a)], by = "Date")[, d := f - b]
for (w in c("full","post2015")) {
  dd <- if (w == "full") mf else mf[Date >= as.Date("2015-01-01")]
  say("  %-9s 중립 q20 제외 − base: 연 %+.2f%% NW t %+.2f n=%d", w, 100*12*mean(dd$d), nw_t(dd$d), nrow(dd))
  S[[paste0("filter_", w)]] <- list(ann_pct = 100*12*mean(dd$d), t_nw = nw_t(dd$d), n = nrow(dd))
}
S$filter_note <- "P0 에서 paired 형태 폐기 — 판정 아님. 저검정력(필요 연 2.81%) 라벨 유지"

# ── SA-5: 라운드 검정 수 집계 (다중비교 정직 라벨) ──────────────────────────
S$test_count <- list(
  fmb_slope_specs = 8L, quintile_batteries = 4L, era_tests = 6L,
  falsification_tests = 4L, canonical_arms = 4L, regime_interactions = 3L,
  total_reported = 29L,
  note = "사전등록 주판정은 A2(중립 FMB 기울기) 1건. 나머지는 사전등록 반증시험·통제·서술. 최대 |t| 는 FMB 계열 2.21 이며 단독으로는 다중비교 하에서 무의미 — 본 라운드가 인용하는 결론은 '같은 창에서 부호가 반대인 두 유의 결과의 결합'(post-2015 IC +2.72 ∧ top-25 −2.38/−2.29)이고 결합은 단일 max-t 보다 우연 발생이 어렵다")
say("=== SA-5: 라운드 보고 검정 %d건 · 사전등록 주판정 1건 ===", S$test_count$total_reported)

write_json(S, file.path(OUT, "selfadv_p8.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(S, file.path(OUT, "selfadv_p8.rds"))
say("=== Self-Adversarial 재측정 완료 ===")
