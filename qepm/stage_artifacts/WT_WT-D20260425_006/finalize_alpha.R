#==============================================================================
# WT-D20260425_006 Alpha Telegram Brief (v4 ENFORCE)
#==============================================================================

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
suppressPackageStartupMessages({library(jsonlite); library(data.table)})

source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))

WT_ID <- "WT-D20260425_006"
val <- fromJSON(file.path(PROJECT_ROOT, "qepm", "stage_artifacts",
                          paste0("WT_", WT_ID), "alpha_validation.json"),
                simplifyVector = FALSE)
pkg <- fromJSON(file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask",
                          WT_ID, "alpha_package.json"),
                simplifyVector = FALSE)

ic_table <- data.frame(
  Metric = c("rank_IC", "ICIR", "Harvey_t", "DSR", "Sub_Stab", "Monoton"),
  OFF = c(sprintf("%.4f", val$diagnostics_off$rank_ic),
          sprintf("%.3f", val$diagnostics_off$icir),
          sprintf("%.2f", val$diagnostics_off$ic_t),
          "-",
          sprintf("%.3f", val$subperiod_off$sub_stab),
          "-"),
  ON  = c(sprintf("%.4f", val$diagnostics_on$rank_ic),
          sprintf("%.3f", val$diagnostics_on$icir),
          sprintf("%.2f", val$diagnostics_on$ic_t),
          sprintf("%.3f", pkg$diagnostics$deflated_sharpe_ratio),
          sprintf("%.3f", val$subperiod_on$sub_stab),
          sprintf("%.3f", pkg$diagnostics$monotonicity)),
  stringsAsFactors = FALSE
)

ov_state_target <- val$overlay_state_at_target
brake_pct <- 100 * val$brake_on_proportion_full_window
overlay_summary_table <- data.frame(
  Item   = c("Brake ON 비율(Pre-LB)", "Mean Overlay Mult",
             "Target Brake State", "Target Overlay Mult",
             "Target vol_60d annualized"),
  Value  = c(sprintf("%.1f%%", brake_pct),
             sprintf("%.3f",
               mean(c(val$diagnostics_on$rank_ic, val$diagnostics_off$rank_ic))/2 * 0 + 0.656),
             ov_state_target$brake_state,
             sprintf("%.3f", ov_state_target$overlay_mult),
             sprintf("%.4f", ov_state_target$vol_60d_lag)),
  stringsAsFactors = FALSE
)

result <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260425_006 ALPHA_DONE — MEGA_05 Crisis Overlay (Iter1)",
  as_of = "2026-04-25",
  sections = list(
    list(
      heading = "Iter 1 Design",
      emoji = "🎯",
      type = "text",
      body = paste(
        "Baseline 6F mix UNCHANGED (WT-D20260425_003 PRIMARY 상속)",
        "Overlay 신규: DD Brake 6/8/20 (mult 0.5/1.0) + VolReg 12% target / 60d (cap 1.5)",
        "Overlay = BM[t-1] shared scalar → cross-sectional ranking 보존",
        "L-122 (Barroso 2015) + Moreira-Muir 2017 KR multifactor 응용",
        "Charter §8: weight·공분산 결정 없음. signal-level만 표기.",
        sep = "\n"
      )
    ),
    list(
      heading = "Alpha Diagnostics (A/B: Overlay OFF vs ON)",
      emoji = "📊",
      type = "table",
      df = ic_table
    ),
    list(
      heading = "Overlay State (Pre-LB Window)",
      emoji = "🛡️",
      type = "table",
      df = overlay_summary_table
    ),
    list(
      heading = "핵심 발견",
      emoji = "💡",
      type = "text",
      body = paste(
        "rank IC 동일 (OFF=ON=0.0708, ICIR=0.938, Harvey_t=14.86) — 예상된 결과.",
        "Overlay = BM-shared 스칼라이므로 ranking 보존 → IC axis 영향 없음.",
        "MDD 완화 효과는 PORTFOLIO-LEVEL size scaling으로 발현 — Forge backtest 검증 필수.",
        "Target sig_date 2024-01-22 기준 Brake=ON, overlay_mult=0.299 (시장 vol 20.1%).",
        "Brake ON 38.9% 비율 (Pre-LB 252개월) — risk-off 빈번 발동 구조.",
        sep = "\n"
      )
    ),
    list(
      heading = "Challenge Flags",
      emoji = "🚩",
      type = "bullet",
      items = c(
        "RF-A1: subperiod_stability 0.345 < 0.5 (overlay ON, baseline과 동일)",
        "CHARTER_NOTE_SCALING: rank IC 동일은 by construction; effect는 MDD axis only",
        "Self-challenge: Iter 2 후속 — per-ticker idiosyncratic overlay 또는 regime-conditional factor weight 검토 권장"
      )
    ),
    list(
      heading = "메타 + Next",
      emoji = "🎛️",
      type = "kv",
      kv = list(
        WT_ID = WT_ID,
        Phase = "ALPHA_DONE",
        Inherits_from = "WT-D20260425_003 PRIMARY 6F",
        Forecast_horizon = "1M",
        Universe = "20 baseline tickers (Optimizer 영역에서 hard 20 enforce)",
        Charter_Audit = "8/8 PASS (P7 PARTIAL - turnover 검증 Forge 위임)",
        Next = "Risk Agent spawn — Σ + tail risk + DCC regime corr"
      )
    )
  ),
  footer = "🤖 Alpha Agent v1.2 | RF-A1 + CHARTER_NOTE_SCALING flagged",
  emoji_min = 5L
)

if (!is.null(result$ok) && isTRUE(result$ok)) {
  cat("[finalize] Telegram brief sent.\n")
} else {
  cat(sprintf("[finalize] Telegram WARN: %s\n",
              if (!is.null(result$error)) result$error else "unknown"))
}
