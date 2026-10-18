## LT 위기 유형 분류 — '전면 급락(systemic)' 대 '분산(dispersed)'(위생 유니버스 일수익만 · 전략 성과 무관 · 보는 창 ≤ τ_D)
##   목적: 판단 Superfan T2 R-20261018-005 C-037 반증 조건 — P2R04 에서 늘 켜진 틸트가 진 깊은 위기 {2008-05~10 · 2020-01~03} 와
##         이긴 깊은 위기 {2011-05~09 · 2021-06~2022-09} 를 전략 성과 없이 시장 자료만으로 가를 수 있는가. 못 가르면 '위기 유형' 기전은 근거를 잃는다.
##   ★이 분류는 P2R04 결과를 본 뒤 세운 질문이다(결과 뒤) — 그래서 측도 · 문턱 · 판정식을 계산 전에 아래에 고정하고, 결과와 무관하게 전부 기록한다.
##   주 측도(계산 전 고정): ρ̄_W = 위기 구간(고점일 ~ 저점일) 일수익의 평균 쌍별 상관(Pollet & Wilson 2010 JFE 96(3) 'Average correlation and
##         stock market returns' · 체계 위험 대리 — Kritzman · Li · Page · Rigobon 2011 JPM 37(4) absorption ratio 와 같은 계열).
##         계산 = 표준화 평균 항등식 ρ̄ = (N · Var_t(mean_i z_it) − 1)/(N − 1) · z = 종목별 구간 내 표준화(모분산) · 표본 = 고점일 위생 멤버(HYG) 중
##         구간 전 거래일 수익이 결측 없는 종목(완전 사례 — 항등식이 정확해지는 조건 · N 기록).
##   보조 측도(기록): D_W = 구간 누적 수익의 횡단면 표준편차 / |횡단면 평균| · 상승 종목 비율(구간 누적 > 0) · 시작 시점 as-of ρ̄(고점일 앞 60거래일 —
##         결합 기전의 전제가 될 수 있는 유일한 형태 · 고점 이후 정보 없음).
##   유형 판정식(계산 전 고정): systemic ⇔ ρ̄_W ≥ 판정 창(고점 ≥ 2005-02-01) LT 위기 ρ̄_W 의 중앙값 · 그 밖 dispersed. 판정 창 앞 위기도 같은 문턱으로 적는다.
##   반증 판정(계산 전 고정 · 주 측도만): 지지 ⇔ min(ρ̄_W[2008-05], ρ̄_W[2020-01]) > max(ρ̄_W[2011-05], ρ̄_W[2021-06]). 네 값의 무작위 순서에서 이 분할이 나올
##         확률 = 1/6 — 지지여도 약한 증거다(위기 4개). 보조 측도는 판정에 쓰지 않는다(갈래 고르기 방지).
##   위기 목록 = P2R03 사전등록 fast_crash_prior 표(LT 20/20 · 2000-01 ~ 2022-12) · 데이터 = mc_load_raw(hygiene = TRUE) · 2022-12-31 까지만 읽는다.
##   실행: Rscript crisis_type_classify.R → 같은 폴더 crisis_type_classify.md · crisis_type_classify.json(P2R05 사전등록 design_inputs · 평가 기록이 읽는다)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
OUT  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/_design_notes")
TAU  <- as.Date("2022-12-31"); JUDGE_FROM <- as.Date("2005-02-01"); ONSET_DAYS <- 60L
SYSTEMIC <- c("2008-05-16", "2020-01-22"); DISPERSED <- c("2011-05-02", "2021-06-25")   # T2 C-037 의 두 묶음(고점일)
source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"))
pre <- fromJSON(file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json"), simplifyVector = FALSE)
T0 <- rbindlist(lapply(pre$fast_crash_prior$table, function(z) {
  k <- strsplit(z$crisis, " → ", fixed = TRUE)[[1]]
  data.table(crisis = z$crisis, peak = as.Date(k[1]), trough = as.Date(k[2]), depth = as.numeric(z$depth %||% NA), fast = isTRUE(z$fast))
}), fill = TRUE)
T0 <- T0[trough <= TAU]
R <- mc_load_raw(ROOT, from = min(T0$peak) - 120, to = TAU, hygiene = TRUE)[, .(Date, Ticker, Ret, HYG)]
stopifnot(max(R$Date) <= TAU)
days <- sort(unique(R$Date))
rho_bar <- function(W) {                         # W = 날짜 × 종목 수익 행렬(완전 사례) → 평균 쌍별 상관(표준화 평균 항등식)
  N <- ncol(W); if (N < 30L || nrow(W) < 10L) return(NA_real_)
  mu <- colMeans(W); s <- sqrt(colMeans(sweep(W, 2, mu)^2)); ok <- s > 0
  Z <- sweep(sweep(W[, ok, drop = FALSE], 2, mu[ok]), 2, s[ok], "/"); N <- ncol(Z)
  zbar <- rowMeans(Z); (N * mean((zbar - mean(zbar))^2) - 1) / (N - 1)
}
panel <- function(d0, d1, cohort) {              # 구간 [d0, d1] · 코호트 종목 · 결측 없는 종목만
  X <- R[Date >= d0 & Date <= d1 & Ticker %in% cohort, .(Date, Ticker, Ret)]
  M <- dcast(X, Date ~ Ticker, value.var = "Ret"); m <- as.matrix(M[, -1, with = FALSE])
  m[, colSums(is.na(m)) == 0L, drop = FALSE]
}
rows <- lapply(seq_len(nrow(T0)), function(i) {
  pk <- T0$peak[i]; tr <- T0$trough[i]
  cohort <- R[Date == pk & HYG %in% TRUE, unique(Ticker)]
  W <- panel(pk, tr, cohort)
  cum <- apply(W, 2, function(r) prod(1 + r) - 1)
  pre_days <- days[days < pk]; d0 <- if (length(pre_days) >= ONSET_DAYS) pre_days[length(pre_days) - ONSET_DAYS + 1L] else NA
  cohort0 <- R[Date == max(pre_days) & HYG %in% TRUE, unique(Ticker)]
  W0 <- if (is.na(d0)) NULL else panel(d0, max(pre_days), cohort0)
  data.table(crisis = T0$crisis[i], peak = pk, trough = tr, depth = T0$depth[i], fast = T0$fast[i],
             window = ifelse(pk >= JUDGE_FROM, "판정 창", "판정 창 앞"),
             n_days = nrow(W), n_names = ncol(W), rho_W = rho_bar(W),
             disp_ratio = sd(cum) / abs(mean(cum)), up_share = mean(cum > 0), ew_cum = mean(cum),
             rho_onset60 = if (is.null(W0)) NA_real_ else rho_bar(W0), n_onset = if (is.null(W0)) NA_integer_ else ncol(W0))
})
D <- rbindlist(rows)
thr <- median(D[window == "판정 창", rho_W])
D[, type := ifelse(rho_W >= thr, "systemic", "dispersed")]
g <- function(p) D[peak == as.Date(p), rho_W]
sys_v <- vapply(SYSTEMIC, g, numeric(1)); dis_v <- vapply(DISPERSED, g, numeric(1))
supported <- isTRUE(min(sys_v) > max(dis_v))
setorder(D, peak)
md <- function(X) c(paste0("| ", paste(names(X), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(X))),
                    apply(X, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |")))
show <- D[, .(crisis, window, depth = sprintf("%.3f", depth), fast, n_days, n_names, rho_W = sprintf("%.3f", rho_W), type,
              disp_ratio = sprintf("%.2f", disp_ratio), up_share = sprintf("%.2f", up_share), ew_cum = sprintf("%+.3f", ew_cum),
              rho_onset60 = sprintf("%.3f", rho_onset60))]
verdict <- sprintf("%s — 전면 급락 묶음 ρ̄_W(2008-05 %.3f · 2020-01 %.3f) %s 분산 묶음(2011-05 %.3f · 2021-06 %.3f) · 무작위 확률 1/6",
                   if (supported) "지지(주 측도가 두 묶음을 가름)" else "반증(주 측도가 두 묶음을 못 가름 — '위기 유형' 기전 근거 상실)",
                   sys_v[1], sys_v[2], if (supported) ">" else "≯", dis_v[1], dis_v[2])
writeLines(c("# LT 위기 유형 — 전면 급락 대 분산(위생 유니버스 일수익만 · 2000-01 ~ 2022-12 · 2026-10-18)", "",
             "- 주 측도 ρ̄_W = 위기 구간 평균 쌍별 상관(고점일 위생 멤버 · 구간 결측 없는 종목 · 표준화 평균 항등식). 유형 = ρ̄_W ≥ 판정 창 LT 위기 중앙값이면 systemic.",
             sprintf("- 문턱(판정 창 7위기 중앙값) = %.3f", thr),
             "- 보조(판정 아님): disp_ratio = 구간 누적 수익 횡단면 표준편차 / |평균| · up_share = 구간 누적 > 0 종목 비율 · rho_onset60 = 고점일 앞 60거래일 ρ̄(as-of).",
             "- ★결과 뒤 질문(P2R04 위기별 결과를 본 뒤) — 측도 · 문턱 · 판정식은 계산 전 스크립트 머리에 고정. 위기 4개라 지지여도 약한 증거(1/6).", "",
             md(show), "", paste0("- 반증 판정(판단 T2 C-037): ", verdict)),
           file.path(OUT, "crisis_type_classify.md"), useBytes = TRUE)
writeLines(toJSON(list(source = "crisis_type_classify.R(위생 유니버스 일수익 · ≤ 2022-12-31 · 전략 성과 무관)",
                       use = "기록 전용 — 신호 · 선택 · 판정 입력 금지(rho_W · type 은 저점까지의 구간 정보 = 위기 시작 시점에는 알 수 없다 · C1/C3) · as-of 로 쓸 수 있는 것은 rho_onset60 뿐",
                       rule = sprintf("systemic iff rho_W >= median(rho_W over LT crises with peak >= %s) = %.4f · rho_W = average pairwise correlation of daily returns over [peak, trough] (hygiene members at peak · complete cases)", JUDGE_FROM, thr),
                       falsification = list(rule = "supported iff min(rho_W[2008-05-16], rho_W[2020-01-22]) > max(rho_W[2011-05-02], rho_W[2021-06-25])",
                                            supported = supported, chance = "1/6", note = "결과 뒤 질문 — 위기 4개"),
                       crises = lapply(seq_len(nrow(D)), function(i) list(crisis = paste(D$peak[i], D$trough[i]), window = D$window[i], type = D$type[i],
                         rho_W = D$rho_W[i], disp_ratio = D$disp_ratio[i], up_share = D$up_share[i], rho_onset60 = D$rho_onset60[i], n_names = D$n_names[i]))),
                  auto_unbox = TRUE, pretty = TRUE, digits = 6),
           file.path(OUT, "crisis_type_classify.json"), useBytes = TRUE)
print(show); cat("\n", verdict, "\n")
