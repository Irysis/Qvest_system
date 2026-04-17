---
name: telegram-protocol
description: "텔레그램 발송 시 적용 — 이모지, 에이전트 태그, 브리핑 9종 템플릿"
---
## 텔레그램 규칙

### 호출
```r
source("02_Infrastructure/telegram/telegram_notify.R")
tg_send("메시지")
tg_send_photo("path/to/chart.png", caption = "설명")
tg_send_document("path/to/file.pdf", caption = "설명")
```

### 필수 규칙
1. **이모지 필수** — 텍스트만 보내기 절대 금지
2. **에이전트 태그** 첫 줄: `[Scout]` / `[Forge]` / `[Judge]` / `[Governor]` / `[Q-Lead]`
3. **차트 동반**: 백테스트 결과 시 equity_curve.png + annual_returns.png 필수
4. **한글** 기본
5. **가독성**: 줄바꿈, 섹션 구분, 들여쓰기. 숫자만 나열 금지.

### 이모지 가이드
📊 Dashboard | 🔍 Scout | 🔨 Forge | ⚖️ Judge | 🏗️ Governor
🏆 Production | ⚠️ Alert | 💡 Insight | 📈📉 차트 | ✅❌ 판정

---

## 브리핑 9종 템플릿

### 1. 모닝 브리핑 (크론 07:10 또는 세션 시작)
```
📊 [Q-Lead] 모닝 브리핑 YYYY-MM-DD

🏗️ 전천후 포트폴리오: XX%
  Core:XX% Div:XX% Def:XX% Ens:XX%

📈 Pipeline: S0(n) S1(n) S4(n) S5(n) S6(n) S7(n) PG(n)
🔄 Regime: CATEGORY (score)
💾 RAM: XX% | Claude: N | R: N

📋 금일 과제:
  1. ...
  2. ...
```

### 2. 전략 결과 (Forge 백테스트 완료)
```
🔨 [Forge] STR_XXXX 백테스트 완료

Grade: X | Score: XX.X (v2.2)
SR: X.XXX | CAGR: XX.X% | MDD: XX.X%
강점: ...
약점: ...

📈 차트 첨부 (equity_curve + annual_returns)
```

### 3. Judge 검증 완료
```
⚖️ [Judge] STR_XXXX S6 검증

Gate 0(PIT): PASS/FAIL
Gate 1(Hard): PASS/FAIL
Gate 2(FF5): alpha t=X.XX
Gate 3(DSR): X.XX
Gate 4(LOO): X/4 pass
Gate 5(Role): honest/dishonest

Grade: X | L-code: L-XXX 작성
```

### 4. 진척률 브리핑 (15분 주기 또는 요청 시)
```
📊 [Q-Lead] 전천후 포트폴리오 진척률 — XX%

🟢 Core Alpha:   ██████████ XX%
   상세...

🟡 Diversifier:  ██████░░░░ XX%
   상세...

🔴 Defense:      ██░░░░░░░░ XX%
   상세...

⬜ Ensemble:     ░░░░░░░░░░ XX%
   상태...

Gap: CAGR X% | SR X.XXX | MDD X%
```

### 5. 마일스톤 (S7 통과, PG 진입 등)
```
🏆 [Q-Lead] 마일스톤 달성!

STR_XXXX → S7 Approved (Grade A)
  역할: core_alpha/diversifier/defense
  다음: PG0 gap 진단 → PG1 admission
```

### 6. 경고 (RAM, stuck, 위반)
```
⚠️ [Q-Lead] 시스템 경고

RAM: 90% — Forge 추가 스폰 중단
또는: STR_XXXX S4 2시간+ stuck
또는: PIT 위반 감지 (artifact_validator)
```

### 7. Scout 가설 생성
```
🔍 [Scout] S0 가설 생성

팩터: FACTOR_NAME
역할: expected_role
gap 근거: why_now
학술: core_reference
교훈: lesson_check
```

### 8. Governor PG 판정
```
🏗️ [Governor] PG1 Admission

STR_XXXX → ADMIT/DEFER/REJECT
  Antipattern: 13/13 pass
  LOO: 4/4 pass
  Role Honesty: honest
  근거: ...
```

### 9. 세션 종료
```
📊 [Q-Lead] Session XX 종료

신규 전략: N건
Grade A 신규: N건
L-code 적립: N건
Pipeline 변동: S4(±N) S5(±N) S6(±N)
진척률: XX% → XX%
다음 과제: next_session_task.md 참조
```

### 10. Defense Sleeve 결과
```
🛡️ [Forge] STR_XXXX Defense S1 결과

📊 전기간: SR X.XXX | CAGR XX.X% | MDD XX.X%
🔻 Beta: X.XX (< 0.85 ✅/❌)

⚔️ 스트레스 구간 성과 (X/8 승리):
  ✅ GFC 2008: +X.X%p alpha
  ✅ COVID 2020: +X.X%p alpha
  ❌ Euro Debt: -X.X%p
  ...

📈 bad IC ratio: X.XX (위기 시 신호 강도)
🔗 Core 상관: X.XX (< 0.5 ✅/❌)

💡 강점: ...
⚠️ 약점: ...
📈 차트 첨부 (equity_curve + annual_returns)
```

### 이모지 누락 방지 (Level 0)
**모든 텔레그램 메시지에 이모지 필수. 텍스트만 전송 절대 금지.**
- 첫 줄: 에이전트 태그 이모지 (🔨🔍⚖️🏗️📊🛡️)
- 수치 앞: 📊📈📉
- 판정: ✅❌⚠️
- 차트 캡션: 📈📊 포함
- Forge가 tg_send() 호출 전 이모지 포함 여부 자체 검증
