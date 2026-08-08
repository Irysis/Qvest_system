# 미커밋 운영 변경 스냅샷 — 2026-08-08

base commit: `fbc495fc` (이 커밋 위에서 만든 패치)
patch 검증: **APPLICABLE**

## 복원 (작업 트리가 리셋된 경우)
```bash
cd "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
git apply stage_artifacts/uncommitted_snapshot_20260808/tracked_changes.patch
cp -r stage_artifacts/uncommitted_snapshot_20260808/files/. .
```

## 담긴 것
- 추적 파일 변경 13 건 (patch, 311974 bytes)
- 신규 파일 5 건 (files/ 원본 복사)

## ★짝 제약
`forward_weights_D3_M4gAE.R`(미러) 와 `generator_pins.json`(sha1) 은 **짝**이다.
한쪽만 복원하면 월간 실행이 sha1 불일치로 abort 한다 — 항상 함께 복원할 것.
