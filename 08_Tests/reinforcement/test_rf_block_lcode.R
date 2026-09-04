#==============================================================================
# test_rf_block_lcode.R — 블록 L-code 무인 발행 검사 (2026-08-30)
#
# 왜: SKILL §0 이 "블록당 L-code 1건" 을 규정했는데 러너에 소비자가 없어서(emit_lcode 0건)
#   세션이 안 오면 학습이 증발했다. 그리고 구 L-code 다수가 record_type="process" 로
#   적립돼 **등급 기반 집계에서 성과로 안 잡혔다**. 둘 다 조용한 실패라 검사로 박아둔다.
# 부작용 없음: dry_run 으로만 발행한다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

led <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
act <- Filter(function(e) identical(e$status, "active"), led$entries)
if (!length(act)) {
  writeLines("  SKIP  active entry 없음 — 발행 경로를 실측할 대상이 없다")
} else {
  E <- act[[1]]
  # ★진행 중 블록을 집으면 "발행 실패" 로 오탐한다 — 등급이 찍힌 칸만 세서 마지막
  #   **완료된** 블록 경계를 고른다(2026-08-30: B3 가 도는 중에 이 검사가 붉게 떴다).
  # ★완료 블록은 **기록된 셀 코드**에서 고른다 (2026-09-04). 구판은 `done %/% 5 * 5` —
  #   블록이 5칸이라는 가정이었다. B1 이 설계에 따라 가변 길이(실측 14칸)가 된 순간 틀린다:
  #   done=14 -> nb=10 -> 격자 2번째 블록(B2) 의 L-code 를 찾아 "적립 파일 부재" 오탐을 냈다.
  #   같은 개수 가정이 커서 · 알림 · 이 검사까지 **세 층**에 있었다. 판정 축은 하나여야 한다:
  #   "그 블록의 칸이 전부 기록됐는가".
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
  .prog0 <- tryCatch(jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE),
                     error = function(e) NULL)
  .cells <- if (is.null(.prog0)) list() else
    do.call(c, lapply(.prog0$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c })))
  # B1 설계가 있으면 러너가 쓰는 격자와 같아야 한다 — 아니면 이 검사가 다른 격자를 본다
  .dz <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), local = TRUE))
                    rf_b1_design_cells(E$base_id, root = ROOT) }, error = function(e) NULL)
  if (length(.dz))
    .cells <- c(lapply(.dz, function(c) { c$block <- "B1"; c }),
                Filter(function(c) !identical(as.character(c$block %||% ""), "B1"), .cells))
  .graded <- Filter(function(a) isTRUE((a$grade %||% "") %in% c("A", "B", "C", "F")), E$attempts %||% list())
  .rec <- vapply(.graded, function(a) as.character(a$cell_code %||% (a$essence$cell_code %||% "")), character(1))
  .rec <- .rec[nzchar(.rec)]
  .done_blocks <- Filter(function(bid) {
    cc <- vapply(Filter(function(c) identical(as.character(c$block %||% ""), bid), .cells),
                 function(c) as.character(c$code), character(1))
    length(cc) > 0L && all(cc %in% .rec)
  }, unique(vapply(.cells, function(c) as.character(c$block %||% ""), character(1))))
  nb <- 0L; .bid <- ""
  if (length(.done_blocks)) {
    .bid <- .done_blocks[[length(.done_blocks)]]
    .ns <- vapply(.graded, function(a) {
      cc <- as.character(a$cell_code %||% (a$essence$cell_code %||% ""))
      if (nzchar(cc) && identical(sub("_.*$", "", cc), .bid)) as.integer(a$n %||% 0L) else NA_integer_
    }, integer(1))
    nb <- suppressWarnings(max(.ns, na.rm = TRUE))
  }
  if (!length(.done_blocks) || !is.finite(nb) || nb < 1L) {
    writeLines("  SKIP  완료된 블록 없음")
  } else {
    r <- rf_emit_block_lcode(E$base_id, nb, root = ROOT, dry_run = TRUE)
    if (!is.null(r)) ok(sprintf("블록 n=%d dry_run 발행", nb)) else ng("dry_run 발행 실패")
    # 실제 적립분에서 계약 2종을 재도출한다 — 진술이 아니라 파일에서
    # ★블록 id 는 **격자 순서**에서 읽는다(발행기 rf_emit_block_lcode 와 같은 규칙). 구판은 sprintf("B%d", nb/5) 로
    #   위치=번호를 가정했는데 2026-09-01 재편으로 순서가 B1→B2→B3→B5→B4 가 되자 4번째 완료 블록(B5) 을
    #   B4 로 찾아 "적립 파일 부재" 오탐을 냈다(2026-09-02 실측). SKILL: 위치 의존 판정은 격자를 손보는 순간 어긋난다.
    # .bid 는 위에서 **기록된 코드**로 이미 정해졌다 — 위치(nb %/% 5)로 되짚지 않는다.
    f <- file.path(ROOT, "stage_artifacts/l_code/reinforcement",
                   sprintf("l_code_%s_%s.json", E$base_id, .bid))
    if (file.exists(f)) {
      d <- jsonlite::fromJSON(f, simplifyVector = TRUE)
      if (identical(d$record_type, "performance")) ok("record_type=performance (등급 집계에 잡힌다)")
      else ng("record_type", paste(d$record_type, "— 성과 기록으로 안 잡힌다"))
      np <- unlist(strsplit(paste(d$next_probe, collapse = " | "), " | ", fixed = TRUE))
      np <- np[nzchar(trimws(np))]
      if (length(np) >= 2L) ok(sprintf("next_probe %d건 (C/F 연속성 계약 >=2)", length(np)))
      else ng("next_probe", sprintf("%d건 — 연속성 계약 미달", length(np)))
      # ★근거 논문 의무는 **강화 레인에 한해** 2026-09-03 도훈이 해제했다
      #   (CLAUDE.md · lean-loop.md §하지 않는 것). 축의 정당성은 격자와 팩터 등록부가 진다.
      #   구판은 `source_paper` 부재를 실패로 봤는데, 이 검사는 오랫동안 skip 상태라
      #   규칙이 폐지된 뒤에도 아무도 못 봤다. 대신 **레인 식별**을 잰다 —
      #   이게 없으면 이 기록이 강화 산출인지 충실구현 산출인지 구분되지 않는다.
      #   ★충실구현·2계층의 근거 의무는 불변이므로 그쪽 검사에서 따로 잰다.
      if (identical(as.character(d$research_mode), "reinforcement"))
        ok("research_mode=reinforcement (강화 레인 — 근거 논문 의무 해제 대상)")
        else ng("research_mode", sprintf("%s — 레인 식별 불가", d$research_mode %||% "결측"))
    } else ng("적립 파일 부재", f)
  }
}

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
# ★단정 0건은 '통과' 가 아니라 skipped 다 — 원장에 완료 블록이 없으면 잴 대상이 없다.
.skip <- if (PASS + FAIL == 0L) 1L else 0L
cat(sprintf('{"test":"rf_block_lcode","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n',
            PASS, FAIL, PASS + FAIL, .skip))
if (FAIL > 0L) quit(status = 1L)
