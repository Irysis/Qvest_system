---
name: qvest-telegram
description: Qvest 텔레그램 발송의 유일한 규칙(SOT). 양식 / 약어 풀이 / 자동 용어풀이(비전공자 가독) / Hook 정책 / caller 예시 통합. tg_agent_brief() 단일 진입점만 허용 (직접 호출 시 PreToolUse Hook 차단).
---

# Qvest Telegram Skill — v7 SOT (단일 규칙 · 비전공자 가독)

**발효**: 2026-05-07 (v6) / **v7 2026-07-10 (도훈 mandate — 비전공자 가독화, 전문용어 유지)** / 본 파일은 텔레그램 양식의 **유일한 SOT**.
**계보**: v3 → v4 → v5 ENFORCE (2026-04-30, L-260) → v6 SOT (가독성 + 단일화) → **v7 비전공자 가독** (전문용어 유지 + 쉬운 설명 3장치).

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
| **1 ⭐** | **연구 목적 한글 명시 의무 (v6.2 도입 / v7.2.1 retain)** | 첫 섹션 = 한글 연구 컨텍스트 (목적 + 검토 내용 + 결론 1줄). 영어 약어 라벨만 X |
| 2 | **간결** | 줄글 우겨넣기 금지. 문장 짧게 끊기. `MIN_BYTES=400` 충족이면 OK |
| 3 | **약어 최소** | 본문에서 직접 한글로 풀어 쓰기. 불가피한 약어는 `tg_decode_jargon()` 자동 풀이 |
| 4 | **정통 한글 퀀트 용어** | "샤프지수 / 최대낙폭 / 연복리수익률 / 정보계수 / 다중검정 t값" 등 (Harvey 2016, Lopez de Prado 표기 한글화) |
| 5 | **한글 중심** | 헤딩·본문·결정 문장 한글. 영어는 변수명 / 메트릭 약어 / 출처(논문명)에 한정 |
| 6 | **이모지 활용** | 메시지당 ≥5개 (`EMOJI_MIN`). 섹션마다 1개 의미 emoji + 강조 emoji |
| 7 | **개조식 + 줄바꿈** | 한 문장 한 줄. `tg_text_smart_break()`가 마침표·슬래시·화살표·종결어미에서 자동 줄바꿈 |
| **8 ⭐⭐** | **비전공자 1분 이해 (v7 도입, 도훈 mandate 2026-07-10)** | 전문용어는 **유지**하되 아래 3장치 의무. 퀀트를 모르는 사람이 읽어도 "무엇을 시도했고 → 결과가 어땠고 → 그래서 돈에 뭐가 달라지는지"를 1분 안에 파악 가능해야 함 |
| **9 ⭐** | **실측 시각화 의무 (v7.1 도입, 도훈 mandate 2026-07-11)** | 실측 수치(백테/canonical/forge/게이트 판정)가 담긴 보고는 **`charts=` 그래프 첨부 의무** — 글만 보내기 금지. 아래 "원칙 9" 절 참조 |

### 원칙 8 — 비전공자 1분 이해 3장치 (v7 핵심)

**설계 철학**: 용어를 순화(dumb-down)하지 않는다. 샤프지수·PORT_t·최대낙폭 같은 전문용어는 그대로 쓰되, **해설을 겹쳐 입힌다**. 전문가는 용어만 읽고, 비전공자는 해설로 따라온다.

| 장치 | 의무 수준 | 구현 |
|---|---|---|
| **① 한줄 결론 평문화** | caller 의무 | 첫 `summary` = 일상어 결론. "무엇을 시도했는데 결과가 어땠다"를 비전공자 언어로. 수치·약어로 시작 금지 |
| **② "쉬운 설명" 섹션** | caller 의무 (R warn-level) | heading에 **"쉬운 설명"** 포함한 `bullet` 섹션 1개 의무. 내용 = ⓐ무엇을 시도했나 ⓑ어떻게 확인했나 ⓒ무슨 결과가 나왔나 ⓓ그래서 뭐가 달라지나 — 각 1줄 평문. 비유 허용 ("표본 외 검증 = 개발에 안 쓴 기간으로 치른 모의고사") |
| **③ 자동 용어 풀이 footer** | R 자동 (caller 무관) | `tg_agent_brief()`가 본문에 등장한 전문용어를 스캔해 메시지 하단에 `📖 용어 풀이` 블록 자동 부착 (§5.5 사전). caller는 본문에서 용어를 자유롭게 사용 — 풀이는 시스템 책임 |

**판정 평문 1줄 의무 (장치 ① 확장)**: PASS/FAIL/ADMIT/REJECT/screen-tier 등 판정이 포함된 메시지는 **"그래서 돈에 뭐가 달라지는지"** 1줄 의무:
- ✅ "판정 FAIL — 이 아이디어에는 실제 자본을 배정하지 않습니다"
- ✅ "screen-tier — 신호는 있지만 자본 투입 기준(다중검정 t값 2.95)에 못 미쳐 참고용으로만 보관합니다"
- ❌ "Gate C FAIL / graduation 불가" (판정 라벨만 — 비전공자는 결과를 모름)

**② 쉬운 설명 예시** (bullet 4줄 패턴):
```r
list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
     items = c(
       "시도: 임원이 자기 회사 주식을 사면 주가가 오르는지 확인했습니다",
       "방법: 과거 20년 데이터로 모의 운용(백테스팅)을 돌렸습니다",
       "결과: 수익 신호는 있지만 우연일 가능성을 배제할 수준(t값 2.95)에는 못 미쳤습니다",
       "의미: 실제 돈은 넣지 않고, 다른 전략의 참고 재료로만 씁니다"))
```

### 원칙 9 — 실측 시각화 의무 (v7.1, 도훈 mandate 2026-07-11 "글만 오니까 밋밋하고 직관적이지가 않아")

**적용 대상**: 실측 수치가 담긴 모든 보고 — 백테스트 결과(forge/canonical_screen_bt/essence_score), 게이트 판정(HARD 3종·screening), sweep/멀티암 비교(A/B·config 서열), 챔피언십/북 상태. **면제**: 수치 없는 착수 알림·상태 전이·스펙 승인·큐 갱신.

**표준 생성기 (단일 경로)**: `02_Infrastructure/telegram/tg_chart_pack.R`
| 함수 | 산출 | 용도 |
|---|---|---|
| `tg_chart_pack(period_returns, out_dir, title, metrics_note=)` | 표준 3종: ①누적수익(로그) vs BM ②연간수익률 막대 vs BM ③낙폭 수중곡선 | 단일 전략/모듈 실측 보고 |
| `tg_chart_sweep(labels, values, out_dir, title, hline=, highlight=)` | 비교 가로막대 + 기준선(2.95/2.0) | sweep·멀티암·챔피언십 서열 |
| `tg_chart_pack_from_bt(bt_result, out_dir)` | 10-component 계약에서 표준 3종 자동 | forge 산출 직결 |

**caller 패턴**:
```r
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
paths <- tg_chart_pack_from_bt(bt_result, out_dir = "stage_artifacts/WT_X",
                               metrics_note = "PORT_t 2.35 · oos 0.71 (forge)")
tg_agent_brief(agent = "forge", title = "...", sections = ..., charts = paths)
```

**차트 형태 자유 (v7.2, 도훈 지시 2026-08-21 — "막대에 한정짓지 말 것")**: 위 표준 생성기는
**기본형(baseline)이지 형태 제약이 아니다.** 차트 형태는 **연구 내용이 정한다** — 분포 표적 라운드는
히스토그램·분위 프로파일·꼬리 비교, 국면 라운드는 시계열 음영·상태별 박스플롯, 횡단면 구조는
산점·히트맵, 서열 비교는 막대 외 슬로프/도트 플롯 등 **내용에 맞는 형태를 자유 선택**한다
(ggplot2 직접 작성 → `charts=` 첨부, 기존 파라미터 그대로). 배경: 하네스의 목적은 알파 서칭 능력
강화이고(CLAUDE.md 존재의의), v8.4 비대칭 리서치의 핵심 산출(분포·왜도·분위)은 막대·누적선만으로
표현되지 않는다. 표준 3종은 단일 전략 실측 보고의 **권장 기본값**으로 유지.

**규율 3항 (형태 자유와 무관하게 불변)**: ① 차트 수치 주석(`metrics_note`)·차트가 표시하는 성과
수치는 **계약 산출값만** — 커스텀 차트도 시각화 전용이며 성과 수치를 자체 계산하지 않는다(자체합성
금지 정합. 분포·중간 통계량의 시각화 변환은 허용 — 게이트/성과 주장 수치만 계약 경유). ② 최소 1장
(권장: 단일 전략 = 표준 3종 ± 내용 적합형 추가, sweep = 비교 1종 + 승자 표준 3종). ③ PNG는 해당
WT/리서치의 `stage_artifacts/` 산하에 저장(임시 디렉토리 금지 — 재현 감사 대상).

### 원칙 1 강제 (v6.2 도입 / v7.2.1 retain — 도훈 명시 2026-05-08)

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
- **옵션 라벨로 갑/을/병/정 사용** (도훈 명시 2026-05-08): 옛 표기 부자연. **A안 / B안 / C안 / D안** 또는 **1안 / 2안 / 3안** 패턴이 한국 실무 자연

**옵션 라벨 정합** (도훈 명시 2026-05-08):

| 비교 대상 | 정합 라벨 | 예시 |
|---|---|---|
| **정량 (비율/비중/수치)** | **수치 자체** | `0% / 10% / 20% / 30%` 또는 `5종목 / 10종목 / 20종목` |
| **카테고리 (방법론/전략)** | **A안 / B안 / C안** 또는 **1안 / 2안** | "A안 분기 리밸 / B안 회전율 패널티 / C안 buffer_zone" |

- ✅ "비중 비교: 0% / 10% / 20% / 30% — 샤프 1.81 / 1.79 / 1.74 / 1.68"
- ✅ "Mitigation: A안 분기 리밸 / B안 회전율 패널티 / C안 buffer_zone / D안 슬리브 평균"
- ❌ "A안 0% / B안 10% / C안 20% / D안 30%" (라벨 + 수치 중복)
- ❌ "갑 (10% admit) / 을 (20%) / 병 (30%) / 정 (현상유지)" (옛 표기)
- ❌ "옵션 ㄱ / ㄴ / ㄷ / ㄹ"

**필수 패턴**:
- 첫 섹션 = 외부 구독자가 무엇을 보고 있는지 1초 안에 인지 가능
- 약어 사용 시 한글 풀이 본문 직접 명시 (decode_jargon 자동 풀이 외에도 caller 명시 의무)

### 핵심 비교 kv 정책 (도훈 명시 2026-05-08 13:XX)

**kv "핵심 비교" 섹션 = 정량 결과 metric만**:
- ✅ 정보계수 / 샤프지수 / 최대낙폭 / 회전율 / 다중검정 t값 / 디플레이티드 샤프 등 결과 지표
- ❌ 인프라 정보 (GPU / 가속률 / CPU 코어 / VRAM / 학습 시간 등)

**인프라 / 환경 정보 위치**:
- 별도 섹션 (예: "🔧 환경" — 후순위 섹션)
- 또는 footer 1줄 (예: `📚 산출: alpha_package.json 49KB / RTX 4080 SUPER GPU 12분`)
- 핵심 비교 kv 안 X

**이유**: 텔레그램 구독자 (외부 + 도훈)가 핵심 비교에서 _연구 결과_만 1초 인지하도록. 인프라는 부수 정보.

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
| `GLOSSARY_MAX_BYTES` | **900** ⭐ v7 | 자동 용어 풀이 footer 최대 바이트. 초과 시 등장 순서 뒤쪽 용어부터 절삭 |

위반 시 `tg_agent_brief()` 자체에서 `stop()`. `force=TRUE` 만 명시 우회.

**v7 신규 파라미터** (`tg_agent_brief()`):

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `glossary` | `TRUE` | 본문 스캔 → `📖 용어 풀이` footer 자동 부착 (§5.5 사전). `FALSE`는 내부 디버그 발송만 |
| (warn) 쉬운 설명 섹션 | — | heading에 "쉬운 설명" 포함 섹션 부재 시 **warn-level** `message()` (기존 자동 caller 비파괴 — cron/파이프라인 발송은 안 끊김). 에이전트 브리핑은 원칙 8-② caller 의무 |

**v6.1 핵심 의무 (caller mandate)**:
- 표 사용 최소화 → `kv` 또는 `bullet` 우선
- 표 사용 시 ncol=2, 한글 column header 4~6자
- bullet 한 항목 80자 이하 (학술 인용 + 정량 + L-code 모두 한 줄에 X — 분할 의무)
- text 220자 초과 시 bullet 분할 (long 섹션 X)

### §3.1 `relaxed=TRUE` 완화 (페이퍼 적재 브리핑 전용 — 도훈 mandate 2026-06-18)

`tg_agent_brief(..., relaxed = TRUE)` 는 다음 **콘텐츠-규율 가드만** 면제한다 (매직 상수 아님 — 함수 파라미터, `.TG_CONFIG` 동기화 무관):

| 면제 대상 | 평소 규칙 |
|---|---|
| `bullet` 항목 길이 | `BULLET_ITEM_MAX` 80자 stop |
| `bullet` 영어 약어 ≥2건 거부 | §2 원칙 3/5 (한글 풀어쓰기) |
| `kv` 값 길이 | `KV_VALUE_MAX` 60자 stop |
| `kv` 키 영어 비율 | 60% 초과 stop |

**유지(면제 안 됨, relaxed여도 적용)**: 전체 메시지 4096 byte 가드 · skeleton 가드(`MIN_BYTES`/`MIN_SECTIONS` — `force=TRUE`로만 우회) · `BULLET_MIN`/`KV_MIN` 구조 최소.

**렌더링 차이**: relaxed=TRUE면 `bullet` 항목을 빈 줄(`\n\n`)로 분리한다(긴 영어 제목이 모바일에서 줄바꿈돼 붙어 보이는 것 방지, 도훈 2026-06-18). 일반(FALSE)은 단일 줄바꿈 유지.

- **기본값 `FALSE`** — 일반 에이전트(alpha/risk/optimizer/judge/governor/Q-Lead 등)는 **사용 금지**. §2 한글 규율 그대로 유지.
- **유일 허용 용도** = 영어 논문 제목 등 고유명사 콘텐츠를 그대로 노출해야 하는 브리핑. 현재 유일 사용처 = 페이퍼 적재 digest (`02_Infrastructure/tools/paper_recharge_daily.R`, "오늘 적재 논문" bullet에 `영어제목 (한글요약)` 표시).

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
| `Σ` / `covariance` | 공분산 (NOT "공동위험") |
| `VaR` / `CVaR` / `ES` / `IVOL` / `TE` / `PnL` / `NAV` | retain (한국 통용 영문 약어) |
| `FF3` / `FF5` | Fama-French 3/5 팩터 |
| `BAB` | 저베타 (NOT "베타 차익거래") |
| `BM_Ret` | 벤치마크 수익률 |
| `OOS` | 표본 외 검증 |
| `t_NW` | Newey-West t값 |

**한글 정통 용어 mandate (도훈 명시 2026-05-08)**:

이미 한국 퀀트 학술/실무에서 통용되는 정통 한글 용어는 **그대로 사용**. 자의적 풀이로 변형 금지:

| ❌ 자의적 풀이 (금지) | ✅ 정통 용어 (사용) |
|---|---|
| 공동위험 (행렬) | **공분산** (행렬) |
| 위험가치 | **조건부 손실** (VaR) |
| 기대단사 | **기대 손실** (ES/CVaR) |
| 변동성 위험 비대칭 | **왜도** (skewness) |

논문 영어 원문 인용 (`Bakshi 2003` / `Frazzini-Pedersen 2014` / `Asness-Frazzini-Pedersen 2019`)은 변환 없이 그대로 사용 OK. v6.4 함수 레벨 면제 적용 (`telegram_notify.R` exempt_pattern 학술 인용 + 저널 약어 추가).

**v6.5 통상 영어 표기 허용 (도훈 mandate 2026-05-15)**:

다음 통상 영어 표기는 **변환 없이 그대로 사용** (자의적 한글 풀이 금지):

| 분류 | 허용 영어 표기 (예시) |
|---|---|
| **ML 모델** | LightGBM / XGBoost / Ridge / LASSO / ElasticNet / Ensemble |
| **알고리즘/통계** | Pareto / Sharpe / Newey-West / HRP / MVO / CVaR / ERC / GARCH / HMM / EWMA / EM |
| **메트릭** | TDC / MDD / IC / ICIR / DSR / TE / VaR / CAGR / SUE / ESBR / ADV / FF3 / FF5 / MRS |
| **시스템 용어** | PIT / OOS / GPU / ML / NN / RL / EW / JSON / API |
| **Agent 이름** | Q-Lead / Alpha / Risk / Optimizer / **Forge** / Judge / Governor / Scout / Execution / Monitoring / **Architect** / **Codex** |

❌ **자의적 한글 변형 금지** (라이트지비엠 / 다각화비 / 포지/코덱스/아키텍트 등 X — 영어 원어 retain)

**구어체 줄임말 금지 (도훈 mandate 2026-05-15)**:

| ❌ 줄임말 (금지) | ✅ 정식 표기 (사용) |
|---|---|
| 리밸 | **리밸런싱** |
| 벡테 / 백테 | **백테스팅** |
| 옵티 | **옵티마이저** |
| 어드미 | **admit** (또는 운용 등재) |

함수 레벨 enforcement: `telegram_notify.R` v6.5 exempt_pattern 통상 영어 quant 용어 + agent name 자동 면제.

### Mode

- `"inline_first"` (default) — 본문 첫 등장에 `약어 (한글)` 부착
- `"footer"` — 본문 미변환 + footer에 `📚 약어: WT-D=발견형 작업 / SR=샤프지수 / ...` 합성
- `"off"` — 변환 없음 (정통 퀀트 보고서 mode)

본문에 이미 한글 풀이가 있으면 lookback 정규식으로 중복 보호.

---

## §5.5 용어 뜻 사전 (v7 — `.METRIC_MEANING` / 자동 용어 풀이 footer)

§5(약어→한글명 변환)와 별개 층위. §5는 "SR → 샤프지수" 명칭 변환, **§5.5는 "샤프지수가 무슨 뜻이고 얼마면 좋은 건지"** 를 푼다. `tg_agent_brief()`가 최종 본문을 스캔해 등장한 용어만 골라 `📖 용어 풀이` footer를 **자동 부착** (R `.METRIC_MEANING`과 1:1 동기화 — 변경 시 본 표 먼저).

**작성 원칙**: ① 일상어 한 줄 ② 가능하면 판정 기준선 포함("얼마면 합격/양호") ③ 비유 허용 ④ 40자 내외.

| 용어 (본문 매칭 패턴) | 쉬운 뜻 (footer 문구) |
|---|---|
| 샤프지수 / SR | 감수한 출렁임 대비 수익 효율. 1 이상 양호, 2 이상 우수 |
| 최대낙폭 / MDD | 고점에서 저점까지 최대 하락률. 작을수록 안전 |
| 연복리수익률 / CAGR | 매년 평균 몇 %씩 복리로 불었는지 |
| 정보계수 안정성 / ICIR | 예측 적중의 꾸준함 (정보계수 평균 대비 변동) |
| 정보계수 / IC | 예측 점수와 실제 수익의 들어맞는 정도. 0.05면 유의미 |
| 정보비율 / IR | 시장 대비 초과수익의 꾸준함. 0.5 이상 양호 |
| 다중검정 t값 / PORT_t / portfolio-alpha t | 초과수익이 우연이 아닐 확신도. 2.95 이상이어야 자본 투입 자격 |
| t값 (단독) | 결과가 우연이 아닐 확신도. 2 이상이면 통계적으로 의미 있음 |
| 디플레이티드 샤프 / DSR | 여러 번 시도한 보정을 반영해 깎아서 본 샤프지수 |
| 표본 외 검증 / OOS | 개발에 쓰지 않은 기간으로 치르는 모의고사 |
| 표본외 유지율 / oos_retention | 개발 기간 성과가 새 기간에도 유지되는 비율. 0.7 이상 합격 |
| 칼마 / Calmar | 연수익을 최대낙폭으로 나눈 값. 0.64 이상 합격 |
| 회전율 / Turnover / TO | 1년에 포트폴리오를 갈아치우는 비율. 높을수록 거래비용 부담 |
| 벤치마크 / BM | 성과 비교 기준이 되는 시장 지수 |
| 백테스팅 | 과거 데이터로 전략을 모의 운용해 보는 검증 |
| PIT / 시점 정합 | 그 시점에 실제로 알 수 있던 정보만 쓰는 원칙 (미래 정보 반입 금지) |
| 미래참조 / look-ahead | 그 시점엔 몰랐을 미래 정보가 섞여 성과가 부풀려지는 오류 |
| 오버레이 / overlay | 기존 포트폴리오 위에 얹는 보조 장치 (예: 위험 신호 시 현금 확대) |
| 알파 / alpha | 시장 평균을 넘어서는 초과수익, 또는 그 원천 |
| 팩터 | 종목을 고르는 기준 신호 (예: 저평가, 이익 개선) |
| graduation / 자본 졸업 | 실제 자본을 배정받을 자격 심사 통과 |
| screen-tier / 스크린 등급 | 신호는 있으나 자본 투입 기준 미달 — 참고용 보관 등급 |
| admission / admit | 실제 운용 목록(북) 편입 승인 |
| book / 운용 북 | 실제 자본이 배정된 전략 묶음 |
| lockbox | 검증 전 결과를 미리 못 보게 봉인하는 장치 |
| long-only | 매수만 하는 운용 (공매도 없음) |
| 워크포워드 / walk-forward | 시간 순서대로 한 구간씩 전진하며 검증하는 방식 |
| 잔차 / residual | 시장·공통 요인으로 설명되고 남은 고유 부분 |
| 국면 / regime | 시장의 상태 구분 (예: 강세장 / 위기) |
| 유니버스 | 투자 대상으로 허용된 종목 집합 |
| L-code / 교훈 코드 | 실험에서 얻은 교훈의 일련번호 |
| 공분산 | 종목들이 함께 움직이는 정도 (분산투자 계산의 재료) |
| 플라시보 / placebo | 가짜 신호로 같은 실험을 돌려 진짜 신호와 구별하는 검사 |

**동작 규칙 (R 구현 계약)**:
- 등장 순서대로 수집, `GLOSSARY_MAX_BYTES`(900) 초과분은 뒤쪽부터 절삭
- 메시지 전체 4096 byte 근접 시 glossary 우선 절삭 (본문 보호)
- footer 형식: `📖 용어 풀이` 헤딩 + `  • 용어 = 뜻` 한 줄씩
- 대상 없으면 미부착 (에러 아님)

---

## §6 표준 5섹션 (권장 — v7)

핵심 알림은 다음 5섹션 순서를 권장 (강제 X — `MIN_SECTIONS=2`만 만족이면 자유. 단 **원칙 8-② "쉬운 설명" 섹션은 에이전트 브리핑 의무**, R warn-level).

| 순서 | type | emoji | 내용 |
|---|---|---|---|
| 1 | `summary` | 📌 | 1줄 결론 — **평문** (비전공자가 모바일 첫 5초에 결과 인지) |
| 2 | `bullet` | 📖 | **쉬운 설명** (시도/방법/결과/의미 — 각 1줄 평문, 원칙 8-②) |
| 3 | `kv` 또는 `table` | 📊 | 핵심 수치 (3~5개, **전문용어 그대로** — 풀이는 자동 footer가 담당) |
| 4 | `bullet` | 🚩 | 리스크 / 주의 (≥2) |
| 5 | `bullet` | ➡️ | 다음 액션 (≥2, 판정 메시지면 "돈에 뭐가 달라지는지" 1줄 포함) |

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
         body = "STR_1715 AR-on-M4-R05 오버레이 단일 sleeve PG2 운용 재확인 (도훈 mandate)."),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("샤프지수" = 1.71,
                   "최대낙폭" = "-24.8%",
                   "정보비율" = 1.575))
  )
)
```

### 7.2 Forge 백테스트 결과 (v7 표준 5섹션)

```r
tg_agent_brief(
  agent = "Forge",
  title = "위험신호 오버레이 전략 백테스트 완료",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "위험신호로 현금 비중을 조절하는 장치를 22년 데이터로 검증 — 성과 유지 확인."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("시도: 시장 위험신호가 켜지면 주식을 줄이는 장치를 얹었습니다",
                   "방법: 268개월 과거 데이터로 모의 운용(워크포워드 백테스팅)했습니다",
                   "결과: 수익 효율(샤프지수)이 검증 구간에서도 유지됐습니다",
                   "의미: 다음 심사(Judge)로 넘길 자격이 확인됐습니다")),
    list(type = "table", emoji = "📊", heading = "기간별 성과",
         df = data.frame(
           기간   = c("훈련", "검증", "전체"),
           샤프   = c("1.78", "1.62", "1.67")
         )),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c("회전율 1,114% — 한도 1,100%를 6개월 초과",
                   "검증구간 샤프지수 0.16 하락")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("Judge 심사 전이 (아직 실제 자본 배정 아님)",
                   "AR 임계값 0.4172 / 0.4502 lockbox 봉인"))
  ),
  charts = c("stage_artifacts/WT-D20260504_001/equity_curve.png")
)
```

→ 발송 시 R이 자동으로 하단에 부착:

```
📖 용어 풀이
  • 샤프지수 = 감수한 출렁임 대비 수익 효율. 1 이상 양호, 2 이상 우수
  • 백테스팅 = 과거 데이터로 전략을 모의 운용해 보는 검증
  • 회전율 = 1년에 포트폴리오를 갈아치우는 비율. 높을수록 거래비용 부담
  • lockbox = 검증 전 결과를 미리 못 보게 봉인하는 장치
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

### 7.4 Judge Gate 판정 (v7 — 판정 평문 1줄 의무)

```r
tg_agent_brief(
  agent = "Judge",
  title = "전략 심사 통과 — 운용 승격 권고",
  sections = list(
    list(type = "summary",
         body = "모든 심사 관문 통과. 실제 자본 배정 후보로 승격을 권고합니다 (최종 결정은 도훈)."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("심사: 미래 정보 반입(미래참조) 여부와 성과의 우연 가능성을 검사했습니다",
                   "결과: 초과수익 확신도(다중검정 t값) 6.70 — 기준 2.95를 크게 상회",
                   "의미: 통계적으로 우연이 아닐 가능성이 매우 높은 전략입니다")),
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
         body = "STR_1715 AR-on-M4-R05 오버레이 PG2 단일 sleeve ADMIT (도훈 confirm)."),
    list(type = "table", emoji = "👑", heading = "Book 변경",
         df = data.frame(
           구분 = c("이전", "이후"),
           구성 = c("STR_1715+M4+R05", "STR_1715+M4+R05+AR")
         )),
    list(type = "bullet", emoji = "➡️", heading = "발효",
         items = c("단일 sleeve 100% (멀티슬리브 아님)",
                   "AR 임계 β 동적 0.4~1.0 vol 오버레이 추가"))
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
         items = c("STR_1715 단일 sleeve 오버레이 운용 (R05/AR)",
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
| R 구현 SOT | `02_Infrastructure/telegram/telegram_notify.R::tg_agent_brief()` |
| 약어 사전 (명칭 변환) | 동상 `::tg_decode_jargon()` / `.JARGON_DICT` |
| **용어 뜻 사전 (v7 자동 풀이)** | 동상 `::tg_build_glossary()` / `.METRIC_MEANING` (§5.5와 1:1 동기화) |
| Smart break | 동상 `::tg_text_smart_break()` |
| Hook | `02_Infrastructure/hooks/telegram_direct_call_guard.sh` |
| Body archive (디버깅) | `/tmp/qvest_tg_body_ARCHIVE/` |
| L-260 (v5 enforce 경위) | `methodology_active.md` |

---

## Change log

- **2026-08-21 v7.2 (도훈 지시 — 차트 형태 자유화)**: 원칙 9 의 사실상 막대·표준3종 한정을 해제 — 형태는 연구 내용이 정한다(분포=히스토그램·분위 프로파일 / 국면=음영·박스 / 횡단면=산점·히트맵 등, ggplot2 직접 작성 + `charts=` 첨부). 표준 3종은 권장 기본값으로 유지, 규율 3항(계약 수치만·stage_artifacts 보존·최소 1장) 불변. 배경 = 하네스 목적은 알파 서칭 능력 강화 — v8.4 분포 리서치 산출이 막대로 표현 불가.
- **2026-07-11 v7.1 (도훈 mandate — 실측 시각화 의무)**: §2 원칙 9 신설 — 실측 수치 보고 = `charts=` 그래프 첨부 의무("글만 오니까 밋밋하고 직관적이지가 않아"). 표준 생성기 `02_Infrastructure/telegram/tg_chart_pack.R` 신설(표준 3종: 누적수익 로그·연간수익 막대·낙폭 수중곡선 + sweep 비교 가로막대 + bt_result 계약 래퍼). 규율: 차트팩 = 시각화 전용(수치 계산 금지, metrics_note는 계약 산출값만)·PNG는 stage_artifacts/ 보존. 면제 = 수치 없는 착수/상태/스펙 알림. 기존 caller 비파괴(charts= 기존 파라미터 활용).
- **2026-07-10 v7 (도훈 mandate — 비전공자 가독화, 전문용어 유지)**: 원칙 8 신설(비전공자 1분 이해 3장치 — ①한줄 결론 평문 ②"쉬운 설명" 섹션 의무(R warn-level) ③자동 용어 풀이 footer) + §5.5 용어 뜻 사전(`.METRIC_MEANING`, 뜻+판정기준 40자 내외) + §6 표준 4→5섹션(쉬운 설명 삽입) + 판정 평문 1줄 의무 + `.TG_CONFIG$GLOSSARY_MAX_BYTES=900` + `tg_agent_brief(glossary=TRUE)` 기본 ON. 기존 자동 caller 비파괴(glossary는 자동 부착, 쉬운 설명 부재는 warn만).
- 2026-06-18 §3.1 `relaxed=TRUE` (페이퍼 적재 브리핑 전용).
- 2026-05-27 v6.6 quant whitelist 확장 / 2026-05-15 v6.5 통상 영어 허용 / 2026-05-08 v6.1~6.3 모바일 상한 + 한글 규율 / 2026-05-07 v6 SOT 단일화.
