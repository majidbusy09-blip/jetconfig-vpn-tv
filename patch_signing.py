#!/usr/bin/env python3
"""Append release signing config to the end of app build.gradle / .kts"""
from pathlib import Path

GROOVY_TAIL = r'''
// --- JET TV release signing (appended) ---
def _jetKp = new Properties()
def _jetKpFile = rootProject.file("key.properties")
if (_jetKpFile.exists()) {
    _jetKp.load(new FileInputStream(_jetKpFile))
    android.signingConfigs {
        release {
            keyAlias _jetKp["keyAlias"]
            keyPassword _jetKp["keyPassword"]
            storeFile _jetKp["storeFile"] ? file(_jetKp["storeFile"]) : null
            storePassword _jetKp["storePassword"]
        }
    }
    android.buildTypes.release.signingConfig android.signingConfigs.release
}
'''

KTS_TAIL = r'''
// --- JET TV release signing (appended) ---
import java.util.Properties
import java.io.FileInputStream
val _jetKp = Properties()
val _jetKpFile = rootProject.file("key.properties")
if (_jetKpFile.exists()) {
    _jetKp.load(FileInputStream(_jetKpFile))
    android.signingConfigs {
        create("release") {
            keyAlias = _jetKp["keyAlias"] as String?
            keyPassword = _jetKp["keyPassword"] as String?
            storeFile = (_jetKp["storeFile"] as String?)?.let { file(it) }
            storePassword = _jetKp["storePassword"] as String?
        }
    }
    android.buildTypes.getByName("release").signingConfig =
        android.signingConfigs.getByName("release")
}
'''

MARKER = "// --- JET TV release signing"

def main() -> None:
    for name, tail in (
        ("android/app/build.gradle", GROOVY_TAIL),
        ("android/app/build.gradle.kts", KTS_TAIL),
    ):
        path = Path(name)
        if not path.exists():
            continue
        g = path.read_text(encoding="utf-8")
        if MARKER in g:
            g = g.split(MARKER)[0].rstrip() + "\n"
        path.write_text(g.rstrip() + "\n" + tail + "\n", encoding="utf-8")
        print("signing tail appended to", name)

if __name__ == "__main__":
    main()
