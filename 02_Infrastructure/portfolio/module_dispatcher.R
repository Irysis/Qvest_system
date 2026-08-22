#!/usr/bin/env Rscript
# =============================================================================
# module_dispatcher.R — Factor Rotation Mode (Track2 배분 엔진).
# 국면 L에서 모듈 가중 w_m(L) 산출. book_optimize 정적 QP의 regime-conditional 래퍼.
#   가중 = shrink 블렌드: (1) 국면조건부 risk-parity(inverse-vol/HRP, denoise)
#                        (2) 국면조건부 실현IR(강 shrink). λ/τ/k0 국면-불변 고정.
# PIT: IS 데이터로만 추정. 실측-only. book_optimize 직접개조 금지(래퍼).
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })

# ── 하이퍼파라미터 (국면-불변 단일세트 고정 — 과적합 통제) ──
.FR_HP <- list(lambda_rp = 0.5, lambda_ir = 0.5, tau = 0.6, k0 = 36, w_cap = 0.25, ir_floor = 0,
                min_retention = 0.25)   # R54 신설: 표현력 하한(아래 주석)

# 국면조건부 모듈 가중. 입력은 IS(결정시점 이전)에서 계산된 값만.
#   regime_ir : named vec(module -> 국면 L 내 shrunk IR)
#   vols      : named vec(module -> IS 일간 vol, risk-parity inverse-vol용)
#   n_regime  : named vec(module -> 국면 L 표본 수, shrink용)  [선택]
compute_regime_module_weights <- function(regime_ir, vols, n_regime = NULL,
                                          hp = .FR_HP, prev_w = NULL) {
  mods <- names(regime_ir); n <- length(mods); if (n == 0L) return(setNames(numeric(0), character(0)))
  if (n == 1L) return(setNames(1, mods))
  # (1) risk-parity 앵커 = inverse-vol (과적합無; 분산·turnover 억제)
  v <- vols[mods]; v[!is.finite(v) | v <= 0] <- stats::median(v[is.finite(v) & v > 0], na.rm = TRUE)
  w_rp <- (1 / v); w_rp <- w_rp / sum(w_rp)
  # (2) 국면조건부 실현IR (강 shrink: 표본 적으면 0으로 수렴)
  ir <- regime_ir[mods]; ir[!is.finite(ir)] <- 0
  if (!is.null(n_regime)) { nL <- n_regime[mods]; nL[!is.finite(nL)] <- 0
    ir <- ir * (nL / (nL + hp$k0)) }                          # shrink toward 0
  ir_pos <- pmax(ir, hp$ir_floor)
  w_ir <- if (sum(ir_pos) > 0) ir_pos / sum(ir_pos) else w_rp # IR 전무 시 rp로 폴백
  # 블렌드 → softmax(온도 τ) → cap → renorm
  score <- hp$lambda_rp * w_rp + hp$lambda_ir * w_ir
  w <- exp(score / hp$tau); w <- w / sum(w)
  # cap 0.25 반복 정규화
  for (it in 1:50) { over <- w > hp$w_cap; if (!any(over)) break
    excess <- sum(w[over] - hp$w_cap); w[over] <- hp$w_cap
    free <- !over & w > 0; if (!any(free)) break
    w[free] <- w[free] + excess * (w[free] / sum(w[free])) }
  w <- w / sum(w); w <- setNames(as.numeric(w), mods)

  # ── 표현력 진단 (2026-08-22 R54 신설) ─────────────────────────────────────
  # ★왜: 이 규칙은 *비중*(합=1)에 softmax 를 건다. 모듈 수 n 이 커지면 score 가 1/n 근처로
  #   몰려 tau 대비 스프레드가 사라지고 출력이 rp 앵커(사실상 균등)로 수렴한다.
  #   R54 실측(n=21): 입력 5.2배 -> 출력 1.40배 = 신호 91% 압축, 정적 EW 와 구분 불가
  #   (대응표본 NW-t +0.225). 그런데 산출물은 여전히 "국면조건부 비중" 으로 라벨된다
  #   = 침묵 실패. 하이퍼(tau 0.6 / cap 0.25 / k0 36)는 모듈 5~10개 규모 캘리브값이다.
  # 측정: softmax 이전의 blend(score)가 rp 앵커에서 벗어난 양 대비, 실제 출력이 벗어난 양.
  #   score 는 이미 합=1 이므로 softmax 가 없었다면 그대로 비중이 됐을 "의도된 비중" 이다.
  l1 <- function(a, b) sum(abs(a - b))
  intended_dev <- l1(score, w_rp)
  actual_dev   <- l1(w, w_rp)
  retention <- if (intended_dev > 1e-12) actual_dev / intended_dev else NA_real_
  attr(w, "fr_diag") <- list(n_modules = n, retention = retention,
                             intended_dev = intended_dev, actual_dev = actual_dev,
                             dev_from_ew = l1(w, rep(1 / n, n)))
  if (is.finite(retention) && retention < hp$min_retention) {
    warning(sprintf(paste0("[compute_regime_module_weights] 표현력 저하: 국면 신호의 %.0f%%가 ",
      "softmax(tau=%.2f)에서 소실 (retention=%.3f < %.2f, n=%d). ",
      "출력이 risk-parity 앵커와 사실상 동일하므로 '국면조건부' 라벨을 붙이지 말 것. ",
      "모듈 수를 줄이거나 tau 를 n 에 맞게 재캘리브할 것 (R54 실측: n=21 에서 91%% 압축)."),
      100 * (1 - retention), hp$tau, retention, hp$min_retention, n), call. = FALSE)
  }
  w
}

#' 표현력 진단 읽기 — compute_regime_module_weights() 결과의 attr 접근자
fr_weight_expressiveness <- function(w) attr(w, "fr_diag")

cat("[module_dispatcher] Loaded. compute_regime_module_weights() (regime-conditional rp+IR shrink blend)
",
    " +표현력 진단(R54): retention < min_retention 이면 warning + attr(w,'fr_diag'). fr_weight_expressiveness() 로 조회.
")
