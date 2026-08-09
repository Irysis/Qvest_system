## z3 — 7개 연속 축 x 2방향 전수로 Category 재현 축을 찾는다 (처음부터 했어야 할 정체 검사)
## z2 확인: Regime_Score_smooth 상위분위는 Category(RISK_ON) 과 **phi −0.394** = 방향 반대.
## ⇒ 축과 방향을 **전수 탐색**해 재현율 최고를 고른다. 그 축으로만 희석 가설을 검정한다.
## ★재현 기준: phi 상관 및 일치율이 무작위 기대(59.5%)를 뚜렷이 넘어야 대리 축 자격.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[z3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1))
dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
NUM <- c("MSM_Crisis_Prob","FRED_MRS","KTRI_Score","VEA_Score","Regime_Score","Regime_Score_smooth","Cash_Pct")
NUM <- intersect(NUM, names(U))
mo <- U[!is.na(.dd)][order(.dd)][, c(list(cat = last(Category)),
        lapply(.SD, function(x) last(x))), by = .(m = mi(.dd)), .SDcols = NUM]
mo[, m_apply := m + 1L]; mo <- mo[m_apply %in% inc$m]
dom <- names(sort(table(mo$cat), decreasing=TRUE))[1]
mo[, lab := cat == dom]
p <- mean(mo$lab); exp_ag <- p^2 + (1-p)^2
say("=== 기준 === Category '%s' = ON · 발화율 %.1f%% (%d/%d) · 무작위 기대 일치 %.1f%%",
    dom, 100*p, sum(mo$lab), nrow(mo), 100*exp_ag)

say("=== ★7축 x 2방향 전수 (Category 재현율) ===")
say("  %-24s %-8s %10s %10s %10s", "축", "방향", "일치율", "phi", "Jaccard")
rows <- list()
for (c0 in NUM) {
  v <- suppressWarnings(as.numeric(mo[[c0]]))
  if (all(!is.finite(v))) { say("  %-24s (비수치)", c0); next }
  for (dir in c("high","low")) {
    th <- if (dir=="high") quantile(v, 1-p, na.rm=TRUE) else quantile(v, p, na.rm=TRUE)
    lb <- if (dir=="high") v >= th else v <= th
    lb[is.na(lb)] <- FALSE
    ag <- mean(mo$lab == lb)
    ph <- suppressWarnings(cor(as.integer(mo$lab), as.integer(lb)))
    ja <- sum(mo$lab & lb) / max(sum(mo$lab | lb), 1L)
    say("  %-24s %-8s %9.1f%% %+10.3f %10.3f", c0, dir, 100*ag, ph, ja)
    rows[[length(rows)+1L]] <- data.table(axis=c0, dir=dir, agree=ag, phi=ph, jac=ja)
  }
}
R <- rbindlist(rows)
setorder(R, -phi)
best <- R[1]
say("=== ★최적 축 ===")
say("  **%s / %s** — 일치 %.1f%% · phi %+.3f · Jaccard %.3f",
    best$axis, best$dir, 100*best$agree, best$phi, best$jac)
say("  무작위 기대 %.1f%% 대비 %+.1f%%p", 100*exp_ag, 100*(best$agree - exp_ag))
qualified <- best$phi > 0.4 && best$agree > exp_ag + 0.10
say("  대리 축 자격(phi>0.4 ∧ 일치>기대+10%%p): **%s**", qualified)
say("  ⇒ %s", if (qualified)
  "★희석 가설 검정 가능 — 이 축으로 발화율을 조여 재측정한다" else
  paste0("★★**어떤 축·방향도 Category 를 재현하지 못한다**(최고 phi ", sprintf("%.3f", best$phi),
         "). Category 는 이 7축의 단순 문턱이 아니라 **다층 규칙**의 산물이다 — ",
         "생산 코드를 봐야 조일 축을 알 수 있다. 희석 가설은 이 자산으로 **검정 불가** 확정."))

say("=== 참고: Category 와 각 축의 연속 관계 (문턱이 아니라 순위로) ===")
for (c0 in NUM) {
  v <- suppressWarnings(as.numeric(mo[[c0]]))
  if (all(!is.finite(v))) next
  say("  %-24s ON 중앙 %+10.3f vs OFF 중앙 %+10.3f · Wilcoxon p %.4f",
      c0, median(v[mo$lab], na.rm=TRUE), median(v[!mo$lab], na.rm=TRUE),
      suppressWarnings(wilcox.test(v[mo$lab], v[!mo$lab])$p.value))
}
say("  ★단조 관계가 강한 축이 있는데도 문턱 재현이 안 되면 = Category 가 **다변량 규칙**이라는 뜻")
fwrite(R, file.path(OUT,"z3_axis.csv"))
say("=== z3 완료 ===")
