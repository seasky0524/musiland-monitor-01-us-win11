param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [string]$StreamName,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class MsiStreamExporter
{
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    private static extern uint MsiOpenDatabase(string szDatabasePath, IntPtr szPersist, out IntPtr phDatabase);

    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    private static extern uint MsiDatabaseOpenView(IntPtr hDatabase, string szQuery, out IntPtr phView);

    [DllImport("msi.dll")]
    private static extern uint MsiViewExecute(IntPtr hView, IntPtr hRecord);

    [DllImport("msi.dll")]
    private static extern uint MsiViewFetch(IntPtr hView, out IntPtr phRecord);

    [DllImport("msi.dll")]
    private static extern uint MsiRecordDataSize(IntPtr hRecord, uint iField);

    [DllImport("msi.dll", EntryPoint = "MsiRecordReadStream")]
    private static extern uint MsiRecordReadStream(IntPtr hRecord, uint iField, byte[] szDataBuf, ref uint pcchDataBuf);

    [DllImport("msi.dll")]
    private static extern uint MsiCloseHandle(IntPtr hAny);

    public static long Export(string msiPath, string streamName, string outputPath)
    {
        IntPtr db = IntPtr.Zero;
        IntPtr view = IntPtr.Zero;
        IntPtr rec = IntPtr.Zero;
        try
        {
            Check(MsiOpenDatabase(msiPath, IntPtr.Zero, out db), "MsiOpenDatabase");
            string escaped = streamName.Replace("'", "''");
            string query = "SELECT `Data` FROM `_Streams` WHERE `Name`='" + escaped + "'";
            Check(MsiDatabaseOpenView(db, query, out view), "MsiDatabaseOpenView");
            Check(MsiViewExecute(view, IntPtr.Zero), "MsiViewExecute");
            Check(MsiViewFetch(view, out rec), "MsiViewFetch");

            uint remaining = MsiRecordDataSize(rec, 1);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath)));

            using (FileStream fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                byte[] buffer = new byte[65536];
                while (remaining > 0)
                {
                    uint request = Math.Min((uint)buffer.Length, remaining);
                    uint actual = request;
                    Check(MsiRecordReadStream(rec, 1, buffer, ref actual), "MsiRecordReadStream");
                    if (actual == 0)
                    {
                        break;
                    }
                    fs.Write(buffer, 0, (int)actual);
                    remaining -= actual;
                }
                return fs.Length;
            }
        }
        finally
        {
            if (rec != IntPtr.Zero) MsiCloseHandle(rec);
            if (view != IntPtr.Zero) MsiCloseHandle(view);
            if (db != IntPtr.Zero) MsiCloseHandle(db);
        }
    }

    private static void Check(uint code, string api)
    {
        if (code != 0)
        {
            throw new InvalidOperationException(api + " failed with MSI error " + code);
        }
    }
}
'@

$written = [MsiStreamExporter]::Export(
    (Resolve-Path -LiteralPath $MsiPath).Path,
    $StreamName,
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
)

[pscustomobject]@{
    MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
    StreamName = $StreamName
    OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    BytesWritten = $written
}
