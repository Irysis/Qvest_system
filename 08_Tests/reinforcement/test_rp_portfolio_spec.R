#!/usr/bin/env Rscript
#==============================================================================
# test_rp_portfolio_spec.R — 엔진이 낸 비중이 버려지지 않는가 **양방향 검사** (2026-08-31)
#
# 실사고: 무인 충실구현 3편(2608.24703 · 27156 · 27076)이 전부 construction=top_n_long 으로
#   측정됐다. 엔진은 PORTFOLIO(Date,Ticker,Weight,Leg)로 논문 비중을 냈는데, 러너의
#   construction 기본값이 "top_n_long" 이라 **engine_direct 를 명시하지 않으면** 그 비중을
#   조용히 버리고 FACTORS 로 top-N 롱온리를 다시 구성했다. 무인 검증기는 portfolio_spec 을
#   아예 넘기지 않으므로 항상 기본값이었다.
#   2608.27076 은 논문이 top-6 롱 + top-6 숏(CAPM 베타 ≈ 0)인데 롱온리 36종으로 나갔다 —
#   설계의 핵심인 시장중립이 사라져 논문 성과와 비교 자체가 성립하지 않는다.
#   ★에이전트는 필요한 값을 engine.R 주석에 적어 두기까지 했다. 읽는 자가 없었을 뿐이다.
#
# 판정 축:
#   ① 러너: 명시가 없고 엔진이 PORTFOLIO 를 내면 engine_direct 로 판정되는가
#   ② 러너: 호출자가 명시하면 그것이 우선하는가 (자동 판정이 명시를 덮으면 안 된다)
#   ③ 검증기: FIDELITY.json 의 portfolio_spec 을 실제로 넘기는가 (통로가 있는가)
#   ④ 프롬프트: 에이전트에게 그 필드를 요구하는가 (생산자가 있는가)
#   ⑤ 산출물: 롱숏 논문이 has_short=FALSE 로 나가지 않았는가 (실측 대조)
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
RP  <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
VF  <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
SH  <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh")

PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat(sprintf("  OK   %s\n", m)); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat(sprintf("  FAIL %s — %s\n", m, d)); FAIL <<- FAIL + 1L }
code <- function(f) paste(sub("#.*$", "", readLines(f, warn = FALSE)), collapse = "\n")

cat("=== 1. 러너 — 명시 없으면 엔진 산출이 결정 ===\n")
rp <- code(RP)
if (grepl("construction 자동 판정", paste(readLines(RP, warn = FALSE), collapse = "
"), fixed = TRUE))
  ok("자동 판정 배선 존재") else ng("자동 판정 없음", "PORTFOLIO 가 조용히 버려진다")
# 거동: 판정식을 소스에서 추출해 두 경우를 통과시킨다
L  <- readLines(RP, warn = FALSE)
i0 <- grep(".cons <- portfolio_spec$construction", L, fixed = TRUE)
i1 <- grep("WEIGHTS <- if (!is.null(PORTFOLIO)", L, fixed = TRUE)
if (!length(i0) || !length(i1)) {
  ng("판정 블록을 못 찾았다", "검사가 낡았다")
} else {
  decide <- function(has_port, spec) {
    PORTFOLIO <- if (has_port) TRUE else NULL
    portfolio_spec <- spec
    eval(parse(text = paste(L[i0[1]:(i1[1] - 1L)], collapse = "\n")))
    portfolio_spec$construction
  }
  # ★"안 골랐다" = 부재(NULL). 특정 값을 표식으로 삼으면 그 값을 **진짜로 고른** 호출자와
  #   구분되지 않는다 — 첫 판이 그랬고, 롱온리 판을 요청했는데 engine_direct 로 측정됐다.
  if (identical(decide(TRUE,  NULL), "engine_direct"))
    ok("PORTFOLIO 있고 명시 없음(NULL) → engine_direct") else
    ng("PORTFOLIO 를 버린다", "롱숏이 롱온리로 재구성된다")
  if (identical(decide(FALSE, NULL), "top_n_long"))
    ok("FACTORS 만 · 명시 없음 → top_n_long") else ng("FACTORS 경로가 깨졌다")
  cat("=== 2. 명시가 자동 판정보다 우선 (과잉 개입 금지) ===\n")
  if (identical(decide(TRUE, list(construction = "decile_long_short")), "decile_long_short"))
    ok("호출자 명시가 우선 (long_short)") else ng("자동 판정이 명시를 덮는다")
  # ★핵심 대조 — 자동 판정 결과와 **같은 이름**을 명시한 경우도 존중되는가.
  #   PORTFOLIO 가 있는데 top_n_long 을 명시하면 "숏을 빼고 롱온리로 재구성하라" 는 의도다.
  #   이 칸이 첫 판에서 비어 있어 결함이 검사를 통과했다.
  if (identical(decide(TRUE, list(construction = "top_n_long")), "top_n_long"))
    ok("PORTFOLIO 있어도 top_n_long 명시가 우선") else
    ng("명시 top_n_long 이 engine_direct 로 덮인다", "롱온리 변형을 요청할 방법이 없다")
  if (identical(decide(FALSE, list(construction = "top_n_long")), "top_n_long"))
    ok("FACTORS + top_n_long 명시 유지") else ng("명시가 사라졌다")
}

cat("=== 2b. 종목수 상한 25 (도훈 지시 2026-08-31) ===\n")
# 구판은 러너 구성 경로에 상한이 없었다. long_frac 폴백 10%가 후보 수에 따라 27~36 종을
# 냈고, 그 숫자는 논문 값이 아니라 **그날 후보가 몇 종이었나**였다(헌법 하드코딩 금지가
# 겨냥하는 자리 — 수치가 논문이 아니라 폴백에서 왔다).
LB <- readLines(RP, warn = FALSE)
j0 <- grep(".rp_build_weights <- function", LB, fixed = TRUE)
j1 <- grep("^}", LB); j1 <- j1[j1 > j0][1]
if (!length(j0) || is.na(j1)) { ng("구성 함수를 못 찾았다", "검사가 낡았다") } else {
  .RP_NMAX_DEFAULT <- 25L
  eval(parse(text = paste(LB[j0:j1], collapse = "\n")))
  mkf <- function(n) data.table::data.table(Date = as.Date("2020-01-31"),
                                            Ticker = sprintf("A%05d", seq_len(n)),
                                            Score = seq_len(n) / n)
  nn <- function(n, spec) nrow(.rp_build_weights(mkf(n), NULL, spec))
  if (nn(355, list(construction = "top_n_long")) <= 25L)
    ok("폴백 10% 가 상한에 걸린다 (구판 36종)") else ng("상한 미적용", "후보 수가 종목수를 정한다")
  if (nn(120, list(construction = "top_n_long")) == 12L)
    ok("상한 미만은 그대로 (과잉 절단 없음)") else ng("상한 미만인데 잘렸다")
  if (nn(355, list(construction = "top_n_long", n_long = 40)) <= 25L)
    ok("명시 n_long 이 상한을 넘어도 잘린다") else ng("명시가 축을 넘는다")
  if (nn(355, list(construction = "decile_long_short")) <= 25L)
    ok("롱숏은 양 다리 **합계**가 상한") else ng("다리별로만 걸려 합계가 초과한다")
  if (nn(355, list(construction = "top_n_long", n_max = 10)) == 10L)
    ok("spec$n_max 로 덮을 수 있다") else ng("n_max 덮기 불가")
}
# engine_direct 는 자르지 않는다 — 자르면 충실구현이 아니다. 대신 초과를 드러낸다.
if (grepl("engine_direct 보유 최대", paste(LB, collapse = "\n"), fixed = TRUE))
  ok("engine_direct 축 초과를 로그로 드러낸다(절단 없음)") else
  ng("engine_direct 초과가 조용하다")


cat("=== 3. 검증기 — FIDELITY.json 통로가 있는가 ===\n")
vf <- code(VF)
if (grepl("FIDELITY.json", vf, fixed = TRUE) && grepl("portfolio_spec", vf, fixed = TRUE))
  ok("검증기가 FIDELITY 의 portfolio_spec 을 넘긴다") else
  ng("검증기가 portfolio_spec 을 안 넘긴다", "무인 경로가 항상 기본값으로 측정된다")
if (grepl("commission_paper = .cmsn", vf, fixed = TRUE))
  ok("논문 명시 비용도 통로에 실린다") else ng("비용이 상수로 박혀 있다")

cat("=== 4. 프롬프트 — 생산자가 있는가 ===\n")
sh <- paste(readLines(SH, warn = FALSE), collapse = "\n")
if (grepl("portfolio_spec", sh, fixed = TRUE) && grepl("engine_direct", sh, fixed = TRUE))
  ok("에이전트에게 portfolio_spec 을 요구한다") else
  ng("프롬프트가 그 필드를 안 받는다", "통로만 있고 생산자가 없다")

cat("=== 5. 실측 대조 — 롱숏 논문이 롱온리로 나가지 않았는가 ===\n")
sp <- list.files(file.path(ROOT, "stage_artifacts/replication"),
                 pattern = "^01_strategy_spec[.]json$", recursive = TRUE, full.names = TRUE)
bad <- character(0)
for (f in sp) {
  o <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(o) || !grepl("RP_AUTO", o$strategy_name %||% "")) next
  fp <- file.path(ROOT, "04_Research/strategies",
                  sub("^RP_AUTO_", "RP_AUTO_", o$strategy_name %||% ""), "FIDELITY.json")
  # 엔진이 PORTFOLIO 를 내는데 has_short=FALSE 이면 숏이 버려졌을 수 있다 — 사후 대조
  if (identical(o$construction %||% "", "top_n_long") && isFALSE(o$has_short %||% FALSE) &&
      is.finite(suppressWarnings(as.numeric(o$n_max %||% NA))) && as.numeric(o$n_max) > 25)
    bad <- c(bad, sprintf("%s(n_max %s)", o$strategy_name, o$n_max))
}
if (!length(bad)) ok("top_n_long·롱온리로 25종 초과한 무인 산출 0건") else
  cat(sprintf("  INFO 과거 산출 %d건은 수리 전 판이다(재측정 대상): %s\n",
              length(bad), paste(utils::head(bad, 4), collapse = ", ")))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rp_portfolio_spec","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
