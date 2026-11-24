"""Work around plugin build files that newer Android Gradle Plugin versions reject.
Run after `flutter pub get` (CI). Edits only the pub cache copy.
"""
import os
import pathlib

cache = pathlib.Path(os.environ.get("PUB_CACHE", pathlib.Path.home() / (".pub-cache" if os.name != "nt" else "AppData/Local/Pub/Cache")))
for gradle in cache.glob("hosted/pub.dev/flutter_inappwebview_android-*/android/build.gradle"):
    s = gradle.read_text(encoding="utf-8")
    t = s.replace("getDefaultProguardFile('proguard-android.txt')", "getDefaultProguardFile('proguard-android-optimize.txt')")
    if t != s:
        gradle.write_text(t, encoding="utf-8")
        print("patched", gradle)
