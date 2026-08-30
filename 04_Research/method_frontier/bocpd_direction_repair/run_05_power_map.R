# run_05_power_map.R — 검정력 지도: 어디서 판별이 가능한가
#
# ── 왜 (내 설계 실수의 정정) ─────────────────────────────────────────────────
# run_01 에서 나는 사전등록 1급을 C1(mass↑ ∩ 사후평균<0)로 잡았다. 그런데 그 조건은
# **발화가 3개월**이다 — n=3 검정은 어떤 효과도 못 잡는다. 검정력을 먼저 재지 않고
# 1급을 확정한 것이 잘못이고(이 저장소 카드: "착수 전 검정력이 설계를 바꿨다"),
# 그렇게 만든 실패를 판정으로 쓴 것은 더 잘못이다. 순서를 바로잡는다.
#
# ★이 스크립트는 **문턱 스윕이 아니다.** 스윕은 성과(p 나 효과)로 문턱을 고르는 것이고,
#   그건 selection 이라 4에피소드 표본에서 감당할 수 없다. 여기서 고르는 것은 없다 —
#   문턱별로 (에피소드 수 → 판별 가능한 최소 효과크기 MDE)를 **지도로 그릴 뿐**이다.
#   지도를 본 뒤 사전등록은 **검정력 기준**으로 한다(효과 기준이 아니라).
#   그래서 아래 표에 p 를 싣되 **판정에 쓰지 않는다** — 진단으로만 읽는다.
#
# ── 두 축 ────────────────────────────────────────────────────────────────────
#   축 1 (통계): 문턱 θ → n_fire · n_episode · MDE(80%) · 실측효과 → 판별가능 여부
#   축 2 (경제): (빈도 × 용량) → 최악 10% 평균을 얼마나 움직이나
#                — 신호가 참이어도 용량이 작으면 무의미하다. 역으로, 목표 개선폭을
#                  주면 필요한 (θ, 용량) 조합이 나온다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_05_power_map.R

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
y <- sub$fwd; mass <- sub$mass
n <- length(y); sdv <- sd(y)
EV <- -0.05; ev <- y < EV; base_rate <- mean(ev)
worst_idx <- order(y)[1:round(n * 0.10)]

cat(sprintf("=== 표본 %d개월 · 월변동성 %.2f%% · P(ret<-5%%)=%.1f%% ===\n",
            n, sdv * 100, base_rate * 100))
cat(sprintf("  mass 분포: min %.3f · q25 %.3f · 중앙 %.3f · q75 %.3f · max %.3f\n",
            min(mass, na.rm = TRUE), quantile(mass, .25, na.rm = TRUE),
            median(mass, na.rm = TRUE), quantile(mass, .75, na.rm = TRUE),
            max(mass, na.rm = TRUE)))

block_perm_p <- function(x, B = 10000L, seed = 20260830) {
  x[is.na(x)] <- 0L
  if (sum(x) == 0L || sum(x) == length(x)) return(NA_real_)
  obs <- mean(y[x == 1L]) - mean(y[x == 0L])
  set.seed(seed); nn <- length(x); st <- sample.int(nn, B, replace = TRUE)
  p <- vapply(st, function(s) {
    xs <- x[c(s:nn, seq_len(s - 1L))]
    if (sum(xs) == 0L || sum(xs) == nn) return(NA_real_)
    mean(y[xs == 1L]) - mean(y[xs == 0L])
  }, numeric(1))
  mean(p <= obs, na.rm = TRUE)
}

# ── 축 1: 통계 검정력 지도 ───────────────────────────────────────────────────
grid <- seq(0.15, 0.90, by = 0.05)
map <- rbindlist(lapply(grid, function(th) {
  x <- as.integer(!is.na(mass) & mass >= th)
  k_m <- sum(x); k_e <- sum(rle(x == 1L)$values)
  if (k_m < 2L || k_m >= n - 2L)
    return(data.table(theta = th, n_fire = k_m, n_epi = k_e, effect = NA_real_,
                      lift = NA_real_, mde80_epi = NA_real_, mde80_mon = NA_real_,
                      resolvable = NA, p_block = NA_real_))
  eff <- mean(y[x == 1L]) - mean(y[x == 0L])
  lf <- mean(ev[x == 1L]) / base_rate
  se_e <- sdv * sqrt(1 / max(k_e, 1L) + 1 / (n - max(k_e, 1L)))   # 에피소드 기준(보수)
  se_m <- sdv * sqrt(1 / k_m + 1 / (n - k_m))                     # 월 기준(낙관)
  data.table(theta = th, n_fire = k_m, n_epi = k_e, effect = eff, lift = lf,
             mde80_epi = (1.645 + 0.84) * se_e, mde80_mon = (1.645 + 0.84) * se_m,
             resolvable = abs(eff) >= (1.645 + 0.84) * se_e,
             p_block = block_perm_p(x))
}))

cat("\n=== 축 1: 통계 검정력 지도 (θ = mass 문턱) ===\n")
cat("   ※ p_block 은 진단이다 — 이 표로 θ 를 고르지 않는다(그건 selection).\n")
print(map[, .(theta, n_fire, n_epi,
              effect_pp = round(effect * 100, 2), lift = round(lift, 2),
              MDE80_epi = round(mde80_epi * 100, 2),
              MDE80_mon = round(mde80_mon * 100, 2),
              판별가능 = ifelse(is.na(resolvable), "-", ifelse(resolvable, "O", "X")),
              p_block = round(p_block, 3))])

# ── 축 1b: 판별하려면 에피소드가 몇 개 필요한가 (효과크기 고정) ─────────────
cat("\n=== 축 1b: 관측 효과크기를 판별하려면 에피소드가 몇 개 필요한가 ===\n")
for (eff_pp in c(2, 3, 3.53, 5)) {
  e <- eff_pp / 100
  # (1.645+0.84)*sd*sqrt(1/k + 1/(n-k)) <= e  → k 최소값 탐색
  k_need <- NA_integer_
  for (k in 2:(n - 3L)) {
    se <- sdv * sqrt(1 / k + 1 / (n - k))
    if ((1.645 + 0.84) * se <= e) { k_need <- k; break }
  }
  cat(sprintf("  효과 %.2f%%p → 에피소드 %s개 필요 (현재 최대 %d개)\n",
              eff_pp, ifelse(is.na(k_need), ">%d" , as.character(k_need)),
              max(map$n_epi, na.rm = TRUE)))
}

# ── 축 2: 경제적 용량 지도 ───────────────────────────────────────────────────
#   개입 = 발화월에 현금 c 를 얹는다 → 그 달 수익 × (1-c). 최악 10% 평균 개선폭을 본다.
cat("\n=== 축 2: 경제 용량 지도 — 최악 10%% 평균 개선폭(%p) ===\n")
cat("   행 = mass 문턱 · 열 = 현금 용량. 목표 = +1.00%p 이상\n")
doses <- c(0.08, 0.20, 0.30, 0.50)
econ <- rbindlist(lapply(grid, function(th) {
  x <- as.integer(!is.na(mass) & mass >= th)
  if (sum(x) < 2L) return(NULL)
  r <- as.list(setNames(vapply(doses, function(cc) {
    ya <- ifelse(x == 1L, y * (1 - cc), y)
    (mean(ya[worst_idx]) - mean(y[worst_idx])) * 100
  }, numeric(1)), sprintf("c%02d", round(doses * 100))))
  c(list(theta = th, n_fire = sum(x), hit_worst = sum(x[worst_idx])), r)
}))
print(econ[, lapply(.SD, function(v) if (is.numeric(v)) round(v, 3) else v)])

cat("\n※ hit_worst = 최악 10%(", length(worst_idx), "개월) 중 발화한 달 수.\n", sep = "")
cat("  개선폭은 이 숫자에 거의 비례한다 — 최악 구간을 못 맞히면 용량을 키워도 안 움직인다.\n")

fwrite(map, file.path(OUT, "power_map.csv"))
fwrite(econ, file.path(OUT, "econ_map.csv"))
cat(sprintf("\n[out] %s/{power_map,econ_map}.csv\n", OUT))
