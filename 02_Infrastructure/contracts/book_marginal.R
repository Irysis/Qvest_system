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
  bcol <- nm[which(tolower(nm) %in% c("benchmark_ret","bm_ret","bench_ret"))[1]]
  if (is.na(dcol) || is.na(rcol)) stop("bm_load_incumbent: 컬럼 식별 실패 — ", paste(nm, collapse=","))
  out <- data.table(date = as.Date(PR[[dcol]]), ret_net = as.numeric(PR[[rcol]]))
  out[, benchmark_ret := if (!is.na(bcol)) as.numeric(PR[[bcol]]) else NA_real_]
  out[, active := ret_net - benchmark_ret]
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
bm_delta_ir <- function(sleeve, weight = 0.20,
                        weight_rule = "static_blend_w_on_sleeve",
                        require_overlap = 60L, ppy = 12L, incumbent = NULL) {
  stopifnot(is.data.frame(sleeve))
  S <- as.data.table(sleeve)
  dcol <- names(S)[which(tolower(names(S)) %in% c("date","period","ym"))[1]]
  rcol <- names(S)[which(tolower(names(S)) %in% c("ret_net","ret","return"))[1]]
  if (is.na(dcol) || is.na(rcol)) stop("bm_delta_ir: sleeve 컬럼(date, ret_net) 식별 실패")
  S <- data.table(date = as.Date(S[[dcol]]), sleeve_ret = as.numeric(S[[rcol]]))

  B <- if (is.null(incumbent)) bm_load_incumbent() else as.data.table(incumbent)
  X <- merge(B, S, by = "date")
  n <- nrow(X)
  if (n < require_overlap) {
    return(list(status = "INSUFFICIENT_OVERLAP", n_overlap = n,
                required = require_overlap, delta_ir = NA_real_,
                note = sprintf("겹침 %d개월 < %d — 국소 ΔIR 은 판정 불가(창 의존)", n, require_overlap)))
  }
  ## ★incumbent IR 은 **겹침 창에서** 재계산한다. 전기간 1.416 과 비교하면 창이 달라 판정이 갈린다.
  ir_inc  <- bm_ir(X$active, ppy)
  book    <- (1 - weight) * X$ret_net + weight * X$sleeve_ret
  ir_book <- bm_ir(book - X$benchmark_ret, ppy)
  ir_sleeve_standalone <- bm_ir(X$sleeve_ret - X$benchmark_ret, ppy)

  d <- ir_book - ir_inc
  list(
    status = "MEASURED",
    metric_type = "backtested",
    ir_convention = "net_active_recon_v1",
    base_provenance = "05_Production/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results (production 자기 산출)",
    weight_rule = weight_rule, weight = weight,
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
    data.table(weight = w, status = o$status, n = o$n_overlap %||% NA_integer_,
               delta_ir = o$delta_ir %||% NA_real_, verdict = o$verdict %||% NA_character_,
               book_ir = o$book_ir %||% NA_real_, cor_inc = o$correlation_with_incumbent %||% NA_real_)
  })
  R <- rbindlist(r, fill = TRUE)
  R[, beats := is.finite(delta_ir) & delta_ir >= 0.05]
  R[]
}

`%||%` <- function(a, b) if (is.null(a)) b else a
cat("[book_marginal.R] Loaded — bm_load_incumbent() / bm_delta_ir() / bm_delta_ir_sweep()\n")
