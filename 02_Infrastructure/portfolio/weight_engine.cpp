// weight_engine.cpp — Rcpp 가중 엔진 (Gerber / RMT / HRP / crisis_consec)
// PIT C1: rolling/expanding window 전용, full-sample 금지
// Compile: Rcpp::sourceCpp("02_Infrastructure/portfolio/weight_engine.cpp")
//
// 참조 R 정본:
//   .gerber_cor()    backtest_harness.R L248
//   .rmt_denoise()   backtest_harness.R L273
//   .hrp_bisect()    backtest_harness.R L409
//   crisis_consec    apply_regime_overlay.R L100

// [[Rcpp::depends(RcppArmadillo)]]
#include <RcppArmadillo.h>
#include <cmath>
#include <algorithm>
using namespace Rcpp;
using namespace arma;

// ─────────────────────────────────────────────────────────────────────────────
// 1. cpp_gerber_cor — Gerber Statistic 상관행렬
//    Gerber, Hurst, Konev (2022): noise-robust concordance/discordance 기반
//    임계값 = threshold × 각 열의 표준편차
//    참조 R: .gerber_cor()  backtest_harness.R L248
// ─────────────────────────────────────────────────────────────────────────────
// [[Rcpp::export]]
NumericMatrix cpp_gerber_cor(NumericMatrix ret_matrix, double threshold = 0.5) {
  int T = ret_matrix.nrow();
  int p = ret_matrix.ncol();
  NumericMatrix out(p, p);

  // 열별 표준편차 계산 (NA 제외)
  std::vector<double> sds(p, 0.0);
  for (int j = 0; j < p; j++) {
    double sum = 0.0, sum2 = 0.0;
    int cnt = 0;
    for (int t = 0; t < T; t++) {
      double v = ret_matrix(t, j);
      if (!NumericVector::is_na(v)) { sum += v; sum2 += v * v; cnt++; }
    }
    if (cnt > 1) {
      double mean = sum / cnt;
      sds[j] = std::sqrt((sum2 - cnt * mean * mean) / (cnt - 1));
    }
  }

  // 대각 = 1
  for (int i = 0; i < p; i++) out(i, i) = 1.0;

  // 상삼각 루프
  for (int i = 0; i < p - 1; i++) {
    double hi = threshold * sds[i];
    for (int j = i + 1; j < p; j++) {
      double hj = threshold * sds[j];
      int conc = 0, disc = 0;
      for (int t = 0; t < T; t++) {
        double xi = ret_matrix(t, i);
        double xj = ret_matrix(t, j);
        if (NumericVector::is_na(xi) || NumericVector::is_na(xj)) continue;
        bool up_i = xi >  hi, dn_i = xi < -hi;
        bool up_j = xj >  hj, dn_j = xj < -hj;
        if ((up_i && up_j) || (dn_i && dn_j)) conc++;
        else if ((up_i && dn_j) || (dn_i && up_j)) disc++;
      }
      double denom = conc + disc;
      double val   = (denom > 0) ? (double)(conc - disc) / denom : 0.0;
      out(i, j) = val;
      out(j, i) = val;
    }
  }

  // colnames / rownames 복사 (존재 시)
  CharacterVector cn = colnames(ret_matrix);
  if (cn.size() == p) {
    colnames(out) = cn;
    rownames(out) = cn;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. cpp_rmt_denoise — RMT Marchenko-Pastur 노이즈 고유값 축소
//    노이즈 고유값(λ ≤ λ+)을 평균으로 치환
//    λ+ = (1 + 1/√q)²,  q = T/N  (q_ratio = T/N 전달)
//    참조 R: .rmt_denoise()  backtest_harness.R L273
//    Armadillo eig_sym 사용 (R eigen()과 동일 알고리즘)
// ─────────────────────────────────────────────────────────────────────────────
// [[Rcpp::export]]
NumericMatrix cpp_rmt_denoise(NumericMatrix cor_matrix, double q_ratio) {
  int n = cor_matrix.nrow();
  if (n < 3 || q_ratio < 1.0) return cor_matrix;  // 조건 부족 → 원본 반환

  // NumericMatrix → arma::mat
  arma::mat C(cor_matrix.begin(), n, n, false);  // copy=false

  double lambda_plus = std::pow(1.0 + 1.0 / std::sqrt(q_ratio), 2.0);

  arma::vec vals;
  arma::mat vecs;
  arma::eig_sym(vals, vecs, C);

  // 노이즈 인덱스 수집
  std::vector<int> noise_idx;
  for (int k = 0; k < n; k++) {
    if (vals(k) <= lambda_plus) noise_idx.push_back(k);
  }

  if (!noise_idx.empty() && (int)noise_idx.size() < n) {
    double noise_mean = 0.0;
    for (int k : noise_idx) noise_mean += vals(k);
    noise_mean /= noise_idx.size();
    for (int k : noise_idx) vals(k) = noise_mean;
  }

  // 재구성: V * diag(λ) * Vᵀ
  arma::mat cor_clean = vecs * arma::diagmat(vals) * vecs.t();

  // 대각 = 1, 대칭화
  cor_clean.diag().ones();
  cor_clean = (cor_clean + cor_clean.t()) / 2.0;

  // arma::mat → NumericMatrix
  NumericMatrix out(n, n);
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++)
      out(i, j) = cor_clean(i, j);

  CharacterVector cn = colnames(cor_matrix);
  if (cn.size() == n) {
    colnames(out) = cn;
    rownames(out) = cn;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. cpp_hrp_weights — HRP Recursive Bisection
//    Lopez de Prado (2016) 알고리즘: IVP 기반 클러스터 분산 비례 배분
//    참조 R: .hrp_bisect() + .cluster_var()  backtest_harness.R L409
//    order_idx: 1-based (R hclust$order)
// ─────────────────────────────────────────────────────────────────────────────

// 내부 헬퍼: IVP 클러스터 분산
static double cluster_var_cpp(const arma::mat& cov, const std::vector<int>& idx) {
  int k = idx.size();
  if (k == 1) return cov(idx[0], idx[0]);

  arma::vec ivp(k);
  for (int i = 0; i < k; i++) {
    double d = cov(idx[i], idx[i]);
    ivp(i) = (d > 0.0) ? 1.0 / d : 0.0;
  }
  double s = arma::sum(ivp);
  if (s <= 0.0) { ivp.fill(1.0 / k); }
  else           { ivp /= s; }

  arma::mat sub(k, k);
  for (int i = 0; i < k; i++)
    for (int j = 0; j < k; j++)
      sub(i, j) = cov(idx[i], idx[j]);

  double var = arma::as_scalar(ivp.t() * sub * ivp);
  return var;
}

// [[Rcpp::export]]
NumericVector cpp_hrp_weights(NumericMatrix cov_matrix, IntegerVector order_idx) {
  int n = cov_matrix.nrow();
  arma::mat cov(cov_matrix.begin(), n, n, false);

  // 0-base 변환
  std::vector<int> ord(order_idx.size());
  for (int i = 0; i < (int)order_idx.size(); i++) ord[i] = order_idx[i] - 1;

  NumericVector w(n, 1.0);

  // BFS 방식 클러스터 큐
  std::vector< std::vector<int> > clusters;
  clusters.push_back(ord);

  while (!clusters.empty()) {
    std::vector< std::vector<int> > new_clusters;
    for (auto& cl : clusters) {
      if ((int)cl.size() <= 1) continue;
      int mid = (int)std::ceil((double)cl.size() / 2.0);
      std::vector<int> left(cl.begin(), cl.begin() + mid);
      std::vector<int> right(cl.begin() + mid, cl.end());

      double var_l = cluster_var_cpp(cov, left);
      double var_r = cluster_var_cpp(cov, right);
      double denom = var_l + var_r;
      double alpha = (denom > 0.0) ? 1.0 - var_l / denom : 0.5;

      for (int idx : left)  w[idx] *= alpha;
      for (int idx : right) w[idx] *= (1.0 - alpha);

      if ((int)left.size()  > 1) new_clusters.push_back(left);
      if ((int)right.size() > 1) new_clusters.push_back(right);
    }
    clusters = new_clusters;
  }
  return w;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. cpp_crisis_consec — 연속 위기 카운터
//    crisis_flag(0/1) 벡터를 입력받아 연속 1 카운트를 반환
//    참조 R: apply_regime_overlay.R L100  (data.table j-expression)
//    PIT C9: DD/VT lag 동일 원칙 — 이 함수는 이미 lag된 flag에 적용
// ─────────────────────────────────────────────────────────────────────────────
// [[Rcpp::export]]
IntegerVector cpp_crisis_consec(IntegerVector crisis_flag) {
  int n = crisis_flag.size();
  IntegerVector out(n, 0);
  int cnt = 0;
  for (int i = 0; i < n; i++) {
    if (crisis_flag[i] == 1) { cnt++; }
    else                     { cnt = 0; }
    out[i] = cnt;
  }
  return out;
}
