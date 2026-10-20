## 끝난 라운드 재판정(결과 동일 실증) — 저장된 칸 산출(results/<칸> · stage_artifacts/replication)을 코어(round_core v1)로 다시 판정한다.
##   읽기만: 저장된 칸 평가 · 셀 로그 · 측정 json · 지문 · 산출물. 쓰기 = --out(스크래치)뿐 — 라운드 결과 폴더 · 역사 수치는 고치지 않는다.
##   계약 = --root(등록 커밋 핀 판 재현 루트 · 핀 재대조 통과해야 판정) · 코어 = 이 저장소 v1.
## 사용: Rscript rejudge.R <P2R04|P2R03|P3R03> --root <재현 루트> --res <저장 칸 산출 디렉터리> --out <출력> [--shard=i/K | --merge]
##       [--minimal 0|1] [--memo 0|1] [--mc8 0|1] [--rawdisk 0|1] [--perf <json>]
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 1L) stop("usage: rejudge.R <round> --root <dir> --res <dir> --out <dir> [--shard=i/K | --merge]")
opt <- function(k, d = NULL) { i <- match(k, a); if (is.na(i) || i == length(a)) d else a[i + 1L] }
round <- a[1]; root <- gsub("\\\\", "/", opt("--root")); res <- gsub("\\\\", "/", opt("--res")); out <- gsub("\\\\", "/", opt("--out"))
shard <- sub("^--shard=", "", grep("^--shard=", a, value = TRUE)[1]); if (is.na(shard)) shard <- NULL
merge <- "--merge" %in% a
flag <- function(k, d) { v <- opt(k, NA_character_); if (is.na(v)) d else identical(v, "1") }
WT <- gsub("\\\\", "/", Sys.getenv("RC_CORE_ROOT", ""))                          # 코어 · 확장을 읽는 저장소(이 worktree)
if (!nzchar(WT)) stop("RC_CORE_ROOT(코어 저장소) 환경 변수가 필요하다")
Sys.setenv(QM_ROOT = root, CLAUDE_PROJECT_DIR = root)                            # 계약의 루트 해석(.mc_root · .dp_root · .ma_root) = 재현 루트
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
dth <- suppressWarnings(as.integer(Sys.getenv("RC_DT_THREADS", "")))            # 속도 실험 손잡이(스레드 수는 결과를 바꾸지 않는다 — 재판정 바이트 대조로 확인)
if (is.finite(dth) && dth >= 1L) data.table::setDTthreads(dth) else if (!is.null(shard)) data.table::setDTthreads(1L)   # 기본: 샤드 워커 1스레드(PERFORMANCE.md) · 단일 = 기본값
source(file.path(WT, "04_Research/programs/_lib/round_core/v1/load.R"))
src <- function(f) sys.source(file.path(WT, "04_Research/programs/_lib/round_core/rejudge", f), envir = globalenv())
pe <- new.env()
t0 <- Sys.time()
dir.create(out, recursive = TRUE, showWarnings = FALSE)
common <- list(minimal_copy = flag("--minimal", FALSE), memo = flag("--memo", FALSE), mc8_memo = flag("--mc8", FALSE), raw_disk_cache = flag("--rawdisk", FALSE))
r <- switch(round,
  P2R04 = { src("P2R04_ext.R"); R <- do.call(p2r04_R, c(list(root = root, res = res, out = out, perf_env = pe), common)); rc_p2_round(R, P2R04_T, shard = shard, merge = merge) },
  P2R03 = { src("P2R03_ext.R"); R <- do.call(p2r03_R, c(list(root = root, res = res, out = out, perf_env = pe), common)); p2r03_round(R, P2R03_T, shard = shard, merge = merge) },
  P3R03 = { src("P3R03_ext.R"); R <- do.call(p3r03_R, c(list(root = root, res = res, out = out, perf_env = pe), common)); R$check_pins <- TRUE; rc_p3_round(R, P3R03_T, shard = shard, merge = merge) },
  stop("모르는 라운드: ", round))
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
## P2R04 — 같은 판정을 rules.R 선언(rules_p2 종류)으로 다시 내 단계 판정과 칸마다 대조(선언 = 단계 · 실데이터 확인) → rules_crosscheck.json
if (identical(round, "P2R04") && is.list(r) && !is.null(r$OUT)) {
  rr <- rc_rules_resolve(p2r04_rules(R$pre[["final_selection_rule"]]), root); rc_p2_rules_tau_check(rr)
  cc <- rc_p2_rules_crosscheck(rr, r$OUT, r$EVS, p2r04_rules_map)
  writeLines(toJSON(list(ok = cc$ok, mismatches = cc$mismatches, sentences = as.list(rc_rules_sentences(rr)), table = cc$table), auto_unbox = TRUE, pretty = TRUE,
                    null = "null", na = "null", digits = NA), file.path(out, "rules_crosscheck.json"), useBytes = TRUE)
  cat(sprintf("[rejudge] P2R04 선언 규칙 = 단계 판정: %s%s\n", cc$ok, if (length(cc$mismatches)) paste0(" — ", paste(cc$mismatches, collapse = " / ")) else ""))
}
pf <- opt("--perf")
if (!is.null(pf)) {
  rec <- c(list(round = round, mode = if (merge) "merge" else if (!is.null(shard)) paste0("shard ", shard) else "single", seconds = round(el, 2), pid = Sys.getpid(),
                at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), opts = common, dt_threads = data.table::getDTthreads()),
           list(stages = lapply(as.list(pe), function(v) round(v, 2)), memo = list(ta_hits = .RCM$ta_hits %||% 0L, ta_miss = .RCM$ta_miss %||% 0L,
                                                                                     mc_hits = .RCM$mc_hits %||% 0L, mc_miss = .RCM$mc_miss %||% 0L)))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA), "\n", sep = "", file = pf, append = TRUE)
}
cat(sprintf("[rejudge] %s %s · %.1f초\n", round, if (merge) "merge" else if (!is.null(shard)) paste("shard", shard) else "single", el))
