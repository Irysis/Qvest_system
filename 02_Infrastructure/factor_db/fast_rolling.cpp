// fast_rolling.cpp — High-performance rolling statistics for Factor DB
//
// Provides O(N) rolling implementations to replace R's O(N*window) frollapply.
//
// Exported functions:
//   rolling_mean_cpp(x, window)
//   rolling_sd_cpp(x, window)
//   rolling_skew_cpp(x, window)       — standardized skewness (m3 / m2^1.5)
//   rolling_kurt_cpp(x, window)       — excess kurtosis (m4 / m2^2 - 3)
//   rolling_beta_cpp(stock, mkt, window) — OLS beta via rolling cov/var
//   rolling_cov_cpp(x, y, window)     — rolling covariance
//   rolling_idiovol_cpp(stock, mkt, window) — rolling CAPM residual std dev
//   rank_pct_cpp(x)                   — cross-sectional rank percentile [0,1]
//
// PIT compliance: all functions use ONLY observations up to index i.
// No future data is accessed at any point.
//
// Build: sourceCpp("fast_rolling.cpp") or via rcpp_helpers.R

// [[Rcpp::plugins(cpp11)]]
#include <Rcpp.h>
#include <cmath>
#include <algorithm>
#include <vector>
using namespace Rcpp;

// ─── Inline helpers ─────────────────────────────────────────────────────────

static inline bool is_na_dbl(double x) {
  return ISNAN(x);
}

// ─── 1. rolling_mean_cpp ─────────────────────────────────────────────────────
// O(N) Welford-style running sum. Returns NA for first (window-1) positions
// and whenever valid count == 0.

// [[Rcpp::export]]
NumericVector rolling_mean_cpp(NumericVector x, int window) {
  int n = x.size();
  NumericVector out(n, NA_REAL);
  if (window <= 0 || n == 0) return out;

  double sum = 0.0;
  int   cnt = 0;

  for (int i = 0; i < n; i++) {
    // Add new observation
    if (!is_na_dbl(x[i])) { sum += x[i]; cnt++; }

    // Remove observation falling out of window
    if (i >= window) {
      if (!is_na_dbl(x[i - window])) { sum -= x[i - window]; cnt--; }
    }

    // Emit result only when full window is available
    if (i >= window - 1 && cnt > 0) {
      out[i] = sum / cnt;
    }
  }
  return out;
}

// ─── 2. rolling_sd_cpp ───────────────────────────────────────────────────────
// Welford online variance (numerically stable). Sample std dev (ddof=1).

// [[Rcpp::export]]
NumericVector rolling_sd_cpp(NumericVector x, int window) {
  int n = x.size();
  NumericVector out(n, NA_REAL);
  if (window <= 1 || n == 0) return out;

  // Circular buffer approach for exact computation
  std::vector<double> buf(window, NA_REAL);
  double sum = 0.0, sum2 = 0.0;
  int cnt = 0, head = 0;

  for (int i = 0; i < n; i++) {
    double old_val = buf[head];
    double new_val = x[i];

    // Remove old value from buffer
    if (!is_na_dbl(old_val)) {
      sum  -= old_val;
      sum2 -= old_val * old_val;
      cnt--;
    }
    // Add new value
    buf[head] = new_val;
    if (!is_na_dbl(new_val)) {
      sum  += new_val;
      sum2 += new_val * new_val;
      cnt++;
    }
    head = (head + 1) % window;

    if (i >= window - 1 && cnt >= 2) {
      double mean_val = sum / cnt;
      double var_val  = (sum2 - cnt * mean_val * mean_val) / (cnt - 1);
      out[i] = (var_val > 0.0) ? std::sqrt(var_val) : 0.0;
    }
  }
  return out;
}

// ─── 3. rolling_skew_cpp ─────────────────────────────────────────────────────
// Standardized skewness = m3 / m2^1.5 (Fisher's moment coefficient).
// Returns NA when cnt < 3.

// [[Rcpp::export]]
NumericVector rolling_skew_cpp(NumericVector x, int window) {
  int n = x.size();
  NumericVector out(n, NA_REAL);
  if (window < 3 || n == 0) return out;

  std::vector<double> buf(window, NA_REAL);
  int cnt = 0, head = 0;
  double s1 = 0.0, s2 = 0.0, s3 = 0.0;  // sum, sum of squares, sum of cubes

  for (int i = 0; i < n; i++) {
    double old_val = buf[head];
    double new_val = x[i];

    if (!is_na_dbl(old_val)) {
      s1 -= old_val;
      s2 -= old_val * old_val;
      s3 -= old_val * old_val * old_val;
      cnt--;
    }
    buf[head] = new_val;
    if (!is_na_dbl(new_val)) {
      s1 += new_val;
      s2 += new_val * new_val;
      s3 += new_val * new_val * new_val;
      cnt++;
    }
    head = (head + 1) % window;

    if (i >= window - 1 && cnt >= 3) {
      double mu  = s1 / cnt;
      double m2  = s2 / cnt - mu * mu;
      double m3  = s3 / cnt - 3.0 * mu * (s2 / cnt) + 2.0 * mu * mu * mu;
      if (m2 > 1e-14) {
        out[i] = m3 / std::pow(m2, 1.5);
      }
    }
  }
  return out;
}

// ─── 4. rolling_kurt_cpp ─────────────────────────────────────────────────────
// Excess kurtosis = m4/m2^2 - 3. Returns NA when cnt < 4.

// [[Rcpp::export]]
NumericVector rolling_kurt_cpp(NumericVector x, int window) {
  int n = x.size();
  NumericVector out(n, NA_REAL);
  if (window < 4 || n == 0) return out;

  std::vector<double> buf(window, NA_REAL);
  int cnt = 0, head = 0;
  double s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0;

  for (int i = 0; i < n; i++) {
    double old_val = buf[head];
    double new_val = x[i];

    if (!is_na_dbl(old_val)) {
      double ov2 = old_val * old_val;
      s1 -= old_val;
      s2 -= ov2;
      s3 -= ov2 * old_val;
      s4 -= ov2 * ov2;
      cnt--;
    }
    buf[head] = new_val;
    if (!is_na_dbl(new_val)) {
      double nv2 = new_val * new_val;
      s1 += new_val;
      s2 += nv2;
      s3 += nv2 * new_val;
      s4 += nv2 * nv2;
      cnt++;
    }
    head = (head + 1) % window;

    if (i >= window - 1 && cnt >= 4) {
      double mu  = s1 / cnt;
      double mu2 = mu * mu;
      double m2  = s2 / cnt - mu2;
      double m3  = s3 / cnt - 3.0 * mu * (s2 / cnt) + 2.0 * mu2 * mu;
      double m4  = s4 / cnt - 4.0 * mu * (s3 / cnt)
                   + 6.0 * mu2 * (s2 / cnt) - 3.0 * mu2 * mu2;
      if (m2 > 1e-14) {
        out[i] = m4 / (m2 * m2) - 3.0;
      }
    }
  }
  return out;
}

// ─── 5. rolling_cov_cpp ──────────────────────────────────────────────────────
// Rolling sample covariance cov(x,y) with ddof=1.

// [[Rcpp::export]]
NumericVector rolling_cov_cpp(NumericVector x, NumericVector y, int window) {
  int n = x.size();
  NumericVector out(n, NA_REAL);
  if (n != y.size() || window <= 1 || n == 0) return out;

  std::vector<double> bx(window, NA_REAL), by_(window, NA_REAL);
  int cnt = 0, head = 0;
  double sx = 0.0, sy = 0.0, sxy = 0.0;

  for (int i = 0; i < n; i++) {
    double ox = bx[head], oy = by_[head];
    double nx = x[i],     ny = y[i];

    if (!is_na_dbl(ox) && !is_na_dbl(oy)) {
      sx -= ox; sy -= oy; sxy -= ox * oy; cnt--;
    }
    bx[head] = nx; by_[head] = ny;
    if (!is_na_dbl(nx) && !is_na_dbl(ny)) {
      sx += nx; sy += ny; sxy += nx * ny; cnt++;
    }
    head = (head + 1) % window;

    if (i >= window - 1 && cnt >= 2) {
      out[i] = (sxy - sx * sy / cnt) / (cnt - 1);
    }
  }
  return out;
}

// ─── 6. rolling_beta_cpp ─────────────────────────────────────────────────────
// Rolling OLS beta = cov(stock, mkt) / var(mkt). Uses ddof=1 internally.

// [[Rcpp::export]]
NumericVector rolling_beta_cpp(NumericVector stock_ret,
                               NumericVector mkt_ret,
                               int window) {
  int n = stock_ret.size();
  NumericVector out(n, NA_REAL);
  if (n != mkt_ret.size() || window <= 1 || n == 0) return out;

  std::vector<double> bs(window, NA_REAL), bm(window, NA_REAL);
  int cnt = 0, head = 0;
  double ss = 0.0, sm = 0.0, sm2 = 0.0, ssm = 0.0;

  for (int i = 0; i < n; i++) {
    double os = bs[head], om = bm[head];
    double ns = stock_ret[i], nm = mkt_ret[i];

    if (!is_na_dbl(os) && !is_na_dbl(om)) {
      ss -= os; sm -= om; sm2 -= om * om; ssm -= os * om; cnt--;
    }
    bs[head] = ns; bm[head] = nm;
    if (!is_na_dbl(ns) && !is_na_dbl(nm)) {
      ss += ns; sm += nm; sm2 += nm * nm; ssm += ns * nm; cnt++;
    }
    head = (head + 1) % window;

    if (i >= window - 1 && cnt >= 2) {
      double var_m = (sm2 - sm * sm / cnt) / (cnt - 1);
      if (var_m > 1e-14) {
        double cov_sm = (ssm - ss * sm / cnt) / (cnt - 1);
        out[i] = cov_sm / var_m;
      }
    }
  }
  return out;
}

// ─── 7. rolling_idiovol_cpp ──────────────────────────────────────────────────
// Rolling idiosyncratic volatility = std dev of CAPM residuals.
// residual_i = stock_ret_i - (alpha + beta * mkt_ret_i)
// alpha and beta are estimated on the SAME rolling window (expanding internally).
// Returns NA for i < window-1.

// [[Rcpp::export]]
NumericVector rolling_idiovol_cpp(NumericVector stock_ret,
                                  NumericVector mkt_ret,
                                  int window) {
  int n = stock_ret.size();
  NumericVector out(n, NA_REAL);
  if (n != mkt_ret.size() || window <= 2 || n == 0) return out;

  std::vector<double> bs(window, NA_REAL), bm(window, NA_REAL);
  int cnt = 0, head = 0;
  double ss = 0.0, sm = 0.0, sm2 = 0.0, ssm = 0.0;
  double ss2 = 0.0;  // sum of stock^2 for residual variance

  for (int i = 0; i < n; i++) {
    double os = bs[head], om = bm[head];
    double ns = stock_ret[i], nm = mkt_ret[i];

    if (!is_na_dbl(os) && !is_na_dbl(om)) {
      ss -= os; sm -= om; sm2 -= om * om; ssm -= os * om;
      ss2 -= os * os;
      cnt--;
    }
    bs[head] = ns; bm[head] = nm;
    if (!is_na_dbl(ns) && !is_na_dbl(nm)) {
      ss += ns; sm += nm; sm2 += nm * nm; ssm += ns * nm;
      ss2 += ns * ns;
      cnt++;
    }
    head = (head + 1) % window;

    if (i >= window - 1 && cnt >= 3) {
      double var_m = (sm2 - sm * sm / cnt) / (cnt - 1);
      if (var_m < 1e-14) continue;

      double cov_sm = (ssm - ss * sm / cnt) / (cnt - 1);
      double beta   = cov_sm / var_m;
      double alpha  = ss / cnt - beta * sm / cnt;

      // RSS = sum((s_i - alpha - beta*m_i)^2) using moments
      // = ss2 - 2*alpha*ss - 2*beta*ssm + cnt*alpha^2 + 2*alpha*beta*sm + beta^2*sm2
      double rss = ss2
                   - 2.0 * alpha * ss
                   - 2.0 * beta  * ssm
                   + cnt * alpha * alpha
                   + 2.0 * alpha * beta * sm
                   + beta * beta * sm2;
      if (rss < 0.0) rss = 0.0;
      double idio_var = rss / (cnt - 2);  // ddof=2 for alpha+beta
      out[i] = std::sqrt(idio_var);
    }
  }
  return out;
}

// ─── 8. rank_pct_cpp ─────────────────────────────────────────────────────────
// Cross-sectional rank percentile in [0, 1]. NAs map to NA.
// Ties broken by average rank. Equivalent to frank(..., ties="average") / n.

// [[Rcpp::export]]
NumericVector rank_pct_cpp(NumericVector x) {
  int n = x.size();
  NumericVector out(n, NA_REAL);
  if (n == 0) return out;

  // Index of non-NA values
  std::vector<int> valid_idx;
  valid_idx.reserve(n);
  for (int i = 0; i < n; i++) {
    if (!is_na_dbl(x[i])) valid_idx.push_back(i);
  }
  int m = valid_idx.size();
  if (m == 0) return out;
  if (m == 1) { out[valid_idx[0]] = 0.5; return out; }

  // Sort valid indices by value
  std::vector<int> sorted = valid_idx;
  std::sort(sorted.begin(), sorted.end(),
            [&](int a, int b){ return x[a] < x[b]; });

  // Assign average ranks for ties
  int j = 0;
  while (j < m) {
    int k = j;
    // Find tie group
    while (k < m - 1 && x[sorted[k]] == x[sorted[k + 1]]) k++;
    double avg_rank = (j + k) / 2.0;  // 0-indexed average
    for (int l = j; l <= k; l++) {
      out[sorted[l]] = avg_rank / (m - 1);  // scale to [0,1]
    }
    j = k + 1;
  }
  return out;
}
