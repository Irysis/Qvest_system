##=============================================================================
## ff5_brief_send.R — 모닝브리핑 스타일 국면 블록: FF5 + 스마트베타 통합 (v3)
## 흐름: FF5 재빌드(~10초) + SB 증분 갱신(신규월만) → 국면 판독 → tg 1건 발송
## 라벨: diagnostic_monitoring — 시장 리뷰 전용(전략/자본 인용 금지)
## v4 (2026-11-24 도훈 "스타일 국면 브리핑 국면판독 부분 개선"): FF5 절 · 국면 판독 · 부활 워치 = 한국 FF 요인 정본
##   (.cache/kr_factor_returns_* · 밤 갱신 [5c]) + 등록부 유의 문턱 — 구 트래커 FF5 는 CMA 부호 · 가격 이음매 결함으로 폴백 전용.
##   새 빌드 단계 kc = reports/kr_ff_regime_chart.R(정본 요인 12개월 t 차트). 검토 = 04_Research/01_reports/style_regime_brief_review_20261124/
## v3 (2026-09-24 도훈 "스타일 국면 브리핑 26년 8월 기준으로 고정된 부분 수정해줘"):
##   구판은 제목·12개월 평균·국면 판독·부활 워치가 월간 파일 마지막 완결월(L$ym)에 묶여 한 달 내내 같은 값을 냈다.
##   → 12개월 창 = 완결 11개월 + 진행월 MTD · 제목 = MTD as_of 기준(폴백 시 완결월 + 사유) ·
##     'FF5 최근월' → 'FF5 최근 완결월 (YYYY-MM)'. 조립 = style_brief_lib.R::sw_compose_brief()
##     (검사 08_Tests/ops/test_style_brief_mtd_window.R 가 이 함수 그 자체를 합성 입력으로 돌린다).
##   ★월간 파일은 완결월만(트래커 규약 불변) — 진행월은 표시층(브리핑·차트)에서만 합친다.
## 환경변수(기본값 = 구 동작 · 크론 무설정):
##   FF5_BRIEF_DRYRUN=1        발송 0 — 제목·절·차트 목록을 표준출력(+ FF5_BRIEF_DRYRUN_OUT 파일)으로만.
##                             FF5_BRIEF_DRYRUN_RENDER=0 이 아니면 tg_agent_brief(dry_run=TRUE) 로 렌더 규율만 검증(발송 없음).
##   FF5_BRIEF_SKIP_BUILD      all(또는 1) | 쉼표 목록 ff,sb,bf,ib,kc — 해당 재빌드 생략(기존 산출 소비)
##   FF5_BRIEF_DATA_DIR        산출물(outputs/… · v4 정본 요인 .cache/kr_factor_returns_*) 읽기 루트 — 기본 QM_ROOT (검사 샌드박스용)
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
## v4.1 (2026-11-24 도훈 "신규데이터 지연없이 업데이트 되게 배선된거지?") — 정본 요인 따라잡기.
##   평소: 밤 갱신 [5c] 가 퀀티 수집 직후 T−1 까지의 정본을 만든다(11-24 실측 04:49~04:51) → 07:18 브리핑이 그 판을 읽는다.
##   빈틈: RAWDATA 가 늦게 들어오거나(11-13 07:45 도착 사례) [5c] 가 실패하면('옛 파일 유지') 정본이 하루 늦은 채 남는다.
##   → 정본 meta last_input_date < RAWDATA 마지막 날이면 같은 빌더를 한 번 다시 돌린다(차트 · 지수 β 빌드보다 먼저).
##   조건 = mrs_daily_briefing.sh 의 국면 산출물 따라잡기와 같다: 리프레시 배리어 free(진행 중 갱신이 같은 산출을 스스로 만든다) ·
##   메모리 관문 통과(mem_gate.py krf_catchup · 정본 06_Registry/memory_policy.json). 못 돌리면 사유를 남기고 브리핑 제목에 '낡음'이 붙는다.
##   드라이런 · 샌드박스(FF5_BRIEF_DATA_DIR ≠ 루트) · FF5_BRIEF_SKIP_BUILD 에 kf 가 있으면 운영 .cache 를 쓰지 않는다(판정만).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
kf_catchup <- function() {
  res <- function(state, note, kf_last = as.Date(NA), rd_last = as.Date(NA)) list(state = state, note = note, kf_last = kf_last, rd_last = rd_last)
  mt <- tryCatch(jsonlite::fromJSON(file.path(ROOT, ".cache/kr_factor_returns_meta.json")), error = function(e) NULL)
  kf_last <- suppressWarnings(as.Date(as.character(if (is.null(mt)) NA else mt$last_input_date)))
  ## mmap = FALSE — 매핑을 남기면 같은 파일의 다음 쓰기(RAWDATA writer)가 Windows 1224 로 막힌다(검토 시험이 실측)
  rd_last <- tryCatch({ tb <- read_parquet(file.path(ROOT, ".cache/rawdata.parquet"), col_select = "Date", as_data_frame = FALSE, mmap = FALSE)
                        v <- as.vector(max(tb$Date)); rm(tb); invisible(gc()); v }, error = function(e) as.Date(NA))
  if (is.na(rd_last)) return(res("unknown", "RAWDATA 끝 날짜 판독 불가", kf_last, rd_last))
  if (!is.na(kf_last) && kf_last >= rd_last) return(res("fresh", sprintf("정본 %s = RAWDATA %s", kf_last, rd_last), kf_last, rd_last))
  why <- sprintf("정본 %s < RAWDATA %s", if (is.na(kf_last)) "없음" else format(kf_last), format(rd_last))
  if (DRYRUN || !identical(normalizePath(DATA, "/", FALSE), normalizePath(ROOT, "/", FALSE)) || skip_build("kf"))
    return(res("skipped", paste(why, "· 드라이런/샌드박스 — 운영 .cache 쓰지 않음"), kf_last, rd_last))
  rb <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/refresh_barrier.R"), local = TRUE); rb_status(ROOT) },
                 error = function(e) list(blocking = TRUE, state = "error"))
  if (isTRUE(rb$blocking)) return(res("held", paste(why, "· 리프레시 배리어", rb$state, "— 진행 중 갱신이 만든다"), kf_last, rd_last))
  py <- Sys.getenv("QVEST_PY", ""); if (!nzchar(py)) py <- "python"
  mg <- suppressWarnings(system2(py, c("-X", "utf8", shQuote(file.path(ROOT, "02_Infrastructure/ops/mem_gate.py")), "krf_catchup"),
                                 stdout = TRUE, stderr = TRUE))
  if (!identical(as.integer(attr(mg, "status") %||% 0L), 0L))
    return(res("mem_wait", paste(why, "· 메모리 관문", paste(tail(mg, 1), collapse = " ")), kf_last, rd_last))
  lg <- file.path(ROOT, ".cache/scheduler_logs/ff5_brief_krf_catchup.log")
  cat(sprintf("\n=== %s 정본 요인 따라잡기 — %s ===\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), why), file = lg, append = TRUE)
  rc <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                 c("--no-save", shQuote(file.path(ROOT, "02_Infrastructure/data/build_kr_factor_returns.R"))),
                                 stdout = lg, stderr = lg, env = c(sprintf("QM_ROOT=%s", ROOT), sprintf("CLAUDE_PROJECT_DIR=%s", ROOT)),
                                 timeout = 900))
  mt2 <- tryCatch(jsonlite::fromJSON(file.path(ROOT, ".cache/kr_factor_returns_meta.json")), error = function(e) NULL)
  k2 <- suppressWarnings(as.Date(as.character(if (is.null(mt2)) NA else mt2$last_input_date)))
  if (identical(as.integer(rc), 0L) && !is.na(k2) && k2 >= rd_last) return(res("ran", sprintf("%s → 따라잡음(정본 %s)", why, k2), k2, rd_last))
  res("failed", sprintf("%s · 따라잡기 실패(rc %s · 로그 ff5_brief_krf_catchup.log)", why, rc), k2, rd_last)
}
KC <- tryCatch(kf_catchup(), error = function(e) list(state = "error", note = conditionMessage(e)))
cat(sprintf("[ff5_brief] 정본 요인 따라잡기: %s — %s\n", KC$state, KC$note))

ok_ff <- .build("ff", "02_Infrastructure/reports/ff5_kr_tracker.R", "FF5")
ok_sb <- .build("sb", "02_Infrastructure/reports/smartbeta_kr_tracker.R", "SB")
ok_bf <- .build("bf", "02_Infrastructure/reports/krx_index_monthend_backfill.R", "index backfill")
ok_ib <- .build("ib", "02_Infrastructure/reports/index_factor_beta.R", "index-beta")
ok_kc <- .build("kc", "02_Infrastructure/reports/kr_ff_regime_chart.R", "regime-chart")   # v4 정본 요인 t 차트

## v4.1 점프 모형 λ · κ 재선택(Shu · Mulvey 2024 §3.2 — 6개월마다 · 6년 검증 창 샤프 최대) — 파일이 없거나 다음 선택일이 지났을 때만.
##   후보 격자 · 적합 주기는 기존 파일의 값을 그대로 쓴다(여기서 정하지 않는다). 하위 프로세스 · 상한 15분 · 실패하면 옛 값 유지
##   (브리핑 줄에 'λ 재선택 지남'). 드라이런 · 샌드박스 · FF5_BRIEF_SKIP_BUILD 의 jm 이면 생략.
jm_reselect <- function() {
  pf <- file.path(ROOT, "outputs/ff5_kr/style_jump_params.json")
  jp0 <- tryCatch(jsonlite::fromJSON(pf), error = function(e) NULL)
  due <- is.null(jp0) || any(vapply(jp0$factors, function(p) is.null(p$next_select) || as.Date(p$next_select) <= Sys.Date(), logical(1)))
  if (!due) return("유효")
  if (DRYRUN || !identical(normalizePath(DATA, "/", FALSE), normalizePath(ROOT, "/", FALSE)) || skip_build("jm")) return("재선택 필요 · 드라이런/샌드박스 생략")
  if (is.null(jp0)) return("파라미터 파일 없음 — style_jump_select.R 첫 실행은 수동(후보 격자 결정)")
  a <- c("--no-save", shQuote(file.path(ROOT, "02_Infrastructure/reports/style_jump_select.R")),
         "--lambdas", paste(jp0$lambdas, collapse = ","), "--kappas", paste(jp0$kappas, collapse = ","),
         "--refit_months", as.character(jp0$refit_months))
  lg <- file.path(ROOT, ".cache/scheduler_logs/ff5_brief_jump_select.log")
  cat(sprintf("\n=== %s 점프 모형 재선택 ===\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), file = lg, append = TRUE)
  rc <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), a, stdout = lg, stderr = lg,
                                 env = c(sprintf("QM_ROOT=%s", ROOT), sprintf("CLAUDE_PROJECT_DIR=%s", ROOT)), timeout = 900))
  sprintf("재선택 rc %s (로그 ff5_brief_jump_select.log)", rc)
}
JMS <- tryCatch(jm_reselect(), error = function(e) paste("재선택 오류:", conditionMessage(e)))
cat(sprintf("[ff5_brief] 점프 모형 λ: %s\n", JMS))
setwd(ROOT)
source("02_Infrastructure/reports/style_brief_lib.R")   # 트래커가 이미 불렀어도 재정의만(부작용 0)
## v4.1 점프 모형(순수 함수 · 파일 I/O 0) — 못 읽으면 국면 판독에 '생략' 한 줄(조립은 계속)
tryCatch(source("02_Infrastructure/reports/style_jump_model.R"), error = function(e) cat("[ff5_brief] 점프 모형 적재 실패:", conditionMessage(e), "\n"))

## v4 (2026-11-24 도훈 "국면판독 부분 개선"): 정본 요인(build_kr_factor_returns.R · 밤 갱신 [5c]) + 등록부 유의 문턱.
##   읽기 실패 · 부재는 kf 를 빈 채로 넘긴다 → 조립이 구 경로로 가며 국면 판독 첫 줄에 사유를 싣는다(침묵 폴백 금지).
##   문턱 = 02_Infrastructure/worktask/constraint_defaults.json::tier_graduation::grade_b_min_portfolio_alpha_t (하드코딩 금지).
sw_read_kf <- function(dpath, ref_as_of = NULL) {
  rd <- function(p, cols = NULL) tryCatch(as.data.table(read_parquet(p, col_select = if (is.null(cols)) NULL else tidyselect::all_of(cols))),
                                          error = function(e) NULL)
  daily <- rd(dpath(".cache/kr_factor_returns_daily.parquet"), c("Date", "MKT_TOTAL", "MKT", "SMB", "HML", "RMW", "CMA", "WML"))
  mon <- rd(dpath(".cache/kr_factor_returns_v2.parquet"), c("ym", "MKT", "SMB", "HML", "RMW", "CMA", "WML"))
  if (!is.null(mon)) mon[, ym := sprintf("%s-%s", substr(as.character(ym), 1, 4), substr(as.character(ym), 5, 6))]
  mt <- sw_read_json(dpath(".cache/kr_factor_returns_meta.json"))
  list(daily = daily, monthly = mon, ref_as_of = ref_as_of,
       meta = if (is.null(mt)) NULL else list(cfg_version = mt$cfg_version, md5 = mt$monthly$content_md5,
                                             built_at = mt$built_at, last_input_date = mt$last_input_date))
}
T_SIG <- tryCatch(as.numeric(jsonlite::fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_graduation[["grade_b_min_portfolio_alpha_t"]]),
                  error = function(e) NULL)

FF <- tryCatch(as.data.table(read_parquet(dp("outputs/ff5_kr/ff5_kr_monthly.parquet"))), error = function(e) NULL)
SB <- tryCatch(as.data.table(read_parquet(dp("outputs/smartbeta_kr/smartbeta_kr_monthly.parquet"))), error = function(e) NULL)
if (is.null(FF) || !nrow(FF)) { cat("[ff5_brief] FF 시리즈 없음 — skip\n") } else {
  mtd5 <- sw_read_json(dp("outputs/ff5_kr/ff5_kr_mtd.json"))
  sbm  <- sw_read_json(dp("outputs/smartbeta_kr/smartbeta_kr_mtd.json"))
  ib   <- sw_read_json(dp("outputs/ff5_kr/index_factor_beta.json"))
  kf   <- sw_read_kf(dp, ref_as_of = if (!is.null(sbm$as_of)) sbm$as_of else mtd5$as_of)
  kf$catchup <- KC                                        # v4.1 따라잡기 결과 — 제목(낡음 사유) · 꼬리말(아침 따라잡기)
  jp   <- sw_read_json(dp("outputs/ff5_kr/style_jump_params.json"))   # 점프 모형 λ(6개월마다 style_jump_select.R)
  out <- sw_compose_brief(FF, SB, mtd5 = mtd5, sbm = sbm, ib = ib, now = Sys.time(), kf = kf, t_sig = T_SIG, jp = jp)
  charts <- out$charts[file.exists(dp(out$charts))]
  cat(sprintf("[ff5_brief] window ff=%s(%s) sb=%s kf=%s | %s\n", out$w_ff$mode, out$w_ff$state$reason,
              if (is.null(out$w_sb)) "-" else out$w_sb$mode,
              if (isTRUE(out$kf_used)) sprintf("정본(%s)", format(out$kf$as_of)) else sprintf("구 경로(%s)", out$kf$reason), out$title))

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
