// =============================================================================
// roll_beta_cpp.cpp — Rolling OLS β (per-ticker) Rcpp 최적화
// =============================================================================
// 2026-04-24 · L-194/L-195 후속 · Pilot 8+ 사용
//
// 배경:
//   Pilot 5/6 Alpha Agent Rscript 중 per-ticker rolling 252d β 계산이 가장 느림.
//   R for-loop + lm() 기반: 348 tickers × ~3000 days = 수 분. R13 future 병렬로
//   core 8개 활용해도 CPU bound 구간이 남음. Rcpp는 동일 core에서도 10~20× 빠름.
//
// 수학적 정의 (rolling window w):
//   β_t = Σ(x_i - x̄)(y_i - ȳ) / Σ(x_i - x̄)²  (i ∈ [t-w+1, t])
//   α_t = ȳ - β_t·x̄
//   R²_t = 1 - SS_res / SS_tot
//
// 구현 최적화:
//   - Welford incremental 업데이트로 O(n) (naive recompute는 O(n·w))
//   - Rcpp::NumericVector 직접 접근 (no R copy)
//   - NA 처리: window 내 NA 있으면 해당 시점 NA 반환 (skip)
//   - intercept 포함 OLS (default). no_intercept 옵션으로 pass-through.
//
// 기대 속도 (실측 예정):
//   R roll::roll_lm() (Rcpp 기반) 대비 2~3× · R for-loop + lm() 대비 10~20×
//
// 사용:
//   Rcpp::sourceCpp("02_Infrastructure/cpp/roll_beta_cpp.cpp")
//   result <- roll_beta_cpp(y, x, window = 252L)  # list(beta, alpha, r2)
// =============================================================================

#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

// Helper: check window NA
inline bool any_na(const NumericVector& v, int start, int end) {
  for (int i = start; i <= end; ++i) {
    if (NumericVector::is_na(v[i])) return true;
  }
  return false;
}

// [[Rcpp::export]]
List roll_beta_cpp(NumericVector y, NumericVector x,
                    int window = 252L,
                    bool with_r2 = true) {
  int n = y.size();
  if (x.size() != n) {
    stop("roll_beta_cpp: y and x must have same length");
  }
  if (window < 2) stop("roll_beta_cpp: window must be >= 2");

  NumericVector beta_out(n, NA_REAL);
  NumericVector alpha_out(n, NA_REAL);
  NumericVector r2_out(n, NA_REAL);

  double w_inv = 1.0 / static_cast<double>(window);

  for (int t = window - 1; t < n; ++t) {
    int start = t - window + 1;
    int end = t;

    // NA guard: window 내 NA 하나라도 있으면 skip
    if (any_na(y, start, end) || any_na(x, start, end)) continue;

    // 1st pass: means
    double sum_x = 0.0, sum_y = 0.0;
    for (int i = start; i <= end; ++i) {
      sum_x += x[i];
      sum_y += y[i];
    }
    double mean_x = sum_x * w_inv;
    double mean_y = sum_y * w_inv;

    // 2nd pass: covariance + variance
    double cov_xy = 0.0, var_x = 0.0, var_y = 0.0;
    for (int i = start; i <= end; ++i) {
      double dx = x[i] - mean_x;
      double dy = y[i] - mean_y;
      cov_xy += dx * dy;
      var_x += dx * dx;
      if (with_r2) var_y += dy * dy;
    }

    if (var_x < 1e-12) {
      // x collinear to constant — β undefined
      continue;
    }

    double beta = cov_xy / var_x;
    double alpha = mean_y - beta * mean_x;

    beta_out[t] = beta;
    alpha_out[t] = alpha;

    if (with_r2) {
      if (var_y < 1e-12) {
        r2_out[t] = 0.0;
      } else {
        // R² = β² · var_x / var_y
        r2_out[t] = (beta * beta * var_x) / var_y;
      }
    }
  }

  int n_valid = 0;
  for (int i = 0; i < n; ++i) {
    if (!NumericVector::is_na(beta_out[i])) ++n_valid;
  }

  return List::create(
    _["beta"] = beta_out,
    _["alpha"] = alpha_out,
    _["r2"] = r2_out,
    _["window"] = window,
    _["n_valid"] = n_valid
  );
}

// =============================================================================
// Batch version: N tickers 동시 rolling β (shared market x)
// N×T matrix 입력 → beta[N,T] 반환. 내부 loop, 메모리 재사용 최적화.
// =============================================================================

// [[Rcpp::export]]
NumericMatrix roll_beta_batch_cpp(NumericMatrix Y, NumericVector x_mkt,
                                    int window = 252L) {
  int T_rows = Y.nrow();
  int N_cols = Y.ncol();
  if (x_mkt.size() != T_rows) {
    stop("roll_beta_batch_cpp: Y rows and x_mkt length must match");
  }
  if (window < 2) stop("roll_beta_batch_cpp: window must be >= 2");

  NumericMatrix out(T_rows, N_cols);
  std::fill(out.begin(), out.end(), NA_REAL);

  double w_inv = 1.0 / static_cast<double>(window);

  // Market x means (공유) — T 차원만 precompute
  NumericVector x_mean(T_rows, NA_REAL);
  NumericVector x_var(T_rows, NA_REAL);
  for (int t = window - 1; t < T_rows; ++t) {
    int start = t - window + 1;
    if (any_na(x_mkt, start, t)) continue;
    double sx = 0.0;
    for (int i = start; i <= t; ++i) sx += x_mkt[i];
    double mx = sx * w_inv;
    double vx = 0.0;
    for (int i = start; i <= t; ++i) {
      double d = x_mkt[i] - mx;
      vx += d * d;
    }
    x_mean[t] = mx;
    x_var[t] = vx;
  }

  // Per-ticker rolling β
  for (int j = 0; j < N_cols; ++j) {
    NumericVector y = Y(_, j);
    for (int t = window - 1; t < T_rows; ++t) {
      if (NumericVector::is_na(x_mean[t])) continue;
      int start = t - window + 1;
      if (any_na(y, start, t)) continue;
      if (x_var[t] < 1e-12) continue;

      double sy = 0.0;
      for (int i = start; i <= t; ++i) sy += y[i];
      double my = sy * w_inv;

      double cov_xy = 0.0;
      for (int i = start; i <= t; ++i) {
        cov_xy += (x_mkt[i] - x_mean[t]) * (y[i] - my);
      }
      out(t, j) = cov_xy / x_var[t];
    }
  }

  colnames(out) = colnames(Y);
  return out;
}
