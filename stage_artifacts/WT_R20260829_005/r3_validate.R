# ── R3 — 추정기 검증(축퇴 진단 + walk-forward bias test) + 조건수 수리
#  selection_objective = condition_number (+ shrinkage_quality 보조). alpha 수익 미참조.
#  ★bias test 의 무작위 균등 바스켓은 **추정품질 계기**이며 비중 권고가 아니다(역할 경계).
#  C1: 각 테스트월의 Sigma 는 그 달 시작 **이전** 756거래일만으로 재추정(롤링).
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
set.seed(20260829L)

R1 <- readRDS(file.path(OUT, "risk_r1.rds")); R2 <- readRDS(file.path(OUT, "risk_r2.rds"))
D <- R1$D; EXPO <- R1$EXPO; ME_win <- R1$ME_win; SIG <- R1$SIG
FR <- R2$FR; UR <- R2$UR; fac_names <- R2$fac_names; SECLV <- R2$SECLV; STY <- R2$STY
WIN_D <- R2$WIN_D
alldates <- sort(unique(D$Date))
setkey(D, Date, Ticker)

condn  <- function(M) tryCatch(kappa(M, exact = TRUE), error = function(e) NA_real_)
mineig <- function(M) min(eigen(M, symmetric = TRUE, only.values = TRUE)$values)
offcor <- function(S) { s <- sqrt(diag(S)); C <- S / outer(s, s); mean(abs(C[upper.tri(C)])) }

## ── (A) 축퇴 진단 — 조건수 단독으로는 퇴화 추정기가 1등이 된다 ─────────────
RMk <- R2$RMk
C_smp <- cor(RMk)
ref_off <- mean(abs(C_smp[upper.tri(C_smp)]))
deg <- list()
for (nm in names(R2$cands)) {
  cd <- R2$cands[[nm]]
  if (is.null(cd$cov)) next
  S <- cd$cov
  o <- offcor(S)
  deg[[nm]] <- list(name = nm, cond = cd$condition, min_eig = cd$min_eig,
                    mean_abs_offdiag_corr = o,
                    corr_structure_retention = o / ref_off)
  cat(sprintf("[R3-A] %-12s cond=%9.4g  mean|rho|=%.4f  retention=%.3f\n",
              nm, cd$condition, o, o / ref_off))
}
cat(sprintf("[R3-A] reference (sample corr) mean|rho| = %.4f\n", ref_off))

## ── (B) walk-forward bias test (24 테스트월 x 100 무작위 EW 25-바스켓) ──────
mk_X <- function(ex) {
  n <- nrow(ex); sec <- factor(ex$Sector, levels = SECLV)
  Xs <- matrix(0, n, length(SECLV) - 1L); li <- as.integer(sec)
  for (k in seq_len(length(SECLV) - 1L)) Xs[, k] <- as.numeric(li == k)
  Xs[li == length(SECLV), ] <- -1
  colnames(Xs) <- paste0("SEC_", SECLV[-length(SECLV)])
  X <- cbind(MKT = 1, Xs, as.matrix(ex[, ..STY])); rownames(X) <- ex$Ticker; X
}
test_me <- tail(ME_win, 25L)                     # 24 테스트월 (직전 월말 -> 다음 달)
NB <- 100L; NH <- 25L
z_rows <- list()
fdates <- sort(unique(FR$Date))

for (i in 1:(length(test_me) - 1L)) {
  d_anchor <- test_me[i]; d_end <- test_me[i + 1L]
  dd_test <- alldates[alldates > d_anchor & alldates <= d_end]
  if (length(dd_test) < 10L) next
  win <- tail(alldates[alldates <= d_anchor], WIN_D)

  ## 후보 종목 = 창 커버리지 90%+ & 테스트월 전일 관측
  Dw <- D[Date %in% win, .(Date, Ticker, Ret)]
  RMx <- dcast(Dw, Date ~ Ticker, value.var = "Ret"); RMx[, Date := NULL]; RMx <- as.matrix(RMx)
  cf <- colMeans(is.finite(RMx)); kt <- names(cf)[cf >= 0.90]
  Dt <- D[Date %in% dd_test, .(Date, Ticker, Ret)]
  cnt <- Dt[, .N, by = Ticker][N >= length(dd_test) - 2L]
  ex_a <- EXPO[Date == d_anchor]
  kt <- intersect(intersect(kt, cnt$Ticker), ex_a$Ticker)
  if (length(kt) < 60L) next
  RMx <- RMx[, kt, drop = FALSE]
  for (j in seq_len(ncol(RMx))) { z <- RMx[, j]; z[!is.finite(z)] <- mean(z, na.rm = TRUE); RMx[, j] <- z }

  ## 후보 Sigma 5종
  Sigs <- list()
  for (mth in c("sample", "ledoit_wolf", "lw_nls", "gerber_rmt")) {
    cc <- tryCatch(suppressWarnings(.get_cor_cov(RMx, mth)), error = function(e) NULL)
    if (!is.null(cc)) Sigs[[mth]] <- cc$cov
  }
  # factor model (같은 창)
  fw <- tail(fdates[fdates <= d_anchor], WIN_D)
  if (length(fw) >= 400L) {
    Fw <- as.matrix(FR[Date %in% fw, ..fac_names]); Om <- cov(Fw)
    e0 <- eigen(Om, symmetric = TRUE); Om <- e0$vectors %*% diag(pmax(e0$values, max(e0$values)*1e-6)) %*% t(e0$vectors)
    exa <- ex_a[Ticker %in% kt]; setorder(exa, Ticker)
    Bx <- mk_X(exa)
    Uw <- UR[Date %in% fw & Ticker %in% exa$Ticker]
    Dsx <- Uw[, .(n = .N, v = var(u)), by = Ticker][n >= 120L]
    mv <- median(Dsx$v, na.rm = TRUE); Dsx[, sh := pmin(1, 120/n)]
    Dsx[, v_sh := pmax((1-sh)*v + sh*mv, 0.25*mv)]
    dv <- setNames(rep(mv, nrow(exa)), exa$Ticker); dv[Dsx$Ticker] <- Dsx$v_sh
    Sf <- Bx %*% Om %*% t(Bx) + diag(dv[exa$Ticker])
    dimnames(Sf) <- list(exa$Ticker, exa$Ticker)
    Sigs[["factor_bwb_d"]] <- Sf
  }

  ## 무작위 EW 바스켓
  baskets <- replicate(NB, sample(kt, NH), simplify = FALSE)
  RT <- dcast(Dt, Date ~ Ticker, value.var = "Ret")[, -1]
  RT <- as.matrix(RT); RT[!is.finite(RT)] <- 0
  nd <- length(dd_test)
  for (bs in baskets) {
    w <- rep(1/NH, NH)
    real <- prod(1 + rowMeans(RT[, bs, drop = FALSE])) - 1
    for (mth in names(Sigs)) {
      S <- Sigs[[mth]]
      if (!all(bs %in% rownames(S))) next
      v <- as.numeric(t(w) %*% S[bs, bs] %*% w) * nd
      if (!is.finite(v) || v <= 0) next
      z_rows[[length(z_rows)+1L]] <- data.table(month = d_end, method = mth,
                                                z = real / sqrt(v))
    }
  }
  cat(sprintf("  [R3-B] %s  names=%d  days=%d\n", as.character(d_end), length(kt), nd))
}
Z <- rbindlist(z_rows)
bias <- Z[, .(bias_stat = sd(z), mean_z = mean(z), n = .N), by = method]
bias[, bias_abs_err := abs(bias_stat - 1)]
setorder(bias, bias_abs_err)
print(bias)

## ── (C) 조건수 수리 — 개별위험 바닥 상향 (RF-R2 cond<=500) ──────────────────
##  근거: 3년 창 측정 개별분산이 횡단면 중앙값 대비 극단적으로 낮은 종목은
##  KR 소형주 저유동 stale-price 아티팩트가 주 원인이다. 바닥 상향은 (i) 조건수를
##  낮추고 (ii) 소형주 개별위험 과소평가라는 위험한 방향의 오차를 줄인다.
B <- R2$B; Omega_d <- R2$Omega_d; ASSETS <- R2$ASSETS; UR2 <- R2$UR; win_d <- R2$win_d
Uw <- UR2[Date %in% win_d & Ticker %in% ASSETS]
Ds <- Uw[, .(n = .N, v = var(u)), by = Ticker][n >= 120L]
med_v <- median(Ds$v, na.rm = TRUE); Ds[, sh := pmin(1, 120/n)]
Ds[, v_base := (1 - sh) * v + sh * med_v]
build_sigma <- function(floor_frac) {
  dv <- setNames(rep(med_v, length(ASSETS)), ASSETS)
  dv[Ds$Ticker] <- pmax(Ds$v_base, floor_frac * med_v)
  S <- B %*% Omega_d %*% t(B) + diag(dv[ASSETS])
  S <- (S + t(S)) / 2; dimnames(S) <- list(ASSETS, ASSETS)
  list(S = S, dv = dv)
}
grid <- c(0.25, 0.30, 0.35, 0.40, 0.45, 0.50)
cal <- data.table(floor_frac = grid, cond = NA_real_, min_eig = NA_real_, n_floored = NA_integer_)
for (k in seq_along(grid)) {
  bb <- build_sigma(grid[k])
  cal$cond[k] <- condn(bb$S); cal$min_eig[k] <- mineig(bb$S)
  cal$n_floored[k] <- sum(Ds$v_base < grid[k] * med_v)
}
print(cal)
sel <- cal[cond <= 500][1]
if (!nrow(sel) || is.na(sel$floor_frac)) sel <- cal[which.min(cond)]
FLOOR <- sel$floor_frac
fin <- build_sigma(FLOOR)
cat(sprintf("[R3-C] specific-variance floor = %.2f x cross-sectional median -> cond=%.1f min_eig=%.3g (floored %d names)\n",
            FLOOR, condn(fin$S), mineig(fin$S), sum(Ds$v_base < FLOOR * med_v)))

saveRDS(list(deg = deg, ref_off = ref_off, bias = bias, Z = Z,
             Sigma_d = fin$S, dvec_final = fin$dv, floor_frac = FLOOR,
             cal = cal, med_v = med_v, Ds = Ds),
        file.path(OUT, "risk_r3.rds"))
cat("[R3] done\n")
