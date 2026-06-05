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
.FR_HP <- list(lambda_rp = 0.5, lambda_ir = 0.5, tau = 0.6, k0 = 36, w_cap = 0.25, ir_floor = 0)

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
  w <- w / sum(w); setNames(as.numeric(w), mods)
}

cat("[module_dispatcher] Loaded. compute_regime_module_weights() (regime-conditional rp+IR shrink blend, λ/τ/k0 fixed).\n")
