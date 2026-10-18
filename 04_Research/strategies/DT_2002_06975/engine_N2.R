## >>> DT_ZONE header orig=+0
# =============================================================================
# engine_template.R — DT_2002_06975 분위 표적 엔진 템플릿 (P2R05_distribution_target · 2026-10-18)
#   원본 = 04_Research/strategies/RP_AUTO_2002_06975/engine.R 3판(아래 DT_SOURCE_MD5)의 사본이다. 원본과 다른 곳은
#   '## >>> DT_ZONE <이름> orig=<원본 행>' … '## <<< DT_ZONE <이름>' 표지 구역뿐이다(orig=a-b = 원본 a~b 행 대체 ·
#   orig=+a = 원본 a 행 뒤 삽입). 표지 밖은 원본과 바이트 동일하다 — template_diff_check.R 이 단정한다(precheck 가 부른다).
#   아래 원본 머리말은 출처 기록으로 그대로 둔다(FIDELITY.json 은 원본 엔진의 것 · 이 엔진은 처방 레인이라 FIDELITY 대상 아님).
#   바꾼 것(설계 P2R05 DESIGN_draft.md §3 · §7.1 · §7.2 · §12):
#     · 파이썬 출력층 50→3(τ 0.1 · 0.5 · 0.9 · 공유 몸통 · 머리 3) · 손실 MSE → 합성 pinball(세 τ 등가중 평균) ·
#       예측 뒤 행별 단조 재배열(Chernozhukov, Fernández-Val & Galichon 2010) + 재배열 전 교차율 기록
#     · 파이썬 양성 대조 → 이분산 합성(§3.3) · 캐시 판본 DT_2002_06975/dnn_quantile/rev1(키는 규칙과 무관 — 7 엔진이 한 번 학습한 예측을 공유)
#     · R 규칙 블록(.DT_RULE ∈ Q50 · V1 · V2 · N1 · N2 · S1 · S2) · σ 짝 · 자기 이력 폭 짝(D^H: s_hist · h_hist — 철학 P1 C-20261018-065) ·
#       예측표 _work/qpred/ · 실행 끝 panel.parquet 삭제 · 식별자(.TAG · 작업 디렉터리)
#   그대로인 것: 특징 31 · 표적 · 학습 창 · 갱신 격자 · 일정 · 시드 · 유니버스 · 전처리 · PIT 단언(구역 밖 = 원본과 바이트 동일).
#   이 템플릿은 실행용이 아니다(.DT_RULE = "TEMPLATE" 이면 멈춘다) — make_engines.R 이 engine_{Q50,V1,V2,N1,N2,S1,S2}.R 을 만든다.
# DT_SOURCE_MD5 6b6a8e1a144b4b316c28628b0de7f95d
## <<< DT_ZONE header
# =============================================================================
# engine.R — RP_AUTO_2002_06975  (3판 · 2026-09-13 — 적대적 충실도 감사(misdeclared) 후 재구현)
# Masaya Abe · Kei Nakagawa, "Cross-sectional Stock Price Prediction using Deep Learning
#   for Actual Investment Management"  arXiv:2002.06975 (v1 2020-02-17)
#   https://arxiv.org/abs/2002.06975 — 본문 = r.jina.ai PDF 텍스트 프록시(2020 논문 · arxiv html 렌더 없음)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양·감사 응답의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# ★3판이 2판과 다른 곳 = §0 특성 목록 · §2 헬퍼 2종 · §7 전부 · §9 계산 경로(1판 재사용층 제거 · 처리 순서 회전) · 파이썬 rev3.
#   감사 지적 7건(signal 축)을 논문 §3.1 인쇄 정의로 되돌렸다:
#   ① 논문은 No.19~33 의 식을 인쇄한다(2판 FIDELITY 의 '식 없음' 선언은 사실과 달랐다) → 식 전부 논문 그대로
#   ② 'No. 19-33 are calculated on a monthly basis (at the end of month)' → 월말 산출 + 그 달 안 캐리(§7 me(t))
#   ③ No.25 ROA = Net Operating Profits/Total Assets → 영업이익/자산총계(2판 = 순이익)
#   ④ No.26 ROIC = NOPAT/(Debt + Net Assets) → 현금 차감 제거
#   ⑤ No.27 Accruals = −(Changes in Current Assets and Liabilities − Depreciation)/Total Assets → 부호·항 논문 그대로(2판 = (NI−CFO)/TA ≈ 반대 부호)
#   ⑥⑦ No.32 · No.33 은 둘 다 설비투자(유형자산 취득 지급액) 원항목이 필요 → 둘 다 data_gap(대리 없음) → 입력 31
#   특성·표적·모델·학습창·스케줄·5분위 조립의 나머지 경로는 2판과 동일(같은 감사에서 timing·universe·portfolio·cost·undeclared 축 통과).
#
# 논문 기전(그대로): 매일 종가 시점에 33 팩터(Table 1)를 유니버스 안 오름차순 순위/최대순위 로 0~1 재척도 →
#   DNN(Table 2 DNN5: 300-300-150-150-50 · dropout 50-50-30-30-10% · ReLU · batch norm · Adam · MSE ·
#   mini-batch 500 · 20 epoch · truncated normal 초기화 sd=sqrt(2/M)) 으로 5일 뒤 수익
#   y_{t+5} = p^c_{t+5}/p^o_{t+1} − 1 의 **횡단면 순위 재척도값**을 회귀 → 최신 1,000 일치 학습집합으로
#   5영업일마다 재학습 → 예측 점수 상위 5분위 EW 롱 / 하위 5분위 EW 숏.
#
# 이 구현: 특성 31종(No.1~31 · 엔진 열 xNN = Table 1 No.NN · No.32·33 = data_gap · changed(9)) 을 RAWDATA(가격·거래량·
#   시총) + QuantiWise 컨센서스(영업이익 FY1 · 목표주가) + 회계 패널(DART 연간 + QuantiWise 분기 → 연간) 에서
#   원값으로 계산하고, 그날 K200∪KQ150 적격 집합 안에서 순위 재척도. DNN 학습·예측은 venv torch
#   파이썬 서브프로세스(아래 .PY_SRC · 이 파일이 매 실행 _work/run_*/ 에 써 넣는다)가 맡는다.
#   하네스가 월간 집행이라 시그널은 **각 달력월 마지막 거래일 1행**만 낸다(changed(3)) — 그 날 유효한 모델
#   = 5영업일 격자에서 그 날 이전 마지막 갱신점 u 의 모델(학습집합 = s ∈ [u−1004, u−5] · 표적이 u 까지 실현된 집합).
#
# 산출: FACTORS(Date, Ticker, Score)          — 그날 적격 종목 전부 · Score = DNN 예측(순위 척도)
#       PORTFOLIO(Date, Ticker, Weight, Leg)  — 상위 5분위 롱 EW Σ=+1 / 하위 5분위 숏 EW Σ=−1
#
# PIT(C1~C15) 구조 보장: 시그널일 t 의 특성 = t 이하 데이터(수익·거래대금 = t 까지의 종가·거래량, 컨센서스 =
#   t 이하 관측, 회계 = 월말 me(t) ≤ t 에서 usable(FY+1 3/31) ≤ me(t) 인 최신 FY · 시총 = me(t) 종가 기준). 학습 표적 y_s 는
#   s+5 종가로 실현되며 파이썬이 lab_i ≤ u_i 를 단언하고 R 이 diag 로 재단언한다. 전 표본 통계 0건(순위 = 그날 횡단면 ·
#   창 = 롤링) · 팩터 DB 미사용. 유동성 스크린 없음(논문 우선 · changed(2)). 예측 캐시는 입력이 바이트 동일할 때만 — PIT 무관.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
## >>> DT_ZONE ident orig=48-48
# 규칙 상수 — 생성기(make_engines.R)가 바로 아래 한 줄만 바꾼다(엔진 7개는 이 한 줄만 다르다 · 셀 기저 캐시 키 = 엔진 파일 md5).
.DT_RULE <- "N2"
.DT_RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
if (!(length(.DT_RULE) == 1L && .DT_RULE %in% .DT_RULES))
  stop(sprintf("[DT_2002_06975] 규칙 상수 .DT_RULE = '%s' — 템플릿은 실행하지 않는다(make_engines.R 이 만든 engine_<규칙>.R 만 실행)",
               paste(.DT_RULE, collapse = ",")))
.TAG <- sprintf("[DT_2002_06975:%s]", .DT_RULE)
## <<< DT_ZONE ident
.t0 <- Sys.time()
.REQ <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.HAS_OPEN <- "Open" %in% names(RAWDATA)

# =============================================================================
# 0. 상수 — 논문 명시값 + 논문이 침묵하는 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.RET_K    <- c(1L, 2L, 3L, 5L, 10L, 20L, 40L, 60L)   # Table 1 No.1~8: k일 전 대비 수익 (changed(7) 해석)
.TV_LONG  <- 60L                                     # Table 1 No.9: 60일 평균 거래대금
.TV_SHORT <- c(5L, 10L, 20L)                         # Table 1 No.10~12: 5/10/20일 평균 ÷ 60일 평균
.CONS_K   <- c(5L, 10L, 20L)                         # Table 1 No.13~18: 5/10/20일 전 대비 전망 변화
.HORIZON  <- 5L                                      # 표적 = p^c_{t+5}/p^o_{t+1} − 1
.N_TRAIN  <- 1000L                                   # "latest N = 1,000 days" 학습집합
.UPD_EVERY <- 5L                                     # "updated every five business days"
.QUINT    <- 5L                                      # top / bottom quintile
.START    <- (if (exists(".RP_START_DATE")) .RP_START_DATE else as.Date("2005-01-01"))                   # 고정 축 — 이 날 이후 시그널만 발행
.ANCHOR   <- as.Date("2001-01-01")                   # ★changed(3) 5영업일 갱신 격자 앵커(첫 거래일 ≥ 이 날)
.GRID_FROM <- as.Date("2000-06-01")                  # ★changed(12) 격자 시작(학습창 1,000일 + 특성 창 60일 선행)
.CONS_ROLL <- 7L                                     # ★changed(7) 컨센서스 관측 → 거래일 격자 캐리 상한(달력일)
.FUND_ROLL <- 456L                                   # ★changed(8) 연간 회계 usable 이후 캐리 상한(달력일 ≈ 15개월)
.MIN_N    <- 10L                                     # ★changed(11) 5분위 정의역(다리당 ≥ 2)
.SEED_BASE <- 20020697L                              # ★changed(6) 시드 = 논문 번호(임의 상수) + 월 인덱스
.N_WORKERS_CAP <- 32L                                # ★changed(15) 워커 상한(실제 = min(상한, 논리 CPU − 1) · cuda 면 ≤ 8)
.FEATS <- sprintf("x%02d", 1:31)                     # ★changed(9) 엔진 열 xNN = Table 1 No.NN (No.32·33 = data_gap)
.FEAT_NAMES <- c("ret_1d", "ret_2d", "ret_3d", "ret_5d", "ret_10d", "ret_20d", "ret_40d", "ret_60d",
                 "tv_60d", "tv_5d/60d", "tv_10d/60d", "tv_20d/60d",
                 "op_fcst_chg_5d", "op_fcst_chg_10d", "op_fcst_chg_20d",
                 "tp_chg_5d", "tp_chg_10d", "tp_chg_20d",
                 "B/P", "E/P", "DY", "S/P", "CF/P", "ROE", "ROA(op)", "ROIC", "accruals(paper sign)", "asset_turnover",
                 "current_ratio", "equity_ratio", "asset_growth")
stopifnot(length(.FEATS) == length(.FEAT_NAMES))
.FUND_FEATS <- .FEATS[19:31]                         # 논문: 'No. 19-33 are calculated on a monthly basis (at the end of month)'

## >>> DT_ZONE dt_const orig=+83
# ── DT 상수(설계 §3.3 · §3.4 · §4 · §12 — 결과 전 고정) ──
.DT_TAUS       <- c(0.1, 0.5, 0.9)   # 분위 머리 3(P10/P50/P90 다분위 관례 — Wen 외 2017 arXiv:1711.11053 · 머리 수 격자 금지) · 파이썬 TAUS 와 같다
.DT_VETO_SHARE <- 0.2                # V1 · N1 · S1 거부 몫 = 논문 5분위 정렬 단위(Abe & Nakagawa 2020 · 위 .QUINT = 5 → 1/5)
.DT_PERM_SEED  <- 20261018L          # N1 · N2 순열 주 시드(P2R04 N0 와 같은 주 시드)
.DT_SIGMA_WIN  <- 252L               # S1 · S2 σ 창 = 직전 252거래일 일 로그수익(P2R04 H2 D03_RealVol 252일과 같은 창)
.DT_SIGMA_MIN  <- 126L               # σ 유효 관측 하한(설계 §4)
.DT_HIST_WIN   <- 252L               # 자기 이력 폭 짝 D^H(철학 P1 C-20261018-065): 직전 252거래일 자기 학습 표적 y 중 실현분(lab_i ≤ u)
.DT_HIST_MIN   <- 126L               # h 유효 관측 하한(σ 와 같은 규약)
.DT_HIST_TAU   <- 0.1                # h = 중앙값 − 10% 분위(= q10 머리의 τ)
# 파이썬 양성 대조의 R 재단언 문턱(설계 §3.3 — 파이썬 PC_* 와 같은 값 · 파이썬을 신뢰하지 않는다):
#   Spearman > 0.8(rev3 문턱 승계) · 홀드아웃 적중 P(y ≤ q10) ∈ [0.05, 0.15] · P(y ≤ q90) ∈ [0.85, 0.95]
.DT_PC_RHO_MIN <- 0.8
.DT_PC_COV10   <- c(0.05, 0.15)
.DT_PC_COV90   <- c(0.85, 0.95)
if (!identical(.DT_VETO_SHARE, 1 / .QUINT)) stop(sprintf("%s 거부 몫 %s ≠ 1/.QUINT", .TAG, format(.DT_VETO_SHARE)))
if (!identical(.DT_HIST_TAU, .DT_TAUS[1])) stop(sprintf("%s 자기 이력 폭 τ %s ≠ q10 머리 τ", .TAG, format(.DT_HIST_TAU)))

## <<< DT_ZONE dt_const
# =============================================================================
# 1. 루트·캐시·파이썬 해석 · 실행별 작업 디렉터리 (r-portability: 표지 파일 검증 · env= 미사용 · 셸 연산자 미사용)
# =============================================================================
.find_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (exists("PROJECT_ROOT", inherits = TRUE)) as.character(get("PROJECT_ROOT", inherits = TRUE))[1] else "",
             getwd())
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  for (p in cands) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, marker))) return(p)
  }
  stop(sprintf("%s 프로젝트 루트를 찾지 못함(표지 %s) — CLAUDE_PROJECT_DIR/QM_ROOT 확인", .TAG, marker))
}
.ROOT  <- .find_root()
.CACHE <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1] else file.path(.ROOT, ".cache")
## >>> DT_ZONE workdir orig=101-101
.WD    <- file.path(.ROOT, "04_Research", "strategies", "DT_2002_06975", "_work")
.QD    <- file.path(.WD, "qpred")                    # 예측표(분위 · 순열 짝 · σ 짝 · 자기 이력 폭 짝 — 실행마다 원자적 쓰기 · 실현 라벨 없음)
dir.create(.QD, recursive = TRUE, showWarnings = FALSE)
## <<< DT_ZONE workdir
.RUN_ID <- sprintf("run_%s_%d", format(Sys.time(), "%Y%m%d_%H%M%S"), Sys.getpid())
.RD    <- file.path(.WD, .RUN_ID)                    # 이 실행의 작업본(패널·스케줄·스크립트·예측)
.CD    <- file.path(.WD, "cache")                    # 실행 간 공유 예측 캐시(월 단위 · 입력 내용 주소)
dir.create(.RD, recursive = TRUE, showWarnings = FALSE)
dir.create(.CD, recursive = TRUE, showWarnings = FALSE)
# 48시간 지난 run_* 작업본 정리 — 이 엔진의 산출 디렉터리 안에서만 · 캐시는 건드리지 않는다
.old_runs <- list.dirs(.WD, recursive = FALSE, full.names = TRUE)
.old_runs <- .old_runs[grepl("/run_[0-9]{8}_[0-9]{6}_[0-9]+$", .old_runs)]
.n_clean <- 0L
for (.d in .old_runs) {
  if (identical(basename(.d), .RUN_ID)) next
  if (as.numeric(difftime(Sys.time(), file.mtime(.d), units = "hours")) > 48) { unlink(.d, recursive = TRUE); .n_clean <- .n_clean + 1L }
}
.PY <- file.path(.ROOT, ".venv_qvest_ml", "Scripts", "python.exe")
if (!file.exists(.PY)) .PY <- Sys.getenv("QVEST_PY", "")
if (!nzchar(.PY) || !file.exists(.PY))
  stop(sprintf("%s 파이썬 실행기 부재(.venv_qvest_ml/Scripts/python.exe · QVEST_PY) — DNN 학습 불가", .TAG))
.probe <- suppressWarnings(system2(.PY, c("-c", shQuote("import torch, pyarrow, pandas, numpy; print(torch.__version__, 'cuda' if torch.cuda.is_available() else 'cpu')")),
                                   stdout = TRUE, stderr = TRUE))
.probe_st <- attr(.probe, "status"); .probe_st <- if (is.null(.probe_st)) 0L else as.integer(.probe_st)
if (.probe_st != 0L)
  stop(sprintf("%s venv 파이썬에서 torch/pyarrow/pandas/numpy import 실패(rc %d): %s", .TAG, .probe_st,
               paste(.probe, collapse = " | ")))
cat(sprintf("%s root %s · cache %s · python %s (torch %s) · 작업본 %s · 정리한 옛 작업본 %d\n",
            .TAG, .ROOT, .CACHE, .PY, paste(.probe, collapse = " "), .RUN_ID, .n_clean))

# =============================================================================
# 2. 헬퍼 + 양성 대조 (구현 결함 = 중단 · 조용한 F 방지)
# =============================================================================
# 논문 전처리: "ranking each input value in ascending order by stock universe at each day and then dividing by
#   the maximum rank value" — 동률 = 평균 순위 · 결측 = 0.5(중앙값 대치 · 논문 미명시 · changed(10))
.rank01 <- function(x) {
  ok <- is.finite(x); out <- rep(0.5, length(x)); n <- sum(ok)
  if (n >= 1L) { r <- frank(x[ok], ties.method = "average"); out[ok] <- r / max(r) }
  out
}
.sdiv <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)      # 양(+) 분모만 (changed(8))
.chg  <- function(v, k) {                                                                  # (F_t − F_{t−k}) / |F_{t−k}| (changed(7))
  l <- shift(v, k)
  fifelse(is.finite(v) & is.finite(l) & abs(l) > 0, (v - l) / abs(l), NA_real_)
}
.nz <- function(x) fifelse(is.finite(x), x, 0)                                             # 차입금 결측 = 0 (changed(8))
# No.26 분자 'Net Operating Profits After Tax' — 논문은 세율 규약을 주지 않는다(NOT STATED · changed(8)):
#   NOPAT = 영업이익 × (1 − τ) · τ = 법인세비용/세전이익 (세전이익 > 0 · [0,1] 절단) · 세전이익 ≤ 0 이면 τ = 0(손실 = 무세)
.nopat <- function(op, tax, pretax) {
  tau <- fifelse(is.finite(pretax) & pretax > 0 & is.finite(tax), pmin(pmax(tax / pretax, 0), 1), NA_real_)
  tau <- fifelse(is.finite(pretax) & pretax <= 0, 0, tau)
  fifelse(is.finite(op) & is.finite(tau), op * (1 - tau), NA_real_)
}
# No.27 논문 그대로: −(Changes in Current Assets and Liabilities − Depreciation)/Total Assets
#   'Changes in Current Assets and Liabilities' = Δ유동자산 − Δ유동부채(운전자본 변화 · 직전 FY 대비 · changed(8))
.accr <- function(ca, ca_p, cl, cl_p, dep, ta) {
  ok <- is.finite(ca) & is.finite(ca_p) & is.finite(cl) & is.finite(cl_p) & is.finite(dep) & is.finite(ta) & ta > 0
  fifelse(ok, -(((ca - ca_p) - (cl - cl_p)) - dep) / ta, NA_real_)
}

local({
  r <- .rank01(c(3, NA, 1, 2, 2))
  if (!isTRUE(all.equal(r, c(1, 0.5, 0.25, 0.625, 0.625)))) stop(sprintf("%s 순위 재척도 검산 실패", .TAG))
  if (!isTRUE(all.equal(.rank01(c(NA_real_, NA_real_)), c(0.5, 0.5)))) stop(sprintf("%s 전 결측 순위 검산 실패", .TAG))
  # 합성 12일 종목: 종가 = 100·1.01^i, 시가 = 종가·0.99 — k일 수익·표적 정렬을 폐형과 대조
  d <- data.table(Ticker = "T", Date = as.Date("2020-01-01") + 0:11, di = 1:12)
  d[, Close := 100 * 1.01^(0:11)]; d[, Open := Close * 0.99]
  d[, r5 := Close / shift(Close, 5L) - 1, by = Ticker]
  if (!isTRUE(all.equal(d$r5[6], 1.01^5 - 1))) stop(sprintf("%s k일 수익 검산 실패", .TAG))
  d[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]
  lab <- d[, .(s_date = shift(Date, .HORIZON), lab_i = di, y_raw = lab_end), by = Ticker][!is.na(s_date) & is.finite(y_raw)]
  d[lab, on = .(Ticker, Date = s_date), c("y_raw", "lab_i") := .(i.y_raw, i.lab_i)]
  # 집합 s = 1행(Date 01-01): 표적 = Close[6]/Open[2] − 1, 실현 인덱스 6
  want <- d$Close[6] / d$Open[2] - 1
  if (!isTRUE(all.equal(d$y_raw[1], want)) || !identical(d$lab_i[1], 6L)) stop(sprintf("%s 표적 정렬 검산 실패", .TAG))
  if (!all(is.na(d$y_raw[8:12]))) stop(sprintf("%s 표적 말단 결측 검산 실패", .TAG))
  ch <- .chg(c(10, 11, 12, -6, 0, 3), 2L)
  if (!isTRUE(all.equal(ch, c(NA, NA, 0.2, (-6 - 11) / 11, -1, (3 + 6) / 6)))) stop(sprintf("%s 전망 변화율 검산 실패", .TAG))
  # No.27: 유동자산 100→120 · 유동부채 50→60 · 감가상각 5 · 자산총계 200 → −((20 − 10) − 5)/200 = −0.025
  ac <- .accr(c(120, 120, 120), c(100, NA, 100), c(60, 60, 60), c(50, 50, 50), c(5, 5, NA), c(200, 200, 200))
  if (!isTRUE(all.equal(ac, c(-0.025, NA, NA)))) stop(sprintf("%s accruals 검산 실패", .TAG))
  # No.26 NOPAT: 영업이익 100 · 세 20 · 세전 80 → 75 · 세전 −10 → 100(τ = 0) · 세 100 세전 80 → 0(τ 절단 1) · 세전 0 → 100(τ = 0) · 세 결측 세전 80 → NA
  np <- .nopat(c(100, 100, 100, 100, 100), c(20, 5, 100, 10, NA), c(80, -10, 80, 0, 80))
  if (!isTRUE(all.equal(np, c(75, 100, 0, 100, NA)))) stop(sprintf("%s NOPAT 검산 실패", .TAG))
  cat(sprintf("%s 양성 대조 통과 — 순위 재척도 · k일 수익 · 표적 정렬(s→s+5 · 시가 s+1) · 전망 변화율 · accruals(논문 부호) · NOPAT\n", .TAG))
})

## >>> DT_ZONE rule_fns orig=+184
# ── DT 규칙 함수(설계 §3.4 · §4) — 신호일 하나의 적격 집합 U_d 안에서만 계산한다(C1: 그날 횡단면 · 전 표본 통계 0 · 미래 정보 0) ──
# 하위 몫 거부: 오름차순 순위(동률 평균)/N ≤ share 이면 TRUE(거부). N = 유한 값 개수 · 비유한 값 = NA(순위에 들지 않는다).
.dt_veto <- function(q, share) {
  ok <- is.finite(q); out <- rep(NA, length(q)); n <- sum(ok)
  if (n >= 1L) out[ok] <- (frank(q[ok], ties.method = "average") / n) <= share
  out
}
.dt_veto_by <- function(d, q, share) {                 # 날짜별(그날 집합 안) 거부 — 입력 행 순서 그대로 반환
  x <- data.table(d = d, q = q)
  x[, v := .dt_veto(q, share), by = d]
  x$v
}
# 무정보 꼬리 순열(N1 · N2): 신호일마다 그날 s 를 종목코드 순(C 로케일)에서 무작위 순열한다 — rf_cell_engine.R null_perm 규약 승계:
#   달 순번 mi = (연 − 시작 연)·12 + (월 − 시작 월) · 달 하위 시드 = 주 시드 runif 흐름 floor(runif(max(mi) + 1)·2147483646) + 1 의 (mi + 1)번째
#   (접두 안정 — 뒤에 달이 붙어도 앞 달의 순열은 그대로다). 끝나면 전역 난수 상태(.Random.seed · RNGkind)를 되돌린다.
.dt_perm_s <- function(d, tk, s, start, seed) {
  n <- length(s)
  if (length(d) != n || length(tk) != n) stop(sprintf("%s 순열 — 입력 길이 불일치", .TAG))
  out <- rep(NA_real_, n)
  if (!n) return(out)
  ud <- sort(unique(d))
  mi <- (as.integer(format(ud, "%Y")) - as.integer(format(start, "%Y"))) * 12L +
        (as.integer(format(ud, "%m")) - as.integer(format(start, "%m")))
  if (any(mi < 0L) || anyDuplicated(mi))
    stop(sprintf("%s 순열 — 신호일이 시작 달 앞이거나 한 달에 둘이다(달 하위 시드 정의 불가)", .TAG))
  rs_old <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  rk_old <- RNGkind()
  on.exit({ if (is.null(rs_old)) { RNGkind(rk_old[1], rk_old[2], rk_old[3])
              if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv()) }
            else assign(".Random.seed", rs_old, envir = globalenv()) }, add = TRUE)
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  ms <- as.integer(floor(stats::runif(max(mi) + 1L) * 2147483646)) + 1L
  for (j in seq_along(ud)) {
    ix <- which(d == ud[j])
    ix <- ix[order(tk[ix], method = "radix")]
    set.seed(ms[mi[j] + 1L], kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
    out[ix] <- s[ix][sample.int(length(ix))]
  }
  out
}
# 순위 대응 재배정(S1 · S2 의 σ 짝 · 자기 이력 폭 짝 D^H 공용): 그날 열쇠(key = σ 또는 h)가 유효한 종목의 s 다중집합을 열쇠 오름차순 ↔
#   s 오름차순으로 다시 배정한다(열쇠 큰 종목에 큰 s · 동률 열쇠 = 종목코드 순 · 주변분포 같음 · 순서만 열쇠). 열쇠 결측 종목 = 그날 s 전체(U_d)의 중앙값.
.dt_match_s <- function(d, tk, s, key) {
  n <- length(s)
  if (length(d) != n || length(tk) != n || length(key) != n) stop(sprintf("%s 순위 대응 — 입력 길이 불일치", .TAG))
  out <- rep(NA_real_, n)
  for (ix in split(seq_len(n), as.integer(d))) {
    ok <- ix[is.finite(key[ix])]
    out[setdiff(ix, ok)] <- stats::median(s[ix])
    if (length(ok)) out[ok[order(key[ok], tk[ok], method = "radix")]] <- sort(s[ok], method = "radix")
  }
  out
}
# 자기 이력 하방 폭 h(D^H 짝 · 철학 P1 C-20261018-065): 한 종목의 표본 행(di 오름차순 · 학습 표적 y · 실현 인덱스 lab)에서 신호일 p(그 신호일
#   학습 격자 u) 마다 di ∈ [p − win, p − 1](창 끝 t−1) ∧ lab ≤ u(실현분만 — 파이썬 · R PIT 단언 max_lab_i ≤ u_i 와 같은 경계) ∧ y 유한 인 y 의
#   중앙값 − tau 분위(type 7). 유효 관측 < min_obs = NA. di 는 정렬돼 있어야 한다(이진 탐색).
.dt_hist_at <- function(di, y, lab, pts, us, win, min_obs, tau) {
  if (is.unsorted(di, strictly = TRUE)) stop(sprintf("%s 자기 이력 폭 — 종목 행의 di 가 순증가가 아니다", .TAG))
  vapply(seq_along(pts), function(j) {
    lo <- findInterval(pts[j] - win - 1L, di) + 1L; hi <- findInterval(pts[j] - 1L, di)
    if (hi < lo) return(NA_real_)
    k <- lo:hi
    k <- k[!is.na(lab[k]) & lab[k] <= us[j] & is.finite(y[k])]
    if (length(k) < min_obs) return(NA_real_)
    stats::median(y[k]) - stats::quantile(y[k], tau, type = 7L, names = FALSE)
  }, numeric(1))
}
# σ(직전 win 거래일 일 로그수익 표준편차 · 창 끝 t−1 · 유효 관측 ≥ min_obs · 수정 종가): 한 종목의 격자 종가 벡터 cl(격자 행 = 연속 거래일 ·
#   관측 없는 날 = NA)에서 신호일 행 번호 p 마다 sd({log(cl_j / cl_{j−1}) : j ∈ [p − win, p − 1]}). 전날 또는 당일 종가가 없는 날의 수익 = NA
#   (유효 관측에서 빠진다). 모멘트 항등식 없이 sd() 직접(셀 엔진 lowvol60 과 같은 이유 — 퇴화 종목의 허수 σ 방지).
.dt_sigma_at <- function(cl, pts, win, min_obs) {
  lr <- log(cl / shift(cl, 1L))
  lr[!is.finite(lr)] <- NA_real_
  vapply(pts, function(p) {
    a <- max(1L, p - win); b <- p - 1L
    if (b < a) return(NA_real_)
    v <- lr[a:b]; v <- v[!is.na(v)]
    if (length(v) >= min_obs) stats::sd(v) else NA_real_
  }, numeric(1))
}
# 점수(FACTORS Score) — 규칙별(설계 §3.4 · §4). q10 ≤ q50 ≤ q90 = 재배열 뒤 · s = q50 − q10 · s_perm · s_sigma = 위 두 함수의 산출.
.dt_score <- function(rule, d, q10, q50, s_perm, s_sigma, share) {
  switch(rule,
    Q50 = q50,                                                              # 중앙값만(진단)
    V1  = fifelse(.dt_veto_by(d, q10, share), NA_real_, q50),               # q10 하위 몫 거부 → 나머지 q50
    V2  = q10,                                                              # q10 순위
    N1  = fifelse(.dt_veto_by(d, q50 - s_perm, share), NA_real_, q50),      # 무정보 꼬리 순열 짝(V1)
    N2  = q50 - s_perm,                                                     # 무정보 꼬리 순열 짝(V2)
    S1  = fifelse(.dt_veto_by(d, q50 - s_sigma, share), NA_real_, q50),     # σ 순위 대응 짝(V1)
    S2  = q50 - s_sigma,                                                    # σ 순위 대응 짝(V2)
    stop(sprintf("%s 규칙 미지원: %s", .TAG, rule)))
}
.dt_md5_str <- function(x) {                             # 문자열 md5(R ≥ 4.5 bytes= · 그 전 = 임시 파일) — 예측표 이름용
  r <- charToRaw(enc2utf8(paste(as.character(x), collapse = "\n")))
  h <- tryCatch(unname(tools::md5sum(bytes = r)), error = function(e) NULL)
  if (is.null(h) || !length(h) || is.na(h)) {
    tf <- tempfile("dt_md5_"); on.exit(unlink(tf), add = TRUE)
    writeBin(r, tf); h <- unname(tools::md5sum(tf))
  }
  as.character(h)
}
local({
  # 거부: 서로 다른 10값 → 순위/N 0.1 · 0.2 인 둘 거부 · 동률 4값(순위 2~5 → 평균 3.5 → 0.35)은 넷 다 통과 · 비유한 값은 N 에서 빠진다
  if (!identical(.dt_veto(c(5, 1, 2, 9, 3, 4, 6, 7, 8, 10), 0.2), c(FALSE, TRUE, TRUE, rep(FALSE, 7))) ||
      !identical(.dt_veto(c(1, 2, 2, 2, 2, 6, 7, 8, 9, 10), 0.2), c(TRUE, rep(FALSE, 9))) ||
      !identical(.dt_veto(c(NA, 1, 2, 3, 4, 5), 0.2), c(NA, TRUE, FALSE, FALSE, FALSE, FALSE)))
    stop(sprintf("%s 거부 규칙 검산 실패", .TAG))
  # 순열: 같은 시드 = 같은 결과 · 날짜별 다중집합 보존 · 전역 난수 상태 복원
  d <- as.Date(c("2005-01-31", "2005-01-31", "2005-01-31", "2005-02-28", "2005-02-28"))
  rs0 <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  p1 <- .dt_perm_s(d, c("B", "A", "C", "A", "B"), c(1, 2, 3, 4, 5), as.Date("2005-01-01"), 7L)
  p2 <- .dt_perm_s(d, c("B", "A", "C", "A", "B"), c(1, 2, 3, 4, 5), as.Date("2005-01-01"), 7L)
  rs1 <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  if (!identical(p1, p2) || !identical(rs0, rs1) || !identical(sort(p1[1:3]), c(1, 2, 3)) || !identical(sort(p1[4:5]), c(4, 5)))
    stop(sprintf("%s 순열 검산 실패", .TAG))
  # 순위 대응: 열쇠 유효 A(3) · B(1) · D(2) 의 s {0.1, 0.4, 0.2} → B 0.1 · D 0.2 · A 0.4 · 열쇠 결측 C = 중앙값(0.1, 0.4, 0.3, 0.2) = 0.25
  sg <- .dt_match_s(rep(as.Date("2005-01-31"), 4), c("A", "B", "C", "D"), c(0.1, 0.4, 0.3, 0.2), c(3, 1, NA, 2))
  if (!isTRUE(all.equal(sg, c(0.4, 0.1, 0.25, 0.2)))) stop(sprintf("%s 순위 대응 검산 실패", .TAG))
  # σ: 창 [p − 4, p − 1] · 종가 결측일과 그다음 날 수익 = NA · 유효 관측 하한
  cl <- c(100, 101, 100, 102, NA, 103, 104)
  sa <- .dt_sigma_at(cl, c(3L, 7L), 4L, 2L)
  if (!is.na(sa[1]) || !isTRUE(all.equal(sa[2], stats::sd(c(log(100 / 101), log(102 / 100))))))
    stop(sprintf("%s σ 창 검산 실패", .TAG))
  # 자기 이력 폭: di 1~12 · lab = di + 5 · p = 12 · u = 11 · 창 [12 − 10, 11] = di 2~11 중 lab ≤ 11 → di 2~6(y = 0.2 · 0.4 · 0.6 · 0.8 · 1.0)
  #   → 중앙값 0.6 − 10% 분위(type 7: 0.2 + 0.4·0.2 = 0.28) = 0.32 · 유효 관측 하한 6 이면 NA(실현분 5개 — u 뒤 라벨은 세지 않는다)
  hy <- c(0.9, 0.2, 0.4, 0.6, 0.8, 1.0, 0.01, 0.01, 0.01, 0.01, 0.01, 0.5)
  ha <- .dt_hist_at(1:12, hy, 1:12 + 5L, 12L, 11L, 10L, 5L, 0.1); hb <- .dt_hist_at(1:12, hy, 1:12 + 5L, 12L, 11L, 10L, 6L, 0.1)
  if (!isTRUE(all.equal(ha, 0.32)) || !is.na(hb)) stop(sprintf("%s 자기 이력 폭 검산 실패", .TAG))
  cat(sprintf("%s 규칙 함수 검산 통과 — 하위 몫 거부(동률 평균 · 비유한 제외) · 순열(재현 · 난수 상태 복원) · 순위 대응(결측 = 중앙값) · σ 창(t−1 끝) · 자기 이력 폭(실현분 lab ≤ u)\n", .TAG))
})

## <<< DT_ZONE rule_fns
# =============================================================================
# 3. 거래일 격자 × 적격 이력 종목 (RAWDATA 비파괴)  ★changed(1)(12)
#    열 정체: Close·Open = 수정주가 · Vol = 주식수 거래량 · Size = 시가총액(KRW) · K200/KQ150 = 그날 멤버십 플래그
# =============================================================================
.cal <- sort(unique(RAWDATA$Date)); .cal <- .cal[.cal >= .GRID_FROM]
.CAL <- data.table(Date = .cal, di = seq_along(.cal))
.cols <- c(.REQ, if (.HAS_OPEN) "Open")
.rd <- RAWDATA[Date >= .GRID_FROM & is.finite(Close) & Close > 0, .cols, with = FALSE]
.rd[, Ticker := as.character(Ticker)]
.rd[, MEM := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]
.rd[, c("K200", "KQ150") := NULL]
if (!.HAS_OPEN) .rd[, Open := NA_real_]
.rd[, Open := as.numeric(Open)]; .rd[!is.finite(Open) | Open <= 0, Open := NA_real_]          # 0·결측 시가 = 센티널 → NA (changed(10))
.rd[, Vol := as.numeric(Vol)]; .rd[, Size := as.numeric(Size)]
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) { cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup)); .rd <- unique(.rd, by = c("Ticker", "Date")) }
.mem_tk <- sort(unique(.rd$Ticker[.rd$MEM]))
if (length(.mem_tk) < 50L) stop(sprintf("%s 적격 이력 종목 %d — 멤버십 플래그 확인", .TAG, length(.mem_tk)))
.rd <- .rd[Ticker %in% .mem_tk]
.G <- CJ(Ticker = .mem_tk, Date = .cal)
.G <- .rd[.G, on = .(Ticker, Date)]
.G[is.na(MEM), MEM := FALSE]
.G[.CAL, on = "Date", di := i.di]
setorder(.G, Ticker, Date)
.n_raw <- nrow(.rd); rm(.rd)
cat(sprintf("%s 격자 %d거래일(%s ~ %s) × 적격 이력 종목 %d = %d행 (관측 %d행) · Open 열 %s · 마지막 날 적격 %d종\n",
            .TAG, nrow(.CAL), as.character(min(.cal)), as.character(max(.cal)), length(.mem_tk), nrow(.G), .n_raw,
            if (.HAS_OPEN) "있음" else "없음(표적 진입가 = 종가 대체 · changed(10))",
            .G[Date == max(.cal), sum(MEM)]))

# =============================================================================
# 4. 가격·거래량 특성 (Table 1 No.1~12) + 표적 — 종목별 행 이동 = 거래일 이동(격자가 달력 완비)
# =============================================================================
.G[, (.FEATS[1:8]) := lapply(.RET_K, function(k) Close / shift(Close, k) - 1), by = Ticker]
.G[, dv := fifelse(is.finite(Vol) & Vol > 0, Vol * Close, NA_real_)]                           # 거래대금 KRW ≈ 거래량 × 수정종가 (changed(7))
.G[, tv60 := frollmean(dv, .TV_LONG, na.rm = TRUE, hasNA = TRUE), by = Ticker]
.G[, c("tv5", "tv10", "tv20") := lapply(.TV_SHORT, function(k) frollmean(dv, k, na.rm = TRUE, hasNA = TRUE)), by = Ticker]
.G[, x09 := fifelse(is.finite(tv60) & tv60 > 0, tv60, NA_real_)]
.G[, x10 := .sdiv(tv5, tv60)]; .G[, x11 := .sdiv(tv10, tv60)]; .G[, x12 := .sdiv(tv20, tv60)]
.G[, c("dv", "tv60", "tv5", "tv10", "tv20") := NULL]
# 표적: 행 r 에서 Close[r]/Open[r−4] − 1 = 집합 s = r−5 의 5일 수익(진입 = s+1 시가 · 청산 = s+5 종가 · 실현일 = r).
#   집합 s 에 붙이되 실현 인덱스 lab_i 를 함께 실어 학습 시점 u 에서 lab_i ≤ u 를 단언한다(파이썬 + R 이중).
.G[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]
if (!.HAS_OPEN) .G[, lab_end := Close / shift(Close, .HORIZON) - 1, by = Ticker]              # changed(10) 시가 열 부재 시만
.LAB <- .G[, .(s_date = shift(Date, .HORIZON), lab_i = di, y_raw = lab_end), by = Ticker]
.LAB <- .LAB[!is.na(s_date) & is.finite(y_raw)]
.G[.LAB, on = .(Ticker, Date = s_date), c("y_raw", "lab_i") := .(i.y_raw, i.lab_i)]
rm(.LAB); .G[, lab_end := NULL]
.n_ext_d <- .G[MEM == TRUE & is.finite(x01), sum(abs(x01) > 0.5)]
.n_ext_y <- .G[MEM == TRUE & is.finite(y_raw), sum(abs(y_raw) > 1)]
cat(sprintf("%s 가격 특성 8 + 거래대금 특성 4 + 표적 완료 · 적격행 |1일 수익|>50%% %d건 · |5일 표적|>100%% %d건 (원천 이음매 결함이 남아 있으면 여기 드러난다 — 값 절단 없음)\n",
            .TAG, .n_ext_d, .n_ext_y))

# =============================================================================
# 5. 컨센서스 특성 (Table 1 No.13~18) — QuantiWise 영업이익 FY1 · 목표주가 (논문 I/B/E/S 의 KR 대응 · changed(7))
# =============================================================================
.read_cons <- function(metric) {
  p <- file.path(.CACHE, "consensus", paste0(metric, ".parquet"))
  if (!file.exists(p)) stop(sprintf("%s 컨센서스 패널 부재: %s — Table 1 No.13~18 원천. data_gap 적재 대상", .TAG, p))
  d <- as.data.table(read_parquet(p))
  if (!all(c("Date", "Ticker", metric) %in% names(d))) stop(sprintf("%s 컨센서스 %s 스키마 불일치: %s", .TAG, metric, paste(names(d), collapse = ",")))
  d <- d[, c("Date", "Ticker", metric), with = FALSE]
  setnames(d, metric, "v")
  if (!inherits(d$Date, "Date")) d[, Date := as.Date(Date)]
  d[, Ticker := as.character(Ticker)]
  d <- d[is.finite(v) & Ticker %in% .mem_tk]
  d <- unique(d, by = c("Ticker", "Date"))
  setorder(d, Ticker, Date)
  d
}
.op <- .read_cons("op_profit_fy1")
.tp <- .read_cons("target_price")
if (nrow(.op) == 0L || nrow(.tp) == 0L)
  stop(sprintf("%s 컨센서스 패널이 적격 종목과 0행 교차(op %d · tp %d) — Ticker 형식(A######) 확인", .TAG, nrow(.op), nrow(.tp)))
.G[, op := .op[.G[, .(Ticker, Date)], on = .(Ticker, Date), roll = .CONS_ROLL, x.v]]           # 관측 ≤ t · 캐리 ≤ 7달력일
.G[, tp := .tp[.G[, .(Ticker, Date)], on = .(Ticker, Date), roll = .CONS_ROLL, x.v]]
.G[, (.FEATS[13:15]) := lapply(.CONS_K, function(k) .chg(op, k)), by = Ticker]
.G[, (.FEATS[16:18]) := lapply(.CONS_K, function(k) .chg(tp, k)), by = Ticker]
cat(sprintf("%s 컨센서스: 영업이익 FY1 %d행(%s~%s) · 목표주가 %d행(%s~%s) · 적격행 커버리지 op %.1f%% · tp %.1f%%\n",
            .TAG, nrow(.op), as.character(min(.op$Date)), as.character(max(.op$Date)),
            nrow(.tp), as.character(min(.tp$Date)), as.character(max(.tp$Date)),
            100 * .G[MEM == TRUE, mean(is.finite(op))], 100 * .G[MEM == TRUE, mean(is.finite(tp))]))
.G[, c("op", "tp") := NULL]; rm(.op, .tp); gc(verbose = FALSE)

# =============================================================================
# 6. 스케줄 — 월말 시그널 · 5영업일 갱신 격자 · 학습창 [u−1004, u−5]  ★changed(3)(5)
# =============================================================================
.CAL[, MI := year(Date) * 12L + month(Date)]
.me <- .CAL[, .(Date = max(Date), di = max(di)), by = MI]
setorder(.me, MI)
.me <- .me[MI < max(MI) & Date >= .START]                                                     # 마지막 달력월 = 부분월 → 제외
.anchor_i <- .CAL[Date >= .ANCHOR, min(di)]
.grid5 <- .CAL[di >= .anchor_i & ((di - .anchor_i) %% .UPD_EVERY) == 0L, di]
.SCH <- .me[, {
  u <- max(.grid5[.grid5 <= di])
  .(pred_i = di, u_i = u, smax_i = u - .HORIZON, smin_i = u - .HORIZON - (.N_TRAIN - 1L))
}, by = .(MI, Date)]
.n_sched_all <- nrow(.SCH)
.SCH <- .SCH[smin_i >= 1L]
setorder(.SCH, pred_i)
.SCH[, k := seq_len(.N)]
.SCH[, seed := .SEED_BASE + k]
if (nrow(.SCH) < 12L) stop(sprintf("%s 스케줄 월 %d개 — 격자 범위 확인", .TAG, nrow(.SCH)))
.PANEL_FROM_I <- min(.SCH$smin_i)
cat(sprintf("%s 스케줄 %d개월(%s ~ %s · 학습창 미달로 제외 %d) · 갱신 격자 앵커 %s · 첫 달: 갱신 %s · 학습집합 %s ~ %s\n",
            .TAG, nrow(.SCH), as.character(min(.SCH$Date)), as.character(max(.SCH$Date)), .n_sched_all - nrow(.SCH),
            as.character(.CAL$Date[.anchor_i]), as.character(.CAL$Date[.SCH$u_i[1]]),
            as.character(.CAL$Date[.SCH$smin_i[1]]), as.character(.CAL$Date[.SCH$smax_i[1]])))

# =============================================================================
# 7. 회계 특성 (Table 1 No.19~31) ★3판 — 식 = 논문 §3.1 인쇄 정의 · 산출 = 월말(논문 규정) · 그 달 안 캐리  ★changed(8)(9)
#    논문: 'No. 19-33 are calculated on a monthly basis (at the end of month).' → 월말 me 에서 (usable ≤ me 인 최신 FY, 시총_me) 로
#    한 번 계산하고, 거래일 t 는 me(t) = t 이하 마지막 월말(월말 당일 포함)의 값을 쓴다. 원천 = fundamental_merged.parquet 원값
#    (DART 연간 + XLSX 분기 → 연간) → usable FY+1 3/31. 월말 패널 .ME 는 격자 전 종목에서 뽑고, 학습·예측 패널 .P 는 적격(MEM) ∧
#    di ≥ 첫 학습창 시작 행으로 좁힌다.
# =============================================================================
.ME_CAL <- .CAL[MI < max(MI), .(me_di = max(di)), by = MI]                                    # 완결 달력월의 마지막 거래일 = 월말 산출점
setorder(.ME_CAL, me_di)
.ME_CAL[, me_key := me_di]
.CAL[, me_di := .ME_CAL[.CAL[, .(di)], on = .(me_key = di), roll = Inf, x.me_di]]             # me(t) ≤ t · 첫 월말 이전 = NA
local({
  ok <- .CAL[!is.na(me_di), all(me_di <= di) &&
               all(fifelse(di %in% .ME_CAL$me_di, me_di == di, .CAL$MI[me_di] == MI - 1L))]
  if (!isTRUE(ok)) stop(sprintf("%s 월말 사상 me(t) 검산 실패", .TAG))
})
.ME <- .G[di %in% .ME_CAL$me_di, .(Ticker, me_di = di, Date, Size)]                           # 격자 전 종목 × 월말 (시총 = 그 월말)
## >>> DT_ZONE sigma252 orig=+310
# DT: 신호일(.SCH$pred_i) 적격 종목의 σ(S1 · S2 짝 · 예측표 기록) — 격자 .G(연속 거래일 × 적격 이력 종목 · 수정 종가)가 지워지기 전에
#   계산한다. .G 는 읽기만 한다(열 추가 · 행 변경 없음). 창 끝 = 신호일 전날(t−1) · 결과 표 .DT_SIG(Ticker, pred_i, sigma252).
.DT_PTS <- sort(unique(.SCH$pred_i))
.DT_SIG <- .G[, {
  if (!identical(di, seq_along(di))) stop(sprintf("%s σ — 종목 %s 의 격자 행이 연속 거래일이 아니다", .TAG, .BY$Ticker))
  p <- .DT_PTS[MEM[.DT_PTS] %in% TRUE]
  list(pred_i = p, sigma252 = .dt_sigma_at(Close, p, .DT_SIGMA_WIN, .DT_SIGMA_MIN))
}, by = Ticker]
cat(sprintf("%s σ(직전 %d거래일 일 로그수익 sd · 창 끝 t−1 · 유효 관측 ≥ %d · 수정 종가): 신호일 %d × 적격 종목 = %d행 · σ 결측 %.1f%%\n",
            .TAG, .DT_SIGMA_WIN, .DT_SIGMA_MIN, length(.DT_PTS), nrow(.DT_SIG), 100 * mean(!is.finite(.DT_SIG$sigma252))))
## <<< DT_ZONE sigma252
.P <- .G[MEM == TRUE & di >= .PANEL_FROM_I]
rm(.G); gc(verbose = FALSE)
.FLOW_ITEMS <- c("Revenue", "OperatingProfit", "PretaxIncome", "TaxExpense", "NetIncome", "OperatingCF", "Dividends", "DepAmort")
.BS_ITEMS   <- c("TotalAssets", "CurrentAssets", "CurrentLiab", "TotalEquity", "ShortTermBorr", "LongTermBorr")
.FUND_ITEMS <- c(.FLOW_ITEMS, .BS_ITEMS)
.fm_path <- file.path(.CACHE, "fundamental_merged.parquet")
if (!file.exists(.fm_path)) stop(sprintf("%s 회계 패널 부재: %s — Table 1 No.19~31 원천. data_gap 적재 대상", .TAG, .fm_path))
.fm <- as.data.table(dplyr::collect(dplyr::filter(arrow::open_dataset(.fm_path),
                                                  Item %in% .FUND_ITEMS, Source %in% c("DART", "XLSX"))))
if (!all(c("Ticker", "Period", "Item", "Value", "Source") %in% names(.fm)))
  stop(sprintf("%s 회계 패널 스키마 불일치: %s", .TAG, paste(names(.fm), collapse = ",")))
.fm[, Ticker := as.character(Ticker)]
.fm <- .fm[Ticker %in% .mem_tk & is.finite(Value)]
if (nrow(.fm) == 0L) stop(sprintf("%s 회계 패널이 적격 종목과 0행 교차 — Ticker 형식 확인", .TAG))
.fm[, Period := as.character(Period)]
.fm[, FY := as.integer(substr(Period, 1L, 4L))]
.fm[, MM := as.integer(substr(Period, 5L, 6L))]
.fm <- .fm[is.finite(FY) & MM %in% c(3L, 6L, 9L, 12L)]
# (a) 유량 항목 — DART 행 = 사업연도 합계 그대로 · XLSX 행 = 분기 관측 → 연간화. XLSX 분기값이 단일분기 유량인지
#     누적(YTD)인지는 패널 문서가 못 박지 않아 데이터 형식으로 판별한다: 매출 4분기 합 ÷ 12월 분기값 중앙값이 3 을 넘으면
#     단일분기(합산), 아니면 누적(12월 값 채택). 성과와 무관한 형식 판별이며 로그에 남긴다(changed(8)).
.fx <- .fm[Item %in% .FLOW_ITEMS]
.xq <- .fx[Source == "XLSX", .(n_q = uniqueN(MM), s4 = sum(Value), q4 = sum(Value[MM == 12L]), has12 = any(MM == 12L)),
           by = .(Ticker, FY, Item)]
.rr <- .xq[Item == "Revenue" & n_q == 4L & q4 > 0 & s4 > 0, s4 / q4]
.rr_med <- if (length(.rr)) median(.rr) else NA_real_
.XFLOW_QTR <- is.finite(.rr_med) && .rr_med > 3
.xa <- if (isTRUE(.XFLOW_QTR)) .xq[n_q == 4L, .(Ticker, FY, Item, Value = s4)] else .xq[has12 == TRUE, .(Ticker, FY, Item, Value = q4)]
.da <- .fx[Source == "DART" & MM == 12L, .(Ticker, FY, Item, Value)]
.fl <- rbind(.da[, pri := 1L], .xa[, pri := 2L])
setorder(.fl, Ticker, FY, Item, pri)
.fl <- unique(.fl, by = c("Ticker", "FY", "Item"))[, pri := NULL]
# (b) 시점 항목 — 12월 말 값 (분기 3/6/9 는 쓰지 않는다 · 결산월 12 기준 = changed(8))
.bs <- .fm[Item %in% .BS_ITEMS & MM == 12L, .(Ticker, FY, Item, Value)]
.FA <- dcast(rbind(.fl, .bs), Ticker + FY ~ Item, value.var = "Value")
for (it in .FUND_ITEMS) if (!it %in% names(.FA)) .FA[, (it) := NA_real_]
.n_ni_x <- .FA[!is.finite(NetIncome) & is.finite(PretaxIncome) & is.finite(TaxExpense), .N]
.FA[!is.finite(NetIncome) & is.finite(PretaxIncome) & is.finite(TaxExpense), NetIncome := PretaxIncome - TaxExpense]   # XLSX 에 순이익 항목 없음 (changed(8))
setorder(.FA, Ticker, FY)
.FA[, FY_prev := shift(FY), by = Ticker]
.FA[, TA_prev := shift(TotalAssets), by = Ticker]
.FA[, CA_prev := shift(CurrentAssets), by = Ticker]
.FA[, CL_prev := shift(CurrentLiab), by = Ticker]
.FA[!(is.finite(FY_prev) & FY_prev == FY - 1L), c("TA_prev", "CA_prev", "CL_prev") := NA_real_]             # 직전 연도만
# ── 논문 §3.1 인쇄 정의(축자) → 구현 ──
.FA[, nopat := .nopat(OperatingProfit, TaxExpense, PretaxIncome)]                                            # 'Net Operating Profits After Tax'
.FA[, invcap := fifelse(is.finite(TotalEquity), .nz(ShortTermBorr) + .nz(LongTermBorr) + TotalEquity, NA_real_)]   # 'Debt + Net Assets' (현금 차감 없음)
.FA[, f_roe  := .sdiv(NetIncome, TotalEquity)]                                                               # No.24 Net Profits/Net Assets
.FA[, f_roa  := .sdiv(OperatingProfit, TotalAssets)]                                                         # No.25 Net Operating Profits/Total Assets
.FA[, f_roic := .sdiv(nopat, invcap)]                                                                        # No.26 NOPAT/(Debt + Net Assets)
.FA[, f_acc  := .accr(CurrentAssets, CA_prev, CurrentLiab, CL_prev, DepAmort, TotalAssets)]                  # No.27 −(ΔCA − ΔCL − Dep)/TA
.FA[, f_at   := .sdiv(Revenue, TotalAssets)]                                                                 # No.28 Sales/Total Assets
.FA[, f_cr   := .sdiv(CurrentAssets, CurrentLiab)]                                                           # No.29 Current Assets/Current Liabilities
.FA[, f_er   := .sdiv(TotalEquity, TotalAssets)]                                                             # No.30 Net Assets/Total Assets
.FA[, f_ag   := fifelse(is.finite(TotalAssets) & is.finite(TA_prev) & TA_prev > 0, TotalAssets / TA_prev - 1, NA_real_)]   # No.31 Change Rate of Total Assets
.FA[, f_div  := fifelse(is.finite(Dividends), abs(Dividends), NA_real_)]                                     # No.21 분자 'Dividends' = 배당금지급액(CF · 유출 부호 제거)
.FA[, usable := as.Date(sprintf("%d-03-31", FY + 1L))]                                                       # C4: 사업연도 익년 3/31 (changed(8))
.fcols <- c("FY", "TotalEquity", "NetIncome", "f_div", "Revenue", "OperatingCF",
            "f_roe", "f_roa", "f_roic", "f_acc", "f_at", "f_cr", "f_er", "f_ag")
.n_fa <- nrow(.FA); .n_fa_tk <- uniqueN(.FA$Ticker); .fy_rng <- range(.FA$FY)
.dep_cov <- .FA[, mean(is.finite(DepAmort))]
.FA <- .FA[, c("Ticker", "usable", .fcols), with = FALSE]
setorder(.FA, Ticker, usable)
# 월말 me 에서: usable ≤ me 인 최신 FY(캐리 ≤ 456일) × 시총_me → No.19~31 (논문 'monthly basis (at the end of month)')
.tmp <- .FA[.ME[, .(Ticker, Date)], on = .(Ticker, usable = Date), roll = .FUND_ROLL]
.ME[, (.fcols) := .tmp[, .fcols, with = FALSE]]
rm(.tmp, .fx, .xq, .xa, .da, .fl, .bs, .fm, .FA)
.ME[, x19 := .sdiv(TotalEquity, Size)]                                                                       # No.19 Net Assets/Market Value
.ME[, x20 := .sdiv(NetIncome, Size)]                                                                         # No.20 Net Profits/Market Value
.ME[, x21 := .sdiv(f_div, Size)]                                                                             # No.21 Dividends/Market Value
.ME[, x22 := .sdiv(Revenue, Size)]                                                                           # No.22 Sales/Market Value
.ME[, x23 := .sdiv(OperatingCF, Size)]                                                                       # No.23 Operating Cashflow/Market Value
.ME[, x24 := f_roe]; .ME[, x25 := f_roa]; .ME[, x26 := f_roic]; .ME[, x27 := f_acc]; .ME[, x28 := f_at]
.ME[, x29 := f_cr]; .ME[, x30 := f_er]; .ME[, x31 := f_ag]
.ME[, FYm := FY]
# 거래일 t → me(t) 의 월말 값 (그 달 안 캐리 · 월말 당일 = 그날 산출값)
.P[.CAL, on = "di", me_di := i.me_di]
.P[.ME, on = .(Ticker, me_di), c(.FUND_FEATS, "FYm") := mget(paste0("i.", c(.FUND_FEATS, "FYm")))]
.n_no_me <- .P[is.na(me_di), .N]
.fund_cov <- .P[, mean(is.finite(FYm))]
.cov_txt <- paste(sprintf("%s %.0f%%", c("No.19", "No.25", "No.26", "No.27"),
                          100 * c(.P[, mean(is.finite(x19))], .P[, mean(is.finite(x25))], .P[, mean(is.finite(x26))], .P[, mean(is.finite(x27))])),
                  collapse = " · ")
.P[, c("me_di", "FYm") := NULL]
cat(sprintf("%s 회계(월말 산출): FY 행 %d(%d종 · FY %d~%d) · XLSX 분기값 형식 = %s(매출 4분기합/12월값 중앙 %s · n=%d) · XLSX 순이익 = 세전−법인세 대치 %d행 · 감가상각 항목 보유 FY 행 %.1f%% · 월말 산출점 %d개 · 첫 월말 이전 패널행 %d · 패널 커버리지 FY %.1f%% · %s\n",
            .TAG, .n_fa, .n_fa_tk, .fy_rng[1], .fy_rng[2],
            if (isTRUE(.XFLOW_QTR)) "단일분기 유량(4분기 합산)" else "누적(12월 값 채택)",
            if (is.finite(.rr_med)) sprintf("%.2f", .rr_med) else "NA", length(.rr), .n_ni_x, 100 * .dep_cov,
            nrow(.ME_CAL), .n_no_me, 100 * .fund_cov, .cov_txt))
if (.fund_cov <= 0) stop(sprintf("%s 회계 패널 커버리지 0 — Ticker 형식 또는 usable 규약 확인", .TAG))
rm(.ME)

# =============================================================================
# 8. 순위 재척도 (그날 적격 집합 안 · 특성 31 + 표적) → 패널 파케이(실행별 작업본)  ★changed(10)
# =============================================================================
.na_pre  <- .P[Date <  .START, lapply(.SD, function(v) 100 * mean(!is.finite(v))), .SDcols = .FEATS]
.na_post <- .P[Date >= .START, lapply(.SD, function(v) 100 * mean(!is.finite(v))), .SDcols = .FEATS]
.P[, (.FEATS) := lapply(.SD, .rank01), by = Date, .SDcols = .FEATS]
.P[, y := NA_real_]
.P[is.finite(y_raw), y := .rank01(y_raw), by = Date]
.P[!is.finite(y), lab_i := NA_integer_]
.P[, lab_i := as.integer(lab_i)]
.PN <- .P[, c("di", "Ticker", .FEATS, "y", "lab_i"), with = FALSE]
.SCHO <- .SCH[, .(k, pred_i, u_i, smin_i, smax_i, seed)]
.panel_path <- file.path(.RD, "panel.parquet"); .sched_path <- file.path(.RD, "schedule.parquet")
.pred_path  <- file.path(.RD, "pred.parquet");  .diag_path  <- file.path(.RD, "diag.parquet")
write_parquet(.PN, .panel_path)
write_parquet(.SCHO, .sched_path)
cat(sprintf("%s 패널 %d행 × 특성 %d (%s ~ %s · 표적 있는 행 %d) → %s\n", .TAG, nrow(.PN), length(.FEATS),
            as.character(min(.P$Date)), as.character(max(.P$Date)), sum(is.finite(.PN$y)), .panel_path))
cat(sprintf("  특성 결측률(순위 전 · 결측 = 0.5 대치) 2005 이전 / 이후: %s\n",
            paste(sprintf("%s %.0f/%.0f%%", .FEAT_NAMES, as.numeric(.na_pre[1, ]), as.numeric(.na_post[1, ])), collapse = " · ")))
rm(.PN); gc(verbose = FALSE)

## >>> DT_ZONE hist252 orig=+424
# DT: 자기 이력 하방 폭 h(D^H 짝 · 철학 P1 C-20261018-065) — 신호일 p(.SCH 의 학습 격자 u) 에 예측 행이 있는 종목마다, 학습 패널 .P 의 그 종목 행에서
#   di ∈ [p − 252, p − 1] ∧ lab_i ≤ u(실현분만 · PIT 단언과 같은 경계) 인 학습 표적 y(그날 적격 집합 안 5일 수익 순위 재척도 — 파이썬이 학습하는 열 그대로)로
#   h = 중앙값 − 10% 분위(유효 관측 ≥ .DT_HIST_MIN). .P 는 읽기만 한다(열 추가 · 행 변경 없음). 결과 표 .DT_HIST(Ticker, pred_i, h_hist).
.DT_U <- .SCH[, .(pred_i, u_i)]
.DT_HIST <- .P[, {
  o <- order(di)
  p <- .DT_U$pred_i[.DT_U$pred_i %in% di]
  list(pred_i = p, h_hist = .dt_hist_at(di[o], y[o], lab_i[o], p, .DT_U$u_i[match(p, .DT_U$pred_i)], .DT_HIST_WIN, .DT_HIST_MIN, .DT_HIST_TAU))
}, by = Ticker]
cat(sprintf("%s 자기 이력 폭 h(직전 %d거래일 자기 y 중 실현분 lab_i ≤ u · 중앙값 − %g 분위 · 유효 관측 ≥ %d): %d행 · h 결측 %.1f%%\n",
            .TAG, .DT_HIST_WIN, .DT_HIST_TAU, .DT_HIST_MIN, nrow(.DT_HIST), 100 * mean(!is.finite(.DT_HIST$h_hist))))

## <<< DT_ZONE hist252
# =============================================================================
# 9. DNN5 — 파이썬(venv torch) 서브프로세스. 스크립트 본문은 여기 있고 매 실행 작업본에 써 넣는다.  ★changed(4)(5)(6)(15)
#    학습 수치 경로(fit_predict)는 1·2판과 동일 — 3판 변경 = 1판 재사용층 제거 · 특성 수를 패널 스키마에서 읽음 · 처리 순서 회전.
# =============================================================================
.PY_SRC <- r"---(
## >>> DT_ZONE py_ident orig=430-430
# dnn_rolling.py - DT_2002_06975 dnn_quantile rev1 (3 quantile heads on Abe & Nakagawa 2020 Table 2 DNN5). Written by engine_<rule>.R on every run; do not edit.
## <<< DT_ZONE py_ident
import os
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
import sys
import math
import time
import hashlib
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import torch
import torch.nn as nn
from concurrent.futures import ProcessPoolExecutor

## >>> DT_ZONE py_const orig=446-446
CODE_VERSION = "DT_2002_06975/dnn_quantile/rev1"   # part of every cache key; rule-independent (all 7 rule engines share one trained prediction per month)
TAUS = [0.1, 0.5, 0.9]                     # quantile heads P10/P50/P90 on one shared body (design 3.3)
N_OUT = len(TAUS)                          # output units = heads
LOSS_NAME = "pinball_mean"                 # (1/3) sum_tau mean rho_tau(y - q_tau), rho_tau(u) = u (tau - 1{u<0})
# positive control (heteroscedastic synthetic, design 3.3) - sample sizes and the centre/width ratio are fixed by the
# registration rehearsal (tests/pc_mutation_test.py, CPU, 2026-10-18; thresholds = design 3.3):
#   PC_N 20000 (rev3 size) under-trains the 0.9 head with this routine (3/3 seeds fail: spearman q90 0.49-0.67) -> 100000:
#   correct code 9/9 seeds pass (spearman >= 0.975, hit q10 0.092-0.120, q90 0.889-0.909); the width-not-learned mutant
#   stays at spearman q10 <= 0.634 / q90 <= 0.541 (population spearman(m, l) ~ 0.56 at PC_F_SD 0.5) -> fails on every seed.
PC_N = 100000                              # training rows (20 epochs x 200 mini-batches = 4000 steps, same fit_predict)
PC_NPRED = 5000                            # holdout rows (rev3 size)
PC_F_SD = 0.5                              # sd of the centre f (width g = 0.25 + 2 X2 has sd(g z_0.1) = 0.740)
PC_RHO_MIN = 0.8                           # spearman threshold (rev3 positive-control threshold, inherited)
PC_COV10 = (0.05, 0.15)                    # holdout hit-rate band for the 0.1 head
PC_COV90 = (0.85, 0.95)                    # holdout hit-rate band for the 0.9 head
## <<< DT_ZONE py_const
HIDDEN = [300, 300, 150, 150, 50]          # Table 2 DNN5 hidden layers
DROPOUT = [0.50, 0.50, 0.30, 0.30, 0.10]   # Table 2 DNN5 dropout rates
EPOCHS = 20                                # Table 2 DNN5 epochs
BATCH = 500                                # paper: mini-batch size 500
LR = 1e-3                                  # not stated -> TensorFlow Adam default
BN_EPS = 1e-3                              # not stated -> TensorFlow batch_normalization default
BN_MOMENTUM = 0.01                         # TensorFlow decay 0.99 == torch momentum 0.01
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
P = {}             # per-process panel arrays (filled by load_panel in every worker)
CACHE_DIR = None


class DNN(nn.Module):
    def __init__(self, m):
        super().__init__()
        layers = []
        prev = m
        for h, p in zip(HIDDEN, DROPOUT):
            layers.append(self.linear(prev, h))
            layers.append(nn.BatchNorm1d(h, eps=BN_EPS, momentum=BN_MOMENTUM))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(p))
            prev = h
## >>> DT_ZONE py_head orig=470-470
        layers.append(self.linear(prev, N_OUT))   # 3 heads on the shared body: output unit j <-> TAUS[j] (same init rule)
## <<< DT_ZONE py_head
        self.net = nn.Sequential(*layers)

    @staticmethod
    def linear(fan_in, fan_out):
        lin = nn.Linear(fan_in, fan_out)
        sd = math.sqrt(2.0 / fan_in)       # paper: tf.truncated_normal, mean 0, std sqrt(2/M), M = fan-in
        nn.init.trunc_normal_(lin.weight, mean=0.0, std=sd, a=-2.0 * sd, b=2.0 * sd)
        nn.init.zeros_(lin.bias)
        return lin

    def forward(self, x):
## >>> DT_ZONE py_forward orig=482-482
        return self.net(x)
## <<< DT_ZONE py_forward


def fit_predict(X, y, Xp, seed):
    # same seed use, same init order, same cpu-generated batch order on any device
    torch.manual_seed(seed)
    gen = torch.Generator()
    gen.manual_seed(seed)
    model = DNN(X.shape[1]).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
## >>> DT_ZONE py_loss_def orig=492-492
    tau_t = torch.tensor(TAUS, dtype=torch.float32, device=DEVICE).unsqueeze(0)   # 1 x 3: column j of the output is trained as TAUS[j]
## <<< DT_ZONE py_loss_def
    Xt = torch.from_numpy(X).to(DEVICE)
    yt = torch.from_numpy(y).to(DEVICE)
    n = Xt.shape[0]
    steps = 0
    skipped = 0
    last = float("nan")
    model.train()
    for _ in range(EPOCHS):
        perm = torch.randperm(n, generator=gen)      # cpu generator -> same batch order on any device
        for b in range(0, n, BATCH):
            idx = perm[b:b + BATCH]
            if idx.numel() < 2:            # batch norm needs at least 2 rows (declared)
                skipped += 1
                continue
            idx = idx.to(DEVICE)
            opt.zero_grad()
## >>> DT_ZONE py_loss_step orig=509-509
            u = yt[idx].unsqueeze(1) - model(Xt[idx])            # residual y - q_tau (batch x 3)
            loss = torch.mean(u * (tau_t - (u < 0).float()))     # composite pinball (Koenker & Bassett 1978; equal weights, Zou & Yuan 2008)
## <<< DT_ZONE py_loss_step
            loss.backward()
            opt.step()
            steps += 1
            last = float(loss.item())
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(Xp).to(DEVICE)).cpu().numpy()
    return pred, steps, skipped, last

## >>> DT_ZONE py_rearrange orig=+518

def rearrange(raw):
    # row-wise monotone rearrangement (Chernozhukov, Fernandez-Val & Galichon 2010, Econometrica 78(3)): sorted heads q10 <= q50 <= q90.
    # crossing rate = share of rows whose raw heads are not non-decreasing (recorded before the rearrangement).
    raw = np.asarray(raw, dtype=np.float64)
    cross = float(np.mean(np.any(np.diff(raw, axis=1) < 0.0, axis=1))) if raw.shape[0] else float("nan")
    return np.sort(raw, axis=1), cross

## <<< DT_ZONE py_rearrange

def feature_names(schema_names):
    return [c for c in schema_names if c[0] == "x" and c[1:].isdigit()]


def load_panel(path, cache_dir):
    global P, CACHE_DIR
    torch.set_num_threads(1)
    t = pq.read_table(path)
    feats = feature_names(t.column_names)
    X = np.empty((t.num_rows, len(feats)), dtype=np.float32)
    for j, c in enumerate(feats):
        X[:, j] = t.column(c).to_pandas().to_numpy(dtype=np.float64)
    y = t.column("y").to_pandas().to_numpy(dtype=np.float64).astype(np.float32)
    lab = t.column("lab_i").to_pandas().to_numpy(dtype=np.float64)
    lab = np.where(np.isnan(lab), -1.0, lab).astype(np.int32)
    di = t.column("di").to_pandas().to_numpy(dtype=np.int64).astype(np.int32)
    tk = t.column("Ticker").to_pandas().to_numpy().astype(str)
    P = dict(X=X, y=y, lab=lab, di=di, tk=tk, feats=feats)
    CACHE_DIR = cache_dir


def select(task):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    di = P["di"]
    y = P["y"]
    m_tr = (di >= smin_i) & (di <= smax_i) & (~np.isnan(y))
    m_pr = di == pred_i
    X = np.ascontiguousarray(P["X"][m_tr])
    yy = np.ascontiguousarray(y[m_tr])
    Xp = np.ascontiguousarray(P["X"][m_pr])
    tk = P["tk"][m_pr]
    lab = P["lab"][m_tr]
    n_days = int(np.unique(di[m_tr]).size) if X.shape[0] else 0
    max_lab = int(lab.max()) if X.shape[0] else -1
    return X, yy, Xp, tk, n_days, max_lab


def cache_key(task, X, y, Xp, tk):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    h = hashlib.sha1()
    h.update(CODE_VERSION.encode("ascii"))
    spec = "|%d|%d|%d|%d|%d|%s|%s|%d|%d|%r|%r|%r|%s" % (pred_i, u_i, smin_i, smax_i, seed, HIDDEN, DROPOUT, EPOCHS, BATCH, LR, BN_EPS, BN_MOMENTUM, ",".join(P["feats"]))
## >>> DT_ZONE py_cache_key orig=+561
    spec += "|LOSS=%s|TAUS=%s|OUT=%d" % (LOSS_NAME, ",".join("%g" % t for t in TAUS), N_OUT)   # quantile target: never collides with a mean-target key
## <<< DT_ZONE py_cache_key
    h.update(spec.encode("ascii"))
    h.update(X.tobytes())
    h.update(y.tobytes())
    h.update(Xp.tobytes())
    h.update("|".join(tk.tolist()).encode("utf-8"))
    return h.hexdigest()


## >>> DT_ZONE py_cache_io orig=570-589
def cache_read(key):
    # npz = raw head outputs score (n x 3, before the rearrangement) + crossing rate + code version
    p = os.path.join(CACHE_DIR, key + ".npz")
    if not os.path.exists(p):
        return None
    try:
        z = np.load(p, allow_pickle=False)
        score = z["score"].astype(np.float64)
        if score.ndim != 2 or score.shape[1] != N_OUT or str(z["code_version"]) != CODE_VERSION:
            return None
        return dict(score=score, tk=z["tk"].astype(str), steps=int(z["steps"]),
                    skipped=int(z["skipped"]), last_loss=float(z["last_loss"]), secs=float(z["secs"]),
                    device=str(z["device"]), source=str(z["source"]), cross_rate=float(z["cross_rate"]))
    except Exception:
        return None


def cache_write(key, score, tk, steps, skipped, last_loss, secs, device, source, cross_rate):
    p = os.path.join(CACHE_DIR, key + ".npz")
    tmp = os.path.join(CACHE_DIR, "%s.%d.tmp.npz" % (key, os.getpid()))
    np.savez(tmp, score=np.asarray(score, dtype=np.float64), tk=np.asarray(tk, dtype=str),
             steps=np.int64(steps), skipped=np.int64(skipped), last_loss=np.float64(last_loss),
             secs=np.float64(secs), device=np.str_(device), source=np.str_(source),
             cross_rate=np.float64(cross_rate), code_version=np.str_(CODE_VERSION))
    os.replace(tmp, p)
## <<< DT_ZONE py_cache_io


def run_task(task):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    X, y, Xp, tk, n_days, max_lab = select(task)
    diag = dict(k=k, pred_i=pred_i, u_i=u_i, smin_i=smin_i, smax_i=smax_i,
                n_train=int(X.shape[0]), n_days=n_days, max_lab_i=max_lab, n_pred=int(Xp.shape[0]),
                steps=0, skipped=0, last_loss=float("nan"), secs=0.0, source="none", device=DEVICE)
    if X.shape[0] == 0 or Xp.shape[0] == 0:
        return k, None, diag
    if max_lab > u_i:
        raise RuntimeError("PIT: a training label is realized after the update day (max_lab_i %d > u_i %d)" % (max_lab, u_i))
    key = cache_key(task, X, y, Xp, tk)
    hit = cache_read(key)
    src = "cache"
## >>> DT_ZONE py_run_task_tail orig=605-617
    if hit is not None and (hit["score"].shape != (len(tk), N_OUT) or not np.array_equal(hit["tk"], tk)):
        hit = None
    if hit is None:
        t0 = time.time()
        pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
        secs = time.time() - t0
        pred = np.asarray(pred, dtype=np.float64).reshape(len(tk), N_OUT)
        cross0 = rearrange(pred)[1]
        cache_write(key, pred, tk, steps, skipped, last, secs, DEVICE, "train", cross0)
        hit = dict(score=pred, steps=steps, skipped=skipped, last_loss=last, secs=secs, device=DEVICE, cross_rate=cross0)
        src = "train"
    raw = hit["score"]
    q, cross = rearrange(raw)
    if not (cross == hit["cross_rate"]):
        raise RuntimeError("crossing rate recomputed from the cached raw heads differs from the stored one (%r vs %r)" % (cross, hit["cross_rate"]))
    out = pd.DataFrame({"pred_i": np.repeat(pred_i, len(tk)), "Ticker": tk,
                        "q10_raw": raw[:, 0], "q50_raw": raw[:, 1], "q90_raw": raw[:, 2],
                        "q10": q[:, 0], "q50": q[:, 1], "q90": q[:, 2]})
    diag.update(steps=hit["steps"], skipped=hit["skipped"], last_loss=hit["last_loss"], secs=hit["secs"],
                source=src, device=hit["device"], cross_rate=cross, cache_key=key)
    return k, out, diag
## <<< DT_ZONE py_run_task_tail


## >>> DT_ZONE py_synth orig=620-632
def synthetic_check(seed, m):
    # positive control (design 3.3): a heteroscedastic synthetic y = f + g * eps must be learned by the same fit_predict routine.
    #   X ~ U(0,1)^m . f = PC_F_SD * (f0 - mean f0) / sd(f0), f0 = X w + 0.5 sin(6 X1) (rev3 centre form; mean/sd from the training draw)
    #   g = 0.25 + 2 X2 (width signal, 9x range) . eps ~ N(0,1).
    #   Training y and holdout labels go to the rank scale (0, 1] through the training-sample empirical CDF Fhat; truth on that
    #   scale: m = Fhat(f), l = Fhat(f + g z_0.1), u = Fhat(f + g z_0.9). The width dominates the order of l and u, so a model
    #   whose heads are q50 + constant fails the l / u spearman.
    #   pass = on the raw heads AND on the rearranged heads: spearman(q50, m), spearman(q10, l), spearman(q90, u) > PC_RHO_MIN and
    #   holdout hit rates P(y <= q10) in PC_COV10, P(y <= q90) in PC_COV90 (raw heads catch head swaps / sign flips that the sort hides).
    rng = np.random.default_rng(seed)
    n, npred = PC_N, PC_NPRED
    X = rng.uniform(0.0, 1.0, size=(n, m)).astype(np.float32)
    w = rng.normal(size=m).astype(np.float64)
    Xp = rng.uniform(0.0, 1.0, size=(npred, m)).astype(np.float32)
    e = rng.normal(size=n)
    ep = rng.normal(size=npred)
    f0 = X.astype(np.float64) @ w + 0.5 * np.sin(6.0 * X[:, 0].astype(np.float64))
    mu0 = float(np.mean(f0))
    sd0 = float(np.std(f0))

    def centre(Z):
        z = Z.astype(np.float64)
        return PC_F_SD * ((z @ w + 0.5 * np.sin(6.0 * z[:, 0])) - mu0) / sd0

    def width(Z):
        return 0.25 + 2.0 * Z[:, 1].astype(np.float64)

    f, g = centre(X), width(X)
    fp, gp = centre(Xp), width(Xp)
    ys = np.sort(f + g * e)

    def fhat(v):
        return np.searchsorted(ys, v, side="right") / float(n)

    y = fhat(f + g * e).astype(np.float32)
    yh = fhat(fp + gp * ep)
    z10 = -1.2815515655446004                  # standard normal 10% quantile (z_0.9 = -z_0.1)
    truth = (fhat(fp + gp * z10), fhat(fp), fhat(fp - gp * z10))
    raw, steps, skipped, last = fit_predict(X, y, Xp, seed)
    raw = np.asarray(raw, dtype=np.float64).reshape(npred, N_OUT)
    rea, cross = rearrange(raw)
    res = dict(steps=int(steps), cross_rate=cross, last_loss=float(last))
    ok = True
    for tag, Q in (("raw", raw), ("rea", rea)):
        for j, nm in enumerate(("10", "50", "90")):
            rho = float(pd.Series(Q[:, j]).corr(pd.Series(truth[j]), method="spearman"))
            res["%s_rho%s" % (tag, nm)] = rho
            ok = ok and (rho > PC_RHO_MIN)
        c10 = float(np.mean(yh <= Q[:, 0]))
        c90 = float(np.mean(yh <= Q[:, 2]))
        res["%s_cov10" % tag] = c10
        res["%s_cov90" % tag] = c90
        ok = ok and (PC_COV10[0] <= c10 <= PC_COV10[1]) and (PC_COV90[0] <= c90 <= PC_COV90[1])
    res["pass"] = bool(ok)
    return res
## <<< DT_ZONE py_synth


def main():
    rd = sys.argv[1]
    cd = sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 32
    os.makedirs(cd, exist_ok=True)
    panel_path = os.path.join(rd, "panel.parquet")
    sched_path = os.path.join(rd, "schedule.parquet")
    pred_path = os.path.join(rd, "pred.parquet")
    diag_path = os.path.join(rd, "diag.parquet")
    for p in (pred_path, diag_path):
        if os.path.exists(p):
            os.remove(p)
    sched = pq.read_table(sched_path).to_pandas()
    m = len(feature_names(pq.read_schema(panel_path).names))
    torch.set_num_threads(1)
    t0 = time.time()
## >>> DT_ZONE py_main_pc orig=651-655
    pc = synthetic_check(int(sched["seed"].iloc[0]) + 7, m)
    print("[dnn] positive control (heteroscedastic synthetic, %d inputs, train %d / holdout %d): raw heads spearman q10 %.3f q50 %.3f q90 %.3f, hit q10 %.3f q90 %.3f | rearranged spearman q10 %.3f q50 %.3f q90 %.3f, hit q10 %.3f q90 %.3f | crossing %.4f | %d steps (%.0fs, device %s)" % (
        m, PC_N, PC_NPRED, pc["raw_rho10"], pc["raw_rho50"], pc["raw_rho90"], pc["raw_cov10"], pc["raw_cov90"],
        pc["rea_rho10"], pc["rea_rho50"], pc["rea_rho90"], pc["rea_cov10"], pc["rea_cov90"], pc["cross_rate"], pc["steps"], time.time() - t0, DEVICE), flush=True)
    if not pc["pass"]:
        print("[dnn] positive control FAILED - the training loop does not learn the known conditional quantiles; aborting", flush=True)
        sys.exit(3)
## <<< DT_ZONE py_main_pc
    tasks = [tuple(int(v) for v in row) for row in sched[["k", "pred_i", "u_i", "smin_i", "smax_i", "seed"]].to_numpy()]
    # processing order rotated by a per-run offset: concurrent runs (lane re-spawn) start on different months and
    # meet through the shared cache instead of training the same months twice; every month's result is order-independent
    off = int(hashlib.sha1(os.path.basename(rd).encode("utf-8")).hexdigest(), 16) % len(tasks)
    tasks = tasks[off:] + tasks[:off]
    ncpu = os.cpu_count() or 2
    workers = max(1, min(cap, 8 if DEVICE == "cuda" else 32, ncpu - 1))
    n_cached = len([f for f in os.listdir(cd) if f.endswith(".npz") and ".tmp." not in f])
    print("[dnn] %d months | inputs %d | device %s | %d worker processes (1 torch thread each, %d logical cpus) | torch %s | cache entries %d | start offset %d" % (
        len(tasks), m, DEVICE, workers, ncpu, torch.__version__, n_cached, off), flush=True)
    outs = []
    diags = []
    t1 = time.time()
    done = 0
    n_tr = 0
    n_ca = 0
    tr_secs = []
    with ProcessPoolExecutor(max_workers=workers, initializer=load_panel, initargs=(panel_path, cd)) as ex:
        for k, out, diag in ex.map(run_task, tasks, chunksize=1):
            diags.append(diag)
            if out is not None:
                outs.append(out)
            done += 1
            if diag["source"] == "train":
                n_tr += 1
                tr_secs.append(diag["secs"])
            elif diag["source"] == "cache":
                n_ca += 1
            if done <= 3 or done % 12 == 0 or done == len(tasks):
                rem = len(tasks) - done
                eta = (rem * (sum(tr_secs) / len(tr_secs)) / workers / 60.0) if tr_secs else 0.0
                print("[dnn]   %d/%d months | trained %d cache %d | n_train %d | steps %d | loss %.4f | %.1f min elapsed | eta %.0f min if all remaining train" % (
                    done, len(tasks), n_tr, n_ca, diag["n_train"], diag["steps"], diag["last_loss"], (time.time() - t1) / 60.0, eta), flush=True)
    if not outs:
        print("[dnn] no predictions produced", flush=True)
        sys.exit(4)
    pred = pd.concat(outs, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(pred, preserve_index=False), pred_path)
    dg = pd.DataFrame(diags)
## >>> DT_ZONE py_main_diag orig=695-695
    for kk in ("raw_rho10", "raw_rho50", "raw_rho90", "raw_cov10", "raw_cov90",
               "rea_rho10", "rea_rho50", "rea_rho90", "rea_cov10", "rea_cov90", "cross_rate", "steps"):
        dg["pc_" + kk] = pc[kk]
    dg["pc_pass"] = bool(pc["pass"])
    dg["code_version"] = CODE_VERSION
    dg["cache_key"] = dg["cache_key"].fillna("").astype(str) if "cache_key" in dg.columns else ""
## <<< DT_ZONE py_main_diag
    dg["workers"] = workers
    dg["ncpu"] = ncpu
    dg["n_inputs"] = m
    pq.write_table(pa.Table.from_pandas(dg, preserve_index=False), diag_path)
    print("[dnn] done: %d prediction rows over %d months (trained %d, cache %d) in %.1f min" % (
        len(pred), len(outs), n_tr, n_ca, (time.time() - t1) / 60.0), flush=True)


if __name__ == "__main__":
    main()
)---"
.script <- file.path(.RD, "dnn_rolling.py")
writeLines(.PY_SRC, .script, useBytes = TRUE)
.old_utf8 <- Sys.getenv("PYTHONUTF8", unset = NA)
Sys.setenv(PYTHONUTF8 = "1")
cat(sprintf("%s DNN5 학습·예측 시작 — %d개월 · 입력 %d · 워커 상한 %d · 캐시 %s · %.1f분 경과\n", .TAG, nrow(.SCH), length(.FEATS), .N_WORKERS_CAP, .CD,
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
.py_args <- c(shQuote(.script), shQuote(.RD), shQuote(.CD), as.character(.N_WORKERS_CAP))
.rc <- system2(.PY, .py_args, stdout = "", stderr = "")
if (is.na(.old_utf8)) Sys.unsetenv("PYTHONUTF8") else Sys.setenv(PYTHONUTF8 = .old_utf8)
.rc <- if (is.null(.rc) || length(.rc) == 0L) 1L else as.integer(.rc)
if (.rc != 0L) stop(sprintf("%s 파이썬 DNN 러너 실패(rc %d) — 위 로그 확인(양성 대조 실패 = rc 3 · 예측 0 = rc 4 · PIT 단언 실패 = 트레이스백)", .TAG, .rc))
if (!file.exists(.pred_path) || !file.exists(.diag_path)) stop(sprintf("%s 파이썬 산출 파케이 부재", .TAG))
.PR <- as.data.table(read_parquet(.pred_path))
.DG <- as.data.table(read_parquet(.diag_path))
## >>> DT_ZONE r_read orig=721-721
.PR[, pred_i := as.integer(pred_i)]; .PR[, Ticker := as.character(Ticker)]
.DT_QCOLS <- c("q10", "q50", "q90", "q10_raw", "q50_raw", "q90_raw")
if (!all(.DT_QCOLS %in% names(.PR)))
  stop(sprintf("%s 파이썬 예측 열 부재: %s", .TAG, paste(setdiff(.DT_QCOLS, names(.PR)), collapse = ", ")))
.PR[, (.DT_QCOLS) := lapply(.SD, as.numeric), .SDcols = .DT_QCOLS]
## <<< DT_ZONE r_read
for (cc in c("k", "pred_i", "u_i", "smin_i", "smax_i", "n_train", "n_days", "max_lab_i", "n_pred", "steps", "skipped", "n_inputs"))
  .DG[, (cc) := as.integer(get(cc))]
.DG[, source := as.character(source)]; .DG[, device := as.character(device)]

# ── PIT 재단언 (R 측 · 파이썬을 신뢰하지 않는다) ──
.bad <- .DG[n_train > 0L & !(max_lab_i <= u_i & u_i <= pred_i & smin_i >= 1L & (smax_i - smin_i + 1L) == .N_TRAIN & n_days <= .N_TRAIN)]
if (nrow(.bad) > 0L)
  stop(sprintf("%s PIT/창 단언 실패 %d개월 (예: k %d · max_lab_i %d · u_i %d · pred_i %d · n_days %d)", .TAG, nrow(.bad),
               .bad$k[1], .bad$max_lab_i[1], .bad$u_i[1], .bad$pred_i[1], .bad$n_days[1]))
## >>> DT_ZONE r_pc_assert orig=731-732
# 양성 대조 재단언(R 측 · 파이썬을 신뢰하지 않는다) — 날 머리 · 재배열 머리 모두 Spearman > 문턱 ∧ 적중률 대역 안(설계 §3.3)
.DT_PC_RHO <- c("pc_raw_rho10", "pc_raw_rho50", "pc_raw_rho90", "pc_rea_rho10", "pc_rea_rho50", "pc_rea_rho90")
.DT_PC_C10 <- c("pc_raw_cov10", "pc_rea_cov10"); .DT_PC_C90 <- c("pc_raw_cov90", "pc_rea_cov90")
if (!all(c(.DT_PC_RHO, .DT_PC_C10, .DT_PC_C90, "pc_pass", "code_version", "cache_key", "cross_rate") %in% names(.DG)))
  stop(sprintf("%s 파이썬 양성 대조 · 판본 기록 열 부재", .TAG))
.pc <- vapply(c(.DT_PC_RHO, .DT_PC_C10, .DT_PC_C90), function(cc) as.numeric(.DG[[cc]][1]), numeric(1))
.pc_ok <- all(is.finite(.pc)) && all(.pc[.DT_PC_RHO] > .DT_PC_RHO_MIN) &&
  all(.pc[.DT_PC_C10] >= .DT_PC_COV10[1] & .pc[.DT_PC_C10] <= .DT_PC_COV10[2]) &&
  all(.pc[.DT_PC_C90] >= .DT_PC_COV90[1] & .pc[.DT_PC_C90] <= .DT_PC_COV90[2]) && isTRUE(as.logical(.DG$pc_pass[1]))
if (!.pc_ok) stop(sprintf("%s 파이썬 양성 대조 미기록/미달(%s)", .TAG, paste(sprintf("%s %.3f", names(.pc), .pc), collapse = " · ")))
.rho <- as.numeric(.pc[["pc_rea_rho50"]])
.DT_CODE_VERSION <- sub('^CODE_VERSION = "([^"]+)".*$', "\\1",
                        grep('^CODE_VERSION = "', strsplit(.PY_SRC, "\n", fixed = TRUE)[[1]], value = TRUE)[1])
if (!identical(unique(as.character(.DG$code_version)), .DT_CODE_VERSION))
  stop(sprintf("%s 파이썬 판본 기록 %s ≠ 스크립트 CODE_VERSION %s", .TAG, paste(unique(as.character(.DG$code_version)), collapse = ","), .DT_CODE_VERSION))
## <<< DT_ZONE r_pc_assert
if (!identical(as.integer(.DG$n_inputs[1]), length(.FEATS))) stop(sprintf("%s 파이썬 입력 차원 %d ≠ 특성 %d", .TAG, as.integer(.DG$n_inputs[1]), length(.FEATS)))
.DG[.CAL, on = .(pred_i = di), Date := i.Date]
## >>> DT_ZONE r_rule orig=+734
# ── DT 규칙 블록(설계 §3.4 · §4) — 신호일 d 의 적격 집합 U_d = 그날 예측 행 중 세 분위가 유한한 행. s · s_perm · s_sigma · s_hist(+ σ · h 원값)는
#    규칙과 무관하게 매 실행 계산한다(예측표에 싣는다). 점수 = .dt_score(.DT_RULE) → 아래 원본 조립이 FACTORS 로 옮긴다(Score 비유한 = 후보 제외).
.PR[.CAL, on = .(pred_i = di), Date := i.Date]
.PR[, dt_ok := is.finite(q10) & is.finite(q50) & is.finite(q90) & !is.na(Date)]
if (.PR[dt_ok == TRUE, any(q10 > q50 | q50 > q90)]) stop(sprintf("%s 재배열 뒤 분위 순서 위반", .TAG))
setorder(.PR, pred_i, Ticker)
.PR[.DT_SIG, on = .(Ticker, pred_i), sigma252 := i.sigma252]
.PR[.DT_HIST, on = .(Ticker, pred_i), h_hist := i.h_hist]
.PR[, c("s", "s_perm", "s_sigma", "s_hist", "Score") := NA_real_]
.PR[dt_ok == TRUE, s := q50 - q10]
.PR[dt_ok == TRUE, s_perm := .dt_perm_s(Date, Ticker, s, .START, .DT_PERM_SEED)]
.PR[dt_ok == TRUE, s_sigma := .dt_match_s(Date, Ticker, s, sigma252)]
.PR[dt_ok == TRUE, s_hist := .dt_match_s(Date, Ticker, s, h_hist)]                  # D^H 짝(기록 · 평가 입력 — 점수 규칙은 쓰지 않는다)
.PR[dt_ok == TRUE, Score := .dt_score(.DT_RULE, Date, q10, q50, s_perm, s_sigma, .DT_VETO_SHARE)]
.DT_n_ok <- .PR[dt_ok == TRUE, .N]; .DT_n_na <- .PR[dt_ok == TRUE, sum(!is.finite(Score))]
cat(sprintf("%s 규칙 %s: 적격 %d행(%d개월 · 분위 비유한 제외 %d행) · 점수 NA(거부) %d행(%.1f%%) · σ 결측 %d행 · h 결측 %d행(둘 다 그날 s 중앙값) · 순열 주 시드 %d · s 중앙 %.4f · 재배열 전 교차율 달 평균 %.4f\n",
            .TAG, .DT_RULE, .DT_n_ok, uniqueN(.PR[dt_ok == TRUE, Date]), .PR[dt_ok == FALSE, .N], .DT_n_na, 100 * .DT_n_na / max(1L, .DT_n_ok),
            .PR[dt_ok == TRUE, sum(!is.finite(sigma252))], .PR[dt_ok == TRUE, sum(!is.finite(h_hist))], .DT_PERM_SEED, .PR[dt_ok == TRUE, stats::median(s)],
            mean(.DG$cross_rate, na.rm = TRUE)))
# 예측표(설계 §7.2) — _work/qpred/<CODE_VERSION md5 8자>_<데이터 지문 8자>.parquet · 원자적 쓰기(임시 파일 → 교체) · 실현 라벨 없음(평가가 RAWDATA 로 재도출).
#   데이터 지문 = 이 실행의 예측 · 짝을 정한 입력의 md5: 시작일 · 신호일 목록 · 달별 내용 주소 캐시 키(파이썬 cache_key = 특징 X · 표적 y · 예측 행 Xp ·
#   예측 종목 · 일정 · 시드 · 모델 상수의 sha1 · k 순) · σ 표 · h 표(종목 · 신호일 · 값의 %.17g) · 짝 상수(순열 주 시드 · σ · h 창 · 하한 · τ). 셀 기저 캐시
#   (rf_base_cache.R)의 데이터 도장과 같은 성격 — 입력이 바뀌면 다른 이름이 된다. 규칙과 무관하다(7 엔진이 같은 이름 · 같은 내용을 쓴다 — 이미 있으면
#   내용을 대조하고 쓰지 않는다 · 같은 이름에 다른 내용이면 비결정이므로 멈춘다).
.DT_Q <- .PR[dt_ok == TRUE, .(Date, Ticker, q10, q50, q90, q10_raw, q50_raw, q90_raw, s_perm, s_sigma, sigma252, s_hist, h_hist)]
setorder(.DT_Q, Date, Ticker)
.DT_keys <- .DG[n_train > 0L & n_pred > 0L & nzchar(as.character(cache_key))][order(k), as.character(cache_key)]
.DT_sig_md5 <- .dt_md5_str(.DT_SIG[order(pred_i, Ticker), sprintf("%s|%d|%.17g", Ticker, pred_i, sigma252)])
.DT_hist_md5 <- .dt_md5_str(.DT_HIST[order(pred_i, Ticker), sprintf("%s|%d|%.17g", Ticker, pred_i, h_hist)])
.DT_FP <- .dt_md5_str(c(paste0("start=", format(.START)), paste0("dates=", paste(format(sort(unique(.SCH$Date))), collapse = ",")),
                        paste0("keys=", paste(.DT_keys, collapse = ",")), paste0("sigma=", .DT_sig_md5), paste0("hist=", .DT_hist_md5),
                        paste0("pair_consts=", .DT_PERM_SEED, ",", .DT_SIGMA_WIN, ",", .DT_SIGMA_MIN, ",", .DT_HIST_WIN, ",", .DT_HIST_MIN, ",", .DT_HIST_TAU)))
.DT_QP <- file.path(.QD, sprintf("%s_%s.parquet", substr(.dt_md5_str(.DT_CODE_VERSION), 1L, 8L), substr(.DT_FP, 1L, 8L)))
.dt_qread <- function(p) if (!file.exists(p)) NULL else                          # mmap 금지 — Windows 에서 매핑이 남으면 다른 실행의 교체가 실패한다(오류 1224)
  tryCatch(as.data.table(read_parquet(p, mmap = FALSE)), error = function(e) NULL)
.dt_qsame <- function(a) !is.null(a) && isTRUE(all.equal(a, .DT_Q, check.attributes = FALSE, tolerance = 0))
.DT_old <- .dt_qread(.DT_QP)
if (!is.null(.DT_old)) {
  if (!.dt_qsame(.DT_old))
    stop(sprintf("%s 예측표 %s 가 이미 있는데 내용이 다르다(같은 데이터 지문 · 다른 내용 = 비결정 — 중단)", .TAG, basename(.DT_QP)))
  .DT_qp_how <- "기존 파일과 내용 일치(쓰기 생략)"
} else {
  .DT_tmp <- sprintf("%s.%d.tmp", .DT_QP, Sys.getpid())
  write_parquet(.DT_Q, .DT_tmp)
  if (file.rename(.DT_tmp, .DT_QP)) .DT_qp_how <- "새로 씀(임시 파일 → 교체)" else {
    unlink(.DT_tmp)                                                              # 동시에 끝난 다른 엔진이 같은 이름을 먼저 썼을 수 있다 — 내용이 같으면 통과
    if (!.dt_qsame(.dt_qread(.DT_QP))) stop(sprintf("%s 예측표 교체 실패: %s", .TAG, .DT_QP))
    .DT_qp_how <- "교체 실패 · 다른 실행이 같은 내용을 먼저 씀(내용 일치)"
  }
}
cat(sprintf("[DT qpred] path=%s rows=%d months=%d\n", .DT_QP, nrow(.DT_Q), uniqueN(.DT_Q$Date)))
cat(sprintf("%s 예측표 %s · CODE_VERSION %s · 데이터 지문 %s(달 키 %d · σ 표 md5 %s · h 표 md5 %s)\n", .TAG, .DT_qp_how, .DT_CODE_VERSION, .DT_FP,
            length(.DT_keys), .DT_sig_md5, .DT_hist_md5))
rm(.DT_old)
## <<< DT_ZONE r_rule

# =============================================================================
# 10. 조립 — 5분위 롱숏 EW (engine_direct) + FACTORS · 검산 · 요약(성과 수치 없음 — 등급은 계약이 낸다)  ★changed(11)
# =============================================================================
.PR[.CAL, on = .(pred_i = di), Date := i.Date]
FACTORS <- .PR[is.finite(Score) & !is.na(Date), .(Date, Ticker, Score)]
if (nrow(FACTORS) == 0L) stop(sprintf("%s 예측 행 0", .TAG))
.rows_p <- list(); .diag_p <- list(); .n_skip <- 0L
for (d in sort(unique(FACTORS$Date))) {
  d <- as.Date(d, origin = "1970-01-01")
  md <- FACTORS[Date == d]
  N <- nrow(md); nq <- N %/% .QUINT
  if (N < .MIN_N || nq < 2L) { .n_skip <- .n_skip + 1L; next }
  o_hi <- order(-md$Score, md$Ticker)                       # 내림차순 · 동률 = 종목코드(선택 규칙 · 결정론)
  o_lo <- order(md$Score, md$Ticker)
  hi <- md$Ticker[o_hi[seq_len(nq)]]; lo <- md$Ticker[o_lo[seq_len(nq)]]
  if (length(intersect(hi, lo)) > 0L) stop(sprintf("%s %s 롱·숏 교차 — N %d nq %d", .TAG, as.character(d), N, nq))
  .rows_p[[length(.rows_p) + 1L]] <- data.table(
    Date = d, Ticker = c(hi, lo),
    Weight = c(rep(1 / nq, nq), rep(-1 / nq, nq)),           # 5분위 내 EW · 롱 Σ=+1 / 숏 Σ=−1
    Leg = rep(c("long", "short"), c(nq, nq)))
  .diag_p[[length(.diag_p) + 1L]] <- data.table(Date = d, N = N, nq = nq)
}
if (length(.rows_p) == 0L) stop(sprintf("%s PORTFOLIO 행 0 (건너뛴 달 %d)", .TAG, .n_skip))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
setorder(PORTFOLIO, Date, Leg, Ticker)
setorder(FACTORS, Date, Ticker)
.chk <- PORTFOLIO[, .(gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0])), by = Date]
.badw <- .chk[abs(gl - 1) > 1e-9 | abs(gs - 1) > 1e-9]
if (nrow(.badw) > 0L) stop(sprintf("%s 다리 총노출 검산 실패 %d건 (예: %s gL %.6f / gS %.6f)", .TAG, nrow(.badw),
                                   as.character(.badw$Date[1L]), .badw$gl[1L], .badw$gs[1L]))
if (anyDuplicated(PORTFOLIO, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s PORTFOLIO (Date,Ticker) 중복", .TAG))
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L)   stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (max(FACTORS$Date) > max(RAWDATA$Date)) stop(sprintf("%s 시그널일이 RAWDATA 범위 밖", .TAG))
.DP <- rbindlist(.diag_p, use.names = TRUE)
.DGo <- .DG[n_train > 0L]
.n_src <- .DGo[, .N, by = source]
.src_txt <- paste(sprintf("%s %d", .n_src$source, .n_src$N), collapse = " · ")
.dev_txt <- paste(unique(.DGo$device), collapse = ",")
.tr_secs <- .DGo[source == "train", secs]
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
## >>> DT_ZONE r_log_adapted orig=776-777
cat(sprintf("%s DT 분위 표적(P2R05 설계 §3 — 원본 기전 그대로: 33→31 팩터(No.32·33 = 설비투자 지급액 data_gap) 유니버스 안 순위/최대순위 0~1 · No.19~31 = 논문 인쇄 식 · 월말 산출 · 표적 = 5일 수익(시가 t+1→종가 t+5) 순위 재척도 · DNN5 300-300-150-150-50 dropout 50-50-30-30-10%% ReLU BN Adam batch 500 epoch 20 trunc-normal sqrt(2/M) · 최신 1,000일 학습집합 · 5영업일 갱신 격자 / 처치: 출력 3(τ 0.1·0.5·0.9) · 합성 pinball · 행별 재배열): 규칙 %s · 유니버스 = 적재 멤버십 플래그(측정 축 주입) · 유동성 스크린 없음 · 월말 시그널만 발행(하네스 월간 집행) · 팩터 DB 미사용 · FACTORS Score = 규칙 점수(비유한 = 후보 제외) · PORTFOLIO = 원본 5분위 롱숏 조립(셀 엔진은 쓰지 않는다)\n",
            .TAG, .DT_RULE))
## <<< DT_ZONE r_log_adapted
cat(sprintf("  발행 %d개월 (%s ~ %s) · 건너뛴 달 %d · 예측 N %d~%d(중앙 %d) · 5분위 %d~%d종/다리 · 학습행 %d~%d(중앙 %d) · 학습일수 %d~%d · 갱신일 지연 0~%d거래일\n",
            nrow(.DP), as.character(min(.DP$Date)), as.character(max(.DP$Date)), .n_skip,
            min(.DP$N), max(.DP$N), as.integer(median(.DP$N)), min(.DP$nq), max(.DP$nq),
            min(.DGo$n_train), max(.DGo$n_train), as.integer(median(.DGo$n_train)), min(.DGo$n_days), max(.DGo$n_days),
            max(.DGo$pred_i - .DGo$u_i)))
## >>> DT_ZONE r_log_dnn orig=783-785
cat(sprintf("  DNN(분위): 양성 대조 재배열 머리 spearman q10 %.3f · q50 %.3f · q90 %.3f · 적중 q10 %.3f · q90 %.3f(날 머리 적중 q10 %.3f · q90 %.3f) · 입력 %d · 예측 출처 [%s] · 장치 [%s] · 워커 %d/논리 CPU %d · 스텝/월 %d~%d · 건너뛴 미니배치(행<2) 합 %d · 최종 학습 pinball 중앙 %.4f · 재배열 전 교차율 달 중앙 %.4f(최대 %.4f) · 학습한 달 월당 %.0f초 · 총 %.1f분\n",
            .pc[["pc_rea_rho10"]], .pc[["pc_rea_rho50"]], .pc[["pc_rea_rho90"]], .pc[["pc_rea_cov10"]], .pc[["pc_rea_cov90"]], .pc[["pc_raw_cov10"]], .pc[["pc_raw_cov90"]],
            as.integer(.DG$n_inputs[1]), .src_txt, .dev_txt, as.integer(.DG$workers[1]), as.integer(.DG$ncpu[1]), min(.DGo$steps), max(.DGo$steps), sum(.DGo$skipped),
            median(.DGo$last_loss), median(.DGo$cross_rate), max(.DGo$cross_rate), if (length(.tr_secs)) median(.tr_secs) else 0, .mins))
## <<< DT_ZONE r_log_dnn
cat(sprintf("  PORTFOLIO %d행 · FACTORS %d행 · 러너 사양 = FIDELITY 파일 portfolio_spec(engine_direct · ew · monthly) · commission_paper = null(논문 비용 무명시 → gross 병기)\n",
            nrow(PORTFOLIO), nrow(FACTORS)))
rm(.P, .PR, .DG, .SCH, .SCHO, .CAL, .me, .ME_CAL); gc(verbose = FALSE)

PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
## >>> DT_ZONE r_cleanup orig=+791
# DT: 이 실행의 패널 작업본(전 종목 위생 유니버스 ≈ 1.37 GB · OneDrive 폴더 안) 삭제 — 엔진 7개 × 패널이 위 48시간 정리 전에 쌓이지 않게
#   (48시간 정리 규칙은 그대로 둔다 · 스케줄 · 스크립트 · 예측 · diag 작업본은 남긴다).
unlink(.panel_path)
cat(sprintf("%s 패널 작업본 삭제 %s — %s\n", .TAG, if (file.exists(.panel_path)) "실패(48시간 정리에 맡긴다)" else "완료", .panel_path))
rm(.DT_SIG, .DT_HIST, .DT_U, .DT_Q, .DT_PTS); gc(verbose = FALSE)
## <<< DT_ZONE r_cleanup
