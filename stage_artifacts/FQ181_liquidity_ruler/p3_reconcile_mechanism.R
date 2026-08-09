## FQ-181 P3 — ① FQ-181 인용치(불일치 2.61% / 상관 0.929) 와의 정합 + ② 방향(net looser) 기전 진단
##
## ★규약: 서로 다른 창·모집단의 수치를 나란히 놓고 '자의 성질'이라 읽지 말 것.
##   FQ-181 이 인용한 2.61% 는 (a) 창이 월말 당일을 **포함**하는 20일 평균이고
##   (b) 모집단이 WT-001 발행 패널이다. 내 P2 는 (a') t-1 창 (b') 전 유니버스다.
##   두 축을 각각 분리 측정해 어디서 갈리는지 못박는다.
##
## read-only. 산출: p3_reconcile.json

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")
LIQ_MIN <- 2e8

R <- as.data.table(read_parquet(".cache/rawdata.parquet",
       col_select = all_of(c("Date","Ticker","Close","Vol","K200","KQ150"))))
R[, Date := as.Date(Date)]
setorder(R, Ticker, Date)
R[, dval := Vol * Close]

## 세 자를 같은 테이블에서 만든다 (모집단·창 교락 제거)
R[, adv20_incl := frollmean(dval, n = 20L, align = "right"), by = Ticker]      # 당일 포함 (FQ-181 인용 변형)
R[, adv20_t1   := shift(frollmean(dval, n = pmin(seq_len(.N), 20L),
                                  adaptive = TRUE, na.rm = TRUE), 1L), by = Ticker]  # 교정판
D <- sort(unique(R$Date))
ME <- sort(unname(as.Date(vapply(split(D, format(D, "%Y-%m")), function(v) as.character(max(v)), character(1)))))

M <- R[Date %in% ME, .(Date, Ticker, K200, KQ150, Vol, dval,
                       adv1 = dval, adv20_incl, adv20_t1)]
U <- M[(K200 == TRUE | KQ150 == TRUE)]

cat("=== ① 자 변형별 대조 (동일 모집단: K200|KQ150 전 유니버스, 동일 창) ===\n")
cmp_pair <- function(a, b, lab) {
  ok <- !is.na(a) & !is.na(b)
  A <- a[ok]; B <- b[ok]
  pa <- A >= LIQ_MIN; pb <- B >= LIQ_MIN
  list(label = lab, n = sum(ok),
       pearson = cor(A, B), spearman = cor(A, B, method = "spearman"),
       disagree_pct = 100 * mean(pa != pb),
       a_only_pct = 100 * mean(pa & !pb), b_only_pct = 100 * mean(!pa & pb))
}
r1 <- cmp_pair(U$adv1, U$adv20_incl, "구판(1일치)  vs  20일평균(당일 포함)")
r2 <- cmp_pair(U$adv1, U$adv20_t1,   "구판(1일치)  vs  20일평균(t-1, 교정판)")
r3 <- cmp_pair(U$adv20_incl, U$adv20_t1, "20일(당일포함) vs 20일(t-1)  ← shift 단독 효과")
for (r in list(r1, r2, r3))
  cat(sprintf("  %-42s n=%s pearson=%.4f spearman=%.4f 불일치=%.3f%% (A만통과 %.3f%% / B만통과 %.3f%%)\n",
              r$label, format(r$n, big.mark=","), r$pearson, r$spearman,
              r$disagree_pct, r$a_only_pct, r$b_only_pct))

cat("\n=== ①b 모집단 축: WT-001 발행 패널로 좁히면 (FQ-181 이 인용한 모집단) ===\n")
f <- "stage_artifacts/WT_D20260808_001/alpha_scores.parquet"
panel_res <- NULL
if (file.exists(f)) {
  P <- as.data.table(read_parquet(f))
  dcol <- intersect(c("Date","date","Factor_Date"), names(P))[1]
  P[, ym := format(as.Date(get(dcol)), "%Y-%m")]
  MM <- copy(M); MM[, ym := format(Date, "%Y-%m")]
  J <- merge(unique(P[, .(Ticker, ym)]), MM[, .(Ticker, ym, adv1, adv20_incl, adv20_t1)],
             by = c("Ticker","ym"), all.x = TRUE)
  q1 <- cmp_pair(J$adv1, J$adv20_incl, "패널: 구판 vs 20일(당일포함)")
  q2 <- cmp_pair(J$adv1, J$adv20_t1,   "패널: 구판 vs 20일(t-1)")
  # FQ-181 이 인용한 '패널의 몇 %가 미달' 축(= 단측)
  n_fail_incl <- sum(!is.na(J$adv20_incl) & J$adv20_incl < LIQ_MIN)
  n_fail_t1   <- sum(!is.na(J$adv20_t1)   & J$adv20_t1   < LIQ_MIN)
  cat(sprintf("  발행 패널 행 %s (매칭 %s)\n", format(nrow(J), big.mark=","),
              format(sum(!is.na(J$adv20_incl)), big.mark=",")))
  for (r in list(q1, q2))
    cat(sprintf("  %-34s n=%s pearson=%.4f spearman=%.4f 불일치=%.3f%%\n",
                r$label, format(r$n, big.mark=","), r$pearson, r$spearman, r$disagree_pct))
  cat(sprintf("  ★단측(패널 중 20일-자 2e8 미달): 당일포함 %d 행 (%.3f%%) / t-1 %d 행 (%.3f%%)\n",
              n_fail_incl, 100*n_fail_incl/nrow(J), n_fail_t1, 100*n_fail_t1/nrow(J)))
  cat("  → FQ-181 인용치(2.61% · 0.929)는 이 (모집단, 자변형) 쌍의 값이다. 내 P2 전-유니버스·t-1 값과 나란히 두고\n")
  cat("    '자의 성질'로 읽지 말 것 — 두 축이 동시에 다르다.\n")
  panel_res <- list(n_rows = nrow(J), incl = q1, t1 = q2,
                    n_fail_incl = n_fail_incl, n_fail_t1 = n_fail_t1)
} else cat("  (발행 패널 부재 — 이 축 측정 불가)\n")

cat("\n=== ② 방향 기전: 교정이 왜 net-looser 인가 ===\n")
U2 <- U[!is.na(adv1) & !is.na(adv20_t1)]
U2[, `:=`(pass_leg = adv1 >= LIQ_MIN, pass_new = adv20_t1 >= LIQ_MIN)]
NEW <- U2[!pass_leg & pass_new]     # 구판 탈락 → 교정 통과
LEG <- U2[pass_leg & !pass_new]     # 구판 통과 → 교정 탈락
cat(sprintf("  교정만 통과 %s 건 / 구판만 통과 %s 건\n",
            format(nrow(NEW), big.mark=","), format(nrow(LEG), big.mark=",")))
cat(sprintf("  [교정만 통과] 월말 당일 Vol==0 비율 = %.1f%%  ·  당일 dval 중앙 %.3g  ·  20일-자 중앙 %.3g\n",
            100*NEW[, mean(Vol == 0, na.rm=TRUE)], NEW[, median(adv1)], NEW[, median(adv20_t1)]))
cat(sprintf("  [구판만 통과] 월말 당일 Vol==0 비율 = %.1f%%  ·  당일 dval 중앙 %.3g  ·  20일-자 중앙 %.3g\n",
            100*LEG[, mean(Vol == 0, na.rm=TRUE)], LEG[, median(adv1)], LEG[, median(adv20_t1)]))
cat(sprintf("  전 유니버스 월말 당일 Vol==0 비율 = %.2f%% (기저)\n", 100*U2[, mean(Vol == 0, na.rm=TRUE)]))
cat(sprintf("  월말 당일 dval 의 변동계수 = %.2f  vs  20일-자 = %.2f  (1일치가 더 시끄럽다)\n",
            U2[, sd(adv1)/mean(adv1)], U2[, sd(adv20_t1)/mean(adv20_t1)]))
cat("  ★해석: 1일치 자는 **잡음이 큰 추정량**이라 양방향으로 오분류한다. 교정은 문턱(2e8)을\n")
cat("    건드리지 않고 추정량만 헌법 정의로 바꾼 것 — 통과 건수 증가는 '제약 완화'가 아니라\n")
cat("    '월말 하루 거래가 없었다는 이유로 유동 종목을 잘못 배제하던 오류의 해소'다.\n")
cat("    ⚠단 이는 **사후 해석이 아니라 검증 대상**이다: 교정이 실제로 비유동 종목을 들이는지는\n")
cat("    구판만 통과(=교정이 조인 쪽) 1,388 건과 대칭으로 봐야 한다 → P4 판정영향에서 확인.\n")

res <- list(
  universe_variants = list(legacy_vs_incl = r1, legacy_vs_t1 = r2, incl_vs_t1_shift_only = r3),
  panel_population = panel_res,
  mechanism = list(
    n_new_only = nrow(NEW), n_legacy_only = nrow(LEG),
    new_only_zero_vol_pct = 100*NEW[, mean(Vol == 0, na.rm=TRUE)],
    legacy_only_zero_vol_pct = 100*LEG[, mean(Vol == 0, na.rm=TRUE)],
    universe_zero_vol_pct = 100*U2[, mean(Vol == 0, na.rm=TRUE)],
    cv_adv1 = U2[, sd(adv1)/mean(adv1)], cv_adv20_t1 = U2[, sd(adv20_t1)/mean(adv20_t1)])
)
write_json(res, file.path(OUT, "p3_reconcile.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p3_reconcile.json\n")
