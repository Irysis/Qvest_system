# FQ-073: 관세청 수출입 통계 API 실호출 probe
# 키는 .env DATA_GO_API_KEY 에서만 읽고, 출력은 전부 마스킹한다.
import os, sys, urllib.parse, urllib.request, ssl, re, json

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

def load_key():
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("DATA_GO_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("DATA_GO_API_KEY not found")

KEY_RAW = load_key()
# data.go.kr 키는 Encoding(%2B..)/Decoding(+..) 두 형태. 둘 다 시험.
KEY_DEC = urllib.parse.unquote(KEY_RAW)
KEY_ENC = urllib.parse.quote(KEY_DEC, safe="")

def mask(s):
    """키 값이 절대 출력되지 않도록 치환."""
    for k in (KEY_RAW, KEY_DEC, KEY_ENC):
        if k:
            s = s.replace(k, "<KEY>")
            s = s.replace(urllib.parse.quote(k, safe=""), "<KEY>")
    return s

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

def call(base, params, keyform="enc", timeout=30, ua=True):
    """serviceKey는 이미 인코딩된 문자열이므로 직접 조립(재인코딩 방지)."""
    kv = KEY_ENC if keyform == "enc" else urllib.parse.quote(KEY_DEC, safe="+/=")
    if keyform == "raw":
        kv = KEY_RAW
    qs = "serviceKey=" + kv
    for k, v in params.items():
        qs += "&" + k + "=" + urllib.parse.quote(str(v), safe="")
    url = base + "?" + qs
    req = urllib.request.Request(url)
    if ua:
        req.add_header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        req.add_header("Accept", "*/*")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            body = r.read().decode("utf-8", "replace")
            return r.status, body, mask(r.geturl())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        return e.code, body, mask(url)
    except Exception as e:
        return -1, "EXC: %s" % type(e).__name__ + " " + str(e), mask(url)

def show(tag, base, params, keyform="enc", n=900):
    st, body, url = call(base, params, keyform)
    body = mask(body)
    one = re.sub(r"\s+", " ", body).strip()
    print("=" * 78)
    print("[%s] keyform=%s" % (tag, keyform))
    print("URL : " + mask(base + "?serviceKey=<KEY>&" +
                          "&".join("%s=%s" % (k, v) for k, v in params.items())))
    print("HTTP: %s" % st)
    print("BODY: %s" % one[:n])
    return st, body

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    print("key len(raw)=%d len(dec)=%d  url_encoded_form=%s"
          % (len(KEY_RAW), len(KEY_DEC), KEY_RAW != KEY_DEC))
