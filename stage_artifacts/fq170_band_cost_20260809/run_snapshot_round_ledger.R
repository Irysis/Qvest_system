## close_round 원장 스냅샷 — 휘발성 .cache 에만 있는 367 라운드를 추적 가능한 곳으로 복사
## 근거: .cache/round_closures.jsonl 이 close_round 내용의 유일한 영구 저장소인데
##   .gitignore:5 `.cache/` 로 무시 → **fresh clone / 새 worktree 는 라운드 이력 0건**.
##   08-08 카드([[project-ppure-track-dead-cache-blocks-lane-20260808]]) = .cache 파일 1개 부재로 레인 4주 정지.
## ★스냅샷은 항구 수리가 아니라 **보존**이다. 항구 수리(close_round 이중쓰기)는 칩으로 분리.
## ⚠원장을 수정하지 않는다. 읽고 복사만 한다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
SRC <- ".cache/round_closures.jsonl"
stopifnot(file.exists(SRC))
ln <- readLines(SRC, warn = FALSE)
cat(sprintf("[입력 실측] 원장 %d줄 · %.2f MB\n", length(ln), file.size(SRC)/1024^2))

parsed <- lapply(ln, function(l) tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL))
ok <- !vapply(parsed, is.null, logical(1))
cat(sprintf("파싱 성공 %d / 실패 %d\n", sum(ok), sum(!ok)))
fld <- function(e, k) { v <- e[[k]]; if (is.null(v)) NA_character_ else as.character(v)[1] }
M <- rbindlist(lapply(parsed[ok], function(e) data.table(
  round_id = fld(e,"round_id"), closed_at = fld(e,"closed_at") %||% fld(e,"timestamp"),
  verdict_type = fld(e,"verdict_type"), layer = fld(e,"layer"),
  n_probes = length(e[["next_probes"]]), n_evid = length(e[["evidence_refs"]]))), fill = TRUE)
`%||%` <- function(a,b) if (is.na(a) || is.null(a)) b else a
M[, day := substr(closed_at, 1, 10)]
cat(sprintf("기간 %s ~ %s\n", min(M$day, na.rm=TRUE), max(M$day, na.rm=TRUE)))
cat(sprintf("evidence_refs 보유 %d/%d · next_probes>=2 보유 %d/%d\n",
            sum(M$n_evid > 0), nrow(M), sum(M$n_probes >= 2), nrow(M)))
cat("\n판정유형 분포:\n"); print(M[, .N, by=verdict_type][order(-N)])
cat("\n최근 7일:\n"); print(tail(M[, .N, by=day][order(day)], 7))

DEST_DIR <- file.path(CODE_ROOT, "06_Registry")
dir.create(DEST_DIR, showWarnings = FALSE, recursive = TRUE)
snap <- file.path(DEST_DIR, "round_closures_snapshot_20260809.jsonl")
writeLines(ln, snap, useBytes = TRUE)
idx <- file.path(DEST_DIR, "round_closures_snapshot_20260809_index.csv")
fwrite(M, idx)
## 재읽기 검증 (쓰고 나서 실제로 같은지 — 존재 검사 아닌 정체 검사)
back <- readLines(snap, warn = FALSE)
ident <- identical(back, ln)
cat(sprintf("\n스냅샷: %s\n색인  : %s\n재읽기 일치: %s (%d줄)\n", snap, idx, ident, length(back)))
if (!ident) stop("스냅샷 내용 불일치 — 중단")

note <- file.path(DEST_DIR, "round_closures_snapshot_20260809_README.md")
writeLines(c(
  "# close_round 원장 스냅샷 (2026-08-09)",
  "",
  "**이것은 라이브 원장이 아니다.** 라이브는 `.cache/round_closures.jsonl` 이며 계속 append 된다.",
  "",
  "## 왜 있나",
  "`close_round()` 는 `.cache/last_round_closure.json`(덮어씀) + `.cache/round_closures.jsonl`(append)",
  "**두 곳에만** 쓴다. `.gitignore:5` 의 `.cache/` 로 둘 다 추적되지 않으므로 **fresh clone 이나 새 worktree 는",
  "라운드 이력이 0건**이다. 라운드 내용(기전 진단·next_probe·소비면·증거·부활조건)의 다른 사본은 없다.",
  "",
  "## 한정",
  "- 스냅샷 시점 이후 라운드는 여기 없다. 시점 = 2026-08-09.",
  sprintf("- 레코드 %d건, 기간 %s ~ %s.", nrow(M), min(M$day,na.rm=TRUE), max(M$day,na.rm=TRUE)),
  "- 항구 수리(`close_round()` 가 추적 경로에 이중쓰기)는 **별도 태스크**. 이 파일은 보존일 뿐이다.",
  "",
  "## 색인",
  "`round_closures_snapshot_20260809_index.csv` = round_id / closed_at / verdict_type / layer /",
  "next_probes 수 / evidence_refs 수."), note, useBytes = TRUE)
cat(sprintf("README: %s\n", note))
