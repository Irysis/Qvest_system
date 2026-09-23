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
# ★정본 경로를 덮을 수 있게 둔다 — 이 검사의 **양성 대조**(구판 헬퍼 주입)를 공유 정본을
#   건드리지 않고 돌리기 위해서다. 2026-09-03 헬퍼가 러너에서 이 파일로 옮겨갔는데
#   프로브는 러너에 주입하고 있어 양성 대조 둘이 하루 동안 죽어 있었다(축을 옮기면 대조도 옮길 것).
SIG <- Sys.getenv("QVEST_RF_SIG", file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"))
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

cat("=== 4b. 오버레이 스택 — 순서 무관 · 단층 서명 불변 (2026-09-17 WP-Z) ===\n")
OA <- list(kind = "dd_brake", arm_id = "dd_brake_q"); OB <- list(kind = "dbeta_tilt", arm_id = "dbeta_tilt_rank")
OC <- list(kind = "ts_mom_gate", arm_id = "ts_mom_sign")
if (identical(.spec_sig(mk(ov = list(OA, OB))), .spec_sig(mk(ov = list(OB, OA)))))
  ok("스택 [A,B] ≡ [B,A] — 곱 합성이라 순서는 측정에 안 들어간다") else ng("스택 순서가 다른 칸으로 샌다")
if (identical(.spec_sig(mk(ov = list(OA, OB, OC))), .spec_sig(mk(ov = list(OC, OA, OB)))))
  ok("3층도 순서 무관") else ng("3층 순서")
if (!identical(.spec_sig(mk(ov = list(OA, OB))), .spec_sig(mk(ov = list(OA, OC)))))
  ok("층 하나가 다르면 다른 칸(음성 대조)") else ng("다른 스택을 중복으로 봤다")
if (!identical(.spec_sig(mk(ov = list(OA, OB))), .spec_sig(mk(ov = OA))))
  ok("[A,B] 와 단층 A 는 다른 칸") else ng("스택과 단층이 같은 서명")
## 구판 서명(정렬 없음)을 그대로 재현해 픽스처의 판별력을 잰다(돌연변이 통제) + 단층 문자열 불변을 대조한다
.old_sig <- function(sp) paste(c(
  paste(.fkeys(.rp_all_factors(sp)), collapse = "+"), as.character(sp$base_weight %||% "ew"),
  as.character(toJSON(sp$weighting %||% list(kind = "ew"), auto_unbox = TRUE)),
  as.character(toJSON(sp$universe  %||% list(kind = "k200_kq150"), auto_unbox = TRUE)),
  as.character(toJSON(sp$overlay   %||% list(), auto_unbox = TRUE)),
  as.character(sp$base_signal$path %||% sp$base_signal$kind %||% "")), collapse = "|")
if (!identical(.old_sig(mk(ov = list(OA, OB))), .old_sig(mk(ov = list(OB, OA)))))
  ok("돌연변이 통제 — 정렬을 되돌리면(구판) [A,B]≠[B,A] 로 갈린다: 위 검사가 결함을 가른다") else ng("픽스처 판별력 없음")
for (o in list(NULL, OA, list(kind = "none"), list(OA)))
  if (!identical(.spec_sig(mk(ov = o)), .old_sig(mk(ov = o)))) { ng("단층/NULL 서명이 구판과 다르다 — 기존 측정이 되살아난다", toJSON(o %||% list(), auto_unbox = TRUE)); break }
ok("단층·NULL·none·1원소 리스트 서명 = 구판 문자열과 비트 동일")
## 실제 스펙 파일 — 단층은 구판과 동일, 2층 이상은 뒤집어도 동일
.spd <- file.path(ROOT, ".cache/rf_parallel")
.fs <- if (dir.exists(.spd)) utils::head(sort(list.files(.spd, pattern = "^spec_B[0-9]+_[0-9]+__.*\\.json$", full.names = TRUE), decreasing = TRUE), 400L) else character(0)
## ★2026-09-21 B6(집행 주기) 신설 반영 — .spec_sig 는 rebalance 가 **있을 때만** 덧붙인다.
##   .old_sig 는 B6 이전 재현이라 그 필드를 모르므로 rebalance 를 단 칸은 당연히 달라진다.
##   그 차이를 빨강으로 두면 배터리가 상시 오탐이 되고, 상시 오탐은 상시 침묵이 된다.
##   축을 갈라 **셋 다 단정**한다:
##     (a) rebalance 없는 칸 = 구판과 비트 동일  → 기존 측정이 되살아나지 않는다(원래 보장)
##     (b) rebalance 있는 칸 = 구판과 **달라야** 한다 → 안 달라지면 규칙이 서명에 안 실린 것이다
##     (c) 같은 entry 안의 B6 칸끼리 = 서로 달라야 한다 → k=2 · k=3 · band · buffer 가 한 칸으로
##         뭉개지면 dedup 이 중복으로 쳐내거나 처치가 조용히 미전달된다.
##         ★entry 를 넘어선 동일 서명은 정상이다(같은 스펙은 같은 칸) — 그래서 entry 안에서만 본다.
n1 <- 0L; n2 <- 0L; nrb <- 0L; bad1 <- character(0); bad2 <- character(0)
rb_unchanged <- character(0); rb_sigs <- character(0); rb_owner <- character(0)
for (f in .fs) {
  s <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); if (is.null(s)) next
  L <- .ov_layers(s$overlay)
  if (length(L) > 1L) {
    n2 <- n2 + 1L; s2 <- s; s2$overlay <- rev(L)
    if (!identical(.spec_sig(s), .spec_sig(s2))) bad2 <- c(bad2, basename(f))
  } else if (!is.null(s[["rebalance"]]) || !is.null(s[["defense_sleeve"]])) {
    ## ★2026-09-23 — B7 defense_sleeve(2026-09-21)도 rebalance 와 같은 '있을 때만 서명에 붙는' 축이다.
    ##   구판 .old_sig 는 그 필드를 모르므로 B7 칸은 당연히 달라진다 — 단층 비트 동일 단정에 넣으면
    ##   배터리가 상시 오탐(09-21 이후 B7_41 3건 상시 빨강)이 되고, 상시 오탐은 상시 침묵이 된다.
    nrb <- nrb + 1L
    if (identical(.spec_sig(s), .old_sig(s))) rb_unchanged <- c(rb_unchanged, basename(f))
    rb_sigs  <- c(rb_sigs,  .spec_sig(s))
    rb_owner <- c(rb_owner, sub("\\.json$", "", sub("^spec_B[0-9]+_[0-9]+__", "", basename(f))))
  } else {
    n1 <- n1 + 1L
    if (!identical(.spec_sig(s), .old_sig(s))) bad1 <- c(bad1, basename(f))
  }
}
if (n1 > 0L && !length(bad1)) ok(sprintf("실제 단층 스펙 %d건 서명 비트 동일(구판 대비 · rebalance 없는 칸)", n1)) else ng("실제 단층 스펙 서명 변경", paste(utils::head(bad1, 3), collapse = ","))
if (nrb == 0L) cat("  --- rebalance 스펙 없음 — B6 축 대조 생략\n") else {
  if (!length(rb_unchanged)) ok(sprintf("B6 스펙 %d건 — rebalance 가 서명에 실린다(구판과 다르다)", nrb))
  else ng("B6 rebalance 가 서명에 안 실린다 — 칸들이 뭉갠다", paste(utils::head(rb_unchanged, 3), collapse = ","))
  .dup <- unlist(lapply(split(rb_sigs, rb_owner), function(z) if (anyDuplicated(z)) z[duplicated(z)] else character(0)))
  if (!length(.dup)) ok(sprintf("B6 스펙 — entry %d곳 안에서 칸별 서명이 전부 갈린다", length(unique(rb_owner))))
  else ng("같은 entry 안 B6 서명 충돌", sprintf("%d건", length(.dup)))
}
if (n2 == 0L) cat("  --- 실제 2층 이상 스펙 없음 — 뒤집기 대조 생략\n") else if (!length(bad2)) ok(sprintf("실제 스택 스펙 %d건 — 층을 뒤집어도 같은 서명", n2)) else ng("실제 스택 스펙 순서 의존", paste(utils::head(bad2, 3), collapse = ","))
if (length(.ov_layers(list(list(OA), list(OB, OC)))) == 3L && length(.ov_layers(list(kind = "x"))) == 1L && !length(.ov_layers("x")))
  ok(".ov_layers 중첩 평탄화 — list(list(A), list(B,C)) → 3층 · 단수 1층 · 비리스트 0층") else ng(".ov_layers 평탄화")
oc <- .ov_own_layers(list(overlay = list(OC, OA, OB)), carry = OC)
if (length(oc) == 2L && identical(oc[[1]]$arm_id, "dd_brake_q")) ok(".ov_own_layers = overlay − carry") else ng(".ov_own_layers", as.character(length(oc)))
oc2 <- .ov_own_layers(list(overlay = list(OC, OA, OB), overlay_cell = OB), carry = OC)
if (length(oc2) == 1L && identical(oc2[[1]]$arm_id, "dbeta_tilt_rank")) ok(".ov_own_layers 는 overlay_cell 을 정본으로") else ng("overlay_cell 우선")
if (length(.ov_own_layers(list(overlay = list(OC, OA)), carry = NULL)) == 2L) ok(".ov_own_layers carry 불명 → 전부(보수)") else ng("carry 불명 폴백")

cat("=== 5. 러너 배선 ===\n")
body <- paste(sub("#.*$", "", src), collapse = "\n")
for (nm in c(".seen_sig", "cell_duplicate_spec")) {
  if (grepl(nm, body, fixed = TRUE)) ok(sprintf("%s 배선", nm)) else
    ng(sprintf("%s 미배선", nm), "계기에 소비자가 없다")
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_spec_dedup","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
