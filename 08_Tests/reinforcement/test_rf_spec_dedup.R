#!/usr/bin/env Rscript
#==============================================================================
# test_rf_spec_dedup.R — 스펙 중복 가드 **양방향 검사** (2026-08-31)
#
# 왜: carry 대조만으로는 부족하다는 것이 실증됐다. 2026-08-31 B4_16~19 는
#   carry 와도 달랐고(유니버스가 carry 의 index/K200 이 아니라 격자 기본값 k200_kq150
#   으로 떨어졌다) **서로는 같았다**. 네 칸이 같은 t(2.241)를 냈는데 어떤 가드도 발화하지
#   않았다 — "carry 와 같은가" 는 봤지만 "서로 같은가" 는 아무도 안 봤다.
#
# 판정 축:
#   ① 실제 사고 재현 — B4_16~19 형태(축 전부 동일)가 하나로 접히는가
#   ② 축 하나라도 다르면 통과하는가 (과잉 차단 금지 — 음성 대조)
#   ③ 오버레이만 다른 칸은 서로 다른 칸인가 (B5 다섯 칸이 전부 닫히면 안 된다)
#   ④ 팩터 순서가 달라도 같은 집합이면 중복인가
#   ⑤ 러너에 실제로 배선됐는가 (소비자 없는 계기 금지)
#
# ★서명 함수는 러너 소스에서 **추출해** 돌린다 — 사본 재구현은 러너가 바뀌면 낡는다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PAR <- Sys.getenv("QVEST_RF_RUNNER", file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"))
SIG <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")
# ★2026-09-03: 헬퍼가 러너 인라인에서 rf_spec_sig.R 정본으로 이동했다.
#   사본 재구현 대신 **정본을 그대로 source** 한다 — 러너가 바뀌어도 안 낡는다.
if (!file.exists(SIG)) { cat("  FAIL 서명 정본 rf_spec_sig.R 부재
"); quit(status = 1) }
suppressMessages(source(SIG))
src <- readLines(PAR, warn = FALSE)   # 배선 검사(⑤)용 — 러너가 정본을 읽는지 본다
cat("=== 헬퍼 = rf_spec_sig.R 정본 ===
")

PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat(sprintf("  OK   %s\n", m)); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat(sprintf("  FAIL %s — %s\n", m, d)); FAIL <<- FAIL + 1L }

AMI  <- list(kind = "db", id = "L01_Amihud")
BM   <- list(kind = "db", id = "V01_BM")
BASE <- list(kind = "engine", path = "X/engine.R")
mk <- function(f = list(AMI), w = list(kind = "ew"),
               u = list(kind = "k200_kq150"), ov = NULL)
  list(factors = f, weighting = w, universe = u, overlay = ov, base_signal = BASE)

cat("=== 1. 실사고 재현 — B4_16~19 형태 ===\n")
sigs <- vapply(list(mk(), mk(), mk(), mk()), .spec_sig, character(1))
if (length(unique(sigs)) == 1L)
  ok("네 칸이 한 서명으로 접힌다 → 하나만 측정, 셋은 중복 종결") else
  ng("같은 스펙인데 서명이 갈린다", paste(unique(sigs), collapse = " / "))

cat("=== 1b. 팩터가 factor2 에 담긴 최초 entry (carry 없음) ===\n")
# ★승계 entry 는 팩터를 factors(복수)에, carry 없는 **최초** entry 는 factor2/factor3 에 담는다.
#   factors 만 보면 최초 entry 의 B1 다섯 칸이 전부 "팩터 없음" 으로 같은 서명이 되어
#   1칸만 남고 4칸이 중복으로 닫힌다(2026-08-31 실사고: B1_2~B1_5 가 실제로 소실됐다).
#   중복 가드가 정상 칸을 죽였다 — 서명은 측정에 들어가는 축 **전부**를 봐야 한다.
mk2 <- function(f2) list(factor2 = f2, weighting = list(kind = "ew"),
                         universe = list(kind = "k200_kq150"), base_signal = BASE)
s_bm  <- .spec_sig(mk2(BM))
s_ami <- .spec_sig(mk2(AMI))
if (!identical(s_bm, s_ami))
  ok("factor2 가 다르면 다른 칸 (B1 다섯 칸이 살아남는다)") else
  ng("factor2 를 서명이 안 본다", "최초 entry 의 B1 4칸이 중복으로 닫힌다")
if (identical(.spec_sig(mk2(AMI)), .spec_sig(mk(f = list(AMI)))))
  ok("factor2 형태와 factors 형태가 같은 서명") else
  ng("두 형태가 갈린다", "승계 전후로 같은 구성이 다르게 보인다")
if (identical(.spec_sig(mk2(NULL)), .spec_sig(mk(f = list()))))
  ok("팩터 없음은 양쪽 형태가 일치") else ng("빈 팩터 처리 불일치")


cat("=== 2. 축 하나라도 다르면 통과 (음성 대조) ===\n")
if (!identical(.spec_sig(mk()), .spec_sig(mk(f = list(AMI, BM)))))
  ok("팩터 차이 → 다른 칸") else ng("팩터 차이를 중복으로 봤다")
if (!identical(.spec_sig(mk()), .spec_sig(mk(w = list(kind = "catalog", catalog_id = "lean:cvar")))))
  ok("비중 차이 → 다른 칸") else ng("비중 차이를 중복으로 봤다")
if (!identical(.spec_sig(mk()), .spec_sig(mk(u = list(kind = "index", flag = "K200")))))
  ok("유니버스 차이 → 다른 칸") else ng("유니버스 차이를 중복으로 봤다")
if (!identical(.spec_sig(mk()),
               .spec_sig(list(factors = list(AMI), weighting = list(kind = "ew"),
                              universe = list(kind = "k200_kq150"),
                              base_signal = list(kind = "mom_12_1")))))
  ok("기저 신호 차이 → 다른 칸") else ng("기저가 달라도 같다고 봤다")

cat("=== 3. 오버레이만 다르면 서로 다른 칸 ===\n")
o1 <- mk(ov = list(kind = "dd_brake",  arm_id = "dd_brake_q"))
o2 <- mk(ov = list(kind = "vol_scale", arm_id = "vol_median"))
if (!identical(.spec_sig(o1), .spec_sig(o2)))
  ok("오버레이 팔이 다르면 다른 칸") else ng("B5 다섯 칸이 한 칸으로 접힌다")
if (!identical(.spec_sig(mk()), .spec_sig(o1)))
  ok("오버레이 유무가 서명에 반영") else ng("오버레이가 서명에서 빠졌다")

cat("=== 4. 팩터 순서 무관 ===\n")
if (identical(.spec_sig(mk(f = list(AMI, BM))), .spec_sig(mk(f = list(BM, AMI)))))
  ok("순서만 다른 같은 집합 → 중복") else ng("순서가 다르면 다른 칸으로 샌다")

cat("=== 5. 러너 배선 ===\n")
body <- paste(sub("#.*$", "", src), collapse = "\n")
for (nm in c(".seen_sig", "cell_duplicate_spec")) {
  if (grepl(nm, body, fixed = TRUE)) ok(sprintf("%s 배선", nm)) else
    ng(sprintf("%s 미배선", nm), "계기에 소비자가 없다")
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_spec_dedup","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
