# build_spec.R — SPEC-2 리밸 timing-luck 측정: 사전등록 스펙 동결 (측정 전 실행, 1회)
# 진단-only. 자본/BOOK 무변경. 텔레그램 금지.
# 순서: RAWDATA pin(입력 동결) → spec.json 작성(판정 규칙 사전등록) → sha256 동결.
# 이후 run_timing_luck.R은 spec.json 해시 일치 검증 후에만 측정 수행.
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", ARROW_NUM_THREADS = "1")
suppressMessages({ library(data.table); library(jsonlite); library(digest) })
setDTthreads(1)

root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(root)
outdir <- file.path(root, "stage_artifacts/spec2_timing_luck")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

spec_path <- file.path(outdir, "spec.json")
if (file.exists(spec_path)) stop("[SPEC2] spec.json 이미 존재 — 사전등록 불변성 위반 방지, overwrite 거부")

source(file.path(root, "02_Infrastructure/data/pin_cache.R"))

# ── 1) 입력 동결: RAWDATA 신규 pin + FQ-011 pinned carrier 재사용 ─────────────
CARRIER_PIN_TAG <- "fq011_20260710_222924"   # FQ-011 재검증이 쓴 pinned carrier 재사용 (과제 지시)
carrier_file <- "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
carrier_pinned_path <- read_pinned(carrier_file, CARRIER_PIN_TAG)  # md5 무결성 검증 포함
carrier_md5 <- unname(tools::md5sum(carrier_pinned_path))

RAW_PIN_TAG <- "spec2_timing_luck_20260711_163751"   # 최초 실행에서 생성된 pin 재사용 (불변성)
raw_src <- file.path(root, ".cache/rawdata.parquet")
if (!file.exists(file.path(root, ".cache/pins", RAW_PIN_TAG, "manifest.json"))) {
  pin_cache(raw_src, RAW_PIN_TAG)
}
raw_pinned_path <- read_pinned(raw_src, RAW_PIN_TAG)  # 원경로 매칭 (FS canonical case = RAWDATA.parquet)
raw_basename <- basename(raw_pinned_path)
raw_md5 <- unname(tools::md5sum(raw_pinned_path))

# ── 2) 사전등록 스펙 (판정 규칙 — 측정 전 동결, 이후 수정 금지) ────────────────
spec <- list(
  spec_id   = "SPEC2_TIMING_LUCK_20260711",
  frozen_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  purpose   = paste0(
    "현 book recon은 월 1회 anchor_date 단일 시계열 — 리밸 집행일 시점운(timing-luck) 분산 미측정. ",
    "본 측정은 진단-only(자본/BOOK 무변경). 프레임: timing-luck 완화(tranche)는 기대 SR 레버가 아니라 ",
    "실현 경로 분산 축소 레버 — SR 개선 주장 금지."),
  inputs = list(
    carrier = list(
      pin_tag = CARRIER_PIN_TAG, file = carrier_file, md5 = carrier_md5,
      source_note = "FQ-011 PORT_t 챔피언십 재검증이 사용한 pinned weighted_screen carrier (book recon holdings, STR_1715_AR_on_M4_R05_overlay_PG2)",
      weights_col = "weight_strategy", month_key = "decision_date", n_months_expect = 269L
    ),
    rawdata = list(
      pin_tag = RAW_PIN_TAG, file = raw_basename, md5 = raw_md5,
      cols_used = c("Date", "Ticker", "Ret"),
      role = "일별 종목수익(Ret) + 거래일 캘린더(distinct Date, 전 종목)"
    )
  ),
  design = list(
    anchor_rule  = "anchor(m) = pinned RAWDATA 거래일 캘린더에서 decision_date(m) 이상 첫 거래일 (carrier 엔진 start_d와 동일 정의)",
    offsets_bdays = c(0L, 1L, 2L, 3L, 4L, 5L),
    exec_rule    = "exec_k(m) = 캘린더상 anchor(m)로부터 +k번째 거래일. 월별 목표 비중(weight_strategy)은 전 offset 동일 — 집행일만 시프트",
    pit_guard    = "stopifnot(all(exec >= anchor)) AND stopifnot(all(exec_k(m) < anchor(m+1))) — 집행일이 다음 월 anchor 침범 금지",
    nav_engine   = "PerformanceAnalytics::Return.portfolio(일별 Ret 패널, weights@exec_k, geometric drift, verbose) — 포트 수익 손계산 금지(python-policy 안 A 정합). 결측 일수익은 0 처리(carrier ret_fwd의 prod-over-available과 동일 의미)",
    overlay      = "exposure=1 (bare equity carrier). 오버레이 노출은 월 스칼라로 전 offset에 공통 곱 — range 판정에 중립이라 진단 범위 밖 (한계에 명기)",
    cost = list(
      convention = "target-weight delta: traded(m) = sum(|w_m - w_{m-1}|) (ticker union, 첫월 buy-in=1 포함) x 15bps one-way",
      charge_timing = "exec_k(m) 직후 첫 수익일에 차감 (신규 비중이 live가 되는 첫 날)",
      invariance = "목표비중이 offset 무관 동일하므로 target-delta 회전율은 offset 불변(구성상) — 산출물에 확인 기록. drift-기반 실현 회전(sum|w_target - EOP@exec|)은 진단으로 병기",
      cost_model_version = "v2.4_kr_retail_15bps (delta-based)"
    ),
    common_window = "6-NAV 일별 수익 index 교집합에서만 지표 산출 (시작·끝 정렬)",
    metrics = list(
      SR   = "공통창 일별 net 수익 → apply.monthly(x, Return.cumulative) 월별 집계 → mean/sd*sqrt(12), Rf=0 (프로젝트 컨벤션, weighted_screen_bt와 동일). 판정은 이 SR만 사용",
      SR_crosscheck = "table.AnnualizedReturns(monthly, scale=12) Sharpe 병기 (판정 비사용)",
      CAGR = "table.AnnualizedReturns(monthly, scale=12) Annualized Return",
      MDD  = "maxDrawdown(공통창 일별 net)"
    ),
    validation = "k=0 gross 홀딩창 수익 vs pinned carrier recon(sum(w*ret_fwd) by month) parity — cor 및 max|diff| 기록 (하니스 자기검증 앵커)"
  ),
  verdict_rule = list(
    statistic  = "range_SR = max(SR_k) - min(SR_k), k in {0..5}, 사전등록 SR 컨벤션",
    threshold  = 0.05,
    if_below   = "settled-null 종료 — tranche 불요",
    if_at_or_above = "tranche(반월 2분할: 리밸 전이의 50%를 anchor+0에, 잔여 50%를 anchor+10거래일에 집행. 비중 근사 = anchor일 0.5*w_prev_target + 0.5*w_new_target, anchor+10일 w_new_target) 1 NAV 추가 산출·보고. 채택 여부는 G5 도훈 — 본 측정은 채택 권고 아님",
    no_sr_improvement_claim = TRUE
  ),
  discipline = c("실측-only", "pin_cache 소비(원본 .cache 직접 재로드 금지)", "단일스레드",
                 "잔류 R 프로세스 kill 후 실행", "텔레그램 금지", "자본/BOOK 무변경"),
  metric_type = "backtested",
  basis = "absolute NAV (bare carrier, no overlay) — 진단-only"
)

write_json(spec, spec_path, auto_unbox = TRUE, pretty = TRUE, digits = 10)
sha <- digest(file = spec_path, algo = "sha256")
writeLines(sha, file.path(outdir, "spec.json.sha256"))
cat(sprintf("[SPEC2] spec 동결 완료: %s\n  sha256 = %s\n  carrier pin = %s (md5 %s)\n  rawdata pin = %s (md5 %s)\n",
            spec_path, sha, CARRIER_PIN_TAG, carrier_md5, RAW_PIN_TAG, raw_md5))
