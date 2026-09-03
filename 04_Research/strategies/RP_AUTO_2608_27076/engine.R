# =============================================================================
# engine.R — RP_AUTO_2608_27076
# "Tabular Deep Learning for Algorithmic Trading: Cross-Regime Bayesian
#  Optimisation for Equity Signal Generation"
#  Joshua Le Grice (arXiv:2608.27076v1)
#  https://arxiv.org/abs/2608.27076
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json
#
# ===== 왜 faithful 이 아닌가 (판정 순서 1 → 2) =====
# 이 논문은 **횡단면 종목선택 논문이 맞다**. 산출 형태가 우리와 같다:
#   원문 §3.1.2 라벨 —
#     r_{t+1}(i) = ln(P_{t+1}(i)/P_t(i)) ;  Rank_{t+1}(i) = PercentileRank(r_{t+1}(i))
#     y_t(i) = 2 if Rank > 0.90 · 0 if Rank < 0.10 · 1 otherwise
#   원문 §3.2.2 포트 — "top n long stocks ... top n short stocks",
#     "split evenly across the long and short books and equally across positions
#      within each side", "**rebalanced daily**", "2.2 basis points per trade", n=6.
# 즉 신호·종목수·비중은 그대로 옮길 수 있다. 막히는 지점은 **딱 하나, 리밸 주기**다.
#
#   측정 계약이 월간 전용이다 — `backtest_harness.R:316 get_execution_date()` 는
#   시그널일 d 를 **익월 첫 거래일**로만 사상한다(`next_start <- 익월 1일` 이후 첫
#   거래일). `replication_harness.R` 는 이 함수로 보유창 (exec, next_exec) 를 잡으므로,
#   일별 시그널을 넣으면 한 달 안의 모든 시그널일이 **같은 exec_date** 로 접히고
#   보유창이 전부 빈 집합이 된다(마지막 1건 제외). 일별 리밸은 구현 불가다.
#   → 리밸이 월간으로 강제되면 예측 지평도 익월로 강제된다(라벨 r_{t+1} 의 t+1 이
#     '다음 거래일'에서 '다음 달'로 바뀐다). 이 둘은 한 몸이라 분리 선택이 없다.
#   이것이 유일한 강제 이탈이고, 그래서 faithful 이 아니라 adapted 다.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전) =====
# 논문의 기여는 피처도 아키텍처도 아니다. 초록이 스스로 그렇게 말한다 —
#   "**No individual tabular deep learning architecture outperforms gradient-boosted
#     trees**, but combining XGBoost and TabNet using **rank aggregation** produces
#     a Hybrid ensemble ..."
#   "Existing evaluations ... **do not explicitly target regime robustness during
#     hyperparameter selection**. ... Bayesian optimisation configured to target
#     trading performance **across three statistically different market regimes**.
#     **Regime-robust hyperparameter selection is associated with out-of-sample
#     generalisation** ..."
# 남기는 기전 두 개 — 둘 다 모델-불가지(model-agnostic)라 그대로 이식된다:
#   (M1) **교차-국면 하이퍼파라미터 선택**. 하나의 평균이 아니라 통계적으로 구별되는
#        3개 국면 폴드 **전부**에서 성립할 것을 요구하고, 어느 한 폴드라도 무너지면
#        벌점을 문다. 원문 Eq.2 그대로 옮긴다:
#          Score = 0.4(r̄/0.15) + 0.4(s̄/1.5) − 0.2(d̄/0.10) − (Pr + Ps + Pd + Pfloor)
#        (목표 = 수익 15% · 샤프 1.5 · 낙폭 10%. 벌점 조건 = 어느 폴드든 수익<0 /
#         샤프<0 / 낙폭>15%, 하드 플로어 = 수익 −20% 시 10.0)
#        탐색기 = TPE(Tree-structured Parzen Estimator) · **30 trials** (원문 명시).
#   (M2) **이종 학습기 rank 집계 앙상블**. 원문 §3.3.2 —
#        "each model's long and short signal probabilities were **ranked, and the
#         resulting ranks were averaged across models** before applying the top-n
#         selection logic."
# 그리고 라벨 정의(0.90/0.10 데실 3-class)·포트 규칙(top-n 양쪽·양 북 균등·측내 EW)·
# 탐색공간(Table 1)·n∈[5,8] 동시 튜닝은 **원문 수치 그대로** 쓴다.
#
# ===== 무엇을 바꿨는가 (changed) =====
#   (1) 리밸·지평: 일간 → **월간**. ← 강제 이탈(측정 계약). 라벨의 r_{t+1} = 익월 수익.
#       ★익월 수익은 러너의 실제 보유창(익월 첫 거래일~익월 말)과 정확히 같은 구간이다.
#   (2) 유니버스: S&P500 대형주 ~300종 → **K200∪KQ150**(PIT 시변) + adv20(t-1) ≥ 2e8.
#   (3) TabNet → **nnet MLP**(은닉 1층 softmax). torch/libtorch 런타임 미보유 —
#       CRAN 설치만으로는 libtorch(~2GB, non-CRAN)가 안 깔려 무인 실행에서 확정 실패한다.
#       ★이건 기전 훼손이 아니다: 논문 스스로 "개별 딥 아키텍처는 GBT 를 못 이긴다"고
#         보고하므로 M2 가 사는 근거는 아키텍처가 아니라 **함수족이 다른 학습기 둘의
#         rank 집계**다. 부스팅 트리와 함수족이 다른, 실제로 신경망인 학습기를 쓴다.
#         TabNet 탐색공간의 이식: nd=na∈{8,16,32} → 은닉폭 size∈{8,16,32}(같은 개념,
#         원문값 그대로) · γ∈[0.5,3.0] → decay = 10^(−γ)(γ 클수록 제약이 느슨하다는
#         TabNet 의미와 방향 일치. nnet 의 자연 척도로 옮긴 단조변환) · decision_steps
#         는 nnet 에 대응물이 없어 **탐색에서 뺀다**(없는 축을 지어내지 않는다. maxit 은
#         nnet 기본값 1개로 고정 — 훑지 않으므로 selection 대상이 아니다).
#   (4) 대체데이터(뉴스 감성·Google Trends) 미보유 → 피처에서 제외. 원문이 스스로
#       "Alternative data plays a **secondary** role once technical and fundamental
#        features are accounted for" 라 보고하고, 트리아지 초안도 기술적+기본적만
#       지정했다. 매크로(FRED)도 종목횡단면 피처가 아니라 제외.
#   (5) 3개 국면의 정의: 원문은 폴드를 **역년**(2022 bear −18.99% / 2023 recovery
#       +26.00% / 2024 bull +25.28%)으로 잡고 pairwise KS 로 분포 상이를 확인했다.
#       KR 2005~ 에 그 연도를 쓸 수 없으므로 **검증창 내 후행 12개월 벤치 수익의
#       3분위**로 bear/sideways/bull 을 만든다(정확히 3폴드 · 문턱 임의지정 없음 ·
#       원문의 상승/하락/횡보 3구분과 동형). KS 검정은 원문 절차대로 진단 출력한다.
#   (6) Pr/Ps/Pd 벌점 크기: 원문은 Pfloor=10.0 만 수치를 준다. 목표항이 1.0 으로
#       정규화돼 있으므로(0.4+0.4−0.2 계수의 분모가 목표값) **단위 벌점 1.0** 을 쓴다 —
#       "하드 플로어 = 10 배"라는 원문 서술과 척도가 정합한다. 임의 적합 없음.
#   (7) 선택 1회 + 연 1회 재적합: 원문은 11년 학습에서 HP 를 **한 번** 고르고
#       그 뒤 테스트한다. 그 프로토콜 그대로 — 첫 시그널 월에 1회만 선택하고 동결한다.
#       다만 배포창이 원문(1년)보다 훨씬 길어, **동결된 HP 로** 12개월마다 확장창
#       재적합만 한다(HP 재선택 아님 — selection 사건은 표본 전체에서 1회다).
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
# 이 엔진은 지도학습이라 '라벨'이 존재한다. 라벨은 미래참조의 상습 발생지이므로
# 문장이 아니라 **구조**로 막는다:
#   ▸ 훈련 풀 경계 — 시그널월 A(시그널일 = A 의 마지막 거래일)에서 쓰는 학습쌍은
#     (피처월 m, 라벨 = 월 m+1 수익) 중 **m ≤ A−1** 인 것뿐이다. 즉 라벨월 m+1 ≤ A 이고,
#     월 A 의 수익은 시그널일 종가로 이미 실현돼 있다. 월 A 자신의 라벨(= 월 A+1 수익)은
#     학습 풀에 **들어갈 수 없다** — 인덱스 부등식 하나가 이걸 강제한다(`.tr_idx`).
#     ★루프가 인덱스 i 로 전진하며 `panel[mi <= i-1L]` 로만 자르므로, 전 표본을 한 번에
#       훑는 지점이 존재하지 않는다.
#   ▸ 선택(HP) 경계 — 검증 폴드는 [i−36, i−1] 피처월, 적합 세트는 [1, i−37] 피처월.
#     둘 다 시그널월 i 보다 엄격히 과거다. 선택은 표본 전체에서 1회, 첫 시그널월에서만
#     일어나므로 이후 전 구간이 선택에 대해 OOS 다.
#   C1  : 전 표본 통계 0건. 국면 3분위·KDE·모델 적합 전부 확장창(≤ i−1) 안에서만.
#         횡단면 rank/percentile 은 **그 달 안** 통계다.
#   C2  : same-day 순환참조 없음. 피처는 시그널일까지, 라벨은 익월, 집행은 익월 첫 거래일.
#   C3  : 같은 기간 집계→적용 없음. 라벨월 m+1 은 피처월 m 과 겹치지 않는다.
#   C4  : 재무 시차는 Factor DB 빌더 소관 — 본 엔진은 커넥터가 낸 월별 패널만 소비한다.
#         ★as-of 검증: 커넥터의 `factor_db_asof_date` 가 요청월과 다르면 그 달을 **버린다**
#           (커넥터의 "가장 가까운 과거월" 폴백이 낡은 패널을 조용히 끼워넣는 경로 차단).
#   C6  : 유니버스 = 각 시그널일의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#   C7  : shift(-N)·수동 미래 인덱싱 0건. 유일한 shift 는 +1(과거 방향).
#   C10 : 유동성 = 20일 평균 거래대금을 by-Ticker shift(1) 한 t-1 값.
#   C11 : 매크로 미사용.
#   C13 : 부호 조작(NEGATE/FLIP) 없음. 피처는 커넥터의 `Z_Score_Aligned` 만 소비한다.
#   C15 : Factor DB parquet 직접 load 없음 — `load_month_factors()` 경유만.
#   ★Market 열 미사용(rawdata Market 열은 KOSDAQ 0건 날조). 시장구분 대신 S01_Size.
#
# ===== 산출 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) — **논문 그대로의 비중**. 롱 +1/(2n) · 숏 −1/(2n)
#       (양 북 균등 배분 → 각 측 Σ|w| = 0.5 · 측내 EW). 러너에 이걸 쓰려면
#       portfolio_spec$construction = "engine_direct".
#   FACTORS(Date, Ticker, Score) — 하이브리드 롱 집계랭크의 부호반전(높을수록 롱 후보).
#       전 적격 종목에 발행되므로 러너의 IC·FF3/FF5/Carhart·FMB 분석이 선다.
#   ※ 논문 명시 비용은 **2.2bps/trade** — 러너 호출 시 commission_paper = 0.00022.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(xgboost)
  library(nnet)
}))

# C16 재현성(조합탐색 은닉 방지) + nnet 초기가중치 고정. 논문 seed 미명시 → 고정 1값.
set.seed(26082707L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"),   is.data.table(BM_DT))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Size", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))
stopifnot(all(c("Date", "BM_Ret") %in% names(BM_DT)))

# ---- Factor DB 관문 (C15: load_month_factors 경유만) ----
.ROOT <- if (exists("PROJECT_ROOT", inherits = TRUE)) get("PROJECT_ROOT", inherits = TRUE) else
         Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
if (!exists("load_month_factors", mode = "function")) {
  if (!exists("CACHE_DIR", inherits = TRUE)) source(file.path(.ROOT, "02_Infrastructure/config.R"))
  source(file.path(.ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
}
stopifnot(exists("load_month_factors", mode = "function"))

# =============================================================================
# 원문 명시값 (지어내지 않은 것 — 전부 arXiv:2608.27076 원문에서)
# =============================================================================
.LAB_HI    <- 0.90     # §3.1.2  y=2 if PercentileRank > 0.90
.LAB_LO    <- 0.10     # §3.1.2  y=0 if PercentileRank < 0.10
.N_TRIALS  <- 30L      # §3.2.3  "30 trials per model", TPE sampler
.VAL_MONTHS<- 36L      # §3.2.1  검증 폴드 3개 × 1년 = 36개월
.FIT_MIN   <- 96L      # 원문 학습 11년 중 검증 3년을 뺀 8년 = 96개월 (8:3 비 유지)
.TGT_RET   <- 0.15     # Eq.2 목표 수익
.TGT_SR    <- 1.5      # Eq.2 목표 샤프
.TGT_DD    <- 0.10     # Eq.2 목표 낙폭
.PEN_DD_HI <- 0.15     # Eq.2 낙폭 벌점 발화 문턱
.PEN_FLOOR_RET <- -0.20  # Eq.2 하드 플로어
.PEN_FLOOR <- 10.0     # Eq.2 하드 플로어 벌점 (원문 명시)
.PEN_UNIT  <- 1.0      # Pr/Ps/Pd — 원문 미명시. 목표항 정규화 척도(=1.0) 단위 벌점.

# 탐색공간 (Table 1) — kind: num(연속) / int(정수) / cat(범주)
.SPACE_XGB <- list(
  nrounds = list(kind = "int", lo = 1000, hi = 1300),   # estimators [1000,1300]
  eta     = list(kind = "num", lo = 0.005, hi = 0.1),   # learning_rate [0.005,0.1]
  depth   = list(kind = "int", lo = 3, hi = 5),         # max_depth [3,5]
  nsel    = list(kind = "int", lo = 5, hi = 8)          # portfolio size n [5,8] 동시 튜닝
)
.SPACE_MLP <- list(
  size    = list(kind = "cat", vals = c(8, 16, 32)),    # TabNet nd=na {8,16,32} → 은닉폭
  gam     = list(kind = "num", lo = 0.5, hi = 3.0),     # TabNet γ [0.5,3.0] → decay=10^(−γ)
  nsel    = list(kind = "int", lo = 5, hi = 8)
)

# ---- 계산 경계 (원문 미명시. 성과를 보고 고르지 않는다 — 각 1값, 훑지 않음) ----
.PANEL_START <- as.Date("1996-01-01")  # 패널 탐색 시작(성립하는 달만 살아남는다)
.LIQ         <- 2e8                    # adv20(t-1) 하한 (KRW) — 축 명시값
.NMIN        <- 50L                    # 월 최소 횡단면 (n=8 양측 + 데실 문턱이 의미를 갖는 하한)
.REFIT_EVERY <- 12L                    # 동결 HP 재적합 주기(개월). HP 재선택 아님
.MLP_MAXIT   <- 100L                   # nnet 기본값 1개 고정 (탐색 대상 아님)
.CLIP        <- 3.0                    # nnet 입력 절단 (상수 — 통계 아님, 누출 없음)
.TPE_STARTUP <- 10L                    # TPE 무작위 시동 (Optuna 기본)
.TPE_NEI     <- 24L                    # EI 후보수 (Optuna 기본)

.FEATS <- c(
  # 기술적 — 모멘텀 / 오실레이터 (원문 §3.1.2 "Return ranks, momentum, oscillators")
  "M09_Composite_Mom", "M10_Intermediate_Mom", "M11_ST_Reversal", "M13_VolAdj_Mom",
  "M18_RSI", "M19_MACD",
  # 기술적 — 거래량 (원문 "volume measures" · 트리아지 '거래량')
  "L02_Turnover", "L03_Volume_Mom", "L05_Dollar_Volume", "L43_Turnover_Change",
  # 기술적 — 레버리지 (트리아지 '레버리지')
  "Q13_Fin_Leverage", "R17_Market_Leverage",
  # 기본적 (트리아지 'ROE·PBR·GP/A')
  "Q02_ROE", "V05_fPBR", "Q01_GPA", "V01_BM",
  # 규모 — 대형주 유니버스 통제
  "S01_Size"
)

# =============================================================================
# 1. RAWDATA → 월말 시그널일 · 적격 유니버스 · 보유월 실현수익
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]   # C10 t-1
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# 월말 시그널일 = 그 달의 마지막 거래일
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)

# 적격: 시그널일의 K200/KQ150 멤버십 + adv20(t-1) 하한 + 유효 시총 (C6·C10)
.elig <- .rd[Date %in% .mend$SigDate][
             (K200 | KQ150) & is.finite(Size) & Size > 0 &
             is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(MI, Ticker)]

# 보유월 실현수익 — 캘린더 월의 일별 수익 누적.
# ★러너 집행창과 동일 구간이다: exec = 익월 첫 거래일, 다음 exec 직전까지 보유
#   → 보유 구간 = 익월 첫 거래일 ~ 익월 마지막 거래일.
.hold <- .rd[is.finite(Ret), .(RetHold = prod(1 + Ret) - 1, ND = .N), by = .(MI, Ticker)]
.hold <- .hold[ND >= 5L, .(MI, Ticker, RetHold)]

# 국면 변수 — 후행 12개월 벤치 로그수익. 종점 = 그 달 말(= 시그널일) → 결정시점 기지.
.bm <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
.bm[, MI := as.integer(format(Date, "%Y")) * 12L + as.integer(format(Date, "%m"))]
.bmm <- .bm[, .(LR = sum(log1p(BM_Ret))), by = MI]
setorder(.bmm, MI)
.bmm[, TR12 := frollsum(LR, 12L, align = "right")]

# =============================================================================
# 2. Factor DB → 월별 피처 패널 (C15 커넥터 경유 · C13 Z_Score_Aligned · C4 as-of 검증)
# =============================================================================
.load_feats <- function(sig_d) {
  # DB 가용월 이전을 요청하면 커넥터가 경고+에러를 낸다 — 조용히 건너뛴다(정상 경로).
  ft <- tryCatch(suppressWarnings(
                   load_month_factors(sig_d, coverage_min = 0.05, factor_names = .FEATS)),
                 error = function(e) NULL)
  if (is.null(ft) || !nrow(ft)) return(NULL)
  # 신선도는 소비면에서 — 커넥터의 "가장 가까운 과거월" 폴백이 낡은 패널을 끼워넣는
  # 경로를 여기서 끊는다. as-of 가 요청월과 다르면 그 달은 없는 것으로 친다(fail-closed).
  asof <- attr(ft, "factor_db_asof_date")
  if (is.null(asof) || length(asof) != 1L || is.na(asof)) return(NULL)
  if (format(as.Date(asof), "%Y%m") != format(sig_d, "%Y%m")) return(NULL)
  w <- dcast(ft, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned", fun.aggregate = mean)
  gone <- setdiff(.FEATS, names(w))
  if (length(gone)) w[, (gone) := NA_real_]
  w[, c("Ticker", .FEATS), with = FALSE]
}

.mis <- .mend[SigDate >= .PANEL_START]
.blocks <- vector("list", nrow(.mis))
.n_skip <- 0L
.t0 <- Sys.time()
for (k in seq_len(nrow(.mis))) {
  mi <- .mis$MI[k]; sd_k <- .mis$SigDate[k]
  el <- .elig[MI == mi, Ticker]
  if (length(el) < .NMIN) { .n_skip <- .n_skip + 1L; next }
  fw <- .load_feats(sd_k)
  if (is.null(fw)) { .n_skip <- .n_skip + 1L; next }
  fw <- fw[Ticker %chin% el]
  if (nrow(fw) < .NMIN) { .n_skip <- .n_skip + 1L; next }
  fw[, MI := mi][, SigDate := sd_k]
  .blocks[[k]] <- fw
  if (k %% 60L == 0L)
    cat(sprintf("[RP_AUTO_2608_27076] 패널 적재 %s | n=%d | 누적 skip=%d\n",
                as.character(sd_k), nrow(fw), .n_skip))
}
.PN <- rbindlist(Filter(Negate(is.null), .blocks), use.names = TRUE)
rm(.blocks); gc(verbose = FALSE)
if (nrow(.PN) == 0L)
  stop("[RP_AUTO_2608_27076] 피처 패널 0행 — Factor DB 가용월/유니버스 확인")

# 라벨 — 피처월 m 의 표적은 **월 m+1** 실현수익의 횡단면 백분위 데실 (원문 §3.1.2).
.lab <- copy(.hold)
.lab[, MI := MI - 1L]                              # 라벨을 그 라벨을 예측하는 피처월로 되당김
.PN <- merge(.PN, .lab, by = c("MI", "Ticker"), all.x = TRUE)
.PN[, PRK := NA_real_]
.PN[is.finite(RetHold), PRK := frank(RetHold, ties.method = "average") / .N, by = MI]
.PN[, YCLS := NA_integer_]
.PN[is.finite(PRK), YCLS := 1L]
.PN[is.finite(PRK) & PRK > .LAB_HI, YCLS := 2L]
.PN[is.finite(PRK) & PRK < .LAB_LO, YCLS := 0L]

setorder(.PN, MI, Ticker)
.MIS <- sort(unique(.PN$MI))
.PN[, mi_idx := match(MI, .MIS)]
.NM <- length(.MIS)
cat(sprintf("[RP_AUTO_2608_27076] 패널 %d행 · %d개월 (%s ~ %s) · skip %d개월 · %.1f분\n",
            nrow(.PN), .NM,
            as.character(min(.PN$SigDate)), as.character(max(.PN$SigDate)), .n_skip,
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# 피처 행렬 두 벌: 원본(xgboost — 결측 자체 처리) / 대체+절단(nnet — 결측 불가)
.XR <- as.matrix(.PN[, .FEATS, with = FALSE])
.XI <- .XR
.XI[!is.finite(.XI)] <- 0                          # z 척도의 중앙 = 0. 날짜 무관 상수 대체
.XI[.XI >  .CLIP] <-  .CLIP
.XI[.XI < -.CLIP] <- -.CLIP

# =============================================================================
# 3. 학습기 두 종 (함수족이 다르다 — M2 가 요구하는 이종성)
# =============================================================================
.cfg_xgb <- function(p) list(
  nrounds = as.integer(max(1000, min(1300, round(p$nrounds)))),
  eta     = p$eta,
  depth   = as.integer(max(3, min(5, round(p$depth)))),
  nsel    = as.integer(max(5, min(8, round(p$nsel))))
)
.cfg_mlp <- function(p) list(
  size  = as.integer(p$size),
  decay = 10^(-p$gam),
  nsel  = as.integer(max(5, min(8, round(p$nsel))))
)

.fit_xgb <- function(rows, cfg) {
  dm <- xgboost::xgb.DMatrix(data = .XR[rows, , drop = FALSE],
                             label = as.numeric(.PN$YCLS[rows]))
  xgboost::xgb.train(
    params = list(objective = "multi:softprob", num_class = 3L,
                  eta = cfg$eta, max_depth = cfg$depth,
                  tree_method = "hist", eval_metric = "mlogloss"),
    data = dm, nrounds = cfg$nrounds, verbose = 0)
}
.prd_xgb <- function(m, rows) {
  p <- predict(m, xgboost::xgb.DMatrix(data = .XR[rows, , drop = FALSE]))
  if (is.null(dim(p))) p <- matrix(p, ncol = 3L, byrow = TRUE)   # xgboost 판본 양쪽 대응
  p
}
.fit_mlp <- function(rows, cfg) {
  y <- .PN$YCLS[rows]
  Y <- cbind(as.integer(y == 0L), as.integer(y == 1L), as.integer(y == 2L))
  colnames(Y) <- c("dn", "md", "up")
  nnet::nnet(x = .XI[rows, , drop = FALSE], y = Y, size = cfg$size, decay = cfg$decay,
             maxit = .MLP_MAXIT, softmax = TRUE, trace = FALSE,
             MaxNWts = 20000L, rang = 0.3)   # rang*max|x| ≈ 1 (nnet 문서 권고, .CLIP=3)
}
.prd_mlp <- function(m, rows) predict(m, .XI[rows, , drop = FALSE], type = "raw")

# =============================================================================
# 4. 포트폴리오 규칙 (원문 §3.2.2) · Eq.2 목적함수
# =============================================================================
# top-n 롱 / top-n 숏 · 양 북 균등(각 측 Σ|w| = 0.5) · 측내 EW.
# 랭크는 "낮을수록 유력". 하이브리드는 모델별 랭크의 산술평균(원문 §3.3.2).
# 양측 동시선정(사실상 발생 안 함)은 롱 우선 — 자기상쇄 포지션을 만들지 않는다.
.pf_month <- function(dt, nsel) {              # 단일 월 전용 (배포 루프)
  dt[, isL := frank(RKL, ties.method = "first") <= nsel]
  dt[, isS := frank(RKS, ties.method = "first") <= nsel & !isL]
  dt
}
.pf_returns <- function(pred, nsel) {          # 다월 (검증창) — 월별 그룹 랭크
  z <- copy(pred)
  z[, isL := frank(RKL, ties.method = "first") <= nsel, by = MI]
  z[, isS := frank(RKS, ties.method = "first") <= nsel, by = MI]
  z[isL == TRUE, isS := FALSE]
  z[, .(r = 0.5 * (if (any(isL)) mean(RetHold[isL]) else 0) -
             0.5 * (if (any(isS)) mean(RetHold[isS]) else 0)), by = MI]
}
.fold_stats <- function(mr) {
  mr[, .(RET = { g <- prod(pmax(1 + r, 1e-8)); g^(12 / .N) - 1 },
         SR  = { s <- sd(r); if (!is.finite(s) || s <= 0) 0 else sqrt(12) * mean(r) / s },
         DD  = { cw <- cumprod(pmax(1 + r, 1e-8)); max(1 - cw / cummax(cw)) }), by = FOLD]
}
# Eq.2 — Score = 0.4(r̄/0.15) + 0.4(s̄/1.5) − 0.2(d̄/0.10) − (Pr + Ps + Pd + Pfloor)
.eq2 <- function(fs) {
  if (!nrow(fs) || any(!is.finite(c(fs$RET, fs$SR, fs$DD)))) return(-1e6)
  s <- 0.4 * (mean(fs$RET) / .TGT_RET) + 0.4 * (mean(fs$SR) / .TGT_SR) -
       0.2 * (mean(fs$DD) / .TGT_DD)
  pen <- 0
  if (any(fs$RET < 0))              pen <- pen + .PEN_UNIT
  if (any(fs$SR  < 0))              pen <- pen + .PEN_UNIT
  if (any(fs$DD  > .PEN_DD_HI))     pen <- pen + .PEN_UNIT
  if (any(fs$RET < .PEN_FLOOR_RET)) pen <- pen + .PEN_FLOOR
  s - pen
}

# =============================================================================
# 5. TPE (Bergstra et al. 2011 — Optuna 기본값: startup 10 · γ=⌈0.1n⌉ · EI 후보 24)
# =============================================================================
.sp_rand <- function(sp) lapply(sp, function(p)
  if (identical(p$kind, "cat")) p$vals[sample.int(length(p$vals), 1L)] else runif(1, p$lo, p$hi))

.bw <- function(obs, p) {                    # Optuna 대역폭: 좌우 이웃 간격의 최대
  n <- length(obs); rg <- p$hi - p$lo
  if (n == 0L) return(numeric(0))
  ix <- order(obs); so <- c(p$lo, obs[ix], p$hi); sg <- numeric(n)
  for (k in seq_len(n)) sg[k] <- max(so[k + 1L] - so[k], so[k + 2L] - so[k + 1L])
  out <- numeric(n); out[ix] <- sg
  pmax(pmin(out, rg), rg / min(100, n + 1L))
}
.kde_num <- function(p, obs) {               # 관측 + prior(구간 중앙, sd=구간폭)
  list(mu = c(obs, (p$lo + p$hi) / 2), sg = c(.bw(obs, p), p$hi - p$lo))
}
.kde_draw <- function(p, obs, n) {
  if (identical(p$kind, "cat")) {
    pr <- (sapply(p$vals, function(v) sum(obs == v)) + 1) ; pr <- pr / sum(pr)
    return(p$vals[sample.int(length(p$vals), n, replace = TRUE, prob = pr)])
  }
  k <- .kde_num(p, obs); j <- sample.int(length(k$mu), n, replace = TRUE)
  pmin(pmax(rnorm(n, k$mu[j], k$sg[j]), p$lo), p$hi)
}
.kde_lp <- function(p, obs, x) {
  if (identical(p$kind, "cat")) {
    pr <- (sapply(p$vals, function(v) sum(obs == v)) + 1); pr <- pr / sum(pr)
    return(log(pr[match(x, p$vals)]))
  }
  k <- .kde_num(p, obs)
  vapply(x, function(v) log(sum(dnorm(v, k$mu, k$sg)) / length(k$mu) + 1e-300), numeric(1))
}
.tpe_ask <- function(sp, hx, hy) {
  n <- length(hy)
  if (n < .TPE_STARTUP) return(.sp_rand(sp))
  ord <- order(hy, decreasing = TRUE)
  nb  <- max(1L, min(25L, ceiling(0.1 * n)))
  lo_i <- ord[seq_len(nb)]; hi_i <- ord[-seq_len(nb)]
  if (!length(hi_i)) return(.sp_rand(sp))
  cand <- lapply(sp, function(p) NULL); sc <- rep(0, .TPE_NEI)
  for (nm in names(sp)) {
    p <- sp[[nm]]
    ol <- vapply(lo_i, function(j) as.numeric(hx[[j]][[nm]]), numeric(1))
    og <- vapply(hi_i, function(j) as.numeric(hx[[j]][[nm]]), numeric(1))
    cv <- .kde_draw(p, ol, .TPE_NEI)
    cand[[nm]] <- cv
    sc <- sc + .kde_lp(p, ol, cv) - .kde_lp(p, og, cv)     # log l(x) − log g(x)
  }
  pick <- which.max(sc)
  lapply(cand, function(v) v[pick])
}

# =============================================================================
# 6. 교차-국면 선택 (M1) — 표본 전체에서 1회. 이후 HP 동결.
# =============================================================================
# 검증창 = 피처월 [i−36, i−1] · 적합창 = 피처월 [1, i−37]. 둘 다 i 보다 엄격히 과거.
.tr_idx <- function(lo, hi) which(.PN$mi_idx >= lo & .PN$mi_idx <= hi & !is.na(.PN$YCLS))

.make_folds <- function(v_lo, v_hi) {
  mm <- .MIS[v_lo:v_hi]
  tq <- .bmm[MI %in% mm][match(mm, MI), TR12]
  ok <- is.finite(tq)
  if (sum(ok) < 6L) return(NULL)
  cut3 <- quantile(tq[ok], probs = c(1/3, 2/3), na.rm = TRUE, names = FALSE)
  fd <- rep(2L, length(mm))                       # 2 = sideways
  fd[ok & tq <= cut3[1]] <- 1L                    # 1 = bear
  fd[ok & tq >  cut3[2]] <- 3L                    # 3 = bull
  fd[!ok] <- 2L
  data.table(MI = mm, FOLD = fd)
}

.eval_cfg <- function(kind, cfg, f_lo, f_hi, folds, vrows) {
  rows <- .tr_idx(f_lo, f_hi)
  if (length(rows) < 500L) return(list(obj = -1e6, pl = NULL, ps = NULL))
  m <- tryCatch(if (kind == "xgb") .fit_xgb(rows, cfg) else .fit_mlp(rows, cfg),
                error = function(e) NULL)
  if (is.null(m)) return(list(obj = -1e6, pl = NULL, ps = NULL))
  P <- tryCatch(if (kind == "xgb") .prd_xgb(m, vrows) else .prd_mlp(m, vrows),
                error = function(e) NULL)
  if (is.null(P) || is.null(dim(P)) || ncol(P) < 3L || nrow(P) != length(vrows))
    return(list(obj = -1e6, pl = NULL, ps = NULL))
  # ★확률을 먼저 열로 붙인 뒤 월별 랭크를 매긴다 — by= 안에서 외부 행렬을 참조하면
  #   그룹 길이와 어긋난다(재활용/에러). 열로 붙이면 그룹 절단이 자동으로 맞는다.
  pr <- data.table(MI = .PN$MI[vrows], RetHold = .PN$RetHold[vrows],
                   PL = P[, 3], PS = P[, 1])                      # class 2 = 롱 · 0 = 숏
  pr[, RKL := frank(-PL, ties.method = "average"), by = MI]
  pr[, RKS := frank(-PS, ties.method = "average"), by = MI]
  mr <- merge(.pf_returns(pr, cfg$nsel), folds, by = "MI")
  list(obj = .eq2(.fold_stats(mr)), pl = P[, 3], ps = P[, 1])
}

.select_once <- function(i) {
  v_hi <- i - 1L; v_lo <- i - .VAL_MONTHS; f_lo <- 1L; f_hi <- v_lo - 1L
  folds <- .make_folds(v_lo, v_hi)
  if (is.null(folds)) stop("[RP_AUTO_2608_27076] 국면 폴드 구성 실패 — 벤치 후행수익 확인")
  vrows <- .tr_idx(v_lo, v_hi)
  if (!length(vrows)) stop("[RP_AUTO_2608_27076] 검증창 라벨 0행")

  # 원문 절차: pairwise KS 로 3폴드가 실제로 다른 국면인지 확인 (진단 — 게이트 아님)
  bmv <- .bmm[MI %in% folds$MI][match(folds$MI, MI)]
  ksp <- c(NA_real_, NA_real_, NA_real_)
  for (pp in 1:3) {
    a <- bmv$LR[folds$FOLD == c(1L, 1L, 2L)[pp]]; a <- a[is.finite(a)]
    b <- bmv$LR[folds$FOLD == c(2L, 3L, 3L)[pp]]; b <- b[is.finite(b)]
    if (length(a) > 2L && length(b) > 2L)
      ksp[pp] <- suppressWarnings(ks.test(a, b)$p.value)
  }
  cat(sprintf(paste0("[RP_AUTO_2608_27076] 국면 폴드 n = (bear %d · side %d · bull %d) | ",
                     "KS p: 1-2 %.3f · 1-3 %.3f · 2-3 %.3f\n"),
              sum(folds$FOLD == 1L), sum(folds$FOLD == 2L), sum(folds$FOLD == 3L),
              ksp[1], ksp[2], ksp[3]))

  keep <- list()
  for (kind in c("xgb", "mlp")) {
    sp <- if (kind == "xgb") .SPACE_XGB else .SPACE_MLP
    hx <- list(); hy <- numeric(0); pick <- NULL; pick_obj <- -Inf; pick_p <- NULL
    for (tr in seq_len(.N_TRIALS)) {
      raw <- .tpe_ask(sp, hx, hy)
      cfg <- if (kind == "xgb") .cfg_xgb(raw) else .cfg_mlp(raw)
      ev  <- .eval_cfg(kind, cfg, f_lo, f_hi, folds, vrows)
      hx[[tr]] <- raw; hy[tr] <- ev$obj
      if (ev$obj > pick_obj) { pick_obj <- ev$obj; pick <- cfg; pick_p <- ev }
      if (tr %% 10L == 0L)
        cat(sprintf("[RP_AUTO_2608_27076] %s TPE %d/%d | 현 최고 Eq.2 = %.3f\n",
                    kind, tr, .N_TRIALS, pick_obj))
    }
    keep[[kind]] <- list(cfg = pick, obj = pick_obj, p = pick_p)
  }

  # 하이브리드 n — 원문은 n 을 같은 목적함수로 튜닝한다(§3.2.3). 배포되는 객체는
  # 하이브리드이므로 rank 집계 후 n∈{5..8} 을 Eq.2 로 다시 고른다(재적합 없음).
  nsel <- keep$xgb$cfg$nsel
  if (!is.null(keep$xgb$p$pl) && !is.null(keep$mlp$p$pl)) {
    pr <- data.table(MI = .PN$MI[vrows], RetHold = .PN$RetHold[vrows],
                     XL = keep$xgb$p$pl, XS = keep$xgb$p$ps,
                     NL = keep$mlp$p$pl, NS = keep$mlp$p$ps)
    pr[, RKL := (frank(-XL, ties.method = "average") +
                 frank(-NL, ties.method = "average")) / 2, by = MI]
    pr[, RKS := (frank(-XS, ties.method = "average") +
                 frank(-NS, ties.method = "average")) / 2, by = MI]
    ob <- -Inf
    for (nn in 5:8) {
      o <- .eq2(.fold_stats(merge(.pf_returns(pr, nn), folds, by = "MI")))
      if (o > ob) { ob <- o; nsel <- nn }
    }
    cat(sprintf("[RP_AUTO_2608_27076] 하이브리드 n = %d (Eq.2 %.3f)\n", nsel, ob))
  }
  list(xgb = keep$xgb$cfg, mlp = keep$mlp$cfg, nsel = nsel,
       obj_x = keep$xgb$obj, obj_n = keep$mlp$obj)
}

# =============================================================================
# 7. 워크포워드 배포 — 시그널월 i 마다 학습풀은 피처월 ≤ i−1 (구조적 PIT 경계)
# =============================================================================
.i0 <- .FIT_MIN + .VAL_MONTHS + 1L
if (.NM < .i0)
  stop(sprintf("[RP_AUTO_2608_27076] 개월 부족 — 필요 %d, 보유 %d", .i0, .NM))

cat(sprintf("[RP_AUTO_2608_27076] 첫 시그널월 = %s (적합 %d + 검증 %d 소요)\n",
            as.character(.PN[mi_idx == .i0, SigDate][1]), .FIT_MIN, .VAL_MONTHS))

.SEL <- .select_once(.i0)
cat(sprintf(paste0("[RP_AUTO_2608_27076] 선택 확정(1회·이후 동결) | xgb nrounds=%d eta=%.4f ",
                   "depth=%d (Eq.2 %.3f) | mlp size=%d decay=%.4f (Eq.2 %.3f) | n=%d\n"),
            .SEL$xgb$nrounds, .SEL$xgb$eta, .SEL$xgb$depth, .SEL$obj_x,
            .SEL$mlp$size, .SEL$mlp$decay, .SEL$obj_n, .SEL$nsel))

.mx <- NULL; .mn <- NULL
.pf_out <- vector("list", .NM); .fx_out <- vector("list", .NM)

for (i in .i0:.NM) {
  rows_i <- which(.PN$mi_idx == i)
  if (length(rows_i) < .NMIN) next

  if (((i - .i0) %% .REFIT_EVERY == 0L) || (is.null(.mx) && is.null(.mn))) {
    tr <- .tr_idx(1L, i - 1L)                      # ★학습풀 경계: 피처월 ≤ i−1 뿐
    if (length(tr) < 500L) next
    .mx <- tryCatch(.fit_xgb(tr, .SEL$xgb), error = function(e) NULL)
    .mn <- tryCatch(.fit_mlp(tr, .SEL$mlp), error = function(e) NULL)
    cat(sprintf("[RP_AUTO_2608_27076] 재적합 %s | 학습 %d행 | xgb %s · mlp %s\n",
                as.character(.PN$SigDate[rows_i[1]]), length(tr),
                if (is.null(.mx)) "FAIL" else "ok", if (is.null(.mn)) "FAIL" else "ok"))
  }
  if (is.null(.mx) && is.null(.mn)) next

  Px <- if (!is.null(.mx)) tryCatch(.prd_xgb(.mx, rows_i), error = function(e) NULL) else NULL
  Pn <- if (!is.null(.mn)) tryCatch(.prd_mlp(.mn, rows_i), error = function(e) NULL) else NULL
  .okp <- function(P) !is.null(P) && !is.null(dim(P)) && ncol(P) >= 3L &&
                      nrow(P) == length(rows_i)
  if (!.okp(Px)) Px <- NULL
  if (!.okp(Pn)) Pn <- NULL
  if (is.null(Px) && is.null(Pn)) next

  d <- data.table(Date = .PN$SigDate[rows_i], Ticker = .PN$Ticker[rows_i])
  # M2 — 모델별로 롱·숏 확률을 각각 랭크한 뒤 모델 간 산술평균 (원문 §3.3.2)
  rkl <- NULL; rks <- NULL; nmod <- 0L
  if (!is.null(Px)) { rkl <- frank(-Px[, 3], ties.method = "average")
                      rks <- frank(-Px[, 1], ties.method = "average"); nmod <- nmod + 1L }
  if (!is.null(Pn)) { a <- frank(-Pn[, 3], ties.method = "average")
                      b <- frank(-Pn[, 1], ties.method = "average")
                      rkl <- if (is.null(rkl)) a else rkl + a
                      rks <- if (is.null(rks)) b else rks + b; nmod <- nmod + 1L }
  d[, RKL := rkl / nmod][, RKS := rks / nmod]

  d <- .pf_month(d, .SEL$nsel)
  nL <- sum(d$isL); nS <- sum(d$isS)
  if (nL == 0L) next
  # 양 북 균등(각 측 Σ|w| = 0.5) · 측내 EW — 원문 §3.2.2
  .pf_out[[i]] <- rbindlist(list(
    d[isL == TRUE, .(Date, Ticker, Weight =  0.5 / nL, Leg = "long")],
    if (nS > 0L) d[isS == TRUE, .(Date, Ticker, Weight = -0.5 / nS, Leg = "short")] else NULL),
    use.names = TRUE)
  .fx_out[[i]] <- d[, .(Date, Ticker, Score = -RKL)]   # 높을수록 롱 후보 (단조)

  if ((i - .i0) %% 24L == 0L) gc(verbose = FALSE)
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_out), use.names = TRUE)
FACTORS   <- rbindlist(Filter(Negate(is.null), .fx_out), use.names = TRUE)
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_AUTO_2608_27076] PORTFOLIO 0행 — 패널/모델 적합 확인")
setorder(PORTFOLIO, Date, -Weight)
setorder(FACTORS, Date, -Score)

cat(sprintf(paste0("[RP_AUTO_2608_27076] adapted: cross-regime TPE(%d trials) + XGB/MLP rank ",
                   "aggregation | 리밸 %d회 %s~%s | 측당 n=%d | PORTFOLIO %d행 · FACTORS %d행\n",
                   "  ★러너 호출: portfolio_spec=list(construction=\"engine_direct\") · ",
                   "commission_paper=0.00022 (논문 2.2bps/trade)\n"),
            .N_TRIALS, uniqueN(PORTFOLIO$Date),
            as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            .SEL$nsel, nrow(PORTFOLIO), nrow(FACTORS)))
