## L9-b — hygiene_manifest 를 **추적 가능한 확장자**로 재발행
## ★이 저장소의 .gitignore 는 **확장자 단위**로 막는다: `*.csv`(24행) · `*.log`.
##   "추적되는 디렉터리에 쓰면 된다" 가 아니라 **확장자까지 확인**해야 한다.
##   오늘 같은 자기모순을 3번 밟았다(csv 색인 → json 재발행, log 스냅샷 → 여기).
## 형식: TSV 3열(ts / action / path) → JSONL 1행 1레코드 (다른 스냅샷과 동형)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
ln <- readLines(".cache/hygiene_manifest.log", warn = FALSE)
parts <- tstrsplit(ln, "\t", fixed = TRUE)
n_col <- length(parts)
cat(sprintf("[입력 실측] %d줄 · 열 %d\n", length(ln), n_col))
bad <- sum(is.na(parts[[min(3L, n_col)]]))
cat(sprintf("3열 미만 줄: %d (구조 이탈 — 원문 보존 필드로 남긴다)\n", bad))

D <- file.path(CODE_ROOT, "06_Registry")
out <- file.path(D, "hygiene_manifest_snapshot_20260809.jsonl")
con <- file(out, open = "w", encoding = "UTF-8")
on.exit(close(con), add = TRUE)          # 함수 밖 최상위 on.exit 금칙② 회피: 여기선 스크립트 종료시 발화
for (i in seq_along(ln)) {
  f <- strsplit(ln[i], "\t", fixed = TRUE)[[1]]
  rec <- if (length(f) >= 3L) list(ts = f[1], action = f[2], path = paste(f[-(1:2)], collapse = "\t"))
         else list(ts = NA, action = NA, path = NA, raw = ln[i])
  writeLines(as.character(toJSON(rec, auto_unbox = TRUE, null = "null", digits = NA)), con)
}
close(con); on.exit()
back <- readLines(out, warn = FALSE)
ok_n <- length(back) == length(ln)
parsed <- sum(vapply(back, function(l) !inherits(try(fromJSON(l), silent = TRUE), "try-error"), logical(1)))
ig <- system2("git", c("-C", shQuote(CODE_ROOT), "check-ignore", "-q",
                       shQuote(file.path("06_Registry", basename(out)))))
cat(sprintf("\n%s\n줄수 보존 %s (%d/%d) · 전건 파싱 %d/%d · ignored %s\n",
            basename(out), ok_n, length(back), length(ln), parsed, length(back),
            if (ig == 0L) "Y (여전히 문제)" else "N"))
## .log 사본 제거 — 추적 불가라 혼동만 만든다
unlink(file.path(D, "hygiene_manifest_snapshot_20260809.log"))
cat(".log 사본 제거(추적 불가)\n")
if (!ok_n || parsed != length(back) || ig == 0L) stop("검증 실패 — 확인 필요")
cat("★검증 통과\n")
