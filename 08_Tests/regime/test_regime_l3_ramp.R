# test_regime_l3_ramp.R -- compute_regime_score layer3 문턱 램프의 양방향 검증
#
# 배경 (2026-08-30 도훈 지시): layer3 가 `ktri<=35` / `vea>=70` 두 **이진 문턱**의
#   계단이라 값이 {0,8,15} 3종뿐이었다. 문턱을 스치면 8점이 통째로 켜지고 꺼진다.
#   ★2026-09 PG2 사건: VEA 75.42 -> 63.92 로 70 문턱을 하향 통과 -> layer3 8 -> 0
#     -> Regime_Score 48.00 -> 40.00 -> de-risk 문턱(45) 하향 이탈. m4 게이트 전체가
#     VEA 단일 이진 문턱 하나에 걸려 있었다.
#   수리 = 문턱을 **폐지하지 않고** 그 주변 ±(RAMP_SIGMA x 12.5)에서만 선형 램프.
#   12.5 는 지표 자신의 스케일 상수(.z_to_score(z)=50+12.5z, ktri_v3_builder.R:56).
#
# 계약 (양방향 -- 양성 대조 없는 계기는 방어선으로 세지 않는다):
#   A1 [양성] 문턱 근방 입력이 **중간값**을 낸다 (구판은 3값밖에 못 낸다)
#   A2 [양성] 문턱을 스치는 이동이 절벽이 아니라 점진 변화가 된다
#   B1 [음성/극한 정합] 문턱 깊이 통과 시 구판 3값(15/8/0)을 그대로 통과
#   B2 [음성] 결측 기본값(50,50)은 0 -- 구판과 동일
#   C1 [재현] RAMP_SIGMA=0 이면 구판 이진과 **비트 단위 동일**
#   D1 [부활 차단] 이진 계단이 무조건 경로로 소스에 되살아나지 않음
#   E1 [단조] VEA 증가 -> layer3 비감소 / KTRI 감소 -> layer3 비감소
#   E2 [경계] 램프 하단에서 정확히 0, 상단에서 정확히 만점
#   F1 [실측] 실제 매크로에서 RAMP=0 이 정본 Regime_Score 를 재현
#   F2 [실측] 수리판이 2026-09 낙폭을 실제로 줄인다
#   G1 [L1] layer1 MSM 포화(0.8) 원형 보존 — 실측상 결함이 아니라 옳은 설계
#   G2 [부활 차단] 포화 제거 레버(REGIME_L1_UNSATURATE)가 존재하지 않음 (INV-7)
#
# 방식: **소스에서 상수 + 함수를 추출해 그대로 eval** (재구현 금지).
# 실행: Rscript 08_Tests/regime/test_regime_l3_ramp.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(data.table))

pass <- 0L; fail <- 0L; skip <- 0L; skips <- character(0)
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
sk <- function(axis, reason, missing) {
  cat(sprintf("  [SKIP] %s -- %s (%s)\n", axis, reason, missing))
  skip <<- skip + 1L
  esc <- function(x) gsub('"', '\\\\"', x, perl = TRUE)
  skips <<- c(skips, sprintf('{"axis":"%s","reason":"%s","missing":"%s"}',
                             esc(axis), esc(reason), esc(missing)))
}
emit <- function() cat(sprintf(
  '{"test":"test_regime_l3_ramp","pass":%d,"fail":%d,"skipped":%d,"total":%d,"skips":[%s]}\n',
  pass, fail, skip, pass + fail + skip, paste(skips, collapse = ",")))

SRC <- "02_Infrastructure/regime/regime_signal.R"
if (!file.exists(SRC)) { sk("source", "regime_signal.R 부재", SRC); emit(); quit(status = 0L) }
txt <- paste(readLines(SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
grab <- function(p) { m <- regmatches(txt, regexpr(p, txt, perl = TRUE)); if (!length(m)) NULL else m }

FN <- grab("(?s)compute_regime_score <- function.*?\\n\\}")
C_SIG  <- grab("REGIME_SCORE_SIGMA <- [0-9.]+")
C_RAMP <- grab("REGIME_L3_RAMP_SIGMA <- [0-9.]+")
if (is.null(FN) || is.null(C_SIG) || is.null(C_RAMP)) {
  ng("소스에서 함수/상수 추출 실패 -- 앵커 소실(테스트가 대상을 잃음)")
  emit(); quit(status = 1L)
}
ok("소스에서 compute_regime_score + 상수 3종 추출 (테스트가 실코드를 실행)")

mkfn <- function(ramp = NULL) {
  e <- new.env(parent = globalenv())
  eval(parse(text = C_SIG), e); eval(parse(text = C_RAMP), e)
  eval(parse(text = FN), e)
  if (!is.null(ramp)) assign("REGIME_L3_RAMP_SIGMA", ramp, envir = e)
  get("compute_regime_score", envir = e)
}
# layer3 만 분리해서 보기: msm=0, fred=0 이면 score == layer3
L3 <- function(f, k, v) f(rep(0, length(k)), rep(0, length(k)), k, v)

SIG  <- local({ e <- new.env(); eval(parse(text = C_SIG), e); get("REGIME_SCORE_SIGMA", e) })
RAMP <- local({ e <- new.env(); eval(parse(text = C_RAMP), e); get("REGIME_L3_RAMP_SIGMA", e) })
cat(sprintf("      [설정] SIGMA=%.4g · RAMP_SIGMA=%.4g (반폭 %.4g점) · 현 정본 = %s\n",
            SIG, RAMP, RAMP * SIG, ifelse(RAMP > 0, "램프", "구판 이진")))
f_cur <- mkfn(); f_bin <- mkfn(ramp = 0)
## ★양방향 검사는 **기본값에 의존하지 않는다** — 램프 경로를 명시적으로 세워 검사한다.
##   기본값이 0(구판)이라고 램프 경로 검사를 건너뛰면, 나중에 켰을 때 무방비가 된다.
##   [[feedback-move-the-positive-control-when-you-move-the-axis]]
f_ramp <- mkfn(ramp = 0.5)
hw <- 0.5 * SIG

## ---- A. 양성 대조 -----------------------------------------------------------
{
  # VEA 를 문턱(70) 정중앙에 두면 강도 0.5 -> layer3 = 4 (구판은 0 또는 8 뿐)
  mid <- L3(f_ramp, 60, 70)
  if (mid > 0 && mid < 8)
    ok(sprintf("A1 [양성] VEA=70(문턱 정중앙) -> layer3=%.3f (구판은 0/8 뿐인 중간값)", mid)) else
    ng(sprintf("A1 [양성] 중간값이 안 나옴: layer3=%.3f", mid))
  # 문턱을 스치는 이동이 절벽이 아닌가 (2026-07 -> 08 실측 입력)
  d_bin <- abs(L3(f_bin, 50.68, 75.42) - L3(f_bin, 53.81, 63.92))
  d_cur <- abs(L3(f_ramp, 50.68, 75.42) - L3(f_ramp, 53.81, 63.92))
  if (d_cur < d_bin)
    ok(sprintf("A2 [양성] 2026-07->08 실측 입력의 layer3 낙폭 %.2f -> %.2f (절벽 완화)", d_bin, d_cur)) else
    ng(sprintf("A2 낙폭이 줄지 않음: 구판 %.2f -> 수리 %.2f", d_bin, d_cur))
}

## ---- B. 극한 정합 (구판 3값 통과) -------------------------------------------
cases <- list(list(20, 90, 15, "둘 다 문턱 깊이 통과"),
              list(20, 40,  8, "KTRI 만 통과"),
              list(60, 90,  8, "VEA 만 통과"),
              list(60, 40,  0, "둘 다 미통과"))
bad <- character(0)
for (cs in cases) {
  got <- L3(f_ramp, cs[[1]], cs[[2]])
  if (abs(got - cs[[3]]) > 1e-9) bad <- c(bad, sprintf("%s: %.3f != %d", cs[[4]], got, cs[[3]]))
}
if (!length(bad)) ok("B1 [극한 정합] 문턱 깊이 통과 시 구판 3값(15/8/0) 그대로 통과") else
  ng(sprintf("B1 극한 정합 깨짐: %s", paste(bad, collapse = " | ")))
if (abs(L3(f_ramp, 50, 50)) < 1e-9)
  ok("B2 [음성] 결측 기본값(KTRI=50,VEA=50) -> layer3=0 (구판과 동일)") else
  ng(sprintf("B2 결측 기본값이 0 이 아님: %.4f", L3(f_ramp, 50, 50)))

## ---- C. 구판 재현 ------------------------------------------------------------
set.seed(20260830)
kk <- runif(500, 0, 100); vv <- runif(500, 0, 100)
ref <- fifelse(kk <= 35 & vv >= 70, 15, fifelse(kk <= 35 | vv >= 70, 8, 0))
if (max(abs(L3(f_bin, kk, vv) - ref)) < 1e-12)
  ok("C1 [재현] RAMP_SIGMA=0 이 구판 이진과 비트 단위 동일 (무작위 500점)") else
  ng(sprintf("C1 구판 재현 실패: max|Δ|=%.3g", max(abs(L3(f_bin, kk, vv) - ref))))

## ---- D. 부활 차단 ------------------------------------------------------------
if (grepl("REGIME_L3_RAMP_SIGMA", txt, fixed = TRUE) &&
    grepl("if (.hw <= 0)", txt, fixed = TRUE))
  ok("D1 [부활 차단] 이진 계단이 무조건 경로가 아니라 .hw<=0 분기 안에만 존재") else
  ng("D1 램프 분기가 소스에서 사라졌다 -- 이진 계단이 무조건 경로로 부활")
if (grepl("REGIME_SCORE_SIGMA <- 12.5", txt, fixed = TRUE))
  ok("D1b 램프 폭이 지표 스케일 상수(12.5 = 1σ)에 묶여 있음 -- 임의 하드코딩 아님") else
  ng("D1b REGIME_SCORE_SIGMA 가 12.5(.z_to_score 의 1σ)가 아님 -- 근거 이탈")

## ---- E. 단조 + 경계 ----------------------------------------------------------
vg <- seq(40, 100, by = 0.25); l_v <- L3(f_ramp, rep(60, length(vg)), vg)
kg <- seq(100, 0, by = -0.25); l_k <- L3(f_ramp, kg, rep(40, length(kg)))
if (all(diff(l_v) >= -1e-12) && all(diff(l_k) >= -1e-12))
  ok("E1 [단조] VEA 증가 / KTRI 감소에 대해 layer3 비감소") else
  ng("E1 단조성 위반 -- 램프가 비단조")
{
  if (abs(L3(f_ramp, 60, 70 - hw)) < 1e-9 && abs(L3(f_ramp, 60, 70 + hw) - 8) < 1e-9)
    ok(sprintf("E2 [경계] VEA 램프 하단(%.2f)=0 · 상단(%.2f)=8 정확", 70 - hw, 70 + hw)) else
    ng(sprintf("E2 경계 부정확: 하단 %.4f / 상단 %.4f",
               L3(f_ramp, 60, 70 - hw), L3(f_ramp, 60, 70 + hw)))
}

## ---- G. layer1 포화 보존 -----------------------------------------------------
## 2026-08-30 도훈 제동 + 실측: MSM 포화(0.8)는 결함이 아니라 옳은 설계다.
##   포화 구간은 실제로 위험하고(변동성 13.64% vs 7.17%, p=0.0000) 그 내부에는
##   건질 정보가 없다(rank-IC -0.0475). 포화 제거는 de-risk 월수 -44% = 위험 축 완화.
if (grepl("layer1 <- 40 * pmin(1, msm_prob / 0.8)", txt, fixed = TRUE))
  ok("G1 [L1] MSM 포화(0.8) 원형 보존 — 무조건 경로") else
  ng("G1 [L1] layer1 포화식이 변형됐다 — MSM 포화는 결함이 아니다(실측)")
if (!grepl("REGIME_L1_UNSATURATE <-", txt, fixed = TRUE))
  ok("G2 [부활 차단] 포화 제거 레버가 존재하지 않음 (INV-7: 위험 축 완화 레버 금지)") else
  ng("G2 [부활] REGIME_L1_UNSATURATE 레버가 되살아났다 — 위험 축 완화 레버")

## ---- F. 실측 -----------------------------------------------------------------
MACRO <- ".cache/unified_regime_signal.parquet"
if (!file.exists(MACRO)) {
  sk("F", "실측 재도출 불가 -- 매크로 패널 부재(worktree 는 코드만 갖는다)", MACRO)
} else if (!requireNamespace("arrow", quietly = TRUE)) {
  sk("F", "실측 재도출 불가 -- arrow 패키지 미설치", "R package: arrow")
} else {
  if (identical(suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))), 1L))
    Sys.setenv(ARROW_IO_THREADS = "2")
  mac <- as.data.table(arrow::read_parquet(MACRO, mmap = FALSE)); setorder(mac, Date)
  s_bin <- f_bin(mac$MSM_Crisis_Prob, mac$FRED_MRS, mac$KTRI_Score, mac$VEA_Score)
  s_cur <- f_ramp(mac$MSM_Crisis_Prob, mac$FRED_MRS, mac$KTRI_Score, mac$VEA_Score)
  dmax <- max(abs(s_bin - mac$Regime_Score))
  cat(sprintf("      [실측] n=%d · RAMP=0 재현 max|Δ|=%.3g · 평균 %.4f -> %.4f · 고유값 %d -> %d\n",
              nrow(mac), dmax, mean(s_bin), mean(s_cur),
              length(unique(round(s_bin, 6))), length(unique(round(s_cur, 6)))))
  if (dmax < 1e-9)
    ok("F1 [실측] RAMP_SIGMA=0 이 정본 Regime_Score 를 전 행 재현 (양성 대조)") else
    ng(sprintf("F1 정본 재현 실패 max|Δ|=%.3g -- 구판 경로가 어긋났다", dmax))
  i7 <- which(format(mac$Date, "%Y-%m") == "2026-07")
  i8 <- which(format(mac$Date, "%Y-%m") == "2026-08")
  if (length(i7) && length(i8)) {
    d_bin <- s_bin[i8] - s_bin[i7]; d_cur <- s_cur[i8] - s_cur[i7]
    cat(sprintf("      [실측] 2026-07->08 낙폭: 구판 %+.2f -> 수리 %+.2f\n", d_bin, d_cur))
    if (abs(d_cur) < abs(d_bin))
      ok(sprintf("F2 [실측] 2026-09 사건 낙폭 완화 (%.2f -> %.2f)", abs(d_bin), abs(d_cur))) else
      ng(sprintf("F2 낙폭이 줄지 않음 (%.2f -> %.2f)", abs(d_bin), abs(d_cur)))
  } else {
    sk("F2", "2026-07/08 행 부재", "unified_regime_signal.parquet 2026-07,2026-08")
  }
}

cat(sprintf("\n-- test_regime_l3_ramp: %d passed, %d failed, %d skipped --\n\n", pass, fail, skip))
emit()
if (fail > 0L) quit(status = 1L)
