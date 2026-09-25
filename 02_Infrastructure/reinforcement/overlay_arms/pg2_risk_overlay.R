#==============================================================================
# pg2_risk_overlay — BOOK_0001 PG2 리스크 오버레이(게이트 × β_R05)를 동결 사양 그대로 무조건 적용
#   (v10.4 · 2026-09-17 · 계열 book_spec · 축 scalar_exposure / multivar)
#
# ★무엇을 하나
#   BOOK_0001 = STR_1715_on_M4gAE_R05_noLayer4_PG2 의 생산 오버레이 두 층을 **상수·표·창·절차 그대로**
#   다른 전략의 보유 위에 얹는다. 총노출 e_t = gate_t × β_t ∈ [0,1], 나머지 = 현금(GEN:170 invested = gate × β_R05).
#     ① gate_t (GEN:129-131) = 0.70 if (m4 발화[weight_str1715 < 0.999] ∧ AE 발화[fire_seq == 1]) else 1.00
#     ② β_t   (GEN:148)     = 국면(CRISIS / CAUTION / BULL·NORMAL) × zlt(보유 R05 z 평균 < 자기 과거 20분위) 표
#   이 파일의 숫자 리터럴은 새 튜닝이 아니라 **동결된 생산 사양의 인용**이다 — BOOK_0001 은 도훈 confirm 으로
#   등록된 사양이고 미러 파일은 핀 레지스트리(02_Infrastructure/ops/generator_pins.json · sha1 ad7a007f)가 고정한다.
#   그래서 상수마다 출처 줄 번호를 옆에 적는다(원문 줄 번호 기준일 2026-09-17).
#
# ★출처 약어
#   GEN   = 02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R          (배포 생성기 미러 · 게이트·β 결합)
#   ALPHA = stage_artifacts/WT_D20260425_010/_recompute_alpha_asof.R       (국면 라벨 산출 · 18-37행)
#   L5    = 02_Infrastructure/portfolio/run_layer5_rerun_extended.R         (과거전용 확장 20분위 282-296행 · β 표 V5)
#   FE    = qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R (m4 패널 생산자 · lag 규약 480-482·536-538·972)
#   ENG   = 02_Infrastructure/reinforcement/rf_cell_engine.R                (arm 호출 규약 563-576 · 682-704 · 727-730)
#
# ★계약 (ENG:563-576 · 682-704)
#   overlay_expo_pg2_risk_overlay(H, t, ctx) → 스칼라 e ∈ [0,1].
#   ctx$date = 신호일 d(월말 거래일) · 홀딩월 = d 의 익월(집행 = 익월 첫 거래일 · ENG:727-729 와 같은 규약) ·
#   ctx$hold$Ticker = 그 달 보유. H 는 읽지 않는다 — 이 arm 의 상태는 전부 PG2 의 외부 패널과 팩터 DB 에서 온다
#   (H$fwd 섭동에 불변). 엔진의 워밍업 축소(ENG:690 · t < n_min=24 에서 1−e 를 t/24 배로 줄인다)는 엔진 소관이라
#   여기서 되돌리지 않는다.
#
# ★PIT (pit.md C5·C11·C14·C15)
#   모든 외부 읽기는 홀딩월 시작일(hs = 익월 1일) **이전** 정보만 쓴다 — 패널마다 assert_overlay_pit(cutoff, hs) HARD.
#     m4 패널  : 행 = 홀딩월(YM). 정보 컷오프 = 전월 말(FE:480-482·536-538 shift(…,1) · FE:972 "weight at t uses
#                regime[t-1], bocpd[t-1], decay[≤t-1]"). 행의 Date 는 집행일(월 1일과 첫 거래일이 섞여 있다 — 실측)이라
#                컷오프로도 조인 키로도 쓰지 않는다.
#     AE 패널  : decision_date = 홀딩월 1일. 정보 컷오프 = last_feat_date (GEN:125 stopifnot(last_feat < AS_OF) 미러).
#     국면     : 벤치·시장 폭 창 종점 = 홀딩월 직전 월말 me (ALPHA:23-24 CUT = AS_OF − 1 · ALPHA:34 sig = 익월 1일).
#     팩터 DB  : load_month_factors(d) 단일 경유(C15 · ENG:203 과 같은 호출) — 파일 = 신호일 d 의 달
#                = GEN:137 factor_db_{AS_OF−1 의 달}. 패널 as-of = attr factor_db_asof_date(NA 면 결손 처리 · 합성 금지).
#   조인은 전부 **연월**로 한다 — PG2 가 결정일 AS_OF(=hs)에 읽는 바로 그 행(m4 YM==홀딩월 · AE decision_date==hs ·
#   국면 sig==hs · 팩터 DB 월==d 의 달).
#
# ★PIT C11 (2026-09-24 · 판정서 V-02 · 결정 PIT-C11-REMEDIATION 안 B 1단계) — 위 컷오프(전월 말·last_feat)는 **날짜
#   라벨**이다. 해외(FRED) 정보를 담는 두 패널(m4·AE)은 라벨이 전월 말이어도 미국 월말 종가(한국 d 종가 뒤 세션)와
#   공표 전 주간값(STLFSI4 +7일·NFCI +6일)을 담았다 — L1 은 신호일 d 종가에 체결하므로(close_d_legacy) 같은 날짜
#   미국 월말 종가 218/223개월, STLFSI4 223/223 · NFCI 187/223 이 결정 시점에 미가용이었다(V3 s12_arm.R).
#   assert_overlay_pit 는 라벨만 비교해 통과시켰다. 이제:
#     · 두 패널은 C11 표식(c11_info_cutoff · c11_regime_key — 생산자: ae_pit_features.py · m4 factor_engine.R)을
#       **요구**한다. 없으면 적재에서 stop — 수리 전 판 위에서 이 arm 을 재지 않는다(중립 강등도 하지 않는다:
#       강등하면 'pg2 arm' 이라는 이름으로 다른 처치를 잰 칸이 생긴다).
#     · 규칙 epoch(c11_regime_key)가 현행 기반(S0) 규칙과 다르면 stop(현행 규칙으로 재빌드).
#     · 호출마다 해외 정보 컷오프 ≤ 신호일 d 를 HARD 로 건다(d 종가 결정 = 판정서 ② 형태 a). close_t1(익일 체결)
#       에도 d 는 집행보다 이르므로 보수 방향이다. 국내 입력(국면 라벨·팩터 DB)의 홀딩월 가드는 그대로 둔다.
#   ※아래 '오프라인 검증'(2026-09-17)은 라벨 컷오프 기준이라 C11 적합의 증거가 아니다.
#
# ★결손 처리 (사전등록 결정 5)
#   어느 달이든 입력이 없으면 그 성분만 중립값(gate 1 · NORMAL · zlt FALSE)으로 두고 진단 카운터에 적는다.
#   합성 픽스처(probe)의 가짜 종목은 팩터 DB 에 없으므로 z 결손 → zlt FALSE, 패널 커버리지 밖의 달은 중립값 —
#   오류 없이 저하한다. 진단 = pg2_overlay_diag() · 월별 자취 = pg2_overlay_trace().
#
# ★사양 그대로 재현하지 못하는 것 (편차 — arm.json basis 에도 적는다)
#   · zlt 의 과거 z 이력은 PG2 자기 픽 이력이 아니라 **이 책의 자기 픽 이력**(엔진이 arm 을 처음 부른 달부터 누적).
#   · 방향 정렬은 커넥터 기본(min_ic_months=36 · sig_date=d)이고 GEN:141 은 (12 · AS_OF)다 — C15 가 커넥터를
#     강제하므로 그대로 두고 차이는 검증 기록에 정량으로 남긴다.
#   · CRISIS 의 종목별 비중 상한(GEN:57 ub 0.10)은 총노출을 바꾸지 않으므로 범위 밖.
#   · AE 패널 이전(2008-01 이전)의 달은 gate 가 발화할 수 없다(중립 1).
#
# ★오프라인 검증 (2026-09-17 · 결정일 2008-01~2026-09 · hold = PG2 자기 픽 top-20 · 백테 0)
#   (a) gate = 패널 재구성(연월 조인) 225/225. GEN:92 축자(Date<=AS_OF 최신행)와는 5개월 갈린다 — m4 행 Date 가 1일보다
#       늦은 달(108/225)에 축자 규칙이 전월 행을 집기 때문이며, 연월 조인이 PG2 가 뜻한 행이다.
#       z = L5 정본 R05_z_avg 와 224/224 동일(max|Δ| 0 → 방향 정렬 36/12개월 차이의 실효 0) · zlt 224/224 ·
#       β 가 갈린 53개월은 전부 국면 라벨 차이. 국면 = 저장 이력(alpha_scores.regime_state)과 4분류 124/225 ·
#       BULL 접힘 172/225 — 현행 ALPHA 가 낸 최근 행(2026-06~09)은 일치하고, 그 이전 행은 저장고에 코드가 없는
#       원 파이프라인 산출(세 스냅샷 269/269 동일 = 재서술 아님)이라 현재 데이터 위의 ALPHA 절차와 갈린다.
#   (b) strict-PIT: 명시 날짜필터(info < hs) 독립 재계산과 0/273 개월 차이 · ALPHA 방식 결정일별 절단 재계산(CUT=AS_OF−1)
#       225/225 동일 · 패널 937행 + 팩터 as-of 273개월 전부 < 홀딩월 시작(max cutoff−hs = −1일).
#   (c) lag-1(진단): 전 입력을 1개월 더 늦추면 gate 14 · 국면 45 · zlt 65 · β 99 · e 103 / 225 개월이 바뀐다.
#==============================================================================
suppressWarnings(suppressPackageStartupMessages({ library(data.table); library(arrow) }))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.PG2_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# ── 동결 사양 상수 (재사용 · 출처 줄 번호) ────────────────────────────────────
.PG2_GATE_DERISK <- 0.70     # GEN:131 — m4 ∧ AE 동시 발화 시 총노출 배율
.PG2_M4_FIRE_LT  <- 0.999    # GEN:130 — m4 발화 = weight_str1715 < 0.999
.PG2_AE_FIRE     <- 1L       # GEN:131 — AE 발화 = fire_seq == 1
.PG2_BETA <- list(CRISIS  = c(zlt = 0.30, base = 0.50),   # GEN:148 · L5 V5 — (국면, zlt) → β
                  CAUTION = c(zlt = 0.50, base = 0.70),
                  NORMAL  = c(zlt = 0.85, base = 1.00))
.PG2_REGIME_MAP  <- c(BULL = "NORMAL", NORMAL = "NORMAL", CAUTION = "CAUTION", CRISIS = "CRISIS")  # GEN:148 BULL ≡ NORMAL
.PG2_ZLT_Q       <- 0.20     # GEN:147 · L5:295 — 과거 z 의 20분위
.PG2_ZLT_MIN_OBS <- 12L      # L5:287 — 과거 관측 12 미만이면 문턱 미정의 → zlt FALSE
.PG2_RG_W  <- c(rv = 0.35, r1 = 0.25, dd = 0.25, b6 = 0.15)   # ALPHA:32 — 국면 점수 가중
.PG2_RG_Q  <- c(0.30, 0.65, 0.85)                             # ALPHA:33 — 확장 분위 절단 (BULL/NORMAL/CAUTION/CRISIS)
.PG2_RG_WARMUP   <- 12L      # ALPHA:33 — i < 12 또는 과거 < 12 → NORMAL
.PG2_EP_MIN      <- 6L       # ALPHA:31 — 확장 백분위 과거 < 6 → 0.5
.PG2_WIN_VOL     <- 90L      # ALPHA:25 — 90일 창 변동성 (행 30 미만이면 그 달 없음)
.PG2_WIN_VOL_MIN <- 30L
.PG2_WIN_DD      <- 380L     # ALPHA:28 — 380일 창 낙폭 (행 20 미만이면 NA)
.PG2_WIN_DD_MIN  <- 20L
.PG2_WIN_BRD     <- 90L      # ALPHA:29 — 90일 창 시장 폭(일별 상승 종목 비율의 평균)
.PG2_FACTOR      <- "R05_Tail_Risk"   # GEN:140

.PG2_P <- list(
  m4    = file.path(.PG2_ROOT, "06_Registry/m4_published/m4_panel_published.parquet"),   # 발행 정본(GEN:91 원천과 동일 내용 · 실측 identical)
  ae    = file.path(.PG2_ROOT, "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"),   # GEN:96
  bm    = file.path(.PG2_ROOT, ".cache/benchmark.parquet"),   # ALPHA:19 load_rawdata → BM_DT
  raw   = file.path(.PG2_ROOT, ".cache/rawdata.parquet"),     # ALPHA:19 → RAWDATA (Date·Ret 두 열만 읽는다)
  guard = file.path(.PG2_ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"),
  fdc   = file.path(.PG2_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"),
  fa    = file.path(.PG2_ROOT, "02_Infrastructure/data/fred_availability.R"),   # C11 기반(S0) — 규칙 epoch 판독
  cache = file.path(.PG2_ROOT, ".cache/pg2_overlay"))

# ── PIT 가드 (정본 함수를 재구현하지 않는다) ──────────────────────────────────
.PG2_GUARD_ENV <- new.env(parent = globalenv())
source(.PG2_P$guard, local = .PG2_GUARD_ENV)
.pg2_assert_pit <- .PG2_GUARD_ENV$assert_overlay_pit

# ── ★C11 표식 계약 (2026-09-24) — 생산자와 같은 이름 · 규칙 epoch 는 기반(S0) 도우미에서만 읽는다 ──────
.PG2_C11_COLS <- c("c11_info_cutoff", "c11_regime_key")
.PG2_C11_KEY <- tryCatch({
  .fa_env <- new.env(parent = globalenv())
  source(.PG2_P$fa, local = .fa_env)
  as.character(.fa_env$fred_avail_rules_meta()$regime_key)
}, error = function(e) NA_character_)
.pg2_c11_require <- function(x, label, exempt = rep(FALSE, nrow(x))) {
  miss <- setdiff(.PG2_C11_COLS, names(x))
  if (length(miss))
    stop(sprintf(paste0("[pg2_risk_overlay] ★C11 미해소 패널(%s) — 표식 열 %s 없음(수리 전 판: 해외 특성 관측일 결합). ",
                        "2단계 재빌드 전에는 이 arm 으로 재지 않는다(판정서 V-02 · PIT-C11-REMEDIATION)"),
                 label, paste(miss, collapse = ",")))
  if (is.na(.PG2_C11_KEY))
    stop("[pg2_risk_overlay] ★C11 규칙 epoch 판독 불가 — ", .PG2_P$fa, " (기반 S0 도우미) 를 source 하지 못했다")
  cut <- as.Date(x$c11_info_cutoff); key <- as.character(x$c11_regime_key)
  chk <- !exempt
  if (any(chk & is.na(cut)))
    stop(sprintf("[pg2_risk_overlay] ★C11 미해소 행(%s) %d개 — c11_info_cutoff 결측", label, sum(chk & is.na(cut))))
  if (any(chk & (is.na(key) | key != .PG2_C11_KEY)))
    stop(sprintf(paste0("[pg2_risk_overlay] ★C11 규칙 epoch 불일치(%s) — 패널 '%s' vs 현행 '%s'. ",
                        "현행 규칙(06_Registry/fred_availability_rules.json)으로 재빌드할 것"),
                 label, key[chk][which(is.na(key[chk]) | key[chk] != .PG2_C11_KEY)[1]], .PG2_C11_KEY))
  cut
}

# ── 진단 ─────────────────────────────────────────────────────────────────────
.PG2_DIAG <- new.env(parent = emptyenv())
.PG2_DIAG_KEYS <- c("n_calls", "n_m4_missing", "n_ae_missing", "n_regime_missing", "n_regime_score_na",
                    "n_z_missing", "n_zlt_undefined", "n_gate_derisk", "n_ae_rows_dropped_pit",
                    "n_ae_rows_dropped_not_first", "n_asof_after_signal")
.pg2_diag_reset <- function() {
  for (k in .PG2_DIAG_KEYS) assign(k, 0L, envir = .PG2_DIAG)
  assign("trace", list(), envir = .PG2_DIAG)
}
.pg2_diag_add <- function(k, n = 1L) assign(k, get(k, envir = .PG2_DIAG) + as.integer(n), envir = .PG2_DIAG)
.pg2_diag_reset()

pg2_overlay_diag  <- function() mget(.PG2_DIAG_KEYS, envir = .PG2_DIAG)
pg2_overlay_trace <- function() {
  tr <- get("trace", envir = .PG2_DIAG)
  if (!length(tr)) return(NULL)
  rbindlist(tr, use.names = TRUE)
}

# ── 달력 도우미 (lubridate 무의존) ───────────────────────────────────────────
.pg2_ym <- function(d) format(as.Date(d), "%Y-%m")
.pg2_holding_start <- function(d) {   # 홀딩월 시작 = 익월 1일 (ENG:727-729 · overlay_pit_guard::holdings_signal_cutoff 와 동일)
  fm <- as.Date(format(as.Date(d), "%Y-%m-01"))
  y <- as.integer(format(fm, "%Y")); m <- as.integer(format(fm, "%m"))
  m2 <- m + 1L; y2 <- y + (m2 - 1L) %/% 12L; m2 <- ((m2 - 1L) %% 12L) + 1L
  as.Date(sprintf("%04d-%02d-01", y2, m2))
}
.pg2_read_cols <- function(path, want) {
  if (!file.exists(path)) return(NULL)
  tryCatch({
    have <- names(open_dataset(path, format = "parquet")$schema)
    as.data.table(read_parquet(path, col_select = intersect(want, have)))
  }, error = function(e) NULL)
}

# ── ① m4 패널 (GEN:91-93 · 130) ──────────────────────────────────────────────
.pg2_load_m4 <- function() {
  x <- .pg2_read_cols(.PG2_P$m4, c("Date", "YM", "weight_str1715", .PG2_C11_COLS, "c11_status"))
  if (is.null(x) || !nrow(x) || !"weight_str1715" %in% names(x)) return(NULL)
  if ("Date" %in% names(x)) x[, Date := as.Date(Date)]
  x[, ym := if ("YM" %in% names(x)) as.character(YM) else .pg2_ym(Date)]
  x <- x[!is.na(ym) & is.finite(weight_str1715)]
  if (!nrow(x)) return(NULL)
  x[, hs := as.Date(paste0(ym, "-01"))]       # 행 = 홀딩월
  x[, cutoff := hs - 1L]                       # 라벨 컷오프 = 전월 말 (FE lag 규약 · 파일 머리 참조)
  setorder(x, hs)
  x <- x[, .SD[.N], by = ym]                   # 연월당 1행 (발행본은 이미 유일 — 방어)
  .pg2_assert_pit(x$cutoff, x$hs, "pg2_risk_overlay:m4")
  # ★C11 — 해외 정보 컷오프는 생산자(factor_engine.R c11_regime_check)가 실은 표식으로만 안다.
  #   c11_status: verified(컷오프 있음) · no_regime(국면 미사용 워밍업 행 — 해외 정보 없음) · unresolved(표식 없음 → 거부)
  if (!"c11_status" %in% names(x))
    stop("[pg2_risk_overlay] ★C11 미해소 패널(m4) — c11_status 열 없음(수리 전 판). 2단계 재빌드 전에는 이 arm 으로 재지 않는다")
  if (any(x$c11_status == "unresolved" | is.na(x$c11_status)))
    stop(sprintf("[pg2_risk_overlay] ★C11 미해소 행(m4) %d개 — 상류 unified 월간 표식 없음(판정서 V-04)",
                 sum(x$c11_status == "unresolved" | is.na(x$c11_status))))
  x[, c11_cut := .pg2_c11_require(x, "m4", exempt = x$c11_status == "no_regime")]
  x[, .(ym, hs, cutoff, c11_cut, w = as.numeric(weight_str1715))]
}

# ── ② AE 패널 (GEN:96-127 · 131) ─────────────────────────────────────────────
.pg2_load_ae <- function() {
  x <- .pg2_read_cols(.PG2_P$ae, c("decision_date", "fire_seq", "last_feat_date", .PG2_C11_COLS))
  if (is.null(x) || !nrow(x) || !all(c("decision_date", "fire_seq", "last_feat_date") %in% names(x))) return(NULL)
  x[, decision_date := as.Date(decision_date)]   # GEN:101 과 동일 변환
  x[, last_feat := as.Date(last_feat_date)]
  x <- x[!is.na(decision_date) & !is.na(fire_seq)]
  # GEN:112 — 결정일은 홀딩월 1일 행만 (그 밖의 행은 PG2 가 신선도 FAIL 로 멈추는 행이다 → 사용하지 않는다)
  nf <- as.integer(format(x$decision_date, "%d")) != 1L
  .pg2_diag_add("n_ae_rows_dropped_not_first", sum(nf)); x <- x[!nf]
  # GEN:124-125 — last_feat 결측 또는 결정일 이후 = PIT 판정 불가 → 사용하지 않는다(그 달 중립 · 카운트)
  bad <- is.na(x$last_feat) | x$last_feat >= x$decision_date
  .pg2_diag_add("n_ae_rows_dropped_pit", sum(bad)); x <- x[!bad]
  if (!nrow(x)) return(NULL)
  x[, ym := .pg2_ym(decision_date)]
  x[, hs := decision_date]
  setorder(x, decision_date)
  x <- x[, .SD[.N], by = ym]
  .pg2_assert_pit(x$last_feat, x$hs, "pg2_risk_overlay:ae")
  # ★C11 — 표식(생산자 ae_pit_features.stamp) 요구. 해외 정보 컷오프 = max(last_feat, c11_info_cutoff)
  x[, c11_cut := pmax(last_feat, .pg2_c11_require(x, "ae"))]
  x[, .(ym, hs, cutoff = last_feat, c11_cut, fire = as.integer(fire_seq))]
}

# ── ③ 국면 라벨 (ALPHA:19-36 축자 재현 · 확장창 과거전용) ───────────────────
.pg2_breadth <- function() {
  # ALPHA:22 — 전 종목(유니버스 필터 없음)의 일별 상승 비율. 원천 1400만 행을 두 열만 읽어 일별로 접는다.
  # ★캐시: 원천(mtime·크기)이 같으면 일별 집계(약 9천 행)를 재사용한다 — 셀마다 원천을 다시 읽지 않는다.
  raw <- .PG2_P$raw
  if (!file.exists(raw)) return(NULL)
  fi  <- file.info(raw)
  key <- gsub("[^A-Za-z0-9]", "", paste0(format(fi$mtime, "%Y%m%d%H%M%S"), "_", fi$size))
  cp  <- file.path(.PG2_P$cache, sprintf("breadth_%s.rds", key))
  if (file.exists(cp)) {
    b <- tryCatch(readRDS(cp), error = function(e) NULL)
    if (is.data.table(b) && nrow(b) && all(c("Date", "b") %in% names(b))) return(b)
  }
  x <- .pg2_read_cols(raw, c("Date", "Ret"))
  if (is.null(x) || !nrow(x) || !"Ret" %in% names(x)) return(NULL)
  x[, Date := as.Date(Date)]
  b <- x[!is.na(Ret), .(b = mean(Ret > 0, na.rm = TRUE)), by = Date]
  rm(x); setorder(b, Date)
  tryCatch({
    dir.create(.PG2_P$cache, recursive = TRUE, showWarnings = FALSE)
    tmp <- paste0(cp, ".", Sys.getpid(), ".tmp"); saveRDS(b, tmp)
    if (!file.rename(tmp, cp) && file.exists(tmp)) unlink(tmp)   # 동시 실행이 먼저 썼으면 내 임시본만 지운다
  }, error = function(e) NULL)
  b
}

.pg2_regime_table <- function() {
  BM <- .pg2_read_cols(.PG2_P$bm, c("Date", "BM_Close", "BM_Ret", "Ret"))
  if (is.null(BM) || !nrow(BM) || !"Date" %in% names(BM)) return(NULL)
  BM[, Date := as.Date(Date)]
  brc <- if ("BM_Ret" %in% names(BM)) "BM_Ret" else "Ret"        # ALPHA:21
  if (!brc %in% names(BM) || !"BM_Close" %in% names(BM)) return(NULL)
  setorder(BM, Date)
  brd <- .pg2_breadth()
  # ALPHA:24 — 연월별 월말 거래일. ALPHA 는 CUT(=AS_OF−1) 이하만 모으지만 점수·라벨이 과거전용 확장창이라
  #   어느 CUT 에서 끊어도 같은 행은 같은 라벨이다 → 전 이력을 한 번에 만든다.
  me <- BM[, .(me = max(Date)), by = .(YM = format(Date, "%Y-%m"))]$me
  me <- sort(unique(me))
  bf <- function(m) {                                            # ALPHA:25-29
    w <- BM[Date <= m & Date > m - .PG2_WIN_VOL]
    if (nrow(w) < .PG2_WIN_VOL_MIN) return(NULL)
    rv <- stats::sd(w[[brc]], na.rm = TRUE) * sqrt(252)
    mc <- BM[Date == m, BM_Close][1]
    pm <- suppressWarnings(BM[format(Date, "%Y-%m") != format(m, "%Y-%m") & Date < m, max(Date)])
    pc <- if (length(pm) == 1L && is.finite(pm)) BM[Date == pm, BM_Close][1] else NA_real_   # 첫 달(직전 월 없음) 방어
    r1 <- if (!is.na(mc) && !is.na(pc) && pc > 0) mc / pc - 1 else NA_real_
    w2 <- BM[Date <= m & Date > m - .PG2_WIN_DD]
    dd <- if (nrow(w2) < .PG2_WIN_DD_MIN) NA_real_ else { px <- cumprod(1 + w2[[brc]]); min(px / cummax(px) - 1, na.rm = TRUE) }
    b6 <- if (is.null(brd)) NA_real_ else brd[Date <= m & Date > m - .PG2_WIN_BRD, mean(b, na.rm = TRUE)]
    data.table(me = m, rv = rv, r1 = r1, dd = dd, b6 = b6)
  }
  rf <- rbindlist(lapply(me, bf), fill = TRUE)
  if (is.null(rf) || !nrow(rf)) return(NULL)
  rf <- rf[!is.na(rv) & !is.na(dd)]; setorder(rf, me)            # ALPHA:30
  ep <- function(x) {                                            # ALPHA:31 — 확장 백분위(과거만)
    n <- length(x); o <- rep(NA_real_, n)
    for (i in seq_len(n)) {
      if (i == 1L) { o[i] <- 0.5; next }
      p <- x[seq_len(i - 1L)]; p <- p[is.finite(p)]
      o[i] <- if (length(p) < .PG2_EP_MIN) 0.5 else mean(p <= x[i], na.rm = TRUE)
    }
    o
  }
  rf[, sc := .PG2_RG_W[["rv"]] * ep(rv) + .PG2_RG_W[["r1"]] * ep(-r1) +
             .PG2_RG_W[["dd"]] * ep(-dd) + .PG2_RG_W[["b6"]] * ep(-b6)]   # ALPHA:32
  cl <- function(s, q = .PG2_RG_Q) {                             # ALPHA:33 — 확장 분위 절단(과거만)
    n <- length(s); o <- character(n); na_sc <- 0L
    for (i in seq_len(n)) {
      if (i < .PG2_RG_WARMUP) { o[i] <- "NORMAL"; next }
      p <- s[seq_len(i - 1L)]; p <- p[is.finite(p)]
      if (length(p) < .PG2_RG_WARMUP) { o[i] <- "NORMAL"; next }
      if (!is.finite(s[i])) { o[i] <- "NORMAL"; na_sc <- na_sc + 1L; next }   # ALPHA 는 여기서 죽는다 — 중립 + 카운트
      th <- stats::quantile(p, q, na.rm = TRUE, names = FALSE)
      o[i] <- if (s[i] <= th[1]) "BULL" else if (s[i] <= th[2]) "NORMAL" else if (s[i] <= th[3]) "CAUTION" else "CRISIS"
    }
    .pg2_diag_add("n_regime_score_na", na_sc)
    o
  }
  rf[, rs := cl(sc)]
  rf[, hs := .pg2_holding_start(me)]                             # ALPHA:34 — sig = 익월 1일 = PG2 결정일 AS_OF
  setorder(rf, hs, -me); rf <- rf[, .SD[1L], by = hs]            # ALPHA:35
  .pg2_assert_pit(rf$me, rf$hs, "pg2_risk_overlay:regime")
  rf[, .(hs, ym = .pg2_ym(hs), cutoff = me, sc, rs)]
}

# ── ④ 팩터 DB — C15 단일 경유 (커넥터를 사설 환경에 source · 전역 오염 없음) ────
.PG2_FDC <- NULL
.pg2_fdc_env <- function() {
  if (is.environment(.PG2_FDC)) return(.PG2_FDC)
  if (isFALSE(.PG2_FDC)) return(NULL)
  e <- new.env(parent = globalenv())
  assign("CACHE_DIR", file.path(.PG2_ROOT, ".cache"), envir = e)          # 커넥터가 config.R 대신 읽는 두 경로
  assign("FUNC_PATH", file.path(.PG2_ROOT, "02_Infrastructure"), envir = e)
  ok <- tryCatch({
    utils::capture.output(suppressMessages(suppressWarnings(source(.PG2_P$fdc, local = e))))
    exists("load_month_factors", envir = e, inherits = FALSE)
  }, error = function(z) FALSE)
  .PG2_FDC <<- if (isTRUE(ok)) e else FALSE
  if (isTRUE(ok)) e else NULL
}

.PG2_FCACHE <- new.env(parent = emptyenv())   # 연월 → list(z = data.table(Ticker, z), asof) 또는 NULL
.pg2_factor_panel <- function(d) {
  key <- .pg2_ym(d)
  if (exists(key, envir = .PG2_FCACHE, inherits = FALSE)) return(get(key, envir = .PG2_FCACHE, inherits = FALSE))
  out <- NULL
  e <- .pg2_fdc_env()
  if (!is.null(e)) {
    f <- tryCatch({
      utils::capture.output(res <- e$load_month_factors(as.Date(d), factor_names = .PG2_FACTOR))   # C15 · ENG:203 과 같은 호출
      res
    }, error = function(z) NULL)
    if (!is.null(f) && nrow(f) && "Z_Score_Aligned" %in% names(f)) {                                # C13 — 정렬 Z 만 소비
      asof <- suppressWarnings(as.Date(attr(f, "factor_db_asof_date") %||% NA))
      if (length(asof) == 1L && is.finite(asof))                                                     # as-of NA = 결손(합성 금지)
        out <- list(z = as.data.table(f)[, .(Ticker = as.character(Ticker), z = as.numeric(Z_Score_Aligned))], asof = asof)
    }
  }
  assign(key, out, envir = .PG2_FCACHE)
  out
}

.pg2_z_now <- function(d, tickers) {   # GEN:143 — 픽 ∩ 패널의 정렬 Z 평균(na.rm) · 교집합이 비면 NA
  tk <- unique(as.character(tickers %||% character(0))); tk <- tk[!is.na(tk) & nzchar(tk)]
  if (!length(tk)) return(list(z = NA_real_, asof = as.Date(NA), n = 0L))
  fp <- .pg2_factor_panel(d)
  if (is.null(fp)) return(list(z = NA_real_, asof = as.Date(NA), n = 0L))
  zz <- fp$z[Ticker %in% tk, z]; zz <- zz[is.finite(zz)]
  if (!length(zz)) return(list(z = NA_real_, asof = fp$asof, n = 0L))
  list(z = mean(zz), asof = fp$asof, n = length(zz))
}

# ── ⑤ zlt — 자기 과거 z 의 확장 20분위 (L5:282-296 · GEN:147) ─────────────────
#   ★이 책의 자기 픽 이력. 엔진은 t 오름차순으로 부르므로 신호일 < d 인 기록만 과거다 — 호출 순서가 달라도
#     미래 날짜의 기록은 배제되고(PIT), 순차 호출에서는 PG2 의 확장 20분위와 같은 절차가 된다.
.PG2_ZHIST <- new.env(parent = emptyenv())
.pg2_zlt <- function(d, z) {
  d <- as.Date(d)
  assign(as.character(d), as.numeric(z), envir = .PG2_ZHIST)
  keys <- ls(.PG2_ZHIST)
  dd <- as.Date(keys); v <- as.numeric(unlist(mget(keys, envir = .PG2_ZHIST)))
  past <- v[dd < d & is.finite(v)]
  if (length(past) < .PG2_ZLT_MIN_OBS) return(list(zlt = FALSE, q20 = NA_real_, n_past = length(past)))
  q20 <- as.numeric(stats::quantile(past, .PG2_ZLT_Q, na.rm = TRUE, names = FALSE))   # L5:288
  list(zlt = isTRUE(is.finite(z) && z < q20), q20 = q20, n_past = length(past))       # GEN:147
}

# ── 패널 적재 (파일 최상위 1회 — arm 은 셀당 약 260회 불린다) ─────────────────
.PG2_M4 <- .pg2_load_m4()
.PG2_AE <- .pg2_load_ae()
.PG2_RG <- .pg2_regime_table()
cat(sprintf(paste0("[pg2_risk_overlay] 패널 적재 — m4 %s · AE %s · 국면 %s · AE 탈락(1일 아님 %d · PIT %d) · 국면 점수 결측 %d\n"),
            if (is.null(.PG2_M4)) "부재" else sprintf("%d행 %s~%s", nrow(.PG2_M4), min(.PG2_M4$ym), max(.PG2_M4$ym)),
            if (is.null(.PG2_AE)) "부재" else sprintf("%d행 %s~%s", nrow(.PG2_AE), min(.PG2_AE$ym), max(.PG2_AE$ym)),
            if (is.null(.PG2_RG)) "부재" else sprintf("%d행 %s~%s", nrow(.PG2_RG), min(.PG2_RG$ym), max(.PG2_RG$ym)),
            get("n_ae_rows_dropped_not_first", envir = .PG2_DIAG), get("n_ae_rows_dropped_pit", envir = .PG2_DIAG),
            get("n_regime_score_na", envir = .PG2_DIAG)))

# ── arm 본체 ─────────────────────────────────────────────────────────────────
overlay_expo_pg2_risk_overlay <- function(H, t, ctx) {
  d <- tryCatch(as.Date(ctx$date), error = function(e) as.Date(NA))
  if (length(d) != 1L || is.na(d)) return(1)              # 신호일이 없으면 무개입
  .h <- .pg2_holding_start(d); ym_h <- .pg2_ym(.h)
  .pg2_diag_add("n_calls")

  # ① gate — GEN:129-131. m4 행·AE 행 = 홀딩월. 결손 성분은 발화하지 못한다(중립).
  m4_fire <- NA; m4_cut <- as.Date(NA); m4_c11 <- as.Date(NA)
  if (!is.null(.PG2_M4)) { r <- .PG2_M4[ym == ym_h]
    if (nrow(r) == 1L) { m4_fire <- r$w[1] < .PG2_M4_FIRE_LT; m4_cut <- r$cutoff[1]; m4_c11 <- r$c11_cut[1] } }
  if (is.na(m4_fire)) .pg2_diag_add("n_m4_missing")
  ae_fire <- NA; ae_cut <- as.Date(NA); ae_c11 <- as.Date(NA)
  if (!is.null(.PG2_AE)) { r <- .PG2_AE[ym == ym_h]
    if (nrow(r) == 1L) { ae_fire <- r$fire[1] == .PG2_AE_FIRE; ae_cut <- r$cutoff[1]; ae_c11 <- r$c11_cut[1] } }
  if (is.na(ae_fire)) .pg2_diag_add("n_ae_missing")
  # ★C11 HARD — 해외 정보를 담은 두 패널 행의 정보 컷오프 ≤ 신호일 d (d 종가 결정 · 판정서 ② 형태 a).
  #   라벨 가드(아래 ④ · 홀딩월 시작)보다 엄격하다: 홀딩월 1일 전이라도 d 종가 뒤에 가용해진 정보는 쓰지 못한다.
  .c11 <- c(m4_c11, ae_c11); .c11 <- .c11[is.finite(.c11)]
  if (length(.c11)) .pg2_assert_pit(.c11, rep(d, length(.c11)), "pg2_risk_overlay:c11")
  gate <- if (isTRUE(m4_fire) && isTRUE(ae_fire)) .PG2_GATE_DERISK else 1.0

  # ② 국면 — ALPHA:36 (sig == hs 인 행 · 없으면 NORMAL)
  regime <- "NORMAL"; rg_cut <- as.Date(NA); rg_raw <- NA_character_
  hit <- FALSE
  if (!is.null(.PG2_RG)) { r <- .PG2_RG[hs == .h]
    if (nrow(r) == 1L && r$rs[1] %in% names(.PG2_REGIME_MAP)) {
      rg_raw <- r$rs[1]; regime <- unname(.PG2_REGIME_MAP[[rg_raw]]); rg_cut <- r$cutoff[1]; hit <- TRUE } }
  if (!hit) .pg2_diag_add("n_regime_missing")

  # ③ zlt — GEN:143-147 · L5:282-296. z = 이 달 보유의 R05 정렬 Z 평균 · 문턱 = 자기 과거 z 의 확장 20분위
  zi <- .pg2_z_now(d, if (is.null(ctx$hold)) NULL else ctx$hold$Ticker)
  if (!is.finite(zi$z)) .pg2_diag_add("n_z_missing")
  if (is.finite(zi$asof) && zi$asof > d) .pg2_diag_add("n_asof_after_signal")   # 월말이 아닌 신호일(픽스처)에서만 생긴다
  zl <- .pg2_zlt(d, zi$z)
  if (is.na(zl$q20)) .pg2_diag_add("n_zlt_undefined")
  beta <- unname(.PG2_BETA[[regime]][[if (isTRUE(zl$zlt)) "zlt" else "base"]])   # GEN:148

  # ④ PIT HARD — 이 달에 실제로 쓴 컷오프 전부가 홀딩월 시작 전인가 (C5)
  cuts <- c(m4_cut, ae_cut, rg_cut, zi$asof); cuts <- cuts[is.finite(cuts)]
  if (length(cuts)) .pg2_assert_pit(cuts, rep(.h, length(cuts)), "pg2_risk_overlay:call")

  e <- max(0, min(1, gate * beta))                                             # GEN:170 invested = gate × β_R05
  if (gate < 1) .pg2_diag_add("n_gate_derisk")
  tr <- get("trace", envir = .PG2_DIAG)
  tr[[length(tr) + 1L]] <- data.table(date = d, hs = .h, gate = gate, m4_fire = m4_fire, ae_fire = ae_fire,
                                      regime_raw = rg_raw, regime = regime, z = zi$z, n_z = zi$n,
                                      q20 = zl$q20, n_past = zl$n_past, zlt = isTRUE(zl$zlt), beta = beta, e = e)
  assign("trace", tr, envir = .PG2_DIAG)
  e
}
