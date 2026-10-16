# 아침 체인 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: morning_chain`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#morning_chain` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 아침 체인(Qvest_MorningBrief · MorningReboot → morning_run.sh)
- 일정: Qvest_MorningBrief 매일 07:10(주말 = 논문 파이프라인만) · Qvest_MorningReboot 부팅 시 따라잡기
- 코드: `02_Infrastructure/ops/morning_run.sh` · `02_Infrastructure/ops/morning_briefing.sh`
- 감시 규칙:
- `run_alerts` (log_patterns): 단계 경보(fail-soft), 재시도 소진, 재시도, R 오류
- `done_today` (expect_today): .cache/scheduler_logs/morning_run.log

## 알려진 고장 형태 (기억 카드 · 실측)

- 잠금 /tmp/qm_morning_run_<YYYYMMDD>.lock 은 날짜별 — 다음 날 새로 돈다. 재시도 상한(기본 3) · 직전 런 생존 중이면 종료(동시 실행 금지 · 2026-08-21 실사고).
- 단계 러너는 fail-soft — exit 0 이어도 '★경보발행' 이면 실질 실패다.
- 주말 = 논문 파이프라인만(브리핑 · 데이터 refresh skip). MorningReboot 은 부팅 시 따라잡기(trigger=reboot).
- 검사 배터리가 trigger=test 로 이 로그에 줄을 남긴다(상한 0/0) — 감시기는 그 블록을 제외한다.

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
