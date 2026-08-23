# =============================================================================
# fe_peer_valuation_sim.R — arXiv 2608.12594 "What Makes a Peer? Valuation-Anchored
#   Similarity in Private Markets" (Frank, Lyu, … Mehta 2026, BlackRock) 의 KR 상장주 사상
# =============================================================================
# 논문 기계 (충실 복제 부분):
#   ① 밸류에이션을 supervisory anchor 로 GBDT 회귀(log 밸류에이션, 1/99 winsorize)
#   ② 트리별 가중치 w_t = |TL_t − TL_{t−1}| / Σ  (학습손실 증분, 식 3-4)
#   ③ 유사도 S(i,j) = Σ_t w_t · I[같은 리프]  (식 5),  D = 1 − S
#   ④ 하류 = 유사도-가중 kNN 밸류에이션(이웃 20, §6.1/§6.2)
# 논문이 기술하지 않은 부분(명시 보충):
#   - 논문은 사모기업 *밸류에이션 추정* 이지 수익률 전략이 아니다. KR 상장주 사상 =
#     **peer-내재 밸류에이션 vs 실제 밸류에이션의 괴리** (논문이 §1.1 에서 직접 계보로 인용한
#     Geertsema & Lu 2023 'Relative valuation with ML' 의 잔차 신호와 같은 구조).
#     Score = y_i − ŷ_i  (y = 밸류에이션 멀티플 z, 높을수록 '싸다'; ŷ = 유사 peer 가중 kNN 값)
#     → peer 가 같은 밸류에이션 드라이버를 가졌는데 더 싸게 거래되는 종목을 매수.
#   - 타깃: 논문 = log(post-money valuation). 상장주 등가 = 밸류에이션 멀티플. factor DB 는
#     원값이 아니라 횡단면 z 만 제공(C15)하므로 **타깃 = 그 달의 Book-to-Market 횡단면 z**
#     (V01_BM; IC-정렬 부호를 PIT 캐시 `.load_ic_direction_cached` 로 되돌려 **원부호 고정**:
#     높을수록 BM 높음 = 싸다). 트리는 단조변환 불변이라 피처는 정렬 z 그대로 사용.
#   - 모델: CatBoost → xgboost(R). 하이퍼파라미터는 논문(53k행 Optuna)이 아니라 월별 ~2k 행
#     규모에 맞춘 고정값(depth 4 · eta 0.05 · 200 trees · min_child 20 · L2 10). 월별 재튜닝은
#     lean 범위 밖(명시 보충).
#   - 피처: 밸류에이션 드라이버 = 수익성·성장·레버리지·투자·규모·위험 + 섹터(논문의 지배
#     피처가 범주형 deal type/country/sector 였던 점에 대응해 Sector one-hot 포함).
#     가격-스케일 팩터(V*, EP, PSR …)는 타깃 누출이라 **제외**.
#   - 학습 표본 = 그 달 factor DB 전 종목(논문의 '넓은 calibration universe'), 스코어링 =
#     K200∪KQ150 ∧ 유동성 유니버스. peer 후보도 전 표본(자기 자신 제외).
#   - 포트폴리오: 논문 미명시 → 시스템 표준 n_holdings=20 EW 월간 리밸(run_alpha_search 인자).
#
# ===== PIT (C1~C15) =====
#   - 모든 입력은 sig_date d 의 load_month_factors(d) 횡단면(재무 lag 는 factor DB 빌드가 적용,
#     C15 경유) + RAWDATA[Date==d] 의 Sector/멤버십. 미래 정보 없음(C2). 월별 독립 학습 =
#     full-sample 통계 없음(C1). 방향 정렬은 PIT 캐시(C14) 의 부호를 되돌리는 것뿐(C13 위반 아님:
#     수동 NEGATE 가 아니라 정렬 이전 원부호 복원).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})
suppressPackageStartupMessages(library(xgboost))

TARGET  <- "V01_BM"
FEATS   <- c("Q01_GPA", "Q02_ROE", "Q03_ROA", "Q05_Accrual", "Q06_Asset_Growth",
             "Q07_Earnings_Stability", "Q09_CFOA", "Q10_Gross_Margin", "Q11_Net_Margin",
             "Q12_Asset_Turnover", "Q13_Fin_Leverage", "Q15_Debt_to_Equity", "Q17_ROIC",
             "Q19_Cash_to_Assets", "Q20_Net_Equity_Issuance", "Q23_Sustainable_Growth",
             "Q26_RnD_Intensity", "Q27_CapEx_to_Rev", "Q35_CashBased_OpProf",
             "GR01_Revenue_Growth", "GR02_Earnings_Growth", "S01_Size",
             "R12_Idiosyncratic_Risk", "R18_Book_Leverage")
K_NN     <- 20L      # 논문 §6.1 neighborhood size
NROUNDS  <- 200L
XGB_PAR  <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 4L,
                 min_child_weight = 20, subsample = 0.8, colsample_bytree = 0.8,
                 lambda = 10, nthread = 4L)
MIN_FEAT <- 8L       # 유효 피처 ≥8 인 행만 학습(결측은 xgboost 가 분기로 처리 — 논문과 동일)

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) 유니버스 (PIT 시변) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(.mem, Date, Ticker)
.sec <- RAWDATA[Date %in% .month_ends, .(Date, Ticker, Sector = as.character(Sector))]
setkey(.sec, Date, Ticker)
RAWDATA[, c(".TV", ".AvgTV20") := NULL]

.winsor <- function(x, p = 0.01) {
  q <- quantile(x, c(p, 1 - p), na.rm = TRUE, names = FALSE)
  pmin(pmax(x, q[1]), q[2])
}

.factor_list <- vector("list", length(.month_ends))
.n_skip <- 0L
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = c(TARGET, FEATS)),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { .n_skip <- .n_skip + 1L; next }
  wide <- dcast(fdt[is.finite(Z_Score_Aligned)], Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (!(TARGET %in% names(wide))) { .n_skip <- .n_skip + 1L; next }
  feats_here <- intersect(FEATS, names(wide))
  if (length(feats_here) < MIN_FEAT) { .n_skip <- .n_skip + 1L; next }

  # 타깃 원부호 복원: 정렬 부호(PIT 캐시) × 정렬 z = 원 z (높을수록 BM 높음 = 싸다)
  s_bm <- 1L
  dirs <- tryCatch(.load_ic_direction_cached(d, 36L), error = function(e) NULL)
  if (!is.null(dirs) && nrow(dirs)) {
    s <- dirs[Factor_Name == TARGET, ic_sign]
    if (length(s) == 1L && is.finite(s) && s != 0) s_bm <- as.integer(sign(s))
  }
  y_all <- wide[[TARGET]] * s_bm

  # 섹터 one-hot (논문의 범주형 지배 피처에 대응)
  sec_d <- .sec[.(d), .(Ticker, Sector), nomatch = 0L]
  wide <- merge(wide, sec_d, by = "Ticker", all.x = TRUE)
  wide[is.na(Sector) | Sector == "", Sector := "UNK"]
  y_all <- wide[[TARGET]] * s_bm
  Xnum  <- as.matrix(wide[, ..feats_here])
  sec_f <- factor(wide$Sector)
  Xsec  <- if (nlevels(sec_f) > 1L) model.matrix(~ sec_f - 1) else matrix(0, nrow(wide), 0)
  X     <- cbind(Xnum, Xsec)
  n_ok  <- rowSums(is.finite(Xnum))
  train_idx <- which(is.finite(y_all) & n_ok >= MIN_FEAT)
  if (length(train_idx) < 200L) { .n_skip <- .n_skip + 1L; next }

  y_tr <- .winsor(y_all[train_idx])
  dtrain <- xgb.DMatrix(X[train_idx, , drop = FALSE], label = y_tr, missing = NA)
  bst <- tryCatch(
    xgb.train(params = XGB_PAR, data = dtrain, nrounds = NROUNDS,
              evals = list(train = dtrain), verbose = 0),
    error = function(e) NULL)
  if (is.null(bst)) {
    bst <- tryCatch(xgb.train(params = XGB_PAR, data = dtrain, nrounds = NROUNDS,
                              watchlist = list(train = dtrain), verbose = 0),
                    error = function(e) NULL)
  }
  if (is.null(bst)) { .n_skip <- .n_skip + 1L; next }

  # 트리 가중치 w_t = |TL_t − TL_{t−1}| / Σ  (TL_0 = 널모델 RMSE = sd(y))
  ev <- tryCatch(attr(bst, "evaluation_log") %||% bst$evaluation_log, error = function(e) NULL)
  tl <- if (!is.null(ev) && "train_rmse" %in% names(ev)) as.numeric(ev$train_rmse) else NULL
  if (is.null(tl) || length(tl) < 2L) {
    w_t <- rep(1 / NROUNDS, NROUNDS)                 # 로그 부재 시 균등(Breiman proximity) — 보고됨
  } else {
    tl0 <- sd(y_tr)
    S_t <- abs(diff(c(tl0, tl)))
    w_t <- if (sum(S_t) > 0) S_t / sum(S_t) else rep(1 / length(S_t), length(S_t))
  }

  # 리프 배정 (n × T) → 유니버스 행 × 전표본 열 유사도
  leaves <- tryCatch(predict(bst, xgb.DMatrix(X, missing = NA), predleaf = TRUE), error = function(e) NULL)
  if (is.null(leaves)) { .n_skip <- .n_skip + 1L; next }
  leaves <- as.matrix(leaves)
  Tn <- min(ncol(leaves), length(w_t))
  u_idx <- which(wide$Ticker %in% uni_tk & is.finite(y_all))
  if (length(u_idx) < 10L) { .n_skip <- .n_skip + 1L; next }
  S <- matrix(0, length(u_idx), nrow(leaves))
  for (t in seq_len(Tn)) {
    lt <- leaves[, t]
    S <- S + w_t[t] * (outer(lt[u_idx], lt, "=="))
  }
  # 자기 자신 제외 · 타깃 결측 peer 제외
  S[cbind(seq_along(u_idx), u_idx)] <- 0
  S[, !is.finite(y_all)] <- 0

  # 유사도-가중 kNN 밸류에이션 (k = 20) → 괴리 = 실제 − peer-내재
  yhat <- vapply(seq_along(u_idx), function(r) {
    s <- S[r, ]
    o <- order(s, decreasing = TRUE)[seq_len(K_NN)]
    o <- o[s[o] > 0]
    if (length(o) < 5L) return(NA_real_)
    sum(s[o] * y_all[o]) / sum(s[o])
  }, numeric(1))
  sc <- y_all[u_idx] - yhat
  out <- data.table(Date = d, Ticker = wide$Ticker[u_idx], Score = sc)[is.finite(Score)]
  if (nrow(out) >= 10L) .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_peer_valuation_sim] FACTORS 0 rows — factor DB/xgboost 경로 점검")

cat(sprintf("[fe_peer_valuation_sim] arXiv 2608.12594 KR 사상: GBDT(%d trees, 손실증분 가중 리프 동시출현) → kNN(k=%d) peer-내재 BM z 대비 괴리 | FACTORS rows=%d | signal months=%d | skipped months=%d\n",
            NROUNDS, K_NN, nrow(FACTORS), uniqueN(FACTORS$Date), .n_skip))
