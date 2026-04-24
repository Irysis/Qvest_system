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
