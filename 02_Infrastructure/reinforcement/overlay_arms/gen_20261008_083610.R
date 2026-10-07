#==============================================================================
# gen_20261008_083610 — 기억 길이 모호성 아래 **이름별 최악 멤버**로 세우는 횡단면 트림
#   (v10.4 2026-10-08 · target cell: action = cross_sectional · state = ml · 측정 8 · 카탈로그 6 · 미포화)
#
# ★기전
#   이 칸의 선행 6종은 전부 **모형을 하나 골라** 그 점예보를 쓴다. 상태층은 예외 없이
#   (rv60, dd, r252, xs) 4축이고 표본은 확장창 전부다 — 즉 '위험을 어느 기억 길이로 재는가' 와
#   '계수를 얼마나 먼 과거까지로 적합하는가' 를 각각 한 번 골라 버린다. 그 선택은 약식별이다:
#   월별 표본에서 변동성 창을 바꿔도 표본외 손실 차이는 표집오차에 묻히는 쪽이 보통이다.
#   그런데 선택이 바뀌면 **체계 충격 예보 s 와 산포 예보 k 의 비**가 바뀌고, 그 비가 종목 순서를
#   회전시킨다(선행 1종이 그 회전을 '상태가 축을 돌린다' 로 썼다 — 다만 모형 하나 안에서).
#   그러니 이 칸의 선행이 내놓은 순서는 전부 **고르지 않았다면 달랐을 순서**다.
#   이 arm 은 고르지 않는다. 기억 길이로 색인된 모형 집합을 전부 적합하고, **표본외에서 자격을
#   번 멤버만** 남긴 뒤, 각 이름을 **그 이름에게 가장 불리한 멤버**로 평가한다(Γ-maximin).
#   핵심 산술은 하나다:
#        max_m sqrt((b_i·s_m)^2 + (u_i·k_m)^2)  ≠  sqrt((b_i·max_m s_m)^2 + (u_i·max_m k_m)^2)
#   체계 채널 b_i 가 큰 이름은 '시장 충격' 을 말하는 멤버를, 고유 채널 u_i 가 큰 이름은 '산포 국면'
#   을 말하는 멤버를 각자 적대 시나리오로 집어 든다. 그래서 순위는 어느 한 멤버 점예보 순위의
#   단조변환이 **아니다** — 깎이는 쪽은 '위험이 큰 이름' 이 아니라 **다투는 시나리오 중 하나에서
#   무너지는 이름**이다. 집합이 한 점으로 수축하면(멤버 하나만 자격을 벌거나 전부 같은 비를 내면)
#   이 arm 은 선행의 점예보 판으로 되돌아간다(자기 소멸 · 거짓 차이를 만들지 않는다).
#   세 자리가 그 때문에 바뀐다.
#     ① **집합을 쓴다** — 위험 기억 축 13(실현창 3 + EWMA 감쇠 10종) × 표본 최근성 2(전구간 ·
#        최근 절반) = 최대 26 멤버. 두 축 다 arm 이 지어낸 값이 아니라 엔진 특징표가 이미 들고 있는
#        기억 길이의 열거다. 선행은 그 중 (rv60, 전구간) 한 칸만 썼다.
#     ② **자격 심사가 집합을 정한다** — 멤버는 LOO(해트 보정) 제곱오차로 무조건부 평균을 이겨야
#        들어온다(θ > 0). 못 번 멤버는 빠지고, 전부 못 벌면 e = 1 로 침묵한다. 모호성은 '아무 모형이나
#        다 센다' 가 아니라 **표본외에서 살아남은 모형들 사이의 다툼**이다.
#     ③ **깊이·예산은 가족 규약 그대로** — 깊이 g 는 멤버별 '오늘 예보가 자기 적합 경로 안에서 차지한
#        분위' 의 집합 평균이 중앙 위일 때만 켜지고, 램프도 e = 1 − g·r(횡단면 평균 1 − g/2)로 고정했다.
#        최악 시나리오는 **순서에만** 들어간다 — 갈리는 인자를 '순서를 만든 양' 하나로 좁히기 위해서다.
#
# ★가정(정직하게 적는다)
#   ①Γ-maximin 은 멤버 사이 사전확률을 거부하는 결정규칙이다. 집합이 넓으면 과하게 보수적이고,
#     여기서는 그 보수성이 순서에만 실려 예산(1 − g/2)은 가족과 같게 묶여 있다.
#   ②멤버는 상태 4축 중 변동성 축만 교체한 같은 함수형이다 — 함수형 자체의 모호성(선형 대 비선형)은
#     집합에 없다. 최근성 축이 계수의 모호성을 일부 대신한다.
#   ③하방·상방 비대칭은 체계 적재(하락측)와 고유변동으로만 들어간다. 고유 채널은 전체 변동이라
#     대칭 분산으로 denominate 되고 체계 채널만 하방으로 denominate 된다 — 고유 쪽이 과대평가되는
#     방향이고, 그 비대칭은 이 arm 의 주장에 유리하지 않다(보수적).
#   ④합성 픽스처에서는 감쇠 계열이 rv60 의 양의 배수라 표준화 후 멤버가 한 점으로 접힌다 —
#     집합이 실제로 벌어지는 것은 엔진 특징표에서다. 그때 이 arm 은 선행 1종의 형태로 떨어진다
#     (통과를 벌기 위한 분기가 아니라 설계된 축소 경로다).
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e in [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd 의 t 행은 신호일에 미실현 — 읽지 않는다. 학습쌍은 i <= t−1 만
#     쓴다(그때 fwd[i] 와 xs[i+1] 의 관측 시점이 t 이하로 확정된다).
#   ctx$hold = 보유 상태(beta · dbeta=하락측 적재 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 능형 강도(차원/(차원+표본))·신뢰도 θ·멤버 표본 하한(가족 하한의 절반)·
#     개입 시작점(경로 중앙)·산포 무차원화(그 멤버 표본 중앙)가 전부 그 시점 확장창에서 나온다.
#   보유 없음·표본 부족·적합 실패·자격 멤버 0·유한 채널 2종 미만 = e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20261008_083610 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                           # 학습쌍 60개월 미만이면 모형을 말하지 않는다(칸 공통 하한)
  eps <- .Machine$double.eps

  # ── ① 기억 길이 열거 — 실현창 3 + EWMA 감쇠 10종. arm 이 고르는 값이 아니라 특징표에 있는 그대로다
  vnm <- c("rv20", "rv60", "rv120", paste0("ew", seq_len(10L)))
  vnm <- vnm[vnm %in% names(H)]
  if (!length(vnm)) return(1)

  # ── ② 학습쌍 — 결과가 실현된 과거쌍만(i <= t−1). t 행의 익월 수익은 읽지 않는다.
  #   멤버끼리 비교 가능하게 **행 집합은 공통**으로 둔다(기억 축 전부가 유한한 달만) — 멤버가 갈리는 것은
  #   어느 열이 들어오는가와 어디서부터 적합하는가뿐이다.
  idx <- seq_len(t - 1L)
  vmt <- vapply(vnm, function(z) as.numeric(H[[z]][idx]), numeric(length(idx)))
  big <- cbind(vmt, as.numeric(H$dd[idx]), as.numeric(H$r252[idx]), as.numeric(H$xs[idx]),
               pmax(0, -as.numeric(H$fwd[idx])), as.numeric(H$xs[idx + 1L]))
  big <- big[stats::complete.cases(big), , drop = FALSE]
  nn  <- nrow(big)
  nfl <- 60L                                       # 모수(절편 + 상태 4축)당 12개월 — 가족 하한
  nmn <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmn) == 1L && !is.na(nmn)) nfl <- max(nfl, nmn)
  if (nn < nfl) return(1)
  nv  <- length(vnm)
  vmf <- big[, seq_len(nv), drop = FALSE]          # 기억 축 후보 블록
  ddv <- big[, nv + 1L]; rrv <- big[, nv + 2L]; xsv <- big[, nv + 3L]
  ydn <- big[, nv + 4L]                            # 익월 시장 하방 손실폭 max(0, −fwd)
  ydp <- big[, nv + 5L]                            # 익월 실현 횡단면산포 xs[i+1] (i+1 <= t 라 관측됨)
  cnw <- c(as.numeric(H$dd[t]), as.numeric(H$r252[t]), as.numeric(H$xs[t]))
  if (any(!is.finite(cnw))) return(1)
  vnw <- vapply(vnm, function(z) as.numeric(H[[z]][t]), numeric(1))

  # ── ③ 멤버 하나 — 능형 적합 + LOO 자격 심사. 자격을 못 벌면 집합에 들어오지 못한다(NULL)
  fit_mem <- function(rws, vcl, vnv) {
    nm  <- length(rws)
    Xm  <- cbind(vcl[rws], ddv[rws], rrv[rws], xsv[rws])
    nax <- ncol(Xm)
    if (nm * 2L < nfl) return(NULL)                # 멤버 표본 하한 = 가족 하한의 절반(최근성 멤버는 정의상 절반이다)
    mu  <- colMeans(Xm)
    sdv <- vapply(seq_len(nax), function(j) stats::sd(Xm[, j]), numeric(1))
    if (any(!is.finite(mu)) || any(!is.finite(sdv)) || any(sdv <= 0)) return(NULL)
    Zm  <- sweep(sweep(Xm, 2, mu, "-"), 2, sdv, "/")      # 표준화 — 4축은 서로 겹친다(변동성 창·산포)
    znw <- (c(vnv, cnw) - mu) / sdv
    if (any(!is.finite(Zm)) || any(!is.finite(znw))) return(NULL)
    lam <- nax / (nax + nm)                        # 능형 강도 = 차원/(차원+표본) — 상수가 아니라 표본이 정한다
    gxx <- vapply(seq_len(nax), function(j)
             vapply(seq_len(nax), function(k) sum(Zm[, j] * Zm[, k]), numeric(1)), numeric(nax))
    if (any(!is.finite(gxx))) return(NULL)
    Ai  <- tryCatch(solve(gxx + diag(lam * mean(diag(gxx)), nax)), error = function(z) NULL)
    if (is.null(Ai) || any(!is.finite(Ai))) return(NULL)
    hdg <- 1 / nm + rowSums((Zm %*% Ai) * Zm)      # 해트 대각(중심화 절편 1/n 포함) — LOO 보정에 쓴다
    if (any(!is.finite(hdg))) return(NULL)
    one_head <- function(yv) {                     # 한 머리 — 적합 경로 · 오늘 예보(신뢰도 축소 후) · 신뢰도
      ybr <- mean(yv)
      cfv <- as.numeric(Ai %*% vapply(seq_len(nax), function(j) sum(Zm[, j] * (yv - ybr)), numeric(1)))
      ftv <- ybr + as.numeric(Zm %*% cfv)
      rsl <- (yv - ftv) / pmax(1 - hdg, eps)       # LOO 잔차(해트 보정)
      rs0 <- (yv - ybr) / (1 - 1 / nm)             # 무조건부 평균의 LOO 잔차
      s1  <- sum(rsl * rsl); s0 <- sum(rs0 * rs0)
      th  <- if (is.finite(s1) && is.finite(s0) && s0 > 0) max(0, min(1, 1 - s1 / s0)) else 0
      if (!(th > 0)) return(list(path = rep(ybr, nm), now = ybr, th = 0))
      list(path = ybr + th * (ftv - ybr), now = ybr + th * sum(cfv * znw), th = th)
    }
    hdd <- one_head(ydn[rws])
    if (!(hdd$th > 0)) return(NULL)                # 표본외에서 번 것이 없는 멤버는 다툴 자격이 없다
    hxs <- one_head(ydp[rws])
    mdp <- stats::median(ydp[rws])                 # 그 멤버 표본의 산포 중앙 — 무차원화 기준
    if (!is.finite(mdp) || mdp <= 0) return(NULL)
    spt <- stats::sd(hdd$path)
    qpt <- if (is.finite(spt) && spt > 0) stats::ecdf(hdd$path)(hdd$now) else 0.5
    list(s = max(0, hdd$now), k = max(0, hxs$now) / mdp, q = qpt)
  }

  # ── ④ 집합 — 기억 축 × 표본 최근성. 자격 심사를 통과한 멤버만 남는다
  rwl <- list(seq_len(nn), (nn - floor(nn / 2) + 1L):nn)
  mem <- list()
  for (ia in seq_along(vnm)) {
    if (!is.finite(vnw[ia])) next
    for (ib in seq_along(rwl)) {
      zmm <- fit_mem(rwl[[ib]], vmf[, ia], vnw[ia])
      if (!is.null(zmm)) mem[[length(mem) + 1L]] <- zmm
    }
  }
  if (!length(mem)) return(1)                      # 아무도 표본외에서 벌지 못했다 = 무개입

  # ── ⑤ 깊이 g — 집합 평균 분위가 경로 중앙 위일 때만 (가족 규약 · 상수 문턱 아님)
  qbr <- mean(vapply(mem, function(z) as.numeric(z$q), numeric(1)))
  g <- max(0, min(1, (qbr - 0.5) / 0.5))
  if (!is.finite(g) || g <= 0) return(1)

  # ── ⑥ 두 채널 — 체계(하락측 적재)·고유(시장과 무관한 변동). 가족과 같은 형태로 고정했다
  bdn <- suppressWarnings(as.numeric(hold$dbeta))
  bal <- suppressWarnings(as.numeric(hold$beta))
  ovl <- suppressWarnings(as.numeric(hold$ovol))
  bcr <- suppressWarnings(as.numeric(hold$bcorr))
  gpd <- !is.finite(bdn) & is.finite(bal)
  bdn[gpd] <- bal[gpd]                             # 하락측 적재 결측 = 전구간 적재로 후퇴
  bsy <- pmax(0, bdn)                              # 음의 하락측 적재(진짜 헤지)는 체계 기여 0
  uid <- ovl * sqrt(pmax(0, 1 - bcr * bcr)) / sqrt(12)   # 월 단위 고유변동
  bsy[!is.finite(bsy)] <- 0
  uid[!is.finite(uid)] <- 0                        # 고유 채널 추정 없음 = 체계 채널로만 잰다
  okn <- (bsy + uid) > 0
  if (sum(okn) < 2L) return(1)                     # 비교할 이름이 둘 미만이면 무개입

  # ── ⑦ 이름별 최악 멤버 — 각 이름이 자기에게 가장 불리한 시나리오를 집어 든다(Γ-maximin)
  wst <- rep(0, length(bsy))
  for (ia in seq_along(mem)) {
    smm <- mem[[ia]]$s; kmm <- mem[[ia]]$k
    if (!is.finite(smm) || !is.finite(kmm)) next
    wst <- pmax(wst, sqrt((bsy * smm)^2 + (uid * kmm)^2))
  }
  if (!any(is.finite(wst) & wst > 0)) return(1)    # 모든 시나리오에서 0 = 순서가 없다

  # ── ⑧ 램프 — 예산·감액 범위는 이 칸의 램프 계열과 같다(갈린 것은 순서를 만든 양이다)
  rnk <- rep(0.5, length(wst))                     # 채널 추정이 없는 이름은 중앙 — 유·불리 어느 쪽도 아니다
  rnk[okn] <- (rank(wst[okn], ties.method = "average") - 0.5) / sum(okn)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * rnk)))
}
