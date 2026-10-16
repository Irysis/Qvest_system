## test_rf_verify_report_composition.R — 충실구현 보고 1통 조립(건식 · 발송 0) — 도훈 10-16 지시 3건
##   검증기(02_Infrastructure/ops/rf_replication_verify.R)의 함수 정의 · 상수만 격리 환경에 올리고(본문은 돌리지 않는다),
##   실제 충실구현 산출물 사본으로 .v1001_report 를 조립한다:
##   1 위기별 낙폭 = 차트(글줄 섹션 없음 · 산출물 폴더 crisis_drawdown.png · 첫 차트) 2 논문명 무절삭(표제 · 대상 줄)
##   3 '팩터 분석 — 알파 유의성(진단)' 섹션(파마-맥베스 · ★유의/비유의 · 등급 글자 없음) · 사후 분석 미산출이면 사유 1줄
## 실행: Rscript 08_Tests/ops/test_rf_verify_report_composition.R      (사후 분석이 없던 산출물이면 수 분 — RAWDATA 적재)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, QVEST_TG_DRY_RUN = "1")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
VERIFY_R <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
ex <- parse(VERIFY_R, keep.source = FALSE, encoding = "UTF-8")
SB <- new.env(parent = globalenv())
is_def <- function(e) is.call(e) && is.name(e[[1L]]) && as.character(e[[1L]]) %in% c("<-", "=") && is.name(e[[2L]]) &&
  (identical(e[[3L]][[1L]], as.name("function")) || grepl("^\\.V1001_", as.character(e[[2L]])))
for (e in ex) if (is_def(e)) eval(e, SB)
assign("ROOT", ROOT, envir = SB)
assign("jlog", function(event, ...) invisible(NULL), envir = SB)
invisible(capture.output(suppressMessages({
  sys.source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"), envir = SB)
  sys.source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"), envir = SB)
  sys.source(file.path(ROOT, "02_Infrastructure/contracts/behavior_card.R"), envir = SB)
  sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_perf_summary.R"), envir = SB)
})))
need <- c(".v1001_report", ".v1001_charts", ".v1001_grade_extra", ".v1001_factor_section", ".tg_target_label")
miss <- need[!vapply(need, exists, logical(1), envir = SB, inherits = FALSE)]
if (length(miss)) { ng("검증기 함수 적재", paste(miss, collapse = ",")); quit(status = 1L) } else ok("검증기 함수 5종 적재(본문 미실행)")

## 실제 산출물 사본(쓰기 = 사본에만)
src <- Filter(function(d) all(file.exists(file.path(d, c("03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv", "authoritative_remeasure.json", "equity_curve.png")))),
              sort(list.dirs(file.path(ROOT, "stage_artifacts/replication"), recursive = FALSE), decreasing = TRUE))[[1]]
td <- gsub("\\\\", "/", file.path(tempdir(), "rfv_comp")); unlink(td, recursive = TRUE); dir.create(td)
file.copy(src, td, recursive = TRUE); art <- file.path(td, basename(src))
cat("  산출물 사본:", basename(src), "\n")
card <- SB$bc_card_from_artifacts(art)
TITLE <- "Regime-Dependent Predictive Structure Between Equity Factors: Evidence from Granger Causality and Rolling Windows"
assign("TITLE", TITLE, envir = SB); assign("PKEY", "axv:2510.00001", envir = SB)
fa <- SB$.v1001_factor_section(art)
r <- SB$.v1001_report(target = SB$.tg_target_label(TITLE, "axv:2510.00001"), program = "구성",
                      status = list(stage = "충실구현 완료", position = "검사", previous = "등급 C(권위)"),
                      verdict_line = "등급 C(권위 · 15bps 순비용) — 재료: 구성 큐", card = card, artifact = art,
                      next_step = "큐 다음 논문으로 넘어간다", push = FALSE, charts = SB$.v1001_charts(art),
                      extra = c(SB$.v1001_grade_extra(art), fa))
m <- r$msg %||% ""
if (nchar(m) > 300L) ok(sprintf("1통 조립(%d자)", nchar(m))) else ng("1통 조립", substr(m, 1, 200))
if (!grepl("위기별 낙폭 (시장 대비)", m, fixed = TRUE) && file.exists(file.path(art, "crisis_drawdown.png")) &&
    file.info(file.path(art, "crisis_drawdown.png"))$size > 20000) ok("1 위기별 낙폭 = 차트(글줄 섹션 없음 · 산출물 폴더 crisis_drawdown.png)") else ng("1 위기 차트")
first <- sub("\n.*$", "", m)
if (grepl(TITLE, first, fixed = TRUE) && grepl(paste0("대상: ", TITLE), m, fixed = TRUE)) ok("2 논문명 무절삭 — 표제 · 대상 줄에 원제 그대로") else ng("2 논문명", first)
if (grepl("팩터 분석 — 알파 유의성(진단)", m, fixed = TRUE) && grepl("진단이다", m, fixed = TRUE) &&
    (grepl("파마-맥베스(", m, fixed = TRUE) || grepl("산출 안 됨", m, fixed = TRUE))) ok("3 팩터 분석 섹션 — 파마-맥베스(또는 미산출 사유) · 진단 표기") else ng("3 팩터 분석 섹션")
fm_line <- regmatches(m, regexpr("파마-맥베스\\([^\n]*", m))
if (!length(fm_line) || (grepl("★유의|비유의", fm_line) && !grepl("\\[[^]]*[ABCD]\\]", fm_line))) ok("3b 유의 표시 = ★유의/비유의(등급 글자 A~D 없음)") else ng("3b", fm_line)
b <- tryCatch(fromJSON(file.path(art, "analysis_basis.json")), error = function(e) list())
if (length(b$basis)) ok(sprintf("3c 분석 근거 기록 — basis %s · status %s", b$basis %||% "NA", b$status %||% "NA")) else ng("3c 분석 근거 json 없음")
## 4 유니버스 표기 = 그 산출물의 측정 축(10-17 — 전 종목+위생 산출물에 구 기본값 'K200∪KQ150' 이 찍혔다)
ax <- tryCatch(fromJSON(file.path(art, "authoritative_remeasure.json"))$measurement_axis$universe, error = function(e) NULL) %||% "K200_KQ150"
want <- if (identical(ax, "ALL_HYG")) "전 종목+위생" else "K200∪KQ150"
if (grepl(want, m, fixed = TRUE) && (!identical(ax, "ALL_HYG") || !grepl("K200∪KQ150", m, fixed = TRUE)))
  ok(sprintf("4 유니버스 표기 = 측정 축(%s → %s)", ax, want)) else ng("4 유니버스 표기", sprintf("축 %s · 기대 %s", ax, want))

unlink(td, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_verify_report_composition","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
