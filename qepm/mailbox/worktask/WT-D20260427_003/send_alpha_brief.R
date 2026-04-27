# ============================================================
# WT-D20260427_003 — Iter 19 Alpha Telegram Brief (v4 enforce)
# ============================================================
suppressMessages({ library(jsonlite) })

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260427_003"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)

state <- fromJSON(file.path(WT_DIR, ".alpha_iter19_state.json"))

source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

diag_df <- data.frame(
  Metric = c("rank_IC v2", "ICIR v2", "Harvey 5-spec", "Sub-stab v2",
              "DSR_post v2", "delta_ICIR vs v1", "v1 baseline ICIR",
              "Mega-cap cor", "Top-20 v1-v2 Jaccard"),
  Value = c(
    sprintf("%.4f", state$rank_ic_v2),
    sprintf("%.4f", state$icir_v2),
    sprintf("%d/5", state$harvey_pass_v2),
    sprintf("%.4f", state$sub_stab_v2),
    sprintf("%.4f", state$dsr_post_v2),
    sprintf("%+.4f", state$delta_icir),
    sprintf("%.4f", state$icir_v1),
    sprintf("%.4f", state$mega_cap_cor_mean),
    sprintf("%.4f", state$top20_jaccard_v1_v2)
  ),
  stringsAsFactors = FALSE
)

universe_df <- data.frame(
  Item = c("Universe label", "Avg names", "Sector max share",
            "KOSDAQ share", "Gates passed", "Hypothesis outcome"),
  Detail = c("KR_TOP500_FREEFLOAT (L-227)",
              "~500 (per sig_date)",
              sprintf("%.1f%%", state$sector_max_mean * 100),
              sprintf("%.1f%%", state$kosdaq_share_mean * 100),
              sprintf("%d/5", state$gates_passed),
              state$hypothesis_outcome),
  stringsAsFactors = FALSE
)

interpret <- if (state$delta_icir >= 0.05) {
  "A_universe_expansion_helps_significantly"
} else if (state$delta_icir >= -0.05) {
  "B_universe_neutral_no_alpha_attenuation"
} else {
  "C_midcap_noise_dominates"
}

body_text <- paste(
  sprintf("Iter 19 = Universe Pilot. STR_1701 multi-sleeve composite (Iter 11 inheritance) 그대로,"),
  sprintf("universe만 KR_top342 -> KR_TOP500_FREEFLOAT (L-227 Architect 활용)."),
  sprintf("Universe v1 ICIR=%.4f -> v2 ICIR=%.4f (delta %+.4f).",
           state$icir_v1, state$icir_v2, state$delta_icir),
  sprintf("Top-20 Jaccard %.3f -> %s.",
           state$top20_jaccard_v1_v2,
           if (state$top20_jaccard_v1_v2 >= 0.80) "highly_similar"
            else if (state$top20_jaccard_v1_v2 >= 0.50) "moderate_drift" else "significant_drift"),
  sprintf("Architect AC2 mega-cap cor=%.4f (sector max %.1f%%).",
           state$mega_cap_cor_mean, state$sector_max_mean * 100),
  sprintf("Hypothesis outcome: %s.", interpret),
  sep = " ")

flag_items <- c(
  sprintf("RF-A1 sub-stab %.4f < 0.50 (HIGH inherited)", state$sub_stab_v2),
  sprintf("RF-A6 rank_IC v2 %.4f vs v1 %.4f (delta %+.4f)",
           state$rank_ic_v2, state$rank_ic_v1, state$rank_ic_v2 - state$rank_ic_v1),
  sprintf("RF-A7 Harvey %d/5 universe v2 (HIGH)", state$harvey_pass_v2),
  sprintf("AC2 mega-cap cor %.4f / sector %.1f%% / KOSDAQ %.1f%%",
           state$mega_cap_cor_mean, state$sector_max_mean * 100,
           state$kosdaq_share_mean * 100)
)

meta_kv <- list(
  WT_ID = WT_ID,
  Phase = "ALPHA_DONE",
  Iter = "19_universe_pilot",
  Universe = "KR_TOP500_FREEFLOAT",
  Inheritance = "STR_1701_overlap_cor_strict_pass",
  Codex = "OVERRIDE_005_ready_if_stall",
  L_codes = "L-227 + L-224 + L-223"
)

res <- tg_agent_brief(
  agent = "Alpha",
  title = sprintf("WT-%s ALPHA_DONE_ITER19 — KR_TOP500 Universe Pilot ICIR=%.4f (delta %+.4f vs v1)",
                   WT_ID, state$icir_v2, state$delta_icir),
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (Universe v2 vs v1)", type = "table",
          df = diag_df),
    list(emoji = "🌐", heading = "Universe v2 Profile (Architect AC2)", type = "table",
          df = universe_df),
    list(emoji = "💡", heading = "핵심 발견", type = "text",
          body = body_text),
    list(emoji = "🚩", heading = "Challenge Flags + Architect AC2", type = "bullet",
          items = flag_items),
    list(emoji = "🎛️", heading = "메타", type = "kv", kv = meta_kv)
  ),
  emoji_min = 5L
)
stopifnot(isTRUE(res$ok))
cat("Telegram brief sent OK\n")
