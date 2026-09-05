#!/usr/bin/env Rscript
#==============================================================================
# test_rf_block_design_code_follows_pick.R — 설계 칸의 코드는 pick 이 격자 코드면 그 코드다 (2026-09-05)
#
# 실사고 (promo2 B3 · 09:5x): rfbd_cells 가 전 블록을 **위치**로 코드 매김(<block>_<시작+i-1>).
#   B3 은 pick 자체가 격자 코드라 설계 [B3_12,B3_11,B3_15,B3_14] 가 슬롯 [B3_11..B3_14] 로 밀렸다.
#   내용은 설계를 따르고 코드만 어긋나, 코드로 대조하는 회피 집행이 슬롯 B3_11(=KOSPI200 단독)을
#   C6 사유로 건너뛰고(예산 1칸 소실), 정작 C6 대상 KOSDAQ150 단독은 코드 B3_12 로 측정됐다.
#
# 판정 축:
#   C1 B3 설계 → 코드 == pick (순서 보존)                     ★실사고
#   C2 B3 각 칸의 universe == 그 pick 의 카탈로그 universe  (내용이 pick 을 따른다)
#   C3 B2 설계(arm id pick) → 코드는 여전히 위치(B2_6..)     (음성 대조 — 반대쪽을 안 죽였나)
#   C4 돌연변이 통제 — 구 위치 규칙이면 실사고가 재현된다
#   C5 격리 root 에서 rfbd_verify 가 B3 설계를 통과시킨다
# 격리: 임시 root 에 reinforce_program.json 만 복사 — 운영 설계 디렉터리에 아무것도 쓰지 않는다.
#==============================================================================
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
.done <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_block_design_code_follows_pick","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L)
}
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), local = globalenv()))))

## 격리 root
TMP <- file.path(tempdir(), paste0("rfbd_code_", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(TMP, "06_Registry/reinforce_program.json"))
PICKS <- c("B3_12", "B3_11", "B3_15", "B3_14")
D <- list(block = "B3", cells = lapply(PICKS, function(p) list(pick = p, label = paste("픽스처", p), why = "격리 검사")))
dp <- rfbd_path(TMP, "T_FIXTURE", "B3")
dir.create(dirname(dp), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(D, auto_unbox = TRUE, pretty = TRUE), dp)

cat("=== 1. B3 코드 == pick ===\n")
cells <- rfbd_cells(TMP, "T_FIXTURE", "B3")
codes <- vapply(cells %||% list(), function(c) as.character(c$code %||% ""), character(1))
if (length(codes) == 4L && identical(codes, PICKS)) ok(paste("C1 코드 == pick:", paste(codes, collapse = ","))) else
  ng("C1 코드가 pick 을 안 따른다 ★실사고", paste(codes, collapse = ","))

cat("=== 2. 내용이 pick 을 따른다 ===\n")
cat_map <- rfbd_catalog("B3", TMP)
.find <- function(id) { k <- which(vapply(cat_map, function(x) identical(as.character(x$id), id), logical(1))); if (length(k)) cat_map[[k[1]]] else NULL }
c2 <- all(vapply(seq_along(cells), function(i) {
  cm <- .find(PICKS[i]); !is.null(cm) && identical(toJSON(cells[[i]]$universe %||% list()), toJSON(cm$universe %||% list()))
}, logical(1)))
if (isTRUE(c2) && length(cells) == 4L) ok("C2 각 칸 universe == 그 pick 의 카탈로그 universe") else ng("C2 내용이 pick 과 어긋난다")

cat("=== 3. 음성 대조 — B2 는 위치 코드 유지 ===\n")
b2 <- tryCatch(rfbd_cells(ROOT, "RP_20260904_163647_18444_rescued_rulefast_promo2", "B2"), error = function(e) NULL)
b2c <- vapply(b2 %||% list(), function(c) as.character(c$code %||% ""), character(1))
if (length(b2c) >= 2L && identical(b2c[1:2], c("B2_6", "B2_7"))) ok(paste("C3 B2 위치 코드 유지:", paste(b2c, collapse = ","))) else
  ng("C3 B2 코드가 바뀌었다", paste(b2c, collapse = ","))

cat("=== 4. 돌연변이 통제 ===\n")
old_codes <- sprintf("B3_%d", 11L + seq_along(PICKS) - 1L)
if (sum(old_codes != PICKS) >= 3L) ok(sprintf("C4 구 위치 규칙은 4칸 중 %d칸을 다른 코드로 — 픽스처가 결함을 가른다", sum(old_codes != PICKS))) else
  ng("C4 픽스처가 구 규칙과 구분되지 않는다")

cat("=== 5. 격리 root 검증 통과 ===\n")
v <- tryCatch(rfbd_verify(D, "B3", TMP), error = function(e) conditionMessage(e))
if (is.null(v) || isTRUE(v)) ok("C5 rfbd_verify PASS") else ng("C5 rfbd_verify 거부", paste(as.character(v), collapse = ";"))
unlink(TMP, recursive = TRUE)
.done()
