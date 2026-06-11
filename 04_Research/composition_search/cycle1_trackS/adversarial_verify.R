# =============================================================================
# adversarial_verify.R — Track S Stage A ADVERSARIAL verification (independent)
#   Written by verification subagent BEFORE engine completion (2026-06-12).
#   Does NOT reuse engine invz_chunks — reads factor DB parquet directly and
#   rebuilds universe/returns from RAWDATA independently (same frozen prereg
#   conditions), then routes through the SAME contract canonical_screen_bt()
#   (mandated single computation path).
#   Items: (6) gate re-application from CSV raw columns
#          (5) numeric reproduction of 1 PASS + 1 FAIL spec (PORT_t tol 1e-3)
#          (3) C10 sensitivity: ADV lag-1 (strict t-1) variant impact
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "04_Research/composition_search/cycle1_trackS")
CSV  <- file.path(OUT, "flow_stage_a_results.csv")
stopifnot(file.exists(CSV))

source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

res <- fread(CSV)
cat("== [6] GATE RE-APPLICATION from raw CSV columns ==\n")
ok <- res[status == "OK"]
ok[, v_gate_full := !is.na(port_t_full) & port_t_full >= 1.96]
ok[, v_gate_2017 := !is.na(port_t_2017p) & port_t_2017p > 0]
ok[, v_gate_pass := v_gate_full & v_gate_2017]
mism <- ok[v_gate_full != gate_full_t196 | v_gate_2017 != gate_2017_pos | v_gate_pass != gate_pass]
cat(sprintf("rows=%d OK=%d | gate mismatches=%d\n", nrow(res), nrow(ok), nrow(mism)))
if (nrow(mism)) print(mism[, .(spec_id, port_t_full, port_t_2017p,
                               gate_full_t196, v_gate_full, gate_2017_pos, v_gate_2017,
                               gate_pass, v_gate_pass)])
cat("recorded PASS list:", paste(ok[gate_pass == TRUE, spec_id], collapse=", "), "\n")
cat("verified PASS list:", paste(ok[v_gate_pass == TRUE, spec_id], collapse=", "), "\n")

# spec selection: deterministic seed, 1 pass + 1 fail
set.seed(20260612)
pass_ids <- ok[gate_pass == TRUE,  spec_id]
fail_ids <- ok[gate_pass == FALSE, spec_id]
pick <- c(if (length(pass_ids)) sample(pass_ids, 1) else character(0),
          if (length(fail_ids)) sample(fail_ids, 1) else character(0))
cat("\n== [5] REPRODUCTION picks:", paste(pick, collapse=", "), "==\n")

SPEC_DEF <- list(
  "FLOW-S01" = list(factors = "INV02_Foreign_NetBuy_60d",           dir = -1, kind = "single"),
  "FLOW-S02" = list(factors = "INV04_Inst_NetBuy_60d",              dir = -1, kind = "single"),
  "FLOW-S03" = list(factors = "INV07_Retail_Contrarian",            dir = -1, kind = "single"),
  "FLOW-S04" = list(factors = c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d",
                                "INV09_Flow_Persistence","INV11_Foreign_Concentration",
                                "INV07_Retail_Contrarian"),         dir = -1, kind = "composite_rez"),
  "FLOW-S05" = list(factors = "INV10_Smart_Money_Flow",             dir = -1, kind = "single"),
  "FLOW-S06" = list(factors = "INV05_Foreign_Momentum",             dir = +1, kind = "single"),
  "FLOW-S07" = list(factors = "INV13_Foreign_Resid_Individual_63d", dir = -1, kind = "single"),
  "FLOW-S08" = list(factors = "INV08_Foreign_Inst_Agreement",       dir = -1, kind = "single"),
  "FLOW-S09" = list(factors = "INV09_Flow_Persistence",             dir = -1, kind = "single"))

TOP_N <- 25L; COST <- 15; LIQ <- 2e8
SIG_FIRST <- "200501"; SIG_LAST <- "202603"

cat("\n[rebuild] RAWDATA -> universe/returns (independent of engine)...\n")
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret","K200","KQ150",
                 "AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2004-10-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)

me_dates <- raw[, .(eom = max(Date)), by = ym]; setorder(me_dates, ym)
ym_sorted <- me_dates$ym
next_map <- data.table(ym = ym_sorted[-length(ym_sorted)], ym_next = ym_sorted[-1])
ym2date  <- me_dates[, .(ym, Date = eom)]

mret <- raw[!is.na(Ret), .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)][ndays >= 5]

bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[Date >= as.Date("2004-12-01")]
bm[, ym := format(Date, "%Y%m")]
bmret <- bm[!is.na(BM_Ret), .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]

raw[, tv := Vol * Close]
raw[, adv20 := frollmean(tv, 20, align = "right"), by = Ticker]
raw[, adv20_lag1 := shift(adv20, 1L), by = Ticker]   # strict t-1 variant (C10 letter)
me_state <- raw[Date %in% me_dates$eom,
  .(Ticker, ym, adv20, adv20_lag1,
    member = (K200 %in% 1) | (KQ150 %in% 1),
    bad = (AdminStock %in% 1) | (TradingHalt %in% 1) | (UnfaithfulDisc %in% 1))]
me_state[is.na(bad), bad := FALSE]
uni      <- me_state[member & !bad & !is.na(adv20)      & adv20      >= LIQ, .(ym, Ticker)]
uni_lag1 <- me_state[member & !bad & !is.na(adv20_lag1) & adv20_lag1 >= LIQ, .(ym, Ticker)]
cat(sprintf("universe rows: engine-mode=%d | t-1-strict=%d | symdiff=%d\n",
            nrow(uni), nrow(uni_lag1),
            nrow(fsetdiff(uni, uni_lag1)) + nrow(fsetdiff(uni_lag1, uni))))
rm(raw); invisible(gc(FALSE))

fwd <- merge(next_map, mret[, .(Ticker, ym_next = ym, Ret_1m = mret)],
             by = "ym_next", allow.cartesian = TRUE)[, .(ym, Ticker, Ret_1m)]
returns_dt <- merge(fwd, ym2date, by = "ym")[, .(Date, Ticker, Ret_1m)]
bench_fwd  <- merge(next_map, bmret[, .(ym_next = ym, BM_Ret = bm_mret)], by = "ym_next")
bench_dt   <- merge(bench_fwd[, .(ym, BM_Ret)], ym2date, by = "ym")[, .(Date, BM_Ret)]

sig_months <- ym_sorted[ym_sorted >= SIG_FIRST & ym_sorted <= SIG_LAST]
need_factors <- unique(unlist(lapply(SPEC_DEF[pick], `[[`, "factors")))

cat("[rebuild] raw Z direct from factor DB (connector coverage filter) ...\n")
load_raw <- function(ym_tag, needed) {
  fp <- file.path(ROOT, ".cache/factor_db", paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fp)) return(NULL)
  dt <- as.data.table(read_parquet(fp, col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
  n_t <- uniqueN(dt$Ticker)
  fc <- dt[, .(N = sum(Coverage == TRUE & !is.na(Z_Score))), by = Factor_Name]
  keep <- fc[N / n_t >= 0.05, Factor_Name]
  dt <- dt[Factor_Name %in% keep & Coverage == TRUE & !is.na(Z_Score)]
  dt[Factor_Name %in% needed, .(Ticker, Factor_Name, Z = Z_Score)]
}
FZ <- rbindlist(lapply(sig_months, function(m) {
  z <- load_raw(m, need_factors)
  if (is.null(z) || !nrow(z)) return(NULL)
  z[, ym := m]; z
}))
cat(sprintf("FZ rows=%d months=%d factors=%s\n", nrow(FZ), uniqueN(FZ$ym),
            paste(sort(unique(FZ$Factor_Name)), collapse=",")))

build_scores <- function(sp, universe) {
  if (sp$kind == "single") {
    sc <- FZ[Factor_Name == sp$factors, .(ym, Ticker, score = sp$dir * Z)]
    sc <- merge(sc, universe, by = c("ym","Ticker"))
  } else {
    Fz <- merge(FZ[Factor_Name %in% sp$factors], universe, by = c("ym","Ticker"))
    CW <- dcast(Fz, ym + Ticker ~ Factor_Name, value.var = "Z")
    fcols <- intersect(sp$factors, names(CW))
    CW[, rm_ := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
    CW <- CW[is.finite(rm_)]
    CW[, score := sp$dir * rm_]
    CW[, score := (score - mean(score, na.rm = TRUE)) / sd(score, na.rm = TRUE), by = ym]
    sc <- CW[, .(ym, Ticker, score)]
  }
  merge(sc, ym2date, by = "ym")[, .(Date, Ticker, score)]
}

vrows <- list()
for (sid in pick) {
  sp <- SPEC_DEF[[sid]]
  for (mode in c("engine", "adv_lag1")) {
    universe <- if (mode == "engine") uni else uni_lag1
    sdt <- build_scores(sp, universe)
    sdt <- sdt[Date %in% bench_dt$Date]
    full <- canonical_screen_bt(sdt, returns_dt, bench_dt, top_n = TOP_N,
                                cost_bps_oneway = COST, liq_dt = NULL,
                                run_id = paste0("verify_", sid, "_", mode),
                                strategy_id = paste0("verify_", sid, "_", mode))
    s17 <- canonical_screen_bt(sdt[Date >= as.Date("2017-01-01")], returns_dt, bench_dt,
                               top_n = TOP_N, cost_bps_oneway = COST, liq_dt = NULL,
                               run_id = paste0("verify_", sid, "_2017_", mode),
                               strategy_id = paste0("verify_", sid, "_2017_", mode))
    vrows[[paste(sid, mode)]] <- data.table(
      spec_id = sid, mode = mode, n_months = full$n_months,
      v_port_t_full = full$portfolio_alpha_t_nw_lag3,
      v_port_t_2017p = s17$portfolio_alpha_t_nw_lag3,
      v_net_sr_full = full$net_sr, v_ir = full$information_ratio,
      v_turnover = full$turnover_annual,
      metric_type = "canonical_screen")
    cat(sprintf("  %s [%s]: PORT_t=%.4f 2017+=%.4f n=%d\n", sid, mode,
                full$portfolio_alpha_t_nw_lag3, s17$portfolio_alpha_t_nw_lag3, full$n_months))
  }
}
V <- rbindlist(vrows)
cmp <- merge(V[mode == "engine"], res[, .(spec_id, port_t_full, port_t_2017p, n_months_csv = n_months)],
             by = "spec_id")
cmp[, diff_full  := abs(v_port_t_full  - port_t_full)]
cmp[, diff_2017p := abs(v_port_t_2017p - port_t_2017p)]
cat("\n== REPRODUCTION COMPARISON (tol vs rounded CSV: 1e-3 + rounding 5e-4) ==\n")
print(cmp[, .(spec_id, n_months, n_months_csv, v_port_t_full, port_t_full, diff_full,
              v_port_t_2017p, port_t_2017p, diff_2017p)])
cmp[, repro_ok := diff_full <= 1.5e-3 & diff_2017p <= 1.5e-3 & n_months == n_months_csv]
cat("\n== C10 SENSITIVITY (engine same-day ADV vs strict t-1 ADV) ==\n")
sens <- dcast(V, spec_id ~ mode, value.var = "v_port_t_full")
sens[, delta := adv_lag1 - engine]
print(sens)

outj <- list(verified_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
             gate_mismatches = nrow(mism),
             recorded_pass = ok[gate_pass == TRUE, spec_id],
             verified_pass = ok[v_gate_pass == TRUE, spec_id],
             picks = pick, comparison = cmp, c10_sensitivity = sens)
write_json(outj, file.path(OUT, "adversarial_verify_result.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("\nVERIFY_DONE repro_ok:", paste(cmp$repro_ok, collapse=","), "\n")
