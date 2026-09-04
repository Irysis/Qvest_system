#!/usr/bin/env Rscript
#==============================================================================
# test_rf_grid_cursor.R — 격자 커서가 개수가 아니라 코드에서 나오는가 (2026-09-04)
#
# 실증(2026-09-03): rf_append_attempt 가 B1_1 을 세 번 거부했다(사유 = 그날 도훈이 해제한
#   root_papers 의무). 병렬 러너는 그 칸만 조용히 빼고 계속 돌았는데, 커서가
#   `cells[[attempts_used + 1L]]` — 개수라서 격자 위치가 그때부터 영구히 어긋났다.
#   결과: B1_1 영영 미측정 · B1_5 두 번 소각 · spec 파일이 셀 코드 이름이라 재실행분이
#   원본을 덮었고, RP_20260903_105808_combo 는 승자 B1_5(t 1.578·5팩터)의 스펙이
#   1팩터(t 1.025)로 바뀐 채 B2~B4 20칸이 그 위에 섰다.
#
# 이 검사는 **양방향**이다 — 정상 진행이 그대로인지(회귀) + 등록 누락을 주입했을 때
#   구판이 저지른 오답(다음 칸으로 미끄러짐)을 실제로 잡는지.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
eq <- function(m, a, b) if (identical(a, b)) ok(m) else ng(m, sprintf("got=%s want=%s", paste(a, collapse=","), paste(b, collapse=",")))

PROG  <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
CELLS <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))
codes <- vapply(CELLS, function(c) as.character(c$code), character(1))
cat(sprintf("=== 격자 %d칸 (%s …) ===\n", length(CELLS), paste(head(codes, 3), collapse = ",")))

cat("\n=== A. 좌표 출처 우선순위 ===\n")
eq("A1 등록 필드(cell_code) 가 1순위",
   .rf_attempt_code(list(n = 1L, cell_code = "B3_11", essence = list(cell_code = "B1_1"), idea = "[무인 병렬 B2_6]"), CELLS), "B3_11")
eq("A2 등록 필드 없으면 essence",
   .rf_attempt_code(list(n = 1L, essence = list(cell_code = "B1_2"), idea = "[무인 병렬 B1_9]"), CELLS), "B1_2")
eq("A3 둘 다 없으면 서술 접두(구 레코드)",
   .rf_attempt_code(list(n = 1L, idea = "[무인 병렬 B5_17] 오버레이"), CELLS), "B5_17")
eq("A4 셋 다 없으면 격자 위치(최후 폴백)",
   .rf_attempt_code(list(n = 3L), CELLS), codes[3])
eq("A5 아무것도 없으면 NA (자리를 지어내지 않는다)",
   .rf_attempt_code(list(), NULL), NA_character_)

cat("\n=== B. 커서 — 정상 진행(회귀) ===\n")
mk <- function(n, code) list(n = n, cell_code = code, essence = list(cell_code = code, port_t = 0.1))
att5 <- lapply(seq_len(5L), function(i) mk(i, codes[i]))
free5 <- .rf_free_cells(CELLS, att5)
eq("B1 5칸 소비 후 첫 빈 칸 = 6번째 셀", codes[free5[1]], codes[6])
eq("B2 빈 칸 수 = 격자 - 소비", length(free5), length(CELLS) - 5L)
eq("B3 소비한 코드는 빈 칸 목록에 없다", any(codes[free5] %in% codes[1:5]), FALSE)

cat("\n=== C. 위반 주입 — 등록 1건 누락(실사고 재현) ===\n")
# 09-03 실사고 형태: B1_1 이 거부돼 등록 안 됨. 나머지 4칸은 n=1..4 로 밀려 기록.
att_gap <- list(mk(1L, "B1_2"), mk(2L, "B1_3"), mk(3L, "B1_4"), mk(4L, "B1_5"))
fg <- .rf_free_cells(CELLS, att_gap)
eq("C1 빠진 칸(B1_1)을 커서가 되찾는다", codes[fg[1]], "B1_1")
if (!("B1_5" %in% codes[fg])) ok("C2 이미 잰 B1_5 를 다시 잡지 않는다(중복 소각 차단)") else
  ng("C2 이미 잰 B1_5 를 다시 잡지 않는다", "B1_5 가 빈 칸으로 나온다")
# ★음성 대조 — 구판(개수) 커서였다면 무엇을 골랐겠는가. 이 줄이 검사의 판별력이다.
old_pick <- codes[length(att_gap) + 1L]
if (identical(old_pick, "B1_5")) ok(sprintf("C3 구판 개수 커서는 %s 를 골랐다 — 검사가 실제 오답을 가른다", old_pick)) else
  ng("C3 구판 오답 재현", sprintf("old_pick=%s (실사고와 다름 — 격자가 바뀌었는지 확인)", old_pick))

cat("\n=== D. 실측 원장 재현 (RP_20260903_105808_combo) ===\n")
led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE), error = function(e) NULL)
E <- if (is.null(led)) NULL else Filter(function(e) identical(e$base_id, "RP_20260903_105808_combo"), led$entries)
if (!length(E)) cat("  SKIP 실사고 entry 부재(사료 정리됨)\n") else {
  tk <- .rf_taken_codes(E[[1]]$attempts, CELLS)
  if (!("B1_1" %in% tk)) ok("D1 실측: B1_1 은 끝내 자리를 못 잡았다(피해 확인)") else ng("D1 실측 B1_1 미등록", "이미 등록됨")
  if (length(tk) < length(E[[1]]$attempts)) ok(sprintf("D2 실측: 시도 %d건이 코드 %d개 — 중복 소각 %d칸",
      length(E[[1]]$attempts), length(tk), length(E[[1]]$attempts) - length(tk))) else
    ng("D2 중복 소각 검출", "코드 수와 시도 수가 같다")
}

cat("\n=== E. 원장 writer — 좌표를 등록 시점에 남기는가 (격리 사본) ===\n")
TMP <- file.path(tempdir(), sprintf("rf_cursor_%s", format(Sys.time(), "%H%M%S")))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
invisible(capture.output(suppressMessages(
  rf_open_entry(1L, "TEST_CURSOR", "C", paper_key = "test", root = TMP))))
invisible(capture.output(suppressMessages(
  rf_append_attempt(1L, "TEST_CURSOR", "테스트 시도", "multifactor",
                    list(list(url = "https://example.org/x")), root = TMP, cell_code = "B1_3"))))
invisible(capture.output(suppressMessages(
  rf_append_attempt(1L, "TEST_CURSOR", "좌표 미지정 시도", "multifactor",
                    list(list(url = "https://example.org/y")), root = TMP))))
o  <- fromJSON(file.path(TMP, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
at <- Filter(function(e) identical(e$base_id, "TEST_CURSOR"), o$entries)[[1]]$attempts
eq("E1 cell_code 가 원장에 남는다", as.character(at[[1]]$cell_code), "B1_3")
eq("E2 미지정이면 NA — 구 호출자 호환(거부 아님)", is.na(at[[2]]$cell_code %||% NA), TRUE)
eq("E3 좌표 집합이 등록만으로 선다(측정 전)", .rf_taken_codes(at[1], CELLS), "B1_3")
unlink(TMP, recursive = TRUE, force = TRUE)

cat("\n=== F. 러너 배선 — 개수 커서 잔존 0 ===\n")
for (f in c("02_Infrastructure/ops/reinforce_auto_parallel.R", "02_Infrastructure/ops/reinforce_auto_run.R")) {
  # ★주석을 걷어내고 본다 — 이 수리의 **사연을 적은 주석**이 구판 표현을 그대로 담고 있어,
  #   문자열 존재로만 재면 검사가 자기 설명문에 발화한다(잴 것을 안 재고 재기 쉬운 것을 잼).
  src <- paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
  b <- basename(f)
  if (grepl(".rf_free_cells", src, fixed = TRUE)) ok(sprintf("F %s — 코드 기반 커서 사용", b)) else
    ng(sprintf("F %s — 코드 기반 커서", b))
  if (grepl("cells[[used + 1L]]", src, fixed = TRUE)) ng(sprintf("F %s — 구판 개수 커서 잔존", b)) else
    ok(sprintf("F %s — 개수 커서 잔존 없음", b))
  if (grepl("cell_code = CELL$code", src, fixed = TRUE)) ok(sprintf("F %s — 등록에 좌표 전달", b)) else
    ng(sprintf("F %s — 등록에 좌표 전달", b))
}
src <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE), collapse = "\n")
if (grepl("halt_append_stuck", src, fixed = TRUE)) ok("F 등록 반복 거부에 출구가 있다(결정론적 실패 정지)") else
  ng("F 등록 반복 거부 상한")

cat("\n=== G. 블록 경계 — 개수가 아니라 격자에서 재도출하는가 ===\n")
# 실사고 2026-09-04 12:10: 커서를 코드 기반으로 고쳤는데 **알림 층에는 개수 판정이 남아 있었다**.
#   조건이 `u2 %% 5L == 0L` 이라, B1 설계가 14칸이 되자 5칸·10칸(블록 한가운데)에 쏘고
#   14칸(진짜 경계)에는 안 쐈다 — 그 블록의 텔레그램과 L-code 가 통째로 증발했다.
#   같은 병이 층을 옮겨 살아남는다: 한 곳을 고칠 때 같은 판정 축을 쓰는 다른 곳을 함께 봐야 한다.
.par <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"),
                                        warn = FALSE)), collapse = "\n")
if (grepl("u2 %% 5L == 0L", .par, fixed = TRUE))
  ng("G1 알림이 아직 개수(%%5)로 경계를 판정한다", "가변 길이 블록에서 어긋난다") else
  ok("G1 개수 기반 경계 판정 잔존 없음")
if (grepl(".blk_left", .par, fixed = TRUE) && grepl(".rf_free_cells(cells, E2$attempts", .par, fixed = TRUE))
  ok("G2 블록 잔여 칸을 격자에서 재도출") else ng("G2 격자 재도출 부재")

# 로직 재도출 — 가변 길이 블록(B1 14칸)에서 중간과 끝을 구분하는가
.mk14 <- c(lapply(seq_len(14L), function(i) list(code = sprintf("B1_%d", i), block = "B1")),
           lapply(6:10, function(i) list(code = sprintf("B2_%d", i), block = "B2")))
.att <- function(k) lapply(seq_len(k), function(i) list(n = i, cell_code = sprintf("B1_%d", i)))
.left <- function(k) { fr <- .rf_free_cells(.mk14, .att(k))
                       sum(vapply(.mk14[fr], function(c) identical(c$block, "B1"), logical(1))) }
if (.left(10L) > 0L) ok(sprintf("G3 10칸 소비 = 블록 한가운데(잔여 %d) — 안 쏜다", .left(10L))) else
  ng("G3 10칸을 경계로 오판")
if (.left(14L) == 0L) ok("G4 14칸 소비 = 블록 경계(잔여 0) — 여기서 쏜다") else
  ng("G4 14칸을 경계로 못 본다", sprintf("잔여 %d", .left(14L)))
if (.left(5L) > 0L) ok("G5 5칸도 한가운데 — 구판이 여기서 쐈다") else ng("G5 5칸 오판")


cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_grid_cursor","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
