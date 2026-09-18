setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp4_defensive_route.R")
d <- wp4_parse_pool()
cat("풀 생성일:", attr(d, "generated"), " 등급 floor:", attr(d, "floor"), "\n")
cat("모듈", nrow(d), "· 경로:\n"); print(table(d$route, d$grade))

def <- d[d$route == "defensive_specialist", ]
cat("\n=== 방어형 경로", nrow(def), "건의 근거 파싱 ===\n")
ok <- !is.na(def$down_excess)
cat("  근거 파싱 성공:", sum(ok), "/", nrow(def), "\n")
def <- def[ok, ]
cat(sprintf("  하락월 초과 중앙 %+.2f%%/월 · 전부 양수인가: %s\n",
            median(def$down_excess), all(def$down_excess > 0)))
cat(sprintf("  적중률 중앙 %.0f%% · t 중앙 %.2f\n", median(def$hit, na.rm = TRUE),
            median(def$down_t, na.rm = TRUE)))
cat(sprintf("  상승월 초과 중앙 %+.2f%%/월 (음수면 상승장에서 뒤처진다는 뜻)\n",
            median(def$up_excess, na.rm = TRUE)))

cat("\n=== ★깊은 낙폭(벤치 -10% 이하) 구간에서도 방어했는가 ===\n")
dp <- def[is.finite(def$deep_excess), ]
cat(sprintf("  관측 %d건 · 깊은 낙폭월 수 중앙 %.0f개\n", nrow(dp), median(dp$n_deep, na.rm = TRUE)))
cat(sprintf("  깊은 낙폭 초과 중앙 %+.2f%%/월\n", median(dp$deep_excess)))
cat(sprintf("  **깊은 낙폭에서 벤치보다 못한 모듈: %d / %d (%.0f%%)**\n",
            sum(dp$deep_excess < 0), nrow(dp), 100 * mean(dp$deep_excess < 0)))
q <- quantile(dp$deep_excess, c(0, .25, .5, .75, 1))
cat("  분위:", paste(sprintf("%s=%+.2f", names(q), q), collapse = " · "), "\n")

cat("\n=== 얕은 방어 대 깊은 방어의 상관 ===\n")
set.seed(20260918)
rho <- suppressWarnings(cor(dp$down_excess, dp$deep_excess, method = "spearman"))
bs <- replicate(4000, { i <- sample(seq_len(nrow(dp)), nrow(dp), TRUE)
  suppressWarnings(cor(dp$down_excess[i], dp$deep_excess[i], method = "spearman")) })
ci <- quantile(bs, c(.025, .975), na.rm = TRUE)
cat(sprintf("  Spearman(하락월 초과, 깊은낙폭 초과) = %+.3f  95%%CI [%+.3f, %+.3f] -> %s\n",
            rho, ci[1], ci[2],
            if (ci[1] > 0) "얕은 방어가 깊은 방어를 어느 정도 예측" else
            if (ci[2] < 0) "역방향" else "예측 못 함"))

cat("\n=== 등급 floor 만 썼다면 (방어형 경로 OFF 반사실) ===\n")
cat(sprintf("  풀 %d → %d (%.0f%% 감소) · B 이상만 %d건\n", nrow(d),
            sum(d$route != "defensive_specialist"), 100 * mean(d$route == "defensive_specialist"),
            sum(d$grade %in% c("A", "B"))))
saveRDS(d, "out/wp4_pool.rds")
