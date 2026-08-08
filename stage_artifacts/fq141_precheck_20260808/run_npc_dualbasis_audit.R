## NP-C — dual-basis 인용 지점 전수 확인
##
## 검거 대상(범주 오류): EW-유니버스 basis 수치를 "사이즈 노출을 제거하면 옮겨올 알파"로 읽는 서술.
##   실제로 `.canon_diag_ew_universe()` 는 **벤치마크만** 교체하고 포트폴리오 수익은 동일 객체다
##   ⇒ capw−EW 격차는 포트폴리오 사이즈 노출의 증거가 아니라 **더 쉬운 벤치로 채점한 값**이다.
## 판정: 인용 지점을 전수 수집 → ①단순 병기(정상) ②기각 전 확인 의무(정상, 원 취지)
##       ③격차를 '회수 가능 알파'로 해석(★위반) ④승격 경로로 사용(★INV-7 위반)
suppressPackageStartupMessages(library(data.table))
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(R)

targets <- c("06_Registry/layer_bottleneck_map.md",
             "06_Registry/alpha_frontier_queue.json",
             "06_Registry/knowledge_index.md")
extra <- list.files("04_Research/01_reports", pattern="\\.md$", full.names=TRUE)
targets <- c(targets, extra)
targets <- targets[file.exists(targets)]
cat(sprintf("[대상] %d 파일\n\n", length(targets)))

## 인용 신호어
PAT_CITE <- "EW[-_ ]?(유니버스|universe)|EW_universe_prefilter|dual[-_ ]?basis|dual_basis|EW-basis|EW basis"
## 위반 신호어 — 격차를 회수 가능한 양/승격 근거로 읽는 표현
PAT_BAD  <- "옮겨올|회수 가능|되찾|승격|graduation|통과 가능|상당분|기인한다|때문이다|제거하면|풀면"

hits <- rbindlist(lapply(targets, function(f) {
  L <- tryCatch(readLines(f, warn=FALSE, encoding="UTF-8"), error=function(e) character(0))
  if (!length(L)) return(NULL)
  i <- grep(PAT_CITE, L, perl=TRUE)
  if (!length(i)) return(NULL)
  data.table(file=f, line=i, txt=substr(L[i],1,220))
}), fill=TRUE)

if (!nrow(hits)) { cat("[결과] dual-basis 인용 0건 — 감사 대상 없음(★0을 합격으로 읽지 말 것: 패턴 점검 필요)\n"); quit(status=0) }

hits[, suspect := grepl(PAT_BAD, txt, perl=TRUE)]
## 이미 정정된 블록(정정 고지문 자체)은 제외 — '정정/범주 오류/성립하지 않는다' 포함 줄
hits[, is_fix := grepl("정정|범주 오류|성립하지 않는|아니다|위반이다|NP-C", txt, perl=TRUE)]

cat(sprintf("[인용] 총 %d건 · 파일 %d개\n", nrow(hits), uniqueN(hits$file)))
print(hits[, .(인용=.N, 의심=sum(suspect & !is_fix), 정정문=sum(is_fix)), by=.(file=basename(file))])

sus <- hits[suspect & !is_fix]
cat(sprintf("\n=== ★검토 필요 %d건 (인용 ∧ 회수가능-해석 신호어 ∧ 정정문 아님) ===\n", nrow(sus)))
if (nrow(sus)) {
  for (k in seq_len(nrow(sus))) with(sus[k],
    cat(sprintf("\n  [%s:%d]\n    %s\n", basename(file), line, txt)))
} else {
  cat("  없음 — 인용은 모두 병기/의무-확인 맥락이거나 이미 정정됨\n")
}

fwrite(hits, "stage_artifacts/fq141_precheck_20260808/npc_dualbasis_audit.csv")
cat(sprintf("\n[저장] npc_dualbasis_audit.csv (%d행)\n", nrow(hits)))
