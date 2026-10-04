"""Create a distributable ZIP without SDKs, signing material or investigation logs."""
import hashlib
import json
from pathlib import Path
import zipfile

project = Path(__file__).resolve().parent
out = project / "dist"
out.mkdir(exist_ok=True)
apk = project / "build" / "mumu-minimal-installer-0.1.apk"
expected = "a03ba9b5286402b4db0df9796a3bcbb82785cd49ac92f5c2ad4638235c63b43a"
assert hashlib.sha256(apk.read_bytes()).hexdigest() == expected, "Use the validated 0.1 APK"
target = out / "mumu-minimal-installer-0.1.1-windows.zip"
members = [project / name for name in ("AndroidManifest.xml", "Install.cmd", "Restore.cmd",
    "Manage-Installer.ps1", "build.py", "prepare_sdk.py", "package.py", "verification.json", "使用说明.txt")]
members += sorted((project / "src").rglob("*.java"))
members += [apk]
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for member in members:
        archive.write(member, member.relative_to(project).as_posix())
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert "build/mumu-minimal-installer-0.1.apk" in archive.namelist()
sums = out / "SHA256SUMS.txt"
sums.write_text("".join(hashlib.sha256(file.read_bytes()).hexdigest() + "  " + file.name + "\n"
                       for file in (apk, target)), encoding="ascii")
print(json.dumps({"zip": str(target), "zip_bytes": target.stat().st_size, "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}))
