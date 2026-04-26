suppressMessages({
  source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")
})

tg_diag_df <- data.frame(
  Metric = c("cor_v18_vs_STR1701", "ICIR", "rank_IC", "Sub_Stab", "Harvey_5spec_pass",
             "DSR_post", "Monotonicity", "Gates_Passed"),
  Value  = c("1.000000 (>=0.95 PASS)", "0.2009", "0.0270", "0.2041", "0/5",
             "0.9716", "0.4444", "2/5"),
  stringsAsFactors = FALSE
)

res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260427_002 ALPHA_DONE — Iter 18 STR_1701 strict inheritance (cor=1.000)",
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (inheritance audit)",
         type = "table", df = tg_diag_df),

    list(emoji = "💡", heading = "핵심 발견",
         type = "text",
         body = paste(
           "Iter 18 = Optimizer Track. STR_1701 base score 그대로 inheritance.",
           "alpha_inheritance_hash cor = 1.000000 (mandate >= 0.95 strict PASS).",
           "Iter 14/15 학습 적용 — confidence weighting/multi-mutation 의도적 회피.",
           "ICIR 0.2009 PASS / DSR 0.972 PASS / 그러나 rank_IC + sub_stab + Harvey FAIL은",
           "STR_1701 base 자체의 inherited limitation (Iter 11 PG2 active 시점 인지된 상태).",
           "본 sprint 가설: Optimizer mechanism으로 net_IR 개선 — alpha 변경 X.",
           "Codex stance REJECT, Q-Lead OVERRIDE_005 (Charter §1 Pure Function)."
         )),

    list(emoji = "🚩", heading = "Challenge Flags & Resolutions",
         type = "bullet",
         items = c(
           "RF-A1 sub_stab 0.20 (inherited; Optimizer Track mandate)",
           "RF-A2 composite ICIR < best component (multi-sleeve trade-off)",
           "RF-A3 alpha rank TO 698% (Optimizer 책임 영역; Iter 11 LinTilt 586%)",
           "RF-A6/A7/A8 graduation 부분 fail (inherited; Optimizer activation 가설)",
           "Codex 8 concerns + 1 weakest_assumption = 9/9 resolution applied"
         )),

    list(emoji = "🎛️", heading = "메타",
         type = "kv",
         kv = list(
           WT_ID = "WT-D20260427_002",
           Iter = "18 — Optimizer Track",
           Phase = "ALPHA_DONE",
           BaseStrategy = "STR_1701 (Iter 11 PG2 80%)",
           InheritanceCor = "1.000000 strict PASS",
           CodexStance = "REJECT",
           QLeadOverride = "OVERRIDE_005",
           ResolutionCount = "9/9",
           NextStage = "Optimizer (CVaR-aware MVO + adaptive psi)"
         ))
  ),
  emoji_min = 5L
)
stopifnot(isTRUE(res$ok))
cat("Telegram brief sent.\n")
