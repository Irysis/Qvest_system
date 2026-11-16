"""registry_1116_apply.py — 수동 채움 등록부에 이음매 묶음 6행 붙이기(11-16 · RAWDATA-7ROWS-CORPACTION-REQUERY-20261115 묶음을
RAWDATA-PRELISTING-EXCLUDE-20261116 범위 all 수리에 싣는다 — 묶음 명세 procedure ①).

 묶음 명세(04_Research/01_reports/rawdata_seam_20260330_repair_20261113/d2_fill/pending_bundle_20261115.json)의
 entries_change 3 + entries_pin 3 을 entries 끝에 붙인다(ret_before 열은 뺀다). 기존 14행은 그대로(11-16 도훈 정정 — 상장 첫날 Ret = 저장값).
 형식 보존 = JSON 들여쓰기 2 · CRLF(읽은 파일을 같은 형식으로 다시 쓰면 바이트가 같은지 먼저 확인 — 다른 바이트 보존) · tmp → 교체.
 사용: python registry_1116_apply.py [--apply]   (저장소 루트에서 · 쓰기는 RAWDATA writer 잠금 아래에서)
"""
import json
import os
import sys
from pathlib import Path

APPLY = "--apply" in sys.argv[1:]
REG = Path("06_Registry/ret_fill_registry.json")
SPEC = Path("04_Research/01_reports/rawdata_seam_20260330_repair_20261113/d2_fill/pending_bundle_20261115.json")


def dump(o):
    return ((json.dumps(o, ensure_ascii=False, indent=2) + "\n").replace("\n", "\r\n")).encode("utf-8")


b0 = REG.read_bytes()
reg = json.loads(b0.decode("utf-8"))
assert dump(reg) == b0, "등록부를 같은 형식으로 다시 쓰면 바이트가 달라진다 — 형식 확인 뒤 다시"
spec = json.loads(SPEC.read_text(encoding="utf-8"))
assert spec.get("status") == "pending", f"명세 status = {spec.get('status')} — pending 이 아니다"
add = [{k: v for k, v in e.items() if k != "ret_before"} for e in spec["entries_change"] + spec["entries_pin"]]
new = dict(reg)
new["entries"] = reg["entries"] + add
keys = [(e["Date"], e["Ticker"]) for e in new["entries"]]
assert len(keys) == len(set(keys)), "등록부 키 중복(이미 붙였나?)"
b1 = dump(new)
print(f"등록부 {len(reg['entries'])} → {len(new['entries'])}행(붙임 {len(add)} = 값 변경 {len(spec['entries_change'])} + 고정 {len(spec['entries_pin'])}) · {'APPLY' if APPLY else 'DRY-RUN'}")
if APPLY:
    tmp = REG.with_name("." + REG.name + ".tmp")
    tmp.write_bytes(b1)
    os.replace(tmp, REG)
    assert REG.read_bytes() == b1
    print(f"썼다: {REG}")
