package com.mumu.store.install;

import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.Process;
import android.util.Log;
import android.widget.Toast;
import android.os.Handler;
import android.os.Looper;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.JSONObject;

/** Clean implementation of MuMu's local-install entry point; ordinary APK only. */
public final class InstallLocalApkService extends Service {
    private static final String TAG = "MuMuMinimalInstaller";
    private static final String DESCRIPTOR = "com.mumu.store.install.LocalInstallInterface";
    private final ExecutorService queue = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final LocalBinder binder = new LocalBinder();

    private final class LocalBinder extends Binder implements IInterface {
        LocalBinder() { attachInterface(this, DESCRIPTOR); }
        public IBinder asBinder() { return this; }
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags)
                throws android.os.RemoteException {
            if (code == INTERFACE_TRANSACTION) {
                reply.writeString(DESCRIPTOR);
                return true;
            }
            if (code != FIRST_CALL_TRANSACTION) return super.onTransact(code, data, reply, flags);
            data.enforceInterface(DESCRIPTOR);
            String path = data.readString();
            String error = null;
            if (checkCallingPermission("android.permission.INSTALL_PACKAGES")
                    != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                throw new SecurityException("INSTALL_PACKAGES required");
            }
            if (path == null || path.isEmpty()) error = "invalid apk path !!";
            else {
                Intent request = new Intent().putExtra("apk_path", path);
                enqueue(request, 0);
            }
            reply.writeNoException();
            reply.writeString(error);
            return true;
        }
    }

    public void onCreate() {
        super.onCreate();
        event("service-created", "uid=" + Process.myUid(), null);
    }
    public IBinder onBind(Intent intent) { return binder; }
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) enqueue(new Intent(intent), startId);
        else stopSelf(startId);
        return START_NOT_STICKY;
    }
    public void onDestroy() {
        queue.shutdown();
        super.onDestroy();
    }
    private void enqueue(final Intent request, final int startId) {
        queue.execute(new Runnable() {
            public void run() {
                install(request);
                if (startId != 0) stopSelfResult(startId);
            }
        });
    }

    private void install(Intent request) {
        File staged = null;
        String path = request.getStringExtra("apk_path");
        String packageName = null;
        int user = request.getIntExtra("user_id", 0);
        try {
            if (user < 0) throw new IOException("Invalid Android user");
            event("request", request.toUri(0), null);
            Uri uri = request.getData();
            if (uri != null && "content".equals(uri.getScheme())) {
                staged = File.createTempFile("content-", ".apk", getCacheDir());
                try (InputStream input = getContentResolver().openInputStream(uri);
                        OutputStream output = new FileOutputStream(staged)) {
                    if (input == null) throw new IOException("Content URI unavailable");
                    byte[] bytes = new byte[65536];
                    int count;
                    while ((count = input.read(bytes)) != -1) output.write(bytes, 0, count);
                }
                staged.setReadable(true, false);
                path = staged.getCanonicalPath();
            } else if (path == null || path.isEmpty()) {
                path = resolveShared(request.getStringExtra("mount_name"),
                        request.getStringExtra("apk_name"));
            } else {
                path = validateFile(path);
            }
            if (!path.toLowerCase(Locale.ROOT).endsWith(".apk")) {
                throw new IOException("Prototype supports ordinary APK only; APKS/XAPK are not implemented");
            }
            PackageInfo info = getPackageManager().getPackageArchiveInfo(path, 0);
            if (info == null) throw new IOException("Invalid APK archive");
            packageName = info.packageName;
            if ("com.mumu.store".equals(packageName)) {
                throw new IOException("Self replacement requires the explicit rollback/install procedure");
            }
            launcher("com.mumu.ACTION_ADD_INSTALLATION", packageName, path, user, 11);
            String label = new File(path).getName();
            message("正在安装 " + label);
            event("install-start", path, packageName);
            String installer = path.startsWith("/mnt/shared/")
                    ? "host-file-mumu-app-store" : "server-file-mumu-app-store";
            Command result = command(Arrays.asList("/system/bin/pm", "install", "-i",
                    installer, "-r", "--user", Integer.toString(user), path), null, 180);
            if (result.exit != 0 || !result.output.matches("(?s).*\\bSuccess\\b.*")) {
                throw new IOException("pm exit=" + result.exit + ": " + result.output);
            }
            event("install-success", result.output.trim(), packageName);
            message("安装完成：" + label);
            launcher("com.mumu.ACTION_REMOVE_INSTALLATION", packageName, path, user, 12);
        } catch (Exception error) {
            event("install-failure", error.toString(), packageName);
            Log.e(TAG, "Installation failed", error);
            message("安装失败：" + error.getMessage());
            launcher("com.mumu.ACTION_REMOVE_INSTALLATION", packageName, path, user, 12);
        } finally {
            if (staged != null && !staged.delete()) Log.w(TAG, "Cannot delete staging file");
        }
    }

    private String validateFile(String path) throws IOException {
        File file = new File(path).getCanonicalFile();
        String canonical = file.getPath();
        if (!(canonical.startsWith("/mnt/shared/") || canonical.startsWith("/storage/")
                || canonical.startsWith("/data/local/tmp/"))) {
            throw new IOException("Unsupported APK source directory: " + canonical);
        }
        if (!file.isFile() || !file.canRead()) throw new IOException("APK is not readable: " + canonical);
        return canonical;
    }

    private String resolveShared(String mountName, String apkName) throws Exception {
        if (mountName == null || !mountName.matches("[a-zA-Z0-9_-]{1,128}")
                || apkName == null || apkName.isEmpty() || apkName.contains("/")
                || apkName.contains("\\") || apkName.equals("..")) {
            throw new IOException("Invalid dynamic shared-folder request");
        }
        File directory = new File("/mnt/shared", mountName);
        File apk = new File(directory, apkName);
        for (int attempt = 0; attempt < 4; attempt++) {
            if (apk.isFile() && apk.canRead()) return validateFile(apk.getPath());
            if (!directory.isDirectory() && !directory.mkdir()) {
                throw new IOException("Cannot create shared mount directory");
            }
            // These two tokens are generated from the validated ASCII mount identifier.
            // Match the original system-UID store's privileged MuMu mount helper protocol.
            String mountCommand = "new.mount.nemusf " + mountName + " " + directory.getPath() + "\nexit\n";
            Command mounted = command(Collections.singletonList("/system/bin/su"), mountCommand, 15);
            event("mount-attempt", "exit=" + mounted.exit + " " + mounted.output.trim(), null);
            Thread.sleep(500);
        }
        return validateFile(apk.getPath());
    }

    private static final class Command {
        final int exit;
        final String output;
        Command(int exit, String output) { this.exit = exit; this.output = output; }
    }
    private Command command(List<String> args, String input, int seconds) throws Exception {
        final java.lang.Process process = new ProcessBuilder(args).redirectErrorStream(true).start();
        final ByteArrayOutputStream capture = new ByteArrayOutputStream();
        final IOException[] readError = new IOException[1];
        Thread reader = new Thread(new Runnable() {
            public void run() {
                try (InputStream stream = process.getInputStream()) {
                    byte[] block = new byte[4096];
                    int length;
                    while ((length = stream.read(block)) != -1) {
                        if (capture.size() < 65536) capture.write(block, 0, Math.min(length, 65536 - capture.size()));
                    }
                } catch (IOException error) { readError[0] = error; }
            }
        }, "installer-output");
        reader.start();
        try (OutputStream stream = process.getOutputStream()) {
            if (input != null) stream.write(input.getBytes("UTF-8"));
        }
        if (!process.waitFor(seconds, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            reader.join(2000);
            throw new IOException("Command timed out after " + seconds + " seconds");
        }
        reader.join(2000);
        if (reader.isAlive()) throw new IOException("Command output did not finish");
        if (readError[0] != null) throw readError[0];
        return new Command(process.exitValue(), capture.toString("UTF-8"));
    }

    private void launcher(String action, String pkg, String path, int user, int state) {
        try {
            Intent update = new Intent(action).setPackage("app.lawnchair")
                    .putExtra("package", pkg).putExtra("file_path", path)
                    .putExtra("title", path == null ? "APK" : new File(path).getName())
                    .putExtra("user_id", user).putExtra("state", state);
            sendBroadcast(update);
        } catch (RuntimeException error) { Log.w(TAG, "Launcher callback", error); }
    }
    private void message(final String text) {
        ui.post(new Runnable() {
            public void run() { Toast.makeText(InstallLocalApkService.this, text, Toast.LENGTH_LONG).show(); }
        });
    }
    private synchronized void event(String kind, String detail, String pkg) {
        try {
            JSONObject record = new JSONObject().put("time", System.currentTimeMillis())
                    .put("event", kind).put("detail", detail).put("package", pkg);
            Log.i(TAG, record.toString());
            try (Writer writer = new OutputStreamWriter(new FileOutputStream(
                    new File(getFilesDir(), "minimal-installer-events.jsonl"), true), "UTF-8")) {
                writer.write(record.toString() + "\n");
            }
        } catch (Exception error) { Log.w(TAG, "Cannot record event", error); }
    }
}
