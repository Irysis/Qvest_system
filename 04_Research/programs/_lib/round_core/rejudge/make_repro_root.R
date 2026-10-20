## 재현 루트 — 끝난 라운드를 그 등록 커밋의 핀 판으로 다시 판정하기 위한 계약 · 설정 루트(스크래치에 만든다 · 저장소 · 라운드 폴더 무수정).
##   만드는 법: 이 저장소의 코드 · 설정(02_Infrastructure · 06_Registry · CLAUDE.md · _lib · 그 라운드의 사양 · 평가 파일 · 사전등록)을 복사하고,
##   사전등록 핀 md5 가 지금과 다른 파일만 `git show <등록 커밋>:<경로>` 로 덮는다. .cache = 이 저장소 전용 .cache 정션(C:/qm_cache 에는 쓰지 않는다).
##   끝에 핀 전체를 재대조해(rc_legacy_pin_mismatches) 0 이 아니면 멈춘다 — 핀이 맞지 않는 루트로는 판정하지 않는다.
## 사용: Rscript make_repro_root.R <저장소(worktree)> <라운드 디렉터리(저장소 상대)> <사전등록(저장소 상대)> <등록 커밋> <출력 루트>
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 5L) stop("usage: make_repro_root.R <repo> <round_dir> <prereg> <commit> <dest>")
WT <- gsub("\\\\", "/", a[1]); RD <- a[2]; PRE <- a[3]; COMMIT <- a[4]; DEST <- gsub("\\\\", "/", a[5])
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
md5 <- function(f) if (file.exists(f)) unname(as.character(tools::md5sum(f))) else "absent"
cp_tree <- function(rel) {
  s <- file.path(WT, rel); d <- file.path(DEST, rel)
  if (dir.exists(s)) { dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE); file.copy(s, dirname(d), recursive = TRUE, copy.date = TRUE) }
  else { dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE); file.copy(s, d, overwrite = TRUE, copy.date = TRUE) }
}
if (dir.exists(DEST)) stop("출력 루트가 이미 있다(덮어쓰지 않는다): ", DEST)
dir.create(DEST, recursive = TRUE)
for (rel in c("CLAUDE.md", "02_Infrastructure", "06_Registry", "04_Research/programs/_lib", file.path(dirname(PRE), "prereg.json"))) cp_tree(rel)
## 라운드 디렉터리 — 결과(results)는 빼고(저장된 칸 산출은 원래 자리에서 읽기만 한다)
dir.create(file.path(DEST, RD), recursive = TRUE, showWarnings = FALSE)
for (f in list.files(file.path(WT, RD), full.names = FALSE, all.files = FALSE)) if (!identical(f, "results")) cp_tree(file.path(RD, f))
## 다른 라운드의 측정 결과 json(작은 파일 · git 추적분) — 판정이 대조 원천으로 읽는다(예: P2R04 RX0 동일성 = P2R03 RX0 결과 json)
for (rj in Sys.glob(file.path(WT, "04_Research/programs/*/*/results/*.json"))) {
  rel <- substring(gsub("\\\\", "/", rj), nchar(WT) + 2L)
  if (startsWith(rel, paste0(RD, "/"))) next
  dir.create(dirname(file.path(DEST, rel)), recursive = TRUE, showWarnings = FALSE); file.copy(rj, file.path(DEST, rel), overwrite = TRUE, copy.date = TRUE)
}
pre <- fromJSON(file.path(WT, PRE), simplifyVector = FALSE)
pins <- c(lapply(pre[["operational_pins"]]$files %||% list(), function(f) c(f$path, f$md5)), lapply(pre[["evaluation"]]$files %||% list(), function(f) c(f$path, f$md5)),
          lapply(pre[["cells"]], function(c) c(c$path, c$md5)), if (!is.null(pre[["behavior_card_cfg"]])) list(c(pre[["behavior_card_cfg"]]$path, pre[["behavior_card_cfg"]]$md5)))
log <- list()
for (p in pins) {
  dst <- file.path(DEST, p[1])
  if (identical(md5(dst), p[2])) next
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  ## 바이트 그대로(줄 끝 · 인코딩 보존) — 문자열로 받지 않고 파일로 바로 받는다
  tf <- tempfile(); rc <- system2("git", c("-C", WT, "show", paste0(COMMIT, ":", p[1])), stdout = tf, stderr = FALSE)
  if (!identical(as.integer(rc), 0L)) stop("git show 실패: ", p[1], " @", COMMIT)
  file.copy(tf, dst, overwrite = TRUE); unlink(tf)
  log[[length(log) + 1L]] <- list(path = p[1], pin = p[2], restored = md5(dst), ok = identical(md5(dst), p[2]))
}
## .cache = 이 저장소 전용 .cache 정션(읽기 · 코어 캐시 쓰기는 거기로 — C:/qm_cache 에는 쓰지 않는다)
jt <- gsub("/", "\\\\", file.path(DEST, ".cache")); tg <- gsub("/", "\\\\", file.path(WT, ".cache"))
system2("powershell.exe", c("-NoProfile", "-Command", shQuote(sprintf("New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null", jt, tg))))
writeLines(toJSON(list(repo = WT, round_dir = RD, prereg = PRE, commit = COMMIT, restored = log, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
                  auto_unbox = TRUE, pretty = TRUE), file.path(DEST, "REPRO_ROOT.json"))
bad <- Filter(function(z) !isTRUE(z$ok), log)
cat(sprintf("[재현 루트] %s · 핀 판 복원 %d 파일 · 실패 %d\n", DEST, length(log), length(bad)))
for (z in log) cat(sprintf("  %s %s → %s\n", if (z$ok) "ok" else "FAIL", z$path, substr(z$restored, 1, 8)))
if (length(bad)) quit(status = 1L)
