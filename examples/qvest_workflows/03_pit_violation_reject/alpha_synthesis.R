# alpha_synthesis.R — Synthetic PIT Violation Example
#
# WARNING: 이 script는 lookahead pattern을 의도적으로 주입한 reference fixture.
# Production 사용 절대 금지. Judge Gate A (PIT C1)에서 자동 차단되는 패턴.

# PIT C1 위반 패턴 (의도적 lookahead injection)
lookahead_model <- lm(future_return ~ today_factor)
# ^^^^^^^^^^^^^^^ 미래 returns를 t 시점 factor로 회귀 — 룩어헤드 명시
# Judge가 이 패턴 감지 시 verdict=FAIL + pit_violations array 작성

# 정상 흐름 (PIT C1 준수 — t-1 lag):
# alpha_t <- z(factor_t_minus_1)
# 실제 production은 위 패턴만 허용

cat("PIT violation injected — Judge Gate A block expected\n")
