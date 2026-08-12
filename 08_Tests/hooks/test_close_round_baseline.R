## test_close_round_baseline.R — close_round 의 baseline 선언 필드 계약 (위반 주입 포함)
## 대상: 02_Infrastructure/contracts/close_round.R (2026-08-10 FQ-127 F1)
## 왜: 비교·개선 주장은 base 없이 해석 불가한데(FQ-170 순열 통제 4/4: 같은 규칙이 base 에 따라
##     +0.845 / +0.264 / **-0.293**), 판정문이 산문이라 **사후에 기계로 물을 수 없다**
##     (FQ-127 C1 에서 정규식 census 가 표본 5/5 오분류로 무효).
##     ⇒ 발행 시점에 필드로 받고, 감사는 "필드가 선언됐나" 라는 **구조적 질문**이 된다.
## ★검사 축: ①비파괴(기존 호출부 무영향) ②필드가 실제로 원장에 도달 ③미선언이 FALSE 로 기록
##          ④선언값 왕복 ⑤빈 문자열은 선언으로 치지 않음 ⑥돌연변이(필드 제거 시 검사 붕괴)
suppressWarnings(suppressMessages({ }))
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash="/", mustWork=FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
SRC <- file.path(.root, "02_Infrastructure/contracts/close_round.R")
if (!file.exists(SRC)) {
  cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  if (nzchar(cand)) SRC <- file.path(cand, "02_Infrastructure/contracts/close_round.R")
}
if (!file.exists(SRC)) stop(sprintf("계약 파일 미발견: %s (러너 위치 문제이지 계약 실패가 아님)", SRC))
suppressPackageStartupMessages(library(jsonlite))
source(SRC)

PASS <- 0L; FAIL <- 0L
.m1 <- function(x) { x <- as.character(x); if (!length(x)) "" else x[1] }
ok  <- function(n,m="") { PASS <<- PASS+1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(.m1(m))) paste0(" — ", .m1(m)) else "")) }
bad <- function(n,m="") { FAIL <<- FAIL+1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(.m1(m))) paste0(" — ", .m1(m)) else "")) }
chk <- function(n,c,m="") if (isTRUE(c)) ok(n,m) else bad(n,m)

## write_marker=FALSE 로 부작용 없이 반환값만 본다 (원장 오염 방지)
call_cr <- function(...) {
  suppressMessages(close_round(
    round_id = "TEST_baseline_contract", verdict_type = "capability_established",
    mechanism_diagnosis = "검사용 기전 진단 문자열 — 20자 이상 요건 충족을 위한 더미 본문이다.",
    next_probes = c("검사 probe 1", "검사 probe 2"),
    consumer_surfaces = "검사 소비면", frontier_update = "검사 frontier",
    live_trigger = c("검사 부활조건"), layer = "test", evidence_refs = "test.json",
    write_marker = FALSE, ...))
}

cat("\n[A] 비파괴 — 기존 호출부(baseline 미지정)가 그대로 동작\n")
r0 <- try(call_cr(), silent = TRUE)
chk("A1_no_baseline_ok", !inherits(r0, "try-error"), "baseline 없이 호출해도 stop 하지 않는다")
chk("A2_field_exists", is.list(r0) && "baseline_declared" %in% names(r0),
    "미지정이어도 `baseline_declared` 필드는 **항상 존재**(결측을 침묵으로 두지 않음)")
chk("A3_declared_false", isTRUE(r0$baseline_declared == FALSE),
    "미선언 = FALSE 로 **기록**된다 — 감사가 구조적 질문이 됨")
chk("A4_baseline_empty", length(r0$baseline) == 0L, "미선언 시 baseline 은 길이 0")

cat("\n[B] 선언값 왕복\n")
r1 <- call_cr(baseline = "PG2 score_eff (book IR 1.416)")
chk("B1_declared_true", isTRUE(r1$baseline_declared), "선언 시 TRUE")
chk("B2_roundtrip", identical(r1$baseline, "PG2 score_eff (book IR 1.416)"), "값이 그대로 보존")
r2 <- call_cr(baseline = c("무밴드 top-25", "CORE4_EW"))
chk("B3_multi", length(r2$baseline) == 2L && isTRUE(r2$baseline_declared), "복수 기준선 허용")

cat("\n[C] 위반 주입 — 빈 값은 선언으로 치지 않는다\n")
chk("C1_empty_string", isFALSE(call_cr(baseline = "")$baseline_declared),
    "빈 문자열 = 미선언 (형식만 채우는 우회 차단)")
chk("C2_all_empty", isFALSE(call_cr(baseline = c("", ""))$baseline_declared),
    "전부 빈 문자열도 미선언")
chk("C3_partial", isTRUE(call_cr(baseline = c("", "PG2"))$baseline_declared) &&
                  identical(call_cr(baseline = c("", "PG2"))$baseline, "PG2"),
    "일부만 유효하면 유효분만 남기고 선언으로 인정")
chk("C4_na_not_declared", isFALSE(call_cr(baseline = NULL)$baseline_declared), "NULL = 미선언")

cat("\n[D] 원장 도달 — 필드가 JSON 직렬화를 건너간다\n")
j <- fromJSON(toJSON(r1, auto_unbox = TRUE), simplifyVector = TRUE)
chk("D1_serializes", !is.null(j$baseline_declared) && isTRUE(j$baseline_declared),
    "toJSON/fromJSON 왕복 후에도 선언 플래그 보존 (원장은 jsonl 이다)")
chk("D2_value_serializes", identical(as.character(j$baseline), "PG2 score_eff (book IR 1.416)"),
    "값도 왕복 보존")

cat("\n[F] 요약 문구가 **실제로 일어난 일**을 말하는가 (2026-08-10 발견)\n")
## ★이 검사를 쓰다가 발견: 요약 마지막 줄이 write_marker 와 무관하게 항상 "마커 발행 →
##   Stop 게이트 자동 통과" 를 주장했다. 드라이런에서도 그렇게 찍혀 **일어나지 않은 일을 사실로 보고**.
cap <- function(...) paste(utils::capture.output(suppressMessages(close_round(
  round_id = "TEST_marker_msg", verdict_type = "capability_established",
  mechanism_diagnosis = "요약 문구 검사용 더미 기전 진단 본문 — 20자 이상 요건 충족.",
  next_probes = c("p1","p2"), consumer_surfaces = "c", frontier_update = "f",
  live_trigger = "t", layer = "test", evidence_refs = "e.json", ...))), collapse = "\n")
s_off <- cap(write_marker = FALSE)
chk("F1_dryrun_says_not_emitted", grepl("미발행", s_off) && !grepl("자동 통과", s_off),
    "write_marker=FALSE 면 **미발행**이라고 말하고 '자동 통과' 를 주장하지 않는다")
chk("F2_baseline_notice", grepl("baseline 미선언", s_off),
    "baseline 미선언이 요약에도 보인다(원장 필드 + 사람용 경고 이중)")
s_bl <- cap(write_marker = FALSE, baseline = "PG2 score_eff")
chk("F3_baseline_shown", grepl("기준선: PG2 score_eff", s_bl) && !grepl("baseline 미선언", s_bl),
    "선언 시 기준선이 요약에 표기되고 경고는 사라진다")

cat("\n[E] 돌연변이 — 필드를 빼면 감사가 불가능해지는가 (검사 사망 통제)\n")
mut <- r1; mut$baseline_declared <- NULL
chk("E1_mutation_breaks_audit", is.null(mut$baseline_declared) && !is.null(r1$baseline_declared),
    "필드 제거 시 감사 질문이 성립 불가 — A2/A3 의 PASS 가 이 필드에서 온 것임을 실증")

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"close_round_baseline","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS+FAIL))
if (FAIL > 0L) quit(status = 1L)
