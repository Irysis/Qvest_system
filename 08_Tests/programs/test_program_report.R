## test_program_report.R — v10.01 보고 발송기 검사 (dry-run · 발송 0)
## 규칙(정본 .claude/skills/qvest-telegram/SKILL.md §v10.01): 판정 먼저 · 지표명 하나 · 숫자 안 자름 · 내부 코드/절대경로 없음 · 1단위 1통
suppressPackageStartupMessages({ library(data.table) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- file.path(.qv_self_dir(), "..", "..")
if (dir.exists(file.path(SELF, "02_Infrastructure/programs"))) ROOT <- SELF
setwd(ROOT); ROOT <- getwd(); Sys.setenv(QM_ROOT = ROOT, QVEST_TG_DRY_RUN = "1")
suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R"))
source("02_Infrastructure/contracts/behavior_card.R")
source("02_Infrastructure/programs/program_report.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

cat("=== A. 숫자 형식 ===\n")
chk("낙폭은 음수 기호(유니코드 마이너스) %", identical(prep_fmt_pct(-0.412), "\u221241.2%"))
chk("수익은 + 부호", identical(prep_fmt_pct(0.153), "+15.3%"))
chk("결측은 —", identical(prep_fmt_pct(NA_real_), "—") && identical(prep_fmt_ratio(NaN), "—"))
chk("판정어 사전", identical(prep_verdict_word("strong"), "강함") && identical(prep_verdict_word("??"), "판정 불가"))

cat("\n=== B. 실제 산출물 카드로 1통 조립(dry-run) ===\n")
# 완료된 산출물만 — 측정 중인 최신 디렉터리(수익 · 벤치 파일 미완성)를 고르면 운영 상태에 따라 검사가 흔들린다(10-13 실측: 진행 중 칸)
art <- Filter(function(d) all(file.exists(file.path(d, c("03_period_returns.csv", "05_benchmark_returns.csv", "authoritative_remeasure.json")))),
              sort(list.dirs("stage_artifacts/replication", recursive = FALSE), decreasing = TRUE))[[1]]
card <- bc_card_from_artifacts(art)
r <- prep_send(program = "방어 엔진", target = "검사용 전략",
               status = list(stage = "P2 방어 엔진 · 라운드 1", position = "측정 1/1", previous = "없음"),
               card = card, next_step = "크기 짝 대조를 붙여 선택 방어인지 가린다",
               artifact = file.path(ROOT, art), push = FALSE)
m <- r$msg %||% ""
first <- sub("\n.*$", "", m)
chk("dry-run 이 본문을 냈다", nchar(m) > 200L)
chk("길이 한계 안(3,900자 이하)", nchar(m) <= 3900L, sprintf("(%d)", nchar(m)))
chk("제목에 계층 표제와 판정어", grepl("\\[1계층·방어 엔진\\].*위기 방어 (강함|보통|약함|판정 불가)", first, perl = TRUE), first)
chk("현재 리서치 상황이 위기 표보다 앞", regexpr("현재 리서치 상황", m) < regexpr("위기별 낙폭", m))
chk("위기 표가 있다", grepl("위기별 낙폭", m, fixed = TRUE))
chk("숫자 중간 절삭 없음(숫자 바로 뒤 …)", !grepl("[0-9]\\.?…", m, perl = TRUE))
chk("절대경로 유출 없음", !grepl("[A-Za-z]:[\\\\/]", m, perl = TRUE))
chk("산출물 포인터는 상대경로 1줄", grepl("산출물: stage_artifacts/replication/", m, fixed = TRUE))
chk("내부 셀 코드 없음(B1_3 류)", !grepl("\\bB[0-9]_[0-9]+\\b", m, perl = TRUE))

cat("\n=== C. 카드 없이도 보낸다(실패 · 차단 보고) ===\n")
r2 <- prep_send(program = "실현 가능성 지도", target = "측정 계약 선행 조건",
                status = list(stage = "P0 · 대기", position = "측정 계약 1/8 완료", previous = "없음"),
                verdict_line = "선행 조건 7건이 남아 라운드를 시작하지 않았다", push = TRUE)
m2 <- r2$msg %||% ""
chk("카드 없는 보고도 조립된다", nchar(m2) > 50L)
chk("카드 없으면 제목에 판정어를 붙이지 않는다", !grepl("위기 방어", sub("\n.*$", "", m2), fixed = TRUE))

cat("\n=== D. 한 줄 길이 경계 — 1줄 헤드라인(20~100자) 밖이어도 1통이 죽지 않는다 ===\n")
long_v <- paste0("등급 C · 기저 PORT_t -0.50(문턱 0.00 미만) — 알파가 반대로 작동해 수익 엔진 재료로 쓰지 않는다. ",
                 "2계층 풀: 방어형 경로로 등재 검토 대상(구조 낙폭 라벨 · 역할 등급 재분류 대기) · 행동 카드는 남긴다")
r3 <- tryCatch(prep_send(program = "수익 엔진", target = "길이 경계 검사", status = list(stage = "충실구현 완료", position = "-", previous = "-"),
                         verdict_line = long_v, next_step = "끝", push = FALSE), error = function(e) list(msg = paste0("ERR ", conditionMessage(e))))
m3 <- r3$msg %||% ""
chk("100자 초과 판정 · 1자 다음 단계도 조립된다(stop 없음)", nchar(m3) > 50L && !startsWith(m3, "ERR"), substr(m3, 1, 120))
chk("긴 판정 문장은 자르지 않고 문단으로 싣는다", grepl("행동 카드는 남긴다", m3, fixed = TRUE))
chk("짧은 다음 단계는 프로그램 맥락을 붙여 1줄로", grepl("다음(수익 엔진", m3, fixed = TRUE))

cat("\n=== E. 위기 차트 모드(crisis = \"chart\" · 도훈 10-16 '위기별 낙폭은 시각화 자료로 대체') ===\n")
tdir <- gsub("\\\\", "/", file.path(tempdir(), "prep_chart_test")); unlink(tdir, recursive = TRUE); dir.create(tdir)
long_title <- "Regime-Dependent Predictive Structure Between Equity Factors: Evidence from Granger Causality and Rolling Windows in Korea"
r4 <- prep_send(program = "충실구현", target = long_title, status = list(stage = "충실구현 완료", position = "검사", previous = "없음"),
                card = card, next_step = "큐 다음 논문으로 넘어간다", artifact = tdir, push = FALSE, crisis = "chart")
m4 <- r4$msg %||% ""; png4 <- file.path(tdir, "crisis_drawdown.png")
chk("차트 모드 — 위기별 낙폭 글줄 섹션이 없다", !grepl("위기별 낙폭 (시장 대비)", m4, fixed = TRUE))
chk("차트 모드 — 위기 차트를 산출물 폴더에 그렸다(빈 그림 아님)", file.exists(png4) && file.info(png4)$size > 20000, if (file.exists(png4)) file.info(png4)$size else "없음")
chk("차트 모드 — 대조 1줄은 '위기 방어 귀속'으로 남는다", grepl("위기 방어 귀속", m4, fixed = TRUE) && grepl("짝 대조", m4, fixed = TRUE))
chk("긴 논문명이 제목 · 대상 줄에 잘리지 않고 들어간다", grepl(long_title, m4, fixed = TRUE) && !grepl("Granger Causa…", m4, fixed = TRUE))
.real_chart <- prep_crisis_chart
prep_crisis_chart <- function(...) stop("주입 실패")                                   # 차트가 실패하면 글줄로 돌아간다(1통 보존)
r5 <- prep_send(program = "충실구현", target = "검사용 전략", status = list(stage = "충실구현 완료", position = "검사", previous = "없음"),
                card = card, artifact = tdir, push = FALSE, crisis = "chart")
prep_crisis_chart <- .real_chart
chk("차트 실패 → 위기별 낙폭 글줄로 되돌아간다", grepl("위기별 낙폭 (시장 대비)", r5$msg %||% "", fixed = TRUE))
r6 <- prep_send(program = "방어 엔진", target = "검사용 전략", status = list(stage = "P2", position = "측정", previous = "없음"), card = card, artifact = tdir, push = FALSE)
chk("기본값(글줄) 호출자는 그대로 — 위기 표 섹션 유지", grepl("위기별 낙폭 (시장 대비)", r6$msg %||% "", fixed = TRUE))

cat(sprintf("\n== program_report: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"program_report","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
