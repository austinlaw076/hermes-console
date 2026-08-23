Option Explicit

Dim shell, fso, base, script, hermesHome, auditLog, qr, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

base = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(base, "hermes-mobile-setup.ps1")
hermesHome = shell.ExpandEnvironmentStrings("%HERMES_HOME%")
If hermesHome = "%HERMES_HOME%" Or Len(Trim(hermesHome)) = 0 Then
    hermesHome = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\hermes")
End If
auditLog = fso.BuildPath(hermesHome, "audit\safe-setup-audit.jsonl")
qr = fso.BuildPath(hermesHome, "console-services\pairing-qr.png")

If Not fso.FileExists(script) Then
    MsgBox "No se encuentra hermes-mobile-setup.ps1 junto a este lanzador.", 16, "Hermes Mobile Setup"
    WScript.Quit 2
End If

command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """"
exitCode = shell.Run(command, 0, True)

If exitCode = 0 Then
    If fso.FileExists(qr) Then
        shell.Run "explorer.exe """ & qr & """", 1, False
        MsgBox "Preparacion completada." & vbCrLf & vbCrLf & _
            "Resumen verificado:" & vbCrLf & _
            "- Hermes Agent disponible" & vbCrLf & _
            "- Gateway autenticado" & vbCrLf & _
            "- Dashboard operativo" & vbCrLf & _
            "- Mobile Bridge actualizado" & vbCrLf & _
            "- Acceso desde el movil comprobado" & vbCrLf & vbCrLf & _
            "El QR esta abierto en el visor de imagenes." & vbCrLf & _
            "Registro: " & auditLog, 64, "Hermes Mobile Setup"
    Else
        MsgBox "La instalacion termino, pero no se encontro el QR." & vbCrLf & "Registro:" & vbCrLf & auditLog, 48, "Hermes Mobile Setup"
    End If
Else
    MsgBox "La instalacion fallo con codigo " & exitCode & "." & vbCrLf & "Registro:" & vbCrLf & auditLog, 16, "Hermes Mobile Setup"
End If
