# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_1403_8125_2002_069   (1판 · 2026-09-17 · 재료 6편 중 [A]·[B] 두 편을 쓴다)
#
#   [A] Abe · Nakagawa, "Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment
#       Management" (arXiv:2002.06975)  https://arxiv.org/abs/2002.06975
#       전문 = r.jina.ai/https://arxiv.org/pdf/2002.06975 (본 세션 직접 판독 · 2020 논문이라 html 판 없음)
#       → **풀(pool)을 정한다**: Table 1 33 팩터(KR 31) → 유니버스 안 순위/최대순위 → DNN5(Table 2) → 5일 뒤 수익 순위 예측
#         → 논문 전략 (i) 'buys the top quintile (i.e., one-fifth) scores of the stocks with equal weight' 의 **상위 5분위**.
#   [B] Choi · Choi · Kang, "Maximum drawdown, recovery, and momentum" (arXiv:1403.8125)  https://arxiv.org/abs/1403.8125
#       전문 = arxiv.org/html/1403.8125v1 (본 세션 직접 판독 2회)
#       → **풀 안의 순위를 정한다**: 6개월 일별 로그가격 경로의 CM = R_I + 2·R_II + R_III = C − MDD (Table 1 (1,2,1) ·
#         'Cumulative return-MDD' · 월간 KOSPI 200 최우수 규칙) 로 5분위 안에서 줄 세워 상위 25종(고정 축) 이 뽑힌다.
#   [C] Polimenis (arXiv:2007.08115) · [D] Borri-Chetverikov-Liu-Tsyvinski (arXiv:2404.08129) ·
#   [E] Pinchuk (arXiv:2301.09173) · [F] André-Coqueret (arXiv:2011.05381) — **이 판에 코드가 없다** (FIDELITY changed ③).
#
# ★fidelity = COMBINATION. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다).
#
# =============================================================================
# 한 문장 요약 — 무엇이 맞물리는가
# =============================================================================
#   [A] 의 DNN 은 5일 뒤 수익의 **횡단면 순위**를 예측한다 — 입력의 가장 긴 창이 60거래일(No.8)이고 표적이 5일이라
#   신호의 지평이 짧다. 그런데 하네스는 월간 집행이라 그 점수를 **1개월** 들고 간다(3판 changed(3)). 논문이 포트폴리오를
#   'top quintile' 로 정의하는 이유가 여기 있다 — 분위 안의 미세 순위는 잡음이다. [B] 는 그 빈 자리를 메운다:
#   6개월 경로의 C − MDD 는 [A] 가 보지 않는 중간 지평(6개월)의 지속성과 **낙폭 기하**를 담고, KOSPI 200 월간에서
#   단순 누적수익(C)보다 강한 모멘텀('smaller maximum drawdown gives stronger momentum')과 낮은 위험을 냈다.
#   그래서 이 판은 두 신호를 평균하지 않는다 — **순차 조건 정렬**이다:
#
#       풀  Q_d  = { i : DNN 점수가 적격 횡단면 상위 floor(N/5) }            ([A] 전략 (i) 의 5분위 · 그대로)
#       순위    = CM_i = C_i − MDD_i (6개월 일별 로그가격 경로)   for i ∈ Q_d    ([B] Table 1 CM · 그대로)
#       보유    = Q_d 안 CM 상위 25종 EW (고정 축 n_max · [A][B] 둘 다 EW)
#
#   저장소의 실측 계보에서 rank-Z 평균 5판(최고 0.766)과 CM 계열 결합 4판(0.69~0.79 · GFC/2022 동조 낙폭)은 전부
#   **약한 신호끼리 스코어를 산술로 섞은** 판이었다. 이 판은 스코어 층에 평균·가중·rank-Z 0건 — [A] 가 '누가 후보인가' 를,
#   [B] 가 '후보 중 누구인가' 를 정한다. 반증 조건은 FIDELITY changed ② 와 §11 의 F1~F4 가 인쇄한다.
#
# =============================================================================
# 구조 — 이 파일의 §0~§9 는 RP_AUTO_2002_06975/engine.R 3판(감사 통과 판 · 2026-09-13)과 **같은 산술**이다
# =============================================================================
#   ▸ 특성 31 · 순위 재척도 · 표적 · DNN5 · 학습창 [u−1004, u−5] · 5영업일 갱신 격자 · 월말 시그널 · 시드 — 전부 동일.
#     파이썬 학습 수치 경로(fit_predict · 하이퍼파라미터 · CODE_VERSION rev3 · 캐시 키)는 바이트 동일하게 유지한다 —
#     그래서 3판이 학습해 둔 월별 예측(_work/cache/<sha1>.npz · 입력 내용 주소)을 **읽기 전용 형제 디렉터리**로 재사용한다.
#     같은 입력에 같은 알고리즘을 적용한 결과를 다시 계산하지 않을 뿐이며 PIT 와 무관하다(입력이 한 바이트라도 다르면
#     키가 달라 이 디렉터리의 캐시에 새로 학습한다 · 형제 디렉터리에는 쓰지 않는다).
#   ▸ 3판과 다른 곳: §1 작업 디렉터리·읽기전용 캐시 목록 · §4 끝 adv20(t−1) 산출 · §7 끝 .PX/.ME_ROWS 추출 ·
#     §9 파이썬 cache_read/main 의 읽기전용 디렉터리 순회(수치 경로 불변) · **§10·§11 신설** · 3판 §10(5분위 롱숏 PORTFOLIO) 제거.
#
# 산출: FACTORS(Date, Ticker, Score) — Date = 각 달력월 마지막 거래일 · 행 = 그날 적격(K200∪KQ150 ∧ adv20(t−1) ≥ 2e8) ∧
#       DNN 예측 보유 종목 **전부**(강화 레인의 팩터 축이 살아 있도록 넓은 패널) · Score 는 3계층 사전식:
#         5분위 ∧ CM 유한  → 2 + rank01(CM | 5분위)  ∈ (2, 3]     (러너 top-25 는 여기서 나온다)
#         5분위 ∧ CM 결측  → 1.5                                    (경로 정의역 밖 · 5분위 자격은 유지)
#         5분위 밖         → rank01(DNN | 5분위 밖) ∈ (0, 1]         (진단·강화용 순서 · 보유에 닿지 않는다)
#       러너 사양 = FIDELITY portfolio_spec (top_n_long · ew · monthly · n_long 25 · n_max 25). PORTFOLIO 는 내지 않는다.
#
# PIT(C1~C15) 구조 보장: (a) DNN 블록 = 3판 그대로 — 시그널일 t 의 특성은 t 이하 데이터, 학습 표적은 갱신일 u 까지 실현된
#   집합(파이썬 단언 + R 재단언). (b) CM 창 = (me[k−6], f] · 종점 f = 시그널 월말 종가 · 집행은 러너가 익 거래일 →
#   창 ∩ 보유월 = ∅. (c) 유동성 = 20거래일 평균 거래대금의 shift(1) → 종점 f−1(C10). (d) 멤버십 = f 당일 플래그(C6).
#   (e) 전 표본 통계 0건(순위·5분위·CM 전부 그날 횡단면·그 창 안) · 음수 shift·lead·미래 인덱싱 0건 · 팩터 DB 미접근(C15) ·
#   부호 조작 0건(방향 = [A] 점수 큰 값 롱 · [B] 오름차순 승자 롱 — 둘 다 논문 선언 · C13).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.TAG <- "[COMBO_DNN_CM]"
.t0 <- Sys.time()
.REQ <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.HAS_OPEN <- "Open" %in% names(RAWDATA)

# =============================================================================
# 0. 상수 — [A] 논문 명시값 + [A] 3판이 신고한 규약(동일) + [B] 논문 명시값 + 고정 축 + 진단 상수
# =============================================================================
# ▸ [A] 2002.06975 — 3판과 동일
.RET_K    <- c(1L, 2L, 3L, 5L, 10L, 20L, 40L, 60L)   # Table 1 No.1~8: k일 전 대비 수익
.TV_LONG  <- 60L                                     # Table 1 No.9: 60일 평균 거래대금
.TV_SHORT <- c(5L, 10L, 20L)                         # Table 1 No.10~12: 5/10/20일 평균 ÷ 60일 평균
.CONS_K   <- c(5L, 10L, 20L)                         # Table 1 No.13~18: 5/10/20일 전 대비 전망 변화
.HORIZON  <- 5L                                      # 표적 = p^c_{t+5}/p^o_{t+1} − 1
.N_TRAIN  <- 1000L                                   # "latest N = 1,000 days" 학습집합
.UPD_EVERY <- 5L                                     # "updated every five business days"
.QUINT    <- 5L                                      # 'top quintile (i.e., one-fifth)' — [A] 전략 (i) 의 풀
.START    <- as.Date("2005-01-01")                   # 고정 축 — 이 날 이후 시그널만 발행
.ANCHOR   <- as.Date("2001-01-01")                   # 5영업일 갱신 격자 앵커(첫 거래일 ≥ 이 날) — 3판 changed(3)
.GRID_FROM <- as.Date("2000-06-01")                  # 격자 시작(학습창 1,000일 + 특성 창 60일 선행) — 3판 changed(12)
.CONS_ROLL <- 7L                                     # 컨센서스 관측 → 거래일 격자 캐리 상한(달력일) — 3판 changed(7)
.FUND_ROLL <- 456L                                   # 연간 회계 usable 이후 캐리 상한(달력일 ≈ 15개월) — 3판 changed(8)
.MIN_N    <- 10L                                     # 5분위 정의역(다리당 ≥ 2) — 3판 changed(11)
.SEED_BASE <- 20020697L                              # 시드 = 논문 번호(임의 상수) + 월 인덱스 — 3판 changed(6)
.N_WORKERS_CAP <- 32L                                # 워커 상한 — 3판 changed(15)
.FEATS <- sprintf("x%02d", 1:31)                     # 엔진 열 xNN = Table 1 No.NN (No.32·33 = data_gap) — 3판 changed(9)
.FEAT_NAMES <- c("ret_1d", "ret_2d", "ret_3d", "ret_5d", "ret_10d", "ret_20d", "ret_40d", "ret_60d",
                 "tv_60d", "tv_5d/60d", "tv_10d/60d", "tv_20d/60d",
                 "op_fcst_chg_5d", "op_fcst_chg_10d", "op_fcst_chg_20d",
                 "tp_chg_5d", "tp_chg_10d", "tp_chg_20d",
                 "B/P", "E/P", "DY", "S/P", "CF/P", "ROE", "ROA(op)", "ROIC", "accruals(paper sign)", "asset_turnover",
                 "current_ratio", "equity_ratio", "asset_growth")
stopifnot(length(.FEATS) == length(.FEAT_NAMES))
.FUND_FEATS <- .FEATS[19:31]                         # 논문: 'No. 19-33 are calculated on a monthly basis (at the end of month)'
# ▸ [B] 1403.8125 — 논문 명시값
.W_CM     <- c(1, 2, 1)                              # Table 1 CM = (R_I, R_II, R_III) 가중 = C − MDD ('Cumulative return-MDD')
.FORM_M   <- 6L                                      # §3.2 "6 months (weeks) of estimation period" — 월말 격자 6스텝
# ▸ 고정 축(지시) — 두 논문에 없다 (FIDELITY changed ③ 신고)
.LIQ      <- 2e8                                     # adv20(t−1) 하한 KRW
.LIQ_WIN  <- 20L                                     # 유동성 창(거래일) · 뒤의 shift(1) 이 종점을 f−1 로 만든다
.NTOP     <- 25L                                     # 고정 축 종목수 — 진단(겹침)의 n 이기도 하다
# ▸ 진단 전용 상수 — Score·자격에 쓰이지 않는다 (FIDELITY changed ③)
.DIAG_MIN <- 5L                                      # 순위상관을 계산하는 최소 쌍 수
.OVL_MAX  <- 0.80                                    # F1: nested top-25 vs DNN top-25 겹침 중앙 ≥ 0.80 = 재라벨(설계 실패)
.RHO_MAX  <- 0.90                                    # F3: 5분위 안 |rho(DNN, CM)| 중앙 ≥ 0.90 = 2단 정렬 잉여(설계 실패)
.QCM_SHORT_MAX <- 0.50                               # F2: 5분위 안 CM 유한 종목 < 25 인 달의 비율 ≥ 0.50 = 2단 정렬 대부분 무작동

# =============================================================================
# 1. 루트·캐시·파이썬 해석 · 실행별 작업 디렉터리 · 읽기 전용 형제 캐시 (r-portability: 표지 파일 검증 · env= 미사용)
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
.WD    <- file.path(.ROOT, "04_Research", "strategies", "RP_AUTO_COMBO_combo_1403_8125_2002_069", "_work")
.RUN_ID <- sprintf("run_%s_%d", format(Sys.time(), "%Y%m%d_%H%M%S"), Sys.getpid())
.RD    <- file.path(.WD, .RUN_ID)                    # 이 실행의 작업본(패널·스케줄·스크립트·예측·진단)
.CD    <- file.path(.WD, "cache")                    # 이 디렉터리의 예측 캐시(쓰기 가능 · 월 단위 · 입력 내용 주소)
dir.create(.RD, recursive = TRUE, showWarnings = FALSE)
dir.create(.CD, recursive = TRUE, showWarnings = FALSE)
# 읽기 전용 형제 캐시 — [A] 충실구현 3판이 같은 산술·같은 키로 학습해 둔 월별 예측. 있으면 읽기만 한다(쓰기 0).
.CD_RO <- file.path(.ROOT, "04_Research", "strategies", "RP_AUTO_2002_06975", "_work", "cache")
.CD_RO <- .CD_RO[dir.exists(.CD_RO)]
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
.n_ro <- if (length(.CD_RO)) length(list.files(.CD_RO, pattern = "\\.npz$")) else 0L
cat(sprintf("%s root %s · cache %s · python %s (torch %s) · 작업본 %s · 정리한 옛 작업본 %d · 읽기전용 형제 캐시 %s (%d 항목)\n",
            .TAG, .ROOT, .CACHE, .PY, paste(.probe, collapse = " "), .RUN_ID, .n_clean,
            if (length(.CD_RO)) .CD_RO else "없음", .n_ro))

# =============================================================================
# 2. 헬퍼 + 양성 대조 (구현 결함 = 중단 · 조용한 F 방지) — [A] 3판의 6종 + [B] 경로 검산 + 조립 검산
# =============================================================================
# [A] 전처리: "ranking each input value in ascending order by stock universe at each day and then dividing by
#   the maximum rank value" — 동률 = 평균 순위 · 결측 = 0.5(중앙값 대치 · 논문 미명시 · 3판 changed(10))
.rank01 <- function(x) {
  ok <- is.finite(x); out <- rep(0.5, length(x)); n <- sum(ok)
  if (n >= 1L) { r <- frank(x[ok], ties.method = "average"); out[ok] <- r / max(r) }
  out
}
.sdiv <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)      # 양(+) 분모만
.chg  <- function(v, k) {                                                                  # (F_t − F_{t−k}) / |F_{t−k}|
  l <- shift(v, k)
  fifelse(is.finite(v) & is.finite(l) & abs(l) > 0, (v - l) / abs(l), NA_real_)
}
.nz <- function(x) fifelse(is.finite(x), x, 0)                                             # 차입금 결측 = 0
# No.26 NOPAT = 영업이익 × (1 − τ) · τ = 법인세비용/세전이익 (세전이익 > 0 · [0,1] 절단) · 세전이익 ≤ 0 이면 τ = 0
.nopat <- function(op, tax, pretax) {
  tau <- fifelse(is.finite(pretax) & pretax > 0 & is.finite(tax), pmin(pmax(tax / pretax, 0), 1), NA_real_)
  tau <- fifelse(is.finite(pretax) & pretax <= 0, 0, tau)
  fifelse(is.finite(op) & is.finite(tau), op * (1 - tau), NA_real_)
}
# No.27 논문 그대로: −(Changes in Current Assets and Liabilities − Depreciation)/Total Assets
.accr <- function(ca, ca_p, cl, cl_p, dep, ta) {
  ok <- is.finite(ca) & is.finite(ca_p) & is.finite(cl) & is.finite(cl_p) & is.finite(dep) & is.finite(ta) & ta > 0
  fifelse(ok, -(((ca - ca_p) - (cl - cl_p)) - dep) / ta, NA_real_)
}
# [B] 형성창 로그가격 경로 → C / MDD / 3-국면 (창 내부 통계만 · C1). RP_AUTO_1403_8125/engine.R(감사 faithful)의 함수와 동일.
#   cl = 창 안 그 종목의 거래일 종가(Date 오름차순). 경로는 미처리(절단·winsorize 0) · cummax 는 t≤τ 포함형(단조 상승 = MDD 0) ·
#   n < 2 = 정의역 밖. 식(1)(2): MDD = 로그가격 경로의 peak→trough 최악 낙폭 · R = trough→말일 · C = PP − MDD + R.
.path_stats <- function(cl) {
  n <- length(cl)
  if (n < 2L)
    return(list(C = NA_real_, MDD = NA_real_, RI = NA_real_, RII = NA_real_, RIII = NA_real_, nobs = n))
  path <- log(cl) - log(cl[1L])                 # 상대 로그가격 경로 (미처리)
  dd   <- path - cummax(path)                   # <= 0
  ts   <- which.min(dd)                         # trough t* (동값이면 최초)
  tp   <- which.max(path[seq_len(ts)])          # trough 이전(포함) peak
  list(C = path[n], MDD = -dd[ts], RI = path[tp], RII = path[ts] - path[tp], RIII = path[n] - path[ts], nobs = n)
}
.med <- function(x) { x <- as.numeric(x); x <- x[is.finite(x)]; if (length(x)) median(x) else NA_real_ }

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
  want <- d$Close[6] / d$Open[2] - 1
  if (!isTRUE(all.equal(d$y_raw[1], want)) || !identical(d$lab_i[1], 6L)) stop(sprintf("%s 표적 정렬 검산 실패", .TAG))
  if (!all(is.na(d$y_raw[8:12]))) stop(sprintf("%s 표적 말단 결측 검산 실패", .TAG))
  ch <- .chg(c(10, 11, 12, -6, 0, 3), 2L)
  if (!isTRUE(all.equal(ch, c(NA, NA, 0.2, (-6 - 11) / 11, -1, (3 + 6) / 6)))) stop(sprintf("%s 전망 변화율 검산 실패", .TAG))
  ac <- .accr(c(120, 120, 120), c(100, NA, 100), c(60, 60, 60), c(50, 50, 50), c(5, 5, NA), c(200, 200, 200))
  if (!isTRUE(all.equal(ac, c(-0.025, NA, NA)))) stop(sprintf("%s accruals 검산 실패", .TAG))
  np <- .nopat(c(100, 100, 100, 100, 100), c(20, 5, 100, 10, NA), c(80, -10, 80, 0, 80))
  if (!isTRUE(all.equal(np, c(75, 100, 0, 100, NA)))) stop(sprintf("%s NOPAT 검산 실패", .TAG))
  # [B] 경로 검산: 로그가격 경로 (0, .1, .05, −.1, 0, .2) → trough = 4번째(−0.2 낙폭) · peak = 2번째(0.1)
  #   C = 0.2 · MDD = 0.2 · R_I = 0.1 · R_II = −0.2 · R_III = 0.3 · CM = R_I + 2R_II + R_III = 0 = C − MDD
  ps <- .path_stats(exp(c(0, 0.1, 0.05, -0.1, 0, 0.2)))
  cm <- .W_CM[1] * ps$RI + .W_CM[2] * ps$RII + .W_CM[3] * ps$RIII
  if (!isTRUE(all.equal(c(ps$C, ps$MDD, ps$RI, ps$RII, ps$RIII, cm), c(0.2, 0.2, 0.1, -0.2, 0.3, 0))))
    stop(sprintf("%s [B] 경로 검산 실패", .TAG))
  if (!isTRUE(all.equal(cm, ps$C - ps$MDD))) stop(sprintf("%s [B] CM = C − MDD 항등 검산 실패", .TAG))
  if (!is.na(.path_stats(c(100))$C)) stop(sprintf("%s [B] 정의역(n<2) 검산 실패", .TAG))
  mono <- .path_stats(c(1, 2, 3))                                  # 단조 상승 = MDD 0 · trough = 첫 관측 → R_I = R_II = 0 · R_III = C
  if (!isTRUE(all.equal(c(mono$MDD, mono$RI, mono$RII, mono$RIII), c(0, 0, 0, mono$C)))) stop(sprintf("%s [B] 단조 경로 검산 실패", .TAG))
  cat(sprintf("%s 양성 대조 통과 — [A] 순위 재척도 · k일 수익 · 표적 정렬 · 전망 변화율 · accruals · NOPAT / [B] 경로 3국면 · CM = C − MDD · 정의역 · 단조 경로\n", .TAG))
})

# =============================================================================
# 3. 거래일 격자 × 적격 이력 종목 (RAWDATA 비파괴) — [A] 3판 §3 그대로
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
.rd[, Open := as.numeric(Open)]; .rd[!is.finite(Open) | Open <= 0, Open := NA_real_]          # 0·결측 시가 = 센티널 → NA
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
            if (.HAS_OPEN) "있음" else "없음(표적 진입가 = 종가 대체)",
            .G[Date == max(.cal), sum(MEM)]))

# =============================================================================
# 4. 가격·거래량 특성 (Table 1 No.1~12) + 표적 — [A] 3판 §4 그대로 + 고정 축 유동성 adv20(t−1) 신설
# =============================================================================
.G[, (.FEATS[1:8]) := lapply(.RET_K, function(k) Close / shift(Close, k) - 1), by = Ticker]
.G[, dv := fifelse(is.finite(Vol) & Vol > 0, Vol * Close, NA_real_)]                           # 거래대금 KRW ≈ 거래량 × 수정종가
.G[, tv60 := frollmean(dv, .TV_LONG, na.rm = TRUE, hasNA = TRUE), by = Ticker]
.G[, c("tv5", "tv10", "tv20") := lapply(.TV_SHORT, function(k) frollmean(dv, k, na.rm = TRUE, hasNA = TRUE)), by = Ticker]
.G[, x09 := fifelse(is.finite(tv60) & tv60 > 0, tv60, NA_real_)]
.G[, x10 := .sdiv(tv5, tv60)]; .G[, x11 := .sdiv(tv10, tv60)]; .G[, x12 := .sdiv(tv20, tv60)]
# 고정 축 유동성(논문 밖 · FIDELITY changed ③): 20거래일 평균 거래대금 후 shift(1) → 종점 t−1 (C10).
#   격자 위에서 재므로 거래가 없는 날(결측·0 거래량)은 거래대금 0 으로 평균에 들어간다(보수적 · 다른 엔진의 자기 행 기준과 다름 · 신고).
.G[, tv0 := fifelse(is.finite(dv), dv, 0)]
.G[, adv20_l1 := shift(frollmean(tv0, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.G[, c("dv", "tv60", "tv5", "tv10", "tv20", "tv0") := NULL]
# 표적: 행 r 에서 Close[r]/Open[r−4] − 1 = 집합 s = r−5 의 5일 수익(진입 = s+1 시가 · 청산 = s+5 종가 · 실현일 = r).
.G[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]
if (!.HAS_OPEN) .G[, lab_end := Close / shift(Close, .HORIZON) - 1, by = Ticker]              # 시가 열 부재 시만
.LAB <- .G[, .(s_date = shift(Date, .HORIZON), lab_i = di, y_raw = lab_end), by = Ticker]
.LAB <- .LAB[!is.na(s_date) & is.finite(y_raw)]
.G[.LAB, on = .(Ticker, Date = s_date), c("y_raw", "lab_i") := .(i.y_raw, i.lab_i)]
rm(.LAB); .G[, lab_end := NULL]
.n_ext_d <- .G[MEM == TRUE & is.finite(x01), sum(abs(x01) > 0.5)]
.n_ext_y <- .G[MEM == TRUE & is.finite(y_raw), sum(abs(y_raw) > 1)]
cat(sprintf("%s 가격 특성 8 + 거래대금 특성 4 + 표적 + adv20(t−1) 완료 · 적격행 |1일 수익|>50%% %d건 · |5일 표적|>100%% %d건 (값 절단 없음)\n",
            .TAG, .n_ext_d, .n_ext_y))

# =============================================================================
# 5. 컨센서스 특성 (Table 1 No.13~18) — QuantiWise 영업이익 FY1 · 목표주가 — [A] 3판 §5 그대로
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
# 6. 스케줄 — 월말 시그널 · 5영업일 갱신 격자 · 학습창 [u−1004, u−5] — [A] 3판 §6 그대로
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
# 7. 회계 특성 (Table 1 No.19~31) — 논문 §3.1 인쇄 정의 · 월말 산출 · 그 달 안 캐리 — [A] 3판 §7 그대로
#    + 끝에서 §10·§11 이 쓸 종가 경로(.PX)·월말 행(.ME_ROWS)을 .G 에서 추출
# =============================================================================
.ME_CAL <- .CAL[MI < max(MI), .(me_di = max(di)), by = MI]                                    # 완결 달력월의 마지막 거래일
setorder(.ME_CAL, me_di)
.ME_CAL[, me_key := me_di]
.CAL[, me_di := .ME_CAL[.CAL[, .(di)], on = .(me_key = di), roll = Inf, x.me_di]]             # me(t) ≤ t · 첫 월말 이전 = NA
local({
  ok <- .CAL[!is.na(me_di), all(me_di <= di) &&
               all(fifelse(di %in% .ME_CAL$me_di, me_di == di, .CAL$MI[me_di] == MI - 1L))]
  if (!isTRUE(ok)) stop(sprintf("%s 월말 사상 me(t) 검산 실패", .TAG))
})
.ME <- .G[di %in% .ME_CAL$me_di, .(Ticker, me_di = di, Date, Size)]                           # 격자 전 종목 × 월말 (시총 = 그 월말)
.P <- .G[MEM == TRUE & di >= .PANEL_FROM_I]
# ── §10·§11 재료 (DNN 패널과 무관 · 3판에 없던 두 추출) ──
.PX <- .G[is.finite(Close), .(Ticker, di, Close)]                                             # 관측 종가 경로(격자 전 종목) — [B] CM 창의 원천
setkey(.PX, di, Ticker)
.ME_ROWS <- .G[di %in% .SCH$pred_i, .(Ticker, di, MEM, adv20_l1)]                             # 시그널 월말 당일 행 — 멤버십·유동성(t−1)
setkey(.ME_ROWS, di, Ticker)
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
# (a) 유량 항목 — DART 행 = 사업연도 합계 그대로 · XLSX 행 = 분기 관측 → 연간화(형식 판별: 매출 4분기 합 ÷ 12월 분기값 중앙값 > 3 = 단일분기)
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
# (b) 시점 항목 — 12월 말 값
.bs <- .fm[Item %in% .BS_ITEMS & MM == 12L, .(Ticker, FY, Item, Value)]
.FA <- dcast(rbind(.fl, .bs), Ticker + FY ~ Item, value.var = "Value")
for (it in .FUND_ITEMS) if (!it %in% names(.FA)) .FA[, (it) := NA_real_]
.n_ni_x <- .FA[!is.finite(NetIncome) & is.finite(PretaxIncome) & is.finite(TaxExpense), .N]
.FA[!is.finite(NetIncome) & is.finite(PretaxIncome) & is.finite(TaxExpense), NetIncome := PretaxIncome - TaxExpense]   # XLSX 에 순이익 항목 없음
setorder(.FA, Ticker, FY)
.FA[, FY_prev := shift(FY), by = Ticker]
.FA[, TA_prev := shift(TotalAssets), by = Ticker]
.FA[, CA_prev := shift(CurrentAssets), by = Ticker]
.FA[, CL_prev := shift(CurrentLiab), by = Ticker]
.FA[!(is.finite(FY_prev) & FY_prev == FY - 1L), c("TA_prev", "CA_prev", "CL_prev") := NA_real_]             # 직전 연도만
# ── 논문 §3.1 인쇄 정의(축자) → 구현 ──
.FA[, nopat := .nopat(OperatingProfit, TaxExpense, PretaxIncome)]                                            # 'Net Operating Profits After Tax'
.FA[, invcap := fifelse(is.finite(TotalEquity), .nz(ShortTermBorr) + .nz(LongTermBorr) + TotalEquity, NA_real_)]   # 'Debt + Net Assets'
.FA[, f_roe  := .sdiv(NetIncome, TotalEquity)]                                                               # No.24 Net Profits/Net Assets
.FA[, f_roa  := .sdiv(OperatingProfit, TotalAssets)]                                                         # No.25 Net Operating Profits/Total Assets
.FA[, f_roic := .sdiv(nopat, invcap)]                                                                        # No.26 NOPAT/(Debt + Net Assets)
.FA[, f_acc  := .accr(CurrentAssets, CA_prev, CurrentLiab, CL_prev, DepAmort, TotalAssets)]                  # No.27 −(ΔCA − ΔCL − Dep)/TA
.FA[, f_at   := .sdiv(Revenue, TotalAssets)]                                                                 # No.28 Sales/Total Assets
.FA[, f_cr   := .sdiv(CurrentAssets, CurrentLiab)]                                                           # No.29 Current Assets/Current Liabilities
.FA[, f_er   := .sdiv(TotalEquity, TotalAssets)]                                                             # No.30 Net Assets/Total Assets
.FA[, f_ag   := fifelse(is.finite(TotalAssets) & is.finite(TA_prev) & TA_prev > 0, TotalAssets / TA_prev - 1, NA_real_)]   # No.31 Change Rate of Total Assets
.FA[, f_div  := fifelse(is.finite(Dividends), abs(Dividends), NA_real_)]                                     # No.21 분자 'Dividends' = 배당금지급액(CF)
.FA[, usable := as.Date(sprintf("%d-03-31", FY + 1L))]                                                       # C4: 사업연도 익년 3/31
.fcols <- c("FY", "TotalEquity", "NetIncome", "f_div", "Revenue", "OperatingCF",
            "f_roe", "f_roa", "f_roic", "f_acc", "f_at", "f_cr", "f_er", "f_ag")
.n_fa <- nrow(.FA); .n_fa_tk <- uniqueN(.FA$Ticker); .fy_rng <- range(.FA$FY)
.dep_cov <- .FA[, mean(is.finite(DepAmort))]
.FA <- .FA[, c("Ticker", "usable", .fcols), with = FALSE]
setorder(.FA, Ticker, usable)
# 월말 me 에서: usable ≤ me 인 최신 FY(캐리 ≤ 456일) × 시총_me → No.19~31
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
# 8. 순위 재척도 (그날 적격 집합 안 · 특성 31 + 표적) → 패널 파케이(실행별 작업본) — [A] 3판 §8 그대로
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

# =============================================================================
# 9. DNN5 — 파이썬(venv torch) 서브프로세스. [A] 3판 rev3 와 **학습 수치 경로·캐시 키 바이트 동일**.
#    이 판의 유일한 변경 = cache_read 가 읽기 전용 디렉터리 목록(argv[4:])을 순회한다(쓰기는 자기 캐시에만).
#    CODE_VERSION 은 rev3 그대로다 — 그 문자열은 fit_predict 의 수치 경로를 가리키고 그것이 바뀌지 않았다.
# =============================================================================
.PY_SRC <- r"---(
# dnn_rolling.py - RP_AUTO_COMBO_combo_1403_8125_2002_069 (Abe & Nakagawa 2020, Table 2 DNN5).
# Numerics, hyper-parameters and cache key are byte-identical to RP_AUTO_2002_06975 rev3 (audited edition);
# only cache_read walks extra read-only directories. Written by engine.R on every run; do not edit.
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

CODE_VERSION = "RP_AUTO_2002_06975/dnn_rolling/rev3"   # part of every cache key; bump only if fit_predict numerics change
HIDDEN = [300, 300, 150, 150, 50]          # Table 2 DNN5 hidden layers
DROPOUT = [0.50, 0.50, 0.30, 0.30, 0.10]   # Table 2 DNN5 dropout rates
EPOCHS = 20                                # Table 2 DNN5 epochs
BATCH = 500                                # paper: mini-batch size 500
LR = 1e-3                                  # not stated -> TensorFlow Adam default
BN_EPS = 1e-3                              # not stated -> TensorFlow batch_normalization default
BN_MOMENTUM = 0.01                         # TensorFlow decay 0.99 == torch momentum 0.01
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
P = {}             # per-process panel arrays (filled by load_panel in every worker)
CACHE_DIR = None   # writable cache (this strategy directory)
RO_DIRS = []       # read-only sibling caches (never written)


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
        layers.append(self.linear(prev, 1))
        self.net = nn.Sequential(*layers)

    @staticmethod
    def linear(fan_in, fan_out):
        lin = nn.Linear(fan_in, fan_out)
        sd = math.sqrt(2.0 / fan_in)       # paper: tf.truncated_normal, mean 0, std sqrt(2/M), M = fan-in
        nn.init.trunc_normal_(lin.weight, mean=0.0, std=sd, a=-2.0 * sd, b=2.0 * sd)
        nn.init.zeros_(lin.bias)
        return lin

    def forward(self, x):
        return self.net(x).squeeze(1)


def fit_predict(X, y, Xp, seed):
    # same seed use, same init order, same cpu-generated batch order on any device
    torch.manual_seed(seed)
    gen = torch.Generator()
    gen.manual_seed(seed)
    model = DNN(X.shape[1]).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    lossf = nn.MSELoss()
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
            loss = lossf(model(Xt[idx]), yt[idx])
            loss.backward()
            opt.step()
            steps += 1
            last = float(loss.item())
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(Xp).to(DEVICE)).cpu().numpy()
    return pred, steps, skipped, last


def feature_names(schema_names):
    return [c for c in schema_names if c[0] == "x" and c[1:].isdigit()]


def load_panel(path, cache_dir, ro_dirs):
    global P, CACHE_DIR, RO_DIRS
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
    RO_DIRS = list(ro_dirs)


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
    h.update(spec.encode("ascii"))
    h.update(X.tobytes())
    h.update(y.tobytes())
    h.update(Xp.tobytes())
    h.update("|".join(tk.tolist()).encode("utf-8"))
    return h.hexdigest()


def cache_read(key):
    # writable cache first, then the read-only sibling caches (same key = same inputs, same numerics)
    for d in [CACHE_DIR] + RO_DIRS:
        p = os.path.join(d, key + ".npz")
        if not os.path.exists(p):
            continue
        try:
            z = np.load(p, allow_pickle=False)
            return dict(score=z["score"].astype(np.float64), tk=z["tk"].astype(str), steps=int(z["steps"]),
                        skipped=int(z["skipped"]), last_loss=float(z["last_loss"]), secs=float(z["secs"]),
                        device=str(z["device"]), source=str(z["source"]), cache_dir=d)
        except Exception:
            continue
    return None


def cache_write(key, score, tk, steps, skipped, last_loss, secs, device, source):
    p = os.path.join(CACHE_DIR, key + ".npz")
    tmp = os.path.join(CACHE_DIR, "%s.%d.tmp.npz" % (key, os.getpid()))
    np.savez(tmp, score=np.asarray(score, dtype=np.float64), tk=np.asarray(tk, dtype=str),
             steps=np.int64(steps), skipped=np.int64(skipped), last_loss=np.float64(last_loss),
             secs=np.float64(secs), device=np.str_(device), source=np.str_(source))
    os.replace(tmp, p)


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
    if hit is not None and (len(hit["score"]) != len(tk) or not np.array_equal(hit["tk"], tk)):
        hit = None
    if hit is not None and hit["cache_dir"] != CACHE_DIR:
        src = "cache_ro"
    if hit is None:
        t0 = time.time()
        pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
        secs = time.time() - t0
        cache_write(key, pred, tk, steps, skipped, last, secs, DEVICE, "train")
        hit = dict(score=pred.astype(np.float64), steps=steps, skipped=skipped, last_loss=last, secs=secs, device=DEVICE)
        src = "train"
    out = pd.DataFrame({"pred_i": np.repeat(pred_i, len(tk)), "Ticker": tk, "Score": hit["score"]})
    diag.update(steps=hit["steps"], skipped=hit["skipped"], last_loss=hit["last_loss"], secs=hit["secs"],
                source=src, device=hit["device"])
    return k, out, diag


def synthetic_check(seed, m):
    # positive control: a known rank-target structure must be learned by the same fit_predict routine
    rng = np.random.default_rng(seed)
    n, npred = 20000, 5000
    X = rng.uniform(0.0, 1.0, size=(n, m)).astype(np.float32)
    w = rng.normal(size=m).astype(np.float32)
    f = X @ w + 0.5 * np.sin(6.0 * X[:, 0])
    y = (pd.Series(f).rank(method="average") / n).to_numpy(dtype=np.float32)
    Xp = rng.uniform(0.0, 1.0, size=(npred, m)).astype(np.float32)
    fp = Xp @ w + 0.5 * np.sin(6.0 * Xp[:, 0])
    pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
    rho = float(pd.Series(pred).corr(pd.Series(fp), method="spearman"))
    return rho, steps


def count_npz(d):
    try:
        return len([f for f in os.listdir(d) if f.endswith(".npz") and ".tmp." not in f])
    except Exception:
        return 0


def main():
    rd = sys.argv[1]
    cd = sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 32
    ro = [d for d in sys.argv[4:] if os.path.isdir(d) and os.path.abspath(d) != os.path.abspath(cd)]
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
    rho, steps = synthetic_check(int(sched["seed"].iloc[0]) + 7, m)
    print("[dnn] positive control (synthetic rank target, %d inputs): spearman %.3f after %d steps (%.0fs, device %s)" % (m, rho, steps, time.time() - t0, DEVICE), flush=True)
    if not rho > 0.8:
        print("[dnn] positive control FAILED - the training loop does not learn a known structure; aborting", flush=True)
        sys.exit(3)
    tasks = [tuple(int(v) for v in row) for row in sched[["k", "pred_i", "u_i", "smin_i", "smax_i", "seed"]].to_numpy()]
    # processing order rotated by a per-run offset: concurrent runs (lane re-spawn) start on different months and
    # meet through the shared cache instead of training the same months twice; every month's result is order-independent
    off = int(hashlib.sha1(os.path.basename(rd).encode("utf-8")).hexdigest(), 16) % len(tasks)
    tasks = tasks[off:] + tasks[:off]
    ncpu = os.cpu_count() or 2
    workers = max(1, min(cap, 8 if DEVICE == "cuda" else 32, ncpu - 1))
    n_cached = count_npz(cd)
    n_ro = sum(count_npz(d) for d in ro)
    print("[dnn] %d months | inputs %d | device %s | %d worker processes (1 torch thread each, %d logical cpus) | torch %s | cache entries %d (+%d in %d read-only sibling dirs) | start offset %d" % (
        len(tasks), m, DEVICE, workers, ncpu, torch.__version__, n_cached, n_ro, len(ro), off), flush=True)
    outs = []
    diags = []
    t1 = time.time()
    done = 0
    n_tr = 0
    n_ca = 0
    n_ro_hit = 0
    tr_secs = []
    with ProcessPoolExecutor(max_workers=workers, initializer=load_panel, initargs=(panel_path, cd, ro)) as ex:
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
            elif diag["source"] == "cache_ro":
                n_ro_hit += 1
            if done <= 3 or done % 12 == 0 or done == len(tasks):
                rem = len(tasks) - done
                eta = (rem * (sum(tr_secs) / len(tr_secs)) / workers / 60.0) if tr_secs else 0.0
                print("[dnn]   %d/%d months | trained %d cache %d sibling-cache %d | n_train %d | steps %d | loss %.4f | %.1f min elapsed | eta %.0f min if all remaining train" % (
                    done, len(tasks), n_tr, n_ca, n_ro_hit, diag["n_train"], diag["steps"], diag["last_loss"], (time.time() - t1) / 60.0, eta), flush=True)
    if not outs:
        print("[dnn] no predictions produced", flush=True)
        sys.exit(4)
    pred = pd.concat(outs, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(pred, preserve_index=False), pred_path)
    dg = pd.DataFrame(diags)
    dg["synthetic_rho"] = rho
    dg["workers"] = workers
    dg["ncpu"] = ncpu
    dg["n_inputs"] = m
    pq.write_table(pa.Table.from_pandas(dg, preserve_index=False), diag_path)
    print("[dnn] done: %d prediction rows over %d months (trained %d, cache %d, sibling-cache %d) in %.1f min" % (
        len(pred), len(outs), n_tr, n_ca, n_ro_hit, (time.time() - t1) / 60.0), flush=True)


if __name__ == "__main__":
    main()
)---"
.script <- file.path(.RD, "dnn_rolling.py")
writeLines(.PY_SRC, .script, useBytes = TRUE)
.old_utf8 <- Sys.getenv("PYTHONUTF8", unset = NA)
Sys.setenv(PYTHONUTF8 = "1")
cat(sprintf("%s DNN5 학습·예측 시작 — %d개월 · 입력 %d · 워커 상한 %d · 캐시 %s · 읽기전용 형제 캐시 %d개 · %.1f분 경과\n", .TAG, nrow(.SCH), length(.FEATS), .N_WORKERS_CAP, .CD,
            length(.CD_RO), as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
.py_args <- c(shQuote(.script), shQuote(.RD), shQuote(.CD), as.character(.N_WORKERS_CAP),
              if (length(.CD_RO)) shQuote(.CD_RO))
.rc <- system2(.PY, .py_args, stdout = "", stderr = "")
if (is.na(.old_utf8)) Sys.unsetenv("PYTHONUTF8") else Sys.setenv(PYTHONUTF8 = .old_utf8)
.rc <- if (is.null(.rc) || length(.rc) == 0L) 1L else as.integer(.rc)
if (.rc != 0L) stop(sprintf("%s 파이썬 DNN 러너 실패(rc %d) — 위 로그 확인(양성 대조 실패 = rc 3 · 예측 0 = rc 4 · PIT 단언 실패 = 트레이스백)", .TAG, .rc))
if (!file.exists(.pred_path) || !file.exists(.diag_path)) stop(sprintf("%s 파이썬 산출 파케이 부재", .TAG))
.PR <- as.data.table(read_parquet(.pred_path))
.DG <- as.data.table(read_parquet(.diag_path))
.PR[, pred_i := as.integer(pred_i)]; .PR[, Ticker := as.character(Ticker)]; .PR[, Score := as.numeric(Score)]
for (cc in c("k", "pred_i", "u_i", "smin_i", "smax_i", "n_train", "n_days", "max_lab_i", "n_pred", "steps", "skipped", "n_inputs"))
  .DG[, (cc) := as.integer(get(cc))]
.DG[, source := as.character(source)]; .DG[, device := as.character(device)]

# ── PIT 재단언 (R 측 · 파이썬을 신뢰하지 않는다) — [A] 3판 그대로 ──
.bad <- .DG[n_train > 0L & !(max_lab_i <= u_i & u_i <= pred_i & smin_i >= 1L & (smax_i - smin_i + 1L) == .N_TRAIN & n_days <= .N_TRAIN)]
if (nrow(.bad) > 0L)
  stop(sprintf("%s PIT/창 단언 실패 %d개월 (예: k %d · max_lab_i %d · u_i %d · pred_i %d · n_days %d)", .TAG, nrow(.bad),
               .bad$k[1], .bad$max_lab_i[1], .bad$u_i[1], .bad$pred_i[1], .bad$n_days[1]))
.rho <- as.numeric(.DG$synthetic_rho[1])
if (!is.finite(.rho) || .rho <= 0.8) stop(sprintf("%s 파이썬 양성 대조 미기록/미달(rho %s)", .TAG, as.character(.rho)))
if (!identical(as.integer(.DG$n_inputs[1]), length(.FEATS))) stop(sprintf("%s 파이썬 입력 차원 %d ≠ 특성 %d", .TAG, as.integer(.DG$n_inputs[1]), length(.FEATS)))
.DG[.CAL, on = .(pred_i = di), Date := i.Date]
.PR[.CAL, on = .(pred_i = di), Date := i.Date]
.PR <- .PR[is.finite(Score) & !is.na(Date)]
if (nrow(.PR) == 0L) stop(sprintf("%s 예측 행 0", .TAG))
.DGo <- .DG[n_train > 0L]
.n_src <- .DGo[, .N, by = source]
.src_txt <- paste(sprintf("%s %d", .n_src$source, .n_src$N), collapse = " · ")
.dev_txt <- paste(unique(.DGo$device), collapse = ",")
.tr_secs <- .DGo[source == "train", secs]
cat(sprintf("%s DNN: 양성 대조 spearman %.3f · 입력 %d · 예측 출처 [%s] · 장치 [%s] · 워커 %d/논리 CPU %d · 스텝/월 %d~%d · 건너뛴 미니배치 합 %d · 최종 학습 MSE 중앙 %.4f · 학습한 달 월당 %.0f초 · 예측 %d행/%d개월 · %.1f분 경과\n",
            .TAG, .rho, as.integer(.DG$n_inputs[1]), .src_txt, .dev_txt, as.integer(.DG$workers[1]), as.integer(.DG$ncpu[1]),
            min(.DGo$steps), max(.DGo$steps), sum(.DGo$skipped), median(.DGo$last_loss),
            if (length(.tr_secs)) median(.tr_secs) else 0, nrow(.PR), uniqueN(.PR$pred_i),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
rm(.P); gc(verbose = FALSE)

# =============================================================================
# 10. [B] CM — 시그널 월말 f 마다 (me[k−6], f] 6개월 일별 종가 로그가격 경로 → C · MDD · 3국면 → CM = C − MDD
#     대상 = f 당일 적격(멤버십 ∧ adv20(t−1) ≥ 2e8) ∧ DNN 예측 보유 종목 전부(진단이 전체 CM 순위도 쓴다)
#     ★창 종점 = f 종가(시그널 시점 기지) · 집행 = 러너가 익 거래일 → 창 ∩ 보유월 = ∅ (C2·C3). 형성일 간 상태 이월 0건(C1).
# =============================================================================
.ELIG <- .ME_ROWS[MEM == TRUE & is.finite(adv20_l1) & adv20_l1 >= .LIQ, .(pred_i = di, Ticker)]
.n_mem_by <- .ME_ROWS[MEM == TRUE, .(n_mem = .N), by = .(pred_i = di)]
.CM <- vector("list", nrow(.SCH))
for (r in seq_len(nrow(.SCH))) {
  hi <- .SCH$pred_i[r]
  j  <- match(hi, .ME_CAL$me_di)
  if (is.na(j) || j <= .FORM_M) next                                     # me[k−6] 필요 ([B] 워밍업 — 격자 2000-06 부터라 2005-01 에 이미 충족)
  lo <- .ME_CAL$me_di[j - .FORM_M]
  tk <- .ELIG[pred_i == hi, Ticker]
  if (!length(tk)) next
  w  <- .PX[di > lo & di <= hi & Ticker %chin% tk]                       # (me[k−6], f] · 종점 = f
  if (!nrow(w)) next
  setorder(w, Ticker, di)                                                 # 그룹 내 Date 오름차순 보장
  st <- w[, .path_stats(Close), by = Ticker]
  st[, cm := .W_CM[1] * RI + .W_CM[2] * RII + .W_CM[3] * RIII]           # CM = C − MDD (승자 = 큰 값 롱 · [B] 오름차순의 최상위 그룹)
  st[, pred_i := hi]
  st[, n_win := as.integer(sum(.CAL$di > lo & .CAL$di <= hi))]           # 창의 거래일 수(진단 · 커버리지 = nobs / n_win · 스크린 아님)
  .CM[[r]] <- st[, .(pred_i, Ticker, cm, C6 = C, MDD6 = MDD, n6 = nobs, n_win)]
}
.CM <- rbindlist(Filter(Negate(is.null), .CM), use.names = TRUE)
if (!nrow(.CM)) stop(sprintf("%s [B] CM 0행 — 격자/월말/적격 확인", .TAG))
setkey(.CM, pred_i, Ticker)
cat(sprintf("%s [B] CM: %d행 · %d개월 · 종목/월 중앙 %d · 창 거래일 중앙 %d · 창 커버리지 중앙 %.2f · CM 유한 %.1f%% · 창내 MDD 중앙 %.1f%% · C 중앙 %.1f%%\n",
            .TAG, nrow(.CM), uniqueN(.CM$pred_i), as.integer(.med(.CM[, .N, by = pred_i]$N)), as.integer(.med(.CM$n_win)),
            .med(.CM$n6 / .CM$n_win), 100 * mean(is.finite(.CM$cm)), 100 * .med(.CM$MDD6), 100 * .med(.CM$C6)))

# =============================================================================
# 11. 조립 — 순차 조건 정렬: [A] 5분위(풀) → [B] CM 순위(풀 안) → 3계층 사전식 Score → FACTORS(적격 전원) · 진단 F1~F4
#     러너가 top-25 EW 월간을 만든다(portfolio_spec). 성과 수치는 여기서 내지 않는다 — 등급은 계약이 낸다.
# =============================================================================
local({                                                                    # 조립 규칙 검산 — 합성 횡단면 12종 (N=12 → 5분위 2종)
  md <- data.table(Ticker = sprintf("S%02d", 1:12), dnn = 12:1 / 12)       # S01 이 DNN 최고
  md[, q := seq_len(.N) <= (.N %/% .QUINT)]                                # S01·S02 = 풀
  md[, cm := c(-0.1, 0.4, NA, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9)]   # 풀 안 CM: S02 > S01 · 풀 밖 CM 은 무관
  md[, r := 0]
  md[q == TRUE & is.finite(cm), r := .rank01(cm)]
  md[q == FALSE, r := .rank01(dnn)]
  md[, Score := fifelse(q & is.finite(cm), 2 + r, fifelse(q, 1.5, r))]
  o <- md[order(-Score, Ticker), Ticker]
  if (!identical(o[1:3], c("S02", "S01", "S03"))) stop(sprintf("%s 조립 검산 실패 — 풀 안은 CM 순 · 풀 밖은 DNN 순이어야 한다", .TAG))
  if (!(md[Ticker == "S02", Score] > 2 && md[Ticker == "S01", Score] > 2 && md[Ticker == "S03", Score] <= 1)) stop(sprintf("%s 조립 계층 검산 실패", .TAG))
  md2 <- copy(md); md2[Ticker == "S01", cm := NA_real_]
  md2[, r := 0]; md2[q == TRUE & is.finite(cm), r := .rank01(cm)]; md2[q == FALSE, r := .rank01(dnn)]
  md2[, Score := fifelse(q & is.finite(cm), 2 + r, fifelse(q, 1.5, r))]
  o2 <- md2[order(-Score, Ticker), Ticker]
  if (!identical(o2[1:3], c("S02", "S01", "S03"))) stop(sprintf("%s 조립 검산 실패 — CM 결측 풀 종목은 풀 밖보다 위여야 한다", .TAG))
  cat(sprintf("%s 조립 검산 통과 — 5분위 안 CM 순 > CM 결측 5분위 > 5분위 밖 DNN 순\n", .TAG))
})

.rows <- list(); .LOG <- list(); .n_skip <- 0L; .n_short_q <- 0L
for (r in seq_len(nrow(.SCH))) {
  hi <- .SCH$pred_i[r]; d <- .SCH$Date[r]
  md <- .PR[pred_i == hi, .(Ticker, dnn = Score)]
  tk <- .ELIG[pred_i == hi, Ticker]
  md <- md[Ticker %chin% tk]                                               # 적격 = 멤버십(f) ∧ adv20(f−1) ≥ 2e8 ∧ 예측 보유
  N <- nrow(md); nq <- N %/% .QUINT
  if (N < .MIN_N || nq < 2L) { .n_skip <- .n_skip + 1L; next }            # 5분위 정의역([A] 3판과 같은 하한)
  setorder(md, -dnn, Ticker)                                               # [A] 점수 내림차순 · 동률 = 종목코드(결정론)
  md[, q := seq_len(.N) <= nq]                                             # 풀 = 'top quintile (i.e., one-fifth)' = floor(N/5)
  md[, c("cm", "C6", "MDD6", "n6") := .(NA_real_, NA_real_, NA_real_, NA_integer_)]
  cmh <- .CM[pred_i == hi]
  if (nrow(cmh)) md[cmh, on = "Ticker", c("cm", "C6", "MDD6", "n6") := .(i.cm, i.C6, i.MDD6, i.n6)]
  md[, r := 0]
  md[q == TRUE & is.finite(cm), r := .rank01(cm)]                           # [B] 순위 — 풀 안에서만
  md[q == FALSE, r := .rank01(dnn)]                                         # 풀 밖 = DNN 순(보유에 닿지 않는다 · 강화·진단용)
  md[, Score := fifelse(q & is.finite(cm), 2 + r, fifelse(q, 1.5, r))]
  md[, Date := d]
  .rows[[r]] <- md[, .(Date, Ticker, Score, dnn, cm, q)]

  # ── 진단 (전부 이 형성일 단면·창 내부 통계 — 미래참조 0 · 성과 아님) ──
  n_q_cm <- md[q == TRUE, sum(is.finite(cm))]
  if (n_q_cm < .NTOP) .n_short_q <- .n_short_q + 1L
  nt <- min(.NTOP, N)
  top_nest <- md[order(-Score, Ticker), Ticker][seq_len(nt)]
  top_dnn  <- md[order(-dnn, Ticker), Ticker][seq_len(nt)]
  cm_all   <- md[is.finite(cm)][order(-cm, Ticker), Ticker]
  top_cm   <- cm_all[seq_len(min(nt, length(cm_all)))]
  qq <- md[q == TRUE & is.finite(cm)]
  rho_q <- if (nrow(qq) >= .DIAG_MIN) suppressWarnings(cor(qq$dnn, qq$cm, method = "spearman")) else NA_real_
  pos_nest <- which(md$Ticker %chin% top_nest)                             # md 는 DNN 내림차순 → 위치 = DNN 순위(1 = 최고) — nested 25 가 5분위 어디까지 내려가나
  n_mem_h <- .n_mem_by[pred_i == hi, n_mem]
  n_mem_h <- if (length(n_mem_h)) as.integer(n_mem_h[1]) else NA_integer_
  .LOG[[r]] <- data.table(
    Date = d, N = N, nq = nq, n_q_cm = n_q_cm, n_mem = n_mem_h, n_liq = length(tk),
    ovl_dnn = length(intersect(top_nest, top_dnn)) / nt,
    ovl_cm  = if (length(top_cm)) length(intersect(top_nest, top_cm)) / nt else NA_real_,
    rho_q = rho_q, dnn_pos_med = .med(pos_nest), dnn_pos_max = if (length(pos_nest)) max(pos_nest) else NA_integer_,
    mdd_nest = .med(md[Ticker %chin% top_nest, MDD6]), mdd_dnn = .med(md[Ticker %chin% top_dnn, MDD6]), mdd_all = .med(md$MDD6),
    c_nest = .med(md[Ticker %chin% top_nest, C6]), c_dnn = .med(md[Ticker %chin% top_dnn, C6]),
    cm_nest = .med(md[Ticker %chin% top_nest, cm]), cm_dnn = .med(md[Ticker %chin% top_dnn, cm]), cm_q = .med(qq$cm))
}
if (!length(Filter(Negate(is.null), .rows))) stop(sprintf("%s FACTORS 0행 — 건너뛴 달 %d", .TAG, .n_skip))
.ALL <- rbindlist(Filter(Negate(is.null), .rows), use.names = TRUE)
FACTORS <- .ALL[is.finite(Score), .(Date, Ticker, Score)]
setorder(FACTORS, Date, -Score, Ticker)
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (max(FACTORS$Date) > max(RAWDATA$Date)) stop(sprintf("%s 시그널일이 RAWDATA 범위 밖", .TAG))
LG <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
write_parquet(.ALL, file.path(.RD, "panel_scores.parquet"))               # 재사용 패널: (Date, Ticker, Score, dnn, cm, q) — 절제 실험용
write_parquet(LG,   file.path(.RD, "diag_combo.parquet"))

# ── 보고 — 구성 요약 + 연도별 표 + 반증 F1~F4 (성과 수치 선언 아님 · 등급은 계약이 낸다) ──
LG[, yr := year(Date)]
.byyr <- LG[, .(n_m = .N, N = as.integer(.med(N)), nq = as.integer(.med(nq)), n_q_cm = as.integer(.med(n_q_cm)),
                ovl = round(.med(ovl_dnn), 2), rho = round(.med(rho_q), 2), pos = as.integer(.med(dnn_pos_med)),
                mdd_n = round(100 * .med(mdd_nest), 1), mdd_d = round(100 * .med(mdd_dnn), 1)), by = yr]
setorder(.byyr, yr)
cat(sprintf("%s 연도별 조립 (N = 적격 · nq = 5분위 · n_q_cm = 5분위 안 CM 유한 · ovl = nested top-25 vs DNN top-25 겹침 · rho = 5분위 안 rho(DNN,CM) · pos = nested 25 의 DNN 순위 중앙 · MDD6 = 창내 낙폭 중앙 nested/DNN):\n", .TAG))
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("    %d | 월 %2d · N %3d · nq %2d · n_q_cm %2d · 겹침 %.2f · rho %+.2f · DNN 순위 중앙 %2d · MDD6 %4.1f%% / %4.1f%%\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$N[i], .byyr$nq[i], .byyr$n_q_cm[i], .byyr$ovl[i], .byyr$rho[i], .byyr$pos[i],
              .byyr$mdd_n[i], .byyr$mdd_d[i]))

# F4 — ★세기 전에 범위를 선언한다: 분모 = 스케줄 월(학습창·고정 축 충족) 전부 · 산출 = FACTORS 가 있는 달.
.cand_d <- .SCH$Date
.got_d  <- unique(FACTORS$Date)
.miss   <- !(.cand_d %in% .got_d)
.rl     <- rle(.miss)
.gapmax <- if (any(.miss)) max(.rl$lengths[.rl$values]) else 0L
.f1 <- .med(LG$ovl_dnn); .f2 <- if (nrow(LG)) .n_short_q / nrow(LG) else NA_real_; .f3 <- .med(LG$rho_q)
.nmn <- FACTORS[, .N, by = Date]
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
cat(sprintf(paste0(
  "%s combination: 풀 = [A] DNN5 상위 5분위(floor(N/5) · 전략 (i)) · 순위 = [B] CM = C − MDD(6개월 일별 경로 · Table 1 (1,2,1)) 풀 안 · 보유 = 러너 top-25 EW 월간\n",
  "  발행 %d개월 (%s ~ %s) · 건너뛴 달 %d · 적격 N %d~%d(중앙 %d) · 5분위 %d~%d종(중앙 %d) · 5분위 안 CM 유한 중앙 %d · 멤버십 중앙 %d → 유동성 통과 중앙 %d\n",
  "  [진단·비스크린] nested 25 의 DNN 순위 중앙 %d(최대 중앙 %d) · 창내 MDD6 중앙 nested %.1f%% / DNN top-25 %.1f%% / 적격 전체 %.1f%% · C6 중앙 nested %.1f%% / DNN top-25 %.1f%% · CM 중앙 nested %.3f / DNN top-25 %.3f / 5분위 %.3f\n",
  "  FACTORS %s행 · 종목/월 중앙 %d (min %d / max %d) · 스코어 3계층 (2,3] / 1.5 / (0,1] · PORTFOLIO 없음(러너 top_n_long) · %.1f분\n"),
  .TAG,
  nrow(LG), as.character(min(LG$Date)), as.character(max(LG$Date)), .n_skip,
  min(LG$N), max(LG$N), as.integer(.med(LG$N)), min(LG$nq), max(LG$nq), as.integer(.med(LG$nq)), as.integer(.med(LG$n_q_cm)),
  as.integer(.med(LG$n_mem)), as.integer(.med(LG$n_liq)),
  as.integer(.med(LG$dnn_pos_med)), as.integer(.med(LG$dnn_pos_max)), 100 * .med(LG$mdd_nest), 100 * .med(LG$mdd_dnn), 100 * .med(LG$mdd_all),
  100 * .med(LG$c_nest), 100 * .med(LG$c_dnn), .med(LG$cm_nest), .med(LG$cm_dnn), .med(LG$cm_q),
  format(nrow(FACTORS), big.mark = ","), as.integer(.med(.nmn$N)), min(.nmn$N), max(.nmn$N), .mins))
cat(sprintf(paste0(
  "%s 반증 (전부 형성일 단면 통계 · 미래참조 0):\n",
  "  F1 [A] 재라벨 아님       : nested top-25 vs DNN top-25 겹침 중앙 %.3f → %s (기준 < %.2f — 2단 정렬이 이름을 바꿨는가)\n",
  "  F2 2단 정렬 작동         : 5분위 안 CM 유한 종목 < 25 인 달 %d/%d = %.3f → %s (기준 < %.2f — 미만이면 CM 이 고를 여지가 없다)\n",
  "  F3 2단 정렬 비잉여       : 5분위 안 rho(DNN, CM) 중앙 %+.3f → %s (기준 |rho| < %.2f — 같으면 CM 은 DNN 의 재표현)\n",
  "  F4 월 결번 0             : [범위 = 스케줄 월 %d] 산출 %d · 최대 연속 결번 %d → %s\n",
  "  ★러너 사양 = FIDELITY.json 의 portfolio_spec (top_n_long · ew · monthly · n_max %d) · commission_paper = null · DNN 예측 출처 [%s]\n"),
  .TAG,
  .f1, if (is.finite(.f1) && .f1 < .OVL_MAX) "PASS" else "FAIL", .OVL_MAX,
  .n_short_q, nrow(LG), .f2, if (is.finite(.f2) && .f2 < .QCM_SHORT_MAX) "PASS" else "FAIL", .QCM_SHORT_MAX,
  .f3, if (is.finite(.f3) && abs(.f3) < .RHO_MAX) "PASS" else "FAIL", .RHO_MAX,
  length(.cand_d), sum(.cand_d %in% .got_d), .gapmax,
  if (length(.cand_d) && all(.cand_d %in% .got_d) && .gapmax == 0L) "PASS" else "FAIL",
  .NTOP, .src_txt))

rm(.PR, .DG, .SCH, .SCHO, .CAL, .me, .ME_CAL, .PX, .ME_ROWS, .ELIG, .CM, .ALL, .rows, .LOG); gc(verbose = FALSE)
FACTORS <- FACTORS[, .(Date, Ticker, Score)]
