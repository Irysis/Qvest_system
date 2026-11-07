## heavy_round_core_v1_p2_rejudge.R — 끝난 라운드 결과 동일 재판정(무거움 — 원자료 적재 · 패킷 · MC8 · SUITES 밖 · 수동 실행)
##   P2R04 → P2R03 → P3R03 을 각 등록 커밋의 핀 판 재현 루트 위에서 코어(round_core v1)로 다시 판정하고, 라운드 결과 폴더의 저장본과 대조한다.
##   저장된 칸 산출(results/<칸> · stage_artifacts/replication)은 읽기만 · 재판정 출력은 작업 디렉터리(스크래치)에 · 역사 수치 무수정.
##   공용 무거운 작업 자리(qm_heavy_slot.lock)는 run_rejudge.sh 가 잡는다(--slot-held = 호출자가 이미 잡음).
## 사용: QM_ROOT=<이 저장소> Rscript 08_Tests/programs/heavy_round_core_v1_p2_rejudge.R <작업 디렉터리> [--slot-held] [--rounds P2R04,P2R03,P3R03]
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/ops/qv_bash.R"))   # bare "bash" 금지(금칙 ⑦ · 11-07) — WSL 있는 PC 에선 System32 bash 가 PATH 보다 먼저 잡힌다
a <- commandArgs(trailingOnly = TRUE)
WORK <- gsub("\\\\", "/", a[1]); if (is.na(WORK)) stop("usage: heavy_round_core_v1_p2_rejudge.R <작업 디렉터리> [--slot-held]")
MAIN <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"                          # 저장된 칸 산출(읽기만 — 결과 폴더는 git 밖 산출을 담는다)
RJ <- file.path(ROOT, "04_Research/programs/_lib/round_core/rejudge")
i <- match("--rounds", a); ROUNDS <- if (is.na(i)) c("P2R04", "P2R03", "P3R03") else strsplit(a[i + 1L], ",")[[1]]
DEF <- list(P2R04 = list(rd = "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings", pre = "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json", commit = "a32201675"),
            P2R03 = list(rd = "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay", pre = "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json", commit = "9bb76f972"),
            P3R03 = list(rd = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction", pre = "stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json", commit = "c7166d2ca"))
dir.create(WORK, recursive = TRUE, showWarnings = FALSE)
for (r in ROUNDS) {
  d <- DEF[[r]]; rr <- file.path(WORK, "repro", r)
  if (!dir.exists(rr)) {
    rc <- system2("Rscript", c(file.path(RJ, "make_repro_root.R"), ROOT, d$rd, d$pre, d$commit, rr))
    if (!identical(as.integer(rc), 0L)) stop("재현 루트 실패: ", r)
  }
  do.call(Sys.setenv, setNames(list(rr, file.path(MAIN, d$rd, "results")), c(paste0("RC_REPRO_", r), paste0("RC_RES_", r))))
}
Sys.setenv(RC_CORE_ROOT = ROOT, RC_SLOT_HELD = if ("--slot-held" %in% a) "1" else "0")
rc <- system2(qv_bash(), c(file.path(RJ, "run_rejudge.sh"), file.path(WORK, "out"), ROUNDS))
if (!identical(as.integer(rc), 0L)) stop("재판정 실행 실패 rc=", rc)
sm <- system2("Rscript", c(file.path(RJ, "summarize.R"), file.path(WORK, "out"), file.path(RJ, "RESULTS.json"),
                           vapply(ROUNDS, function(r) sprintf("%s=%s", r, file.path(MAIN, DEF[[r]]$rd, "results")), "")), stdout = TRUE, stderr = TRUE)
cat(sm, sep = "\n")
J <- jsonlite::fromJSON(file.path(RJ, "RESULTS.json"), simplifyVector = FALSE)
PASS <- 0L; FAIL <- 0L
for (r in ROUNDS) { x <- J$rounds[[r]]; ok <- isTRUE(x$verdict_same) && isTRUE(x$cell_verdicts_same) && isTRUE(x$key_numbers_same)
  if (ok) PASS <- PASS + 1L else FAIL <- FAIL + 1L
  cat(sprintf("  [%s] %s 판정 %s / %s · 칸 판정 %s · 핵심 수치 %s · 구조 차이 %s · 패킷 %s/%s\n", if (ok) "ok" else "FAIL", r, x$verdict_stored, x$verdict_core,
              x$cell_verdicts_same, x$key_numbers_same, x$n_structural_diffs, x$packets_same, x$packets_compared)) }
cat(sprintf('{"test":"round_core_v1_p2_rejudge","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
