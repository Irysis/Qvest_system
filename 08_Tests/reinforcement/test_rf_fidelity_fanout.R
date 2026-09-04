#!/usr/bin/env Rscript
#==============================================================================
# test_rf_fidelity_fanout.R — 축 팬아웃 감사가 **분류를 없앴는가** (도훈 2026-09-04)
#
# 배경: 단일 감사자는 축을 고른다. 2026-09-04 2302.10175 감사가 자기 산출물에
#   "최고위험 2건을 원문 대조" 라고 적었다 — 나머지는 안 봤다는 뜻인데 verdict 는
#   하나로 나왔고 **무엇을 안 봤는지가 아무 데도 안 남았다.**
#
# 이 검사가 지키는 것:
#   ① 발견 하나가 나머지 축의 "이상 없음" 으로 희석되지 않는다 (최악 채택)
#   ② faithful 은 required 축이 **원문을 읽었을 때만** 낼 수 있다 — 안 읽고 낸 faithful 이
#      이 감사의 최악 실패 모드다(침묵과 같은 값어치)
#   ③ 근거 없는 기각은 판정을 끌고 가지 못한다 (잡음 차단)
#   ④ 안 본 축이 **명시적으로 남는다** (미산출 축이 조용히 빠지지 않는다)
#   ⑤ 하류 스키마 무손상 — verify·disposition 이 그대로 돈다
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

AXP <- file.path(ROOT, "06_Registry/rf_fidelity_axes.json")
MRG <- file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_merge.R")
AX  <- fromJSON(AXP, simplifyVector = FALSE)$axes
KEYS <- vapply(AX, function(a) a$key, character(1))
REQ  <- KEYS[vapply(AX, function(a) isTRUE(a$required), logical(1))]
OPT  <- setdiff(KEYS, REQ)

# ★시나리오마다 **별도 디렉터리** — 픽스처 별칭으로 검사가 서로를 오염시킨 전례가 있다
.run <- function(files) {
  w <- file.path(tempdir(), sprintf("fo_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e8))))
  dir.create(w, recursive = TRUE, showWarnings = FALSE)
  for (k in names(files)) write(toJSON(files[[k]], auto_unbox = TRUE, null = "null"),
                                file.path(w, sprintf("fidelity_axis_%s.json", k)))
  system2("Rscript", c("-e", shQuote(sprintf("source('%s')", MRG)), shQuote(w), shQuote(AXP)),
          stdout = NULL, stderr = NULL)
  p <- file.path(w, "fidelity_audit.json")
  if (!file.exists(p)) return(NULL)
  fromJSON(p, simplifyVector = FALSE)
}
.faith <- function(k) list(axis = k, verdict = "faithful", undeclared_changes = list(),
                           signal_mismatch = list(), evidence = sprintf("3절 대조 완료(%s)", k),
                           confidence = "high", checked = "전 항목", note = "")
.all_faith <- function() setNames(lapply(KEYS, .faith), KEYS)

cat("=== A. 축 등록부 — 축을 코드에 박지 않았는가 ===\n")
if (length(AX) >= 4L) ok(sprintf("A1 축 %d개", length(AX))) else ng("A1 축이 너무 적다")
if (length(REQ) >= 1L && length(OPT) >= 1L)
  ok(sprintf("A2 required %d / 선택 %d 로 갈린다", length(REQ), length(OPT))) else
  ng("A2 required 구분 없음", "한 레인이 흔들리면 감사 전체가 죽는다")
mods <- unique(vapply(AX, function(a) a$model, character(1)))
if (length(mods) >= 2L) ok(sprintf("A3 모델이 축 성질로 갈린다(%s)", paste(mods, collapse = "/"))) else
  ng("A3 전 축 동일 모델", "판독형/대조형 분리가 설계에만 있다")
fsrc <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_fanout.sh"), warn = FALSE), collapse = "\n")
if (!any(vapply(KEYS, function(k) grepl(sprintf('"%s"', k), fsrc, fixed = TRUE), logical(1))))
  ok("A4 러너가 축 이름을 하드코딩하지 않는다(등록부에서 읽는다)") else
  ng("A4 축이 셸에 박혔다", "등록부를 고쳐도 안 따라온다")

cat("\n=== B. 병합 규칙 — 정상 방향 ===\n")
r <- .run(.all_faith())
if (!is.null(r) && identical(r$verdict, "faithful")) ok("B1 전 축 faithful → faithful") else
  ng("B1", as.character(r$verdict %||% "NULL"))
f <- .all_faith(); f[[REQ[1]]] <- list(axis = REQ[1], verdict = "misdeclared",
  undeclared_changes = list("논문은 t-1 인데 구현은 t"), signal_mismatch = list(),
  evidence = "2절 식 (4)", confidence = "high", checked = "부호·창", note = "")
r <- .run(f)
if (!is.null(r) && identical(r$verdict, "misdeclared"))
  ok("B2 한 축 발견이 나머지 축의 '이상 없음' 으로 희석되지 않는다 ★핵심") else
  ng("B2 발견이 희석됐다", as.character(r$verdict %||% "NULL"))
if (!is.null(r) && length(r$undeclared_changes) == 1L &&
    startsWith(as.character(r$undeclared_changes[[1]]), paste0("[", REQ[1], "]")))
  ok("B3 발견에 축 라벨이 붙는다(재구현이 어느 축인지 안다)") else ng("B3 축 라벨 없음")
f <- .all_faith(); f[[OPT[1]]]$verdict <- "adapted"
r <- .run(f)
if (!is.null(r) && identical(r$verdict, "adapted")) ok("B4 adapted 승계") else
  ng("B4", as.character(r$verdict %||% "NULL"))

cat("\n=== C. 위반 주입 — 잡음과 침묵을 막는가 ===\n")
f <- .all_faith(); f[[REQ[1]]] <- list(axis = REQ[1], verdict = "misdeclared",
  undeclared_changes = list("뭔가 이상하다"), signal_mismatch = list(),
  evidence = "", confidence = "low", checked = "", note = "")
r <- .run(f)
if (!is.null(r) && !identical(r$verdict, "misdeclared"))
  ok("C1 근거 없는 misdeclared 는 판정을 못 끈다(잡음 차단)") else
  ng("C1 근거 없는 기각이 판정을 끌었다")
f <- .all_faith(); f[[REQ[1]]] <- list(axis = REQ[1], verdict = "misdeclared",
  undeclared_changes = list("미신고 변경 없음"), signal_mismatch = list("신호 불일치 없음"),
  evidence = "3절", confidence = "high", checked = "", note = "")
r <- .run(f)
if (!is.null(r) && !identical(r$verdict, "misdeclared"))
  ok("C2 채움 항목만인 misdeclared 는 불채택(배열 길이 게이트 우회 차단)") else
  ng("C2 채움 문장이 게이트를 통과했다")
f <- .all_faith(); f[[REQ[1]]] <- NULL          # required 축 미산출
r <- .run(f)
if (!is.null(r) && identical(r$verdict, "unverifiable"))
  ok("C3 required 축이 원문을 못 읽으면 faithful 불가 ★핵심") else
  ng("C3 안 읽고 faithful 을 냈다", as.character(r$verdict %||% "NULL"))
f <- .all_faith(); f[[OPT[1]]] <- NULL          # 대조형 축 하나 미산출
r <- .run(f)
if (!is.null(r) && identical(r$verdict, "faithful"))
  ok("C4 대조형 레인 하나가 죽어도 감사는 산다(과잉 fail-closed 아님)") else
  ng("C4 한 레인 실패로 감사 전체가 죽었다", as.character(r$verdict %||% "NULL"))
f <- .all_faith(); f[[REQ[1]]]$verdict <- "unverifiable"
r <- .run(f)
if (!is.null(r) && identical(r$verdict, "unverifiable"))
  ok("C5 required 축의 자기신고 unverifiable 도 같게 취급") else ng("C5")

cat("\n=== D. 무엇을 안 봤는지가 남는가 (팬아웃의 존재 이유) ===\n")
f <- .all_faith(); f[[OPT[1]]] <- NULL
r <- .run(f)
av <- r$axis_verdicts %||% list()
if (length(av) == length(KEYS))
  ok(sprintf("D1 axis_verdicts 에 전 축 %d개가 남는다(미산출 포함)", length(KEYS))) else
  ng("D1 축이 조용히 빠졌다", sprintf("%d/%d", length(av), length(KEYS)))
miss <- Filter(function(x) identical(x$axis, OPT[1]), av)
if (length(miss) && nzchar(as.character(miss[[1]]$reason %||% "")))
  ok("D2 미산출 축에 사유가 붙는다") else ng("D2 사유 없음", "왜 안 봤는지 모른다")
if (length(r$flags %||% list()) >= 1L) ok("D3 불채택·미산출이 flags 로 표면화") else
  ng("D3 flags 침묵")

cat("\n=== E. 하류 무손상 — 구판 소비자가 그대로 도는가 ===\n")
f <- .all_faith(); f[[REQ[1]]] <- list(axis = REQ[1], verdict = "misdeclared",
  undeclared_changes = list("논문은 EW 인데 구현은 VW"), signal_mismatch = list(),
  evidence = "Table 2", confidence = "high", checked = "비중", note = "")
w <- file.path(tempdir(), sprintf("fo_e_%d", Sys.getpid()))
dir.create(w, recursive = TRUE, showWarnings = FALSE)
for (k in names(f)) write(toJSON(f[[k]], auto_unbox = TRUE, null = "null"),
                          file.path(w, sprintf("fidelity_axis_%s.json", k)))
system2("Rscript", c("-e", shQuote(sprintf("source('%s')", MRG)), shQuote(w), shQuote(AXP)),
        stdout = NULL, stderr = NULL)
AUD <- file.path(w, "fidelity_audit.json")
rc <- system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R")),
                           "verify", shQuote(AUD)), stdout = NULL, stderr = NULL)
if (identical(as.integer(rc), 0L)) ok("E1 병합 산출이 구판 verify 를 통과한다 ★스키마 무손상") else
  ng("E1 verify 거부", sprintf("rc=%s", rc))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R")))
aud <- rf_audit_read(AUD)
dsp <- rf_audit_disposition(aud, 0L)
if (identical(dsp$action, "reimplement")) ok("E2 disposition 이 재구현으로 간다") else
  ng("E2 disposition", as.character(dsp$action %||% ""))
if (grepl(paste0("[", REQ[1], "]"), as.character(dsp$feedback %||% ""), fixed = TRUE))
  ok("E3 재구현 피드백에 축 라벨이 실린다") else ng("E3 축 라벨 유실")

cat("\n=== F. 배선 — 오케스트레이터가 아니라 평면인가 ===\n")
asrc <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit.sh"), warn = FALSE), collapse = "\n")
if (grepl("rf_fidelity_fanout.sh", asrc, fixed = TRUE)) ok("F1 감사자가 팬아웃으로 위임") else
  ng("F1 위임 없음")
cfg <- fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE)
if (isTRUE(cfg$fidelity_audit$fanout$enabled)) ok("F2 fanout 활성") else ng("F2 설정 부재")
if (grepl("Agent", fsrc, fixed = TRUE) && grepl("disallowed-tools", fsrc, fixed = TRUE))
  ok("F3 축 레인이 Agent 를 금지한다 — 오케스트레이터가 아님을 구조로 강제") else
  ng("F3 Agent 미금지", "축 레인이 또 분류할 수 있다")
if (grepl("rf_fidelity_merge.R", fsrc, fixed = TRUE)) ok("F4 병합은 R 이 한다(LLM 판정자 없음)") else
  ng("F4 병합기 미연결")
if (grepl("wait", fsrc, fixed = TRUE)) ok("F5 레인이 병렬로 돌고 전부 기다린다") else
  ng("F5 병렬/대기 없음")

cat("
=== G. 채움 필터가 실질 발견을 죽이지 않는가 (실사고 회귀) ===
")
# 실측 2026-09-04 1403.8125: 필터가 "없다|없음" 을 **포함하면** 버려서
#   156~331자짜리 실질 발견 4건이 전부 사라졌고, flags 가 "required 축 2/3만
#   원문 확인" 이라는 **거짓을** 냈다. 발견의 정상 서술이 "논문은 … 명시하지
#   않는다. changed 에도 없다." 이기 때문이다.
.long <- paste0("커버리지 하한 .COV=0.80 — 형성창 거래일의 80% 이상 종가 데이터를 갖지 못한 ",
                "종목을 데실 정렬에서 제외(engine.R:128). 논문 Section 3.2는 개별 종목 데이터 ",
                "커버리지 요건을 일절 명시하지 않는다. FIDELITY.changed에도 없다.")
f <- .all_faith(); f[[REQ[1]]] <- list(axis = REQ[1], verdict = "misdeclared",
  undeclared_changes = list(.long), signal_mismatch = list(),
  evidence = "Section 3.2", confidence = "high", checked = "유니버스 필터 전수", note = "")
r <- .run(f)
if (!is.null(r) && identical(r$verdict, "misdeclared") && length(r$undeclared_changes) == 1L)
  ok("G1 본문에 '없다' 가 들어간 실질 발견은 살아남는다 ★실사고") else
  ng("G1 실질 발견이 채움로 오판됐다", as.character(r$verdict %||% "NULL"))
if (!is.null(r) && length(r$flags %||% list()) == 0L)
  ok("G2 정상 발견에 허위 flag 가 안 붙는다") else
  ng("G2 허위 flag", paste(unlist(r$flags), collapse = " | "))
f <- .all_faith(); f[[REQ[1]]] <- list(axis = REQ[1], verdict = "misdeclared",
  undeclared_changes = list("미신고 변경 없음", "  불일치 없다.  "), signal_mismatch = list("N/A"),
  evidence = "3절", confidence = "high", checked = "", note = "")
r <- .run(f)
if (!is.null(r) && !identical(r$verdict, "misdeclared"))
  ok("G3 항목 전체가 비발견이면 여전히 걸러낸다(공백·불릿 포함)") else
  ng("G3 채움이 통과했다")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_fidelity_fanout","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
