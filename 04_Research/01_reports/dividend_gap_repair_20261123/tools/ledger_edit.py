# ledger_edit.py — 판 표식 원장(06_Registry/factor_db_vintage.json)에 한 줄을 열거나(open) 닫는다(close). 추가 전용.
#   쓰기 전 단정: 지금 파일을 읽어 같은 형식으로 다시 쓰면 바이트가 같다(형식 보존) · 같은 id 가 이미 있으면 open 거부 ·
#   close 는 그 id 의 completed_at 이 비어 있을 때만. 임시 파일 → 원자 교체. --check = 쓰지 않고 형식 보존만 확인.
import json, os, sys, datetime, tempfile
ROOT = "G:/OneDrive/Quant_Module_Moltbot"
P = os.path.join(ROOT, "06_Registry", "factor_db_vintage.json")
def dump(obj, nl):
    return (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").replace("\n", nl)
def load():
    raw = open(P, "rb").read()
    text = raw.decode("utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    obj = json.loads(text)
    same = dump(obj, nl).encode("utf-8") == raw
    return raw, obj, nl, same
def write(obj, nl):
    data = dump(obj, nl).encode("utf-8")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(P), prefix=".fdv_", suffix=".tmp")
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    for k in range(6):
        try:
            os.replace(tmp, P); return
        except PermissionError:
            import time; time.sleep(0.5)
    os.replace(tmp, P)
def now_kst():
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y-%m-%dT%H:%M:%S+09:00")
def main():
    mode = sys.argv[1]
    raw, obj, nl, same = load()
    print("형식 보존(읽어서 그대로 쓰면 같은 바이트):", same, "· 줄바꿈", repr(nl), "· 항목", len(obj["entries"]),
          "· 열린 줄", [e["id"] for e in obj["entries"] if e.get("completed_at") is None])
    if mode == "--check":
        return 0 if same else 2
    if not same:
        print("형식이 보존되지 않는다 — 쓰지 않음"); return 2
    spec = json.load(open(sys.argv[2], encoding="utf-8"))
    ids = [e["id"] for e in obj["entries"]]
    if mode == "open":
        if spec["id"] in ids:
            print("이미 있는 id — 쓰지 않음:", spec["id"]); return 3
        obj["entries"].append({"id": spec["id"], "completed_at": None, "scope": spec["scope"], "decision": spec["decision"],
                               "note": spec["note"], "evidence": spec["evidence"]})
    elif mode == "close":
        i = ids.index(spec["id"])
        if obj["entries"][i].get("completed_at") is not None:
            print("이미 닫힌 줄 — 쓰지 않음"); return 3
        obj["entries"][i]["completed_at"] = spec.get("completed_at") or now_kst()
        obj["entries"][i]["note"] = spec["note"]
        obj["entries"][i]["evidence"] = spec["evidence"]
    else:
        print("모드는 open | close | --check"); return 1
    write(obj, nl)
    raw2, obj2, nl2, same2 = load()
    print("썼다 ·", mode, spec["id"], "· 항목", len(obj2["entries"]), "· 다시 읽기 형식 보존", same2,
          "· 앞부분 불변", raw2[:len(raw) - 8] == raw[:len(raw) - 8] if mode == "open" else "n/a")
    return 0
sys.exit(main())
