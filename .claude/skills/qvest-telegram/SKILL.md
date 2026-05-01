---
name: qvest-telegram
description: QEPM Telegram 브리핑 v5 ENFORCE 모바일 가독성. tg_agent_brief() 단일 진입점. 직접 호출 금지 (PreToolUse Hook 차단).
---

# Qvest Telegram Skill

**v5 ENFORCE 발효**: 2026-04-30 (L-260) / Session 75 v6.4 skill 분리

## 7대 규칙 (Level 0)

1. **이모지 필수**: 모든 메시지에 맥락 이모지 5+ 포함
2. **차트 필수**: 백테스트 결과 발송 시 PNG 첨부 (`charts=c(...)` 인자)
3. **한글**: 모든 메시지 한글 기본 + 사용자 이름 미사용 (텔레그램 제3자 채널)
4. **가독성 v5**:
   - **표 ncol ≤ 3** + **total_width ≤ 32** (모바일 한 줄)
   - 줄바꿈/엔터 자동 (마침표 + 공백 → 엔터)
   - 줄글 나열 금지
5. **에이전트 태그**: 메시지 첫 줄에 `[Alpha/Risk/Optimizer/Forge/Judge/Governor/Q-Lead]` 태그
6. **성과 필수 포맷**: 시니컬 + 유머 톤 (도훈 명시). 전문 용어 1줄 풀이 + 비유 + 결정 위주
7. **API**: `tg_agent_brief()` 단일 진입점만 (`tg_send` 직접 호출 금지 — Hook L3 차단)

## Hard Validation (`tg_agent_brief()` 자체 stop())

- `bytes ≥ 1200`
- `sections ≥ 4`
- 표 `ncol ≤ 3`
- 표 `total_width ≤ 32`

위반 시 `stop()` 발생 + Hook deny.

## Section Type 5종

| type | 의무 |
|---|---|
| `text` | body ≥ 50자 |
| `bullet` | items ≥ 3 |
| `kv` | named list 길이 ≥ 3 |
| `table` | df nrow ≥ 2 + ncol ≥ 2 + ncol ≤ 3 |
| `code` | body ≥ 20자 |

## 이모지 자동 추천 (heading 키워드)

- risk / 리스크 / flag → 🚩
- challenge / 반론 → ⚔️
- stress / 위기 / regime / crisis → 🌪️
- alert / 경보 / alarm → 🚨
- insight / 핵심 / 발견 / finding → 💡
- method / 방법 / 비교 / covariance → 🔬
- hedge / overlay / beta / β → 🛡️
- config / 설정 / 제약 / option → 🎛️
- performance / 성과 / SR / CAGR / MDD → 📈
- integration / 통합 / mapping → 🔗
- new / latest / 최신 → ✨
- reference / 참조 / 논문 → 📚
- shortlist / ranking / top → 🏆

(default: 📊)

## 사용 예

```r
source("02_Infrastructure/telegram/telegram_notify.R")

sections <- list(
  list(
    heading = "성과 요약",
    type = "kv",
    emoji = "📈",
    kv = list("SR" = 1.55, "CAGR" = "30.8%", "MDD" = "-28.1%")
  ),
  list(
    heading = "Risk Flags",
    type = "table",
    df = data.frame(Flag = c("RF-R3", "RF-R5"), Sev = c("HIGH", "HIGH")),
    max_col_width = 18L
  ),
  list(
    heading = "분석",
    type = "text",
    body = "BHEQ alpha-vector cor 0.05 vs returns level 0.717. predecessor full-sample lookahead -31% inflation 정량 증거 확보. v6.4 cert eligibility 강화 candidate. (50+ 자)"
  ),
  list(
    heading = "결정",
    type = "bullet",
    items = c("BHEQ 보류", "Iter 9 family pivot", "v6.4 patch 진행")
  )
)

result <- tg_agent_brief(
  agent = "Q-Lead",
  title = "Session N 종합",
  sections = sections,
  footer = "📚 SOT links",
  emoji_min = 5L,
  force = FALSE
)
# result$ok == TRUE / bytes 1200~4000 / ok=TRUE 검증
```

## Single-Dispatch Lock

같은 agent + title prefix 중복 호출 차단 (Forge 2번 발송 사례 방지).
- `lock_scope` NULL이면 자동: `agent + WT-id` 또는 `agent + title 첫 40자`
- `force=TRUE` 로 override 가능

## 채널

- Bot: `@quant12323413245_bot`
- Channel: `-1003850915447`

## 참조

- `02_Infrastructure/telegram/telegram_notify.R::tg_agent_brief()` (line 598+)
- `tg_format_table()` (mobile fit auto-truncate)
- L-260 (v5 enforce 사례)
