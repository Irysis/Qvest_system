## noLayer4 book — 월간 live paper-tracking 모니터 (holdout 대조 + drift + Telegram)
## 실행: Rscript monitor_nolayer4_paper.R  (월간 cron/trigger. 앞서 base+비중 최신화 후 호출)
## monitor_faithtrend_paper.R 미러 (도훈 지시 2026-07-03 Layer4 제거 → noLayer4 book 전환).
##   변경점: BOOK_ID/LT(noLayer4 live_track)/백테소스(슬롯2-3 03_period_returns, date→realized_ym·ret_net)/paper_nav 부재 시 seed.
## measurement-graduation §3 holdout 라이브 연장: trailing 실측 → judge_holdout → 하단 침범 alert(퇴출은 도훈 수동).
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT,"02_Infrastructure/contracts/holdout_falsification.R"))
source(file.path(ROOT,"02_Infrastructure/portfolio/resolve_admitted_slot.R"))

## ── 추적 대상 = 실제 운용 중인 북 (하드코딩 제거, 도훈 mandate 2026-08-01) ──────
##   구판: BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2" 고정.
##   2026-07-19 D3 swap-in 으로 admitted 는 ..._M4gAE_... 로 바뀌었는데 이 트래커는
##   교체 전 북을 계속 추적했다 — **배포되지 않은 전략의 성과를 보고**하는 상태.
##   해석 실패 시엔 구 ID 로 폴백(추적이 죽지 않게) + 경고.
PRIOR_BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2"   # 이관 원본(이력 승계용) — 갱신 불요
.slot   <- tryCatch(resolve_admitted_slot(root=ROOT, fallback_id=PRIOR_BOOK_ID), error=function(e) NULL)
BOOK_ID <- if (!is.null(.slot)) .slot$id else PRIOR_BOOK_ID
if (is.null(.slot)) cat(sprintf("[monitor][WARN] admitted 슬롯 해석 실패 — 구 북 %s 로 폴백\n", BOOK_ID))
LT <- live_track_lane(BOOK_ID, root=ROOT, carry_from=PRIOR_BOOK_ID)
iv <- fromJSON(file.path(LT,"holdout_interval.json"))
navf <- file.path(LT,"paper_nav.csv")
## paper_nav.csv 부재 시 seed (deploy start 행). faith paper_nav 미러 — beta_faith 없음(Layer4 제거).
if (!file.exists(navf)) {
  ## seed 날짜는 하드코딩하지 않는다 (도훈 mandate 2026-08-01 "날짜 하드코딩은 다 없애라").
  ## 배포 시작 = book_state 갱신 시점(admission)에서 파생. 없으면 당월 1일.
  .bs <- tryCatch(fromJSON(file.path(ROOT,"qepm/mailbox/governor/book_state.json")),
                  error=function(e) NULL)
  .dep <- tryCatch(as.Date(substr(.bs[["updated_at"]],1,10)), error=function(e) NA)
  if (is.na(.dep)) .dep <- as.Date(format(Sys.Date(), "%Y-%m-01"))
  seed <- data.table(date=as.character(.dep), event="DEPLOY_START", paper_ret_net=NA_real_, paper_nav=1,
                     regime=NA_character_, beta_R05=NA_real_, m4=NA_real_,
                     note=sprintf("noLayer4 book paper-tracking 시작 (배포일 %s — book_state.updated_at 파생)", .dep))
  fwrite(seed, navf)
}
pnav <- fread(navf)
if ("date" %in% names(pnav)) pnav[, date := as.character(date)]   # ★fread IDate→char 고정: append 시 date 형변환 NA 방지

## 최신 noLayer4 시리즈. ★live_track 확장본 우선(extend_nolayer4_series.R가 매월 단일-vintage 재계산 —
## 어제 캐시 tipping 방어). 부재 시에만 slot 2-3 materialized 03_period_returns.csv 폴백(05_Production 정적).
bt_live <- file.path(ROOT,"06_Registry/live_track",BOOK_ID,"live_book_series.csv")
## 폴백도 admitted 슬롯에서 해석 (구판은 슬롯 2-3 고정 — 교체 후 구 북을 읽었다)
bt_slot <- (if (!is.null(.slot)) file.path(.slot$slot_dir,"04_backtest_results/03_period_returns.csv")
            else file.path(ROOT,"05_Production/2.Factor_Model",
                           paste0("2-3.",PRIOR_BOOK_ID),"04_backtest_results/03_period_returns.csv"))
bt_path <- if (file.exists(bt_live)) bt_live else bt_slot
cat(sprintf("[monitor] 시리즈 소스: %s\n", if(identical(bt_path,bt_live))"live_track 확장본(extend_nolayer4_series)" else sprintf("슬롯 %s materialized(폴백)", if(!is.null(.slot)) .slot$slot else "2-3")))
bt <- fread(bt_path)
if (!("realized_ym" %in% names(bt))) bt[, realized_ym := substr(as.character(date), 1, 7)]
setorder(bt, realized_ym)
tracked <- if ("realized_ym" %in% names(pnav)) pnav[event=="REALIZED" & !is.na(realized_ym), realized_ym] else character(0)
## ── deploy 컷오프: 하드코딩 대신 paper_nav 의 DEPLOY_START 에서 파생 ──────────
##   구판: realized_ym > "2026-06" 고정 (도훈 mandate 2026-08-01 제거 대상).
.dep_row <- pnav[event=="DEPLOY_START"]
DEPLOY_YM <- if (nrow(.dep_row)) substr(as.character(.dep_row$date[1]), 1, 7) else min(bt$realized_ym)
CUTOFF_YM <- format(as.Date(paste0(DEPLOY_YM, "-01")) - 1, "%Y-%m")   # 배포월 직전월까지는 기존 이력
new_rows <- bt[!(realized_ym %in% tracked) & realized_ym > CUTOFF_YM]

## ── ★결손 감지 (2026-08-01) — "신규 없음"을 무조건 정상이라 부르지 않는다 ─────
##   실사고: 2026-07·08 두 번 리밸했는데 시리즈가 2026-06 에 멈춰 있었고, 이 스크립트는
##   "deploy 후 첫 리밸 대기 … 설정 정상" 을 **조건 없이** 출력해 2개월 공백을 덮었다.
##   판정 기준 = 시리즈 종점이 '있어야 할 실현월'(직전 달)에 도달했는가.
##   realized_ym 컨벤션 = 장부 기록월(= 수익월 + 1). 오늘이 M월이면 M-1월 수익이 확정됐고
##   그 장부월은 M → 시리즈 max realized_ym 이 최소 M 이어야 한다.
EXPECT_YM  <- format(Sys.Date(), "%Y-%m")
SERIES_MAX <- max(bt$realized_ym, na.rm = TRUE)
.lag_m <- length(seq(as.Date(paste0(SERIES_MAX,"-01")), as.Date(paste0(EXPECT_YM,"-01")), by="month")) - 1L
STALE  <- .lag_m > 0L

alert <- FALSE; msg_lines <- c()
if (STALE) {
  alert <- TRUE
  msg_lines <- c(msg_lines,
    sprintf("시리즈 %d개월 결손 (종점 %s, 기대 %s)", .lag_m, SERIES_MAX, EXPECT_YM))
  cat(sprintf(paste0("[%s] ★시리즈 결손 %d개월 — 종점 %s, 기대 %s.\n",
                     "   상류(run_all.R → m4 → base 패널 → extend_nolayer4_series) 확인 필요.\n",
                     "   ※ '신규 실현월 없음'을 정상으로 보고하던 구판 결함 수리 (2026-08-01).\n"),
              as.character(Sys.Date()), .lag_m, SERIES_MAX, EXPECT_YM))
}
if (nrow(new_rows)==0L) {
  if (!STALE) cat(sprintf("[%s] 신규 실현월 없음 · 시리즈 종점 %s = 기대치 — 정상.\n",
                          as.character(Sys.Date()), SERIES_MAX))
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
  ## ★v10 (2026-09-03): §5.6b 계층 표제 [BOOK] · agent Monitoring(v10 퇴역) → Book.
  .bkid <- tryCatch({
    .br  <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/book/book_registry.json"), simplifyVector = FALSE)
    .act <- Filter(function(e) identical(e$status, "active"), .br$entries)
    .mm  <- Filter(function(e) identical(e$strategy_id, BOOK_ID), .act)
    if (length(.mm)) .mm[[1]]$book_id else if (length(.act)) .act[[1]]$book_id else "BOOK"
  }, error = function(e) "BOOK")
  hd <- if (STALE) sprintf("[BOOK] 경보 — %s 트래킹 시리즈 결손 (성과 반영 안 됨)", .bkid)
        else if (alert) sprintf("[BOOK] 경보 — %s 봉인구간 하단 침범 (도훈 확인)", .bkid)
        else sprintf("[BOOK] 트래킹 — %s 월간 리포트", .bkid)
  body <- if (length(msg_lines)) paste(msg_lines, collapse=" · ")
          else sprintf("신규 실현월 없음 · 시리즈 종점 %s = 기대치, 정상.", SERIES_MAX)
  if (nchar(body) > 95) body <- substr(body,1,95)
  tg_agent_brief(agent="Book", title=hd,
    sections=list(
      list(type="summary", emoji=if(alert)"⚠️" else "📈", body=body),
      list(type="kv", emoji="📊", heading="트래킹 상태",
        kv=list("책"=sprintf("noLayer4 PG2 (슬롯 %s)", if(!is.null(.slot)) .slot$slot else "?"),
                "봉인 예측구간"=sprintf("샤프 [%.2f, %.2f]", iv$q05, iv$q95),
                "기록 실현월"=as.character(nrow(pnav[event=="REALIZED"])),
                "판정"=if(alert)"하단 침범 — 도훈 확인" else "구간 내 정상"))),
    footer="📚 퇴출은 도훈 수동 · 06_Registry/live_track")
}, error=function(e) cat("[TG skip]", conditionMessage(e), "\n"))
cat("=== monitor done ===\n")
