#==============================================================================
# test_strategy_role.R — 역할 계약 양방향 검사 (2026-10-07)
#   정본 벤치·국면(실데이터)에 합성 전략 수익을 얹어 sr_card 를 구동한다(운영 레지스트리를 쓰지 않는다).
#   N1 순수 베타(β 0.8 · 잡음 0)      → 방어·공격·반등 B+ 아님 (구 '하락월 초과' 는 여기서 B+ 였다 = 베타 착시)
#   P1 약세장 초과(ps_bear 달 +1.5%/월) → defensive B+ · offensive 아님
#   P2 강세장 초과(비약세 달 +1.5%/월)  → offensive B+ · defensive 아님
#   N2 무상관 잡음 50판                  → 방어 B+ 비율 ≤ 10% (명목 5% 근방)
#   S1 60개월 미만                       → status too_short
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
root <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(root, "02_Infrastructure/contracts/strategy_role.R"))
cfg <- sr_cfg(root); E <- .sr_env; dcfg <- E$rfd_cfg(root)
bm <- E$rfd_bench_daily(root, dcfg); R <- sr_regimes(bm)
bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))][ym >= "2005-03" & ym <= "2026-08"]
bmm <- merge(bmm, R, by = "ym")
pass <- 0L; fail <- 0L
ck <- function(name, ok) { if (isTRUE(ok)) { pass <<- pass + 1L; cat("PASS", name, "\n") } else { fail <<- fail + 1L; cat("FAIL", name, "\n") } }
card <- function(r) sr_card(data.table(ym = bmm$ym, r = r, b = bmm$b, ew = NA_real_), R, cfg)
bplus <- function(cd, role) cd$roles[[role]]$grade %in% c("A", "B")
set.seed(7)
eps <- function(s = 0.01) rnorm(nrow(bmm), 0, s)
c1 <- card(0.8 * bmm$b + eps(0.005))
ck("N1 pure beta: defensive not B+", !bplus(c1, "defensive"))
ck("N1 pure beta: offensive not B+", !bplus(c1, "offensive"))
ck("N1 pure beta: rebound not B+", !bplus(c1, "rebound"))
c2 <- card(0.8 * bmm$b + ifelse(bmm$ps_bear, 0.015, 0) + eps(0.01))
ck("P1 bear excess: defensive B+", bplus(c2, "defensive"))
ck("P1 bear excess: offensive not B+", !bplus(c2, "offensive"))
c3 <- card(0.8 * bmm$b + ifelse(!bmm$ps_bear, 0.015, 0) + eps(0.01))
ck("P2 bull excess: offensive B+", bplus(c3, "offensive"))
ck("P2 bull excess: defensive not B+", !bplus(c3, "defensive"))
fp <- mean(vapply(1:50, function(i) bplus(card(0.8 * bmm$b + eps(0.02)), "defensive"), logical(1)))
ck(sprintf("N2 noise defensive B+ rate %.2f <= 0.10", fp), fp <= 0.10)
c5 <- sr_card(data.table(ym = head(bmm$ym, 40), r = head(bmm$b, 40), b = head(bmm$b, 40), ew = NA_real_), R, cfg)
ck("S1 too_short", identical(c5$status, "too_short"))
cat(sprintf("FINAL: %d pass / %d fail / %d total\n", pass, fail, pass + fail))
if (fail) quit(status = 1)
