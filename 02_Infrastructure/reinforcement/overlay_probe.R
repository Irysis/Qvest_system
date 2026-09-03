#==============================================================================
# overlay_probe.R — 오버레이 arm 오프라인 검증 (v10.2 2026-09-03 · Phase 1)
#
# ★왜: 비중 arm 은 sync_catalog(probe=TRUE) 가 25종목 합성 픽스처로 실행 가능 여부를 미리 거른다.
#   오버레이는 그게 없어서, 나쁜 arm 하나가 백테를 다 차린 뒤 런타임 stop() 으로 죽으며
#   격자 칸 하나를 통째로 태웠다. 등재 전에 백테 예산 0 으로 거른다.
#
# 계약: 부작용 없음 — 카탈로그·원장에 쓰지 않는다. 판정만 돌려준다.
#   overlay_probe_arm(kind, root) -> list(ok, checks(data.table), reason)
#==============================================================================
suppressPackageStartupMessages(library(data.table))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.OP_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# 주석을 걷어낸 소스 — 근거를 적은 주석이 스캔에 걸리면 안 되고,
# 반대로 주석 안에 숨긴 코드가 통과해서도 안 된다.
.op_src_nc <- function(path) {
  ln <- readLines(path, warn = FALSE)
  paste(sub("#.*$", "", ln), collapse = "\n")
}

#' 결정론적 합성 픽스처 — 240개월 · 25종목 · 위기 구간 주입
#' ★위기를 넣는 이유: 낙폭 기반 arm 이 반응할 여지가 없으면 "상수 1" 이 arm 결함인지
#'   픽스처 결함인지 구분되지 않는다. 픽스처가 처치 기회를 보장해야 판정이 의미를 갖는다.
overlay_probe_fixture <- function(n_month = 240L, n_ticker = 25L, seed = 20260903L) {
  set.seed(seed)
  d <- seq(as.Date("2006-01-31"), by = "month", length.out = n_month)
  r <- stats::rnorm(n_month, 0.006, 0.05)
  r[70:78]  <- r[70:78]  - 0.11        # 위기 1
  r[150:156] <- r[150:156] - 0.08      # 위기 2
  nav <- cumprod(1 + r)
  dd  <- 1 - nav / cummax(nav)
  rv  <- as.numeric(stats::filter(abs(r), rep(1/6, 6), sides = 1)) * sqrt(12)
  rv[is.na(rv)] <- stats::sd(r) * sqrt(12)
  M <- data.table(
    Date = d, i = seq_len(n_month),
    rv20 = rv * 1.1, rv60 = rv, rv120 = rv * 0.9,
    dd = dd, r252 = c(rep(NA_real_, 12), nav[-seq_len(12)] / nav[seq_len(n_month - 12)] - 1),
    nav = nav, xs = abs(r) * 1.5 + 0.01)
  for (k in 1:10) M[, (paste0("ew", k)) := rv * (0.95 + k / 100)]
  M[, fwd := shift(nav, 1L, type = "lead") / nav - 1]
  tk <- sprintf("T%03d", seq_len(n_ticker))
  hold <- data.table(
    Ticker = tk,
    beta   = seq(0.5, 1.5, length.out = n_ticker),
    dbeta  = seq(0.3, 1.8, length.out = n_ticker),
    ovol   = seq(0.15, 0.55, length.out = n_ticker),
    bcorr  = seq(0.2, 0.9, length.out = n_ticker),
    n_obs  = 3000L)
  list(M = M, hold = hold)
}

overlay_probe_arm <- function(kind, root = .OP_ROOT()) {
  chk <- data.table(check = character(), status = character(), detail = character())
  add <- function(c_, s_, d_ = "") chk <<- rbind(chk, data.table(check = c_, status = s_, detail = d_))
  bad <- function(reason) list(ok = FALSE, checks = chk, reason = reason)

  # ── ① 파일·함수 계약
  p <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".R"))
  if (!file.exists(p)) { add("file", "FAIL", p); return(bad("arm 파일 부재")) }
  env <- new.env(parent = globalenv())
  e1 <- tryCatch({ source(p, local = env); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(e1)) { add("file", "FAIL", e1); return(bad(paste("source 실패:", e1))) }
  fn_name <- paste0("overlay_expo_", kind)
  if (!exists(fn_name, envir = env, inherits = FALSE)) {
    add("file", "FAIL", fn_name); return(bad(sprintf("%s() 부재 — arm 계약 위반", fn_name))) }
  FN <- get(fn_name, envir = env)
  if (!is.function(FN)) { add("file", "FAIL", "not a function"); return(bad("함수가 아니다")) }
  add("file", "PASS", basename(p))

  # ── ② 측정 누출 — 소스가 성과 필드를 참조하면 '성과를 보지 않는다' 가 거짓 주장이 된다.
  #   ★스캐너를 재구현하지 않는다 — 정본(weight_catalog.R)을 불러 쓴다. 두 구현이 갈리면
  #     갈린 순간 둘 중 하나는 실제 소스를 안 재는 것이 된다(이 저장소의 반복 결함).
  wc <- file.path(root, "02_Infrastructure/portfolio/weight_catalog.R")
  lk_fn <- NULL
  if (file.exists(wc)) {
    wenv <- new.env(parent = globalenv())
    tryCatch(suppressMessages(source(wc, local = wenv)), error = function(e) NULL)
    if (exists("wc_scan_measurement_leak", envir = wenv, inherits = FALSE))
      lk_fn <- get("wc_scan_measurement_leak", envir = wenv)
  }
  if (is.null(lk_fn)) {
    add("leak", "SKIP", "wc_scan_measurement_leak 미가용 — 이 축은 미측정(통과 아님)")
  } else {
    s <- lk_fn(p)
    if (!isTRUE(s$ok)) { add("leak", "FAIL", as.character(s$reason))
                         return(bad(paste("측정 누출:", s$reason))) }
    add("leak", "PASS", "측정 토큰 0")
  }

  # ── ③ 임의 상수 — 시장/종목 특징을 숫자 리터럴과 직접 비교하지 않을 것
  src <- .op_src_nc(p)
  # ★인덱스 허용 — 가장 흔한 형태가 H$dd[t] > 0.2 다. 대괄호를 안 넣으면 이 구멍으로 다 샌다.
  lit <- c("H\\$[A-Za-z0-9_.]+(\\[[^]]*\\])?\\s*[<>]=?\\s*-?[0-9]",
           "(ctx\\$)?hold\\$[A-Za-z0-9_.]+(\\[[^]]*\\])?\\s*[<>]=?\\s*-?[0-9]",
           "-?[0-9.]+\\s*[<>]=?\\s*H\\$[A-Za-z0-9_.]+")
  hit <- lit[vapply(lit, function(rx) grepl(rx, src, perl = TRUE), logical(1))]
  if (length(hit)) { add("literal", "FAIL", paste(hit, collapse = " | "))
                     return(bad("임의 상수 문턱 — 특징을 리터럴과 직접 비교했다")) }
  add("literal", "PASS", "리터럴 문턱 0")

  fx <- overlay_probe_fixture()
  M <- fx$M; hold <- fx$hold; N <- nrow(M)
  mk_ctx <- function(t, H) list(t = t, date = M$Date[t], v_now = H$rv60[t],
                                tgt = stats::median(H$rv60, na.rm = TRUE), n_min = 24L, hold = hold)

  # ── ④ 미래 참조 — H$fwd 의 **t 행은 미실현**이다. 그 값을 흔들어 산출이 바뀌면 누출이다.
  tp <- as.integer(N * 0.8)
  H0 <- M[seq_len(tp)]
  o0 <- tryCatch(FN(H0, tp, mk_ctx(tp, H0)), error = function(e) e)
  if (inherits(o0, "error")) { add("run", "FAIL", conditionMessage(o0))
                               return(bad(paste("실행 오류:", conditionMessage(o0)))) }
  H1 <- copy(H0); H1[tp, fwd := (fwd %||% 0) + 0.5]
  o1 <- tryCatch(FN(H1, tp, mk_ctx(tp, H1)), error = function(e) e)
  .flat <- function(z) if (is.data.frame(z)) as.numeric(z$e) else as.numeric(z)
  if (inherits(o1, "error") || !isTRUE(all.equal(.flat(o0), .flat(o1)))) {
    add("future", "FAIL", "H$fwd[t] 섭동에 산출이 반응")
    return(bad("미래 참조 — 신호일 t 의 fwd(익월 수익)를 읽었다")) }
  add("future", "PASS", "fwd[t] 섭동 불변")

  # ── ⑤ 처치 전달 — 전 기간을 돌려 시간축 ∨ 횡단면 변동이 있는지
  ex <- numeric(N); xs <- numeric(N); nvec <- 0L
  for (t in seq_len(N)) {
    if (t < 12L) { ex[t] <- 1; next }
    H <- M[seq_len(t)]
    o <- tryCatch(FN(H, t, mk_ctx(t, H)), error = function(e) e)
    if (inherits(o, "error")) { add("run", "FAIL", sprintf("t=%d %s", t, conditionMessage(o)))
                                return(bad(paste("실행 오류 t=", t, ": ", conditionMessage(o), sep = ""))) }
    if (is.data.frame(o)) {
      v <- as.numeric(o$e); nvec <- nvec + 1L
      ex[t] <- mean(v, na.rm = TRUE); xs[t] <- if (length(v) > 1L) stats::sd(v, na.rm = TRUE) else 0
    } else { ex[t] <- as.numeric(o)[1]; xs[t] <- 0 }
  }
  add("run", "PASS", sprintf("%d개월 무오류 · 벡터 반환 %d개월", N, nvec))
  t_var <- stats::sd(ex, na.rm = TRUE); x_var <- max(xs, na.rm = TRUE)
  if ((!is.finite(t_var) || t_var < 1e-12) && x_var < 1e-12) {
    add("treatment", "FAIL", "시간축·횡단면 모두 상수")
    return(bad("처치 미전달 — 노출이 상수다(격자에서도 측정 무효로 죽는다)")) }
  if (mean(ex, na.rm = TRUE) >= 1 - 1e-12 && x_var < 1e-12) {
    add("treatment", "FAIL", "노출 상시 1")
    return(bad("처치 미전달 — 노출이 상시 1")) }
  add("treatment", "PASS", sprintf("시간 sd %.4f · 횡단면 sd 최대 %.4f · 평균노출 %.3f",
                                   t_var, x_var, mean(ex, na.rm = TRUE)))
  add("axis", "INFO", if (nvec > 0L) "cross_sectional" else "scalar_exposure")
  list(ok = TRUE, checks = chk, reason = NA_character_,
       axis = if (nvec > 0L) "cross_sectional" else "scalar_exposure",
       mean_exposure = mean(ex, na.rm = TRUE), t_var = t_var, x_var = x_var)
}

cat("[overlay_probe.R] Loaded — overlay_probe_arm(kind) / overlay_probe_fixture()\n")
