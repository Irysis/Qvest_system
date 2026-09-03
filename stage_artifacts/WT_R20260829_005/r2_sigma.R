# ── R2 — Sigma = B Omega B^T + D 추정 + 추정기 비교(method shopping log, 상한 5)
#  C1 : 모든 통계는 **롤링 756일 창**. full-sample 미사용.
#  선택 기준(selection_objective) = condition_number (estimation quality only)
#  ★alpha 재해석/weight 산출 없음. 무작위 EW 바스켓 bias test 는 추정품질 지표이지 비중 권고가 아니다.
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
set.seed(20260829L)

R1 <- readRDS(file.path(OUT, "risk_r1.rds"))
D <- R1$D; BMd <- R1$BMd; EXPO <- R1$EXPO; ME_win <- R1$ME_win; SIG <- R1$SIG; UNIV <- R1$UNIV
WIN_D <- 756L          # 롤링 추정창 (거래일 3년)

STY <- c("X_BETA","X_SIZE","X_VAL","X_MOM","X_LIQ","X_RVOL")
EXPO[is.na(Sector) | Sector == "", Sector := "UNKNOWN"]
SECLV <- sort(unique(EXPO$Sector))
cat(sprintf("[R2] sectors=%d styles=%d months=%d\n", length(SECLV), length(STY), length(ME_win)))

## ── 일별 횡단면 WLS 회귀 -> 팩터수익 f_d, 잔차 u_id ─────────────────────────
##   설계: r_d = MKT + sum_k SEC_k(sum-to-zero) + sum_s STY_s + u   (weight = sqrt(Size))
##   B_m = 월말 m-1 노출 (PIT: 홀딩월 시작 전 자료만)
alldates <- sort(unique(D$Date))
setkey(D, Date, Ticker)
setkey(EXPO, Date, Ticker)

mk_X <- function(ex) {
  n <- nrow(ex)
  sec <- factor(ex$Sector, levels = SECLV)
  Xs <- matrix(0, n, length(SECLV) - 1L)
  li <- as.integer(sec)
  for (k in seq_len(length(SECLV) - 1L)) Xs[, k] <- as.numeric(li == k)
  Xs[li == length(SECLV), ] <- -1                      # contr.sum
  colnames(Xs) <- paste0("SEC_", SECLV[-length(SECLV)])
  X <- cbind(MKT = 1, Xs, as.matrix(ex[, ..STY]))
  rownames(X) <- ex$Ticker
  X
}

fac_names <- c("MKT", paste0("SEC_", SECLV[-length(SECLV)]), STY)
K <- length(fac_names)
f_list <- list(); u_list <- list(); r2_list <- numeric(0)

for (i in 1:(length(ME_win) - 1L)) {
  d_from <- ME_win[i]; d_to <- ME_win[i + 1L]
  ex <- EXPO[Date == d_from]
  if (!nrow(ex)) next
  X <- mk_X(ex)
  w <- sqrt(ex$Size); w <- w / sum(w) * nrow(ex)
  dd <- alldates[alldates > d_from & alldates <= d_to]
  for (d in dd) {
    rr <- D[.(as.Date(d)), .(Ticker, Ret), nomatch = 0L]
    idx <- match(rr$Ticker, ex$Ticker)
    ok <- !is.na(idx) & is.finite(rr$Ret)
    if (sum(ok) < 60L) next
    Xi <- X[idx[ok], , drop = FALSE]; yi <- rr$Ret[ok]; wi <- w[idx[ok]]
    keep <- apply(Xi, 2, function(z) length(unique(z)) > 1L); keep["MKT"] <- TRUE
    Xk <- Xi[, keep, drop = FALSE]
    fit <- tryCatch(qr.solve(crossprod(Xk * sqrt(wi)) + diag(1e-10, ncol(Xk)),
                             crossprod(Xk * wi, yi)), error = function(e) NULL)
    if (is.null(fit)) next
    fv <- setNames(rep(0, K), fac_names); fv[colnames(Xk)] <- as.numeric(fit)
    resid <- yi - as.numeric(Xk %*% fit)
    tot <- sum(wi * (yi - weighted.mean(yi, wi))^2); res <- sum(wi * resid^2)
    r2_list <- c(r2_list, 1 - res / tot)
    f_list[[length(f_list) + 1L]] <- data.table(Date = as.Date(d), t(fv))
    u_list[[length(u_list) + 1L]] <- data.table(Date = as.Date(d), Ticker = rr$Ticker[ok], u = resid)
  }
  if (i %% 12 == 0) cat(sprintf("  [R2] xsreg %d/%d months\n", i, length(ME_win) - 1L))
}
FR <- rbindlist(f_list); UR <- rbindlist(u_list)
cat(sprintf("[R2] factor returns: %d days %s..%s | mean cross-sec R2 = %.3f\n",
            nrow(FR), min(FR$Date), max(FR$Date), mean(r2_list, na.rm = TRUE)))

## ── as-of 노출 B (2026-07-31) — alpha 유니버스 340종 ─────────────────────────
ex_now <- EXPO[Date == SIG]
ex_now <- ex_now[Ticker %in% UNIV]
missing_u <- setdiff(UNIV, ex_now$Ticker)
cat(sprintf("[R2] as-of exposures: %d / %d (missing %d)\n", nrow(ex_now), length(UNIV), length(missing_u)))
setorder(ex_now, Ticker)
B <- mk_X(ex_now)
ASSETS <- ex_now$Ticker

## ── Omega / D : 롤링 756일 ──────────────────────────────────────────────────
fdates <- sort(unique(FR$Date)); win_d <- tail(fdates, WIN_D)
Fw <- as.matrix(FR[Date %in% win_d, ..fac_names])
Omega_d <- cov(Fw)
eg <- eigen(Omega_d, symmetric = TRUE)
fl <- max(eg$values) * 1e-6
Omega_d <- eg$vectors %*% diag(pmax(eg$values, fl)) %*% t(eg$vectors)
Omega_d <- (Omega_d + t(Omega_d)) / 2
dimnames(Omega_d) <- list(fac_names, fac_names)
cond_omega <- kappa(Omega_d, exact = TRUE)

Uw <- UR[Date %in% win_d & Ticker %in% ASSETS]
Ds <- Uw[, .(n = .N, v = var(u)), by = Ticker][n >= 120L]
med_v <- median(Ds$v, na.rm = TRUE)
Ds[, sh := pmin(1, 120 / n)]
Ds[, v_sh := (1 - sh) * v + sh * med_v]
Ds[, v_sh := pmax(v_sh, 0.25 * med_v)]
dvec <- setNames(rep(med_v, length(ASSETS)), ASSETS)
dvec[Ds$Ticker] <- Ds$v_sh
n_short <- length(ASSETS) - nrow(Ds)
cat(sprintf("[R2] specific risk: %d/%d estimated (n>=120d), %d fallback to cross-sec median\n",
            nrow(Ds), length(ASSETS), n_short))

Sig_fac_d <- B %*% Omega_d %*% t(B) + diag(dvec[ASSETS])
Sig_fac_d <- (Sig_fac_d + t(Sig_fac_d)) / 2
dimnames(Sig_fac_d) <- list(ASSETS, ASSETS)

## ── 비교 추정기: 동일 창의 일별 수익행렬 ────────────────────────────────────
Dw <- D[Date %in% win_d & Ticker %in% ASSETS, .(Date, Ticker, Ret)]
RM <- dcast(Dw, Date ~ Ticker, value.var = "Ret")
dts <- RM$Date; RM[, Date := NULL]
RM <- as.matrix(RM)
cov_frac <- colMeans(is.finite(RM))
keep_t <- names(cov_frac)[cov_frac >= 0.90]
RMk <- RM[, keep_t, drop = FALSE]
for (j in seq_len(ncol(RMk))) { z <- RMk[, j]; z[!is.finite(z)] <- mean(z, na.rm = TRUE); RMk[, j] <- z }
cat(sprintf("[R2] return matrix: n=%d x p=%d (q=n/p=%.2f) | %d names dropped (<90pct coverage)\n",
            nrow(RMk), ncol(RMk), nrow(RMk)/ncol(RMk), ncol(RM) - ncol(RMk)))

condn <- function(M) tryCatch(kappa(M, exact = TRUE), error = function(e) NA_real_)
mineig <- function(M) min(eigen(M, symmetric = TRUE, only.values = TRUE)$values)

cands <- list()
for (mth in c("sample", "ledoit_wolf", "lw_nls", "gerber_rmt")) {
  t0 <- Sys.time()
  cc <- tryCatch(suppressWarnings(.get_cor_cov(RMk, mth)), error = function(e) NULL)
  if (is.null(cc)) { cands[[mth]] <- list(name = mth, error = "failed"); next }
  Sg <- cc$cov
  cands[[mth]] <- list(name = mth, cov = Sg,
                       condition = condn(Sg), min_eig = mineig(Sg),
                       secs = as.numeric(difftime(Sys.time(), t0, units = "secs")),
                       degenerate = !is.null(attr(cc, "lw_degenerate")))
  cat(sprintf("  [R2] %-12s cond=%.4g min_eig=%.3g (%.1fs)\n", mth,
              cands[[mth]]$condition, cands[[mth]]$min_eig, cands[[mth]]$secs))
}
sub <- ASSETS[ASSETS %in% keep_t]
cands[["factor_bwb_d"]] <- list(name = "factor_bwb_d", cov = Sig_fac_d[sub, sub],
                                condition = condn(Sig_fac_d[sub, sub]),
                                min_eig = mineig(Sig_fac_d[sub, sub]), secs = NA_real_,
                                degenerate = FALSE)
cat(sprintf("  [R2] %-12s cond=%.4g min_eig=%.3g\n", "factor_bwb_d",
            cands[["factor_bwb_d"]]$condition, cands[["factor_bwb_d"]]$min_eig))
cat(sprintf("[R2] FULL 340-name factor Sigma: cond=%.4g min_eig=%.3g\n",
            condn(Sig_fac_d), mineig(Sig_fac_d)))

saveRDS(list(FR = FR, UR = UR, B = B, ASSETS = ASSETS, Omega_d = Omega_d, dvec = dvec,
             Sig_fac_d = Sig_fac_d, fac_names = fac_names, SECLV = SECLV, STY = STY,
             cands = cands, RMk = RMk, dts = dts, keep_t = keep_t, win_d = win_d,
             ex_now = ex_now, r2_xs = mean(r2_list, na.rm = TRUE), cond_omega = cond_omega,
             n_short_specific = n_short, missing_u = missing_u, WIN_D = WIN_D),
        file.path(OUT, "risk_r2.rds"))
cat("[R2] done\n")
