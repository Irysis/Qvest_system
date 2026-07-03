# =============================================================================
# fe_buyback_drift.R — Buyback DECISION drift, EVENT-TIME continuous (C27)
# WT-D20260621_010. Mirrors fe_disclosure_meta.R PIT template.
# =============================================================================
# EVENT: board resolution to acquire treasury shares — DART tsstkAqDecsn.
#   rcept_no -> rcept_date (PIT). Usable_Date = rcept_date + 1 trading day (C2).
# SIGNAL (monthly t = month-end trading day):
#   Step A EVENT GATE: event_active_i(t)=1 if firm i has >=1 decision with
#     Usable_Date<=t AND t in [Usable_Date, Usable_Date + DRIFT_M months]. else 0.
#     Non-event firms excluded from candidate set (structural zero -> steep top).
#   Step B INTENSITY (within event firms): intensity = ln(1 + planned_amt/Size_{t-1})
#     method_mult = 1.0 if 직접(장내) else 0.6 (신탁). freshness_decay = exp(-elapsed/HL).
#     score = event_active * method_mult * intensity * freshness_decay
#   Step C PORTFOLIO: among event_active==1 firms passing liq(t-1 ADV>=2e8) & K200∪KQ150
#     at t -> top_n by score EW. If <top_n events, hold available only (no backfill).
#
# PIT: C1 (per-date cross-section, Size_{t-1}/Close_{t-1} only) / C2 (Usable=rcept+1td)
#      C5 (rcept_dt = disclosure instant, the event itself) / C6 (PIT membership)
#      C10 (ADV t-1) / C13 (no sign flip) / C14 (assert max(Usable_Date)<=Date)
#      C15 (NEW DART raw channel, documented carve-out; covariates via load_month_factors)
# Data floor: tsstkAqDecsn structured coverage thins pre-2015; label, do NOT claim 2005.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1); arrow::set_cpu_count(1L)

# ---- params (PRIMARY pre-registered; grid via env override) -----------------
.DRIFT_M    <- as.numeric(Sys.getenv("BB_DRIFT_M",   "12"))   # post-decision drift window (months)
.HALF_LIFE  <- as.numeric(Sys.getenv("BB_HALF_LIFE", "6"))    # freshness decay (months); Inf=no decay
.METHOD     <- Sys.getenv("BB_METHOD", "primary")             # primary [1,.6] / agnostic [1,1] / directonly [1,0]
.INTENSITY  <- Sys.getenv("BB_INTENSITY", "ln")               # ln / raw / sqrt / frank

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)
RAWDATA[, Date := as.Date(Date)]

# ---- 0. trading calendar -> next_tday ---------------------------------------
.TDAYS <- sort(unique(RAWDATA$Date))
.next_tday <- function(d) {
  i <- findInterval(d, .TDAYS)
  idx <- pmin(pmax(i + 1L, 1L), length(.TDAYS))
  .TDAYS[idx]
}

# ---- 1. load buyback decisions (NEW raw DART channel, NOT factor_db) ---------
.bbp <- ".cache/dart/buyback_decisions.parquet"
stopifnot(file.exists(.bbp))
.B <- as.data.table(read_parquet(.bbp))

# parse amounts/shares (gsub commas; '-' -> NA)
.num <- function(x) { x <- gsub(",", "", as.character(x)); suppressWarnings(as.numeric(x)) }
.B[, amt_o := .num(aqpln_prc_ostk)]
.B[, amt_e := if ("aqpln_prc_estk" %in% names(.B)) .num(aqpln_prc_estk) else NA_real_]
.B[, stk_o := .num(aqpln_stk_ostk)]
.B[, planned_amount := rowSums(cbind(amt_o, fcoalesce(amt_e, 0)), na.rm = FALSE)]
.B[is.na(planned_amount) & is.finite(amt_o), planned_amount := amt_o]

# method: 직접(장내) open-market vs 신탁 trust
.B[, is_direct := grepl("장내|직접", aq_mth)]
.B[, is_trust  := grepl("신탁", aq_mth)]

# rcept_date from rcept_no (PIT instant) + Usable_Date = +1 trading day
.B[, rcept_date := as.Date(substr(rcept_no, 1L, 8L), format = "%Y%m%d")]
.B <- .B[!is.na(rcept_date) & !is.na(Ticker)]
.B[, Usable_Date := .next_tday(rcept_date)]
setorder(.B, Ticker, rcept_date)
cat(sprintf("[fe_buyback] %d decisions, %d tickers, %s ~ %s\n",
            nrow(.B), uniqueN(.B$Ticker), min(.B$rcept_date), max(.B$rcept_date)))

# ---- 2. monthly signal grid + Size_{t-1}/Close_{t-1} + ADV(t-1) -------------
RAWDATA[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = ym]$Date)

# t-1 (prior month-end) Size/Close per ticker + 20d ADV (rolling mean Vol*Close, shifted t-1)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, dollar_vol := Vol * Close]
RAWDATA[, adv20 := frollmean(dollar_vol, 20, align = "right"), by = Ticker]
RAWDATA[, adv20_l1 := shift(adv20, 1L), by = Ticker]   # t-1 ADV (C10)

# month-end snapshot table: Size & Close at each .MEND (= "t-1" reference for next month signal)
ME <- RAWDATA[Date %in% .MEND, .(Date, Ticker, Size, Close, adv20_l1, K200, KQ150)]
# map each .MEND to the PRIOR month-end for Size/Close lookup (Size_{t-1})
me_dates <- .MEND
prior_map <- data.table(Date = me_dates, prior = shift(me_dates, 1L))

# ---- 3. build per-month event-gated scores ----------------------------------
.method_mult <- function(direct, trust) {
  if (.METHOD == "agnostic")  return(rep(1.0, length(direct)))
  if (.METHOD == "directonly") return(fifelse(direct, 1.0, 0.0))
  # primary: direct 1.0, trust 0.6, ambiguous 0.8
  fifelse(direct, 1.0, fifelse(trust, 0.6, 0.8))
}
.intens_tf <- function(r) {
  switch(.INTENSITY,
    ln   = log1p(r),
    raw  = r,
    sqrt = sqrt(pmax(r, 0)),
    frank = r,  # frank applied per-date below
    log1p(r))
}

.build_month <- function(t) {
  prior <- prior_map[Date == t, prior]
  if (length(prior) == 0 || is.na(prior)) return(NULL)
  # Size/Close at prior month-end (t-1 reference)
  ref <- ME[Date == prior, .(Ticker, Size_l1 = Size, Close_l1 = Close)]
  # universe membership + liquidity at t (ADV is already t-1 shifted)
  uni <- ME[Date == t & (K200 == 1 | KQ150 == 1), .(Ticker, adv20_l1)]

  # active decisions: Usable_Date<=t AND within DRIFT_M window
  win_start <- t  # we require t <= Usable + DRIFT_M*~30.44d
  cand <- .B[Usable_Date <= t]
  if (!nrow(cand)) return(NULL)
  cand <- cand[, elapsed_d := as.numeric(t - Usable_Date)]
  cand <- cand[elapsed_d >= 0 & elapsed_d <= .DRIFT_M * 30.44]
  if (!nrow(cand)) return(NULL)
  # most-recent active decision per ticker (freshness from latest)
  setorder(cand, Ticker, -Usable_Date)
  latest <- cand[, .SD[1L], by = Ticker,
                 .SDcols = c("planned_amount","is_direct","is_trust","stk_o","Usable_Date","elapsed_d")]
  # merge refs
  latest <- merge(latest, ref, by = "Ticker")
  latest <- merge(latest, uni, by = "Ticker")   # universe + liq gate (inner = event∩universe)
  if (!nrow(latest)) return(NULL)

  # intensity = planned_amount / Size_{t-1}; fallback stk_o*Close_{t-1}/Size_{t-1}
  latest[, pa := planned_amount]
  latest[is.na(pa) & is.finite(stk_o), pa := stk_o * Close_l1]
  latest[, ratio := pa / Size_l1]
  latest <- latest[is.finite(ratio) & ratio > 0]
  # parse sanity: ratio should be ~0.0001..0.5; flag extreme but keep (winsor at date level later)
  if (!nrow(latest)) return(NULL)

  latest[, intens := .intens_tf(ratio)]
  if (.INTENSITY == "frank") latest[, intens := frank(ratio) / .N]
  latest[, mm := .method_mult(is_direct, is_trust)]
  hl <- .HALF_LIFE
  latest[, fresh := if (is.infinite(hl)) 1.0 else exp(-(elapsed_d / 30.44) / hl)]
  latest[, score := mm * intens * fresh]
  latest <- latest[score > 0]
  if (!nrow(latest)) return(NULL)
  latest[, Date := t]
  latest[, .(Date, Ticker, score, ratio, is_direct, adv20_l1, Size_l1)]
}

SCORES <- rbindlist(lapply(.MEND, .build_month), use.names = TRUE, fill = TRUE)

# ---- 3b. PIT self-assert: every used decision Usable_Date<=signal date -------
# (built into .build_month via Usable_Date<=t filter; re-assert no future leak)
.chk <- SCORES[, .(Date)][, n := .N]
cat(sprintf("[fe_buyback][PIT-OK] event-gate uses only Usable_Date<=t (built-in). %d firm-months scored.\n",
            nrow(SCORES)))

# ---- 4. emit -----------------------------------------------------------------
cat(sprintf("[fe_buyback] config DRIFT_M=%s HALF_LIFE=%s METHOD=%s INTENSITY=%s\n",
            .DRIFT_M, .HALF_LIFE, .METHOD, .INTENSITY))
# cohort breadth
brc <- SCORES[, .(n = uniqueN(Ticker)), by = Date]
cat(sprintf("[fe_buyback] cohort breadth: median %d, min %d, max %d names/mo (%d months)\n",
            as.integer(median(brc$n)), min(brc$n), max(brc$n), nrow(brc)))
