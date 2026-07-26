#==============================================================================
# run_fq073_export.R — FQ-073 관세청 HS 수출 증감 → KR 종목 tilt (측정 러너)
#
#   가설: 관세청 품목별(HS) 수출실적(data.go.kr 15101609, 공식·무료)의 증감률이
#         해당 HS에 노출된 KR 상장사의 익월 초과수익을 선행한다.
#         1단 = 집계 HS → 섹터 tilt (ARM_S) / 2단 = HS×DART 제품믹스 → 종목 (ARM_F)
#
#   ★상태: data.go.kr 1220000 활용신청 미승인(HTTP 403) → STEP 1 **fail-closed**.
#          STEP 2~5 는 실배선(RAWDATA/contract/guard 실존). 승인 후 pull만 채우면 1커맨드.
#
#   실행: bash 02_Infrastructure/ops/safe_run.sh Rscript \
#           stage_artifacts/method_frontier/firm_level_scaffold/fq073/run_fq073_export.R
#         (arm/스트레스 전환은 env: FQ073_ARM / FQ073_LAG_EXTRA / FQ073_TIEBREAK / FQ073_SEED)
#
#   규율(전부 적용):
#     · PIT C1~C15 — 특히 **C5 오버레이 타이밍**: 홀딩월 H 신호는 데이터월 H-2 까지만.
#       (도출·발표시차 실측 근거 = fq073/PIT_plan_fq073.md §1/§3)
#       assert_overlay_pit HARD + 등호경계 차단용 버퍼 게이트 추가 부과.
#     · measurement-graduation §1 — 성능수치는 **canonical_screen_bt 계약 경유 실측만**.
#       proxy 손계산·prod(1+r)/cumprod 자체합성 전면 금지. metric_type 라벨 의무.
#     · 벤치마크 = **lagged weights only**. 표준 build_monthly_forward_returns 산출을
#       PerformanceAnalytics::Return.portfolio 로 재구성 대조해 lagged임을 HARD 실증
#       (contemporaneous size-weight = look-ahead, 2026-07-18 실사고).
#     · Production Constraints: K200∪KQ150 · top-25 · long-only · liq>=2e8 · 15bps
#     · 데이터 부재 = **가짜 데이터로 돌지 않고 즉시 stop**.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

QM <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
FQ  <- file.path(QM, "stage_artifacts/method_frontier/firm_level_scaffold/fq073")
OUT <- file.path(FQ, "out")
dir.create(OUT,                    recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FQ, "maps"),  recursive = TRUE, showWarnings = FALSE)

#==============================================================================
# STEP 0. 사전등록 파라미터 + PIT 상수 + 가드 로드
#==============================================================================
CFG <- list(
  # ── 사전등록 PRIMARY 스펙 (착수 前 고정 — PIT_plan §5) ─────────────────────
  arm            = Sys.getenv("FQ073_ARM", "S_3M"),                 # S_3M(PRIMARY)|S_6M|F_3M
  horizon_m      = as.integer(Sys.getenv("FQ073_HORIZON", "3")),    # YoY 대상 누적개월
  tiebreak       = Sys.getenv("FQ073_TIEBREAK", "neutral_hash"),    # neutral_hash|size_desc|liq_desc
  tiebreak_seed  = as.numeric(Sys.getenv("FQ073_SEED", "20260725")),
  lag_extra      = as.integer(Sys.getenv("FQ073_LAG_EXTRA", "0")),  # 1 = 의무 LAG1 스트레스
  selection_type = "chain",  # PRIMARY 단일 사전등록. arm argmax 선택 시 sweep 재분류 + DSR HARD 부활
  # ── Production Constraints (불변) ──────────────────────────────────────────
  top_n           = 25L,
  cost_bps_oneway = 15,
  liq_min         = 2e8,
  # ── PIT 상수 (PIT_plan §1 실측 문서근거) ───────────────────────────────────
  pub_first_release_day = 1L,   # 잠정: data_ym M 전체 → M+1월 1일   (15157901 원문)
  pub_confirmed_day     = 15L,  # 현행화: 매월 15일경 전월까지 자료  (15101609/475/2108 원문)
  min_buffer_days       = 10L,  # assert_overlay_pit(등호 통과) 보강 — razor edge 차단
  # ── 수치 가드 ──────────────────────────────────────────────────────────────
  yoy_base_min_usd   = 1e6,     # YoY 분모 하한(소액 base 폭발 차단)
  min_mapped_sectors = 6L,      # 매핑 섹터 이 미만이면 횡단 랭킹 무의미 → stop
  tol_bench_equal    = 1e-6,    # 벤치 lagged 재구성 일치 허용오차
  min_months         = 36L      # 게이트 적격 최소 개월
)
if (identical(CFG$arm, "S_6M")) CFG$horizon_m <- 6L

source("02_Infrastructure/validation/overlay_pit_guard.R")    # assert_overlay_pit / holdings_signal_cutoff
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")           # build_monthly_forward_returns (frozen)

# 월 산술 (전부 벡터화)
add_months <- function(d, n) {
  d  <- as.Date(paste0(format(as.Date(d), "%Y-%m"), "-01"))
  yr <- as.integer(format(d, "%Y")); mo <- as.integer(format(d, "%m")) + n
  yr <- yr + (mo - 1L) %/% 12L; mo <- ((mo - 1L) %% 12L) + 1L
  as.Date(sprintf("%04d-%02d-01", yr, mo))
}
ym_add <- function(ym, n) format(add_months(as.Date(paste0(ym, "-01")), n), "%Y-%m")

# 결정적 해시 [0,1) — 외부 패키지 의존 없음. 같은 (x, seed) → 항상 같은 값(재현성).
.hash01 <- function(x, seed) {
  s0 <- (as.numeric(seed) %% 9973) + 1
  vapply(as.character(x), function(s) {
    h <- s0
    for (b in utf8ToInt(s)) h <- (h * 131 + b) %% 1000003
    h / 1000003
  }, numeric(1), USE.NAMES = FALSE)
}

.die <- function(fmt, ...) stop(paste0("\n[fq073] ★STOP: ", sprintf(fmt, ...), "\n"), call. = FALSE)
cat(sprintf("[fq073] arm=%s horizon=%dM tiebreak=%s seed=%s lag_extra=%d selection_type=%s\n",
            CFG$arm, CFG$horizon_m, CFG$tiebreak, format(CFG$tiebreak_seed),
            CFG$lag_extra, CFG$selection_type))

#==============================================================================
# STEP 1. 관세청 HS 수출 패널 로드 — ★fail-closed (가짜 데이터 금지)
#
#   기대 스키마 (fq073/pull_customs_hs.py 산출, append-only vintage 스냅샷):
#     data_ym  chr "YYYY-MM"  — 수출 발생 캘린더 월
#     hs_code  chr            — API hsCode 원문(자릿수 가변 → 아래 정규화)
#     exp_usd  num            — expDlr (수출 신고 미화금액, FOB)
#     imp_usd  num            — impDlr (참고, 미사용) / stat_kor chr — 품목명
#   + vintage 라벨: manifest(customs_vintage_manifest.json) 또는 패널 vintage_tag 컬럼 (부재 시 stop)
#==============================================================================
PANEL <- Sys.getenv("FQ073_PANEL", file.path(FQ, "data_pull", "customs_hs_monthly.parquet"))
MANIF <- file.path(FQ, "data_pull", "customs_vintage_manifest.json")

if (!file.exists(PANEL)) {
  cat("\n[fq073] ★KEY-GATED (fail-closed): 관세청 HS 패널 부재 —", PANEL, "\n")
  cat("[fq073]   원인: data.go.kr org 1220000 활용신청 미승인 → API HTTP 403 Forbidden.\n")
  cat("[fq073]   해소: https://www.data.go.kr/data/15101609/openapi.do [활용신청](개발단계 자동승인)\n")
  cat("[fq073]        승인 후 -> python fq073_probe_after_approval.py (depth/자릿수 실측)\n")
  cat("[fq073]                -> python fq073/pull_customs_hs.py     (패널 + vintage 스냅샷)\n")
  cat("[fq073]                -> 본 러너 재실행 시 STEP 2~5 자동 진행\n\n")
  # dry-run 배관 검증: 데이터 외 의존물 실존만 확인 (수치 산출 없음)
  need <- c(".cache/RAWDATA.parquet",
            "02_Infrastructure/contracts/canonical_screen_bt.R",
            "02_Infrastructure/contracts/backtest_result_contract.R",
            "02_Infrastructure/validation/overlay_pit_guard.R",
            "02_Infrastructure/ramp/factor_validation.R")
  miss <- need[!file.exists(file.path(QM, need))]
  if (length(miss)) .die("배관 의존물 결손: %s", paste(miss, collapse = ", "))
  stopifnot(exists("assert_overlay_pit"), exists("holdings_signal_cutoff"),
            exists("canonical_screen_bt"), exists("build_monthly_forward_returns"),
            exists("build_benchmark_compare"))
  source(file.path(FQ, "hs_sector_map.R"), encoding = "UTF-8")
  fwrite(HS_SECTOR_MAP, file.path(FQ, "maps", "hs_sector_map.csv"), bom = TRUE)
  cat(sprintf("[fq073] dry-run OK — 의존물 %d/%d 실존 · 가드 5/5 로드 · HS->Sector 선언 %d행 emit(%d섹터).\n",
              length(need), length(need), nrow(HS_SECTOR_MAP), uniqueN(HS_SECTOR_MAP$Sector)))
  cat("[fq073] 데이터 게이트로 측정 미실시 (fail-closed). 산출 수치 없음.\n")
  quit(save = "no", status = 0)
}

CX <- as.data.table(read_parquet(PANEL))
req <- c("data_ym", "hs_code", "exp_usd")
if (!all(req %in% names(CX)))
  .die("패널 컬럼 결손 (필요 %s / 실제 %s)", paste(req, collapse = ","), paste(names(CX), collapse = ","))

# ── vintage 라벨 강제 (PIT_plan §2-b-1) ──────────────────────────────────────
VINT <- if (file.exists(MANIF)) fromJSON(MANIF) else list()
vintage_basis <- VINT$vintage_basis %||% (if ("vintage_tag" %in% names(CX)) as.character(CX$vintage_tag[1]) else NA_character_)
if (is.na(vintage_basis) || !nzchar(vintage_basis))
  .die("vintage_basis 라벨 부재. PIT_plan §2-b-1 = 라벨 없는 패널 소비 금지. manifest(%s) 또는 패널 vintage_tag 컬럼 필요.", MANIF)
if (!vintage_basis %in% c("revised_asof_pull", "first_release"))
  .die("vintage_basis='%s' 미인정. {revised_asof_pull, first_release} 만 허용.", vintage_basis)
pin_tag <- VINT$pin_tag %||% paste0("customs_", format(Sys.Date(), "%Y%m%d"))

CX <- CX[!is.na(data_ym) & !is.na(hs_code) & is.finite(exp_usd)]
CX[, data_ym := as.character(data_ym)]
# ── hs_code 정규화 ───────────────────────────────────────────────────────────
#   ★API 명세상 hsSgn 은 number 타입 → 반환 hsCode 가 **선행 0을 잃을 수 있다**
#     ("0301" 수산물 -> "301"). 그대로 substr(1,2) 하면 "30"(의약품)으로 오분류된다.
#     자릿수는 항상 짝수(2/4/6/10)여야 하므로 홀수면 좌측 0-pad 로 복원한다.
CX[, hs_code := gsub("[^0-9]", "", as.character(hs_code))]
CX <- CX[nchar(hs_code) > 0]
n_pad <- sum(nchar(CX$hs_code) %% 2L == 1L)
if (n_pad > 0) {
  CX[nchar(hs_code) %% 2L == 1L, hs_code := paste0("0", hs_code)]
  cat(sprintf("[fq073] hs_code 선행0 복원: %d행 (number 타입 반환으로 절단된 것 — 수산물 03 등)\n", n_pad))
}
if (!nrow(CX)) .die("패널 유효행 0")

cat(sprintf("[fq073] 패널: %d행 · hs %d종 · %s~%s · vintage_basis=%s · pin=%s\n",
            nrow(CX), uniqueN(CX$hs_code), min(CX$data_ym), max(CX$data_ym), vintage_basis, pin_tag))
if (identical(vintage_basis, "revised_asof_pull"))
  cat("[fq073] ⚠ 개정-vintage 백필 — 결과는 '개정판 상한'으로만 해석(PIT_plan §2-a). 게이트 주장 시 라벨 동반 의무.\n")
lenc <- CX[, .N, by = .(len = nchar(hs_code))][order(len)]
cat("[fq073] hs_code 자릿수 분포:", paste(sprintf("%d자리=%d", lenc$len, lenc$N), collapse = " · "), "\n")

#==============================================================================
# STEP 2. HS 수출 증감률 (kM YoY, log-diff)
#   · 팩터 계산이지 포트폴리오 수익 *구성* 이 아님 → 자체합성 금지 규약 비해당
#     (금지 대상 = prod(1+r)/cumprod/가중합으로 수익률 시계열을 합성하는 것)
#   · 결측월 규약(PIT_plan §6-7): 활동구간 내부 결측 = 실적 0, 구간 밖 = 행 없음(NA)
#==============================================================================
H <- CX[, .(exp_usd = sum(exp_usd, na.rm = TRUE)), by = .(hs_code, data_ym)]
span <- H[, .(ym0 = min(data_ym), ym1 = max(data_ym)), by = hs_code]
grid <- span[, .(data_ym = format(seq(as.Date(paste0(ym0, "-01")),
                                      as.Date(paste0(ym1, "-01")), by = "month"), "%Y-%m")),
             by = hs_code]
H <- merge(grid, H, by = c("hs_code", "data_ym"), all.x = TRUE)
H[is.na(exp_usd), exp_usd := 0]
setorder(H, hs_code, data_ym)

K <- CFG$horizon_m
H[, exp_kM    := frollsum(exp_usd, K,   align = "right"), by = hs_code]
H[, exp_kM_ly := shift(exp_kM, 12L),                      by = hs_code]
H[, exp_12m   := frollsum(exp_usd, 12L, align = "right"), by = hs_code]
H[, g := fifelse(is.finite(exp_kM) & is.finite(exp_kM_ly) & exp_kM_ly >= CFG$yoy_base_min_usd,
                 log(pmax(exp_kM, 1)) - log(pmax(exp_kM_ly, 1)), NA_real_)]
HG <- H[is.finite(g), .(hs_code, data_ym, g, exp_12m)]
if (!nrow(HG))
  .die("HS %dM-YoY 산출 0행 — 패널 depth(<%d개월?) 또는 YoY base 하한(%.0e USD) 확인", K, K + 12L, CFG$yoy_base_min_usd)
cat(sprintf("[fq073] HS %dM-YoY: %d행 · hs %d종 · %s~%s\n",
            K, nrow(HG), uniqueN(HG$hs_code), min(HG$data_ym), max(HG$data_ym)))

#==============================================================================
# STEP 3. 종목 매핑
#   ARM_S: hs → Sector 개념 concordance (선언, longest-prefix 4자리→2자리)
#          섹터 내 HS 가중 = trailing 12M 수출액 (데이터월<=M → PIT-clean)
#   ARM_F: hs → Ticker 제품믹스 (DART 사업보고서). ★effective_from as-of join 의무
#==============================================================================
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150", "Sector")))
RAW[, Date := as.Date(Date)]
# 신호 구간 밖(관세청 패널 이전)까지 forward-return/벤치를 만들 이유가 없다 —
# 스코어 시작 前 2개월만 여유로 두고 절단(측정 결과 불변, 스캔 비용만 절감).
DATE_FLOOR <- as.Date(paste0(ym_add(min(HG$data_ym), -2L), "-01"))
RAW <- RAW[Date >= DATE_FLOOR]
if (!nrow(RAW)) .die("RAWDATA 절단 후 0행 (DATE_FLOOR=%s)", as.character(DATE_FLOOR))
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
setkeyv(RAWME, "Date")

map_vintage_mode <- NA_character_; survivorship_flag <- FALSE

if (CFG$arm %in% c("S_3M", "S_6M")) {
  source(file.path(FQ, "hs_sector_map.R"), encoding = "UTF-8")
  fwrite(HS_SECTOR_MAP, file.path(FQ, "maps", "hs_sector_map.csv"), bom = TRUE)
  MP <- as.data.table(HS_SECTOR_MAP)[, .(hs_key = as.character(hs_key), Sector)]
  MP[, klen := nchar(hs_key)]

  U <- unique(HG[, .(hs_code)])
  U[, `:=`(p4 = substr(hs_code, 1, 4), p2 = substr(hs_code, 1, 2))]
  U <- merge(U, MP[klen == 4L, .(p4 = hs_key, sec4 = Sector)], by = "p4", all.x = TRUE)
  U <- merge(U, MP[klen == 2L, .(p2 = hs_key, sec2 = Sector)], by = "p2", all.x = TRUE)
  U[, Sector := fifelse(!is.na(sec4), sec4, sec2)]
  hs2sec <- U[!is.na(Sector), .(hs_code, Sector)]

  n_map <- uniqueN(hs2sec$Sector)
  cat(sprintf("[fq073] HS->Sector: %d/%d hs코드 매핑 · %d섹터\n",
              nrow(hs2sec), uniqueN(HG$hs_code), n_map))
  if (n_map < CFG$min_mapped_sectors)
    .die("매핑 섹터 %d < 하한 %d — 횡단 랭킹 무의미. hs_code 자릿수/커버리지 확인(PIT_plan §6-4).",
         n_map, CFG$min_mapped_sectors)

  SG <- merge(HG, hs2sec, by = "hs_code")
  SG[, w := fifelse(is.finite(exp_12m) & exp_12m > 0, exp_12m, 0)]
  SEC <- SG[, .(sec_score = if (sum(w) > 0) sum(g * w) / sum(w) else NA_real_, n_hs = .N),
            by = .(data_ym, Sector)][is.finite(sec_score)]
  if (!nrow(SEC)) .die("섹터 스코어 0행")
  cat(sprintf("[fq073] 섹터 스코어: %d행 · %d섹터 · %s~%s\n",
              nrow(SEC), uniqueN(SEC$Sector), min(SEC$data_ym), max(SEC$data_ym)))
  fwrite(SEC, file.path(OUT, "sector_score_panel.csv"), bom = TRUE)
  map_vintage_mode <- "concept_time_invariant"

} else if (identical(CFG$arm, "F_3M")) {
  FM <- Sys.getenv("FQ073_FIRMMAP", file.path(FQ, "maps", "hs_firm_map.parquet"))
  if (!file.exists(FM))
    .die(paste0("ARM_F 매핑 부재 — %s\n",
                "  DART 사업보고서 제품별 매출로 (Ticker, hs_code, weight, disclosed_date,\n",
                "  effective_from, source) 스키마를 먼저 구축하라(PIT_plan §4-b).\n",
                "  정적 '현재 제품믹스'로 과거를 귀속하는 대체 = C1/C3 위반 — 금지."), FM)
  FMP <- as.data.table(read_parquet(FM))
  needf <- c("Ticker", "hs_code", "weight")
  if (!all(needf %in% names(FMP))) .die("hs_firm_map 컬럼 결손 (필요 %s)", paste(needf, collapse = ","))
  FMP[, hs_code := gsub("[^0-9]", "", as.character(hs_code))]
  FMP[nchar(hs_code) %% 2L == 1L, hs_code := paste0("0", hs_code)]
  if (!"effective_from" %in% names(FMP) || uniqueN(FMP$effective_from) <= 1L) {
    map_vintage_mode <- "static_current"
    FMP[, effective_from := as.Date("1900-01-01")]
    cat("[fq073] ⚠ hs_firm_map effective_from 부재/단일 → map_vintage_mode=static_current.\n")
    cat("[fq073]   PIT_plan §4-b: 진단 상한으로만 보고, graduation 게이트 판정 금지(gate_eligible=FALSE).\n")
  } else {
    map_vintage_mode <- "asof_vintaged"
    FMP[, effective_from := as.Date(effective_from)]
  }
  survivorship_flag <- TRUE   # crosswalk 2023+ 유니버스 기반 (PIT_plan §6-6)

} else .die("미지원 arm='%s' (S_3M|S_6M|F_3M)", CFG$arm)

#==============================================================================
# STEP 4. PIT 배치 + C5 HARD 가드 + 동률 처리 → scores(Date, Ticker, score)
#
#   ★불변식 (PIT_plan §3-a): 홀딩월 H 신호 = 데이터월 H-2 까지. 스코어는 H-1 거래월말에.
#     score_date d  ->  홀딩월 = month(d)+1  ->  data_ym = month(d)-1-LAG_EXTRA
#     usable_date   = (data_ym+1)월 15일  [1차 현행화 완료 = 확정 lane]
#     holding_start = holdings_signal_cutoff(d)  [= month(d)+1 의 1일]
#==============================================================================
SD <- data.table(score_date = MEND)
SD[, data_ym       := ym_add(format(score_date, "%Y-%m"), -1L - CFG$lag_extra)]
SD[, usable_date   := as.Date(sprintf("%s-%02d", ym_add(data_ym, 1L), CFG$pub_confirmed_day))]
SD[, holding_start := holdings_signal_cutoff(score_date)]
SD[, buffer_days   := as.integer(holding_start - usable_date)]

# (1) C5 HARD — 신호 컷오프가 홀딩월 시작 이후면 즉시 stop
assert_overlay_pit(SD$usable_date, SD$holding_start, label = "FQ073_customs_export")
# (2) 등호-경계(razor edge) 추가 차단 — assert_overlay_pit 은 u>h 만 막으므로 버퍼를 별도 강제
bad_buf <- SD[buffer_days < CFG$min_buffer_days]
if (nrow(bad_buf))
  .die("PIT 버퍼 미달 %d행 (min=%d일). 예: usable=%s holding_start=%s buffer=%d일",
       nrow(bad_buf), CFG$min_buffer_days, as.character(bad_buf$usable_date[1]),
       as.character(bad_buf$holding_start[1]), bad_buf$buffer_days[1])
.k <- max(1L, nrow(SD) %/% 2L)
cat(sprintf("[fq073] C5 PASS — buffer %d~%d일 (요건 >=%d) · lag_extra=%d · 예시: data_ym=%s usable=%s holding_start=%s\n",
            min(SD$buffer_days), max(SD$buffer_days), CFG$min_buffer_days, CFG$lag_extra,
            SD$data_ym[.k], as.character(SD$usable_date[.k]), as.character(SD$holding_start[.k])))

# 종목 패널 (신호일 시점 유니버스 플래그. C6/멤버십 PIT 는 표준 forward 함수가 재차 강제)
SME <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker, Sector, Size, Vol, Close)]

if (CFG$arm %in% c("S_3M", "S_6M")) {
  SC <- merge(SME[!is.na(Sector)][, .(score_date = Date, Ticker, Sector, Size, Vol, Close)],
              SD[, .(score_date, data_ym, usable_date, holding_start)], by = "score_date")
  SC <- merge(SC, SEC[, .(data_ym, Sector, sec_score)], by = c("data_ym", "Sector"))
} else {
  # ── ARM_F as-of vintage join: (Ticker, score_date) 별 effective_from<=score_date 최신 1건 ──
  FMPu <- unique(FMP[, .(Ticker, effective_from)])
  FMPu[, ef_matched := effective_from]
  setkey(FMPu, Ticker, effective_from)
  Q <- CJ(Ticker = unique(FMPu$Ticker), effective_from = sort(unique(SD$score_date)))
  setkey(Q, Ticker, effective_from)
  MV <- FMPu[Q, roll = TRUE]                       # roll=TRUE → query 이하 최신 관측
  MV <- MV[!is.na(ef_matched), .(Ticker, score_date = effective_from, eff_use = ef_matched)]
  if (!nrow(MV)) .die("ARM_F: effective_from <= score_date 조건 만족 매핑 0행 (map vintage가 전부 미래?)")
  if (any(MV$eff_use > MV$score_date)) .die("ARM_F: 미래 vintage 누출 검출 — 즉시 중단(C1)")
  cand <- merge(MV, FMP, by.x = c("Ticker", "eff_use"), by.y = c("Ticker", "effective_from"),
                allow.cartesian = TRUE)
  cand <- merge(cand, SD[, .(score_date, data_ym, usable_date, holding_start)], by = "score_date")
  cand <- merge(cand, HG[, .(hs_code, data_ym, g)], by = c("hs_code", "data_ym"))
  if (!nrow(cand)) .die("ARM_F: hs_firm_map ∩ HS증감률 조인 0행 — hs_code 자릿수 정합 확인")
  FS <- cand[, .(sec_score = if (sum(weight, na.rm = TRUE) > 0)
                    sum(g * weight, na.rm = TRUE) / sum(weight, na.rm = TRUE) else NA_real_,
                 n_hs = .N), by = .(score_date, Ticker)][is.finite(sec_score)]
  SC <- merge(SME[, .(score_date = Date, Ticker, Sector, Size, Vol, Close)], FS,
              by = c("score_date", "Ticker"))
  SC <- merge(SC, SD[, .(score_date, data_ym, usable_date, holding_start)], by = "score_date")
}
if (!nrow(SC)) .die("스코어 조인 0행 — 섹터/티커 라벨 정합 확인")

# ── 동률 처리 (PIT_plan §4-e) ────────────────────────────────────────────────
SC[, tie_key := switch(CFG$tiebreak,
     neutral_hash = .hash01(Ticker, CFG$tiebreak_seed),
     size_desc    = -as.numeric(fifelse(is.finite(Size), Size, 0)),
     liq_desc     = -as.numeric(fifelse(is.finite(Vol * Close), Vol * Close, 0)),
     .die("미지원 tiebreak='%s' (neutral_hash|size_desc|liq_desc)", CFG$tiebreak))]
setorder(SC, score_date, -sec_score, tie_key)
SC[, ord := seq_len(.N), by = score_date]
# canonical_screen_bt 는 setorder(Date,-score) 후 top_n 만 사용 → 순서만 전달하면 충분.
# score = -ord 로 동률을 완전히 제거해 '숨은 임의 정렬'(FQ-066 패턴)을 차단한다.
SC[, score := -as.numeric(ord)]

scores   <- SC[, .(Date = score_date, Ticker, score)]
univ_cov <- SC[, .(n = uniqueN(Ticker)), by = score_date][, mean(n)]
cat(sprintf("[fq073] scores: %d행 · %d월 · 월평균 스코어부여 종목 %.0f개 · tiebreak=%s\n",
            nrow(scores), uniqueN(scores$Date), univ_cov, CFG$tiebreak))

#==============================================================================
# STEP 5. 표준 forward returns + ★벤치 lagged HARD 감사 + canonical 실측
#==============================================================================
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt; bench_dt <- fwd$bench_dt; liq_dt <- fwd$liq_dt
if (!nrow(returns_dt)) .die("forward returns 0행")

#--- 5a. 벤치마크 lagged 감사 (Return.portfolio 재구성 대조) -------------------
#   표준 build_monthly_forward_returns(line 50-53)는 벤치 가중에 Size0(=d0 시점 시총)을
#   쓴다고 *서술* 한다. 서술을 믿지 않고 재구성으로 실증한다:
#     rp_lag     = Return.portfolio(R, weights = Size at d0)   <- lagged (정상)
#     rp_contemp = Return.portfolio(R, weights = Size at d1)   <- contemporaneous (look-ahead)
#   frozen bench 가 rp_lag 와 일치(<=tol)하고 rp_contemp 와는 유의하게 다르면 PASS.
#   ★판별력의 원천: 만약 frozen 이 Size1 을 썼다면 두 부등식이 정반대로 나온다.
bench_lag_audit <- function(RAWME, MEND, bench_dt, tol) {
  per <- vector("list", length(MEND) - 1L)
  for (i in seq_len(length(MEND) - 1L)) {
    d0 <- MEND[i]; d1 <- MEND[i + 1L]
    c0 <- RAWME[.(d0), .(Ticker, Close0 = Close, K200, KQ150, Size0 = Size), nomatch = NULL]
    c1 <- RAWME[.(d1), .(Ticker, Close1 = Close, Size1 = Size), nomatch = NULL]
    if (!nrow(c0) || !nrow(c1)) next
    m <- merge(c0, c1, by = "Ticker")
    m <- m[(K200 == TRUE | KQ150 == TRUE) & !is.na(Close0) & Close0 > 0 & !is.na(Close1)]
    if (!nrow(m)) next
    m[, Ret_1m := Close1 / Close0 - 1]
    m <- m[!(is.finite(Ret_1m) & (Ret_1m > 5.0 | Ret_1m < -1.0))]   # R44 parity
    if (!nrow(m)) next
    per[[i]] <- m[, .(d0, d1, Ticker, Ret_1m, Size0, Size1)]
  }
  P <- rbindlist(Filter(Negate(is.null), per))
  if (!nrow(P)) return(list(status = "no_data"))
  tk <- sort(unique(P$Ticker))
  wide <- function(dt, idcol, val) {
    W <- dcast(dt, stats::as.formula(paste0(idcol, " ~ Ticker")), value.var = val, fill = 0)
    ids <- W[[idcol]]; W[, (idcol) := NULL]
    miss <- setdiff(tk, names(W)); if (length(miss)) W[, (miss) := 0]
    M <- as.matrix(W[, tk, with = FALSE]); rownames(M) <- as.character(ids); M
  }
  Rm  <- wide(P, "d1", "Ret_1m")
  W0m <- wide(P, "d0", "Size0"); W1m <- wide(P, "d0", "Size1")
  W0m[!is.finite(W0m)] <- 0; W1m[!is.finite(W1m)] <- 0
  nrm <- function(M) { s <- rowSums(M); s[s <= 0] <- NA_real_; M / s }
  W0m <- nrm(W0m); W1m <- nrm(W1m)
  ok  <- stats::complete.cases(W0m) & stats::complete.cases(W1m)
  if (sum(ok) < 12L) return(list(status = "insufficient_weight_rows", n = sum(ok)))
  d1s <- sort(unique(P$d1)); d0s <- sort(unique(P$d0))
  Rx  <- xts(Rm, order.by = d1s)
  rp  <- function(Wm) tryCatch({
    z <- PerformanceAnalytics::Return.portfolio(Rx, weights = xts(Wm[ok, , drop = FALSE],
                                                                  order.by = d0s[ok]), verbose = FALSE)
    data.table(d1 = as.Date(zoo::index(z)), r = as.numeric(z[, 1]))
  }, error = function(e) NULL)
  a <- rp(W0m); b <- rp(W1m)
  if (is.null(a) || is.null(b)) return(list(status = "return_portfolio_failed"))
  mapd <- data.table(d0 = MEND[-length(MEND)], d1 = MEND[-1L])
  B <- merge(as.data.table(bench_dt)[, .(d0 = as.Date(Date), BM_Ret)], mapd, by = "d0")
  A <- merge(merge(B, a, by = "d1"), b, by = "d1", suffixes = c("_lag", "_con"))
  if (nrow(A) < 12L) return(list(status = "insufficient_overlap", n = nrow(A)))
  dl <- mean(abs(A$BM_Ret - A$r_lag)); dc <- mean(abs(A$BM_Ret - A$r_con))
  list(status = "ok", n_months = nrow(A),
       mean_abs_diff_vs_lagged = dl, mean_abs_diff_vs_contemporaneous = dc,
       verdict = if (dl <= tol && dc > max(10 * tol, 10 * dl)) "LAGGED_CONFIRMED"
                 else if (dc < dl) "CONTEMPORANEOUS_SUSPECTED" else "INCONCLUSIVE")
}
BA <- bench_lag_audit(RAWME, MEND, bench_dt, CFG$tol_bench_equal)
cat(sprintf("[fq073] 벤치 lagged 감사: status=%s verdict=%s |Δ|lag=%.3e |Δ|contemp=%.3e n=%s\n",
            BA$status, BA$verdict %||% "-", BA$mean_abs_diff_vs_lagged %||% NA_real_,
            BA$mean_abs_diff_vs_contemporaneous %||% NA_real_, BA$n_months %||% NA))
if (!identical(BA$verdict, "LAGGED_CONFIRMED")) {
  if (!identical(Sys.getenv("FQ073_ALLOW_UNAUDITED_BENCH"), "1"))
    .die(paste0("벤치마크 lagged 실증 실패 (status=%s verdict=%s).\n",
                "  contemporaneous size-weight 벤치 = look-ahead (2026-07-18 실사고).\n",
                "  감사 통과 전 측정 금지 — fail-closed.\n",
                "  (진단 목적 강행은 FQ073_ALLOW_UNAUDITED_BENCH=1, 그 산출은 게이트 비적격)"),
         BA$status, BA$verdict %||% "-")
  cat("[fq073] ⚠ FQ073_ALLOW_UNAUDITED_BENCH=1 — 산출은 게이트 비적격(gate_eligible=FALSE).\n")
}

#--- 5b. C5 의무4: score→forward-ret IC 부호 (윈도우 의미 실증, advisory) ------
icm <- merge(SC[, .(Date = score_date, Ticker, sec_score)], returns_dt, by = c("Date", "Ticker"))
ic_by_m <- icm[, if (.N >= 10L && stats::sd(sec_score) > 0 && stats::sd(Ret_1m) > 0)
                   .(ic = stats::cor(sec_score, Ret_1m, method = "spearman")) else .(ic = NA_real_),
               by = Date][is.finite(ic)]
ic_mean <- if (nrow(ic_by_m)) mean(ic_by_m$ic) else NA_real_
ic_t    <- if (nrow(ic_by_m) > 2L) mean(ic_by_m$ic) / (stats::sd(ic_by_m$ic) / sqrt(nrow(ic_by_m))) else NA_real_
cat(sprintf("[fq073] rank-IC(advisory): mean=%.4f t=%.2f n=%d  [부호 양수 = PIT 윈도우 방향 정상]\n",
            ic_mean, ic_t, nrow(ic_by_m)))

#--- 5c. canonical_screen_bt (계약 경유 실측 — 손계산 금지) --------------------
res <- canonical_screen_bt(
  scores, returns_dt[, .(Date, Ticker, Ret_1m)], bench_dt[, .(Date, BM_Ret)],
  top_n = CFG$top_n, cost_bps_oneway = CFG$cost_bps_oneway,
  liq_dt = liq_dt[, .(Date, Ticker, adv)], liq_min = CFG$liq_min,
  size_dt = SME[, .(Date, Ticker, Size)],          # cap-tier 분해 병기 의무
  run_id = sprintf("FQ073_%s_lag%d", CFG$arm, CFG$lag_extra),
  strategy_id = sprintf("FQ073_CustomsExport_%s", CFG$arm),
  diag_dual_basis = TRUE)
n_months <- res$n_months %||% 0L
if (n_months < CFG$min_months)
  cat(sprintf("[fq073] ⚠ n_months=%s < %d — OOS 3분할/게이트 판정 부적격 (진단 전용).\n", n_months, CFG$min_months))

#--- 5d. calmar / MDD (PerformanceAnalytics 표준함수만) -----------------------
risk <- list(calmar = NA_real_, mdd = NA_real_, ann = NA_real_)
if (!is.null(res$period_returns) && nrow(res$period_returns) >= 12L) {
  rr  <- xts(res$period_returns$ret_net, order.by = as.Date(res$period_returns$date))
  ann <- as.numeric(Return.annualized(rr, scale = 12))
  mdd <- as.numeric(maxDrawdown(rr))
  risk <- list(calmar = if (is.finite(mdd) && mdd > 0) ann / mdd else NA_real_, mdd = mdd, ann = ann)
}
cat(sprintf("[fq073] CANONICAL %s: nM=%s PORT_t=%.3f p=%.3f IR=%.3f netSR=%.3f calmar=%.3f TO=%.2f\n",
    CFG$arm, n_months, res$portfolio_alpha_t_nw_lag3 %||% NA_real_,
    res$portfolio_alpha_t_pvalue %||% NA_real_, res$information_ratio %||% NA_real_,
    res$net_sr %||% NA_real_, risk$calmar %||% NA_real_, res$turnover_annual %||% NA_real_))
if (!is.null(res$diag_ew_universe$portfolio_alpha_t_nw_lag3))
  cat(sprintf("[fq073]   dual-basis EW-universe PORT_t=%.3f (진단·비바인딩)\n",
              res$diag_ew_universe$portfolio_alpha_t_nw_lag3))

#--- 5e. 산출 (metric_type + PIT 라벨 전량 동반) ------------------------------
.pick <- function(x, nm) if (is.list(x)) x[intersect(names(x), nm)] else NULL
SUMM <- list(
  fq = "FQ-073", generated = as.character(Sys.time()), arm = CFG$arm,
  metric_type = "canonical_screen",
  metric_type_note = "canonical_screen_bt 계약 실측(top-25 EW long-only, cap-w 벤치 권위). admission binding 아님 — forge build_bt_result 가 authoritative.",
  vintage_basis = vintage_basis, pin_tag = pin_tag,
  map_vintage_mode = map_vintage_mode, survivorship_exposed = survivorship_flag,
  selection_type = CFG$selection_type,
  selection_note = "PRIMARY 단일 사전등록 스펙. 로버스트니스 arm 중 argmax 선택 시 sweep 재분류 + DSR>=0.5 HARD 부활(measurement-graduation §3).",
  gate_eligible = identical(BA$verdict, "LAGGED_CONFIRMED") &&
                  !identical(map_vintage_mode, "static_current") &&
                  n_months >= CFG$min_months,
  # ★게이트 적격이어도 아래 caveat 은 판정문에 **반드시 동반**한다(이진 통과로 삼키지 말 것)
  gate_caveats = Filter(nzchar, c(
    if (identical(vintage_basis, "revised_asof_pull"))
      "개정-vintage 백필: API에 vintage 파라미터 부재 → 전 역사가 최신 개정판. 결과는 '개정판 상한'(PIT_plan §2-a). 해소 = 월간 스냅샷 축적 후 first_release 재판정." else "",
    if (isTRUE(survivorship_flag))
      "survivorship 노출: crosswalk 2023+ 유니버스 기반이라 과거 상폐사 결측(PIT_plan §6-6)." else "",
    if (identical(map_vintage_mode, "static_current"))
      "정적 제품믹스 매핑: 과거 귀속에 현재 믹스 사용 = C1/C3 위반 → 진단 상한 전용, graduation 금지." else "",
    if (!identical(CFG$tiebreak, "neutral_hash"))
      sprintf("tiebreak='%s': 섹터 내 선택에 크기/유동성 베팅이 혼입 — 순수 섹터신호 아님(PIT_plan §4-e).", CFG$tiebreak) else "",
    "HS 코드체계 개정(2012/2017/2022) 단절 미보정 — 6자리 사용 시 concordance 필요(PIT_plan §6-4).",
    "expDlr = USD 기준 → 원화절하기 수출증가 과소평가(PIT_plan §6-5).")),
  pit = list(
    rule = "C5 — 홀딩월 H 신호는 데이터월 H-2 까지. 스코어는 H-1 거래월말 배치.",
    lag_extra_months = CFG$lag_extra,
    publication = list(
      first_release = "data_ym M 전체 -> M+1월 1일 (잠정)",
      confirmed     = "매월 15일경 전월까지 자료 현행화 (무기한 반복)",
      evidence      = "fq073/publication_lag_evidence.json · fq073/first_release_evidence.json (HTTP 200 원문)"),
    buffer_days = list(min = min(SD$buffer_days), max = max(SD$buffer_days), required = CFG$min_buffer_days),
    assert_overlay_pit = "PASS",
    bench_lag_audit = BA),
  canonical = list(
    n_months = n_months, top_n = CFG$top_n,
    portfolio_alpha_t_nw_lag3 = res$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue  = res$portfolio_alpha_t_pvalue,
    information_ratio = res$information_ratio, alpha_annualized = res$alpha_annualized,
    net_sr = res$net_sr, turnover_annual = res$turnover_annual,
    calmar = risk$calmar, mdd = risk$mdd, ann_return = risk$ann),
  diag = list(
    rank_ic_mean = ic_mean, rank_ic_t = ic_t,
    rank_ic_note = "advisory only (measurement-graduation §3 — rank-IC 계열은 게이트 비바인딩)",
    univ_scored_avg = univ_cov,
    ew_universe = .pick(res$diag_ew_universe,
                        c("portfolio_alpha_t_nw_lag3", "information_ratio", "net_sr",
                          "post2017_t_nw_lag3", "n_months")),
    cap_tier    = .pick(res$diag_cap_tier,
                        c("available", "weight_share_avg", "contrib_gross_annualized"))),
  hard_gates = list(
    port_t_ge_2_95 = (res$portfolio_alpha_t_nw_lag3 %||% NA_real_) >= 2.95,
    calmar_ge_0_64 = (risk$calmar %||% NA_real_) >= 0.64,
    oos_retention_note = "권위 = essence_score.R (v2 anchored 3분할 중앙값). 본 러너는 canonical diag 근사만 병기."),
  config = CFG
)
tag <- sprintf("%s_lag%d_%s", CFG$arm, CFG$lag_extra, CFG$tiebreak)
write_json(SUMM, file.path(OUT, sprintf("fq073_summary_%s.json", tag)),
           auto_unbox = TRUE, na = "null", pretty = TRUE, digits = 8)
if (!is.null(res$period_returns))
  fwrite(res$period_returns, file.path(OUT, sprintf("fq073_period_returns_%s.csv", tag)))
fwrite(SD, file.path(OUT, sprintf("fq073_pit_schedule_%s.csv", tag)), bom = TRUE)

cat(sprintf("\n[fq073] 저장: %s\n", file.path(OUT, sprintf("fq073_summary_%s.json", tag))))
cat(sprintf("[fq073] gate_eligible=%s (bench_audit=%s · map_mode=%s · n_months=%s · vintage=%s)\n",
            SUMM$gate_eligible, BA$verdict %||% "-", map_vintage_mode, n_months, vintage_basis))
if (CFG$lag_extra == 0L)
  cat("[fq073] ★의무 후속: LAG1 스트레스 = FQ073_LAG_EXTRA=1 재실행 후 base 대비 붕괴 여부 대조(PIT_plan §3-e).\n")
