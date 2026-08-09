# =============================================================================
# correct_p5.R — 결함 2건 수리 후 재측정 (p2 의 raw arm 을 대체)
#
#  [수리 1] 빈 분위 NaN — 원인은 raw z 동점(C02 최빈값 점유 중앙 41.7% / M26 21.7%).
#     수리 = 분위 랭크에 **무작위 동점처리**(frank ties.method="random", 시드 고정)를 전 셀에
#            **균일 적용**. 동점이 없는 곳(중립 arm·앵커)에서는 average 랭크와 **완전 동일**해야
#            하므로, 먼저 앵커가 비트 단위로 재현되는지 확인하고(무-작동 검증) 통과할 때만 진행한다.
#     대안(강건성) = 빈 분위가 발생한 월을 제외. 두 수리 결과를 **함께** 보고한다.
#     ★ 결과를 보고 고르지 않는다 — 판정은 두 수리에서 일치할 때만 유지.
#  [수리 2] 추론 3종(부트 백분위 / 부트 정규근사 / NW)이 갈림 → **가장 보수적인 값**만 인용.
#
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/correct_p5.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p5] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/required_effect_size.R")
set.seed(20260809L)

SPN <- readRDS(file.path(OUT, "signal_panel_neutral.rds"))
P0  <- readRDS(file.path(IN3, "p0_panels.rds")); P1p <- readRDS(file.path(IN3, "prereg_p1.rds"))
D <- copy(P1p$D)
ACT_A <- D[, .(Date, Ticker, act)]
ACT_B <- merge(P0$E[, .(Date, Ticker)], P0$returns_dt, by = c("Date","Ticker"))
ACT_B <- merge(ACT_B, P0$bench_dt, by = "Date")[, .(Date, Ticker, act = Ret_1m - BM_Ret)]
R <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
          metric_type = "canonical_screen / diag", attributed_to = "WT-D20260808_003 next_probe NP-A")

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
acf1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_); as.numeric(acf(x, lag.max = 1, plot = FALSE)$acf[2]) }
mbb_draws <- function(x, block = 12L, B = 2000L) { n <- length(x); nb <- ceiling(n/block); sm <- n - block + 1L
  replicate(B, { st <- sample.int(sm, nb, replace = TRUE)
    idx <- as.vector(outer(0:(block-1L), st, function(a,b) b + a)); mean(x[idx[seq_len(n)]]) }) }

battery <- function(x, tag = "") {
  x <- x[is.finite(x)]; r1 <- acf1(x)
  t3 <- nw_t(x, 3L); t12 <- nw_t(x, 12L)
  cite_lag <- if (is.finite(r1) && r1 > 0.30) 12L else 3L
  tc <- if (cite_lag == 12L) t12 else t3
  m <- mbb_draws(x)
  p_pct <- 2*min(mean(m <= 0), mean(m >= 0)); p_nrm <- 2*(1-pnorm(abs(mean(x))/sd(m)))
  p_nw  <- 2*(1-pnorm(abs(tc)))
  list(n = length(x), mean_monthly = mean(x), ann_pct = 100*12*mean(x), acf_r1 = r1,
       t_nw_lag3 = t3, t_nw_lag12 = t12, cited_lag = cite_lag, t_cited = tc,
       boot_ci_ann_pct = 100*12*quantile(m, c(0.025, 0.975), names = FALSE),
       p_boot_percentile = p_pct, p_boot_normal = p_nrm, p_nw = p_nw,
       p_conservative = max(p_pct, p_nrm, p_nw),
       p_conservative_source = c("boot_percentile","boot_normal","nw")[which.max(c(p_pct, p_nrm, p_nw))],
       sign_neg_pct = 100*mean(x < 0), tag = tag)
}

# 분위 프로파일 — 부모 prof() 와 동일하되 (a) 동점처리 균일화 (b) 빈 분위 명시 집계
prof2 <- function(X, zc, ties = "random") {
  X[, { qr <- frank(get(zc), ties.method = ties)/.N
    .(q1 = mean(act[qr <= 0.2]), q2 = mean(act[qr > 0.2 & qr <= 0.4]), q3 = mean(act[qr > 0.4 & qr <= 0.6]),
      q4 = mean(act[qr > 0.6 & qr <= 0.8]), q5 = mean(act[qr > 0.8]),
      nmin = min(c(sum(qr <= 0.2), sum(qr > 0.2 & qr <= 0.4), sum(qr > 0.4 & qr <= 0.6),
                   sum(qr > 0.6 & qr <= 0.8), sum(qr > 0.8))), nn = .N) }, by = Date]
}

# ── 0. 무-작동 검증: 동점 없는 arm 에서 average ↔ random 이 동일해야 한다 ────
say("=== 0. 수리의 무-작동 검증 (동점 없는 곳에서 랭크 규칙이 결과를 바꾸지 않는가) ===")
gold <- fromJSON(file.path(IN3, "selfadv_p8.json"))$profile
for (wn in c("full","post2015")) {
  Xw <- if (wn == "full") D else D[Date >= as.Date("2015-01-01")]
  s_avg <- prof2(Xw[is.finite(q01_n) & is.finite(act)], "q01_n", "average")
  s_rnd <- prof2(Xw[is.finite(q01_n) & is.finite(act)], "q01_n", "random")
  qa <- 100*12*c(mean(s_avg$q1),mean(s_avg$q2),mean(s_avg$q3),mean(s_avg$q4),mean(s_avg$q5))
  qr_<- 100*12*c(mean(s_rnd$q1),mean(s_rnd$q2),mean(s_rnd$q3),mean(s_rnd$q4),mean(s_rnd$q5))
  gg <- gold[[paste0("q01_n_", wn)]]$quintile_ann_pct
  say("  앵커 %-9s: average↔random 최대편차 %.3e · 부모정본 대비 최대편차 %.3e · 최소분위 크기 %d",
      wn, max(abs(qa-qr_)), max(abs(qr_-gg)), min(s_rnd$nmin))
  stopifnot(max(abs(qa-qr_)) < 1e-12, max(abs(qr_-gg)) < 1e-9)
}
say("  ★ 무-작동 검증 통과 — 수리는 동점이 있는 곳에서만 작동한다")
R$repair_noop_verified <- TRUE

# ── 1. 두 수리 변형으로 전 셀 재측정 ────────────────────────────────────────
SIGS <- sort(unique(SPN$Factor_Name)); MIN_NAMES <- 30L
WINS <- list(full = as.Date("1900-01-01"), post2015 = as.Date("2015-01-01"))

run_cell <- function(frame, arm, win, repair) {
  ACT <- if (frame == "A") ACT_A else ACT_B
  zc <- if (arm == "raw") "z" else "zn"
  res <- list(); gaps <- list(); drop_log <- list()
  for (fn in SIGS) {
    X <- merge(SPN[Factor_Name == fn, .(Date, Ticker, z, zn)], ACT, by = c("Date","Ticker"))
    X <- X[Date >= WINS[[win]] & is.finite(get(zc)) & is.finite(act)]
    s <- prof2(X, zc, if (repair == "tiebreak") "random" else "average")
    s <- s[nn >= MIN_NAMES]
    n_before <- nrow(s)
    if (repair == "dropmonths") s <- s[nmin > 0]      # 빈 분위 월 제외
    drop_log[[fn]] <- n_before - nrow(s)
    if (nrow(s) < 24L) next
    q <- 100*12*c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
    if (!all(is.finite(q))) { say("  ★ %s/%s/%s/%s 여전히 비유한 — 정지", frame, arm, win, fn); next }
    ewrel <- q - mean(q); g <- s$q5 - s$q3
    res[[fn]] <- list(n_month = nrow(s), n_month_dropped = drop_log[[fn]], avg_names = mean(s$nn),
      quintile_ann_pct = q, ew_relative_ann_pct = ewrel, argmax_quintile = which.max(q),
      hump_weak = q[5] < q[3], hump_strict = which.max(q) %in% 2:4, top_below_ew = ewrel[5] < 0,
      gap_q5_q3 = battery(g, "gap"))
    gaps[[fn]] <- data.table(Date = s$Date, g = g)
  }
  P <- rbindlist(gaps, idcol = "fn")[, .(g = mean(g), k = .N), by = Date][order(Date)]
  pooled <- battery(P$g, "pooled"); pooled$avg_signals_per_month <- mean(P$k)
  P[, tt := as.numeric(Date - min(Date))/365.25]
  lf <- lm(g ~ tt, data = P)
  ct <- lmtest::coeftest(lf, vcov. = sandwich::NeweyWest(lf, lag = pooled$cited_lag, prewhite = FALSE))
  era <- list(slope_ann_pct_per_year = 100*12*unname(ct[2,1]), t = unname(ct[2,3]))
  k <- length(res); nh <- sum(sapply(res, function(z) isTRUE(z$hump_weak)))
  cnt <- list(n_signals = k, hump_weak = nh,
              hump_strict = sum(sapply(res, function(z) isTRUE(z$hump_strict))),
              top_below_ew = sum(sapply(res, function(z) isTRUE(z$top_below_ew))),
              binom_p = unname(binom.test(nh, k, 0.5)$p.value),
              months_dropped_total = sum(unlist(drop_log)))
  say("  [%s|%-7s|%-8s|%-10s] 신호 %2d · hump %d/%d · top<EW %d · 월제외 %3d | pooled 연 %+.3f%% ACF %+.2f t %+.2f 보수적p %.3f(%s)",
      frame, arm, win, repair, k, nh, k, cnt$top_below_ew, cnt$months_dropped_total,
      pooled$ann_pct, pooled$acf_r1, pooled$t_cited, pooled$p_conservative, pooled$p_conservative_source)
  list(per_signal = res, pooled = pooled, era_continuous = era, count = cnt)
}

say("=== 1. 두 수리 × 프레임 × arm × 창 재측정 ===")
CELLS <- list()
for (rp in c("tiebreak","dropmonths")) for (fr in c("A","B")) for (ar in c("raw","neutral")) for (wn in c("full","post2015"))
  CELLS[[paste(rp, fr, ar, wn, sep = "|")]] <- run_cell(fr, ar, wn, rp)
R$cells <- CELLS

# ── 2. 판정 규칙 (사전등록 원문, 보수적 p 사용) ─────────────────────────────
say("=== 2. 사전등록 판정 규칙 (보수적 p 채택) ===")
verdict_of <- function(ce) {
  k <- ce$count$n_signals; nh <- ce$count$hump_weak
  neg_sig <- (ce$pooled$ann_pct < 0) && (ce$pooled$p_conservative < 0.05)
  if (nh >= ceiling(2*k/3) && neg_sig) "COMMON" else if (nh <= floor(k/3)) "Q01_SPECIFIC" else "MIXED"
}
V <- list()
for (rp in c("tiebreak","dropmonths")) for (wn in c("full","post2015")) {
  vs <- sapply(c("A|raw","A|neutral","B|raw","B|neutral"),
               function(fa) verdict_of(CELLS[[paste(rp, fa, wn, sep = "|")]]))
  fin <- if (length(unique(vs)) == 1L) unname(vs[1]) else "MIXED"
  V[[paste(rp, wn, sep = "|")]] <- list(cells = as.list(vs), all_agree = length(unique(vs)) == 1L, final = fin)
  say("  %-10s %-9s → %s  ⇒ %s", rp, wn, paste(sprintf("%s=%s", names(vs), vs), collapse = " "), fin)
}
R$verdict <- V
R$primary_verdict <- V[["tiebreak|full"]]$final
R$repair_agreement <- (V[["tiebreak|full"]]$final == V[["dropmonths|full"]]$final) &&
                      (V[["tiebreak|post2015"]]$final == V[["dropmonths|post2015"]]$final)
say("  ★ 두 수리 판정 일치: %s", R$repair_agreement)

# ── 3. 앵커 위치 + 검정력 라벨 ──────────────────────────────────────────────
say("=== 3. 앵커 위치 (부모 중립 Q01) + 검정력 ===")
anch <- list()
for (wn in c("full","post2015")) {
  Xw <- D[Date >= WINS[[wn]] & is.finite(q01_n) & is.finite(act)]
  s <- prof2(Xw, "q01_n", "random"); s <- s[nn >= MIN_NAMES]
  q <- 100*12*c(mean(s$q1),mean(s$q2),mean(s$q3),mean(s$q4),mean(s$q5))
  b <- battery(s$q5 - s$q3, "anchor")
  ce <- CELLS[[paste("tiebreak","A","neutral",wn, sep="|")]]
  pop <- sort(sapply(ce$per_signal, function(z) z$gap_q5_q3$ann_pct))
  anch[[wn]] <- list(quintile_ann_pct = q, ew_relative_ann_pct = q - mean(q),
    gap = b, rank_ascending = sum(pop < b$ann_pct) + 1L, n_pop = length(pop),
    pop_median = median(pop), pop_min = min(pop), pop_max = max(pop), pop_sorted = pop)
  say("  %-9s 앵커 EW-상대 [%s] 갭 %+.2f%% (t %+.2f, 보수적 p %.3f) → 모집단 %d개 중 %d번째로 작음 (중앙 %+.2f)",
      wn, paste(sprintf("%+.2f", q-mean(q)), collapse=" "), b$ann_pct, b$t_cited, b$p_conservative,
      length(pop), anch[[wn]]$rank_ascending, median(pop))
}
R$anchor <- anch
pw <- list()
for (nm in c("tiebreak|A|neutral|full","tiebreak|A|raw|full","tiebreak|A|neutral|post2015","tiebreak|A|raw|post2015")) {
  p <- CELLS[[nm]]$pooled
  v <- verdict_with_power(observed_t = abs(p$t_cited), observed_monthly = abs(p$mean_monthly),
                          n = p$n, t_threshold = 2.0, sd_monthly = SPREAD_SD_MONTHLY_25EW)
  pw[[nm]] <- list(verdict = v$verdict, implied_t_threshold = v$implied_t_threshold,
                   required_annual_pct = 100*v$required$required_annual,
                   bar_restates_t = v$bar_restates_t, observed_ann_pct = p$ann_pct, t = p$t_cited)
  say("  검정력 %-30s implied_t %.2f (2.0~3.2 이면 재진술) · 필요 연 %.2f%% · %s",
      nm, v$implied_t_threshold, 100*v$required$required_annual, v$verdict)
}
R$power_labels <- pw
R$test_count <- list(cells = length(CELLS), per_signal_gaps = length(CELLS)*10,
  conditioning_tests = 6L, primary_prereg = 1L,
  note = "사전등록 주판정 = tiebreak|A 프레임 전표본 1건. 나머지는 강건성·서술")

saveRDS(list(cells = CELLS, anchor = anch), file.path(OUT, "correct_p5.rds"))
write_json(R, file.path(OUT, "measurement_corrected.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== 수리 후 측정 완료 → measurement_corrected.json · 주판정 = %s ===", R$primary_verdict)
