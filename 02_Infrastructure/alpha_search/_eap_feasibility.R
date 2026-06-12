# =============================================================================
# _eap_feasibility.R — Frazzini-Lamont (2007) EAP KR 타당성 사전점검
# =============================================================================
# 목적: 논문 메커니즘("이번 달 실적공시 예정 vs 아닌" 횡단면 분할)이 KR에서
#       유의미한 규모로 존재하는지 실측. 비공시 그룹이 매월 유니버스의 20% 이상
#       존재하지 않으면 INFEASIBLE → 구현 생략.
# 데이터: .cache/dart/dart_raw_quarterly.parquet (rcept_no 첫 8자 = 접수일)
#         + RAWDATA K200/KQ150 PIT 멤버십.
# PIT: 모두 과거 관측치(접수일 분포). forward label 없음. 진단 전용(게이트 미사용).
# =============================================================================
suppressMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/alpha_search/run_alpha_search.R")

cat("=== [EAP-FEAS] Step 1: RAWDATA + universe membership ===\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
stopifnot(all(c("K200","KQ150") %in% names(RAWDATA)))

# 월말 거래일 그리드
RAWDATA[, .ym := format(Date, "%Y-%m")]
MEND <- RAWDATA[, .(Date = max(Date)), by = .ym][order(Date)]
# 각 월말의 유니버스 멤버 (K200 ∪ KQ150, PIT)
UNI <- unique(RAWDATA[Date %in% MEND$Date & (K200 == TRUE | KQ150 == TRUE),
                      .(me = Date, ym = .ym, Ticker)])
uni_sz <- UNI[, .(uni_n = uniqueN(Ticker)), by = .(ym, me)][order(me)]
cat(sprintf("[EAP-FEAS] 유니버스 월수=%d | 멤버 종목수 중앙값=%d (min %d / max %d)\n",
            nrow(uni_sz), as.integer(median(uni_sz$uni_n)), min(uni_sz$uni_n), max(uni_sz$uni_n)))

cat("=== [EAP-FEAS] Step 2: DART 접수일 분포 ===\n")
dcp <- file.path(ROOT, ".cache", "dart", "dart_raw_quarterly.parquet")
D <- as.data.table(read_parquet(dcp, col_select = c("rcept_no","reprt_code","bsns_year","Ticker")))
FIL <- unique(D[, .(rcept_no, reprt_code, bsns_year, Ticker)]); rm(D); gc(verbose = FALSE)
FIL[, rcept_date := as.Date(substr(rcept_no, 1L, 8L), format = "%Y%m%d")]
FIL <- FIL[!is.na(rcept_date)]
FIL[, rym := format(rcept_date, "%Y-%m")]
FIL[, rmon := as.integer(format(rcept_date, "%m"))]

cat(sprintf("[EAP-FEAS] DART filing 건수=%d | 접수일 범위 %s ~ %s | 종목수=%d\n",
            nrow(FIL), as.character(min(FIL$rcept_date)), as.character(max(FIL$rcept_date)),
            uniqueN(FIL$Ticker)))

# 2a. 월(calendar month)별 공시 접수 분포 — 집중도 진단
mon_dist <- FIL[, .(n_fil = .N, n_tkr = uniqueN(Ticker)), by = rmon][order(rmon)]
mon_dist[, pct_fil := round(100 * n_fil / sum(n_fil), 1)]
cat("\n[EAP-FEAS] 캘린더 월별 공시 접수 분포 (전체 filing 기준):\n")
print(mon_dist[, .(월 = rmon, filing수 = n_fil, 비율pct = pct_fil)])

# 2b. reprt_code별 접수월 분포 (분기별 동기화 확인)
rc_lab <- c("11013"="Q1","11012"="반기","11014"="Q3","11011"="사업")
FIL[, rc_lab := rc_lab[reprt_code]]
rc_mon <- FIL[!is.na(rc_lab), .N, by = .(rc_lab, rmon)]
rc_wide <- dcast(rc_mon, rmon ~ rc_lab, value.var = "N", fill = 0L)
cat("\n[EAP-FEAS] 보고서종류 x 접수월 (분기 동기화 확인):\n")
print(rc_wide)

cat("\n=== [EAP-FEAS] Step 3: 핵심 — 월별 유니버스 내 공시/비공시 분할 ===\n")
# 각 월말 t 시점에서, 그 달(rym==ym)에 실제 공시한 유니버스 종목 비율.
# (논문: '이번 달 공시 예정' 그룹. PIT 예측은 구현 단계 — 여기선 실현 분할의 규모만.)
FIL_uni <- FIL[Ticker %in% unique(UNI$Ticker)]
# 그 달에 1건 이상 공시한 (ym, Ticker)
announced <- unique(FIL_uni[, .(ym = rym, Ticker, announced = 1L)])

# 유니버스(월별 멤버) 와 결합
SPLIT <- merge(UNI[, .(ym, Ticker)], announced, by = c("ym","Ticker"), all.x = TRUE)
SPLIT[is.na(announced), announced := 0L]
mo_split <- SPLIT[, .(uni_n = .N,
                      ann_n = sum(announced),
                      non_n = sum(announced == 0L)), by = ym][order(ym)]
mo_split[, ann_pct := round(100 * ann_n / uni_n, 1)]
mo_split[, non_pct := round(100 * non_n / uni_n, 1)]
# 검증 가용 구간 2016~ 로 라벨 (DART floor)
mo_split[, yr := as.integer(substr(ym, 1, 4))]
mo_split[, cmon := as.integer(substr(ym, 6, 7))]

cat(sprintf("\n[EAP-FEAS] 월별 분할 요약 (전 구간, 월수=%d):\n", nrow(mo_split)))
cat(sprintf("  비공시 비율 — 중앙값 %.1f%% | min %.1f%% | max %.1f%% | p25 %.1f%% | p75 %.1f%%\n",
            median(mo_split$non_pct), min(mo_split$non_pct), max(mo_split$non_pct),
            quantile(mo_split$non_pct, .25), quantile(mo_split$non_pct, .75)))
cat(sprintf("  공시 비율   — 중앙값 %.1f%% | min %.1f%% | max %.1f%%\n",
            median(mo_split$ann_pct), min(mo_split$ann_pct), max(mo_split$ann_pct)))

# 검증 가용 구간(2016~)만
ms16 <- mo_split[yr >= 2016]
cat(sprintf("\n[EAP-FEAS] 검증 가용 구간(2016~, 월수=%d):\n", nrow(ms16)))
cat(sprintf("  비공시 비율 — 중앙값 %.1f%% | min %.1f%% | max %.1f%%\n",
            median(ms16$non_pct), min(ms16$non_pct), max(ms16$non_pct)))

# 공시월(공시비율 높은 달) 에 비공시 그룹 규모 — 핵심 판정
# "공시월"= 분기 마감월(3/5/8/11월 부근). 각 캘린더 월별 평균 분할.
cmon_split <- mo_split[yr >= 2016, .(
  mean_ann_pct = round(mean(ann_pct), 1),
  mean_non_pct = round(mean(non_pct), 1),
  n_mo = .N), by = cmon][order(cmon)]
cat("\n[EAP-FEAS] ★ 캘린더 월별 평균 공시/비공시 비율 (2016~, 핵심 판정표):\n")
print(cmon_split)

# 공시 집중월(공시비율 상위) 에서 비공시 그룹 최소 규모
peak_months <- cmon_split[order(-mean_ann_pct)][1:4]
cat(sprintf("\n[EAP-FEAS] 공시 집중 상위 4개월의 비공시 비율: %s\n",
            paste(sprintf("%d월=%.1f%%", peak_months$cmon, peak_months$mean_non_pct), collapse=" / ")))
worst_non <- min(peak_months$mean_non_pct)
cat(sprintf("[EAP-FEAS] 공시 집중월 중 최소 비공시 비율 = %.1f%%\n", worst_non))

# 판정
cat("\n=== [EAP-FEAS] 판정 ===\n")
verdict <- if (worst_non >= 20) "FEASIBLE" else "INFEASIBLE"
cat(sprintf("[EAP-FEAS] 기준: 공시 집중월에 유니버스 비공시 >= 20%% 존재 → 횡단면 분할 유의미\n"))
cat(sprintf("[EAP-FEAS] 실측 공시집중월 최소 비공시비율 = %.1f%% → 판정 = %s\n", worst_non, verdict))

# 저장
out <- list(
  universe_months = nrow(uni_sz),
  universe_median_n = as.integer(median(uni_sz$uni_n)),
  dart_filings = nrow(FIL),
  dart_date_min = as.character(min(FIL$rcept_date)),
  dart_date_max = as.character(max(FIL$rcept_date)),
  mon_dist = mon_dist,
  rc_wide = rc_wide,
  cmon_split = cmon_split,
  non_pct_median_all = median(mo_split$non_pct),
  non_pct_median_2016 = median(ms16$non_pct),
  peak_month_min_non_pct = worst_non,
  verdict = verdict)
saveRDS(out, "02_Infrastructure/alpha_search/_eap_feasibility_result.rds")
cat("\n[EAP-FEAS] 결과 저장: _eap_feasibility_result.rds\n")
cat(sprintf("VERDICT=%s WORST_NON=%.1f\n", verdict, worst_non))
