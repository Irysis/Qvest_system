#!/usr/bin/env Rscript
#==============================================================================
# test_rf_block_design_catalog_parity.R — 설계 검증기 ↔ 엔진 카탈로그 술어 일치 (2026-09-05)
#
# 실사고 (promo2 B2_10 · 09:34): LLM 설계가 gen:lean_score_tilt__shr_lw_nls 를 골랐다. 그 id 는
#   weight_catalog.json 에 status=unverified 로 **있다**. 검증기 rfbd_catalog 는 status != retracted 만
#   걸러 통과시켰고, 엔진 rf_cell_engine 은 weight_catalog_arms(min_status="active") 를 읽어
#   "카탈로그 arm 부재" 로 죽였다. 같은 질문("실행 가능한 arm 인가")에 술어가 둘이었다 —
#   52 entry 중 13(unverified 5 · blocked_inputs 5 · degraded_wiring 3)이 설계엔 초록, 엔진엔 부재.
#   잃은 것은 설계의 대조쌍(목적함수 동일 · 공분산만 교체 = 추정오차 축) 칸 하나.
#
# 판정 축:
#   P1 검증기 id 집합 == 엔진 id 집합 (같은 함수를 부르므로 구성상 같아야 한다)
#   P2 실사고 id 가 검증기 목록에 없다 ★실사고
#   P3 실사고 id 하나짜리 설계를 rfbd_verify 가 기각한다
#   P4 양성 대조 — active id(lean:minvar) 설계는 통과 (고쳐서 반대쪽을 죽이지 않았나)
#   P5 돌연변이 통제 — 구 술어(!= retracted)는 실사고 id 를 포함한다 (픽스처의 판별력)
#
# 단독 실행: Rscript 08_Tests/reinforcement/test_rf_block_design_catalog_parity.R
# (배터리 등록은 test_reinforce_auto.sh 이설 세션 뒤로 보류)
#==============================================================================
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
.done <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_block_design_catalog_parity","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L)
}
ld <- function(f) tryCatch({ invisible(capture.output(suppressMessages(source(file.path(ROOT, f), local = globalenv())))); TRUE },
                           error = function(e) { ng(paste("source", f), conditionMessage(e)); FALSE })
if (!ld("02_Infrastructure/reinforcement/rf_block_design.R")) .done()
if (!ld("02_Infrastructure/portfolio/weight_catalog.R")) .done()
ok("검증기·카탈로그 적재")

cat("=== 1. 술어 일치 ===\n")
ver <- vapply(rfbd_catalog("B2", ROOT), function(x) as.character(x$id), character(1))
eng <- as.character(weight_catalog_arms(quiet = TRUE)$catalog_id)
if (length(ver) && setequal(ver, eng)) ok(sprintf("P1 검증기 %d == 엔진 %d", length(ver), length(eng))) else
  ng("P1 두 목록이 다르다", sprintf("검증기만: %s | 엔진만: %s",
     paste(setdiff(ver, eng), collapse = ","), paste(setdiff(eng, ver), collapse = ",")))

cat("=== 2. 실사고 id ===\n")
INC <- "gen:lean_score_tilt__shr_lw_nls"
if (!(INC %in% ver)) ok("P2 실사고 id 가 검증기 목록에 없다 ★실사고") else ng("P2 unverified arm 이 설계를 통과한다")
d1 <- list(block = "B2", cells = list(list(pick = INC, label = "대조쌍", why = "공분산만 교체")))
v1 <- tryCatch(rfbd_verify(d1, "B2", ROOT), error = function(e) conditionMessage(e))
if (is.character(v1) && length(v1) && nzchar(v1[[1L]])) ok(paste0("P3 rfbd_verify 기각: ", substr(v1[[1L]], 1, 60))) else
  ng("P3 rfbd_verify 가 실사고 설계를 통과시킨다")

cat("=== 3. 양성 대조 ===\n")
d2 <- list(block = "B2", cells = list(list(pick = "lean:minvar", label = "분산 최소화", why = "하한")))
v2 <- tryCatch(rfbd_verify(d2, "B2", ROOT), error = function(e) conditionMessage(e))
if (is.null(v2) || isTRUE(v2) || (is.character(v2) && !length(v2))) ok("P4 lean:minvar 설계 통과") else
  ng("P4 active id 를 거부한다", paste(as.character(v2), collapse = ";"))

cat("=== 4. 돌연변이 통제 ===\n")
J <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE), error = function(e) NULL)
old <- vapply(Filter(function(x) !identical(as.character(x$status %||% ""), "retracted"), J$entries %||% list()),
              function(x) as.character(x$catalog_id %||% ""), character(1))
if (INC %in% old) ok("P5 구 술어(!= retracted)는 실사고 id 를 포함 → 검사가 결함을 가른다") else
  ng("P5 픽스처가 구 술어에서도 안 잡힌다", "실사고 entry 가 카탈로그에서 사라졌나")

cat("=== 5. B5 술어 일치 — 설계 검증기 == 규칙 픽커(active) (2026-09-17) ===\n")
## 실사고 계열: B2 와 같은 병이 B5 에도 있었다 — rfbd_catalog("B5") 는 status 를 안 읽어 retired arm 이 설계를 통과했다.
##   규칙 픽커(rf_overlay_arms.R:46)는 active 만 뽑는다. 같은 질문에 술어가 둘이면 안 된다.
if (!ld("02_Infrastructure/ops/rf_overlay_arms.R")) .done()
v5 <- vapply(rfbd_catalog("B5", ROOT), function(x) as.character(x$id), character(1))
A5 <- rf_overlay_catalog(ROOT); p5 <- if (is.null(A5)) character(0) else A5[status == "active"]$id
if (length(v5) && setequal(v5, p5)) ok(sprintf("P6 B5 검증기 %d == 픽커 active %d", length(v5), length(p5))) else
  ng("P6 B5 두 목록이 다르다", sprintf("검증기만: %s | 픽커만: %s", paste(setdiff(v5, p5), collapse = ","), paste(setdiff(p5, v5), collapse = ",")))
## retired 주입 — 격리 root 에 카탈로그 사본을 두고 한 arm 을 retired 로 바꾼다
TMP <- file.path(tempdir(), sprintf("rfbd_par_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(TMP, "06_Registry/reinforce_program.json"))
cat5 <- fromJSON(file.path(ROOT, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)
## ★운영 카탈로그의 **active 인 arm** 을 골라 주입한다 (2026-09-17). 구판은 arms[[1]] 을 retired 로 바꾸고 "전체 − 1" 을 기대했다 —
##   운영 카탈로그에 이미 retired arm 이 하나라도 생기면(09-17 uw_erosion_dbeta_v1) 목록 길이가 "active − 1" 이라 거짓 FAIL 이 났다.
##   기대값은 입력에서 재도출한다: 주입 전 active 수 − 1.
.st5 <- vapply(cat5$arms, function(a) as.character(a$status %||% "active"), character(1))
.ia5 <- which(.st5 == "active")
RETID <- cat5$arms[[.ia5[1]]]$id; cat5$arms[[.ia5[1]]]$status <- "retired"
write(toJSON(cat5, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(TMP, "06_Registry/overlay_catalog.json"))
v5t <- vapply(rfbd_catalog("B5", TMP), function(x) as.character(x$id), character(1))
if (!(RETID %in% v5t) && length(v5t) == length(.ia5) - 1L) ok(sprintf("P7 retired 로 바꾼 %s 가 검증기 목록에서 빠진다(active %d → %d)", RETID, length(.ia5), length(v5t))) else ng("P7 retired 가 목록에 남는다", sprintf("active %d · 목록 %d", length(.ia5), length(v5t)))
r7 <- rfbd_verify(list(block = "B5", cells = list(list(pick = RETID, label = "r", why = "w"))), "B5", TMP)
if (is.character(r7) && grepl("retired", r7, fixed = TRUE)) ok(paste0("P8 rfbd_verify 기각: ", r7)) else ng("P8 retired 설계가 통과한다", as.character(r7))
r8 <- rfbd_verify(list(block = "B5", cells = list(list(pick = cat5$arms[[.ia5[2]]]$id, label = "a", why = "w"))), "B5", TMP)
if (isTRUE(r8)) ok("P9 양성 대조 — active arm 설계는 통과") else ng("P9 active 를 거부한다", as.character(r8))
if (RETID %in% vapply(cat5$arms, function(a) a$id, character(1))) ok("P10 돌연변이 통제 — 구 술어(status 무시)면 retired id 가 목록에 있었다") else ng("P10 판별력")
unlink(TMP, recursive = TRUE, force = TRUE)
.done()
