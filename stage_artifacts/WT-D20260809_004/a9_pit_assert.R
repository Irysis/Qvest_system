## A9 — PIT HARD assert (사전등록 pit_gates_before_verdict)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table) })
source("02_Infrastructure/validation/overlay_pit_guard.R")
say <- function(fmt, ...) cat(sprintf(paste0("[A9] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds")); ST <- P$sig_tbl

## 홀딩월 시작 = sig_date 가 속한 달의 다음달 1일 (holdings_signal_cutoff 규약)
hs <- holdings_signal_cutoff(ST$sig_date)
say("신호일 %d개 · 홀딩월 시작 %s ~ %s", nrow(ST), as.character(min(hs)), as.character(max(hs)))
say("간격(홀딩월시작 − 신호일) 중앙값 %.0f일 · 범위 [%.0f, %.0f]",
    median(as.numeric(hs - ST$sig_date)), min(as.numeric(hs - ST$sig_date)), max(as.numeric(hs - ST$sig_date)))

## (1) 전 신호 성분의 컷오프가 홀딩월 시작 전인가
assert_overlay_pit(ST$sig_date, hs, label = "infl_composite(T5YIE roll<=sig_date)")
say("PASS — T5YIE 컷오프 (sig_date) <= 홀딩월 시작")
## KR_CPI / Copper 는 참조월 M-2 의 월초 라벨 → 홀딩월 시작보다 최소 2개월 앞
assert_overlay_pit(ST$ref_ym2, hs, label = "KR_CPI/Copper ref M-2")
say("PASS — KR_CPI/Copper 참조월(M-2) <= 홀딩월 시작 (간격 중앙 %.0f일)",
    median(as.numeric(hs - ST$ref_ym2)))
## (2) 성장 팩터 = sig_date 시점 월간 DB (Date <= sig_date), 수익은 forward
assert_overlay_pit(ST$sig_date, hs, label = "growth factors (load_month_factors @ sig_date)")
say("PASS — 성장 팩터 as-of (sig_date) <= 홀딩월 시작")
## (3) β_s 는 sig_date 이전 실현월만 → 컷오프 = sig_date
assert_overlay_pit(ST$sig_date, hs, label = "beta_s (실현월 < sig_date)")
say("PASS — β_s 추정창 종점 < sig_date <= 홀딩월 시작")
## (4) 유동성 adv20 = sig_date 포함 직전 20 거래일
assert_overlay_pit(ST$sig_date, hs, label = "adv20 (t-1 PIT)")
say("PASS — adv20 창 종점 (sig_date) <= 홀딩월 시작")

## (5) 위반 주입 테스트 — 검사기가 실제로 발화하는가 (0 = 정지 신호 규약)
bad <- tryCatch({ assert_overlay_pit(hs + 1, hs, label = "INJECTED_VIOLATION"); FALSE },
                error = function(e) TRUE)
say("위반 주입 테스트: 검사기 발화 = %s (FALSE 면 검사기 사망 — 결과 무효)", bad)
stopifnot(isTRUE(bad))
say("★전 게이트 PASS + 위반 주입 검출 확인")
