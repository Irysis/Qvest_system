# =============================================================================
# fe_cid_pinchuk2023.R — Cross-Industry Dispersion (CID) beta
# =============================================================================
# 논문: Pinchuk, Mykola (2023) "Labor Income Risk and the Cross-Section of
#       Expected Returns". arXiv:2301.09173  https://arxiv.org/abs/2301.09173
#
# 주장: 산업간 수익률 분산(CID)은 sectoral shift 발 실업위험의 proxy 다.
#   CID 충격 민감도(beta_CID)가 높은 종목은 실업위험 헤지 자산이라 기대수익이
#   낮다 — 고민감/저민감 스프레드 연 5.9%(월 49bps, t=3.19, VW).
#
# ★ 논문 명시값 (전부 그대로 복제) -------------------------------------------
#   (1) CID_t = (1/N) * sum_i |R_i,t - R_MKT,t|                      (Eq.1)
#         R_i,t   = 산업 포트폴리오 월간수익 (시총가중, 전월말 시총)
#         R_MKT,t = 전 상장기업 시총가중 시장수익
#         산업은 **소속 기업 10개 이상**인 것만 ("at least 10 firms")
#   (2) 충격:  dCID_t = g0 + g1*dCID_{t-1} + g2*CID_{t-1} + u_t      (Eq.2)
#         잔차 u_t 를 이후 회귀의 CID 로 사용
#   (3) beta:  R_i,t = a + beta*u_t + e_t, **24개월(2년) 월간수익** 창 (Eq.3)
#         beta 를 단면 1%/99% winsorize (논문 명시)
#   (4) 정렬: 매월 beta_CID 5분위, 시총가중(전월말 시총), 월간 리밸
#         논문 표기 L/S = Q5-Q1 = -49bps/월 → **수익 방향은 Q1-Q5**
#         (Q1 0.79% > Q2 0.63 > Q3 0.58 > Q4 0.45 > Q5 0.30 단조 감소)
#
# ★ 유일한 변경 = 유니버스 (러너가 K200∪KQ150 PIT 시변 멤버십으로 치환).
#   단 CID 자체는 **거시 상태변수**라 논문대로 시장 전체(전 상장종목)에서 만든다 —
#   논문도 "value-weighted market return across all firms from CRSP" 다.
#   유니버스 치환은 정렬 대상(test asset)에만 걸린다.
#
# ★ 미명시값 보충 (명시) -----------------------------------------------------
#   - AR 잔차를 **expanding window** 로 뽑는다 (논문은 전표본 1회 추정).
#     전표본 추정은 C1(full-sample 통계) 위반이라 PIT 가 논문 문자를 이긴다.
#     burn-in 60개월. 백테는 2005~ 라 여유 충분(데이터 1990~).
#   - beta 창 24개월 중 유효 관측 **>=18** 요구 (논문 최소관측 무명시).
#   - 논문의 $5 주가 / $50M 시총 필터는 **미적용** — 그 필터 목적은 CRSP microcap
#     제거이고 유니버스 치환(K200∪KQ150)이 그 역할을 더 강하게 이미 수행한다.
#     달러 문턱을 원화로 옮기는 순간 근거 없는 수치가 된다.
#   - 일간 |Ret| > 1.0 은 결측 처리 — KRX 일간 가격제한폭(±30%) 하에서 불가능한
#     값이므로 액면/재상장 단위 아티팩트다(14,078,648행 중 307행 = 0.002%).
#     전략 파라미터가 아니라 거래소 규칙에 근거한 데이터 위생 조치.
#   - beta 회귀 종속변수 = **원수익률**(논문은 초과수익률). 단일 회귀변수 OLS 에서
#     rf 차감은 모든 종목의 beta 를 같은 상수 Cov(rf,u)/Var(u) 만큼 이동시키므로
#     **단면 순위·5분위 소속이 불변**이다(창이 종목 공통). KR 무위험(ECOS CD91)은
#     2005-08 이후만 있어 1990~ 워밍업 창을 덮지 못한다 — 순위 불변성이 대체 근거.
#   - 산업분류 = RAWDATA Sector_Lv2(48군 — FF49 의 최근접 아날로그). 각 월말에 기록된
#     값을 그대로 쓴다(3,388종 중 910종이 이력 내 재분류 기록 보유 → 시변 기록으로 판단).
#
# ===== PIT =====
#   - 시그널일 d = 월 t 마지막 거래일, 사용 정보는 월 t 종가까지.
#     실행 = get_execution_date(d) = 월 t+1 첫 거래일 → 보유월 t+1.
#     신호 컷오프(월 t 말) < 보유월 시작 — C5 정합.
#   - AR 계수·잔차 = expanding(<= t)만. 전표본 통계 없음 (C1).
#   - beta 창 = 월 t 로 끝나는 과거 24개월 (과거 윈도우만).
#   - winsorize 는 그 달 단면 내부에서만 (by = ymi) — 시계열 미래 미참조.
#   - 가중치 = 전월말 시총 (논문 그대로, 동일시점 순환참조 없음).
#   - 부호: Score = -beta 는 논문이 **사전 선언한 방향**(고민감 = 저수익)을
#     매수 우선순위로 옮긴 것이지 사후 방향반전이 아니다.
# RAWDATA columns: Date, Ticker, Ret, Size, Sector_Lv2, K200, KQ150 ...
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Ret", "Size", "Sector_Lv2") %in% names(RAWDATA)))

CID_MIN_FIRMS   <- 10L    # 논문: industries with at least 10 firms
CID_BETA_WIN    <- 24L    # 논문: two years of monthly returns
CID_BETA_MINOBS <- 18L    # 보충(논문 무명시)
CID_AR_BURNIN   <- 60L    # 보충(논문은 전표본 — PIT 상 expanding 필요)
CID_RET_CAP     <- 1.0    # KRX 일간 가격제한폭 초과 = 단위 아티팩트

# ---- 1. 일간 -> 월간 패널 ---------------------------------------------------
DD <- RAWDATA[, .(Date, Ticker, Ret, Size, Sector_Lv2)]
DD[, rr := Ret]
DD[!is.finite(rr) | abs(rr) > CID_RET_CAP, rr := NA_real_]
DD[, ymi := year(Date) * 12L + month(Date)]

ME <- DD[, .(me = max(Date)), by = ymi]                    # 시장 전체 월말 거래일

MON <- DD[, .(mret = if (sum(is.finite(rr)) >= 1L) prod(1 + rr[is.finite(rr)]) - 1 else NA_real_,
              nd   = sum(is.finite(rr))), by = .(Ticker, ymi)]

EOM <- DD[Date %in% ME$me, .(Ticker, ymi, size_end = Size, ind = Sector_Lv2)]
MON <- merge(MON, EOM, by = c("Ticker", "ymi"))

setorder(MON, Ticker, ymi)                                  # 전월말 시총(논문 가중치)
MON[, `:=`(size_prev = shift(size_end), ymi_prev = shift(ymi)), by = Ticker]
MON[!is.finite(ymi_prev) | ymi_prev != ymi - 1L, size_prev := NA_real_]

# ---- 2. 산업 포트폴리오 + 시장 -> CID (Eq.1) --------------------------------
VAL <- MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0 & !is.na(ind)]
IP  <- VAL[, .(nf = .N, r_ind = sum(mret * size_prev) / sum(size_prev)),
           by = .(ymi, ind)][nf >= CID_MIN_FIRMS]
MKT <- MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0,
           .(r_mkt = sum(mret * size_prev) / sum(size_prev)), by = ymi]
CIDT <- merge(IP, MKT, by = "ymi")[, .(CID = mean(abs(r_ind - r_mkt)), n_ind = .N), by = ymi]
setorder(CIDT, ymi)

# ---- 3. CID 충격 u_t — expanding window AR (Eq.2, PIT 보정) -----------------
CIDT[, dC := CID - shift(CID)]
CIDT[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
CIDT[, u := NA_real_]
fit_rows <- which(is.finite(CIDT$dC) & is.finite(CIDT$dC_l1) & is.finite(CIDT$C_l1))
if (length(fit_rows) >= CID_AR_BURNIN) {
  for (k in seq.int(CID_AR_BURNIN, length(fit_rows))) {
    sub <- CIDT[fit_rows[seq_len(k)]]                       # <= t 만 (expanding)
    f   <- stats::lm(dC ~ dC_l1 + C_l1, data = sub)
    res <- stats::residuals(f)
    set(CIDT, i = fit_rows[k], j = "u", value = as.numeric(res[length(res)]))
  }
}

# ---- 4. beta_CID — 종목별 24개월 rolling 회귀 (Eq.3) ------------------------
UM <- CIDT[, .(ymi, u)]
SS <- MON[, .(Ticker, ymi, mret)]
GRID <- SS[, .(ymi = seq.int(min(ymi), max(ymi))), by = Ticker]   # 결측월 자리 확보
SS <- merge(GRID, SS, by = c("Ticker", "ymi"), all.x = TRUE)
SS <- merge(SS, UM, by = "ymi", all.x = TRUE)
setorder(SS, Ticker, ymi)

SS[, ok := as.integer(is.finite(mret) & is.finite(u))]
SS[, `:=`(p_ru = fifelse(ok == 1L, mret * u, 0), p_r = fifelse(ok == 1L, mret, 0),
          p_uu = fifelse(ok == 1L, u * u, 0),    p_u = fifelse(ok == 1L, u, 0))]
SS[, `:=`(n_ok = frollsum(ok,   CID_BETA_WIN), Sxy = frollsum(p_ru, CID_BETA_WIN),
          Sy   = frollsum(p_r,  CID_BETA_WIN), Sxx = frollsum(p_uu, CID_BETA_WIN),
          Sx   = frollsum(p_u,  CID_BETA_WIN)), by = Ticker]
SS[, den := n_ok * Sxx - Sx * Sx]
SS[, beta := fifelse(is.finite(den) & den > 0, (n_ok * Sxy - Sx * Sy) / den, NA_real_)]
SS[!is.finite(n_ok) | n_ok < CID_BETA_MINOBS, beta := NA_real_]

# ---- 5. 단면 winsorize 1%/99% (논문 명시) + 방향 ----------------------------
BW <- SS[is.finite(beta), .(Ticker, ymi, beta)]
BW[, beta_w := {
  qq <- stats::quantile(beta, c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  pmin(pmax(beta, qq[1]), qq[2])
}, by = ymi]

# 논문 사전 선언 방향: beta_CID 高 = 기대수익 低 (Q1 0.79% > Q5 0.30%).
# 매수 우선순위(Score 高) = beta 低 = 논문의 고수익 다리(Q1).
BW <- merge(BW, ME, by = "ymi")
FACTORS <- BW[is.finite(beta_w), .(Date = me, Ticker, Score = -beta_w)]
setorder(FACTORS, Date, -Score)

cat(sprintf("[fe_cid_pinchuk2023] CID months=%d (u 유효 %d) · 산업수 중앙값 %.0f · FACTORS rows=%d dates=%d\n",
            nrow(CIDT), sum(is.finite(CIDT$u)), stats::median(CIDT$n_ind, na.rm = TRUE),
            nrow(FACTORS), uniqueN(FACTORS$Date)))
cat(sprintf("[fe_cid_pinchuk2023] CID 평균 %.4f · sd %.4f · 1-lag 자기상관 %.3f (논문 US: -0.05)\n",
            mean(CIDT$CID, na.rm = TRUE), stats::sd(CIDT$CID, na.rm = TRUE),
            stats::cor(CIDT$CID[-1], CIDT$CID[-nrow(CIDT)], use = "complete.obs")))
