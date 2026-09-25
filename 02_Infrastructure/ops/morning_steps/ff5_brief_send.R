##=============================================================================
## ff5_brief_send.R — 모닝브리핑 스타일 국면 블록: FF5 + 스마트베타 통합 (v3)
## 흐름: FF5 재빌드(~10초) + SB 증분 갱신(신규월만) → 국면 판독 → tg 1건 발송
## 라벨: diagnostic_monitoring — 시장 리뷰 전용(전략/자본 인용 금지)
## v3 (2026-09-24 도훈 "스타일 국면 브리핑 26년 8월 기준으로 고정된 부분 수정해줘"):
##   구판은 제목·12개월 평균·국면 판독·부활 워치가 월간 파일 마지막 완결월(L$ym)에 묶여 한 달 내내 같은 값을 냈다.
##   → 12개월 창 = 완결 11개월 + 진행월 MTD · 제목 = MTD as_of 기준(폴백 시 완결월 + 사유) ·
##     'FF5 최근월' → 'FF5 최근 완결월 (YYYY-MM)'. 조립 = style_brief_lib.R::sw_compose_brief()
##     (검사 08_Tests/ops/test_style_brief_mtd_window.R 가 이 함수 그 자체를 합성 입력으로 돌린다).
##   ★월간 파일은 완결월만(트래커 규약 불변) — 진행월은 표시층(브리핑·차트)에서만 합친다.
## 환경변수(기본값 = 구 동작 · 크론 무설정):
##   FF5_BRIEF_DRYRUN=1        발송 0 — 제목·절·차트 목록을 표준출력(+ FF5_BRIEF_DRYRUN_OUT 파일)으로만.
##                             FF5_BRIEF_DRYRUN_RENDER=0 이 아니면 tg_agent_brief(dry_run=TRUE) 로 렌더 규율만 검증(발송 없음).
##   FF5_BRIEF_SKIP_BUILD      all(또는 1) | 쉼표 목록 ff,sb,bf,ib — 해당 재빌드 생략(기존 산출 소비)
##   FF5_BRIEF_DATA_DIR        산출물(outputs/…) 읽기 루트 — 기본 QM_ROOT (검사 샌드박스용)
##   FF5_BRIEF_FORCE           수동 재발송(쿨다운 우회) — 크론은 기본 FALSE
##=============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
DRYRUN <- identical(Sys.getenv("FF5_BRIEF_DRYRUN", ""), "1")
if (DRYRUN) Sys.setenv(QVEST_TG_DRY_RUN = "1")   # 이중 차단 — 어떤 경로로도 tg_agent_brief 가 실발송하지 않는다
DATA <- Sys.getenv("FF5_BRIEF_DATA_DIR", ""); if (!nzchar(DATA)) DATA <- ROOT   # 빈 값 = 기본(운영 루트)
dp <- function(p) file.path(DATA, p)
.skip <- tolower(trimws(strsplit(Sys.getenv("FF5_BRIEF_SKIP_BUILD", ""), ",")[[1]]))
skip_build <- function(k) any(.skip %in% c("1", "all", k))
.build <- function(k, path, what) {
  if (skip_build(k)) { cat(sprintf("[ff5_brief] %s build SKIP (FF5_BRIEF_SKIP_BUILD)\n", what)); return(NA) }
  tryCatch({ source(path); TRUE },
           error = function(e) { cat(sprintf("[ff5_brief] %s build FAIL: %s\n", what, conditionMessage(e))); FALSE })
}
ok_ff <- .build("ff", "02_Infrastructure/reports/ff5_kr_tracker.R", "FF5")
ok_sb <- .build("sb", "02_Infrastructure/reports/smartbeta_kr_tracker.R", "SB")
ok_bf <- .build("bf", "02_Infrastructure/reports/krx_index_monthend_backfill.R", "index backfill")
ok_ib <- .build("ib", "02_Infrastructure/reports/index_factor_beta.R", "index-beta")
setwd(ROOT)
source("02_Infrastructure/reports/style_brief_lib.R")   # 트래커가 이미 불렀어도 재정의만(부작용 0)

FF <- tryCatch(as.data.table(read_parquet(dp("outputs/ff5_kr/ff5_kr_monthly.parquet"))), error = function(e) NULL)
SB <- tryCatch(as.data.table(read_parquet(dp("outputs/smartbeta_kr/smartbeta_kr_monthly.parquet"))), error = function(e) NULL)
if (is.null(FF) || !nrow(FF)) { cat("[ff5_brief] FF 시리즈 없음 — skip\n") } else {
  mtd5 <- sw_read_json(dp("outputs/ff5_kr/ff5_kr_mtd.json"))
  sbm  <- sw_read_json(dp("outputs/smartbeta_kr/smartbeta_kr_mtd.json"))
  ib   <- sw_read_json(dp("outputs/ff5_kr/index_factor_beta.json"))
  out <- sw_compose_brief(FF, SB, mtd5 = mtd5, sbm = sbm, ib = ib, now = Sys.time())
  charts <- out$charts[file.exists(dp(out$charts))]
  cat(sprintf("[ff5_brief] window ff=%s(%s) sb=%s | %s\n", out$w_ff$mode, out$w_ff$state$reason,
              if (is.null(out$w_sb)) "-" else out$w_sb$mode, out$title))

  if (DRYRUN) {
    lines <- c(sprintf("=== ff5_brief DRYRUN — 발송 없음 · %s KST · builds ff=%s sb=%s bf=%s ib=%s ===",
                       format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Asia/Seoul"), ok_ff, ok_sb, ok_bf, ok_ib),
               sw_dryrun_lines(out, charts_root = DATA))
    rendered <- NULL
    if (!identical(Sys.getenv("FF5_BRIEF_DRYRUN_RENDER", "1"), "0")) {
      ## 렌더 규율(bullet ≤80자·약어·skeleton) 검증만 — dry_run=TRUE 명시 + QVEST_TG_DRY_RUN=1(위) 이중 차단
      source("02_Infrastructure/telegram/telegram_notify.R")
      rr <- tryCatch(tg_agent_brief(agent = "Q-Lead", title = out$title, sections = out$sections,
                                    charts = charts, footer = out$footer, dry_run = TRUE),
                     error = function(e) list(ok = FALSE, dry_run = TRUE, error = conditionMessage(e)))
      if (!isTRUE(rr$dry_run)) stop("[ff5_brief] DRYRUN 인데 dry_run 반환이 아니다 — 중단")
      rendered <- c("", sprintf("=== RENDER (tg_agent_brief dry_run · 발송 없음) ok=%s%s ===", isTRUE(rr$ok),
                                if (is.null(rr$error)) "" else paste0(" · ", rr$error)),
                    if (is.null(rr$msg)) character(0) else rr$msg)
    }
    lines <- c(lines, rendered)
    cat(paste(lines, collapse = "\n"), "\n", sep = "")
    of <- Sys.getenv("FF5_BRIEF_DRYRUN_OUT", "")
    if (nzchar(of)) { writeLines(enc2utf8(lines), of, useBytes = TRUE); cat("[ff5_brief] DRYRUN 본문 →", of, "\n") }
    cat("[ff5_brief] DRYRUN ok (발송 없음) tg_loaded=", exists("tg_send_rich", mode = "function"),
        " ff_build=", ok_ff, " sb_build=", ok_sb, "\n", sep = "")
  } else {
    source("02_Infrastructure/telegram/telegram_notify.R")
    res <- tg_agent_brief(
      agent = "Q-Lead",
      title = out$title,
      sections = out$sections,
      charts = charts,
      footer = out$footer,
      force = nzchar(Sys.getenv("FF5_BRIEF_FORCE", ""))   # 수동 재발송용(쿨다운 우회) — 크론은 기본 FALSE
    )
    cat("[ff5_brief] sent ok=", isTRUE(res$ok), " ff_build=", ok_ff, " sb_build=", ok_sb, "\n", sep = "")
  }
}
