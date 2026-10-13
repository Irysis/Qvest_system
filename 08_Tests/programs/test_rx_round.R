## test_rx_round.R — 처방 루프 v0 라운드 도구 검사기 (양방향: 통과 · 위반 주입)
## 대상: 02_Infrastructure/programs/rx_round.R (v10.01 · 2026-10-13 · S2 파일럿)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/programs"))) ROOT <- SELF
setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
ov <- .rx_overlay_vocab(ROOT); wt <- .rx_weight_vocab(ROOT)

cat("=== A. 처방 검증(rx_validate) — 통과 ===\n")
good <- list(overlay = list(kind = ov$kind[1], arm_id = ov$arm_id[1]),
             weighting = list(kind = "catalog", catalog_id = wt$catalog_id[1], label = wt$label[1]),
             rebalance = list(kind = "interval", k = 2L, phase = 0L),
             defense_sleeve = list(kind = "factor_topk", k = 5L, select = "ic_bad_rank_asof", rank = 1L),
             factors = list(list(kind = "db", id = "V01_BM")), universe = list(kind = "size_band", q_lo = 0.2, q_hi = 1),
             cap_core = list(k = 5L, satellite = "floor"))
v <- rx_validate(good, ROOT)
chk("A1 7축 유효 delta 통과", isTRUE(v$ok), paste(v$errors, collapse = " | "))
chk("A2 층 목록 오버레이 통과", isTRUE(rx_validate(list(overlay = list(list(kind = ov$kind[1], arm_id = ov$arm_id[1]),
                                                                      list(kind = ov$kind[2], arm_id = ov$arm_id[2]))), ROOT)$ok))

cat("\n=== B. 처방 검증 — 위반 주입(침묵 무처치 차단) ===\n")
bad <- function(delta) !isTRUE(rx_validate(delta, ROOT)$ok)
chk("B1 바꿀 수 없는 축(n_max · base_weight · fixed_axes) 거부", bad(list(n_max = 10)) && bad(list(base_weight = 0.3)) && bad(list(fixed_axes = list())))
chk("B2 카탈로그에 없는 오버레이 arm 거부", bad(list(overlay = list(kind = "dd_brake", arm_id = "no_such_arm"))))
chk("B3 오버레이 kind 불일치 거부", bad(list(overlay = list(kind = "turbulence", arm_id = "dd_brake_q"))))
chk("B4 비활성/없는 비중 카탈로그 id 거부", bad(list(weighting = list(kind = "catalog", catalog_id = "lean:nonexistent"))))
chk("B5 엔진 리밸 파서가 거부하는 값(interval k=1) 거부", bad(list(rebalance = list(kind = "interval", k = 1L))))
chk("B6 엔진 슬리브 파서가 거부하는 select 거부", bad(list(defense_sleeve = list(kind = "factor_topk", k = 5L, select = "ic_bad_rank"))))
chk("B7 엔진 cap_core 파서가 거부하는 k 거부", bad(list(cap_core = list(k = -1L))))
chk("B8 팩터 DB 에 없는 id · db 아닌 kind 거부", bad(list(factors = list(list(kind = "db", id = "ZZ_NOPE")))) &&
      bad(list(factors = list(list(kind = "engine", id = "V01_BM")))))
chk("B9 universe all_listed(이 기저 지지집합 밖) · size_band 역전 거부", bad(list(universe = list(kind = "all_listed"))) &&
      bad(list(universe = list(kind = "size_band", q_lo = 0.8, q_hi = 0.2))))
chk("B10 빈 delta 거부", bad(list()))

cat("\n=== C. 사양 컴파일 — 고정 축 · 기저 신호 보존 ===\n")
base <- list(code = "B6_36", block = "B6", label = "x", fixed_axes = list(n_max = 25, base_weight = 0.5),
             base_signal = list(kind = "engine", path = "e.R"), base_weight = 0.5, factors = list(list(kind = "db", id = "M01_Mom_12_1")),
             weighting = list(kind = "catalog", catalog_id = "lean:entropy"), rebalance = list(kind = "rank_buffer", mult = 2),
             defense_sleeve = NULL, preflight = list(note = "old"), selection_accounting = list(n_family_at_registration = 81))
sp <- rx_compile_spec(base, list(overlay = list(kind = "dd_brake", arm_id = "dd_brake_q")), code = "RX_T1", label = "L", idea = "I",
                      selection_accounting = list(selection_type = "sweep", n_family_at_registration = 200L))
chk("C1 바꾼 축만 달라진다(오버레이 추가 · 나머지 축 동일)", identical(sp$overlay$arm_id, "dd_brake_q") && identical(sp$factors, base$factors) &&
      identical(sp$weighting, base$weighting) && identical(sp$rebalance, base$rebalance))
chk("C2 고정 축 · 기저 신호 · 기저 가중 보존", identical(sp$fixed_axes, base$fixed_axes) && identical(sp$base_signal, base$base_signal) &&
      identical(sp$base_weight, base$base_weight))
chk("C3 코드 · 블록(RX) · 아이디어 · 시행 회계 교체 · 구 사전 점검 블록 제거", identical(sp$code, "RX_T1") && identical(sp$block, "RX") &&
      identical(sp$selection_accounting$n_family_at_registration, 200L) && is.null(sp$preflight))

cat("\n=== D. 처방 입력 검사(.rx_assert_clean) — 위반 주입 ===\n")
chk("D1 τ_D 이후 날짜 거부", err(.rx_assert_clean("위기 2023-05-01 에 방어", ROOT, "t")))
chk("D2 τ_D 이후 연-월 거부", err(.rx_assert_clean("2024-08 급락", ROOT, "t")))
chk("D3 등급 표기 거부", err(.rx_assert_clean("이 신호는 등급 B 였다", ROOT, "t")) && err(.rx_assert_clean("Grade A 후보", ROOT, "t")))
chk("D4 τ_D 이전 날짜 · arXiv id · 지표 이름은 통과(거짓 양성 없음)",
    !err(.rx_assert_clean("2008-10-24 바닥 · arXiv 2002.06975 · 2022-12 · 등급 산식 S", ROOT, "t")))

cat("\n=== E. 문서 · 경로 ===\n")
tb <- rx_toolbox_md(ROOT)
chk("E1 도구 상자: custom 범주(자동 등록 전략 신호) 없음", !grepl("\\| custom \\|", tb))
chk("E2 도구 상자: active · 집행 가능 오버레이 전부 실림", all(vapply(ov$arm_id, function(a) grepl(paste0("| ", a, " |"), tb, fixed = TRUE), logical(1))))
chk("E3 도구 상자: 설명문 수치 가림(<stat>) 작동", grepl("<stat>", tb, fixed = TRUE))
eng <- readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"), encoding = "UTF-8")
i <- grep("\\.OV_BUILTIN <- c\\(", eng)[1]
src <- paste(eng[i:(i + 2L)], collapse = " ")
eb <- regmatches(src, gregexpr('"[a-z_]+"', src))[[1]]; eb <- gsub('"', "", eb)
chk("E4 오버레이 빌트인 목록 = 엔진 정본(드리프트 없음)", setequal(eb, .RX_OV_BUILTIN), paste(setdiff(union(eb, .RX_OV_BUILTIN), intersect(eb, .RX_OV_BUILTIN)), collapse = ","))
chk("E5 작업 디렉터리가 R6 성과 경로 정규식에 걸리면 거부", err(rx_paths("P2_DEFENSE", "R1_essence_check", ROOT)$lane("analyst")))
chk("E6 정상 라운드 경로는 04_Research/programs 아래", grepl("/04_Research/programs/P2_DEFENSE/R1/lane_analyst$", rx_paths("P2_DEFENSE", "R1", ROOT)$lane("analyst")))
chk("E7 출력 마지막 json 블록 판독 · 없으면 오류",
    identical(rx_parse_json("a\n```json\n{\"x\":1}\n```\nb\n```json\n{\"x\":2}\n```")$x, 2L) && err(rx_parse_json("json 없음")))
ml <- c("# 보고", "```json", "{\"a\": [1,", "  2],", " \"b\": {\"c\": \"d\"}}", "```")
chk("E8 여러 줄 json 블록(실제 에이전트 출력 형태) 판독 — (?s) 없으면 못 찾던 결함(10-13 실측)",
    identical(rx_parse_json(ml)$b$c, "d") && length(rx_parse_json(ml)$a) == 2L)
chk("E9 CRLF 줄끝 출력도 판독", identical(rx_parse_json(paste(ml, collapse = "\r\n"))$b$c, "d"))

cat(sprintf("\n== rx_round: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"rx_round","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
