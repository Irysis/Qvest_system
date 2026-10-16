# 텔레그램 발신기 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: telegram_emitter`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#telegram_emitter` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 텔레그램 발신기(telegram_notify.R · tg_agent_brief · prep_send)
- 일정: 모든 레인 · 세션의 발송
- 코드: `02_Infrastructure/telegram/telegram_notify.R` · `02_Infrastructure/programs/program_report.R`
- 감시 규칙:
- `send_failures` (log_patterns): 실발송 실패
- `dup_blocks` (log_patterns): 중복 차단

## 알려진 고장 형태 (기억 카드 · 실측)

- 한글 제목이 같은 잠금 키로 접혀 정상 발송이 '중복'으로 막혔다 — 2026-10-15 수리(.tg_title_scope · 커밋 4af1d800b).
- 발신 실패는 두 얼굴 — 미지 인자(예외)와 ok=FALSE(조용한 반환)(기억 카드 feedback-emitter-contract-…).
- 검사 배터리의 탐침(injection probe · No emoji · Briefing 📈 ready)은 실패 원장에 의도된 실패를 남긴다 — 감시기는 제외한다.
- 429(초당 발송 한도) 연속 — 대량 상세 발송(논문풀 적재 상세 n/29)에서 실측(2026-08-30).

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
