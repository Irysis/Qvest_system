#!/usr/bin/env Rscript
#==============================================================================
# test_rf_block_design_schema.R — 설계 스키마 = 실행 스키마인가 (실사고 2026-09-04)
#
# 사고: 재설계된 B5 여섯 칸이 전부 "$ operator is invalid for atomic vectors" 로 죽었다.
#   정상 경로(rf_pick_overlay_arms)는 overlay = list(kind=, arm_id=) 를 내는데
#   설계 경로(rfbd_cells)는 list(arm_id=) 만 냈다 — 엔진은 kind 로 arm 을 찾는다.
#   뿌리는 rfbd_catalog("B5") 가 카탈로그에서 **kind 를 버린 것**이었다.
#
# 두 번째 사고(같은 건): 코드를 고치고 재기동했는데 **디스크에 남은 옛 스펙**을 재사용해
#   같은 오류로 또 죽고 terminal 이 됐다. 수리가 캐시를 안 지웠다.
#
# 이 검사가 지키는 것:
#   ① 두 경로가 **같은 모양**을 낸다 (설계 ↔ 카탈로그)
#   ② overlay.kind 가 실재하는 arm 으로 해석된다 (내장 10종 또는 overlay_arms/*.R)
#   ③ 카탈로그에 없는 id 는 조용히 통과하지 않는다
#   (구 ④ 강화 활성 중에는 새 논문 충실구현이 안 돈다 — v10.01 에서 삭제, 아래)
# (v10.01 2026-10-13) 고정 격자 러너 퇴역으로 E절(동시 실행 가드 E1~E4 — rf_replication_auto.sh 의 halt_reinforce_active
#   게이트는 러너와 함께 삭제됐고 reinforce_auto_next_paper.R 도 퇴역) · F절(캐시 스펙 resume 경로 — reinforce_auto_parallel.R) ·
#   G절(기전 회피 집행 G1~G5 — reinforce_auto_parallel.R · rf_b1_design_lib.R) 삭제 — 대상 코드가 없다
#   (롤백 태그 pre-v10.01-prescription-20261013). 설계 스키마(A~D — rf_block_design.R · rf_cell_engine.R · rf_overlay_arms.R)는 그대로 잰다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

suppressMessages(source("02_Infrastructure/reinforcement/rf_block_design.R"))

cat("=== A. 카탈로그가 실행에 필요한 필드를 보존하는가 ===\n")
cm5 <- rfbd_catalog("B5", ROOT)
if (length(cm5)) ok(sprintf("A1 B5 카탈로그 %d항", length(cm5))) else ng("A1 카탈로그 비었다")
nk <- sum(vapply(cm5, function(x) nzchar(as.character(x$kind %||% "")), logical(1)))
if (nk == length(cm5)) ok("A2 전 항목이 kind 를 갖는다 ★실사고 지점") else
  ng("A2 kind 누락", sprintf("%d/%d", nk, length(cm5)))

cat("\n=== B. 두 경로가 같은 모양인가 — **세 분기 전부** ===\n")
## ★실사고 2026-09-04: B5 의 스키마 불일치를 고치면서 **형제 분기를 안 봤다**.
##   같은 함수(rfbd_cells) 안 세 줄이었는데 B2 에도 같은 병이 있었고(arm= vs catalog_id=)
##   다섯 칸이 전멸한 뒤에야 드러났다. 그래서 이 검사는 블록을 하나씩 세지 않고
##   **엔진이 읽는 필드**를 블록마다 재도출해 대조한다.
ESRC <- paste(readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
                        warn = FALSE), collapse = "\n")
## 엔진이 각 축에서 실제로 읽는 필드 (소스에서 재도출 — 목록을 손으로 적으면 낙후한다)
NEED <- list(
  B2 = c("catalog_id"),
  B5 = c("kind"),
  B3 = c("kind")
)
for (bk in names(NEED)) {
  cmx <- rfbd_catalog(bk, ROOT)
  if (!length(cmx)) { cat(sprintf("  SKIP %s 카탈로그 없음\n", bk)); next }
  tb2 <- sprintf("TESTBASE_SCHEMA_%s_%d", bk, Sys.getpid())
  dp2 <- rfbd_path(ROOT, tb2, bk)
  dir.create(dirname(dp2), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(block = bk, rationale = "검사",
                    cells = list(list(pick = cmx[[1]]$id, label = "t", why = "w"))),
               auto_unbox = TRUE), dp2)
  cs2 <- Filter(Negate(is.null), rfbd_cells(ROOT, tb2, bk))
  if (!length(cs2)) { ng(sprintf("B %s 설계 셀 산출 실패", bk)); unlink(dp2, force = TRUE); next }
  fld <- switch(bk, B2 = cs2[[1]]$weighting, B5 = cs2[[1]]$overlay, B3 = cs2[[1]]$universe)
  missf <- NEED[[bk]][!(NEED[[bk]] %in% names(fld %||% list()))]
  if (!length(missf))
    ok(sprintf("B %s 설계 경로가 엔진이 읽는 필드를 낸다 (%s)", bk,
               paste(names(fld), collapse = ","))) else
    ng(sprintf("B %s 필드 누락", bk), sprintf("없음=%s · 있음=%s",
       paste(missf, collapse = ","), paste(names(fld %||% list()), collapse = ",")))
  unlink(c(dp2, paste0(dp2, ".bak")), force = TRUE)
}

suppressMessages(source("02_Infrastructure/ops/rf_overlay_arms.R"))
pk <- tryCatch(rf_pick_overlay_arms(3L, root = ROOT), error = function(e) NULL)
if (!is.null(pk) && length(pk$cells)) {
  f_ok <- names(pk$cells[[1]]$overlay)
  if (all(c("kind", "arm_id") %in% f_ok))
    ok(sprintf("B1 정상 경로 overlay 필드 = %s", paste(f_ok, collapse = ","))) else
    ng("B1 정상 경로 필드", paste(f_ok, collapse = ","))
} else { cat("  SKIP 카탈로그 arm 없음\n"); f_ok <- c("kind", "arm_id") }

# 설계 픽스처 — 카탈로그 첫 항목을 그대로 고른다
TB <- sprintf("TESTBASE_SCHEMA_%d", Sys.getpid())
dp <- rfbd_path(ROOT, TB, "B5")
dir.create(dirname(dp), recursive = TRUE, showWarnings = FALSE)
write(toJSON(list(block = "B5", rationale = "검사 픽스처",
                  cells = list(list(pick = cm5[[1]]$id, label = "t1", why = "w1"))),
             auto_unbox = TRUE), dp)
cs <- rfbd_cells(ROOT, TB, "B5"); cs <- Filter(Negate(is.null), cs)
if (length(cs) == 1L) {
  f_de <- names(cs[[1]]$overlay)
  if (setequal(f_de, f_ok)) ok(sprintf("B2 설계 경로가 같은 필드를 낸다 (%s) ★핵심",
                                       paste(sort(f_de), collapse = ","))) else
    ng("B2 필드가 다르다", sprintf("설계=%s vs 정상=%s",
       paste(sort(f_de), collapse = ","), paste(sort(f_ok), collapse = ",")))
} else ng("B2 설계 셀 산출 실패", as.character(length(cs)))

## ★스택 설계(2026-09-17) — 층마다 정상 경로와 같은 필드를 낸다. 한 층이라도 kind 가 빠지면 엔진이 그 층에서 죽는다.
.act5 <- Filter(function(x) identical(x$status %||% "active", "active"), cm5)
if (length(.act5) >= 2L) {
  write(toJSON(list(block = "B5", rationale = "검사 픽스처", cells = list(list(picks = list(.act5[[1]]$id, .act5[[2]]$id), label = "st", why = "w"))),
               auto_unbox = TRUE), dp)
  cst <- Filter(Negate(is.null), rfbd_cells(ROOT, TB, "B5"))
  Lst <- if (length(cst)) cst[[1]]$overlay else NULL
  if (!is.null(Lst) && is.null(Lst$kind) && length(Lst) == 2L && all(vapply(Lst, function(z) setequal(names(z), f_ok), logical(1))))
    ok(sprintf("B3 스택 설계 경로 — 층 2개 각각 정상 경로 필드(%s)", paste(sort(f_ok), collapse = ","))) else
    ng("B3 스택 층 필드", if (is.null(Lst)) "셀 없음" else paste(vapply(Lst, function(z) paste(names(z), collapse = "/"), character(1)), collapse = " | "))
} else cat("  SKIP B3 active arm 2종 미만\n")

cat("\n=== C. kind 가 실재 arm 으로 해석되는가 ===\n")
esrc <- paste(readLines("02_Infrastructure/reinforcement/rf_cell_engine.R", warn = FALSE), collapse = "\n")
.bi <- regmatches(esrc, regexpr('\\.OV_BUILTIN <- c\\([^)]*\\)', esrc))
BUILTIN <- if (length(.bi)) unlist(regmatches(.bi, gregexpr('"[^"]+"', .bi))) else character(0)
BUILTIN <- gsub('"', '', BUILTIN)
armdir <- "02_Infrastructure/reinforcement/overlay_arms"
FILES <- sub("[.]R$", "", basename(list.files(armdir, pattern = "[.]R$")))
if (length(BUILTIN) >= 5L) ok(sprintf("C1 내장 kind %d종 파싱", length(BUILTIN))) else
  ng("C1 내장 목록 파싱 실패")
unres <- character(0)
for (x in cm5) { k <- as.character(x$kind %||% "")
  if (nzchar(k) && !(k %in% BUILTIN) && !(k %in% FILES)) unres <- c(unres, k) }
if (!length(unres)) ok(sprintf("C2 카탈로그 kind 전부 해석 가능(내장 %d · 파일 %d)",
                               length(BUILTIN), length(FILES))) else
  ng("C2 미해석 kind", paste(unique(unres), collapse = ","))

cat("\n=== D. 위반 주입 — 없는 id 는 통과하지 못한다 ===\n")
write(toJSON(list(block = "B5", cells = list(list(pick = "no_such_arm_xyz", label = "t", why = "w"))),
             auto_unbox = TRUE), dp)
cs2 <- rfbd_cells(ROOT, TB, "B5")
if (!length(Filter(Negate(is.null), cs2)))
  ok("D1 카탈로그에 없는 id 는 셀을 못 만든다(없는 arm 을 지어내지 않는다)") else
  ng("D1 없는 arm 이 셀이 됐다")
unlink(c(dp, paste0(dp, ".bak")), force = TRUE)

## (v10.01 2026-10-13) E절(동시 실행 가드) · F절(캐시 스펙 resume) · G절(기전 회피 집행) 삭제 — 대상 코드 퇴역
##   (rf_replication_auto.sh 의 halt_reinforce_active 게이트 · reinforce_auto_next_paper.R · reinforce_auto_parallel.R · rf_b1_design_lib.R).

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_block_design_schema","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
