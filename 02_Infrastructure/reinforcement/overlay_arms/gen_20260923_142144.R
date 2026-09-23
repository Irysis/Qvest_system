#==============================================================================
# gen_20260923_142144 — 다변량 상태 × **한계 위험기여 비례 배분** (순위 램프가 아니다)
#                       (표적 칸: action = cross_sectional · state = multivar)
#
# ★기전 (사전 선언 — 한 인자만 갈리는 통제 대조로 설계했다)
#   이 칸의 선행 arm 3종은 배분 규칙이 전부 같다: 종목별 위험 점수를 만들고 그 **순위**로
#   e = 1 − g·r 을 준다(r = 보유 안 백분위). 순위 램프는 두 가지를 버린다.
#     ① 크기 — 이름들 사이의 위험 차이가 실제로 얼마나 큰지는 버려지고 등수만 남는다.
#        책이 거의 균질한 달에도 램프는 1등에게 g, 꼴등에게 0 을 배정한다(없는 차이를 만든다).
#     ② 포트폴리오성 — 점수는 이름 하나의 특성에서만 나온다. 그런데 노출을 깎아 줄어드는 것은
#        **책의 위험**이고, 한 이름을 깎으면 그 이름이 책의 공통 노출에 실어 놓은 몫이 함께 줄어
#        나머지 전원의 위험까지 내려간다. 한계 효과는 이름의 특성이 아니라 책의 구성에 달렸다.
#   이 arm 이 바꾸는 것은 그 배분 규칙 하나다. 예산(총 감액)은 선행과 똑같이 두고, 그 예산을
#   **지금 상태에서의 한계 위험기여에 비례**해 나눈다. 1팩터 위험모형으로 쓰면
#       V(x) = v_f (Σ x_i b_i)² + Σ x_i² s_i²        (x_i = 비중 × 노출)
#       ∂V/∂c_i ∝ v_f · b_i · B + w_i · s_i²         (c_i = 감액 · B = Σ x_j b_j)
#   이고 배분은 c_i ∝ (그 값의 양의 부분), 총합 = 예산이다. 성질이 여기서 나온다:
#     · 책이 균질하면 배분이 균등으로 수렴한다 — 차등을 스스로 접는다(라벨만 횡단면인 층이 되지 않는다).
#     · 공통항 v_f·b_i·B 가 '누가 책의 공통 노출을 만드나'를 세므로, 지목이 개별 특성의 등수가 아니라
#       책 전체에 대한 기여로 간다. 25종 등가중이면 고유분산 몫이 1/n 로 눌려 공통항이 지배하는데
#       그것이 오류가 아니라 분산된 책의 실제 구조다(고유위험은 이미 분산으로 처리돼 있다).
#     · B < 0 (책이 순공매도성 적재)인 달에는 부호가 뒤집혀 고적재 이름을 깎는 것이 위험을 늘린다 —
#       그 이름의 기여가 음수가 되어 감액 0 으로 떨어진다. 순위 램프는 이 경우를 표현할 수 없다.
#
#   ★고정한 것(선행과 같은 형태) — 갈리는 인자를 하나로 묶기 위해:
#     상태 4축(rv60 · dd · −r252 · xs) · 확장창 표준화 · GLS 합성 a = S^{-1}1 ·
#     개입 강도 g(합성 지수 자기 이력 경험분포의 중앙에서 시작) ·
#     **횡단면 평균 노출 1 − g/2** · **이름별 감액 상한 g**(램프의 최대 감액과 동일).
#   평균도 범위도 같으므로 차이가 나면 그 차이는 '언제 얼마나 줄였나'가 아니라 그 범위 안에서
#   '누구에게 얼마를 배정했나'에서만 온다 — 노출을 짝지은 대조와 같은 축에서 답한다.
#   ★배분 규칙을 바꾸면 단위도 따라온다 — 순위는 무차원이지만 한계 기여는 분산 단위다. 그래서
#   적재(b)는 베타 단위, 고유변동(s)은 연율 변동성 단위로 쓰고 상태는 **수준**으로 들어온다
#   (v_f = 지금 시장 분산 · 고유분산 배율 = 지금 횡단면분산 / 자기 이력 중앙). 표준화 z 로는
#   한계 기여를 말할 수 없다. 이것이 규칙 변경에 딸린 필연이고, 갈린 인자는 여전히 하나다.
#
#   ★한계 명시: ①ctx$hold 에 비중이 없어 기저 비중은 등가중으로 대용한다 — 실제 비중이 균일에서
#   멀면 B 와 w_i·s_i² 가 그만큼 틀린다. ②적재 b 는 확장창 베타/하방베타라 느리게 움직인다 —
#   달마다의 배분 변화는 대부분 상태(v_f · 축 배합)에서 온다. ③양의 기여를 가진 이름이 책의 절반
#   미만이면 상한 g 에 걸려 예산을 다 쓰지 못한다(그 달은 선행보다 덜 깎는다 — 평균 노출에 보이는
#   보수적 폴백이며 숨기지 않는다). ④상태 축이 스트레스 방향으로 서지 않으면 무개입이다(증액 없음).
#   ★반증 조건: 한계 기여 비례 배분이 순위 램프와 같은 순서·같은 몫을 내면(책이 균질하거나 적재가
#   고유변동과 한 줄로 얽혀 있으면) 이 층의 주장은 0 으로 수렴한다. 반대로 배분이 갈리는데 성과가
#   나빠지면, 위험을 줄이는 배분이 회복까지 함께 깎는다는 뜻이다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로 기여의
#   횡단면 차등이 아예 서지 않는 달(보유 1종 · 특징 전부 결측 · 기여가 완전 균등)은 스칼라로
#   때우지 않고 무개입한다.
#   H = 확장창(t 행까지 · 미래 행 없음) — t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 합성 지수 자기 이력의 경험분포 중앙, 축 배합은 그 시점 상관행렬,
#   분산 수준은 그 시점 실현값과 자기 이력 중앙의 비, 배분은 그 달 보유의 한계 기여에서 온다.
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다. 외부 데이터 없음(H·ctx$hold).
#==============================================================================

overlay_expo_gen_20260923_142144 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                      # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) != 1L || !is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (length(tt) != 1L || !is.finite(tt)) return(1)

  # ── ① 상태 4축 — 부호를 스트레스 방향(값이 클수록 나쁨)으로 맞춘다. t 행까지만 읽는다.
  X <- cbind(vol   =  suppressWarnings(as.numeric(H$rv60)),
             dd    =  suppressWarnings(as.numeric(H$dd)),
             trend = -suppressWarnings(as.numeric(H$r252)),
             disp  =  suppressWarnings(as.numeric(H$xs)))
  tt <- min(tt, nrow(X))
  if (tt < 2L) return(1)
  X <- X[seq_len(tt), , drop = FALSE]

  fin <- stats::complete.cases(X) & is.finite(rowSums(X))
  if (!isTRUE(fin[tt])) return(1)                     # 지금 달 상태가 결측 = 개입 근거 없음
  if (sum(fin) < max(nmin, ncol(X) * 6L)) return(1)   # 상관 추정 표본 부족
  Xo <- X[fin, , drop = FALSE]

  # ── ② 확장창 표준화 — 축마다 단위가 다르므로 자기 이력의 평균·산포로 무차원화
  mu  <- colMeans(Xo)
  sdv <- apply(Xo, 2L, stats::sd)
  keep <- is.finite(sdv) & sdv > 0
  if (sum(keep) < 2L) return(1)                       # 다변량이 성립 안 하면 이 arm 의 일이 아니다
  Zo <- sweep(sweep(Xo[, keep, drop = FALSE], 2L, mu[keep], "-"), 2L, sdv[keep], "/")
  ax <- colnames(Xo)[keep]

  # ── ③ 상태 GLS 합성 a = S^{-1}1 — 겹친 축이 몫을 나눠 갖는다(중복 계상 제거)
  S_s <- suppressWarnings(stats::cor(Zo))
  a <- tryCatch(as.numeric(solve(S_s, rep(1, ncol(Zo)))), error = function(z) NULL)
  if (is.null(a) || !all(is.finite(a))) a <- rep(1, ncol(Zo))   # 특이행렬 폴백 = 단순 평균
  den <- sqrt(sum(a))
  if (!is.finite(den) || den <= 0) return(1)                    # 축들이 서로 상쇄 = 합성 불가
  m <- as.numeric(Zo %*% a) / den
  if (!all(is.finite(m))) return(1)

  # ── ④ 개입 예산 g — 합성 지수가 자기 이력에서 얼마나 위쪽인가(확장창 경험분포)
  q <- stats::ecdf(m)(m[length(m)])            # 0~1. 경험분포 중앙 위에서만 개입한다
  g <- max(0, min(1, (q - 0.5) / 0.5))         # 중앙 = 개입 시작점(데이터가 정한다)
  if (g <= 0) return(1)

  # ── ⑤ 축 기여도 w — 지금 합성 지수를 만든 몫(Σ_j a_j·z_j = m·den 이라 가법 분해).
  #   낙폭·추세 축의 몫이 클수록 적재를 하방베타 쪽으로 옮긴다 — 손실이 실려 오는 통로가 다르다.
  z_now <- as.numeric(Zo[nrow(Zo), ])
  w <- pmax(0, a * z_now)
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(1)     # 스트레스 방향으로 선 축이 없다
  w <- w / sw
  w_dn <- sum(w[ax %in% c("dd", "trend")])
  w_dn <- max(0, min(1, w_dn))

  # ── ⑥ 적재 b (베타 단위) — 대칭 베타와 하방베타의 상태 가중 혼합
  bb  <- suppressWarnings(as.numeric(hold$beta))
  dbv <- suppressWarnings(as.numeric(hold$dbeta))
  if (length(bb) != n_h) bb <- rep(NA_real_, n_h)
  if (length(dbv) != n_h) dbv <- rep(NA_real_, n_h)
  b_sym <- bb
  b_dn  <- ifelse(is.finite(dbv), dbv, bb)     # 하방 표본이 짧아 못 읽은 이름은 대칭 베타로
  med_s <- suppressWarnings(stats::median(b_sym[is.finite(b_sym)]))
  med_d <- suppressWarnings(stats::median(b_dn[is.finite(b_dn)]))
  if (!is.finite(med_s) || !is.finite(med_d)) return(1)   # 적재를 한 이름도 못 읽으면 위험모형이 없다
  b_sym[!is.finite(b_sym)] <- med_s            # 모름은 보유 중앙 — 지목 근거로 삼지 않는다
  b_dn[!is.finite(b_dn)]   <- med_d
  b <- (1 - w_dn) * b_sym + w_dn * b_dn
  if (!all(is.finite(b))) return(1)

  # ── ⑦ 고유분산 s² — ovol·sqrt(1−bcorr²) 의 제곱. 수준은 지금 횡단면분산 / 자기 이력 중앙의 비로 맞춘다
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  if (length(ov) != n_h) ov <- rep(NA_real_, n_h)
  if (length(bc) != n_h) bc <- rep(NA_real_, n_h)
  bc <- pmax(-1, pmin(1, bc))                  # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  s_i <- ov * sqrt(pmax(0, 1 - bc * bc))
  med_i <- suppressWarnings(stats::median(s_i[is.finite(s_i)]))
  if (!is.finite(med_i) || med_i < 0) return(1)
  s_i[!is.finite(s_i)] <- med_i
  xs_v <- suppressWarnings(as.numeric(H$xs))[seq_len(tt)]
  xs_v <- xs_v[is.finite(xs_v)]
  rho <- 1                                     # 배율을 못 재면 1 — 없는 수준 변화를 만들지 않는다
  if (length(xs_v) >= nmin) {
    xs_med <- suppressWarnings(stats::median(xs_v))
    xs_now <- xs_v[length(xs_v)]
    if (is.finite(xs_med) && xs_med > 0 && is.finite(xs_now) && xs_now > 0) rho <- xs_now / xs_med
  }
  s2 <- (s_i * s_i) * rho

  # ── ⑧ 시장(공통) 분산 수준 v_f — 지금 실현변동성의 제곱. 못 읽으면 자기 이력 중앙으로.
  rv <- suppressWarnings(as.numeric(H$rv60))[seq_len(tt)]
  v_lvl <- rv[length(rv)]
  if (!is.finite(v_lvl) || v_lvl <= 0) v_lvl <- suppressWarnings(stats::median(rv[is.finite(rv)]))
  if (!is.finite(v_lvl) || v_lvl <= 0) return(1)
  v_f <- v_lvl * v_lvl

  # ── ⑨ 한계 위험기여 — c_i 를 1 늘릴 때 줄어드는 책의 스트레스 분산.
  #   비중은 주어지지 않으므로 등가중으로 대용한다(w_i = 1/n): B = Σ w_j b_j = mean(b).
  #   공통항 v_f·b_i·B 는 책 전체에 실린 몫이고, 고유항 w_i·s_i² 는 그 이름 안에만 남는 몫이다.
  wt <- 1 / n_h
  B  <- sum(wt * b)
  mcr <- v_f * b * B + wt * s2
  if (!all(is.finite(mcr))) return(1)
  mcr_p <- pmax(0, mcr)                        # 음의 기여 = 깎으면 위험이 오르는 이름 → 감액 0
  if (sum(mcr_p) <= 0) return(1)               # 깎아서 줄어드는 위험이 없다 = 이 층의 일이 아니다
  sd_m <- suppressWarnings(stats::sd(mcr_p))
  if (!is.finite(sd_m) || sd_m <= 0) return(1) # 기여가 완전 균등 = 횡단면 차등 미성립 → 무개입

  # ── ⑩ 예산 배분 — 총 감액 = (g/2)·n (평균 노출 1 − g/2, 선행과 동일) · 이름별 상한 g(램프와 동일).
  #   상한에 걸린 이름의 잔여 예산은 남은 이름들의 기여 비례로 다시 나눈다(경계 투영).
  tol    <- 1e-12
  budget <- (g / 2) * n_h
  cut    <- rep(0, n_h)
  for (it in seq_len(12L)) {
    rem <- budget - sum(cut)
    if (!is.finite(rem) || rem <= tol) break
    fr <- (mcr_p > 0) & (cut < g - tol)
    if (!any(fr)) break                        # 전원이 상한 — 예산을 덜 쓰고 끝낸다(보수적 폴백)
    sm <- sum(mcr_p[fr])
    if (!is.finite(sm) || sm <= 0) break
    cut[fr] <- pmin(g, cut[fr] + rem * mcr_p[fr] / sm)
  }
  e <- pmax(0, pmin(1, 1 - cut))
  if (!all(is.finite(e))) return(1)

  data.table::data.table(Ticker = as.character(hold$Ticker), e = e)
}
