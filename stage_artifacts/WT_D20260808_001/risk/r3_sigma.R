# =============================================================================
# r3_sigma.R — Ω method shopping + D + Σ = BΩB' + D  (+ 예측-실현 bias 검정)
#
#   ★selection_objective = shrinkage_quality  (R4 P3 enum)
#     1차 시도에서 objective=condition_number 로 고르니 inline linear LW 가 cond=1.00
#     (Σ≈μI, 상관구조 전멸) 로 "이겼다" — 팩터 분산 자릿수가 sector vs style 로 달라
#     μI 축약이 style 분산을 부풀렸다(EW-25 예측 연변동 0.776). cond 최소화는 퇴화에
#     상을 준다 ⇒ 추정품질(rolling OOS 가우시안 NLL + bias 통계)로 교체. alpha 미참조.
#   metric_type = risk_estimate / risk_validation
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt, ...) cat(sprintf(paste0("[r3] ", fmt, "\n"), ...))
source("02_Infrastructure/portfolio/hrp_core.R")

E   <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[, Date := as.Date(Date)]
FR  <- as.data.table(read_parquet(file.path(OUT,"factor_returns.parquet"))); FR[, Date := as.Date(Date)]
RES <- as.data.table(read_parquet(file.path(OUT,"residuals_panel.parquet"))); RES[, Date := as.Date(Date)]
SECM<- as.data.table(read_parquet(file.path(OUT,"sector_map.parquet"))); SECM[, Date := as.Date(Date)]
m2  <- readRDS(file.path(OUT,"r2_meta.rds"))
fac_names <- m2$fac_names; STY <- m2$sty; base_sec <- m2$base_sec; sec_use <- m2$sec_use
SC <- as.data.table(m2$sec_counts); SC[, Date := as.Date(Date)]

AS_OF <- as.Date("2026-06-30"); WINF <- 60L
say("입력 factor_returns 월 %d (%s~%s) | residuals rows=%d | sector_map rows=%d | AS_OF %s",
    nrow(FR), as.character(min(FR$Date)), as.character(max(FR$Date)), nrow(RES), nrow(SECM), as.character(AS_OF))

.cond  <- function(M){ ev <- eigen(M, symmetric=TRUE, only.values=TRUE)$values; max(ev)/max(min(ev), .Machine$double.eps) }
.minev <- function(M) min(eigen(M, symmetric=TRUE, only.values=TRUE)$values)

.lw_diagtarget <- function(X) {   # 대각(분산) 보존 · 상관만 shrink
  S <- stats::cov(X); p <- ncol(S); n <- nrow(X)
  sds <- sqrt(diag(S)); R <- S/outer(sds,sds); diag(R) <- 1
  Xs <- scale(X); num <- 0; den <- 0
  for (i in 1:(p-1)) for (j in (i+1):p) {
    v <- stats::var(Xs[,i]*Xs[,j])*n/(n-1)^2
    num <- num + v; den <- den + R[i,j]^2
  }
  d <- if (den > 0) min(max(num/den, 0), 1) else 1
  Rs <- (1-d)*R; diag(Rs) <- 1
  Rs * outer(sds, sds)
}
est_fun <- list(
  sample      = function(X) stats::cov(X),
  ledoit_wolf = function(X) .get_cor_cov(X,"ledoit_wolf")$cov,
  lw_nls      = function(X) .get_cor_cov(X,"lw_nls")$cov,
  gerber_rmt  = function(X) .get_cor_cov(X,"gerber_rmt")$cov,
  lw_diag     = .lw_diagtarget
)

# ── 추정품질 A: rolling OOS 가우시안 NLL  L = logdet(Ω) + tr(Ω^-1 S_oos) ─────
#    (Stein loss 는 S_oos 가 특이하면 정의 불가 — 1차 시도에서 fold 0 이 났다.
#     NLL 은 특이 S_oos 에도 정의되는 proper scoring rule.)
FRo <- FR[order(Date)]; nT <- nrow(FRo)
oos_nll <- function(fname, test_len = 24L, step = 6L) {
  Ls <- c()
  for (s in seq(WINF+1L, nT-test_len, by = step)) {
    Xtr <- as.matrix(FRo[(s-WINF):(s-1), ..fac_names]); Xte <- as.matrix(FRo[s:(s+test_len-1L), ..fac_names])
    Xtr[!is.finite(Xtr)] <- 0; Xte[!is.finite(Xte)] <- 0
    al <- which(apply(Xtr,2,stats::sd) > 1e-10)
    Xtr <- Xtr[,al,drop=FALSE]; Xte <- Xte[,al,drop=FALSE]
    Om <- tryCatch(est_fun[[fname]](Xtr), error=function(e) NULL); if (is.null(Om)) next
    if (.minev(Om) <= 1e-14) next
    Se <- stats::cov(Xte); Oi <- tryCatch(solve(Om), error=function(e) NULL); if (is.null(Oi)) next
    ld <- determinant(Om, logarithm=TRUE); if (!is.finite(ld$modulus)) next
    Ls <- c(Ls, as.numeric(ld$modulus) + sum(diag(Oi %*% Se)))
  }
  Ls
}

fsub <- tail(FRo[Date <= AS_OF], WINF)
FM0 <- as.matrix(fsub[, ..fac_names]); FM0[!is.finite(FM0)] <- 0
alive <- which(apply(FM0,2,stats::sd) > 1e-10); FM <- FM0[,alive,drop=FALSE]
say("Ω 창 T=%d K=%d (무변동 %d 제외)", nrow(FM), ncol(FM), length(fac_names)-length(alive))

method_log <- list()
for (mth in names(est_fun)) {
  Om <- tryCatch(est_fun[[mth]](FM), error=function(e) NULL)
  Ls <- oos_nll(mth)
  method_log[[mth]] <- list(name=mth,
    condition = if (is.null(Om)) NA_real_ else round(.cond(Om),2),
    min_eigen = if (is.null(Om)) NA_real_ else signif(.minev(Om),4),
    oos_gaussian_nll_median = if (length(Ls)) round(median(Ls),4) else NA_real_,
    oos_folds = length(Ls), selected = FALSE)
  say("  Ω[%-11s] cond=%14.2f min_eig=%10.3e | OOS NLL(중앙) %9.4f (fold %d)",
      mth, method_log[[mth]]$condition, method_log[[mth]]$min_eigen,
      method_log[[mth]]$oos_gaussian_nll_median, length(Ls))
}
nl <- sapply(method_log, function(z) z$oos_gaussian_nll_median)
sel <- names(which.min(ifelse(is.na(nl), Inf, nl))); method_log[[sel]]$selected <- TRUE
OMEGA <- est_fun[[sel]](FM); dimnames(OMEGA) <- list(colnames(FM), colnames(FM))
say("선택 = %s | cond %.2f | min_eig %.3e (objective=shrinkage_quality/OOS Gaussian NLL)",
    sel, .cond(OMEGA), .minev(OMEGA))
cond_pre <- .cond(OMEGA)
if (cond_pre > 500) {
  say("cond %.1f > 500 → 대각보존 eigen-floor 재추정 (trace 보존)", cond_pre)
  eg <- eigen(OMEGA, symmetric=TRUE); tr0 <- sum(eg$values)
  fl <- max(eg$values)/500; v2 <- pmax(eg$values, fl); v2 <- v2 * tr0/sum(v2)
  OMEGA <- eg$vectors %*% diag(v2) %*% t(eg$vectors); OMEGA <- (OMEGA+t(OMEGA))/2
  dimnames(OMEGA) <- list(colnames(FM), colnames(FM))
  say("  floor 후 cond %.2f (trace 보존 %.6f → %.6f)", .cond(OMEGA), tr0, sum(diag(OMEGA)))
}
cond_post <- .cond(OMEGA)

# ── D ────────────────────────────────────────────────────────────────────────
d_from <- function(asof) {
  lo <- seq(asof, by="-60 months", length.out=2)[2]
  ds <- RES[Date <= asof & Date > lo][, .(n=.N, sv=stats::var(resid)), by=Ticker][n>=24]
  pri <- median(ds$sv, na.rm=TRUE); ds[, w := n/(n+24)][, spec_var := w*sv+(1-w)*pri]
  list(ds=ds, prior=pri)
}
D0 <- d_from(AS_OF); dstat <- D0$ds; prior <- D0$prior
say("D 종목 %d | 고유 연변동 중앙 %.3f", nrow(dstat), sqrt(median(dstat$spec_var)*12))
bias_z <- c()
for (a in seq(as.Date("2011-06-30"), AS_OF, by="3 months")) {
  a <- as.Date(a); nxt <- RES[Date > a][order(Date)][1]$Date; if (is.na(nxt)) next
  nr <- merge(RES[Date==nxt], d_from(a)$ds[, .(Ticker, spec_var)], by="Ticker")
  if (nrow(nr)) bias_z <- c(bias_z, nr$resid/sqrt(nr$spec_var))
}
say("고유위험 bias sd(z)=%.3f (n=%d) — 1.0 무편향 / >1 과소예측", stats::sd(bias_z,na.rm=TRUE), length(bias_z))

# ── B 구성 (sum-to-zero 섹터 코딩 동일 적용) ─────────────────────────────────
build_B <- function(tickers, asof, fnames) {
  sub <- E[Date==asof & Ticker %in% tickers]
  sm <- SECM[Date==asof]; sub <- merge(sub, sm[, .(Ticker, sec)], by="Ticker", all.x=TRUE)
  sub[is.na(sec), sec := "OTHER"]
  cn <- SC[Date==asof]; nb <- cn[sec==base_sec]$N; if (!length(nb) || nb==0) nb <- 1
  B <- matrix(0, nrow(sub), length(fnames), dimnames=list(sub$Ticker, fnames))
  if ("MKT" %in% fnames) B[,"MKT"] <- 1
  isb <- as.numeric(sub$sec == base_sec)
  for (s in sec_use) {
    col <- paste0("SEC_", s); if (!(col %in% fnames)) next
    ns <- cn[sec==s]$N; ns <- if (length(ns)) ns else 0
    B[, col] <- as.numeric(sub$sec==s) - (ns/nb)*isb
  }
  for (s in intersect(STY, fnames)) B[,s] <- ifelse(is.finite(sub[[s]]), sub[[s]], 0)
  B
}

# ── 추정품질 B: 포트폴리오 수준 예측-실현 bias (무작위 25종 EW) ──────────────
#   metric_type=risk_validation. 실현치는 단일기간 횡단면 가중평균(복리·성과주장 아님).
set.seed(20260808)
val <- list()
vdates <- FRo$Date[FRo$Date >= as.Date("2011-01-01") & FRo$Date < AS_OF]
for (d in vdates) {
  d <- as.Date(d)
  Om_t <- tryCatch({ ft <- tail(FRo[Date < d], WINF)
      if (nrow(ft) < WINF) NULL else {
        X <- as.matrix(ft[, ..fac_names]); X[!is.finite(X)] <- 0
        a <- which(apply(X,2,stats::sd)>1e-10); est_fun[[sel]](X[,a,drop=FALSE]) } },
      error=function(e) NULL)
  if (is.null(Om_t)) next
  dd <- d_from(d)$ds
  pool <- E[Date==d & Ticker %in% dd$Ticker & is.finite(Ret_1m)]$Ticker
  if (length(pool) < 60) next
  Bt <- tryCatch(build_B(pool, d, colnames(Om_t)), error=function(e) NULL); if (is.null(Bt)) next
  dv <- dd[match(rownames(Bt), Ticker)]$spec_var; dv[!is.finite(dv)] <- prior
  rt <- E[Date==d][match(rownames(Bt), Ticker)]$Ret_1m
  for (k in 1:20) {
    ix <- sample(seq_len(nrow(Bt)), 25)
    w <- rep(1/25, 25); x <- as.numeric(t(Bt[ix,,drop=FALSE]) %*% w)
    v <- as.numeric(t(x) %*% Om_t %*% x) + sum(w^2*dv[ix])
    if (!is.finite(v) || v <= 0) next
    rp <- sum(w*rt[ix]); if (!is.finite(rp)) next
    val[[length(val)+1]] <- c(pred_sd=sqrt(v), realized=rp)
  }
}
VM <- do.call(rbind, val)
say("포트폴리오 bias 검정: n=%d 무작위 EW-25 | 예측 연변동 중앙 %.3f | sd(z)=%.3f",
    nrow(VM), median(VM[,"pred_sd"])*sqrt(12), stats::sd(VM[,"realized"]/VM[,"pred_sd"]))
say("  (sd(z) 1.0 = 무편향, >1 = Σ 과소예측, <1 = Σ 과대예측)")

# ── Σ ────────────────────────────────────────────────────────────────────────
alpha_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json")
tk25 <- names(alpha_pkg$alpha_vector)
B25 <- build_B(tk25, AS_OF, colnames(OMEGA))
say("B(%d x %d) — alpha_vector 25종 커버 %d", nrow(B25), ncol(B25), nrow(B25))
d25 <- dstat[match(rownames(B25), Ticker)]$spec_var; d25[!is.finite(d25)] <- prior
SIG <- B25 %*% OMEGA %*% t(B25) + diag(d25); SIG <- (SIG+t(SIG))/2
say("Σ(25x25) cond=%.2f min_eig=%.3e PSD=%s | 개별 예측 연변동 중앙 %.3f [%.3f, %.3f]",
    .cond(SIG), .minev(SIG), .minev(SIG) > -1e-12,
    median(sqrt(diag(SIG)*12)), min(sqrt(diag(SIG)*12)), max(sqrt(diag(SIG)*12)))
w <- rep(1/nrow(B25), nrow(B25))
var_tot <- as.numeric(t(w)%*%SIG%*%w); var_spec <- sum(w^2*d25)
say("EW-25 예측 연변동 %.4f | 팩터 %.1f%% | 고유 %.1f%%",
    sqrt(var_tot*12), 100*(var_tot-var_spec)/var_tot, 100*var_spec/var_tot)
x <- as.numeric(t(B25)%*%w); names(x) <- colnames(OMEGA)
ctab <- data.table(factor=colnames(OMEGA), exposure=round(x,4),
                   var_contrib = x*as.numeric(OMEGA%*%x))[, share := var_contrib/var_tot][order(-share)]
print(head(ctab[, .(factor, exposure, share_pct=round(100*share,2))], 10))
grp_mkt <- ctab[factor=="MKT"]$share
grp_sec <- sum(ctab[grepl("^SEC_",factor)]$var_contrib)/var_tot
grp_sty <- sum(ctab[factor %in% STY]$var_contrib)/var_tot
say("그룹 share: MKT %.3f | SECTOR %.3f | STYLE %.3f | SPECIFIC %.3f",
    grp_mkt, grp_sec, grp_sty, var_spec/var_tot)

write_parquet(as.data.table(SIG, keep.rownames="Ticker"), "stage_artifacts/WT_D20260808_001/covariance.parquet")
write_parquet(as.data.table(OMEGA, keep.rownames="factor"), file.path(OUT,"factor_covariance.parquet"))
write_parquet(as.data.table(B25, keep.rownames="Ticker"), file.path(OUT,"exposure_matrix.parquet"))
write_parquet(data.table(Ticker=rownames(B25), specific_var=d25, specific_vol_ann=sqrt(d25*12)),
              file.path(OUT,"specific_risk.parquet"))
saveRDS(list(OMEGA=OMEGA, SIG=SIG, B25=B25, d25=d25, dstat=dstat, prior=prior, method_log=method_log,
             selected=sel, cond_pre=cond_pre, cond_post=cond_post, cond_sig=.cond(SIG),
             min_eig_sig=.minev(SIG), ctab=ctab, var_tot=var_tot, var_spec=var_spec,
             tk25=tk25, bias_sd=stats::sd(bias_z,na.rm=TRUE), bias_n=length(bias_z),
             port_bias_sd=stats::sd(VM[,"realized"]/VM[,"pred_sd"]), port_bias_n=nrow(VM),
             grp=c(MKT=grp_mkt, SECTOR=grp_sec, STYLE=grp_sty, SPECIFIC=var_spec/var_tot)),
        file.path(OUT,"r3_sigma.rds"))
say("저장 완료")
