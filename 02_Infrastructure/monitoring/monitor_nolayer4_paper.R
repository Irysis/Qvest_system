## noLayer4 book — 월간 live paper-tracking 모니터 (holdout 대조 + drift + Telegram)
## 실행: Rscript monitor_nolayer4_paper.R  (월간 cron/trigger. 앞서 base+비중 최신화 후 호출)
## monitor_faithtrend_paper.R 미러 (도훈 지시 2026-07-03 Layer4 제거 → noLayer4 book 전환).
##   변경점: BOOK_ID/LT(noLayer4 live_track)/백테소스(슬롯2-3 03_period_returns, date→realized_ym·ret_net)/paper_nav 부재 시 seed.
## measurement-graduation §3 holdout 라이브 연장: trailing 실측 → judge_holdout → 하단 침범 alert(퇴출은 도훈 수동).
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT,"02_Infrastructure/contracts/holdout_falsification.R"))
BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2"
LT <- file.path(ROOT,"06_Registry/live_track",BOOK_ID); dir.create(LT,showWarnings=FALSE,recursive=TRUE)
iv <- fromJSON(file.path(LT,"holdout_interval.json"))
navf <- file.path(LT,"paper_nav.csv")
## paper_nav.csv 부재 시 seed (deploy start 행). faith paper_nav 미러 — beta_faith 없음(Layer4 제거).
if (!file.exists(navf)) {
  seed <- data.table(date="2026-07-01", event="DEPLOY_START", paper_ret_net=NA_real_, paper_nav=1,
                     regime="CAUTION", beta_R05=0.5, m4=1,
                     note="noLayer4 book paper-tracking 시작. 6월 홀딩(invested 0.2478=m4×β_R05, Layer4 제거) 보유 중.")
  fwrite(seed, navf)
}
pnav <- fread(navf)
if ("date" %in% names(pnav)) pnav[, date := as.character(date)]   # ★fread IDate→char 고정: append 시 date 형변환 NA 방지

## 최신 noLayer4 시리즈. ★live_track 확장본 우선(extend_nolayer4_series.R가 매월 단일-vintage 재계산 —
## 어제 캐시 tipping 방어). 부재 시에만 slot 2-3 materialized 03_period_returns.csv 폴백(05_Production 정적).
bt_live <- file.path(ROOT,"06_Registry/live_track",BOOK_ID,"live_book_series.csv")
bt_slot <- file.path(ROOT,"05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results/03_period_returns.csv")
bt_path <- if (file.exists(bt_live)) bt_live else bt_slot
cat(sprintf("[monitor] 시리즈 소스: %s\n", if(identical(bt_path,bt_live))"live_track 확장본(extend_nolayer4_series)" else "slot 2-3 materialized(폴백)"))
bt <- fread(bt_path)
if (!("realized_ym" %in% names(bt))) bt[, realized_ym := substr(as.character(date), 1, 7)]
setorder(bt, realized_ym)
tracked <- if ("realized_ym" %in% names(pnav)) pnav[event=="REALIZED" & !is.na(realized_ym), realized_ym] else character(0)
new_rows <- bt[!(realized_ym %in% tracked) & realized_ym > "2026-06"]   # deploy 이후 신규 실현월만

alert <- FALSE; msg_lines <- c()
if (nrow(new_rows)==0L) {
  cat(sprintf("[%s] 신규 실현월 없음 — deploy 후 첫 리밸 대기(현 6월홀딩 보유중). 설정 정상.\n", as.character(Sys.Date())))
} else {
  for (i in seq_len(nrow(new_rows))) {
    rr <- new_rows[i]
    pnav <- rbind(pnav, data.table(date=as.character(rr$date), event="REALIZED",
      realized_ym=rr$realized_ym, paper_ret_net=rr$ret_net, paper_nav=NA_real_, regime=NA_character_,
      beta_R05=NA_real_, m4=NA_real_,
      note=sprintf("실현 %s (cash %.2f)", rr$realized_ym, ifelse("cash_weight" %in% names(rr), rr$cash_weight, NA_real_))), fill=TRUE)
    msg_lines <- c(msg_lines, sprintf("%s 실현 %+.2f%%", rr$realized_ym, rr$ret_net*100))
  }
  # NAV 재계산
  rv <- pnav[event=="REALIZED", paper_ret_net]; pnav[event=="REALIZED", paper_nav := cumprod(1+rv)]
  # trailing 21m holdout 대조
  real <- pnav[event=="REALIZED", paper_ret_net]
  if (length(real) >= 6L) {
    jd <- judge_holdout(iv, tail(real, iv$holdout_months), window_label="live_trailing")
    msg_lines <- c(msg_lines, sprintf("trailing SR %.2f vs 봉인 [%.2f,%.2f] → %s", jd$realized_sr, iv$q05, iv$q95, jd$verdict))
    if (isTRUE(grepl("FAIL|BELOW|FALSIFIED", jd$verdict))) alert <- TRUE
  }
  fwrite(pnav, navf)
  cat(sprintf("[%s] %d 신규월 기록.\n%s\n", as.character(Sys.Date()), nrow(new_rows), paste(msg_lines, collapse="\n")))
}

## Telegram (월간 상태 / 침범 alert) — NOLAYER4_MONITOR_TG=0 으로 테스트 시 억제 (기본=발송)
if (Sys.getenv("NOLAYER4_MONITOR_TG","1") != "1") {
  cat("[monitor] TG suppressed (NOLAYER4_MONITOR_TG!=1)\n")
} else tryCatch({
  source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
  hd <- if (alert) "⚠️ noLayer4 페이퍼 트래킹 — 봉인구간 하단 침범 (도훈 확인)" else "noLayer4 book 페이퍼 트래킹 월간 리포트"
  body <- if (length(msg_lines)) paste(msg_lines, collapse=" · ") else "신규 실현월 없음. deploy 후 첫 리밸 대기, 설정 정상."
  if (nchar(body) > 95) body <- substr(body,1,95)
  tg_agent_brief(agent="Monitoring", title=hd,
    sections=list(
      list(type="summary", emoji=if(alert)"⚠️" else "📈", body=body),
      list(type="kv", emoji="📊", heading="트래킹 상태",
        kv=list("책"="noLayer4 PG2 (slot 2-3)",
                "봉인 예측구간"=sprintf("샤프 [%.2f, %.2f]", iv$q05, iv$q95),
                "기록 실현월"=as.character(nrow(pnav[event=="REALIZED"])),
                "판정"=if(alert)"하단 침범 — 도훈 확인" else "구간 내 정상"))),
    footer="📚 퇴출은 도훈 수동 · 06_Registry/live_track")
}, error=function(e) cat("[TG skip]", conditionMessage(e), "\n"))
cat("=== monitor done ===\n")
