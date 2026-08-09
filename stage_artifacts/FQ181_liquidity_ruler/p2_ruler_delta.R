## FQ-181 P2 — 두 자(ruler) 실측 대조 (전 구간) + ⑤ production 현행 북 스팟체크
##
##   자 A (구판, 결함) : adv = Vol0 * Close0            = 월말 **당일 1일치** 거래대금
##   자 B (헌법, 교정) : adv = mean(Vol*Close, 20일), 창이 t-1 에서 끝남(당일 미포함)
##
## read-only. 소급 재작성 없음 — 비교값은 이 디렉터리에만 쓴다.
## 산출: p2_ruler_delta.json / p2_disagree_by_month.csv / p2_prod_spotcheck.csv

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")
source(file.path(QM, "02_Infrastructure/ramp/factor_validation.R"))

LIQ_MIN <- 2e8   # 헌법 LIQ_THRESHOLD (완화 금지 — 조이는 방향만)

## ── vintage pin ─────────────────────────────────────────────────────────────
fi <- file.info(".cache/rawdata.parquet")
PIN <- list(path = ".cache/rawdata.parquet", size_bytes = as.numeric(fi$size),
            mtime = format(fi$mtime, "%Y-%m-%d %H:%M:%S"))
cat(sprintf("[pin] rawdata.parquet %.0f bytes mtime=%s\n", PIN$size_bytes, PIN$mtime))

## ── 입력 형태 실측 (가정 금지) ──────────────────────────────────────────────
R <- as.data.table(read_parquet(".cache/rawdata.parquet",
       col_select = all_of(c("Date","Ticker","Close","Vol","K200","KQ150"))))
R[, Date := as.Date(Date)]
dpm <- median(as.integer(table(format(sort(unique(R$Date)), "%Y-%m"))))
cat(sprintf("[shape] rows=%s dates=%s tickers=%s | 캘린더월당 거래일 중앙값=%.0f → %s\n",
            format(nrow(R), big.mark=","), format(uniqueN(R$Date), big.mark=","),
            format(uniqueN(R$Ticker), big.mark=","), dpm,
            if (dpm >= 15) "일간(20일 자 계산 가능)" else "★일간 아님 — 중단"))
stopifnot(dpm >= 15)

## ── 월말 거래일 ─────────────────────────────────────────────────────────────
D <- sort(unique(R$Date))
ME <- as.Date(vapply(split(D, format(D, "%Y-%m")), function(v) as.character(max(v)), character(1)))
ME <- sort(unname(ME))
cat(sprintf("[me] 월말 거래일 %d 개 (%s .. %s)\n", length(ME), min(ME), max(ME)))

## ── 자 B: 20일 평균(t-1) ────────────────────────────────────────────────────
t0 <- Sys.time()
ADV <- build_adv20_t1(R[, .(Date, Ticker, Vol, Close)], at_dates = ME)
setnames(ADV, "adv", "adv20_t1")
cat(sprintf("[B] build_adv20_t1: %s 행 / %.1f 초\n", format(nrow(ADV), big.mark=","),
            as.numeric(difftime(Sys.time(), t0, units="secs"))))

## ── 자 A: 구판 월말 1일치 ───────────────────────────────────────────────────
LEG <- R[Date %in% ME, .(Date, Ticker, adv1_sameday = Vol * Close, K200, KQ150)]

CMP <- merge(LEG, ADV, by = c("Date","Ticker"), all.x = TRUE)
CMP[, in_univ := (K200 == TRUE | KQ150 == TRUE)]
U <- CMP[in_univ == TRUE & !is.na(adv1_sameday) & !is.na(adv20_t1)]
cat(sprintf("[cmp] 유니버스(K200|KQ150) 종-월 %s 건 대조\n", format(nrow(U), big.mark=",")))

## ── 1) 상관 ─────────────────────────────────────────────────────────────────
cor_p <- cor(U$adv1_sameday, U$adv20_t1)
cor_s <- cor(U$adv1_sameday, U$adv20_t1, method = "spearman")
cor_lp <- cor(log(pmax(U$adv1_sameday,1)), log(pmax(U$adv20_t1,1)))
cat(sprintf("[1] 상관: pearson=%.4f  spearman=%.4f  log-pearson=%.4f\n", cor_p, cor_s, cor_lp))

## ── 2) 문턱(2e8) 판정 불일치 ────────────────────────────────────────────────
U[, `:=`(pass_leg = adv1_sameday >= LIQ_MIN, pass_new = adv20_t1 >= LIQ_MIN)]
n <- nrow(U)
n_dis <- U[pass_leg != pass_new, .N]
n_leg_only <- U[pass_leg & !pass_new, .N]   # 구판이 잘못 통과시킨 것 (교정이 조인다)
n_new_only <- U[!pass_leg & pass_new, .N]   # 구판이 잘못 탈락시킨 것 (교정이 푼다)
cat(sprintf("[2] 판정 불일치 %s / %s = %.3f%%\n", format(n_dis, big.mark=","), format(n, big.mark=","), 100*n_dis/n))
cat(sprintf("    - 구판만 통과(교정이 **조임**): %s (%.3f%%)\n", format(n_leg_only, big.mark=","), 100*n_leg_only/n))
cat(sprintf("    - 교정만 통과(교정이 **푼다**): %s (%.3f%%)\n", format(n_new_only, big.mark=","), 100*n_new_only/n))
cat(sprintf("    - 순 통과수 변화: %+d 건 (%.3f%%p) → 교정 방향 = %s\n",
            n_new_only - n_leg_only, 100*(n_new_only-n_leg_only)/n,
            if (n_new_only < n_leg_only) "조임(net tighter)" else "★완화 — 재확인 필요"))

## ── 3) 시대별 분해 (FQ-181 은 초기표본 편중을 보고했다) ─────────────────────
U[, era := fifelse(Date < as.Date("2005-01-01"), "~2004",
           fifelse(Date < as.Date("2010-01-01"), "2005-2009",
           fifelse(Date < as.Date("2017-01-01"), "2010-2016", "2017~")))]
ERA <- U[, .(n = .N, dis = sum(pass_leg != pass_new),
             leg_only = sum(pass_leg & !pass_new), new_only = sum(!pass_leg & pass_new)), by = era]
ERA[, dis_pct := round(100*dis/n, 3)]
setorder(ERA, era); cat("[3] 시대별:\n"); print(ERA)

## ── 4) 월별 불일치 (④ 영향 가능 구간 판별용) ────────────────────────────────
MON <- U[, .(n_univ = .N,
             n_leg_only = sum(pass_leg & !pass_new),
             n_new_only = sum(!pass_leg & pass_new)), by = Date]
MON[, n_dis := n_leg_only + n_new_only]
MON[, dis_pct := round(100*n_dis/n_univ, 3)]
setorder(MON, Date)
n_clean_months <- MON[n_dis == 0, .N]
cat(sprintf("[4] 월 %d 개 중 불일치 0 인 달 = %d (%.1f%%) → 그 달 판정은 자 교정에 **구조적으로 면역**\n",
            nrow(MON), n_clean_months, 100*n_clean_months/nrow(MON)))
cat(sprintf("    불일치 상위 5개월:\n")); print(head(MON[order(-n_dis)], 5))
fwrite(MON, file.path(OUT, "p2_disagree_by_month.csv"))

## ── 5) ⑤ production 현행 북 스팟체크 (05_Production read-only) ─────────────
cat("\n=== ⑤ production 현행 북 스팟체크 ===\n")
source(file.path(QM, "02_Infrastructure/portfolio/resolve_admitted_slot.R"))
slot <- resolve_admitted_slot()
H <- fread(slot$holdings)
cat(sprintf("[prod] %s | as_of %s | 파일 %s\n", slot$id, slot$as_of, basename(slot$holdings)))
cat(sprintf("[prod] 컬럼: %s | 행 %d\n", paste(names(H), collapse=", "), nrow(H)))
tick_col <- names(H)[names(H) %in% c("Ticker","ticker","code","Code","종목코드")][1]
stopifnot(!is.na(tick_col))
prod_ticks <- as.character(H[[tick_col]])
# as_of 이전 마지막 거래일 기준 20일-자
asof <- as.Date(slot$as_of)
md_prod <- max(D[D <= asof])
ADVP <- build_adv20_t1(R[Date <= md_prod, .(Date, Ticker, Vol, Close)], at_dates = md_prod)
SP <- merge(data.table(Ticker = prod_ticks), ADVP[, .(Ticker, adv20_t1 = adv)], by = "Ticker", all.x = TRUE)
LEGP <- R[Date == md_prod, .(Ticker, adv1_sameday = Vol * Close)]
SP <- merge(SP, LEGP, by = "Ticker", all.x = TRUE)
SP[, `:=`(pass_new = adv20_t1 >= LIQ_MIN, pass_leg = adv1_sameday >= LIQ_MIN)]
cat(sprintf("[prod] 기준 거래일 %s | 보유 %d 종목 중 20일-자 매칭 %d\n",
            md_prod, nrow(SP), SP[!is.na(adv20_t1), .N]))
cat(sprintf("[prod] 20일-자 min=%.3g  median=%.3g  max=%.3g\n",
            min(SP$adv20_t1, na.rm=TRUE), median(SP$adv20_t1, na.rm=TRUE), max(SP$adv20_t1, na.rm=TRUE)))
n_fail_prod <- SP[!is.na(adv20_t1) & adv20_t1 < LIQ_MIN, .N]
cat(sprintf("[prod] ★20일-자 2e8 미달 = %d 종목 %s\n", n_fail_prod,
            if (n_fail_prod == 0) "→ 현행 북 청정(실측 확정)" else "→ ★목록 확인 필요"))
if (n_fail_prod > 0) print(SP[adv20_t1 < LIQ_MIN])
n_na_prod <- SP[is.na(adv20_t1), .N]
if (n_na_prod > 0) { cat(sprintf("[prod] 자 미산출(패널 부재) %d 종목:\n", n_na_prod)); print(SP[is.na(adv20_t1)]) }
fwrite(SP, file.path(OUT, "p2_prod_spotcheck.csv"))

## ── 저장 ────────────────────────────────────────────────────────────────────
res <- list(
  vintage_pin = PIN, liq_min = LIQ_MIN,
  input_shape = list(rows = nrow(R), dates = uniqueN(R$Date), tickers = uniqueN(R$Ticker),
                     trading_days_per_month_median = dpm, unit = "daily"),
  n_month_ends = length(ME), me_min = as.character(min(ME)), me_max = as.character(max(ME)),
  n_universe_stock_months = n,
  correlation = list(pearson = cor_p, spearman = cor_s, log_pearson = cor_lp),
  threshold_disagreement = list(
    n = n_dis, pct = 100*n_dis/n,
    legacy_pass_only = n_leg_only, legacy_pass_only_pct = 100*n_leg_only/n,
    new_pass_only = n_new_only, new_pass_only_pct = 100*n_new_only/n,
    net_direction = if (n_new_only < n_leg_only) "tighter" else "looser"),
  by_era = ERA,
  months_total = nrow(MON), months_zero_disagreement = n_clean_months,
  production_spotcheck = list(
    strategy = slot$id, as_of = as.character(slot$as_of), ref_trading_day = as.character(md_prod),
    holdings_file = basename(slot$holdings), n_holdings = nrow(SP),
    adv20_min = min(SP$adv20_t1, na.rm=TRUE), adv20_median = median(SP$adv20_t1, na.rm=TRUE),
    n_below_2e8 = n_fail_prod, n_unmatched = n_na_prod,
    verdict = if (n_fail_prod == 0 && n_na_prod == 0) "CLEAN (20일-자 전건 통과)" else "확인 필요")
)
write_json(res, file.path(OUT, "p2_ruler_delta.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p2_ruler_delta.json / p2_disagree_by_month.csv / p2_prod_spotcheck.csv\n")
