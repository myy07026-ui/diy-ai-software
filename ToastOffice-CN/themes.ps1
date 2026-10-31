function Theme-Color($key) {
    $palette=switch($state.theme){
        'pink'{@{bg='#F9E5EB';card='#FFFCF4';done='#CABDC2';ink='#352B30';accent='#E8BDCC';edit='#EBD5DE';delete='#F0C7D0';line='#927782'}}
        'dark'{@{bg='#191919';card='#1B467E';done='#222222';ink='#E6E6E6';accent='#484848';edit='#454545';delete='#554347';line='#666666'}}
        default{@{bg='#FFF7DE';card='#FFFEF5';done='#ADADAD';ink='#000000';accent='#C5DDB3';edit='#D8EBCB';delete='#FFC4CC';line='#423328'}}
    }
    [Drawing.ColorTranslator]::FromHtml($palette[$key])
}
function Apply-TaskTheme($card) {
    $fill=if($state.done[$card.Name]){Theme-Color 'done'}else{Theme-Color 'card'}
    $card.BackColor=Theme-Color 'bg';$card.FillColor=$fill;$card.ForeColor=Theme-Color 'line'
    foreach($child in $card.Controls){
        $child.ForeColor=Theme-Color 'ink';$child.BackColor=$fill
        if($child -is [Windows.Forms.Button]){$child.BackColor=if($child.Text -eq '删除'){Theme-Color 'delete'}else{Theme-Color 'edit'}}
    }
    $card.Invalidate()
}
function Apply-Theme {
    $bg=Theme-Color 'bg';$ink=Theme-Color 'ink'
    foreach($control in @($form,$banner,$header,$bar,$templateName,$top,$min,$exitButton,$trashButton,$settingsButton,$multi,$batchDelete,$footer,$foot,$add,$panel,$sectionStatus)){
        $control.BackColor=$bg;$control.ForeColor=$ink;$control.Invalidate()
    }
    $banner.ThemeName=[string]$state.theme;$banner.Invalidate()
    foreach($tab in @($morningTab,$afternoonTab,$temporaryTab)){$tab.ForeColor=$ink}
    foreach($card in $panel.Controls){
        if($card -is [CozyCard]){Apply-TaskTheme $card}
        elseif($card -is [TaskGroupHeader]){$card.ForeColor=[Drawing.Color]::Black}
    }
    Update-SectionStatus
}
function Show-Settings {
    if($script:settingsMenu -and -not $script:settingsMenu.IsDisposed){$script:settingsMenu.Dispose()}
    $menu=[Windows.Forms.ContextMenuStrip]::new();$menu.Font=$form.Font;$menu.ShowImageMargin=$false;$menu.BackColor=Theme-Color 'bg';$menu.ForeColor=Theme-Color 'ink'
    $forms=$menu.Items.Add('选择表单')
    foreach($template in $state.templates){
        $item=$forms.DropDownItems.Add($template.name);$item.Checked=$state.selectedTemplate -eq $template.id
        $use=$item.DropDownItems.Add('使用此表单');$use.Tag=$template.id;$use.Checked=$item.Checked
        $use.Add_Click({Select-TaskTemplate $this.Tag})
        $edit=$item.DropDownItems.Add('设置');$edit.Tag=$template.id;$edit.Font=[Drawing.Font]::new($form.Font,[Drawing.FontStyle]::Underline)
        $edit.Add_Click({Show-TemplateEditor $this.Tag})
    }
    [void]$forms.DropDownItems.Add([Windows.Forms.ToolStripSeparator]::new())
    $add=$forms.DropDownItems.Add('＋ 增加表单');$add.Add_Click({$new=@{id='form-'+[guid]::NewGuid().ToString('N');name='新表单';tasks=@()};$state.templates=@($state.templates)+@($new);Save-State;Show-TemplateEditor $new.id})
    $theme=$menu.Items.Add('主题颜色')
    foreach($option in @(@{id='cream';name='奶油吐司';color='#FFF7DE'},@{id='pink';name='浅粉猫咪';color='#F9E5EB'},@{id='dark';name='深色 · 沉稳';color='#191919'})){
        $choice=$theme.DropDownItems.Add($option.name);$choice.Tag=$option.id;$choice.Checked=$state.theme -eq $option.id
        $choice.Image=[Drawing.Bitmap]::new(16,16);$g=[Drawing.Graphics]::FromImage($choice.Image);$g.Clear([Drawing.ColorTranslator]::FromHtml($option.color));$g.Dispose()
        $choice.Add_Click({$state.theme=[string]$this.Tag;Apply-Theme;Save-State})
    }
    [void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $startup=$menu.Items.Add('开机自启动');$startup.Checked=Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Startup')) 'ToastOfficeShareCN.lnk')
    $startup.Add_Click({try{Set-ShareAutoStart (-not $this.Checked)}catch{[void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'开机启动设置')}})
    $script:settingsMenu=$menu
    $menu.Show($settingsButton,[Drawing.Point]::new(0,$settingsButton.Height))
}
function Set-ShareAutoStart([bool]$enabled) {
    $target=Join-Path ([Environment]::GetFolderPath('Startup')) 'ToastOfficeShareCN.lnk'
    if(-not $enabled){if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target};return}
    function VbsExpr([string]$text){return (@($text.ToCharArray()|ForEach-Object {'ChrW('+[int]$_+')'}) -join ' & ')}
    $launchRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ToastOfficeShareCN'
    [void][IO.Directory]::CreateDirectory($launchRoot)
    $launchPath=Join-Path $launchRoot 'Start.vbs'
    $command="& '"+(Join-Path $base 'widget.ps1').Replace("'","''")+"'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $launcher='Set sh = CreateObject("WScript.Shell")'+[Environment]::NewLine+'sh.Run "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -EncodedCommand '+$encoded+'", 0, False'
    [IO.File]::WriteAllText($launchPath,$launcher,[Text.Encoding]::ASCII)
    $installer=Join-Path $env:TEMP ('ToastOfficeShareCN-'+[guid]::NewGuid().ToString('N')+'.vbs')
    $lines=@('Set sh = CreateObject("WScript.Shell")',('Set lk = sh.CreateShortcut('+(VbsExpr $target)+')'),'lk.TargetPath = "C:\Windows\System32\wscript.exe"',('lk.Arguments = Chr(34) & '+(VbsExpr $launchPath)+' & Chr(34)'),('lk.IconLocation = '+(VbsExpr ((Join-Path $base 'schedule.ico')+',0'))),'lk.Save')
    [IO.File]::WriteAllLines($installer,$lines,[Text.Encoding]::ASCII)
    try{& (Join-Path $env:WINDIR 'System32\cscript.exe') //Nologo $installer;if($LASTEXITCODE -ne 0){throw '无法设置开机启动。'}}finally{Remove-Item -LiteralPath $installer -ErrorAction SilentlyContinue}
}
