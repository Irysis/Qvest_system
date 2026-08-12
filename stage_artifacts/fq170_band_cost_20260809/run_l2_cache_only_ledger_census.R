## L2 — `.cache` 에만 쓰는 **사건 원장** census (close_round 결함이 계통인가)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  `.cache` 자체는 정당하다 — CLAUDE.md 가 명시하듯 파생 캐시는 bootstrap 재생성 대상이고 권위 없음.
##  결함은 **재생성 불가한 사건 기록**(무엇이 일어났는가)이 `.cache` 에만 있을 때다.
##  판별 대리: **append 의미로 쓰는 사이트** — 사건을 쌓을 때만 append 한다(파생물은 덮어쓴다).
##    APPEND 신호: `append=TRUE` · `cat(..., append` · 대상이 `.jsonl`
##  ★파일명 추측 금지(이번 턴에 그래서 원장을 놓쳤다) — **코드의 쓰기 경로를 읽는다**.
##  ★존재 검사 아닌 정체 검사: 대상 파일이 실제로 있는지 + **레코드 수**까지 센다
##    (경로만 있고 파일이 없으면 '위험 자산'이 아니라 dead code).
##  분류:
##   D1_DEFECT   : `.cache` 로 append + 같은 파일에 추적 경로 쓰기 **없음** + 대상 파일 실재
##   D2_MITIGATED: `.cache` append 인데 같은 파일이 추적 경로에도 씀
##   D3_DEAD     : append 경로인데 대상 파일 부재
##  ⚠상시 경로(02_Infrastructure/contracts·ops·axiom·hooks·portfolio·validation·worktask)와
##    일회성 리서치(ramp/run_*·stage_artifacts)를 분리 보고한다 — 후자는 결함 아님.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

roots <- c("02_Infrastructure", "qepm", "ops", ".claude/hooks")
roots <- roots[dir.exists(roots)]
files <- unlist(lapply(roots, function(r)
  list.files(r, pattern="\\.(R|r|py|sh)$", full.names=TRUE, recursive=TRUE)))
files <- files[!grepl("/(\\.venv|node_modules|renv)/", files)]
cat(sprintf("[입력 실측] 스캔 대상 %d 파일 (루트 %s)\n", length(files), paste(roots, collapse=", ")))

## 상시 경로 판정 — 일회성 리서치 스크립트 제외
is_standing <- function(p) {
  grepl("02_Infrastructure/(contracts|ops|axiom|hooks|portfolio|validation|worktask|memory|telegram|tools)/", p) ||
  grepl("qepm/(scripts|registry|mailbox)/", p) || grepl("^ops/", p) || grepl("^\\.claude/hooks/", p)
}
APPEND_PAT <- "append\\s*=\\s*(TRUE|True|1)|>>\\s|\\.jsonl"
CACHE_PAT  <- "\\.cache/"

rows <- list()
for (f in files) {
  ln <- tryCatch(readLines(f, warn=FALSE), error=function(e) character(0))
  if (!length(ln)) next
  hit <- grep(CACHE_PAT, ln, perl=TRUE)
  if (!length(hit)) next
  ctx <- ln[hit]
  app_i <- hit[grepl(APPEND_PAT, ctx, perl=TRUE)]
  if (!length(app_i)) next
  ## 같은 파일이 추적 경로(=.cache 아님, *.csv 아님)에도 쓰는가
  wr <- grep("write_json|writeLines|fwrite|saveRDS|write\\.csv|open\\(|>>", ln, perl=TRUE)
  tracked_write <- any(grepl("06_Registry|04_Research|qepm/(registry|memory)|00_Lawbook", ln[wr], perl=TRUE) &
                       !grepl(CACHE_PAT, ln[wr], perl=TRUE))
  ## 대상 경로 추출 → 실재/레코드수 (정체 검사)
  tgt <- unique(unlist(regmatches(ln[app_i],
    gregexpr("\\.cache/[A-Za-z0-9_./-]+\\.(jsonl|json|log|txt|rds|csv)", ln[app_i], perl=TRUE))))
  for (t in (if (length(tgt)) tgt else NA_character_)) {
    ex <- !is.na(t) && file.exists(t)
    nrec <- if (ex) length(readLines(t, warn=FALSE)) else NA_integer_
    rows[[length(rows)+1L]] <- data.table(
      file=f, standing=is_standing(f), target=t, exists=ex, n_rec=nrec,
      tracked_sibling=tracked_write,
      klass = if (is.na(t) || !ex) "D3_DEAD" else if (tracked_write) "D2_MITIGATED" else "D1_DEFECT")
  }
}
R <- rbindlist(rows, fill=TRUE)
if (!nrow(R)) { cat("append-to-.cache 사이트 0건 — 이것 자체가 확인 필요\n"); quit(save="no") }
cat(sprintf("\nappend-to-.cache 사이트 %d건 (파일 %d개)\n", nrow(R), uniqueN(R$file)))
cat("\n=== 분류 x 상시경로 ===\n"); print(dcast(R[, .N, by=.(klass, standing)], klass ~ standing, value.var="N", fill=0))

SD <- R[standing == TRUE & klass == "D1_DEFECT"][order(-n_rec)]
cat(sprintf("\n★상시 경로 D1_DEFECT: %d건\n", nrow(SD)))
if (nrow(SD)) print(SD[, .(file=sub("^02_Infrastructure/","2I/",file), target=sub("^\\.cache/","",target), n_rec)])
ONE <- R[standing == FALSE & klass == "D1_DEFECT"]
cat(sprintf("\n(참고) 일회성 스크립트 D1: %d건 — 결함 아님\n", nrow(ONE)))
at_risk <- sum(SD$n_rec, na.rm=TRUE)
cat(sprintf("\n★상시 경로에서 .cache 에만 쌓인 총 레코드: %d\n", at_risk))
verdict <- if (nrow(SD) >= 2) "S1_SYSTEMIC" else if (nrow(SD) == 1) "S2_ISOLATED" else "S3_NONE"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "S1_SYSTEMIC") cat("⇒ close_round 1건이 아니라 계통. 룰 레벨 규약 필요(계약은 추적 경로에 쓴다)\n")
fwrite(R, file.path(OUT,"l2_cache_ledger_census.csv"))
write_json(list(verdict=verdict, n_sites=nrow(R), standing_defects=nrow(SD),
                records_at_risk=at_risk, defects=SD, all=R),
           file.path(OUT,"l2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
