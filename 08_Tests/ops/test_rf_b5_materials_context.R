#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b5_materials_context.R — B5 설계 재료의 (2b) 프로그램 낙폭 구조 절 (2026-09-21 플랜 Part 3 · D3 (c))
#
# ① 컨텍스트 파일 존재·신선 → 절 3~4줄 · 숫자만 · 날짜 0(b5_has_dates) ② 부재 → 절 없음 ③ 48h 초과 → 절 없음
# ④ 파손 JSON → 절 없음(오류 없음) ⑤ b5_materials 조립 순서에 director 가 floor 뒤에 있고 sec$director 가 tryCatch 로 감싸여 있다
# 샌드박스 root(QVEST_RF_ROOT) — 운영 무접촉 · 쓰기 0.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_b5_materials_context","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
S <- gsub("\\", "/", file.path(tempdir(), sprintf("b5ctx_%d", Sys.getpid())), fixed = TRUE)
dir.create(file.path(S, ".cache"), recursive = TRUE, showWarnings = FALSE)
Sys.setenv(QVEST_RF_ROOT = S, QVEST_B5_CODE_ROOT = ROOT)
B <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(suppressWarnings(sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_b5_design_lib.R"), envir = B)))))
if (exists("b5_director_context", envir = B)) ok("b5_director_context 존재") else { ng("함수 부재"); finish() }
P <- file.path(S, ".cache/rf_director_context.json")
if (!length(B$b5_director_context(S))) ok("② 부재 → 절 없음") else ng("② 부재인데 절이 나옴")
ctx <- list(as_of = "2026-09-21T08:00:00+0900", binding = "calmar", co_binding = list("oos_retention"),
            program_best = list(port_t = 4.349, calmar = 0.501, mdd = 0.551, cagr = 0.276), thresholds = list(calmar_min = 0.64, port_t_min = 2.95),
            recurring_class = list(shape = "침식형", shape_rule = "최심 에피소드 고점→저점 중앙 ≤ 6개월 = 급락형", depth_median = 0.584, m_peak_trough_median = 25.75, ratio_median = 1.35, n_lineages_sharing = 4),
            pool_inventory = list(defensive_n = 213, defensive_deep_dd_excess_median = 2.57, defensive_deep_dd_negative_share = 0.169, n_surviving_binding_class = 177),
            overlay = list(status = "dead", adv_pass = 0, n_verdict = 46))
writeLines(toJSON(ctx, auto_unbox = TRUE), P)
L <- B$b5_director_context(S)
if (length(L) >= 4L && startsWith(L[1], "## (2b)")) ok(sprintf("① 절 %d줄 · 머리 (2b)", length(L))) else ng("① 절 생성", paste(L, collapse = " / "))
if (any(grepl("calmar+oos_retention", L, fixed = TRUE)) && any(grepl("4.349", L, fixed = TRUE)) && any(grepl("침식형", L, fixed = TRUE)) && any(grepl("25.8", L, fixed = TRUE)) && any(grepl("0/46", L, fixed = TRUE))) ok("① 숫자 항등(구속·최고·형태·개월·반증)") else ng("① 숫자", paste(L, collapse = " / "))
if (!B$b5_has_dates(L)) ok("① 날짜 0 (b5_has_dates)") else ng("① 날짜 노출")
if (!any(grepl("2026", L, fixed = TRUE))) ok("① as_of 가 본문에 없다") else ng("① as_of 노출")
Sys.setFileTime(P, Sys.time() - 3 * 24 * 3600)
if (!length(B$b5_director_context(S))) ok("③ 72h 경과 → 절 없음(낡은 컨텍스트 차단)") else ng("③ 낡은 컨텍스트 통과")
writeLines("{not json", P)
if (!length(tryCatch(B$b5_director_context(S), error = function(e) "ERR"))) ok("④ 파손 JSON → 절 없음 · 오류 없음") else ng("④ 파손 처리")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_b5_design_lib.R"), encoding = "UTF-8", warn = FALSE)
if (any(grepl('order <- c("axioms", "entry", "floor", "director", "outcomes"', src, fixed = TRUE)) && any(grepl("sec$director <- tryCatch(b5_director_context(root)", src, fixed = TRUE))) ok("⑤ 조립 순서 floor→director · tryCatch 감쌈") else ng("⑤ 조립 배선")
unlink(S, recursive = TRUE)
finish()
