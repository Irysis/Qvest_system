# =============================================================================
# verify_p9.R — 발행 후 기계 검증 (handoff 지시: write_json 은 PreToolUse 를 우회한다)
#   (1) 전 JSON 산출물 파싱 검증
#   (2) ast_spec_gate 적용 여부를 **주장 아닌 실측**으로 확인 (파일명 정규식 대조)
#   (3) 판정 인용 수치가 산출물과 일치하는지 역대조 (손기입 0 확인)
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/verify_p9.R")'
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p9] ", fmt, "\n"), ...))
ok <- TRUE

say("=== 1. JSON 파싱 검증 ===")
for (f in list.files(OUT, pattern = "\\.json$", full.names = TRUE)) {
  r <- tryCatch({ fromJSON(f); "PASS" }, error = function(e) paste("FAIL:", conditionMessage(e)))
  if (!identical(r, "PASS")) ok <- FALSE
  say("  %-34s %s", basename(f), r) }

say("=== 2. ast_spec_gate 적용 여부 (주장 아닌 실측) ===")
gate_re <- "^alpha_package.*\\.json$"     # ast_spec_gate.sh:95 의 정규식
emitted <- basename(list.files(OUT, pattern = "\\.json$"))
hit <- emitted[grepl(gate_re, emitted)]
say("  게이트 대상 정규식 %s 에 걸리는 산출물: %d건 %s", gate_re, length(hit),
    if (length(hit)) paste(hit, collapse = ", ") else "(없음)")
say("  → 본 라운드는 alpha_package 를 발행하지 않는다(신규 WT 미생성, next_probe 산출로 귀속).")
say("    따라서 ast_spec_gate·alpha_package schema 는 **적용 대상 아님** — 통과가 아니라 비적용이다.")

say("=== 3. 판정 인용 수치 역대조 (손기입 0 확인) ===")
V  <- fromJSON(file.path(OUT, "np_a_verdict.json"))
SA <- readRDS(file.path(OUT, "selfadv_p6.rds"))
C5 <- readRDS(file.path(OUT, "correct_p5.rds"))
BOOK7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
           "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
chk <- function(nm, a, b, tol = 1e-9) { d <- abs(a - b)
  if (!is.finite(d) || d > tol) ok <<- FALSE
  say("  %-46s 판정값 %+.6f vs 재계산 %+.6f  편차 %.2e  %s", nm, a, b, d, if (d <= tol) "OK" else "MISMATCH") }
# 계수 역계산
for (k in c("tiebreak|A|neutral|full","tiebreak|A|raw|full")) {
  ce <- C5$cells[[k]]
  n <- sum(sapply(ce$per_signal[BOOK7], function(z) isTRUE(z$hump_weak)))
  fld <- if (grepl("neutral", k)) V$primary_basis$count_full_neutral else V$primary_basis$count_full_raw
  chk(paste("book7 hump count", k), fld, n, 0) }
# pooled 크기 역대조
chk("book7 pooled neutral|full ann_pct", V$primary_basis$book7_pooled$`neutral|full`$ann_pct,
    SA$SA2_book7_pooled[["neutral|full"]]$ann_pct)
chk("book7 pooled raw|full ann_pct", V$primary_basis$book7_pooled$`raw|full`$ann_pct,
    SA$SA2_book7_pooled[["raw|full"]]$ann_pct)
# 앵커 — 부모 정본과의 일치
gold <- fromJSON("stage_artifacts/WT_D20260808_003/selfadv_p8.json")$profile$q01_n_post2015$quintile_ann_pct
chk("앵커 post2015 EW-상대 q5 (부모 정본 파생)", V$anchor_q01$post2015$ew_relative[5], gold[5] - mean(gold), 1e-9)

say("=== 종합: %s ===", if (ok) "전 항목 PASS" else "★ 불일치 존재 — 발행 보류")
stopifnot(ok)
