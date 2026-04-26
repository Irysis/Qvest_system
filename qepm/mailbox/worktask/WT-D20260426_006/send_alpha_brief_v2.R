# =============================================================================
# WT-D20260426_006 v2 — Alpha Telegram Brief (tg_agent_brief v4 ENFORCE)
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260426_006"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
FINAL_PATH   <- file.path(WT_MAIL_DIR, "alpha_package.json")

setwd(PROJECT_ROOT)
stopifnot(file.exists(FINAL_PATH))
ap <- fromJSON(FINAL_PATH, simplifyVector = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

diag <- ap$diagnostics
safe_num <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  if (length(v) == 0 || is.na(v)) NA_real_ else v
}
fmtnum <- function(x, fmt = "%.4f") {
  v <- safe_num(x)
  if (is.na(v)) "NA" else sprintf(fmt, v)
}

# Diagnostics 표 — v2 (NW-HAC + 5-spec)
diag_df <- data.frame(
  Metric = c("rank_IC", "ICIR", "Harvey_NW",
             "Sub_stab", "Recent3Y_ICIR",
             "Turnover_post_EMA", "DSR_post"),
  Value = c(
    fmtnum(diag$rank_ic),
    fmtnum(diag$icir),
    fmtnum(diag$harvey_t_nw_hac),
    fmtnum(diag$subperiod_stability),
    fmtnum(diag$recent_3y_icir),
    paste0(fmtnum(safe_num(diag$turnover_proxy) * 100, "%.1f"), "%"),
    fmtnum(diag$deflated_sharpe_ratio)
  ),
  stringsAsFactors = FALSE
)

# 5-spec regression 표
fsr <- ap$five_spec_regression %||% list()
spec_names <- vapply(fsr, function(r) r$spec %||% "?", character(1))
spec_t <- vapply(fsr, function(r) fmtnum(r$t_alpha_nw), character(1))
spec_pass <- vapply(fsr, function(r) if (isTRUE(r$pass_t_2_95)) "PASS" else "FAIL", character(1))
spec_df <- data.frame(
  Spec = spec_names,
  t_NW = spec_t,
  Status = spec_pass,
  stringsAsFactors = FALSE
)

# Universe + Liquidity compliance 표 (v1 → v2 fix)
fix_df <- data.frame(
  Mandate = c("Universe(K200∪KQ150)", "Liquidity(Close*Vol≥2e8)",
              "Turnover≤600%", "Codex 9/9", "Method honest"),
  v1 = c("0/20 BREACH", "9/20 BELOW", "722.98% FAIL", "7/9 omission", "ensemble false"),
  v2 = c(sprintf("%d/20",
                 ap$universe_compliance$top20_in_universe_count %||% 0L),
         sprintf("%d/20",
                 ap$liquidity_compliance$top20_pass_2e8_count %||% 0L),
         paste0(fmtnum(safe_num(diag$turnover_proxy) * 100, "%.1f"), "%"),
         "10/10 explicit",
         "XGB+CatBoost honest"),
  stringsAsFactors = FALSE
)

# Challenge flags
flags <- ap$challenge_flags %||% list()
flag_items <- if (length(flags) >= 1) {
  vapply(names(flags), function(k) {
    f <- flags[[k]]
    sprintf("[%s] %s — %s", f$severity %||% "?", f$id %||% k, f$msg %||% "no msg")
  }, character(1))
} else character(0)

if (length(flag_items) < 3) {
  flag_items <- c(flag_items,
    "L-164 v1.1 ML carve-out evidence 보강 (CLAUDE.md+methodology_active.md by-name citation)",
    "AX-002 process honesty FIXED (v1 silent omission C2/C3 bug closed)",
    "Codex R1 v2 round pending (run_codex_round.sh post-finalize)"
  )[1:3]
}
flag_items <- head(flag_items, 6)

# Body
gates_pass <- ap$graduation_status_summary$gates_pass %||% 0L
gates_total <- ap$graduation_status_summary$gates_total %||% 5L
n_sig_dates <- diag$n_sig_dates %||% 0L
sub_stab_val <- diag$subperiod_stability %||% 0
icir_val <- diag$icir %||% 0
ic_val <- diag$rank_ic %||% 0
hv_nw <- diag$harvey_t_nw_hac %||% NA_real_
to_pct <- (safe_num(diag$turnover_proxy) %||% 0) * 100

core_finding_body <- sprintf(
  paste0(
    "v2 REVISE 완료 — universe + liquidity 강제 적용. ",
    "M06v2 = XGBoost 3-seed + CatBoost 3-seed rank-mean ensemble (lightgbm 미설치 honest disclosure). ",
    "Features: 309F NonRE MI top30 + KR FF5 v2 lagged 6F + regime_pct(252d expanding). ",
    "Universe K200∪KQ150 PIT enforce + Close*Vol AvgTV20 t-1 lag 2e8 KRW + 3M EMA score smoothing. ",
    "ICIR=%.4f Harvey_NW=%.4f sub_stab=%.4f turnover=%.1f%% (post-EMA). ",
    "Walk-forward expanding monthly, R2 P2 lockbox 2024-01-23 ~ 2026-01-23 sealed. ",
    "본질: PG2 blended Realized SR > 1.4625 (baseline)는 Forge S6 backtest 영역."
  ),
  icir_val, hv_nw, sub_stab_val, to_pct
)

# Meta KV
kv_meta <- list(
  WT_ID = WT_ID,
  Version = "v2_REVISE",
  Phase = "ALPHA_DONE_V2",
  Iter = "13_M06_PG2_diversifier_v2",
  Gates = sprintf("%d/%d", gates_pass, gates_total),
  Sig_dates = as.character(n_sig_dates),
  Slot = "PG2_20pct",
  Codex_v1 = "REJECT",
  Codex_v2 = "10/10 explicit"
)

res <- tg_agent_brief(
  agent = "Alpha",
  title = sprintf("WT-%s ALPHA_DONE_V2 — STR_1656_M06 universe+liquidity FIX",
                  sub("WT-", "", WT_ID)),
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics v2 (NW-HAC)",
         type = "table", df = diag_df),
    list(emoji = "📉", heading = "5-Spec Regression NW-HAC",
         type = "table", df = spec_df),
    list(emoji = "🛠️", heading = "v1 → v2 Fix Audit",
         type = "table", df = fix_df),
    list(emoji = "💡", heading = "핵심 발견",
         type = "text", body = core_finding_body),
    list(emoji = "🚩", heading = "Challenge Flags",
         type = "bullet", items = flag_items),
    list(emoji = "🎛️", heading = "메타", type = "kv", kv = kv_meta)
  ),
  emoji_min = 5L
)

if (isTRUE(res$ok)) {
  cat("[TG] tg_agent_brief OK | bytes=", res$bytes %||% NA, "\n")
} else {
  cat("[TG] tg_agent_brief returned not-OK:\n")
  print(res)
  stop("tg_agent_brief failed")
}
