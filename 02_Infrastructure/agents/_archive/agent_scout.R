#==============================================================================
# Scout Agent — Hypothesis Generator for Perpetual Research Engine
#
# Role: Mailbox polling + Paper search + Hypothesis generation
# IPC: agent_mailbox.R (qepm/R/orchestration/agent_mailbox.R)
# PIT: lookahead_detector.R (02_Infrastructure/lookahead_detector.R)
#
# Commands:
#   "generate_hypotheses" — full hypothesis pipeline (papers + axioms + families)
#   "search_only"         — paper search only (returns ideas)
#   "status"              — report agent health
#
# Usage:
#   cd "$PROJECT_ROOT" && Rscript -e 'source("02_Infrastructure/agent_scout.R")'
#==============================================================================

cat("=== Scout Agent: Initializing ===\n")

# --- Resolve project root (Korean path safe) ---
.scout_root <- tryCatch(
  dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) {
    candidates <- c(
      "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
      Sys.getenv("QM_ROOT", unset = "")
    )
    found <- candidates[nchar(candidates) > 0 & sapply(candidates, dir.exists)]
    if (length(found) == 0) stop("[Scout] Cannot resolve PROJECT_ROOT")
    found[1]
  }
)

# --- Source infrastructure ---
tryCatch({
  source(file.path(.scout_root, "02_Infrastructure", "config.R"))
}, error = function(e) {
  cat("[Scout] config.R load failed:", conditionMessage(e), "\n")
  PROJECT_ROOT <<- .scout_root
})

MAILBOX_PATH <- file.path(.scout_root, "qepm", "R", "orchestration", "agent_mailbox.R")
if (!file.exists(MAILBOX_PATH)) stop("[Scout] agent_mailbox.R not found: ", MAILBOX_PATH)
source(MAILBOX_PATH)

LOOKAHEAD_PATH <- file.path(.scout_root, "02_Infrastructure", "validation", "lookahead_detector.R")
if (file.exists(LOOKAHEAD_PATH)) source(LOOKAHEAD_PATH)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

cat(sprintf("[Scout] PROJECT_ROOT: %s\n", .scout_root))

.scout_start_time <- Sys.time()

#==============================================================================
# CONSTANTS
#==============================================================================

AGENT_NAME <- "scout"
POLL_INTERVAL <- 15  # seconds

# Bucket distribution targets (Lawbook Ch.13)
BUCKET_TARGETS <- list(
  exploit   = 0.35,
  stabilize = 0.30,
  explore   = 0.20,
  diagnose  = 0.15
)

# --- Non-traditional keyword pool (50+ keywords) ---
RANDOM_KEYWORD_POOL <- c(
  # Behavioral finance
  "behavioral finance anomaly", "disposition effect factor",
  "investor attention bias", "lottery stock anomaly",
  "overconfidence trading", "herding behavior stock market",
  "anchoring bias equity", "prospect theory portfolio",
  "mental accounting investment", "loss aversion premium",
  # Market microstructure
  "market microstructure Korea", "order flow imbalance factor",
  "bid-ask spread premium", "price impact trading cost",
  "high frequency trading alpha", "market maker inventory",
  "informed trading probability", "tick size regime change",
  # Network / information
  "network centrality stock return", "supply chain network alpha",
  "information entropy portfolio", "patent citation factor",
  "customer concentration risk", "geographic momentum spillover",
  "industry linkage return prediction", "corporate governance network",
  # Alternative data
  "alternative data factor", "satellite data economic activity",
  "web traffic stock prediction", "social media sentiment Korea",
  "Google trends factor", "NLP earnings call sentiment",
  "news sentiment factor model", "ESG factor Korea",
  # Quantitative / mathematical
  "fractal dimension volatility", "realized skewness factor",
  "idiosyncratic skewness premium", "co-skewness risk premium",
  "higher moment risk premium", "jump risk factor equity",
  "variance risk premium portfolio", "option implied skewness factor",
  # Macro / cross-asset
  "cross-asset momentum spillover", "commodity currency equity link",
  "sovereign CDS equity transmission", "FX carry trade equity factor",
  "credit default swap equity signal", "carbon risk premium equity",
  "political connection premium", "military spending factor",
  # Korean market specific
  "Korean equity factor", "KOSPI anomaly seasonal",
  "margin trading factor Korea", "retail investor herding Korea",
  "foreign investor flow Korea", "institutional ownership factor Korea",
  # Machine learning
  "machine learning feature selection factor", "deep learning stock prediction",
  "reinforcement learning portfolio optimization", "ensemble method equity factor",
  "autoencoder anomaly detection market", "transformer stock prediction",
  # Misc
  "tail risk premium equity", "earnings announcement drift",
  "post-IPO performance anomaly", "insider trading signal factor",
  "short interest factor premium", "weather anomaly stock return",
  "demographic shift portfolio", "liquidity commonality factor",
  "funding liquidity premium equity", "idiosyncratic volatility puzzle"
)

#==============================================================================
# PAPER SEARCH FUNCTIONS
#==============================================================================

#' Search papers via arxiv_collector.py (system2 call)
#'
#' @param keywords Character vector of search keywords
#' @param max_results Maximum papers per query
#' @return list(papers, ideas)
search_papers <- function(keywords, max_results = 3) {
  query <- paste(c(keywords, "factor portfolio equity"), collapse = " ")
  collector_path <- file.path(.scout_root, "02_Infrastructure", "arxiv_collector.py")

  papers <- list()
  ideas  <- list()

  if (!file.exists(collector_path)) {
    cat("[Scout] arxiv_collector.py not found, using keyword-based hypothesis only\n")
    # Fallback: generate ideas from keywords directly
    for (kw in keywords) {
      ideas[[length(ideas) + 1]] <- list(
        source     = "keyword_derived",
        keyword    = kw,
        mechanism  = sprintf("Explore %s as factor in Korean equity market", kw),
        relevance  = "medium"
      )
    }
    return(list(papers = papers, ideas = ideas))
  }

  # Call Python arxiv search
  raw <- tryCatch({
    system2("python3",
      args = c(
        shQuote(collector_path),
        "--query", shQuote(query),
        "--max", as.character(max_results)
      ),
      stdout = TRUE,
      stderr = FALSE,
      timeout = 120
    )
  }, error = function(e) {
    cat("[Scout] arxiv search failed:", conditionMessage(e), "\n")
    character(0)
  })

  # Parse output (JSON lines or plain text)
  if (length(raw) > 0) {
    papers <- parse_arxiv_results(raw)
    ideas  <- extract_ideas_from_papers(papers)
  }

  # Keyword-based fallback if no papers found
  if (length(ideas) == 0) {
    for (kw in keywords) {
      ideas[[length(ideas) + 1]] <- list(
        source    = "keyword_derived",
        keyword   = kw,
        mechanism = sprintf("Investigate %s as potential alpha source", kw),
        relevance = "medium"
      )
    }
  }

  list(papers = papers, ideas = ideas)
}

#' Parse raw arxiv output into structured paper list
#'
#' @param raw_output Character vector from system2 stdout
#' @return List of paper objects
parse_arxiv_results <- function(raw_output) {
  papers <- list()

  # Try JSON parsing first
  json_text <- paste(raw_output, collapse = "\n")
  parsed <- tryCatch(
    fromJSON(json_text, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (!is.null(parsed) && is.list(parsed)) {
    if (!is.null(parsed$papers)) parsed <- parsed$papers
    for (p in parsed) {
      papers[[length(papers) + 1]] <- list(
        title    = p$title %||% "Unknown",
        abstract = p$abstract %||% p$summary %||% p$note %||% "",
        year     = p$year %||% p$published %||% "",
        authors  = p$authors %||% "",
        arxiv_id = p$arxiv_id %||% p$source %||% ""
      )
    }
    return(papers)
  }

  # Fallback: line-by-line parsing
  current <- list()
  for (line in raw_output) {
    line <- trimws(line)
    if (nchar(line) == 0) next
    if (grepl("^Title:", line, ignore.case = TRUE)) {
      if (length(current) > 0 && !is.null(current$title)) {
        papers[[length(papers) + 1]] <- current
      }
      current <- list(title = sub("^Title:\\s*", "", line, ignore.case = TRUE))
    } else if (grepl("^Abstract:", line, ignore.case = TRUE)) {
      current$abstract <- sub("^Abstract:\\s*", "", line, ignore.case = TRUE)
    } else if (grepl("^Year:", line, ignore.case = TRUE)) {
      current$year <- sub("^Year:\\s*", "", line, ignore.case = TRUE)
    } else if (grepl("^Authors?:", line, ignore.case = TRUE)) {
      current$authors <- sub("^Authors?:\\s*", "", line, ignore.case = TRUE)
    }
  }
  if (length(current) > 0 && !is.null(current$title)) {
    papers[[length(papers) + 1]] <- current
  }

  papers
}

#' Extract factor ideas from paper abstracts
#'
#' @param papers List of paper objects
#' @return List of idea objects
extract_ideas_from_papers <- function(papers) {
  ideas <- list()

  factor_keywords <- c(
    "anomaly", "premium", "factor", "alpha", "predictability",
    "mispricing", "return prediction", "cross-section", "outperform",
    "risk-adjusted", "excess return", "information ratio"
  )

  for (p in papers) {
    abstract_lower <- tolower(p$abstract %||% "")
    title_lower    <- tolower(p$title %||% "")
    combined       <- paste(title_lower, abstract_lower)

    # Score relevance by keyword hits
    hits <- sum(sapply(factor_keywords, function(kw) grepl(kw, combined)))
    relevance <- if (hits >= 3) "high" else if (hits >= 1) "medium" else "low"

    if (relevance != "low") {
      mechanism <- extract_mechanism(combined)
      ideas[[length(ideas) + 1]] <- list(
        source    = paste0("arxiv:", p$arxiv_id %||% "unknown"),
        title     = p$title %||% "Unknown",
        mechanism = mechanism,
        relevance = relevance,
        year      = p$year %||% ""
      )
    }
  }

  ideas
}

#' Extract core mechanism from paper text
#'
#' @param text Combined title + abstract (lowercase)
#' @return Character string describing the mechanism
extract_mechanism <- function(text) {
  # Look for causal patterns
  patterns <- c(
    "we (find|show|demonstrate|document) that ([^.]+)",
    "our results (suggest|indicate|show) ([^.]+)",
    "(predicts?|forecasts?) (future )?returns? ([^.]+)",
    "generates? (significant |abnormal )?(alpha|returns?) ([^.]+)"
  )

  for (pat in patterns) {
    m <- regmatches(text, regexpr(pat, text, perl = TRUE))
    if (length(m) > 0 && nchar(m[1]) > 10) {
      return(substr(m[1], 1, 200))
    }
  }

  # Fallback: first sentence
  first_sentence <- sub("^([^.]+\\.).*", "\\1", text)
  substr(first_sentence, 1, 200)
}

#' Convert a paper idea to a formal hypothesis
#'
#' @param idea Idea object from extract_ideas
#' @return Hypothesis list with experiment contract, or NULL
paper_to_hypothesis <- function(idea) {
  if (is.null(idea) || is.null(idea$mechanism)) return(NULL)

  # Construct hypothesis
  h <- list(
    objective   = sprintf("Test: %s", substr(idea$mechanism, 1, 100)),
    family      = "paper_derived",
    type        = "empirical_test",
    source      = idea$source %||% "unknown",
    description = idea$mechanism,
    bucket      = "explore",
    contract    = make_experiment_contract(
      exp_id      = paste0("SCOUT_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
                            sprintf("%03d", sample(1:999, 1))),
      family      = "paper_derived",
      hypothesis  = idea$mechanism,
      source_ref  = idea$source %||% "unknown"
    )
  )

  h
}

#==============================================================================
# KEYWORD DERIVATION
#==============================================================================

#' Derive search keywords from axioms, families, lessons
#'
#' @param axioms List of axiom objects
#' @param families List of family objects
#' @param lessons List of recent lesson strings
#' @return Character vector of search keywords
derive_search_keywords <- function(axioms = list(), families = list(),
                                    lessons = list()) {
  keywords <- character(0)

  # From axioms: extract family/mechanism names
  for (ax in axioms) {
    fam <- ax$family %||% ""
    if (nchar(fam) > 0) {
      keywords <- c(keywords, gsub("_", " ", fam))
    }
    # If axiom mentions a specific mechanism
    desc <- ax$description %||% ax$objective %||% ""
    if (nchar(desc) > 0) {
      # Extract key nouns (simple heuristic)
      words <- strsplit(tolower(desc), "\\s+")[[1]]
      informative <- words[nchar(words) >= 5 & !words %in%
        c("about", "should", "could", "would", "which", "where", "there",
          "these", "those", "after", "before", "between", "through")]
      if (length(informative) > 0) {
        keywords <- c(keywords, paste(informative[1:min(3, length(informative))],
                                       collapse = " "))
      }
    }
  }

  # From families: focus on low-trial or promising families
  for (fam in families) {
    name <- fam$name %||% names(families)[which(sapply(families, identical, fam))]
    if (is.character(name) && length(name) > 0 && nchar(name[1]) > 0) {
      tc <- fam$trial_count %||% 0
      fs <- fam$fail_streak %||% 0
      if (tc < 5 && fs < 3) {
        keywords <- c(keywords, gsub("_", " ", name[1]))
      }
    }
  }

  # From lessons: extract direction hints
  for (l in lessons) {
    l_text <- if (is.character(l)) l else (l$text %||% l$description %||% "")
    if (nchar(l_text) > 0) {
      # Look for "try X" or "explore Y" patterns
      m <- regmatches(l_text, regexpr("(try|explore|investigate|test)\\s+([^,;.]+)",
                                       l_text, ignore.case = TRUE, perl = TRUE))
      if (length(m) > 0) {
        keywords <- c(keywords, sub("^(try|explore|investigate|test)\\s+", "", m[1],
                                     ignore.case = TRUE))
      }
    }
  }

  # Deduplicate + limit
  keywords <- unique(keywords)
  if (length(keywords) == 0) keywords <- sample(RANDOM_KEYWORD_POOL, 3)
  if (length(keywords) > 5) keywords <- keywords[1:5]

  keywords
}

#==============================================================================
# HYPOTHESIS DESIGN HELPERS
#==============================================================================

#' Design an axiom-based hypothesis test
#'
#' @param axiom Axiom object with fields: family, description, n_passing_axes, failing_axes
#' @return Hypothesis list or NULL
design_axiom_test <- function(axiom) {
  if (is.null(axiom)) return(NULL)

  fam     <- axiom$family %||% "general"
  desc    <- axiom$description %||% axiom$objective %||% ""
  failing <- axiom$axiom_readiness$failing_axes %||%
             axiom$failing_axes %||% character(0)

  # Design test targeting the weakest axis
  if (length(failing) > 0) {
    target_axis <- failing[1]
    test_type <- switch(target_axis,
      "falsification" = "adverse_condition",
      "independence"  = "orthogonalization",
      "mechanism"     = "causal_isolation",
      "scope"         = "universe_expansion",
      "stability"     = "temporal_robustness",
      "parameter_variation"
    )

    h <- list(
      objective   = sprintf("Axiom test [%s] for %s: %s", target_axis, fam, desc),
      family      = fam,
      type        = paste0("axiom_", test_type),
      description = sprintf("Test %s axis for family '%s': %s", target_axis, fam,
                             substr(desc, 1, 150)),
      bucket      = "exploit",
      contract    = make_experiment_contract(
        exp_id     = paste0("AX_", format(Sys.time(), "%Y%m%d_%H%M%S")),
        family     = fam,
        hypothesis = sprintf("Axiom %s for %s can pass %s axis", desc, fam, target_axis),
        source_ref = sprintf("axiom:%s", fam)
      )
    )
    return(h)
  }

  NULL
}

#' Design a family extension hypothesis
#'
#' @param fam Family object (from families.json)
#' @param lessons Recent lessons
#' @return Hypothesis list or NULL
design_family_extension <- function(fam, lessons = list()) {
  if (is.null(fam)) return(NULL)

  fam_name <- fam$name %||% "unknown"
  tc       <- fam$trial_count %||% 0
  pc       <- fam$pass_count %||% 0
  ga       <- fam$grade_a_count %||% 0
  fs       <- fam$fail_streak %||% 0

  # Skip cooled down families
  if (identical(fam$status, "COOL_DOWN") || fs >= 3) return(NULL)

  # Identify extension direction
  direction <- if (ga > 0) {
    "Optimize best variant: tune parameters or combine with complementary sleeve"
  } else if (pc > 0) {
    "Strengthen passing variant: improve robustness or add regime conditioning"
  } else {
    "Variant exploration: try different signal construction or weighting"
  }

  h <- list(
    objective   = sprintf("Family extension [%s]: %s (trials=%d, GA=%d)",
                           fam_name, direction, tc, ga),
    family      = fam_name,
    type        = "family_extension",
    description = direction,
    bucket      = "stabilize",
    contract    = make_experiment_contract(
      exp_id     = paste0("FEXT_", format(Sys.time(), "%Y%m%d_%H%M%S")),
      family     = fam_name,
      hypothesis = sprintf("Extending %s (%d trials) via: %s", fam_name, tc, direction),
      source_ref = sprintf("family:%s", fam_name)
    )
  )

  h
}

#' Find untested ideas mentioned in L-codes
#'
#' @param lessons List of lesson objects/strings
#' @return List of hypothesis objects for untested ideas
find_untested_ideas <- function(lessons = list()) {
  ideas <- list()

  suggestion_patterns <- c(
    "(could|should|might)\\s+(try|test|explore)\\s+([^.;]+)",
    "untested:?\\s*([^.;]+)",
    "future\\s+(work|experiment|test):?\\s*([^.;]+)",
    "next\\s+step:?\\s*([^.;]+)"
  )

  for (l in lessons) {
    l_text <- if (is.character(l)) l else (l$text %||% l$description %||% "")
    if (nchar(l_text) == 0) next

    for (pat in suggestion_patterns) {
      m <- regmatches(l_text, regexpr(pat, l_text, ignore.case = TRUE, perl = TRUE))
      if (length(m) > 0 && nchar(m[1]) > 10) {
        idea_text <- substr(m[1], 1, 200)

        ideas[[length(ideas) + 1]] <- list(
          objective   = sprintf("Untested idea from L-code: %s", idea_text),
          family      = "l_code_derived",
          type        = "untested_idea",
          description = idea_text,
          bucket      = "explore",
          contract    = make_experiment_contract(
            exp_id     = paste0("LINT_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
                                 sprintf("%02d", length(ideas) + 1)),
            family     = "l_code_derived",
            hypothesis = idea_text,
            source_ref = "l_code_scan"
          )
        )
        break  # one idea per lesson
      }
    }
  }

  ideas
}

#' Design an ensemble variant hypothesis from Grade A strategies
#'
#' @param grade_a List of Grade A strategy entries
#' @return Hypothesis list
design_ensemble_variant <- function(grade_a) {
  if (length(grade_a) < 3) return(NULL)

  # Pick 2-4 strategies for a new blend
  n_pick <- min(4, length(grade_a))
  picked <- sample(grade_a, n_pick)
  ids    <- sapply(picked, function(x) x$strategy_id %||% "unknown")

  # Determine blend type
  blend_types <- c("equal_weight", "risk_parity", "inverse_vol",
                    "regime_conditional", "cardinality_constrained")
  blend <- sample(blend_types, 1)

  h <- list(
    objective   = sprintf("Ensemble: %s blend of %s", blend, paste(ids, collapse = "+")),
    family      = "ensemble",
    type        = "ensemble_variant",
    description = sprintf("Combine %d Grade A strategies (%s) using %s weighting",
                           n_pick, paste(ids, collapse = ", "), blend),
    bucket      = "exploit",
    components  = ids,
    blend_type  = blend,
    contract    = make_experiment_contract(
      exp_id     = paste0("ENS_", format(Sys.time(), "%Y%m%d_%H%M%S")),
      family     = "ensemble",
      hypothesis = sprintf("%s blend of %s yields SR improvement", blend,
                            paste(ids, collapse = "+")),
      source_ref = "grade_a_catalog"
    )
  )

  h
}

#==============================================================================
# EXPERIMENT CONTRACT (Lawbook 8.1 — 8 items)
#==============================================================================

#' Create a standard experiment contract
#'
#' @param exp_id Experiment ID
#' @param family Factor/strategy family
#' @param hypothesis 1-sentence hypothesis
#' @param source_ref Reference source (paper/axiom/l-code)
#' @param universe "KOSPI" (default)
#' @param frequency "monthly" (default)
#' @param benchmark "IKS200" (default)
#' @return Named list with 8 items
make_experiment_contract <- function(exp_id,
                                      family = "general",
                                      hypothesis = "",
                                      source_ref = "",
                                      universe = "KOSPI",
                                      frequency = "monthly",
                                      benchmark = "IKS200") {
  list(
    # 1. Scope
    scope = list(
      exp_id    = exp_id,
      family    = family,
      universe  = universe,
      frequency = frequency,
      benchmark = benchmark,
      tc_model  = "commission=0.0015"
    ),
    # 2. Hypothesis
    hypothesis = list(
      statement             = hypothesis,
      mechanism             = "",
      falsification_condition = "OOS Sharpe retention < 0.3 or MDD > 45%"
    ),
    # 3. Data PIT
    data_pit = list(
      snapshot_id   = format(Sys.time(), "%Y%m%dT%H%M%S"),
      pit_checklist = TRUE
    ),
    # 4. Implementation
    implementation = list(
      strategy_id = NA_character_,
      parameters  = list(),
      constraints = list(max_holdings = 30, long_only = TRUE)
    ),
    # 5. Execution
    execution = list(
      preflight = TRUE,
      full_run  = TRUE
    ),
    # 6. Metrics
    metrics = c("net_cagr", "sharpe0_m_ann", "mdd", "cvar99_m", "turnover", "ic_icir"),
    # 7. Statistical Validation
    stat_validation = c("ff3", "carhart4", "ff5", "fama_macbeth"),
    # 8. Decision (filled by Judge)
    decision = list(
      grade        = NULL,
      verdict      = NULL,
      next_actions = NULL
    ),
    # Metadata
    source_ref  = source_ref,
    created_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    created_by  = "scout"
  )
}

#==============================================================================
# ALPHA LAB STAGE 0 SCREENING (Lawbook 8.2)
#==============================================================================

#' Quick pre-screening: ICIR >= 0.15, t-stat >= 1.5
#'
#' @param factors data.table with Date, Ticker, Score columns
#' @param rawdata data.table with Date, Ticker, Ret columns
#' @param lag Forecast horizon in months (default 1)
#' @return list(pass, icir, t_stat, n_obs)
alpha_lab_screen <- function(factors, rawdata, lag = 1) {
  result <- list(pass = FALSE, icir = NA_real_, t_stat = NA_real_, n_obs = 0L)

  tryCatch({
    if (!is.data.table(factors)) factors <- as.data.table(factors)
    if (!is.data.table(rawdata)) rawdata <- as.data.table(rawdata)

    # Ensure required columns
    if (!all(c("Date", "Ticker", "Score") %in% names(factors))) {
      cat("[AlphaLab] Missing columns in factors\n")
      return(result)
    }
    if (!all(c("Date", "Ticker", "Ret") %in% names(rawdata))) {
      cat("[AlphaLab] Missing columns in rawdata\n")
      return(result)
    }

    # Forward return: next month's cross-sectional return
    signal_dates <- sort(unique(factors$Date))
    ret_dates    <- sort(unique(rawdata$Date))

    ic_values <- numeric(0)
    for (sd in signal_dates) {
      # Find next rebalance date (at least 20 trading days ahead)
      future_dates <- ret_dates[ret_dates > sd]
      if (length(future_dates) < 20) next
      target_date <- future_dates[min(20 * lag, length(future_dates))]

      # Cross-sectional IC: rank correlation of Score vs forward return
      sig <- factors[Date == sd, .(Ticker, Score)]
      fwd <- rawdata[Date == target_date, .(Ticker, Ret)]
      merged <- merge(sig, fwd, by = "Ticker")
      merged <- merged[!is.na(Score) & !is.na(Ret)]

      if (nrow(merged) >= 20) {
        ic <- cor(merged$Score, merged$Ret, method = "spearman", use = "complete.obs")
        if (!is.na(ic)) ic_values <- c(ic_values, ic)
      }
    }

    n_obs <- length(ic_values)
    if (n_obs >= 6) {
      icir   <- mean(ic_values, na.rm = TRUE) / sd(ic_values, na.rm = TRUE)
      t_stat <- icir * sqrt(n_obs)
      result <- list(
        pass   = abs(icir) >= 0.15 & abs(t_stat) >= 1.5,
        icir   = round(icir, 4),
        t_stat = round(t_stat, 3),
        n_obs  = n_obs
      )
    }
  }, error = function(e) {
    cat("[AlphaLab] Error:", conditionMessage(e), "\n")
  })

  result
}

#==============================================================================
# MAIN HYPOTHESIS GENERATOR
#==============================================================================

#' Generate hypotheses from multiple sources
#'
#' @param axioms List of axiom objects
#' @param families Named list of family objects (from families.json)
#' @param lessons List of recent lesson objects/strings
#' @param grade_a List of Grade A strategy entries
#' @return List of hypothesis objects, each with bucket tag and experiment contract
generate_hypotheses <- function(axioms = list(),
                                 families = list(),
                                 lessons = list(),
                                 grade_a = list()) {
  hypotheses <- list()
  cat("[Scout] Generating hypotheses...\n")

  # --- 0a. Random explore (20%): non-traditional keywords -> paper search ---
  tryCatch({
    random_kw <- sample(RANDOM_KEYWORD_POOL, 2)
    cat(sprintf("[Scout] Random explore: %s\n", paste(random_kw, collapse = ", ")))
    random_papers <- search_papers(random_kw)
    for (idea in random_papers$ideas) {
      h <- paper_to_hypothesis(idea)
      if (!is.null(h)) {
        h$bucket <- "explore"
        hypotheses <- c(hypotheses, list(h))
      }
    }
  }, error = function(e) {
    cat("[Scout] Random explore failed:", conditionMessage(e), "\n")
  })

  # --- 0b. Targeted paper search (35%): keywords from axioms/families ---
  tryCatch({
    search_keywords <- derive_search_keywords(axioms, families, lessons)
    cat(sprintf("[Scout] Targeted search: %s\n",
                paste(search_keywords, collapse = ", ")))
    paper_results <- search_papers(search_keywords)
    for (idea in paper_results$ideas) {
      h <- paper_to_hypothesis(idea)
      if (!is.null(h)) {
        h$bucket <- "exploit"
        hypotheses <- c(hypotheses, list(h))
      }
    }
  }, error = function(e) {
    cat("[Scout] Targeted search failed:", conditionMessage(e), "\n")
  })

  # --- 1. Axiom-based tests (exploit) ---
  tryCatch({
    for (ax in axioms) {
      n_pass <- ax$n_passing_axes %||%
                ax$axiom_readiness$n_passing_axes %||% 0
      if (n_pass >= 3) {
        h <- design_axiom_test(ax)
        if (!is.null(h)) {
          h$bucket <- "exploit"
          hypotheses <- c(hypotheses, list(h))
        }
      }
    }
  }, error = function(e) {
    cat("[Scout] Axiom tests failed:", conditionMessage(e), "\n")
  })

  # --- 2. Family extensions (stabilize) ---
  tryCatch({
    fam_list <- if (is.data.frame(families)) {
      split(families, seq_len(nrow(families)))
    } else {
      families
    }
    for (fn in names(fam_list)) {
      fam <- fam_list[[fn]]
      fam$name <- fn
      fs <- fam$fail_streak %||% 0
      tc <- fam$trial_count %||% 0
      if (fs < 3 && tc >= 2) {
        h <- design_family_extension(fam, lessons)
        if (!is.null(h)) {
          h$bucket <- "stabilize"
          hypotheses <- c(hypotheses, list(h))
        }
      }
    }
  }, error = function(e) {
    cat("[Scout] Family extensions failed:", conditionMessage(e), "\n")
  })

  # --- 3. Untested ideas from L-codes (explore) ---
  tryCatch({
    untested <- find_untested_ideas(lessons)
    n_take <- min(3, length(untested))
    if (n_take > 0) {
      for (idea in untested[1:n_take]) {
        idea$bucket <- "explore"
        hypotheses <- c(hypotheses, list(idea))
      }
    }
  }, error = function(e) {
    cat("[Scout] L-code scan failed:", conditionMessage(e), "\n")
  })

  # --- 4. Ensemble variants (exploit, if 3+ Grade A) ---
  tryCatch({
    if (length(grade_a) >= 3) {
      h <- design_ensemble_variant(grade_a)
      if (!is.null(h)) {
        h$bucket <- "exploit"
        hypotheses <- c(hypotheses, list(h))
      }
    }
  }, error = function(e) {
    cat("[Scout] Ensemble variant failed:", conditionMessage(e), "\n")
  })

  cat(sprintf("[Scout] Generated %d hypotheses\n", length(hypotheses)))

  # --- Report bucket distribution ---
  if (length(hypotheses) > 0) {
    buckets <- sapply(hypotheses, function(h) h$bucket %||% "unknown")
    bt <- table(buckets)
    cat(sprintf("[Scout] Bucket distribution: %s\n",
                paste(sprintf("%s=%d", names(bt), as.integer(bt)), collapse = ", ")))
  }

  hypotheses
}

#==============================================================================
# UTILITY: Load context data
#==============================================================================

#' Load families.json
load_families_safe <- function() {
  fpath <- file.path(.scout_root, "qepm", "registry", "families.json")
  tryCatch({
    if (file.exists(fpath)) fromJSON(fpath, simplifyVector = FALSE) else list()
  }, error = function(e) {
    cat("[Scout] families.json load failed:", conditionMessage(e), "\n")
    list()
  })
}

#' Load grade_a_catalog.json
load_grade_a_safe <- function() {
  fpath <- file.path(.scout_root, "04_Research", "grade_a_catalog.json")
  tryCatch({
    if (file.exists(fpath)) fromJSON(fpath, simplifyVector = FALSE) else list()
  }, error = function(e) {
    cat("[Scout] grade_a_catalog.json load failed:", conditionMessage(e), "\n")
    list()
  })
}

#==============================================================================
# MAILBOX POLLING LOOP
#==============================================================================

cat("[Scout] Starting mailbox polling loop (interval:", POLL_INTERVAL, "sec)\n")
cat(sprintf("[Scout] Stop file: /tmp/STOP_SCOUT\n"))

while (!file.exists("/tmp/STOP_SCOUT") && !file.exists("/tmp/STOP_RESEARCH")) {

  tryCatch({
    # Check inbox
    msgs <- mailbox_receive(AGENT_NAME, mark_read = TRUE)

    for (msg in msgs) {
      cmd <- msg$body$cmd %||% msg$subject %||% ""
      cat(sprintf("[Scout] Received: cmd='%s' from='%s' id='%s'\n",
                  cmd, msg$from, msg$msg_id))

      if (cmd == "generate_hypotheses") {
        # --- Full hypothesis pipeline ---
        ctx <- msg$body$context %||% msg$body %||% list()

        hypotheses <- generate_hypotheses(
          axioms   = ctx$axioms   %||% list(),
          families = ctx$families %||% load_families_safe(),
          lessons  = ctx$lessons  %||% list(),
          grade_a  = ctx$grade_a  %||% load_grade_a_safe()
        )

        mailbox_reply(msg, AGENT_NAME,
          result  = list(hypotheses = hypotheses,
                          n_generated = length(hypotheses),
                          timestamp = format(Sys.time())),
          success = TRUE
        )
        cat(sprintf("[Scout] Replied with %d hypotheses\n", length(hypotheses)))

      } else if (cmd == "search_only") {
        # --- Paper search only ---
        kw <- msg$body$keywords %||% sample(RANDOM_KEYWORD_POOL, 3)
        results <- search_papers(kw)

        mailbox_reply(msg, AGENT_NAME,
          result  = list(papers = results$papers,
                          ideas = results$ideas,
                          keywords = kw),
          success = TRUE
        )

      } else if (cmd == "status") {
        # --- Health check ---
        mailbox_reply(msg, AGENT_NAME,
          result  = list(
            agent     = AGENT_NAME,
            status    = "alive",
            uptime    = as.numeric(difftime(Sys.time(),
                          .scout_start_time, units = "mins")),
            n_keywords = length(RANDOM_KEYWORD_POOL)
          ),
          success = TRUE
        )

      } else {
        cat(sprintf("[Scout] Unknown command: '%s'\n", cmd))
        mailbox_reply(msg, AGENT_NAME,
          result  = list(error = paste("Unknown command:", cmd)),
          success = FALSE
        )
      }
    }
  }, error = function(e) {
    cat(sprintf("[Scout] Error in polling loop: %s\n", conditionMessage(e)))
  })

  Sys.sleep(POLL_INTERVAL)
}

cat("[Scout] Stopped.\n")
