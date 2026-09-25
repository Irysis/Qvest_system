#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b1_materials_redact.R — B1 설계 재료의 교차 entry 전기간 수치 가림 (R2 2026-09-25 · pit.md C1 D-E)
#
# 배경: B1 설계 레인은 팩터를 고르는 무인 자동 선정기다. 재료의 "앞선 논문들에서 이미 배운 것" 절이 다른 entry 의
#   블록 L-code 서술을 옮겨 싣는데, 그 안에 팩터별 전기간 측정값이 그대로 있었다(09-25 실측: 발송 재료 29건 중 28건 —
#   "B1_1 L19_Price_Delay PORT_t 0.338 · B1_2 L22_Ret_Autocorr 0.040"). C1 D-E: 평가 창 결과를 소비하는 자동 선정 = C1/C14.
#   수리 = rf_b1_design_lib.R 가 교차 절 수치를 <stat> 로 가리고(식별자 보존) · 발송 전 재도출 검증이 잔존 시 재료를 쓰지 않는다.
#
# 양방향:
#   A. 가림 규칙 단위 — 양성 대조(실측 재료 문장형) · 식별자 보존(arXiv·버전·연.월·RP_·셀 코드·정수 개수) · 한글 인접·문장 끝 마침표
#   B. b1_materials 전체 — 합성 루트(원장 · 교차 entry L-code 3건에 팩터별 수치 강제 삽입 · 자기 entry L-code 1건) →
#      교차 절 수치 0(★검사 자체 판별기 — 피검 코드의 검증기를 빌리지 않는다) · <stat> 존재 · 기전 문장·팩터 id 보존 ·
#      기저 절(이 entry 자신의 등급·t·Calmar)은 가리지 않는다 · jlog 에 가린 개수 · 절단이 식별자를 잘라도 오탐 폴백 없음(B9)
#   C. 돌연변이 — ① 기전 가림 호출 삭제(게이트 유지) → 재료 생성 중단·파일 없음·materials_rejected(게이트가 잡는다)
#                 ② 가림 호출 + 게이트 삭제 → 재료에 수치 잔존 → 이 검사의 판별기가 잡는다(red)
#                 ③ 가림 규칙 dec 삭제 → A 절 판별기가 잡는다(red)
#                 ④ 절단 뒤 가림 삭제 → 700자 절단이 자른 식별자 조각이 게이트를 멈춘다(B9 = 오탐 폴백 방지 검사가 잡는다)
#   (수리 전 코드 red 실증 = QVEST_B1_LIB 를 기준판으로 바꿔 이 검사를 돌리면 A 는 함수 부재 · B 는 수치 잔존으로 실패한다)
# 격리: QVEST_RF_ROOT = tempdir 합성 루트 · QVEST_RP_JLOG = tempdir · 후보 풀은 합성 풀로 대체(등록부·IC 패널 무접촉) — 운영 무접촉.
# 대상 교체: QVEST_B1_LIB (기본 = QM_ROOT/02_Infrastructure/ops/rf_b1_design_lib.R)
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
CODE <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
LIB  <- Sys.getenv("QVEST_B1_LIB", file.path(CODE, "02_Infrastructure/ops/rf_b1_design_lib.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)

# ── 검사 자체 판별기(피검 코드와 독립) — 식별자를 지운 뒤 소수·백분율이 남았나 ─────────────────────
ID_RX <- c("(?<![A-Za-z0-9_.])\\d{4}\\.\\d{4,5}(v\\d+)?(?![A-Za-z0-9_])", "(?<![A-Za-z0-9_.])[vV]\\d+(\\.\\d+)+(?![A-Za-z0-9_])",
           "(?<![A-Za-z0-9_.])(19[89]\\d|20[0-3]\\d)\\.(0[1-9]|1[0-2])(?![0-9])")
residual <- function(x) {
  x <- as.character(x); for (rx in ID_RX) x <- gsub(rx, " ", x, perl = TRUE)
  m <- regmatches(x, gregexpr("[-+\u2212]?\\d*\\.\\d+|\\d+(\\.\\d+)?\\s?(%|pp(?![A-Za-z]))", x, perl = TRUE))
  unique(unlist(m))
}

SB <- file.path(tempdir(), sprintf("r2_b1_redact_%d", Sys.getpid()))
unlink(SB, recursive = TRUE, force = TRUE)
dir.create(file.path(SB, "06_Registry"), recursive = TRUE)
LCD <- file.path(SB, "stage_artifacts/l_code/reinforcement"); dir.create(LCD, recursive = TRUE)
ART <- file.path(SB, "art/base"); dir.create(ART, recursive = TRUE)
JLOG <- file.path(SB, "jlog.jsonl")
Sys.setenv(QVEST_RF_ROOT = SB, QVEST_RP_JLOG = JLOG)
BID <- "T_R2_BASE"
write(toJSON(list(entries = list(list(base_id = BID, status = "active", paper_key = "paper_x", base_grade = "C",
                                      engine_path = "engine.R", base_artifacts = ART))), auto_unbox = TRUE),
      file.path(SB, "06_Registry/reinforce_ledger_l1.json"))
write(toJSON(list(replication = list(source_paper = list(title = "T", url = "https://arxiv.org/abs/2002.06975")),
                  essence = list(portfolio_alpha_t_nw_lag3 = 2.345, calmar = 0.456)), auto_unbox = TRUE),
      file.path(ART, "authoritative_remeasure.json"))
MECH <- paste("판정: 이 블록의 팩터 선정 축은 초과수익만 움직였고 낙폭은 사실상 고정이다.",
              "B1_1 L19_Price_Delay PORT_t 0.338 · B1_2 L22_Ret_Autocorr 0.040 · B4_21 PORT_t 1.619/1.534 ·",
              "MDD 0.539~0.560(폭 0.021) · MDD 57% · 폭 6.0%p · 폭 5.5pp · 4pp 차 · 계열 IC 0.22·ICIR 1.88·FM t 16.9 · Calmar 0.504. PORT_t 3 ·",
              "−0.280 과 +1.25 · 소형 분위 B3_13 이 PORT_t 1.886이고 폭0.021 이다 ·",
              "근거 arXiv 2002.06975 · v10.4 · 2019.12 고점 · RP_20260917_105807_22632 · L-RF-20260905_120000 · 5칸 · 25종")
wr_l <- function(bid, blk, mech, acts = list(), avoid = character(0)) {
  f <- file.path(LCD, sprintf("l_code_%s_%s.json", bid, blk))
  write(toJSON(list(l_code = sprintf("L-RF-%s-%s", bid, blk), strategy_id = paste0(bid, "_", blk), mechanism = mech,
                    next_block_actions = acts, avoid = as.list(avoid)), auto_unbox = TRUE), f)
  f
}
for (k in 1:3) wr_l(sprintf("T_OTHER%02d", k), "B1", MECH,
                    acts = list(list(action = "Calmar 0.5 이상 칸만 승계 · IC 1위 팩터 고정", why = "x", expect = "y")),
                    avoid = c("PORT_t 1.619/1.534 인 결합 재탕", "MDD 25% 넘는 스칼라 축"))
invisible(wr_l(BID, "B5", "자기 entry 기전 PORT_t 9.999"))      # 자기 entry — B1 재료의 교차 절에서 빠진다(기존 규칙)

load_lib <- function(path) {
  e <- new.env(parent = globalenv())
  suppressWarnings(suppressMessages(source(path, local = e, encoding = "UTF-8")))
  e$.pool <- function() data.table(id = c("L19_Price_Delay", "M01_Mom_12_1", "V02_EP"),
                                   category = c("liquidity", "momentum", "value"))
  e
}
mutate <- function(tag, pairs) {
  s <- readLines(LIB, warn = FALSE, encoding = "UTF-8"); t <- paste(s, collapse = "\n"); n_hit <- 0L
  for (pr in pairs) { if (lengths(regmatches(t, gregexpr(pr[1], t, fixed = TRUE))) == 1L) n_hit <- n_hit + 1L
                      t <- sub(pr[1], pr[2], t, fixed = TRUE) }
  p <- file.path(SB, sprintf("lib_mut_%s.R", tag)); writeLines(t, p, useBytes = TRUE)
  list(path = p, applied = identical(n_hit, length(pairs)))
}
jl <- function() if (file.exists(JLOG)) readLines(JLOG, warn = FALSE, encoding = "UTF-8") else character(0)
xsec <- function(txt) { i <- grep("^## 앞선 논문", txt); if (!length(i)) character(0) else txt[i[1]:length(txt)] }

cat("=== test_rf_b1_materials_redact ===\n")
E <- tryCatch(load_lib(LIB), error = function(e) { ng("라이브러리 적재", conditionMessage(e)); NULL })

cat("--- A. 가림 규칙 단위 ---\n")
if (!is.null(E) && exists("rf_b1_redact_stats", envir = E) && exists("rf_b1_has_stats", envir = E)) {
  raw <- c(MECH, "Calmar 0.504.", "0.338이 가장 높고 폭0.021", "IC 1위 · PORT_t 3 칸")
  red <- E$rf_b1_redact_stats(raw)
  chk(!length(residual(red)), "A1 양성 대조 — 실측형 수치(소수·범위·분수·백분율·%p·pp·유니코드 부호·한글 인접·문장 끝) 전부 <stat>",
      paste(residual(red), collapse = ","))
  chk(all(grepl("<stat>", red, fixed = TRUE)), "A2 가린 자리는 <stat> 로 남는다(수치가 있었다는 사실은 보존)")
  chk(grepl("arXiv 2002.06975", red[1], fixed = TRUE) && grepl("v10.4", red[1], fixed = TRUE) &&
      grepl("2019.12", red[1], fixed = TRUE) && grepl("RP_20260917_105807_22632", red[1], fixed = TRUE) &&
      grepl("L-RF-20260905_120000", red[1], fixed = TRUE) && grepl("B1_1 L19_Price_Delay", red[1], fixed = TRUE) &&
      grepl("5칸", red[1], fixed = TRUE) && grepl("25종", red[1], fixed = TRUE),
      "A3 식별자 보존 — arXiv id · 버전 · 연.월 · RP_/L-RF- id · 셀 코드·팩터 id · 정수 개수")
  chk(!grepl("IC 1위", red[4], fixed = TRUE) && grepl("IC <stat>위", red[4], fixed = TRUE) && grepl("PORT_t <stat> 칸", red[4], fixed = TRUE),
      "A4 지표 뒤 정수(IC 1위 · PORT_t 3)도 가린다 — 지표 이름은 남긴다", red[4])
  chk(isTRUE(E$rf_b1_has_stats(raw)) && !isTRUE(E$rf_b1_has_stats(red)), "A5 검증기 양방향 — 원문 TRUE · 가린 판 FALSE")
  idonly <- "arXiv 2002.06975 · v10.4 · 2019.12 · RP_20260917_105807_22632 · B1_2 · 25종 · L-RF-20260905_120000"
  chk(!isTRUE(E$rf_b1_has_stats(idonly)) && identical(E$rf_b1_redact_stats(idonly), idonly),
      "A6 식별자만 있는 문장 = 오탐 0 · 무변경")
  chk(identical(E$rf_b1_redact_stats(character(0)), character(0)) && identical(E$rf_b1_redact_stats(""), ""),
      "A7 빈 입력 안전")
} else ng("A 가림 함수 부재(rf_b1_redact_stats · rf_b1_has_stats)", "수리 전 판이면 기대된 red")

cat("--- B. b1_materials — 교차 entry 절 수치 0 · 기저 절 보존 ---\n")
MAT <- file.path(SB, "mat.txt")
if (!is.null(E)) {
  r <- tryCatch({ E$b1_materials(BID, MAT); "ok" }, error = function(e) conditionMessage(e))
  if (identical(r, "ok") && file.exists(MAT)) {
    txt <- readLines(MAT, warn = FALSE, encoding = "UTF-8"); xs <- xsec(txt)
    chk(length(xs) > 0L && sum(grepl("^### T_OTHER", xs)) == 3L, "B1 교차 절에 다른 entry 교훈 3건", sprintf("n=%d", sum(grepl("^### T_OTHER", xs))))
    rs <- residual(xs)
    chk(!length(rs), "B2 ★교차 절 전기간 수치 0 (검사 자체 판별기)", paste(head(rs, 8), collapse = ","))
    chk(any(grepl("<stat>", xs, fixed = TRUE)), "B3 교차 절에 <stat> 자리표시 존재(가림이 실제로 일어났다)")
    chk(any(grepl("초과수익만 움직였고", xs, fixed = TRUE)) && any(grepl("L19_Price_Delay", xs, fixed = TRUE)) &&
        any(grepl("^- 그때의 처방: ", xs)) && any(grepl("^- 쓰지 말 것: ", xs)),
        "B4 기전 문장·팩터 id·처방·회피 줄은 남는다(기전 전이는 유지)")
    chk(!any(grepl("9.999", txt, fixed = TRUE)) && !any(grepl(sprintf("### %s_B5", BID), txt, fixed = TRUE)),
        "B5 자기 entry L-code 는 교차 절에 안 실린다(기존 규칙 회귀)")
    base_line <- grep("기저 등급", txt, value = TRUE)
    chk(length(base_line) == 1L && grepl("2.345", base_line, fixed = TRUE) && grepl("0.456", base_line, fixed = TRUE),
        "B6 기저 절(이 entry 자신의 t·Calmar)은 가리지 않는다 — 가림 범위 = 교차 entry 만", paste(base_line, collapse = ""))
    chk(any(grepl("pit.md C1 D-E", xs, fixed = TRUE)), "B7 교차 절 머리에 가린 이유(C1 D-E) 명시")
    jw <- grep('"event":"materials_written"', jl(), value = TRUE, fixed = TRUE)
    nm <- suppressWarnings(as.integer(sub('.*"cross_entry_stats_masked":([0-9]+).*', "\\1", tail(jw, 1))))
    chk(length(jw) >= 1L && isTRUE(nm > 0L), "B8 jlog materials_written 에 가린 개수(cross_entry_stats_masked > 0)", tail(jw, 1))
  } else ng("B b1_materials 실행", r)
  # B9 — 700자 절단이 식별자 가운데를 자르는 교훈(오탐 폴백 방지): 조각("2002.069")도 가려져 재료가 멈추지 않아야 한다
  cut_mech <- paste0(strrep("가", 691L), " 2002.06975 이후 PORT_t 0.338")   # 700자 절단 = "2002.069…"
  f9 <- wr_l("T_OTHER99", "B1", cut_mech)
  unlink(MAT)
  r9 <- tryCatch({ E$b1_materials(BID, MAT); "ok" }, error = function(e) conditionMessage(e))
  xs9 <- if (file.exists(MAT)) xsec(readLines(MAT, warn = FALSE, encoding = "UTF-8")) else character(0)
  chk(identical(r9, "ok") && !length(residual(xs9)) && any(grepl("^### T_OTHER99", xs9)),
      "B9 절단이 arXiv id 가운데를 잘라도 재료는 쓰이고(오탐 폴백 없음) 조각까지 가려진다", r9)
  unlink(f9)
}

cat("--- C. 돌연변이 ---\n")
unlink(MAT)
m1 <- mutate("no_mech_redact", list(c(".mx <- rf_b1_redact_stats(as.character(x$mechanism))", ".mx <- as.character(x$mechanism)")))
if (!m1$applied) ng("C1 돌연변이 좌표 낡음(기전 가림 호출)") else {
  E1 <- load_lib(m1$path); n0 <- length(grep("materials_rejected", jl(), fixed = TRUE))
  r1 <- tryCatch({ E1$b1_materials(BID, MAT); "written" }, error = function(e) conditionMessage(e))
  chk(!identical(r1, "written") && grepl("전기간 수치 잔존", r1, fixed = TRUE) && !file.exists(MAT) &&
      length(grep("materials_rejected", jl(), fixed = TRUE)) > n0,
      "C1 [돌연변이] 기전 가림 삭제 → 발송 전 게이트가 재료 생성을 멈춘다(파일 없음 · materials_rejected)", r1)
}
unlink(MAT)
m2 <- mutate("no_redact_no_gate", list(c(".mx <- rf_b1_redact_stats(as.character(x$mechanism))", ".mx <- as.character(x$mechanism)"),
                                       c("if (rf_b1_has_stats(.xl)) {", "if (FALSE) {")))
if (!m2$applied) ng("C2 돌연변이 좌표 낡음(가림 + 게이트)") else {
  E2 <- load_lib(m2$path)
  r2 <- tryCatch({ E2$b1_materials(BID, MAT); "written" }, error = function(e) conditionMessage(e))
  rs2 <- if (file.exists(MAT)) residual(xsec(readLines(MAT, warn = FALSE, encoding = "UTF-8"))) else character(0)
  chk(identical(r2, "written") && length(rs2) > 0L && "0.338" %in% rs2,
      "C2 [돌연변이] 가림·게이트 둘 다 삭제 → 재료에 0.338 등 잔존 = B2 판별기가 잡는다(red)", paste(head(rs2, 6), collapse = ","))
}
m3 <- mutate("no_dec_rule", list(c('  dec = "(?<![A-Za-z0-9_.])[-+\\u2212]?\\\\d*\\\\.\\\\d+(?![A-Za-z0-9_])")',
                                   '  dec = "(?!x)x")')))
if (!m3$applied) ng("C3 돌연변이 좌표 낡음(dec 규칙)") else {
  E3 <- load_lib(m3$path)
  chk(length(residual(E3$rf_b1_redact_stats(MECH))) > 0L, "C3 [돌연변이] dec 규칙 무력화 → A1 판별기가 소수 잔존을 잡는다(red)")
}

m4 <- mutate("no_post_cut_redact", list(c('.mx <- rf_b1_redact_stats(paste0(substr(.mx, 1L, 700L), "…"))',
                                           '.mx <- paste0(substr(.mx, 1L, 700L), "…")')))
if (!m4$applied) ng("C4 돌연변이 좌표 낡음(절단 뒤 가림)") else {
  E4 <- load_lib(m4$path); f4 <- wr_l("T_OTHER99", "B1", paste0(strrep("가", 691L), " 2002.06975 이후 PORT_t 0.338")); unlink(MAT)
  r4 <- tryCatch({ E4$b1_materials(BID, MAT); "written" }, error = function(e) conditionMessage(e))
  chk(!identical(r4, "written") && grepl("전기간 수치 잔존", r4, fixed = TRUE),
      "C4 [돌연변이] 절단 뒤 가림 삭제 → 잘린 식별자 조각이 게이트를 멈춘다(= B9 가 오탐 폴백을 잡는다)", r4)
  unlink(f4)
}

# (R2 적대 검증 09-25) C5 — pct 규칙에서 pp 를 빼면 퍼센트포인트 수치("5.5pp")가 가림·게이트 둘 다 비껴간다
m5 <- mutate("no_pp", list(c("\\\\s?(%p?|pp(?![A-Za-z]))\",", "\\\\s?%p?\",")))
if (!m5$applied) ng("C5 돌연변이 좌표 낡음(pct pp)") else {
  E5 <- load_lib(m5$path)
  rs5 <- residual(E5$rf_b1_redact_stats(MECH))
  chk(length(rs5) > 0L && any(grepl("5.5", rs5, fixed = TRUE)) && !isTRUE(E5$rf_b1_has_stats(E5$rf_b1_redact_stats(MECH))),
      "C5 [돌연변이] pp 삭제 → 5.5pp 잔존을 이 검사 판별기가 잡는다(red) · 피검 검증기는 못 잡는다(같은 식 — 독립 판별기가 필요한 이유)",
      paste(head(rs5, 6), collapse = ","))
}

unlink(SB, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_b1_materials_redact","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
