---
name: qvest-telegram
description: Qvest 텔레그램 발송의 유일한 규칙(SOT). 양식 / 약어 풀이 / Hook 정책 / caller 예시 통합. tg_agent_brief() 단일 진입점만 허용 (직접 호출 시 PreToolUse Hook 차단).
---

# Qvest Telegram Skill — v6 SOT (단일 규칙)

**발효**: 2026-05-07 / 본 파일은 텔레그램 양식의 **유일한 SOT**.
**계보**: v3 → v4 → v5 ENFORCE (2026-04-30, L-260) → **v6 SOT** (가독성 + 단일화).

---

## §1 SOT 선언 (중요)

본 파일이 **Qvest 텔레그램의 유일한 규칙서**.

- R 구현 (`02_Infrastructure/telegram/telegram_notify.R`) → 본 파일 §3 매직 상수와 1:1 동기화
- 모든 caller (agent / prompt / command / strategy R script) → 본 파일 §7 예시 참조
- 분산된 텔레그램 가이드 모두 폐기. 다른 파일은 본 파일 1줄 reference만.

규칙 변경 시 본 파일을 먼저 수정하고 R `.TG_CONFIG`를 동기화. 역방향(R 먼저 수정) 금지.

---

## §2 7대 원칙 (도훈 피드백 2026-05-07 + 2026-05-08)

텔레그램 채널(`-1003850915447`) 외부 구독자가 명료하게 읽을 수 있도록.

| # | 원칙 | 구현 |
|---|---|---|
| **1 ⭐** | **연구 목적 한글 명시 의무 (v6.2 신규)** | 첫 섹션 = 한글 연구 컨텍스트 (목적 + 검토 내용 + 결론 1줄). 영어 약어 라벨만 X |
| 2 | **간결** | 줄글 우겨넣기 금지. 문장 짧게 끊기. `MIN_BYTES=400` 충족이면 OK |
| 3 | **약어 최소** | 본문에서 직접 한글로 풀어 쓰기. 불가피한 약어는 `tg_decode_jargon()` 자동 풀이 |
| 4 | **정통 한글 퀀트 용어** | "샤프지수 / 최대낙폭 / 연복리수익률 / 정보계수 / 다중검정 t값" 등 (Harvey 2016, Lopez de Prado 표기 한글화) |
| 5 | **한글 중심** | 헤딩·본문·결정 문장 한글. 영어는 변수명 / 메트릭 약어 / 출처(논문명)에 한정 |
| 6 | **이모지 활용** | 메시지당 ≥5개 (`EMOJI_MIN`). 섹션마다 1개 의미 emoji + 강조 emoji |
| 7 | **개조식 + 줄바꿈** | 한 문장 한 줄. `tg_text_smart_break()`가 마침표·슬래시·화살표·종결어미에서 자동 줄바꿈 |

### 원칙 1 강제 (v6.2 — 도훈 명시 2026-05-08)

**모든 텔레그램 brief는 첫 섹션에 한글 연구 컨텍스트 의무**:

```r
list(type = "text", emoji = "📚", heading = "연구 컨텍스트",
     body = paste(
       "[연구 목적] 한 줄로 무엇을 검증/발굴/진단하려는지 한글.",
       "[검토 내용] 어떤 데이터·방법·구간을 활용했는지 한글.",
       "[결론 1줄] PASS/FAIL/PARTIAL + 핵심 수치 한글."
     ))
```

또는 `summary` type으로 동일 내용 (≤100자 한글 헤드라인 + 후속 섹션에서 보강).

**Title도 한글 우선**:
- ❌ "WT-D20260508_002 v5 ALPHA_DONE — DISCOVERY_FAIL_HONEST_PIT_PROPER"
- ✅ "변동성 위험 프리미엄 알파 정밀 검증 (정직한 empirical 실패)" 또는
  "ML 기반 4번째 알파 발굴 시도 — PIT-proper 적용 후 실패 입증"

**금지 패턴**:
- title이 영어 약어 / 라벨 / 코드 ID만 (의미 한글 부재)
- summary가 metric 발표만 ("IC 0.291 → 0.0193")
- bullet에 영어 약어 나열 ("Codex 6 path remediation / PIT-rolling factor universe")

**필수 패턴**:
- 첫 섹션 = 외부 구독자가 무엇을 보고 있는지 1초 안에 인지 가능
- 약어 사용 시 한글 풀이 본문 직접 명시 (decode_jargon 자동 풀이 외에도 caller 명시 의무)

---

## §3 Hard Validation (`.TG_CONFIG` 매직 상수)

R `02_Infrastructure/telegram/telegram_notify.R::.TG_CONFIG` list와 1:1 동기화.

**v6.1 (2026-05-08)**: 모바일 짤림 강제 — text/bullet/kv 상한선 추가 + table ncol 2 default.

| Key | 값 | 의미 |
|---|---|---|
| `MIN_BYTES` | **400** | 메시지 최소 바이트 (skeleton 차단) |
| `MIN_SECTIONS` | **2** | 비어있지 않은 섹션 최소 수 |
| `TEXT_MIN` | **30** | `text` body 최소 자수 |
| `TEXT_MAX` | **220** ⭐ v6.1 | `text` body **최대 자수** (모바일 가독). 초과 시 bullet 분할 의무 |
| `BULLET_MIN` | **2** | `bullet` 항목 최소 수 |
| `BULLET_ITEM_MAX` | **80** ⭐ v6.1 | `bullet` 한 항목 **최대 자수** (모바일 한 줄) |
| `KV_MIN` | **2** | `kv` 항목 최소 수 |
| `KV_VALUE_MAX` | **60** ⭐ v6.1 | `kv` 값 **최대 자수** (key 별도 짧게 4~6자 권장) |
| `MAX_NCOL` | **2** ⭐ v6.1 | `table` 최대 열 (v6 3 → v6.1 2, 모바일 짤림 방지) |
| `MAX_TOTAL_WIDTH` | **28** ⭐ v6.1 | `table` 합산 폭 (v6 32 → v6.1 28) |
| `MAX_COL_WIDTH` | **13** ⭐ v6.1 | `table` 개별 열 (v6 20 → v6.1 13) |
| `EMOJI_MIN` | **5** | 메시지당 emoji 최소 개수 |
| `SUMMARY_MIN` | **20** | `summary` type 최소 자수 (1줄 헤드라인) |
| `SUMMARY_MAX` | **100** ⭐ v6.1 | `summary` 최대 (v6 200 → v6.1 100, 1줄 의무) |

위반 시 `tg_agent_brief()` 자체에서 `stop()`. `force=TRUE` 만 명시 우회.

**v6.1 핵심 의무 (caller mandate)**:
- 표 사용 최소화 → `kv` 또는 `bullet` 우선
- 표 사용 시 ncol=2, 한글 column header 4~6자
- bullet 한 항목 80자 이하 (학술 인용 + 정량 + L-code 모두 한 줄에 X — 분할 의무)
- text 220자 초과 시 bullet 분할 (long 섹션 X)

---

## §4 Section Type 6종

| type | 의무 | 용도 |
|---|---|---|
| `summary` ⭐ 신규 | 자수 [`SUMMARY_MIN`, `SUMMARY_MAX`] | 1줄 헤드라인 (heading 없이 굵은 1줄) |
| `text` | body ≥ `TEXT_MIN` 자 | 단락 narrative. `smart_break` 자동 적용 |
| `bullet` | items ≥ `BULLET_MIN` | 결정 / 리스크 / 다음 액션 (개조식) |
| `kv` | named list ≥ `KV_MIN` | 핵심 수치 (메트릭) |
| `table` | nrow ≥ 2, ncol ≥ 2, ncol ≤ `MAX_NCOL`, 폭 ≤ `MAX_TOTAL_WIDTH` | 비교 (≤3 컬럼) |
| `code` | body ≥ 20 자 | 명령어 / 출력 발췌 |

---

## §5 약어 풀이 사전 (`tg_decode_jargon()` 자동 적용)

`tg_agent_brief()`는 default `decode_jargon=TRUE` `decode_mode="inline_first"`. 본문 첫 등장 시 1회 한글 풀이를 괄호로 부착, 이후는 그대로.

### 내부 식별자

| 약어 | 한글 |
|---|---|
| `WT-D{8자리숫자}_{3자리}` | 발견형 작업 (Discovery) |
| `WT-P{8자리숫자}_{3자리}` | 운용형 작업 (Promotion) |
| `STR_{4자리}` | 전략 |
| `AX-{3자리}` | 공리 |
| `L-{2~4자리}` | 교훈 코드 |
| `RF-{알파벳}{숫자}` | 위험신호 |
| `PG{0~3}` | 운용단계 |

### 계량 지표 (정통 한글 — Harvey 2016 / Lopez de Prado)

| 약어 | 한글 |
|---|---|
| `SR` | 샤프지수 |
| `MDD` | 최대낙폭 |
| `CAGR` | 연복리수익률 |
| `IC` | 정보계수 |
| `ICIR` | 정보계수 안정성 |
| `DSR` | 디플레이티드 샤프 |
| `Harvey-t` / `Harvey t` | 다중검정 t값 |
| `t_NW` | Newey-West t값 |
| `Bailey-LdP` | Lopez de Prado 검정 |
| `TDC` | 꼬리 의존성 |
| `MRS` | 시장 국면 점수 |
| `SUE` | 표준화 어닝 서프라이즈 |
| `ESBR` | 이익 변경률 |
| `ADV` | 평균 거래대금 |
| `Σ` | 공분산 |
| `FF3` / `FF5` | Fama-French 3/5 팩터 |
| `BAB` | 베타 차익거래 |
| `BM_Ret` | 벤치마크 수익률 |
| `OOS` | 표본 외 검증 |
| `t_NW` | Newey-West t값 |

### Mode

- `"inline_first"` (default) — 본문 첫 등장에 `약어 (한글)` 부착
- `"footer"` — 본문 미변환 + footer에 `📚 약어: WT-D=발견형 작업 / SR=샤프지수 / ...` 합성
- `"off"` — 변환 없음 (정통 퀀트 보고서 mode)

본문에 이미 한글 풀이가 있으면 lookback 정규식으로 중복 보호.

---

## §6 표준 4섹션 (권장)

핵심 알림은 다음 4섹션 순서를 권장 (강제 X — `MIN_SECTIONS=2`만 만족이면 자유).

| 순서 | type | emoji | 내용 |
|---|---|---|---|
| 1 | `summary` | 📌 | 1줄 헤드라인 (도훈이 모바일에서 첫 5초에 인지) |
| 2 | `kv` 또는 `table` | 📊 | 핵심 수치 (3~5개) |
| 3 | `bullet` | 🚩 | 리스크 / 주의 (≥2) |
| 4 | `bullet` | ➡️ | 다음 액션 (≥2) |

---

## §7 caller 예시 (6종)

### 7.1 간결 알림 (380~500 bytes)

```r
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Q-Lead",
  title = "PG2 운용 변경 안내",
  sections = list(
    list(type = "summary",
         body = "운용형 작업 PG2 70/15/15 도훈 승인. 6월 1일 발효."),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("샤프지수" = 1.665,
                   "최대낙폭" = "-16.6%",
                   "연복리수익률" = "26.4%"))
  )
)
```

### 7.2 Forge 백테스트 결과

```r
tg_agent_brief(
  agent = "Forge",
  title = "WT-D20260504_001 백테스트 완료",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "STR_1715 AR 임계값 오버레이 268개월 워크포워드 완료."),
    list(type = "table", emoji = "📊", heading = "기간별 성과",
         df = data.frame(
           기간   = c("훈련", "검증", "전체"),
           샤프   = c("1.78", "1.62", "1.67"),
           낙폭   = c("-22%", "-31%", "-25%")
         )),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c("회전율 614% 한도 600% 초과 6개월",
                   "검증구간 샤프 0.16 하락")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("Judge 전이",
                   "AR 임계값 0.4172 / 0.4502 lockbox 봉인"))
  ),
  charts = c("stage_artifacts/WT-D20260504_001/equity_curve.png")
)
```

### 7.3 Risk 공분산 진단

```r
tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260504_001 Σ + 헷지 완료",
  sections = list(
    list(type = "summary",
         body = "Ledoit-Wolf 공분산 + 꼬리위험 진단 완료. 정상."),
    list(type = "table", emoji = "🔬", heading = "추정기 비교",
         df = data.frame(
           추정기   = c("샘플", "Ledoit", "Gerber"),
           조건수   = c("248", "11", "128"),
           추천     = c("X", "✅", "△")
         )),
    list(type = "bullet", emoji = "🛡️", heading = "헷지 권고",
         items = c("팩터 베타 0.92 정상",
                   "꼬리 의존성 0.27 (임계 0.30 미만)",
                   "스트레스 시나리오 -18% 통과"))
  )
)
```

### 7.4 Judge Gate 판정

```r
tg_agent_brief(
  agent = "Judge",
  title = "WT-D20260504_001 GRADE_A / ADMIT",
  sections = list(
    list(type = "summary",
         body = "Gate 0~5 모두 PASS. 등급 A 판정. 운용 단계 승격 권고."),
    list(type = "kv", emoji = "⚖️", heading = "Gate 결과",
         kv = list("PIT C1~C15" = "PASS",
                   "다중검정 t값" = "6.70",
                   "디플레이티드 샤프" = "z=6.10")),
    list(type = "bullet", emoji = "🚩", heading = "잔존 위험",
         items = c("회전율 614% 모니터링 필요",
                   "AR 임계값 봉인 검증 후 발효"))
  )
)
```

### 7.5 Governor admit

```r
tg_agent_brief(
  agent = "Governor",
  title = "WT-P20260505_001 PG2 ADMIT",
  sections = list(
    list(type = "summary",
         body = "Hybrid 70/15/15 PG2 ADMIT. 6월 1일 운용 발효."),
    list(type = "table", emoji = "👑", heading = "Book 변경",
         df = data.frame(
           구분     = c("이전", "이후"),
           전략수   = c("1", "3"),
           구성     = c("STR_1715 100%", "70/15/15")
         )),
    list(type = "bullet", emoji = "➡️", heading = "발효 일정",
         items = c("5월: 위험자산 70 + 현금 30 (M4 정상)",
                   "6월 1일: STR_1715 70 + TSMOM 15 + 국채 15"))
  )
)
```

### 7.6 Q-Lead 종합 (풍부 1500+ bytes)

```r
tg_agent_brief(
  agent = "Q-Lead",
  title = "Session 76 Hybrid PG2 정착 완료",
  sections = list(
    list(type = "summary",
         body = "9-step 사이클 완주. Restall 9-item 모두 통과. 운용 발효."),
    list(type = "kv", emoji = "📊", heading = "성과 (256개월)",
         kv = list("샤프지수"     = "1.665 (+0.08)",
                   "최대낙폭"     = "-16.6% (-9.83pp)",
                   "연복리수익률" = "26.4%")),
    list(type = "text", emoji = "💡", heading = "본질 통찰",
         body = "단일 직교 source는 Pareto 일면적이라 두 source 결합 시너지가 핵심. 60/40 + managed futures hybrid 패러다임 진화."),
    list(type = "bullet", emoji = "🚩", heading = "잔여 P0",
         items = c("샤프지수 목표 2.0 vs 실측 1.665, 격차 0.335",
                   "4번째 직교 source 다음 사이클 탐색")),
    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c("6월 1일 70/15/15 발효",
                   "9-Day grace PD1~PD3 모니터링",
                   "메모리 L-284 적립"))
  ),
  footer = "📚 SOT: docs/qvest_v7_2_1_sot.md"
)
```

---

## 부록 A — Hook 정책

`02_Infrastructure/hooks/telegram_direct_call_guard.sh` (PreToolUse[Bash]):

| 차단 대상 | 우회 |
|---|---|
| `tg_send(...)` 직접 호출 | tg_agent_brief 동시 호출 시 허용 |
| `tg_send_rich(...)` 직접 호출 | 동일 |
| `tg_send_photo(...)` 직접 호출 | 동일 |

→ 모든 agent / prompt / strategy script는 **`tg_agent_brief()` 만** 호출.

---

## 부록 B — Single-Dispatch Lock

같은 `agent + WT-id`(또는 title 첫 40자) 중복 발송 차단.

- `lock_scope=NULL` default → 자동 scope 생성
- `force=TRUE` → 우회 (수동 재전송 명시)
- Lock 파일: `/tmp/qvest_tg_lock_<scope>.lock`

---

## 부록 C — 채널 / 봇

| 항목 | 값 |
|---|---|
| Bot | `@quant12323413245_bot` |
| Channel | `-1003850915447` |
| Personal DM fallback | `1355291682` |
| 자격증명 | `.env` `TG_BOT_TOKEN`, `TG_CHAT_ID`, `TG_PERSONAL_CHAT_ID` |

---

## 참조

| 자원 | 경로 |
|---|---|
| R 구현 SOT | `02_Infrastructure/telegram/telegram_notify.R::tg_agent_brief()` (line 598+) |
| 약어 사전 | 동상 `::tg_decode_jargon()` |
| Smart break | 동상 `::tg_text_smart_break()` |
| Hook | `02_Infrastructure/hooks/telegram_direct_call_guard.sh` |
| Body archive (디버깅) | `/tmp/qvest_tg_body_ARCHIVE/` |
| L-260 (v5 enforce 경위) | `methodology_active.md` |
