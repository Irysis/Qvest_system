# =============================================================================
# measure_p2.R — NP-A 본 측정 (preregistration.json 고정 후)
#   판정 = (i) 형태 계수 count  (ii) 신호간 평균 월계열 pooled  — 사전등록대로
#   ★ 첫 출력 = 입력 형태 실측. NW lag 는 ACF 실측에 따라 규칙적용.
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/measure_p2.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
IN3 <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p2] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/required_effect_size.R")
set.seed(20260809L)

PRE <- fromJSON(file.path(OUT, "preregistration.json"))
P0  <- readRDS(file.path(IN3, "p0_panels.rds"))
P1p <- readRDS(file.path(IN3, "prereg_p1.rds"))
SPN <- readRDS(file.path(OUT, "signal_panel_neutral.rds"))   # Date,Ticker,Factor_Name,z,zn

R <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
          metric_type = "canonical_screen / diag",
          attributed_to = "WT-D20260808_003 next_probe NP-A")

# ── 0. 입력 형태 실측 ────────────────────────────────────────────────────────
shape <- function(d, nm) { d <- as.data.table(d); ud <- sort(unique(as.Date(d$Date)))
  gap <- median(as.numeric(diff(ud)))
  unit <- if (gap <= 5) "DAILY" else if (gap <= 45) "MONTHLY" else "LOWER"
  say("INPUT %-24s nrow=%8d 관측단위=%s(간격중앙 %.1f일) n_date=%d %s~%s",
      nm, nrow(d), unit, gap, length(ud), min(ud), max(ud))
  list(nrow = nrow(d), unit = unit, gap_median_days = gap, n_date = length(ud)) }
sh <- list(signal_panel = shape(SPN, "SPN(신호패널 long)"),
           frameA = shape(P1p$D, "P1$D(프레임A)"))
D <- copy(P1p$D)
ACT_A <- D[, .(Date, Ticker, act)]
ACT_B <- merge(P0$E[, .(Date, Ticker)], P0$returns_dt, by = c("Date","Ticker"))
ACT_B <- merge(ACT_B, P0$bench_dt, by = "Date")[, .(Date, Ticker, act = Ret_1m - BM_Ret)]
sh$frameB <- shape(ACT_B, "프레임B(E∩수익)")
R$input_shapes <- sh
say("판정 계열 관측단위 = MONTHLY (월별 횡단면 평균의 시계열) — NW lag 는 월 기준")

# ── 통계 도구 ────────────────────────────────────────────────────────────────
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]),
                           error = function(e) NA_real_) }
acf1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_); as.numeric(acf(x, lag.max = 1, plot = FALSE)$acf[2]) }
# 이동블록 부트스트랩 (block=12, B=2000) — 자기상관 내성 CI (사전등록 주추론)
mbb <- function(x, block = 12L, B = 2000L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 24L) return(c(NA_real_, NA_real_, NA_real_))
  nb <- ceiling(n/block); starts_max <- n - block + 1L
  m <- replicate(B, { s <- sample.int(starts_max, nb, replace = TRUE)
    idx <- as.vector(outer(0:(block-1L), s, function(a,b) b + a)); mean(x[idx[seq_len(n)]]) })
  p2 <- 2*min(mean(m <= 0), mean(m >= 0))
  c(quantile(m, 0.025, names = FALSE), quantile(m, 0.975, names = FALSE), min(1, p2))
}
stride_mean <- function(x, k = 12L) { x <- x[is.finite(x)]
  s <- sapply(seq_len(k), function(o) { v <- x[seq(o, length(x), by = k)]; if (length(v) >= 8L) mean(v) else NA_real_ })
  s[is.finite(s)] }

# 부모 prof() 원문 이식 (재구현 금지) — score 컬럼만 매개변수화
prof_parent <- function(X, zc) {
  d <- X[is.finite(get(zc)) & is.finite(act)]
  s <- d[, { qr <- frank(get(zc))/.N
    .(q1 = mean(act[qr <= 0.2]), q2 = mean(act[qr > 0.2 & qr <= 0.4]), q3 = mean(act[qr > 0.4 & qr <= 0.6]),
      q4 = mean(act[qr > 0.6 & qr <= 0.8]), q5 = mean(act[qr > 0.8]), nn = .N) }, by = Date]
  s
}

# ── 갭 계열 배터리 (NW lag 규칙 = ACF 실측 종속) ─────────────────────────────
battery <- function(x, tag = "") {
  x <- x[is.finite(x)]; r1 <- acf1(x)
  t3 <- nw_t(x, 3L); t12 <- nw_t(x, 12L)
  bb <- mbb(x); sm <- stride_mean(x, 12L)
  cite_lag <- if (is.finite(r1) && r1 > 0.30) 12L else 3L
  list(n = length(x), mean_monthly = mean(x), ann_pct = 100*12*mean(x),
       acf_r1 = r1, t_nw_lag3 = t3, t_nw_lag12 = t12,
       cited_lag = cite_lag, t_cited = if (cite_lag == 12L) t12 else t3,
       boot_ci_ann_pct = 100*12*bb[1:2], boot_p2 = bb[3],
       sign_neg_pct = 100*mean(x < 0),
       stride12_n = length(sm), stride12_mean_ann_pct = 100*12*mean(sm),
       stride12_t = if (length(sm) >= 3L) as.numeric(t.test(sm)$statistic) else NA_real_,
       tag = tag)
}

MIN_NAMES <- 30L   # 사전등록 월 문턱
SIGS <- sort(unique(SPN$Factor_Name))
WINS <- list(full = as.Date("1900-01-01"), post2015 = as.Date("2015-01-01"))

run_cell <- function(frame, arm, win) {
  ACT <- if (frame == "A") ACT_A else ACT_B
  zc  <- if (arm == "raw") "z" else "zn"
  cut <- WINS[[win]]
  res <- list(); gaps <- list()
  for (fn in SIGS) {
    X <- merge(SPN[Factor_Name == fn, .(Date, Ticker, z, zn)], ACT, by = c("Date","Ticker"))
    X <- X[Date >= cut & is.finite(get(zc)) & is.finite(act)]
    s <- prof_parent(X, zc)
    s <- s[nn >= MIN_NAMES]
    if (nrow(s) < 24L) next
    q <- 100*12*c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
    ewrel <- q - mean(q)
    g <- s$q5 - s$q3                      # 갭 계열 (월)
    te <- s$q5 - rowMeans(s[, .(q1,q2,q3,q4,q5)])   # 최상위 − EW 유니버스
    bg <- battery(g, "gap_q5_q3"); bt <- battery(te, "top_vs_ew")
    res[[fn]] <- list(
      n_month = nrow(s), avg_names = mean(s$nn),
      quintile_ann_pct = q, ew_relative_ann_pct = ewrel,
      profile_spearman_vs_rank = as.numeric(cor(q, 1:5, method = "spearman")),
      argmax_quintile = which.max(q),
      hump_weak = q[5] < q[3], hump_strict = which.max(q) %in% 2:4, top_below_ew = ewrel[5] < 0,
      gap_q5_q3 = bg, top_vs_ew = bt)
    gaps[[fn]] <- data.table(Date = s$Date, fn = fn, g = g)
  }
  # pooled: 월별 신호간 평균 갭
  G <- rbindlist(gaps)
  P <- G[, .(g = mean(g), k = .N), by = Date][order(Date)]
  pooled <- battery(P$g, "pooled_gap")
  pooled$avg_signals_per_month <- mean(P$k)
  # 연속 시대축 (분할 금지) — 갭 ~ 시간지수
  P[, tt := as.numeric(Date - min(Date))/365.25]
  lmf <- lm(g ~ tt, data = P)
  ct <- lmtest::coeftest(lmf, vcov. = sandwich::NeweyWest(lmf, lag = pooled$cited_lag, prewhite = FALSE))
  era <- list(slope_ann_pct_per_year = 100*12*unname(ct[2,1]), t = unname(ct[2,3]),
              intercept_ann_pct = 100*12*unname(ct[1,1]))
  nh <- sum(sapply(res, function(z) isTRUE(z$hump_weak)))
  ns <- sum(sapply(res, function(z) isTRUE(z$hump_strict)))
  nt <- sum(sapply(res, function(z) isTRUE(z$top_below_ew)))
  k  <- length(res)
  bt_ <- binom.test(nh, k, 0.5)
  count <- list(n_signals = k, hump_weak = nh, hump_strict = ns, top_below_ew = nt,
                binom_p_hump_weak = unname(bt_$p.value),
                binom_note = "신호간 독립 위배(모두 KR long-only) — 서술용, 단독 판정 근거 아님")
  say("  [%s|%s|%s] 신호 %d개 · hump_weak %d/%d · strict %d · top<EW %d | pooled 갭 연 %+.3f%% ACF %.2f t(lag%d) %+.2f boot CI[%+.3f,%+.3f] p=%.3f",
      frame, arm, win, k, nh, k, ns, nt, pooled$ann_pct, pooled$acf_r1, pooled$cited_lag,
      pooled$t_cited, pooled$boot_ci_ann_pct[1], pooled$boot_ci_ann_pct[2], pooled$boot_p2)
  list(per_signal = res, pooled = pooled, era_continuous = era, count = count)
}

say("=== 1. 셀 실행 (프레임 A/B × arm raw/neutral × 창 full/post2015) ===")
CELLS <- list()
for (fr in c("A","B")) for (ar in c("raw","neutral")) for (wn in c("full","post2015"))
  CELLS[[paste(fr, ar, wn, sep = "_")]] <- run_cell(fr, ar, wn)
R$cells <- CELLS

# ── 2. 앵커: 부모의 정확한 arm (중립 Q01) 재현 ───────────────────────────────
say("=== 2. 앵커 — 부모 중립 Q01 (q01_n) 동일 프레임 재측정 ===")
anch <- list()
for (wn in c("full","post2015")) {
  X <- D[Date >= WINS[[wn]]]
  s <- prof_parent(X, "q01_n"); s <- s[nn >= MIN_NAMES]
  q <- 100*12*c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
  g <- s$q5 - s$q3
  anch[[wn]] <- list(quintile_ann_pct = q, ew_relative_ann_pct = q - mean(q),
                     hump_weak = q[5] < q[3], argmax_quintile = which.max(q),
                     gap_q5_q3 = battery(g, "anchor_gap"), n_month = nrow(s))
  say("  Q01_EB_NEU %-9s EW-상대 [%s] hump=%s 갭 연 %+.3f%% (ACF %.2f, t(lag%d) %+.2f)",
      wn, paste(sprintf("%+.2f", q - mean(q)), collapse = " "), q[5] < q[3],
      anch[[wn]]$gap_q5_q3$ann_pct, anch[[wn]]$gap_q5_q3$acf_r1,
      anch[[wn]]$gap_q5_q3$cited_lag, anch[[wn]]$gap_q5_q3$t_cited)
}
R$anchor_q01_neutral <- anch

# ── 3. 검정력 라벨 (외부기준 + arm 자신 = 재진술 라벨) ───────────────────────
say("=== 3. 검정력 라벨 — implied_t_threshold 확인 의무 ===")
pw <- list()
for (cn in c("A_raw_full","A_neutral_full","A_raw_post2015","A_neutral_post2015")) {
  p <- CELLS[[cn]]$pooled
  se_arm <- abs(p$mean_monthly)/abs(p$t_cited)
  v_ext <- verdict_with_power(observed_t = p$t_cited, observed_monthly = p$mean_monthly,
                              n = p$n, t_threshold = 2.0, sd_monthly = SPREAD_SD_MONTHLY_25EW)
  # arm 자신의 sd 를 넣으면 required = 2.0*1.25*se_iid 가 되어 바가 t 검정의 재진술로 퇴화한다.
  # 수치를 새로 만들지 않고 se_arm 만 기록해 그 사실을 투명하게 남긴다.
  pw[[cn]] <- list(external = list(verdict = v_ext$verdict, implied_t_threshold = v_ext$implied_t_threshold,
                                   required_annual_pct = 100*v_ext$required$required_annual,
                                   bar_restates_t = v_ext$bar_restates_t,
                                   negative_powered_reachable = v_ext$negative_powered_reachable),
                   observed = list(ann_pct = p$ann_pct, t_cited = p$t_cited, n = p$n, se_arm_monthly = se_arm))
  say("  %-20s 외부바 필요 연 %+.2f%% · implied_t %.2f · verdict %s%s",
      cn, 100*v_ext$required$required_annual, v_ext$implied_t_threshold, v_ext$verdict,
      if (isTRUE(v_ext$bar_restates_t)) "  ★바=t 재진술(정보 없음)" else "")
}
R$power_labels <- pw

# ── 4. 사전등록 판정 규칙 적용 ───────────────────────────────────────────────
say("=== 4. 사전등록 판정 규칙 적용 ===")
verdict_of <- function(cell) {
  k <- cell$count$n_signals; nh <- cell$count$hump_weak
  pooled_neg_sig <- (cell$pooled$ann_pct < 0) && (cell$pooled$boot_ci_ann_pct[2] < 0)
  if (nh >= ceiling(2*k/3) && pooled_neg_sig) "COMMON"
  else if (nh <= floor(k/3)) "Q01_SPECIFIC"
  else "MIXED"
}
V <- list()
for (wn in c("full","post2015")) {
  vr <- verdict_of(CELLS[[paste0("A_raw_", wn)]]); vn <- verdict_of(CELLS[[paste0("A_neutral_", wn)]])
  vBr<- verdict_of(CELLS[[paste0("B_raw_", wn)]]); vBn<- verdict_of(CELLS[[paste0("B_neutral_", wn)]])
  agree_arm <- (vr == vn); agree_frame <- (vr == vBr) && (vn == vBn)
  fin <- if (!agree_arm || !agree_frame) "MIXED" else vr
  V[[wn]] <- list(A_raw = vr, A_neutral = vn, B_raw = vBr, B_neutral = vBn,
                  arms_agree = agree_arm, frames_agree = agree_frame, final = fin)
  say("  %-9s A_raw=%s A_neu=%s B_raw=%s B_neu=%s → arm일치 %s · frame일치 %s ⇒ %s",
      wn, vr, vn, vBr, vBn, agree_arm, agree_frame, fin)
}
R$verdict <- V
R$primary_verdict <- V$full$final
R$inherited_window_verdict <- V$post2015$final

saveRDS(list(cells = CELLS, anchor = anch), file.path(OUT, "measure_p2.rds"))
write_json(R, file.path(OUT, "measurement.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== 측정 완료 → measurement.json · 주판정(전표본) = %s ===", R$primary_verdict)
