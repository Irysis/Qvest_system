"""Probe NPS endpoints. NEVER prints the API key (masked at all times)."""
import os, re, sys, json, urllib.parse, urllib.request, ssl

ROOT = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
key = None
with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if line.startswith("DATA_GO_API_KEY"):
            key = line.split("=", 1)[1].strip().strip('"').strip("'")
            break
if not key:
    print("NO KEY FOUND"); sys.exit(1)

MASK = "<KEY:%d chars, %s...%s>" % (len(key), key[:3], key[-2:])


def mask(s):
    out = s.replace(key, "<KEY>")
    try:
        out = out.replace(urllib.parse.quote(key, safe=""), "<KEY>")
        out = out.replace(urllib.parse.quote_plus(key), "<KEY>")
        out = out.replace(urllib.parse.unquote(key), "<KEY>")
    except Exception:
        pass
    return out


ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def call(label, base, params, decoded=True):
    k = urllib.parse.unquote(key) if decoded else key
    qs = urllib.parse.urlencode(dict(params, serviceKey=k), quote_via=urllib.parse.quote)
    url = base + "?" + qs
    print("\n=== %s ===" % label)
    print("URL: " + mask(url))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=45, context=ctx) as r:
            body = r.read().decode("utf-8", "replace")
            print("HTTP=%d len=%d" % (r.status, len(body)))
            print("BODY[:1400]: " + mask(body[:1400]))
            return r.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        print("HTTP=%d (HTTPError) len=%d" % (e.code, len(body)))
        print("BODY[:1400]: " + mask(body[:1400]))
        return e.code, body
    except Exception as e:
        print("EXC: " + mask(str(e)))
        return None, ""


print("Key loaded: " + MASK)

V2 = "https://apis.data.go.kr/B552015/NpsBplcInfoInqireServiceV2"
V1 = "https://apis.data.go.kr/B552015/NpsBplcInfoInqireService"

# 1) V2 basic search (required: wkplNm)
call("V2 getBassInfoSearchV2 (decoded key)", V2 + "/getBassInfoSearchV2",
     {"wkplNm": "삼성전자", "numOfRows": "3", "pageNo": "1", "dataType": "JSON"})

# 2) V2 with encoded key (in case .env stores decoded)
call("V2 getBassInfoSearchV2 (raw/encoded key)", V2 + "/getBassInfoSearchV2",
     {"wkplNm": "삼성전자", "numOfRows": "3", "pageNo": "1", "dataType": "JSON"}, decoded=False)

# 3) V1 control (expected: the previously observed 500)
call("V1 getBassInfoSearch (control)", V1 + "/getBassInfoSearch",
     {"wkplNm": "삼성전자", "numOfRows": "3", "pageNo": "1"})

# 4) odcloud 15083277 control (expected: -401 not authorized)
odc = "https://api.odcloud.kr/api/15083277/v1/uddi:b9bf303e-a60e-4a49-a517-99797889484e"
call("odcloud 15083277 (control)", odc,
     {"page": "1", "perPage": "3", "returnType": "JSON"})
