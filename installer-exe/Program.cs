using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace RescueDrive
{
    // One-file installer: extracts the embedded toolkit payload to a temp
    // folder and launches the PowerShell installer GUI. Elevation comes from
    // app.manifest, with a runtime self-relaunch as a fallback; every failure
    // path surfaces a dialog rather than exiting silently.
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            try
            {
                if (!IsAdministrator())
                {
                    RelaunchElevated();
                    return;
                }
                Run();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Rescue Drive installer failed:\n\n" + ex,
                    "Claude Rescue Drive", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static bool IsAdministrator()
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            {
                return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        private static void RelaunchElevated()
        {
            var psi = new ProcessStartInfo
            {
                FileName = Assembly.GetExecutingAssembly().Location,
                UseShellExecute = true,
                Verb = "runas"
            };
            try { Process.Start(psi); }
            catch (Exception)
            {
                MessageBox.Show(
                    "This installer needs administrator rights to manage USB drives.\n" +
                    "Please accept the elevation prompt, or right-click the exe and choose 'Run as administrator'.",
                    "Claude Rescue Drive", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private static void Run()
        {
            string dest = Path.Combine(Path.GetTempPath(),
                "ClaudeRescueDrive_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
            Directory.CreateDirectory(dest);

            var asm = Assembly.GetExecutingAssembly();
            using (Stream zip = asm.GetManifestResourceStream("RescueDrive.payload.zip"))
            {
                if (zip == null)
                    throw new InvalidOperationException("Embedded payload missing — rebuild with installer-exe\\Build-Exe.ps1.");
                using (var archive = new ZipArchive(zip, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        string path = Path.GetFullPath(Path.Combine(dest, entry.FullName));
                        if (!path.StartsWith(dest, StringComparison.OrdinalIgnoreCase))
                            continue; // ignore malformed entry paths
                        if (string.IsNullOrEmpty(entry.Name))
                        {
                            Directory.CreateDirectory(path);
                            continue;
                        }
                        Directory.CreateDirectory(Path.GetDirectoryName(path));
                        entry.ExtractToFile(path, true);
                    }
                }
            }

            // Prefer the unified one-window app; fall back to the standalone
            // installer GUI if an older payload doesn't carry it.
            string installer = Path.Combine(dest, "RescueDrive.ps1");
            if (!File.Exists(installer))
                installer = Path.Combine(dest, "RescueDrive-Installer.ps1");
            if (!File.Exists(installer))
                throw new FileNotFoundException("RescueDrive.ps1 missing from payload.", installer);

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                WorkingDirectory = dest
            };
            var stderr = new StringBuilder();
            using (Process p = Process.Start(psi))
            {
                p.ErrorDataReceived += (s, e) => { if (e.Data != null) stderr.AppendLine(e.Data); };
                p.BeginErrorReadLine();
                p.WaitForExit();
                if (p.ExitCode != 0)
                {
                    string detail = stderr.Length > 0 ? stderr.ToString() : "(no error output)";
                    if (detail.Length > 2000) detail = detail.Substring(0, 2000) + "...";
                    throw new InvalidOperationException(
                        "The installer window exited with code " + p.ExitCode + ".\n\n" + detail);
                }
            }

            try { Directory.Delete(dest, true); } catch { /* still in use; temp cleanup will get it */ }
        }
    }
}
