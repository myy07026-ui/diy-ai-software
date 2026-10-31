param([switch]$SelfTest, [switch]$Preview, [string]$DataDirectory)
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class WidgetDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][WidgetDpi]::SetProcessDPIAware()
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
Add-Type -Path (Join-Path $base 'style.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $base 'task-document.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
$isCheck=[bool]($SelfTest -or $Preview)
$mutex=$null
if(-not $isCheck){
    $mutex=[Threading.Mutex]::new($false,'Local\ToastOfficeShareCNWidget')
    $acquired=$false
    try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
    if(-not $acquired){$mutex.Dispose();exit}
}
$dataRoot=if($DataDirectory){$DataDirectory}elseif($isCheck){$base}else{Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ToastOfficeShareCN\UserData'}
if(-not $isCheck -and -not (Test-Path -LiteralPath (Join-Path $dataRoot 'tasks.json'))){
    [void][IO.Directory]::CreateDirectory($dataRoot)
    Copy-Item -LiteralPath (Join-Path $base 'starter-guide.json') -Destination (Join-Path $dataRoot 'tasks.json')
    [void][IO.Directory]::CreateDirectory((Join-Path $dataRoot 'documents'))
    Get-ChildItem -LiteralPath (Join-Path $base 'guide-documents') -Filter '*.rtf'|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dataRoot 'documents')}
}
$dataPath = Join-Path $dataRoot 'tasks.json'
if($isCheck -and -not (Test-Path -LiteralPath $dataPath)){$dataPath=Join-Path $base 'starter-guide.json'}
$state = @{ date=''; done=@{}; completedAt=@{}; notified=@{}; custom=@(); trash=@(); edits=@{}; reviewRules=@{}; reviewPending=@{}; orders=@{}; snoozes=@{}; deferrals=@{}; groups=@(); groupOrder=@(); defaultGroupName='未分组'; taskGroups=@{}; groupCollapsed=@{}; groupColors=@{}; windowSize=@{}; templateOrders=@{}; templates=@(); selectedTemplate=''; lastTemplateUseDate=''; sloganIndex=-1; theme='cream'; title='今日工作小食光'; weekend=$false }
if (Test-Path $dataPath) {
    try {
        $saved = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($map in @('templateOrders','completedAt','reviewRules','reviewPending','orders','snoozes','deferrals','taskGroups','groupCollapsed','groupColors')){if($saved.$map){foreach($entry in $saved.$map.PSObject.Properties){$state[$map][$entry.Name]=$entry.Value}}}
        if($saved.lastTemplateUseDate){$state.lastTemplateUseDate=[string]$saved.lastTemplateUseDate}
        $state.templates=@($saved.templates | Where-Object {$_})
        if($saved.selectedTemplate){$state.selectedTemplate=[string]$saved.selectedTemplate}
        $state.groups=@($saved.groups | Where-Object {$_})
        $state.groupOrder=@($saved.groupOrder | Where-Object {$_})
        if($saved.defaultGroupName){$state.defaultGroupName=[string]$saved.defaultGroupName}
        if($saved.windowSize){$state.windowSize=@{width=[int]$saved.windowSize.width;height=[int]$saved.windowSize.height}}
        if($null -ne $saved.sloganIndex){$state.sloganIndex=[int]$saved.sloganIndex}
        if($saved.theme -in @('cream','pink','dark')){$state.theme=[string]$saved.theme}
        if($saved.title){$state.title=[string]$saved.title}
        $state.date=$saved.date; $state.weekend=[bool]$saved.weekend
        foreach($p in $saved.done.PSObject.Properties){$state.done[$p.Name]=$p.Value}
        foreach($p in $saved.notified.PSObject.Properties){$state.notified[$p.Name]=$p.Value}
        $state.custom=@($saved.custom | Where-Object { $_ })
        $state.trash=@($saved.trash | Where-Object { $_ })
        if($saved.edits){foreach($entry in $saved.edits.PSObject.Properties){$state.edits[$entry.Name]=$entry.Value}}
    } catch { [System.Windows.Forms.MessageBox]::Show('任务记录无法读取，请先备份 tasks.json 后再检查。程序不会覆盖原记录。','每日工作助手'); exit 1 }
}
if(-not $isCheck){
    @{startedAt=[datetime]::Now.ToString('s');pid=$PID;source=$PSCommandPath;dataPath=$dataPath;customCount=@($state.custom).Count;temporaryCount=@($state.custom|Where-Object {$_.section -eq '临时任务'}).Count;selectedTemplate=$state.selectedTemplate} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dataRoot 'startup-diagnostics.json') -Encoding UTF8
}
function Save-State {
    if($isCheck){return}
    $tmp=$dataPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
        if(Test-Path -LiteralPath $dataPath){
            $backups=Join-Path $dataRoot 'backups';[void][IO.Directory]::CreateDirectory($backups)
            $backup=Join-Path $backups ('tasks-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fffffff')+'.json')
            [IO.File]::Replace($tmp,$dataPath,$backup)
            Get-ChildItem -LiteralPath $backups -Filter 'tasks-*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
        }else{[IO.File]::Move($tmp,$dataPath)}
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
. (Join-Path $base 'groups.ps1')
. (Join-Path $base 'templates.ps1')
if($state.templates.Count -eq 0){
    $seed=Get-Content -LiteralPath (Join-Path $base 'templates-seed.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $state.templates=@($seed)
    foreach($template in $state.templates){foreach($task in $template.tasks){if($task.reviewMinutes -gt 0){$state.reviewRules[$task.id]=[int]$task.reviewMinutes}}}
}
function Copy-TaskRecord($task) {
    $copy=@{}
    if($task -is [Collections.IDictionary]){foreach($key in $task.Keys){$copy[$key]=$task[$key]}}
    else{foreach($property in $task.PSObject.Properties){$copy[$property.Name]=$property.Value}}
    return $copy
}
function Defer-Task($id,[datetime]$now=(Get-Date)) {
    $task=$script:tasks | Where-Object {$_.id -eq $id} | Select-Object -First 1
    if(-not $task){return}
    $state.deferrals[$id]=@{date=$now.Date.AddDays(1).ToString('yyyy-MM-dd');task=(Copy-TaskRecord $task)}
    $state.done.Remove($id);$state.notified.Remove($id);$state.snoozes.Remove($id);$state.reviewPending.Remove($id)
}
function Get-Tasks([datetime]$day) {
    $list = [System.Collections.Generic.List[object]]::new()
    $active=($state.weekend -or [int]$day.DayOfWeek -in 1..5)
    $selected=Get-SelectedTemplate
    
    if($selected){foreach($task in @($selected.tasks)){$list.Add((Copy-TaskRecord $task))}}
    foreach($task in $state.custom){if($selected -and $task.section -ne '临时任务'){continue};if($task.section -notin @('上午','下午','临时任务')){$task.section='临时任务'}; $list.Add((Copy-TaskRecord $task))}
    foreach($id in $state.deferrals.Keys){
        $deferred=$state.deferrals[$id]
        if($selected -and $deferred.task.section -ne '临时任务' -and $id -notin @($selected.tasks.id)){continue}
        if($deferred.date -eq $day.ToString('yyyy-MM-dd') -and -not @($list | Where-Object {$_.id -eq $id}).Count){$list.Add((Copy-TaskRecord $deferred.task))}
    }
    foreach($task in $list){
        if($state.edits.ContainsKey($task.id)){
            $edit=$state.edits[$task.id]; $task.text=$edit.text; $task.note=$edit.note; $task.time=$edit.time; foreach($property in @('reminderAt','reminderMode','weekdays')){if($task -is [hashtable]){$task[$property]=$edit.$property}else{$task | Add-Member -NotePropertyName $property -NotePropertyValue $edit.$property -Force}}
        }
    }
    if($selected){foreach($task in $list){if($task.id -in @($selected.tasks.id) -and $task.reminderMode -eq 'weekly'){$task.weekdays=@(0,1,2,3,4,5,6)}}}
    foreach($task in $list){if($task.section -eq '临时任务' -and -not $task.note){$task.note='图文任务 · 双击卡片编辑'}}
    foreach($task in $list){
        if($state.deferrals.ContainsKey($task.id)){
            $target=$state.deferrals[$task.id].date
            if($target -eq $day.ToString('yyyy-MM-dd') -and $task.time -and $task.reminderMode -ne 'off'){
                $task.reminderMode='date';$task.reminderAt=$target+' '+$task.time
            }
        }
    }
    $deletedIds=@($state.trash | ForEach-Object {$_.id})
    return @($list.ToArray() | Where-Object {$_.id -notin $deletedIds -and (-not $state.deferrals.ContainsKey($_.id) -or $state.deferrals[$_.id].date -le $day.ToString('yyyy-MM-dd'))})
}
function Request-DeleteTask($id) {
    $task=$script:tasks | Where-Object {$_.id -eq $id} | Select-Object -First 1
    if(-not $task){return}
    $message='确定删除此任务吗？'+[Environment]::NewLine+[Environment]::NewLine+$task.text+[Environment]::NewLine+[Environment]::NewLine+'删除后可从垃圾箱恢复。'
    $answer=[Windows.Forms.MessageBox]::Show($form,$message,'确认删除',[Windows.Forms.MessageBoxButtons]::OKCancel,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2)
    if($answer -ne [Windows.Forms.DialogResult]::OK){return}
    Move-ToTrash $id;Save-State;Paint-Tasks
}
function Move-ToTrash($id) {
    $task=$state.custom | Where-Object {$_.id -eq $id} | Select-Object -First 1
    if(-not $task){
        $found=$script:tasks | Where-Object {$_.id -eq $id} | Select-Object -First 1
        if(-not $found){return}
        $task=@{};foreach($key in $found.Keys){$task[$key]=$found[$key]};$task.isFixed=$true
    }
    if(@($state.trash | Where-Object {$_.id -eq $id}).Count){return}
    $state.trash=@($state.trash)+@($task)
    $state.custom=@($state.custom | Where-Object {$_.id -ne $id})
    $state.reviewPending.Remove($id)
}
function Restore-Task($id) {
    $task=$state.trash | Where-Object {$_.id -eq $id} | Select-Object -First 1
    if(-not $task){return}
    if(-not $task.isFixed -and -not @($state.custom | Where-Object {$_.id -eq $id}).Count){$state.custom=@($state.custom)+@($task)}
    $state.trash=@($state.trash | Where-Object {$_.id -ne $id})
}
function Schedule-Review($id,[bool]$completed,[datetime]$now=(Get-Date)) {
    $state.reviewPending.Remove($id)
    if(-not $completed -or -not $state.reviewRules.ContainsKey($id)){return}
    $task=$script:tasks | Where-Object {$_.id -eq $id} | Select-Object -First 1
    $state.reviewPending[$id]=@{due=$now.AddMinutes([int]$state.reviewRules[$id]).ToString('o');text=$task.text;token=[guid]::NewGuid().ToString()}
}
function Set-ReviewRule($id,[int]$minutes) {
    if($minutes -le 0){$state.reviewRules.Remove($id);$state.reviewPending.Remove($id)}else{$state.reviewRules[$id]=$minutes}
    Save-State
}
function Custom-ReviewRule($id) {
    $dialog=[Windows.Forms.Form]::new();$dialog.Text='完成后提醒';$dialog.Size=[Drawing.Size]::new(300,180);$dialog.StartPosition='CenterParent';$dialog.Font=$form.Font;$dialog.BackColor=$form.BackColor;$dialog.TopMost=$true
    $label=[Windows.Forms.Label]::new();$label.Text='打钩完成后，多少分钟提醒复查？';$label.SetBounds(12,15,270,26)
    $minutes=[Windows.Forms.NumericUpDown]::new();$minutes.Minimum=1;$minutes.Maximum=10080;$minutes.Value=5;$minutes.SetBounds(15,50,140,28)
    if($state.reviewRules.ContainsKey($id)){$minutes.Value=$state.reviewRules[$id]}
    $ok=[Windows.Forms.Button]::new();$ok.Text='确定';$ok.SetBounds(180,90,80,30)
    $ok.Add_Click({Set-ReviewRule $id ([int]$minutes.Value);$dialog.Close()})
    $dialog.Controls.AddRange(@($label,$minutes,$ok));$dialog.AcceptButton=$ok;[void]$dialog.ShowDialog($form);$dialog.Dispose()
}
function Attach-ReviewMenu($row,$id) {
    $menu=[Windows.Forms.ContextMenuStrip]::new()
    $root=[Windows.Forms.ToolStripMenuItem]::new();$root.Text='完成后提醒'
    foreach($value in @(5,10,0,-1)){
        $item=[Windows.Forms.ToolStripMenuItem]::new();$item.Tag=@{id=$id;minutes=$value}
        switch($value){5{$item.Text='5分钟后'}10{$item.Text='10分钟后'}0{$item.Text='关闭提醒'}-1{$item.Text='自定义…'}}
        if($state.reviewRules.ContainsKey($id)){
            $configured=[int]$state.reviewRules[$id]
            $item.Checked=($configured -eq $value -or ($value -eq -1 -and $configured -notin @(5,10)))
        }else{$item.Checked=$value -eq 0}
        $item.Add_Click({if($this.Tag.minutes -eq -1){Custom-ReviewRule $this.Tag.id}else{Set-ReviewRule $this.Tag.id $this.Tag.minutes}})
        [void]$root.DropDownItems.Add($item)
    }
    $menu.Add_Opening({
        foreach($choice in $this.Items[0].DropDownItems){
            $key=$choice.Tag.id;$value=$choice.Tag.minutes
            if($state.reviewRules.ContainsKey($key)){$n=[int]$state.reviewRules[$key];$choice.Checked=($n -eq $value -or ($value -eq -1 -and $n -notin @(5,10)))}else{$choice.Checked=$value -eq 0}
        }
    })
    [void]$menu.Items.Add($root)
    [void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $deleteItem=[Windows.Forms.ToolStripMenuItem]::new();$deleteItem.Text='删除任务';$deleteItem.Tag=$id
    $deleteItem.Add_Click({Request-DeleteTask $this.Tag})
    [void]$menu.Items.Add($deleteItem)
    $tomorrow=[Windows.Forms.ToolStripMenuItem]::new();$tomorrow.Text='移到明天';$tomorrow.Tag=$id
    $tomorrow.Add_Click({Defer-Task $this.Tag;Save-State;Paint-Tasks})
    [void]$menu.Items.Add($tomorrow)
    if($row.Tag -eq '临时任务'){
        $move=$menu.Items.Add('移动到分组')
        foreach($group in @(Get-TaskGroups)){
            $choice=$move.DropDownItems.Add($group.name);$choice.Tag=@{id=$id;group=$group.id};$choice.Checked=(Get-TaskGroup $id) -eq $group.id
                        $choice.Add_Click({
                if($script:batchMode){
                    foreach($selectedId in @($script:batchSelected.Keys)){
                        if($script:batchSelected[$selectedId]){Move-TaskGroup $selectedId $this.Tag.group}
                    }
                    $script:batchSelected.Clear()
                }else{Move-TaskGroup $this.Tag.id $this.Tag.group}
                Save-State;Paint-Tasks
            })
        }
        $create=$menu.Items.Add('新建分组');$create.Add_Click({Edit-GroupName})
    }
    $row.ContextMenuStrip=$menu
    foreach($child in $row.Controls){$child.ContextMenuStrip=$menu}
    foreach($surface in @($row)+@($row.Controls)){
        $surface.Add_MouseUp({param($sender,$eventArgs) if($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Right -and $sender.ContextMenuStrip){$sender.ContextMenuStrip.Show($sender,$eventArgs.Location)}})
    }
    $row.Add_Disposed({if($this.ContextMenuStrip){$this.ContextMenuStrip.Dispose()}})
}
function Show-ReviewReminder {
    if($script:reviewPopup -or $script:popup){return}
    $now=Get-Date;$key=$null
    foreach($id in $state.reviewPending.Keys){if([datetime]::Parse($state.reviewPending[$id].due) -le $now){$key=$id;break}}
    if(-not $key){return}
    $pending=$state.reviewPending[$key]
    $window=[Windows.Forms.Form]::new();$script:reviewPopup=$window
    $window.Text='完成后复查提醒';$window.Size=[Drawing.Size]::new(440,230);$window.StartPosition='CenterScreen';$window.TopMost=$true;$window.Font=$form.Font;$window.BackColor=$form.BackColor
    $window.Tag=@{id=$key;token=$pending.token}
    $message=[Windows.Forms.Label]::new();$message.Text='请检查任务是否已更新或处理成功：'+[Environment]::NewLine+[Environment]::NewLine+$pending.text;$message.SetBounds(18,15,390,105)
    $done=[Windows.Forms.Button]::new();$done.Text='已检查';$done.SetBounds(175,135,95,32)
    $later=[Windows.Forms.Button]::new();$later.Text='再等5分钟';$later.SetBounds(280,135,120,32)
    $done.Add_Click({
        $info=$script:reviewPopup.Tag
        if($state.reviewPending.ContainsKey($info.id) -and $state.reviewPending[$info.id].token -eq $info.token){$state.reviewPending.Remove($info.id);Save-State}
        $script:reviewPopup.Close()
    })
    $later.Add_Click({$script:reviewPopup.Close()})
    $window.Add_FormClosed({
        $info=$this.Tag
        if($state.reviewPending.ContainsKey($info.id) -and $state.reviewPending[$info.id].token -eq $info.token){$state.reviewPending[$info.id].due=(Get-Date).AddMinutes(5).ToString('o');Save-State}
        $script:reviewPopup=$null;$this.Dispose()
    })
    $window.Controls.AddRange(@($message,$done,$later));[Media.SystemSounds]::Exclamation.Play();$window.Show()
}
function Get-OrderedTasks($items,$section) {
    $used=@{};$ordered=[Collections.Generic.List[object]]::new()
    foreach($id in @($state.orders[$section])){
        foreach($task in $items){if($task.id -eq $id -and -not $used.ContainsKey($id)){$ordered.Add($task);$used[$id]=$true;break}}
    }
    foreach($task in $items){if(-not $used.ContainsKey($task.id)){$ordered.Add($task)}}
    foreach($task in $ordered){$task}
}
function Apply-TaskOrder {
    $tasks=@($script:tasks | Where-Object {$_.section -eq $script:selectedSection})
    $ordered=@(Get-OrderedTasks $tasks $script:selectedSection)
    $panel.SuspendLayout()
    $index=0
    foreach($task in $ordered){
        $card=$panel.Controls | Where-Object {$_.Name -eq $task.id} | Select-Object -First 1
        if($card){$panel.Controls.SetChildIndex($card,$index);$index++}
    }
    $panel.ResumeLayout()
}
function Get-EditorReminderValue($task,[datetime]$now=(Get-Date)) {
    if($task.reminderAt){return [datetime]::ParseExact($task.reminderAt,'yyyy-MM-dd HH:mm',$null)}
    if($task.time){return $now.Date.Add([timespan]::Parse($task.time))}
    if($task.reminderMode -ne 'off' -and $task.note -match '^\s*([0-2]?[0-9]:[0-5][0-9])'){
        return $now.Date.Add([timespan]::Parse($Matches[1]))
    }
    return $now
}
function Get-ReminderCaption($task) {
    if($task.id -like 'guide-*' -and -not $state.done[$task.id]){return $task.note}
    if($task.section -eq '临时任务' -and $state.done[$task.id]){
        if($state.completedAt[$task.id]){return '完成于：'+$state.completedAt[$task.id]}
        return '已完成 · 时间未记录'
    }
    if($task.reminderMode -eq 'off'){return '提醒已关闭'}
    if($task.reminderMode -eq 'weekly' -and $task.time){
        $names=@('日','一','二','三','四','五','六')
        $days=@(foreach($day in @(1,2,3,4,5,6,0)){if($day -in @($task.weekdays)){$names[$day]}})
        return '每周'+($days -join '、')+' '+$task.time
    }
    if($task.reminderAt){return '提醒：'+$task.reminderAt}
    return $task.note
}
function Snooze-TaskReminders($ids,[datetime]$now=(Get-Date)) {
    foreach($id in $ids){if(-not $state.done[$id]){$state.snoozes[$id]=$now.AddMinutes(5).ToString('o')}}
}
function Test-ScheduledReminderDue($task,[datetime]$now) {
    if($state.done[$task.id]){return $false}
    if($state.snoozes.ContainsKey($task.id)){return [datetime]::Parse($state.snoozes[$task.id]) -le $now}
    return (-not $state.notified[$task.id] -and (Test-ReminderDue $task $now))
}
function Test-ReminderDue($task,[datetime]$now) {
    if($task.id -and $state.done[$task.id]){return $false}
    if(-not $task.time -or $task.reminderMode -eq 'off'){return $false}
    if($task.reminderMode -eq 'weekly'){
        return ([int]$now.DayOfWeek -in @($task.weekdays) -and $now.TimeOfDay -ge [timespan]::Parse($task.time))
    }
    if($task.reminderAt){
        $scheduled=[datetime]::ParseExact($task.reminderAt,'yyyy-MM-dd HH:mm',$null)
        return ($scheduled.Date -eq $now.Date -and $scheduled -le $now)
    }
    return ($now.TimeOfDay -ge [timespan]::Parse($task.time))
}
function Reset-DailyRecords {
    $keepDone=@{}; $keepNotified=@{}
    foreach($task in @($state.custom)+@($state.trash)){
        if($task.section -in @('上午','下午')){continue}
        if($state.done.ContainsKey($task.id)){$keepDone[$task.id]=$state.done[$task.id]}
        if($state.notified.ContainsKey($task.id)){$keepNotified[$task.id]=$state.notified[$task.id]}
    }
    $state.done=$keepDone; $state.notified=$keepNotified
}

if($SelfTest){
    $script:tasks=@(Get-Tasks ([datetime]'2026-10-29'))
    if($script:tasks.Count -ne 15 -or @($state.custom).Count -ne 8){throw 'Unexpected starter tasks'}
    if(@($script:tasks|Where-Object {Test-ReminderDue $_ ([datetime]'2026-10-29 15:00')}).Count){throw 'Tutorial reminders must be disabled'}
    $id=$state.custom[0].id;Move-ToTrash $id
    if(@($state.trash).Count -ne 1 -or @($state.custom).Count -ne 7){throw 'Trash failed'}
    Restore-Task $id
    if(@($state.custom).Count -ne 8 -or @($state.trash).Count -ne 0){throw 'Restore failed'}
    if(Remove-TaskGroup 'guide-group'){throw 'Non-empty group must not be deleted'}
    $state.done[$id]=$true;$state.completedAt[$id]='2026-10-29 10:05'
    $task=$state.custom|Where-Object {$_.id -eq $id}|Select-Object -First 1
    if((Get-ReminderCaption $task) -ne '完成于：2026-10-29 10:05'){throw 'Completion caption failed'}
    if((Get-Tasks ([datetime]'2026-10-31')).Count -ne 15){throw 'Template visibility failed'}
    Write-Output 'PASS: guide-only startup, disabled guide reminders, trash/restore, group guard, completion timestamps and template visibility'
    exit
}
$form=[CozyWindow]::new()
$form.Text='吐司办公 · 朋友体验版'; $form.Size=[System.Drawing.Size]::new(460,790)
$workArea=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.MinimumSize=[Drawing.Size]::new([Math]::Min(430,$workArea.Width),[Math]::Min(400,$workArea.Height))
$form.MaximumSize=[Drawing.Size]::new([Math]::Min(560,$workArea.Width),[Math]::Min(1200,$workArea.Height))
if($state.windowSize.width -and $state.windowSize.height){
    $form.Size=[Drawing.Size]::new([Math]::Max($form.MinimumSize.Width,[Math]::Min($form.MaximumSize.Width,$state.windowSize.width)),[Math]::Max($form.MinimumSize.Height,[Math]::Min($form.MaximumSize.Height,$state.windowSize.height)))
}
$form.Add_ResizeEnd({$state.windowSize=@{width=$form.Width;height=$form.Height};Save-State})
$form.StartPosition='Manual'; $screen=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location=[System.Drawing.Point]::new(([Math]::Max($screen.Left, $screen.Right-$form.Width-20)),40)
$form.ForeColor=[Drawing.Color]::Black; $form.TopMost=$true; $form.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#FFF7DE')
$form.Font=[System.Drawing.Font]::new('Microsoft YaHei UI',10)
$header=[System.Windows.Forms.Label]::new(); $header.Dock='Top'; $header.Height=40
$header.Padding=[System.Windows.Forms.Padding]::new(18,5,0,0)
$header.Font=[System.Drawing.Font]::new('Microsoft YaHei UI',11,[System.Drawing.FontStyle]::Bold)
$bar=[System.Windows.Forms.FlowLayoutPanel]::new(); $bar.Dock='Top'; $bar.Height=45; $bar.Padding=[System.Windows.Forms.Padding]::new(6,4,0,0)
$templateName=[TemplateNameLabel]::new();$templateName.Text='选择表单';$templateName.AutoEllipsis=$true;$templateName.Size=[Drawing.Size]::new(120,28);$templateName.TextAlign='MiddleCenter';$templateName.Cursor='Hand'
$templateClick=[Windows.Forms.Timer]::new();$templateClick.Interval=[Windows.Forms.SystemInformation]::DoubleClickTime
$templateClick.Add_Tick({$templateClick.Stop();Show-TemplateChooser})
$templateName.Add_Click({$templateClick.Stop();$templateClick.Start()})
$templateName.Add_DoubleClick({$templateClick.Stop();Rename-SelectedTemplate})
$form.Add_Disposed({$templateClick.Dispose()})
$top=[PinToggle]::new(); $top.Checked=$true
$add=[System.Windows.Forms.Button]::new(); $add.Text='＋'; $add.Width=44; $add.Dock='Right'; $add.Font=[Drawing.Font]::new('Microsoft YaHei UI',18); $add.FlatStyle='Flat'; $add.BackColor=[Drawing.ColorTranslator]::FromHtml('#FFF7DE'); $add.ForeColor=[Drawing.Color]::Black; $add.FlatAppearance.BorderSize=0; $add.FlatAppearance.MouseOverBackColor=$add.BackColor; $add.FlatAppearance.MouseDownBackColor=$add.BackColor
$bar.Controls.Add($templateName)
$min=[Windows.Forms.Button]::new(); $min.Text='−'; $min.Width=25; $min.FlatStyle='Flat'; $min.Add_Click({$form.WindowState='Minimized'})
$exitButton=[Windows.Forms.Button]::new(); $exitButton.Text='×'; $exitButton.Width=25; $exitButton.FlatStyle='Flat'; $exitButton.Add_Click({$form.Close()})
# Window controls are hosted in the banner.
$trashButton=[RecycleButton]::new()
$trashButton.BackColor=[Drawing.ColorTranslator]::FromHtml('#FFF7DE'); $trashButton.FlatAppearance.MouseOverBackColor=$trashButton.BackColor; $trashButton.FlatAppearance.MouseDownBackColor=$trashButton.BackColor
$bar.WrapContents=$false
$bar.Controls.Add($trashButton)
$trashButton.Add_Click({Show-Trash})
$script:batchMode=$false;$script:batchSelected=@{}
$multi=[Windows.Forms.CheckBox]::new();$multi.Text='多选';$multi.AutoSize=$true;$bar.Controls.Add($multi)
$bar.Controls.SetChildIndex($multi,$bar.Controls.GetChildIndex($trashButton))
$multi.Add_CheckedChanged({$script:batchMode=$this.Checked;$script:batchSelected.Clear();$batchDelete.Visible=$this.Checked
$footer.Height=if($this.Checked){76}else{45}
Update-FooterLayout
Paint-Tasks})
$settingsButton=[SettingsButton]::new();$bar.Controls.Add($settingsButton);$settingsButton.Add_Click({Show-Settings})
$toolbarGap=[Windows.Forms.Panel]::new();$toolbarGap.Height=1;$toolbarGap.Margin=[Windows.Forms.Padding]::Empty
$bar.Controls.Add($toolbarGap);$bar.Controls.SetChildIndex($toolbarGap,1)
function Align-ToolbarRight {
    $used=$bar.Padding.Horizontal+8
    foreach($control in $bar.Controls){if($control -ne $toolbarGap){$used+=$control.Width+$control.Margin.Horizontal}}
    $toolbarGap.Width=[Math]::Max(0,$bar.ClientSize.Width-$used)
}
$bar.Add_SizeChanged({Align-ToolbarRight})
$bar.Add_Layout({Align-ToolbarRight})
Align-ToolbarRight
. (Join-Path $base 'themes.ps1')
$foot=[System.Windows.Forms.Label]::new(); $foot.Dock='Bottom'; $foot.Height=45; $bar.Padding=[System.Windows.Forms.Padding]::new(6,4,0,0)
$foot.Text='打钩即完成 · 次日自动重置 · 最小化后仍提醒'; $foot.Padding=[System.Windows.Forms.Padding]::new(10,8,0,0)
$footer=[Windows.Forms.Panel]::new(); $footer.Dock='Bottom'; $footer.Height=45
$foot.Dock='Fill'; $foot.Font=[Drawing.Font]::new('Microsoft YaHei UI',8)
$footer.Controls.Add($foot); $footer.Controls.Add($add)
$batchDelete=[RecycleButton]::new();$batchDelete.AccessibleName='删除选中的任务';$batchDelete.Visible=$false
$batchDelete.Anchor='Top,Right';$batchDelete.SetBounds(($footer.Width-40),0,32,28);$footer.Controls.Add($batchDelete);$batchDelete.BringToFront()
function Update-FooterLayout {
    $foot.Dock='None';$foot.SetBounds(0,0,[Math]::Max(0,$footer.ClientSize.Width-48),$footer.ClientSize.Height)
    $add.Dock='None';$add.Anchor='Bottom,Right'
    $add.SetBounds([Math]::Max(0,$footer.ClientSize.Width-44),[Math]::Max(0,$footer.ClientSize.Height-36),44,36)
    $batchDelete.SetBounds([Math]::Max(0,$footer.ClientSize.Width-38),2,32,28)
    $add.BringToFront();$batchDelete.BringToFront()
}
$footer.Add_SizeChanged({Update-FooterLayout})
Update-FooterLayout
$batchDelete.Add_Click({
    $ids=@($script:batchSelected.Keys | Where-Object {$script:batchSelected[$_]})
    if($ids.Count -eq 0){[void][Windows.Forms.MessageBox]::Show($form,'请先勾选要删除的任务。','批量删除');return}
    $answer=[Windows.Forms.MessageBox]::Show($form,('确定删除选中的 '+$ids.Count+' 项任务吗？'+[Environment]::NewLine+'删除后可从垃圾箱恢复。'),'确认批量删除',[Windows.Forms.MessageBoxButtons]::OKCancel,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2)
    if($answer -ne [Windows.Forms.DialogResult]::OK){return}
    foreach($id in $ids){Move-ToTrash $id}
    $script:batchSelected.Clear();Save-State;Paint-Tasks
})
$panel=[StableTaskList]::new(); $panel.Dock='Fill'; $panel.AutoScroll=$true
$panel.FlowDirection='TopDown'; $panel.WrapContents=$false
$groupSlide=[GroupSlide]::new($panel);$groupSlide.Add_Completed({Paint-Tasks;Save-State})
$taskSorter=[TaskSorter]::new($panel)
$taskSorter.Add_OrderChanged({
        $visible=@($panel.Controls | Where-Object {$_ -is [CozyCard]} | ForEach-Object {$_.Name})
    if($script:selectedSection -eq '临时任务'){
        $state.groupOrder=@($panel.Controls | Where-Object {$_ -is [TaskGroupHeader]} | ForEach-Object {$_.GroupId})
        $currentGroup='ungrouped'
        foreach($control in $panel.Controls){
            if($control -is [TaskGroupHeader]){$currentGroup=$control.GroupId}
            elseif($control -is [CozyCard]){Move-TaskGroup $control.Name $currentGroup}
        }
    }
    $other=@($state.orders[$script:selectedSection] | Where-Object {$_ -and $_ -notin $visible})
    $state.orders[$script:selectedSection]=@($visible)+@($other)
    Save-State
    if($script:selectedSection -eq '临时任务'){Paint-Tasks}else{Apply-TaskOrder}
})
$sectionStatus=[Windows.Forms.TableLayoutPanel]::new(); $sectionStatus.Dock='Top'; $sectionStatus.Height=42
$sectionStatus.ColumnCount=3; $sectionStatus.RowCount=1
[void]$sectionStatus.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,30))
[void]$sectionStatus.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,30))
[void]$sectionStatus.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,40))
$script:selectedSection='上午'
$morningTab=[Windows.Forms.Button]::new(); $afternoonTab=[Windows.Forms.Button]::new()
$temporaryTab=[Windows.Forms.Button]::new(); $temporaryTab.Tag='临时任务'
$morningTab.Tag='上午'; $afternoonTab.Tag='下午'
foreach($tab in @($morningTab,$afternoonTab,$temporaryTab)){
    $menu=[Windows.Forms.ContextMenuStrip]::new()
    $newItem=[Windows.Forms.ToolStripMenuItem]::new(); $newItem.Text='新建任务'; $newItem.Tag=$tab.Tag
    $newItem.Add_Click({
        $script:selectedSection=$this.Tag
        Paint-Tasks
        $panel.AutoScrollPosition=[Drawing.Point]::Empty
        $add.PerformClick()
    })
    [void]$menu.Items.Add($newItem); $tab.ContextMenuStrip=$menu
    $tab.Dock='Fill'; $tab.FlatStyle='Flat'; $tab.Margin=[Windows.Forms.Padding]::new(3,0,3,3)
    $tab.ForeColor=[Drawing.Color]::Black; $tab.Font=[Drawing.Font]::new($form.Font,[Drawing.FontStyle]::Bold)
    $tab.Add_Click({
        if($script:selectedSection -eq $this.Tag){return}
        $script:selectedSection=$this.Tag
        Paint-Tasks
        $panel.AutoScrollPosition=[Drawing.Point]::Empty
    })
}
$sectionStatus.Controls.Add($morningTab,0,0); $sectionStatus.Controls.Add($afternoonTab,1,0); $sectionStatus.Controls.Add($temporaryTab,2,0)
$form.Controls.Add($panel); $form.Controls.Add($sectionStatus); $form.Controls.Add($bar); $form.Controls.Add($header); $form.Controls.Add($footer); $banner=[CozyBanner]::new(); $banner.Caption=$state.title; $banner.Add_TitleCommitted({$state.title=$banner.Caption; Save-State}); $form.Controls.Add($banner)
$min.Anchor='Top,Right';$exitButton.Anchor='Top,Right'
$top.Anchor='Top,Right';$top.SetBounds(($banner.Width-132),5,36,32)
$min.SetBounds(($banner.Width-90),5,36,32);$exitButton.SetBounds(($banner.Width-46),5,36,32)
foreach($button in @($min,$exitButton)){
    $button.FlatAppearance.BorderSize=0
    $button.Font=[Drawing.Font]::new('Microsoft YaHei UI',14)
    $button.AccessibleName=if($button -eq $min){'最小化'}else{'收起到托盘'}
}
$banner.Controls.AddRange(@($top,$min,$exitButton))
$pinTip=[Windows.Forms.ToolTip]::new();$pinTip.SetToolTip($top,'置顶／取消置顶');$form.Add_Disposed({$pinTip.Dispose()})
$bar.Padding=[Windows.Forms.Padding]::new(12,4,0,0)
$slogans=@(
    '今天也是元气满满的一天呢！',
    '不慌不忙，一件一件来。',
    '做完一件，就少惦记一件。',
    '今日份努力，正在加载中……',
    '工作有条理，心里有底气。',
    '小小进度，也值得一个大大的勾。',
    '今天的待办，正在变成已完成。',
    '慢慢来，你已经在前进啦。',
    '认真工作，也别忘了喝水。',
    '电量不足？先给自己充个电。',
    '愿今天的忙碌，都有好结果。',
    '上班搭子已就位，今天也一起加油！',
    '把事情理顺，把心情放松。',
    '今日目标：有进度，也有好心情。',
    '吐司烤好了，今天也会好起来的。'
)
$state.sloganIndex=(([int]$state.sloganIndex+1)%$slogans.Count)
$banner.Slogan=$slogans[$state.sloganIndex]
Save-State
$script:today=''; $script:tasks=@(); $script:popup=$null
function Update-SectionStatus {
    $selectedForm=Get-SelectedTemplate;$templateName.Text=if($selectedForm){$selectedForm.name}else{'选择表单'}
    foreach($tab in @($morningTab,$afternoonTab,$temporaryTab)){
        $items=@($script:tasks | Where-Object {$_.section -eq $tab.Tag})
        $count=@($items | Where-Object {$state.done[$_.id]}).Count
        $tab.Text="$($tab.Tag) · $count/$($items.Count)"
        if($tab.Tag -eq $script:selectedSection){$tab.BackColor=Theme-Color 'accent'}
        else{$tab.BackColor=Theme-Color 'bg'}
    }
}
function Show-Trash {
    $bin=[Windows.Forms.Form]::new(); $bin.Text='垃圾箱 · 可恢复误删任务'; $bin.Size=[Drawing.Size]::new(540,420)
    $bin.StartPosition='CenterParent'; $bin.Font=$form.Font; $bin.BackColor=$form.BackColor; $bin.TopMost=$form.TopMost
    $hint=[Windows.Forms.Label]::new(); $hint.Dock='Top'; $hint.Height=42; $hint.Text='删除的任务保留在这里，选中后点击恢复。'; $hint.Padding=[Windows.Forms.Padding]::new(10)
    $list=[Windows.Forms.ListView]::new();$list.Dock='Fill';$list.View='Details';$list.FullRowSelect=$true;$list.GridLines=$true;$list.MultiSelect=$false;$list.HideSelection=$false
    [void]$list.Columns.Add('任务',325);[void]$list.Columns.Add('时间',165)
    $list.Add_SizeChanged({$this.Columns[0].Width=[Math]::Max(180,$this.ClientSize.Width-175)})
    $actions=[Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock='Bottom'; $actions.Height=46
    $restore=[Windows.Forms.Button]::new(); $restore.Text='恢复选中任务'; $restore.Width=140; $restore.BackColor=[Drawing.ColorTranslator]::FromHtml('#C5DDB3')
    $refresh={
        $list.Items.Clear()
        foreach($task in $state.trash){
            $title=$task.text
            if($state.edits.ContainsKey($task.id)){$title=$state.edits[$task.id].text}
            $created=if($task.createdAt){[string]$task.createdAt}elseif($task.date){[string]$task.date}else{'—'}
            $item=[Windows.Forms.ListViewItem]::new([string]$title);$item.Tag=$task.id;[void]$item.SubItems.Add($created);[void]$list.Items.Add($item)
        }
        $restore.Enabled=$list.Items.Count -gt 0
        if($list.Items.Count -gt 0){$list.Items[0].Selected=$true}
    }
    $restore.Add_Click({
        if($list.SelectedItems.Count -eq 0){return}
        Restore-Task $list.SelectedItems[0].Tag
        Save-State; & $refresh; Paint-Tasks
    })
    $actions.Controls.Add($restore); $bin.Controls.Add($list); $bin.Controls.Add($hint); $bin.Controls.Add($actions)
    & $refresh
    [void]$bin.ShowDialog($form); $bin.Dispose()
}
function Edit-Task($id,[switch]$Document) {
    $temporary=$script:tasks | Where-Object {$_.id -eq $id -and $_.section -eq '临时任务'} | Select-Object -First 1
    if($temporary -and $Document){
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$key=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($id)))).Replace('-','')}finally{$hash.Dispose()}
        $documentPath=Join-Path (Join-Path $dataRoot 'documents') ($key+'.rtf')
        $onDocumentSaved=[Action[string,string]]{
            param($savedId,$savedTitle)
            if(-not $state.edits.ContainsKey($savedId)){
                $record=@($state.custom)+@($state.trash) | Where-Object {$_.id -eq $savedId} | Select-Object -First 1
                $state.edits[$savedId]=@{text=$savedTitle;note=$record.note;time=$record.time}
            }
            $state.edits[$savedId].text=$savedTitle
            Save-State;Paint-Tasks
        }
        [void][TaskDocument]::Open($form,$documentPath,$temporary.text,$id,$onDocumentSaved)
        return
    }
    $task=$script:tasks | Where-Object {$_.id -eq $id} | Select-Object -First 1
    if(-not $task){return}
    $editForm=[Windows.Forms.Form]::new(); $editForm.Text='编辑任务'; $editForm.Size=[Drawing.Size]::new(440,430)
    $editForm.StartPosition='CenterParent'; $editForm.Font=$form.Font; $editForm.BackColor=$form.BackColor; $editForm.TopMost=$true
    $fields=@()
    $captions=@('任务名称','说明')
    $values=@($task.text,$task.note,$task.time)
    for($i=0;$i -lt 2;$i++){
        $label=[Windows.Forms.Label]::new(); $label.Text=$captions[$i]; $label.SetBounds(18,(12+$i*72),370,24)
        $field=[Windows.Forms.TextBox]::new(); $field.Text=$values[$i]; $field.SetBounds(18,(38+$i*72),365,28)
        $fields+=,$field; $editForm.Controls.AddRange(@($label,$field))
    }
    $enableReminder=[Windows.Forms.CheckBox]::new();$enableReminder.Text='启用提醒';$enableReminder.Checked=$true;$enableReminder.SetBounds(18,156,150,24)
    $weekly=[Windows.Forms.RadioButton]::new();$weekly.Text='每周重复';$weekly.SetBounds(18,187,130,25)
    $specific=[Windows.Forms.RadioButton]::new();$specific.Text='指定日期';$specific.SetBounds(160,187,130,25)
    $days=[Windows.Forms.FlowLayoutPanel]::new();$days.SetBounds(18,222,395,35);$days.WrapContents=$false
    $dayChecks=@()
    foreach($day in @(1,2,3,4,5,6,0)){
        $box=[Windows.Forms.CheckBox]::new();$box.Text=@('日','一','二','三','四','五','六')[$day];$box.Tag=$day;$box.Width=49
        $box.Checked=($day -eq [int](Get-Date).DayOfWeek)
        if($task.weekdays){$box.Checked=($day -in @($task.weekdays))}
        $dayChecks+=,$box;$days.Controls.Add($box)
    }
    $datePicker=[Windows.Forms.DateTimePicker]::new();$datePicker.Format='Custom';$datePicker.CustomFormat='yyyy-MM-dd';$datePicker.SetBounds(18,267,190,28)
    $timePicker=[Windows.Forms.DateTimePicker]::new();$timePicker.Format='Custom';$timePicker.CustomFormat='HH:mm';$timePicker.ShowUpDown=$true;$timePicker.SetBounds(225,267,165,28)
    $current=Get-EditorReminderValue $task;$datePicker.Value=$current;$timePicker.Value=$current
    if($task.reminderAt){$previous=[datetime]::ParseExact($task.reminderAt,'yyyy-MM-dd HH:mm',$null);$datePicker.Value=$previous;$timePicker.Value=$previous;$specific.Checked=$true}elseif($task.section -eq '临时任务'){$specific.Checked=$true}else{$weekly.Checked=$true}
    if($task.reminderMode -eq 'weekly'){$weekly.Checked=$true;if($task.time){$timePicker.Value=[datetime]::Today.Add([timespan]::Parse($task.time))}}
    $syncReminder={
        $weekly.Enabled=$enableReminder.Checked;$specific.Enabled=$enableReminder.Checked
        $days.Enabled=$enableReminder.Checked -and $weekly.Checked
        $datePicker.Enabled=$enableReminder.Checked -and $specific.Checked;$timePicker.Enabled=$enableReminder.Checked
    }
    if($task.reminderMode -eq 'off'){$enableReminder.Checked=$false}
    $enableReminder.Add_CheckedChanged($syncReminder);$weekly.Add_CheckedChanged($syncReminder);$specific.Add_CheckedChanged($syncReminder)
    $editForm.Controls.AddRange(@($enableReminder,$weekly,$specific,$days,$datePicker,$timePicker)); & $syncReminder
    $save=[Windows.Forms.Button]::new(); $save.Text='保存'; $save.SetBounds(300,335,90,32); $save.BackColor=[Drawing.ColorTranslator]::FromHtml('#FFC4CC')
    $save.Add_Click({
        if([string]::IsNullOrWhiteSpace($fields[0].Text)){return}
        $reminder='';$reminderAt='';$mode='off';$weekdays=@()
        if($enableReminder.Checked){
            $reminder=$timePicker.Value.ToString('HH:mm')
            if($weekly.Checked){
                $mode='weekly';$weekdays=@($dayChecks | Where-Object {$_.Checked} | ForEach-Object {[int]$_.Tag})
                if($weekdays.Count -eq 0){[void][Windows.Forms.MessageBox]::Show($editForm,'请至少选择一个星期。','每周提醒');return}
            }else{$mode='date';$reminderAt=$datePicker.Value.ToString('yyyy-MM-dd')+' '+$reminder}
        }
        $state.edits[$task.id]=@{text=$fields[0].Text.Trim();note=$fields[1].Text.Trim();time=$reminder;reminderAt=$reminderAt;reminderMode=$mode;weekdays=$weekdays}
        $state.notified.Remove($task.id)
        Save-State; $editForm.Close(); Paint-Tasks
    })
    $editForm.Controls.Add($save); [void]$editForm.ShowDialog($form); $editForm.Dispose()
}
function Resize-TaskCards {
    if($script:resizingCards -or $panel.IsDisposed -or ($groupSlide -and $groupSlide.IsRunning)){return}
    $script:resizingCards=$true
    try{
        $panel.SuspendLayout()
        $width=[Math]::Max(300,$panel.ClientSize.Width-28)
        foreach($card in $panel.Controls){if($card -is [CozyCard]){$card.FitWidth($width)}elseif($card -is [TaskGroupHeader]){$card.Width=$width}}
        $panel.ResumeLayout()
        $banner.Invalidate()
    }finally{$script:resizingCards=$false}
}
$panel.Add_ClientSizeChanged({Resize-TaskCards})
$groupMenu=[Windows.Forms.ContextMenuStrip]::new();$newGroup=$groupMenu.Items.Add('新建分组');$newGroup.Add_Click({Edit-GroupName})
$groupMenu.Add_Opening({param($sender,$eventArgs) $eventArgs.Cancel=$script:selectedSection -ne '临时任务'})
$panel.ContextMenuStrip=$groupMenu
function Paint-Tasks {
    if($groupSlide -and $groupSlide.IsRunning){$groupSlide.Cancel()}
    $panel.SuspendLayout(); $panel.Controls.Clear()
    $day=Get-Date
    $header.Text=$day.ToString('MM月dd日 dddd')+' · 今日工作'
    $script:tasks=@(Get-Tasks $day)
    foreach($section in @($script:selectedSection)){
        $items=@($script:tasks | Where-Object {$_.section -eq $section})
        $count=@($items | Where-Object {$state.done[$_.id]}).Count
        $items=@(Get-OrderedTasks $items $section)
        if($section -eq '临时任务'){$items=@(Get-GroupedItems $items)}
        foreach($task in $items){
            if($task.isGroupHeader){$panel.Controls.Add((New-GroupHeader $task));continue}
            $row=[CozyCard]::new(); $row.Font=$form.Font; $row.Name=$task.id; $row.GroupId=Get-TaskGroup $task.id; $row.Tag=$section; $row.Width=[Math]::Max(345,($panel.ClientSize.Width-48)); $row.Height=80
            $row.Margin=[System.Windows.Forms.Padding]::new(8,3,4,3); $row.FillColor=[Drawing.ColorTranslator]::FromHtml('#FFFEF5')
            $check=[TaskCheckBox]::new(); $check.Font=$form.Font; $check.Text=$task.text; $check.Tag=$task.id
            $check.BackColor=$row.FillColor; $check.ForeColor=[Drawing.Color]::Black; $check.Location=[System.Drawing.Point]::new(14,8); $check.Size=[System.Drawing.Size]::new(($row.Width-32),36)
            $check.Checked=[bool]$state.done[$task.id]
            if($check.Checked){
                $check.Font=[System.Drawing.Font]::new($form.Font,[System.Drawing.FontStyle]::Strikeout)
                $row.FillColor=[Drawing.ColorTranslator]::FromHtml('#ADADAD'); $check.BackColor=$row.FillColor
            }
            $check.Add_Click({
                if($script:batchMode){$script:batchSelected[$this.Tag]=$this.Checked;return}
                $state.done[$this.Tag]=$this.Checked
                if($this.Parent.Tag -eq '临时任务'){
                    if($this.Checked){$state.completedAt[$this.Tag]=[datetime]::Now.ToString('yyyy-MM-dd HH:mm')}
                    else{$state.completedAt.Remove($this.Tag)}
                    $currentTask=$script:tasks | Where-Object {$_.id -eq $this.Tag} | Select-Object -First 1
                    foreach($label in $this.Parent.Controls){if($label.Tag -eq 'task-note'){$label.Text=Get-ReminderCaption $currentTask}}
                    $this.Parent.FitTaskText()
                }
                if($this.Checked){$state.snoozes.Remove($this.Tag)}
                Schedule-Review $this.Tag $this.Checked
                $oldFont=$this.Font
                $style=[Drawing.FontStyle]::Regular
                if($this.Checked){$style=[Drawing.FontStyle]::Strikeout}
                $this.Font=[Drawing.Font]::new($form.Font,$style)
                if(-not [object]::ReferenceEquals($oldFont,$form.Font)){$oldFont.Dispose()}
                $this.ForeColor=[Drawing.Color]::Black
                $card=$this.Parent
                $fill=[Drawing.ColorTranslator]::FromHtml('#FFFEF5')

                if($this.Checked){$fill=[Drawing.ColorTranslator]::FromHtml('#ADADAD')}
                $card.FillColor=$fill
                foreach($child in $card.Controls){
                    $child.BackColor=$fill
                    if($child.Tag -eq 'task-title'){
                        $previous=$child.Font
                        $child.Font=[Drawing.Font]::new($form.Font,$style)
                        $previous.Dispose()
                    }
                }
                Apply-TaskTheme $card
                Update-SectionStatus
                Save-State
            })
            $note=[System.Windows.Forms.Label]::new(); $note.Tag='task-note'; $note.Text=Get-ReminderCaption $task; $note.BackColor=$row.FillColor; $note.Location=[System.Drawing.Point]::new(33,48)
            $note.Size=[System.Drawing.Size]::new(($row.Width-40),22); $note.Font=[System.Drawing.Font]::new('Microsoft YaHei UI',8)
            $note.ForeColor=[Drawing.Color]::Black
            $check.Width=$row.Width-88; $note.Width=$row.Width-90
            $editButton=[Windows.Forms.Button]::new(); $editButton.Text='编辑'; $editButton.Tag=$task.id
            $editButton.FlatStyle='Flat'; $editButton.BackColor=[Drawing.ColorTranslator]::FromHtml('#D8EBCB')
            $editButton.SetBounds(($row.Width-74),8,62,28)
            $editButton.Add_Click({Edit-Task $this.Tag})
            $row.Controls.AddRange(@($check,$note,$editButton))
            if(@($state.custom | Where-Object {$_.id -eq $task.id}).Count){
                $check.Width=$row.Width-88; $note.Width=$row.Width-90

                $row.Name=$task.id; $row.Add_DoubleClick({Edit-Task $this.Name -Document})
                $note.Name=$task.id; $note.Add_DoubleClick({Edit-Task $this.Name -Document})
                $check.Text=''; $check.Width=20
                $titleLabel=[Windows.Forms.Label]::new(); $titleLabel.Text=$task.text; $titleLabel.Name=$task.id
                $titleLabel.Tag='task-title'; $titleLabel.BackColor=$row.FillColor
                $titleLabel.SetBounds(35,8,($row.Width-110),36)
                $titleLabel.Font=[Drawing.Font]::new($form.Font,$check.Font.Style); $titleLabel.ForeColor=[Drawing.Color]::Black; $titleLabel.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
                $titleLabel.Add_DoubleClick({Edit-Task $this.Name -Document})
                $row.Controls.Add($titleLabel)
            }
            $delete=[Windows.Forms.Button]::new(); $delete.Text='删除'; $delete.Tag=$task.id
                $delete.FlatStyle='Flat'; $delete.BackColor=[Drawing.ColorTranslator]::FromHtml('#FFC4CC')
                $delete.Size=[Drawing.Size]::new(62,28); $delete.Location=[Drawing.Point]::new(($row.Width-74),43)
                $delete.Add_Click({
                    $id=$this.Tag
                    Request-DeleteTask $id
                })
            $row.Controls.Add($delete)
            if($script:batchMode){$check.Checked=[bool]$script:batchSelected[$task.id]}
            $row.FitTaskText()
            Attach-ReviewMenu $row $task.id
            $taskSorter.Attach($row)
            $panel.Controls.Add($row)
        }
    }
    if($script:tasks.Count -eq 0){$foot.Text='暂无任务，可选择表单或添加任务。'}else{$foot.Text='打钩即完成 · 次日自动重置 · 最小化后仍提醒'}
    Apply-Theme; $panel.ResumeLayout(); Resize-TaskCards; Update-SectionStatus
}
function Roll-Day {
    $date=(Get-Date).ToString('yyyy-MM-dd')
    if($state.date -ne $date){$state.date=$date; Reset-DailyRecords; Save-State}
    if($script:today -ne $date){$script:today=$date; Paint-Tasks}
}

$top.Add_CheckedChanged({$form.TopMost=$top.Checked})
$add.Add_Click({
    $currentTemplate=Get-SelectedTemplate
    if($currentTemplate -and $script:selectedSection -in @('上午','下午')){
        Edit-TemplateTask $currentTemplate $null $script:selectedSection
        return
    }
    $dialog=[System.Windows.Forms.Form]::new(); $targetSection=$script:selectedSection; $dialog.Text='新建'+$targetSection+'任务'; $dialog.Size=[System.Drawing.Size]::new(370,270)
    $dialog.StartPosition='CenterParent'; $dialog.Font=$form.Font; $dialog.TopMost=$true
    $name=[System.Windows.Forms.TextBox]::new(); $name.Location=[System.Drawing.Point]::new(20,35); $name.Width=310
    $caption=[System.Windows.Forms.Label]::new(); $caption.Text='任务内容（保留至手动删除）'; $caption.Location=[System.Drawing.Point]::new(20,10); $caption.Width=310
    $ok=[System.Windows.Forms.Button]::new(); $ok.Text='添加'; $ok.Location=[System.Drawing.Point]::new(240,165)
    $ok.Add_Click({
        if([string]::IsNullOrWhiteSpace($name.Text)){return}
        $task=@{id=[guid]::NewGuid().ToString(); createdAt=[datetime]::Now.ToString('yyyy-MM-dd HH:mm'); date=(Get-Date).ToString('yyyy-MM-dd'); text=$name.Text.Trim(); time=''; section=$targetSection; note=$(if($targetSection -eq '临时任务'){'图文任务 · 双击卡片编辑'}else{''})}

        $state.custom=@($state.custom)+@($task); if($targetSection -eq '临时任务' -and $script:activeGroup){Move-TaskGroup $task.id $script:activeGroup;$state.groupCollapsed[$script:activeGroup]=$false}; Save-State; $dialog.Close(); Paint-Tasks; Edit-Task $task.id -Document
    })
    $dialog.AcceptButton=$ok; $dialog.Controls.AddRange(@($caption,$name,$ok)); [void]$dialog.ShowDialog($form); $dialog.Dispose()
})
$timer=[System.Windows.Forms.Timer]::new(); $timer.Interval=15000
$timer.Add_Tick({
    Roll-Day
    Show-ReviewReminder
    $now=Get-Date
    $due=@($script:tasks | Where-Object {
        Test-ScheduledReminderDue $_ $now
    })
    if($due.Count -eq 0 -or $script:popup){return}
    foreach($t in $due){$state.notified[$t.id]=$true;$state.snoozes.Remove($t.id)}; Save-State
    $script:popup=[System.Windows.Forms.Form]::new(); $script:popup.Tag=@($due | ForEach-Object {$_.id}); $script:popup.Text='工作提醒'; $script:popup.Size=[System.Drawing.Size]::new(440,330)
    $script:popup.TopMost=$true; $script:popup.StartPosition='CenterScreen'; $script:popup.Font=$form.Font; $script:popup.BackColor=$form.BackColor
    $message=[System.Windows.Forms.TextBox]::new(); $message.Multiline=$true; $message.ReadOnly=$true; $message.ScrollBars='Vertical'
    $message.Location=[System.Drawing.Point]::new(15,15); $message.Size=[System.Drawing.Size]::new(390,200)
    $message.Text="以下任务已到时间（含今天错过的提醒）：`r`n`r`n"+(($due | ForEach-Object {$_.time+'  '+$_.text}) -join "`r`n")
    $close=[System.Windows.Forms.Button]::new(); $close.Text='查看任务'; $close.Location=[System.Drawing.Point]::new(290,235); $close.Width=110
    $close.Add_Click({$tray.Restore(); $script:popup.Close()})
    $snooze=[Windows.Forms.Button]::new();$snooze.Text='稍后提醒（5分钟）';$snooze.SetBounds(120,235,160,30)
    $snooze.Add_Click({Snooze-TaskReminders @($script:popup.Tag);Save-State;$script:popup.Close()})
    $script:popup.Add_FormClosed({$script:popup.Dispose(); $script:popup=$null})
    $script:popup.Controls.AddRange(@($message,$close,$snooze)); [System.Media.SystemSounds]::Exclamation.Play(); $script:popup.Show()
})
$form.Add_FormClosing({$banner.CommitTitle(); Save-State})
$form.Add_FormClosed({$timer.Stop()})

if($Preview){
    $form.FormBorderStyle='None';$form.Show();Roll-Day;[Windows.Forms.Application]::DoEvents()
    if(@($script:tasks).Count -ne 15){throw 'Starter guide count mismatch'}
    foreach($sectionName in @('上午','下午','临时任务')){
        $script:selectedSection=$sectionName;Paint-Tasks;Update-FooterLayout;[Windows.Forms.Application]::DoEvents()
        $shot=[Drawing.Bitmap]::new($form.Width,$form.Height);$form.DrawToBitmap($shot,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height))
        $suffix=switch($sectionName){'上午'{'morning'}'下午'{'afternoon'}default{'temporary'}}
        $shot.Save((Join-Path $dataRoot ('cn-'+$suffix+'.png')));$shot.Dispose()
    }
    foreach($theme in @('pink','dark')){$state.theme=$theme;Apply-Theme;[Windows.Forms.Application]::DoEvents()}
    $state.theme='cream';Apply-Theme
    $probe=[Windows.Forms.Timer]::new();$probe.Interval=350
    $probe.Add_Tick({foreach($window in @([Windows.Forms.Application]::OpenForms)){if($window -ne $form){$window.Close()}}});$probe.Start()
    Show-TemplateEditor $state.templates[0].id
    Edit-TemplateTask $state.templates[0] $state.templates[0].tasks[0]
    $document=Get-ChildItem (Join-Path $dataRoot 'documents') -Filter '*.rtf'|Select-Object -First 1
    $editor=[TaskDocument]::Open($form,$document.FullName,'使用说明','guide-test',[Action[string,string]]{param($id,$title)})
    [Windows.Forms.Application]::DoEvents();$editor.Close()
    $probe.Stop();$probe.Dispose()
    $form.Dispose();Write-Output 'PASS: Chinese share sections, tutorial counts, themes, template editors and guide document';exit
}
$desktopBehavior=[CozyDesktop]::new($form)
$tray=[ToastTray]::new($form,$desktopBehavior,(Join-Path $base 'schedule.ico'))
[void](Register-TemplateUse)
$form.Add_Activated({[void](Register-TemplateUse)})
Roll-Day; $timer.Start()
[System.Windows.Forms.Application]::Run($form)
if($mutex){$mutex.ReleaseMutex(); $mutex.Dispose()}
