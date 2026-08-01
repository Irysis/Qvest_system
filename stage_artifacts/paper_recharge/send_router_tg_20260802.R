#!/usr/bin/env Rscript
# Paper Router v2 텔레그램 보고 — 20260802
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
    title  = "논문 라우터 v2 — 리서치 소스 배분 + 팩터 마이닝 (20260802)",
    relaxed = TRUE,
    force   = TRUE,
    lock_scope = "paper_router_20260802",
    sections = list(
      list(
        emoji   = "📊",
        heading = "배분 요약",
        type    = "summary",
        body    = "arxiv 38건 배분 완료. testable 팩터 2건 발굴, AUTORUN 2건 실행 중."
      ),
      list(
        emoji   = "💡",
        heading = "쉬운 설명",
        type    = "bullet",
        items   = c(
          "논문 38편을 역할별 분류: alpha 5 | optimizer 3 | risk 4 | regime 2 | 범위 밖 24.",
          "범위 밖: 암호화폐·옵션이론·순수 수학 등 한국 주식 적용 불가 논문들.",
          "optimizer·regime 논문에서 숨은 팩터 2건 발굴 → 자동 백테스트 투입.",
          "5단계 검증 게이트(PIT·계약·강건성·충실성·자동판정) 통과분만 지식 적립."
        )
      ),
      list(
        emoji   = "🔄",
        heading = "AUTORUN 실행 중 (2건)",
        type    = "bullet",
        items   = c(
          "C_VolRankStability — 변동성 랭크 3개월 변화 신호 (arxiv:2607.27461, confidence 0.78). 기존 DB에 없는 신호. 종목별 과거 1년 변동성 랭크가 낮아지고 있으면 매수 우선.",
          "T_RetAutoCorr_12M — 월간 수익률 12개월 자기상관 신호 (arxiv:2607.19497, confidence 0.55). 수익률 추세가 일관되게 지속되는 종목 선택. T15(21일 일별)과 구분: 월 빈도 횡단면."
        )
      ),
      list(
        emoji   = "🔬",
        heading = "STEP2 팩터 발굴 (route 무관 overlay)",
        type    = "bullet",
        items   = c(
          "C_VolRankStability (optimizer 논문에서 추출) — testable | DB 신규 | 가격만으로 산출 가능",
          "T_RetAutoCorr_12M (regime 논문에서 추출) — testable | DB 유사 존재 가능성 uncertain | 가격만으로 산출 가능",
          "C_VolRankStability: 논문 핵심 발견 = 변동성 랭크는 1개월 예측 가능, 수익률 랭크는 불가.",
          "T_RetAutoCorr_12M: 논문 핵심 발견 = 추세추종 알파 = 수익률 저주파 스펙트럼 질량 과잉."
        )
      ),
      list(
        emoji   = "📋",
        heading = "optimizer / risk / regime 큐",
        type    = "bullet",
        items   = c(
          "optimizer 큐 3건: Kelly 흡수경계 비선형 sizing (2607.28230) | 3행렬 동적배분 (2607.27461) | MACD 잠재드리프트 수학적 기초 (2607.01705)",
          "risk 큐 4건: rough Heston 조건부 밀도 (2607.27588) | Transformer 잠재 변동성 표현 (2607.25459) | 장기기억 GARCH 마르코프 (2607.25189) | 특성 기반 공분산 CD-DFM (2607.24410)",
          "regime 큐 2건: 중국 A주 군집투자 지표(한국 시장 국면감지 후보, 2607.27063) | 추세추종 통합이론 (2607.19497)"
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
