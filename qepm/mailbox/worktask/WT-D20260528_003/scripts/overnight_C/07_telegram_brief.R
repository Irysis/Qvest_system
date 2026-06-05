#==============================================================================
# WT-D20260528_003 / hypothesis_C — Telegram silent brief (3-section)
#
# 도훈 sleep mode → silent dispatch (lock_scope override).
# tg_agent_brief() 단일 진입점 — caller 직접 호출 금지.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

source(file.path(PROJ_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

WT_ID <- "WT-D20260528_003"
ap_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID, "alpha_package_C.json")

ap <- fromJSON(ap_path, simplifyVector = FALSE)
d <- ap$diagnostics
g <- ap$graduation_gate_summary$criteria
n_gate_pass <- sum(sapply(g, function(x) isTRUE(x$pass)))
n_gate_total <- length(g)

# Title (한글 + 명확)
title <- "마이크로구조 거래량 알파 — 다중sleeve 후보 진단 (hypothesis_C)"

# Sections (3, 한글)
sections <- list(
  # 1. 연구 컨텍스트 (의무 §2 원칙 1) — summary type
  list(
    type = "summary",
    emoji = "📚",
    heading = "연구 컨텍스트",
    body = "STR_1725 거래량 미시구조 4 인자 다중sleeve 알파 발굴 — Codex REJECT 응답 후 정직한 합성 정보계수 측정 결과 graduation 일부 통과 (3/5)."
  ),
  list(
    type = "bullet",
    emoji = "🔬",
    heading = "방법론 요약",
    items = list(
      "L44 거래량-수익률 비대칭 / L42 거래량 왜도 / L33 절대수익-거래량 상관 / L13 거래량 분산비",
      "4 패밀리 × 5종목 다중sleeve 합성 (AX-007 예외 조항 #1 정합)",
      "2008-01 ~ 2023-12 (191 신호일) PIT 정시 검증",
      "KR_top342 유니버스 + 20일 평균거래대금 2억원 유동성 필터",
      "load_month_factors 단독 경유 (C15) + Z_Score_Aligned 단독 (C13)"
    )
  ),

  # 2. 핵심 진단 (kv — 결과 metric only)
  list(
    type = "kv",
    emoji = "📊",
    heading = "핵심 진단 (PIT-정합 실측 합성)",
    kv = list(
      "정보계수 평균 (rank IC)" = sprintf("%.4f (관문 0.04 기준 %s)",
                                          d$rank_ic %||% NA_real_,
                                          ifelse(isTRUE(g$min_rank_ic$pass), "통과", "미달")),
      "정보비율 평균 (ICIR)" = sprintf("%.3f (관문 0.20 기준 %s)",
                                       d$icir %||% NA_real_,
                                       ifelse(isTRUE(g$min_icir$pass), "통과", "미달")),
      "다중검정 t값 (Harvey)" = sprintf("%.2f (관문 3.0 기준 %s)",
                                        d$harvey_t_stat %||% NA_real_,
                                        ifelse(isTRUE(g$min_harvey_t$pass), "통과", "미달")),
      "디플레이티드 샤프 (DSR)" = sprintf("%.3f (관문 0.50 기준 %s)",
                                          d$dsr_skill %||% NA_real_,
                                          ifelse(isTRUE(g$min_dsr$pass), "통과", "미달")),
      "부기간 안정성" = sprintf("%.2f (관문 0.50 기준 %s)",
                                d$subperiod_stability %||% NA_real_,
                                ifelse(isTRUE(g$min_subperiod_stability$pass), "통과", "미달")),
      "4인자 교차상관 최댓값" = sprintf("%.3f (mandate 0.5 기준 %s)",
                                      ap$cross_correlation_audit$max_abs_cor %||% NA_real_,
                                      ifelse(isTRUE(ap$cross_correlation_audit$pass), "통과", "미달")),
      "졸업 관문 종합" = sprintf("%d / %d 기준 통과", n_gate_pass, n_gate_total),
      "최근 3년 ICIR 비율" = sprintf("%.2f배 (RF-A3 임계 1.5배 기준 %s)",
                                    d$recent_p3_ratio %||% NA_real_,
                                    ifelse((d$recent_p3_ratio %||% 0) > 1.5, "Red Flag", "정상"))
    )
  ),

  # 3. Codex Round 결과 + 다음 단계 (각 ≤ 80자)
  list(
    type = "bullet",
    emoji = "🤖",
    heading = "외부 평가 + 다음 단계",
    items = list(
      "코덱스 평가: 거부 — 비판 7건 (높음 5 중간 2)",
      "수용 4건: 실측 정보계수 / 유동성 / 로더 / 최근 3년 집중",
      "부분 인정 3건: Z정렬 / 직교성 본질 / alpha 단계 범위",
      "근거 학술 5 / 코드규칙 6 / 정량 7 — 반박 0건",
      "Q-Lead 아침 retrieval — A안 B안 비교 후 결정",
      "본 알파 단독 평가 X — 3가설 통합 비교 후 admit/terminate"
    )
  )
)

footer <- sprintf("📚 산출물: alpha_package_C.json + alpha_scores.parquet (%d signals × %d unique tickers) + alpha_validation.json + challenge_note_C.md + artifact_lineage_C.json",
                  d$composite_n_months %||% NA_integer_,
                  20L)

# Dispatch (silent, force=TRUE override duplicate scope)
res <- tg_agent_brief(
  agent = "Alpha",
  title = title,
  sections = sections,
  as_of = "2026-05-28",
  footer = footer,
  force = TRUE,
  lock_scope = "Alpha_WT-D20260528_003_hypothesis_C"
)

cat("\n=== Telegram dispatch result ===\n")
print(res)
