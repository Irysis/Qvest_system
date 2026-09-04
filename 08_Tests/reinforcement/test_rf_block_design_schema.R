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
#   ④ 강화 활성 중에는 새 논문 충실구현이 안 돈다 (가드가 한쪽에만 있었다)
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

cat("\n=== E. 동시 실행 가드 — 강화 중 새 논문 금지 ===\n")
rsrc <- paste(readLines("02_Infrastructure/ops/rf_replication_auto.sh", warn = FALSE), collapse = "\n")
if (grepl("halt_reinforce_active", rsrc, fixed = TRUE))
  ok("E1 충실구현 레인에 강화-활성 가드 ★실사고(2511.12490 이 강화와 나란히 돌았다)") else
  ng("E1 가드 없음", "가드가 next_paper 한쪽에만 있으면 레인이 그냥 집는다")
if (grepl("QVEST_RP_ALLOW_CONCURRENT", rsrc, fixed = TRUE))
  ok("E2 해제 스위치 존재") else ng("E2 스위치 없음")
if (grepl("pending", rsrc, fixed = TRUE) && grepl("보류", rsrc, fixed = TRUE))
  ok("E3 요청을 지우지 않고 보류한다(강화 후 그대로 집힌다)") else
  ng("E3 요청 처분 불명")
nsrc <- paste(readLines("02_Infrastructure/ops/reinforce_auto_next_paper.R", warn = FALSE), collapse = "\n")
if (grepl("halt_active_exists", nsrc, fixed = TRUE))
  ok("E4 next_paper 쪽 가드 보존(회귀)") else ng("E4 구 가드 손상")

cat("\n=== F. 캐시 스펙이 수리를 무력화하지 않는가 ===\n")
psrc <- paste(readLines("02_Infrastructure/ops/reinforce_auto_parallel.R", warn = FALSE), collapse = "\n")
if (grepl("resume_pending", psrc, fixed = TRUE))
  ok("F1 resume 경로 존재 — 이 경로가 옛 스펙을 재사용했다(사실 고정)") else
  cat("  SKIP resume 경로 없음\n")
cat("  NOTE 코드 수리 후에는 .cache/rf_parallel/spec_<code>__<base>.json 을 지울 것 —\n")
cat("       2026-09-04 19:21 재기동이 19:15 자 스펙을 재사용해 같은 오류로 두 번째 죽었다.\n")

cat("
=== G. 기전 회피 목록이 집행되는가 ===
")
## 실측 2026-09-04: avoid 를 읽는 코드가 rf_b1_design_lib.R **하나뿐**이었다(B1 설계
##   프롬프트). 칸을 고르는 러너는 안 읽으므로 격자 기본 칸에는 원리상 안 걸렸다 —
##   기전이 "B3_11 은 측정 무효 사유" 라고 적었는데 그대로 돌았다.
psrc2 <- paste(readLines("02_Infrastructure/ops/reinforce_auto_parallel.R", warn = FALSE), collapse = "
")
if (grepl("avoid_enforced", psrc2, fixed = TRUE))
  ok("G1 러너가 회피를 집행한다 ★실사고") else ng("G1 러너가 avoid 를 안 읽는다")
if (grepl("측정 무효|편의|편향|누출", psrc2))
  ok("G2 **측정 무효 사유**만 건너뛴다") else ng("G2 사유 구분 없음")
if (grepl("avoid_noted", psrc2, fixed = TRUE) && grepl("AX-000", psrc2, fixed = TRUE))
  ok("G3 성과 사유는 로그만 — 사실 기록이지 금지 목록이 아니다(AX-000)") else
  ng("G3 성과 사유까지 막는다", "3~4회 실패로 한계 단정 금지와 충돌")
lsrc <- paste(readLines("02_Infrastructure/ops/rf_b1_design_lib.R", warn = FALSE), collapse = "
")
if (grepl("avoid", lsrc, fixed = TRUE))
  ok("G4 설계 프롬프트 주입은 보존(회귀)") else ng("G4 구 경로 손상")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_block_design_schema","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
