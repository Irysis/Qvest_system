"""판 원장에 D2 부작용 수리 항목(진행 중 · 범위 = 밸류 · 성장 7팩터)을 한 줄 더한다 — 추가 전용 · 다른 바이트 보존(LF · 들여쓰기 2칸).
argv: ledger_path
왜: D2 팩터 DB 부분 재계산(stamp 20261114_182836)의 수리 명세 모듈 목록에 xlsx_fund 가 없어, 빌더의 XF → DART 채움 병합
  (factor_db_builder.R .fdb_xf_fill_merge — XF 행이 0 이면 건너뜀)이 돌지 않았다 → 7팩터가 DART 행만 남았다.
  completed_at 을 비워 두면 계약(contracts/factor_db_vintage.R)이 그 7팩터에 닿는 측정을 낡음으로 가린다. 수리가 끝나면 vintage_finalize 로 닫는다.
"""
import json, sys

path = sys.argv[1]
raw = open(path, "rb").read()
assert b"\r\n" not in raw
txt = raw.decode("utf-8")
d = json.loads(txt)
EID = "D2-XF-FILL-RESTORE-20261114"
assert not [x for x in d["entries"] if x["id"] == EID], "이미 있다"
FACTORS = ["V01_BM", "V02_EP", "V03_CFP", "V08_PSR", "GR01_Revenue_Growth", "GR02_Earnings_Growth", "GR03_Asset_Growth"]
entry = {
    "id": EID,
    "completed_at": None,   # 진행 중 = JSON null 만(계약 fdv_ledger 가 빈 문자열을 형식 위반으로 멈춘다 — 11-14 21:51 처음 판이 "" 로 써서 22:1x 에 null 로 고쳤다)
    "scope": {"factors": FACTORS},
    "decision": "RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114(D2 팩터 DB 재계산의 부작용 수리 — 이음매 세션 결함 · 11-14 21:5x 발견)",
    "note": ("D2 팩터 DB 부분 재계산(stamp 20261114_182836 · 판 원장 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114 21:40 완료)의 수리 명세 모듈 목록에 xlsx_fund 가 없어 "
             "빌더의 XF → DART 채움 병합(.fdb_xf_fill_merge — XF 행이 0 이면 건너뜀)이 돌지 않았다 → 밸류 · 성장 7팩터가 DART 행만 남았다"
             "(옛 파일 대비 '옛만' 약 7.4만 행 · 2015~ 연 1~7천 · 202611 340 · 값이 남은 행은 그대로). 다른 팩터는 영향 없음(채움 병합은 빌더 마지막 단계 · 대상 7팩터 행만 바꿔 끼웠다). "
             "수리 = value · growth · xlsx_fund 모듈로 7팩터만 전 기간 다시 계산(양성 대조 = 부분 산출 = 전체 산출 한 달) → IC · 결합용 뷰 → 202611 → completed_at. "
             "그때까지 7팩터에 닿는 측정은 낡음(팩터 목록을 선언한 칸 중 7팩터가 없는 칸만 비켜 간다 · 임의 코드 엔진은 닿은 것으로 본다)."),
    "evidence": (".cache/scheduler_logs/subset_worker_20261114_182836_r0_w*.jsonl(per_factor only_old) · .cache/scheduler_logs/subset_d2_202611.jsonl · "
                 "02_Infrastructure/factor_db/factor_db_builder.R .fdb_xf_fill_merge · "
                 "04_Research/01_reports/rawdata_seam_20260330_repair_20261113/d2_fill/repair_spec.json(modules 에 xlsx_fund 없음)"),
}
blk = json.dumps(entry, ensure_ascii=False, indent=2)
blk = "\n".join("    " + ln for ln in blk.split("\n"))
tail = "\n    }\n  ]\n}\n"
if not txt.endswith(tail):
    tail = tail[:-1]
assert txt.endswith(tail), "unexpected tail"
new = txt[: len(txt) - len(tail)] + "\n    },\n" + blk + tail[len("\n    }"):]
d2 = json.loads(new)
assert d2["entries"][:-1] == d["entries"] and d2["entries"][-1] == entry
assert {k: v for k, v in d2.items() if k != "entries"} == {k: v for k, v in d.items() if k != "entries"}
open(path, "wb").write(new.encode("utf-8"))
print("added", EID, "(in progress · factors", len(FACTORS), ")")
