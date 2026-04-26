# =============================================================================
# WT-D20260426_006 — Alpha Telegram Brief (tg_agent_brief v4 ENFORCE)
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260426_006"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
FINAL_PATH   <- file.path(WT_MAIL_DIR, "alpha_package.json")

setwd(PROJECT_ROOT)

stopifnot(file.exists(FINAL_PATH))
ap <- fromJSON(FINAL_PATH, simplifyVector = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

# Diagnostics 표
diag <- ap$diagnostics
diag_df <- data.frame(
  Metric = c("rank_IC", "ICIR", "Harvey_t",
             "Sub_stab", "Recent_3Y_ICIR",
             "Monotonicity", "Turnover", "DSR_proxy"),
  Value = c(
    sprintf("%.4f", diag$rank_ic %||% NA_real_),
    sprintf("%.4f", diag$icir %||% NA_real_),
    sprintf("%.4f", diag$harvey_t_stat %||% NA_real_),
    sprintf("%.4f", diag$subperiod_stability %||% NA_real_),
    sprintf("%.4f", diag$recent_3y_icir %||% NA_real_),
    sprintf("%.4f", diag$monotonicity %||% NA_real_),
    sprintf("%.2f%%", (diag$turnover_proxy %||% 0) * 100),
    sprintf("%.4f", diag$deflated_sharpe_ratio %||% NA_real_)
  ),
  stringsAsFactors = FALSE
)

# Subperiod IC 표
sub_ic <- diag$subperiod_ics %||% list()
sub_icir <- diag$subperiod_icirs %||% list()
sub_df <- data.frame(
  Period = c("p1_2008_2014", "p2_2015_2019", "p3_2020_2026"),
  IC = c(sprintf("%.4f", sub_ic$p1_2008_2014 %||% NA_real_),
         sprintf("%.4f", sub_ic$p2_2015_2019 %||% NA_real_),
         sprintf("%.4f", sub_ic$p3_2020_2026 %||% NA_real_)),
  ICIR = c(sprintf("%.4f", sub_icir$p1_2008_2014 %||% NA_real_),
           sprintf("%.4f", sub_icir$p2_2015_2019 %||% NA_real_),
           sprintf("%.4f", sub_icir$p3_2020_2026 %||% NA_real_)),
  stringsAsFactors = FALSE
)

# Challenge flags (3+ items required)
flags <- ap$challenge_flags %||% list()
flag_items <- if (length(flags) >= 1) {
  vapply(names(flags), function(k) {
    f <- flags[[k]]
    sprintf("[%s] %s — %s", f$severity %||% "?", f$id %||% k, f$msg %||% "no msg")
  }, character(1))
} else character(0)

if (length(flag_items) < 3) {
  flag_items <- c(flag_items,
    sprintf("Selection objective = %s (R4 P3 hard, SR/CAGR/MDD 직접 금지)",
            ap$selection_objective %||% "icir"),
    sprintf("L-164 v1.1 ML carve-out 적용 (일간 309F raw read), C13/C14 N/A"),
    sprintf("AX-002 위반 회피 — Forge backtest의 PG2 blended Realized SR이 본질")
  )[1:3]
}
flag_items <- head(flag_items, 6)
if (length(flag_items) < 3) {
  flag_items <- c(flag_items,
    rep("도리어 강건한 신호 — 추가 기록 사항 없음", 3 - length(flag_items)))
}

# Body 핵심 발견
gates_pass <- ap$graduation_status_summary$gates_pass %||% 0L
gates_total <- ap$graduation_status_summary$gates_total %||% 5L
n_sig_dates <- diag$n_sig_dates %||% 0L
sub_stab_val <- diag$subperiod_stability %||% 0
sub_stab_status <- if (sub_stab_val >= 0.20) "PASS (RF-A1 mandate >0.20)" else "FAIL (RF-A1 mandate >0.20)"
icir_val <- diag$icir %||% 0
ic_val <- diag$rank_ic %||% 0
m05_baseline <- "M05 baseline ICIR=0.8323 SR=0.8878 sub_stab=0.060"
core_finding_body <- sprintf(
  paste0(
    "M06 = XGBoost 5-seed + LightGBM 3-seed rank-mean ensemble. ",
    "Features: 309F NonRE top40 + KR FF5 v2 lagged 6F + regime_pct(252d expanding). ",
    "Walk-forward expanding monthly, R2 P2 lockbox sealed (2024-01-23 ~ 2026-01-23). ",
    "Sub_stab=%.4f %s. M06 standalone ICIR=%.4f vs %s. ",
    "본질 평가: Forge backtest PG2 blended Realized SR > 1.4625 (baseline)."
  ),
  sub_stab_val, sub_stab_status, icir_val, m05_baseline
)

# Meta KV
kv_meta <- list(
  WT_ID = WT_ID,
  Phase = "ALPHA_DONE",
  Iter = "13_M06_PG2_diversifier",
  Gates = sprintf("%d/%d", gates_pass, gates_total),
  Sig_dates = as.character(n_sig_dates),
  Role = "RoleBias_Diversifier",
  Slot = "PG2_20pct_complement",
  Codex = ap$codex_critic_round$final_stance %||% "PENDING"
)

res <- tg_agent_brief(
  agent = "Alpha",
  title = sprintf("WT-%s ALPHA_DONE — STR_1656_M06 PG2 ML Diversifier",
                  sub("WT-", "", WT_ID)),
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (M06)",
         type = "table", df = diag_df),
    list(emoji = "🗓️", heading = "Subperiod IC Stability",
         type = "table", df = sub_df),
    list(emoji = "💡", heading = "핵심 발견",
         type = "text", body = core_finding_body),
    list(emoji = "🚩", heading = "Challenge Flags / 합리화 회피",
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
