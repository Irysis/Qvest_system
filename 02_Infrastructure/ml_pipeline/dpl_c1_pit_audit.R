#!/usr/bin/env Rscript
# dpl_c1_pit_audit.R — Qvest cycle1: 92f augmented panel PIT 검증 (Cycle 50 lookahead 재발 방지).
#
# (1) forward-label 독립 재계산: panel Ret_1m이 진짜 month-end→next-month-end FORWARD인지
#     rawdata에서 독립 재산출 대조. forward match ≥ 0.95 AND backward match < 0.10.
# (2) RESIDMOM 피처 backward-only 검증: RESIDMOM__lvl/__slp이 forward label과 비정상 상관
#     (트리비얼 lookahead) 아닌지. residual-mom은 month-end signal이라 forward ret와 약한
#     예측상관(IC~0.016)은 정상 — 강한 동시상관(|cor|>0.3)이면 lookahead 의심.
# (3) bear_date_audit.R (있으면) — benchmark forward 21d label semantics.
#
# Exit: 0 = ALL PASS, 1 = ANY FAIL (sweep 진입 차단).

suppressPackageStartupMessages({ library(arrow); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "WT_DPL_C1")
PANEL <- file.path(OUT, "dpl_feature_panel.parquet")
RAW  <- file.path(ROOT, ".cache", "rawdata.parquet")
fail <- function(msg) { cat("[c1_pit][FAIL]", msg, "\n"); quit(status = 1L) }

# ── (1) forward label recompute ──────────────────────────────────────
cat("[c1_pit] (1) panel forward-label independent recompute ...\n")
pan <- as.data.table(read_parquet(PANEL))
pan[, ymk := format(as.Date(date), "%Y-%m")]
raw <- as.data.table(read_parquet(RAW, col_select = c("Date","Ticker","Close")))
raw[, Date := as.Date(Date)]; raw <- raw[!is.na(Close) & Close > 0]
raw[, ymk := format(Date, "%Y-%m")]; setorder(raw, Ticker, Date)
me <- raw[, .SD[.N], by = .(Ticker, ymk)]; setorder(me, Ticker, ymk)
me[, close_next := shift(Close, n = 1L, type = "lead"), by = Ticker]
me[, fwd_recompute := close_next / Close - 1]
me[, close_prev := shift(Close, n = 1L, type = "lag"), by = Ticker]
me[, bwd_recompute := Close / close_prev - 1]
cmp <- merge(pan[, .(ymk, Ticker, Ret_1m)], me[, .(ymk, Ticker, fwd_recompute, bwd_recompute)],
             by = c("ymk","Ticker"), all.x = TRUE)
cmp <- cmp[!is.na(Ret_1m) & !is.na(fwd_recompute)]
set.seed(42); samp <- cmp[sample(.N, min(800L, .N))]
samp[, fwd_match := abs(Ret_1m - fwd_recompute) < 1e-6]
samp[, bwd_match := !is.na(bwd_recompute) & abs(Ret_1m - bwd_recompute) < 1e-6]
fwd_rate <- mean(samp$fwd_match); bwd_rate <- mean(samp$bwd_match)
cat(sprintf("[c1_pit] forward_match=%.4f backward_match=%.4f (n=%d)\n", fwd_rate, bwd_rate, nrow(samp)))
label_pass <- (fwd_rate >= 0.95) && (bwd_rate < 0.10)

# ── (2) RESIDMOM backward-only (no trivial concurrent lookahead) ──────
cat("[c1_pit] (2) RESIDMOM feature vs forward label correlation ...\n")
sub <- pan[!is.na(Ret_1m) & is.finite(RESIDMOM__lvl)]
cor_lvl <- cor(sub$RESIDMOM__lvl, sub$Ret_1m)
cor_slp <- cor(sub$RESIDMOM__slp, sub$Ret_1m)
cat(sprintf("[c1_pit] cor(RESIDMOM__lvl, fwd_ret)=%.4f  cor(RESIDMOM__slp, fwd_ret)=%.4f\n", cor_lvl, cor_slp))
# legitimate weak predictive corr (IC ~0.016) expected; |cor|>0.30 => concurrent lookahead suspect
residmom_pass <- (abs(cor_lvl) < 0.30) && (abs(cor_slp) < 0.30)
cat(sprintf("[c1_pit] RESIDMOM backward-only -> %s (|cor|<0.30 both)\n", ifelse(residmom_pass,"PASS","FAIL")))

# ── (3) bear_date_audit (optional; benchmark forward semantics) ───────
bear_pass <- NA
bda <- file.path(ROOT, "02_Infrastructure/sanity_checks/bear_date_audit.R")
bm_path <- file.path(ROOT, ".cache/benchmark.parquet")
tgt_path <- file.path(ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/02_targets/targets_full.parquet")
if (file.exists(bda) && file.exists(bm_path) && file.exists(tgt_path)) {
  cat("[c1_pit] (3) bear_date_audit.R ...\n")
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  ba <- tryCatch(system2(rscript, c(shQuote(bda), shQuote(tgt_path), shQuote(bm_path)),
                         stdout = TRUE, stderr = TRUE), error = function(e) { attr(e,"status")<-1L; "" })
  st <- attr(ba, "status"); if (is.null(st)) st <- 0L
  bear_pass <- (st == 0L)
  cat(sprintf("[c1_pit] bear_date_audit exit=%d -> %s\n", st, ifelse(bear_pass,"PASS","FAIL")))
} else {
  cat("[c1_pit] (3) bear_date_audit SKIP (targets_full/benchmark not present — N/A for this panel)\n")
}

overall <- label_pass && residmom_pass && (is.na(bear_pass) || bear_pass)
out <- list(panel_forward_match = fwd_rate, panel_backward_match = bwd_rate, label_pass = label_pass,
            residmom_cor_lvl = cor_lvl, residmom_cor_slp = cor_slp, residmom_pass = residmom_pass,
            bear_date_audit_pass = bear_pass, overall_pass = overall, n_sample = nrow(samp))
jsonlite::write_json(out, file.path(OUT, "pit_audit.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[c1_pit] -> %s\n", file.path(OUT, "pit_audit.json")))
if (!overall) fail("PIT audit failed — sweep 진입 금지.")
cat("[c1_pit] ALL PASS — sweep 진입 허가.\n")
