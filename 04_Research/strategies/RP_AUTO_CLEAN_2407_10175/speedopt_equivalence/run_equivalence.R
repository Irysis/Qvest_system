# =============================================================================
# run_equivalence.R — 구판(engine.pre_speedopt.R) 대 새 판(engine.R) 등가 시험 · 시간 측정
#
# run:     Rscript run_equivalence.R run <old|new> <variant> <inputs.rds> <out.rds> <YYYY-MM-DD,...>
#            new 판의 작업자 수 · 캐시는 환경변수(RP_2407_WORKERS · RP_2407_CACHE_DIR · RP_2407_CACHE)로 정한다.
# compare: Rscript run_equivalence.R compare <ref.rds> <cand.rds> [<out.json>]
#
# 엔진 코드는 고치지 않는다. 엔진 파일을 구문 분석해 최상위 식을 레인과 같은 순서로 평가하되(입력 = RAWDATA · BM_DT ·
# .RP_START_DATE · .RP_VARIANT), 마지막 '모든 신호월을 도는' 식 직전에서 멈추고 고른 신호월만 그 엔진의 경로로 돈다:
#   old = 구판 루프의 몸체 그대로(.fit_month(.sig_lo[s], .sig_hi[s]) 를 월 순서로) · new = 새 판의 .run_months(고른 위치).
# 평가 함수의 프레임에 ofile(엔진 경로)을 둬 source() 안에서 도는 것과 같은 자기 위치 판독을 받게 한다.
# 월마다 기록: 신호일 · 로그 주석(note) · PORTFOLIO 행 · 그 달 시간 · 끝난 뒤의 난수 상태(.Random.seed).
# =============================================================================
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(TRUE)
.SELF <- gsub("\\\\", "/", sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
.EDIR <- dirname(dirname(.SELF))                                    # 전략 폴더(엔진 두 판이 있는 곳)

eval_engine_upto <- function(ofile, env, stop_rx) {                  # ofile = source() 의 지역 변수 이름(엔진의 자기 위치 판독)
  ex <- parse(ofile, keep.source = FALSE)
  txt <- vapply(ex, function(e) paste(deparse(e, width.cutoff = 500L), collapse = " "), "")
  cut <- which(grepl(stop_rx, txt))
  if (length(cut) != 1L) stop("stop expression not found exactly once: ", stop_rx)
  for (i in seq_len(cut - 1L)) eval(ex[[i]], envir = env)
  invisible(cut)
}

if (identical(a[1], "run")) {
  which_eng <- a[2]; variant <- a[3]; inputs <- a[4]; out <- a[5]
  want <- as.Date(strsplit(a[6], ",", fixed = TRUE)[[1]])
  eng <- file.path(.EDIR, if (identical(which_eng, "old")) "engine.pre_speedopt.R" else "engine.R")
  t_load <- proc.time()[[3L]]
  inp <- readRDS(inputs)
  env <- new.env(parent = globalenv())
  env$RAWDATA <- inp$RAWDATA; env$BM_DT <- inp$BM_DT; env$.RP_START_DATE <- inp$start_date; env$.RP_VARIANT <- variant
  meta_in <- inp$meta
  rm(inp); invisible(gc())
  rx <- if (identical(which_eng, "old")) '^\\.res <- vector\\("list", length\\(\\.sig_hi\\)\\)$' else '^\\.res <- lapply\\(\\.run_months\\('
  eval_engine_upto(eng, env, rx)
  t_setup <- proc.time()[[3L]] - t_load
  sd <- env$.dates[env$.sig_hi]
  pos <- match(want, sd)
  if (anyNA(pos)) stop("not signal dates: ", paste(want[is.na(pos)], collapse = ","))
  pos <- sort(pos)                                                   # 월 순서(구판 루프와 같은 순서)
  cat(sprintf("[eq] %s engine · variant %s · %d months · setup %.1fs · signal months total %d\n",
              which_eng, env$VARIANT, length(pos), t_setup, length(sd)))
  t0 <- proc.time()[[3L]]
  rows <- vector("list", length(pos))
  if (identical(which_eng, "old")) {
    for (j in seq_along(pos)) {
      s <- pos[j]; t1 <- proc.time()[[3L]]
      fm <- env$.fit_month(env$.sig_lo[s], env$.sig_hi[s])
      secs <- proc.time()[[3L]] - t1
      rows[[j]] <- list(date = sd[s], note = fm$note, pf = fm$pf, secs = secs, hit = NA)
      cat(sprintf("[eq] %s %s (%.1fs)\n", format(sd[s]), fm$note, secs))
    }
  } else {
    rr <- env$.run_months(pos)
    for (j in seq_along(pos))
      rows[[j]] <- list(date = sd[pos[j]], note = rr[[j]]$note, pf = rr[[j]]$pf, secs = rr[[j]]$secs, hit = rr[[j]]$hit)
  }
  wall <- proc.time()[[3L]] - t0
  rng <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  saveRDS(list(engine = which_eng, engine_file = eng, engine_md5 = unname(tools::md5sum(eng)), variant = env$VARIANT,
               months = rows, wall = wall, setup = t_setup, rng_final = rng, inputs_meta = meta_in,
               workers_env = Sys.getenv("RP_2407_WORKERS"), cache_env = c(Sys.getenv("RP_2407_CACHE"), Sys.getenv("RP_2407_CACHE_DIR")),
               r_version = R.version.string, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), out)
  cat(sprintf("[eq] done wall %.1fs -> %s\n", wall, out))
} else if (identical(a[1], "compare")) {
  A <- readRDS(a[2]); B <- readRDS(a[3])
  da <- vapply(A$months, function(m) format(m$date), ""); db <- vapply(B$months, function(m) format(m$date), "")
  common <- intersect(da, db)
  per <- lapply(common, function(d) {
    x <- A$months[[match(d, da)]]; y <- B$months[[match(d, db)]]
    same_note <- identical(x$note, y$note)
    px <- x$pf; py <- y$pf
    same_pf <- if (is.null(px) || is.null(py)) is.null(px) && is.null(py) else
      identical(names(px), names(py)) && identical(px$Date, py$Date) && identical(px$Ticker, py$Ticker) &&
      identical(px$Weight, py$Weight, num.eq = FALSE) && identical(px$Leg, py$Leg)
    maxdiff <- if (!is.null(px) && !is.null(py) && nrow(px) == nrow(py)) max(abs(px$Weight - py$Weight)) else NA_real_
    fp <- function(z) if (is.null(z)) NA_character_ else            # 그 달 PORTFOLIO 행의 지문(열 값 비트 그대로)
      unname(tools::sha256sum(bytes = serialize(list(as.integer(z$Date), z$Ticker, z$Weight, z$Leg), NULL, xdr = TRUE, version = 2L)))
    list(date = d, rows = if (is.null(px)) 0L else nrow(px), identical_note = same_note, identical_rows = same_pf,
         max_abs_weight_diff = maxdiff, secs_ref = round(x$secs, 1), secs_cand = round(y$secs, 1),
         cand_ssl_from_cache = isTRUE(y$hit), sha256_ref = fp(px), sha256_cand = fp(py), note = x$note)
  })
  pa <- rbindlist(lapply(A$months[match(common, da)], function(m) m$pf))
  pb <- rbindlist(lapply(B$months[match(common, db)], function(m) m$pf))
  all_same <- identical(pa, pb) && identical(pa$Weight, pb$Weight, num.eq = FALSE)
  rng_same <- identical(A$rng_final, B$rng_final)
  res <- list(ref = list(engine = A$engine, md5 = A$engine_md5, variant = A$variant, wall = round(A$wall, 1)),
              cand = list(engine = B$engine, md5 = B$engine_md5, variant = B$variant, wall = round(B$wall, 1),
                          workers = B$workers_env, cache = B$cache_env),
              months = length(common), all_months_identical = all(vapply(per, function(p) p$identical_note && p$identical_rows, NA)),
              portfolio_identical = all_same, portfolio_rows = nrow(pa), final_rng_identical = rng_same, per_month = per,
              compared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  for (p in per) cat(sprintf("%s rows=%d note=%s rows_identical=%s maxdiff=%s ref=%.1fs cand=%.1fs%s\n", p$date, p$rows,
                             p$identical_note, p$identical_rows, format(p$max_abs_weight_diff), p$secs_ref, p$secs_cand,
                             if (p$cand_ssl_from_cache) " [cand ssl cache]" else ""))
  cat(sprintf("== %s/%s vs %s/%s : months %d · all identical %s · PORTFOLIO identical %s (%d rows) · final RNG identical %s · wall %.0fs vs %.0fs\n",
              A$engine, A$variant, B$engine, B$variant, length(common), res$all_months_identical, all_same, nrow(pa), rng_same, A$wall, B$wall))
  if (length(a) >= 4L) writeLines(jsonlite::toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null"), a[4])
} else stop("usage: run|compare ...")
