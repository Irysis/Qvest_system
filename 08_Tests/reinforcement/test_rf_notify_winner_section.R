#!/usr/bin/env Rscript
#==============================================================================
# test_rf_notify_winner_section.R — rf_auto_notify.R 승자 셀 요약 배선 (2026-09-25 · QEPM 동결 잔여 수리 (4))
#
# 결함: rf_auto_notify() 의 승자 셀 산출물 탐색이 정의되지 않은 `info$entry$attempts` 를 읽었다(2026-08-30 도입 이래).
#   tryCatch 가 오류를 NULL 로 삼켜 .win_dir 가 늘 NULL → 도훈 지시(08-30)의 "승자 셀 성과 요약" 섹션이 한 번도 안 나갔다.
#   수리 = 원장 entry(S$entry). ★수리하면 그 아래 [팩터 분석] 후속(tg_pass_analysis)이 처음 살아나는데, 그 함수는 tg_send
#   직송이라 QVEST_TG_DRY_RUN 을 모른다 — 드라이런 배터리(test_rf_notify_fit_length D1)가 실발송할 뻔했다. 그래서 후속은
#   본문(.sent)이 실발송 성공일 때만(run_alpha_search.R [팩터분석TG] 관례).
#
# ★정본 무접촉 · 실발송 0: 샌드박스 루트에 텔레그램 **스텁**(tg_agent_brief·tg_pass_analysis 기록만)을 두고 rf_auto_notify 를 돌린다.
#   실제 telegram_notify.R 은 로드하지 않는다. 차트 함수도 스텁. 원장·산출물은 합성.
# 축:
#   W1 블록 렌더 → '승자 셀 성과 요약' 섹션 존재 · 등급 값 = 승자 산출물 authoritative_remeasure.json::essence_grade(재도출)
#   W2 승자 산출물 디렉터리 부재 → 섹션 없이 정상 렌더(음성 대조)
#   F1 본문 드라이런(dry_run=TRUE) → [팩터 분석] 후속 0 (분석 CSV 가 있어도)
#   F2 본문 실발송 성공(ok=TRUE · dry_run=FALSE · env 없음) → 후속 정확히 1회 · 승자 디렉터리(양성 대조 — 가드가 죽은 줄이 아니다)
#   F3 본문 실패(ok=FALSE) → 후속 0
#   F4 env QVEST_TG_DRY_RUN=1 → 후속 0 (본문 스텁이 dry_run 을 안 알려도)
#   S1 정적: rf_auto_notify 본문의 자유 변수에 `info` 없음(codetools::findGlobals)
#   M1 돌연변이(S$entry → info$entry 복원) → W1 red
#   M2 돌연변이(후속 드라이런 가드 제거) → F1 red
#
# 요약 규약: 마지막 줄 {"test":"rf_notify_winner_section","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.MARKER <- "02_Infrastructure/ops/rf_auto_notify.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE); m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return(""); dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- .c; break }
}
if (!nzchar(PROJ)) stop("[test_rf_notify_winner_section] PROJECT_ROOT 해석 실패 — 표지 부재")

PASS <- 0L; FAIL <- 0L
ok  <- function(n) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", n)) }
bad <- function(n, d) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s  (%s)\n", n, d)) }
fwd <- function(p) gsub("\\\\", "/", p)

BASE <- file.path(tempdir(), paste0("rfwin_", Sys.getpid()))
unlink(BASE, recursive = TRUE); dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(BASE, recursive = TRUE)   # top-level on.exit 금지(금칙②)
SB <- fwd(file.path(BASE, "root"))
for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "02_Infrastructure/telegram", "06_Registry",
            "stage_artifacts/replication/win1"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
.deps <- c("02_Infrastructure/ops/rf_perf_summary.R", "02_Infrastructure/ops/rf_block_insights.R",
           "02_Infrastructure/reinforcement/rf_spec_sig.R")
.dep_ok <- all(vapply(.deps, function(p) isTRUE(file.copy(file.path(PROJ, p), file.path(SB, p), overwrite = TRUE)), logical(1)))
writeLines(c(
  "## 테스트 스텁 — 실제 발송 경로 대체(샌드박스 전용 · 실발송 0)",
  "tg_agent_brief <- function(agent, title, sections = list(), ...) {",
  "  cap <- if (exists('.TG_CAP', envir = globalenv())) get('.TG_CAP', envir = globalenv()) else list()",
  "  cap[[length(cap) + 1L]] <- list(agent = agent, title = title, sections = sections)",
  "  assign('.TG_CAP', cap, envir = globalenv())",
  "  ret <- if (exists('.TG_RET', envir = globalenv())) get('.TG_RET', envir = globalenv()) else list(ok = TRUE, dry_run = TRUE)",
  "  invisible(c(ret, list(msg = '')))",
  "}",
  "tg_pass_analysis <- function(strategy_name, output_dir) {",
  "  pa <- if (exists('.TG_PA', envir = globalenv())) get('.TG_PA', envir = globalenv()) else list()",
  "  pa[[length(pa) + 1L]] <- list(name = strategy_name, dir = output_dir)",
  "  assign('.TG_PA', pa, envir = globalenv()); invisible(NULL)",
  "}"), file.path(SB, "02_Infrastructure/telegram/telegram_notify.R"))

# 승자 산출물(계약 산출물 모양만 — 수치는 재계산하지 않고 파일에서 읽는지 본다)
WIN <- fwd(file.path(SB, "stage_artifacts/replication/win1"))
AUTH <- list(essence_grade = "B", essence = list(portfolio_alpha_t_nw_lag3 = 2.567, oos_retention = 0.812))
writeLines(toJSON(AUTH, auto_unbox = TRUE, pretty = TRUE), file.path(WIN, "authoritative_remeasure.json"))
writeLines(c("metric_name,metric_value", "Sharpe,0.91", "CAGR,0.181", "MDD,-0.301", "Calmar,0.601",
             "Average_N_Holdings,21", "Annualized_Turnover,2.4"), file.path(WIN, "06_metrics.csv"))
writeLines(c("Model,Alpha_Annual_Pct,Alpha_tstat,Adj_R2", "FF3,3.1,2.2,0.61"), file.path(WIN, "analysis_multifactor.csv"))
EXP_GRADE <- as.character(fromJSON(file.path(WIN, "authoritative_remeasure.json"))$essence_grade)   # 재도출 기대값

mk_att <- function(n, code, grade, pt, cal, art) list(n = n, cell_code = code, grade = grade, artifacts = art,
  essence = list(cell_code = code, block = sub("_.*$", "", code), port_t = pt, net_sharpe = 0.9, cagr = 0.18,
                 mdd = 0.30, calmar = cal, oos_retention = 0.8, spec = "", source = "authoritative_remeasure.json"))
write_ledger <- function(win_art) {
  NOPE <- fwd(file.path(SB, "stage_artifacts/replication/absent"))
  ENT <- list(base_id = "RP_W_1", base_grade = "B", paper_key = "0000.00000", status = "active",
              attempts_used = 5L, max_attempts = 25L, block_order = list("B1", "B5", "B2", "B3", "B4"),
              attempts = list(mk_att(1L, "B1_1", "B", 2.10, 0.40, NOPE), mk_att(2L, "B1_2", "B", 2.20, 0.42, NOPE),
                              mk_att(3L, "B1_3", "C", 1.50, 0.30, NOPE), mk_att(4L, "B1_4", "B", 2.30, 0.45, NOPE),
                              mk_att(5L, "B1_5", "B", 2.57, 0.60, win_art)))
  writeLines(toJSON(list(schema_version = "test", layer = 1L, max_attempts = 25L, entries = list(ENT)),
                    auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(SB, "06_Registry/reinforce_ledger_l1.json"))
}
write_ledger(WIN)

load_notify <- function(path) {
  isTRUE(tryCatch({
    invisible(capture.output(suppressMessages(source(path, local = globalenv()))))
    assign("rf_notify_charts", function(...) character(0), envir = globalenv())   # 차트 파일 쓰기 차단
    TRUE }, error = function(e) { cat("  (로드 실패: ", conditionMessage(e), ")\n", sep = ""); FALSE }))
}
render <- function(ret = list(ok = TRUE, dry_run = TRUE), env_dry = FALSE) {
  for (v in c(".TG_CAP", ".TG_PA")) if (exists(v, envir = globalenv())) rm(list = v, envir = globalenv())
  assign(".TG_RET", ret, envir = globalenv())
  old <- Sys.getenv("QVEST_TG_DRY_RUN", unset = NA)
  if (env_dry) Sys.setenv(QVEST_TG_DRY_RUN = "1") else Sys.unsetenv("QVEST_TG_DRY_RUN")
  r <- tryCatch(capture.output(suppressWarnings(suppressMessages(rf_auto_notify("RP_W_1", 5L, kind = "block")))),
                error = function(e) structure(conditionMessage(e), class = "rerr"))
  if (is.na(old)) Sys.unsetenv("QVEST_TG_DRY_RUN") else Sys.setenv(QVEST_TG_DRY_RUN = old)
  cap <- if (exists(".TG_CAP", envir = globalenv())) get(".TG_CAP", envir = globalenv()) else list()
  pa  <- if (exists(".TG_PA", envir = globalenv())) get(".TG_PA", envir = globalenv()) else list()
  list(err = if (inherits(r, "rerr")) as.character(r) else NULL, cap = cap, pa = pa)
}
win_sec <- function(R) { m <- if (length(R$cap)) R$cap[[1]] else NULL
  if (is.null(m)) return(NULL)
  s <- Filter(function(x) startsWith(as.character(x$heading %||% ""), "승자 셀 성과 요약"), m$sections %||% list())
  if (length(s)) s[[1]] else NULL }
w1_ok <- function(R) { s <- win_sec(R); is.null(R$err) && !is.null(s) && identical(as.character(s$kv[["등급"]] %||% ""), EXP_GRADE) }
pa_n  <- function(R) length(R$pa)

.qm0 <- Sys.getenv("QM_ROOT", unset = NA_character_)
Sys.setenv(QM_ROOT = SB)
.loaded <- .dep_ok && load_notify(file.path(PROJ, .MARKER))
if (!.loaded) {
  bad("W0 렌더 준비", "의존 파일 복제 또는 rf_auto_notify.R 로드 실패")
} else if (!identical(fwd(get("ROOT", envir = globalenv())), SB)) {
  bad("W0 렌더 준비", sprintf("ROOT 가 샌드박스가 아니다(%s) — 운영 루트로 렌더하지 않는다", get("ROOT", envir = globalenv())))
} else {
  R <- render()
  if (w1_ok(R)) ok(sprintf("W1 블록 렌더 → '승자 셀 성과 요약' 섹션 · 등급 = 승자 산출물 essence_grade(%s)", EXP_GRADE))
  else bad("W1 승자 셀 섹션", sprintf("err=%s · 섹션=%s", R$err %||% "-", if (is.null(win_sec(R))) "없음" else "등급 불일치"))
  if (is.null(R$err) && pa_n(R) == 0L) ok("F1 본문 드라이런 → [팩터 분석] 후속 0(분석 CSV 존재)") else bad("F1 드라이런 후속", sprintf("후속 %d회 · err=%s", pa_n(R), R$err %||% "-"))
  R <- render(list(ok = TRUE, dry_run = FALSE))
  if (is.null(R$err) && pa_n(R) == 1L && identical(fwd(R$pa[[1]]$dir), WIN))
    ok("F2 본문 실발송 성공 → 후속 정확히 1회 · 승자 디렉터리(양성 대조)")
  else bad("F2 실발송 후속", sprintf("후속 %d회 · err=%s", pa_n(R), R$err %||% "-"))
  R <- render(list(ok = FALSE, dry_run = FALSE))
  if (is.null(R$err) && pa_n(R) == 0L) ok("F3 본문 실패 → 후속 0") else bad("F3 본문 실패 후속", sprintf("후속 %d회", pa_n(R)))
  R <- render(list(ok = TRUE, dry_run = FALSE), env_dry = TRUE)
  if (is.null(R$err) && pa_n(R) == 0L) ok("F4 env QVEST_TG_DRY_RUN=1 → 후속 0") else bad("F4 env 드라이런 후속", sprintf("후속 %d회", pa_n(R)))
  write_ledger(fwd(file.path(SB, "stage_artifacts/replication/absent_win")))
  R <- render()
  if (is.null(R$err) && length(R$cap) >= 1L && is.null(win_sec(R))) ok("W2 승자 산출물 부재 → 섹션 없이 정상 렌더(음성 대조)")
  else bad("W2 산출물 부재", sprintf("err=%s · 섹션=%s", R$err %||% "-", !is.null(win_sec(R))))
  write_ledger(WIN)
  # S1 — 자유 변수 정적 검사
  if (requireNamespace("codetools", quietly = TRUE)) {
    gv <- codetools::findGlobals(get("rf_auto_notify", envir = globalenv()), merge = FALSE)$variables
    if (!("info" %in% gv)) ok("S1 rf_auto_notify 자유 변수에 `info` 없음(codetools)") else bad("S1 자유 변수", "info 참조 잔존")
  } else bad("S1 자유 변수", "codetools 미설치 — 정적 검사 불가")

  # M — 돌연변이 사본(샌드박스)
  SRC <- readLines(file.path(PROJ, .MARKER), warn = FALSE, encoding = "UTF-8")
  i1 <- which(trimws(SRC) == "S$entry$attempts)")
  if (length(i1) != 1L) bad("M1 픽스처", "S$entry$attempts) 줄이 정확히 1개가 아니다") else {
    m1 <- SRC; m1[i1] <- sub("S$entry$attempts)", "info$entry$attempts)", m1[i1], fixed = TRUE)
    p1 <- file.path(SB, "m1_rf_auto_notify.R"); writeLines(m1, p1, useBytes = TRUE)
    if (load_notify(p1)) { R <- render()
      if (!w1_ok(R)) ok("M1 구판(info$entry) 복원 → W1 red(승자 섹션 소멸 — 구 결함 재현)") else bad("M1 구판 복원", "W1 이 여전히 통과 — 판별력 없음")
    } else bad("M1 로드", "돌연변이 사본 로드 실패")
  }
  i2 <- grep("isTRUE(.sent$ok) && !isTRUE(.sent$dry_run) &&", SRC, fixed = TRUE)
  i3 <- grep('!identical(Sys.getenv("QVEST_TG_DRY_RUN", ""), "1") &&', SRC, fixed = TRUE)
  if (length(i2) != 1L || length(i3) != 1L) bad("M2 픽스처", "후속 가드 줄이 정확히 1개씩이 아니다") else {
    m2 <- SRC; m2[i2] <- sub(" isTRUE(.sent$ok) && !isTRUE(.sent$dry_run) &&", "", m2[i2], fixed = TRUE); m2 <- m2[-i3]
    if (identical(m2[i2], SRC[i2])) bad("M2 픽스처", "가드 삭제 치환이 무변 — 돌연변이가 안 걸렸다") else {
      p2 <- file.path(SB, "m2_rf_auto_notify.R"); writeLines(m2, p2, useBytes = TRUE)
      if (load_notify(p2)) { R <- render()
        if (pa_n(R) >= 1L) ok("M2 후속 가드 제거 → F1 red(드라이런에서 tg_pass_analysis 호출 = 실발송 경로)") else bad("M2 가드 제거", "후속이 안 불림 — F1 판별력 없음")
      } else bad("M2 로드", "돌연변이 사본 로드 실패")
    }
  }
}
if (is.na(.qm0)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = .qm0)

.cleanup()
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_notify_winner_section","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
