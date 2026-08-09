## book_marginal.R — PG2 incumbent 대비 book-marginal ΔIR 측정 (단일 경로)
##
## 왜 계약인가: measurement-graduation §4 가 admission 을 "standalone 졸업" 이 아니라
##   **ΔIR = new_book_ir − incumbent_book_ir ≥ 0.05** 로 규정한다. 그런데 ΔIR 은
##   [[project-base-strength-flips-verdict-20260803]] 실측대로 **가중 규칙에 조건부인 국소량**이다
##   (같은 후보가 재구성 base 에서 +0.169, production base 에서 −0.149). 따라서
##   ①base 출처 ②가중 규칙 ③IR convention 세 가지를 **선언 필드로 못박지 않으면 판정이 갈린다**.
##
## base 권위 = [[feedback-production-code-as-baseline]] — 05_Production 현행 PG2 산출물(read-only).
##   저장 패널 재사용 금지 사고([[project-stored-panel-samemonth-lookahead]]) 회피: 여기서 읽는 것은
##   production 이 **자기 코드로 만든 backtest 산출물**이지 파생 알파 패널이 아니다.
## IR convention = book_state.json 선언과 동일한 `net_active_recon_v1`(net-active, arith).
##
## 자체합성 금지 정합: 포트 수익률 **구성**은 하지 않는다 — sleeve 월수익 계열을 받아
##   가중 결합만 하며, 결합 규칙을 declared 필드로 남긴다. Sharpe/IR 은 계약 경로 재사용.

suppressPackageStartupMessages({ library(data.table) })

.BM_PG2_DIR <- file.path("05_Production", "2.Factor_Model",
                         "2-3.STR_1715_on_M4_R05_noLayer4_PG2", "04_backtest_results")

#' PG2 incumbent 월별 계열 로드 (read-only)
#' @return data.table(date, ret_net, benchmark_ret, active)
bm_load_incumbent <- function(root = Sys.getenv("QM_ROOT",
                                "C:/Users/99922/OneDrive/Quant_Module_Moltbot")) {
  p <- file.path(root, .BM_PG2_DIR, "03_period_returns.csv")
  if (!file.exists(p)) stop("bm_load_incumbent: PG2 period_returns 부재 — ", p)
  PR <- fread(p)
  nm <- names(PR)
  dcol <- nm[which(tolower(nm) %in% c("date","period","ym"))[1]]
  rcol <- nm[which(tolower(nm) %in% c("ret_net","return","ret","portfolio_ret"))[1]]
  if (is.na(dcol) || is.na(rcol)) stop("bm_load_incumbent: 컬럼 식별 실패 — ", paste(nm, collapse=","))
  out <- data.table(date = as.Date(PR[[dcol]]), ret_net = as.numeric(PR[[rcol]]))

  ## 벤치는 계약 10-component 의 **별도 파일**에 있다(03_period_returns 에 없음).
  ## ★여기서 NA 로 넘기면 active 전량 NA 가 되고 IR 이 조용히 NA 가 된다 — 실측으로 걸렀음.
  bp <- file.path(root, .BM_PG2_DIR, "05_benchmark_returns.csv")
  if (!file.exists(bp)) stop("bm_load_incumbent: PG2 benchmark_returns 부재 — ", bp)
  BR <- fread(bp)
  bd <- names(BR)[which(tolower(names(BR)) %in% c("date","period","ym"))[1]]
  bc <- names(BR)[which(tolower(names(BR)) %in% c("benchmark_ret","bm_ret","bench_ret"))[1]]
  if (is.na(bd) || is.na(bc)) stop("bm_load_incumbent: 벤치 컬럼 식별 실패 — ", paste(names(BR), collapse=","))
  B <- data.table(date = as.Date(BR[[bd]]), benchmark_ret = as.numeric(BR[[bc]]),
                  benchmark_id = if ("benchmark_id" %in% names(BR)) as.character(BR$benchmark_id) else NA_character_)
  out <- merge(out, B, by = "date")
  if (nrow(out) == 0L) stop("bm_load_incumbent: 수익-벤치 날짜 겹침 0 — 정합 확인 필요")
  out[, active := ret_net - benchmark_ret]
  if (all(!is.finite(out$active))) stop("bm_load_incumbent: active 전량 비유한 — 조용한 NA 차단")
  setorder(out, date)
  out[]
}

#' net-active IR (arith, annualized) — convention `net_active_recon_v1`
bm_ir <- function(active, ppy = 12L) {
  a <- active[is.finite(active)]
  if (length(a) < 12L) return(NA_real_)
  s <- stats::sd(a)
  if (!is.finite(s) || s <= 0) return(NA_real_)
  mean(a) / s * sqrt(ppy)
}

#' ★book-marginal ΔIR 측정
#' @param sleeve data.table(date, ret_net) — 후보 슬리브 **월별 net 수익**(15bps 반영분)
#' @param weight 후보 비중 w. book = (1-w)*incumbent + w*sleeve
#' @param weight_rule 선언 필드. 판정 재현에 필수 — 값이 다르면 다른 판정이다.
#' @param require_overlap 최소 겹침 개월(기본 60) — 짧은 창의 국소 ΔIR 은 판정 불가
#' 월 인덱스 (연도 넘김 안전 — ym 정수 산술 금지: 200412+2 = 200414 는 존재하지 않는 달)
.bm_mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))

#' ★날짜 규약 정렬 — 두 계열은 **같은 수익월을 다르게 라벨**한다 (2026-08-09 실측 확정)
#'  PG2      : 수익월의 **다음 달 초**로 라벨 (2008-10 수익 → 2008-11-XX 행)
#'  후보 패널 : **신호월 말**로 라벨 (2008-10 수익 → 2008-09-30 행)
#'  ⇒ candidate month_index + 2 = PG2 month_index
#'  근거 3중: 벤치 상관 0.9375(2위 0.247) · 부호일치 88.1%(offset0 46.1%) · 2008-11 위기월 정합.
#'  ★날짜 그대로 merge 하면 겹침 0 이 되어 전 후보가 INSUFFICIENT_OVERLAP 으로 조용히 탈락한다.
.bm_align_offset <- function(sleeve_dates, incumbent_dates) {
  ds <- as.integer(format(sleeve_dates, "%d")); di <- as.integer(format(incumbent_dates, "%d"))
  s_is_eom <- stats::median(ds, na.rm = TRUE) >= 26
  i_is_eom <- stats::median(di, na.rm = TRUE) >= 26
  if (s_is_eom && !i_is_eom) return(list(offset = 2L, basis = "sleeve=월말(신호월) · incumbent=월초(수익월+1) → +2"))
  if (!s_is_eom && !i_is_eom) return(list(offset = 0L, basis = "양쪽 동일 규약(월초) → 0"))
  if (s_is_eom && i_is_eom)  return(list(offset = 0L, basis = "양쪽 동일 규약(월말) → 0"))
  list(offset = -2L, basis = "sleeve=월초 · incumbent=월말 → -2")
}

bm_delta_ir <- function(sleeve, weight = 0.20,
                        weight_rule = "static_blend_w_on_sleeve",
                        require_overlap = 60L, ppy = 12L, incumbent = NULL,
                        align_offset = NULL, bootstrap = TRUE, B_boot = 1000L) {
  stopifnot(is.data.frame(sleeve))
  S <- as.data.table(sleeve)
  dcol <- names(S)[which(tolower(names(S)) %in% c("date","period","ym"))[1]]
  rcol <- names(S)[which(tolower(names(S)) %in% c("ret_net","ret","return"))[1]]
  if (is.na(dcol) || is.na(rcol)) stop("bm_delta_ir: sleeve 컬럼(date, ret_net) 식별 실패")
  S <- data.table(date = as.Date(S[[dcol]]), sleeve_ret = as.numeric(S[[rcol]]))

  B <- if (is.null(incumbent)) bm_load_incumbent() else as.data.table(incumbent)
  al <- if (is.null(align_offset)) .bm_align_offset(S$date, B$date)
        else list(offset = as.integer(align_offset), basis = "caller 명시")
  S[, m := .bm_mi(date) + al$offset]
  B2 <- copy(B)[, m := .bm_mi(date)]
  X <- merge(B2, S[, .(m, sleeve_ret)], by = "m")
  n <- nrow(X)
  if (n < require_overlap) {
    return(list(status = "INSUFFICIENT_OVERLAP", n_overlap = n,
                required = require_overlap, delta_ir = NA_real_,
                align_offset = al$offset, align_basis = al$basis,
                note = sprintf(paste0("겹침 %d개월 < %d — 국소 ΔIR 은 판정 불가(창 의존). ",
                  "★겹침 0 이면 날짜 규약 불일치를 먼저 의심하라(적용 offset %+d: %s)"),
                  n, require_overlap, al$offset, al$basis)))
  }
  ## ★incumbent IR 은 **겹침 창에서** 재계산한다. 전기간 1.416 과 비교하면 창이 달라 판정이 갈린다.
  ir_inc  <- bm_ir(X$active, ppy)
  book    <- (1 - weight) * X$ret_net + weight * X$sleeve_ret
  ir_book <- bm_ir(book - X$benchmark_ret, ppy)
  ir_sleeve_standalone <- bm_ir(X$sleeve_ret - X$benchmark_ret, ppy)

  d <- ir_book - ir_inc

  # ── [additive 2026-08-09] ★ΔIR 신뢰구간 + CI-기반 verdict ────────────────────
  #  왜: 문턱 0.05 는 **이 표본 길이에서 해상도 아래**다. 실측(합성 rho0.4·IR_s0.5·w0.20):
  #    73개월 se 0.0935 / 108개월 0.0760 / **269개월 0.0460** → 문턱은 269개월에서도 1.09se.
  #    2se 판별에 ~911개월(75.9년) 필요 = 가용치의 3.4배.
  #  ⇒ 점추정만 보고 "BEATS_PG2" 를 찍으면 **잡음을 통과로 보고**하게 된다(2026-08-09 실사고:
  #    Q-Lead 가 계약 슬리브를 그 라벨로 보고했고 CI 는 0 을 포함하고 있었다).
  #  ★비대칭이 핵심: **탈락 판정은 유효**(큰 음수는 여러 se 밖) · **통과 판정은 무효**.
  #  ★문턱을 낮추는 것이 아니다(제약 완화 금지 INV-7) — 문턱은 그대로 두고 CI 를 병기한다.
  #  블록 부트스트랩(block=12): active 계열은 자기상관이 있어 iid 는 se 를 과소추정한다
  #  (저장소 holdout 규약과 동일 블록 길이).
  ci <- local({
    if (!isTRUE(bootstrap) || n < 24L) return(list(available = FALSE, note = "n<24 또는 bootstrap=FALSE"))
    a_i <- X$ret_net - X$benchmark_ret; a_s <- X$sleeve_ret - X$benchmark_ret
    bl <- min(12L, max(2L, floor(n / 6)))
    nb <- ceiling(n / bl); starts <- seq_len(n - bl + 1L)
    dd <- vapply(seq_len(B_boot), function(b) {
      idx <- unlist(lapply(sample(starts, nb, TRUE), function(s) s:(s + bl - 1L)))[seq_len(n)]
      bm_ir((1 - weight) * a_i[idx] + weight * a_s[idx], ppy) - bm_ir(a_i[idx], ppy)
    }, numeric(1))
    dd <- dd[is.finite(dd)]
    if (length(dd) < 100L) return(list(available = FALSE, note = "부트스트랩 유효 표본 부족"))
    list(available = TRUE, block = bl, n_boot = length(dd),
         se = stats::sd(dd), lo = unname(stats::quantile(dd, 0.05)),
         hi = unname(stats::quantile(dd, 0.95)),
         p_above_threshold = mean(dd >= 0.05), p_above_zero = mean(dd > 0))
  })

  # CI 기반 verdict — 점추정 verdict 는 point_verdict 로 보존(비파괴)
  verdict_ci <- if (!isTRUE(ci$available)) "UNRESOLVED_NO_CI"
    else if (ci$lo >= 0.05) "BEATS_PG2"
    else if (ci$hi < 0)     "NO_IMPROVEMENT"
    else if (ci$hi < 0.05)  "BELOW_THRESHOLD"
    else                    "UNRESOLVED"

  list(
    status = "MEASURED",
    delta_ir_ci = ci,
    verdict_ci = verdict_ci,
    verdict_note = paste0(
      "★verdict_ci 가 권위다. verdict(점추정)는 ΔIR 의 표준오차를 무시하므로 ",
      "문턱 근처에서 잡음을 통과로 보고한다(실측: 269개월에서도 문턱은 1.09 표준오차). ",
      "UNRESOLVED = 통과도 미달도 단정 불가 — 증거 누적 대기. ",
      "★탈락 판정(NO_IMPROVEMENT)은 신뢰할 수 있고 통과 판정은 CI 하단이 문턱을 넘을 때만 유효하다."),
    metric_type = "backtested",
    ir_convention = "net_active_recon_v1",
    base_provenance = "05_Production/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results (production 자기 산출)",
    weight_rule = weight_rule, weight = weight,
    align_offset = al$offset, align_basis = al$basis,
    n_overlap = n, window = c(as.character(min(X$date)), as.character(max(X$date))),
    incumbent_ir_full_period = 1.416,
    incumbent_ir_on_overlap = ir_inc,
    book_ir = ir_book,
    sleeve_standalone_ir = ir_sleeve_standalone,
    delta_ir = d,
    admit_threshold = 0.05,
    verdict = if (!is.finite(d)) "UNDEFINED" else if (d >= 0.05) "BEATS_PG2" else if (d > 0) "POSITIVE_BUT_SUBTHRESHOLD" else "NO_IMPROVEMENT",
    correlation_with_incumbent = suppressWarnings(stats::cor(X$sleeve_ret - X$benchmark_ret, X$active)),
    caveat = paste0("ΔIR 은 weight_rule·weight·창에 조건부인 국소량이다(base_strength_flips 실증). ",
                    "인용 시 세 값을 반드시 병기. 자본 admit 은 governor 수동 — 이 함수는 판정 근거일 뿐."))
}

#' 여러 weight 에서 ΔIR 을 훑어 **단일 draw 취약성**을 배제 ([[project-threshold-single-draw-fragility-20260802]])
bm_delta_ir_sweep <- function(sleeve, weights = c(0.05, 0.10, 0.15, 0.20, 0.30), ...) {
  inc <- bm_load_incumbent()
  r <- lapply(weights, function(w) {
    o <- bm_delta_ir(sleeve, weight = w, incumbent = inc, ...)
    ci <- o$delta_ir_ci
    data.table(weight = w, status = o$status, n = o$n_overlap %||% NA_integer_,
               delta_ir = o$delta_ir %||% NA_real_,
               ci_lo = if (isTRUE(ci$available)) ci$lo else NA_real_,
               ci_hi = if (isTRUE(ci$available)) ci$hi else NA_real_,
               se = if (isTRUE(ci$available)) ci$se else NA_real_,
               verdict_ci = o$verdict_ci %||% NA_character_,
               verdict_point = o$verdict %||% NA_character_,
               book_ir = o$book_ir %||% NA_real_, cor_inc = o$correlation_with_incumbent %||% NA_real_)
  })
  R <- rbindlist(r, fill = TRUE)
  ## ★beats 는 **CI 하단**이 문턱을 넘을 때만 TRUE. 점추정 기준 통과는 beats_point 로 분리 보존.
  R[, beats := is.finite(ci_lo) & ci_lo >= 0.05]
  R[, beats_point := is.finite(delta_ir) & delta_ir >= 0.05]
  R[, unresolved := verdict_ci == "UNRESOLVED"]
  R[]
}

#' ★파킹 계열 구성 — **정렬을 계약 안에서** 한다 (2026-08-09 실사고 재발방지)
#'
#' 실사고: 파킹은 `ifelse(on, sleeve_r, benchmark_ret)` 인데, 나는 벤치를
#'   `merge(inc[, .(m, benchmark_ret)], S[, .(m, r)], by = "m")` 로 **손으로** 붙였다.
#'   슬리브 계열(`s1_inventory`)은 월 인덱스 `m` 만 보존하고 **date 를 버려** 라벨 규약이 소실됐고,
#'   실측 결과 12전략 중 **10건이 +1 어긋나** 있었다(offset0 상관 ~0, +1 에서 0.42~0.75).
#'   ⇒ OFF 월에 **한 달 전 벤치**를 넣고 있었다. `bm_delta_ir` 는 내부 정렬(`.bm_align_offset`)을
#'   갖지만 그건 **평가 시점**이고, 파킹 **구성**은 그 호출 *이전*에 계약 밖에서 일어났다.
#' ★지문: 무작위 라벨 파킹의 실현 β 가 **OFF 비율과 거의 같아진다**(실측 0.636 vs 0.644).
#'   정렬돼 있으면 β ≈ ON·β_sleeve + OFF·1 이라 1 근방이어야 한다.
#' ★피해: 부호가 뒤집힌 라벨 2건 · 전략-무관 예측 규칙(bm_gap) rho 0.815 → **0.156 으로 소멸**.
#'
#' @param sleeve data.table(m, r) — 슬리브 월수익 (월 인덱스 `m` = .bm_mi(date))
#' @param label  data.table(m, on) — 국면 라벨 (`m` 은 슬리브와 같은 공간)
#' @param incumbent bm_load_incumbent() 산출
#' @param cost_bps 라벨 전환 시 레그당 비용 (기본 15bps)
#' @param offset NULL 이면 실측(상관 최대). 정수를 주면 그 값을 쓰되 실측과 다르면 경고.
#' @return list(parked = data.table(date, m, ret_net, on), alignment = <선언 필드>)
bm_park <- function(sleeve, label, incumbent, cost_bps = 15, offset = NULL,
                    min_overlap = 60L, min_cor = 0.15) {
  stopifnot(all(c("m","r") %in% names(sleeve)), all(c("m","on") %in% names(label)))
  S <- as.data.table(sleeve)[, .(m, r)]
  I <- as.data.table(incumbent)[, .(m = .bm_mi(date), date, benchmark_ret)]
  ## ①정렬 실측 — 슬리브 수익과 벤치 수익의 상관이 최대인 오프셋
  ks <- -3:3
  cc <- vapply(ks, function(k) {
    Z <- merge(I[, .(m = m - k, benchmark_ret)], S, by = "m")
    if (nrow(Z) < 40L) return(NA_real_)
    suppressWarnings(stats::cor(Z$r, Z$benchmark_ret, use = "complete.obs"))
  }, numeric(1))
  k_meas <- if (all(is.na(cc))) NA_integer_ else as.integer(ks[which.max(cc)])
  c_max  <- if (all(is.na(cc))) NA_real_ else max(cc, na.rm = TRUE)
  ## ★저베타 슬리브는 정렬을 상관으로 못 정한다 — 조용히 0 을 고르지 말고 표시한다
  ambiguous <- !is.finite(c_max) || c_max < min_cor
  k_use <- if (!is.null(offset)) as.integer(offset) else if (ambiguous) 0L else k_meas
  if (!is.null(offset) && is.finite(k_meas) && !ambiguous && as.integer(offset) != k_meas)
    warning(sprintf("bm_park: 선언 offset %+d 이 실측 %+d 과 다릅니다 (max cor %.3f)",
                    as.integer(offset), k_meas, c_max))
  ## ★부호 규약을 **이름으로** 못박는다 — 검사에서 4/4 가 부호 반대로 읽혀 드러난 모호성.
  ##   offset = inc 의 월 라벨 − 슬리브의 월 라벨 (같은 수익월에 대해).
  ##   적용은 항상 `I[, m := m - offset]` (= inc 를 슬리브 월 공간으로 옮긴다).
  ## ②정렬된 벤치로 파킹 구성
  X <- merge(I[, .(m = m - k_use, date, benchmark_ret)], S, by = "m")
  X <- merge(X, as.data.table(label)[, .(m, on)], by = "m")
  setorder(X, m)
  if (nrow(X) < min_overlap)
    return(list(parked = NULL, alignment = list(status = "INSUFFICIENT_OVERLAP", n = nrow(X),
                offset_applied = k_use, offset_inc_minus_sleeve = k_meas, max_cor = c_max)))
  X[, sw := c(0L, abs(diff(as.integer(on))))]
  X[, ret_net := ifelse(on, r, benchmark_ret) - sw * cost_bps / 1e4]
  list(parked = X[, .(date, m, ret_net, on, sleeve_r = r, benchmark_ret)],
       alignment = list(status = if (ambiguous) "AMBIGUOUS_LOWCOR" else "MEASURED",
                        offset_applied = k_use, offset_inc_minus_sleeve = k_meas, max_cor = c_max,
                        cor_at_zero = cc[ks == 0L], n = nrow(X), cost_bps = cost_bps,
                        note = paste0("★offset_inc_minus_sleeve = inc 월라벨 − 슬리브 월라벨(같은 수익월). ",
                                      "적용은 항상 I[, m := m - offset]. 슬리브 계열의 월-라벨 규약 차이다. ",
                                      "AMBIGUOUS_LOWCOR 이면 상관으로 정렬을 정할 수 없으므로 ",
                                      "판정 인용 시 이 라벨을 병기할 것.")))
}

`%||%` <- function(a, b) if (is.null(a)) b else a
cat("[book_marginal.R] Loaded — bm_load_incumbent() / bm_delta_ir() / bm_delta_ir_sweep() / bm_park()\n")
