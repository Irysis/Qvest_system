# test_cleaner_tg_headline.R -- 주간 클리너 · 무인 증류 보고의 요약 줄이 발송기 헤드라인 규격을 통과하는가 (2026-11-10 전수점검)
#
# 지키는 것:
#   발송기(telegram_notify.R)의 요약 줄은 1줄 헤드라인이고 길이가 [SUMMARY_MIN, SUMMARY_MAX] 밖이면 발송 전체가 멈춘다.
#   주간 클리너 스윕 보고는 120자, 무인 증류 완료 보고는 104자 문장을 요약 줄에 넣고 있어서 매주 발송이 실패했다
#   (fail-soft 라 로그에만 남았다 — 스윕 8회 · 증류 여러 회). 수리 = 짧은 헤드라인 + 세부는 불릿 + 발송기의 무인용 안전망
#   tg_summary_fit(규격 초과 시 잘라서 보낸다).
#
# 축:
#   A  발송기의 실제 규격 함수(tg_format_summary)로 두 보고의 요약 줄을 렌더 — 값이 극단이어도 통과 · 둘 다 안전망을 거친다
#   B  안전망(tg_summary_fit) — 규격을 넘는 문장은 SUMMARY_MAX 자로 잘리고 규격 함수를 통과 · 짧은 문장은 그대로
#   C  [양성 대조] 수리 전 문장은 규격 함수가 거부한다(이 시험이 그 결함을 볼 수 있다)
#
# 방식: 소스에서 함수 · 식을 그대로 꺼내 평가(재구현 금지). 발송 없음 · 파일 쓰기 없음.

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)
done <- function() {
  cat(sprintf('{"test":"cleaner_tg_headline","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
  if (sys.nframe() == 0L) quit(save = "no", status = if (fail > 0L) 1L else 0L)
}

TG    <- file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R")
SWEEP <- file.path(root, "02_Infrastructure", "ops", "weekly_cleaner_sweep.R")
DLIB  <- file.path(root, "02_Infrastructure", "ops", "cleaner_distill_lib.R")
if (!all(file.exists(c(TG, SWEEP, DLIB)))) { ng("대상 소스 부재"); done() } else {

  parse_src <- function(p) parse(text = readLines(p, warn = FALSE, encoding = "UTF-8"), keep.source = FALSE)
  # 최상위 대입 중 이름이 맞는 것만 평가
  grab_top <- function(ex, names, env) {
    for (x in ex) if (is.call(x) && identical(x[[1]], as.name("<-")) && is.name(x[[2]]) && as.character(x[[2]]) %in% names) eval(x, envir = env)
    env
  }
  # 식 나무를 내려가며 list(type = "summary", …, body = <식>) 의 body 식을 모은다
  summary_bodies <- function(ex) {
    out <- list()
    walk <- function(x) {
      if (missing(x) || is.null(x)) return(invisible(NULL))
      if (is.call(x)) {
        nm <- names(x)
        if (identical(x[[1]], as.name("list")) && !is.null(nm) && all(c("type", "body") %in% nm) && identical(x[["type"]], "summary"))
          out[[length(out) + 1L]] <<- x[["body"]]
        for (i in seq_along(x)) walk(x[[i]])
      } else if (is.pairlist(x) || is.expression(x)) {
        for (i in seq_along(x)) walk(x[[i]])
      }
      invisible(NULL)
    }
    walk(ex); out
  }
  uses_fit <- function(e) grepl("tg_summary_fit(", paste(deparse(e, width.cutoff = 500L), collapse = ""), fixed = TRUE)

  # 발송기의 규격 함수 · 안전망 · 설정(그대로)
  NEED <- c(".TG_CONFIG", "tg_html_escape", "tg_format_summary", "tg_summary_fit")
  E <- grab_top(parse_src(TG), NEED, new.env(parent = globalenv()))
  have_tg <- all(vapply(NEED, exists, logical(1), envir = E, inherits = FALSE))
  chk(have_tg, "발송기에서 규격 함수 · 안전망 · 설정 추출")
  if (!have_tg) { done() } else {
    MX <- as.integer(E$.TG_CONFIG$SUMMARY_MAX); MN <- as.integer(E$.TG_CONFIG$SUMMARY_MIN)
    renders <- function(s) !inherits(tryCatch(E$tg_format_summary(s), error = function(e) e), "error")
    `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

    cat("== A 두 보고의 요약 줄 ==\n")
    sw_ex <- parse_src(SWEEP)
    sb <- summary_bodies(sw_ex)
    chk(length(sb) == 1L, sprintf("A1 스윕 보고의 요약 섹션은 1개(실제 %d)", length(sb)))
    if (length(sb) == 1L) {
      for (n in c(0L, 7L, 999999L)) {
        ev <- new.env(parent = E); assign("sweep_deleted_n", n, envir = ev)
        s <- tryCatch(eval(sb[[1]], envir = ev), error = function(e) NA_character_)
        chk(is.character(s) && !is.na(s) && nchar(s) >= MN && nchar(s) <= MX && renders(s), sprintf("A2 스윕 요약(정크 %d건) — %s자 · 규격 통과", n, if (is.na(s)) "NA" else nchar(s)))
      }
      chk(uses_fit(sb[[1]]), "A3 스윕 요약은 안전망(tg_summary_fit)을 거친다")
    }
    D <- grab_top(parse_src(DLIB), "cd_notify", new.env(parent = E))
    chk(exists("cd_notify", envir = D, inherits = FALSE), "A4 증류 lib 에 발송 함수가 있다")
    if (exists("cd_notify", envir = D, inherits = FALSE)) {
      db <- summary_bodies(body(D$cd_notify))
      chk(length(db) == 1L, sprintf("A5 증류 보고의 요약 섹션은 1개(실제 %d)", length(db)))
      if (length(db) == 1L) {
        cases <- list(
          list(m = list(week_of = "2026-W45", digest = list(ok = TRUE)),  n_dr = 0L,   n_lc = 0L,   dl = list(), rj = list()),
          list(m = list(week_of = "2026-W45", digest = list(ok = FALSE)), n_dr = 999L, n_lc = 999L, dl = vector("list", 99999L), rj = vector("list", 9999L)),
          list(m = list(),                                                n_dr = 3L,   n_lc = 2L,   dl = vector("list", 5L), rj = list()))
        for (i in seq_along(cases)) {
          ev <- list2env(cases[[i]], envir = new.env(parent = D)); assign("%||%", `%||%`, envir = ev)
          s <- tryCatch(eval(db[[1]], envir = ev), error = function(e) NA_character_)
          chk(is.character(s) && !is.na(s) && nchar(s) >= MN && nchar(s) <= MX && renders(s), sprintf("A6 증류 요약 사례 %d — %s자 · 규격 통과", i, if (is.na(s)) "NA" else nchar(s)))
        }
        chk(uses_fit(db[[1]]), "A7 증류 요약은 안전망(tg_summary_fit)을 거친다")
      }
    }

    cat("== B 안전망 ==\n")
    long <- strrep("가", MX + 37L); short <- strrep("나", MN + 5L)
    cut <- E$tg_summary_fit(long)
    chk(nchar(cut) == MX && renders(cut), sprintf("B1 규격을 넘는 문장은 %d자로 잘리고 규격 통과", MX))
    chk(identical(E$tg_summary_fit(short), short), "B2 짧은 문장은 그대로")
    chk(identical(E$tg_summary_fit(strrep("다", MX)), strrep("다", MX)), "B3 경계(딱 SUMMARY_MAX 자)는 자르지 않는다")

    cat("== C 양성 대조 ==\n")
    old_sweep <- sprintf("정크 %d건 자동 정리 + 주간 리서치 인벤토리 수집 완료. 증류(엑기스 추출·DIST 초안·L-code 적립·잔재 삭제)는 곧바로 무인 레인이 이어받는다 — 완료 보고가 따로 온다(충돌 시 연기 후 일간 재시도).", 7L)
    old_dist  <- sprintf("%s 주차 증류를 무인 레인이 완주했다. digest %s · DIST 초안 %d건(proposed — 주입 안 됨) · L-code %d건 · 잔재 삭제 %d건(기계 거부 %d건).", "2026-W45", "작성", 2L, 1L, 3L, 0L)
    chk(nchar(old_sweep) > MX && !renders(old_sweep), sprintf("C1 수리 전 스윕 문장(%d자)은 규격 함수가 거부한다", nchar(old_sweep)))
    chk(nchar(old_dist)  > MX && !renders(old_dist),  sprintf("C2 수리 전 증류 문장(%d자)은 규격 함수가 거부한다", nchar(old_dist)))
    chk(renders(E$tg_summary_fit(old_sweep)) && renders(E$tg_summary_fit(old_dist)), "C3 같은 문장도 안전망을 거치면 발송된다(잘린 줄)")
    done()
  }
}
