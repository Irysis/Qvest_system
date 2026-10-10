// msm_fast_kernel.cpp — Calvet-Fisher binomial MSM Hamilton filter, Kronecker-factored (2026-10-10, L2 MC1 prep).
//
// WHY: production msm_update.R / MSM.R run the same filter with a dense 2^K x 2^K transition matrix
//   (K=10 -> 1024x1024, ~1e6 flops/step). Re-estimating the 4 parameters as-of each refit date (PIT C1 repair of
//   the full-sample 2026-01-18 fit) needs hundreds of likelihood evaluations per refit, so the dense kernel is too slow.
//   A = Q_1 (x) Q_2 (x) ... (x) Q_K (MSM.R compute_transition_matrix: A = kron(A, Q_k), Q_1 outermost)
//   => pi*A = apply each symmetric 2x2 Q_k along its own axis (component k <-> bit stride 2^(K-k)).
//   State value = sigma * sqrt(prod_k M_k), M in {m0, 2-m0} (compute_state_space: kron of {m0,2-m0}) -> depends on
//   popcount only. Same recursion, same 1e-10 likelihood floor, same crisis set {s > sigma} as the production kernel.
// Model ref: Calvet & Fisher (2004) J. Financial Econometrics 2(1) https://doi.org/10.1093/jjfinec/nbh003
// Equivalence to the dense production kernel is asserted numerically in build_msm_asof.R (positive control PC1).
#include <Rcpp.h>
#include <cmath>
#include <vector>
using namespace Rcpp;

// [[Rcpp::export]]
List msm_fast_filter(NumericVector returns, int k_bar, double m0, double sigma, double b, double gamma_1,
                     bool want_path) {
  const int T = returns.size();
  const int n = 1 << k_bar;
  std::vector<double> pi(n, 1.0 / n), g(k_bar);
  for (int k = 1; k <= k_bar; ++k) g[k - 1] = 1.0 - std::pow(1.0 - gamma_1, std::pow(b, k - 1));
  // popcount -> state vol (bit=0 -> m0, bit=1 -> 2-m0; order irrelevant for the value)
  std::vector<int> pc(n);
  for (int i = 0; i < n; ++i) { int c = 0, x = i; while (x) { c += x & 1; x >>= 1; } pc[i] = c; }
  std::vector<double> s_c(k_bar + 1);
  std::vector<int> crisis_c(k_bar + 1);
  for (int c = 0; c <= k_bar; ++c) {
    s_c[c] = sigma * std::sqrt(std::pow(m0, k_bar - c) * std::pow(2.0 - m0, c));
    crisis_c[c] = (s_c[c] > sigma) ? 1 : 0;
  }
  NumericVector cp(want_path ? T : 0), vol(want_path ? T : 0);
  std::vector<double> dens(k_bar + 1);
  const double inv_sqrt_2pi = 1.0 / std::sqrt(2.0 * M_PI);
  double ll = 0.0;
  for (int t = 0; t < T; ++t) {
    // predict: pi <- pi * (Q_1 (x) ... (x) Q_K); Q_k symmetric [[1-g/2, g/2],[g/2, 1-g/2]]
    for (int k = 1; k <= k_bar; ++k) {
      const int stride = 1 << (k_bar - k);
      const double stay = 1.0 - 0.5 * g[k - 1], move = 0.5 * g[k - 1];
      for (int base = 0; base < n; base += 2 * stride) {
        for (int i = base; i < base + stride; ++i) {
          const double p0 = pi[i], p1 = pi[i + stride];
          pi[i] = stay * p0 + move * p1;
          pi[i + stride] = move * p0 + stay * p1;
        }
      }
    }
    const double r = returns[t];
    for (int c = 0; c <= k_bar; ++c) dens[c] = (inv_sqrt_2pi / s_c[c]) * std::exp(-0.5 * (r / s_c[c]) * (r / s_c[c]));
    double sumlik = 0.0;
    for (int i = 0; i < n; ++i) { pi[i] *= dens[pc[i]]; sumlik += pi[i]; }
    if (sumlik < 1e-10) sumlik = 1e-10;                         // production floor (MSM.R / msm_update.R)
    double cpt = 0.0, vt = 0.0;
    for (int i = 0; i < n; ++i) {
      pi[i] /= sumlik;
      if (want_path) { if (crisis_c[pc[i]]) cpt += pi[i]; vt += pi[i] * s_c[pc[i]]; }
    }
    ll += std::log(sumlik);
    if (want_path) { cp[t] = cpt; vol[t] = vt; }
  }
  return List::create(Named("negloglik") = -ll, Named("crisis_prob") = cp, Named("vol") = vol);
}
