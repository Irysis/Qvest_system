## p8 — ★요구조건 지도: PG2 를 이기려면 정확히 무엇이 필요한가 (해석해 + 실측 대조)
## 2자산 혼합에서 book active = (1-w)*a_i + w*a_s 이므로
##   mean = (1-w)m_i + w*m_s
##   var  = (1-w)^2 s_i^2 + w^2 s_s^2 + 2w(1-w) rho s_i s_s
## IR_book = mean/sd * sqrt(12). incumbent 의 (m_i, s_i) 는 실측 고정.
## 슬리브를 (rho, IR_s) 로 파라미터화하면 ΔIR 이 **닫힌 형태**로 나온다 — 몬테카를로 불필요.
## ★해석해를 합성 시뮬로 교차검증한 뒤 지도를 낸다(둘이 어긋나면 지도가 아니라 내 수식이 틀린 것).
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p8] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- m_i/s_i*sqrt(12)
say("=== incumbent 실측 ===")
say("  active 평균 %+.6f/월 · sd %.6f · IR %.4f (%d개월)", m_i, s_i, ir_i, nrow(inc))

## 슬리브: 변동성을 incumbent 와 같게 두고(k=1) IR 로 평균을 정한다.
## k(=s_s/s_i) 도 지도에 넣는다 — 실측 슬리브들은 변동성이 다르다.
dIR <- function(rho, ir_s, w, k = 1) {
  m_s <- ir_s/sqrt(12) * (k*s_i)
  mu  <- (1-w)*m_i + w*m_s
  v   <- (1-w)^2*s_i^2 + w^2*(k*s_i)^2 + 2*w*(1-w)*rho*s_i*(k*s_i)
  mu/sqrt(v)*sqrt(12) - ir_i
}

say("=== 1. 해석해 vs 합성 시뮬 교차검증 (수식이 맞는지) ===")
set.seed(5)
chk <- function(rho, ir_s, w) {
  e <- rnorm(nrow(inc)); e <- e - as.numeric(lm(e ~ inc$active)$fitted.values); e <- e/sd(e)
  a <- (inc$active - m_i)/s_i
  s <- rho*a + sqrt(1-rho^2)*e; s <- s/sd(s)*s_i + ir_s/sqrt(12)*s_i
  o <- bm_delta_ir(data.table(date = inc$date, ret_net = inc$benchmark_ret + s), weight = w)
  c(analytic = dIR(rho, ir_s, w), sim = o$delta_ir, cor_realized = o$correlation_with_incumbent)
}
for (p in list(c(0.0,1.416,0.20), c(0.4,0.8,0.20), c(0.8,2.0,0.20), c(0.2,0.4,0.10))) {
  r <- chk(p[1], p[2], p[3])
  say("  rho %.1f · IR_s %.2f · w %.2f → 해석 %+.4f vs 시뮬 %+.4f (차 %+.5f · 실현상관 %+.3f)",
      p[1], p[2], p[3], r[1], r[2], r[2]-r[1], r[3])
}

say("=== 2. ★요구조건 지도 — ΔIR>=0.05 를 넘는 최소 슬리브 IR (w=0.20, k=1) ===")
say("  %8s %14s %12s", "rho", "최소 슬리브IR", "달성 가능?")
RHO <- c(-0.3,-0.1,0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9)
map <- list()
for (rho in RHO) {
  f <- function(x) dIR(rho, x, 0.20) - 0.05
  lo <- -1; hi <- 12
  need <- if (f(hi) < 0) NA_real_ else tryCatch(uniroot(f, c(lo,hi))$root, error=function(e) NA_real_)
  say("  %8.1f %14s %12s", rho,
      if (is.na(need)) "불가" else sprintf("%.3f", need),
      if (is.na(need)) "★어떤 알파로도 불가" else if (need <= 1.416) "PG2 이하로도 가능" else "PG2 초과 필요")
  map[[length(map)+1L]] <- data.table(rho=rho, min_ir=need)
}
MP <- rbindlist(map)

say("=== 3. w 민감도 (rho 0.4 고정) ===")
for (w in c(0.05,0.10,0.15,0.20,0.30,0.40,0.50)) {
  f <- function(x) dIR(0.4, x, w) - 0.05
  need <- if (f(12) < 0) NA_real_ else tryCatch(uniroot(f, c(-1,12))$root, error=function(e) NA_real_)
  say("  w %.2f → 최소 슬리브IR %s", w, if (is.na(need)) "불가" else sprintf("%.3f", need))
}

say("=== 4. ★실측 24재료를 지도에 얹기 — 얼마나 모자란가 ===")
D <- fread(file.path(OUT, "p7_overlap.csv"))
say("  실측 상관 범위 %.3f ~ %.3f (중앙 %.3f)", min(D$cor), max(D$cor), median(D$cor))
say("  실측 슬리브IR 범위 %.3f ~ %.3f (중앙 %.3f)", min(D$sleeve_ir), max(D$sleeve_ir), median(D$sleeve_ir))
D[, min_ir_needed := vapply(cor, function(rc) {
  f <- function(x) dIR(rc, x, 0.20) - 0.05
  if (f(12) < 0) NA_real_ else tryCatch(uniroot(f, c(-1,12))$root, error=function(e) NA_real_) }, numeric(1))]
D[, shortfall := min_ir_needed - sleeve_ir]
say("  ★필요 슬리브IR 중앙 %.3f · 실측 중앙 %.3f · **부족분 중앙 %.3f**",
    median(D$min_ir_needed, na.rm=TRUE), median(D$sleeve_ir), median(D$shortfall, na.rm=TRUE))
say("  가장 가까운 3건:")
for (i in order(D$shortfall)[1:3]) say("    %-28s 상관 %+.3f · IR %+.3f · 필요 %.3f · 부족 %.3f",
  substr(D$factor[i],1,28), D$cor[i], D$sleeve_ir[i], D$min_ir_needed[i], D$shortfall[i])

say("=== 5. ★계약 국면규칙은 왜 됐나 (지도 대조) ===")
say("  계약 국면규칙: 상관 +0.140 · 슬리브IR +0.758")
need_c <- uniroot(function(x) dIR(0.140, x, 0.20) - 0.05, c(-1,12))$root
say("  → 상관 0.140 에서 필요 최소 IR = **%.3f** · 실측 0.758 → 여유 %+.3f", need_c, 0.758-need_c)
say("  계약 무조건부: 상관 +0.564 · 슬리브IR +0.281")
need_u <- uniroot(function(x) dIR(0.564, x, 0.20) - 0.05, c(-1,12))$root
say("  → 상관 0.564 에서 필요 최소 IR = **%.3f** · 실측 0.281 → 부족 %+.3f", need_u, 0.281-need_u)
say("  ⇒ ★국면 규칙이 한 일: 상관을 0.564→0.140 으로 낮춰 **문턱 자체를 %.3f→%.3f 로 내렸다**",
    need_u, need_c)

fwrite(MP, file.path(OUT,"p8_requirement_map.csv")); fwrite(D, file.path(OUT,"p8_gap.csv"))
say("=== p8 완료 ===")
