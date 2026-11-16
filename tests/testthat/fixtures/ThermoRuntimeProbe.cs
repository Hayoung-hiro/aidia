// Exercise the shipped helper's request/response interface with isolated default
// roots. Only the in-process profile paths are redirected; installed Thermo
// programs, registry entries and user configuration are never modified.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Web.Script.Serialization;

internal static class ThermoRuntimeProbe {
    static int Main(string[] args) {
        var program = Assembly.LoadFrom(args[0]).GetType("Program", true);
        var profiles = (Array)program.GetField("Profiles", BindingFlags.Static | BindingFlags.NonPublic).GetValue(null);
        // Synthetic profiles test future adapters without enabling them in the
        // production profile allowlist or pretending their vendor IO is tested.
        if (args.Length == 5) {
            var replacements = new JavaScriptSerializer().Deserialize<Dictionary<string, string>[]>(File.ReadAllText(args[4]));
            if (replacements.Length != profiles.Length) throw new InvalidOperationException("Unexpected fixture profile count.");
            for (int i = 0; i < replacements.Length; ++i) {
                var profile = profiles.GetValue(i);
                foreach (var field in replacements[i])
                    profile.GetType().GetField(field.Key, BindingFlags.Instance | BindingFlags.NonPublic).SetValue(profile, field.Value);
            }
        }
        foreach (var profile in profiles) {
            var location = profile.GetType().GetField("InstallDirectory", BindingFlags.Instance | BindingFlags.NonPublic);
            location.SetValue(profile, Path.Combine(Path.GetFullPath(args[1]), (string)location.GetValue(profile)));
        }
        return (int)program.GetMethod("Main").Invoke(null, new object[] {new[] {args[2], args[3]}});
    }
}
