##=============================================================================
## ff5_brief_send.R — 모닝브리핑 스타일 국면 블록: FF5 + 스마트베타 통합 (v2)
## 흐름: FF5 재빌드(~10초) + SB 증분 갱신(신규월만) → 국면 판독 → tg 1건 발송
## 라벨: diagnostic_monitoring — 시장 리뷰 전용(전략/자본 인용 금지)
##=============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)

ok_ff <- tryCatch({ source("02_Infrastructure/reports/ff5_kr_tracker.R"); TRUE },
                  error = function(e) { cat("[ff5_brief] FF5 build FAIL:", conditionMessage(e), "\n"); FALSE })
ok_sb <- tryCatch({ source("02_Infrastructure/reports/smartbeta_kr_tracker.R"); TRUE },
                  error = function(e) { cat("[ff5_brief] SB build FAIL:", conditionMessage(e), "\n"); FALSE })
ok_bf <- tryCatch({ source("02_Infrastructure/reports/krx_index_monthend_backfill.R"); TRUE },
                  error = function(e) { cat("[ff5_brief] index backfill FAIL:", conditionMessage(e), "\n"); FALSE })
ok_ib <- tryCatch({ source("02_Infrastructure/reports/index_factor_beta.R"); TRUE },
                  error = function(e) { cat("[ff5_brief] index-beta build FAIL:", conditionMessage(e), "\n"); FALSE })

FF <- tryCatch(as.data.table(read_parquet("outputs/ff5_kr/ff5_kr_monthly.parquet")), error = function(e) NULL)
SB <- tryCatch(as.data.table(read_parquet("outputs/smartbeta_kr/smartbeta_kr_monthly.parquet")), error = function(e) NULL)
if (is.null(FF) || !nrow(FF)) { cat("[ff5_brief] FF 시리즈 없음 — skip\n") } else {
  setorder(FF, ym)
  for (cc in c("MKT", "SMB", "HML", "RMW", "CMA")) FF[, (paste0("r12_", cc)) := frollmean(get(cc), 12)]
  L <- FF[.N]
  fmt <- function(v) if (is.na(v)) "NA" else sprintf("%+.2f%%", v * 100)   # 월 수익률 % 표기 (도훈 지시 07-18)
  regime_line <- sprintf("%s 주도 / %s 우위 / 퀄리티 %s",
    ifelse(L$r12_SMB < 0, "대형", "소형"), ifelse(L$r12_HML < 0, "성장", "가치"),
    ifelse(is.na(L$r12_RMW), "?", ifelse(L$r12_RMW > 0, "강세", "약세")))
  revive_watch <- if (!is.na(L$r12_SMB) && !is.na(L$r12_HML) && L$r12_SMB > 0 && L$r12_HML > 0)
    "SMB·HML rolling 동반 양전 — 소형/가치 반전 신호, 매장 팩터 un-bury 검토 발화"
  else "반전 신호 없음 (SMB·HML rolling 동반 양전 시 발화)"

  sections <- list(
    list(heading = "FF5 최근월", type = "kv", kv = list(
      "시장초과 MKT" = fmt(L$MKT), "소형-대형 SMB" = fmt(L$SMB), "가치-성장 HML" = fmt(L$HML),
      "수익성 RMW" = fmt(L$RMW), "투자보수 CMA" = fmt(L$CMA))),
    list(heading = "FF5 최근 12개월 평균", type = "kv", kv = list(
      "시장초과 MKT" = fmt(L$r12_MKT), "소형-대형 SMB" = fmt(L$r12_SMB), "가치-성장 HML" = fmt(L$r12_HML),
      "수익성 RMW" = fmt(L$r12_RMW), "투자보수 CMA" = fmt(L$r12_CMA))))
  ## 진행월 MTD (직전영업일까지 — 도훈 지시 07-18)
  mtd5 <- tryCatch(jsonlite::fromJSON("outputs/ff5_kr/ff5_kr_mtd.json"), error = function(e) NULL)
  if (!is.null(mtd5) && !is.null(mtd5$as_of)) {
    sections[[length(sections) + 1]] <- list(
      heading = sprintf("진행월 MTD (직전영업일 %s, %d거래일)", mtd5$as_of, mtd5$n_days), type = "kv", kv = list(
        "시장초과 MKT" = fmt(mtd5$MKT), "소형-대형 SMB" = fmt(mtd5$SMB), "가치-성장 HML" = fmt(mtd5$HML),
        "수익성 RMW" = fmt(mtd5$RMW), "투자보수 CMA" = fmt(mtd5$CMA)))
  }
  charts <- "outputs/ff5_kr/charts/ff5_rolling12.png"

  sb_line <- NULL
  if (!is.null(SB) && nrow(SB) >= 12) {
    setorder(SB, ym)
    sty <- intersect(c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV"), names(SB))
    r12 <- vapply(sty, function(s) mean(tail(SB[[s]], 12), na.rm = TRUE), numeric(1))
    kv_names <- c(VAL = "가치포워드", QUAL = "퀄리티", MOM = "모멘텀",
                  LOWVOL = "저변동성", SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
    kvl <- as.list(vapply(r12, fmt, character(1))); names(kvl) <- kv_names[sty]
    sections[[length(sections) + 1]] <- list(heading = "스마트베타 최근 12개월 평균 초과수익", type = "kv", kv = kvl)
    top <- sty[which.max(r12)]; bot <- sty[which.min(r12)]
    sb_line <- sprintf("스마트베타: %s 최강 / %s 최약 (최근 12개월 유니버스 대비)", kv_names[top], kv_names[bot])
    ## v3 최근동향 차트 (도훈 지시): 정렬 막대 + 24개월 히트맵 (장기 소형패널은 rolling12 파일로 별도 보관)
    charts <- c(charts, "outputs/smartbeta_kr/charts/smartbeta_recent_bars.png",
                "outputs/smartbeta_kr/charts/smartbeta_heatmap24.png")
  }
  ## 지수 팩터 민감도 (도훈 지시 07-18)
  ib <- tryCatch(jsonlite::fromJSON("outputs/ff5_kr/index_factor_beta.json"), error = function(e) NULL)
  if (!is.null(ib) && !is.null(ib$betas)) {
    bn <- c(KOSPI200 = "코스피200", KOSDAQ150 = "코스닥150", KOSPI = "코스피", KOSDAQ = "코스닥")
    ## 전체 프로파일 표기 (도훈 정정 07-18 — "RMW만 나옴": 최대 1개 → 4팩터 전체)
    items_ff <- vapply(names(bn), function(ix) { b <- ib$betas[[ix]]
      v <- c(SMB = b$SMB, HML = b$HML, RMW = b$RMW, CMA = b$CMA)
      tk <- vapply(names(v), function(f) sprintf("%s %+.2f", f, v[f]), character(1))
      tk[which.max(abs(v))] <- sprintf("<b>%s</b>", tk[which.max(abs(v))])   # 최대 민감도 볼드
      sprintf("%s: %s (MKT %.2f)", bn[ix], paste(tk, collapse = " · "), b$MKT) }, character(1))
    sections[[length(sections) + 1]] <- list(heading = "지수 팩터 민감도 (FF5·36개월 베타)",
                                             type = "bullet", items = unname(items_ff))
    charts <- c(charts, "outputs/ff5_kr/charts/index_factor_beta.png")
    if (!is.null(ib$sb_betas)) {
      krs <- c(VAL = "가치", QUAL = "퀄리티", MOM = "모멘텀", LOWVOL = "저변동성",
               SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
      items_sb <- vapply(names(bn), function(ix) { v <- unlist(ib$sb_betas[[ix]]); o <- order(-abs(v))[1:2]
        sprintf("%s: <b>%s %+.2f</b> · %s %+.2f (상위 2)", bn[ix],
                krs[names(v)[o[1]]], v[o[1]], krs[names(v)[o[2]]], v[o[2]]) }, character(1))
      sections[[length(sections) + 1]] <- list(heading = "지수 스마트베타 민감도 (36개월·시장통제)",
                                               type = "bullet", items = unname(items_sb))
      charts <- c(charts, "outputs/ff5_kr/charts/index_smartbeta_beta.png")
    }
  }
  sections[[length(sections) + 1]] <- list(heading = "국면 판독", type = "bullet", items = c(
    sprintf("현 국면: %s", regime_line),
    if (!is.null(sb_line)) sb_line,
    sprintf("부활조건 워치: %s", revive_watch)))

  source("02_Infrastructure/telegram/telegram_notify.R")
  res <- tg_agent_brief(
    agent = "Q-Lead",
    title = sprintf("스타일 국면 브리핑 — FF5 + 스마트베타 (%s 기준)", L$ym),
    sections = sections,
    charts = charts[file.exists(charts)],
    footer = "diagnostic_monitoring · 시장 리뷰 전용(전략/자본 인용 금지) · ff5_kr + smartbeta_kr",
    force = nzchar(Sys.getenv("FF5_BRIEF_FORCE", ""))   # 수동 재발송용(쿨다운 우회) — 크론은 기본 FALSE
  )
  cat("[ff5_brief] sent ok=", isTRUE(res$ok), " ff_build=", ok_ff, " sb_build=", ok_sb, "\n", sep = "")
}
