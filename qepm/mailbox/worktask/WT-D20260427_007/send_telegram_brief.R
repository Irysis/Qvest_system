# Telegram brief v4 ENFORCE — Iter 22b ALPHA_DONE
suppressPackageStartupMessages({
  library(jsonlite)
})
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

source("02_Infrastructure/telegram/telegram_notify.R")

ap <- fromJSON("qepm/mailbox/worktask/WT-D20260427_007/alpha_package.json", simplifyVector = FALSE)

dx <- ap$diagnostics
dca <- ap$drawdown_conditioned_audit
ax <- ap$ax_001_v2_audit
gp <- ap$gates_pass

diag_df <- data.frame(
  Metric = c("cor_dd_V22b", "cor_norm_V22b", "ICIR", "rank_IC",
             "bad/normal IC", "AX-001 v2", "Gates", "MDD relief best"),
  Value  = c(sprintf("%.4f", dca$chosen_drawdown_cor),
             sprintf("%.4f", dca$v22b_top_only_vs_str1701_normal_cor),
             sprintf("%.4f", dx$icir_overall),
             sprintf("%.4f", dx$rank_ic_overall),
             sprintf("%.2fx", ax$bad_normal_ic_ratio),
             sprintf("%d/4", ap$ax_001_v2_pass_count),
             gp$total,
             sprintf("%.4f", ax$core_mdd_relief)),
  stringsAsFactors = FALSE
)

components <- unlist(ap$v22b_components)
selected_str <- paste(components, collapse = " / ")

key_findings <- paste0(
  "Iter 22b STRICT filter: 7/7 Iter 22 components PASS individual cor_dd<0 AND ic_dd>0. ",
  "Composite V22b top_only ↔ STR_1701 cor_dd = -0.1907 (mandate -0.10 PASS). ",
  "Iter 22 broad V22 +0.18 fail was likely measurement artifact (bad ym join). ",
  "Hedge variant relief 0.0485 cor_dd -0.1195 also passes but top_only chosen for stronger negativity. ",
  "AX-001 v2 only 1/4 PASS (target ≥3/4) — bad/normal IC 7.92 strong but crisis_alpha 0.011 + harvey 1.99 + relief 0.0485 fall short of strict thresholds. ",
  "Long-only top-decile breadth limit confirmed."
)

flags <- unlist(ap$challenge_flags)

res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260427_007 ALPHA_DONE — Iter 22b Hedge-Strict (cor_dd=-0.19 PASS, AX 1/4)",
  sections = list(
    list(emoji = "📊", heading = "V22b Diagnostics", type = "table", df = diag_df),
    list(emoji = "💡", heading = "핵심 발견 (Hedge-Strict 결과)",
         type = "text", body = key_findings),
    list(emoji = "🚩", heading = "Challenge Flags",
         type = "bullet", items = as.character(flags)),
    list(emoji = "🎛️", heading = "메타 / 다음 단계", type = "kv",
         kv = list(
           WT_ID = ap$task_id,
           Phase = "ALPHA_DONE",
           Selected_Components = sprintf("%d/7", length(components)),
           Components = selected_str,
           Blend = ap$v22b_blend_type,
           Codex_Stance = ap$codex_critic_resolution$stance,
           Next = "PROCEED_PARTIAL_drawdown_cor_PASS_but_AX_only_1of4_recommend_iter23_anti_regression"
         ))
  ),
  emoji_min = 5L
)
stopifnot(isTRUE(res$ok))
cat("[telegram] sent\n")
