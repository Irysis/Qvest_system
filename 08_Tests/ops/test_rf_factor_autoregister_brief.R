#!/usr/bin/env Rscript
#==============================================================================
# test_rf_factor_autoregister_brief.R — 팩터 자동등록 레인의 **발신기 계약** 검사
#
# 왜 (실사고 2026-09-17): 등록은 성공했는데 브리핑이 `사용되지 않은 인자 (body = ...)` 로
#   죽었다. tg_agent_brief 에는 body 인자가 없고 sections 배열을 받는다. 이 레인의 유일한
#   성공 발화가 그대로 침묵했다 — 발화한 줄 아무도 몰랐다.
#
# 설계 원칙 (메모리 규약):
#   · **재도출**: 소스 문자열을 단정하지 않는다. 파일을 파싱해 실제 호출의 인자 이름을 꺼내
#     `formals(tg_agent_brief)` 와 대조한다 — 리팩터가 줄을 옮겨도 살아 있고, body= 말고
#     **어떤 미지 인자든** 잡는다(이 결함 계열 전체).
#   · **양방향**: 양성 대조(드라이런 실제 통과) + 돌연변이 통제(검사기가 진짜 발화하는가).
#   · 상한은 relaxed 없이도 통과하도록 본다 — relaxed 가 빠지는 날 조용히 깨지지 않게.
#
# 실행: cd <ROOT> && Rscript -e 'source("08_Tests/ops/test_rf_factor_autoregister_brief.R")'
#==============================================================================
suppressMessages({ library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "02_Infrastructure/ops/rf_factor_autoregister.R")

.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

# ── 로더: 파일을 source 할 수 없다(맨 끝에서 main() 이 돈다). AST 로 함수만 꺼낸다 ──
EXPRS <- parse(SRC)
.take_fn <- function(nm) {
  for (e in EXPRS) {
    if (is.call(e) && length(e) >= 3L &&
        as.character(e[[1]]) %in% c("<-", "=") &&
        identical(as.character(e[[2]]), nm)) {
      env <- new.env(parent = globalenv()); assign("%||%", `%||%`, envir = env)
      return(eval(e[[3]], envir = env))
    }
  }
  NULL
}

# ── 재도출: 파일 안의 모든 tg_agent_brief 호출에서 **명명 인자 이름**을 수집 ──
.brief_call_args <- function() {
  found <- list()
  walk <- function(x) {
    if (is.call(x)) {
      fn <- x[[1]]
      if ((is.name(fn) && identical(as.character(fn), "tg_agent_brief")))
        found[[length(found) + 1L]] <<- names(as.list(x))[-1]
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    } else if (is.pairlist(x) || is.list(x)) {
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    }
  }
  for (e in EXPRS) walk(e)
  found
}

cat("== rf_factor_autoregister 발신기 계약 ==\n")

# ── 발신기 정본 적재 ──────────────────────────────────────────────────────────
tg_ok <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  exists("tg_agent_brief", mode = "function")
}, error = function(e) { cat("  [SKIP-CAUSE] telegram_notify 적재 실패: ", conditionMessage(e), "\n"); FALSE })

# ── T1 [계약·재도출] 호출 인자 ⊆ formals(tg_agent_brief) ──────────────────────
#   ★이 한 검사가 body= 뿐 아니라 **모든 미지 인자**를 잡는다.
CALLS <- .brief_call_args()
if (!length(CALLS)) {
  ng("T1 호출을 못 찾았다", "tg_agent_brief 호출이 소스에 없다 — 레인이 보고를 잃었다")
} else if (!tg_ok) {
  ng("T1 발신기 미적재로 대조 불가")
} else {
  FML <- names(formals(tg_agent_brief))
  bad <- unique(unlist(lapply(CALLS, function(a) setdiff(a[nzchar(a %||% "")], FML))))
  if (!length(bad)) ok(sprintf("T1 호출 %d건의 명명 인자 전부가 formals 안에 있다", length(CALLS)))
  else ng("T1 미지 인자", paste(bad, collapse = ", "))
}

# ── T2 [돌연변이 통제] 검사기가 진짜 발화하는가 — body= 를 주입하면 T1 이 죽어야 한다 ──
if (tg_ok) {
  FML <- names(formals(tg_agent_brief))
  mutated <- c("agent", "title", "body")            # 구판(2026-09-17 실사고)의 인자 구성
  if (length(setdiff(mutated, FML))) ok("T2 [돌연변이] 구판 body= 구성은 계약 위반으로 잡힌다")
  else ng("T2 돌연변이를 통과시켰다", "body 가 formals 에 있다면 T1 은 아무것도 못 잡는다")
}

# ── T3 [양성 대조] 실제 sections 로 드라이런이 통과하는가 ────────────────────
BS <- .take_fn("rf_fa_brief_sections")
if (is.null(BS)) {
  ng("T3 rf_fa_brief_sections 부재", "브리핑이 다시 호출부에 인라인되면 양성 대조를 걸 자리가 없다")
} else {
  SEC <- BS(fid = "RP_combo_1403_8125_2002_06975_2007_08115", grade = "B", n_rows = 79442L,
            d_from = "2005-01-31", d_to = "2026-08-31",
            max_rho = 0.3736, worst = "L35_Reversal_Intensity", rho_max = 0.8)
  if (tg_ok) {
    res <- tryCatch(tg_agent_brief(agent = "AlphaSearch", dry_run = TRUE,
                                   title = "[1계층] 팩터 DB 자동등록 — 검사 픽스처 (등급 B)",
                                   sections = SEC),
                    error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    if (isTRUE(res$ok)) ok(sprintf("T3 [양성 대조] 드라이런 통과 · %s bytes", res$bytes %||% "?"))
    else ng("T3 드라이런 실패", res$error %||% "ok!=TRUE")
  }

  # ── T4 relaxed 없이도 상한 안 — relaxed 가 빠지는 날 조용히 깨지지 않게 ──
  .n <- function(z) nchar(as.character(z %||% ""))
  bad <- character(0)
  for (s in SEC) {
    ty <- s$type %||% "text"
    if (ty == "summary" && (.n(s$body) < 20L || .n(s$body) > 100L))
      bad <- c(bad, sprintf("summary %d자(20~100)", .n(s$body)))
    if (ty == "text" && (.n(s$body) < 30L || .n(s$body) > 220L))
      bad <- c(bad, sprintf("text %d자(30~220)", .n(s$body)))
    if (ty == "bullet") {
      lens <- vapply(s$items, .n, integer(1))
      if (length(s$items) < 2L) bad <- c(bad, sprintf("bullet 항목 %d개(>=2)", length(s$items)))
      if (any(lens > 80L)) bad <- c(bad, sprintf("bullet %d자(<=80)", max(lens)))
    }
  }
  if (!length(bad)) ok("T4 relaxed 없이도 전 섹션이 상한 안") else ng("T4 상한 초과", paste(bad, collapse = " · "))

  # ── T5 skeleton 가드 — 비어있지 않은 섹션 >=2 ────────────────────────────
  ne <- sum(vapply(SEC, function(s) {
    ty <- s$type %||% "text"
    (ty %in% c("summary", "text") && .n(s$body) >= 20L) || (ty == "bullet" && length(s$items) >= 2L)
  }, logical(1)))
  if (ne >= 2L) ok(sprintf("T5 비어있지 않은 섹션 %d개(>=2)", ne)) else ng("T5 skeleton", sprintf("%d개", ne))

  # ── T6 [경계] NA rho · 긴 id 에서도 상한 유지 (sprintf 길이0 붕괴 회귀 포함) ──
  S2 <- tryCatch(BS(fid = paste0(rep("X", 200), collapse = ""), grade = "A", n_rows = 1L,
                    d_from = "2005-01-31", d_to = "2026-08-31",
                    max_rho = NA_real_, worst = NULL, rho_max = 0.8),
                 error = function(e) e)
  if (inherits(S2, "error")) {
    ng("T6 경계 입력에서 죽는다", conditionMessage(S2))
  } else {
    # ★초판 결함(2026-09-21): bullet 섹션엔 body 가 **없는 것이 정상**인데 `s$body %||% ""` 로
    #   빈 문자열을 만들어 자기가 만든 빈칸을 세고 빨갛게 나왔다. 코드가 아니라 기대값이 틀렸다.
    #   타입이 실제로 싣는 자리만 센다.
    lens <- unlist(lapply(S2, function(s)
      if (identical(s$type %||% "text", "bullet")) vapply(s$items, function(z) nchar(as.character(z)), integer(1))
      else integer(0)))
    blanks <- sum(vapply(S2, function(s) {
      z <- if (identical(s$type %||% "text", "bullet")) as.character(s$items %||% character(0))
           else as.character(s$body %||% "")
      sum(!nzchar(z)) }, integer(1)))
    if (max(lens) <= 80L && blanks == 0L)
      ok("T6 [경계] NA rho · 200자 id 에서도 상한 유지 · 빈 문자열 0")
    else ng("T6 경계", sprintf("max bullet %d자 · 빈 항목 %d", max(lens), blanks))
  }

  # ── T7 발신기 v8 WARN 의 재도출 — '현재 리서치 상황' 이 **최상단**에 있는가 ──
  .h <- vapply(SEC, function(s) as.character(s$heading %||% ""), character(1))
  .i <- which(grepl("현재 리서치 상황", .h, fixed = TRUE))
  if (length(.i) && .i[1] == 1L) ok("T7 '현재 리서치 상황' 섹션이 최상단")
  else ng("T7 상황 섹션", if (!length(.i)) "없음 — 발신기가 v8 WARN 을 낸다" else sprintf("%d번째", .i[1]))
}

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L)
