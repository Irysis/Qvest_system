source("02_Infrastructure/contracts/required_effect_size.R")
cat("필요 효과크기 (문턱 t=2.0 · sd 0.0394 · NW k=1.25)\n")
cat(sprintf("%-14s %5s %9s %14s\n","design","n","유효n","필요 연%"))
for (d in c("full","split","interaction")) {
  for (n in c(24,28,40,60,80,163,269)) {
    r <- required_effect(n, design=d)
    cat(sprintf("%-14s %5d %9.1f %13.2f%%\n", d, n, r$effective_n, r$required_annual*100))
  }
}
cat("\n-- verdict_with_power 예시 --\n")
v1 <- verdict_with_power(observed_t=1.2, observed_monthly=0.004, n=28)
cat(" n=28 t=1.2 eff=0.4%/월 ->", v1$verdict, "\n  ", v1$note, "\n")
v2 <- verdict_with_power(observed_t=1.2, observed_monthly=0.030, n=269, design="full")
cat(" n=269 t=1.2 eff=3.0%/월 ->", v2$verdict, "\n  ", v2$note, "\n")
