#!/usr/bin/env Rscript
#==============================================================================
# test_dr_fail_signature.R — Daily Refresh [7] 실패 서명 게이트 (v10.4 2026-09-24)
#
# 왜: [7] 이 같은 원인을 매일 새 "★부분실패" 푸시로 보냈다(consensus 정체 6일 연속 같은 내용 · 2주 8회). 진짜 결함 채널이라
#   없애지 않고 소음만 뺀다 — 서명이 바뀔 때만 푸시, 반복은 무음 요약, 비면 해소 1회. 서명에 숫자(lag·rc·개수)가
#   들어가면 같은 원인이 매일 새 서명이 되어 게이트가 죽는다(= 이 검사의 돌연변이 M1).
#
# 판정 (운영 상태 파일 무접촉 — 임시 디렉터리):
#   G1 같은 항목·다른 숫자 → 같은 서명        G2 다른 항목 → 다른 서명            G3 첫 실패 = new · 푸시
#   G4 같은 서명 반복 = repeat · 무음 · N일째  G5 원인 변경 = changed · 푸시        G6 실패 0 + 이전 서명 = 해소 1회
#   G7 실패 0 + 이전 없음 = 종전 "완료" · 상태 불변   G8 커밋 왕복          G9 파손 상태 파일 → new(보수적)
#   W  daily_refresh.sh [7] 배선: 게이트 호출 · mute 전달 · 발송 ok 뒤에만 커밋 · tg_sent 증거 줄 · 구판 모듈 폴백
#   M1 돌연변이(숫자 제거 안 함) → G1 red      M2 돌연변이(반복 판정 제거) → G4 red
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.root <- function() {
  for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
    if (nzchar(c) && file.exists(file.path(c, "02_Infrastructure/hooks/qvest_hook_router.py"))) return(c)
  stop("root 미발견")
}
ROOT <- .root()
HELPER <- file.path(ROOT, "02_Infrastructure/data/dr_fail_signature.R")
DR <- file.path(ROOT, "02_Infrastructure/data/daily_refresh.sh")
PASS <- 0L; FAIL <- 0L
chk <- function(label, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  ok   ", label, "\n", sep = "") }
  else { FAIL <<- FAIL + 1L; cat("  FAIL ", label, if (nzchar(detail)) paste0(" \u2014 ", detail) else "", "\n", sep = "") }
}
finish <- function() {
  cat(sprintf("  \u2500\u2500 %d/%d pass\n", PASS, PASS + FAIL))
  cat(sprintf('{"test":"dr_fail_signature","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L)
}
if (!file.exists(HELPER)) { chk("helper 존재", FALSE, HELPER); finish() }

run_suite <- function(helper_src, tag = "") {
  e <- new.env()
  eval(parse(text = helper_src, encoding = "UTF-8"), envir = e)
  r <- list()
  s1 <- paste(e$dr_sig_items("ingest_freshness benchmark_currency(gate_rc=1,updater_rc=0) r12(rc=1) factor_emission_regress:202608:3(INV13_A,INV13_B)",
                             "benchmark consensus"), collapse = " ")
  s2 <- paste(e$dr_sig_items("ingest_freshness benchmark_currency(gate_rc=2,updater_rc=3) r12(rc=137) factor_emission_regress:202609:5(INV13_A,INV13_B)",
                             "consensus benchmark"), collapse = " ")
  r$G1 <- identical(s1, s2)
  r$G2 <- !identical(s1, paste(e$dr_sig_items("ingest_freshness", "consensus investor_act"), collapse = " "))
  d_new <- e$dr_sig_decide("ingest_freshness", "consensus", list(signature = ""), as.Date("2026-09-24"))
  r$G3 <- identical(d_new$kind, "new") && !isTRUE(d_new$mute) && grepl("\u2605\ubd80\ubd84\uc2e4\ud328", d_new$hdr) &&
          grepl("\uc2e0\uaddc", d_new$hdr) && identical(d_new$state$since, "2026-09-24")
  prev <- list(signature = d_new$sig, since = "2026-09-22")
  d_rep <- e$dr_sig_decide("ingest_freshness", "consensus", prev, as.Date("2026-09-24"))
  r$G4 <- identical(d_rep$kind, "repeat") && isTRUE(d_rep$mute) && grepl("3\uc77c\uc9f8", d_rep$hdr) &&
          identical(d_rep$state$since, "2026-09-22")
  d_chg <- e$dr_sig_decide("ingest_freshness", "benchmark", prev, as.Date("2026-09-24"))
  r$G5 <- identical(d_chg$kind, "changed") && !isTRUE(d_chg$mute)
  d_res <- e$dr_sig_decide("\uc5c6\uc74c", "", prev, as.Date("2026-09-25"))
  r$G6 <- identical(d_res$kind, "resolved") && !isTRUE(d_res$mute) && grepl("\ud574\uc18c", d_res$hdr) &&
          identical(d_res$state$signature, "")
  d_ok <- e$dr_sig_decide("\uc5c6\uc74c", "", list(signature = ""), as.Date("2026-09-25"))
  r$G7 <- identical(d_ok$kind, "ok") && identical(d_ok$hdr, "[Daily Refresh v2 \uc644\ub8cc]") && is.null(d_ok$state)
  td <- tempfile("drsig"); dir.create(td); p <- file.path(td, "dr_fail_signature.json")
  e$dr_sig_commit(p, d_new$state); back <- e$dr_sig_read(p)
  r$G8 <- identical(as.character(back$signature), d_new$sig) && identical(as.character(back$since), "2026-09-24")
  writeLines("{ not json", p); bad <- e$dr_sig_read(p)
  r$G9 <- identical(e$dr_sig_decide("ingest_freshness", "consensus", bad, as.Date("2026-09-24"))$kind, "new")
  unlink(td, recursive = TRUE)
  r
}

src <- paste(readLines(HELPER, encoding = "UTF-8", warn = FALSE), collapse = "\n")
cat("== DR [7] 실패 서명 게이트 ==\n")
r <- run_suite(src)
lab <- c(G1 = "G1 같은 항목·다른 숫자(lag/rc/월/개수) → 같은 서명", G2 = "G2 다른 항목 → 다른 서명",
         G3 = "G3 첫 실패 = new · 푸시 · ★부분실패(신규)", G4 = "G4 같은 서명 반복 = repeat · 무음 · 3일째",
         G5 = "G5 원인 변경 = changed · 푸시", G6 = "G6 실패 0 + 이전 서명 = 해소 1회(상태 비움)",
         G7 = "G7 실패 0 + 이전 없음 = 종전 '완료' · 상태 불변", G8 = "G8 커밋 → 읽기 왕복",
         G9 = "G9 파손 상태 파일 → new(무음으로 접지 않음)")
for (k in names(lab)) chk(lab[[k]], r[[k]])

# 돌연변이
m1 <- sub('f <- gsub(":[0-9]+", "", f)', 'f <- f', src, fixed = TRUE)
m1 <- sub('f <- gsub("\\\\((?:[A-Za-z_]*rc=-?[0-9]+,?)+\\\\)", "", f, perl = TRUE)', 'f <- f', m1, fixed = TRUE)
chk("M1 전제: 숫자 제거 두 줄이 돌연변이로 제거됨", !identical(m1, src) && !grepl(":[0-9]+", m1, fixed = TRUE))
chk("M1 돌연변이(서명에 숫자 유지) → G1 red", !isTRUE(run_suite(m1)$G1))
m2 <- sub("if (identical(sig, psig) && length(since) == 1L && !is.na(since)) {", "if (FALSE) {", src, fixed = TRUE)
chk("M2 전제: 반복 판정 분기 제거됨", !identical(m2, src))
chk("M2 돌연변이(반복 판정 제거) → G4 red", !isTRUE(run_suite(m2)$G4))

# 배선 — daily_refresh.sh [7] 블록(게이트를 부르는 run_r 블록 하나)
cat("\n== daily_refresh.sh [7] 배선 ==\n")
L <- readLines(DR, encoding = "UTF-8", warn = FALSE)
i7 <- grep("dr_sig_decide(", L, fixed = TRUE)
chk("W1 [7] 블록이 서명 게이트를 부른다(1곳)", length(i7) == 1L, as.character(length(i7)))
if (length(i7) == 1L) {
  a <- max(grep("^run_r '", L[seq_len(i7)])); b <- i7 + min(grep("^'", L[(i7 + 1L):length(L)]))
  blk <- L[a:b]
  i_ok <- grep(".ok <- isTRUE(.r$ok)", blk, fixed = TRUE); i_cm <- grep("dr_sig_commit(", blk, fixed = TRUE)
  chk("W2 발송 반환값을 읽는다(.ok <- isTRUE(.r$ok))", length(i_ok) == 1L)
  chk("W3 상태 커밋은 발송 ok 뒤에만(if (.ok ...) 안)", length(i_cm) == 1L && length(i_ok) == 1L && i_cm > i_ok &&
        any(grepl("if (.ok && !is.null(.dec))", blk[i_ok:i_cm], fixed = TRUE)))
  chk("W4 mute 전달 + 구판 모듈(mute 인자 없음) 폴백", any(grepl('"mute" %in% names(formals(tg_send))', blk, fixed = TRUE)) &&
        any(grepl("mute = isTRUE(.dec$mute)", blk, fixed = TRUE)))
  chk("W5 task_health 증거 줄 [7] tg_sent=%s reported=%s (발송·가드 두 경로)",
      sum(grepl("[7] tg_sent=", blk, fixed = TRUE)) == 2L && any(grepl("reported=%s", blk, fixed = TRUE)))
  chk("W6 게이트 실패 시 종전 헤더 폴백(통보 자체는 막지 않음)", any(grepl("error = function(e) {", blk, fixed = TRUE)) &&
        any(grepl("} else if (identical(.fails,", blk, fixed = TRUE)))
  chk("W7 블록 안 작은따옴표 0(bash '...' 인용 안전)", !any(grepl("'", blk[-c(1L, length(blk))], fixed = TRUE)))
  pe <- tryCatch({ parse(text = blk[-c(1L, length(blk))], encoding = "UTF-8"); "" }, error = function(e) conditionMessage(e))
  chk("W8 [7] R 블록 구문", !nzchar(pe), pe)
}
finish()
