## DEPRECATED 2026-07-03 — Layer4 제거로 noLayer4 버전(monitor_nolayer4_paper.R)으로 대체. rollback 보존용 (호출 끊김, 로직 미변경).
## FaithTrend book — 월간 live paper-tracking 모니터 (holdout 대조 + drift + Telegram)
## 실행: Rscript monitor_faithtrend_paper.R  (월간 cron/trigger. 앞서 base+overlay 최신화 후 호출)
## measurement-graduation §3 holdout 라이브 연장: trailing 실측 → judge_holdout → 하단 침범 alert(퇴출은 도훈 수동).
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT,"02_Infrastructure/contracts/holdout_falsification.R"))
BOOK_ID <- "STR_1715_FaithTrend_on_M4_R05_overlay_PG2"
LT <- file.path(ROOT,"06_Registry/live_track",BOOK_ID)
iv <- fromJSON(file.path(LT,"holdout_interval.json"))
navf <- file.path(LT,"paper_nav.csv"); pnav <- fread(navf)

## 최신 faith 백테 (run_layer5_faith_overlay.R 산출 — 사전 최신화 가정)
faith_path <- file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv")
faith <- fread(faith_path); setorder(faith, realized_ym)
tracked <- if ("realized_ym" %in% names(pnav)) pnav[event=="REALIZED" & !is.na(realized_ym), realized_ym] else character(0)
## ── deploy 컷오프 + 결손 감지 (도훈 mandate 2026-08-01 "날짜 하드코딩은 다 없애라") ──
##   구판: `realized_ym > "2026-06"` 고정 — 매달 손으로 늘려야 했고, 안 늘리면 조용히 낡는다.
##   컷오프는 paper_nav 의 DEPLOY_START 에서 파생한다. 아울러 nolayer4 미러와 동일하게
##   "신규 없음"을 무조건 정상이라 부르지 않는다(시리즈 종점이 기대 실현월에 닿았는지 확인).
.dep_row  <- pnav[event=="DEPLOY_START"]
DEPLOY_YM <- if (nrow(.dep_row)) substr(as.character(.dep_row$date[1]), 1, 7) else min(faith$realized_ym)
CUTOFF_YM <- format(as.Date(paste0(DEPLOY_YM, "-01")) - 1, "%Y-%m")
new_rows  <- faith[!(realized_ym %in% tracked) & realized_ym > CUTOFF_YM]

EXPECT_YM  <- format(Sys.Date(), "%Y-%m")
SERIES_MAX <- max(faith$realized_ym, na.rm = TRUE)
.lag_m <- length(seq(as.Date(paste0(SERIES_MAX,"-01")), as.Date(paste0(EXPECT_YM,"-01")), by="month")) - 1L
if (.lag_m > 0L)
  cat(sprintf("[%s][faith] ★시리즈 결손 %d개월 — 종점 %s, 기대 %s (상류 백테 최신화 필요)\n",
              as.character(Sys.Date()), .lag_m, SERIES_MAX, EXPECT_YM))

alert <- FALSE; msg_lines <- c()
if (nrow(new_rows)==0L) {
  cat(sprintf("[%s] 신규 실현월 없음 — deploy 후 첫 리밸 대기(현 6월홀딩 보유중). 설정 정상.\n", as.character(Sys.Date())))
} else {
  for (i in seq_len(nrow(new_rows))) {
    rr <- new_rows[i]
    pnav <- rbind(pnav, data.table(date=as.character(rr$anchor_date), event="REALIZED",
      realized_ym=rr$realized_ym, paper_ret_net=rr$ret_L5_faith, paper_nav=NA_real_, regime=rr$regime,
      beta_faith=rr$beta_faith, beta_R05=rr$beta_R05, m4=rr$m4,
      note=sprintf("실현 %s", rr$realized_ym)), fill=TRUE)
    msg_lines <- c(msg_lines, sprintf("%s 실현 %+.2f%% (β_faith %.1f)", rr$realized_ym, rr$ret_L5_faith*100, rr$beta_faith))
  }
  # NAV 재계산
  rv <- pnav[event=="REALIZED", paper_ret_net]; pnav[event=="REALIZED", paper_nav := cumprod(1+rv)]
  # trailing 21m holdout 대조
  real <- pnav[event=="REALIZED", paper_ret_net]
  if (length(real) >= 6L) {
    jd <- judge_holdout(iv, tail(real, iv$holdout_months), window_label="live_trailing")
    msg_lines <- c(msg_lines, sprintf("trailing SR %.2f vs 봉인 [%.2f,%.2f] → %s", jd$sr_realized, iv$q05, iv$q95, jd$verdict))
    if (isTRUE(grepl("FAIL|BELOW|FALSIFIED", jd$verdict))) alert <- TRUE
  }
  fwrite(pnav, navf)
  cat(sprintf("[%s] %d 신규월 기록.\n%s\n", as.character(Sys.Date()), nrow(new_rows), paste(msg_lines, collapse="\n")))
}

## Telegram (월간 상태 / 침범 alert)
tryCatch({
  source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
  hd <- if (alert) "⚠️ FaithTrend 페이퍼 트래킹 — 봉인구간 하단 침범 (도훈 확인)" else "FaithTrend book 페이퍼 트래킹 월간 리포트"
  body <- if (length(msg_lines)) paste(msg_lines, collapse=" · ") else "신규 실현월 없음. deploy 후 첫 리밸 대기, 설정 정상."
  if (nchar(body) > 95) body <- substr(body,1,95)
  tg_agent_brief(agent="Monitoring", title=hd,
    sections=list(
      list(type="summary", emoji=if(alert)"⚠️" else "📈", body=body),
      list(type="kv", emoji="📊", heading="트래킹 상태",
        kv=list("책"="FaithTrend PG2 (slot 2-2)",
                "봉인 예측구간"=sprintf("샤프 [%.2f, %.2f]", iv$q05, iv$q95),
                "기록 실현월"=as.character(nrow(pnav[event=="REALIZED"])),
                "판정"=if(alert)"하단 침범 — 도훈 확인" else "구간 내 정상"))),
    footer="📚 퇴출은 도훈 수동 · 06_Registry/live_track")
}, error=function(e) cat("[TG skip]", conditionMessage(e), "\n"))
cat("=== monitor done ===\n")
