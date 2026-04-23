---
name: telegram-protocol
description: QEPM 3-Agent Telegram 브리핑 프로토콜 v2. Alpha/Risk/Optimizer/Forge/Judge/Governor 산출물을 이모지 + 가독성 높은 포맷으로 자동 발송. parse_mode 기본값 plain (HTML parse error 방지). 차트 자동 첨부 (tg_send_photo).
---

# Telegram Protocol v2 — QEPM 3-Agent Briefing

QEPM 3-Agent Work Task 산출물을 Telegram으로 발송하는 표준 포맷.

## Core Function

```r
source("02_Infrastructure/telegram/telegram_notify.R")

tg_send(msg, parse_mode="", silent=FALSE)
tg_send_photo(path, caption="", parse_mode="")
```

**parse_mode 기본값 `""` (plain)** — HTML/Markdown tag 오인 차단. `<15`, `> 0.10` 등 기호 안전.

## Agent별 브리핑 템플릿

### 🧠 Alpha Agent 완료
```
[Alpha Agent] 🧠 α̂ 생성 완료 — WT{id}
━━━━━━━━━━━━━━━━━
🎯 Hypothesis: {task_title}
📊 Alpha 통계
  종목수: {N}
  α̂ 평균: {mean}% / 중앙값: {median}%
  α̂ top 5: {symbols}
📈 Diagnostics
  Rank IC: {rank_ic} ✅
  ICIR: {icir}
  Monotonicity: {monotonicity}
  Subperiod stability: {stability}
  Turnover proxy: {to}%
📚 Factor specs ({K}개)
  · {family_1} / {proxy_1} — {rationale}
  · {family_2} / {proxy_2} — {rationale}
⚠️ Challenge flags: {count}
➡️ Next: Risk Agent spawn
```

### 🛡️ Risk Agent 완료
```
[Risk Agent] 🛡️ Σ 추정 완료 — WT{id}
━━━━━━━━━━━━━━━━━
📐 Covariance 구조
  Σ = BΩB' + D ({method})
  Condition number: {cn}
  Shrinkage: {shrinkage_method}
🔥 Top common risks
  {rank_1}: {pct}% | {rank_2}: {pct}% | {rank_3}: {pct}%
📊 Stress tests
  Market -5%: {loss_1}
  Value crash: {loss_2}
  Momentum reversal: {loss_3}
⚠️ Warnings
  Crowding: {crowding_flags}
  Liquidity: {liquidity_flags}
➡️ Next: Optimizer Agent spawn
```

### ⚖️ Optimizer Agent 완료
```
[Optimizer Agent] ⚖️ Weights 결정 완료 — WT{id}
━━━━━━━━━━━━━━━━━
🎯 Method selected: {method} (SR 최대)
📊 Portfolio
  종목수: {N} / 20 ✅
  Weight bounds: [{min}, {max}] ✅
  Σw: {sum} ✅
📈 Expected performance
  Active return: {ar}%
  Tracking error: {te}%
  Information Ratio: {ir}
  Turnover: {to}%
  Cost: {cost}%
🏆 Method comparison (IR)
  1. {method_1}: {ir_1}
  2. {method_2}: {ir_2}
  3. {method_3}: {ir_3}
🔝 Top overweights: {top_names}
🔻 Top underweights: {bottom_names}
⚠️ Binding constraints: {constraints}
➡️ Next: Forge integrate → Judge
```

### 🏁 Work Task 완주 (Governor admission 후)
```
[Q-Lead] 🏁 WT{id} 완주 — {hypothesis_title}
━━━━━━━━━━━━━━━━━
📊 최종 성과 (전기간)
  CAGR: {cagr}% {emoji}
  Sharpe: {sr} {emoji}
  MDD: {mdd}% {emoji}
  Turnover: {to}%
🎯 vs Benchmark
  Active return: {ar}%
  IR: {ir}
  Tracking error: {te}%
🛡️ Stress 구간 (AX-001 v2)
  GFC 2008: {alpha_1}pt
  EuDebt 2011: {alpha_2}pt
  COVID 2020: {alpha_3}pt
  Rate 2022: {alpha_4}pt
🏆 3-Agent method
  Alpha: {alpha_method}
  Risk: {risk_method}
  Optimizer: {optimizer_method}
📋 Gate status (Judge S6)
  Gate 0 PIT: ✅ / Gate 4 Harvey t: {t_stat}
  Gate 8 AX-001 v2: {audit_result}
📈 Governor 판정: {pg_verdict}
```

## 이모지 매핑 (표준)

**Agent**:
- Alpha: 🧠 (brain)
- Risk: 🛡️ (shield)
- Optimizer: ⚖️ (balance)
- Forge: 🔨 (hammer)
- Judge: ⚖️ (justice)
- Governor: 👑 (crown)

**Status**:
- Success: ✅ / Fail: ❌ / Warn: ⚠️ / Info: ℹ️
- Progress: 🔄 / Pending: ⏳ / Block: 🚧

**Performance**:
- SR ≥ 2.0: 🚀 / 1.5~2.0: ✨ / 1.0~1.5: ✅ / less than 1.0: ⚠️
- MDD less than 20%: ✅ / 20~35%: ⚠️ / greater than 35%: ❌
- CAGR ≥ 16%: 🎯 / 10~16%: ✅ / less than 10%: ⚠️

**Regime**:
- CRISIS 🚨 (60 이상) / STRESS 🔥 (40~60) / CAUTION 🟡 (25~40)
- NORMAL 🟢 (15~25) / EASY 💚 (15 미만)

**Sections**:
- 📊 (수치) / 📈 (상승) / 📉 (하락) / 🎯 (목표)
- 🔥 (집중) / ⚠️ (경고) / 📚 (참조) / 🏆 (비교)

## 가독성 규칙

1. **첫 줄 필수**: `[Agent] {이모지} {액션} — WT{id}`
2. **구분선 항상**: `━━━━━━━━━━━━━━━━━`
3. **섹션 이모지**: 매 섹션 시작에 맥락 이모지
4. **비교 1./2./3.** 순위 명시
5. **긴 수치 대신 차트**: `tg_send_photo()` 자동 호출 (equity_curve / annual_returns / regime heatmap)

## 특수문자 안전 규칙

**HTML/Markdown 충돌 회피**:
- `<15` → `15 미만` 또는 `less than 15`
- `> 0.10` → `0.10 초과` 또는 `greater than 0.10`
- `*weight*` → `weight` (굵은 글씨 피하기)
- `_confidence_` → `confidence`

**Escape 대상** (꼭 써야 할 경우):
- `<` → `&lt;`
- `>` → `&gt;`
- `&` → `&amp;`

**plain mode 사용 권장** (parse_mode=""):
- 이모지 + 한글 + 숫자 조합은 모두 안전
- 단, `<`, `>` 문자열 포함 시 주의

## 차트 자동 첨부

3-agent WT 산출물에 차트 필수 포함:
- Alpha: IC time series / decile monotonicity bar
- Risk: covariance heatmap / stress loss bar chart
- Optimizer: method_comparison bar / weight distribution pie
- Judge: equity_curve / annual_returns
- Governor: regime matrix 4×5 / PG0 gap vector chart

```r
tg_send(msg, parse_mode="")
tg_send_photo(chart_path, caption="📊 {context}")
```

## L-code Integration

L-code 신규 발행 시 자동 브리핑:
```
[Q-Lead] 📚 L-code 신규 발행 — L-{id}
━━━━━━━━━━━━━━━━━
🎯 Type: {type} (methodological/empirical)
📝 Rule: {lesson_text}
🔗 Core reference: {core_reference}
🏷️ Tags: {tags}
```

## 발송 레이트 제한

- Telegram API: 초당 30건
- WT 산출물은 agent당 1건 브리핑 (과도 금지)
- 긴급 알림 (Hook block / CRITICAL red flag)만 즉시, 나머지는 batch

## Version

- **v1.0** (2026-04-10) — 기존 단일 전략 브리핑 포맷
- **v2.0** (2026-04-23) — QEPM 3-Agent WT 포맷 + parse_mode 기본값 "" + 이모지 매핑 확장
