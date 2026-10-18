## 위기 진행 중 as-of 유형 식별 탐침(벤치 · 위생 유니버스 일수익만 · 전략 성과 무관 · ≤ τ_D)
##   목적: 판단 Superfan T1 R-20261018-007 C-20261018-060 · 헌장 빈칸 CHARTER-GAPS-7 항목 1(권고 C 의 전제) · P2R05 다음 행동 표 V3(상태 조건부 꼬리 거부) ·
##         P2 정지 보고 2(미측정 형태) — crisis_type_classify 는 위기 구간(고점 ~ 저점) 정보로만 '전면 급락 대 분산'을 갈랐고 시작 시점 as-of 로는 못 갈랐다.
##         그 사이 — 위기가 진행 중인 시점에 그때까지의 정보만으로 유형을 알아볼 수 있는가.
##   ★결과 뒤 질문(P2R04 위기별 결과 · crisis_type_classify 결과를 본 뒤) — 측도 · 결정 시점 · 판정식을 계산 전에 아래에 고정하고 결과와 무관하게 전부 기록한다.
##   측도(계산 전 고정): ρ̄20(t) = t−1 까지의 직전 20거래일 일수익 평균 쌍별 상관(표준화 평균 항등식 · 코호트 = 창 20일 내내 위생 멤버이고 수익 결측 없는 종목 ·
##         Pollet & Wilson 2010) · pct(t) = 2000-01-01 이후 t 이전 날들(최소 250일)의 ρ̄20 중 ρ̄20(t) 이하 비율(확장창 백분위 · as-of).
##   결정 시점(계산 전 고정): D10 = 위기 고점 뒤 벤치(KOSPI200) 낙폭이 처음 10% 이상인 날 · D20 = 처음 20% 이상인 날(LT 확정).
##         ★고점은 사후 정보지만 '고점 이후 최대 낙폭 ≥ x%'는 그날의 확장 최고점 대비 낙폭이라 그날 알 수 있다 — 결정일 = 직전 확장 최고점 대비 낙폭이 처음 x% 를 넘은 날.
##   유형 기준(사후): crisis_type_classify.json 의 rho_W(위기 구간 평균 쌍별 상관 — 기록 전용 분류).
##   반증 판정(주 · 계산 전 고정): 지지 ⇔ D10 의 pct 로 min(pct[2008-05], pct[2020-01]) > max(pct[2011-05], pct[2021-06])(무작위 1/6).
##   보조(기록 · 판정 아님): D20 판 · 14위기 Spearman(pct@D10, rho_W) · 결정일 → 저점 남은 거래일(결정이 저점 근처면 쓸모 없음) · 결정일 → 저점 벤치 추가 하락.
##   실행: Rscript crisis_type_asof.R → 같은 폴더 crisis_type_asof.md · crisis_type_asof.json(기록 전용 — 신호 · 판정 입력 아님)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
OUT  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/_design_notes")
TAU  <- as.Date("2022-12-31"); WIN <- 20L; HIST_MIN <- 250L; HIST_FROM <- as.Date("2000-01-01")
SYSTEMIC <- c("2008-05-16", "2020-01-22"); DISPERSED <- c("2011-05-02", "2021-06-25")
source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"))
CT <- fromJSON(file.path(OUT, "crisis_type_classify.json"), simplifyVector = FALSE)
CR <- rbindlist(lapply(CT$crises, function(z) { k <- strsplit(z$crisis, " ", fixed = TRUE)[[1]]
  data.table(crisis = z$crisis, peak = as.Date(k[1]), trough = as.Date(k[2]), window = z$window, rho_W = as.numeric(z$rho_W), type = z$type) }))
## 벤치 낙폭(확장 최고점 대비 · 그날 알 수 있음)
B <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))[is.finite(BM_Ret), .(Date = as.Date(Date), r = BM_Ret)]
setorder(B, Date); B <- B[Date <= TAU]; B[, nav := cumprod(1 + r)]
## 위생 유니버스 일수익 넓은 행렬
R <- mc_load_raw(ROOT, from = HIST_FROM - 60, to = TAU, hygiene = TRUE)[, .(Date, Ticker, Ret, HYG)]
stopifnot(max(R$Date) <= TAU)
days <- sort(unique(R$Date))
W <- dcast(R[HYG %in% TRUE], Date ~ Ticker, value.var = "Ret"); setkey(W, Date)
M <- as.matrix(W[, -1, with = FALSE]); dts <- W$Date
## ρ̄20(t) — t−1 까지 직전 20거래일(행 i−WIN .. i−1) · 그 창에 결측 없는 열만
rho_at <- function(i) {
  if (i <= WIN) return(NA_real_)
  X <- M[(i - WIN):(i - 1), , drop = FALSE]
  ok <- colSums(is.na(X)) == 0L; X <- X[, ok, drop = FALSE]; N <- ncol(X); if (N < 30L) return(NA_real_)
  mu <- colMeans(X); s <- sqrt(colMeans(sweep(X, 2, mu)^2)); k <- s > 0
  Z <- sweep(sweep(X[, k, drop = FALSE], 2, mu[k]), 2, s[k], "/"); N <- ncol(Z)
  zb <- rowMeans(Z); (N * mean((zb - mean(zb))^2) - 1) / (N - 1)
}
cat("ρ̄20 일별 계산:", length(dts), "일\n")
RHO <- data.table(Date = dts, rho20 = vapply(seq_along(dts), rho_at, numeric(1)))
RHO <- RHO[Date >= HIST_FROM]
RHO[, pct := { v <- rho20; out <- rep(NA_real_, .N)
  for (j in seq_len(.N)) { past <- v[seq_len(j - 1L)]; past <- past[is.finite(past)]
    if (length(past) >= HIST_MIN && is.finite(v[j])) out[j] <- mean(past <= v[j]) }
  out }]
## 결정일: 고점 이후 그날의 확장 최고점(고점부터) 대비 낙폭이 처음 x% 이상
dec_day <- function(pk, tr, x) { S <- B[Date >= pk & Date <= tr]; S[, dd := 1 - nav / cummax(nav)]; d <- S[dd >= x, Date]; if (length(d)) min(d) else as.Date(NA) }
rows <- lapply(seq_len(nrow(CR)), function(i) {
  pk <- CR$peak[i]; tr <- CR$trough[i]; d10 <- dec_day(pk, tr, 0.10); d20 <- dec_day(pk, tr, 0.20)
  g <- function(d) if (is.na(d)) c(NA_real_, NA_real_) else unlist(RHO[Date == d, .(rho20, pct)])
  a10 <- g(d10); a20 <- g(d20)
  left <- function(d) if (is.na(d)) NA_integer_ else length(days[days > d & days <= tr])
  more <- function(d) if (is.na(d)) NA_real_ else 1 - B[Date == tr, nav] / B[Date == d, nav]
  data.table(crisis = CR$crisis[i], window = CR$window[i], type_post = CR$type[i], rho_W = CR$rho_W[i],
             d10 = d10, rho20_d10 = a10[1], pct_d10 = a10[2], days_left_d10 = left(d10), more_drop_d10 = more(d10),
             d20 = d20, rho20_d20 = a20[1], pct_d20 = a20[2], days_left_d20 = left(d20), more_drop_d20 = more(d20))
})
D <- rbindlist(rows); setorder(D, d10)
gp <- function(col, p) D[startsWith(crisis, p), get(col)]
sv <- vapply(SYSTEMIC, function(p) gp("pct_d10", p), numeric(1)); dv <- vapply(DISPERSED, function(p) gp("pct_d10", p), numeric(1))
supported <- isTRUE(min(sv) > max(dv))
sv20 <- vapply(SYSTEMIC, function(p) gp("pct_d20", p), numeric(1)); dv20 <- vapply(DISPERSED, function(p) gp("pct_d20", p), numeric(1))
sp <- suppressWarnings(cor(D$pct_d10, D$rho_W, method = "spearman", use = "complete.obs"))
md <- function(X) c(paste0("| ", paste(names(X), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(X))),
                    apply(X, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |")))
show <- D[, .(crisis, window, type_post, rho_W = sprintf("%.3f", rho_W), d10 = format(d10), pct_d10 = sprintf("%.2f", pct_d10),
              days_left_d10, more_drop_d10 = sprintf("%.3f", more_drop_d10), d20 = format(d20), pct_d20 = sprintf("%.2f", pct_d20),
              days_left_d20, more_drop_d20 = sprintf("%.3f", more_drop_d20))]
verdict <- sprintf("%s — D10 백분위 전면 급락(2008-05 %.2f · 2020-01 %.2f) %s 분산(2011-05 %.2f · 2021-06 %.2f) · 무작위 1/6 · 보조 D20 판 %s(%.2f · %.2f 대 %.2f · %.2f) · 14위기 Spearman(pct@D10, rho_W) %.2f",
                   if (supported) "지지(진행 중 as-of 가 두 묶음을 가름)" else "반증(진행 중 as-of 도 못 가름)",
                   sv[1], sv[2], if (supported) ">" else "≯", dv[1], dv[2], if (isTRUE(min(sv20) > max(dv20))) "가름" else "못 가름", sv20[1], sv20[2], dv20[1], dv20[2], sp)
writeLines(c("# 위기 진행 중 as-of 유형 식별 — ρ̄20 확장창 백분위(벤치 · 위생 유니버스 일수익만 · ≤ 2022-12-31 · 2026-10-18)", "",
             "- 측도 = t−1 까지 20거래일 평균 쌍별 상관 ρ̄20 의 확장창 백분위(as-of). 결정일 D10 · D20 = 그날의 확장 최고점(고점부터) 대비 벤치 낙폭이 처음 10% · 20% 이상인 날.",
             "- 사후 유형 = crisis_type_classify(위기 구간 ρ̄_W · 기록 전용). days_left = 결정일 뒤 저점까지 남은 거래일 · more_drop = 결정일 → 저점 벤치 추가 하락.",
             "- ★결과 뒤 질문 — 측도 · 결정일 · 판정식은 계산 전 스크립트 머리에 고정. 위기 4개라 지지여도 약한 증거(1/6). 기록 전용(신호 · 판정 입력 아님).", "",
             md(show), "", paste0("- 반증 판정(판단 T1 C-060 · 헌장 빈칸 7-1 전제): ", verdict)),
           file.path(OUT, "crisis_type_asof.md"), useBytes = TRUE)
writeLines(toJSON(list(source = "crisis_type_asof.R(벤치 · 위생 유니버스 일수익 · ≤ 2022-12-31 · 전략 성과 무관)",
                       use = "기록 전용 — 신호 · 선택 · 판정 입력 아님(결과 뒤 질문 · 위기 4개)",
                       rule = "pct = expanding percentile of trailing-20d (t-1) average pairwise correlation · decision day = first day drawdown from running max since peak >= 10% (D10) / 20% (D20)",
                       falsification = list(rule = "supported iff min(pct_d10[2008-05,2020-01]) > max(pct_d10[2011-05,2021-06])", supported = supported, chance = "1/6",
                                            d20_separates = isTRUE(min(sv20) > max(dv20)), spearman_pct_d10_rhoW_14 = sp),
                       crises = lapply(seq_len(nrow(D)), function(i) as.list(D[i]))), auto_unbox = TRUE, pretty = TRUE, digits = 6, Date = "ISO8601"),
           file.path(OUT, "crisis_type_asof.json"), useBytes = TRUE)
print(show); cat("\n", verdict, "\n")
