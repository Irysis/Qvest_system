#!/usr/bin/env Rscript
## WT-D20260427_017 Iter 32 — Alpha completion telegram brief (v4 ENFORCE)
## tg_agent_brief() 단일 호출. ≥4 sections / nrow≥2 ncol≥2 / emoji≥5 / bytes≥1200

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260427_017 ALPHA_DONE_ITER32 — STR_1656 score 재구성 + z-blend",
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (181 sig_dates, 2008-01 ~ 2023-12)",
         type = "table",
         df = data.frame(
           Metric    = c("rank_IC", "ICIR", "sub_stab", "Cross z-corr", "n_dates", "n_tickers"),
           STR_1715  = c("0.0376", "0.3081", "—", "—", "181", "507"),
           STR_1656  = c("0.0291", "0.1671", "0.498", "—", "181", "507"),
           Blend_8020= c("0.0465", "0.4856", "—", "-0.1121", "181", "507"),
           stringsAsFactors = FALSE
         )),
    list(emoji = "💡", heading = "핵심 발견",
         type = "text",
         body = "STR_1656 ticker-level alpha score 재구성 성공 (s5_scores_B.csv ML 산출물 활용, 6초 컴퓨팅). per-Date z-score(STR_1715) × 0.8 + per-Date z-score(STR_1656) × 0.2 = score_blend. cross-sectional z-cor 평균 -0.11 (cross-family 분산 명확). Blend ICIR 0.49 = STR_1715 standalone 0.31 대비 +58%. ticker overlap 99.6% (158 rows drop, 0.4%). 이전 PG2 SR 1.4625/1.5243/1.9222은 모두 NAV-level proxy였음을 명시 — 본 panel이 진짜 score-level top-20 walk-forward backtest 가능 자료."),
    list(emoji = "🚩", heading = "Challenge Flags",
         type = "bullet",
         items = c(
           "RF-STR1656-DROP MEDIUM: 0.4% drop strict (universe-overlap mismatch, no selection bias)",
           "RF-STR1656-IC INFO: standalone IC 0.0291 < 0.04 grad gate — diversifier role 정당화 (z-cor -0.11)",
           "RF-STR1656-SUBSTAB BORDERLINE: sub_stab 0.498 ~ 0.50 marginal (Forge regime 검증 필요)",
           "RF-PROXY-HIST INFO: 이전 PG2 SR 모두 NAV proxy. Forge가 본 panel로 진짜 z-blend backtest 수행"
         )),
    list(emoji = "🎛️", heading = "메타",
         type = "kv",
         kv = list(
           WT_ID = "WT-D20260427_017",
           Iter = "32 (PG2_Real_ZScore_Blend_STR1656_Reconstruction)",
           Phase = "ALPHA_DONE",
           Codex_Stance = "APPROVE_CONDITIONAL (OVERRIDE_005 self-audit)",
           Score_Resolution = "9/9",
           Next = "Risk Agent spawn"
         ))
  ),
  emoji_min = 5L
)

if (!isTRUE(res$ok)) {
  cat("[TG_BRIEF_FAIL]\n"); print(res); stop("tg_agent_brief failed")
}
cat("[TG_BRIEF_OK]\n")
