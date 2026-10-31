Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
command = "& '" & Replace(base & "\widget.ps1", "'", "''") & "'"
Set xml = CreateObject("MSXML2.DOMDocument.6.0")
Set node = xml.createElement("b64")
node.DataType = "bin.base64"
Set stream = CreateObject("ADODB.Stream")
stream.Type = 2
stream.Charset = "unicode"
stream.Open
stream.WriteText command
stream.Position = 0
stream.Type = 1
stream.Position = 2
node.nodeTypedValue = stream.Read
encoded = Replace(Replace(node.Text, vbCr, ""), vbLf, "")
stream.Close
sh.Run "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -EncodedCommand " & encoded, 0, False
