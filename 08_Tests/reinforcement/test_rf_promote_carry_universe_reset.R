#!/usr/bin/env Rscript
#==============================================================================
# test_rf_promote_carry_universe_reset.R — 승격 carry 는 유니버스를 고정 축으로 리셋한다 (2026-09-05 · 도훈 결정)
# 실사고: promo2 최고 n=17 = KOSDAQ150 단독(NAV 2010-02~) · B 2.567 > 부모 2.171 → 승격 조건 충족.
#   구판 next_paper.R:124 는 universe = ws$universe 를 그대로 물려줘 다음 세대 B1·B2·B4 가 고정 축 밖(KQ150 단독 · 창 2010~)에서 돌게 된다.
# 판정 축: U1 유니버스 리셋 · U2 provenance 보존 · U3 팩터·비중·오버레이는 그대로(음성 대조) · U4 돌연변이 통제 · U5 call site
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R"), local = globalenv()))))
ws <- list(factors = list(list(kind = "db", id = "S01_Size"), list(kind = "db", id = "R03_CVaR_95")),
           weighting = list(kind = "catalog", catalog_id = "lean:cvar", label = "cvar"),
           universe = list(kind = "index", flag = "KQ150"),
           overlay = list(kind = "arm", arm_id = "dbeta_tilt"))
best <- list(cell_code = "B3_12", port_t = 2.567)
c1 <- rf_promote_carry(ws, ws$factors, best, "spec.json")
if (identical(c1$universe, list(kind = "k200_kq150"))) ok("U1 carry 유니버스 == k200_kq150 (KQ150 단독 승자에서도)") else ng("U1 유니버스가 리셋되지 않는다 ★실사고", paste(unlist(c1$universe), collapse = ","))
if (identical(c1$universe_reset_from, ws$universe)) ok("U2 승자 유니버스는 provenance 로 보존") else ng("U2 provenance 소실")
if (identical(c1$factors, ws$factors) && identical(c1$weighting, ws$weighting) && identical(c1$overlay, ws$overlay) && identical(c1$source_cell, "B3_12"))
  ok("U3 팩터·비중·오버레이·source_cell 그대로") else ng("U3 다른 축이 훼손됐다")
naive <- list(universe = ws$universe)
if (!identical(naive$universe, c1$universe)) ok("U4 구판(ws$universe 그대로)이면 KQ150 이 carry 됐다 — 픽스처가 결함을 가른다") else ng("U4 픽스처 판별력 없음")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), encoding = "UTF-8", warn = FALSE)
if (any(grepl("rf_promote_carry(", src, fixed = TRUE)) && !any(grepl("universe = ws$universe", src, fixed = TRUE)))
  ok("U5 next_paper.R 이 rf_promote_carry 를 부르고 구 줄이 없다") else ng("U5 call site 미교체 또는 구 줄 잔존")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_promote_carry_universe_reset","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
