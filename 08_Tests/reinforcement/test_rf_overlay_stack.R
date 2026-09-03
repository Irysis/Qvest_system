#!/usr/bin/env Rscript
# 오버레이 중첩 계약 (v10.2 · 2026-09-03)
# 재는 것: ①.ov_stack 정규화 ②승계 배선(부모 오버레이가 자식 B1/B2/B3 로 전달) ③B5 중첩
#          ④B4 LOO 기저 보존 ⑤★단층 시그니처 불변(기존 측정이 되살아나면 안 된다)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK    %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

A <- list(kind = "dd_brake",   arm_id = "a1")
B <- list(kind = "dbeta_tilt", arm_id = "b1")

cat("=== A. .ov_stack 정규화 ===\n")
if (is.null(.ov_stack(NULL, NULL))) ok("A1 빈 입력 -> NULL") else ng("A1")
r <- .ov_stack(NULL, A)
if (!is.null(r$kind) && identical(r$kind, "dd_brake")) ok("A2 단층 -> 구판 단수 객체 그대로") else ng("A2 단층이 리스트로 감싸졌다")
r <- .ov_stack(A, B)
if (is.null(r$kind) && length(r) == 2L && identical(r[[1]]$kind, "dd_brake") && identical(r[[2]]$kind, "dbeta_tilt"))
  ok("A3 2층 -> 순서 보존 리스트") else ng("A3 2층 합성 실패")
r <- .ov_stack(A, A)
if (!is.null(r$kind)) ok("A4 같은 arm 중복 제거 — 이중 축소 방지") else ng("A4 같은 arm 이 두 번 얹혔다")
r <- .ov_stack(list(kind = "none"), B)
if (!is.null(r$kind) && identical(r$kind, "dbeta_tilt")) ok("A5 none 층 소거") else ng("A5")
r <- .ov_stack(list(A, B), NULL)
if (length(.ov_layers(r)) == 2L) ok("A6 이미 리스트인 입력 평탄화") else ng("A6")

cat("\n=== B. 시그니처 연속성 (회귀 방지) ===\n")
sp_old <- list(factors = list(), weighting = list(kind = "ew"),
               universe = list(kind = "k200_kq150"), overlay = A)
sp_new <- sp_old; sp_new$overlay <- .ov_stack(NULL, A)
if (identical(.spec_sig(sp_old), .spec_sig(sp_new)))
  ok("B1 단층 시그니처 불변 — 기존 측정이 되살아나지 않는다") else
  ng("B1 단층인데 시그니처가 바뀌었다 — 전 격자 재측정 유발")
sp_two <- sp_old; sp_two$overlay <- .ov_stack(A, B)
if (!identical(.spec_sig(sp_old), .spec_sig(sp_two)))
  ok("B2 중첩판은 다른 구성으로 식별 — 중복측정 회피가 산다") else
  ng("B2 중첩과 단층이 같은 시그니처")
if (!.same_axis(sp_two$overlay, sp_old$overlay))
  ok("B3 .same_axis 가 층 수를 구분 — 무처치 오판 없음") else ng("B3")

cat("\n=== C. 러너 배선 (소스 대조) ===\n")
src <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"),
                       warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl('c("B5", "B4")) && !is.null(E$carry$overlay)) SPEC$overlay <- E$carry$overlay', src, fixed = TRUE))
  ok("C1 오버레이 승계 — B1/B2/B3 가 부모 위험통제를 물려받는다") else
  ng("C1 carry 에 overlay 승계 줄이 없다")
if (grepl("SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)", src, fixed = TRUE))
  ok("C2 B5 중첩 — 덮어쓰기가 아니라 곱 합성") else ng("C2 B5 가 아직 덮어쓴다")
if (grepl('if ("B5" %in% use) .w5_overlay else (E$carry$overlay %||% NULL)', src, fixed = TRUE))
  ok("C3 B4 LOO — B5 제외 칸도 부모 오버레이는 기저로 남는다") else
  ng("C3 B4 가 B5 제외 시 부모 오버레이까지 벗긴다")
if (grepl("rf_spec_sig.R", src, fixed = TRUE)) ok("C4 러너가 공용 헬퍼를 source") else ng("C4")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_overlay_stack","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
