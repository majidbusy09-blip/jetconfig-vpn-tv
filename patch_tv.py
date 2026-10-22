#!/usr/bin/env python3
# پچ Manifest و Gradle برای Android TV — جدا از اپ موبایل
from pathlib import Path
import re

def patch_manifest():
    p = Path("android/app/src/main/AndroidManifest.xml")
    if not p.exists():
        raise SystemExit("AndroidManifest.xml not found")
    t = p.read_text(encoding="utf-8")

    t = re.sub(r'android:label="[^"]*"', 'android:label="JET VPN TV"', t)

    if "android.software.leanback" not in t and "<application" in t:
        inject = (
            '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
            '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
            '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        )
        t = t.replace("<application", inject + "    <application", 1)

    if "LEANBACK_LAUNCHER" not in t:
        block = (
            "\n                <intent-filter>\n"
            '                    <action android:name="android.intent.action.MAIN"/>\n'
            '                    <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>\n'
            "                </intent-filter>"
        )
        needle = 'android.intent.category.LAUNCHER"/>'
        idx = t.find(needle)
        if idx != -1:
            end = t.find("</intent-filter>", idx)
            if end != -1:
                end = end + len("</intent-filter>")
                t = t[:end] + block + t[end:]

    p.write_text(t, encoding="utf-8")
    print("manifest ok")


def patch_gradle():
    for name in ("android/app/build.gradle", "android/app/build.gradle.kts"):
        path = Path(name)
        if not path.exists():
            continue
        g = path.read_text(encoding="utf-8")
        g = re.sub(r"minSdkVersion\s+[^\n]+", "minSdkVersion 24", g)
        g = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", g)
        g = re.sub(r"compileSdkVersion\s+[^\n]+", "compileSdkVersion 35", g)
        g = re.sub(r"compileSdk\s*=\s*[^\n]+", "compileSdk = 35", g)
        g = re.sub(r"targetSdkVersion\s+[^\n]+", "targetSdkVersion 35", g)
        g = re.sub(r"targetSdk\s*=\s*[^\n]+", "targetSdk = 35", g)
        path.write_text(g, encoding="utf-8")
        print("gradle ok:", name)


if __name__ == "__main__":
    patch_manifest()
    patch_gradle()
