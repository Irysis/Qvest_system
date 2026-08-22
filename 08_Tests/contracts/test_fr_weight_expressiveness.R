## test_fr_weight_expressiveness.R — FR 배분 규칙 표현력 진단 (양방향: 위반 주입 + 양성 대조)
## ★근거: R54(2026-08-22) — n=21 에서 softmax(tau=0.6)가 국면 신호를 91% 압축해 출력이 정적 rp 와
##   구분 불가였는데(대응표본 NW-t +0.225) 산출물은 여전히 "국면조건부 비중" 으로 라벨됐다 = 침묵 실패.
## ★검사 설계 — 한 방향만 재면 통과가 무의미하다:
##   (a) 퇴화 케이스에서 **발화해야** 한다 (검출력)
##   (b) 표현 케이스에서 **발화하면 안 된다** (오탐 없음)
##   (c) 진단값 자체가 R54 실측을 재현해야 한다 (계기 정합)
suppressPackageStartupMessages({library(data.table)})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
source("02_Infrastructure/portfolio/module_dispatcher.R")

PASS <- 0L; FAIL <- 0L
chk <- function(nm, ok, d = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", nm)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", nm, d)) }
}
# 경고를 잡되 결과는 그대로 받는다
grab <- function(expr) {
  wm <- NULL
  v <- withCallingHandlers(expr,
        warning = function(cond) { wm <<- c(wm, conditionMessage(cond)); invokeRestart("muffleWarning") })
  list(w = v, warns = wm, fired = length(wm) > 0L)
}
mk <- function(n, ir, vol = 1) setNames(rep(vol, n), paste0("m", 1:n))

cat("=== A. 위반 주입: 모듈 수가 많아 신호가 압축되는 케이스 (R54 실사고 재현) ===\n")
set.seed(20260822)
n21 <- 21L
ir21 <- setNames(seq(-0.5, 1.5, length.out = n21), paste0("m", 1:n21))   # 뚜렷한 IR 스프레드
vo21 <- mk(n21, 0, 0.15)
nr21 <- setNames(rep(60L, n21), paste0("m", 1:n21))
g21 <- grab(compute_regime_module_weights(ir21, vo21, nr21))
d21 <- fr_weight_expressiveness(g21$w)
cat(sprintf("    n=21 retention = %.4f (압축 %.0f%%) | dev_from_ew = %.4f\n",
            d21$retention, 100 * (1 - d21$retention), d21$dev_from_ew))
chk("★n=21 퇴화에서 경고 발화 (검출력)", isTRUE(g21$fired), sprintf("(fired=%s)", g21$fired))
chk("경고 문구가 '국면조건부 라벨 금지' 를 명시", any(grepl("국면조건부", g21$warns %||% "")))
chk("retention 이 문턱 미만", is.finite(d21$retention) && d21$retention < .FR_HP$min_retention,
    sprintf("(%.4f)", d21$retention))
chk("★R54 실측 재현: 압축률 75%% 이상", (1 - d21$retention) > 0.75, sprintf("(%.1f%%)", 100*(1-d21$retention)))

cat("\n=== B. 양성 대조: 모듈 수가 적어 규칙이 표현 가능한 케이스 (오탐 없음) ===\n")
n5 <- 5L
ir5 <- setNames(seq(-0.5, 1.5, length.out = n5), paste0("m", 1:n5))
g5 <- grab(compute_regime_module_weights(ir5, mk(n5, 0, 0.15), setNames(rep(60L, n5), paste0("m", 1:n5))))
d5 <- fr_weight_expressiveness(g5$w)
cat(sprintf("    n=5 retention = %.4f | dev_from_ew = %.4f\n", d5$retention, d5$dev_from_ew))
chk("★n=5 에서는 경고 미발화 (오탐 없음)", isFALSE(g5$fired), sprintf("(fired=%s)", g5$fired))
chk("★n=5 retention 이 n=21 보다 크다 (n 이 원인임을 실증)", d5$retention > d21$retention,
    sprintf("(%.4f vs %.4f)", d5$retention, d21$retention))
chk("n=5 비중 분산이 n=21 보다 크다", sd(as.numeric(g5$w)) > sd(as.numeric(g21$w)))

cat("\n=== C. 진단이 '신호 없음' 과 '신호 압축' 을 구분하는가 ===\n")
## IR 이 전부 동일하면 애초에 벗어날 신호가 없다 — 이건 규칙 결함이 아니다
irflat <- setNames(rep(0.5, n21), paste0("m", 1:n21))
gf <- grab(compute_regime_module_weights(irflat, vo21, nr21))
df <- fr_weight_expressiveness(gf$w)
cat(sprintf("    IR 평탄 n=21: intended_dev = %.6f · retention = %s\n", df$intended_dev,
            ifelse(is.finite(df$retention), sprintf("%.4f", df$retention), "NA")))
chk("★신호 자체가 없으면(intended_dev≈0) 오분류하지 않는다",
    df$intended_dev < 1e-6 || !isTRUE(gf$fired), sprintf("(dev=%.6f fired=%s)", df$intended_dev, gf$fired))

cat("\n=== D. 계약 방어 + 회귀 ===\n")
g1 <- grab(compute_regime_module_weights(setNames(1, "solo"), setNames(0.1, "solo")))
chk("모듈 1개면 비중 1 (기존 계약 불변)", isTRUE(all.equal(as.numeric(g1$w), 1)))
chk("모듈 0개면 빈 벡터 (기존 계약 불변)",
    length(compute_regime_module_weights(setNames(numeric(0), character(0)), setNames(numeric(0), character(0)))) == 0L)
chk("★비중 합 = 1 (진단 추가가 값을 바꾸지 않음)", abs(sum(as.numeric(g21$w)) - 1) < 1e-10)
chk("★cap 0.25 준수 유지", max(as.numeric(g5$w)) <= .FR_HP$w_cap + 1e-9)
chk("이름 보존", identical(names(g21$w), paste0("m", 1:n21)))
chk("as.numeric() 하면 attr 이 조용히 사라진다 (호출자 비파괴)",
    is.null(attr(as.numeric(g21$w), "fr_diag")))
chk("t(w) 가 기존대로 동작 (run_wf_ensemble.R:126 사용 형태)", ncol(t(g21$w)) == n21)

cat("\n=== E. 문턱 자체의 검출력 (돌연변이) ===\n")
hp_loose <- .FR_HP; hp_loose$min_retention <- 0
gl <- grab(compute_regime_module_weights(ir21, vo21, nr21, hp = hp_loose))
chk("★문턱을 0 으로 낮추면 발화가 멈춘다 (문턱이 실제 게이트임을 실증)", isFALSE(gl$fired))
hp_tight <- .FR_HP; hp_tight$min_retention <- 0.99
gt <- grab(compute_regime_module_weights(ir5, mk(n5,0,0.15), setNames(rep(60L,n5), paste0("m",1:n5)), hp = hp_tight))
chk("★문턱을 0.99 로 올리면 n=5 도 발화 (양방향 확인)", isTRUE(gt$fired))

cat(sprintf("\n=== 결과: PASS %d / FAIL %d ===\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
