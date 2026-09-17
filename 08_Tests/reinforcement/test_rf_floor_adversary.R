#!/usr/bin/env Rscript
#==============================================================================
# test_rf_floor_adversary.R — 누적 바닥(.wbest_spec)이 적대검증 판정을 따르는가 (양방향 · 2026-09-17)
#
# 왜: 적대검증 fail/error/not_candidate 인 B5 칸은 승자·carry·A 후보에서 빠지는데, PORT_t 최고면 러너의
#   누적 바닥(.wbest_spec)으로 뽑혀 그 오버레이가 뒤 블록(B2·B3)에 **승계**됐다 — 소비 보류가 새는 비대칭.
#   러너 실물 블록을 소스에서 떼어 돌린다(문자열 grep 이 아니라 실행 — 리팩터가 좌표를 옮겨도 의미로 잰다).
#   돌연변이: 필터 줄을 지운 사본은 fail 칸을 바닥으로 뽑아야 한다(검사가 결함을 잡는지 확인).
#
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_floor_adversary.R
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
cat(sprintf("ROOT = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")))))
RUNNER <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
src <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8")

# 러너 실물 블록: `.metric` 정의 1줄쌍 + `.wbest_spec <- NULL` 부터 그 블록을 닫는 `} } }` 까지
i_m <- grep("^\\.metric <- function\\(a, key\\)", src)
i0  <- grep("^\\.wbest_spec <- NULL", src)
i1  <- if (length(i0)) i0[1] + which(grepl("^\\s*\\} \\} \\}\\s*$", src[(i0[1] + 1):length(src)]))[1] else NA_integer_
if (length(i_m) != 1L || length(i0) != 1L || is.na(i1)) {
  ng("러너 블록 위치 찾기", sprintf("metric=%d wbest=%d end=%s", length(i_m), length(i0), i1))
  quit(status = 1)
}
metric_src <- src[i_m:(i_m + 1L)]
block_src  <- src[i0[1]:i1]
ok(sprintf("러너 블록 추출 (.metric %d줄 · 바닥 %d줄)", length(metric_src), length(block_src)))

tmp <- tempfile("rf_floor_"); dir.create(tmp)
mkspec <- function(code, overlay = NULL) {
  p <- file.path(tmp, sprintf("spec_%s.json", code))
  sp <- list(code = code, factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew"),
             universe = list(kind = "k200_kq150"))
  if (!is.null(overlay)) sp$overlay <- overlay
  write(toJSON(sp, auto_unbox = TRUE, null = "null"), p); p
}
att <- function(n, code, port_t, verdict = NULL, overlay = NULL) {
  a <- list(n = n, cell_code = code,
            essence = list(port_t = port_t, calmar = 0.3, cell_code = code, spec = mkspec(code, overlay)))
  if (!is.null(verdict)) a$adversary <- list(verdict = verdict)
  a
}
run_block <- function(attempts, lines = block_src) {
  env <- new.env(parent = globalenv())
  env$E <- list(attempts = attempts); env$cells <- list(); env$BID <- "RP_TEST_floor"
  env$EV <- character(0)
  env$jlog <- function(event, ...) assign("EV", c(get("EV", envir = env), event), envir = env)
  env$`%||%` <- `%||%`
  env$rf_adversary_ok <- rf_adversary_ok
  env$.rf_attempt_code <- function(a, cells = NULL) as.character(a$cell_code %||% "")
  env$fromJSON <- jsonlite::fromJSON
  eval(parse(text = c(metric_src, lines)), envir = env)
  list(code = env$.wbest_code, spec = env$.wbest_spec, events = env$EV)
}
ov <- list(kind = "gen_x", arm_id = "arm_x")

# A. fail 인 B5 칸이 PORT_t 최고 → 바닥에서 빠지고 차선(B1_5)이 바닥
r <- run_block(list(att(1, "B1_5", 3.20), att(2, "B5_20", 3.50, "fail", ov), att(3, "B2_7", 3.00)))
if (identical(r$code, "B1_5") && "floor_excluded_adversary" %in% r$events && is.null(r$spec$overlay))
  ok("A fail 칸(PORT_t 3.50) 제외 → 바닥 B1_5 · 이벤트 floor_excluded_adversary · 오버레이 미승계") else
  ng("A", sprintf("code=%s events=%s", r$code, paste(r$events, collapse = ",")))

# B. error · not_candidate 도 같은 취급
for (v in c("error", "not_candidate")) {
  r <- run_block(list(att(1, "B1_5", 3.20), att(2, "B5_19", 3.40, v, ov)))
  if (identical(r$code, "B1_5")) ok(sprintf("B verdict=%s 칸도 바닥 제외", v)) else ng(sprintf("B %s", v), r$code)
}

# C. pass 인 B5 칸은 바닥이 될 수 있다(오버레이 승계) · 이벤트 없음
r <- run_block(list(att(1, "B1_5", 3.20), att(2, "B5_18", 3.40, "pass", ov)))
if (identical(r$code, "B5_18") && !("floor_excluded_adversary" %in% r$events) && identical(r$spec$overlay$arm_id, "arm_x"))
  ok("C pass 칸은 바닥 · 오버레이 승계 · 제외 이벤트 없음") else ng("C", sprintf("code=%s", r$code))

# D. 판정 필드 없는 구 시도(legacy)는 그대로 후보
r <- run_block(list(att(1, "B1_5", 3.20), att(2, "B5_17", 3.60, NULL, ov)))
if (identical(r$code, "B5_17") && !length(r$events)) ok("D 판정 필드 없음(구 entry) → 기존대로 바닥 후보") else ng("D", r$code)

# E. 최고가 fail 이 아니면 이벤트를 내지 않는다(잡음 금지) — 하위 칸이 fail 이어도
r <- run_block(list(att(1, "B1_5", 3.80), att(2, "B5_16", 3.10, "fail", ov)))
if (identical(r$code, "B1_5") && !("floor_excluded_adversary" %in% r$events)) ok("E 최고가 통과 칸이면 제외 이벤트 없음") else ng("E", paste(r$events, collapse = ","))

# F. 돌연변이 — 필터 줄을 지운 사본은 fail 칸을 바닥으로 뽑는다(= 이 검사가 결함을 잡는다)
mut <- block_src[!grepl("^\\s*\\.cd0 <- Filter\\(rf_adversary_ok, \\.cd0\\)", block_src)]
if (length(mut) == length(block_src)) ng("F 돌연변이 적용 실패", "필터 줄을 못 찾음") else {
  r <- run_block(list(att(1, "B1_5", 3.20), att(2, "B5_20", 3.50, "fail", ov), att(3, "B2_7", 3.00)), lines = mut)
  if (identical(r$code, "B5_20")) ok("F [돌연변이] 필터 제거 사본은 fail 칸을 바닥으로 뽑는다 — A 가 그 결함을 잡는다") else
    ng("F 돌연변이 무반응", r$code)
}

unlink(tmp, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_floor_adversary","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1)
