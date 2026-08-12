## AZ1 — INVERTED 재료 후보를 factor_db 에서 직접 스크린 (FQ-171 대기 우회)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  이 아크의 최대 미검: INVERTED 표본이 **D03 1건**뿐이라 '형태 조건부' 와 'D03 고유' 가 구별 안 된다.
##  ⇒ load_month_factors() 경유(C15)로 팩터를 받아 **decile 프로파일 형태**를 census 한다.
##  형태 규칙 = WT-D20260809_003 p1_shape.R::classify 원문 승계(재작성 금지):
##    MONOTONE_TOP: spearman >= 0.70 ∧ argmax == 10
##    HUMP        : argmax in 4:8 ∧ top < median
##    INVERTED    : spearman <= -0.70
##   BA1 표본 확보: INVERTED 가 D03 외 >=2건 → AE3 를 FQ-171 대기 없이 착수 가능
##   BA2 희소: 0~1건 → INVERTED 는 드문 형태이며 'D03 고유' 쪽 증거가 강해진다
##  ★본 라운드는 **census 만** 한다. 성과 측정·결합은 다음 라운드(사전등록 별도).
##  BA3 자본 자격 주장 없음
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

# C15: Factor DB parquet 직접 load 금지 → load_month_factors() 경유
lm_path <- file.path(CODE_ROOT, "02_Infrastructure/factor_db/load_month_factors.R")
if (!file.exists(lm_path)) {
  cands <- list.files(file.path(CODE_ROOT, "02_Infrastructure"), pattern="load_month_factors",
                      recursive=TRUE, full.names=TRUE)
  cat("[C15 loader 탐색]", if (length(cands)) paste(head(cands,3), collapse=" | ") else "없음", "\n")
  if (length(cands)) lm_path <- cands[1]
}
if (!file.exists(lm_path)) {
  cat("★load_month_factors 미발견 — C15 규약상 parquet 직접 로드 금지이므로 라운드 중단.\n")
  cat("  (0 은 결론이 아니라 정지 신호 — 경로를 확정한 뒤 재개할 것)\n"); quit(status=0)
}
cat("[C15 loader]", lm_path, "\n")
source(lm_path)
cat("[로드 후 함수]", paste(head(ls(pattern="load_month|factor"), 10), collapse=", "), "\n")
if (!exists("load_month_factors")) { cat("★load_month_factors() 미정의 — 중단\n"); quit(status=0) }
cat("[signature]", paste(names(formals(load_month_factors)), collapse=", "), "\n")
