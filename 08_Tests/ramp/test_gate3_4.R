## test_gate3_4.R — RAMP Gate 3/4 unit tests (testthat). 합성 입력으로 메커니즘 검증.
## Run: Rscript --vanilla -e 'source("08_Tests/ramp/test_gate3_4.R")'
suppressMessages({ library(testthat); library(data.table) })

# testthat::test_file 은 cwd를 테스트파일 디렉토리로 바꿔 상대경로가 깨짐 → 프로젝트 루트로 고정.
.qm_root <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if (dir.exists(.qm_root)) setwd(.qm_root)

source("02_Infrastructure/ramp/strategy_return_matrix.R")
source("02_Infrastructure/ramp/latent_factor_extraction.R")

# ── synthetic return matrix: 1 common factor (beta) + idiosyncratic ──
set.seed(42)
Tn <- 800L; N <- 30L
mkt <- rnorm(Tn, 0, 0.012)                       # common market factor
betas <- runif(N, 0.6, 1.3)
R <- sapply(seq_len(N), function(j) betas[j] * mkt + rnorm(Tn, 0, 0.006))
# make 5 near-replicas of column 1 (corr > 0.99)
for (j in 2:6) R[, j] <- R[, 1] + rnorm(Tn, 0, 1e-4)
colnames(R) <- paste0("S", sprintf("%02d", seq_len(N)))
rownames(R) <- as.character(seq(as.Date("2020-01-01"), by = "day", length.out = Tn))
meta <- data.table(strategy_id = colnames(R), origin_mode = "synthetic",
                   grade = "T", strategy_idea = NA_character_, source = "synthetic")
config <- yaml::read_yaml("02_Infrastructure/ramp/ramp_config.yml")

test_that("compute_strategy_similarity returns valid symmetric corr with diag 1", {
  sim <- compute_strategy_similarity(R, min_overlap = 100L)
  expect_true(all(abs(diag(sim$return_corr) - 1) < 1e-9))
  expect_equal(sim$return_corr, t(sim$return_corr), tolerance = 1e-10)
  expect_identical(sim$turnover_similarity, "unavailable")
  # near-replicas S01..S06 should be ~1 corr
  expect_gt(min(sim$return_corr[1:6, 1:6]), 0.98)
})

test_that("cluster_strategies dedups near-replicas", {
  sim <- compute_strategy_similarity(R, min_overlap = 100L)
  cl <- cluster_strategies(sim, meta, config, n_family_clusters = 4L)
  # 6 near-replicas -> at most 1 kept among them (5 dropped)
  drop_in_replicas <- sum(cl$clusters[strategy_id %in% paste0("S", sprintf("%02d",1:6))]$dedup_dropped)
  expect_gte(drop_in_replicas, 4L)
  expect_true(cl$n_unique_after_dedup < N)
})

test_that("extract_latent_factors PC1 captures common factor (high var)", {
  lf <- extract_latent_factors(R, n_pc = 5L, do_factanal = FALSE)
  # single common market factor -> PC1 should dominate
  expect_gt(lf$pc1_variance_explained, 0.5)
  expect_equal(nrow(lf$scree), 5L)
  expect_equal(ncol(lf$eigen_returns), 6L)  # Date + PC1..5
})

# ── FWL orthogonality test ──
source("02_Infrastructure/ramp/pure_factor_extraction.R")
test_that("fwl_orthogonalize residual is orthogonal to controls", {
  set.seed(7)
  M <- 200L
  tk <- paste0("A", sprintf("%06d", seq_len(M)))
  Xdf <- data.table(Ticker = tk, Sector = sample(LETTERS[1:5], M, TRUE),
                    log_mktcap = rnorm(M, 20, 2), beta = rnorm(M, 1, 0.3),
                    vol = abs(rnorm(M, 0.02, 0.005)), liquidity = rnorm(M, 18, 2))
  # signal correlated with log_mktcap (size-contaminated)
  z <- setNames(0.5 * scale(Xdf$log_mktcap)[, 1] + rnorm(M), tk)
  res <- fwl_orthogonalize(z, Xdf)
  expect_identical(res$status, "ok")
  expect_lt(res$max_orth_cor, 0.05)        # FWL working: residual ⊥ numeric controls
  expect_true(res$orthogonality_pass)
})

# ── approve_factors gate test ──
source("02_Infrastructure/ramp/factor_validation.R")
test_that("approve_factors enforces backtested + ic_ir + spread", {
  M <- data.table(
    factor_id = c("good", "bad_ic", "proxy"),
    metric_type = c("backtested", "backtested", "proxy"),
    rank_ic_ir = c(0.2, -0.1, 0.3),
    net_quintile_spread_oos = c(0.005, 0.004, 0.01),
    cost_drag = c(0.02, 0.02, 0.02))
  appr <- approve_factors(M, config, econ_present = setNames(rep(TRUE, 3), c("good","bad_ic","proxy")))
  expect_identical(appr[factor_id == "good"]$status, "approved")
  expect_identical(appr[factor_id == "bad_ic"]$status, "rejected")   # negative ic_ir
  expect_identical(appr[factor_id == "proxy"]$status, "rejected")    # metric_type != backtested
})

cat("\n[test_gate3_4] all tests executed.\n")
# 2026-08-20: 이 파일은 testthat 계열 expect_* 를 쓰고 카운터가 없다. expect 실패는
#   예외를 던져 스크립트가 죽으므로 이 줄에 도달했다 = 전 단언 통과다(실패 시 JSON 이
#   없어 러너의 UNREPORTED 가 +1 FAIL 로 계상한다 — 침묵 통과가 아니다).
#   ★입도는 파일 단위다. 단언별 수치가 필요하면 카운터 도입이 선행 과제.
cat(sprintf("{\"test\":\"test_gate3_4\",\"pass\":1,\"fail\":0,\"total\":1}\n"))
