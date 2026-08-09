# ============================================================================
# test_register_module.R - contract regression for register_module()
# Target (read-only): 02_Infrastructure/contracts/register_module.R
# All writes are redirected to a tempdir() sandbox via PROJECT_ROOT +
# explicit catalog/quarantine paths - the real repo is never touched.
# Covered branches:
#   - FR input floor pass -> 04_Research/strategies/{id} + module_catalog
#   - floor violation (metric_type / missing provenance) -> quarantine path
#   - allow_quarantine=FALSE -> hard stop
#   - module_hash auto-compute: identical sim -> identical hash,
#     mutated sim -> different hash; explicit hash respected
#   - sim schema validation errors (missing DAILY_NAV_DT / bm_xts / <60 obs)
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })

## 자기 위치 해석 (2026-08-08 수리) — 구판은 `--file=` 만 봤다. 헌법은 `source(...)` 를 강제하는데
## 그 경로엔 `--file=` 이 없어 NA → "Execution halted" 로만 죽었다(원인 불가시).
.here <- local({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a) && !is.na(a[1]) && nzchar(a[1]))
    return(dirname(normalizePath(sub("^--file=", "", a[1]), winslash = "/", mustWork = FALSE)))
  for (r in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT")))
    if (nzchar(r) && dir.exists(file.path(r, "08_Tests", "contract_regression")))
      return(file.path(r, "08_Tests", "contract_regression"))
  if (file.exists(file.path(getwd(), "helpers.R"))) return(getwd())
  stop("자기 위치 해석 실패 — ★도구 경로 실패이지 계약 실패가 아닙니다.")
})
source(file.path(.here, "helpers.R"))
REAL_ROOT <- t_root()

SB <- t_sandbox("register_module")
dir.create(file.path(SB, "02_Infrastructure"), showWarnings = FALSE)
dir.create(file.path(SB, "04_Research"), showWarnings = FALSE)
PROJECT_ROOT <- SB   # .RM_ROOT() returns this; all writes stay in sandbox

source(file.path(REAL_ROOT, "02_Infrastructure/contracts/register_module.R"))

CATALOG <- file.path(SB, "06_Registry", "module_catalog.json")
QUAR    <- file.path(SB, "06_Registry", "module_quarantine.json")

mk_sim <- function(seed_shift = 0) {
  n <- 80L
  r <- rep(c(0.002, -0.001, 0.0015, 0.0005), 20) + seed_shift
  d <- seq(as.Date("2024-01-01"), by = "day", length.out = n)
  list(DAILY_NAV_DT = data.table(Date = d, NAV = cumprod(1 + r), Strategy_Ret = r),
       bm_xts = xts(rep(1e-4, n), order.by = d))
}
full_contract <- list(metric_type = "backtested", contract_pass = TRUE,
                      frozen = TRUE, source_contract_id = "SRC_TEST_001",
                      build_version = "test_build_v1",
                      cost_model_version = "v2.4_kr_retail_15bps")

reg <- function(id, sim = mk_sim(), ...) {
  args <- modifyList(full_contract, list(...))
  do.call(register_module,
          c(list(sim_result = sim, strategy_id = id, grade = "B",
                 origin_mode = "alpha_search",
                 catalog_path = CATALOG, quarantine_path = QUAR),
            args))
}

# --- RM01: floor pass -> FR-eligible catalog entry + strategies dir ----------
r1 <- reg("TST_OK_01", module_hash = "deadbeef01")
cat_obj <- fromJSON(CATALOG, simplifyVector = FALSE)
t_check("register:RM01_floor_pass_catalog",
        isTRUE(r1$fr_eligible) && identical(r1$quarantined, FALSE) &&
        file.exists(file.path(SB, "04_Research/strategies/TST_OK_01/sim_result.rds")) &&
        !is.null(cat_obj$modules[["TST_OK_01"]]) &&
        identical(cat_obj$modules[["TST_OK_01"]]$contract$eligibility_reason,
                  "FR_ELIGIBLE") &&
        identical(cat_obj$modules[["TST_OK_01"]]$module_hash, "deadbeef01"))

# --- RM02: metric_type proxy -> quarantine ------------------------------------
r2 <- reg("TST_QUAR_METRIC", metric_type = "proxy")
quar_obj <- fromJSON(QUAR, simplifyVector = FALSE)
cat_obj2 <- fromJSON(CATALOG, simplifyVector = FALSE)
t_check("register:RM02_proxy_metric_quarantined",
        isTRUE(r2$quarantined) && identical(r2$fr_eligible, FALSE) &&
        grepl("metric_type != backtested", r2$reason, fixed = TRUE) &&
        file.exists(file.path(SB, "stage_artifacts/module_quarantine/TST_QUAR_METRIC/sim_result.rds")) &&
        !is.null(quar_obj$modules[["TST_QUAR_METRIC"]]) &&
        is.null(cat_obj2$modules[["TST_QUAR_METRIC"]]))

# --- RM03: missing provenance field -> quarantine with named reason ----------
r3 <- reg("TST_QUAR_BUILD", build_version = NULL)
t_check("register:RM03_missing_build_version_quarantined",
        isTRUE(r3$quarantined) &&
        grepl("build_version missing", r3$reason, fixed = TRUE))

r3b <- reg("TST_QUAR_FROZEN", frozen = FALSE)
t_check("register:RM03b_not_frozen_quarantined",
        isTRUE(r3b$quarantined) &&
        grepl("frozen != TRUE", r3b$reason, fixed = TRUE))

# --- RM04: hash determinism ---------------------------------------------------
sim_a <- mk_sim()
h_expected <- local({
  tmp <- tempfile(fileext = ".rds"); on.exit(unlink(tmp))
  saveRDS(sim_a, tmp); unname(tools::md5sum(tmp))
})
r4a <- reg("TST_HASH_A", sim = sim_a)          # auto-computed hash
r4b <- reg("TST_HASH_B", sim = mk_sim())       # identical content
r4c <- reg("TST_HASH_C", sim = mk_sim(1e-6))   # mutated content
t_check("register:RM04_hash_match_identical_sim",
        identical(r4a$entry$module_hash, h_expected) &&
        identical(r4a$entry$module_hash, r4b$entry$module_hash))
t_check("register:RM04b_hash_mismatch_mutated_sim",
        !identical(r4a$entry$module_hash, r4c$entry$module_hash))

# --- RM05: sim schema validation hard stops -----------------------------------
err_of <- function(expr) tryCatch({ expr; "" }, error = function(e) conditionMessage(e))
sim_no_nav <- mk_sim(); sim_no_nav$DAILY_NAV_DT <- NULL
sim_no_bm  <- mk_sim(); sim_no_bm$bm_xts <- NULL
sim_short  <- mk_sim()
sim_short$DAILY_NAV_DT <- sim_short$DAILY_NAV_DT[1:50]
t_check("register:RM05_missing_nav_stops",
        grepl("DAILY_NAV_DT", err_of(reg("TST_ERR_1", sim = sim_no_nav)), fixed = TRUE))
t_check("register:RM05b_missing_bm_stops",
        grepl("bm_xts", err_of(reg("TST_ERR_2", sim = sim_no_bm)), fixed = TRUE))
t_check("register:RM05c_short_sample_stops",
        grepl("< 60", err_of(reg("TST_ERR_3", sim = sim_short)), fixed = TRUE))

# --- RM06: allow_quarantine = FALSE -> stop on floor fail ---------------------
t_check("register:RM06_no_quarantine_stops",
        grepl("FR input floor failed",
              err_of(reg("TST_ERR_4", metric_type = "proxy",
                         allow_quarantine = FALSE)), fixed = TRUE))

t_summary("test_register_module")
