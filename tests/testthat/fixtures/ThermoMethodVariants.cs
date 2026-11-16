// Developer-only integration fixture builder. Uses the installed Astral runtime;
// no Thermo binaries or generated .meth files belong in the repository.
using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;

internal static class ThermoMethodVariants {
    static object Get(object target, string name) { return target.GetType().GetProperty(name).GetValue(target, null); }
    static void Set(object target, string name, object value) {
        var property = target.GetType().GetProperty(name);
        property.SetValue(target, property.PropertyType.IsEnum ? Enum.Parse(property.PropertyType, value.ToString()) :
            Convert.ChangeType(value, property.PropertyType, CultureInfo.InvariantCulture), null);
    }
    static object Call(object target, string name, params object[] args) {
        return target.GetType().GetMethod(name, args.Select(a => a.GetType()).ToArray()).Invoke(target, args);
    }
    static void Validate(object api) {
        if (!(bool)Call(api, "ValidateMethod")) throw new InvalidOperationException("Invalid fixture: " +
            string.Join("; ", ((IEnumerable)Call(api, "GetLastValidationErrors")).Cast<object>()));
    }
    static object TargetList(object api) {
        var scans = ((IEnumerable)Get(Get(api, "Method"), "Experiments")).Cast<object>()
            .SelectMany(e => ((IEnumerable)Get(e, "ScanList")).Cast<object>());
        return Get(scans.Single(s => s.GetType().Name == "MerkurTMSnScan"), "MassList");
    }
    static int Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        var runtime = args[0]; var source = Path.GetFullPath(args[1]); var destination = args[2];
        AppDomain.CurrentDomain.AssemblyResolve += (sender, request) => {
            var path = Path.Combine(runtime, new AssemblyName(request.Name).Name + ".dll");
            return File.Exists(path) ? Assembly.LoadFrom(path) : null;
        };
        var assembly = Assembly.LoadFrom(Path.Combine(runtime, "Thermo.TNG.Merkur.MethodXML.dll"));
        var api = Activator.CreateInstance(assembly.GetType("Thermo.TNG.Merkur.MethodXML.MerkurMethodXML", true));
        try {
            var standard = Assembly.LoadFrom(Path.Combine(runtime, "Thermo.TNG.Common.Standard.dll"));
            var info = standard.GetType("Thermo.TNG.Common.Config.SysInfo").GetProperty("Instance").GetValue(null, null);
            var config = Get(Get(info, "Data"), "Configuration");
            Set(config, "InstrumentModel", "Merkur_OA"); Set(config, "IsWorkstation", true);
            standard.GetType("Thermo.TNG.Common.Utils.TNGDirectoryInitializer").GetMethod("Initialize").Invoke(null, null);
            Call(api, "Initialize", true); Call(api, "EnableValidation", true);
            if (destination == "--verify-fragments") {
                Call(api, "Open", source); Validate(api);
                var list = TargetList(api); var rows = (IList)Get(list, "Records");
                if (!(bool)Call(list, "ContainsColumn", "FirstLastMass") || rows.Count < 2 ||
                    rows.Cast<object>().Any(r => Convert.ToDouble(Get(r, "FirstMass")) != 200.0 ||
                        Convert.ToDouble(Get(r, "LastMass")) != 1960.0))
                    throw new InvalidOperationException("Saved fragment ranges differ from 200-1960.");
                Call(api, "Close"); Console.WriteLine("All saved fragment ranges preserved: 200-1960"); return 0;
            }
            Directory.CreateDirectory(destination);
            foreach (var variant in new[] {"row-it", "row-agc", "mixed-fragments", "uniform-fragments"}) {
                var output = Path.Combine(destination, variant + ".meth");
                if (File.Exists(output) || string.Equals(source, Path.GetFullPath(output), StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Fixtures require new output paths.");
                Call(api, "Open", source);
                var method = Get(api, "Method");
                var list = TargetList(api); var rows = (IList)Get(list, "Records");
                if (rows.Count < 2) throw new InvalidOperationException("Fixture needs at least two rows.");
                string column = variant == "row-it" ? "MaxITTime" : variant == "row-agc" ? "AgcTarget" : "FirstLastMass";
                if (!(bool)Call(list, "ContainsColumn", column)) Call(list, "AddColumn", column);
                for (int i = 0; i < rows.Count; ++i) {
                    if (variant == "row-it") Set(rows[i], "MaxITTime", 10.0);
                    else if (variant == "row-agc") Set(rows[i], "AgcTarget", 25000.0);
                    else {
                        Set(rows[i], "FirstMass", variant == "mixed-fragments" && i > 0 ? 250.0 : 200.0);
                        Set(rows[i], "LastMass", 1960.0);
                    }
                }
                Call(method, "PrepareToSave"); Call(method, "DownConvert"); Validate(api);
                Call(api, "SaveAs", output); Call(api, "Close"); Call(api, "Open", output); Validate(api); Call(api, "Close");
                Console.WriteLine(variant + ": saved and validated");
            }
            return 0;
        } catch (Exception error) {
            Console.Error.WriteLine(error.GetBaseException()); return 1;
        } finally { if (api is IDisposable) ((IDisposable)api).Dispose(); }
    }
}
