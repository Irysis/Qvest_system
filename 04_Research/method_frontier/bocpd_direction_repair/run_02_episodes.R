# run_02_episodes.R — 후보의 실질 n: 에피소드 수 + 블록 순열
#
# ── 왜 ───────────────────────────────────────────────────────────────────────
# run_01 의 순열검정은 월을 독립 표본으로 다룬다. 그런데 국면 신호의 발화는 **연속월로
# 뭉친다** — 11번 발화가 서로 다른 11개 사건이 아니라 한두 에피소드일 수 있다.
# 그러면 실질 n 은 11 이 아니라 1~2 이고, 월 단위 순열의 p 는 낙관적으로 편향된다.
# (메모리: project-episode-count-not-month-count-binds — "구속하는 건 월 수가 아니라
#  에피소드 수. 창을 늘려도 에피소드는 안 는다")
#
# 그래서 두 가지를 더 잰다:
#   ① 발화의 **에피소드 분해** — 연속 발화 블록 수, 최대 블록 길이, 연도 분포
#   ② **블록 순열** — 라벨을 월 단위로 섞지 않고 길이 6 블록 단위로 순환이동시켜
#      자기상관을 보존한 귀무분포를 만든다. 월 순열보다 보수적이다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_02_episodes.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(data.table))

OUT <- "04_Research/method_frontier/bocpd_direction_repair"
d <- fread(file.path(OUT, "panel_measured.csv"))
d[, Date := as.Date(Date)]
sub <- d[clean == TRUE & !is.na(fwd)][order(Date)]
cands <- c("C1", "C2", "C3", "C4", "LEGACY")

# ── ① 에피소드 분해 ─────────────────────────────────────────────────────────
epi <- rbindlist(lapply(cands, function(cc) {
  x <- sub[[cc]]; x[is.na(x)] <- 0L
  if (sum(x) == 0L) return(data.table(cand = cc, n_fire = 0L, n_episode = 0L,
                                      max_block = 0L, years = ""))
  r <- rle(x == 1L)
  blocks <- r$lengths[r$values]
  yrs <- sort(unique(format(sub$Date[x == 1L], "%Y")))
  data.table(cand = cc, n_fire = sum(x), n_episode = length(blocks),
             max_block = max(blocks), years = paste(yrs, collapse = ","))
}))
cat("=== 발화의 에피소드 분해 (매크로 clean 구간) ===\n"); print(epi)

# ── ② 블록 순열 (길이 6 순환이동 — 자기상관 보존) ───────────────────────────
block_perm_p <- function(x, y, B = 5000L, seed = 20260830) {
  x[is.na(x)] <- 0L
  if (sum(x) == 0L) return(NA_real_)
  obs <- mean(y[x == 1L]) - mean(y[x == 0L])
  set.seed(seed); n <- length(x)
  st <- sample.int(n, B, replace = TRUE)
  p <- vapply(st, function(s) {
    xs <- x[c(s:n, seq_len(s - 1L))]           # 순환이동 = 블록 구조 보존
    if (sum(xs) == 0L || sum(xs) == n) return(NA_real_)
    mean(y[xs == 1L]) - mean(y[xs == 0L])
  }, numeric(1))
  mean(p <= obs, na.rm = TRUE)
}

y <- sub$fwd
bp <- rbindlist(lapply(cands, function(cc)
  data.table(cand = cc, p_block = block_perm_p(sub[[cc]], y))))
res <- fread(file.path(OUT, "candidates.csv"))
m <- merge(merge(res[, .(cand, n_fire, mean_fire, mean_rest, lift, recall, p_perm)],
                 epi[, .(cand, n_episode, max_block, years)], by = "cand"),
           bp, by = "cand")
setorder(m, cand)
cat("\n=== 월 순열 vs 블록 순열 (실질 n 반영) ===\n")
print(m[, .(cand, n_fire, n_episode,
            mean_fire = round(mean_fire * 100, 2), mean_rest = round(mean_rest * 100, 2),
            lift = round(lift, 3), p_month = round(p_perm, 4), p_block = round(p_block, 4))])
cat("\n연도 분포:\n"); print(m[, .(cand, n_episode, years)])
fwrite(m, file.path(OUT, "episodes.csv"))
cat(sprintf("\n[out] %s/episodes.csv\n", OUT))
