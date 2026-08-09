#!/usr/bin/env Rscript
# =============================================================================
# p1d_feature_panel.R — FQ-174 ML 피처 패널 (PIT 엄수)
#
# 규약
#  - 행 (ym=t, module_id=i) 의 모든 피처는 **월 t 종료 시점까지의 정보만**.
#    타깃은 **월 t+1** 실현치. ⇒ 홀딩월(t+1) 시작 전 데이터만 (PIT C5).
#  - 자체합성 금지: 누적수익/낙폭/하방편차는 PerformanceAnalytics 표준함수만.
#    (Return.cumulative / maxDrawdown / DownsideDeviation / Drawdowns)
#    평균·표준편차·OLS 기울기는 통계량이지 수익률 합성이 아니므로 직접 계산.
#  - active = r_i - bm  (월별 산술차). p0 사전실측과 동일 basis.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow); library(xts)
  library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1d_feature_panel.log"), split = TRUE)
t_start <- Sys.time()

# ---------------------------------------------------------------- [0] 입력 실측
cat("=== [0] INPUT SHAPE (실측) ===\n")
P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok
cat(sprintf("  PAN: %d rows x %d cols | ym %s..%s | 1행=1개월(중복 %d) | bm decimal(mean %.5f)\n",
            nrow(PAN), ncol(PAN), min(PAN$ym), max(PAN$ym), sum(duplicated(PAN$ym)),
            mean(PAN$bm, na.rm = TRUE)))
cat(sprintf("  scrap_ok=%d elite_ok=%d start_ym=%s\n",
            length(scrap_ok), length(P$elite_ok), P$start_ym))

# 표준함수 known-case 검증 (계약 함수가 기대대로 동작하는지 먼저 확인)
kc <- c(0.10, -0.50, 0.20)                       # NAV 1.10 -> 0.55 -> 0.66, MDD = 0.50
kc_mdd <- as.numeric(maxDrawdown(kc))
kc_cum <- as.numeric(Return.cumulative(kc))      # 1.1*0.5*1.2 - 1 = -0.34
cat(sprintf("  [known-case] maxDrawdown=%.6f (기대 0.500000) | Return.cumulative=%.6f (기대 -0.340000)\n",
            kc_mdd, kc_cum))
stopifnot(abs(kc_mdd - 0.5) < 1e-9, abs(kc_cum - (-0.34)) < 1e-9)
kc_m <- maxDrawdown(cbind(a = kc, b = -kc))
cat(sprintf("  [known-case] maxDrawdown 행렬 입력 → 길이 %d, 값 %s (열별 반환 확인)\n",
            length(as.numeric(kc_m)), paste(sprintf("%.4f", as.numeric(kc_m)), collapse = ", ")))
stopifnot(length(as.numeric(kc_m)) == 2)

# ---------------------------------------------------------------- [1] 창 + dedup
cat("\n=== [1] WINDOW + DEDUP (p0f 방식 재사용) ===\n")
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
Mall <- as.matrix(sub[, ..scrap_ok])
cov_m <- colSums(is.finite(Mall)); keep <- which(cov_m >= 253)
rows_ok <- complete.cases(Mall[, keep, drop = FALSE])
M <- Mall[rows_ok, keep, drop = FALSE]
ids <- scrap_ok[keep]
ymv <- sub$ym[rows_ok]; bmv <- sub$bm[rows_ok]
cat(sprintf("  창: %d개월 %s..%s  x  %d 모듈 (cov>=253 필터)\n",
            nrow(M), min(ymv), max(ymv), ncol(M)))
stopifnot(!any(is.na(M)))   # 창 내부 결측 0 확인 (p0 '191개 완전 커버리지' 검증)
cat("  창 내부 결측 = 0 (assert 통과)\n")

C <- cor(M); diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[, 1] < hi[, 2], , drop = FALSE]
comp <- local({                                   # ★ 최상위 `<<-` 회피 (p0f 수정 이력)
  par <- seq_len(ncol(M))
  fnd <- function(x) { while (par[x] != x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) {
    a <- fnd(hi[r, 1]); b <- fnd(hi[r, 2]); if (a != b) par[b] <- a
  }
  vapply(seq_len(ncol(M)), fnd, integer(1))
})
reps <- vapply(unique(comp), function(g) which(comp == g)[1], integer(1))
R  <- M[, reps, drop = FALSE]                     # 총수익 (dedup 후)
mid <- ids[reps]
grp_size <- vapply(unique(comp), function(g) sum(comp == g), integer(1))
cat(sprintf("  ★유효 독립 = %d / %d (축소율 %.1f%%)  — p0f 기준값 85/191 대조\n",
            ncol(R), ncol(M), 100 * (1 - ncol(R) / ncol(M))))
stopifnot(ncol(R) == 85)
A <- R - matrix(bmv, nrow(R), ncol(R))            # active
K <- nrow(A); NM <- ncol(A)

# ---------------------------------------------------------------- [2] 국면 라벨
cat("\n=== [2] REGIME LABEL (t-1 lag, PIT C5) ===\n")
rp <- file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")
regime_available <- file.exists(rp)
first_day <- as.Date(paste0(substr(ymv, 1, 4), "-", substr(ymv, 5, 6), "-01"))
last_day  <- as.Date(c(first_day[-1], seq(first_day[K], by = "month", length.out = 2)[2])) - 1
lab_next <- rep(NA_character_, K); rs_next <- rep(NA_real_, K); msm_next <- rep(NA_real_, K)
anchor_dt <- as.Date(rep(NA, K)); gap_days <- rep(NA_real_, K)
if (regime_available) {
  RG <- as.data.table(read_parquet(rp)); setorder(RG, Date)
  RG <- RG[!is.na(Category)]
  cat(sprintf("  parquet: %d일 %s..%s | last_updated 고유값 %d개\n", nrow(RG),
              as.character(min(RG$Date)), as.character(max(RG$Date)), uniqueN(RG$last_updated)))
  for (k in seq_len(K)) {                         # 월 k 의 마지막 일별 관측 = 월 k+1 을 지배할 라벨
    idx <- which(RG$Date <= last_day[k])
    if (!length(idx)) next
    i2 <- idx[length(idx)]
    anchor_dt[k] <- RG$Date[i2]; lab_next[k] <- RG$Category[i2]
    rs_next[k]   <- RG$Regime_Score_smooth[i2]; msm_next[k] <- RG$MSM_Crisis_Prob[i2]
  }
  # 홀딩월(k+1) 시작 대비 anchor 간격 실측 — PIT C5 규약
  nxt_start <- c(first_day[-1], NA)
  gap_days <- as.numeric(nxt_start - anchor_dt)
  cat(sprintf("  anchor→홀딩월 시작 간격(일): median=%.0f min=%.0f max=%.0f  (양수여야 PIT 정상)\n",
              median(gap_days, na.rm = TRUE), min(gap_days, na.rm = TRUE), max(gap_days, na.rm = TRUE)))
  cat(sprintf("  anchor 결측 개월 = %d / %d\n", sum(is.na(lab_next)), K))
  cat("  라벨 분포(적용 기준):\n"); print(table(lab_next, useNA = "ifany"))
  cat("  ⚠ 이 parquet 은 vintage 컬럼이 없고 last_updated 가 전 행 동일 →\n")
  cat("     과거 Category 는 '그 시점의 판정'이 아니라 '오늘 모델의 소급 재계산'일 수 있다.\n")
  cat("     MSM_Crisis_Prob 는 Markov-switching smoothed prob 계열 = 전표본 사용 위험(C1).\n")
  cat("     ⇒ 국면 피처는 pit_status='unaudited_vintage' 로 라벨. vintage-swap 통제 전 HARD 판정 인용 금지.\n")
} else {
  cat("  ★ 파일 부재 → 국면 라벨 피처 전부 제외하고 명시 보고\n")
}
lab_cur <- c(NA_character_, lab_next[-K])         # 월 k 를 지배한 라벨 = 월 k-1 말 라벨

# ---------------------------------------------------------------- [3] 회전율
cat("\n=== [3] TURNOVER (HOLDINGS_LOG 실측) ===\n")
TOP <- file.path(OUT, "turnover_monthly.rds")
turn_available <- file.exists(TOP)
TURN <- matrix(NA_real_, K, NM, dimnames = list(ymv, mid))
if (turn_available) {
  TO <- readRDS(TOP)[module_id %in% mid]
  rng <- TO[, .(f = min(ym), l = max(ym)), by = module_id]
  wide <- dcast(TO, ym ~ module_id, value.var = "turnover")
  wi <- match(ymv, wide$ym); ci <- match(mid, names(wide))
  for (j in seq_len(NM)) if (!is.na(ci[j])) TURN[, j] <- wide[[ci[j]]][wi]
  # 리밸런스 없는 달 = 거래 없음 = 0. 단 모듈 관측범위 밖은 NA 유지.
  for (j in seq_len(NM)) {
    rr <- rng[module_id == mid[j]]
    if (!nrow(rr)) next
    inr <- ymv >= rr$f & ymv <= rr$l
    TURN[inr & is.na(TURN[, j]), j] <- 0
  }
  cat(sprintf("  회전율 커버리지: 셀 %d/%d (%.1f%%) | 값 median=%.4f max=%.4f\n",
              sum(!is.na(TURN)), length(TURN), 100 * mean(!is.na(TURN)),
              median(TURN, na.rm = TRUE), max(TURN, na.rm = TRUE)))
} else cat("  ★ turnover_monthly.rds 부재 → 회전율 피처 제외\n")

# ---------------------------------------------------------------- [4] 피처 함수
# ★ build_features 는 인자로 받은 행 1..n 만 사용한다 (미래 행 참조 없음).
#   → 누출검사 #4(절단 불변성)에서 같은 함수를 잘린 패널에 돌려 동일성 검증.
roll_slope <- function(Y, x, w) {                 # 열별 OLS 기울기 (trailing w개월)
  n <- nrow(Y); S <- matrix(NA_real_, n, ncol(Y))
  for (k in w:n) {
    xi <- x[(k - w + 1):k]; if (!all(is.finite(xi)) || sd(xi) == 0) next
    Yi <- Y[(k - w + 1):k, , drop = FALSE]
    xc <- xi - mean(xi)
    S[k, ] <- as.numeric(crossprod(xc, Yi)) / sum(xc^2)
  }
  S
}
roll_stat <- function(Y, w, f, dts = NULL) {
  # dts 제공 시 창을 xts 로 감싸 전달 — PerformanceAnalytics checkData 요구사항.
  n <- nrow(Y); S <- matrix(NA_real_, n, ncol(Y))
  if (is.null(colnames(Y))) colnames(Y) <- paste0("m", seq_len(ncol(Y)))
  for (k in w:n) {
    idx <- (k - w + 1):k
    X <- Y[idx, , drop = FALSE]
    if (!is.null(dts)) X <- xts::xts(X, order.by = dts[idx])
    S[k, ] <- f(X)
  }
  S
}
cum_cond_mean <- function(Y, mask) {              # 확장창 조건부 평균 + 개수
  m <- as.numeric(mask); m[is.na(m)] <- 0
  cs <- apply(Y * m, 2, cumsum); cn <- cumsum(m)
  list(mean = cs / ifelse(cn == 0, NA, cn), n = cn)
}

build_features <- function(A, R, bmv, ymv, lab_cur, lab_next, TURN, dts, min_n_state = 3L) {
  n <- nrow(A); p <- ncol(A)
  F <- list()
  # --- trailing active mean/sd/IR
  for (w in c(36L, 12L)) {
    mu <- roll_stat(A, w, colMeans)
    sg <- roll_stat(A, w, function(X) apply(X, 2, sd))
    F[[paste0("act_mean_", w)]] <- mu
    F[[paste0("act_sd_", w)]]   <- sg
    F[[paste0("act_ir_", w)]]   <- mu / ifelse(sg > 0, sg, NA)
  }
  # --- 상태-조건부 trailing active (★핵심 피처). 상태는 그 달의 bm 로 정의 = 과거 정보.
  st <- ifelse(bmv <= -0.05, "DOWN", ifelse(bmv >= 0.05, "SURGE", "FLAT"))
  for (s in c("DOWN", "SURGE", "FLAT")) {
    cc <- cum_cond_mean(A, st == s)
    v <- cc$mean; v[matrix(rep(cc$n, p), n, p) < min_n_state] <- NA
    F[[paste0("act_mean_", tolower(s))]] <- v
    F[[paste0("n_", tolower(s))]] <- matrix(rep(cc$n, p), n, p)
  }
  # --- 국면-조건부 trailing active: 과거 s<=t 중 lab_cur[s]==lab_next[t] 인 달들의 평균
  if (!all(is.na(lab_next))) {
    cats <- sort(unique(na.omit(c(lab_cur, lab_next))))
    ms <- lapply(cats, function(cg) cum_cond_mean(A, lab_cur == cg))
    names(ms) <- cats
    vm <- matrix(NA_real_, n, p); vn <- matrix(NA_real_, n, p)
    for (k in seq_len(n)) {
      L <- lab_next[k]; if (is.na(L) || !(L %in% cats)) next
      vm[k, ] <- ms[[L]]$mean[k, ]; vn[k, ] <- ms[[L]]$n[k]
    }
    vm[vn < min_n_state] <- NA
    F[["act_mean_regime"]] <- vm; F[["n_regime"]] <- vn
  }
  # --- trailing drawdown / downside deviation (PerformanceAnalytics 표준함수)
  F[["mdd_24"]]     <- roll_stat(R, 24L, function(X) as.numeric(maxDrawdown(X)), dts)
  F[["mdd_24_act"]] <- roll_stat(A, 24L, function(X) as.numeric(maxDrawdown(X)), dts)
  F[["dsd_36"]]     <- roll_stat(A, 36L, function(X)
                                 as.numeric(DownsideDeviation(X, MAR = 0, method = "full")), dts)
  # --- rolling PC1 beta: PC1 을 **확장창(1..k)** 으로 추정 → 미래 데이터로 PC1 추정 금지
  f1_full <- rep(NA_real_, n); BPC <- matrix(NA_real_, n, p)
  MINK <- 36L
  for (k in MINK:n) {
    Ak <- A[1:k, , drop = FALSE]
    sdk <- apply(Ak, 2, sd); if (any(!is.finite(sdk)) || any(sdk == 0)) next
    Z <- scale(Ak)                                # 평균/분산도 1..k 만 사용
    pc <- prcomp(Z, center = FALSE, scale. = FALSE)
    ld <- pc$rotation[, 1]
    sgn <- if (sum(ld) < 0) -1 else 1             # 결정적 부호 고정 (적재 합 > 0)
    f1k <- as.numeric(pc$x[, 1]) * sgn
    f1_full[k] <- f1k[k]
    w <- min(36L, k)
    xi <- f1k[(k - w + 1):k]; xc <- xi - mean(xi)
    if (sum(xc^2) > 0) BPC[k, ] <- as.numeric(crossprod(xc, A[(k - w + 1):k, , drop = FALSE])) / sum(xc^2)
  }
  F[["beta_pc1_36"]] <- BPC
  # --- trailing beta vs bm (총수익 기준)
  F[["beta_bm_36"]] <- roll_slope(R, bmv, 36L)
  # --- 회전율 trailing 12m 평균 (리밸런스 없는 달 = 0 으로 채워진 TURN 사용)
  if (!all(is.na(TURN))) F[["turnover_12"]] <- roll_stat(TURN, 12L,
                                                function(X) colMeans(X, na.rm = TRUE))
  # --- 시장/국면 (전 모듈 공통, 행 단위) : 전부 월 t 까지
  bm_1  <- bmv
  bm_3  <- c(rep(NA, 2), vapply(3:n, function(k) as.numeric(Return.cumulative(bmv[(k-2):k])), 0))
  bm_12 <- c(rep(NA, 11), vapply(12:n, function(k) as.numeric(Return.cumulative(bmv[(k-11):k])), 0))
  bm_vol12 <- c(rep(NA, 11), vapply(12:n, function(k) sd(bmv[(k-11):k]), 0))
  bm_dd <- as.numeric(Drawdowns(xts::xts(matrix(bmv, ncol = 1,
             dimnames = list(NULL, "bm")), order.by = dts)))  # 확장 낙폭: k 값은 1..k 만 사용
  cs_disp <- apply(A, 1, sd)
  cs_disp12 <- c(rep(NA, 11), vapply(12:n, function(k) mean(cs_disp[(k-11):k]), 0))
  apc <- rep(NA_real_, n)
  for (k in 36L:n) {
    Ck <- suppressWarnings(cor(A[(k-35):k, , drop = FALSE]))
    apc[k] <- mean(Ck[upper.tri(Ck)], na.rm = TRUE)
  }
  MK <- function(v) matrix(rep(v, p), n, p)
  F[["bm_ret_1m"]] <- MK(bm_1);   F[["bm_ret_3m"]] <- MK(bm_3); F[["bm_ret_12m"]] <- MK(bm_12)
  F[["bm_vol_12m"]] <- MK(bm_vol12); F[["bm_dd_depth"]] <- MK(bm_dd)
  F[["cs_disp"]] <- MK(cs_disp); F[["cs_disp_12m"]] <- MK(cs_disp12)
  F[["avg_pair_corr_36m"]] <- MK(apc)
  F[["state_now_down"]]  <- MK(as.numeric(st == "DOWN"))
  F[["state_now_surge"]] <- MK(as.numeric(st == "SURGE"))
  F
}

cat("\n=== [4] BUILD FEATURES (full panel) ===\n")
FF <- build_features(A, R, bmv, ymv, lab_cur, lab_next, TURN, last_day)
cat(sprintf("  피처 블록 %d개 생성 (%.1fs)\n", length(FF),
            as.numeric(difftime(Sys.time(), t_start, units = "secs"))))

# ---------------------------------------------------------------- [5] long 변환 + 타깃
cat("\n=== [5] TARGETS ===\n")
cat("  y_ret     = 다음달 모듈 active 수익           = A[t+1, i]\n")
cat("  y_dd      = 다음달 active 의 하방부분(primary) = min(A[t+1, i], 0)\n")
cat("              ⇒ 정의 근거: '낙폭 기여'를 월 단위로 관측 가능한 최소단위로 환원.\n")
cat("                 값 <=0, 0 = 그 달 하방기여 없음. MDD 자체가 아니라 그 구성요소.\n")
cat("  y_dd_bear = 다음달 bm 하락 시의 active        = A[t+1,i] * 1{bm[t+1] < 0}  (secondary)\n")
cat("  y_bm_next = 다음달 bm (그룹핑/분석용 — ★타깃측 필드, 피처로 사용 금지)\n")
Anext  <- rbind(A[-1, , drop = FALSE], NA)
bmnext <- c(bmv[-1], NA)
y_ret  <- Anext
y_dd   <- pmin(Anext, 0)
y_ddb  <- Anext * matrix(rep(as.numeric(bmnext < 0), NM), K, NM)

DT <- data.table(ym = rep(ymv, times = NM), module_id = rep(mid, each = K))
DT[, dup_group_size := rep(grp_size, each = K)]
for (nm in names(FF)) set(DT, j = nm, value = as.numeric(FF[[nm]]))
if (!all(is.na(lab_next))) {
  DT[, reg_cat_t := rep(lab_next, times = NM)]
  DT[, reg_score_smooth_t := rep(rs_next, times = NM)]
  DT[, reg_msm_crisis_t   := rep(msm_next, times = NM)]
  DT[, reg_anchor_date := rep(anchor_dt, times = NM)]
}
DT[, y_ret := as.numeric(y_ret)]
DT[, y_dd  := as.numeric(y_dd)]
DT[, y_dd_bear := as.numeric(y_ddb)]
DT[, y_bm_next := rep(bmnext, times = NM)]
DT[, target_ym := rep(c(ymv[-1], NA), times = NM)]
feat_cols <- setdiff(names(DT), c("ym","module_id","target_ym","dup_group_size",
                                  "reg_anchor_date","y_ret","y_dd","y_dd_bear","y_bm_next"))
DT_all <- copy(DT)
DT <- DT[!is.na(y_ret)]
cat(sprintf("\n  long 패널: %d행 (%d개월 x %d모듈, 타깃 결측행 제거)  피처 %d개\n",
            nrow(DT), uniqueN(DT$ym), uniqueN(DT$module_id), length(feat_cols)))
cmpl <- DT[, sum(complete.cases(.SD)), .SDcols = feat_cols]
cat(sprintf("  전 피처 완비 행 = %d (%.1f%%)  — 36m warm-up 때문에 초기 구간 결측은 정상\n",
            cmpl, 100 * cmpl / nrow(DT)))
first_full <- DT[complete.cases(DT[, ..feat_cols]), min(ym)]
cat(sprintf("  전 피처 완비 시작 ym = %s\n", first_full))

# ------------------------------------------------------- [5b] 파생 피처 정합 검사
cat("\n=== [5b] SANITY — 파생값 범위 + P0 기준값 대조 ===\n")
rngchk <- function(nm, v, lo, hi) {
  v <- v[is.finite(v)]
  ok <- all(v >= lo - 1e-9 & v <= hi + 1e-9)
  cat(sprintf("  %-18s min=%+.4f max=%+.4f  기대범위 [%.2f, %.2f] → %s\n",
              nm, min(v), max(v), lo, hi, if (ok) "OK" else "★범위 이탈"))
  ok
}
s_ok <- c(
  rngchk("mdd_24",       DT$mdd_24,       0, 1),
  rngchk("mdd_24_act",   DT$mdd_24_act,   0, 1),
  rngchk("dsd_36",       DT$dsd_36,       0, 1),
  rngchk("bm_dd_depth",  DT$bm_dd_depth, -1, 0),
  rngchk("turnover_12",  DT$turnover_12,  0, 1),
  rngchk("avg_pair_corr_36m", DT$avg_pair_corr_36m, -1, 1))
cat(sprintf("  bm_dd_depth 최저 = %.4f  (P0 기준 BM MDD 47.1%% ⇒ -0.471 부근이어야)\n",
            min(DT$bm_dd_depth, na.rm = TRUE)))
# 마지막 행의 확장 조건부 평균 = 전 창 조건부 평균 ⇒ P0 사전실측과 직접 대조
lastrow <- FF[["act_mean_down"]][K, ]; lastsur <- FF[["act_mean_surge"]][K, ]
lastfla <- FF[["act_mean_flat"]][K, ]
cat(sprintf("  [P0 대조] 최종행 확장 조건부평균의 모듈간 분포 (P0 기준값과 일치해야):\n"))
cat(sprintf("    DOWN  mean=%+.3f%%/m sd=%.3f range[%+.3f,%+.3f]  | P0: +1.700 sd1.318 [-1.015,+7.358]\n",
            100*mean(lastrow), 100*sd(lastrow), 100*min(lastrow), 100*max(lastrow)))
cat(sprintf("    SURGE mean=%+.3f%%/m sd=%.3f range[%+.3f,%+.3f]  | P0: -2.026 sd1.345 [-7.638,+0.049]\n",
            100*mean(lastsur), 100*sd(lastsur), 100*min(lastsur), 100*max(lastsur)))
cat(sprintf("    FLAT  mean=%+.3f%%/m sd=%.3f                      | P0: +0.482 sd0.290\n",
            100*mean(lastfla), 100*sd(lastfla)))
cat(sprintf("    상태 개월수: DOWN=%d SURGE=%d FLAT=%d | P0: 31 / 49 / 174\n",
            FF[["n_down"]][K,1], FF[["n_surge"]][K,1], FF[["n_flat"]][K,1]))
p0_match <- (abs(100*mean(lastrow) - 1.700) < 0.02) && (abs(100*mean(lastsur) - (-2.026)) < 0.02) &&
            (abs(100*mean(lastfla) - 0.482) < 0.02) &&
            (FF[["n_down"]][K,1] == 31) && (FF[["n_surge"]][K,1] == 49) && (FF[["n_flat"]][K,1] == 174)
cat(sprintf("  ⇒ P0 기준값 재현 = %s\n", p0_match))
SAN <- list(range_checks_all_ok = all(s_ok),
            bm_dd_min = min(DT$bm_dd_depth, na.rm = TRUE),
            p0_state_reproduction = p0_match,
            down = list(mean_pct_m = 100*mean(lastrow), sd = 100*sd(lastrow), n = FF[["n_down"]][K,1]),
            surge = list(mean_pct_m = 100*mean(lastsur), sd = 100*sd(lastsur), n = FF[["n_surge"]][K,1]),
            flat = list(mean_pct_m = 100*mean(lastfla), sd = 100*sd(lastfla), n = FF[["n_flat"]][K,1]))

# ---------------------------------------------------------------- [6] 누출 검사
cat("\n=== [6] LEAKAGE CHECKS ===\n")
LC <- list()

## (1) 피처 최대 Date < 타깃월 시작
mx_src <- pmax(as.numeric(last_day), as.numeric(anchor_dt), na.rm = TRUE)
tgt_start <- as.numeric(c(first_day[-1], NA))
ok1 <- mx_src[1:(K-1)] < tgt_start[1:(K-1)]
cat(sprintf("  [1] 피처 소스 max Date < 타깃월 시작 : %d/%d 통과 (최소 여유 %.0f일)\n",
            sum(ok1), K-1, min(tgt_start[1:(K-1)] - mx_src[1:(K-1)])))
if (turn_available) {
  TO2 <- readRDS(TOP); TO2[, ymn := as.integer(ym)]
  cat(sprintf("      회전율 소스 ym 최대 = %s (창 최대 %s) — 행 t 는 ym<=t 만 사용(roll_stat 구조)\n",
              max(TO2$ym), max(ymv)))
}
LC$check1_feature_date_before_target <- list(
  passed = as.integer(sum(ok1)), of = K - 1L,
  min_slack_days = as.numeric(min(tgt_start[1:(K-1)] - mx_src[1:(K-1)])),
  note = "피처 소스 = 월t 말일 / 국면 anchor(월t 내 마지막 일별 관측). 타깃 = 월t+1.")
stopifnot(all(ok1))

## (2) 각 피처의 lag-1 자기상관 (모듈 내)
cat("  [2] 피처 lag-1 자기상관 (모듈 내 pooled). trailing 창은 겹침이 커서 높은 게 정상 —\n")
cat("      판정선은 '1.0 과 구분 불가(>0.99999)' 인 것만 의심으로 본다.\n")
setorder(DT_all, module_id, ym)
num_feat <- feat_cols[vapply(feat_cols, function(f) is.numeric(DT_all[[f]]), logical(1))]
cat_feat <- setdiff(feat_cols, num_feat)
cat(sprintf("      수치 피처 %d개 / 범주 피처 %d개 (%s) — 상관 검사는 수치 피처만\n",
            length(num_feat), length(cat_feat),
            if (length(cat_feat)) paste(cat_feat, collapse = ",") else "-"))
ac <- data.table(feature = num_feat, lag1_autocorr = NA_real_, corr_with_y = NA_real_,
                 lag1_corr_with_y = NA_real_)
for (i in seq_along(num_feat)) {
  f <- num_feat[i]
  X <- DT_all[[f]]; Xl <- DT_all[, shift(get(f), 1L), by = module_id]$V1
  ac$lag1_autocorr[i] <- suppressWarnings(cor(X, Xl, use = "complete.obs"))
  ac$corr_with_y[i]   <- suppressWarnings(cor(X, DT_all$y_ret, use = "complete.obs"))
  ac$lag1_corr_with_y[i] <- suppressWarnings(cor(Xl, DT_all$y_ret, use = "complete.obs"))
}
susp <- ac[!is.na(lag1_autocorr) & lag1_autocorr > 0.99999]
cat(sprintf("      자기상관>0.99999 인 피처: %d개 %s\n", nrow(susp),
            if (nrow(susp)) paste(susp$feature, collapse = ", ") else "(없음)"))
cat(sprintf("      |corr(feature_t, y_ret_t)| 최대 = %.4f  (%s)  — 1 에 근접하면 타깃 누출\n",
            max(abs(ac$corr_with_y), na.rm = TRUE),
            ac$feature[which.max(abs(ac$corr_with_y))]))
print(ac[order(-abs(corr_with_y))][1:8])
LC$check2_shift_autocorr <- list(
  n_numeric_features = nrow(ac), n_categorical_features = length(cat_feat),
  n_autocorr_gt_0_99999 = nrow(susp),
  max_abs_corr_with_target = max(abs(ac$corr_with_y), na.rm = TRUE),
  max_corr_feature = ac$feature[which.max(abs(ac$corr_with_y))],
  note = "trailing 창 겹침으로 높은 자기상관은 정상. 타깃과의 상관이 판별선.")

## (3) 국면 라벨 anchor ↔ 홀딩월 간격 (PIT C5)
if (regime_available) {
  cat(sprintf("  [3] 국면 anchor → 홀딩월 시작 간격: median=%.0f일 min=%.0f일 max=%.0f일 (전부 양수 = 홀딩월 시작 전)\n",
              median(gap_days, na.rm=TRUE), min(gap_days, na.rm=TRUE), max(gap_days, na.rm=TRUE)))
  cat(sprintf("      음수/0 간격 개월 = %d  (0 이하면 C5 위반)\n", sum(gap_days <= 0, na.rm = TRUE)))
  LC$check3_regime_anchor_gap <- list(
    median_days = median(gap_days, na.rm=TRUE), min_days = min(gap_days, na.rm=TRUE),
    max_days = max(gap_days, na.rm=TRUE), n_violation_le0 = sum(gap_days <= 0, na.rm = TRUE),
    pit_status = "unaudited_vintage",
    caveat = "parquet 에 vintage 컬럼 없음 + last_updated 전행 동일 + MSM smoothed prob 계열 → 과거 라벨이 소급 재계산일 위험(C1). 소비 타이밍은 C5 정상.")
} else LC$check3_regime_anchor_gap <- list(status = "regime_file_absent")

## (4) ★절단 불변성 (위반 주입 방식의 정공법): 미래 행을 제거해도 행 T 피처가 동일한가
cat("  [4] 절단 불변성 테스트 — 패널을 T 에서 자른 뒤 행 T 피처를 전체판과 대조\n")
Tcut <- 200L
FF2 <- build_features(A[1:Tcut, , drop=FALSE], R[1:Tcut, , drop=FALSE], bmv[1:Tcut],
                      ymv[1:Tcut], lab_cur[1:Tcut], lab_next[1:Tcut],
                      TURN[1:Tcut, , drop=FALSE], last_day[1:Tcut])
common <- intersect(names(FF), names(FF2))
mism <- c(); maxdiff <- 0
for (nm in common) {
  a1 <- FF[[nm]][Tcut, ]; a2 <- FF2[[nm]][Tcut, ]
  d <- max(abs(a1 - a2), na.rm = TRUE); if (!is.finite(d)) d <- 0
  na1 <- is.na(a1); na2 <- is.na(a2)
  if (d > 1e-10 || !identical(na1, na2)) mism <- c(mism, sprintf("%s(maxdiff=%.3e)", nm, d))
  maxdiff <- max(maxdiff, d)
}
cat(sprintf("      비교 피처 블록 %d개 | 불일치 %d개 | 최대 절대차 %.3e\n",
            length(common), length(mism), maxdiff))
if (length(mism)) cat(sprintf("      ★불일치: %s\n", paste(mism, collapse=", ")))
cat(sprintf("      ⇒ %s\n", if (!length(mism))
    "행 T 피처는 T 이후 데이터에 전혀 의존하지 않음 (forward 정보 유입 0)" else
    "★미래 의존 발견 — 해당 피처 수리 전 사용 금지"))
LC$check4_truncation_invariance <- list(
  cut_row = Tcut, cut_ym = ymv[Tcut], n_blocks = length(common),
  n_mismatch = length(mism), max_abs_diff = maxdiff,
  mismatches = if (length(mism)) mism else NULL,
  note = "행 T 를 미래 없는 패널에서 재계산해 전체판과 대조. 일치 = forward 정보 유입 0.")

## (5) 음성 대조: 일부러 미래를 넣은 피처는 이 검사에 걸리는가 (검사 실효 확인)
cat("  [5] 위반 주입 — 고의로 forward 피처(A[t+1]) 를 만들어 검사 #4 가 잡는지 확인\n")
inj_full <- rbind(A[-1, , drop=FALSE], NA)[Tcut, ]
inj_cut  <- rbind(A[1:Tcut, , drop=FALSE][-1, , drop=FALSE], NA)[Tcut, ]
caught <- !isTRUE(all.equal(inj_full, inj_cut)) || !identical(is.na(inj_full), is.na(inj_cut))
cat(sprintf("      주입 피처 전체판 vs 절단판 불일치 검출 = %s (TRUE 여야 검사 실효)\n", caught))
LC$check5_violation_injection <- list(
  injected = "forward_active_A[t+1]", detected_by_check4 = caught,
  note = "검사 #4 가 진짜 미래 의존을 잡는지 확인하는 양성 대조. TRUE = 검사 살아있음.")
stopifnot(caught)

# ---------------------------------------------------------------- [7] 저장
cat("\n=== [7] SAVE ===\n")
setcolorder(DT, c("ym","target_ym","module_id","dup_group_size", feat_cols,
                  intersect("reg_anchor_date", names(DT)),
                  "y_ret","y_dd","y_dd_bear","y_bm_next"))
saveRDS(list(
  panel = DT, feature_cols = feat_cols, module_ids = mid,
  window_ym = ymv, bm = bmv,
  target_def = list(
    y_ret = "A[t+1,i] = r[t+1,i] - bm[t+1] (다음달 모듈 active 수익, 월별 산술차)",
    y_dd  = "min(A[t+1,i], 0) — 다음달 active 의 하방부분. PRIMARY 낙폭기여 정의.",
    y_dd_bear = "A[t+1,i] * 1{bm[t+1] < 0} — bm 하락월의 active. SECONDARY.",
    y_bm_next = "bm[t+1] — 분석/그룹핑용 타깃측 필드. 피처 사용 금지."),
  metric_type = "diagnostic_precheck",
  pit_note = "행(t,i) 피처는 월 t 종료까지 정보만. 국면 피처는 pit_status=unaudited_vintage.",
  leakage_checks = LC
), file.path(OUT, "ml_feature_panel.rds"))

rep <- list(
  round = "FQ-174 scrap ensemble — ML feature panel",
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "diagnostic_precheck",
  input = list(
    source = "stage_artifacts/scrap_ensemble_20260809/p0_panel.rds",
    PAN_rows = nrow(PAN), PAN_cols = ncol(PAN),
    PAN_unit = "wide monthly: 1 row = 1 month, no duplicate ym, no calendar gap",
    PAN_ym_range = c(min(PAN$ym), max(PAN$ym)),
    bm_scale = "decimal monthly return",
    scrap_ok = length(scrap_ok), elite_ok = length(P$elite_ok)),
  window = list(n_months = K, ym_start = min(ymv), ym_end = max(ymv),
                n_modules_pre_dedup = ncol(M), missing_cells_in_window = 0L),
  dedup = list(method = "union-find on corr>=0.999, representative = first member",
               n_in = ncol(M), n_out = NM, reduction_pct = 100*(1-NM/ncol(M)),
               matches_p0f_reference_85 = (NM == 85L),
               largest_group = max(grp_size)),
  panel = list(rows = nrow(DT), months = uniqueN(DT$ym), modules = uniqueN(DT$module_id),
               n_features = length(feat_cols),
               complete_rows = cmpl, complete_pct = 100*cmpl/nrow(DT),
               first_full_ym = first_full,
               format = "long: ym, target_ym, module_id, <features>, y_ret, y_dd, y_dd_bear, y_bm_next"),
  features = feat_cols,
  sanity = SAN,
  feature_notes = list(
    state_conditional = "act_mean_down/surge/flat = 확장창 조건부 평균 (상태는 그 달 bm: DOWN<=-5%, SURGE>=+5%, 나머지 FLAT). min 3관측.",
    regime_conditional = "act_mean_regime = 과거 중 '지금과 같은 국면 라벨'이 지배한 달들의 active 평균.",
    pc1_beta = "PC1 을 확장창(1..t)으로 매월 재추정(미래 데이터 사용 없음), 부호는 적재합>0 로 결정적 고정, trailing 36m OLS 기울기.",
    turnover = "HOLDINGS_LOG name-level 0.5*sum|Δw| 실측 (proxy 아님). 리밸런스 없는 달=0, 모듈 관측범위 밖=NA. trailing 12m 평균.",
    drawdown = "mdd_24/mdd_24_act = PerformanceAnalytics::maxDrawdown (24m rolling). dsd_36 = DownsideDeviation(MAR=0, full).",
    market = "bm_ret_3m/12m = Return.cumulative. bm_dd_depth = Drawdowns() 확장 낙폭. 전부 월 t 까지.",
    excluded = if (!regime_available) "regime features (parquet absent)" else NULL),
  regime_source = list(
    file = ".cache/unified_regime_signal_daily.parquet", available = regime_available,
    unit = "daily, 1 row per date", rows = if (regime_available) nrow(RG) else NULL,
    anchor_rule = "월 t 내 마지막 일별 관측 → 월 t+1 에 적용 (PIT C5)",
    pit_status = "unaudited_vintage",
    caveat = "vintage 컬럼 부재 + last_updated 전행 동일 + MSM smoothed prob 계열 ⇒ 과거 라벨이 소급 재계산일 위험. 소비 타이밍(C5)은 정상이나 vintage-swap 통제 전 HARD 판정 인용 금지."),
  targets = list(
    y_ret = "A[t+1,i] = r[t+1,i] - bm[t+1]",
    y_dd = "min(A[t+1,i], 0) — PRIMARY. 다음달 active 의 하방부분(월별 낙폭기여 구성요소)",
    y_dd_bear = "A[t+1,i] * 1{bm[t+1]<0} — SECONDARY",
    y_bm_next = "bm[t+1] (타깃측 보조필드, 피처 사용 금지)",
    y_dd_rationale = "MDD 는 경로의존 통계라 월 단위 타깃으로 분해 불가. 관측 가능한 최소 구성요소인 '그 달의 하방 active' 로 환원했고, bm 하락월 한정판(y_dd_bear)을 병기해 정의 민감도를 남긴다."),
  leakage_checks = LC,
  constraints_note = list(
    max_25_names = "모듈 HOLDINGS_LOG 실측 종목수는 20~30 → NAV-레벨 앙상블은 max25 자동 충족 안 됨. 본 산출은 screen-tier 진단, 자본 졸업 주장 없음.",
    no_self_synthesis = "누적수익/낙폭/하방편차 전부 PerformanceAnalytics 표준함수. known-case 검증 로그 기록.",
    scope = "모듈 멤버십/배합 축만. 노출 스케일(overlay/exposure timing)은 WT-D20260809_002 소관 — 미접촉."),
  outputs = list(
    rds = "stage_artifacts/scrap_ensemble_20260809/ml_feature_panel.rds",
    json = "stage_artifacts/scrap_ensemble_20260809/panel_build_report.json",
    turnover = "stage_artifacts/scrap_ensemble_20260809/turnover_monthly.rds"),
  runtime_sec = as.numeric(difftime(Sys.time(), t_start, units = "secs"))
)
write_json(rep, file.path(OUT, "panel_build_report.json"),
           auto_unbox = TRUE, digits = NA, pretty = TRUE, null = "null")
cat(sprintf("  saved: ml_feature_panel.rds (%.1f MB) + panel_build_report.json\n",
            file.size(file.path(OUT, "ml_feature_panel.rds"))/1e6))
cat(sprintf("  총 소요 %.1fs\n", as.numeric(difftime(Sys.time(), t_start, units="secs"))))
cat("\n[done]\n"); sink()
