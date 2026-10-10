#==============================================================================
# lib_mc1.R — 2계층 역할 로테이션 MC1(국면 예측기 판별력) 공용 함수 (2026-10-10)
#
# 설계 = 04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §2.2 · §3(MC1)
# 원칙: 기존 국면 엔진(02_Infrastructure/regime/*)은 읽기만 — 수정 0. 05_Production 은 텍스트 읽기만.
#   PIT: 예측기 값 = 결정일 t(보유월 시작 전 마지막 한국 거래일) 이하 정보만. 사후 연대기(PS)는 평가 표적으로만.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

qroot <- function() {
  for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), normalizePath("../..", winslash = "/", mustWork = FALSE))) {
    p <- gsub("\\\\", "/", p)
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(p)
  }
  stop("[lib_mc1] repo root not found (QM_ROOT)")
}
ROOT <- qroot()
L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
WORK <- file.path(L2DIR, "work")
dir.create(WORK, showWarnings = FALSE, recursive = TRUE)

file_sig <- function(p) {
  p <- if (grepl("^[A-Za-z]:/", p)) p else file.path(ROOT, p)
  if (!file.exists(p)) return(list(path = p, exists = FALSE))
  list(path = sub(paste0("^", ROOT, "/"), "", p), exists = TRUE,
       mtime = format(file.info(p)$mtime, "%Y-%m-%dT%H:%M:%S%z"),
       size = unname(file.info(p)$size), md5 = unname(tools::md5sum(p)))
}

now_kst <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "Asia/Seoul")

write_json_atomic <- function(x, path) {
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  write_json(x, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}

# ── 정본 벤치마크(.cache/benchmark.parquet) ─────────────────────────────────
load_bm <- function() {
  b <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
  b[, Date := as.Date(Date)]
  setorder(b, Date)
  b[!is.na(BM_Close) & BM_Close > 0]
}

# msm_update.R §3-4 와 같은 입력: 로그수익(종가) + expanding past-only 디민(2026-08-13 PIT 수리판)
msm_returns <- function(bm) {
  r <- c(NA_real_, diff(log(bm$BM_Close)))
  d <- bm$Date
  r <- r[-1]; d <- d[-1]
  cs_n <- cumsum(!is.na(r)); cs_s <- cumsum(ifelse(is.na(r), 0, r))
  data.table(Date = d, r_raw = r, r = r - cs_s / pmax(cs_n, 1L))
}

# 운영 커널(msm_update.R 안의 C++ 문자열)을 **텍스트로 읽어** 컴파일 — msm_update.R 자체는 source 하지 않는다
#   (source 하면 .cache/msm_*.parquet 를 덮어쓴다). 반환 = extract_msm_path 함수를 가진 환경.
prod_msm_kernel <- function() {
  src <- readLines(file.path(ROOT, "04_Research/regime_comparison/msm_update.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^\\s*msm_cpp_code <- '", src)
  i1 <- which(trimws(src) == "'")
  i1 <- i1[i1 > i0][1]
  stopifnot(length(i0) == 1L, is.finite(i1))
  code <- c(sub("^\\s*msm_cpp_code <- '", "", src[i0]), src[(i0 + 1L):(i1 - 1L)])
  e <- new.env()
  Rcpp::sourceCpp(code = paste(code, collapse = "\n"), env = e, verbose = FALSE)
  e
}

fast_msm_kernel <- function() {
  e <- new.env()
  Rcpp::sourceCpp(file.path(L2DIR, "msm_fast_kernel.cpp"), env = e, verbose = FALSE)
  e
}

# ── 결정일: 보유월 m 시작 전 마지막 한국 거래일(벤치 달력) ───────────────────
decision_table <- function(months, bm_dates) {
  bm_dates <- sort(unique(as.Date(bm_dates)))
  first_day <- as.Date(paste0(months, "-01"))
  idx <- findInterval(first_day - 1L, bm_dates)          # 마지막 거래일 <= 전월 말일 = < 월초
  data.table(ym = months, t = bm_dates[idx], t_lag1 = bm_dates[pmax(idx - 1L, 1L)])
}

# as-of 조회: Date <= d 인 마지막 행의 값(같은 날 포함). 사용한 원 날짜도 반환.
asof_value <- function(dates_src, values_src, d) {
  o <- order(dates_src); ds <- as.Date(dates_src)[o]; vs <- values_src[o]
  j <- findInterval(as.Date(d), ds)
  list(value = ifelse(j > 0, vs[pmax(j, 1L)], NA_real_), src_date = as.Date(ifelse(j > 0, ds[pmax(j, 1L)], NA), origin = "1970-01-01"))
}

# ── 표적 ─────────────────────────────────────────────────────────────────────
# (1) Pagan-Sossounov 약세 국면(사후 연대기 · 평가 표적 전용) — 정본 계약 함수 그대로(strategy_role.R::sr_regimes)
ps_chronology <- function() {
  e <- new.env()
  sys.source(file.path(ROOT, "02_Infrastructure/contracts/strategy_role.R"), envir = e)
  b <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet"), col_select = c("Date", "BM_Ret")))
  setnames(b, c("date", "bm")); b[, date := as.Date(date)]; b <- b[!is.na(bm)]; setkey(b, date)
  R <- e$sr_regimes(b)
  attr(R, "bm_last_date") <- max(b$date)
  R
}

# (2) 월 실현변동성 = 월 내 일간 로그수익 표준편차
monthly_rv <- function(bm) {
  x <- data.table(Date = bm$Date[-1], lr = diff(log(bm$BM_Close)))
  x[, ym := format(Date, "%Y-%m")]
  x[, .(rv = sd(lr), n_days = .N), by = ym]
}

# ── AUC (Mann-Whitney, 동률 0.5) ─────────────────────────────────────────────
auc_mw <- function(score, y) {
  ok <- is.finite(score) & !is.na(y)
  s <- score[ok]; y <- as.logical(y[ok])
  n1 <- sum(y); n0 <- sum(!y)
  if (n1 == 0L || n0 == 0L) return(NA_real_)
  rk <- rank(s, ties.method = "average")
  (sum(rk[y]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

# 원형 이동 블록 부트스트랩 인덱스(블록 길이 L 개월) — 모든 예측기에 같은 인덱스(공통 난수 → 쌍대 비교 가능)
cbb_indices <- function(n, L = 12L, B = 5000L, seed = 20261010L) {
  set.seed(seed)
  nb <- ceiling(n / L)
  lapply(seq_len(B), function(i) {
    st <- sample.int(n, nb, replace = TRUE)
    idx <- as.vector(vapply(st, function(s) ((s - 1L + 0:(L - 1L)) %% n) + 1L, integer(L)))
    idx[seq_len(n)]
  })
}

boot_auc <- function(score, y, idx_list) vapply(idx_list, function(ix) auc_mw(score[ix], y[ix]), numeric(1))

ci_q <- function(v, lo, hi) { v <- v[is.finite(v)]; if (!length(v)) return(c(NA_real_, NA_real_)); unname(quantile(v, c(lo, hi), type = 7)) }

# 원형 이동 귀무(보조 진단): 예측기 계열을 표적 대비 k개월 원형 이동(|k| >= L) — 두 계열의 자기상관을 보존한 우연 분포
shift_null_p <- function(score, y, L = 12L) {
  ok <- is.finite(score) & !is.na(y); s <- score[ok]; yy <- y[ok]; n <- length(s)
  obs <- auc_mw(s, yy)
  ks <- L:(n - L)
  null <- vapply(ks, function(k) auc_mw(s[((seq_len(n) - 1L + k) %% n) + 1L], yy), numeric(1))
  list(obs = obs, n_shifts = length(ks), p_one_sided = (1 + sum(null >= obs)) / (1 + length(null)),
       null_q95 = unname(quantile(null, 0.95)))
}
