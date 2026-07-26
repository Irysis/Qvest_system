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
nps <- as.data.table(read_parquet(NPS_RAW))   # data_ym, wkpl_nm, bizno6, hc, amt, acq, lss, wkpl_norm

# ─── STEP 2. crosswalk join: bizno6 prefix + 사업장명 → Ticker ───────────────
#   ★2026-07-25 실측: 국민연금 공표 사업자등록번호는 **앞 6자리 마스킹**(파일·API 공통).
#     PIT_plan §3이 예고한 마스킹 분기가 실현됨 → full 10자리 exact join 불가.
#     6자리는 세무서코드(3)+구분(2)+일련 첫자리(1)라 firm 고유키가 아니다
#     (crosswalk 내부만도 충돌 prefix 69개 / 관여 상장사 190사).
#   조인 전략: prefix로 후보 축소 → **사업장명 정규화 매칭**으로 확정.
#     startsWith 우선, 실패분만 부분포함 폴백. 다중 상장사 충돌 시 **최장 corp_norm 우선**
#     (예: '삼성전자'와 '삼성전자서비스'가 동시 후보면 더 긴 쪽이 정확한 매칭).
#   census 실측(2026-06): prefix 존재 474/474 · 사업장명 매칭 436/474 · 매칭 사업장수 median 1.
#   ⚠잔여 편향: 기업마다 신고구조가 달라 롤업 완전성이 불균일(삼성전자=전사 단일 신고 vs
#     기아=공장 사업장이 별도 명칭으로 분리되어 이름매칭에서 누락). 레벨 횡단비교는 오염되나
#     본 팩터가 Δln 모멘텀이라 시간-불변 누락은 차분에서 소거된다. 단 사업장 신설·분할은
#     가짜 점프를 만들므로 STEP 3에 outlier 가드 필수.
xw <- as.data.table(read_parquet(file.path(SCAF, "firm_crosswalk.parquet")))
.norm <- function(s) gsub("[[:space:]\\-\\.,]", "", gsub("\\(주\\)|㈜|주식회사|\\(유\\)", "", s))
xw[, bizno6 := substr(as.character(bizr_no), 1, 6)]
xw[, corp_norm := .norm(as.character(corp_name))]
nps[, bizno6 := sprintf("%06s", as.character(bizno6))]

cand <- merge(nps, xw[, .(bizno6, Ticker, corp_norm)], by = "bizno6", allow.cartesian = TRUE)
cand[, hit := startsWith(wkpl_norm, corp_norm)]
cand[hit == FALSE, hit := mapply(grepl, corp_norm, wkpl_norm, MoreArgs = list(fixed = TRUE))]
cand <- cand[hit == TRUE]
#   한 사업장이 복수 상장사에 매칭되면 최장 corp_norm 하나만 채택(과대계상 방지)
cand[, .nlen := nchar(corp_norm)]
setorder(cand, data_ym, wkpl_nm, -.nlen)
cand <- unique(cand, by = c("data_ym", "wkpl_nm", "bizno6"))
cat(sprintf("[fq064] 매칭 사업장-월 %d행 / 상장사 %d사 / 월 %d\n",
            nrow(cand), uniqueN(cand$Ticker), uniqueN(cand$data_ym)))

#   법인-내 다-사업장 합산 (대기업 필수)
firm <- cand[, .(member_cnt = sum(hc, na.rm = TRUE),
                 pay_amt    = sum(amt, na.rm = TRUE),
                 acq_cnt    = sum(acq, na.rm = TRUE),
                 lss_cnt    = sum(lss, na.rm = TRUE),
                 n_wkpl     = .N), by = .(Ticker, data_ym)]

# ─── STEP 3. 헤드카운트 모멘텀 팩터 (PIT usable_date = data_ym M+1 15일) ────────
setorder(firm, Ticker, data_ym)
#   FQ064_BASE 로 정보축 선택 — 국민연금 원장은 헤드카운트 말고도 축이 더 있다:
#     hc  = 가입자수(고용 스톡)          pay = 당월고지금액(총보수 프록시, 質까지 반영)
#     chn = (신규취득+상실)/가입자수      = 고용 churn 강도(방향 아닌 불안정성)
#   base 자체는 이론적 선택이며 argmax 대상이 아니다. 각 측정은 n_trials에 누적 기록.
.BASE <- Sys.getenv("FQ064_BASE", "hc")
firm[, base_val := switch(.BASE,
                          hc  = as.numeric(member_cnt),
                          pay = as.numeric(pay_amt),
                          chn = (as.numeric(acq_cnt) + as.numeric(lss_cnt)) / pmax(member_cnt, 1),
                          stop("FQ064_BASE는 hc|pay|chn"))]
firm[, ln_hc := log(pmax(base_val, 1e-6))]
#   ★결측월 방어: 패널에 구멍이 있다(실측 결측 2020-03~05·2022-09~11). shift(3)은 행 기준이라
#     구멍을 건너뛰어 실제로는 6개월 간격인 쌍을 3M으로 오인한다 → **달력 기준 명시 조인**.
firm[, mi := as.integer(substr(data_ym, 1, 4)) * 12L + as.integer(substr(data_ym, 6, 7))]
for (h in c(3L, 6L)) {
  lagd <- firm[, .(Ticker, mi_t = mi + h, ln_lag = ln_hc, nw_lag = n_wkpl)]
  firm <- merge(firm, lagd, by.x = c("Ticker", "mi"), by.y = c("Ticker", "mi_t"), all.x = TRUE)
  set(firm, j = sprintf("mom%d", h), value = firm$ln_hc - firm$ln_lag)
  set(firm, j = sprintf("nwchg%d", h), value = firm$n_wkpl != firm$nw_lag)
  firm[, c("ln_lag", "nw_lag") := NULL]
}
#   ★outlier/구성변화 가드: 사업장 개수가 창 안에서 바뀌면 헤드카운트 점프가 신호가 아니라
#     매칭 구성 변화(신설·분할·명칭변경)일 수 있다 → 해당 관측 제외. 추가로 |Δln|>log(2)
#     (3개월 내 2배 변동)는 물리적으로 고용 신호로 보기 어려워 제외(정직: 진짜 대형 M&A도
#     함께 잘리나, 오염 유입보다 보수적 손실을 택함).
firm[nwchg3 == TRUE | abs(mom3) > log(2), mom3 := NA_real_]
firm[nwchg6 == TRUE | abs(mom6) > log(2), mom6 := NA_real_]
cat(sprintf("[fq064] mom3 유효 %d / 전체 %d (구성변화·극단 제외 후)\n",
            sum(is.finite(firm$mom3)), nrow(firm)))
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
#   신호 방향·horizon은 env로 명시 선택(암묵 default 금지 — n_trials 감사 가능성).
#   FQ064_SIGN=-1 : employment growth anomaly 방향(고용성장 低 롱). 문헌 사전 부호
#     (Bazdresch-Belo-Lin 계열: low employment growth → high subsequent returns).
#     ★부호는 자유 파라미터가 아니라 이론이 정하는 값 — sweep 아닌 사전-이론 선택으로 기록.
#   FQ064_H=3|6 : 헤드카운트 모멘텀 horizon.
.SIGN <- as.numeric(Sys.getenv("FQ064_SIGN", "1"))
.H    <- Sys.getenv("FQ064_H", "3")
.col  <- paste0("mom", .H)
firm[, .sig := get(.col) * .SIGN]
scores <- firm[is.finite(.sig) & !is.na(sig_date), .(Date = sig_date, Ticker, score = .sig)]
if (nrow(scores) == 0L) stop("[fq064] scores 0행 — PIT map/커버리지 확인 필요")
cat(sprintf("[fq064] signal=%s x sign(%+.0f) | scores %d행\n", .col, .SIGN, nrow(scores)))

# ─── STEP 5. canonical_screen_bt (계약 경유 — PORT_t/IR/SR 자체합성 없음) ───────
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
stopifnot(exists("build_benchmark_compare"))
res <- canonical_screen_bt(scores[, .(Date, Ticker, score)], returns_dt, bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq_dt, liq_min = 2e8,
                           run_id = sprintf("FQ064_hc_%s_%s", .H, ifelse(.SIGN < 0, "neg", "pos")), strategy_id = sprintf("NPS_HC_Mom_%sM_%s", .H, ifelse(.SIGN < 0, "neg", "pos")),
                           diag_dual_basis = TRUE)   # M2 dual-basis(EW-uni/cap-tier) 병기
res$benchmark_compare <- NULL; res$period_returns <- NULL
write_json(res, file.path(OUT, sprintf("fq064_canonical_%s_%sM_%s.json", .BASE, .H, ifelse(.SIGN < 0, "neg", "pos"))), auto_unbox = TRUE, na = "null", pretty = TRUE)
cat(sprintf("[fq064] n_months=%s PORT_t=%.3f net_sr=%.3f IR=%.3f\n",
    res$n_months, res$portfolio_alpha_t_nw_lag3 %||% NA, res$net_sr %||% NA, res$information_ratio %||% NA))
