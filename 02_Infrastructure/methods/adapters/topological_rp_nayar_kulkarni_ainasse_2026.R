# topological_rp_nayar_kulkarni_ainasse_2026.R — arXiv 2604.16773 "Topological Risk Parity"(Nayar · Ainasse · Kulkarni, 2026) —
#   변형 (i) TRP-MST: 뿌리 있는 최소 신장 나무(rooted MST) 배분기(2026-11-11 · 비중 카탈로그 후보 · 독립 구현 — 레인 엔진 코드 미참조).
#
# 원문 = arXiv LaTeX 원본(TRPtex.tex · mcp arxiv get_paper_latex_section). 절 번호 = LaTeX 절. ★주의: 원본의 §6 후반 · §7 · §8.3 · §9 는
#   `\begin{commentg}` 환경 안에 있고 전문(preamble)이 `\excludecomment{commentg}` 라 **컴파일된 PDF 에는 안 나온다**. 아래 인용 중
#   그 범위에서 온 것은 [숨은 절] 로 표시했다(정의 · 식은 모두 숨지 않은 §4 · §5 · 부록 §11 · §13 에서 온다).
#
# 논문 메커니즘(변형 I · §4 · §5.1 · 부록 §11 원문):
#   ① 활동 필터(§4.1 식 eq:active-set): m_i := (1/k) Σ_{t=T−k+1}^T |r_it| · 𝒜 := { i : m_i > ε, |s_i| > τ } ·
#      'In our baseline specification we take τ = 10^{-3}'. (k · ε 의 수치는 논문에 없다 — 아래 '구현이 정한 것' ①)
#   ② 상관 · 거리(§4.2 식 eq:mantegna-distance): C = corr(R^(A)) · 'The implementation clips C entrywise to [−1,1], replaces NaNs by zero,
#      and symmetrizes.' · D_ij = sqrt((1 − C_ij)/2). 완전 가중 그래프 G = (V, E, D) 의 최소 신장 나무 MST(G).
#      (참고 문헌에 Kruskal 1956 · Prim 1957 — 알고리즘 지정은 없다. 동률이 없으면 MST 는 유일하므로 알고리즘은 결과를 바꾸지 않는다.)
#   ③ 뿌리(§5.1 Step 2): 'hub mode: a node of maximal degree in the MST; max-magnitude mode: a node with maximal |s_i|;
#      fixed-index mode: a designated index, often the first active node.' — 뿌리에서 바깥으로 방향을 준다(부모 · 자식 유일).
#      b(u) := |Ch(u)|(자식 수 = 분기수).
#   ④ 전파 계수(§5.1 Step 3 식 eq:alpha): 'Fix a parameter ρ ∈ [0,1]. For each internal node u with b(u) ≥ 1,
#      α_u(ρ) := (1 − ρ) + ρ / b(u). This is the key propagation coefficient.'
#   ⑤ 위상 인자(§5.1 Step 4 식 eq:recursive-g · eq:path-product): g_r = 1 · g_v = α_pa(v)(ρ) g_pa(v) = Π_{u ∈ Path(r,v)} α_u(ρ)
#      (Path = 뿌리 포함 · v 제외 조상). ★'비중을 전부 내려보내지 않는다'(초록 'there is imperfect correlation between parent and child
#      nodes, and thus does not propagate weights entirely to the children')의 구현은 이것이다 — 내부 노드도 자산이라 자기 인자 g_u 를
#      그대로 갖고, 자식 각각은 α_u g_u 를 받는다(HRP 처럼 부모 몫을 자식에게 전부 쪼개 넘기지 않는다). ρ < 1 이면 자식 합
#      Σ_{Ch(u)} g_v = (b(u)(1−ρ)+ρ) g_u ≥ g_u(§6.2 식 eq:beta — 비보존).
#   ⑥ 사전 정규화(§5.1 Step 5): 'The implementation uses the original signal, not a volatility-rescaled signal: x_v = s_v^(A) g_v.'
#   ⑦ 정규화(§5.1 Step 6 식 eq:normalized-weights · 부록 §11 식 eq:compact-final): w_v = L x_v / ‖x‖_1 · 비활성 자산 = 0.
#      변형 I 에는 후처리(clip · 문턱 — 식 eq:postprocess)가 없다('Unlike Variant I, the Semi-Supervised TRP variant then applies
#      post-processing' · §5.2). 부분 나무 질량 S_u 는 변형 I 에서 안 쓴다(§5.1 Remark · 부록 §13.2) — 구현하지 않는다.
#
# 변형 (ii) Semi-Supervised TRP(TRP-SPY/XL · §5.2 — SPY 가상 뿌리 + 'ticker begins with XL' 업종 ETF 11개 둘째 층 + DFS 신장 나무 +
#   clip/문턱 후처리)는 **구현하지 않는다**: ctx 에는 지수 · 업종 ETF 수익 계열이 없다(ctx = 선택 종목의 일별 수익뿐). 업종 라벨로
#   흉내 내면 논문 밖 사상이 되고 ctx 밖 자료(PIT 경계)를 읽어야 한다.
#
# KR 롱온리 사상(우리 축: long-only · ≤25종 · Σw ≤ 1 — 종목 선택은 엔진이 한다 · 이 어댑터는 선택된 종목의 비중만 정한다):
#   · 논문의 부호 신호 s 는 외생이고 롱숏용이다(초록 'intended for long/short, market neutral, factor-aware portfolios'). 롱온리 축에서는
#     받은 종목이 전부 매수 후보이므로 **s_i = +1(전부 · 크기 1)** 로 둔다 → x_v = g_v · w ∝ g. 남는 것은 위상(나무 기하) 인자뿐이다.
#     ctx$mu 의 크기를 싣지 않는다(점수 크기를 싣는 판은 논문 밖 사상 — 나중에 다른 이름의 변형으로 구분한다).
#   · 이 사상에서 논문의 시장 중립 · 헤지 성질(롱숏 부호 보존 · 층별 Σw = 0 중립화 — §5.2 · [숨은 절] §8.1 ②)은 **작동하지 않는다**.
#     남는 기전 = 나무에서 깊은(분기를 많이 거친) 종목일수록 비중이 줄고, 허브(뿌리)와 얕은 노드가 크다.
#   · 음수 비중: s > 0 · g > 0(α_u ∈ (0, 1] — ρ ∈ [0,1] · b ≥ 1) 이라 w > 0 이 항상 성립한다(§6.3 Sign preservation). 음수 처리 불필요.
#   · L(목표 총 레버리지) = 1 — 롱온리 Σw = 1 이 L = 1 · ‖x‖_1 정규화와 같다(합 정규화 · 롱온리 강제는 wrap_adapter 가 다시 한다).
#
# ── 논문이 준 것 / 이 구현이 정한 것 ───────────────────────────────────────────────────────────────────────────────────────────────
#   논문이 준 것: 거리 D = sqrt((1−C)/2) · C 의 clip · NaN→0 · 대칭화 · MST · 세 뿌리 규칙 · α_u = (1−ρ)+ρ/b(u) · g 의 경로곱 · x = s·g ·
#     L1 정규화 · 비활성 = 0 · τ = 1e-3 · 변형 I 후처리 없음.
#   이 구현이 정한 것:
#     ① 활동 필터 창 k = T(ctx$R 전 행 · 논문 조건 k ≤ T 의 가장 단순한 값) · ε = 0(m_i > 0 — 논문은 'ε > 0' 만 요구하고 수치를 주지
#        않는다 · 가장 단순한 처리 = 창 전체에서 절대 수익이 전부 0 인 종목만 뺀다). τ = 1e-3 는 논문값이지만 s ≡ 1 이라 늘 통과.
#     ② ρ = 1(TRP_RHO): **논문은 ρ 의 수치를 주지 않는다**(§5.1 'Fix a parameter ρ ∈ [0,1]'). ρ = 0 은 '정규화된 원 신호'(§6.1 Limit
#        cases (a))라 s ≡ 1 에서 정확히 EW — 위상이 사라진다. 논문이 이름을 붙인 비퇴화 값은 ρ = 1 하나뿐이다(§6.1 (b) 'conservative
#        equal-split rooted-tree method' · §5.2 Remark 'the equal-split conservative limit corresponds to setting ρ=1' · 부록 §12
#        'topological risk parity: use only for conservative, risk-based variants, not for the generic TRP-MST construction when ρ<1').
#        중간값(예: 0.5)은 논문에 없다 — 지어내지 않는다. 그래서 ρ = 1 단일 사전 고정(스윕 없음). 다른 ρ 는 다른 이름의 변형이다.
#     ③ 뿌리 규칙 = hub mode(최대 차수). 논문은 세 규칙 중 기준을 정하지 않는다. s ≡ 1 에서 max-magnitude mode 는 전원 동률이라 동률
#        처리 규칙(이름순)만 남아 기하와 무관한 노드가 뿌리가 되고, fixed-index mode('often the first active node')는 자산 순서에
#        의존한다(치환 불변 깨짐). 기하를 쓰는 규칙은 hub 하나라 hub 를 고른다.
#     ④ 동률 처리(결정적 · 자산 순서 치환 불변): MST 는 Kruskal — 간선을 (D 오름차순, 작은 이름, 큰 이름) 사전순으로 정렬해 고른다.
#        hub 동률은 이름이 가장 작은 노드. 문자열 정렬은 method = "radix"(C 로캘 바이트 순 — 로캘 무관). 이름 = ctx$assets.
#     ⑤ 상관 = 표본 상관 stats::cor(ctx$R[, assets], use = "pairwise.complete.obs")(논문 '`sample correlation matrix`' — 결측 처리는
#        논문에 없다 · ctx$R 은 보통 결측 없는 창이다). ctx$Sigma 는 쓰지 않는다(논문은 수익 이력에서 상관을 만든다).
#     ⑥ 활성 종목이 0 이면 stop(래퍼가 이름을 부르고 EW 폴백) · 1 이면 그 종목 1(나무 = 노드 하나 · g_r = 1).
#
# 성질(시험이 지키는 것): 수익 척도 변화 r_i → a_i r_i + c_i(a_i > 0)에 불변(상관 불변 · m_i > 0 판정 불변) · 자산 순서 치환에 공변 ·
#   결정적(난수 없음).
# PIT: ctx$R 은 엔진이 Date < 신호일로 자른 창이다(C1 · C2 · C9). 어댑터는 ctx 밖을 보지 않는다. 전기간 통계 없음.
# 진단 줄: 호출마다 '[trp] d=… n=… root=… depth=… leaves=… active=…' 한 줄(n = 받은 종목 수 · root = 뿌리 이름 · depth = 나무 최대 깊이 ·
#   leaves = 자식 없는 노드 수 · active = 활동 필터 통과 수 — 성과 수치 아님).
# 반환: 선호 벡터(이름 = ctx$assets · 비음). long-only · Σw = 1 은 wrap_adapter(method_registry.R)가 강제한다.

TRP_RHO <- 1      # §5.1 식 eq:alpha 의 ρ — 논문 수치 없음 · 비퇴화 명명 극한(§6.1 (b) · §5.2 Remark · §12) — 머리말 '정한 것' ②
TRP_TAU <- 1e-3   # §4.1 'In our baseline specification we take τ = 10^{-3}'
TRP_EPS <- 0      # §4.1 ε — 논문 수치 없음 · 가장 단순한 값(m_i > 0) — 머리말 '정한 것' ①

## §4.2 — 상관(clip · NaN→0 · 대칭화) → Mantegna 거리
.trp_distance <- function(X) {
  C <- suppressWarnings(stats::cor(X, use = "pairwise.complete.obs"))
  C[!is.finite(C)] <- 0
  C <- pmin(pmax(C, -1), 1)
  C <- (C + t(C)) / 2
  diag(C) <- 1
  D <- sqrt((1 - C) / 2)
  dimnames(D) <- list(colnames(X), colnames(X))
  D
}

## MST(Kruskal · 결정적 동률 처리 — 머리말 ④). 반환 = 간선 행렬(이름 2열)
.trp_mst <- function(D) {
  nm <- colnames(D); n <- length(nm)
  if (n < 2L) return(matrix(character(0), ncol = 2L))
  ij <- which(upper.tri(D), arr.ind = TRUE)
  rk <- integer(n); rk[order(nm, method = "radix")] <- seq_len(n)   # 이름의 바이트 순 순위(로캘 무관)
  r1 <- rk[ij[, 1]]; r2 <- rk[ij[, 2]]
  lo_r <- pmin(r1, r2); hi_r <- pmax(r1, r2)
  byrk <- nm[order(nm, method = "radix")]
  lo <- byrk[lo_r]; hi <- byrk[hi_r]
  dv <- D[ij]
  o <- order(dv, lo_r, hi_r, method = "radix")                     # (D, 작은 이름, 큰 이름)
  par <- setNames(nm, nm)
  find <- function(x) { while (par[[x]] != x) x <- par[[x]]; x }
  E <- matrix(character(0), ncol = 2L)
  for (k in o) {
    ra <- find(lo[k]); rb <- find(hi[k])
    if (ra != rb) {
      par[[rb]] <- ra
      E <- rbind(E, c(lo[k], hi[k]))
      if (nrow(E) == n - 1L) break
    }
  }
  E
}

## §5.1 Step 2~4 — hub 뿌리 · 방향 · b(u) · α · g(경로곱 — 너비 우선으로 부모가 먼저 계산된다)
.trp_rooted_factors <- function(nm, E, rho = TRP_RHO) {
  n <- length(nm)
  deg <- setNames(integer(n), nm)
  for (k in seq_len(nrow(E))) { deg[E[k, 1]] <- deg[E[k, 1]] + 1L; deg[E[k, 2]] <- deg[E[k, 2]] + 1L }
  cand <- nm[deg == max(deg)]
  root <- cand[order(cand, method = "radix")][1]                     # hub mode · 동률 = 이름 최소(머리말 ③ · ④)
  adj <- lapply(setNames(nm, nm), function(v) c(E[E[, 1] == v, 2], E[E[, 2] == v, 1]))
  parent <- setNames(rep(NA_character_, n), nm); depth <- setNames(rep(NA_integer_, n), nm)
  depth[root] <- 0L; queue <- root; ordv <- character(0)
  while (length(queue)) {
    u <- queue[1]; queue <- queue[-1]; ordv <- c(ordv, u)
    for (v in adj[[u]]) if (is.na(depth[v])) { parent[v] <- u; depth[v] <- depth[u] + 1L; queue <- c(queue, v) }
  }
  b <- setNames(vapply(nm, function(u) sum(parent == u, na.rm = TRUE), integer(1)), nm)
  alpha <- ifelse(b >= 1L, (1 - rho) + rho / pmax(b, 1L), NA_real_)  # 식 eq:alpha(내부 노드만)
  g <- setNames(rep(NA_real_, n), nm); g[root] <- 1                  # g_r = 1
  for (v in ordv[-1]) g[v] <- alpha[[parent[[v]]]] * g[[parent[[v]]]]  # 식 eq:recursive-g
  list(root = root, parent = parent, depth = depth, b = b, alpha = alpha, g = g)
}

## 전 과정(시험용 노출) — X = 수익 창 · s = 부호 신호(기본 KR 롱온리 사상 s ≡ 1) · 반환 w(L = 1 · 이름 = colnames(X))
trp_mst_weights <- function(X, s = NULL, rho = TRP_RHO, eps = TRP_EPS, tau = TRP_TAU) {
  a <- colnames(X)
  if (is.null(s)) s <- setNames(rep(1, length(a)), a)
  m <- colMeans(abs(X), na.rm = TRUE)                                # §4.1 m_i(k = T — 머리말 ①)
  act <- a[is.finite(m) & m > eps & abs(s[a]) > tau]                 # 식 eq:active-set
  if (!length(act)) stop("활동 필터 통과 종목 0 — 배분 불가")
  D <- .trp_distance(X[, act, drop = FALSE])
  E <- .trp_mst(D)
  f <- .trp_rooted_factors(act, E, rho)
  x <- s[act] * f$g[act]                                             # §5.1 Step 5
  w <- setNames(numeric(length(a)), a)
  w[act] <- x / sum(abs(x))                                          # 식 eq:normalized-weights(L = 1) · 비활성 = 0
  list(w = w, active = act, edges = E, root = f$root, depth = f$depth, b = f$b, g = f$g, D = D)
}

method_weights <- function(ctx) {
  a <- ctx$assets
  X <- ctx$R[, a, drop = FALSE]
  r <- trp_mst_weights(X)
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[trp] d=%s n=%d root=%s depth=%d leaves=%d active=%d\n", dd, length(a), r$root,
              max(r$depth, na.rm = TRUE), sum(r$b == 0L), length(r$active)))
  r$w
}
