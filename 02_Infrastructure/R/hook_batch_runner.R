#==============================================================================
# hook_batch_runner.R -- Hook R logic batch wrapper (Block C token optimization)
#
# pipeline_trigger.sh / forge_code_guard.sh에서 개별 Rscript -e '...' 호출을
# 하나의 R source()로 통합. R 세션 재활용으로 spawn overhead 절감.
#
# 사용:
#   Rscript --no-save -e "source('02_Infrastructure/R/hook_batch_runner.R'); hook_determine_role(...)"
#   Rscript --no-save -e "source('02_Infrastructure/R/hook_batch_runner.R'); hook_pit_gate(...)"
#
# 제약 (Level 0):
#   - PIT C1~C15 검증 로직 0% 변경
#   - Axiom AX-000~AX-005 강제 로직 0% 변경
#   - Stage Gate 순서 강제 0% 변경
#==============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")
  library(jsonlite)
})

# ============================================================================
# 1. hook_determine_role(strategy_dir, s4_file)
#    pipeline_trigger.sh:120 -- S4 DONE 후 role 결정
#    반환: role 문자열 (core_alpha / defense / cash_allocation / ...)
# ============================================================================
hook_determine_role <- function(strategy_dir, s4_file) {
  tryCatch({
    suppressMessages({
      source("02_Infrastructure/config.R")
      source("02_Infrastructure/stage_gate_engine.R")
    })
    # S2 artifact
    s2_path <- list.files(strategy_dir, pattern = "s2_profile.*\\.json",
                          recursive = TRUE, full.names = TRUE)
    s2 <- if (length(s2_path) > 0) {
      tryCatch(fromJSON(s2_path[1], simplifyVector = FALSE), error = function(e) list())
    } else list()
    # S3 artifact
    s3_path <- list.files(strategy_dir, pattern = "s3_orthogonality.*\\.json",
                          recursive = TRUE, full.names = TRUE)
    s3 <- if (length(s3_path) > 0) {
      tryCatch(fromJSON(s3_path[1], simplifyVector = FALSE), error = function(e) list())
    } else list()
    # S4 artifact
    s4 <- tryCatch(fromJSON(s4_file, simplifyVector = FALSE), error = function(e) list())
    # sg_determine_role
    role <- tryCatch(sg_determine_role(s2, s3, s4), error = function(e) "core_alpha")
    role
  }, error = function(e) "core_alpha")
}

# ============================================================================
# 2. hook_pg2_distill_and_gap(strategy)
#    pipeline_trigger.sh:285 -- PG2 DONE 후 axiom partial distill + gap->Scout
# ============================================================================
hook_pg2_distill_and_gap <- function(strategy) {
  tryCatch({
    suppressMessages({
      source("02_Infrastructure/config.R")
      source("02_Infrastructure/axiom_memory_interface.R")
      source("02_Infrastructure/portfolio_governor.R")
    })

    # 1. Axiom partial distill
    sg_sync_methodology_memory()

    # 2. PG0 gap
    gap <- pg0_gap_review("V7_ALLWEATHER_001")

    # 3. Scout gap TODO (PG0->S0 feedback loop)
    scout_inbox <- file.path(PROJECT_ROOT, "qepm/mailbox/scout/inbox")
    existing <- list.files(scout_inbox, "TODO_S0_GAP_", full.names = TRUE)
    if (length(existing) == 0 && length(gap[["sleeve_needs"]]) > 0) {
      todo <- list(
        task_type  = "S0_gap_directed",
        sleeve_needs = gap[["sleeve_needs"]],
        gap        = gap[["gap"]],
        regime     = gap[["regime_state"]],
        instructions = sprintf(
          "PG2 gap: %s. CAGR %+.1f%%, SR %+.3f, MDD %+.1f%%. %s.",
          paste(gap[["sleeve_needs"]], collapse = "+"),
          gap[["gap"]][["cagr_gap"]] * 100,
          gap[["gap"]][["sharpe_gap"]],
          gap[["gap"]][["mdd_gap"]] * 100,
          gap[["regime_state"]][["category"]]
        ),
        created_at = as.character(Sys.time())
      )
      ts <- gsub("[- :]", "", as.character(Sys.time()))
      todo_path <- file.path(scout_inbox, sprintf("TODO_S0_GAP_%s.json", ts))
      write_json(todo, todo_path, auto_unbox = TRUE, pretty = TRUE)
      cat(sprintf("[Hook] PG2->S0: Scout TODO_S0_GAP (%s)\n",
                  paste(gap[["sleeve_needs"]], collapse = "+")))
    }
    cat(sprintf("[Axiom] Partial distill + gap for %s\n", strategy))
  }, error = function(e) {
    cat(sprintf("[Axiom] pg2_distill error: %s\n", e$message))
  })
}

# ============================================================================
# 3. hook_pg3_full_distill(strategy)
#    pipeline_trigger.sh:343 -- PG3/ARCHIVE DONE 후 full axiom distill
# ============================================================================
hook_pg3_full_distill <- function(strategy) {
  tryCatch({
    suppressMessages({
      source("02_Infrastructure/axiom_memory_interface.R")
    })
    sg_sync_methodology_memory()
    tryCatch({
      source("qepm/R/memory/r7_axiom.R")
      candidates <- scan_axiom_candidates()
      cat(sprintf("[Axiom] Full distill: %d candidates for %s\n",
                  length(candidates), strategy))
    }, error = function(e) {
      cat(sprintf("[Axiom] scan_axiom error: %s\n", e$message))
    })
  }, error = function(e) {
    cat(sprintf("[Axiom] pg3_distill error: %s\n", e$message))
  })
}

# ============================================================================
# 4. hook_pit_gate(strat_dir)
#    forge_code_guard.sh:397 -- PIT Engine v3 blocking gate
#    반환: PIT_RESULT|CLEAN/FAIL|severity|n_violations (stdout line protocol)
# ============================================================================
hook_pit_gate <- function(strat_dir) {
  tryCatch({
    options(warn = -1)
    suppressPackageStartupMessages(
      source("02_Infrastructure/validation/pit_engine_v3.R")
    )
    r <- pit_engine_v3$blocking_gate(strat_dir,
                                     levels = c("static", "ast"),
                                     verbose = FALSE)
    cat(sprintf("PIT_RESULT|%s|%s|%d\n",
                if (isTRUE(r$clean)) "CLEAN" else "FAIL",
                r$severity, length(r$violations)))
    if (!isTRUE(r$clean)) {
      for (v in r$violations[1:min(5, length(r$violations))]) {
        cat(sprintf("  - %s (line %s): %s\n",
                    v$code %||% "PIT",
                    v$line %||% "?",
                    substr(v$match %||% v$pattern %||% "?", 1, 80)))
      }
    }
  }, error = function(e) {
    cat(sprintf("PIT_RESULT|ERROR|critical|0\n"))
    cat(sprintf("  - error: %s\n", e$message))
  })
}

# ============================================================================
# 5. hook_academic_factcheck(s0_record_path, hyp_id)
#    academic_factcheck.sh -- S0 Compact Mode: DOI/author/year 추출 + 로컬 문헌
#    반환: JSON stdout (academic_factcheck_{H_ID}.json 내용)
#    NOTE: 현재 python3로 처리하므로 R 측은 placeholder.
#          향후 Factor DB 기반 cross-reference 확장 시 사용.
# ============================================================================
hook_academic_factcheck <- function(s0_record_path, hyp_id = "unknown") {
  tryCatch({
    if (!file.exists(s0_record_path)) {
      cat(sprintf('{"hypothesis_id":"%s","error":"s0_record not found"}\n', hyp_id))
      return(invisible(NULL))
    }
    d <- fromJSON(s0_record_path, simplifyVector = FALSE)
    core_ref <- d[["core_reference"]] %||% ""
    family   <- d[["economic_family"]] %||% d[["family"]] %||% ""

    result <- list(
      hypothesis_id           = hyp_id,
      core_reference_parsed   = nchar(core_ref) > 0,
      mechanism_family        = family,
      r_side_check            = "placeholder"
    )
    cat(toJSON(result, auto_unbox = TRUE, pretty = FALSE))
    cat("\n")
  }, error = function(e) {
    cat(sprintf('{"hypothesis_id":"%s","error":"%s"}\n', hyp_id, e$message))
  })
}

# ============================================================================
# 6. hook_quant_factcheck(factors_json, hyp_id, family)
#    quant_factcheck.sh -- S0 Compact Mode: Factor DB ICIR/IC sign 자동 조회
#    factors_json: JSON array string '["Q07","M08",...]'
#    반환: JSON stdout {factors, icir_10y, kr_ic_sign, factor_db_exists}
# ============================================================================
hook_quant_factcheck <- function(factors_json, hyp_id = "unknown", family = "") {
  tryCatch({
    factors <- tryCatch(fromJSON(factors_json), error = function(e) character(0))
    if (length(factors) == 0) {
      cat(sprintf('{"hypothesis_id":"%s","factors":[],"icir_10y":{},"kr_ic_sign":{},"factor_db_exists":{}}\n', hyp_id))
      return(invisible(NULL))
    }

    # Factor DB 존재 확인 + ICIR 계산
    icir_10y       <- list()
    kr_ic_sign     <- list()
    factor_db_ok   <- list()

    # load_month_factors() 경유 (C15 준수)
    tryCatch({
      suppressMessages(source("02_Infrastructure/config.R"))
      suppressMessages(source("02_Infrastructure/factor_db/load_month_factors.R"))

      for (fac in factors) {
        tryCatch({
          # Factor DB에서 해당 팩터 존재 확인
          dt <- load_month_factors(fac, start_date = "2015-01-01",
                                   end_date = "2025-12-31")
          if (!is.null(dt) && nrow(dt) > 0) {
            factor_db_ok[[fac]] <- TRUE

            # ICIR 계산: IC = rank correlation(factor, next_ret) by month
            if ("Z_Score_Aligned" %in% names(dt) && "Ret_1M" %in% names(dt)) {
              dt_complete <- dt[!is.na(Z_Score_Aligned) & !is.na(Ret_1M)]
              if (nrow(dt_complete) > 60) {
                ic_by_month <- dt_complete[, .(ic = cor(Z_Score_Aligned, Ret_1M,
                                                        method = "spearman",
                                                        use = "complete.obs")),
                                           by = .(Date)]
                ic_vec <- ic_by_month$ic[!is.na(ic_by_month$ic)]
                if (length(ic_vec) > 12) {
                  icir <- mean(ic_vec) / sd(ic_vec)
                  icir_10y[[fac]] <- round(icir, 4)
                  kr_ic_sign[[fac]] <- if (mean(ic_vec) > 0) "+" else "-"
                } else {
                  icir_10y[[fac]] <- NA
                  kr_ic_sign[[fac]] <- "?"
                }
              } else {
                icir_10y[[fac]] <- NA
                kr_ic_sign[[fac]] <- "?"
              }
            } else {
              icir_10y[[fac]] <- NA
              kr_ic_sign[[fac]] <- "?"
            }
          } else {
            factor_db_ok[[fac]] <- FALSE
            icir_10y[[fac]]     <- NA
            kr_ic_sign[[fac]]   <- "?"
          }
        }, error = function(e2) {
          factor_db_ok[[fac]] <<- FALSE
          icir_10y[[fac]]     <<- NA
          kr_ic_sign[[fac]]   <<- "?"
        })
      }
    }, error = function(e_load) {
      # load_month_factors 자체 실패 시 모든 팩터를 unknown 처리
      for (fac in factors) {
        factor_db_ok[[fac]] <<- FALSE
        icir_10y[[fac]]     <<- NA
        kr_ic_sign[[fac]]   <<- "?"
      }
    })

    # conditional_ic_matrix.csv 조회 (있으면)
    cic_path <- file.path(".", ".cache", "conditional_ic_matrix.csv")
    if (file.exists(cic_path)) {
      tryCatch({
        cic <- fread(cic_path)
        for (fac in factors) {
          if (fac %in% names(cic)) {
            # hit_rate = % of months with positive IC
            ic_col <- cic[[fac]]
            ic_col <- ic_col[!is.na(ic_col)]
            if (length(ic_col) > 0) {
              hit <- round(sum(ic_col > 0) / length(ic_col), 3)
              # Override sign from CIC if available
              kr_ic_sign[[fac]] <- if (mean(ic_col) > 0) "+" else "-"
            }
          }
        }
      }, error = function(e_cic) {
        # CIC 없어도 진행
      })
    }

    result <- list(
      hypothesis_id    = hyp_id,
      factors          = factors,
      icir_10y         = icir_10y,
      kr_ic_sign       = kr_ic_sign,
      factor_db_exists = factor_db_ok
    )
    cat(toJSON(result, auto_unbox = TRUE, pretty = FALSE, na = "null"))
    cat("\n")
  }, error = function(e) {
    cat(sprintf('{"hypothesis_id":"%s","error":"%s"}\n', hyp_id, e$message))
  })
}
