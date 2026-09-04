#==============================================================================
# gen_20260905_085656 — 학습된 하방 예보 × 하방베타 횡단면 트림 (v10.4 2026-09-05)
#   target cell: action = cross_sectional · state = ml (기전 지도 미측정 칸)
#
# ★기전
#   dbeta_tilt(상태=낙폭)은 개입 강도 g 를 '지금 낙폭이 자기 이력에서 몇 분위냐' 하나로 읽는다.
#   그건 단변량 현재 상태다 — 낙폭이 얕아도 여러 시장 특징(단·중·장기 실현변동·모멘텀·횡단면
#   분산)이 동시에 나쁘게 정렬되면 다음 달 하방이 커질 수 있는데 낙폭 분위 하나는 그걸 못 본다.
#   이 arm 은 상태를 **학습**으로 읽는다(state = ml): 확장창 안에서 t-1 이하 행의 실현 익월
#   수익으로 다변량 선형모형을 적합해 시장 특징 → 익월 하방 크기(pmax(0,-fwd)) 사상을 학습하고,
#   그 모형이 이번 달 특징에 대해 내는 예보값으로 g 를 정한다. 방향(평균)이 아니라 하방 크기를
#   표적으로 삼는 건 시장 예측기의 정보가 분산에 있고 방향엔 거의 없다는 실측 규율을 따른 것이다.
#   행동은 dbeta_tilt 와 같은 종목축이다(하방베타 횡단면 순위로 차등) — 비교군 안에서 이 arm 을
#   가르는 건 그 축이 아니라 **g 를 만드는 상태 원천이 다변량 학습 예보라는 점**이다.
#
# ★PIT
#   학습표 = 확장창 1..(t-1) 행의 특징 X 와 그 행들의 실현 H$fwd(익월수익 — 이미 실현됨).
#   예보 = 이번 달(t) 의 특징 X_t(신호일에 관측 가능). H$fwd[t] 는 미실현이라 절대 읽지 않는다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e ∈ [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 개입 강도는 모형 예보값의 인-샘플 경험분포 중앙 대비 위치, 종목 차등은
#   그 달 보유 안의 하방베타 횡단면 순위에서. 표본 부족·적합 실패·추정 불가 시 e <- 1(무개입).
#==============================================================================

overlay_expo_gen_20260905_085656 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  out_noop <- function() 1

  # ── ① 상태 g — 확장창에서 학습한 다변량 하방 예보 (state = ml)
  feat <- c("rv20", "rv60", "rv120", "dd", "r252", "xs")
  feat <- feat[feat %in% names(H)]
  if (length(feat) < 2L || !("fwd" %in% names(H))) return(out_noop())

  g <- tryCatch({
    # 학습 구간 = t-1 이하 행만 (그 행들의 fwd 는 실현됐다). t 행은 표에서 배제한다.
    tr_idx <- seq_len(t - 1L)
    if (length(tr_idx) < 36L) return(out_noop())            # 6특징 선형모형에 못 미치면 무개입

    X_tr <- as.matrix(H[tr_idx, feat, with = FALSE])
    y_raw <- suppressWarnings(as.numeric(H$fwd[tr_idx]))
    y_dn  <- pmax(0, -y_raw)                                  # 익월 하방 크기 — 방향 아닌 손실 규모

    keep <- is.finite(y_dn) & apply(is.finite(X_tr), 1L, all)
    if (sum(keep) < 36L) return(out_noop())
    X_tr <- X_tr[keep, , drop = FALSE]; y_dn <- y_dn[keep]

    # 특징 표준화(학습표 중심·척도) — 예보에도 같은 변환을 적용해 스케일 결합을 막는다
    ctr <- colMeans(X_tr)
    scl <- apply(X_tr, 2L, stats::sd)
    scl[!is.finite(scl) | scl <= 0] <- 1
    Xz  <- scale(X_tr, center = ctr, scale = scl)

    fit <- stats::lm.fit(x = cbind(1, Xz), y = y_dn)
    bcoef <- fit$coefficients
    if (any(!is.finite(bcoef))) return(out_noop())

    x_now <- suppressWarnings(as.numeric(H[t, feat, with = FALSE]))
    if (any(!is.finite(x_now))) return(out_noop())            # 이번 달 특징 결측 → 무개입
    xz_now <- (x_now - ctr) / scl
    s_now  <- sum(c(1, xz_now) * bcoef)                        # 이번 달 하방 예보값

    # 예보의 인-샘플 경험분포 중앙 위에서만 개입 (상수 문턱 아님 — 데이터가 정한다)
    s_hist <- as.numeric(cbind(1, Xz) %*% bcoef)
    s_hist <- s_hist[is.finite(s_hist)]
    if (length(s_hist) < 24L || !is.finite(s_now)) return(out_noop())
    q  <- stats::ecdf(s_hist)(s_now)
    gg <- (q - 0.5) / 0.5                                      # 중앙 = 개입 시작점
    max(0, min(1, gg))
  }, error = function(e) 0)

  if (!is.finite(g) || g <= 0) return(out_noop())

  # ── ② 종목 차등 r — 그 달 보유 안에서 하방베타 횡단면 순위
  b  <- suppressWarnings(as.numeric(hold$dbeta))
  ok <- is.finite(b)
  if (sum(ok) < 2L) return(out_noop())                        # 순위 불가 → 무개입
  r  <- rep(0.5, length(b))                                   # 추정 없는 종목은 중앙 — 유·불리 없음
  r[ok] <- (rank(b[ok], ties.method = "average") - 0.5) / sum(ok)

  # ── ③ 노출 = 1 − g·r  (횡단면 평균 ≈ 1 − g/2 — 스칼라 축소 1−g 보다 덜 깎고 하방 기여 쪽에 몰아준다)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
