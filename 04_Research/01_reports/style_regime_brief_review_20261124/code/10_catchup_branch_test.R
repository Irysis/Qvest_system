## 10_catchup_branch_test.R — ff5_brief_send.R v4.1 kf_catchup() 분기 시험(운영 .cache 무접촉 · 임시 루트)
##   경우: fresh(정본 = RAWDATA) · 드라이런 생략 · 샌드박스(DATA ≠ ROOT) 생략 · RAWDATA 판독 불가 ·
##         낡음 → 배리어 free → 메모리 관문(가용 고정 주입) 통과 → 빌더 실패(임시 루트엔 입력 없음) → 'failed' ·
##         낡음 → 메모리 관문 대기(가용 고정 주입) → 'mem_wait'
suppressMessages({ library(arrow); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE); SEND <- a[1]; PROD <- a[2]
T <- file.path(tempdir(), sprintf("kfc_%d", Sys.getpid())); dir.create(file.path(T, ".cache"), recursive = TRUE)
dir.create(file.path(T, "02_Infrastructure/ops"), recursive = TRUE); dir.create(file.path(T, "06_Registry"))
for (f in c("02_Infrastructure/ops/refresh_barrier.R", "02_Infrastructure/ops/refresh_barrier.sh", "02_Infrastructure/ops/mem_gate.py",
            "06_Registry/memory_policy.json")) file.copy(file.path(PROD, f), file.path(T, f))
dir.create(file.path(T, ".cache/scheduler_logs"))
ex <- parse(file = SEND, encoding = "UTF-8", keep.source = FALSE)
for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && as.character(e[[2]]) %in% c("kf_catchup", "%||%")) eval(e, globalenv())
skip_build <- function(k) FALSE
put <- function(meta_last, rd_last) {
  write_json(list(last_input_date = meta_last), file.path(T, ".cache/kr_factor_returns_meta.json"), auto_unbox = TRUE)
  if (is.null(rd_last)) unlink(file.path(T, ".cache/rawdata.parquet")) else
    write_parquet(data.frame(Date = as.Date(c("2026-11-20", rd_last))), file.path(T, ".cache/rawdata.parquet"))
}
run <- function(label, expect, ...) {
  env <- list(...); for (n in names(env)) assign(n, env[[n]], envir = globalenv())
  r <- kf_catchup(); ok <- identical(r$state, expect)
  cat(sprintf("  %s %-44s → %-8s %s\n", if (ok) "OK  " else "FAIL", label, r$state, r$note)); ok
}
ROOT <- T; DATA <- T; DRYRUN <- FALSE
res <- c(
  { put("2026-11-23", "2026-11-23"); run("신선(정본 = RAWDATA)", "fresh") },
  { put("2026-11-20", "2026-11-23"); run("낡음 · 드라이런 → 운영 쓰기 생략", "skipped", DRYRUN = TRUE) },
  { put("2026-11-20", "2026-11-23"); run("낡음 · 샌드박스(DATA ≠ ROOT) → 생략", "skipped", DRYRUN = FALSE, DATA = file.path(T, "sbx")) },
  { put("2026-11-20", NULL); run("RAWDATA 판독 불가", "unknown", DATA = T) },
  { Sys.setenv(MG_AVAIL_MB = "2000"); put("2026-11-20", "2026-11-23"); run("낡음 · 메모리 부족(가용 2 GB 주입) → 대기", "mem_wait") },
  { Sys.setenv(MG_AVAIL_MB = "30000"); put("2026-11-20", "2026-11-23"); run("낡음 · 관문 통과 → 빌더 실패(입력 없음) → failed", "failed") })
Sys.unsetenv("MG_AVAIL_MB")
cat(sprintf("합계: 통과 %d / %d\n", sum(res), length(res)))
unlink(T, recursive = TRUE)
quit(status = if (all(res)) 0L else 1L)
