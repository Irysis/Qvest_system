## test_governor_dir_resolution.R — governor 의 ΔIR 해상도 경고 검사
## 배경(2026-08-09): pg1_admission_with_book_context() 가 **점추정으로 ADMIT/DEFER** 를 판정한다.
##   그런데 문턱 0.05 는 269개월 전기간에서도 1.09 표준오차 — 문턱 근처 통과는 잡음과 구분 불가.
##   ★결정 규칙은 도훈 권한이라 바꾸지 않았고, **해상도 라벨을 인증 문서에 붙이는** 부가만 했다.
## 이 검사는 ①경고가 문턱 근처에서 발화하는가 ②멀리 떨어지면 침묵하는가
##   ③표본 미상이면 UNKNOWN 으로 명시하는가 ④**결정을 바꾸지 않는가**(비파괴)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")

P <- 0L; F <- 0L
ok <- function(c, m) { if (isTRUE(c)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", m)) }
                       else { F <<- F+1L; cat(sprintf("  FAIL  %s\n", m)) } }
cat("=== test_governor_dir_resolution ===\n")

## 판정 함수를 소스에서 그대로 추출해 단위 검사 (governor 전체 로드는 부작용이 크다)
src <- readLines("02_Infrastructure/portfolio/portfolio_governor.R", warn = FALSE, encoding = "UTF-8")
i0 <- grep("\\.pg_dir_resolution <- function", src)
ok(length(i0) == 1L, "0a. .pg_dir_resolution 정의가 정확히 1곳")
i1 <- i0 + which(grepl("^  \\}$", src[(i0+1):(i0+60)]))[1]
`%||%` <- function(a,b) if (is.null(a)) b else a
eval(parse(text = paste(src[i0:i1], collapse = "\n")))
ok(is.function(.pg_dir_resolution), "0b. 추출·평가 성공")

THR <- 0.05
## n=269 → se 하한 0.0460 · 2se 0.0920 (문턱에서 이만큼 안이면 판별 불가)
## n=73  → se 하한 0.0883 · 2se 0.1766

cat("-- 1. 문턱 근처 = UNRESOLVED 발화 (핵심 회귀) --\n")
r1 <- .pg_dir_resolution(0.0740, THR, 73L)     # 오늘 실사고 값
ok(identical(r1$state, "UNRESOLVED"),
   sprintf("1a. 실사고 재현 ΔIR 0.0740 @ n=73 → %s", r1$state))
ok(grepl("구분할 수 없다", r1$note, fixed = TRUE), "1b. 경고문이 판별 불가를 명시")
r2 <- .pg_dir_resolution(0.0600, THR, 269L)
ok(identical(r2$state, "UNRESOLVED"), sprintf("1c. ΔIR 0.0600 @ n=269 → %s (전기간에서도 근처는 불가)", r2$state))
r3 <- .pg_dir_resolution(0.1200, THR, 269L)
ok(identical(r3$state, "UNRESOLVED"), sprintf("1d. ΔIR 0.1200 @ n=269 (간격 0.070 < 2se 0.092) → %s", r3$state))

cat("-- 2. 충분히 멀면 침묵 (음성 대조 — 항상 경고하면 무정보) --\n")
r4 <- .pg_dir_resolution(0.3000, THR, 269L)
ok(identical(r4$state, "OUTSIDE_BAND"), sprintf("2a. ΔIR 0.3000 @ n=269 → %s", r4$state))
r5 <- .pg_dir_resolution(-0.2000, THR, 269L)
ok(identical(r5$state, "OUTSIDE_BAND"), sprintf("2b. ΔIR -0.2000 (큰 음수 = 탈락 유효) → %s", r5$state))
ok(grepl("판별 가능", r4$note) && grepl("증명이 아니다", r4$note),
   "2c. ★OUTSIDE_BAND 도 '판별 가능' 을 주장하지 않는다 (단측 판정 명시)")

cat("-- 3. 표본 길이 의존성 (같은 ΔIR 이 n 에 따라 갈린다) --\n")
d <- 0.1500
s_short <- .pg_dir_resolution(d, THR, 60L)$state
s_long  <- .pg_dir_resolution(d, THR, 269L)$state
ok(identical(s_short, "UNRESOLVED") && identical(s_long, "OUTSIDE_BAND"),
   sprintf("3. ΔIR %.3f: n=60 → %s · n=269 → %s (표본이 판정을 바꾼다)", d, s_short, s_long))
ok(.pg_dir_resolution(d, THR, 60L)$se_lower_bound > .pg_dir_resolution(d, THR, 269L)$se_lower_bound,
   "3b. 짧은 표본의 se 하한이 더 크다")

cat("-- 4. 결측/이상 입력 (조용한 통과 금지) --\n")
ok(identical(.pg_dir_resolution(0.07, THR, NA)$state, "UNKNOWN"), "4a. n 결측 → UNKNOWN")
ok(identical(.pg_dir_resolution(0.07, THR, 5L)$state, "UNKNOWN"), "4b. n<12 → UNKNOWN")
ok(identical(.pg_dir_resolution(NA_real_, THR, 269L)$state, "UNKNOWN"), "4c. ΔIR 결측 → UNKNOWN")
ok(!any(vapply(list(.pg_dir_resolution(0.07, THR, NA), .pg_dir_resolution(NA_real_, THR, 269L)),
               function(x) identical(x$state, "OUTSIDE_BAND"), TRUE)),
   "4d. ★결측이 OUTSIDE_BAND(=안심) 로 내려앉지 않는다")

cat("-- 5. 비파괴: 결정 로직을 바꾸지 않았는가 (소스 검사) --\n")
dec <- grep("artifact\\$decision <- \"DEFER\"", src)
ok(length(dec) >= 2L, sprintf("5a. 기존 DEFER 전환 지점 %d곳 보존", length(dec)))
res_blk <- grep("book_delta_ir_resolution", src)
ok(length(res_blk) >= 1L, "5b. 해상도 필드가 artifact 에 기록됨")
## 해상도 경고가 decision 을 건드리지 않는지 — 경고 블록 안에 decision 대입이 없어야
i2 <- grep("해상도 경고", src)[1]
ok(is.finite(i2) && !any(grepl("artifact\\$decision <-", src[max(1,i2-3):(i2+2)])),
   "5c. ★경고 블록이 decision 을 변경하지 않는다 (자본 게이트는 도훈 권한)")

cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", P, F))
# 2026-08-20: 배터리는 마지막 줄의 JSON 요약만 읽는다. 이 줄이 없어 이 파일은
#   등재조차 되지 못했다(측정 권위 계약이 회귀 보호 밖에 있었음).
cat(sprintf("{\"test\":\"test_governor_dir_resolution\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", P, F, P + F))
if (F > 0) quit(status = 1L)
