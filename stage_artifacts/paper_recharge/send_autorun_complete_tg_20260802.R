#!/usr/bin/env Rscript
# Paper Router v2 AUTORUN 완료 텔레그램 — 20260802
suppressWarnings(suppressMessages({ library(jsonlite) }))

.FIND_ROOT <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR",""), Sys.getenv("QM_ROOT",""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p,"02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash="/", mustWork=TRUE))
  stop("project root not found")
}
PROJECT_ROOT <- .FIND_ROOT()
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a

result <- tryCatch(
  tg_agent_brief(
    agent  = "AlphaSearch",
    title  = "AUTORUN 완료 — 2건 QUARANTINE (20260802)",
    relaxed = TRUE,
    force   = TRUE,
    lock_scope = "paper_router_autorun_complete_20260802",
    sections = list(
      list(
        emoji   = "📊",
        heading = "결과 요약",
        type    = "summary",
        body    = "AUTORUN 2건 모두 QUARANTINE. 프론티어 4건 신규 등재."
      ),
      list(
        emoji   = "💡",
        heading = "쉬운 설명",
        type    = "bullet",
        items   = c(
          "두 신호 모두 5단계 검증 통과 못해 자본 배정 없음(격리 처리).",
          "실패 원인: 낙폭 과다(MDD 55~62%)·신호→실제 포트 전환 차단.",
          "신호가 완전히 사라진 건 아님 — 방향 반전·오버레이 결합 등 4개 후속 탐색 등재."
        )
      ),
      list(
        emoji   = "❌",
        heading = "C_VolRankStability_3M (QUARANTINE)",
        type    = "bullet",
        items   = c(
          "신호: 변동성 순위 3개월 개선 종목 매수 (arxiv:2607.27461)",
          "SR 0.275 | MDD 62.1% | OOS 0.045 | IR -0.234",
          "실패: KR에서 신호 역작동. GFC/금리쇼크에서 벤치마크보다 더 급락.",
          "비교: 7월 동류 실험(VOL_RANK_STABILITY_v1, SR 0.167) 대비 소폭 개선 — 동일 벽."
        )
      ),
      list(
        emoji   = "❌",
        heading = "T_RetAutoCorr_12M (QUARANTINE)",
        type    = "bullet",
        items   = c(
          "신호: 월간 수익률 12개월 자기상관 높은 종목 매수 (arxiv:2607.19497)",
          "SR 0.517 | MDD 55.4% | PORT_t -0.295 | OOS 0.161",
          "주목: Fama-MacBeth t=2.50* — 횡단면 신호 자체는 유효. 포트 번역이 차단.",
          "실패: 낙폭 과다(MDD 55%) + 신호→포트폴리오 전이 벽(DIST-AR-003 패턴)."
        )
      ),
      list(
        emoji   = "🔭",
        heading = "후속 탐색 큐 (FQ-092~095 등재)",
        type    = "bullet",
        items   = c(
          "FQ-092: vol rank 역방향 신호 (순위 상승=고변동성 모멘텀 long).",
          "FQ-093: vol rank 상승 속도 → 위기 조기 경보 overlay 입력 후보.",
          "FQ-094: autocorr 역방향 (낮은 autocorr=평균회귀 구간 종목 long).",
          "FQ-095: autocorr × BearProb overlay 결합 (FMB 2.50* 신호력 + MDD 레버)."
        )
      )
    )
  ),
  error = function(e) list(ok=FALSE, error=conditionMessage(e))
)

if (isTRUE(result$ok)) {
  cat("TG_OK\n")
} else {
  cat(sprintf("TG_FAIL: %s\n", result$error %||% "unknown"))
}
