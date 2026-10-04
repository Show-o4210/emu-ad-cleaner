"""Direct SDK build. No Gradle or modifications to any emulator."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = Path(__file__).resolve().parent
SDK = Path(os.environ.get("MUMU_ANDROID_SDK_ROOT", r"F:\Tools\.agent\tools\android-sdk\35"))
BUILD_TOOLS = SDK / "build-tools" / "35.0.0"
PLATFORM = SDK / "platforms" / "android-35" / "android.jar"
KEYS = Path(os.environ.get("MUMU_TEST_KEY_DIR", r"F:\Tools\.agent\tools\aosp-test-platform-key\public-test-key"))
OUT = PROJECT / "build"

def run(*args):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        print(result.stderr.strip())

def public_test_material():
    KEYS.mkdir(parents=True, exist_ok=True)
    base = "https://raw.githubusercontent.com/aosp-mirror/platform_build/master/target/product/security/"
    for name in ("platform.pk8", "platform.x509.pem"):
        target = KEYS / name
        if not target.exists():
            with urllib.request.urlopen(base + name, timeout=30) as source:
                target.write_bytes(source.read())

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    classes = OUT / "classes"
    dex = OUT / "dex"
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    public_test_material()
    run(BUILD_TOOLS / "aapt2.exe", "link", "-o", OUT / "resources.apk", "--manifest",
        PROJECT / "AndroidManifest.xml", "-I", PLATFORM)
    sources = sorted((PROJECT / "src").rglob("*.java"))
    run("javac", "-J-Duser.language=en", "-J-Duser.country=US", "--release", "8", "-encoding", "UTF-8", "-classpath", PLATFORM,
        "-d", classes, *sources)
    jar = OUT / "classes.jar"
    with zipfile.ZipFile(jar, "w", zipfile.ZIP_DEFLATED) as z:
        for file in sorted(classes.rglob("*.class")):
            z.write(file, file.relative_to(classes).as_posix())
    run("java", "-cp", BUILD_TOOLS / "lib" / "d8.jar", "com.android.tools.r8.D8",
        "--min-api", "26", "--lib", PLATFORM, "--output", dex, jar)
    unsigned = OUT / "unsigned.apk"
    with zipfile.ZipFile(OUT / "resources.apk") as original, zipfile.ZipFile(unsigned, "w") as z:
        for member in original.infolist():
            z.writestr(member, original.read(member))
        z.write(dex / "classes.dex", "classes.dex", compress_type=zipfile.ZIP_DEFLATED)
    run(BUILD_TOOLS / "zipalign.exe", "-f", "4", unsigned, OUT / "aligned.apk")
    signed = OUT / "mumu-minimal-installer-0.1.apk"
    run("java", "-jar", BUILD_TOOLS / "lib" / "apksigner.jar", "sign", "--key", KEYS / "platform.pk8",
        "--cert", KEYS / "platform.x509.pem", "--out", signed, OUT / "aligned.apk")
    run("java", "-jar", BUILD_TOOLS / "lib" / "apksigner.jar", "verify", "--verbose", "--print-certs", signed)
    run(BUILD_TOOLS / "zipalign.exe", "-c", "4", signed)
    run(BUILD_TOOLS / "aapt2.exe", "dump", "badging", signed)
    record = {"apk": str(signed), "size": signed.stat().st_size,
              "sha256": hashlib.sha256(signed.read_bytes()).hexdigest(),
              "source_sha256": {str(p.relative_to(PROJECT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in [PROJECT / "AndroidManifest.xml", *sources]},
              "status": "built-and-signed; emulator compatibility untested"}
    (OUT / "build-report.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps(record, indent=2))
