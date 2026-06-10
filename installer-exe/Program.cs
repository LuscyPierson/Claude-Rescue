using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

namespace RescueDrive
{
    // One-file installer: extracts the embedded toolkit payload to a temp
    // folder and launches the PowerShell installer GUI. The app.manifest
    // requests admin, so Windows shows a single UAC prompt on double-click.
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            try
            {
                string dest = Path.Combine(Path.GetTempPath(),
                    "ClaudeRescueDrive_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
                Directory.CreateDirectory(dest);

                var asm = Assembly.GetExecutingAssembly();
                using (Stream zip = asm.GetManifestResourceStream("RescueDrive.payload.zip"))
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

                string installer = Path.Combine(dest, "RescueDrive-Installer.ps1");
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = dest
                };
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                }

                try { Directory.Delete(dest, true); } catch { /* still in use; temp cleanup will get it */ }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Rescue Drive installer failed to start:\n\n" + ex.Message,
                    "Claude Rescue Drive", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
