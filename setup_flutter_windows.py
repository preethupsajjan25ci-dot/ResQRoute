"""Generate Android platform files and copy the supplied Flutter app source."""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
PROJECT_DIR = ROOT / "resqroute_mobile"
SOURCE_DIR = ROOT / "mobile-source"


def main() -> int:
    if shutil.which("flutter") is None:
        print("Flutter was not found on PATH. Install Flutter, restart your terminal, then retry.")
        return 1

    if not (PROJECT_DIR / "android").exists():
        command = [
            "flutter", "create", "--platforms=android", "--org", "com.resqroute",
            "--project-name", "resqroute_mobile", str(PROJECT_DIR),
        ]
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            return result.returncode

    (PROJECT_DIR / "lib").mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE_DIR / "pubspec.yaml", PROJECT_DIR / "pubspec.yaml")
    shutil.copy2(SOURCE_DIR / "lib" / "main.dart", PROJECT_DIR / "lib" / "main.dart")

    # Local HTTP is only for development with a local backend; remove before deployment.
    manifest = PROJECT_DIR / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if manifest.exists():
        content = manifest.read_text(encoding="utf-8-sig")
        if "android.permission.INTERNET" not in content:
            content = content.replace(
                "<manifest ",
                '<manifest xmlns:tools="http://schemas.android.com/tools" ',
                1,
            ) if "xmlns:tools=" not in content else content
            content = content.replace(
                "<application",
                '    <uses-permission android:name="android.permission.INTERNET" />\n\n    <application',
                1,
            )
        if "android:usesCleartextTraffic" not in content:
            content = content.replace(
                "<application",
                '<application android:usesCleartextTraffic="true"',
                1,
            )
        manifest.write_text(content, encoding="utf-8")

    result = subprocess.run(["flutter", "pub", "get"], cwd=PROJECT_DIR)
    if result.returncode:
        return result.returncode

    print("\nFlutter setup finished.")
    print(f"Open this folder in VS Code: {PROJECT_DIR}")
    print("Start the backend in another terminal, then run: flutter run")
    print("For local development only, the Android manifest allows HTTP to the local backend.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
