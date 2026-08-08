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

main <- function() {
  R  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  RS <- file.path(Sys.getenv("R_HOME", "C:/Program Files/R/R-4.5.2"), "bin/Rscript.exe")
  SCRIPT <- file.path(R, "02_Infrastructure/monitoring/extend_nolayer4_series.R")
  PANEL  <- file.path(R, "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
  LEDGER <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
  stopifnot(file.exists(SCRIPT), file.exists(PANEL), file.exists(RS))

  BK_P <- paste0(PANEL, ".testbak"); BK_L <- paste0(LEDGER, ".testbak")
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
    unlink(c(BK_P, BK_L))
  })

  ## ★원복 자체를 채점한다 — 초판은 여기서 걸렸을 결함이었다
  results[[length(results) + 1L]] <- data.table(case = "⑥ 정리(원복) — 패널 바이트 원상복구",
      expect = "복구", actual = if (isTRUE(st$restored_ok)) "복구" else "미복구",
      verdict = if (isTRUE(st$restored_ok)) "PASS" else "FAIL")
  cat(sprintf("  [%s] ⑥ 정리(원복) — 패널 바이트 원상복구\n", if (isTRUE(st$restored_ok)) "PASS" else "FAIL"))

  res <- rbindlist(results)
  cat(sprintf("\n[결과] %d/%d PASS\n", sum(res$verdict == "PASS"), nrow(res)))
  print(res)
  if (any(res$verdict == "FAIL")) return(1L)
  cat("[OK] 차단 실효 확인 — 위반 주입 시 발화, 정상 시 미발화, 정리 무손상\n")
  0L
}

.rc <- main()
if (!interactive() && identical(.rc, 1L)) quit(status = 1)
