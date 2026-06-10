# =============================================================================
# fe_single.R — 단일 factor 직교축 스크리닝용 generic factor engine
# =============================================================================
# 목적: factor DB 임의의 단일 factor(환경변수 FACTOR_NAME)의 Z_Score_Aligned를
#       K200∪KQ150 멤버십+유동성 universe 내에서 Score로 산출.
#       driver_ls_generic.R가 이를 받아 top−bottom decile long-short 스크리닝.
#
# ★ 부호: Z_Score_Aligned 그대로 사용 (C13 NEGATE/FLIP 금지). load_month_factors는
#   IC 방향으로 이미 정렬(높을수록 좋은 방향)된 z를 반환 — 본 엔진은 그대로 전달.
#   ⇒ driver의 long=top decile(z 높음=IC상 우월) / short=bottom decile.
#
# ★ 일괄 로딩(L-534 회피): 월별 grid를 한 번 순회하며 load_month_factors(d) 호출.
#   parquet은 connector가 월 단위로 캐시 로드(루프 내 동일 월 반복 로드 없음).
#
# ===== PIT (C1~C15) =====
#   - C14: load_month_factors(sig_date)의 Z_Score_Aligned = Usable_Date<=sig_date IC
#     방향정렬. C13: NEGATE/FLIP 없음(Aligned 그대로). C15: load_month_factors 경유.
#   - C4: 재무 의존 factor(accruals/investment/issuance)는 factor DB 빌드 단계서
#     연간 5월/분기 45일 lag 반영. 본 엔진은 추가 lookahead 도입 없음(과거 시점 z만).
#   - C1: z-score는 factor DB 빌드 시점 cross-section(full-sample 통계 아님).
#   - 멤버십/유동성: 월말 시점 K200/KQ150 멤버 + 20일 평균 거래대금(과거 윈도우) 2e8.
#
# 환경변수:
#   FACTOR_NAME (필수) — factor_registry.json의 Factor_Name (예 AC07_Operating_Accruals)
# 출력: FACTORS(Date, Ticker, Score)  [decile 분할은 driver가 수행 — N marker 없음]
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.FE_FACTOR <- Sys.getenv("FACTOR_NAME", "")
if (!nzchar(.FE_FACTOR))
  stop("[fe_single] FACTOR_NAME 환경변수 미설정 — 검증할 factor_registry Factor_Name을 지정하세요.")

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

# =============================================================================
# ★ OOM 근본 해결 v2 (2026-06-06 — IN04 등 회계 factor 6종 batch 비결정 OOM fix)
# =============================================================================
#  증상: driver_ls_generic가 fe_env$RAWDATA <- RAWDATA(13.9M행, 378MB)로 *2번째 바인딩*을
#        만든 뒤 fe_single을 source. v1(slim 추출)으로 universe-pass transient는 잡았으나,
#        그 full 공유 RAWDATA가 fe_env에 *그대로 살아있는 채로* 직후 월별 load_month_factors
#        루프(full ~288팩터 parquet read + align merge·재z화 254회)가 돌아 → 무거운 factor
#        loading peak와 378MB RAWDATA가 co-resident → RAM 한계 초과 → 비결정 OOM/segfault.
#        smoke(fresh 프로세스)는 누적 메모리 적어 운좋게 완주.
#  ★ 핵심: 본 fe_single 대상 factor(회계/유동성/투자/발행 — IN04/IN06/GR03/L01/V11/Q35,
#    accruals 등)는 전부 factor DB(Z_Score_Aligned) 기반이다. RAWDATA는 *universe(멤버십
#    +유동성) 산출* 외에는 전혀 필요 없다(momentum/가격 driver가 아님). 따라서 universe
#    (.mem)를 만든 직후 RAWDATA(fe_env 바인딩)를 *완전 해제*하면 factor 일괄로딩 동안
#    378MB peak가 사라진다. driver의 자체 RAWDATA(별도 env, line 56)는 무영향 — section 3
#    build_leg_daily forward 수익 구성에 그대로 살아있음.
#  해결 3축 (smoke 로직·결과 불변):
#   (1) universe(.mem) 산출에 필요한 6열만 slim 로컬 추출(.rd_slim) → 거기서만 setorder/
#       .TV/.AvgTV20 frollmean. 공유 RAWDATA reorder/컬럼추가 deep-copy 회피.
#   (2) .mem 산출 직후 .rd_slim *및 공유 RAWDATA 바인딩* 즉시 rm + gc() → factor 일괄로딩
#       전 universe-pass transient(13.9M frollmean) + RAWDATA 378MB 둘 다 완전 해제.
#       ★ 가드: fe_single은 .mem 산출 이후 RAWDATA를 일절 참조하지 않음(아래 (3) 전부
#         .mem + load_month_factors만 사용). momentum/가격 기반 fe였다면 이 rm 금지.
#   (3) factor 루프: load_month_factors(d) full dt를 *호출 직후* 단일 factor × universe로
#       slim하고 rm(fdt) — full 288팩터 dt가 다음 iteration까지 살지 않게 즉시 폐기
#       (fe_valearn L-534 패턴). 주기적 gc로 align merge 잔여 해제.
# =============================================================================

# ---- (1)(2) universe 산출 = full RAWDATA 무수정. slim 6열 로컬 추출만 ----
.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]   # shallow 추출(새 data.table)
setorder(.rd_slim, Ticker, Date)

.rd_slim[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
.rd_slim[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")          # factor DB 재무 의존 factor 가용 시작
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) universe (PIT 시변, 과거 윈도우)
.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- .rd_slim[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                   !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                 .(Date, Ticker)]
setkey(.mem, Date, Ticker)
# ★ (2) universe-pass transient(.rd_slim 13.9M frollmean) + 공유 RAWDATA(fe_env 바인딩,
#   378MB) 둘 다 즉시 해제. 이후 (3) factor 일괄로딩이 RAWDATA-free로 돌아 peak 평탄.
#   가드: fe_single은 .mem 산출 이후 RAWDATA를 참조하지 않음(가격/momentum driver 아님).
rm(.rd_slim)
if (exists("RAWDATA", inherits = FALSE)) rm(RAWDATA)   # fe_env 바인딩만 해제(driver env 무영향)
gc(verbose = FALSE)

# ---- (3) 월별 단일 factor Z_Score_Aligned (universe 한정, full dt 즉시 폐기) ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  # 호출 직후 단일 factor × universe만 남기고 full 288팩터 dt 즉시 폐기(메모리 누적 차단)
  fz <- fdt[Factor_Name == .FE_FACTOR & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
            .(Ticker, Score = Z_Score_Aligned)]
  rm(fdt)                                   # ★ full dt를 다음 iteration 전 즉시 free
  if (nrow(fz) < 20L) next                  # decile 분할 위해 최소 종목수 확보
  fz[, Date := d]
  .factor_list[[i]] <- fz[, .(Date, Ticker, Score)]
  if (i %% 24L == 0L) gc(verbose = FALSE)   # 주기적 gc — align merge 잔여 해제(peak 평탄화)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
rm(.factor_list); gc(verbose = FALSE)

cat(sprintf("[fe_single] factor=%s | FACTORS rows=%d | signal months=%d | avg N/month=%.0f\n",
            .FE_FACTOR, nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) nrow(FACTORS) / max(uniqueN(FACTORS$Date), 1L) else 0))
