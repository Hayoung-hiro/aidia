# Local Thermo method helper

`aidia-thermo-method.exe` is AIDIA-owned code, built from
`tools/thermo/Aidia.ThermoMethod.cs` in the source repository. It contains no
Thermo libraries. The package supplies the executable so users do not need a
compiler, SDK, or Python. Developers rebuild it with `tools/thermo/build.ps1`.

Supported environment: Windows x64 and .NET Framework supplied with Thermo
Workstation. Validated installations are Exploris 480 Workstation 5.1 SP1
(launcher 5.1.761.17, implementation DLL 5.0.4564.7) and Astral Workstation
2.2 SP1 for Astral Zoom (launcher 2.2.821.21, implementation DLL 5.0.4647.12).
Users obtain Thermo software from
[Thermo FlexNet Operations](https://thermo.flexnetoperations.com/); Workstation
and full instrument-control installers are distinct downloads.

The executable accepts request/response JSON paths. R owns these temporary
files. `probe`, `inspect`, and `write` are the only actions. It opens no network
listener and starts no instrument acquisition. The helper first checks the
matching default installation under `C:/Program Files/Thermo Scientific/Instruments`:
`Exploris/5.1` or `Astral/2.2`. It validates both the implementation DLL and the
Workstation launcher versions before using a location.

If that location is missing or has an unsupported build, the helper reads
`thermo_runtime_path` from the matching entry in the existing
`config/instruments.json`. In a source checkout this is
`inst/config/instruments.json`; in an installed R package, locate it with:

```r
system.file("config", "instruments.json", package = "aidia")
```

For example, set this field inside the existing `astral_zoom` object, retaining
its other settings:

```json
"thermo_runtime_path": "D:/Thermo Scientific/Instruments/Astral/2.2"
```

Use the version folder containing `System`, rather than an individual DLL or
the `dependencies/tng` folder. Paths must be absolute; forward slashes avoid JSON
backslash escaping. Windows environment variables such as `%ProgramFiles%` are
expanded. Blank or absent fields mean no custom location. The file is reread on
each request when needed, so saving it and retrying the upload is sufficient.
An error identifies the configuration file, instrument field and required version.
A valid default installation takes priority even if the custom setting is stale.
Local path edits belong to that PC and should be preserved when updating the package.

Existing scripts can still explicitly override discovery with
`options(aidia.thermo.runtime = "path/to/Exploris/5.1")` or the Astral/2.2 root.
That option takes priority and remains version checked. Normally leave it unset
to allow model-specific discovery. `thermo_method_status()` returns the effective
configuration file as `config_path` and availability/reasons for each runtime.
Each process loads one implementation, checks the binary instrument code against
the stored title, and initializes that model before opening it.

All Thermo presets use this same optional setting, including `eclipse` and
`fusion_lumos`. A configured path does not enable native method support: the
helper advertises only models with a verified reader/writer profile. Eclipse,
Lumos, ordinary Astral and Q Exactive presets retain their existing optimization
capabilities while their native method adapters remain unverified.

When adding a native adapter, register its instrument key and verified runtime
layout in the helper's `Profile`: `InstallDirectory` is relative to Program Files;
`ImplementationFile` and `LauncherFile` are relative to that installation root.
`RuntimeName`, `Build` and `DllVersion` identify the tested Workstation release.
The shared resolver then applies default discovery, the instrument's
`thermo_runtime_path`, version checks and configuration guidance without new
model-specific path logic. The adapter must separately implement and validate
its storage/model identification, DLL initialization and method round trips.
Synthetic Eclipse/Lumos profile tests cover discovery with different DLL and
launcher layouts; they do not establish vendor method compatibility.

Accepted Exploris templates have one MS1 plus one tMS2 experiment. Astral Zoom
templates have one full-duration MS1 plus either one full-duration tMS2 or
ordered, non-overlapping DIA experiments with uniform acquisition and loop settings.
DIA input requires MassRange windows without adaptive/reference DIA. Astral
tMS2 uses the Astral detector without isolation offsets or extra mass lists.
Astral requires Custom MS2 IT. Background-spectrum Adaptive RT settings can be
preserved on Astral Zoom, using its first Orbitrap Full Scan for alignment. PRTC
Dynamic RT, dynamic IT, multiplexing and multiple microscans are not supported. The
template's remaining settings and non-MS streams are preserved. Native output
retains one MS1 experiment and cannot extend the template's duration. Astral's
zero serial MS1 scans in the parallel timing model does not remove its MS1
experiment. Ordinary Astral, Eclipse and other builds remain unverified.

Both profiles write one MS1 and one scheduled tMS2 experiment. All RT groups
share one table with compound name, center m/z, charge, isolation width and
start/end RT. Astral DIA converts through the vendor's public MethodScanBase
into MerkurTMSnScan, with common acquisition properties checked for preservation.
Charge 0 and specified charges are supported. The Astral DIA Editor lacks the
name/charge/RT columns that its tMS2 Editor supports; import/export checks the
schema for the actual scan type. Its 2.2 writer upgrades the tested input from
format 23 to 24. Readback checks cover row/column/scan/global settings and summary
equality. Astral's nonserialized experiment InternalCalibrationOptions and
serializer-renumbered experiment/tree identifiers are excluded from snapshot
equality; saved identifiers and actual GlobalSettings are checked separately.

The helper uses public objects in the installed, model-specific Thermo
implementation. This is a tested integration for this build, not a guarantee
of SDK compatibility with other releases. No vendor files are redistributed.
See the repository's native-method ADR and verification report for the tested
scope. Saved methods still require normal review in the instrument software.

For Zoom, `export_thermo_method()` preserves the template's Adaptive RT state
and embedded reference. Both RT flags and embedded payload hashes are verified
after reopening. AIDIA provides an optional instrument-side setup guide; it does
not enable or disable RT correction, prepare a reference-run method, import
`.rtbin`, or select file locations on the instrument. Configure those in Method
Editor before importing the template or after exporting the designed method.
Reference compatibility with LC, sample matrix and alignment scans, and actual
RT correction still require acquisition validation. RAW/report-to-rtbin
conversion is not provided.
See `docs/ASTRAL_ZOOM_ADAPTIVE_RT_WORKFLOW.md` in the source repository.

Structured Storage is inspected read-only for preservation checks; all writes
use Thermo's serializer. The COM stream access mode follows Microsoft's
[IStorage::OpenStream specification](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-istorage-openstream).
