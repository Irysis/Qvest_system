## P3R02 evaluate.R 순수 도우미 픽스처 검사(합성 · 결과 무접촉 · 사전등록 고정 대상) — 본 실행 블록은 sys.nframe() > 0 이라 안 돈다
## 실행: Rscript evaluate_fixture.R   (공통 창 사본 · 위기 짝 · 로그 파싱 · 이력 탈락 · 전달률 · 위기 보유 집행일 · β 대조)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/evaluate.R")
if (exists("EVS")) ng("본 실행 블록이 source 에서 돌았다") else ok("source 시 본 실행 블록 미실행(sys.nframe 가드)")

## 1) 공통 창 사본
src <- file.path(tempdir(), "art_src"); out <- file.path(tempdir(), "art_out"); unlink(c(src, out), recursive = TRUE); dir.create(src)
d <- seq(as.Date("2005-01-03"), by = "day", length.out = 40)
r <- c(rep(0.01, 10), rep(-0.02, 10), rep(0.005, 20))
nav <- cumprod(1 + r)
fwrite(data.table(date = d, ret_net = r), file.path(src, "03_period_returns.csv"))
fwrite(data.table(date = d, benchmark_ret = r / 2, benchmark_nav = cumprod(1 + r / 2)), file.path(src, "05_benchmark_returns.csv"))
fwrite(data.table(date = d, nav_gross = nav * 1.001, nav_net = nav, cum_cost = nav * 0.001, drawdown_net = nav / cummax(nav) - 1), file.path(src, "02_nav.csv"))
fwrite(data.table(date = rep(d[c(1, 15, 30)], each = 2), ticker = rep(c("000660", "005930"), 3), target_weight = 0.5), file.path(src, "04_holdings.csv"))
writeLines('{"x":1}', file.path(src, "00_manifest.json")); writeLines('{"y":2}', file.path(src, "authoritative_remeasure.json"))
st <- d[20]                                                         # 낙폭 바닥 부근에서 자른다 → 새 창의 낙폭은 그 이후만
tr <- p3_trim_artifacts(src, out, st)
nv2 <- fread(file.path(out, "02_nav.csv")); nv2[, date := as.Date(date)]
br2 <- fread(file.path(out, "05_benchmark_returns.csv")); H2 <- fread(file.path(out, "04_holdings.csv"), colClasses = list(character = "ticker"))
if (min(as.Date(nv2$date)) == st && abs(nv2$nav_net[1] - 1) < 1e-12 && abs(nv2$drawdown_net[1]) < 1e-12 &&
    isTRUE(all.equal(nv2$drawdown_net, nv2$nav_net / cummax(nv2$nav_net) - 1)))
  ok("1a NAV 재기준 · 낙폭 재계산(시작 이전 고점 미혼입)") else ng("1a NAV/낙폭")
if (abs(br2$benchmark_nav[1] - (1 + br2$benchmark_ret[1])) < 1e-12) ok("1b 벤치 NAV 재기준") else ng("1b 벤치 NAV")
if (identical(sort(unique(as.character(as.Date(H2$date)))), as.character(d[c(15, 30)])) && identical(H2$ticker[1], "000660"))
  ok("1c 보유 = 시작에 들고 있던 리밸(d15)부터 · ticker 선행 0 보존") else ng("1c 보유", paste(unique(H2$date)))
if (file.exists(file.path(out, "authoritative_remeasure.json")) && file.exists(file.path(out, "00_manifest.json"))) ok("1d 비 CSV 파일 복사") else ng("1d 복사")
## 위반 주입: 낙폭을 재계산하지 않으면(원 drawdown_net 그대로) 첫 날 낙폭 ≠ 0 — 1a 가 가른다
raw_dd <- fread(file.path(src, "02_nav.csv"))[as.Date(date) >= st]$drawdown_net[1]
if (abs(raw_dd) > 1e-6) ok(sprintf("1e 위반 주입 대조 — 원 낙폭 첫 값 %.4f ≠ 0(재계산이 필요한 경우를 픽스처가 담는다)", raw_dd)) else ng("1e 픽스처가 낙폭 재계산을 시험하지 못한다")

## 2) 위기 짝 과반 — JSON 행 배열(simplifyVector = FALSE) 모양 그대로
crm <- fromJSON(toJSON(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"),
                                  cum_capture = c(0.60, 0.95, 0.70), recover_date = c(NA, "2012-03-01", NA)), na = "null"), simplifyVector = FALSE)
crr <- fromJSON(toJSON(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"),
                                  cum_capture = c(0.80, 0.90, 0.75), recover_date = c(NA, NA, NA)), na = "null"), simplifyVector = FALSE)
mj <- p3_crisis_majority(crm, crr, 1e-9)
if (mj$n_pair == 3L && mj$n_better == 2L && abs(mj$share - 2/3) < 1e-12 && mj$unpaired == 0L) ok("2a 짝 3 · 개선 2 · 비율 2/3(null 칸 처리)") else ng("2a", paste(mj$n_pair, mj$n_better, mj$share))
crr2 <- crr; crr2[[3]]$peak_date <- "2020-02-20"                    # 다른 위기 정의 → 짝 안 됨
mj2 <- p3_crisis_majority(crm, crr2, 1e-9)
if (mj2$n_pair == 2L && mj2$unpaired == 2L) ok("2b 날짜가 다른 위기는 짝짓지 않는다(미짝 기록)") else ng("2b", paste(mj2$n_pair, mj2$unpaired))
mj3 <- p3_crisis_majority(crm, crr, 0.5)                           # tol 이 크면 개선 0
if (mj3$n_better == 0L) ok("2c tol 이 판정에 들어간다(위반 주입)") else ng("2c tol 무시")
if (is.na(p3_crisis_majority(list(), crr, 1e-9)$share)) ok("2d 위기 없음 → NA(판정 불가 — 0 으로 접지 않음)") else ng("2d")

## 3) 셀 로그 파싱
L <- c("[rf_cell_engine] catalog paper:EigenCleanMarkowitz | 차별화 250 · EW폴백 3 · 커버리지 98.4% (선정일 254/258) · 유니버스 지지 100.0% (빈 시그널일 0 — 비중 무관)",
       "[ecm] d=2005-01-31 n=23 k=5 cap=0.20 active=9 capbind=2 eps2=0.4012 infeasible=0",
       "[ecm] d=2005-02-28 n=4 k=NA cap=0.20 active=NA capbind=NA eps2=NA infeasible=1",
       "[method:paper:EigenCleanMarkowitz] 어댑터 실패 → EW 폴백: 상한 불능 — 종목 4 × 상한 0.20 < 1",
       "[ecm] d=2005-03-31 n=25 k=5 cap=0.20 active=11 capbind=0 eps2=0.3876 infeasible=0")
pl <- p3_parse_cell_log(L)
if (identical(pl$coverage$n_hit, 254) && identical(pl$coverage$n_try, 258) && identical(pl$coverage$carry_days, 4) && identical(pl$coverage$ew_fallback, 3))
  ok("3a 커버리지 줄 → 선정일 254/258 · 이월 4 · EW 폴백 3") else ng("3a", paste(unlist(pl$coverage)))
if (nrow(pl$ecm) == 3L && sum(pl$ecm$infeasible) == 1L && identical(pl$ecm$active[1], 9L) && is.na(pl$ecm$active[2]) && pl$n_method_fallback == 1L)
  ok("3b [ecm] 3줄 · 상한 불능 1 · 폴백 호명 1") else ng("3b")
pl0 <- p3_parse_cell_log(character(0))
if (is.null(pl0$coverage) && nrow(pl0$ecm) == 0L) ok("3c 빈 로그 → 커버리지 NULL · 진단 0(지어 넣지 않음)") else ng("3c")

## 4) 이력 탈락 — 신호일 d 의 다음 첫 집행일 RX0 선정 수 − n
Hr <- data.table(date = as.Date(c(rep("2005-02-01", 25), rep("2005-03-02", 25), rep("2005-04-01", 25))), ticker = sprintf("%06d", 1:75), w = 0.04)
hd <- p3_history_drops(pl$ecm, Hr)
if (identical(hd$drops, c(2L, 21L, 0L)) && isTRUE(all.equal(hd$drop_share, c(2, 21, 0) / 25))) ok("4a 탈락 = 선정 25 − n(23 · 4 · 25) → 2 · 21 · 0") else ng("4a", paste(hd$drops))
if (identical(as.character(hd$exec), c("2005-02-01", "2005-03-02", "2005-04-01"))) ok("4b 신호일 → 다음 첫 집행일 짝") else ng("4b", paste(hd$exec))

## 5) 처치 전달률 · 폴백 사유별
if (isTRUE(all.equal(p3_delivery(pl), 2 / 258))) ok("5a 전달률 = 계획 해 신호일 2 / 선정 258") else ng("5a", p3_delivery(pl))
if (is.na(p3_delivery(pl0))) ok("5b 커버리지 줄 없음 → NA(미시험)") else ng("5b")
if (identical(pl$fallback_by_reason$cap_infeasible, 1L) && identical(pl$fallback_by_reason$other, 0L)) ok("5c 폴백 사유 분리(상한 불능 1 · 기타 0)") else ng("5c", paste(unlist(pl$fallback_by_reason)))

## 6) 위기 보유 집행일 — 고점 이하 마지막 집행일 ∪ (고점, 저점] 안
ex <- as.Date(c("2008-04-01", "2008-05-02", "2008-06-02", "2008-07-01", "2008-11-03", "2011-07-01", "2011-08-01"))
crj <- fromJSON(toJSON(data.table(peak_date = c("2008-05-16", "2011-07-29"), trough_date = c("2008-10-24", "2011-09-26"))), simplifyVector = FALSE)
cx <- p3_crisis_execs(ex, crj)
if (identical(as.character(cx), c("2008-05-02", "2008-06-02", "2008-07-01", "2011-07-01", "2011-08-01"))) ok("6a 위기 보유 집행일(행 배열 입력)") else ng("6a", paste(cx))
if (!length(p3_crisis_execs(ex, list()))) ok("6b 위기 없음 → 빈 집합") else ng("6b")

## 7) β 대조 — selection_sum 짝 과반(market_beta_sum 없는 입력 포함)
exm <- fromJSON(toJSON(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"),
                                  selection_sum = c(0.02, -0.01, 0.03), market_beta_sum = c(-0.20, -0.08, -0.15))), simplifyVector = FALSE)
exr <- fromJSON(toJSON(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"),
                                  selection_sum = c(0.01, 0.00, 0.04))), simplifyVector = FALSE)
sv <- p3_selection_vs_ref(exm, exr)
if (sv$n_pair == 3L && sv$n_better == 1L && abs(sv$share - 1/3) < 1e-12) ok("7a 선택 기여 개선 1/3(β 열 없는 기준 칸도 처리)") else ng("7a", paste(sv$n_pair, sv$n_better, sv$share))
if (is.na(p3_selection_vs_ref(list(), exr)$share)) ok("7b 노출 분해 없음 → NA(기전 방어 불인정 · 꼬리표 부착)") else ng("7b")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
