## test_label_eligibility_gate.R — 라벨 자격 관문 위반 주입 테스트 (FQ-119)
##
## 이 검사가 재는 것: 관문이 **자격 없는 라벨을 실제로 막는가**, 그리고
##   **자격 있는 라벨을 잘못 막지 않는가**(양방향). 한쪽만 재면 항상-차단/항상-통과를 구별 못 한다.
##
## ★설계: 합성 케이스로 경계를 재고, **실제 국면 라벨**로 현장 검출을 실증한다
##   (합성만 쓰면 "현실에서 발화하는가"를 못 본다 — 오늘 계통).
##
## 실행: Rscript 08_Tests/contract_regression/test_label_eligibility_gate.R

.root <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = Sys.getenv("QM_ROOT", unset = getwd()))
setwd(.root)
source("02_Infrastructure/contracts/label_eligibility_gate.R")

pass <- 0L; fail <- 0L
ck <- function(label, cond) {
  if (isTRUE(cond)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s\n", label)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s\n", label)) }
}
set.seed(20260808L)

## ── A. 자격 있는 라벨 = 통과해야 함 (양성 대조) ────────────────────────────
n <- 300L
evt <- rep(FALSE, n); evt[sample(n, 60)] <- TRUE          # base 0.20
lab <- evt                                                 # 완벽 라벨
lab[sample(which(evt), 15)] <- FALSE                       # recall 손실
lab[sample(which(!evt), 10)] <- TRUE                       # 오경보 소량
gA <- label_eligibility(lab, evt)
ck("A1 판별력 있는 라벨 → eligible TRUE", isTRUE(gA$eligible))
ck("A2 recall > base", gA$recall > gA$base_rate)
ck("A3 fisher p < 0.05", gA$fisher_p < 0.05)
ck("A4 verdict = ELIGIBLE", identical(gA$verdict, "ELIGIBLE"))

## ── B. 위반 주입: 무작위 라벨 = 반드시 차단 ────────────────────────────────
lab_rand <- rep(FALSE, n); lab_rand[sample(n, 60)] <- TRUE
gB <- label_eligibility(lab_rand, evt)
ck("B1 무작위 라벨 → eligible FALSE", identical(gB$eligible, FALSE))
ck("B2 verdict = INELIGIBLE_NO_DISCRIMINATION",
   identical(gB$verdict, "INELIGIBLE_NO_DISCRIMINATION"))

## ── C. 위반 주입: 역방향 라벨(사건을 피해 켜짐) = 차단 ─────────────────────
lab_inv <- !evt
gC <- label_eligibility(lab_inv, evt)
ck("C1 역방향 라벨 → eligible FALSE", identical(gC$eligible, FALSE))
ck("C2 recall < base (방향 확인)", gC$recall < gC$base_rate)

## ★양방향 실증 — 통과와 차단이 실제로 갈리는가(항상 같은 답이면 검사 사망)
ck("★검출력: 자격 라벨 ≠ 무작위 라벨 판정", !identical(gA$eligible, gB$eligible))

## ── D. 빈 결과 = 합격으로 새지 않아야 함 ───────────────────────────────────
gD1 <- label_eligibility(logical(0), logical(0))
ck("D1 빈 입력 → UNMEASURABLE (TRUE 아님)", identical(gD1$verdict, "UNMEASURABLE_NO_DATA"))
ck("D2 빈 입력 → eligible NA (FALSE 도 TRUE 도 아님)", is.na(gD1$eligible))
gD2 <- label_eligibility(rep(FALSE, 50), c(rep(TRUE, 10), rep(FALSE, 40)))
ck("D3 라벨 상수 → UNMEASURABLE_DEGENERATE", identical(gD2$verdict, "UNMEASURABLE_DEGENERATE"))
gD3 <- label_eligibility(c(rep(TRUE, 10), rep(FALSE, 40)), rep(FALSE, 50))
ck("D4 사건 0건 → UNMEASURABLE_DEGENERATE", identical(gD3$verdict, "UNMEASURABLE_DEGENERATE"))

## ── E. NA 처리: 공통 관측만 사용 ───────────────────────────────────────────
lab_na <- lab; lab_na[1:20] <- NA
gE <- label_eligibility(lab_na, evt)
ck("E1 NA 제외 후 n 감소", gE$n == n - 20L)
ck("E2 NA 있어도 판정 성립", !is.na(gE$eligible))

## ── F. assert 가 실제로 중단시키는가 (차단 실효) ───────────────────────────
okF <- tryCatch({ assert_label_eligible(lab_rand, evt, "무작위라벨"); FALSE },
                error = function(e) grepl("자격 미달", conditionMessage(e)))
ck("F1 무자격 라벨에 assert stop 발화", isTRUE(okF))
okF2 <- tryCatch({ assert_label_eligible(lab, evt, "자격라벨"); TRUE }, error = function(e) FALSE)
ck("F2 자격 라벨은 통과(오차단 없음)", isTRUE(okF2))

## ── G. ★현장 실증: 실제 국면 라벨이 이 관문에 걸리는가 ─────────────────────
##   08-03 실측(WT-017/019)은 CRISIS 라벨 recall 0.096 < base 0.457 이었다.
##   재료가 있으면 그 사실이 관문에서 재현되는지 본다(없으면 skip — 거짓 통과 금지).
##   ★2026-08-08 실측으로 규약 확정 — 정본은 `.cache/unified_regime_signal.parquet` 의 `Category`
##   (`regime_daily_v2.parquet` 에는 라벨 컬럼이 없다 — 원장 오기재였음).
##   확립 사실: 자격은 **(라벨, 사건정의) 쌍**에 붙는다. 같은 라벨이 정의에 따라 뒤집힌다.
##     월수익<0%  → lift 1.16x, p 0.0511  INELIGIBLE
##     월수익<-5% → lift 1.97x, p<1e-4     ELIGIBLE
##     월수익<-10%→ lift 3.19x, p<1e-4     ELIGIBLE
##   이 축이 죽으면 "라벨 무자격" 과잉 일반화가 되살아난다(08-03 오판의 재발 경로).
.lab_f <- ".cache/unified_regime_signal.parquet"; .bm_f <- ".cache/benchmark.parquet"
if (file.exists(.lab_f) && file.exists(.bm_f) &&
    requireNamespace("arrow", quietly = TRUE) && requireNamespace("data.table", quietly = TRUE)) {
  suppressPackageStartupMessages({library(data.table); library(arrow)})
  u <- tryCatch(as.data.table(read_parquet(.lab_f)), error = function(e) NULL)
  b <- tryCatch(as.data.table(read_parquet(.bm_f)),  error = function(e) NULL)
  if (!is.null(u) && !is.null(b) && "Category" %in% names(u)) {
    u[, ym := format(as.Date(Date), "%Y%m")]                 # YM 컬럼 불신 — Date 에서 재생성
    setnames(b, tolower(names(b)))
    b[, date := as.Date(date)][, ym := format(date, "%Y%m")]
    mk <- b[, .(bm_m = prod(1 + bm_ret) - 1), by = ym]
    m  <- merge(u[, .(ym, Category)], mk, by = "ym")[!is.na(bm_m)]
    ck("G0 현장 병합 비어있지 않음 (0 을 결론으로 쓰지 않음)", nrow(m) > 300L)
    on <- m$Category %in% c("CRISIS", "CAUTION")
    g0  <- label_eligibility(on, m$bm_m < 0)
    g5  <- label_eligibility(on, m$bm_m < -0.05)
    g10 <- label_eligibility(on, m$bm_m < -0.10)
    cat(sprintf("  [현장] n=%d · <0%%: lift %.2f p %.4f | <-5%%: lift %.2f p %.4f | <-10%%: lift %.2f p %.4f\n",
                nrow(m), g0$lift, g0$fisher_p, g5$lift, g5$fisher_p, g10$lift, g10$fisher_p))
    ck("G1 사건 <-5% 에서 자격 통과 (lift>1.5)", isTRUE(g5$eligible) && g5$lift > 1.5)
    ck("G2 사건 <-10% 에서 자격 통과 (lift>2.5)", isTRUE(g10$eligible) && g10$lift > 2.5)
    ck("G3 ★사건 정의 조건부 — <0% 와 <-10% 판정이 갈린다",
       !identical(g0$eligible, g10$eligible))
    ck("G4 심할수록 판별력 증가 (lift 단조)", g0$lift < g5$lift && g5$lift < g10$lift)
  } else {
    cat("  [skip] 라벨 정본 읽기 실패 또는 Category 부재 — 현장 축 미실행(합격으로 세지 않음)\n")
  }
} else {
  cat("  [skip] 라벨/벤치 패널 부재 — 현장 축 미실행(합격으로 세지 않음)\n")
}

cat(sprintf("\n[test_label_eligibility_gate] PASS=%d FAIL=%d\n", pass, fail))
cat(sprintf('{"test":"label_eligibility_gate","pass":%d,"fail":%d,"total":%d}\n',
            pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
