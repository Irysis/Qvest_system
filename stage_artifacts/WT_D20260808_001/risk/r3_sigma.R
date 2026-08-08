# =============================================================================
# r3_sigma.R — Ω method shopping + D + Σ = BΩB' + D
#
#   ★selection_objective = shrinkage_quality  (R4 P3 enum)
#     사유: 1차 실행에서 objective=condition_number 로 고르니 inline linear LW 가
#     cond=1.00 (Σ≈μI, 상관구조 전멸) 로 "이겼다". 팩터 분산이 sector(연 28%) vs
#     style(연 10%) 로 자릿수가 다른데 μI 로 축약하면 style 분산을 6배 부풀린다
#     (EW-25 예측 연변동 77.6% = 실현 대비 3배 이상). cond 최소화는 퇴화를 상으로
#     준다 → 추정품질(OOS 가우시안 손실)로 교체. alpha return 미참조(HARD 준수).
#   metric_type = risk_estimate
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt, ...) cat(sprintf(paste0("[r3] ", fmt, "\n"), ...))
source("02_Infrastructure/portfolio/hrp_core.R")

E   <- as.data.table(read_parquet(file.path(OUT, "exposure_panel.parquet"))); E[, Date := as.Date(Date)]
FR  <- as.data.table(read_parquet(file.path(OUT, "factor_returns.parquet"))); FR[, Date := as.Date(Date)]
RES <- as.data.table(read_parquet(file.path(OUT, "residuals_panel.parquet"))); RES[, Date := as.Date(Date)]
m2  <- readRDS(file.path(OUT, "r2_meta.rds")); fac_names <- m2$fac_names; STY <- m2$sty

AS_OF <- as.Date("2026-06-30"); WINF <- 60L
say("입력 factor_returns 월 %d (%s~%s) | residuals rows=%d | AS_OF %s",
    nrow(FR), as.character(min(FR$Date)), as.character(max(FR$Date)), nrow(RES), as.character(AS_OF))

.cond  <- function(M){ ev <- eigen(M, symmetric=TRUE, only.values=TRUE)$values; max(ev)/max(min(ev), .Machine$double.eps) }
.minev <- function(M) min(eigen(M, symmetric=TRUE, only.values=TRUE)$values)

# ── 추가 후보: 대각 보존 상관 shrinkage (target = diag(S)) ───────────────────
.lw_diagtarget <- function(X, delta = NULL) {
  S <- stats::cov(X); p <- ncol(S); n <- nrow(X)
  sds <- sqrt(diag(S)); R <- S / outer(sds, sds); diag(R) <- 1
  # 유한표본 상관 잡음 기반 shrink 강도 (Schafer-Strimmer 유형)
  Xs <- scale(X); w <- array(NA_real_, c(n, p, p))
  for (i in 1:p) for (j in 1:p) w[, i, j] <- Xs[, i] * Xs[, j]
  varr <- apply(w, c(2,3), stats::var) * n / (n-1)^2
  off <- upper.tri(R)
  d <- if (sum(R[off]^2) > 0) sum(varr[off]) / sum(R[off]^2) else 1
  d <- min(max(d, 0), 1)
  if (!is.null(delta)) d <- delta
  Rs <- (1 - d) * R; diag(Rs) <- 1
  list(cov = Rs * outer(sds, sds), delta = d)
}

# ── 추정기 후보 5 (상한 5) ───────────────────────────────────────────────────
est_fun <- list(
  sample      = function(X) stats::cov(X),
  ledoit_wolf = function(X) .get_cor_cov(X, "ledoit_wolf")$cov,
  lw_nls      = function(X) .get_cor_cov(X, "lw_nls")$cov,
  gerber_rmt  = function(X) .get_cor_cov(X, "gerber_rmt")$cov,
  lw_diag     = function(X) .lw_diagtarget(X)$cov
)

# ── 추정품질: rolling OOS 가우시안 손실 (Stein loss) — alpha 미참조 ──────────
# L = tr(Ω^-1 S_oos) - log det(Ω^-1 S_oos) - K   (작을수록 좋음; 정확추정 시 ≈0)
FRo <- FR[order(Date)]
dts <- FRo$Date
oos_eval <- function(fname) {
  losses <- c(); conds <- c()
  starts <- seq(WINF + 1L, length(dts) - 12L, by = 6L)
  for (s in starts) {
    Xtr <- as.matrix(FRo[(s-WINF):(s-1), ..fac_names]); Xte <- as.matrix(FRo[s:(s+11), ..fac_names])
    Xtr[!is.finite(Xtr)] <- 0; Xte[!is.finite(Xte)] <- 0
    al <- which(apply(Xtr, 2, stats::sd) > 1e-10 & apply(Xte, 2, stats::sd) > 1e-10)
    if (length(al) < 5) next
    Xtr <- Xtr[, al, drop=FALSE]; Xte <- Xte[, al, drop=FALSE]
    Om <- tryCatch(est_fun[[fname]](Xtr), error = function(e) NULL); if (is.null(Om)) next
    if (.minev(Om) <= 1e-14) next
    Se <- stats::cov(Xte); Oi <- tryCatch(solve(Om), error=function(e) NULL); if (is.null(Oi)) next
    M <- Oi %*% Se; ev <- Re(eigen(M, only.values = TRUE)$values)
    if (any(ev <= 0)) next
    losses <- c(losses, sum(ev) - sum(log(ev)) - ncol(Xtr))
    conds  <- c(conds, .cond(Om))
  }
  list(loss_med = if(length(losses)) median(losses) else NA_real_,
       loss_mean = if(length(losses)) mean(losses) else NA_real_,
       n_folds = length(losses), cond_med = if(length(conds)) median(conds) else NA_real_)
}

fsub <- tail(FRo[Date <= AS_OF], WINF)
FM0 <- as.matrix(fsub[, ..fac_names]); FM0[!is.finite(FM0)] <- 0
alive <- which(apply(FM0, 2, stats::sd) > 1e-10); FM <- FM0[, alive, drop = FALSE]
say("Ω 창 T=%d K=%d (무변동 %d 제외)", nrow(FM), ncol(FM), length(fac_names)-length(alive))

method_log <- list()
for (mth in names(est_fun)) {
  Om <- tryCatch(est_fun[[mth]](FM), error = function(e) NULL)
  ev <- oos_eval(mth)
  rec <- list(name = mth,
              condition = if (is.null(Om)) NA_real_ else round(.cond(Om), 2),
              min_eigen = if (is.null(Om)) NA_real_ else signif(.minev(Om), 4),
              oos_stein_loss_median = round(ev$loss_med, 3),
              oos_folds = ev$n_folds, selected = FALSE)
  method_log[[mth]] <- rec
  say("  Ω[%-11s] cond=%14.2f min_eig=%10.3e | OOS Stein loss(중앙) %8.3f (fold %d)",
      mth, rec$condition, rec$min_eigen, rec$oos_stein_loss_median, ev$n_folds)
}
ls_ <- sapply(method_log, function(z) z$oos_stein_loss_median)
sel <- names(which.min(ifelse(is.na(ls_), Inf, ls_)))
method_log[[sel]]$selected <- TRUE
OMEGA <- est_fun[[sel]](FM)
say("선택 = %s | cond %.2f | min_eig %.3e (objective = shrinkage_quality/OOS Stein loss)",
    sel, .cond(OMEGA), .minev(OMEGA))
say("method shopping candidates_tried = %d (상한 5)", length(method_log))
if (.cond(OMEGA) > 500) {
  say("cond > 500 → eigen-floor 재추정 (init prompt hard_constraints)")
  eg <- eigen(OMEGA, symmetric = TRUE); fl <- max(eg$values)/500
  OMEGA <- eg$vectors %*% diag(pmax(eg$values, fl)) %*% t(eg$vectors)
  OMEGA <- (OMEGA + t(OMEGA))/2
  say("  eigen-floor 후 cond %.2f", .cond(OMEGA))
}
dimnames(OMEGA) <- list(colnames(FM), colnames(FM))

# ── D: 고유위험 + 단일종목 bias 검정 (추정품질, alpha 미참조) ────────────────
d_from <- function(asof) {
  lo <- seq(asof, by = "-60 months", length.out = 2)[2]
  rs <- RES[Date <= asof & Date > lo]
  ds <- rs[, .(n = .N, sv = stats::var(resid)), by = Ticker][n >= 24]
  pri <- median(ds$sv, na.rm = TRUE); ds[, w := n/(n+24)][, spec_var := w*sv + (1-w)*pri]
  list(ds = ds, prior = pri)
}
D0 <- d_from(AS_OF); dstat <- D0$ds; prior <- D0$prior
say("D: 종목 %d | 고유 연변동 중앙 %.3f", nrow(dstat), sqrt(median(dstat$spec_var)*12))
# bias: z_it = e_it / sd_hat(i, t-1) — trailing 추정으로 표준화한 다음달 잔차
bias_z <- c()
for (a in seq(as.Date("2016-06-30"), AS_OF, by = "3 months")) {
  a <- as.Date(a); nxt <- RES[Date > a][order(Date)][1]$Date
  if (is.na(nxt)) next
  dd <- d_from(a)$ds
  nr <- merge(RES[Date == nxt], dd[, .(Ticker, spec_var)], by = "Ticker")
  if (!nrow(nr)) next
  bias_z <- c(bias_z, nr$resid / sqrt(nr$spec_var))
}
say("고유위험 bias 통계 sd(z) = %.3f (n=%d) — 1.0 = 무편향, >1 과소예측", stats::sd(bias_z, na.rm=TRUE), length(bias_z))

# ── B / Σ ────────────────────────────────────────────────────────────────────
alpha_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json")
tk25 <- names(alpha_pkg$alpha_vector); Eo <- E[Date == AS_OF]
fn_alive <- colnames(OMEGA)
build_B <- function(tickers, Edt, fnames) {
  sub <- Edt[Ticker %in% tickers]; sub[, sec := as.character(Sector)]
  B <- matrix(0, nrow(sub), length(fnames), dimnames = list(sub$Ticker, fnames))
  if ("MKT" %in% fnames) B[, "MKT"] <- 1
  for (s in unique(sub$sec)) { cn <- paste0("SEC_", s); if (cn %in% fnames) B[, cn] <- as.numeric(sub$sec == s) }
  for (s in intersect(STY, fnames)) B[, s] <- ifelse(is.finite(sub[[s]]), sub[[s]], 0)
  B
}
B25 <- build_B(tk25, Eo, fn_alive)
say("B(%d x %d) — alpha_vector 25종 중 노출 커버 %d", nrow(B25), ncol(B25), nrow(B25))
d25 <- dstat[match(rownames(B25), Ticker)]$spec_var; d25[!is.finite(d25)] <- prior
SIG <- B25 %*% OMEGA %*% t(B25) + diag(d25); SIG <- (SIG+t(SIG))/2
say("Σ(25x25) cond=%.2f min_eig=%.3e PSD=%s | 개별 연변동 중앙 %.3f [%.3f, %.3f]",
    .cond(SIG), .minev(SIG), .minev(SIG) > -1e-12,
    median(sqrt(diag(SIG)*12)), min(sqrt(diag(SIG)*12)), max(sqrt(diag(SIG)*12)))

w <- rep(1/nrow(B25), nrow(B25))
var_tot <- as.numeric(t(w)%*%SIG%*%w); var_spec <- sum(w^2*d25)
say("EW-25 예측 연변동 %.4f | 팩터 %.1f%% | 고유 %.1f%%",
    sqrt(var_tot*12), 100*(var_tot-var_spec)/var_tot, 100*var_spec/var_tot)
x <- as.numeric(t(B25)%*%w); names(x) <- fn_alive
contrib <- x * as.numeric(OMEGA %*% x)
ctab <- data.table(factor=fn_alive, exposure=round(x,4), var_contrib=contrib,
                   share=contrib/var_tot)[order(-share)]
print(head(ctab[, .(factor, exposure, share_pct = round(100*share,2))], 10))
say("그룹 share: MKT %.3f | SECTOR %.3f | STYLE %.3f | SPECIFIC %.3f",
    ctab[factor=="MKT"]$share, sum(ctab[grepl("^SEC_",factor)]$var_contrib)/var_tot,
    sum(ctab[factor %in% STY]$var_contrib)/var_tot, var_spec/var_tot)

covdt <- as.data.table(SIG, keep.rownames="Ticker")
write_parquet(covdt, "stage_artifacts/WT_D20260808_001/covariance.parquet")
write_parquet(as.data.table(OMEGA, keep.rownames="factor"), file.path(OUT,"factor_covariance.parquet"))
write_parquet(as.data.table(B25, keep.rownames="Ticker"), file.path(OUT,"exposure_matrix.parquet"))
write_parquet(data.table(Ticker=rownames(B25), specific_var=d25, specific_vol_ann=sqrt(d25*12)),
              file.path(OUT,"specific_risk.parquet"))
saveRDS(list(OMEGA=OMEGA, SIG=SIG, B25=B25, d25=d25, dstat=dstat, prior=prior, method_log=method_log,
             selected=sel, cond_sig=.cond(SIG), min_eig_sig=.minev(SIG), ctab=ctab, var_tot=var_tot,
             var_spec=var_spec, fn_alive=fn_alive, tk25=tk25, bias_sd=stats::sd(bias_z,na.rm=TRUE),
             bias_n=length(bias_z), build_B=build_B, STY=STY),
        file.path(OUT,"r3_sigma.rds"))
say("저장 완료")
