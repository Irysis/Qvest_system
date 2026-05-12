#==============================================================================
# WT-D20260508_006 — Telegram brief (v6.2 SOT)
# Run AFTER alpha_package.json (post-Codex) finalize.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

WT_ID <- "WT-D20260508_006"
final_path <- sprintf("qepm/mailbox/worktask/%s/alpha_package.json", WT_ID)
draft_path <- sprintf("qepm/mailbox/worktask/%s/alpha_package_draft.json", WT_ID)
codex_path <- sprintf("qepm/mailbox/worktask/%s/codex_critic_response_alpha.json", WT_ID)

pkg_path <- if (file.exists(final_path)) final_path else draft_path
pkg <- fromJSON(pkg_path, simplifyVector = FALSE)

# Codex stance
codex_stance <- "PENDING"
if (file.exists(codex_path)) {
  cdex <- fromJSON(codex_path, simplifyVector = FALSE)
  codex_stance <- cdex$stance %||% (cdex$verdict %||% "UNKNOWN")
}
"%||%" <- function(x, y) if (!is.null(x) && length(x) > 0 && !identical(x, "")) x else y

# Section 1: 연구 컨텍스트 (한글, v6.2 의무)
sec_context <- list(
  type = "bullet",
  emoji = "📚",
  heading = "연구 컨텍스트",
  items = c(
    "목적: KPS 2019 JFE 특성 instrumented 잠재팩터 알파 한국 검증",
    "방법: KOSPI200∪KOSDAQ150 348종목 5개 핵심 특성 IPCA + Γ_α 추정",
    "구간: 학습 156개월 + 검증 24개월 + 락박스 16개월 (1990~2026)",
    "결론: 12/13 graduation+robustness 기준 FAIL — 정직한 음의 발견"
  )
)

# Section 2: 핵심 비교 (정량 결과 metric만)
diag <- pkg$diagnostics
sec_metrics <- list(
  type = "kv",
  emoji = "📊",
  heading = "핵심 비교 (graduation 검증)",
  kv = list(
    "정보계수 IC" = sprintf("%+.4f / 기준 0.04 ❌", diag$rank_ic),
    "ICIR" = sprintf("%+.4f / 기준 0.20 ❌", diag$icir),
    "Harvey-t (NW)" = sprintf("%+.3f / 기준 3.0 ❌", diag$harvey_t_stat),
    "검증 IC (24개월)" = sprintf("%+.4f ❌", diag$validation_mean_IC),
    "락박스 IC (16개월)" = sprintf("%+.4f ❌", diag$lockbox_mean_IC),
    "락박스 연샤프" = sprintf("%+.3f", diag$lockbox_LS_annualized_SR),
    "DSR (n=40 보정)" = sprintf("%.3f / 기준 0.5 ❌",
                              pkg$diagnostics$Bailey_LdP_DSR_n_eff_40 %||% 0.217),
    "단일 V01_BM ICIR" = "+0.210 (composite +0.022 = -89%)",
    "섹터중립 IC" = "-0.0025 (retention -74%)"
  )
)

# Section 3: 시그널 decay 패턴
sub <- diag$subperiod_breakdown
sec_decay <- list(
  type = "kv",
  emoji = "📉",
  heading = "부기간 IC 추이 (시그널 감쇠)",
  kv = list(
    "2010-2014 (60개월)" = "+0.0577 (positive)",
    "2015-2019 (60개월)" = "-0.0080 (zero)",
    "2020-2024 (60개월)" = "-0.0394 (negative)"
  )
)

# Section 4: Challenge Flags
fail_codes <- pkg$graduation_assessment$fail_codes
sec_flags <- list(
  type = "bullet",
  emoji = "🚩",
  heading = "Challenge Flags (graduation FAIL 6건)",
  items = c(
    "GRAD_RANK_IC_FAIL: 정보계수 +0.003 (기준 0.04)",
    "GRAD_ICIR_FAIL: 정보계수 안정성 +0.022 (기준 0.20)",
    "GRAD_HARVEY_T_FAIL: 다중검정 t값 +0.23 (기준 3.0)",
    "GRAD_SUBPERIOD_INSTABILITY: 안정성 0.0 (3분기 중 1분기만 양수)",
    "VALIDATION_OOS_NEGATIVE: 검증 IC 음전 (2023-24 -0.046)",
    "LOCKBOX_OOS_NEGATIVE: 락박스 IC 음전 (2025-26.04 -0.027)"
  )
)

# Section 5: Decision + Codex
sec_decision <- list(
  type = "kv",
  emoji = "🎯",
  heading = "최종 결정",
  kv = list(
    "결정" = "GRADUATION_FAIL_HONEST_NEGATIVE_DEEP",
    "Codex stance" = codex_stance,
    "downstream" = "Risk/Optimizer 차단 (Charter §8)",
    "본질 진단" = "KR 단순 특성 anomaly base 2015후 decay → IPCA 음전"
  )
)

# Section 6: Next
sec_next <- list(
  type = "bullet",
  emoji = "➡️",
  heading = "다음 단계",
  items = c(
    "challenge_note.md Codex stance 반영 update",
    "alpha_package.json finalize (graduation FAIL stamp)",
    "Q-Lead 결과 보고 (Risk/Optimizer 비전이)",
    "L-code 후속 적립 검토: KR IPCA K=4 L=6 단순화 시 시그널 decay post-2020 (AX-empirical 후보)"
  )
)

ok_or_err <- tryCatch({
  res <- tg_agent_brief(
    agent = "Alpha",
    title = "특성 instrumented 잠재팩터 알파 검증 (정직한 empirical 실패)",
    as_of = "2026-05-08",
    sections = list(sec_context, sec_metrics, sec_decay, sec_flags, sec_decision, sec_next),
    footer = paste0("📦 산출: alpha_package_draft.json + alpha_validation.json + ipca_fit.rds + alpha_scores.parquet ",
                    "(KPS 2019 IPCA ALS 156개월 학습, 37 iter 수렴, 한국 cross-section 무력 입증)")
  )
  cat("[telegram] sent:", isTRUE(res$ok), " bytes:", res$bytes, "\n")
  res
}, error = function(e) {
  cat("[telegram] ERROR:", conditionMessage(e), "\n")
  list(ok = FALSE, error = conditionMessage(e))
})
