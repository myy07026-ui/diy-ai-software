function Get-GroupColor($id) {
    switch([string]$state.groupColors[$id]){
        'pink'{return [Drawing.ColorTranslator]::FromHtml('#F5D7DF')}
        'blue'{return [Drawing.ColorTranslator]::FromHtml('#D5E6F5')}
        'gray'{return [Drawing.ColorTranslator]::FromHtml('#DEDFDC')}
        default{return [Drawing.ColorTranslator]::FromHtml('#D8EBCB')}
    }
}
function Get-TaskGroup($id) {
    $group=[string]$state.taskGroups[$id]
    if($group -and @($state.groups | Where-Object {$_.id -eq $group}).Count){return $group}
    return 'ungrouped'
}
function Get-TaskGroups {
    $all=@([pscustomobject]@{id='ungrouped';name=$(if($state.defaultGroupName){$state.defaultGroupName}else{'未分组'})})+@($state.groups)
    $used=@{}
    foreach($id in @($state.groupOrder)){
        foreach($group in $all){if($group.id -eq $id -and -not $used.ContainsKey($id)){$group;$used[$id]=$true;break}}
    }
    foreach($group in $all){if(-not $used.ContainsKey($group.id)){$group}}
}
function Move-TaskGroup($id,$group) {
    if($group -ne 'ungrouped' -and -not @($state.groups | Where-Object {$_.id -eq $group}).Count){return}
    $state.taskGroups[$id]=$group
}
function Get-GroupTaskCount($group) {
    return @($state.custom | Where-Object {(Get-TaskGroup $_.id) -eq $group}).Count
}
function Remove-TaskGroup($group) {
    if($group -eq 'ungrouped' -or (Get-GroupTaskCount $group) -gt 0){return $false}
    $state.groups=@($state.groups | Where-Object {$_.id -ne $group})
    foreach($id in @($state.taskGroups.Keys)){if($state.taskGroups[$id] -eq $group){$state.taskGroups.Remove($id)}}
    $state.groupCollapsed.Remove($group);$state.groupColors.Remove($group)
    $script:activeGroup='ungrouped'
    return $true
}
function Edit-GroupName($id='') {
    $dialog=[Windows.Forms.Form]::new();$dialog.Text=if($id){'重命名分组'}else{'新建分组'};$dialog.Size=[Drawing.Size]::new(350,170)
    $dialog.Font=$form.Font;$dialog.BackColor=$form.BackColor;$dialog.StartPosition='CenterParent';$dialog.TopMost=$form.TopMost
    $name=[Windows.Forms.TextBox]::new();$name.SetBounds(18,20,295,28);$name.MaxLength=80
    if($id -eq 'ungrouped'){$name.Text=(Get-TaskGroups | Where-Object {$_.id -eq 'ungrouped'} | Select-Object -First 1).name}elseif($id){$name.Text=($state.groups | Where-Object {$_.id -eq $id} | Select-Object -First 1).name}
    $ok=[Windows.Forms.Button]::new();$ok.Text='保存';$ok.SetBounds(225,65,90,30)
    $ok.Add_Click({
        if([string]::IsNullOrWhiteSpace($name.Text)){return}
        if($id -eq 'ungrouped'){$state.defaultGroupName=$name.Text.Trim()}elseif($id){($state.groups | Where-Object {$_.id -eq $id} | Select-Object -First 1).name=$name.Text.Trim()}
        else{$group=@{id=[guid]::NewGuid().ToString();name=$name.Text.Trim()};$state.groups=@($state.groups)+@($group);$script:activeGroup=$group.id}
        Save-State;$dialog.Close();Paint-Tasks
    })
    $dialog.Controls.AddRange(@($name,$ok));$dialog.AcceptButton=$ok;[void]$dialog.ShowDialog($form);$dialog.Dispose()
}
function New-GroupHeader($entry) {
    $header=[TaskGroupHeader]::new();$header.GroupId=$entry.groupId;$header.Name='group-'+$entry.groupId;$header.Tag='group-header';$header.BackColor=Get-GroupColor $entry.groupId
    $arrow=if($state.groupCollapsed[$entry.groupId]){'▸'}else{'▾'}
    $header.Text=$arrow+' '+$entry.name+'    '+$entry.completed+'/'+$entry.total
    $header.Width=[Math]::Max(300,$panel.ClientSize.Width-28);$header.Font=[Drawing.Font]::new($form.Font,[Drawing.FontStyle]::Bold)
    $header.Add_GroupActivated({
        if($groupSlide.IsRunning){return}
        $groupSlide.Prepare()
        $id=$this.GroupId;$script:activeGroup=$id
        $expand=[bool]$state.groupCollapsed[$id]
        $state.groupCollapsed[$id]=-not $expand
        if($expand){Paint-Tasks}else{$this.Text=$this.Text -replace '^▾','▸'}
        $groupSlide.Start($id,$expand)
    })
    $header.Add_GroupRenameRequested({Edit-GroupName $this.GroupId})
    $menu=[Windows.Forms.ContextMenuStrip]::new()
    $add=$menu.Items.Add('新建分组');$add.Add_Click({Edit-GroupName})
    $rename=$menu.Items.Add('重命名分组');$rename.Tag=$entry.groupId;$rename.Add_Click({Edit-GroupName $this.Tag})
    $colors=$menu.Items.Add('分组颜色')
    foreach($option in @(@{key='green';name='浅绿'},@{key='pink';name='浅粉'},@{key='blue';name='浅蓝'},@{key='gray';name='浅灰'})){
        $choice=$colors.DropDownItems.Add($option.name);$choice.Tag=@{group=$entry.groupId;color=$option.key}
        $current=[string]$state.groupColors[$entry.groupId];if(-not $current){$current='green'};$choice.Checked=$current -eq $option.key
        $choice.Add_Click({$state.groupColors[$this.Tag.group]=$this.Tag.color;Save-State;Paint-Tasks})
        $choice.Image=[Drawing.Bitmap]::new(16,16);$graphics=[Drawing.Graphics]::FromImage($choice.Image)
        $color=switch($option.key){'pink'{'#F5D7DF'}'blue'{'#D5E6F5'}'gray'{'#DEDFDC'}default{'#D8EBCB'}}
        $graphics.Clear([Drawing.ColorTranslator]::FromHtml($color));$graphics.Dispose()
    }
    if($entry.groupId -ne 'ungrouped'){
        $remove=$menu.Items.Add('删除分组');$remove.Tag=$entry.groupId
        $remove.Add_Click({
            if((Get-GroupTaskCount $this.Tag) -gt 0){
                [void][Windows.Forms.MessageBox]::Show($form,'分组内还有任务，请先移动或删除组内任务，再删除分组。','无法删除分组',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
                return
            }
            $answer=[Windows.Forms.MessageBox]::Show($form,'确定删除此空分组吗？','删除分组',[Windows.Forms.MessageBoxButtons]::OKCancel)
            if($answer -eq [Windows.Forms.DialogResult]::OK -and (Remove-TaskGroup $this.Tag)){Save-State;Paint-Tasks}
        })
    }
    $header.ContextMenuStrip=$menu;$header.Add_Disposed({$this.ContextMenuStrip.Dispose()})
    return $header
}
function Get-GroupedItems($items) {
    foreach($group in @(Get-TaskGroups)){
        $children=@($items | Where-Object {(Get-TaskGroup $_.id) -eq $group.id})
        @{isGroupHeader=$true;groupId=$group.id;name=$group.name;total=$children.Count;completed=@($children | Where-Object {$state.done[$_.id]}).Count}
        if(-not $state.groupCollapsed[$group.id]){foreach($task in $children){$task}}
    }
}
