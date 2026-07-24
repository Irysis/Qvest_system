#==============================================================================
# run_fq064_headcount.R — FQ-064 국민연금 헤드카운트 모멘텀 측정 러너 (스캐폴드 템플릿)
#
#   ★상태: data.go.kr 키 랜딩 前 스캐폴드. STEP 1(데이터 pull)만 placeholder,
#          STEP 2~5(crosswalk join → 팩터 → canonical)는 실배선(RAWDATA/benchmark/crosswalk
#          는 지금 실존). 키 랜딩 시 STEP 1 placeholder만 실 pull로 교체하면 1커맨드 측정.
#
#   실행: bash 02_Infrastructure/ops/safe_run.sh Rscript \
#           stage_artifacts/method_frontier/firm_level_scaffold/run_fq064_headcount.R
#
#   규율(전부 적용): K200∪KQ150 · top-25 EW long-only · [0,0.20] · liq>=2e8 · 15bps ·
#                    PIT usable_date=M+1 15일 · canonical_screen_bt 계약(자체합성 없음)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a,b) if (is.null(a)) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SCAF <- "stage_artifacts/method_frontier/firm_level_scaffold"
OUT  <- file.path(SCAF, "fq064_out"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ─── STEP 1. data.go.kr 국민연금 사업장 가입자수 pull  ★KEY-GATED placeholder ──────
#   키 랜딩 시 이 블록을 실 pull로 교체. 엔드포인트: 국민연금공단_국민연금 가입 사업장 내역
#   (data.go.kr 3046071 / 15071659). 반환 firm-month 원장 스키마(기대):
#     bizr_no(사업자등록번호), data_ym(기준월), member_cnt(가입자수), plan_name(사업장명)
#   ★PIT: pull 시점의 vintage를 그대로 스냅샷 저장(개정 소급 금지). usable_date=data_ym M+1 15일.
#   FQ064_NPS_RAW env로 경로 override 가능 (합성 패널 배관 스모크용 — 실판정엔 기본 경로만).
NPS_RAW <- Sys.getenv("FQ064_NPS_RAW", file.path(SCAF, "data_pull", "nps_headcount_raw.parquet"))
if (!file.exists(NPS_RAW)) {
  cat("[fq064] ★KEY-GATED: NPS pull 산출 부재:", NPS_RAW, "\n")
  cat("[fq064]   data.go.kr 15083277 활용신청 승인 후 pull_nps.py가 이 parquet 생성 →\n")
  cat("[fq064]   본 러너 재실행 시 STEP 2~5 자동 진행. 지금은 배관 검증(dry) 종료.\n")
  # dry-run 배관 검증: crosswalk·rawdata·benchmark 실존 확인만
  stopifnot(file.exists(file.path(SCAF, "firm_crosswalk.parquet")),
            file.exists(".cache/rawdata.parquet"), file.exists(".cache/benchmark.parquet"))
  cat("[fq064] dry-run OK — crosswalk/RAWDATA/benchmark 실존. STEP 2~5 배선 준비 완료.\n")
  quit(save = "no", status = 0)
}
nps <- as.data.table(read_parquet(NPS_RAW))   # bizr_no, data_ym, member_cnt

# ─── STEP 2. crosswalk join: bizr_no → Ticker ────────────────────────────────
xw <- as.data.table(read_parquet(file.path(SCAF, "firm_crosswalk.parquet")))
#   ★조인은 full bizr_no(10자리) 우선. 국민연금 공표가 6자리 마스킹이면 bizr_no6 조인은
#     121건 충돌(crosswalk_coverage) → 사업장명+소재지 disambiguation 필요(PIT_plan §3).
nps <- merge(nps, xw[, .(bizr_no, Ticker)], by = "bizr_no", all.x = FALSE)
#   법인-내 다-사업장 합산 (대기업 필수)
firm <- nps[, .(member_cnt = sum(member_cnt, na.rm = TRUE)), by = .(Ticker, data_ym)]

# ─── STEP 3. 헤드카운트 모멘텀 팩터 (PIT usable_date = data_ym M+1 15일) ────────
setorder(firm, Ticker, data_ym)
firm[, ln_hc := log(pmax(member_cnt, 1))]
firm[, mom3 := ln_hc - shift(ln_hc, 3L), by = Ticker]   # 3M Δln headcount
firm[, mom6 := ln_hc - shift(ln_hc, 6L), by = Ticker]   # 6M Δln headcount (대체 horizon)
#   ★PIT(FQ064 실측 수리 2026-07-25): data_ym=M 신호는 자격취득 신고마감(M+1월 15일) 이후에만
#     완전 관측 가능(PIT_plan §1). 따라서 신호를 홀딩월 M+1의 month-end에 배정하고
#     그 스코어로 M+2월 수익을 측정한다(usable(M+1 15일) < 홀딩월 M+1 말 → look-ahead 없음).
#     구 plac 자리표시(sig_date = data_ym-01, data월 시작)는 ~1.5개월 look-ahead → 제거.
#     sig_ym = data_ym + 1개월. 실 Date(거래월말)는 STEP 4의 me_map으로 부여(STEP 5 직전).
{
  .y <- as.integer(substr(firm$data_ym, 1, 4)); .m <- as.integer(substr(firm$data_ym, 6, 7)) + 1L
  .y <- .y + (.m > 12L); .m <- ifelse(.m > 12L, 1L, .m)
  firm[, sig_ym := sprintf("%04d-%02d", .y, .m)]        # 홀딩월(=data월 M+1) ym
}

# ─── STEP 4. 표준 forward returns + benchmark + liq (frozen 규약 재사용) ────────
#   ★2026-07-25 수리(키 랜딩 前 사전검증에서 적발): 손수 만든 month-end 수익/벤치를
#   표준 build_monthly_forward_returns로 교체. 구판 결함 2건 —
#   (a) ★유니버스 PIT 멤버십 미적용: K200/KQ150 플래그를 로드만 하고 필터에 쓰지 않아
#       유니버스를 static crosswalk(474사, 시점 컬럼 전무)가 결정 → C6 survivorship
#       (과거 상폐사 결측) + 비-PIT 멤버십(후행 편입사를 전기간 편입 취급). 표준 함수는
#       신호일 d0 시점 플래그로 필터한다(factor_validation.R:39).
#   (b) 벤치 월간화에 prod(1+BM_Ret)-1 자체합성 사용 → backtest-contract 명시 금지 패턴이며,
#       표준 벤치(유니버스 시총가중 단일구간 forward, compounding 없음)와 basis도 불일치
#       → realized_ym 정렬 offset 리스크(reference-book-benchmark-alignment-realized-ym).
#   표준 경유로 두 결함 동시 해소 + 기존 라운드와 basis parity 확보.
#   ※ Close 기반 Ret_1m은 표준도 동일 규약(factor_validation.R:40) + R44 sanity 방화벽
#     (표준 내부 + canonical_screen_bt 입력단 이중) → 결함 아님.
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns (frozen)
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% .MEND]                       # 월말만 (표준 함수 asof 스캔 비용 절감)
fwd <- build_monthly_forward_returns(RAWME, .MEND)
returns_dt <- fwd$returns_dt; bench_dt <- fwd$bench_dt; liq_dt <- fwd$liq_dt
#   ⚠ 표준 루프는 seq_len(n-1)이라 마지막 sig_date에 forward 짝이 없어 드롭 → 그 달 liq 공백
#     (기지: reference-forward-returns-terminal-month-liq-gap). STEP 4b의 sig_date NA 제외가 흡수.
#   ⚠ 표준 liq = Vol0*Close0(당월말 1일 거래대금). 헌법 LIQ_THRESHOLD는 20일 ADV 기준이라
#     보수성 방향이 다를 수 있음 → 본판정 후 ADV20 변형으로 robustness 재확인 대상.

# ─── STEP 4b. PIT Date 부여: sig_ym(홀딩월=M+1) → 그 달 거래 month-end ────────────
#   me_map: ym → month-end 거래일(.MEND). 신호를 홀딩월 말에 배정 → canonical이 다음달 수익 측정.
me_map <- data.table(ym = format(.MEND, "%Y-%m"), sig_date = .MEND)
firm <- merge(firm, me_map, by.x = "sig_ym", by.y = "ym", all.x = TRUE)
#   sig_ym이 RAWDATA 커버리지 밖(예: 최신월 홀딩월 미도래)이면 sig_date=NA → 자동 제외(보수적).
scores <- firm[is.finite(mom3) & !is.na(sig_date), .(Date = sig_date, Ticker, score = mom3)]
if (nrow(scores) == 0L) stop("[fq064] scores 0행 — PIT map/커버리지 확인 필요")

# ─── STEP 5. canonical_screen_bt (계약 경유 — PORT_t/IR/SR 자체합성 없음) ───────
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
stopifnot(exists("build_benchmark_compare"))
res <- canonical_screen_bt(scores[, .(Date, Ticker, score)], returns_dt, bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq_dt, liq_min = 2e8,
                           run_id = "FQ064_headcount", strategy_id = "NPS_Headcount_Mom_3M",
                           diag_dual_basis = TRUE)   # M2 dual-basis(EW-uni/cap-tier) 병기
res$benchmark_compare <- NULL; res$period_returns <- NULL
write_json(res, file.path(OUT, "fq064_canonical.json"), auto_unbox = TRUE, na = "null", pretty = TRUE)
cat(sprintf("[fq064] n_months=%s PORT_t=%.3f net_sr=%.3f IR=%.3f\n",
    res$n_months, res$portfolio_alpha_t_nw_lag3 %||% NA, res$net_sr %||% NA, res$information_ratio %||% NA))
