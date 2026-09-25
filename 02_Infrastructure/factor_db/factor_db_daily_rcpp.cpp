// factor_db_daily_rcpp.cpp — Daily Factor DB 핵심 롤링 함수 (Rcpp)
// DnBeta/UpBeta/CondBeta + 범용 rolling OLS/stats
// PIT C1~C3: rolling window only, align=right, no future data
// Compile: Rcpp::sourceCpp("factor_db_daily_rcpp.cpp")

#include <Rcpp.h>
#include <cmath>
#include <algorithm>
using namespace Rcpp;

// ─── 1. Rolling Conditional Beta (Downside/Upside) ──────────────────────────
// 핵심 병목 해소: frollapply → C++ (~100x speedup)
// downside=true: bm<0 일만, upside=false: bm>0 일만
// [[Rcpp::export]]
NumericVector roll_cond_beta_cpp(NumericVector ret, NumericVector bm,
                                 int n, bool downside) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;

  for (int i = n - 1; i < m; i++) {
    double sx = 0.0, sy = 0.0, sxy = 0.0, sx2 = 0.0;
    int cnt = 0;
    for (int j = i - n + 1; j <= i; j++) {
      if (NumericVector::is_na(ret[j]) || NumericVector::is_na(bm[j])) continue;
      bool cond = downside ? (bm[j] < 0.0) : (bm[j] > 0.0);
      if (!cond) continue;
      double b = bm[j], r = ret[j];
      sx += b; sy += r; sxy += r * b; sx2 += b * b;
      cnt++;
    }
    if (cnt < 5) continue;
    double den = (double)cnt * sx2 - sx * sx;
    if (std::abs(den) < 1e-12) continue;
    out[i] = ((double)cnt * sxy - sx * sy) / den;
  }
  return out;
}

// ─── 2. Rolling OLS Beta (unconditional) ────────────────────────────────────
// frollsum 대비 단일 패스 + 온라인 알고리즘 (수치 안정)
// [[Rcpp::export]]
NumericVector roll_beta_cpp(NumericVector ret, NumericVector bm, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 3) return out;

  // 초기 윈도우 축적
  double sr = 0.0, sb = 0.0, srb = 0.0, sb2 = 0.0;
  int valid = 0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(ret[j]) || NumericVector::is_na(bm[j])) continue;
    double r = ret[j], b = bm[j];
    sr += r; sb += b; srb += r * b; sb2 += b * b;
    valid++;
  }
  if (valid >= 3) {
    double den = (double)valid * sb2 - sb * sb;
    if (std::abs(den) > 1e-12)
      out[n - 1] = ((double)valid * srb - sr * sb) / den;
  }

  // 슬라이딩 윈도우
  for (int i = n; i < m; i++) {
    // remove oldest
    int old = i - n;
    if (!NumericVector::is_na(ret[old]) && !NumericVector::is_na(bm[old])) {
      double r = ret[old], b = bm[old];
      sr -= r; sb -= b; srb -= r * b; sb2 -= b * b;
      valid--;
    }
    // add newest
    if (!NumericVector::is_na(ret[i]) && !NumericVector::is_na(bm[i])) {
      double r = ret[i], b = bm[i];
      sr += r; sb += b; srb += r * b; sb2 += b * b;
      valid++;
    }
    if (valid < 3) continue;
    double den = (double)valid * sb2 - sb * sb;
    if (std::abs(den) > 1e-12)
      out[i] = ((double)valid * srb - sr * sb) / den;
  }
  return out;
}

// ─── 3. Rolling IVol (잔차 표준편차) ─────────────────────────────────────────
// IVol^2 = Var(ret) - Cov(ret,bm)^2 / Var(bm)
// [[Rcpp::export]]
NumericVector roll_ivol_cpp(NumericVector ret, NumericVector bm, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 3) return out;

  double sr = 0, sb = 0, sr2 = 0, sb2 = 0, srb = 0;
  int valid = 0;

  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(ret[j]) || NumericVector::is_na(bm[j])) continue;
    double r = ret[j], b = bm[j];
    sr += r; sb += b; sr2 += r * r; sb2 += b * b; srb += r * b;
    valid++;
  }
  auto compute = [&]() -> double {
    if (valid < 3) return NA_REAL;
    double vn = (double)valid;
    double vr = (sr2 - sr * sr / vn) / (vn - 1.0);
    double vb = (sb2 - sb * sb / vn) / (vn - 1.0);
    double cv = (srb - sr * sb / vn) / (vn - 1.0);
    if (vb < 1e-12) return NA_REAL;
    double iv2 = vr - cv * cv / vb;
    return (iv2 > 0.0) ? std::sqrt(iv2) : NA_REAL;
  };

  out[n - 1] = compute();
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(ret[old]) && !NumericVector::is_na(bm[old])) {
      double r = ret[old], b = bm[old];
      sr -= r; sb -= b; sr2 -= r * r; sb2 -= b * b; srb -= r * b;
      valid--;
    }
    if (!NumericVector::is_na(ret[i]) && !NumericVector::is_na(bm[i])) {
      double r = ret[i], b = bm[i];
      sr += r; sb += b; sr2 += r * r; sb2 += b * b; srb += r * b;
      valid++;
    }
    out[i] = compute();
  }
  return out;
}

// ─── 4. Rolling SD (online Welford) ──────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_sd_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 2) return out;

  double s1 = 0.0, s2 = 0.0;
  int valid = 0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(x[j])) continue;
    s1 += x[j]; s2 += x[j] * x[j]; valid++;
  }
  if (valid >= 2) {
    double var = (s2 - s1 * s1 / (double)valid) / ((double)valid - 1.0);
    if (var > 0.0) out[n - 1] = std::sqrt(var);
  }
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(x[old])) { s1 -= x[old]; s2 -= x[old] * x[old]; valid--; }
    if (!NumericVector::is_na(x[i]))   { s1 += x[i];   s2 += x[i] * x[i];     valid++; }
    if (valid < 2) continue;
    double var = (s2 - s1 * s1 / (double)valid) / ((double)valid - 1.0);
    if (var > 0.0) out[i] = std::sqrt(var);
  }
  return out;
}

// ─── 5. Rolling Mean (online) ────────────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_mean_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 1) return out;

  double s = 0.0; int valid = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(x[j])) { s += x[j]; valid++; }
  }
  if (valid > 0) out[n - 1] = s / (double)valid;
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(x[old])) { s -= x[old]; valid--; }
    if (!NumericVector::is_na(x[i]))   { s += x[i];   valid++; }
    if (valid > 0) out[i] = s / (double)valid;
  }
  return out;
}

// ─── 6. Rolling Sum (online) ─────────────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_sum_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 1) return out;

  double s = 0.0; int valid = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(x[j])) { s += x[j]; valid++; }
  }
  if (valid == n) out[n - 1] = s;
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(x[old])) { s -= x[old]; valid--; }
    else valid++;  // was NA, now removed
    if (!NumericVector::is_na(x[i]))   { s += x[i]; valid++; }
    else valid--;  // new NA
    // only output if all valid
    if (valid == n) out[i] = s;
  }
  return out;
}

// ─── 7. Rolling Skewness (3rd central moment) ───────────────────────────────
// [[Rcpp::export]]
NumericVector roll_skew_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 3) return out;

  double s1 = 0, s2 = 0, s3 = 0;
  int valid = 0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(x[j])) continue;
    double v = x[j];
    s1 += v; s2 += v * v; s3 += v * v * v; valid++;
  }
  auto compute = [&]() -> double {
    if (valid < 3) return NA_REAL;
    double vn = (double)valid;
    double mu = s1 / vn;
    double m2 = s2 / vn - mu * mu;
    double sig = std::sqrt(std::max(m2, 0.0));
    if (sig < 1e-12) return NA_REAL;
    double m3 = s3 / vn - 3.0 * mu * (s2 / vn) + 2.0 * mu * mu * mu;
    return m3 / (sig * sig * sig);
  };

  out[n - 1] = compute();
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(x[old])) {
      double v = x[old]; s1 -= v; s2 -= v * v; s3 -= v * v * v; valid--;
    }
    if (!NumericVector::is_na(x[i])) {
      double v = x[i]; s1 += v; s2 += v * v; s3 += v * v * v; valid++;
    }
    out[i] = compute();
  }
  return out;
}

// ─── 8. Rolling Kurtosis (4th central moment, excess) ───────────────────────
// [[Rcpp::export]]
NumericVector roll_kurt_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 4) return out;

  double s1 = 0, s2 = 0, s3 = 0, s4 = 0;
  int valid = 0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(x[j])) continue;
    double v = x[j], v2 = v * v;
    s1 += v; s2 += v2; s3 += v2 * v; s4 += v2 * v2; valid++;
  }
  auto compute = [&]() -> double {
    if (valid < 4) return NA_REAL;
    double vn = (double)valid, mu = s1 / vn;
    double m2 = s2 / vn - mu * mu;
    double sig4 = m2 * m2;
    if (sig4 < 1e-24) return NA_REAL;
    double m4 = s4 / vn - 4.0 * mu * (s3 / vn) + 6.0 * mu * mu * (s2 / vn) - 3.0 * mu * mu * mu * mu;
    return m4 / sig4 - 3.0;
  };

  out[n - 1] = compute();
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(x[old])) {
      double v = x[old], v2 = v * v;
      s1 -= v; s2 -= v2; s3 -= v2 * v; s4 -= v2 * v2; valid--;
    }
    if (!NumericVector::is_na(x[i])) {
      double v = x[i], v2 = v * v;
      s1 += v; s2 += v2; s3 += v2 * v; s4 += v2 * v2; valid++;
    }
    out[i] = compute();
  }
  return out;
}

// ─── 9. Rolling Autocorrelation lag-1 ───────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_autocorr_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n + 1 || n < 3) return out;

  // Corr(ret[t], ret[t-1]) over rolling window
  for (int i = n; i < m; i++) {
    double sx = 0, sy = 0, sxy = 0, sx2 = 0, sy2 = 0;
    int cnt = 0;
    for (int j = i - n + 1; j <= i; j++) {
      if (NumericVector::is_na(ret[j]) || NumericVector::is_na(ret[j - 1])) continue;
      double x = ret[j], y = ret[j - 1];
      sx += x; sy += y; sxy += x * y; sx2 += x * x; sy2 += y * y;
      cnt++;
    }
    if (cnt < 3) continue;
    double cn = (double)cnt;
    double vx = (sx2 - sx * sx / cn);
    double vy = (sy2 - sy * sy / cn);
    if (std::abs(vx) < 1e-12 || std::abs(vy) < 1e-12) continue;
    out[i] = (sxy - sx * sy / cn) / std::sqrt(vx * vy);
  }
  return out;
}

// ─── 10. Running Max (52-week high 등) ──────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_max_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 1) return out;

  // Simple O(n*m) — for n=252 and m~5000 per ticker, this is fine
  for (int i = n - 1; i < m; i++) {
    double mx = -1e300;
    bool any_valid = false;
    for (int j = i - n + 1; j <= i; j++) {
      if (!NumericVector::is_na(x[j]) && x[j] > mx) {
        mx = x[j]; any_valid = true;
      }
    }
    if (any_valid) out[i] = mx;
  }
  return out;
}

// ─── 11. Rolling RSI (via mean gain/loss) ───────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_rsi_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 2) return out;

  double sg = 0.0, sl = 0.0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(ret[j])) continue;
    if (ret[j] > 0) sg += ret[j]; else sl += std::abs(ret[j]);
  }
  double ag = sg / (double)n, al = sl / (double)n;
  if (al > 1e-12) out[n - 1] = 100.0 - 100.0 / (1.0 + ag / al);

  for (int i = n; i < m; i++) {
    int old = i - n;
    // remove old
    if (!NumericVector::is_na(ret[old])) {
      if (ret[old] > 0) sg -= ret[old]; else sl -= std::abs(ret[old]);
    }
    // add new
    if (!NumericVector::is_na(ret[i])) {
      if (ret[i] > 0) sg += ret[i]; else sl += std::abs(ret[i]);
    }
    ag = sg / (double)n; al = sl / (double)n;
    if (al > 1e-12) out[i] = 100.0 - 100.0 / (1.0 + ag / al);
  }
  return out;
}

// ─── 12. Cumulative Return (log-sum, rolling) ───────────────────────────────
// [[Rcpp::export]]
NumericVector roll_cumret_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 1) return out;

  double lsum = 0.0;
  int valid = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(ret[j])) {
      lsum += std::log(std::max(1.0 + ret[j], 1e-9));
      valid++;
    }
  }
  if (valid == n) out[n - 1] = std::exp(lsum) - 1.0;

  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(ret[old])) {
      lsum -= std::log(std::max(1.0 + ret[old], 1e-9));
    } else { valid++; }
    if (!NumericVector::is_na(ret[i])) {
      lsum += std::log(std::max(1.0 + ret[i], 1e-9));
    } else { valid--; }
    if (valid == n) out[i] = std::exp(lsum) - 1.0;
  }
  return out;
}

// ─── 13. Rolling Max of single values (for MaxRet) ─────────────────────────
// [[Rcpp::export]]
NumericVector roll_max_val_cpp(NumericVector x, int n) {
  return roll_max_cpp(x, n);
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 3 추가 함수들 — Defense/Liquidity/Risk/Crowding 확장
// ═══════════════════════════════════════════════════════════════════════════

// ─── 14. Rolling Min ────────────────────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_min_cpp(NumericVector x, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 1) return out;
  for (int i = n - 1; i < m; i++) {
    double mn = 1e300; bool any = false;
    for (int j = i - n + 1; j <= i; j++) {
      if (!NumericVector::is_na(x[j]) && x[j] < mn) { mn = x[j]; any = true; }
    }
    if (any) out[i] = mn;
  }
  return out;
}

// ─── 15. Rolling Quantile (for VaR) ────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_quantile_cpp(NumericVector x, int n, double prob) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  std::vector<double> buf(n);
  for (int i = n - 1; i < m; i++) {
    int cnt = 0;
    for (int j = i - n + 1; j <= i; j++) {
      if (!NumericVector::is_na(x[j])) buf[cnt++] = x[j];
    }
    if (cnt < 5) continue;
    std::sort(buf.begin(), buf.begin() + cnt);
    double idx = prob * (cnt - 1);
    int lo = (int)idx; int hi = lo + 1;
    if (hi >= cnt) hi = cnt - 1;
    double frac = idx - lo;
    out[i] = buf[lo] * (1.0 - frac) + buf[hi] * frac;
  }
  return out;
}

// ─── 16. Rolling CVaR (mean below VaR) ─────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_cvar_cpp(NumericVector x, int n, double prob) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  std::vector<double> buf(n);
  for (int i = n - 1; i < m; i++) {
    int cnt = 0;
    for (int j = i - n + 1; j <= i; j++) {
      if (!NumericVector::is_na(x[j])) buf[cnt++] = x[j];
    }
    if (cnt < 5) continue;
    std::sort(buf.begin(), buf.begin() + cnt);
    int cutoff = std::max(1, (int)(prob * cnt));
    double s = 0.0;
    for (int k = 0; k < cutoff; k++) s += buf[k];
    out[i] = s / cutoff;
  }
  return out;
}

// ─── 17. Rolling MDD (Maximum Drawdown) ────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_mdd_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  for (int i = n - 1; i < m; i++) {
    double cum = 1.0, peak = 1.0, mdd = 0.0;
    for (int j = i - n + 1; j <= i; j++) {
      if (NumericVector::is_na(ret[j])) continue;
      cum *= (1.0 + ret[j]);
      if (cum > peak) peak = cum;
      double dd = (peak - cum) / peak;
      if (dd > mdd) mdd = dd;
    }
    out[i] = mdd;
  }
  return out;
}

// ─── 18. Downside Deviation ────────────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_downside_dev_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  double s2 = 0.0; int cnt = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(ret[j]) && ret[j] < 0) {
      s2 += ret[j] * ret[j]; cnt++;
    }
  }
  if (cnt >= 3) out[n-1] = std::sqrt(s2 / cnt);
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(ret[old]) && ret[old] < 0) { s2 -= ret[old]*ret[old]; cnt--; }
    if (!NumericVector::is_na(ret[i]) && ret[i] < 0) { s2 += ret[i]*ret[i]; cnt++; }
    if (cnt >= 3) out[i] = std::sqrt(std::max(s2 / cnt, 0.0));
  }
  return out;
}

// ─── 19. Parkinson Volatility (log(H/L)) ──────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_parkinson_vol_cpp(NumericVector hi, NumericVector lo, int n) {
  int m = hi.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  double s = 0.0; int cnt = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(hi[j]) && !NumericVector::is_na(lo[j]) && lo[j] > 0) {
      double lhl = std::log(hi[j] / lo[j]);
      s += lhl * lhl; cnt++;
    }
  }
  if (cnt >= 3) out[n-1] = std::sqrt(s / (cnt * 4.0 * std::log(2.0)));
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(hi[old]) && !NumericVector::is_na(lo[old]) && lo[old] > 0) {
      double lhl = std::log(hi[old] / lo[old]);
      s -= lhl * lhl; cnt--;
    }
    if (!NumericVector::is_na(hi[i]) && !NumericVector::is_na(lo[i]) && lo[i] > 0) {
      double lhl = std::log(hi[i] / lo[i]);
      s += lhl * lhl; cnt++;
    }
    if (cnt >= 3) out[i] = std::sqrt(std::max(s / (cnt * 4.0 * std::log(2.0)), 0.0));
  }
  return out;
}

// ─── 20. Garman-Klass Volatility ───────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_gk_vol_cpp(NumericVector hi, NumericVector lo,
                               NumericVector cl, NumericVector op, int n) {
  int m = hi.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  double s = 0.0; int cnt = 0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(hi[j]) || NumericVector::is_na(lo[j]) ||
        NumericVector::is_na(cl[j]) || NumericVector::is_na(op[j]) ||
        lo[j] <= 0 || op[j] <= 0) continue;
    double lhl = std::log(hi[j]/lo[j]), lco = std::log(cl[j]/op[j]);
    s += 0.5 * lhl * lhl - (2.0*std::log(2.0)-1.0) * lco * lco;
    cnt++;
  }
  if (cnt >= 3) out[n-1] = std::sqrt(std::max(s / cnt, 0.0));
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(hi[old]) && !NumericVector::is_na(lo[old]) &&
        !NumericVector::is_na(cl[old]) && !NumericVector::is_na(op[old]) &&
        lo[old] > 0 && op[old] > 0) {
      double lhl = std::log(hi[old]/lo[old]), lco = std::log(cl[old]/op[old]);
      s -= 0.5*lhl*lhl - (2.0*std::log(2.0)-1.0)*lco*lco; cnt--;
    }
    if (!NumericVector::is_na(hi[i]) && !NumericVector::is_na(lo[i]) &&
        !NumericVector::is_na(cl[i]) && !NumericVector::is_na(op[i]) &&
        lo[i] > 0 && op[i] > 0) {
      double lhl = std::log(hi[i]/lo[i]), lco = std::log(cl[i]/op[i]);
      s += 0.5*lhl*lhl - (2.0*std::log(2.0)-1.0)*lco*lco; cnt++;
    }
    if (cnt >= 3) out[i] = std::sqrt(std::max(s / cnt, 0.0));
  }
  return out;
}

// ─── 21. EWMA Volatility (RiskMetrics λ=0.94) ─────────────────────────────
// [[Rcpp::export]]
NumericVector roll_ewma_vol_cpp(NumericVector ret, int n, double lambda) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  // Initialize with simple variance
  double s2 = 0.0; int cnt = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(ret[j])) { s2 += ret[j]*ret[j]; cnt++; }
  }
  if (cnt < 3) return out;
  double ewma = s2 / cnt;
  out[n-1] = std::sqrt(ewma);
  for (int i = n; i < m; i++) {
    if (!NumericVector::is_na(ret[i])) {
      ewma = lambda * ewma + (1.0 - lambda) * ret[i] * ret[i];
      out[i] = std::sqrt(ewma);
    }
  }
  return out;
}

// ─── 22. Proportion of negative returns ────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_neg_prop_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  int neg = 0, cnt = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(ret[j])) { if (ret[j] < 0) neg++; cnt++; }
  }
  if (cnt > 0) out[n-1] = (double)neg / cnt;
  for (int i = n; i < m; i++) {
    int old = i - n;
    if (!NumericVector::is_na(ret[old])) { if (ret[old] < 0) neg--; cnt--; }
    if (!NumericVector::is_na(ret[i])) { if (ret[i] < 0) neg++; cnt++; }
    if (cnt > 0) out[i] = (double)neg / cnt;
  }
  return out;
}

// ─── 23. Rolling Correlation ───────────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_corr_cpp(NumericVector x, NumericVector y, int n) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 5) return out;
  double sx=0,sy=0,sxy=0,sx2=0,sy2=0; int cnt=0;
  for (int j = 0; j < n; j++) {
    if (NumericVector::is_na(x[j]) || NumericVector::is_na(y[j])) continue;
    sx+=x[j]; sy+=y[j]; sxy+=x[j]*y[j]; sx2+=x[j]*x[j]; sy2+=y[j]*y[j]; cnt++;
  }
  auto compute = [&]() -> double {
    if (cnt < 5) return NA_REAL;
    double cn=(double)cnt;
    double vx=cn*sx2-sx*sx, vy=cn*sy2-sy*sy;
    if (vx<1e-20||vy<1e-20) return NA_REAL;
    return (cn*sxy-sx*sy)/std::sqrt(vx*vy);
  };
  out[n-1] = compute();
  for (int i = n; i < m; i++) {
    int old = i-n;
    if (!NumericVector::is_na(x[old])&&!NumericVector::is_na(y[old])) {
      sx-=x[old]; sy-=y[old]; sxy-=x[old]*y[old]; sx2-=x[old]*x[old]; sy2-=y[old]*y[old]; cnt--;
    }
    if (!NumericVector::is_na(x[i])&&!NumericVector::is_na(y[i])) {
      sx+=x[i]; sy+=y[i]; sxy+=x[i]*y[i]; sx2+=x[i]*x[i]; sy2+=y[i]*y[i]; cnt++;
    }
    out[i] = compute();
  }
  return out;
}

// ─── 24. Zero-count (zero volume/return days) ──────────────────────────────
// [[Rcpp::export]]
NumericVector roll_zero_count_cpp(NumericVector x, int n, double tol) {
  int m = x.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 1) return out;
  int zc = 0, cnt = 0;
  for (int j = 0; j < n; j++) {
    if (!NumericVector::is_na(x[j])) { if (std::abs(x[j]) <= tol) zc++; cnt++; }
  }
  if (cnt > 0) out[n-1] = (double)zc / cnt;
  for (int i = n; i < m; i++) {
    int old = i-n;
    if (!NumericVector::is_na(x[old])) { if (std::abs(x[old]) <= tol) zc--; cnt--; }
    if (!NumericVector::is_na(x[i])) { if (std::abs(x[i]) <= tol) zc++; cnt++; }
    if (cnt > 0) out[i] = (double)zc / cnt;
  }
  return out;
}

// ─── 25. Trend Strength (slope/R² of log price) ───────────────────────────
// [[Rcpp::export]]
NumericVector roll_trend_cpp(NumericVector cl, int n) {
  int m = cl.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 10) return out;
  for (int i = n-1; i < m; i++) {
    double sx=0,sy=0,sxy=0,sx2=0; int cnt=0;
    for (int j = i-n+1; j <= i; j++) {
      if (NumericVector::is_na(cl[j]) || cl[j] <= 0) continue;
      double t = (double)(j - (i-n+1));
      double lp = std::log(cl[j]);
      sx += t; sy += lp; sxy += t*lp; sx2 += t*t; cnt++;
    }
    if (cnt < 10) continue;
    double cn = (double)cnt;
    double den = cn*sx2 - sx*sx;
    if (std::abs(den) < 1e-12) continue;
    out[i] = (cn*sxy - sx*sy) / den * 252.0; // annualized slope
  }
  return out;
}

// ─── 26. NCSKEW (crash risk) ───────────────────────────────────────────────
// [[Rcpp::export]]
NumericVector roll_ncskew_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 10) return out;
  for (int i = n-1; i < m; i++) {
    double s1=0,s2=0,s3=0; int cnt=0;
    for (int j = i-n+1; j <= i; j++) {
      if (NumericVector::is_na(ret[j])) continue;
      s1+=ret[j]; s2+=ret[j]*ret[j]; s3+=ret[j]*ret[j]*ret[j]; cnt++;
    }
    if (cnt < 10) continue;
    double cn=(double)cnt, mu=s1/cn;
    double m2=s2/cn-mu*mu, m3=s3/cn-3*mu*(s2/cn)+2*mu*mu*mu;
    double sig3 = m2 * std::sqrt(m2);
    if (std::abs(sig3) < 1e-18) continue;
    out[i] = -(cn*(cn-1)*std::sqrt(cn-1)/((cn-1)*(cn-2))) * m3/sig3;
  }
  return out;
}

// ─── 27. DUVOL (down-to-up volatility ratio, crash risk) ───────────────────
// [[Rcpp::export]]
NumericVector roll_duvol_cpp(NumericVector ret, int n) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (m < n || n < 10) return out;
  for (int i = n-1; i < m; i++) {
    double mu=0; int cnt=0;
    for (int j = i-n+1; j <= i; j++) {
      if (!NumericVector::is_na(ret[j])) { mu+=ret[j]; cnt++; }
    }
    if (cnt < 10) continue;
    mu /= cnt;
    double sd2=0, su2=0; int nd=0, nu=0;
    for (int j = i-n+1; j <= i; j++) {
      if (NumericVector::is_na(ret[j])) continue;
      if (ret[j] < mu) { sd2 += (ret[j]-mu)*(ret[j]-mu); nd++; }
      else { su2 += (ret[j]-mu)*(ret[j]-mu); nu++; }
    }
    if (nd < 3 || nu < 3) continue;
    double dd = std::sqrt(sd2/nd), du = std::sqrt(su2/nu);
    if (du < 1e-12) continue;
    out[i] = std::log(dd/du);
  }
  return out;
}

// ─── 28. Expanding Tail Beta (PIT C1 수리 2026-09-24 · 판정서 1-4 · D08_Tail_Beta) ──────
// 구판(phase6:218-229)은 종목 전 이력의 sd(bm)·꼬리일로 계수 1개를 추정해 모든 날짜에 복제했다(C1).
// 누적판: t 의 값은 t 이하 행만으로 —
//   sd_t  = sd(bm[0..t], NA 제외, n-1 분모 = R sd())
//   꼬리  = { j ≤ t : ret_j·bm_j 모두 유효, |bm_j| > k_sd * sd_t }
//   출력  = -OLS 기울기(ret ~ bm | 꼬리). 꼬리 수 < min_tail · sd_t ≤ 1e-8(구판 가드) · 분모≈0 → NA.
// 정의 수치(k_sd·min_tail)는 호출부가 구판 값 그대로 넘긴다. 기존 함수는 건드리지 않는다(추가만).
// O(m log m): |bm| 정렬 슬롯 위 펜윅 트리(개수·Σx·Σy·Σxy·Σx²), 꼬리 = 전체 − (|bm| ≤ c 슬롯 접두합).
// [[Rcpp::export]]
NumericVector roll_expanding_tail_beta_cpp(NumericVector ret, NumericVector bm,
                                           double k_sd, int min_tail) {
  int m = ret.size();
  NumericVector out(m, NA_REAL);
  if (bm.size() != m) stop("roll_expanding_tail_beta_cpp: ret/bm 길이 불일치");
  std::vector<double> vals;
  vals.reserve(m);
  for (int i = 0; i < m; i++)
    if (!ISNAN(ret[i]) && !ISNAN(bm[i])) vals.push_back(std::fabs(bm[i]));
  std::sort(vals.begin(), vals.end());
  const int K = (int)vals.size();
  std::vector<double> fn(K + 1, 0.0), fx(K + 1, 0.0), fy(K + 1, 0.0), fxy(K + 1, 0.0), fx2(K + 1, 0.0);
  std::vector<int> next_off(K > 0 ? K : 1, 0);
  double tn = 0.0, tx = 0.0, ty = 0.0, txy = 0.0, tx2 = 0.0;
  long nb = 0; double mean_b = 0.0, m2_b = 0.0;
  for (int t = 0; t < m; t++) {
    if (!ISNAN(bm[t])) {
      nb++;
      double d = bm[t] - mean_b;
      mean_b += d / (double)nb;
      m2_b += d * (bm[t] - mean_b);
    }
    if (!ISNAN(ret[t]) && !ISNAN(bm[t])) {
      double a = std::fabs(bm[t]);
      int lb = (int)(std::lower_bound(vals.begin(), vals.end(), a) - vals.begin());
      int slot = lb + next_off[lb]++;
      double x = bm[t], y = ret[t];
      for (int k = slot + 1; k <= K; k += k & (-k)) {
        fn[k] += 1.0; fx[k] += x; fy[k] += y; fxy[k] += x * y; fx2[k] += x * x;
      }
      tn += 1.0; tx += x; ty += y; txy += x * y; tx2 += x * x;
    }
    if (nb < 2) continue;
    double sd = std::sqrt(m2_b / (double)(nb - 1));
    if (!(sd > 1e-8)) continue;
    double c = k_sd * sd;
    int p = (int)(std::upper_bound(vals.begin(), vals.end(), c) - vals.begin());
    double pn = 0.0, px = 0.0, py = 0.0, pxy = 0.0, px2 = 0.0;
    for (int k = p; k > 0; k -= k & (-k)) {
      pn += fn[k]; px += fx[k]; py += fy[k]; pxy += fxy[k]; px2 += fx2[k];
    }
    double n = tn - pn, sx = tx - px, sy = ty - py, sxy = txy - pxy, sx2 = tx2 - px2;
    if (n < (double)min_tail - 0.5) continue;
    double den = n * sx2 - sx * sx;
    if (std::abs(den) < 1e-12) continue;
    out[t] = -((n * sxy - sx * sy) / den);
  }
  return out;
}
