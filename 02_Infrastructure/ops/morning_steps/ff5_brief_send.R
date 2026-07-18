##=============================================================================
## ff5_brief_send.R — 모닝브리핑 FF5 스타일 국면 블록 (mrs_daily_briefing.sh 스텝)
## 흐름: 트래커 재빌드(~10초, 게이트 내장) → 최근월+rolling 12m 국면 판독 → tg 발송
## 라벨: diagnostic_monitoring — L/S 스프레드는 시장 리뷰 전용(전략/자본 인용 금지)
##=============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)

ok_build <- tryCatch({ source("02_Infrastructure/reports/ff5_kr_tracker.R"); TRUE },
                     error = function(e) { cat("[ff5_brief] build FAIL:", conditionMessage(e), "\n"); FALSE })

FF <- tryCatch(as.data.table(read_parquet("outputs/ff5_kr/ff5_kr_monthly.parquet")), error = function(e) NULL)
if (is.null(FF) || !nrow(FF)) { cat("[ff5_brief] series 없음 — skip\n") } else {
  setorder(FF, ym)
  for (cc in c("MKT", "SMB", "HML", "RMW", "CMA")) FF[, (paste0("r12_", cc)) := frollmean(get(cc), 12)]
  L <- FF[.N]
  arrow_of <- function(x) if (is.na(x)) "?" else if (x > 0) "+" else "-"
  regime_line <- sprintf("%s 주도 / %s 우위 / 퀄리티 %s",
    ifelse(L$r12_SMB < 0, "대형", "소형"), ifelse(L$r12_HML < 0, "성장", "가치"), arrow_of(L$r12_RMW))
  revive_watch <- if (L$r12_SMB > 0 && L$r12_HML > 0) "SMB·HML rolling 동반 양전 — 소형/가치 반전 신호, 매장 팩터 un-bury 검토 발화" else "반전 신호 없음 (SMB·HML rolling 동반 양전 시 발화)"
  fmt <- function(v) sprintf("%+.4f", v)
  source("02_Infrastructure/telegram/telegram_notify.R")
  res <- tg_agent_brief(
    agent = "Q-Lead",
    title = sprintf("FF5 스타일 국면 (%s 기준)", L$ym),
    sections = list(
      list(heading = "최근월 팩터 수익", type = "kv", kv = list(
        "시장초과 MKT" = fmt(L$MKT), "소형-대형 SMB" = fmt(L$SMB), "가치-성장 HML" = fmt(L$HML),
        "수익성 RMW" = fmt(L$RMW), "투자보수 CMA" = fmt(L$CMA))),
      list(heading = "최근 12개월 평균", type = "kv", kv = list(
        "시장초과 MKT" = fmt(L$r12_MKT), "소형-대형 SMB" = fmt(L$r12_SMB), "가치-성장 HML" = fmt(L$r12_HML),
        "수익성 RMW" = fmt(L$r12_RMW), "투자보수 CMA" = fmt(L$r12_CMA))),
      list(heading = "국면 판독", type = "bullet", items = c(
        sprintf("현 국면: %s", regime_line),
        sprintf("부활조건 워치: %s", revive_watch)))
    ),
    charts = "outputs/ff5_kr/charts/ff5_rolling12.png",
    footer = "diagnostic_monitoring · 시장 리뷰 전용(전략/자본 인용 금지) · ff5_kr_tracker"
  )
  cat("[ff5_brief] sent ok=", isTRUE(res$ok), " build_ok=", ok_build, "\n", sep = "")
}
