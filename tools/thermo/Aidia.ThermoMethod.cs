// AIDIA-owned local helper. No Thermo assemblies are redistributed or referenced
// at build time. Public members of the user's installed runtime are version gated.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Xml;
using STATSTG = System.Runtime.InteropServices.ComTypes.STATSTG;

internal static class Program
{
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 67108864 };
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    static string runtime;
    static object api;
    static object method, ms1, ms2, list;
    static object[] diaExperiments;
    static readonly Dictionary<string, HashSet<string>> EditorColumns = new Dictionary<string, HashSet<string>>();
    static string summary;
    static double duration;
    sealed class Profile {
        internal string Instrument, Model, Code, RuntimeName, Build, DllVersion;
        // Verified installation layout belongs to the model adapter. Discovery
        // and config lookup stay shared when another Thermo family is added.
        internal string InstallDirectory, ImplementationFile, LauncherFile;
    }
    static readonly Profile[] Profiles = {
        new Profile {Instrument="exploris", Model="Orbitrap Exploris 480", Code="Merkur_A",
            RuntimeName="Exploris 480 Workstation 5.1 SP1", Build="5.1.761.17", DllVersion="5.0.4564.7",
            InstallDirectory=@"Thermo Scientific\Instruments\Exploris\5.1",
            ImplementationFile=@"System\Programs\dependencies\tng\Thermo.TNG.Merkur.MethodXML.dll",
            LauncherFile=@"System\Programs\Thermo.Exploris.Method.EditorLauncher.exe"},
        new Profile {Instrument="astral_zoom", Model="Orbitrap Astral Zoom", Code="Merkur_OA",
            RuntimeName="Astral Workstation 2.2 SP1", Build="2.2.821.21", DllVersion="5.0.4647.12",
            InstallDirectory=@"Thermo Scientific\Instruments\Astral\2.2",
            ImplementationFile=@"System\Programs\dependencies\tng\Thermo.TNG.Merkur.MethodXML.dll",
            LauncherFile=@"System\Programs\Thermo.Exploris.Method.EditorLauncher.exe"}
    };
    static Profile profile;
    static bool Astral { get { return profile.Instrument == "astral_zoom"; } }
    static bool Dia { get { return ms2.GetType().Name == "MerkurDIAScan"; } }
    static bool IsMS2(object scan) { return scan.GetType().Name == "MerkurTMSnScan" || (Astral && scan.GetType().Name == "MerkurDIAScan"); }
    static readonly HashSet<string> Geometry = new HashSet<string> {
        "CompoundName", "MoverZ", "Z", "IsolationWindow", "StartTime", "EndTime",
        "RetentionTime", "RetentionWindow", "RowIndex", "Formula", "AdductPositive", "AdductNegative" };
    static readonly HashSet<string> RowOverrides = new HashSet<string> {
        "MaxITTime", "AgcTarget", "Resolution", "MicroScans", "Offset" };

    static object Get(object o, string name) {
        var t = o.GetType(); var p = t.GetProperty(name);
        if (p != null) return p.GetValue(o, null);
        var f = t.GetField(name);
        if (f != null) return f.GetValue(o);
        throw new InvalidOperationException("Runtime member unavailable: " + t.Name + "." + name);
    }
    static void Set(object o, string name, object value) {
        var p = o.GetType().GetProperty(name); var f = o.GetType().GetField(name);
        var t = p != null ? p.PropertyType : f != null ? f.FieldType : null;
        if (t == null) throw new InvalidOperationException("Runtime member unavailable: " + name);
        object v = t.IsInstanceOfType(value) ? value : t.IsEnum ? Enum.Parse(t, Convert.ToString(value, Inv)) : Convert.ChangeType(value, t, Inv);
        if (p != null) p.SetValue(o, v, null); else f.SetValue(o, v);
    }
    static object Call(object o, string name, params object[] args) {
        return o.GetType().GetMethod(name, args.Select(x => x.GetType()).ToArray()).Invoke(o, args);
    }
    static double Number(object o, string name) { return Convert.ToDouble(Get(o, name), Inv); }
    static string Str(object o, string name) { return Convert.ToString(Get(o, name), Inv); }
    static IList Items(object o, string name) { return (IList)Get(o, name); }
    static Dictionary<string, object> Dict(object o) { return (Dictionary<string, object>)o; }
    static string Hash(string path) { using (var s = File.OpenRead(path)) using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(s)).Replace("-", "").ToLowerInvariant(); }
    static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }

    static string RuntimeConfigPath(Dictionary<string, object> request) {
        object path;
        return Path.GetFullPath(request.TryGetValue("runtime_config_path", out path) && path != null ? (string)path :
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "config", "instruments.json"));
    }

    static string ConfiguredRuntime(Profile selected, string path) {
        if (!File.Exists(path)) return null;
        try {
            var settings = Json.DeserializeObject(File.ReadAllText(path)) as Dictionary<string, object>;
            Require(settings != null, "Expected the instruments.json configuration object.");
            object entry;
            if (!settings.TryGetValue(selected.Instrument, out entry)) return null;
            var instrument = entry as Dictionary<string, object>;
            Require(instrument != null, selected.Instrument + " must be an instrument configuration object.");
            object value;
            if (!instrument.TryGetValue("thermo_runtime_path", out value) || value == null) return null;
            Require(value is string, selected.Instrument + ".thermo_runtime_path must be an installation path string.");
            if (string.IsNullOrWhiteSpace((string)value)) return null;
            var root = Environment.ExpandEnvironmentVariables(((string)value).Trim());
            // IsPathRooted alone accepts drive-relative C:folder and \folder.
            Require(Regex.IsMatch(root, @"^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+(?:[\\/]|$))"),
                selected.Instrument + ".thermo_runtime_path must be an absolute installation path.");
            return Path.GetFullPath(root);
        } catch (Exception e) {
            throw new InvalidOperationException("Cannot read Thermo configuration " + path + ": " + e.Message, e);
        }
    }

    static string FindRuntime(Dictionary<string, object> request, Profile selected) {
        Require(new[] {selected.InstallDirectory, selected.ImplementationFile, selected.LauncherFile,
            selected.RuntimeName, selected.Build, selected.DllVersion}.All(p => !string.IsNullOrWhiteSpace(p)),
            "Incomplete verified runtime profile for " + selected.Instrument + ".");
        object custom;
        // Preserve the explicit R option for scripts that intentionally select
        // one runtime. Normal app use tries the default before reading config.
        if (request.TryGetValue("runtime_path", out custom) && custom != null)
            return ValidateRuntime((string)custom, selected);
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), selected.InstallDirectory);
        string failure;
        try { return ValidateRuntime(root, selected); }
        catch (Exception e) { failure = e.Message + " Checked default installation: " + root + "."; }
        var config = RuntimeConfigPath(request);
        try {
            var configured = ConfiguredRuntime(selected, config);
            if (configured != null) return ValidateRuntime(configured, selected);
        } catch (Exception e) { failure += " " + e.Message; }
        var example = Json.Serialize(new Dictionary<string, string> {
            {"thermo_runtime_path", "D:/" + selected.InstallDirectory.Replace('\\', '/')}
        });
        throw new InvalidOperationException(failure + " If Workstation is installed elsewhere, edit " + config +
            " and set " + selected.Instrument + ".thermo_runtime_path to the installation root folder. Example field: " +
            example + ". Keep the other instrument settings and use forward slashes in JSON paths. Save, then retry the .meth upload. Install the matching Workstation if it is not installed.");
    }

    static string ValidateRuntime(string root, Profile selected) {
        var dll = Path.Combine(root, selected.ImplementationFile);
        var required = selected.RuntimeName + " (" + selected.Build + ")";
        Require(File.Exists(dll), "Install " + required + " on this Windows PC to read or write this method. Missing: " + dll);
        Require(FileVersionInfo.GetVersionInfo(dll).FileVersion == selected.DllVersion, "This Thermo runtime version has not been validated at " + root + ". Required: " + required);
        var launcher = Path.Combine(root, selected.LauncherFile);
        Require(File.Exists(launcher) && FileVersionInfo.GetVersionInfo(launcher).FileVersion == selected.Build,
            "Native methods require " + required + ". Check the launcher in " + root + ".");
        return Path.GetDirectoryName(dll);
    }

    static object Probe(Dictionary<string, object> request) {
        var results = Profiles.Select(p => {
            try { var dir = FindRuntime(request, p); return new {instrument=p.Instrument, model=p.Model, available=true, runtime_version=p.Build, path=dir, reason=(string)null}; }
            catch (Exception e) { return new {instrument=p.Instrument, model=p.Model, available=false, runtime_version=p.Build, path=(string)null, reason=e.Message}; }
        }).ToArray();
        return new {available=results.Any(r => r.available), config_path=RuntimeConfigPath(request), runtimes=results};
    }

    static void Open(string path) {
        Require(new FileInfo(path).Length <= 64 * 1024 * 1024, "Method exceeds the 64 MB size limit.");
        // The stored summary selects a runtime; the serialized instrument code
        // independently verifies it before any model-dependent initialization.
        var fileLib = Assembly.LoadFrom(Path.Combine(runtime, "Thermo.TNG.Common.FileLib.dll"));
        var storage = Activator.CreateInstance(fileLib.GetType("Thermo.TNG.Common.FileLib.COMIStorageMethodFile", true),
            new object[] {path, FileMode.Open, FileAccess.Read, "Merkur"});
        object data = null;
        try {
            data = Call(storage, "GetMethod");
            Require(data != null, "Thermo could not read the stored method. Close other readers of this file and retry with a local copy.");
            Require(Str(data, "InstModel") == profile.Code,
                "The stored instrument code does not match the method title. Choose a method saved by the matching instrument editor.");
        } finally { if (data is IDisposable) ((IDisposable)data).Dispose(); if (storage is IDisposable) ((IDisposable)storage).Dispose(); }
        var assembly = Assembly.LoadFrom(Path.Combine(runtime, "Thermo.TNG.Merkur.MethodXML.dll"));
        api = Activator.CreateInstance(assembly.GetType("Thermo.TNG.Merkur.MethodXML.MerkurMethodXML", true));
        if (Astral) {
            var standard = Assembly.LoadFrom(Path.Combine(runtime, "Thermo.TNG.Common.Standard.dll"));
            var sysInfo = standard.GetType("Thermo.TNG.Common.Config.SysInfo").GetProperty("Instance").GetValue(null, null);
            var config = Get(Get(sysInfo, "Data"), "Configuration");
            Set(config, "InstrumentModel", profile.Code); Set(config, "IsWorkstation", true);
            standard.GetType("Thermo.TNG.Common.Utils.TNGDirectoryInitializer").GetMethod("Initialize").Invoke(null, null);
        }
        Call(api, "Initialize", true); Call(api, "Open", path); Call(api, "EnableValidation", true);
        Bind(); Validate(); Bind();
    }
    static void Bind() {
        method = Get(api, "Method"); summary = (string)Call(api, "GetMethodSummary");
        Require(Str(method, "OldInstrumentModel") == profile.Code &&
            summary.StartsWith(profile.Model + " Method Summary", StringComparison.Ordinal), "Thermo loaded an unexpected instrument model.");
        var experiments = Items(method, "Experiments");
        var scans = experiments.Cast<object>().SelectMany(e => Items(e, "ScanList").Cast<object>()).ToArray();
        Require((Astral ? experiments.Count >= 2 : experiments.Count == 2) &&
            experiments.Cast<object>().All(e => Items(e, "ScanList").Count == 1) &&
            scans.Count(s => s.GetType().Name == "MerkurMasterScan") == 1 &&
            scans.Count(IsMS2) == experiments.Count-1,
            "Choose a template with one MS1 experiment and " + (Astral ? "one tMS2 or non-overlapping Astral DIA experiments." : "one tMS2 experiment."));
        ms1 = scans.Single(s => s.GetType().Name == "MerkurMasterScan");
        ms2 = scans.First(IsMS2);
        Require(scans.Where(IsMS2).All(s => s.GetType() == ms2.GetType()) && (Dia || experiments.Count == 2),
            "Use one tMS2 experiment or uniform DIA experiments; mixed MS2 scan types are not supported.");
        Require(scans.All(s => Number(s, "MicroScans") == 1),
            "Templates with multiple microscans are not supported by the current timing model.");
        // A newly converted scan owns its replacement list before SaveAs
        // rebuilds the method-level list registry. Read the scan's live list.
        list = Get(ms2, "MassList");
        var match = Regex.Match(summary, @"Method Duration \(min\) = ([0-9.]+)");
        Require(match.Success, "Cannot determine template duration.");
        duration = double.Parse(match.Groups[1].Value, Inv);
        foreach (var scan in scans.Where(IsMS2)) {
            Require(!(bool)Get(scan, "EnableMultiplexIons"), "Multiplexed templates are not yet supported.");
            if (scan.GetType().Name == "MerkurTMSnScan") {
                var dynamicRT = Str(scan, "DynamicRT");
                Require(dynamicRT == "Off" || (Astral && dynamicRT == "AdaptiveRT"),
                    "Background-spectrum Adaptive RT is supported only for Astral Zoom. PRTC Dynamic RT is not supported.");
            }
            Require(Str(scan, "LoopControl") == "All" || Str(scan, "LoopControl") == "Count", "Choose a template using All or Count loop control.");
            Require(Items(Get(scan, "MassList"), "Records").Count > 0, "The MS2 template has no mass-list rows.");
            if (scan.GetType().Name == "MerkurTMSnScan") {
                var overrides = Items(Get(scan, "MassList"), "Columns").Cast<object>()
                    .Select(c => Str(c, "DataFieldName")).Where(RowOverrides.Contains).ToArray();
                Require(overrides.Length == 0, "Unsupported per-row acquisition columns: " + string.Join(", ", overrides) +
                    ". Set these values at scan level and remove the row columns in Method Editor before importing.");
            }
        }
        if (Astral) {
            Require(ReferenceEquals(Items(experiments[0], "ScanList")[0], ms1) &&
                Number(experiments[0], "StartTimeMin") == 0 && Number(experiments[0], "EndTimeMin") == duration,
                "Astral native export requires the first MS1 experiment to cover the full method duration.");
            diaExperiments = experiments.Cast<object>().Skip(1).ToArray();
            double previousEnd = 0;
            var commonSkip = new HashSet<string> {"Summary", "ScanSummary", "MassListIndex", "MassListIndexBaseOne", "ParentTreeNodeName", "MassListNumberRows", "NumberOfScans", "NoOfScansInMethod"};
            var common = Json.Serialize(Snapshot(ms2, commonSkip));
            foreach (var experiment in diaExperiments) {
                var scan = Items(experiment, "ScanList")[0];
                var start = Number(experiment, "StartTimeMin"); var end = Number(experiment, "EndTimeMin");
                Require(start >= previousEnd && end > start && end <= duration, "Astral DIA experiments must have ordered, non-overlapping RT ranges within the method duration.");
                previousEnd = end;
                Require(Str(ms1, "DetectorType") == "Orbitrap" && Str(scan, "DetectorType") == "Astral", "Choose Orbitrap MS1 and Astral MS2 detection.");
                if (Dia) {
                    Require(Str(scan, "WindowMode") == "MassRange", "Astral DIA import currently requires mass-range windows.");
                    Require(Number(scan, "DIAMode") == 0 && !Equals(Get(scan, "AcquireReference"), true),
                        "Adaptive/reference DIA cannot be converted to the scheduled tMS2 output.");
                } else {
                    Require(start == 0 && end == duration, "Astral tMS2 templates must cover the full method duration; schedule targets in the mass list.");
                    Require(Str(scan, "IsolationOffsetMode") == "Off", "Astral tMS2 isolation offsets are not supported by the window geometry model.");
                    Require(Items(scan, "ExtraMassLists").Cast<object>().All(l => l == null || Items(l, "Records").Count == 0),
                        "Astral tMS2 templates with additional mass lists are not supported.");
                }
                Require(Str(scan, "MaxITType") == "Custom", "Astral native export currently requires Custom MS2 maximum injection time.");
                ValidateEditorColumns(Get(scan, "MassList"), scan.GetType().Name);
                Require(Json.Serialize(Snapshot(scan, commonSkip)) == common, "Astral DIA experiments must use the same acquisition and loop settings.");
            }
            Require(experiments.Cast<object>().Skip(1).All(e => !Equals(Get(e, "IsRTNavigator"), true)),
                "Adaptive RT requires the first Orbitrap Full Scan experiment as the only alignment experiment.");
            if (!Dia && Str(ms2, "DynamicRT") == "AdaptiveRT") {
                Require(Equals(Get(experiments[0], "IsRTNavigator"), true), "Adaptive RT requires an Orbitrap Full Scan alignment experiment.");
                Require(ReferenceFile() != null, "Adaptive RT requires an embedded .rtbin reference. Import it in Method Editor before using this template.");
            }
        }
    }

    // ReferenceFileLocation may hold only a GUID after reopen. Resolve the
    // method's embedded-file registry and verify its actual payload separately.
    static object ReferenceFile() {
        if (!Astral || Dia) return null;
        var location = Get(ms2, "ReferenceFileLocation");
        if (location == null || Get(location, "EmbeddedFileGuid") == null) return null;
        var id = Get(location, "EmbeddedFileGuid");
        var file = Items(method, "EmbeddedFiles").Cast<object>().SingleOrDefault(f => Equals(Get(f, "EmbeddedFileGuid"), id));
        Require(file != null && !Equals(Get(file, "IsReferenceOnly"), true) && File.Exists(Str(file, "FullPath")) &&
            new FileInfo(Str(file, "FullPath")).Length > 0,
            "The method's embedded Adaptive RT reference is missing. Import a .rtbin reference in Method Editor.");
        return file;
    }
    static object AdaptiveRTState() {
        if (!Astral) return new {supported=false, mode="off", alignment=false, acquire_reference=false,
            has_reference=false, reference_name=(string)null, reference_sha256=(string)null};
        var alignment = Equals(Get(Items(method, "Experiments")[0], "IsRTNavigator"), true);
        var acquire = Equals(Get(ms1, "AcquireReference"), true);
        var enabled = !Dia && Str(ms2, "DynamicRT") == "AdaptiveRT";
        var file = ReferenceFile();
        return new {supported=true, mode=enabled ? "adaptive" : alignment && acquire ? "acquire_reference" : "off",
            alignment=alignment, acquire_reference=acquire, has_reference=file != null,
            reference_name=file == null ? null : Str(file, "FileName"),
            reference_sha256=file == null ? null : Hash(Str(file, "FullPath"))};
    }
    static string EmbeddedSnapshot() {
        if (!Astral) return "";
        return Json.Serialize(Items(method, "EmbeddedFiles").Cast<object>().Select(f => new {
            id=Str(f, "EmbeddedFileGuid"), name=Str(f, "FileName"), reference_only=Get(f, "IsReferenceOnly"),
            sha256=File.Exists(Str(f, "FullPath")) ? Hash(Str(f, "FullPath")) : null
        }).OrderBy(f => f.id).ToArray());
    }
    static void ValidateEditorColumns(object massList, string scanType) {
        HashSet<string> editorColumns;
        if (!EditorColumns.TryGetValue(scanType, out editorColumns)) {
            var assembly = Assembly.LoadFrom(Path.Combine(runtime, "Thermo.TNG.Common.TNGMEComponents.dll"));
            var resource = "Thermo.TNG.Common.TNGMEComponents.Merkur." + profile.Code + ".TNGMEModelComponents.xml";
            var doc = new XmlDocument();
            using (var stream = assembly.GetManifestResourceStream(resource)) {
                Require(stream != null, "The installed Astral Method Editor schema is unavailable."); doc.Load(stream);
            }
            editorColumns = new HashSet<string>();
            foreach (XmlNode node in doc.SelectNodes("//ComponentType[DataClassName='" + scanType + "']/ParameterTypeList/ParameterType[DataFieldName='MassList']/ChildParameterTypeList/*")) {
                var definition = node.Name == "CommonParameterType" ? doc.SelectSingleNode(
                    "/ComponentTypeDefinition/CommonTypes/CommonParameterTypeList/ParameterType[@name='" + node.Attributes["name"].Value + "']") : node;
                var field = definition == null ? null : definition.SelectSingleNode("DataFieldName");
                Require(definition != null, "Cannot resolve an Astral Method Editor table parameter.");
                // The normalized AGC display has no direct data member; the
                // serialized per-row AGC column is defined separately.
                if (field != null) editorColumns.Add(field.InnerText);
            }
            Require(editorColumns.Count > 0, "The installed Astral Method Editor schema has no mass-list columns.");
            EditorColumns[scanType] = editorColumns;
        }
        var unsupported = Items(massList, "Columns").Cast<object>().Select(c => Str(c, "DataFieldName")).Where(n => !editorColumns.Contains(n)).ToArray();
        Require(unsupported.Length == 0, (scanType == "MerkurDIAScan" ? "DIA" : "tMS2") + " table has unsupported Editor columns: " + string.Join(", ", unsupported) + ". Re-export from the original instrument template.");
    }
    static void Validate() {
        if (!(bool)Call(api, "ValidateMethod"))
            throw new InvalidOperationException("Thermo validation failed: " + string.Join("; ", ((IEnumerable)Call(api, "GetLastValidationErrors")).Cast<object>()));
    }
    static Dictionary<string, object> Acquisition(object scan) {
        var it = Str(scan, "MaxITType");
        Require(it == "Auto" || it == "Custom", "Dynamic injection time is not yet supported; choose an Auto or Custom IT template.");
        return new Dictionary<string, object> {
            {"resolution", Astral && IsMS2(scan) ? null : (object)Number(scan, "OrbitrapResolution")}, {"max_it_mode", it},
            {"max_it_ms", Number(scan, "MaxITTime")}, {"agc_percent", Number(scan, "NormalizedAgcTargetPercentage")},
            {"agc_absolute", Number(scan, "AgcTarget")}, {"agc_mode", Str(scan, "AGCTargetType")},
            {"mz_min", Number(scan, "FirstMass")}, {"mz_max", Number(scan, "LastMass")}
        };
    }
    static Dictionary<string, object>[] Rows(object massList) {
        return Items(massList, "Records").Cast<object>().Select(r => new Dictionary<string, object> {
            {"compound", Str(r, "CompoundName")}, {"mz", Dia ? (Number(r, "FirstMass") + Number(r, "LastMass")) / 2 : Number(r, "MoverZ")}, {"charge", Number(r, "Z")},
            {"width", Dia ? Number(r, "LastMass") - Number(r, "FirstMass") : Number(r, "IsolationWindow")}, {"start", Number(r, "StartTime")}, {"end", Number(r, "EndTime")},
            {"rt", Number(r, "RetentionTime")}, {"rt_window", Number(r, "RetentionWindow")}, {"index", Number(r, "RowIndex")}
        }).ToArray();
    }
    static Dictionary<string, object> Inspect(string path) {
        var rows = Rows(list); var mode = Str(ms2, "TimeMode");
        bool rowWidths = Items(list, "Columns").Cast<object>().Any(c => Str(c, "DataFieldName") == "IsolationWindow");
        if (!Dia && !rowWidths) foreach (var row in rows) row["width"] = Number(ms2, "IsolationWindow");
        if (Dia) {
            rows = diaExperiments.SelectMany((e, i) => Rows(Get(Items(e, "ScanList")[0], "MassList")).Select(r => {
                r["start"] = Number(e, "StartTimeMin"); r["end"] = Number(e, "EndTimeMin"); r["experiment_index"] = i+2; r["charge"] = 0.0; return r;
            })).ToArray();
            mode = diaExperiments.Length == 1 && Number(diaExperiments[0], "StartTimeMin") == 0 && Number(diaExperiments[0], "EndTimeMin") == duration ? "Unscheduled" : "ExperimentTimeRange";
        } else foreach (var row in rows) {
            if (mode == "Unscheduled") { row["start"] = 0.0; row["end"] = duration; }
            if (mode == "RetentionTimeWindow") {
                row["start"] = (double)row["rt"] - (double)row["rt_window"] / 2;
                row["end"] = (double)row["rt"] + (double)row["rt_window"] / 2;
            }
        }
        var count = Str(ms2, "LoopControl") == "Count" ? (int)Number(ms2, "LoopCount") : ConcurrentWindows(rows);
        return new Dictionary<string, object> {
            {"schema_version", 1}, {"model", profile.Model}, {"instrument", profile.Instrument},
            {"runtime_version", profile.Build}, {"implementation_version", profile.DllVersion},
            {"expected_peak_width_sec", Number(Get(method, "GlobalSettings"), "ExpectedPeakWidth")},
            {"sha256", Hash(path)}, {"duration_min", duration}, {"ms1", Acquisition(ms1)}, {"ms2", Acquisition(ms2)},
            {"ms1_scans_per_cycle", 1}, {"window_count", count}, {"time_mode", mode},
            {"adaptive_rt", AdaptiveRTState()},
            {"dia_experiment_count", Dia ? diaExperiments.Length : 0},
            {"ms2_scan_type", Dia ? "DIA" : "tMS2"}, {"native_output_scan_type", "tMS2"},
            {"ms2_experiment_name", Str(Items(method, "Experiments").Cast<object>().First(e => Items(e, "ScanList").Contains(ms2)), "ExperimentName")},
            {"ms2_experiment_count", Dia ? diaExperiments.Length : 1},
            {"editor_columns", TargetMassLists().SelectMany(l => Items(l, "Columns").Cast<object>().Select(c => Str(c, "DataFieldName"))).Distinct().ToArray()},
            {"loop_control", Str(ms2, "LoopControl")}, {"loop_count", Number(ms2, "LoopCount")},
            {"mz_min", rows.Min(r => (double)r["mz"] - (double)r["width"] / 2)},
            {"mz_max", rows.Max(r => (double)r["mz"] + (double)r["width"] / 2)},
            {"rows", rows}, {"summary", summary}, {"native_write", true}
        };
    }
    static IEnumerable<object> TargetMassLists() {
        return Dia ? diaExperiments.Select(e => Get(Items(e, "ScanList")[0], "MassList")) : new[] {list};
    }
    static int ConcurrentWindows(IEnumerable<Dictionary<string, object>> rows) {
        var events = new SortedDictionary<double, int>();
        foreach (var row in rows) {
            double start = (double)row["start"], end = (double)row["end"];
            int change;
            events.TryGetValue(start, out change); events[start] = change + 1;
            events.TryGetValue(end, out change); events[end] = change - 1;
        }
        // Apply ends and starts together: adjacent RT groups share a transition,
        // not an extra acquisition cycle containing both groups.
        int active = 0, maximum = 0;
        foreach (var change in events.Values) { active += change; maximum = Math.Max(maximum, active); }
        return maximum;
    }
    static string RowFingerprint() {
        // Hash the same ordered scalar/range snapshots one row at a time.
        // JSON array framing preserves row/list boundaries without retaining a
        // second full table or hitting the serializer's whole-document limit.
        using (var hash = SHA256.Create()) {
            using (var stream = new CryptoStream(Stream.Null, hash, CryptoStreamMode.Write))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false))) {
                var skip = new HashSet<string>(); bool firstList = true;
                writer.Write('[');
                foreach (var massList in TargetMassLists()) {
                    if (!firstList) writer.Write(','); firstList = false;
                    writer.Write('['); bool firstRow = true;
                    foreach (var row in Items(massList, "Records")) {
                        if (!firstRow) writer.Write(','); firstRow = false;
                        writer.Write(Json.Serialize(Snapshot(row, skip)));
                    }
                    writer.Write(']');
                }
                writer.Write(']');
            }
            return BitConverter.ToString(hash.Hash);
        }
    }
    static string ColumnSnapshot() { return Json.Serialize(TargetMassLists().Select(l => Items(l, "Columns").Cast<object>().Select(c => Str(c, "DataFieldName")).ToArray()).ToArray()); }

    // Capture scalar and range properties without traversing vendor object cycles.
    static object Plain(object value) {
        if (value == null) return null;
        var t = value.GetType();
        if (t.IsEnum) return value.ToString();
        if (t.IsPrimitive || value is string || value is decimal) return value;
        if (value is Array) return ((Array)value).Cast<object>().Select(Plain).ToArray();
        if (t.GetProperty("Low") != null && t.GetProperty("High") != null)
            return new object[] {Get(value, "Low"), Get(value, "High")};
        return null;
    }
    static SortedDictionary<string, object> Snapshot(object target, HashSet<string> skip) {
        var result = new SortedDictionary<string, object>(StringComparer.Ordinal);
        foreach (var p in target.GetType().GetProperties()) {
            if (p.GetIndexParameters().Length != 0 || skip.Contains(p.Name)) continue;
            var v = Plain(p.GetValue(target, null)); if (v != null) result[p.Name] = v;
        }
        foreach (var f in target.GetType().GetFields()) {
            if (skip.Contains(f.Name)) continue;
            var v = Plain(f.GetValue(target)); if (v != null) result[f.Name] = v;
        }
        return result;
    }
    static string ScanSnapshot() {
        var skip = new HashSet<string> {"Summary", "ScanSummary", "MassListNumberRows", "NumberOfScans", "NoOfScansInMethod"};
        // Astral 2.2 resets this nonserialized experiment-level flag on reopen.
        // Actual calibration settings belong to GlobalSettings, checked below.
        var experimentSkip = new HashSet<string>(skip);
        if (Astral) {
            experimentSkip.UnionWith(new[] {"InternalCalibrationOptions", "Name", "TreeNodeName"});
            skip.Add("ParentTreeNodeName"); // CopyAndAppendExperiment is renumbered by the serializer.
        }
        return Json.Serialize(Items(method, "Experiments").Cast<object>().Select(e => new object[] {
            Snapshot(e, experimentSkip), Items(e, "ScanList").Cast<object>().Select(s => Snapshot(s, skip)).ToArray()
        }).ToArray());
    }
    static string ComparableSummary(string text) {
        var lines = new List<string>(); var block = new List<string>();
        foreach (var line in Regex.Split(text, "\\r?\\n")) {
            if (Regex.IsMatch(line, @"^\s+[^|]+ = ")) block.Add(line);
            else {block.Sort(StringComparer.Ordinal); lines.AddRange(block); block.Clear(); lines.Add(line);}
        }
        block.Sort(StringComparer.Ordinal); lines.AddRange(block);
        return string.Join("\n", lines);
    }
    static void ApplyAcquisition(object scan, Dictionary<string, object> settings) {
        bool orbitrap = !(Astral && IsMS2(scan));
        var requested = orbitrap ? Convert.ToInt32(settings["resolution"], Inv) : 0;
        if (orbitrap && Number(scan, "OrbitrapResolution") != requested) {
            var type = Get(scan, "Resolution").GetType(); bool found = false;
            foreach (var value in Enum.GetValues(type)) {
                Set(scan, "Resolution", value.ToString());
                if (Number(scan, "OrbitrapResolution") == requested) {found = true; break;}
            }
            Require(found, "Resolution is not supported by this instrument: " + requested);
        }
        var mode = (string)settings["max_it_mode"];
        Require(mode == "Auto" || mode == "Custom", "Unsupported maximum injection time mode.");
        Require(orbitrap || mode == "Custom", "Astral MS2 requires Custom maximum injection time.");
        Set(scan, "MaxITType", mode);
        if (mode == "Custom") {
            double it = Convert.ToDouble(settings["max_it_ms"], Inv);
            Require(it > 0 && it <= 10000, "Invalid maximum injection time."); Set(scan, "MaxITTime", it);
        }
        double agc = Convert.ToDouble(settings["agc_percent"], Inv);
        Require(agc > 0 && agc <= 10000, "Invalid normalized AGC target.");
        if (Number(scan, "NormalizedAgcTargetPercentage") != agc) {
            Set(scan, "AGCTargetType", "Custom"); Set(scan, "NormalizedAgcTargetPercentage", agc);
        }
        Require((!orbitrap || Number(scan, "OrbitrapResolution") == requested) && Number(scan, "NormalizedAgcTargetPercentage") == agc,
            "Thermo runtime did not apply the requested acquisition settings.");
        Require(Str(scan, "MaxITType") == mode && (mode != "Custom" || Number(scan, "MaxITTime") == Convert.ToDouble(settings["max_it_ms"], Inv)),
            "Thermo runtime did not apply the requested maximum injection time.");
    }

    static void ConvertAstralDiaToTms() {
        // Both scan types use the vendor's public MethodScanBase representation.
        // Reuse its full acquisition settings, changing only the scan identity;
        // no private stream editing or reconstruction from selected UI values.
        var prototype = Items(list, "Records")[0];
        var original = ms2;
        var converter = original.GetType().GetMethod("DownConvert");
        var data = converter.Invoke(original, new[] {Activator.CreateInstance(converter.GetParameters()[0].ParameterType)});
        Set(data, "ScanComponentType", Convert.ToInt32(Enum.Parse(Get(original, "ComponentType").GetType(), "tMSn"), Inv));
        Set(data, "ScanType", Convert.ToInt32(Enum.Parse(Get(original, "ScanType").GetType(), "tMSn"), Inv));
        var parent = Get(original, "Parent");
        var type = original.GetType().Assembly.GetType("Thermo.TNG.Merkur.Method.MerkurTMSnScan", true);
        var targeted = Activator.CreateInstance(type, new[] {parent, data});
        Set(targeted, "WindowMode", "CenterMass");
        var skip = new HashSet<string> {"Summary", "ScanSummary", "ComponentType", "ScanType", "WindowMode",
            "MassListIndex", "MassListIndexBaseOne", "MassListNumberRows"};
        var before = Snapshot(original, skip); var after = Snapshot(targeted, skip);
        foreach (var pair in before.Where(p => after.ContainsKey(p.Key)))
            Require(Json.Serialize(pair.Value) == Json.Serialize(after[pair.Key]), "DIA to tMS2 conversion changed acquisition setting: " + pair.Key);
        Require(Str(targeted, "ComponentType") == "tMSn" && Str(targeted, "DetectorType") == "Astral",
            "Thermo did not create an Astral tMS2 scan.");

        Set(parent, "Scan", targeted);
        var experiments = Items(method, "Experiments");
        Items(experiments[1], "ScanList")[0] = targeted;
        for (int i=experiments.Count-1; i>=2; --i) experiments.RemoveAt(i);
        Set(experiments[1], "StartTimeMin", 0.0); Set(experiments[1], "EndTimeMin", duration);
        // All RT groups become scheduled rows in one independent tMS2 list.
        var targetedList = Activator.CreateInstance(list.GetType()); Set(targetedList, "Type", Get(list, "Type"));
        foreach (var column in new[] {"MoverZ", "IsolationWindow"}) Call(targetedList, "AddColumn", column);
        Items(targetedList, "Records").Add(Call(prototype, "PropertyClone"));
        Set(targeted, "MassList", targetedList);
        ms2 = targeted; list = targetedList;
    }

    static void ValidateUniformRowAcquisition() {
        var skip = new HashSet<string>(Geometry);
        // DIA stores precursor window edges here; tMS2 uses the same fields for
        // fragment acquisition ranges, which must survive prototype cloning.
        if (Dia) skip.UnionWith(new[] {"FirstMass", "LastMass", "FirstLastMass"});
        var expected = Json.Serialize(Snapshot(Items(list, "Records")[0], skip));
        Require(TargetMassLists().All(l => Items(l, "Records").Cast<object>()
            .All(r => Json.Serialize(Snapshot(r, skip)) == expected)),
            "The template has differing per-row acquisition settings. Use a template with uniform row settings.");
    }

    static object Write(Dictionary<string, object> req, string source) {
        Require(!req.ContainsKey("adaptive_rt"), "Configure Adaptive RT in the instrument Method Editor. AIDIA preserves the template settings.");
        Require(Hash(source) == (string)req["template_sha256"], "The template changed. Upload it again and confirm the analysis.");
        var output = Path.GetFullPath((string)req["output"]);
        Require(!string.Equals(Path.GetFullPath(source), output, StringComparison.OrdinalIgnoreCase) && !File.Exists(output),
            "Choose a new method output path; the template cannot be overwritten.");
        var originalStreams = Storage.Hashes(source);
        var settings = Dict(req["acquisition"]);
        Require(Convert.ToInt32(settings["ms1_scans_per_cycle"], Inv) == 1, "Native export requires one MS1 scan per cycle.");
        ValidateUniformRowAcquisition();
        if (Dia) ConvertAstralDiaToTms();
        // Timeline captions are stored independently of the actual scan type.
        // Also repair tMS2 templates produced before this caption was updated.
        if (Astral) Set(Items(method, "Experiments")[1], "ExperimentName", "tMS2");
        ApplyAcquisition(ms1, Dict(settings["ms1"])); ApplyAcquisition(ms2, Dict(settings["ms2"]));
        var rows = ((IEnumerable)req["windows"]).Cast<object>().ToArray();
        Require(rows.Length > 0 && rows.Length <= 100000, "Invalid window count.");
        var records = Items(list, "Records"); var prototype = records[0];
        records.Clear();
        int index = 0;
        foreach (var entry in rows) {
            var w = Dict(entry);
            double mz = Convert.ToDouble(w["mz"], Inv), width = Convert.ToDouble(w["width"], Inv),
                start = Convert.ToDouble(w["start"], Inv), end = Convert.ToDouble(w["end"], Inv), charge = Convert.ToDouble(w["charge"], Inv);
            Require(new[] {mz,width,start,end,charge}.All(v => !double.IsNaN(v) && !double.IsInfinity(v)) &&
                mz > 0 && width > 0 && mz-width/2 > 0 && start >= 0 && end > start && end <= duration &&
                charge >= 0 && charge <= 100 && charge == Math.Floor(charge), "A window is outside the template's acquisition bounds.");
            var row = Call(prototype, "PropertyClone");
            Set(row, "CompoundName", (string)w["compound"]); Set(row, "Formula", "");
            Set(row, "AdductPositive", "(no adduct)"); Set(row, "AdductNegative", "(no adduct)");
            Set(row, "MoverZ", mz); Set(row, "Z", charge); Set(row, "IsolationWindow", width);
            Set(row, "StartTime", start); Set(row, "EndTime", end);
            Set(row, "RetentionTime", (start+end)/2); Set(row, "RetentionWindow", end-start);
            Set(row, "RowIndex", ++index); records.Add(row);
        }
        Set(list, "Records", records);
        // Keep optional acquisition columns, replace only time/geometry columns.
        var columns = Items(list, "Columns");
        for (int i=columns.Count-1; i>=0; --i) {
            var name = Str(columns[i], "DataFieldName");
            if (name == "RetentionTime" || name == "RetentionWindow") columns.RemoveAt(i);
        }
        Set(list, "Columns", columns);
        var geometryColumns = new[] {"CompoundName","Formula","AdductPositive","MoverZ","Z","StartTime","EndTime","IsolationWindow"};
        foreach (var name in geometryColumns)
            if (!(bool)Call(list, "ContainsColumn", name)) Call(list, "AddColumn", name);
        Set(ms2, "MassList", list);
        Set(ms2, "TimeMode", "StartEndTime");
        var loop = Convert.ToInt32(req["loop_count"], Inv);
        Require(loop >= 0 && loop <= rows.Length, "Invalid loop count.");
        Set(ms2, "LoopControl", loop > 0 ? "Count" : "All"); if (loop > 0) Set(ms2, "LoopCount", loop);
        // ValidateMethod reads the serialized model. Synchronize new list objects
        // through the vendor's own preparation routine before asking it to validate.
        Call(method, "PrepareToSave");
        Call(method, "DownConvert");
        Bind(); Validate();
        var expectedRows = RowFingerprint();
        var expectedScans = ScanSnapshot();
        var expectedGlobal = Json.Serialize(Snapshot(Get(method, "GlobalSettings"), new HashSet<string>()));
        var expectedColumns = ColumnSnapshot();
        var expectedAdaptiveRT = Json.Serialize(AdaptiveRTState());
        var expectedEmbedded = EmbeddedSnapshot();
        var expectedSummary = ComparableSummary((string)Call(api,"GetMethodSummary"));
        string temporary = Path.Combine(Path.GetDirectoryName(output), ".aidia-" + Guid.NewGuid().ToString("N") + ".meth");
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        try {
            Call(api, "SaveAs", temporary); Call(api, "Close");
            Require(new FileInfo(temporary).Length <= 64 * 1024 * 1024, "The method with its embedded reference exceeds the 64 MB size limit.");
            Call(api, "Open", temporary); Bind(); Validate();
            Require(expectedRows == RowFingerprint(), "Saved mass list does not match the requested method.");
            Require(expectedScans == ScanSnapshot(), "Saved scan settings differ from the requested method.");
            Require(expectedGlobal == Json.Serialize(Snapshot(Get(method, "GlobalSettings"), new HashSet<string>())), "Saved global settings differ from the template.");
            Require(expectedColumns == ColumnSnapshot(), "Saved mass-list columns changed.");
            Require(expectedAdaptiveRT == Json.Serialize(AdaptiveRTState()), "Saved Adaptive RT settings or reference changed.");
            Require(expectedEmbedded == EmbeddedSnapshot(), "Saved embedded reference files changed.");
            Require(expectedSummary == ComparableSummary(summary), "Saved method summary differs from the requested method.");
            if (Astral) {
                int experimentIndex = 0;
                foreach (var experiment in Items(method, "Experiments")) {
                    var name = "E" + (++experimentIndex).ToString(Inv);
                    Require(Str(experiment, "Name") == name && Str(experiment, "TreeNodeName") == name+"_TN1" &&
                        Str(Items(experiment, "ScanList")[0], "ParentTreeNodeName") == name+"_TN1", "Saved experiment identities are inconsistent.");
                }
            }
            var savedStreams = Storage.Hashes(temporary);
            Require(originalStreams.Keys.SequenceEqual(savedStreams.Keys), "Saving changed the method's storage structure.");
            var allowed = new HashSet<string> {"LCQ Header", "TNG-Merkur/Data", "TNG-Merkur/Header", "TNG-Merkur/Text"};
            foreach (var pair in originalStreams)
                Require(allowed.Contains(pair.Key) || savedStreams[pair.Key] == pair.Value, "Saving changed non-MS data: " + pair.Key);
            Require(Hash(source) == (string)req["template_sha256"], "The source template changed during export.");
            var adaptiveRT = AdaptiveRTState();
            Call(api, "Close"); File.Move(temporary, output);
            return new { output = output, sha256 = Hash(output), rows = rows.Length, validated = true,
                non_ms_streams_preserved = true, adaptive_rt = adaptiveRT };
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public static int Main(string[] args) {
        if (args.Length != 2) { Console.Error.WriteLine("Usage: aidia-thermo-method request.json response.json"); return 2; }
        Console.SetOut(Console.Error);
        object response; int code = 0;
        try {
            CultureInfo.CurrentCulture = Inv; CultureInfo.CurrentUICulture = Inv;
            var req = Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(args[0]));
            var action = (string)req["action"];
            if (action == "probe") {
                File.WriteAllText(args[1], Json.Serialize(new {ok=true, result=Probe(req)}), new UTF8Encoding(false)); return 0;
            }
            var source = Path.GetFullPath((string)req["template"]);
            Require(new FileInfo(source).Length <= 64 * 1024 * 1024, "Method exceeds the 64 MB size limit.");
            var storedSummary = Storage.MethodSummary(source);
            profile = Profiles.SingleOrDefault(p => storedSummary.StartsWith(p.Model + " Method Summary", StringComparison.Ordinal));
            Require(profile != null, "Native methods currently support Exploris 480 MS1/tMS2 and Astral Zoom MS1 with DIA or tMS2 templates. This model has not been validated.");
            runtime = FindRuntime(req, profile);
            AppDomain.CurrentDomain.AssemblyResolve += delegate(object sender, ResolveEventArgs e) {
                var path = Path.Combine(runtime, new AssemblyName(e.Name).Name + ".dll");
                return File.Exists(path) ? Assembly.LoadFrom(path) : null;
            };
            {
                Open(source);
                object result;
                if (action == "inspect") result = Inspect(source);
                else if (action == "write") result = Write(req, source);
                else throw new InvalidOperationException("Unknown action.");
                response = new {ok=true, result=result};
            }
        } catch (Exception e) {
            while (e is TargetInvocationException && e.InnerException != null) e=e.InnerException;
            Console.Error.WriteLine(e);
            response = new {ok=false, error=e.Message}; code=1;
        } finally { if (api is IDisposable) ((IDisposable)api).Dispose(); }
        File.WriteAllText(args[1], Json.Serialize(response), new UTF8Encoding(false)); return code;
    }
}

// Read-only Windows Structured Storage inspection. Thermo alone writes .meth.
internal static class Storage
{
    [DllImport("ole32.dll", CharSet=CharSet.Unicode, PreserveSig=false)]
    static extern void StgOpenStorage(string name, IStorage priority, uint mode, IntPtr exclude, uint reserved, out IStorage result);
    [ComImport, Guid("0000000B-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IStorage {
        void CreateStream();
        void OpenStream([MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr reserved, uint mode, uint reserved2, out IStream stream);
        void CreateStorage();
        void OpenStorage([MarshalAs(UnmanagedType.LPWStr)] string name, IStorage priority, uint mode, IntPtr exclude, uint reserved, out IStorage storage);
        void CopyTo(); void MoveElementTo(); void Commit(); void Revert();
        void EnumElements(uint reserved1, IntPtr reserved2, uint reserved3, out IEnumStat enumerator);
    }
    [ComImport, Guid("0000000D-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IEnumStat {
        [PreserveSig] int Next(uint count, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex=0)] STATSTG[] values, out uint fetched);
    }
    internal static SortedDictionary<string,string> Hashes(string path) {
        string ignored; return Read(path, true, out ignored);
    }
    internal static string MethodSummary(string path) {
        string summary; Read(path, false, out summary); return summary;
    }
    static SortedDictionary<string,string> Read(string path, bool hashStreams, out string summary) {
        IStorage root; StgOpenStorage(path, null, 0x20, IntPtr.Zero, 0, out root);
        var result = hashStreams ? new SortedDictionary<string,string>(StringComparer.Ordinal) : null;
        summary = "";
        try { Walk(root, "", result, ref summary); } finally {Marshal.ReleaseComObject(root);}
        return result;
    }
    static void Walk(IStorage storage, string prefix, SortedDictionary<string,string> hashes, ref string summary) {
        IEnumStat iterator; storage.EnumElements(0, IntPtr.Zero, 0, out iterator);
        try {
            var stats = new STATSTG[1]; uint count;
            while (iterator.Next(1, stats, out count) == 0 && count == 1) {
                var s=stats[0]; var name=prefix+s.pwcsName;
                if(s.type==1) {
                    if (hashes == null && name != "TNG-Merkur") continue;
                    IStorage child; storage.OpenStorage(s.pwcsName,null,0x10,IntPtr.Zero,0,out child);
                    try{Walk(child,name+"/",hashes,ref summary);}finally{Marshal.ReleaseComObject(child);}
                } else if(s.type==2) {
                    if (hashes == null && name != "TNG-Merkur/Text") continue;
                    IStream stream; storage.OpenStream(s.pwcsName,IntPtr.Zero,0x10,0,out stream);
                    try {
                        if(s.cbSize<0 || s.cbSize>64*1024*1024) throw new InvalidOperationException("Oversized method stream.");
                        if (hashes != null) {
                            using (var hash = SHA256.Create()) {
                                using (var destination = new CryptoStream(Stream.Null, hash, CryptoStreamMode.Write))
                                    CopyStream(stream, s.cbSize, destination);
                                hashes[name] = BitConverter.ToString(hash.Hash).Replace("-", "");
                            }
                        } else {
                            using (var destination = new MemoryStream()) {
                                CopyStream(stream, s.cbSize, destination);
                                summary = Encoding.Unicode.GetString(destination.GetBuffer(), 0, (int)destination.Length).TrimStart('\uFEFF');
                            }
                        }
                    }finally{Marshal.ReleaseComObject(stream);}
                }
            }
        }finally{Marshal.ReleaseComObject(iterator);}
    }
    static void CopyStream(IStream source, long length, Stream destination) {
        var buffer = new byte[65536]; var read = Marshal.AllocCoTaskMem(4);
        try {
            while (length > 0) {
                int requested = (int)Math.Min(length, buffer.Length);
                source.Read(buffer, requested, read);
                int count = Marshal.ReadInt32(read);
                if (count <= 0 || count > requested) throw new IOException("Incomplete method stream.");
                destination.Write(buffer, 0, count); length -= count;
            }
        } finally { Marshal.FreeCoTaskMem(read); }
    }
}
