# 예약 작업 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: scheduler`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#scheduler` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 예약 작업(Windows 작업 스케줄러 · scheduler_task_health.sh)
- 일정: 아침 체인 [0.7] · Qvest_StrandedRepairs
- 코드: `02_Infrastructure/ops/scheduler_task_health.sh` · `02_Infrastructure/ops/scheduler/`
- 감시 규칙:
- `task_health` (log_patterns): 새 실패, 정체 작업

## 알려진 고장 형태 (기억 카드 · 실측)

- Qvest_AuditWatch 는 관리자 권한 작업이라 세션이 켤 수 없다(도훈이 작업 스케줄러에서 직접).
- 데스크톱 앱(MSIX) 세션의 AppData 쓰기는 가상화된다 — 예약 작업은 실디스크를 본다(기억 카드 reference-desktop-app-msix-…).
- 2026-10-10~10-15 예약 작업 비활성 기간의 '정체' 흔적은 사건이 아니다.

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
