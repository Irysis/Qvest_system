# test_tau_d_date_nonbmp.R -- 정보 경계(τ_D) 날짜 검사가 BMP 밖 문자 뒤 날짜도 잡는가 (2026-11-10 전수점검)
#
# 지키는 것:
#   R 기본 정규식 엔진의 gregexpr + regmatches 는 BMP 밖 문자(수식 기호 U+1D465 등) 뒤에서 위치가 어긋나, 그 뒤에 오는
#   'YYYY-MM-DD' 를 놓친다(1~3자 선행 시 미검출 · 4자 이상은 다른 조각을 집는다). 처방 입력 검사(rx_round.R)와
#   보는 창 가림 · 누출 검사(round_core v1 util.R)가 같은 약점을 공유했다 — 가림이 놓친 것을 누출 검사도 놓친다.
#   수리 = 세 곳 모두 perl = TRUE.
#
# 축:
#   A  round_core 가림(rc_redact_after_tau) — BMP 밖 문자 0~6자 뒤의 τ_D 이후 날짜를 가린다
#   B  round_core 누출 검사(rc_after_tau_leaks) — 가리지 않은 원문에서 그 날짜를 보고한다
#   C  처방 입력 검사(.rx_assert_clean) — 그 날짜가 있으면 멈추고, 멈춤 사유에 그 날짜(연도만이 아니라 YYYY-MM-DD)를 적는다
#   D  [음성] τ_D 이전 날짜는 건드리지 않는다
#   E  [위반 주입] perl = TRUE 를 뺀 사본은 A · B · C 를 통과하지 못한다
#
# 방식: 소스에서 함수를 그대로 꺼내 실행(재구현 금지). 운영 파일 쓰기 없음(E 의 처방 입력 검사 돌연변이만 tempdir 루트).
#
# 2026-11-11 재조준(밤 배터리 회귀 — 11-10 감사 커밋 a0c0ef417 · 3bec690f1 · c0a4b6212):
#   util.R 의 가림 · 누출 검사가 표기 변형 도우미(.rc_tau_alt_hits · RC_TAU_ALT_RX 등)를 부르게 되어, 이름 목록으로만 꺼내던 적재가
#   'could not find function' 으로 죽었다 → util.R 은 최상위 정의 전부를 꺼낸다(최상위 문장은 정의뿐 · library 호출 제외).
#   .rx_assert_clean 은 따로 둔 정규식 대신 util.R::rc_input_issues 를 root 에서 적재해 쓴다 → C 의 돌연변이 대상은 이제 util.R 이다.
#   그 검사에는 τ_D 뒤 '연도' 검사(.rc_year_hits)가 함께 있어 perl 을 빼도 '2024' 로 멈춘다 — 그래서 C 는 '멈춘다'에 더해
#   '멈춤 사유에 그 날짜 YYYY-MM-DD 가 있다'를 잰다(BMP 밖 문자 뒤 날짜 검출이라는 같은 성질 · perl 없으면 날짜가 사유에서 빠진다).

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)
done <- function() {
  cat(sprintf('{"test":"tau_d_date_nonbmp","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
  if (sys.nframe() == 0L) quit(save = "no", status = if (fail > 0L) 1L else 0L)
}

UTIL <- file.path(root, "04_Research", "programs", "_lib", "round_core", "v1", "util.R")
RX   <- file.path(root, "02_Infrastructure", "programs", "rx_round.R")
if (!file.exists(UTIL) || !file.exists(RX)) { ng("대상 소스 부재"); done() } else {

  # 소스 텍스트에서 함수 정의만 꺼내 평가(파일 전체 source 는 다른 의존을 끌고 온다)
  grab_fns <- function(path, names, text = NULL) {
    txt <- if (is.null(text)) readLines(path, warn = FALSE, encoding = "UTF-8") else text
    ex <- parse(text = txt, keep.source = FALSE)
    e <- new.env(parent = globalenv())
    for (x in ex) if (is.call(x) && identical(x[[1]], as.name("<-")) && is.name(x[[2]]) &&
                      (is.null(names) || as.character(x[[2]]) %in% names)) eval(x, envir = e)
    e
  }
  TAU <- as.Date("2022-12-31")
  NB  <- intToUtf8(0x1D465L)                     # 수식 기호 x (BMP 밖)
  mk  <- function(k, d) paste0(strrep(NB, k), " ", d, " 뒤")
  POST <- "2024-12-30"; PRE <- "2021-05-31"

  load_util <- function(text = NULL) {
    e <- grab_fns(UTIL, NULL, text)              # 최상위 정의 전부(도우미 · 정규식 상수까지 — 이름 목록은 도우미가 늘면 낡는다)
    stopifnot(exists("rc_redact_after_tau", envir = e), exists("rc_after_tau_leaks", envir = e), exists("RC_REDACT", envir = e))
    e
  }
  load_rx <- function(text = NULL) {
    e <- grab_fns(RX, ".rx_assert_clean", text)
    stopifnot(exists(".rx_assert_clean", envir = e))
    e
  }
  # 처방 입력 검사는 rr(루트)의 util.R 과 behavior_card.json 을 읽는다 — 멈춤 사유 문자열(멈추지 않으면 NA)
  rx_why <- function(e, s, rr = root) tryCatch({ e$.rx_assert_clean(s, rr, "시험 입력"); NA_character_ }, error = function(x) conditionMessage(x))
  rx_stops <- function(e, s, rr = root) !is.na(rx_why(e, s, rr))
  rx_names <- function(e, s, d, rr = root) { w <- rx_why(e, s, rr); !is.na(w) && grepl(d, w, fixed = TRUE) }

  U <- load_util(); R <- load_rx()
  ok("소스에서 가림 · 누출 검사 · 처방 입력 검사 함수 추출")

  cat("== A 가림 ==\n")
  for (k in 0:6) {
    out <- U$rc_redact_after_tau(mk(k, POST), TAU)
    chk(!grepl(POST, out, fixed = TRUE) && grepl(U$RC_REDACT, out, fixed = TRUE), sprintf("A BMP 밖 %d자 뒤 날짜를 가린다", k))
  }
  cat("== B 누출 검사 ==\n")
  for (k in c(0, 1, 2, 3, 4, 6)) chk(POST %in% U$rc_after_tau_leaks(mk(k, POST), TAU), sprintf("B BMP 밖 %d자 뒤 날짜를 보고한다", k))
  chk(length(U$rc_after_tau_leaks(U$rc_redact_after_tau(mk(3, POST), TAU), TAU)) == 0L, "B 가린 뒤에는 누출 0")
  cat("== C 처방 입력 검사 ==\n")
  for (k in c(0, 1, 3, 5)) chk(rx_names(R, mk(k, POST), POST), sprintf("C BMP 밖 %d자 뒤 날짜면 멈추고 사유에 그 날짜를 적는다", k))
  cat("== D 음성 ==\n")
  chk(identical(U$rc_redact_after_tau(mk(2, PRE), TAU), mk(2, PRE)), "D1 τ_D 이전 날짜는 가리지 않는다")
  chk(length(U$rc_after_tau_leaks(mk(2, PRE), TAU)) == 0L, "D2 τ_D 이전 날짜는 누출로 세지 않는다")
  chk(!rx_stops(R, mk(2, PRE)), "D3 τ_D 이전 날짜만 있으면 처방 입력 검사를 통과한다")

  cat("== E 위반 주입(perl = TRUE 제거) ==\n")
  strip_perl <- function(path, needle) {
    txt <- readLines(path, warn = FALSE, encoding = "UTF-8")
    hit <- grepl(needle, txt, fixed = TRUE) & grepl(", perl = TRUE)", txt, fixed = TRUE)
    txt[hit] <- sub(", perl = TRUE)", ")", txt[hit], fixed = TRUE)
    list(text = txt, n = sum(hit))
  }
  mu <- strip_perl(UTIL, "[12][0-9]|3[01])\"")           # 일 단위 날짜 패턴 2곳
  chk(mu$n == 2L, sprintf("E0 util.R 돌연변이 대상 2곳(실제 %d)", mu$n))
  UM <- load_util(mu$text)
  miss_red  <- any(vapply(1:3, function(k) grepl(POST, UM$rc_redact_after_tau(mk(k, POST), TAU), fixed = TRUE), logical(1)))
  miss_leak <- any(vapply(1:3, function(k) !(POST %in% UM$rc_after_tau_leaks(mk(k, POST), TAU)), logical(1)))
  chk(miss_red,  "E1 perl 없으면 가림이 날짜를 놓친다 — A 가 이것을 잡는다")
  chk(miss_leak, "E2 perl 없으면 누출 검사도 놓친다 — B 가 이것을 잡는다")
  # 처방 입력 검사는 util.R::rc_input_issues 한 구현이다(c0a4b6212) — rx_round.R 에 따로 둔 날짜 정규식이 없어야 하고,
  #   돌연변이는 util.R 사본을 tempdir 루트에 두고 .rx_assert_clean 이 그 루트를 읽게 한다.
  rx_txt <- readLines(RX, warn = FALSE, encoding = "UTF-8")
  chk(!any(grepl("[12]\\d|3[01])\"", rx_txt, fixed = TRUE)) && any(grepl("rc_input_issues", rx_txt, fixed = TRUE)),
      "E3 rx_round.R 에 따로 둔 날짜 정규식 없음 · 검사는 util.R::rc_input_issues")
  mroot <- file.path(tempdir(), "tau_d_nonbmp_mut")
  dir.create(file.path(mroot, "04_Research", "programs", "_lib", "round_core", "v1"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(mroot, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(mu$text), file.path(mroot, "04_Research", "programs", "_lib", "round_core", "v1", "util.R"), useBytes = TRUE)
  file.copy(file.path(root, "06_Registry", "behavior_card.json"), file.path(mroot, "06_Registry", "behavior_card.json"), overwrite = TRUE)
  chk(any(vapply(1:3, function(k) !rx_names(R, mk(k, POST), POST, mroot), logical(1))) &&
        rx_names(R, mk(0, POST), POST, mroot),
      "E4 perl 없는 util.R 사본이면 처방 입력 검사의 사유에서 BMP 밖 문자 뒤 날짜가 빠진다 — C 가 이것을 잡는다(0자 = 대조 · 잡힘)")
  unlink(mroot, recursive = TRUE)

  cat("== F 등록부 설명문의 날짜 붙은 유지보수 주석(도구 상자 생성을 막던 것) ==\n")
  S <- grab_fns(RX, ".rx_strip_dated_notes")
  if (!exists(".rx_strip_dated_notes", envir = S)) ng("F0 .rx_strip_dated_notes 없음") else {
    strip <- S$.rx_strip_dated_notes
    r19 <- "mean(z(-R01), z(R07)) — composite oriented 'higher = less risk' (2026-11-09 fix: R01 is stored as loss size; old composite averaged opposite components)."
    l35 <- "mean(|r_t|) over sign-reversal days (252d); stored negated. 2026-11-09: text aligned to the code (the old text did not match it)."
    pl  <- "12-1 month momentum (skip the most recent month); winsorized cross-section."
    hasd <- function(s) grepl("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", s, perl = TRUE)
    chk(!hasd(strip(r19)) && grepl("less risk'", strip(r19), fixed = TRUE), "F1 괄호 주석 '(날짜 fix: …)' 제거 · 정의 본문 유지")
    chk(!hasd(strip(l35)) && grepl("stored negated.", strip(l35), fixed = TRUE), "F2 문장형 주석 '날짜: …' 제거 · 정의 본문 유지")
    chk(identical(strip(pl), pl), "F3 날짜 없는 정의는 그대로")
    chk(!rx_stops(R, strip(r19)) && !rx_stops(R, strip(l35)), "F4 정리된 정의는 처방 입력 검사를 통과")
    chk(rx_stops(R, paste(strip(r19), "측정 2025-03-31")), "F5 정리 뒤에도 다른 곳에 τ_D 뒤 날짜가 있으면 멈춘다(검사 약화 아님)")
  }
  done()
}
