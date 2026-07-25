#==============================================================================
# test_cert_rules.R — Phase 8 dry-run test
# cr_check_eligibility behavior 검증 (positive/negative fixtures).
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

#──────────────────────────────────────────────────────────────────────────────
# PROJECT_ROOT 해석 (2026-07-25 수리)
#
# 구: CLAUDE_PROJECT_DIR 미설정 시 하드코딩 WSL 경로 "/mnt/c/Users/User/..." 폴백.
#     이 머신엔 없는 경로라 source() 가 즉시 죽어 `Execution halted`(assertion 0건)
#     — 러너가 env 를 넘겨줄 때만 우연히 살아 있던 구조였다.
#     (integration/*.R 하드코딩 PROJ 수리 f18f6c90 과 같은 계열)
#
# 신: 후보를 순회하되 **존재검사가 아니라 표지(marker) 검증**으로 정체를 확인한다.
#     dir.exists() 만으로 루트를 신뢰하다 직렬화가 무력화된 tg_lock 사고와 같은
#     기전을 피한다 — "있다"가 "그것이다"를 뜻하지 않는다.
#     전부 실패하면 조용한 폴백 대신 진단 가능한 stop().
#──────────────────────────────────────────────────────────────────────────────
.MARKER <- "02_Infrastructure/worktask/cert_rules.R"   # 이 테스트가 실제로 소비하는 파일

.is_proj_root <- function(p) {
  nzchar(p) && dir.exists(p) && file.exists(file.path(p, .MARKER))
}

# Rscript 호출 시 --file= 인자에서 자기 위치를 얻는다(없으면 "").
# 경로 정규화 함수는 한글 경로에서 불안정해 쓰지 않는다 (python-policy §2 정합).
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return("")
  dirname(sub("^--file=", "", m[1L]))
}

.sd <- .script_dir()
.CANDIDATES <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
  Sys.getenv("QM_ROOT",            unset = ""),
  if (nzchar(.sd)) file.path(.sd, "..", "..") else "",  # 08_Tests/hooks → root
  getwd(),
  file.path(getwd(), "..", "..")
)

PROJ_ROOT <- ""
for (.c in .CANDIDATES) {
  if (.is_proj_root(.c)) { PROJ_ROOT <- .c; break }
}
if (!nzchar(PROJ_ROOT)) {
  stop(sprintf(paste0(
    "[test_cert_rules] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보가 없음.\n",
    "  시도한 후보: %s\n",
    "  cwd=%s / CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s'"),
    .MARKER,
    paste(sprintf("'%s'", .CANDIDATES[nzchar(.CANDIDATES)]), collapse = ", "),
    getwd(),
    Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
    Sys.getenv("QM_ROOT", unset = "")))
}

source(file.path(PROJ_ROOT, .MARKER))

PASS <- 0
FAIL <- 0
results <- character()

check <- function(name, expect, actual) {
  if (identical(expect, actual)) {
    PASS <<- PASS + 1
    results <<- c(results, sprintf("PASS: %s", name))
  } else {
    FAIL <<- FAIL + 1
    results <<- c(results, sprintf("FAIL: %s (expected=%s actual=%s)",
                                    name, expect, actual))
  }
}

TEST_DIR <- tempfile(pattern = "cert_test_")
dir.create(TEST_DIR, recursive = TRUE)
on.exit(unlink(TEST_DIR, recursive = TRUE))

# ─── Positive fixture: alpha_discovery eligible ───
alpha_pos <- list(
  task_id = "WT-D20260601_001",
  hypothesis_summary = paste(rep("Lorem ipsum dolor sit amet", 5), collapse = " "),
  factor_specs = list(
    list(factor_id = "X1", economic_rationale = "test rationale"),
    list(factor_id = "X2", economic_rationale = "another")
  ),
  diagnostics = list(
    alpha_inheritance_cor = 0.42,
    harvey_t_specs_pass_count = 4
  )
)
alpha_pos_path <- file.path(TEST_DIR, "alpha_pos.json")
write_json(alpha_pos, alpha_pos_path, auto_unbox = TRUE, pretty = TRUE)

res1 <- cr_check_eligibility("alpha_discovery", alpha_pos_path)
check("alpha_discovery_positive", TRUE, res1$eligible)

# ─── Negative fixture: alpha_discovery cor >= 0.95 ───
alpha_neg <- alpha_pos
alpha_neg$diagnostics$alpha_inheritance_cor <- 0.97
alpha_neg_path <- file.path(TEST_DIR, "alpha_neg_cor.json")
write_json(alpha_neg, alpha_neg_path, auto_unbox = TRUE, pretty = TRUE)

res2 <- cr_check_eligibility("alpha_discovery", alpha_neg_path)
check("alpha_discovery_cor_95_negative", FALSE, res2$eligible)

# ─── Negative fixture: alpha_discovery harvey_t < 3 ───
alpha_ht <- alpha_pos
alpha_ht$diagnostics$harvey_t_specs_pass_count <- 1
alpha_ht_path <- file.path(TEST_DIR, "alpha_neg_ht.json")
write_json(alpha_ht, alpha_ht_path, auto_unbox = TRUE, pretty = TRUE)

res3 <- cr_check_eligibility("alpha_discovery", alpha_ht_path)
check("alpha_discovery_harvey_t_negative", FALSE, res3$eligible)

# ─── Positive fixture: sr_provenance ───
sr_pos <- list(
  task_id = "WT-D20260601_001",
  sr_realized_share_based = 1.5,
  measurement_basis_primary = "forge_realized_share_based",
  weights_csv_unique_dates_count = 100L,
  schedule_density_ratio = 1.0
)
sr_pos_path <- file.path(TEST_DIR, "sr_pos.json")
write_json(sr_pos, sr_pos_path, auto_unbox = TRUE, pretty = TRUE)

res4 <- cr_check_eligibility("sr_provenance", sr_pos_path)
check("sr_provenance_positive", TRUE, res4$eligible)

# ─── Negative fixture: sr_provenance basis wrong ───
sr_neg <- sr_pos
sr_neg$measurement_basis_primary <- "estimated"
sr_neg_path <- file.path(TEST_DIR, "sr_neg.json")
write_json(sr_neg, sr_neg_path, auto_unbox = TRUE, pretty = TRUE)

res5 <- cr_check_eligibility("sr_provenance", sr_neg_path)
check("sr_provenance_basis_negative", FALSE, res5$eligible)

# ─── Positive fixture: forge_package_validated 8-field ───
forge_pos <- list(
  task_id = "WT-D20260601_001",
  backtest_summary = list(sr = 1.5),
  sr_realized_share_based = 1.5,
  measurement_basis_primary = "forge_realized_share_based",
  weights_csv_unique_dates_count = 100L,
  alpha_sig_dates_count = 100L,
  schedule_density_ratio = 1.0,
  schedule_density_pass = TRUE,
  pure_function_violation = "none"
)
forge_pos_path <- file.path(TEST_DIR, "forge_pos.json")
write_json(forge_pos, forge_pos_path, auto_unbox = TRUE, pretty = TRUE)

res6 <- cr_check_eligibility("forge_package_validated", forge_pos_path)
check("forge_package_validated_positive", TRUE, res6$eligible)

# ─── Negative fixture: forge_package missing field ───
forge_neg <- forge_pos
forge_neg$alpha_sig_dates_count <- NULL
forge_neg_path <- file.path(TEST_DIR, "forge_neg.json")
write_json(forge_neg, forge_neg_path, auto_unbox = TRUE, pretty = TRUE)

res7 <- cr_check_eligibility("forge_package_validated", forge_neg_path)
check("forge_package_validated_missing_field_negative", FALSE, res7$eligible)

# ─── Role Card test ───
discovery_card <- cr_get_role_card("discovery")
check("role_card_discovery_own_4", 4L, length(discovery_card$own))

deployment_card <- cr_get_role_card("deployment")
check("role_card_deployment_inherit_1", 1L, length(deployment_card$inherit))

# Summary
cat("=== test_cert_rules.R ===\n")
for (r in results) cat(sprintf("  %s\n", r))
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))

# JSON output
cat(toJSON(list(
  test = "cert_rules",
  pass = PASS,
  fail = FAIL,
  total = PASS + FAIL
), auto_unbox = TRUE), "\n")

quit(save = "no", status = FAIL)
