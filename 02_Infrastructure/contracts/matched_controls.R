#==============================================================================
# matched_controls.R — 크기 짝 · 노출 짝 무신호 대조 계약 (MC8 · v10.01 · 2026-10-13)
#
# 왜: 행동 카드의 위기 방어(CR)가 '실력'인지 '크기 · 노출 효과'인지 가른다.
#   2026-06~07 KOSPI200 −40.9% 급락은 초대형주 주도였다(동일가중 −18.7%) — 중소형을 든 전략은
#   아무것도 고르지 않아도 '덜 빠진다'(크기 방어 착시 · 설계 §7.3). 현금을 든 전략도 마찬가지다.
#   설계 = 04_Research/01_reports/l1_prescription_redesign_20261013/README.md
#     §3.4 R5: 방어 처방은 노출 짝 대조(같은 평균 노출의 정적 축소)와 함께 잰다 — 기전 방어 / 노출 방어
#     §3.5 D6 조건: 같은 평균 노출 · 같은 크기 분포의 무신호 포트폴리오보다 덜 빠져야 '방어 실력' — 선택 방어 / 크기 방어
#
# 무엇을 만드나 (보유 기록 04_holdings.csv · 수익 03_period_returns.csv · 벤치 05_benchmark_returns.csv · RAWDATA):
#   ① 노출 경로 E_k = 리밸 k 의 롱 Σ목표비중 — 집행 엔진이 레그 수익에 매일 곱하는 그 값
#      (replication_harness.R::run_replication_simulation  Rg = GL·Lr). 평균 노출 Ē = 보유 일수 가중 평균.
#   ② 크기 바스켓(기댓값) — 리밸마다 집행일 전 거래일(as-of) 유니버스를 시가총액 분위로 나누고,
#      전략 목표 비중의 분위별 몫 W_b 를 그 분위 전 종목에 동일가중으로 나눠 든다(DGTW 1997 특성 짝).
#   ③ 크기 플라시보(분포) — 리밸마다 분위별로 전략이 그 분위에 든 종목 수만큼 분위 멤버를 무작위로 뽑아
#      전략 비중을 그대로 얹는다(분위 몫 · 비중 분포 보존 · 분위 안 선택만 무작위 · Kothari-Warner 2001 모의 포트폴리오).
#      ★판정은 평균이 아니라 분위다(09-21 오버레이 노출 짝 플라시보 관례 · rf_overlay_adversary.R) —
#      바스켓(기댓값)과 비교하면 분위 안에서 우연히 좋은 종목 하나를 든 무선택 전략도 '선택'으로 센다(검사 P).
#      보유창 안 매수후보유 · 결측 수익 = 0(집행 엔진과 같은 처리) · 비용 없음(전략에 보수적).
#   ④ 대조:
#      exposure_matched      = 벤치 × Ē           (R5 노출 짝 — 결정론)
#      size_exposure_matched = 크기 바스켓 × Ē     (D6 크기+노출 짝의 기댓값 — 보고용 포착률)
#      size_matched          = 크기 바스켓 × 1     (진단 — 크기 효과 단독)
#      size_exposure_path    = 크기 바스켓 × E_k   (진단 — 노출 경로가 변할 때만)
#      플라시보 × Ē(판정) · 플라시보 × E_k(진단 — 타이밍을 고정한 순수 선택)
#   ⑤ 귀속 라벨(위기 과반 · behavior_card.json::majority_share — 새 숫자 없음):
#      크기+노출 플라시보의 alpha 분위보다 덜 빠짐 → selection_defense(선택·기전 방어 — 종목 선택 또는 노출 타이밍)
#      아니고 노출 짝보다 덜 빠짐 → size_defense(크기 방어 — 같은 크기 분포의 무작위 무신호 포트폴리오와 같은 방어)
#      아니고 시장(벤치)보다는 덜 빠짐 → exposure_defense(노출 방어 — 현금 덕에 시장보다 덜 빠졌지만 같은 평균 노출의 벤치보다 낫지 않다)
#      시장보다도 과반 위기에서 덜 빠지지 못함 → no_defense(방어 없음 — 10-13 도훈 '2번 반영': 평균 노출 1.0 전략이
#        '노출 방어'로 찍히던 혼동을 가른다. 평균 노출 1 이면 노출 짝 = 시장이라 노출 방어는 정의상 나올 수 없다)
#      위기 2번 미만 → insufficient('매번'은 둘 이상 — behavior_card.R .bc_verdict 와 같은 관례)
#      전체 · 보는 창(τ_D 이전) · 시험 창(τ_D 이후) 따로 낸다.
#
# PIT: 크기 · 멤버십 · 거래정지 = 집행일 전 거래일 값만(보유 시작 전에 알려진 값 · 분위 경계도 그날 유니버스로만).
#   W_b 는 전략 목표 비중(시그널일에 정해진 값). 수익은 보유창 안에서만 쓴다. as-of ≥ 집행일이면 멈춘다.
# 한계(기록): 분위는 거칠다 — 분위 안 크기 차이(예: 최상위 분위의 초대형 1~2종)는 분위 짝으로 다 걷히지 않는다(size_buckets 로 조절).
#   시가총액 가중 전략은 리밸 사이 이긴 종목 비중을 들고 간다(표류) — 플라시보는 리밸마다 재배정하므로, 분위 안 수익 분산이
#   작은 위기에선 그 표류가 분포 꼬리에 들 수 있다(검사 D3: 합성 세계 4번 중 1번). 라벨은 위기 과반으로만 낸다.
# 경계: 등급을 내지 않는다(등급 정본 = essence_score.R → grade_v3.R). 행동 카드에 대조를 붙여 기록할 뿐이다.
#   롱숏(음수 비중) 전략은 정의 밖 — status = not_applicable_long_short(침묵 통과 아님).
#
# 공개: mc_cfg · mc_load_raw · mc_exposure · mc_size_basket · mc_controls · mc_attribution · mc_card · mc_write
# 검사: 08_Tests/contracts/test_matched_controls.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.mc_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# 부동소수 동치 여유(결정 수치 아님) — 같은 수익 경로를 다른 산술 순서로 잰 두 낙폭이 1e-15 수준으로 갈려
#   '대조를 넘음'으로 세지는 것을 막는다(검사 A: 전략 = 크기 바스켓 그 자체).
.MC_TOL <- 1e-9

# 루트 = 호출자 명시 → CLAUDE_PROJECT_DIR → QM_ROOT → getwd. 정체성 표식(CLAUDE.md + 06_Registry)으로 검증한다.
.mc_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[matched_controls] 프로젝트 루트 해석 실패")
}

# 행동 카드 계약을 사적 환경에 한 번 싣는다 — 전역을 더럽히지 않고, 같은 루트면 재사용한다.
.MC <- new.env(parent = emptyenv())
.mc_deps <- function(root) {
  if (isTRUE(.MC$loaded) && identical(.MC$root, root)) return(invisible(.MC$e))
  e <- new.env(parent = globalenv())
  p <- file.path(root, "02_Infrastructure/contracts/behavior_card.R")
  if (!file.exists(p)) stop("[matched_controls] 의존 계약 없음: ", p)
  invisible(utils::capture.output(suppressMessages(sys.source(p, envir = e, keep.source = FALSE))))
  .MC$e <- e; .MC$root <- root; .MC$loaded <- TRUE
  invisible(e)
}

# 난수 상태를 빌렸다가 돌려준다 — 호출자의 난수 흐름을 바꾸지 않는다
.mc_with_seed <- function(seed, expr) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = globalenv(), inherits = FALSE) else NULL
  on.exit(if (had) assign(".Random.seed", old, envir = globalenv())
          else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv()))
  set.seed(seed)
  expr
}

#' 설정 정본 — 필수 키 · 어휘가 어긋나면 멈춘다(기본값을 지어내지 않는다)
mc_cfg <- function(root = NULL, path = NULL) {
  p <- .mc_or(path, file.path(.mc_root(root), "06_Registry/matched_controls.json"))
  cfg <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(cfg)) stop("[matched_controls] 설정 판독 불가: ", p)
  need <- c("size_buckets", "universe", "asof", "within_bucket_weight", "holding", "exposure", "costs",
            "placebo_n", "placebo_alpha", "placebo_seed", "label_rule")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[matched_controls] 설정 키 누락: ", paste(miss, collapse = ","))
  vocab <- list(universe = "measurement_membership", asof = "previous_trading_day", within_bucket_weight = "equal",
                holding = "buy_and_hold_between_rebalances", exposure = "static_mean", costs = "none",
                label_rule = "nested_majority_placebo_v2")
  for (k in names(vocab)) if (!identical(cfg[[k]], vocab[[k]]))
    stop("[matched_controls] ", k, " 어휘 밖: ", paste(cfg[[k]], collapse = ","), " (기대 ", vocab[[k]], ")")
  int1 <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x == round(x)
  if (!int1(cfg$size_buckets) || cfg$size_buckets < 2)
    stop("[matched_controls] size_buckets 는 2 이상 정수여야 한다: ", paste(cfg$size_buckets, collapse = ","))
  a <- cfg$placebo_alpha
  if (!is.numeric(a) || length(a) != 1L || !is.finite(a) || a <= 0 || a >= 0.5)
    stop("[matched_controls] placebo_alpha 는 (0, 0.5) 실수여야 한다: ", paste(a, collapse = ","))
  # alpha 분위가 표본 안에서 정해지려면 n·alpha ≥ 1 이어야 한다(산술 조건 — 새 문턱 아님)
  if (!int1(cfg$placebo_n) || cfg$placebo_n * a < 1)
    stop("[matched_controls] placebo_n 은 정수이고 placebo_n × placebo_alpha ≥ 1 이어야 한다: ", paste(cfg$placebo_n, collapse = ","))
  if (!int1(cfg$placebo_seed)) stop("[matched_controls] placebo_seed 는 정수여야 한다")
  cfg$size_buckets <- as.integer(cfg$size_buckets); cfg$placebo_n <- as.integer(cfg$placebo_n)
  cfg
}

#' RAWDATA 좁은 판 — 대조에 필요한 열만(날짜 · 종목 · 멤버십 · 시가총액 · 수익 · 거래정지). 여러 디렉터리에 재사용한다.
mc_load_raw <- function(root = NULL, from = NULL, to = NULL, path = NULL, hygiene = FALSE) {
  p <- .mc_or(path, file.path(.mc_root(root), ".cache/RAWDATA.parquet"))
  if (!file.exists(p)) stop("[matched_controls] RAWDATA 없음: ", p)
  if (!requireNamespace("arrow", quietly = TRUE)) stop("[matched_controls] arrow 미설치")
  base_cols <- c("Date", "Ticker", "K200", "KQ150", "Size", "Ret", "TradingHalt")
  if (!isTRUE(hygiene)) {
    R <- as.data.table(arrow::read_parquet(p, col_select = base_cols))
    if (!inherits(R$Date, "Date")) R[, Date := as.Date(Date)]
    if (!is.null(from)) R <- R[Date >= as.Date(from)]
    if (!is.null(to)) R <- R[Date <= as.Date(to)]
    return(R)
  }
  # ★측정 축 ALL_HYG(MC1 · 2026-10-13) — 위생 멤버십(HYG)은 20일 평균(t−1)이 필요해 **잘리기 전 전체 시계열**에서 한 번 계산한다
  #   (계약 = contracts/measurement_axis.R::ma_membership · 표준 판정식 corp_action_member). 그 뒤 날짜를 자르고 보조 열을 버린다.
  R <- as.data.table(arrow::read_parquet(p, col_select = c(base_cols, "Close", "Vol", "AdminStock", "UnfaithfulDisc")))
  if (!inherits(R$Date, "Date")) R[, Date := as.Date(Date)]
  ma <- new.env(parent = globalenv())
  sys.source(file.path(.mc_root(root), "02_Infrastructure/contracts/measurement_axis.R"), envir = ma, keep.source = FALSE)
  ep <- ma$ma_epoch_by_universe("ALL_HYG", root = .mc_root(root))
  R[, HYG := ma$ma_membership(R, ep)]
  R[, c("Close", "Vol", "AdminStock", "UnfaithfulDisc") := NULL]
  if (!is.null(from)) R <- R[Date >= as.Date(from)]
  if (!is.null(to)) R <- R[Date <= as.Date(to)]
  setattr(R, "mc_hygiene_epoch", ep$id)
  R
}

# ALL_HYG 위생 멤버십 열 — 러너가 주입한 판(K200_IDX 존재 = K200 이 위생 멤버십) 또는 mc_load_raw(hygiene = TRUE) 의 HYG.
#   둘 다 없으면 멈춘다 — 위생 없는 '전 종목'으로 조용히 바뀌면 대조 유니버스가 측정 유니버스와 어긋난다.
.mc_hyg_col <- function(R) {
  if ("K200_IDX" %in% names(R)) return(R$K200 %in% 1)
  if ("HYG" %in% names(R) && !all(is.na(R$HYG))) return(R$HYG %in% TRUE)
  stop("[matched_controls] universe ALL_HYG 대조는 위생 멤버십이 필요하다 — mc_load_raw(hygiene = TRUE) 또는 측정 축이 주입된 RAWDATA")
}

# 측정 유니버스 멤버 표식 — run_paper_replication.R .apply_universe 와 같은 정의
#   (K200_KQ150 · INDEX = K200 | KQ150 플래그 · ALL_HYG = 위생 멤버십(HYG 열) · 그 밖 = 전 종목). 플래그는 0/1 숫자이고 NA 는 비멤버다.
.mc_member <- function(R, universe) {
  if (!is.null(universe) && !is.na(universe) && universe %in% c("K200_KQ150", "INDEX")) {
    if (!all(c("K200", "KQ150") %in% names(R))) stop("[matched_controls] 멤버십 열(K200 · KQ150) 없음")
    (R$K200 %in% 1) | (R$KQ150 %in% 1)
  } else if (identical(universe, "ALL_HYG")) {
    if (!"HYG" %in% names(R) || all(is.na(R$HYG))) stop("[matched_controls] ALL_HYG 멤버십 열(HYG) 없음")
    R$HYG %in% TRUE
  } else rep(TRUE, nrow(R))
}

# 보유창 — 집행 엔진(run_replication_simulation)과 같은 규약
#   close_t1 · open_t1 = (집행일, 다음 집행일] · close_d_legacy = [집행일, 다음 집행일). 마지막 창은 수익 끝까지.
#   open_t1 의 장중 · 겹밤 분할은 창 경계 반나절 근사다(spec 에 window_approx 로 남긴다).
.mc_windows <- function(ret_dates, exec_dates, exec_price) {
  e <- sort(unique(as.Date(exec_dates))); d <- sort(unique(as.Date(ret_dates)))
  k <- if (identical(exec_price, "close_d_legacy")) findInterval(d, e) else findInterval(d, e, left.open = TRUE)
  out <- data.table(date = d, k = k)[k >= 1L]
  out[, exec_date := e[k]]
  out[, k := NULL][]
}

# 집행 규약 — 전략 명세가 정본. 명세가 없으면 날짜로 판정한다(첫 수익일 ≤ 첫 집행일 = 집행일 수익을 버는 legacy)
.mc_exec_price <- function(spec, ret_dates, exec_dates) {
  ep <- spec[["exec_price"]]
  if (!is.null(ep) && length(ep) && !is.na(ep[1]) && nzchar(ep[1])) {
    ep <- as.character(ep[1])
    if (!ep %in% c("close_t1", "open_t1", "close_d_legacy")) stop("[matched_controls] exec_price 어휘 밖: ", ep)
    return(list(value = ep, source = "strategy_spec"))
  }
  legacy <- min(as.Date(ret_dates)) <= min(as.Date(exec_dates))
  list(value = if (legacy) "close_d_legacy" else "close_t1", source = "inferred_from_dates")
}

#' 노출 경로 — 리밸마다 롱 Σ목표비중(GL) · 평균 노출 = 보유 일수 가중 평균
#' @param H data.table(date = 집행일, ticker, target_weight) · @param win .mc_windows 산출(date, exec_date)
mc_exposure <- function(H, win) {
  h <- as.data.table(H)
  E <- h[, .(GL = sum(target_weight[target_weight > 0]), has_short = any(target_weight < 0)), by = .(exec_date = date)]
  n <- win[, .(n_days = .N), by = exec_date]
  E <- merge(E, n, by = "exec_date", all.x = TRUE)[order(exec_date)]
  E[is.na(n_days), n_days := 0L]
  live <- E[n_days > 0]
  m <- if (nrow(live)) sum(live$GL * live$n_days) / sum(live$n_days) else NA_real_
  list(mean = m, path = E, varies = nrow(live) > 1L && isTRUE(stats::sd(live$GL) > .MC_TOL),
       has_short = any(E$has_short))
}

#' 크기 분위 — 리밸마다 as-of(집행일 전 거래일) 유니버스를 시가총액 분위로 나누고 전략 보유를 그 경계에 놓는다
#' @param H data.table(date = 집행일, ticker, target_weight) · @param R mc_load_raw 판(또는 같은 열의 합성 표)
#' @return list(members = 크기 바스켓(exec_date, asof, Ticker, b, w) · hold = 분위가 정해진 전략 보유(exec_date, Ticker, b, w — 리밸마다 합 1)
#'   · univ = 분위가 정해진 유니버스(exec_date, Ticker, b) · diag = 리밸별 상태 · asof = (exec_date, asof))
mc_size_basket <- function(H, R, cfg, universe) {
  B <- cfg$size_buckets
  h <- as.data.table(H)[is.finite(target_weight) & target_weight > 0,
                        .(exec_date = as.Date(date), Ticker = as.character(ticker), w = target_weight)]
  ex <- sort(unique(h$exec_date))
  cal <- sort(unique(R$Date))
  i <- findInterval(ex, cal, left.open = TRUE)                 # cal[i] < 집행일 ≤ cal[i+1] → cal[i] = 전 거래일
  A <- data.table(exec_date = ex, asof = cal[ifelse(i >= 1L, i, NA_integer_)])
  if (any(A$asof >= A$exec_date, na.rm = TRUE)) stop("[matched_controls] PIT — as-of 가 집행일 이후다")
  col <- function(nm) if (nm %in% names(R)) R[[nm]] else rep(NA_real_, nrow(R))
  ## ★정수 일 번호로 비교한다(2026-10-15 속도 수리 · 결과 비트 동일) — Date 의 %in% · match 는 양쪽을 문자열로 서식화(mtfrm →
  ##   as.character.Date → sprintf)해서 1,200만 행을 매번 문자열로 바꿨다. 같은 날 ⇔ 같은 일 번호(정수 값 Date)라 고른 행이 같다.
  if (!inherits(R$Date, "Date")) stop("[matched_controls] R$Date 는 Date 여야 한다 — 정수 일 번호 비교(POSIXct 면 초 단위라 아무 행도 안 골라진다)")
  sel <- as.integer(R$Date) %in% as.integer(A$asof[!is.na(A$asof)])
  SZ <- data.table(Date = R$Date[sel], Ticker = R$Ticker[sel], Size = R$Size[sel],
                   K200 = col("K200")[sel], KQ150 = col("KQ150")[sel], TradingHalt = col("TradingHalt")[sel])
  if (identical(universe, "ALL_HYG")) set(SZ, j = "HYG", value = .mc_hyg_col(R)[sel])   # MC1 — 위생 멤버십(측정 유니버스와 같게)
  set(SZ, j = "mem", value = .mc_member(SZ, universe))
  set(SZ, j = "halt", value = is.finite(SZ$TradingHalt) & SZ$TradingHalt > 0)
  SZs <- split(SZ, by = "Date", keep.by = FALSE)
  mem <- vector("list", nrow(A)); hold <- vector("list", nrow(A)); univ <- vector("list", nrow(A)); dg <- vector("list", nrow(A))
  for (j in seq_len(nrow(A))) {
    e <- A$exec_date[j]; a <- A$asof[j]
    st <- function(s, nu = 0L, nb = 0L, un = 1) data.table(exec_date = e, asof = a, n_universe = nu, n_basket = nb,
                                                           unmapped_share = un, status = s)
    if (is.na(a)) { dg[[j]] <- st("no_asof"); next }
    u <- SZs[[as.character(a)]]
    if (is.null(u) || !nrow(u)) { dg[[j]] <- st("asof_missing"); next }
    u <- unique(u, by = "Ticker")
    U <- u[mem & is.finite(Size) & Size > 0 & !halt]
    if (nrow(U) < B) { dg[[j]] <- st("universe_too_small", nrow(U)); next }
    bp <- stats::quantile(U$Size, probs = seq_len(B - 1L) / B, names = FALSE, type = 7)
    U[, b := findInterval(Size, bp) + 1L]
    hk <- h[exec_date == e]
    hk[u, Size := i.Size, on = "Ticker"]                         # 비멤버 보유도 그날 시가총액으로 같은 경계에 놓는다
    hk[, b := ifelse(is.finite(Size) & Size > 0, findInterval(Size, bp) + 1L, NA_integer_)]
    tot <- sum(hk$w)
    hk <- hk[!is.na(b) & b %in% U$b]                             # 멤버가 없는 분위에 놓인 보유는 짝을 지을 수 없다
    un <- if (tot > 0) max(0, 1 - sum(hk$w) / tot) else 1
    if (!nrow(hk)) { dg[[j]] <- st("unmapped", nrow(U), 0L, un); next }
    hk[, w := w / sum(w)]
    Wb <- hk[, .(Wb = sum(w)), by = b]
    M <- merge(U[, .(Ticker, b)], Wb, by = "b")
    M[, w := Wb / .N, by = b]
    mem[[j]] <- M[, .(exec_date = e, asof = a, Ticker, b, w)]
    hold[[j]] <- hk[, .(exec_date = e, Ticker, b, w)]
    univ[[j]] <- U[b %in% Wb$b, .(exec_date = e, Ticker, b)]
    dg[[j]] <- st("ok", nrow(U), nrow(M), un)
  }
  list(members = rbindlist(mem), hold = rbindlist(hold), univ = rbindlist(univ), diag = rbindlist(dg), asof = A)
}

# 바스켓 일간 수익 — 창마다 매수후보유(종목 누적곱 × 비중의 합) · 결측 수익 = 0(사라진 종목은 그 값에 머문다)
.mc_basket_returns <- function(members, win, R) {
  MK <- members[, .(exec_date, Ticker, w)]
  DK <- win[exec_date %in% unique(MK$exec_date), .(exec_date, date)]
  if (!nrow(DK)) return(data.table(date = as.Date(character(0)), exec_date = as.Date(character(0)), ret = numeric(0)))
  G <- MK[DK, on = "exec_date", allow.cartesian = TRUE, nomatch = NULL]
  RT <- R[Ticker %in% unique(MK$Ticker) & Date >= min(DK$date) & Date <= max(DK$date), .(Ticker, Date, Ret)]
  G[RT, r := i.Ret, on = .(Ticker, date = Date)]
  if (!"r" %in% names(G)) G[, r := NA_real_]
  G[!is.finite(r), r := 0]
  setorder(G, exec_date, Ticker, date)
  G[, cum := cumprod(1 + r), by = .(exec_date, Ticker)]
  V <- G[, .(V = sum(w * cum)), by = .(exec_date, date)]
  V <- merge(V, MK[, .(W0 = sum(w)), by = exec_date], by = "exec_date")
  setorder(V, exec_date, date)
  V[, Vp := shift(V, fill = W0[1]), by = exec_date]
  V[, .(date, exec_date, ret = V / Vp - 1)][order(date)]
}

# 크기 플라시보 일간 수익(레그 · Σw = 1 기준) — 리밸마다 분위별로 전략 보유 수만큼 분위 멤버를 무작위로 뽑아
#   전략 비중을 그대로 얹는다(뽑힌 순서 = 무작위 배정). 분위 멤버보다 보유가 많으면 복원 추출(비중 누적).
#   @return list(date, exec_date, P = 행렬(일 × n)) — 행 순서 = 날짜 순
.mc_placebo_paths <- function(sb, win, R, n, seed) {
  hold <- sb$hold; univ <- sb$univ
  exs <- sort(unique(hold$exec_date))
  W <- win[exec_date %in% exs][order(date)]
  if (!nrow(W)) return(NULL)
  RT <- R[Ticker %in% unique(univ$Ticker) & Date >= min(W$date) & Date <= max(W$date), .(Ticker, Date, Ret)]
  ## ★속도 수리(2026-10-15 · 결과 비트 동일) — 구판 `RT[Date %in% dd & Ticker %in% tk]` 는 리밸마다(≈300회) RT 전체(수백만~천만 행)의
  ##   Date 를 문자열로 서식화했다(mtfrm) — 평가 시간의 95%(프로파일 실측 · 칸당 ≈ 90분). 정수 일 번호로 먼저 날짜를 좁히고(부분집합의
  ##   부분집합 = 원래 행 순서 보존) 그 안에서 종목을 거른다 → 고른 행 · 순서가 구판과 같다. 난수 호출(sample.int) 순서는 손대지 않는다.
  if (!inherits(RT$Date, "Date") || !inherits(W$date, "Date"))
    stop("[matched_controls] 날짜 열은 Date 여야 한다 — 정수 일 번호 비교(POSIXct 면 초 단위라 아무 행도 안 골라진다)")
  RT[, .di := as.integer(Date)]
  out <- .mc_with_seed(seed, lapply(exs, function(e) {
    dd <- W[exec_date == e]$date
    if (!length(dd)) return(NULL)
    hk <- hold[exec_date == e]; uk <- univ[exec_date == e]
    tk <- unique(uk$Ticker)
    ddi <- as.integer(dd)
    sub <- RT[.di %in% ddi][Ticker %in% tk]
    Rm <- matrix(0, length(dd), length(tk))
    if (nrow(sub)) Rm[cbind(match(sub$.di, ddi), match(sub$Ticker, tk))] <- ifelse(is.finite(sub$Ret), sub$Ret, 0)
    cum <- apply(1 + Rm, 2, cumprod)
    if (!is.matrix(cum)) cum <- matrix(cum, nrow = length(dd))
    Wm <- matrix(0, length(tk), n)
    for (bb in sort(unique(hk$b))) {
      ws <- hk[b == bb]$w; m <- length(ws)
      mi <- match(uk[b == bb]$Ticker, tk); nb <- length(mi)
      if (m <= nb) {
        idx <- matrix(vapply(seq_len(n), function(j) mi[sample.int(nb, m)], integer(m)), nrow = m)
        Wm[cbind(as.vector(idx), rep(seq_len(n), each = m))] <- rep(ws, n)
      } else for (j in seq_len(n)) {
        pk <- mi[sample.int(nb, m, replace = TRUE)]
        for (q in seq_len(m)) Wm[pk[q], j] <- Wm[pk[q], j] + ws[q]
      }
    }
    V <- cum %*% Wm
    Vp <- rbind(colSums(Wm), V[-nrow(V), , drop = FALSE])
    list(date = dd, P = V / Vp - 1)
  }))
  out <- Filter(Negate(is.null), out)
  dts <- do.call(c, lapply(out, `[[`, "date"))
  P <- do.call(rbind, lapply(out, `[[`, "P"))
  o <- order(dts)
  list(date = dts[o], exec_date = W$exec_date[match(dts[o], W$date)], P = P[o, , drop = FALSE])
}

#' 대조 수익 — 노출 짝(결정론) · 크기+노출 짝(기댓값 + 플라시보 분포) + 진단
#' @return list(status, series = list(<이름> = data.table(date, ret)), placebo, exposure, diag, basket_diag)
mc_controls <- function(H, pr, br, R, cfg, exec_price, universe) {
  H <- as.data.table(H); pr <- as.data.table(pr); br <- as.data.table(br)
  if (!all(c("date", "ticker", "target_weight") %in% names(H))) stop("[matched_controls] 보유 기록 열(date · ticker · target_weight) 없음")
  H <- copy(H)[, date := as.Date(date)][is.finite(target_weight) & target_weight != 0]
  if (!nrow(H)) return(list(status = "no_holdings", reason = "보유 기록이 비었다"))
  if (any(H$target_weight < 0))
    return(list(status = "not_applicable_long_short",
                reason = "음수 비중(숏) — 크기 · 노출 짝 대조는 롱온리 처방의 정의(설계 §3.4 R5)다"))
  win <- .mc_windows(pr$date, H$date, exec_price)
  if (!nrow(win)) return(list(status = "no_windows", reason = "보유창에 든 수익일이 없다"))
  ex <- mc_exposure(H, win)
  sb <- mc_size_basket(H, R, cfg, universe)
  if (!nrow(sb$members)) return(list(status = "no_basket", reason = "모든 리밸에서 크기 바스켓을 못 만들었다",
                                     basket_diag = sb$diag))
  bk <- .mc_basket_returns(sb$members, win, R)
  pl <- .mc_placebo_paths(sb, win, R, cfg$placebo_n, cfg$placebo_seed)
  bm <- merge(win, br[, .(date = as.Date(date), benchmark_ret)], by = "date")[is.finite(benchmark_ret)]
  E <- ex$mean
  series <- list(exposure_matched = bm[, .(date, ret = E * benchmark_ret)][order(date)],
                 size_exposure_matched = bk[, .(date, ret = E * ret)],
                 size_matched = bk[, .(date, ret)])
  if (isTRUE(ex$varies))
    series$size_exposure_path <- merge(bk, ex$path[, .(exec_date, GL)], by = "exec_date")[, .(date, ret = GL * ret)][order(date)]
  ok <- sb$diag[status == "ok"]
  diag <- list(n_rebalances = nrow(sb$asof), n_rebalances_ok = nrow(ok),
               status_counts = as.list(table(sb$diag$status)),
               unmapped_share_max = if (nrow(sb$diag)) max(sb$diag$unmapped_share) else NA_real_,
               unmapped_share_mean = if (nrow(sb$diag)) mean(sb$diag$unmapped_share) else NA_real_,
               universe_n_median = if (nrow(ok)) stats::median(ok$n_universe) else NA_real_,
               basket_n_median = if (nrow(ok)) stats::median(ok$n_basket) else NA_real_,
               asof_lag_days_max = suppressWarnings(max(as.numeric(sb$asof$exec_date - sb$asof$asof), na.rm = TRUE)),
               n_dates = nrow(win), n_dates_covered = nrow(bk),
               n_dates_placebo = if (is.null(pl)) 0L else length(pl$date))
  list(status = "ok", series = series,
       placebo = if (is.null(pl)) NULL else c(pl, list(n = cfg$placebo_n, alpha = cfg$placebo_alpha, seed = cfg$placebo_seed)),
       exposure = ex, diag = diag, basket_diag = sb$diag)
}

# 열마다 최대낙폭(시작 수준 1 포함) — 행 = 일, 열 = 경로
.mc_dd_cols <- function(M) {
  if (!NROW(M)) return(rep(NA_real_, NCOL(M)))
  nav <- apply(1 + M, 2, cumprod)
  if (!is.matrix(nav)) nav <- matrix(nav, nrow = NROW(M))
  nav <- rbind(1, nav)
  apply(nav, 2, function(v) max(1 - v / cummax(v)))
}

# 위기마다 플라시보 낙폭 포착률 분포 → alpha 분위 · p · 넘음(전략 포착률 < 분위 − tol)
.mc_placebo_crises <- function(CR, pl, scale, bm, alpha, tol) {
  K <- bm$benchmark_ret[match(pl$date, as.Date(bm$date))]
  rows <- lapply(seq_len(nrow(CR)), function(i) {
    ix <- which(pl$date > CR$peak_date[i] & pl$date <= CR$trough_date[i] & is.finite(K))
    if (!length(ix)) return(NULL)
    nav <- c(1, cumprod(1 + K[ix])); bdd <- max(1 - nav / cummax(nav))
    if (!(bdd > 0)) return(NULL)
    cap <- .mc_dd_cols(pl$P[ix, , drop = FALSE] * scale[ix]) / bdd
    cap <- cap[is.finite(cap)]
    if (!length(cap)) return(NULL)
    s <- CR$dd_capture[i]
    q <- as.numeric(stats::quantile(cap, alpha, names = FALSE, type = 7))
    data.table(peak_date = CR$peak_date[i], window = CR$window[i], strategy_dd_capture = s,
               placebo_q = q, placebo_median = stats::median(cap),
               placebo_p = (1 + sum(cap <= s)) / (length(cap) + 1), beats = s < q - tol)
  })
  rbindlist(rows)
}

#' 대조를 카드에 붙이고 귀속 라벨을 낸다(전체 · 보는 창 · 시험 창)
#' @param card behavior_card.R::bc_card 산출 · @param ctl mc_controls 산출 · @param bm data.table(date, benchmark_ret)
#' @param bcfg behavior_card.json 설정(majority_share) · @param e behavior_card.R 이 실린 환경(없으면 사적 환경)
mc_attribution <- function(card, ctl, bm, bcfg, e = NULL, tol = .MC_TOL) {
  if (is.null(e)) e <- .mc_deps(.mc_root(NULL))
  if (!identical(ctl$status, "ok")) {
    card$controls <- list(status = ctl$status, reason = .mc_or(ctl$reason, NA_character_))
    return(card)
  }
  card <- e$bc_attach_controls(card, ctl$series, bm, tol = tol)
  ctrl <- card$controls
  P <- ctl$exposure$path
  ctrl$exposure_profile <- list(mean = ctl$exposure$mean, varies = ctl$exposure$varies,
                                min = min(P$GL[P$n_days > 0]), max = max(P$GL[P$n_days > 0]),
                                path = P[, .(exec_date, GL, n_days)])
  ctrl$diag <- ctl$diag
  if (!identical(ctrl$status, "ok")) { card$controls <- ctrl; return(card) }       # no_crises
  maj <- bcfg$majority_share
  if (!is.numeric(maj) || !is.finite(maj)) stop("[matched_controls] majority_share 설정 없음(behavior_card.json)")
  pl <- ctl$placebo
  if (is.null(pl) || !NROW(pl$P)) stop("[matched_controls] 플라시보 경로 없음 — 크기+노출 짝 판정 불가")
  CR <- as.data.table(card$crises)
  bmd <- as.data.table(bm)[, .(date = as.Date(date), benchmark_ret)]
  pst <- .mc_placebo_crises(CR, pl, rep(ctl$exposure$mean, length(pl$date)), bmd, pl$alpha, tol)
  ppa <- if (isTRUE(ctl$exposure$varies))
    .mc_placebo_crises(CR, pl, P$GL[match(pl$exec_date, P$exec_date)], bmd, pl$alpha, tol) else NULL
  ctrl$placebo <- list(n = pl$n, alpha = pl$alpha, seed = pl$seed, per_crisis = pst, per_crisis_path = ppa)
  per <- function(p, w) {
    if (is.null(p) || !NROW(p)) return(NULL)
    p <- as.data.table(p)
    if (w != "overall") p <- p[window == w]
    p
  }
  one <- function(w) {
    se <- per(pst, w); sp <- per(ppa, w)
    ex <- per(ctrl[["exposure_matched"]][["per_crisis"]], w)
    if (!is.null(ex)) ex <- ex[is.finite(strategy_dd_capture) & is.finite(control_dd_capture)]
    ev <- per(ctrl[["size_exposure_matched"]][["per_crisis"]], w)
    cw <- per(CR, w)
    n <- min(if (is.null(se)) 0L else nrow(se), if (is.null(ex)) 0L else nrow(ex))
    s_se <- if (is.null(se) || !nrow(se)) NA_real_ else mean(se$beats)
    s_ex <- if (is.null(ex) || !nrow(ex)) NA_real_ else mean(ex$strategy_dd_capture < ex$control_dd_capture - tol)
    # 시장(벤치) 자체보다 덜 빠졌나 — 벤치의 하락 포착률은 정의상 1 이다(10-13 도훈 "2번 반영": 노출 방어 ≠ 방어 없음)
    s_bm <- if (is.null(cw) || !nrow(cw)) NA_real_ else mean(cw$dd_capture < 1 - tol)
    lab <- if (n < 2L || !is.finite(s_se) || !is.finite(s_ex) || !is.finite(s_bm)) "insufficient"
           else if (s_se > maj) "selection_defense" else if (s_ex > maj) "size_defense"
           else if (s_bm > maj) "exposure_defense" else "no_defense"
    md <- function(x) if (length(x)) stats::median(x) else NA_real_
    list(label = lab, n_crisis = n, share_beats_size_exposure = s_se, share_beats_exposure = s_ex, share_beats_bench = s_bm,
         median_placebo_p = if (is.null(se)) NA_real_ else md(se$placebo_p),
         median_gap_size_exposure = if (is.null(ev)) NA_real_ else md(ev$control_dd_capture - ev$strategy_dd_capture),
         median_gap_exposure = if (is.null(ex)) NA_real_ else md(ex$control_dd_capture - ex$strategy_dd_capture),
         share_beats_size_exposure_path = if (is.null(sp) || !nrow(sp)) NA_real_ else mean(sp$beats))
  }
  ctrl$attribution <- list(rule = "nested_majority_placebo_v2", majority_share = maj, placebo_alpha = pl$alpha, tol = tol,
                           overall = one("overall"), visible = one("visible"), test = one("test"))
  card$controls <- ctrl
  card
}

# 긴 벤치 이력(연대기 · 위기 정의용) — grade_v3.R::gv3_bench_history 와 같은 원천 · 같은 정규화
.mc_bench_history <- function(root) {
  bp <- file.path(root, ".cache/benchmark.parquet")
  if (!file.exists(bp) || !requireNamespace("arrow", quietly = TRUE)) return(NULL)
  h <- as.data.table(arrow::read_parquet(bp))
  if (!all(c("Date", "BM_Ret") %in% names(h))) return(NULL)
  h[is.finite(BM_Ret), .(date = as.Date(Date), benchmark_ret = BM_Ret)][order(date)]
}

#' 측정 산출물 디렉터리 → 행동 카드 + 크기 · 노출 짝 대조 + 귀속 라벨
#'   카드는 등급 v3 와 같은 입력으로 만든다(벤치 이력은 측정 마지막 날까지만 — grade_v3.R 재현성 규약).
#' @param raw mc_load_raw 판(여러 디렉터리면 한 번 읽어 넘긴다) · @param bm_hist 긴 벤치 이력(없으면 .cache 에서)
mc_card <- function(dir, root = NULL, raw = NULL, bm_hist = NULL, cfg = NULL, bcfg = NULL) {
  root <- .mc_root(root); e <- .mc_deps(root)
  cfg <- .mc_or(cfg, mc_cfg(root)); bcfg <- .mc_or(bcfg, e$bc_cfg(root))
  f <- function(n) { p <- file.path(dir, n); if (!file.exists(p)) stop("[matched_controls] 산출물 없음: ", p); p }
  pr <- fread(f("03_period_returns.csv")); br <- fread(f("05_benchmark_returns.csv")); H <- fread(f("04_holdings.csv"))
  pr[, date := as.Date(date)]; br[, date := as.Date(date)]; H[, date := as.Date(date)]
  rj <- function(n) { p <- file.path(dir, n); if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(err) list()) else list() }
  spec <- rj("01_strategy_spec.json"); man <- rj("00_manifest.json")
  uni <- .mc_or(spec[["universe"]], man[["universe_id"]])
  if (is.null(uni) || !length(uni) || is.na(uni[1]) || !nzchar(uni[1]))
    stop("[matched_controls] 유니버스 미상(01_strategy_spec.universe · 00_manifest.universe_id 없음) — 대조 유니버스를 정할 수 없다")
  uni <- as.character(uni[1])
  ep <- .mc_exec_price(spec, pr$date, H$date)
  last_d <- max(pr$date)
  if (is.null(bm_hist)) bm_hist <- .mc_bench_history(root)
  bmh <- if (is.null(bm_hist)) NULL else as.data.table(bm_hist)[date <= last_d]
  sid <- tryCatch(as.character(pr$strategy_id[1]), error = function(err) NA_character_)
  card <- e$bc_card(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], cfg = bcfg, bm_hist = bmh,
                    strategy_id = sid, root = root)
  if (is.null(raw)) raw <- mc_load_raw(root, from = min(H$date) - 31L, to = last_d, hygiene = identical(uni, "ALL_HYG"))
  ctl <- mc_controls(H, pr, br, raw, cfg, ep$value, uni)
  card <- mc_attribution(card, ctl, br[, .(date, benchmark_ret)], bcfg, e)
  card$controls$spec <- list(contract = "matched_controls_v1", cfg_schema = .mc_or(cfg$schema, NA_character_),
                             size_buckets = cfg$size_buckets, universe = uni, exec_price = ep$value,
                             exec_price_source = ep$source, window_approx = identical(ep$value, "open_t1"),
                             source_dir = dir)
  card
}

#' 카드 저장 — behavior_card.json(대조가 붙은 상위 판 · 원자적 쓰기는 behavior_card.R::bc_write)
mc_write <- function(card, out_dir, name = "behavior_card.json", root = NULL) {
  .mc_deps(.mc_root(root))$bc_write(card, out_dir, name)
}
