---
name: telegram-protocol
description: "QEPM Telegram 브리핑 v3 — 단일 진입점 tg_agent_brief() 강제. 모든 agent (Alpha/Risk/Optimizer/Forge/Judge/Governor/Q-Lead)는 이 함수 외 직접 조립 금지. auto_escape + auto_sanitize + emoji + Single-Dispatch + 모바일 guard 자동."
---

# Telegram Protocol v3 — Single Entry Point SOT

**2026-04-24 전면 재작성**. 반복 발생한 렌더 깨짐 (HTML entity / CJK width / raw 부등호 / Single-Dispatch 위반)을 **단일 함수로 수렴** 시켜 영구 해결.

## 절대 규칙 (Level 0)

**모든 agent + Q-Lead + Scout은 `tg_agent_brief()` 함수만 사용한다.**

- ❌ 직접 `tg_send_rich(msg)` 조립 금지
- ❌ 직접 `tg_format_table()` + `paste0(...)` 조립 금지
- ❌ `tg_send(msg, parse_mode="HTML")` 수동 호출 금지
- ✅ `source("02_Infrastructure/telegram/telegram_notify.R")` → `tg_agent_brief(...)`만

이유: 반복 오류의 공통 근원은 caller가 sanitize/escape를 놓치는 것. 단일 함수가 전부 자동 처리.

## 함수 시그니처

```r
tg_agent_brief(
  agent = "Alpha",    # Alpha/Risk/Optimizer/Forge/Judge/Governor/Q-Lead/Scout/Execution/Monitoring
  title = "WT-D... 완료",
  as_of = "2026-04-24",
  sections = list(...),   # named list of section dicts (아래 참조)
  charts = NULL,          # optional char vector of PNG paths (text 후 이어서 발송)
  footer = NULL,          # optional "➡️ Next: ..." 스타일
  emoji_min = 5L,         # minimum emoji count
  dry_run = FALSE         # TRUE면 cat만 하고 미발송 (테스트용)
)
```

Return: `list(ok=TRUE/FALSE, bytes=int, error=NULL/str)`. `ok=FALSE`면 `/tmp/qvest_tg_brief.log` 참조.

## 섹션 스키마 (4 type)

### `type = "table"` — 표 섹션
```r
list(emoji = "🔬",
     heading = "Covariance 자율 비교",
     type = "table",
     df = data.frame(Estimator=c(...), Cond=c(...), stringsAsFactors=FALSE),
     max_col_width = 15L,       # default 18
     notes = c("Primary: LW Oracle", "Backup: Sample"))  # optional bullet
```

### `type = "text"` — 서술 섹션
```r
list(emoji = "💡",
     heading = "핵심 발견",
     type = "text",
     body = paste0(
       "<b>A PRIMARY</b> 설명\n",
       "  상세 포인트"))
```
body 내 `<b>` `<code>` `<pre>` 등 Telegram HTML 태그 유효. raw `<`, `>`, `&`는 sanitize가 자동 escape.

### `type = "bullet"` — 글머리 목록
```r
list(emoji = "🚩",
     heading = "Red Flags",
     type = "bullet",
     items = c("RF-R1 HIGH: market 60.9%",
               "RF-R2 WARN: condition 11"))
```

### `type = "code"` — 여러 줄 코드 블록
```r
list(emoji = "📋",
     heading = "수식",
     type = "code",
     body = "max w'α - (λ/2)·w'Σw\nsubject to Σw=1")
```

## 자동 처리 (caller가 신경 쓸 필요 없음)

| 처리 | 자동화 계층 |
|---|---|
| CJK width 정확 (한글 2칸) | `tg_format_table` v2 |
| `<`, `>`, `&` auto_escape (표) | `tg_format_table` v3 |
| `&quot;` entity 제거 | `tg_send_rich` v3 auto_sanitize |
| plain text raw `<40` 자동 escape | `tg_send_rich` v4 auto_sanitize |
| 유효 HTML 태그 보존 (`<b>`, `<code>`, `<pre>` 등) | regex whitelist |
| 모바일 width guard (>40 WARN) | `tg_format_table` v2 |
| emoji 최소 개수 검증 | `tg_send_rich` validate_emoji |
| 4096 bytes 제한 경고 | `tg_agent_brief` |
| 실패 시 로그 + return | `tg_agent_brief` |

## Single-Dispatch 원칙 (v2.2 계승)

**Agent 1 spawn = `tg_agent_brief` 1 호출.**
- Step 1/2/3 중간 진행 발송 금지
- 모든 산출물 write + status.json 전환 **직전** 단일 호출
- charts 여러 장은 OK (`charts=c(path1, path2)`)
- 예외 없음

## 표준 사용법 (Agent 실전 예시)

### Alpha Agent 완료
```r
source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260424_003 α̂ 생성 완료",
  as_of = "2026-04-24",
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics", type = "table",
         df = data.frame(
           Metric = c("rank_IC", "ICIR", "Harvey t", "Subperiod"),
           Value = c("0.0318", "0.180", "4.42", "3/3"),
           stringsAsFactors = FALSE),
         max_col_width = 14L),
    list(emoji = "💡", heading = "핵심 발견", type = "text",
         body = "CAPM retention 97.4%. HEDGE_COMPATIBLE."),
    list(emoji = "🚩", heading = "Challenge Flags", type = "bullet",
         items = c("rank_IC HIGH", "Market risk HIGH", "DSR MEDIUM"))
  ),
  footer = "➡️ Next: Risk Agent spawn",
  emoji_min = 5L
)
```

### Judge Agent 심사 완료 (차트 포함)
```r
tg_agent_brief(
  agent = "Judge",
  title = "WT-D... Grade C CONDITIONAL_PROGRESS",
  sections = list(
    list(emoji = "📊", heading = "Gate A~F", type = "table",
         df = data.frame(Gate=c("A","B","C"), Result=c("PASS","PASS","FAIL"))),
    list(emoji = "💡", heading = "핵심", type = "text",
         body = "Breadth cannot save weak alpha.")
  ),
  charts = c("stage_artifacts/WT_X/equity_curve_full.png",
             "stage_artifacts/WT_X/equity_curve_oos.png"),
  footer = "📚 L-193 등재"
)
```

## Agent 이모지 매핑 (자동)

| Agent | 이모지 |
|---|---|
| Alpha | 🔬 |
| Risk | 🛡️ |
| Optimizer | ⚖️ |
| Forge | 🔨 |
| Judge | ⚖️ |
| Governor | 👑 |
| Q-Lead | 🎯 |
| Scout | 📚 |
| Execution | 🎬 |
| Monitoring | 📡 |

## 이모지 규칙 v3.1 (2026-04-24, tg_agent_brief 통합)

### 섹션 이모지 자동 추천 (heading keyword 기반)

`sections[i]$emoji` 미지정 시 `tg_agent_brief` 가 heading 키워드로 자동 추론:

| Heading keyword | 자동 이모지 | 용도 |
|---|---|---|
| risk / 리스크 / flag | 🚩 | Red flag 섹션 |
| challenge / 반론 | ⚔️ | Challenge loop (P4) |
| stress / 위기 / regime / crisis | 🌪️ | Stress test / regime 분석 |
| alert / 경보 | 🚨 | 긴급 alert |
| insight / 핵심 / 발견 | 💡 | Key insight |
| method / 방법 / 비교 / estimator | 🔬 | Method shopping log / 비교 |
| hedge / overlay / beta / β | 🛡️ | Hedge overlay |
| config / 설정 / 제약 / constraint | 🎛️ | Configuration |
| performance / 성과 / IR / SR / CAGR / MDD | 📈 | Performance metrics |
| integration / 통합 / mapping | 🔗 | 통합/매핑 |
| latest / 최신 / supplement | ✨ | 신규/최신 |
| reference / 참조 / 논문 | 📚 | 문헌 |
| shortlist / ranking / top | 🏆 | 순위 |
| test / 검증 | 🧪 | 테스트 |
| audit / 검사 | 🛠️ | 감사 |
| next / action / 계획 | ➡️ | 다음 단계 |
| compare / vs | 🔍 | 비교 |
| gate / verdict / 판정 | ⚖️ | Judge gate |
| lockbox / oos / seal | 🔒 | Lockbox OOS |
| diagnosis / 진단 | 📊 | 진단 (default metrics) |

### Status 이모지 (helper: `tg_emoji("status", key)`)

| Key | Emoji | 의미 |
|---|---|---|
| pass | ✅ | Pass |
| fail | ❌ | Fail |
| warn | ⚠️ | Warning |
| info | ℹ️ | Info |
| progress | 🔄 | In progress |
| pending | ⏳ | Pending |
| block | 🚧 | Blocked |
| cond | 🟡 | Conditional |
| mixed | 🔵 | Mixed |

### Verdict 자동 이모지 (helper: `tg_emoji_verdict(char_vector)`)

문자열 내 keyword 매칭으로 자동 emoji 반환. **우선순위**: COND → MIXED → BLOCK → PASS → FAIL → WARN → INFO → PENDING.

```r
tg_emoji_verdict(c("PASS","FAIL","CONDITIONAL_FAIL","MIXED_PASS"))
# → c("✅","❌","🟡","🔵")
```

표 내 Verdict column 자동 emoji 가공:
```r
df <- data.frame(Gate = c("A","B","C"), Verdict = c("PASS","FAIL","CONDITIONAL_FAIL"))
df$E <- tg_emoji_verdict(df$Verdict)
```

### Performance Grade 자동 이모지 (helper: `tg_emoji_perf(sr, mdd, cagr)`)

수치 → 이모지 자동 매핑. 기준:

| Metric | Thresholds | Emojis |
|---|---|---|
| SR | ≥2.0 / ≥1.5 / ≥1.0 / <1.0 | 🚀 / ✨ / ✅ / ⚠️ |
| MDD (abs) | <20% / <35% / ≥35% | ✅ / ⚠️ / ❌ |
| CAGR | ≥16% / ≥10% / <10% | 🎯 / ✅ / ⚠️ |

```r
e <- tg_emoji_perf(sr = 1.337, mdd = -0.37, cagr = 0.09)
# → list(sr="✅", mdd="❌", cagr="⚠️")
```

### Regime 자동 이모지 (helper: `tg_emoji_regime(score)`)

MRS score (0~100) → 이모지:

| Score | Emoji | 의미 |
|---|---|---|
| ≥60 | 🚨 | CRISIS |
| 40~60 | 🔥 | STRESS |
| 25~40 | 🟡 | CAUTION |
| 15~25 | 🟢 | NORMAL |
| <15 | 💚 | EASY |

```r
tg_emoji_regime(63.1)  # → "🚨"
```

### 표 Verdict column 패턴 (권장)

Verdict 있는 표는 helper로 emoji 자동 추가:
```r
gates <- data.frame(
  Gate    = c("A PIT","B ISO","C Alpha","D Crowd"),
  Verdict = c("PASS","PASS","CONDITIONAL_FAIL","FAIL"),
  stringsAsFactors = FALSE
)
gates$Mark <- tg_emoji_verdict(gates$Verdict)
# tg_agent_brief 에 df로 전달
```

### Emoji 최소 개수 (검증)

- `emoji_min = 5L` default (`tg_agent_brief`)
- 다양성 권장: Agent 태그 1 + Section heading 3~5 + Status/Performance 1~3 = 5+ 자연스럽게 충족
- 위반 시 `[tg_send_rich] WARN emoji count X < min 5` + `/tmp/qvest_tg_emoji_warn.log`

## 위반 시 조치

1. agent 자체 Rscript에서 `tg_send_rich` 또는 `tg_format_table` 직접 호출 감지 시 → Q-Lead가 SendMessage로 시정 지시
2. 반복 위반 시 → prompt에 "오직 tg_agent_brief만" 재주입
3. `tg_agent_brief` 함수 자체의 버그는 `telegram_notify.R` 내부에서 수정. caller 변경 불필요.

## 폐기 (legacy, 2026-04-24)

- v1.0 (2026-04-10) — 단일 전략 브리핑 포맷 (참조용 archive)
- v2.0 (2026-04-23) — 3-Agent 포맷 수동 조립 (caller가 escape 관리 → 깨짐 반복)

## Version

- **v3.0** (2026-04-24) — 단일 진입점 `tg_agent_brief()` SOT. 모든 caller 수동 조립 금지.

## 관련 파일

- `02_Infrastructure/telegram/telegram_notify.R` — `tg_agent_brief` + helper 전체 구현
- `02_Infrastructure/prompts/_shared_prefix.md` — telegram_protocol section (v2.2 Single-Dispatch + v3 SOT 지시)
- `02_Infrastructure/prompts/{agent}_init.md` — 각 agent prompt 내 "오직 tg_agent_brief()" 규칙
