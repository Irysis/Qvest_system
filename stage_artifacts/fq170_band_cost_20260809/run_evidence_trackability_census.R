## 증거 추적성 census — close_round evidence_refs 가 **git 이 영구히 무시하는 파일**을 가리키는가
## 동기: .gitignore:24 의 전역 `*.csv` 로 stage_artifacts 하 CSV 는 추적 0건.
##   evidence_refs 가 CSV 만 가리키는 라운드는 **증거가 저장소에 남지 않는다**
##   (도훈의 원 과제와 같은 계통 — 감사 추적이 조용히 비는 것).
## 측정: 모든 close_round 마커의 evidence_refs 를 열어 확장자별로 분류하고,
##   ★핵심 = **CSV 만 있고 tracked 대체본(json/rds)이 없는 라운드 수**.
## ⚠존재 검사가 아니라 정체 검사: 같은 basename 의 .json 이 실제로 존재하는지 파일로 확인한다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

cands <- c("06_Registry/continuity_rounds.json", "06_Registry/close_round_log.json",
           ".cache/close_round_markers.json", "qepm/observability/close_rounds.jsonl")
found <- cands[file.exists(cands)]
mk <- list.files(".cache", pattern="close_round|continuity", full.names=TRUE, recursive=TRUE)
mk2 <- list.files("06_Registry", pattern="close_round|continuity", full.names=TRUE)
cat("후보 존재:", if (length(found)) paste(found, collapse=", ") else "(없음)", "\n")
cat(".cache 매치:", if (length(mk)) paste(head(mk,8), collapse=", ") else "(없음)", "\n")
cat("06_Registry 매치:", if (length(mk2)) paste(head(mk2,8), collapse=", ") else "(없음)", "\n")

src <- unique(c(found, mk, mk2))
src <- src[grepl("\\.(json|jsonl)$", src)]
if (!length(src)) { cat("\n⇒ close_round 마커 저장소를 못 찾음. census 불가 — 이것 자체가 발견.\n"); quit(save="no") }

recs <- list()
for (f in src) {
  x <- try(if (grepl("\\.jsonl$", f)) lapply(readLines(f, warn=FALSE), function(l) try(fromJSON(l), silent=TRUE))
           else list(fromJSON(f)), silent=TRUE)
  if (inherits(x,"try-error")) next
  for (e in x) if (!inherits(e,"try-error") && is.list(e)) recs[[length(recs)+1L]] <- list(src=f, e=e)
}
cat(sprintf("\n마커 레코드 %d건 (파일 %d개)\n", length(recs), length(src)))
if (!length(recs)) quit(save="no")

get_refs <- function(e) {
  r <- e[["evidence_refs"]]; if (is.null(r)) r <- e[["evidence"]]
  if (is.null(r)) return(character(0)); as.character(unlist(r))
}
rows <- list()
for (rc in recs) {
  refs <- get_refs(rc$e); if (!length(refs)) next
  paths <- unlist(regmatches(refs, gregexpr("[A-Za-z0-9_./-]+\\.(csv|json|rds|parquet|R|md)",
                                            refs, perl=TRUE)))
  if (!length(paths)) next
  ext <- tolower(sub(".*\\.", "", paths))
  csvs <- paths[ext == "csv"]
  # 정체 검사: CSV 마다 같은 stem 의 tracked 확장자 대체본이 **파일로** 있는가
  has_alt <- vapply(csvs, function(p) {
    stem <- sub("\\.csv$", "", p)
    any(file.exists(paste0(stem, c(".json", ".rds", "_result.json")))) ||
    any(file.exists(file.path(dirname(p), paste0(sub("_.*$","",basename(stem)), "_result.json"))))
  }, logical(1))
  rows[[length(rows)+1L]] <- data.table(
    round_id = rc$e[["round_id"]] %||% NA_character_,
    n_ref = length(paths), n_csv = length(csvs),
    n_tracked_ext = sum(ext %in% c("json","rds","parquet","r","md")),
    csv_without_alt = if (length(csvs)) sum(!has_alt) else 0L)
}
`%||%` <- function(a,b) if (is.null(a)) b else a
R <- rbindlist(rows, fill=TRUE)
cat(sprintf("evidence_refs 를 가진 라운드 %d건\n", nrow(R)))
if (!nrow(R)) quit(save="no")
cat(sprintf("  CSV 인용 라운드            : %d\n", sum(R$n_csv > 0)))
cat(sprintf("  ★CSV 인용인데 대체본 없음  : %d\n", sum(R$csv_without_alt > 0)))
cat(sprintf("  추적가능 증거 0인 라운드   : %d\n", sum(R$n_tracked_ext == 0)))
bad <- R[csv_without_alt > 0 | n_tracked_ext == 0]
if (nrow(bad)) { cat("\n[증거 추적 불가 라운드]\n"); print(head(bad[, .(round_id, n_ref, n_csv, csv_without_alt, n_tracked_ext)], 20)) }
fwrite(R, file.path(OUT, "evidence_trackability.csv"))
write_json(list(n_rounds=nrow(R), csv_citing=sum(R$n_csv>0),
                csv_without_alt=sum(R$csv_without_alt>0), no_tracked=sum(R$n_tracked_ext==0),
                results=R), file.path(OUT,"evidence_trackability.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
