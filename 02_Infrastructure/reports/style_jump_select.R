##=============================================================================
## style_jump_select.R — 점프 모형 λ 재선택(6개월마다) + 시험 구간 평가 · Shu · Mulvey (2024) arXiv 2410.14841 §3.2 절차
##   학습 = 확장창 8~12년 · 매달(월말) 다시 적합 · 사이 기간 = 온라인 추론(중심값 고정) ·
##   λ 후보마다 가상 롱숏(기대 연수익 ±5% 에서 ±100% · 그 사이 선형 · 이틀 뒤 적용 · 회전 5bp)의 6년 검증 창 샤프 최대 → 다음 6개월 적용.
##   PIT: 적합 · 표준화 · 강세/약세 표지 = 그 적합일까지 · 선택 = 그 선택일 전 6년 · 적용 = 선택일 뒤.
##   쓰기: <out>/style_jump_params.json(요인별 최근 선택 λ · 선택일 · 다음 선택일) + <out>/style_jump_eval.csv(시험 구간 평가) · 차트 없음.
##   사용: Rscript style_jump_select.R [--kf <정본 폴더>] [--out <출력 폴더>] [--lambdas 1,3,10,30,100,300]
##   동적계획 = Rcpp 판(컴파일 가능 시 · 순수 R 판과 같은 결과를 실행 중 대조) — 아니면 순수 R(느림).
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
opt <- function(k, d) { i <- which(args == k); if (length(i) && i < length(args)) args[i + 1L] else d }
root <- Sys.getenv("CLAUDE_PROJECT_DIR", ""); if (!nzchar(root)) root <- Sys.getenv("QM_ROOT", ".")
KF <- opt("--kf", file.path(root, ".cache")); OUT <- opt("--out", file.path(root, "outputs/ff5_kr"))
LAMS <- as.numeric(strsplit(opt("--lambdas", "10,30,100,300,1000"), ",")[[1]])
KAPS <- strsplit(opt("--kappas", "none,2,3,4"), ",")[[1]]              # none = 같은 가중(JM) · 수 = 희소판 L1 상한 κ
REFIT_M <- as.integer(opt("--refit_months", "1"))                      # 원 논문 = 매달(1) · 빠른 평가 = 분기(3)
GRID <- expand.grid(lam = LAMS, kap = KAPS, stringsAsFactors = FALSE); GRID$key <- sprintf("l%s_k%s", GRID$lam, GRID$kap)
source(file.path(root, "02_Infrastructure/reports/style_jump_model.R"))
FAC <- c("SMB", "HML", "RMW", "CMA", "WML")
VAL_Y <- 6; STEP_M <- 6; CAP <- 0.05; COST <- 5e-4; LAG <- 2L            # Shu · Mulvey §3.2 그대로

## Rcpp 동적계획(같은 식) — 실패하면 순수 R
dp_fun <- jm_dp; on_fun <- jm_online; engine <- "R"
if (requireNamespace("Rcpp", quietly = TRUE)) {
  ok <- tryCatch({
    Rcpp::cppFunction('IntegerVector dp_cpp(NumericMatrix L, double lam) {
      int n = L.nrow(); IntegerMatrix B(n, 2); double v1 = L(0,0), v2 = L(0,1);
      for (int t = 1; t < n; t++) { double a1 = v1, b1 = v2 + lam, a2 = v1 + lam, b2 = v2;
        int c1 = (a1 <= b1) ? 1 : 2; int c2 = (b2 <= a2) ? 2 : 1;
        v1 = std::min(a1, b1) + L(t,0); v2 = std::min(a2, b2) + L(t,1); B(t,0) = c1; B(t,1) = c2; }
      IntegerVector s(n); s[n-1] = (v1 <= v2) ? 1 : 2;
      for (int t = n - 1; t > 0; t--) s[t-1] = B(t, s[t]-1);
      return s; }')
    Rcpp::cppFunction('IntegerVector on_cpp(NumericMatrix L, double lam) {
      int n = L.nrow(); IntegerVector s(n); double v1 = L(0,0), v2 = L(0,1); s[0] = (v1 <= v2) ? 1 : 2;
      for (int t = 1; t < n; t++) { double n1 = std::min(v1, v2 + lam) + L(t,0), n2 = std::min(v1 + lam, v2) + L(t,1);
        double m = std::min(n1, n2); v1 = n1 - m; v2 = n2 - m; s[t] = (v1 <= v2) ? 1 : 2; }
      return s; }')
    set.seed(1); Lt <- matrix(abs(rnorm(4000)), ncol = 2)
    stopifnot(identical(dp_cpp(Lt, 3), jm_dp(Lt, 3)), identical(on_cpp(Lt, 3), jm_online(Lt, 3)))
    TRUE }, error = function(e) { cat("[jump_select] Rcpp 불가 — 순수 R:", conditionMessage(e), "\n"); FALSE })
  if (ok) { dp_fun <- dp_cpp; on_fun <- on_cpp; engine <- "Rcpp(순수 R 과 대조 일치)" }
}
cat(sprintf("[jump_select] 동적계획 = %s · λ 후보 %s · κ 후보 %s · 다시 적합 %d개월마다\n", engine,
            paste(LAMS, collapse = ","), paste(KAPS, collapse = ","), REFIT_M))

D <- as.data.table(read_parquet(file.path(KF, "kr_factor_returns_daily.parquet"), col_select = c("Date", "MKT", FAC)))
D[, Date := as.Date(Date)]; setorder(D, Date); D <- D[complete.cases(D)]

## 한 요인 · 한 λ: 매달 다시 적합 → 다음 월말까지 온라인 상태 · 기대 연수익(학습 창 상태 평균)
FEAT <- lapply(setNames(FAC, FAC), function(f) { r <- D[[f]]; X <- sjm_features(r, D$MKT); keep <- complete.cases(X)
  list(X = X[keep, , drop = FALSE], rr = r[keep], dd = D$Date[keep]) })
online_path <- function(f, lam, kap = "none") {
  kappa <- if (identical(kap, "none")) NULL else as.numeric(kap)
  X <- FEAT[[f]]$X; rr <- FEAT[[f]]$rr; dd <- FEAT[[f]]$dd; n <- nrow(X)
  ym <- format(dd, "%Y-%m"); me <- which(c(ym[-1] != ym[-n], FALSE))
  me <- me[as.numeric(dd[me] - dd[1]) >= 365.25 * 8]
  if (REFIT_M > 1L) me <- me[as.integer(format(dd[me], "%m")) %% REFIT_M == 0L]
  st <- rep(NA_integer_, n); ex <- rep(NA_real_, n)
  for (j in seq_along(me)) {
    fi <- me[j]; nx <- if (j < length(me)) me[j + 1L] else n
    if (fi == nx) next
    ## 한 상태로 무너지면 직전 적합일로 물러난다(최대 4번 · 과거 자료만) — 운영 sw_jump_regime 과 같은 규칙
    fit <- NULL
    for (fc in rev(me[max(1L, j - 4L):j])) {
      t0 <- max(1L, which(dd >= dd[fc] - round(365.25 * 12))[1]); tr <- t0:fc
      mu <- colMeans(X[tr, , drop = FALSE]); sg <- apply(X[tr, , drop = FALSE], 2, sd); sg[!is.finite(sg) | sg == 0] <- 1
      Z <- sweep(sweep(X[t0:nx, , drop = FALSE], 2, mu), 2, sg, "/")
      fit <- jm_fit_sparse(Z[seq_along(tr), , drop = FALSE], lam, kappa, dp = dp_fun)
      if (!is.null(fit)) break
    }
    if (is.null(fit)) next
    mret <- vapply(1:2, function(k) mean(rr[tr][fit$s == k]), numeric(1)); bull <- which.max(mret)
    so <- on_fun(jm_loss(sweep(Z, 2, sqrt(fit$w), "*"), fit$Th), lam)
    idx <- (fi + 1L):nx; loc <- idx - t0 + 1L
    st[idx] <- ifelse(so[loc] == bull, 1L, -1L); ex[idx] <- 252 * mret[so[loc]]
  }
  data.table(Date = dd, r = rr, state = st, exp_ann = ex)
}
ls_ret <- function(P) {                                    # 가상 롱숏 일수익(이틀 뒤 적용 · 회전 비용)
  pos <- pmax(-1, pmin(1, P$exp_ann / CAP)); pos[is.na(pos)] <- 0
  pl <- shift(pos, LAG, fill = 0); tc <- COST * abs(pl - shift(pl, 1L, fill = 0))
  pl * P$r - tc
}
sharpe <- function(x) { x <- x[is.finite(x)]; if (length(x) < 60 || sd(x) == 0) NA_real_ else mean(x) / sd(x) * sqrt(252) }

res <- list(); params <- list(); evals <- list()
for (f in FAC) {
  t0 <- Sys.time()
  paths <- lapply(seq_len(nrow(GRID)), function(i) online_path(f, GRID$lam[i], GRID$kap[i])); names(paths) <- GRID$key
  L1 <- paths[[1]]; dd <- L1$Date
  lsr <- sapply(paths, ls_ret)                             # 날 × λ
  first_state <- min(which(!is.na(L1$state)))
  sel_dates <- seq(as.Date(format(dd[first_state] + round(365.25 * VAL_Y), "%Y-%m-01")), max(dd), by = sprintf("%d months", STEP_M))
  chosen <- rep(NA_character_, length(dd)); seltab <- list()
  for (k in seq_along(sel_dates)) {
    sdt <- sel_dates[k]; nxt <- if (k < length(sel_dates)) sel_dates[k + 1L] else max(dd) + 1
    win <- dd < sdt & dd >= sdt - round(365.25 * VAL_Y)
    sh <- apply(lsr[win, , drop = FALSE], 2, sharpe)
    if (all(!is.finite(sh))) next
    gi <- which.max(sh); lb <- GRID$key[gi]
    chosen[dd >= sdt & dd < nxt] <- lb
    seltab[[k]] <- data.table(factor = f, select_date = sdt, cfg = lb, lambda = GRID$lam[gi], kappa = GRID$kap[gi],   # 'key' 는 data.table 예약 인자
                              val_sharpe = max(sh, na.rm = TRUE))
  }
  ST <- data.table(Date = dd, r = L1$r, lambda = chosen)
  ST[, state := NA_integer_]; ST[, exp_ann := NA_real_]
  for (l in unique(na.omit(chosen))) { i <- which(ST$lambda == l); P <- paths[[l]]
    ST$state[i] <- P$state[i]; ST$exp_ann[i] <- P$exp_ann[i] }
  te <- ST[!is.na(state)]
  te[, ls := ls_ret(te)]
  fwd <- function(x, h) { n <- length(x); cs <- c(0, cumsum(log1p(x))); o <- rep(NA_real_, n); i <- seq_len(n - h); o[i] <- exp(cs[i + h + 1] - cs[i + 1]) - 1; o }
  yrs <- as.numeric(diff(range(te$Date))) / 365.25; rl <- rle(te$state)
  evals[[f]] <- data.table(factor = f, test_from = min(te$Date), test_to = max(te$Date),
    shifts_per_year = round(sum(diff(te$state) != 0) / yrs, 2), median_run_days = median(rl$lengths),
    bull_share = round(mean(te$state == 1), 3),
    hit21 = round(mean(sign(fwd(te$r, 21)) == te$state, na.rm = TRUE), 3), hit63 = round(mean(sign(fwd(te$r, 63)) == te$state, na.rm = TRUE), 3),
    base_up21 = round(mean(fwd(te$r, 21) > 0, na.rm = TRUE), 3),
    ls_sharpe = round(sharpe(te$ls), 2), factor_sharpe = round(sharpe(te$r), 2))
  st_tab <- rbindlist(seltab)
  res[[f]] <- list(test = te, sel = st_tab)
  last <- st_tab[.N]
  params[[f]] <- list(lambda = last$lambda, kappa = if (identical(last$kappa, "none")) NULL else as.numeric(last$kappa),
                      cfg = last$cfg, select_date = format(last$select_date),
                      next_select = format(seq(last$select_date, by = sprintf("%d months", STEP_M), length.out = 2)[2]),
                      val_sharpe = round(last$val_sharpe, 3), val_years = VAL_Y)
  cat(sprintf("[jump_select] %s 끝 %.0f초 · 최근 %s(%s) · 시험 전환 %.2f/년 · 롱숏 샤프 %.2f\n", f,
              as.numeric(difftime(Sys.time(), t0, units = "secs")), last$cfg, format(last$select_date),
              evals[[f]]$shifts_per_year, evals[[f]]$ls_sharpe))
}
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write_json(list(schema = "style_jump_params_v1", engine = engine, built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                kf_last = format(max(D$Date)), lambdas = LAMS, kappas = KAPS, refit_months = REFIT_M,
                validation_years = VAL_Y, reselect_months = STEP_M,
                train_years = c(8, 12), position_cap_ann = CAP, cost = COST, lag_days = LAG,
                source = "Shu · Mulvey (2024) arXiv 2410.14841 §3.2 · Nystrup · Lindström · Madsen (2020) ESWA 150",
                factors = params), file.path(OUT, "style_jump_params.json"), auto_unbox = TRUE, pretty = TRUE)
fwrite(rbindlist(evals), file.path(OUT, "style_jump_eval.csv"))
saveRDS(res, file.path(OUT, "style_jump_test_paths.rds"))
print(rbindlist(evals))
