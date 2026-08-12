## L9 — 마지막 미보존 사건 원장: hygiene_manifest.log (933건)
## L5 의 AST 스캐너가 weekly_cleaner_sweep.R:99 를 새로 찾아내면서 드러났다
## (L2 정규식 스캐너는 못 봄 — `manifest_path` 가 변수).
## ★.cache 는 심볼릭 링크(/c/qm_cache) 라 저장소 밖이다 — 보존이 곧 유일한 저장소 흔적.
suppressPackageStartupMessages(library(jsonlite))
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
SRC <- ".cache/hygiene_manifest.log"
stopifnot(file.exists(SRC))
ln <- readLines(SRC, warn = FALSE)
D <- file.path(CODE_ROOT, "06_Registry")
dst <- file.path(D, "hygiene_manifest_snapshot_20260809.log")
writeLines(ln, dst, useBytes = TRUE)
back <- readLines(dst, warn = FALSE)
cat(sprintf("hygiene_manifest.log  %d줄 · %.1f KB → %s\n재읽기 일치: %s\n",
            length(ln), file.size(SRC)/1024, basename(dst), identical(back, ln)))
if (!identical(back, ln)) stop("내용 불일치 — 중단")
ig <- system2("git", c("-C", shQuote(CODE_ROOT), "check-ignore", "-q",
                       shQuote(file.path("06_Registry", basename(dst)))))
cat(sprintf("ignored: %s\n", if (ig == 0L) "Y (문제)" else "N"))
cat(sprintf("\n첫 줄: %s\n마지막 줄: %s\n", substr(ln[1], 1, 110), substr(ln[length(ln)], 1, 110)))
