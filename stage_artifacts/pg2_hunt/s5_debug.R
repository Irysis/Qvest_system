## s5 — s4 가 0행을 낸 원인 규명 (조용한 skip 이 났다 — 0 은 정지 신호)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[s5] ", fmt, "\n"), ...)); flush.console() }
INV <- readRDS("stage_artifacts/pg2_hunt/s1_inventory.rds")
say("저장 필드: %s", paste(names(INV), collapse=", "))
for (k in names(INV)) say("  %-8s 길이/행 %s", k,
  if (is.data.frame(INV[[k]])) nrow(INV[[k]]) else length(INV[[k]]))
say("names 표본: %s", paste(head(INV$names, 8), collapse=" | "))
say("keep 표본 : %s", paste(head(INV$keep, 8), collapse=", "))
say("★ser 는 **전체 52** · names/keep 은 상관행렬 기준 인덱스인가 확인")
say("  ser 길이 %d · names 길이 %d · idx 행 %d", length(INV$ser), length(INV$names), nrow(INV$idx))
say("=== 이름 매칭 ===")
for (nm in c("STR_1698_WT008_M08_Swap","WT_D20260424_009_pilot11","WT_WT-S20260504_004")) {
  i <- which(INV$names == nm)
  say("  %-30s exact %s · grepl %s", nm,
      if (length(i)) paste(i, collapse=",") else "없음",
      paste(which(grepl(substr(nm,1,14), INV$names, fixed=TRUE)), collapse=","))
}
say("=== idx$id 와 names 관계 ===")
say("  idx$id 표본: %s", paste(head(INV$idx$id, 6), collapse=" | "))
say("  ★names 는 make.unique(idx$id) 였으므로 순서가 같아야 한다: 일치 %s",
    identical(make.unique(INV$idx$id), INV$names))
say("=== s2 가 쓴 인덱스 검증 ===")
say("  s2 는 `for (j in KEEP) S <- SER[[j]]` 로 접근했다.")
say("  KEEP 최대 %d · SER 길이 %d → 범위 %s", max(INV$keep), length(INV$ser),
    if (max(INV$keep) <= length(INV$ser)) "정상" else "★초과")
say("  ⇒ s2 는 정상 동작했고(40행 출력), s4 만 실패했다면 원인은 **이름 매칭**이다")
