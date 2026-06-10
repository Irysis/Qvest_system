#!/usr/bin/env Rscript
# dpl_c2_pit_audit.R — Qvest cycle2: 98f panel PIT 검증 (Cycle 50 lookahead 재발 방지).
#
# (1) forward-label 독립 재계산: panel Ret_1m이 month-end→next FORWARD인지 rawdata 대조.
#     forward match >= 0.95 AND backward match < 0.10 (trivial concurrent classification 차단).
# (2) 신규 피처 4종(RESIDMOM/PIOTROSKI/MOHANRAM/NETISSUE) backward-only:
#     각 __lvl/__slp이 forward label과 비정상 동시상관(|cor|>0.30) 아닌지. 약한 예측상관은 정상.
# (3) bear_date_audit.R (해당 자산 있으면) — benchmark forward semantics.
#
# Exit: 0 = ALL PASS, 1 = ANY FAIL (sweep 진입 차단).
suppressPackageStartupMessages({ library(arrow); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "WT_DPL_C2")
PANEL <- file.path(OUT, "dpl_feature_panel.parquet")
RAW  <- file.path(ROOT, ".cache", "rawdata.parquet")
fail <- function(msg) { cat("[c2_pit][FAIL]", msg, "\n"); quit(status = 1L) }

# ── (1) forward label recompute ──────────────────────────────────────
cat("[c2_pit] (1) panel forward-label independent recompute ...\n")
pan <- as.data.table(read_parquet(PANEL))
# panel은 ym 키 보유(date 없음) — ym 그대로 사용
stopifnot("ym" %in% names(pan))
raw <- as.data.table(read_parquet(RAW, col_select = c("Date","Ticker","Close")))
raw[, Date := as.Date(Date)]; raw <- raw[!is.na(Close) & Close > 0]
raw[, ymk := format(Date, "%Y-%m")]; setorder(raw, Ticker, Date)
me <- raw[, .SD[.N], by = .(Ticker, ymk)]; setorder(me, Ticker, ymk)
me[, close_next := shift(Close, n = 1L, type = "lead"), by = Ticker]
me[, fwd_recompute := close_next / Close - 1]
me[, close_prev := shift(Close, n = 1L, type = "lag"), by = Ticker]
me[, bwd_recompute := Close / close_prev - 1]
cmp <- merge(pan[, .(ymk = ym, Ticker, Ret_1m)], me[, .(ymk, Ticker, fwd_recompute, bwd_recompute)],
             by = c("ymk","Ticker"), all.x = TRUE)
cmp <- cmp[!is.na(Ret_1m) & !is.na(fwd_recompute)]
set.seed(42); samp <- cmp[sample(.N, min(1000L, .N))]
samp[, fwd_match := abs(Ret_1m - fwd_recompute) < 1e-6]
samp[, bwd_match := !is.na(bwd_recompute) & abs(Ret_1m - bwd_recompute) < 1e-6]
fwd_rate <- mean(samp$fwd_match); bwd_rate <- mean(samp$bwd_match)
cat(sprintf("[c2_pit] forward_match=%.4f backward_match=%.4f (n=%d)\n", fwd_rate, bwd_rate, nrow(samp)))
label_pass <- (fwd_rate >= 0.95) && (bwd_rate < 0.10)

# ── (2) 신규 피처 concurrent-lookahead 검사 ──────────────────────────
cat("[c2_pit] (2) new-feature vs forward-label concurrent correlation ...\n")
new_feats <- c("RESIDMOM__lvl","RESIDMOM__slp","PIOTROSKI__lvl","PIOTROSKI__slp",
               "MOHANRAM__lvl","MOHANRAM__slp","NETISSUE__lvl","NETISSUE__slp")
new_feats <- new_feats[new_feats %in% names(pan)]
sub <- pan[!is.na(Ret_1m)]
cors <- sapply(new_feats, function(cc) {
  v <- sub[[cc]]; ok <- is.finite(v) & is.finite(sub$Ret_1m)
  if (sum(ok) < 100) return(NA_real_)
  cor(v[ok], sub$Ret_1m[ok])
})
for (cc in new_feats) cat(sprintf("[c2_pit]   cor(%s, fwd_ret)=%.4f\n", cc, cors[[cc]]))
feat_pass <- all(abs(cors[is.finite(cors)]) < 0.30)
cat(sprintf("[c2_pit] new-feature backward-only -> %s (all |cor|<0.30)\n", ifelse(feat_pass,"PASS","FAIL")))

# ── (3) bear_date_audit (optional) ───────────────────────────────────
bear_pass <- NA
bda <- file.path(ROOT, "02_Infrastructure/sanity_checks/bear_date_audit.R")
bm_path <- file.path(ROOT, ".cache/benchmark.parquet")
tgt_path <- file.path(ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/02_targets/targets_full.parquet")
if (file.exists(bda) && file.exists(bm_path) && file.exists(tgt_path)) {
  cat("[c2_pit] (3) bear_date_audit.R ...\n")
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  ba <- tryCatch(system2(rscript, c(shQuote(bda), shQuote(tgt_path), shQuote(bm_path)),
                         stdout = TRUE, stderr = TRUE), error = function(e) { attr(e,"status")<-1L; "" })
  st <- attr(ba, "status"); if (is.null(st)) st <- 0L
  bear_pass <- (st == 0L)
  cat(sprintf("[c2_pit] bear_date_audit exit=%d -> %s\n", st, ifelse(bear_pass,"PASS","FAIL")))
} else {
  cat("[c2_pit] (3) bear_date_audit SKIP (targets_full/benchmark N/A for this panel)\n")
}

overall <- label_pass && feat_pass && (is.na(bear_pass) || bear_pass)
out <- list(panel_forward_match = fwd_rate, panel_backward_match = bwd_rate, label_pass = label_pass,
            new_feature_cors = as.list(cors), feature_pass = feat_pass,
            bear_date_audit_pass = bear_pass, overall_pass = overall, n_sample = nrow(samp))
jsonlite::write_json(out, file.path(OUT, "pit_audit.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[c2_pit] -> %s\n", file.path(OUT, "pit_audit.json")))
if (!overall) fail("PIT audit failed — sweep 진입 금지.")
cat("[c2_pit] ALL PASS — sweep 진입 허가.\n")
