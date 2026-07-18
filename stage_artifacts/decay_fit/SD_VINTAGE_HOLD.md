# S-D 계층 vintage 보류 (2026-07-18, 도훈 제기)

**사유**: S-D 일간 계층이 소비한 fdb_daily vintage(registry v6.0.0, created 2026-07-17T20:25:55, total_rows 14,018,027 — prereg_SD.json 기록)가 **타 세션에서 결함 판정 → 전면 재빌드 중**(2026-07-18 확인: fdb_daily 0파일·registry 삭제·phase6 재실행 중). 결함 내용은 본 세션 미확인.

## 보류(vintage-suspect) 대상 — 재빌드 완료 전 인용 금지
- `decay_fit_SD_20260718.parquet` (S-D 적합 162행 — break 83·no_init 74 등)
- `sd_ic_daily_panel_20260718.parquet` (일간 IC 패널 174팩터 — suspect vintage 파생)
- `revival_bands_20260718.parquet` 중 **layer=="SD" 83행** (SM 158행은 유효)
- L-AR-20260718_103500의 **F4**(1d-horizon 단절 1997-98·2021·C-M 일치 0.05) + next_probe P3
- 텔레그램 브리핑(07-18)의 "일간(1d) 신호력 단절" bullet

## 유효 유지 (fdb_daily 무관 — 입력이 pinned 월간 IC 패널 + r6 패널 + rawdata)
- S-M·C-M 전 산출: **F1(계단 단절 지배·월간 235건 high) / F2(2018-19→기저 2016-17 날짜) / F3(dual-basis 괴리 34건) / F5(북 팩터)** — 라운드 헤드라인 전부 월간 계층 산출.
- "벽=전이·벤치 계층" 결론은 F3+기존 아크로 성립 — F4는 *추가* 확증 경로였고 회수되어도 결론 비의존.

## 재개 절차 (재빌드 완료 시)
1. 무결성 게이트(파일수·zero-size·registry) + old/new registry diff(n_factors·total_rows — 결함 규모 추정)
2. 구 패널 아카이브: `sd_ic_daily_panel_20260718.parquet` → `_vintage20260717suspect` 접미
3. `run_decay_fit_daily.R` 재실행(패널 캐시 부재 시 stage1 자동 재구축, ~10분)
4. old/new 라벨·break-date diff 실측 → F4 판정 갱신 + 텔레그램 정정 동봉
