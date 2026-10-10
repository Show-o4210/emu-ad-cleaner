// Native executable test double: never forwards commands to a real ADB/MuMu.
using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;

class FakeMuMu {
    static JavaScriptSerializer json = new JavaScriptSerializer();
    static Dictionary<string, object> Read(string file) {
        return json.Deserialize<Dictionary<string, object>>(File.ReadAllText(file));
    }
    static int Number(Dictionary<string, object> data, string key, int fallback) {
        return data.ContainsKey(key) ? Convert.ToInt32(data[key]) : fallback;
    }
    static string Str(Dictionary<string, object> data, string key, string fallback) {
        return data.ContainsKey(key) ? Convert.ToString(data[key]) : fallback;
    }
    static int Main(string[] args) {
        try { return Run(args); }
        catch (Exception error) { Console.Error.WriteLine(error.GetType().Name + ": " + error.Message); return 98; }
    }
    static int Run(string[] args) {
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);
        string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar)).FullName;
        string scenarioFile = Path.Combine(root, "scenario.json");
        string stateFile = Path.Combine(root, "state.json");
        var scenario = Read(scenarioFile);
        var state = File.Exists(stateFile) ? Read(stateFile) : new Dictionary<string, object> {
            {"version", Number(scenario, "version", 1225)},
            {"installed", Str(scenario, "installed", "true")},
            {"enabled", Number(scenario, "enabled", 0)},
            {"counts", new Dictionary<string, object>()}
        };
        bool manager = Path.GetFileName(Environment.GetCommandLineArgs()[0]).Equals("MuMuManager.exe", StringComparison.OrdinalIgnoreCase);
        File.AppendAllText(Path.Combine(root, "calls.jsonl"), json.Serialize(new { tool = manager ? "manager" : "adb", args = args }) + "\n");
        string command = string.Join(" ", args);
        if (!manager && args.Length >= 2 && args[0] == "-s") command = string.Join(" ", args, 2, args.Length - 2);
        string countKey = (manager ? "manager:" : "adb:") + command;
        var counts = (Dictionary<string, object>)state["counts"];
        int count = Number(counts, countKey, 0) + 1;
        counts[countKey] = count;
        string stdout = "", stderr = "";
        int exit = 0;
        if (manager) {
            var players = (Dictionary<string, object>)scenario["players"];
            if (count >= Number(scenario, "change_on", int.MaxValue)) {
                var player = (Dictionary<string, object>)players[Str(scenario, "change_index", "0")];
                string field = Str(scenario, "change_field", "adb_port");
                player[field] = scenario["change_value"];
            }
            stdout = json.Serialize(players);
            exit = Number(scenario, "manager_exit", 0);
        } else {
            Dictionary<string, object> response = null;
            if (scenario.ContainsKey("responses")) {
                var responses = (Dictionary<string, object>)scenario["responses"];
                string responseKey = command.StartsWith("install ") ? "install" : command;
                if (responses.ContainsKey(responseKey)) {
                    var queue = (System.Collections.IList)responses[responseKey];
                    response = (Dictionary<string, object>)queue[Math.Min(count - 1, queue.Count - 1)];
                }
            }
            bool apply = response == null || (response.ContainsKey("apply") && Convert.ToBoolean(response["apply"]));
            if (command == "version") stdout = "Android Debug Bridge version 1.0.41\nVersion 36.0.0-test";
            else if (command.StartsWith("connect ")) stdout = "connected to " + command.Substring(8);
            else if (command == "get-state") stdout = "device";
            else if (command == "shell ls /system/priv-app/com.mumu.store/com.mumu.store.apk") stdout = "/system/priv-app/com.mumu.store/com.mumu.store.apk";
            else if (command == "shell dumpsys package com.mumu.store") {
                stdout = "versionCode=" + state["version"] + "\nversionName=" + (Convert.ToInt32(state["version"]) == 1226 ? "minimal-prototype-0.1" : "9.2.25") +
                    "\nsharedUser=android.uid.system/1000\nUser 0: installed=" + state["installed"] + " hidden=false enabled=" + state["enabled"];
            } else if (command.StartsWith("install ")) { if (apply) state["version"] = 1226; stdout = "Success"; }
            else if (command == "shell cmd package install-existing --user 0 com.mumu.store") { if (apply) state["installed"] = "true"; stdout = "Package installed for user: 0"; }
            else if (command == "shell pm default-state --user 0 com.mumu.store") { if (apply) state["enabled"] = 0; stdout = "Package new state: default"; }
            else if (command == "shell pm uninstall-system-updates com.mumu.store") { if (apply) state["version"] = 1225; stdout = "Success"; exit = 1; }
            else if (command == "shell pm path com.mumu.store") stdout = "package:/system/priv-app/com.mumu.store/com.mumu.store.apk";
            else { stderr = "Unexpected test command: " + command; exit = 99; }
            if (response != null) {
                stdout = Str(response, "stdout", ""); stderr = Str(response, "stderr", ""); exit = Number(response, "exit", 0);
            }
        }
        File.WriteAllText(stateFile, json.Serialize(state));
        if (stdout.Length > 0) Console.Out.WriteLine(stdout);
        if (stderr.Length > 0) Console.Error.WriteLine(stderr);
        return exit;
    }
}
