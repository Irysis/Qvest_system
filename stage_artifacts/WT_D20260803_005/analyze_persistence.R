# =============================================================================
# analyze_persistence.R — WT-D20260803_005 (FQ-131) Step C: 자격 부호 지속성 분석
#   입력 : canonical_pool.rds (Step B) + pool_meta.rds + registry_labels.rds
#   사전등록: preregistration.json (측정 전 고정 — 창 격자/정의/판별 변경 금지)
#
#   산출: (a) 부호 유지 기간 분포 + 반감기  (b) |t_k| → 다음 창 부호 예측력
#         (c) family / 회전율 / cap-tier 조건별 안정성
#         + 상수-알파 잡음 귀무분포 + 위반 주입 2종
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/analyze_persistence.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005C] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/backtest_result_contract.R")   # .nw_t_mean
nw_t <- function(x, lag = 3L) .nw_t_mean(x, lag = lag)

CP   <- readRDS(file.path(OUT, "canonical_pool.rds"))
META <- readRDS(file.path(OUT, "pool_meta.rds"))
LAB  <- readRDS(file.path(OUT, "registry_labels.rds"))
RES  <- CP$res; SUMM <- CP$summary; CAP <- CP$cap
say("입력: %d factor canonical 시계열", length(RES))

# ── 1. active 행렬 정렬 ─────────────────────────────────────────────────────
DATES <- sort(unique(unlist(lapply(RES, function(x) as.character(x$date)))))
DATES <- as.Date(DATES)
A <- matrix(NA_real_, nrow = length(DATES), ncol = length(RES),
            dimnames = list(as.character(DATES), names(RES)))
for (f in names(RES)) {
  r <- RES[[f]]; A[as.character(r$date), f] <- r$active
}
say("active 행렬: %d월 x %d factor | 완전관측 factor %d",
    nrow(A), ncol(A), sum(colSums(is.na(A)) == 0L))

# ── 2. 중복 제거 (사전등록: active 시계열 상관 >= 0.99, 알파벳 tie-break) ───
CM <- suppressWarnings(cor(A, use = "pairwise.complete.obs"))
CM[!is.finite(CM)] <- 0
DUP_THR <- 0.99
ord <- sort(colnames(A))
keep <- character(0); dropped <- data.table()
for (f in ord) {
  if (length(keep) == 0L) { keep <- f; next }
  mx <- max(abs(CM[f, keep]), na.rm = TRUE)
  if (mx >= DUP_THR) {
    rep_f <- keep[which.max(abs(CM[f, keep]))]
    dropped <- rbind(dropped, data.table(dropped_factor = f, kept_rep = rep_f, cor = mx))
  } else keep <- c(keep, f)
}
say("중복 제거: %d → %d factor (|cor(active)| >= %.2f 제거 %d건)",
    ncol(A), length(keep), DUP_THR, nrow(dropped))
if (nrow(dropped)) print(head(dropped[order(-cor)], 15))
A <- A[, keep, drop = FALSE]
POOL <- keep

# ── 3. 창 격자 (사전등록: 비중첩, 표본 끝 정렬) ─────────────────────────────
make_bounds <- function(n, W) {
  b <- list(); e <- n
  while (e - W + 1L >= 1L) { b[[length(b) + 1L]] <- c(e - W + 1L, e); e <- e - W }
  rev(b)
}
window_t <- function(vec, bounds, min_obs) {
  vapply(bounds, function(ix) {
    x <- vec[ix[1]:ix[2]]; xv <- x[is.finite(x)]
    if (length(xv) < min_obs || length(xv) / (ix[2] - ix[1] + 1L) < 0.90) return(NA_real_)
    nw_t(xv)
  }, numeric(1))
}
GRIDS <- list(primary = list(W = 60L, min_obs = 24L),
              rob36   = list(W = 36L, min_obs = 24L),
              rob24   = list(W = 24L, min_obs = 20L))

build_T <- function(W, min_obs) {
  bnd <- make_bounds(nrow(A), W)
  TT <- vapply(POOL, function(f) window_t(A[, f], bnd, min_obs), numeric(length(bnd)))
  if (is.null(dim(TT))) TT <- matrix(TT, nrow = length(bnd), dimnames = list(NULL, POOL))
  list(t = TT, bounds = bnd,
       from = DATES[vapply(bnd, `[`, integer(1), 1)],
       to   = DATES[vapply(bnd, `[`, integer(1), 2)])
}
TG <- lapply(GRIDS, function(g) build_T(g$W, g$min_obs))
for (nm in names(TG)) say("격자 %s: 창 %d개 (%s ~ %s) | 유효 셀 %d/%d",
  nm, length(TG[[nm]]$bounds), TG[[nm]]$from[1], TG[[nm]]$to[length(TG[[nm]]$to)],
  sum(is.finite(TG[[nm]]$t)), length(TG[[nm]]$t))

# ── 4. 지속성 통계 ─────────────────────────────────────────────────────────
pairs_of <- function(TT) {
  K <- nrow(TT)
  rbindlist(lapply(seq_len(K - 1L), function(k) {
    tk <- TT[k, ]; tn <- TT[k + 1L, ]
    ok <- is.finite(tk) & is.finite(tn)
    if (!any(ok)) return(NULL)
    data.table(Factor_Name = colnames(TT)[ok], k = k, t_k = tk[ok], t_next = tn[ok])
  }))
}
add_rel <- function(P, TT) {
  era <- P[, .(mu_k = mean(t_k)), by = k]
  eran <- P[, .(mu_n = mean(t_next)), by = k]
  P <- merge(merge(P, era, by = "k"), eran, by = "k")
  P[, `:=`(t_k_rel = t_k - mu_k, t_next_rel = t_next - mu_n)][]
}
PR <- lapply(TG, function(g) add_rel(pairs_of(g$t), g$t))

boot_p <- function(P, col_k = "t_k", col_n = "t_next", B = 2000L, seed = 20260803L) {
  set.seed(seed)
  fs <- unique(P$Factor_Name); n <- length(fs)
  agree_all <- sign(P[[col_k]]) == sign(P[[col_n]])
  base <- mean(agree_all)
  bs <- vapply(seq_len(B), function(b) {
    ff <- sample(fs, n, replace = TRUE)
    idx <- unlist(lapply(ff, function(x) which(P$Factor_Name == x)))
    mean(sign(P[[col_k]][idx]) == sign(P[[col_n]][idx]))
  }, numeric(1))
  c(p = base, lo = unname(quantile(bs, 0.025)), hi = unname(quantile(bs, 0.975)))
}
PP  <- lapply(PR, boot_p)
PPR <- lapply(PR, function(P) boot_p(P, "t_k_rel", "t_next_rel"))
for (nm in names(PP)) say("P_persist[%s] 절대 %.3f [%.3f, %.3f] (n=%d) | 상대(era-demean) %.3f [%.3f, %.3f]",
  nm, PP[[nm]]["p"], PP[[nm]]["lo"], PP[[nm]]["hi"], nrow(PR[[nm]]),
  PPR[[nm]]["p"], PPR[[nm]]["lo"], PPR[[nm]]["hi"])

# ── 5. run length + 반감기 (KM, 우측절단 처리) ──────────────────────────────
runs_of <- function(TT) {
  rbindlist(lapply(colnames(TT), function(f) {
    s <- sign(TT[, f]); s[!is.finite(s)] <- NA
    if (all(is.na(s))) return(NULL)
    # 연속 유효 구간만
    r <- rle(ifelse(is.na(s), NA_real_, s))
    len <- r$lengths; val <- r$values
    idx_end <- cumsum(len); idx_start <- idx_end - len + 1L
    keep <- !is.na(val)
    if (!any(keep)) return(NULL)
    data.table(Factor_Name = f, len = len[keep], sign = val[keep],
               censored = (idx_start[keep] == 1L) | (idx_end[keep] == length(s)))
  }))
}
km_median <- function(len, censored) {
  # 이산 KM: 사건 = 부호 전환(비절단 run 종료). 절단 run은 우측절단.
  tt <- sort(unique(len)); n <- length(len); S <- 1; out <- data.table()
  at_risk <- n
  for (u in tt) {
    d <- sum(len == u & !censored); c_ <- sum(len == u & censored)
    if (at_risk > 0) S <- S * (1 - d / at_risk)
    out <- rbind(out, data.table(len = u, d = d, cens = c_, at_risk = at_risk, S = S))
    at_risk <- at_risk - d - c_
  }
  med <- out[S <= 0.5, min(len)]
  list(tbl = out, median_windows = if (is.finite(med)) med else NA_real_)
}
RUN <- lapply(TG, function(g) runs_of(g$t))
for (nm in names(RUN)) {
  R0 <- RUN[[nm]]; W <- GRIDS[[nm]]$W
  km <- km_median(R0$len, R0$censored)
  comp <- R0[censored == FALSE]
  say("run[%s] W=%dm: 전체 %d run (비절단 %d) | 비절단 중앙값 %.1f창(%.0f개월) | KM 중앙 %s창 | 평균 %.2f창",
      nm, W, nrow(R0), nrow(comp),
      if (nrow(comp)) as.numeric(median(comp$len)) else NA_real_,
      if (nrow(comp)) as.numeric(median(comp$len)) * W else NA_real_,
      ifelse(is.na(km$median_windows), "NA(도달못함)", as.character(km$median_windows)),
      mean(R0$len))
  RUN[[nm]] <- list(runs = R0, km = km)
}
# 기하 반감기 (P_persist 상수 가정): S(L)=p^(L-1) → median L = 1 + ln .5 / ln p
geo_half <- function(p, W) if (p <= 0 || p >= 1) NA_real_ else (1 + log(0.5)/log(p)) * W
for (nm in names(PP)) say("기하 반감기[%s]: p=%.3f → %.1f 개월 (창 %d개월 단위)",
  nm, PP[[nm]]["p"], geo_half(PP[[nm]]["p"], GRIDS[[nm]]$W), GRIDS[[nm]]$W)

# ── 6. 상수-알파 잡음 귀무분포 (block bootstrap, 시간순서 파괴) ─────────────
null_p <- function(W, min_obs, B = 500L, block = 12L, seed = 20260803L) {
  set.seed(seed)
  n <- nrow(A); bnd <- make_bounds(n, W)
  vapply(seq_len(B), function(b) {
    AB <- matrix(NA_real_, nrow = n, ncol = ncol(A), dimnames = dimnames(A))
    nb <- ceiling(n / block)
    starts <- sample.int(n, nb, replace = TRUE)
    idx <- unlist(lapply(starts, function(s) ((s - 1L) + seq_len(block) - 1L) %% n + 1L))[seq_len(n)]
    AB[] <- A[idx, , drop = FALSE]
    TT <- vapply(colnames(AB), function(f) window_t(AB[, f], bnd, min_obs), numeric(length(bnd)))
    if (is.null(dim(TT))) TT <- matrix(TT, nrow = length(bnd), dimnames = list(NULL, colnames(AB)))
    P <- pairs_of(TT)
    if (is.null(P) || !nrow(P)) return(NA_real_)
    mean(sign(P$t_k) == sign(P$t_next))
  }, numeric(1))
}
NULLD <- lapply(names(GRIDS), function(nm) null_p(GRIDS[[nm]]$W, GRIDS[[nm]]$min_obs))
names(NULLD) <- names(GRIDS)
for (nm in names(NULLD)) {
  nd <- NULLD[[nm]][is.finite(NULLD[[nm]])]
  say("귀무(상수알파)[%s]: 평균 %.3f [%.3f, %.3f] | 관측 %.3f | 관측-귀무 %+.3f (귀무분포 내 백분위 %.1f%%)",
      nm, mean(nd), quantile(nd, .025), quantile(nd, .975), PP[[nm]]["p"],
      PP[[nm]]["p"] - mean(nd), 100 * mean(nd <= PP[[nm]]["p"]))
}

# ── 7. (b) |t_k| → 다음 창 예측력 ──────────────────────────────────────────
bin_tab <- function(P, col_k = "t_k", col_n = "t_next") {
  Q <- copy(P)
  Q[, absk := abs(get(col_k))]
  Q[, bin := cut(absk, c(-Inf, 0.5, 1, 2, Inf),
                 labels = c("[0,0.5)", "[0.5,1)", "[1,2)", "[2,inf)"), right = FALSE)]
  Q[, .(n = .N, p_persist = mean(sign(get(col_k)) == sign(get(col_n))),
        mean_t_next_signed = mean(sign(get(col_k)) * get(col_n))), by = bin][order(bin)]
}
cl_lm <- function(P, yv, xv) {
  fit <- lm(P[[yv]] ~ P[[xv]])
  g <- unique(P$Factor_Name); G <- length(g)
  X <- model.matrix(fit); u <- residuals(fit)
  bread <- solve(crossprod(X))
  meat <- matrix(0, ncol(X), ncol(X))
  for (gg in g) {
    ix <- which(P$Factor_Name == gg)
    sg <- colSums(X[ix, , drop = FALSE] * u[ix])
    meat <- meat + tcrossprod(sg)
  }
  n <- nrow(X); k <- ncol(X)
  adj <- (G / (G - 1)) * ((n - 1) / (n - k))
  V <- bread %*% (adj * meat) %*% bread
  b <- coef(fit)[2]; se <- sqrt(V[2, 2])
  c(b = unname(b), se = unname(se), t = unname(b / se),
    p = unname(2 * pt(-abs(b / se), df = G - 1)), n = n, n_clusters = G,
    r2 = summary(fit)$r.squared)
}
auc_of <- function(score, lab) {
  lab <- as.integer(lab)
  if (length(unique(lab)) < 2L) return(NA_real_)
  r <- rank(score); n1 <- sum(lab == 1L); n0 <- sum(lab == 0L)
  (sum(r[lab == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
BIN <- lapply(PR, bin_tab)
BINR <- lapply(PR, function(P) bin_tab(P, "t_k_rel", "t_next_rel"))
LM  <- lapply(PR, function(P) cl_lm(P, "t_next", "t_k"))
LMR <- lapply(PR, function(P) cl_lm(P, "t_next_rel", "t_k_rel"))
AUC <- vapply(PR, function(P) auc_of(P$t_k, P$t_next > 0), numeric(1))
AUCR <- vapply(PR, function(P) auc_of(P$t_k_rel, P$t_next_rel > 0), numeric(1))
for (nm in names(PR)) {
  say("--- (b) 격자 %s ---", nm)
  print(BIN[[nm]])
  say("level reg 절대: b=%+.4f (SE %.4f, t %+.2f, p %.4f, R2 %.4f, clusters %d)",
      LM[[nm]]["b"], LM[[nm]]["se"], LM[[nm]]["t"], LM[[nm]]["p"], LM[[nm]]["r2"],
      as.integer(LM[[nm]]["n_clusters"]))
  say("level reg 상대: b=%+.4f (SE %.4f, t %+.2f, p %.4f) | AUC 절대 %.3f / 상대 %.3f",
      LMR[[nm]]["b"], LMR[[nm]]["se"], LMR[[nm]]["t"], LMR[[nm]]["p"], AUC[nm], AUCR[nm])
}

# ── 8. 위반 주입 ───────────────────────────────────────────────────────────
#  LEAK_OVERLAP: 예측자 t_k를 다음 창 첫 12개월까지 연장해 계산 (의도적 미래 중첩)
#  LEAK_FULL   : 예측자를 전기간 PORT_t로 대체
inject <- function(W, min_obs, lead = 12L) {
  bnd <- make_bounds(nrow(A), W)
  K <- length(bnd)
  base <- vapply(POOL, function(f) window_t(A[, f], bnd, min_obs), numeric(K))
  if (is.null(dim(base))) base <- matrix(base, nrow = K, dimnames = list(NULL, POOL))
  bnd_leak <- lapply(seq_len(K - 1L), function(k) c(bnd[[k]][1], min(bnd[[k]][2] + lead, nrow(A))))
  leak <- vapply(POOL, function(f) window_t(A[, f], bnd_leak, min_obs), numeric(K - 1L))
  if (is.null(dim(leak))) leak <- matrix(leak, nrow = K - 1L, dimnames = list(NULL, POOL))
  full_t <- vapply(POOL, function(f) nw_t(A[is.finite(A[, f]), f]), numeric(1))
  L <- rbindlist(lapply(seq_len(K - 1L), function(k) {
    tk <- base[k, ]; tl <- leak[k, ]; tn <- base[k + 1L, ]
    ok <- is.finite(tk) & is.finite(tl) & is.finite(tn)
    if (!any(ok)) return(NULL)
    data.table(Factor_Name = POOL[ok], k = k, t_k = tk[ok], t_leak = tl[ok],
               t_next = tn[ok], t_full = full_t[POOL[ok]])
  }))
  L
}
INJ <- inject(GRIDS$primary$W, GRIDS$primary$min_obs)
inj_stat <- function(L, col) {
  p <- mean(sign(L[[col]]) == sign(L$t_next))
  lmv <- cl_lm(L, "t_next", col)
  a <- auc_of(L[[col]], L$t_next > 0)
  bt <- { Q <- copy(L); Q[, ab := abs(get(col))]
          Q[ab >= 2, mean(sign(get(col)) == sign(t_next))] }
  c(p_persist = p, b = lmv["b"], t = lmv["t"], p_val = lmv["p"], auc = a, top_bin_p = bt)
}
IS_BASE <- inj_stat(INJ, "t_k"); IS_LEAK <- inj_stat(INJ, "t_leak"); IS_FULL <- inj_stat(INJ, "t_full")
INJTAB <- data.table(arm = c("BASE(비중첩)", "LEAK_OVERLAP(+12m)", "LEAK_FULL(전기간)"),
  rbind(IS_BASE, IS_LEAK, IS_FULL))
say("--- 위반 주입 (primary W=60) ---"); print(INJTAB)
fired <- (IS_LEAK["p_persist"] > IS_BASE["p_persist"] + 0.02) ||
         (IS_FULL["p_persist"] > IS_BASE["p_persist"] + 0.02)
say("주입 판정: %s (LEAK_OVERLAP Δp %+.3f / LEAK_FULL Δp %+.3f)",
    ifelse(fired, "FIRED — 비중첩 규율이 실구속", "NOT FIRED — 측정 검사력 부족 의심"),
    IS_LEAK["p_persist"] - IS_BASE["p_persist"], IS_FULL["p_persist"] - IS_BASE["p_persist"])

# ── 9. 조건부 분해 (family / 회전율 / cap-tier) ────────────────────────────
COND <- merge(data.table(Factor_Name = POOL),
              LAB[, .(Factor_Name, family, turnover_profile, capacity, corr_group, evidence)],
              by = "Factor_Name", all.x = TRUE)
COND <- merge(COND, SUMM[, .(Factor_Name, turnover_annual, port_t_full, net_sr, n_months)],
              by = "Factor_Name", all.x = TRUE)
COND <- merge(COND, CAP, by = "Factor_Name", all.x = TRUE)
COND[, to_tercile := cut(turnover_annual, quantile(turnover_annual, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                         labels = c("TO_low", "TO_mid", "TO_high"), include.lowest = TRUE)]
COND[, cap_tercile := cut(hold_size_pct, quantile(hold_size_pct, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                          labels = c("CAP_small", "CAP_mid", "CAP_large"), include.lowest = TRUE)]
P1 <- merge(PR$primary, COND, by = "Factor_Name", all.x = TRUE)
cond_tab <- function(P, byv) {
  x <- P[!is.na(get(byv)), .(n_pairs = .N, n_factors = uniqueN(Factor_Name),
      p_persist = mean(sign(t_k) == sign(t_next)),
      p_persist_rel = mean(sign(t_k_rel) == sign(t_next_rel)),
      mean_abs_t = mean(abs(t_k))), by = byv]
  setorderv(x, "p_persist", -1)[]
}
say("--- (c) family 별 ---"); print(cond_tab(P1, "family"))
say("--- (c) 회전율 tercile ---"); print(cond_tab(P1, "to_tercile"))
say("--- (c) cap-tier tercile ---"); print(cond_tab(P1, "cap_tercile"))
say("--- (c) turnover_profile(registry) ---"); print(cond_tab(P1, "turnover_profile"))
# family 차이 유의성: factor-clustered bootstrap으로 최고-최저 family 차이 CI
fam_boot <- function(P, B = 1000L, seed = 20260803L) {
  set.seed(seed); fams <- P[!is.na(family), unique(family)]
  fs <- unique(P$Factor_Name)
  M <- matrix(NA_real_, B, length(fams), dimnames = list(NULL, fams))
  for (b in seq_len(B)) {
    ff <- sample(fs, length(fs), replace = TRUE)
    idx <- unlist(lapply(ff, function(x) which(P$Factor_Name == x)))
    Q <- P[idx]
    agg <- Q[!is.na(family), .(p = mean(sign(t_k) == sign(t_next))), by = family]
    M[b, agg$family] <- agg$p
  }
  M
}
FB <- fam_boot(P1)
famci <- data.table(family = colnames(FB),
                    lo = apply(FB, 2, quantile, 0.025, na.rm = TRUE),
                    hi = apply(FB, 2, quantile, 0.975, na.rm = TRUE))
print(merge(cond_tab(P1, "family"), famci, by = "family")[order(-p_persist)])

# ── 10. 판별 판정 ──────────────────────────────────────────────────────────
prim_W <- GRIDS$primary$W
km_med <- RUN$primary$km$median_windows
comp_med <- RUN$primary$runs[censored == FALSE, if (.N) median(len) else NA_real_]
disc_a <- (is.finite(comp_med) && comp_med >= 2) && (PP$primary["p"] >= 0.65)
top_bin_p <- BIN$primary[bin == "[2,inf)", p_persist]
disc_b <- (LM$primary["b"] > 0) && (LM$primary["p"] < 0.05) &&
          (length(top_bin_p) && is.finite(top_bin_p) && top_bin_p >= 0.65)
say("=== 판별 ===")
say("(a) 운용가능 지속성: %s — 비절단 run 중앙 %.1f창 / P_persist %.3f (기준 >=2창 & >=0.65)",
    ifelse(disc_a, "PASS", "FAIL"), comp_med, PP$primary["p"])
say("(b) 게이트 원리적 가능성: %s — b=%+.4f (p %.4f), 최상위 |t| bin persistence %s (기준 b>0 & p<0.05 & bin>=0.65)",
    ifelse(disc_b, "PASS", "FAIL"), LM$primary["b"], LM$primary["p"],
    ifelse(length(top_bin_p) && is.finite(top_bin_p), sprintf("%.3f", top_bin_p), "NA"))

saveRDS(list(A = A, pool = POOL, dropped_dup = dropped, grids = GRIDS, TG = TG, PR = PR,
             pp = PP, pp_rel = PPR, runs = RUN, nulls = NULLD, bins = BIN, bins_rel = BINR,
             lm = LM, lm_rel = LMR, auc = AUC, auc_rel = AUCR,
             injection = list(tab = INJTAB, fired = fired, raw = INJ),
             cond = COND, cond_pairs = P1, fam_ci = famci,
             discriminants = list(a = disc_a, b = disc_b, comp_med = comp_med,
                                  km_median_windows = km_med, top_bin_p = top_bin_p),
             geo_halflife_months = vapply(names(PP), function(nm)
               geo_half(PP[[nm]]["p"], GRIDS[[nm]]$W), numeric(1)),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "persistence_results.rds"))
say("저장 — persistence_results.rds")
