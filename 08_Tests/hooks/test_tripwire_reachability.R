## test_tripwire_reachability.R — WIRE-1(R43-F1) 도달가능성 라벨 위반 주입 테스트
##
## 배경: insider SAFE tripwire 가 253개월 중 126개월(49.8%) 문턱 도달 불가로 침묵하는데
##   리포트가 '자격자 부재'와 '문턱 도달 불가'를 구별하지 못했다(R43-F1, WT-D20260802_012).
##   WIRE-1 은 그 둘을 가르는 라벨을 추가한다. 본 테스트는 **그 라벨이 실제로 뒤집히는지**를 잰다.
##
## ★설계 원칙: 정의를 사본으로 두지 않고 **production 파일에서 직접 파싱해 평가**한다.
##   사본 검사는 원본이 죽어도 통과한다(메모리: 검사가 옳은 것을 재지만 잘못된 지점에 서 있다).
##
## 실행: Rscript 08_Tests/hooks/test_tripwire_reachability.R

.root <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = Sys.getenv("QM_ROOT", unset = getwd()))
if (!file.exists(file.path(.root, "CLAUDE.md")))
  .root <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), "..", ".."), mustWork = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a

SRC <- file.path(.root, "02_Infrastructure", "reports", "filing_delay_watch.R")
stopifnot(file.exists(SRC))

pass <- 0L; fail <- 0L
ck <- function(label, cond) {
  if (isTRUE(cond)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s\n", label)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s\n", label)) }
}

## ── production 정의 직접 추출 (사본 금지) ──────────────────────────────────
src <- readLines(SRC, warn = FALSE)
i0 <- grep("^tripwire_reachability <- function", src)
if (length(i0) != 1L) stop("production 정의를 찾지 못함 — 함수가 사라졌거나 서명이 바뀜(그 자체가 결함)")
## 함수 본문 끝 = 첫 열의 닫는 중괄호
j <- i0 + 1L
while (j <= length(src) && !grepl("^\\}", src[j])) j <- j + 1L
eval(parse(text = paste(src[i0:j], collapse = "\n")), envir = environment())
ck("production 정의 파싱·평가 성공", is.function(tripwire_reachability))

THR <- 1.0

## ── 위반 주입 1: 최대값이 문턱 미만 → 반드시 UNREACHABLE ───────────────────
r_below <- tripwire_reachability(c(0.10, 0.55, 0.862, 0.99968), THR)
ck("주입① max<thr → unreachable TRUE", isTRUE(r_below$unreachable))
ck("주입① status = A_UNREACHABLE_MONTH", identical(r_below$status, "A_UNREACHABLE_MONTH"))
ck("주입① n_at_or_above = 0", identical(r_below$n_at_or_above, 0L))

## ── 위반 주입 2: 문턱 도달자 존재 → 반드시 REACHABLE ───────────────────────
r_above <- tripwire_reachability(c(0.10, 0.55, 1.0, 2.7), THR)
ck("주입② max>=thr → unreachable FALSE", identical(r_above$unreachable, FALSE))
ck("주입② status = REACHABLE", identical(r_above$status, "REACHABLE"))
ck("주입② n_at_or_above = 2", identical(r_above$n_at_or_above, 2L))

## ★라벨이 실제로 뒤집혔는가 — 항상 같은 값이면 검사 사망
ck("★라벨 반전 실증 (주입①≠주입②)", !identical(r_below$status, r_above$status))

## ── 경계: 정확히 문턱값 = 도달(>=) — tripwire 비교와 동일해야 함 ───────────
r_edge <- tripwire_reachability(c(0.5, 1.0), THR)
ck("경계 z==thr → REACHABLE (>= 비교, tripwire 정합)", identical(r_edge$status, "REACHABLE"))
r_edge2 <- tripwire_reachability(c(0.5, 0.999999), THR)
ck("경계 z<thr(극근접) → UNREACHABLE", identical(r_edge2$status, "A_UNREACHABLE_MONTH"))

## ── 빈 입력 / 전량 NA = '합격'으로 새지 않아야 함 (빈 결과=합격 계통 차단) ──
r_empty <- tripwire_reachability(numeric(0), THR)
ck("빈 입력 → NO_COVERAGE (REACHABLE 로 새지 않음)", identical(r_empty$status, "NO_COVERAGE"))
ck("빈 입력 → unreachable NA (FALSE 아님)", is.na(r_empty$unreachable))
r_na <- tripwire_reachability(c(NA_real_, NA_real_), THR)
ck("전량 NA → NO_COVERAGE", identical(r_na$status, "NO_COVERAGE"))
ck("전량 NA → n_covered 0", identical(r_na$n_covered, 0L))

## ── 부분 NA: 유한값만으로 판정 ─────────────────────────────────────────────
r_mix <- tripwire_reachability(c(NA_real_, 0.4, NA_real_, 0.7), THR)
ck("부분 NA → 유한값만 계수(n_covered=2)", identical(r_mix$n_covered, 2L))
ck("부분 NA → UNREACHABLE", identical(r_mix$status, "A_UNREACHABLE_MONTH"))

## ── 배선 실증: production 파일이 함수를 **실제로 호출·노출**하는가 ─────────
## (정의만 있고 소비가 없으면 dead code — '배선 완료'로 위장된다)
ck("배선① 호출부 존재 (ins_reach 할당)",
   any(grepl("ins_reach\\s*<<-\\s*tripwire_reachability\\(", src)))
ck("배선② 출력 노출 (tripwire_reachability 필드)",
   any(grepl("tripwire_reachability\\s*=\\s*if", src)))
ck("배선③ 문턱 frozen 불변 (INS_NB_THR 재정의 없음)",
   sum(grepl("^INS_NB_THR\\s*<-", src)) == 1L)

## ── 돌연변이 검출력: 정의를 망가뜨리면 테스트가 잡는가 ─────────────────────
mutant <- function(z_vec, thr) {   # >= 를 > 로 바꾼 오구현
  z <- z_vec[is.finite(z_vec)]; n <- length(z)
  if (n == 0L) return(list(n_covered = 0L, max_z = NA_real_, n_at_or_above = 0L,
                           unreachable = NA, status = "NO_COVERAGE"))
  nge <- sum(z > thr)
  list(n_covered = n, max_z = max(z), n_at_or_above = nge,
       unreachable = (nge == 0L),
       status = if (nge == 0L) "A_UNREACHABLE_MONTH" else "REACHABLE")
}
ck("★돌연변이(>= → >) 를 경계 케이스가 검출",
   !identical(mutant(c(0.5, 1.0), THR)$status, r_edge$status))

cat(sprintf("\n[test_tripwire_reachability] PASS=%d FAIL=%d\n", pass, fail))
## 배터리 집계 규약 — 마지막 줄에 요약 JSON 발행 (run_all_hooks.sh 가 파싱).
##   ★없으면 "UNREPORTED: 요약 JSON 파싱 실패"로 잡힌다 = 등재됐는데 집계 안 되는 상태.
##   (실사고: 본 검사기 최초 등재 시 이 줄이 없어 570 중 1건 FAIL 로 표시됐다.)
cat(sprintf('{"test":"tripwire_reachability","pass":%d,"fail":%d,"total":%d}\n',
            pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
