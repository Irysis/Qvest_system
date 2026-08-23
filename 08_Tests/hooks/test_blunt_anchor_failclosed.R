## test_blunt_anchor_failclosed.R — extend_nolayer4_series.R 2c fail-closed 위반 주입 테스트
##
## 대상 계약: 신규월에 배포 manifest 가 없고(앵커 불가) ∧ 그 달 β 가 z 결측으로 무뎌졌으면
##            원장에 틀린 값이 기록되므로 **중단**한다. 그 외에는 통과한다(오탐 금지).
##
## ★검사 설계: 조건 로직을 복제해서 재지 않는다 — 실제 스크립트를 돌려 종료코드로 판정한다.
##   (복제 검사는 대상이 바뀌어도 계속 통과하는 죽은 검사가 되기 쉽다)
##
## ★★2026-08-08 초판 결함 수리 — 이 파일이 실제로 패널을 오염시켰다.
##   초판은 최상위에서 `on.exit(restore())` 를 썼다. r-portability.md 금칙 ②(최상위 on.exit 미발화)
##   그대로다 — 정확히는 **조기 발화**해 백업을 먼저 지워버렸고, 끝에서 부른 restore() 는
##   백업이 없어 아무것도 못 했다. 결과: 마지막 주입분(n_R05_valid=20, z_avg=NaN)이 패널에 잔존
##   → 재생성(run_layer5_rerun_extended.R)으로 복구해야 했다.
##   수리: on.exit 제거 → 전체를 함수로 감싸고 `tryCatch(finally=)` 로 원복 보장 + **원복 검증까지 채점**.
suppressPackageStartupMessages(library(data.table))

`%||%` <- function(a, b) if (is.null(a)) b else a

## ★★★2026-08-24 v9.2 S1a — 이 파일이 만든 **두 번째** 오염과 그 수리
##   사건: live_book_series.csv 가 546줄로 발견됐다(정상 272줄 블록 2벌 + 640B 조각).
##   이 파일이 최종 기록자였다 — 운영 원본을 직접 조작하고 생산자를 5회 돌리는데
##   ① 백업 경로가 **고정**(`.testbak`)이라 두 실행이 겹치면 서로의 백업을 덮어쓰고
##   ② 채점이 PANEL 만 봤다(:96-100) — **원장 원복은 재지 않았다**. 어제 사고가 정확히 그 사각.
##   수리 3종: 백업에 PID 부착 · **원장 md5 채점 추가** · QM_ROOT 샌드박스(운영 원본 무접촉).
##   ★샌드박스는 :6-7 설계축을 지킨다 — 조건 로직을 복제하지 않고 **실제 스크립트를 그대로**
##     돌린다. 바뀌는 것은 스크립트가 읽는 ROOT 뿐이라 코드 경로는 동일하다.
##     (`QVEST_TEST_NO_SANDBOX=1` 로 구 거동 = 운영 원본 직접 조작. 등가 확인용.)

## 샌드박스에 필요한 최소 집합 — 생산자가 실제로 읽는 경로만.
##   부족하면 스크립트가 명시적으로 실패하므로 조용한 오탐이 되지 않는다.
.SANDBOX_FILES <- c(
  "02_Infrastructure/monitoring/extend_nolayer4_series.R",
  "02_Infrastructure/portfolio/resolve_admitted_slot.R",
  "02_Infrastructure/contracts/panel_alignment_guard.R",
  "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv",
  "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds",
  "qepm/mailbox/governor/book_state.json",
  ".cache/indices.parquet")
.SANDBOX_DIRS <- c("06_Registry/live_track", "05_Production/2.Factor_Model")

.build_sandbox <- function(src, dst) {
  unlink(dst, recursive = TRUE, force = TRUE)
  dir.create(dst, recursive = TRUE, showWarnings = FALSE)
  for (rel in .SANDBOX_FILES) {
    s <- file.path(src, rel); if (!file.exists(s)) next
    d <- file.path(dst, rel); dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE)
    file.copy(s, d, overwrite = TRUE)
  }
  for (rel in .SANDBOX_DIRS) {
    s <- file.path(src, rel); if (!dir.exists(s)) next
    d <- file.path(dst, rel); dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE)
    ## 05_Production 은 **읽기만** 한다(복사 = 읽기). 샌드박스 쪽만 쓰기 대상.
    file.copy(s, dirname(d), recursive = TRUE, overwrite = TRUE)
  }
  dir.create(file.path(dst, ".cache"), recursive = TRUE, showWarnings = FALSE)
  ## ★★샌드박스 전용 .Renviron — 이게 없으면 격리가 **조용히 무효**다.
  ##   실측(2026-08-24): `QM_ROOT=<sandbox> Rscript ...` 로 자식을 띄워도 R 은 기동 시
  ##   `~/.Renviron`(QM_ROOT=<운영루트>)을 읽어 **상속값을 덮어쓴다**. 그래서 격리했다고
  ##   믿은 실행이 운영 원장을 계속 기록했다(md5 가 매 실행 바뀌는 것으로 적발).
  ##   ⇒ 원본 .Renviron 을 그대로 복제하되 QM_ROOT 만 샌드박스로 바꾸고,
  ##      자식에게 R_ENVIRON_USER 로 그 파일을 지정한다(다른 변수는 손실 없음).
  ##   ※ R_ENVIRON_USER 는 .Renviron 처리 **이전**에 상속 환경에서 읽히므로 유효하다.
  home_renv <- path.expand("~/.Renviron")
  lines <- if (file.exists(home_renv)) readLines(home_renv, warn = FALSE) else character()
  lines <- lines[!grepl("^\\s*QM_ROOT\\s*=", lines)]
  writeLines(c(lines, paste0("QM_ROOT=", dst)), file.path(dst, ".Renviron"))
  dst
}

main <- function() {
  SRC <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  RS  <- file.path(Sys.getenv("R_HOME", "C:/Program Files/R/R-4.5.2"), "bin/Rscript.exe")
  ISOLATE <- !identical(Sys.getenv("QVEST_TEST_NO_SANDBOX", "0"), "1")
  SBOX <- file.path(SRC, ".cache", sprintf("_test_blunt_anchor_root_%d", Sys.getpid()))
  R <- if (ISOLATE) .build_sandbox(SRC, SBOX) else SRC
  cat(sprintf("[격리] %s (root=%s)\n",
              if (ISOLATE) "샌드박스 — 운영 원본 무접촉" else "★OFF — 운영 원본 직접 조작",
              sub(SRC, "<QM_ROOT>", R, fixed = TRUE)))
  ## 자식 Rscript 가 샌드박스를 ROOT 로 읽게 한다.
  ##   ★QM_ROOT 만 세우면 안 된다 — 자식 R 이 ~/.Renviron 으로 되돌린다(위 주석 참조).
  ##     R_ENVIRON_USER 를 샌드박스 .Renviron 으로 돌려야 실제로 격리된다.
  .old_qm  <- Sys.getenv("QM_ROOT", unset = NA_character_)
  .old_env <- Sys.getenv("R_ENVIRON_USER", unset = NA_character_)
  Sys.setenv(QM_ROOT = R)
  if (ISOLATE) Sys.setenv(R_ENVIRON_USER = file.path(R, ".Renviron"))

  SCRIPT <- file.path(R, "02_Infrastructure/monitoring/extend_nolayer4_series.R")
  PANEL  <- file.path(R, "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
  LEDGER <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
  stopifnot(file.exists(SCRIPT), file.exists(PANEL), file.exists(RS))

  ## ★격리 실효 자체를 잰다 — 격리했다고 **믿는** 것과 격리된 것은 다르다.
  ##   운영 원본의 md5 를 실행 전후로 비교한다. ISOLATE=TRUE 인데 바뀌면 격리 사망이다.
  OPER_LEDGER <- file.path(SRC,
    "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
  OPER_PANEL  <- file.path(SRC,
    "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
  .oper_md5 <- function() unname(tools::md5sum(c(OPER_LEDGER, OPER_PANEL)))
  oper_before <- .oper_md5()

  ## ★백업 경로에 PID — 고정 경로는 겹친 실행이 서로의 백업을 덮어쓴다(어제 사고의 필요조건).
  BK_P <- sprintf("%s.testbak.%d", PANEL, Sys.getpid())
  BK_L <- sprintf("%s.testbak.%d", LEDGER, Sys.getpid())
  stopifnot(file.copy(PANEL, BK_P, overwrite = TRUE))
  had_ledger <- file.exists(LEDGER)
  if (had_ledger) stopifnot(file.copy(LEDGER, BK_L, overwrite = TRUE))

  results <- list()
  ## ★환경 객체(참조 의미론)로 둔다 — finally 가 어느 프레임에서 평가되든 여기에 쓰인다.
  ##   초판은 `<<-` 로 프레임을 건너뛰어 전역에 쓰는 바람에 정상 정리를 FAIL 로 오판했다.
  st <- new.env(parent = emptyenv()); st$restored_ok <- NA

  ## ★2026-08-08 2차 수리 — 초판은 `system2(..., env=)` 였다. r-portability.md 금칙 ①:
  ##   Windows 에서 env= 는 환경변수가 아니라 **인자(argv)로 주입**된다. 즉 케이스 ③ 은
  ##   플래그를 세운 적이 없고 **플래그 없는 상태를 재면서 "우회 통과"라고 이름 붙이고** 있었다.
  ##   수리: Sys.setenv/Sys.unsetenv 로 실제 프로세스 환경에 세우고 원복까지 보장한다
  ##   (자식 Rscript 는 부모 환경을 상속하므로 이 경로가 플랫폼 무관 정본).
  run_script <- function(env = character()) {
    restore <- NULL
    if (length(env)) {
      nm  <- sub("=.*$", "", env); val <- sub("^[^=]*=", "", env)
      old <- Sys.getenv(nm, unset = NA_character_, names = TRUE)
      do.call(Sys.setenv, as.list(setNames(val, nm)))
      restore <- function() {
        for (k in nm) {
          if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(setNames(old[[k]], k)))
        }
      }
      on.exit(restore(), add = TRUE)   # 함수 내부 on.exit = 정상 발화(금칙 ②는 최상위 한정)
    }
    out <- suppressWarnings(system2(RS, c("--no-save", SCRIPT), stdout = TRUE, stderr = TRUE))
    list(rc = attr(out, "status") %||% 0L, txt = paste(out, collapse = "\n"))
  }
  chk <- function(name, expect_block, r) {
    blocked <- r$rc != 0L && grepl("fail-closed", r$txt)
    ok <- identical(blocked, expect_block)
    results[[length(results) + 1L]] <<- data.table(case = name,
        expect = if (expect_block) "차단" else "통과",
        actual = if (blocked) "차단" else "통과", verdict = if (ok) "PASS" else "FAIL")
    cat(sprintf("  [%s] %-48s 기대=%s 실제=%s\n", if (ok) "PASS" else "FAIL", name,
                if (expect_block) "차단" else "통과", if (blocked) "차단" else "통과"))
  }

  tryCatch({
    base <- fread(BK_P)                     # ★주입 원본은 항상 백업에서 (오염 누적 방지)
    cat("=== 위반 주입 테스트: 2c blunt-anchor fail-closed ===\n")

    ## 주입 대상 = 앵커 없는 신규월(=manifest 부재로 WARN 나는 달). 하드코딩 대신 탐색.
    probe <- run_script()
    tgt_ym <- regmatches(probe$txt, regexpr("신규월 [0-9]{4}-[0-9]{2}: 수익월", probe$txt, perl = TRUE))
    tgt_ym <- if (length(tgt_ym)) sub("^신규월 ([0-9-]+):.*$", "\\1", tgt_ym) else NA_character_
    chk("① 무주입 — 정상 통과해야", FALSE, probe)
    if (is.na(tgt_ym) || !nrow(base[realized_ym == tgt_ym])) {
      cat("  [SKIP] 앵커 없는 신규월 부재 — 주입 대상 없음(계약 미시험)\n")
    } else {
      cat(sprintf("  (주입 대상 월: %s)\n", tgt_ym))
      i <- base[realized_ym == tgt_ym, which = TRUE]

      inj <- copy(base); inj[i, R05_z_avg := NaN]
      if ("n_R05_valid" %in% names(inj)) inj[i, n_R05_valid := NA_integer_]
      fwrite(inj, PANEL); chk("② z 신호 결측 주입 — 차단해야", TRUE, run_script())
      chk("③ 우회 플래그(opt-in) — 통과해야", FALSE, run_script(env = "QVEST_ALLOW_BLUNT_ANCHOR=1"))

      inj2 <- copy(base); inj2[, n_R05_valid := 20L]; inj2[i, n_R05_valid := 0L]
      fwrite(inj2, PANEL); chk("④ n_R05_valid=0 주입 — 차단해야", TRUE, run_script())

      inj3 <- copy(base); inj3[, n_R05_valid := 20L]; inj3[i, R05_z_avg := NaN]
      fwrite(inj3, PANEL); chk("⑤ 명시신호 정상 ∧ z_avg NaN — 통과해야(명시 우선)", FALSE, run_script())
    }
  }, finally = {
    ## ★원복은 예외·중단 어느 경로로 빠져도 반드시 실행된다
    if (file.exists(BK_P)) file.copy(BK_P, PANEL, overwrite = TRUE)
    if (had_ledger && file.exists(BK_L)) file.copy(BK_L, LEDGER, overwrite = TRUE)
    st$restored_ok <- file.exists(BK_P) &&
      identical(unname(tools::md5sum(BK_P)), unname(tools::md5sum(PANEL)))
    ## ★★원장 원복도 채점한다 — 2026-08-23 파손이 정확히 이 사각에서 나왔다.
    ##   구판은 원장을 복사만 하고 **결과를 재지 않았다**: 5회 실행이 남긴 원장이
    ##   어떤 모양이든 검사는 초록이었다. 안 재는 것은 안 지키는 것이다.
    st$ledger_ok <- if (!had_ledger) NA else
      (file.exists(BK_L) && file.exists(LEDGER) &&
       identical(unname(tools::md5sum(BK_L)), unname(tools::md5sum(LEDGER))))
    ## 원장 구조 단언(md5 가 같아도 애초에 깨진 상태로 들어왔을 수 있다)
    st$ledger_shape <- tryCatch({
      if (!file.exists(LEDGER)) NA else {
        ln <- readLines(LEDGER, warn = FALSE)
        hdr <- sum(startsWith(ln, "date,realized_ym"))
        d <- data.table::fread(LEDGER)
        hdr == 1L && !any(duplicated(d$date)) && nrow(d) == length(ln) - 1L
      }
    }, error = function(e) FALSE)
    unlink(c(BK_P, BK_L))
    if (ISOLATE) unlink(SBOX, recursive = TRUE, force = TRUE)
    if (is.na(.old_qm))  Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = .old_qm)
    if (is.na(.old_env)) Sys.unsetenv("R_ENVIRON_USER") else Sys.setenv(R_ENVIRON_USER = .old_env)
  })

  ## ★원복 자체를 채점한다 — 초판은 여기서 걸렸을 결함이었다
  results[[length(results) + 1L]] <- data.table(case = "⑥ 정리(원복) — 패널 바이트 원상복구",
      expect = "복구", actual = if (isTRUE(st$restored_ok)) "복구" else "미복구",
      verdict = if (isTRUE(st$restored_ok)) "PASS" else "FAIL")
  cat(sprintf("  [%s] ⑥ 정리(원복) — 패널 바이트 원상복구\n", if (isTRUE(st$restored_ok)) "PASS" else "FAIL"))

  .lo <- if (is.na(st$ledger_ok)) TRUE else isTRUE(st$ledger_ok)
  results[[length(results) + 1L]] <- data.table(case = "⑦ 정리(원복) — 원장 md5 원상복구",
      expect = "복구", actual = if (is.na(st$ledger_ok)) "원장부재(N/A)" else if (.lo) "복구" else "미복구",
      verdict = if (.lo) "PASS" else "FAIL")
  cat(sprintf("  [%s] ⑦ 정리(원복) — 원장 md5 원상복구%s\n", if (.lo) "PASS" else "FAIL",
              if (is.na(st$ledger_ok)) " (원장 부재 — N/A)" else ""))

  .ls <- if (is.na(st$ledger_shape)) TRUE else isTRUE(st$ledger_shape)
  results[[length(results) + 1L]] <- data.table(case = "⑧ 원장 구조 — 헤더1 ∧ date중복0 ∧ 줄수정합",
      expect = "정상", actual = if (.ls) "정상" else "파손", verdict = if (.ls) "PASS" else "FAIL")
  cat(sprintf("  [%s] ⑧ 원장 구조 — 헤더1 ∧ date중복0 ∧ 줄수정합\n", if (.ls) "PASS" else "FAIL"))

  ## ★⑨ 격리 실효 — 이 검사가 없으면 '격리했다'가 주장으로만 남는다.
  ##   2026-08-24 실측: ~/.Renviron 이 자식의 QM_ROOT 를 되돌려 격리가 무효였는데
  ##   ①⑥⑦⑧ 은 전부 PASS 였다. 즉 다른 항목으로는 격리 사망이 안 보인다.
  .iso <- if (!ISOLATE) NA else identical(oper_before, .oper_md5())
  .iso_ok <- if (is.na(.iso)) TRUE else isTRUE(.iso)
  results[[length(results) + 1L]] <- data.table(case = "⑨ 격리 실효 — 운영 원본 md5 무변경",
      expect = if (ISOLATE) "무변경" else "격리OFF(N/A)",
      actual = if (is.na(.iso)) "격리OFF(N/A)" else if (.iso_ok) "무변경" else "★변경됨",
      verdict = if (.iso_ok) "PASS" else "FAIL")
  cat(sprintf("  [%s] ⑨ 격리 실효 — 운영 원본 md5 무변경%s\n", if (.iso_ok) "PASS" else "FAIL",
              if (is.na(.iso)) " (QVEST_TEST_NO_SANDBOX=1 — N/A)" else ""))

  res <- rbindlist(results)
  cat(sprintf("\n[결과] %d/%d PASS\n", sum(res$verdict == "PASS"), nrow(res)))
  # 2026-08-20: 배터리 요약. 카운터가 아니라 res 데이터프레임의 verdict 열이 원천이라
  #   요약 cat 과 **같은 식**을 쓴다(별도 집계를 만들면 두 수가 갈릴 수 있다).
  cat(sprintf("{\"test\":\"test_blunt_anchor_failclosed\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
              sum(res$verdict == "PASS"), sum(res$verdict != "PASS"), nrow(res)))
  print(res)
  if (any(res$verdict == "FAIL")) return(1L)
  cat("[OK] 차단 실효 확인 — 위반 주입 시 발화, 정상 시 미발화, 정리 무손상\n")
  0L
}

.rc <- main()
if (!interactive() && identical(.rc, 1L)) quit(status = 1)
