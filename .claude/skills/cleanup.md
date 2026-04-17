---
description: "작업폴더 위생 관리 — Rplots/로그/mailbox 처리완료/백업 파일 주기적 정리. bootstrap 시 자동 실행."
---

# Cleanup Skill

작업폴더 임시파일/로그/처리완료 mailbox를 정리합니다.

## 사용법
```bash
bash 02_Infrastructure/ops/cleanup.sh --dry-run    # 리포트만 (기본)
bash 02_Infrastructure/ops/cleanup.sh --execute    # 실제 삭제
```

## 정리 대상
| 대상 | 보존 기간 |
|------|-----------|
| Rplots.pdf | 즉시 삭제 |
| /tmp/qm_*.log | 7일 |
| 04_Research/logs/*.log | 30일 |
| mailbox DONE_*/processed/ | 14일 |
| .cache *_backup_* | 3일 |
| .cache 빈 하위폴더 | 즉시 |

## 안전장치
- `01_Literature/`, `05_Production/` 절대 미접근
- `--dry-run`이 기본값

## 실행 시점
- `/qvest` 부팅 시 bootstrap.sh에서 자동 호출
- crontab: 매주 일요일 새벽 3시
- 수동: 이 스킬 호출 시
