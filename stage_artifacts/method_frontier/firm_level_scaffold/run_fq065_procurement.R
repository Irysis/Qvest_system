#==============================================================================
# run_fq065_procurement.R — FQ-065 나라장터 정부조달 수주 magnitude 러너 (스캐폴드 템플릿)
#
#   ★상태: data.go.kr 키 랜딩 前 스캐폴드. STEP 1(pull)만 placeholder, STEP 2~5 실배선.
#   ★FQ-002(DART 자체공시 계약금액)와 같은 '수주→매출 선행' family — 파서/스코어 로직 공유.
#          단 원천(정부조달 vs 자체공시)·커버리지 독립. occurrence-only는 null(FQ-002 t=0.59);
#          본 팩터는 magnitude(금액/시총)=directional long-side로 구분.
#
#   실행: bash 02_Infrastructure/ops/safe_run.sh Rscript \
#           stage_artifacts/method_frontier/firm_level_scaffold/run_fq065_procurement.R
#
#   규율: K200∪KQ150 · top-25 EW long-only · [0,0.20] · liq>=2e8 · 15bps ·
#         PIT usable_date=최초 낙찰일(변경분 최초일 vintage 고정) · canonical 계약
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a,b) if (is.null(a)) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SCAF <- "stage_artifacts/method_frontier/firm_level_scaffold"
OUT  <- file.path(SCAF, "fq065_out"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ─── STEP 1. 나라장터 낙찰/계약 pull  ★KEY-GATED placeholder ──────────────────
#   data.go.kr 15129397/15129427/15129466(낙찰정보/계약현황). 반환 award 원장 스키마(기대):
#     bizno(낙찰기업 사업자번호), award_date(최초 낙찰일), amount(낙찰/계약금액), item, org
#   ★필드 실존 확인 의무: '낙찰기업 사업자번호' 필드가 API 스펙에 실존하는지 pull 前 확인(추측 금지).
#   ★PIT: award_date=최초 낙찰일 스냅샷. 계약변경(증액/감액)은 최초일 vintage로 고정,
#         변경금액을 최초일로 소급 반영 금지(PIT_plan §2). 공표시차≈0.
G2B_RAW <- file.path(SCAF, "data_pull", "g2b_awards_raw.parquet")   # ← 키 랜딩 시 생성물
if (!file.exists(G2B_RAW)) {
  cat("[fq065] ★KEY-GATED: 나라장터 pull 산출 부재:", G2B_RAW, "\n")
  cat("[fq065]   키 랜딩 후 pull_g2b.R(미작성)가 이 parquet 생성 → 본 러너 재실행 시 STEP 2~5 자동.\n")
  stopifnot(file.exists(file.path(SCAF, "firm_crosswalk.parquet")),
            file.exists(".cache/RAWDATA.parquet"), file.exists(".cache/benchmark.parquet"))
  cat("[fq065] dry-run OK — crosswalk/RAWDATA/benchmark 실존. STEP 2~5 배선 준비 완료.\n")
  quit(save = "no", status = 0)
}
g2b <- as.data.table(read_parquet(G2B_RAW))   # bizno, award_date, amount

# ─── STEP 2. crosswalk join + 계열 귀속 ───────────────────────────────────────
xw <- as.data.table(read_parquet(file.path(SCAF, "firm_crosswalk.parquet")))
g2b <- merge(g2b, xw[, .(bizr_no, Ticker)], by.x = "bizno", by.y = "bizr_no", all.x = FALSE)
#   ★계열매핑: 승자 상당수 비상장 자회사 → 상장모기업 귀속(별도 계열 테이블 필요, 랜딩 시 구축).
#     여기선 직접 상장사 낙찰만(보수적). 계열 확장은 group_map.parquet 조인으로 추가.
g2b[, award_date := as.Date(award_date)]
g2b[, ym := format(award_date, "%Y-%m")]

# ─── STEP 3. 수주 magnitude 팩터 (TTM 낙찰금액 / 시총 + YoY) ───────────────────
#   월별 firm 수주합 → TTM rolling 12M → 시총 정규화 → YoY. usable_date=낙찰월(시차0).
firm_m <- g2b[, .(award_amt = sum(amount, na.rm = TRUE)), by = .(Ticker, ym)]
#   전체 월 grid로 확장(수주 없는 월=0) 후 TTM
allym <- sort(unique(firm_m$ym))
grid <- CJ(Ticker = unique(firm_m$Ticker), ym = allym)
firm_m <- merge(grid, firm_m, by = c("Ticker","ym"), all.x = TRUE)
firm_m[is.na(award_amt), award_amt := 0]
setorder(firm_m, Ticker, ym)
firm_m[, ttm := frollsum(award_amt, 12L, align = "right"), by = Ticker]
firm_m[, ttm_lag := shift(ttm, 12L), by = Ticker]
firm_m[, yoy := ifelse(is.finite(ttm_lag) & ttm_lag > 0, ttm / ttm_lag - 1, NA_real_)]
firm_m[, Date := as.Date(paste0(ym, "-01"))]   # ★랜딩 시 낙찰월 month-end로 매핑(PIT_plan §2)
#   score = z(ttm/시총) 결합 — 시총은 STEP 4 RAWDATA에서 조인. 여기선 raw magnitude 사용,
#   시총 정규화는 아래에서. (템플릿상 raw ttm; 랜딩 시 /Size 결합)
scores <- firm_m[is.finite(ttm) & ttm > 0, .(Date, Ticker, score = log1p(ttm))]

# ─── STEP 4. 표준 forward returns + benchmark + liq + Size (실존 인프라) ────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; setorder(RAW, Ticker, Date)
RAW[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
ME <- RAW[Date %in% .MEND, .(Date, Ticker, Close, Size)]
setorder(ME, Ticker, Date); ME[, Close_next := shift(Close, -1L), by = Ticker]
ME[, Ret_1m := Close_next / Close - 1]
returns_dt <- ME[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]
size_dt <- ME[is.finite(Size), .(Date, Ticker, Size)]   # diag_cap_tier용
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date = as.Date(Date), BM_Ret)][!is.na(BM_Ret)]
bm[, ym := format(Date, "%Y-%m")]
bm_m <- bm[, .(BM_Ret = prod(1 + BM_Ret) - 1, Date = max(Date)), by = ym]
setorder(bm_m, Date); bm_m[, BM_fwd := shift(BM_Ret, -1L)]
bench_dt <- bm_m[is.finite(BM_fwd), .(Date, BM_Ret = BM_fwd)]
RAW[, dv := Vol * Close]; RAW[, adv20 := frollmean(dv, 20, align = "right"), by = Ticker]
RAW[, adv20_l1 := shift(adv20, 1L), by = Ticker]
liq_dt <- RAW[Date %in% .MEND, .(Date, Ticker, adv = adv20_l1)]

# ─── STEP 5. canonical_screen_bt ──────────────────────────────────────────────
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
stopifnot(exists("build_benchmark_compare"))
res <- canonical_screen_bt(scores[, .(Date, Ticker, score)], returns_dt, bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq_dt, liq_min = 2e8,
                           run_id = "FQ065_procurement", strategy_id = "GovProc_Award_MagYoY",
                           diag_dual_basis = TRUE, size_dt = size_dt)
res$benchmark_compare <- NULL; res$period_returns <- NULL
write_json(res, file.path(OUT, "fq065_canonical.json"), auto_unbox = TRUE, na = "null", pretty = TRUE)
cat(sprintf("[fq065] n_months=%s PORT_t=%.3f net_sr=%.3f IR=%.3f\n",
    res$n_months, res$portfolio_alpha_t_nw_lag3 %||% NA, res$net_sr %||% NA, res$information_ratio %||% NA))
