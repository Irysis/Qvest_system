# S-D 계층 vintage 보류 → 해제(10:55) → **결함 정체 판명 + 확장 재실행 (07-18 오후)**

## ★결함 정체 확정 (타 세션 메모리 07-18: project-fdb-daily-rebuild-procedure / benchmark-parquet-date32)
결함 = benchmark.parquet Date dtype(POSIXct/date32 writer 불일치) → phase7 재merge 조인 silent all-NA → **β-계열 팩터 ~54종 전멸**. 함의 재해석:
- 그 전멸 세트는 **내 IC 패널에 애초 진입한 적 없음**(all-NA → min-pairs 규칙 자동 제외) → **적합된 169팩터 결과는 무오염**(2회 스냅샷 bit-identical과 정합 — 둘 다 phase6 값 기반). "identical" 판정 유지, 단 의미 = "적합 커버리지(169) 위 안정"이지 전체 174 아님.
- 실제 문제는 **커버리지 공백**: build1/2에 부재하던 β 54 + 추가 팩터들 = 미적합.
- **정본 3차 빌드(run_fdb_rebuild.sh, 07-18 15:40 registry, n_factors=298·rows 동일) 완주 확인** → S-D를 298팩터 fixed vintage로 확장 재실행(v3, build2 산출은 `*_build2_169f` 아카이브). 기대: 기존 169 라벨 재안정 확인 + β 54·M08/Q07/Q25·INV 등 129 신규 커버.

## ★해제 판정 (sd_vintage_diff_20260718.json)
재빌드 파이프라인 정온(전 phase 종료·10분 확인) 후 신 vintage(fdb_daily 20260718T1024, phase6 재실행분·phase7은 fdb parquet 무수정 확인)로 **S-D 전체 재실행 + 신구 diff**:
- **IC 패널 1,306,729셀 전부 max|Δ|=0** (값 변경 팩터 0/169, 행수 완전 일치)
- **라벨 162/162 동일 · break 시점 83/83 일 단위 동일** (1997-98·2021 클러스터 그대로 재현)
→ **F4·SD 부활밴드 83건·일간 IC 패널 = 유효 승격** (verdict: IDENTICAL — 재빌드가 S-D 소비면을 바꾸지 않음).
**잔여 조건(정직)**: 이 판정은 "재빌드 전후 동일"의 증명이지 절대 정합성의 증명이 아님 — 타 세션의 결함 정의가 미상이므로, 만약 결함이 "유니버스 행의 팩터 값 자체"로 판명되면(양 빌드 공유) F4는 재보류. 결함이 비소비 영역(비유니버스·phase7+ 산출·프로세스 상태)이면 본 판정 최종. 구판 산출은 `*_vintage0717suspect.parquet`로 보존(감사 가능).

---
(이하 원 보류 기록 — 2026-07-18 오전)

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
