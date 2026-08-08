# =============================================================================
# r3_sigma.R — Step 2~4: Ω(팩터공분산) method shopping + D(고유위험) + Σ = BΩB' + D
#   selection_objective = condition_number (R4 P3 HARD — alpha return 미참조)
#   metric_type = risk_estimate
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt, ...) cat(sprintf(paste0("[r3] ", fmt, "\n"), ...))
source("02_Infrastructure/portfolio/hrp_core.R")   # .get_cor_cov (sample/LW/lw_nls/gerber_rmt)

E   <- as.data.table(read_parquet(file.path(OUT, "exposure_panel.parquet"))); E[, Date := as.Date(Date)]
FR  <- as.data.table(read_parquet(file.path(OUT, "factor_returns.parquet"))); FR[, Date := as.Date(Date)]
RES <- as.data.table(read_parquet(file.path(OUT, "residuals_panel.parquet"))); RES[, Date := as.Date(Date)]
m2  <- readRDS(file.path(OUT, "r2_meta.rds"))
fac_names <- m2$fac_names; STY <- m2$sty; base_sec <- m2$base_sec

AS_OF <- as.Date("2026-06-30")
say("입력: factor_returns 월 %d (%s~%s) | residuals rows=%d | AS_OF=%s",
    nrow(FR), as.character(min(FR$Date)), as.character(max(FR$Date)), nrow(RES), as.character(AS_OF))

# ── Ω: trailing 60m (PIT) ────────────────────────────────────────────────────
WINF <- 60L
fsub <- FR[Date <= AS_OF][order(Date)]
fsub <- tail(fsub, WINF)
FM <- as.matrix(fsub[, ..fac_names]); FM[!is.finite(FM)] <- 0
# 관측 0 인 팩터(해당 창에 부재 섹터) 제거
alive <- which(apply(FM, 2, function(z) stats::sd(z) > 1e-10))
FM <- FM[, alive, drop = FALSE]
say("Ω 창: T=%d, K=%d (활성 팩터 — 창 내 무변동 %d개 제외)", nrow(FM), ncol(FM), length(fac_names)-length(alive))

.cond <- function(M) { ev <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
                       max(ev)/max(min(ev), .Machine$double.eps) }
.minev <- function(M) min(eigen(M, symmetric = TRUE, only.values = TRUE)$values)

method_log <- list(); cand <- c("sample","ledoit_wolf","lw_nls","gerber_rmt")
omegas <- list()
for (mth in cand) {
  cc <- tryCatch(.get_cor_cov(FM, mth), error = function(e) NULL)
  if (is.null(cc)) { method_log[[length(method_log)+1]] <- list(name=mth, condition=NA, min_eigen=NA,
                       selected=FALSE, note="estimator error"); next }
  Om <- cc$cov
  method_log[[length(method_log)+1]] <- list(name = mth, condition = round(.cond(Om), 2),
                                             min_eigen = signif(.minev(Om), 4), selected = FALSE)
  omegas[[mth]] <- Om
  say("  Ω[%-11s] cond=%12.2f  min_eig=%.3e", mth, .cond(Om), .minev(Om))
}
conds <- sapply(method_log, function(z) z$condition)
sel_i <- which.min(ifelse(is.na(conds), Inf, conds))
sel <- method_log[[sel_i]]$name; method_log[[sel_i]]$selected <- TRUE
OMEGA <- omegas[[sel]]
say("선택 estimator = %s (cond %.2f) — selection_objective=condition_number", sel, .cond(OMEGA))
say("method shopping candidates_tried = %d (상한 5)", length(method_log))

# ── D: 고유위험 (trailing 60m 잔차분산 + 횡단면 shrinkage) ────────────────────
rs <- RES[Date <= AS_OF & Date > seq(AS_OF, by = "-60 months", length.out = 2)[2]]
say("D 창 잔차: rows=%d, 월 %d, 종목 %d", nrow(rs), uniqueN(rs$Date), uniqueN(rs$Ticker))
dstat <- rs[, .(n = .N, sv = stats::var(resid)), by = Ticker][n >= 24]
prior <- median(dstat$sv, na.rm = TRUE)
dstat[, w := n / (n + 24)]
dstat[, spec_var := w * sv + (1 - w) * prior]
say("고유분산: 종목 %d | 중앙 sd %.4f (연율 %.3f) | prior sd %.4f",
    nrow(dstat), sqrt(median(dstat$spec_var)), sqrt(median(dstat$spec_var)*12), sqrt(prior))

# ── B: as_of 노출 ────────────────────────────────────────────────────────────
alpha_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json")
tk25 <- names(alpha_pkg$alpha_vector)
say("alpha_vector 종목 %d", length(tk25))
Eo <- E[Date == AS_OF]
say("AS_OF exposure rows=%d | 25종 중 노출 보유 %d", nrow(Eo), sum(tk25 %in% Eo$Ticker))
miss <- setdiff(tk25, Eo$Ticker); if (length(miss)) say("  노출 결측 종목: %s", paste(miss, collapse=","))

build_B <- function(tickers, Edt, fnames) {
  sub <- Edt[Ticker %in% tickers]
  sub[, sec := as.character(Sector)]
  B <- matrix(0, nrow(sub), length(fnames), dimnames = list(sub$Ticker, fnames))
  if ("MKT" %in% fnames) B[, "MKT"] <- 1
  for (s in unique(sub$sec)) { cn <- paste0("SEC_", s); if (cn %in% fnames) B[, cn] <- as.numeric(sub$sec == s) }
  for (s in intersect(STY, fnames)) B[, s] <- ifelse(is.finite(sub[[s]]), sub[[s]], 0)
  B
}
fn_alive <- colnames(OMEGA)
B25 <- build_B(tk25, Eo, fn_alive)
say("B(25 x %d) 구성 완료 — 커버 종목 %d", ncol(B25), nrow(B25))

d25 <- dstat[match(rownames(B25), Ticker)]$spec_var
d25[!is.finite(d25)] <- prior
SIG <- B25 %*% OMEGA %*% t(B25) + diag(d25)
SIG <- (SIG + t(SIG))/2
cn_sig <- .cond(SIG); me_sig <- .minev(SIG)
say("Σ(25x25): cond=%.2f  min_eigen=%.3e  PSD=%s", cn_sig, me_sig, me_sig > -1e-12)
say("Σ 연율 변동 중앙 %.3f  (범위 %.3f ~ %.3f)",
    median(sqrt(diag(SIG)*12)), min(sqrt(diag(SIG)*12)), max(sqrt(diag(SIG)*12)))

# ── 위험 분해 (EW 25 기준 — 비중 제안 아님, 계약상 진단 기준 포트폴리오) ─────
w <- rep(1/nrow(B25), nrow(B25))
var_tot <- as.numeric(t(w) %*% SIG %*% w)
var_spec <- sum(w^2 * d25)
var_fac <- var_tot - var_spec
say("EW-25 예측 위험: 총 연율 %.4f | 팩터 %.1f%% | 고유 %.1f%%",
    sqrt(var_tot*12), 100*var_fac/var_tot, 100*var_spec/var_tot)

# 팩터별 기여 (marginal: x_k * (Ω x)_k)
x <- as.numeric(t(B25) %*% w); names(x) <- fn_alive
contrib <- x * as.numeric(OMEGA %*% x)
ctab <- data.table(factor = fn_alive, exposure = round(x,4),
                   var_contrib = contrib, share = contrib/var_tot)[order(-share)]
say("공동위험 상위 (총분산 대비 %%):"); print(head(ctab[, .(factor, exposure, share = round(100*share,2))], 10))

# 그룹 합산
grp <- function(p) sum(ctab[grepl(p, factor)]$var_contrib)/var_tot
say("그룹 share: MKT %.3f | SECTOR %.3f | STYLE %.3f | SPECIFIC %.3f",
    ctab[factor=="MKT"]$share, grp("^SEC_"), sum(ctab[factor %in% STY]$share), var_spec/var_tot)

# ── 산출 ────────────────────────────────────────────────────────────────────
covdt <- as.data.table(SIG, keep.rownames = "Ticker")
write_parquet(covdt, "stage_artifacts/WT_D20260808_001/covariance.parquet")
write_parquet(as.data.table(OMEGA, keep.rownames = "factor"), file.path(OUT, "factor_covariance.parquet"))
write_parquet(as.data.table(B25, keep.rownames = "Ticker"), file.path(OUT, "exposure_matrix.parquet"))
write_parquet(data.table(Ticker = rownames(B25), specific_var = d25,
                         specific_vol_ann = sqrt(d25*12)), file.path(OUT, "specific_risk.parquet"))
saveRDS(list(OMEGA=OMEGA, SIG=SIG, B25=B25, d25=d25, dstat=dstat, prior=prior,
             method_log=method_log, selected=sel, cond_sig=cn_sig, min_eig_sig=me_sig,
             ctab=ctab, var_tot=var_tot, var_spec=var_spec, fn_alive=fn_alive, tk25=tk25),
        file.path(OUT, "r3_sigma.rds"))
say("저장: covariance.parquet + factor_covariance/exposure_matrix/specific_risk")
