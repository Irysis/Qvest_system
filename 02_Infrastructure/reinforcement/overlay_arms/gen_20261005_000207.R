#==============================================================================
# gen_20261005_000207 — 학습 예보를 '순위 램프' 가 아니라 '종목별 위험예산' 으로 전달하는 트림
#   target cell: action = cross_sectional · state = ml (기전 지도 표적 칸 · 측정 8 · 카탈로그 3 · 미포화)
#
# ★기전
#   이 칸의 기존 arm 2종(ml_dual_forecast_tilt · ml_posterior_loading_tilt)은 확장창 학습으로 채널
#   배율을 세운 뒤 보유의 예측 하방 산포 L 의 **보유 내 순위** r 로 e = 1 - g*r 을 준다. 순위 램프는
#   척도불변이라 두 가지를 버린다: ①L 이 기준을 얼마나 넘는지(크기) ②책의 L 이 균질한지 흩어졌는지.
#   전원의 L 이 같아도 상단은 g 만큼 깎이고, L 이 수십 배 갈려도 램프의 모양은 같다. 깊이는 g 가 따로
#   정하므로 **학습 예보의 수준은 노출에 직접 실리지 않는다** — 순서와 g 를 통해서만 들어온다.
#   한편 예산 사상 e = min(1, 예산/위험) 은 이 저장소에 이미 있으나 책 수준 스칼라 하나로만 있다
#   (book_risk_budget_brake · family = holding_level — 어떤 이름이 그 위험을 나르는지는 묻지 않는다).
#   그 사상을 **종목축으로 옮기고 위험 쪽을 학습 예보로 denominate** 하는 것이 이 칸의 미측정 내용이다.
#   램프를 지우고 각 보유에 e_i = min(1, b / L_i) 를 준다. 세 성질이 따라온다:
#     ①깊이가 예보 수준에 연속으로 비례한다 — g 의 중앙 문턱(예보가 자기 적합값 중앙 아래인 달은
#       전면 무개입)이 없어 평상월에도 꼬리 이름만 조용히 깎인다.
#     ②책이 균질한 달에는 스스로 침묵한다(전원 e=1) — 램프는 그 달에도 차등을 만든다.
#     ③차등이 순서가 아니라 배율이라 L 이 꼬리로 벌어진 이름만 깊게 깎인다.
#   예보 머리도 사상이 요구하는 denomination 으로 맞춘다 — 예산은 위험 척도라 1차모멘트(평균 손실폭)가
#   아니라 2차모멘트가 필요하다. 그래서 익월 하방 **2차모멘트** 를 학습하고 그 제곱근(하방 준편차)을 쓴다.
#   예산을 시장 척도로 잡지 않는 이유: 한 이름의 위험은 분산된 시장·책보다 늘 크므로 시장 준편차를
#   종목에 대면 전 종목 상시 대폭 축소로 떨어진다. 예산은 **그 책의 보통 이름**(기준 상태 L 의 횡단면
#   중앙)에서 뽑는다 — 구성 성분과 상태 성분이 e_i = min(1, (b/L_ref,i)·(L_ref,i/L_i)) 로 분리된다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e in [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd 의 t 행은 미실현이라 읽지 않는다 — 학습쌍은 i <= t-1 만 쓴다.
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 상태 예보는 확장창 과거쌍 회귀, 기준 상태는 그 모형 자기 적합값 경로의 중앙,
#   산포 국면은 학습 표본 중앙 대비 배수, 예산은 그 달 횡단면 중앙에서 나온다.
#   보유 없음·표본 부족·적합 실패·유한 적재 2종 미만이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20261005_000207 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                       # 학습쌍이 60개월 미만이면 모형을 말하지 않는다(칸 공통 하한)

  # ── ① 상태 예보 — 확장창 과거쌍만(i <= t-1). 축은 이 칸의 선행과 같은 4종으로 고정했다.
  idx <- seq_len(t - 1L)                       # 결과가 실현된 쌍만
  fw  <- as.numeric(H$fwd[idx])
  trd <- data.frame(
    yd = pmax(0, -fw)^2,                       # 익월 하방 2차모멘트 재료 (상승월 = 0)
    yx = as.numeric(H$xs[idx + 1L]),           # 익월 실현 횡단면분산 — i+1 <= t 라 관측됐다
    f1 = as.numeric(H$rv60[idx]),
    f2 = as.numeric(H$dd[idx]),
    f3 = as.numeric(H$r252[idx]),
    f4 = as.numeric(H$xs[idx]))
  trd <- trd[stats::complete.cases(trd), , drop = FALSE]
  if (nrow(trd) < 60L) return(1)

  nd <- data.frame(f1 = as.numeric(H$rv60[t]), f2 = as.numeric(H$dd[t]),
                   f3 = as.numeric(H$r252[t]), f4 = as.numeric(H$xs[t]))
  if (!all(is.finite(unlist(nd)))) return(1)

  fitD <- tryCatch(suppressWarnings(stats::lm(yd ~ f1 + f2 + f3 + f4, data = trd)),
                   error = function(z) NULL)
  fitX <- tryCatch(suppressWarnings(stats::lm(yx ~ f1 + f2 + f3 + f4, data = trd)),
                   error = function(z) NULL)
  if (is.null(fitD) || is.null(fitX)) return(1)
  pd <- tryCatch(suppressWarnings(as.numeric(stats::predict(fitD, nd))), error = function(z) NA_real_)
  px <- tryCatch(suppressWarnings(as.numeric(stats::predict(fitX, nd))), error = function(z) NA_real_)
  if (!is.finite(pd) || !is.finite(px)) return(1)

  s_now <- sqrt(max(0, pd))                    # 예측 체계 하방 준편차 (월 단위 수익률)
  fdv <- as.numeric(stats::fitted(fitD)); fdv <- fdv[is.finite(fdv)]
  if (length(fdv) < 60L) return(1)
  s_ref <- stats::median(sqrt(pmax(0, fdv)))   # 모형 자기 예측 경로의 중앙 = 기준 상태(상수 문턱 아님)
  if (!is.finite(s_ref)) return(1)             # s_ref = 0 은 죽은 달이 아니다 — 예산이 고유 채널로만 선다(아래 b)

  xref <- stats::median(trd$yx)                # 학습 표본의 평상시 횡단면분산
  rho  <- if (is.finite(xref) && xref > 0) max(0, px) / xref else 1   # 산포 국면 배수(무차원)
  if (!is.finite(rho) || rho <= 0) rho <- 1

  # ── ② 적재 — 체계 하방 채널 + 고유 채널의 직교합. 형태는 이 칸의 선행과 같게 두었다
  #    (갈리는 인자를 'L -> e 사상' 하나로 만들기 위해서다).
  db    <- suppressWarnings(as.numeric(hold$dbeta))
  bfull <- suppressWarnings(as.numeric(hold$beta))
  if (length(bfull) == length(db)) {
    gap <- !is.finite(db) & is.finite(bfull)
    db[gap] <- bfull[gap]                      # 하방 적재 결측 = 전구간 적재로 후퇴(책 커버리지 보존)
  }
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  sysl <- pmax(0, db)                          # 음의 적재는 0 에서 자른다 — 가짜 헤지를 믿지 않는다
  idio <- ov * sqrt(pmax(0, 1 - bc * bc)) / sqrt(12)   # 월 단위 특이변동
  L_now <- sqrt((sysl * s_now)^2 + (idio * rho)^2)     # 지금 상태에서의 예측 하방 준편차
  L_ref <- sqrt((sysl * s_ref)^2 + idio^2)             # 기준 상태(예보 중앙 · 산포 배수 1)에서의 같은 양
  ok <- is.finite(L_now) & is.finite(L_ref) & L_now > 0
  if (sum(ok) < 2L) return(1)                  # 차등을 세울 수 없으면 무개입

  # ── ③ 예산 b — 기준 상태에서 이 책의 '보통 이름' 위험(횡단면 중앙). 시장 척도를 종목에 대지 않는다.
  b <- stats::median(L_ref[ok])
  if (!is.finite(b) || b <= 0) return(1)

  # ── ④ 노출 = min(1, 예산/위험). 증액은 하지 않는다(e <= 1) · 예산 이하 이름은 그대로 둔다.
  e <- rep(1, length(L_now))                   # 값 없는 이름은 무개입 — 유·불리 어느 쪽도 아니다
  e[ok] <- pmin(1, b / L_now[ok])
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, e)))
}
