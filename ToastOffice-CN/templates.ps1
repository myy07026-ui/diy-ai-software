function Get-SelectedTemplate {
    $state.templates | Where-Object {$_.id -eq $state.selectedTemplate} | Select-Object -First 1
}
function Get-TemplateTask($task) {
    $copy=Copy-TaskRecord $task
    if($state.edits.ContainsKey($task.id)){
        $edit=$state.edits[$task.id]
        foreach($key in @('text','note','time','reminderMode','reminderAt','weekdays')){$copy[$key]=$edit.$key}
    }
    if($copy.reminderMode -eq 'weekly'){$copy.weekdays=@(0,1,2,3,4,5,6)}
    return $copy
}
function Edit-TemplateTask($template,$record=$null,$newSection='上午') {
    $task=if($record){Get-TemplateTask $record}else{@{text='';note='';section=$newSection;time='09:00';reminderMode='weekly';weekdays=@(0,1,2,3,4,5,6);appearDays=@(0,1,2,3,4,5,6);reviewMinutes=0}}
    $edit=[Windows.Forms.Form]::new();$edit.Text='表单任务设置';$edit.Size=[Drawing.Size]::new(510,505);$edit.Font=$form.Font;$edit.StartPosition='CenterParent';$edit.BackColor=$form.BackColor;$edit.ForeColor=$form.ForeColor;$edit.TopMost=$form.TopMost
    $name=[Windows.Forms.TextBox]::new();$name.Text=$task.text;$name.SetBounds(110,15,360,28)
    $note=[Windows.Forms.TextBox]::new();$note.Text=$task.note;$note.SetBounds(110,55,360,50);$note.Multiline=$true
    $section=[Windows.Forms.ComboBox]::new();$section.DropDownStyle='DropDownList';[void]$section.Items.AddRange(@('上午','下午'));$section.SelectedItem=$task.section;$section.SetBounds(110,118,150,28)
    $enabled=[Windows.Forms.CheckBox]::new();$enabled.Text='启用定时提醒';$enabled.Checked=$task.reminderMode -ne 'off';$enabled.SetBounds(18,245,180,26)
    $time=[Windows.Forms.DateTimePicker]::new();$time.Format='Custom';$time.CustomFormat='HH:mm';$time.ShowUpDown=$true;$time.SetBounds(210,245,120,28);if($task.time){$time.Value=[datetime]::Today.Add([timespan]::Parse($task.time))}
    $days=[Windows.Forms.FlowLayoutPanel]::new();$days.SetBounds(105,162,370,34);$days.WrapContents=$false
    $checks=@();foreach($d in @(1,2,3,4,5,6,0)){$c=[Windows.Forms.CheckBox]::new();$c.Text=@('日','一','二','三','四','五','六')[$d];$c.Tag=$d;$c.Width=48;$c.Checked=$true;$c.Enabled=$false;$checks+=,$c;$days.Controls.Add($c)}
    $hint=[Windows.Forms.Label]::new();$hint.Text='按照实际使用的表单提醒，不再区分星期。';$hint.SetBounds(18,206,455,34)
    $review=[Windows.Forms.CheckBox]::new();$review.Text='完成后再次提醒';$review.SetBounds(18,300,180,26);$review.Checked=[int]$task.reviewMinutes -gt 0
    if($record -and $state.reviewRules.ContainsKey($record.id)){$review.Checked=[int]$state.reviewRules[$record.id] -gt 0}
    $minutes=[Windows.Forms.NumericUpDown]::new();$minutes.Minimum=1;$minutes.Maximum=10080;$minutes.Value=if([int]$task.reviewMinutes -gt 0){[int]$task.reviewMinutes}else{5};if($record -and $state.reviewRules[$record.id]){$minutes.Value=[int]$state.reviewRules[$record.id]};$minutes.SetBounds(210,300,100,28)
    $minuteLabel=[Windows.Forms.Label]::new();$minuteLabel.Text='分钟后';$minuteLabel.SetBounds(320,302,90,25)
    $save=[Windows.Forms.Button]::new();$save.Text='保存';$save.SetBounds(365,385,100,34)
    foreach($entry in @(@('任务名称',18,18),@('说明',18,58),@('所属时段',18,121),@('使用日提醒',18,165))){$l=[Windows.Forms.Label]::new();$l.Text=$entry[0];$l.SetBounds($entry[1],$entry[2],90,26);$edit.Controls.Add($l)}
    $save.Add_Click({
        if([string]::IsNullOrWhiteSpace($name.Text)){return}
        $chosen=@($checks|Where-Object {$_.Checked}|ForEach-Object {[int]$_.Tag})
        if($chosen.Count -eq 0){[void][Windows.Forms.MessageBox]::Show($edit,'请至少选择一个提醒星期。');return}
        $new=@{id=$(if($record){$record.id}else{'template-'+[guid]::NewGuid().ToString('N')});text=$name.Text.Trim();note=$note.Text.Trim();section=[string]$section.SelectedItem;appearDays=$chosen;weekdays=$chosen;reminderMode=$(if($enabled.Checked){'weekly'}else{'off'});time=$(if($enabled.Checked){$time.Value.ToString('HH:mm')}else{''});reminderAt='';reviewMinutes=$(if($review.Checked){[int]$minutes.Value}else{0})}
        if($record){$template.tasks=@($template.tasks|ForEach-Object {if($_.id -eq $record.id){$new}else{$_}})}else{$template.tasks=@($template.tasks)+@($new)}
        $state.edits.Remove($new.id);$state.notified.Remove($new.id)
        if($new.reviewMinutes -gt 0){$state.reviewRules[$new.id]=$new.reviewMinutes}else{$state.reviewRules.Remove($new.id);$state.reviewPending.Remove($new.id)}
        Save-State;Paint-Tasks;$edit.DialogResult='OK';$edit.Close()
    })
    $edit.Controls.AddRange(@($name,$note,$section,$days,$hint,$enabled,$time,$review,$minutes,$minuteLabel,$save));$edit.AcceptButton=$save;[void]$edit.ShowDialog($form);$edit.Dispose()
}
function Show-TemplateEditor($id) {
    $template=$state.templates|Where-Object {$_.id -eq $id}|Select-Object -First 1
    if(-not $template){return}
    $manager=[Windows.Forms.Form]::new();$manager.Text='表单设置';$manager.Size=[Drawing.Size]::new(760,560);$manager.Font=$form.Font;$manager.StartPosition='CenterParent';$manager.TopMost=$form.TopMost;$manager.BackColor=$form.BackColor;$manager.ForeColor=$form.ForeColor
    $title=[Windows.Forms.TextBox]::new();$title.Text=$template.name;$title.Dock='Top'
    $rename=[Windows.Forms.Button]::new();$rename.Text='保存表单名称';$rename.AutoSize=$true;$rename.Add_Click({if($title.Text.Trim()){$template.name=$title.Text.Trim();Save-State;$manager.Text='表单设置 · '+$template.name}})
    $tabs=[Windows.Forms.ComboBox]::new();$tabs.DropDownStyle='DropDownList';[void]$tabs.Items.AddRange(@('上午','下午'));$tabs.SelectedIndex=0;$tabs.Width=110
    $list=[Windows.Forms.ListView]::new();$list.Dock='Fill';$list.View='Details';$list.FullRowSelect=$true;$list.GridLines=$true;$list.MultiSelect=$false
    [void]$list.Columns.Add('任务',280);[void]$list.Columns.Add('提醒星期',155);[void]$list.Columns.Add('提醒',100);[void]$list.Columns.Add('完成后',95)
    $refresh={
        $list.Items.Clear();foreach($t in @($template.tasks|Where-Object {$_.section -eq $tabs.SelectedItem})){
            $effective=Get-TemplateTask $t;$item=[Windows.Forms.ListViewItem]::new([string]$effective.text);$item.Tag=$t.id
            [void]$item.SubItems.Add((@($effective.weekdays|ForEach-Object {@('日','一','二','三','四','五','六')[[int]$_]}) -join '、'))
            [void]$item.SubItems.Add($(if($effective.reminderMode -eq 'off'){'不提醒'}else{[string]$effective.time}))
            [void]$item.SubItems.Add($(if($state.reviewRules[$t.id]){[string]$state.reviewRules[$t.id]+'分钟'}else{'不提醒'}));[void]$list.Items.Add($item)
        }
    }
    $addTask=[Windows.Forms.Button]::new();$addTask.Text='增加任务';$addTask.Add_Click({Edit-TemplateTask $template $null ([string]$tabs.SelectedItem);& $refresh})
    $editTask=[Windows.Forms.Button]::new();$editTask.Text='编辑任务';$editAction={if($list.SelectedItems.Count){$record=$template.tasks|Where-Object {$_.id -eq $list.SelectedItems[0].Tag}|Select-Object -First 1;Edit-TemplateTask $template $record;& $refresh}}
    $editTask.Add_Click($editAction);$list.Add_DoubleClick($editAction)
    $remove=[Windows.Forms.Button]::new();$remove.Text='删除任务';$remove.Add_Click({if($list.SelectedItems.Count -and [Windows.Forms.MessageBox]::Show($manager,'确定从此模板删除选中的任务吗？','删除任务','OKCancel') -eq 'OK'){$removeId=$list.SelectedItems[0].Tag;$template.tasks=@($template.tasks|Where-Object {$_.id -ne $removeId});Save-State;& $refresh;Paint-Tasks}})
    $up=[Windows.Forms.Button]::new();$up.Text='上移';$up.Tag=-1;$down=[Windows.Forms.Button]::new();$down.Text='下移';$down.Tag=1
    $moveAction={if($list.SelectedItems.Count){$taskId=$list.SelectedItems[0].Tag;$items=@($template.tasks);$idx=0;while($idx -lt $items.Count -and $items[$idx].id -ne $taskId){$idx++};$target=$idx+[int]$this.Tag;while($target -ge 0 -and $target -lt $items.Count -and $items[$target].section -ne $tabs.SelectedItem){$target+=[int]$this.Tag};if($target -ge 0 -and $target -lt $items.Count){$tmp=$items[$idx];$items[$idx]=$items[$target];$items[$target]=$tmp;$template.tasks=$items;$state.orders.Remove([string]$tabs.SelectedItem);Save-State;& $refresh;Paint-Tasks}}}
    $up.Add_Click($moveAction);$down.Add_Click($moveAction)
    $actions=[Windows.Forms.FlowLayoutPanel]::new();$actions.Dock='Top';$actions.Height=42;$actions.Controls.AddRange(@($tabs,$addTask,$editTask,$remove,$up,$down,$rename))
    $tabs.Add_SelectedIndexChanged({& $refresh});$manager.Controls.Add($list);$manager.Controls.Add($actions);$manager.Controls.Add($title);& $refresh;[void]$manager.ShowDialog($form);$manager.Dispose()
}
function Select-TaskTemplate($id,[string]$useDate='') {
    $previous=if($state.selectedTemplate){$state.selectedTemplate}else{'legacy'}
    $state.templateOrders[$previous]=@{morning=@($state.orders['上午']);afternoon=@($state.orders['下午'])}
    $state.lastTemplateUseDate=if($useDate){$useDate}else{[datetime]::Now.ToString('yyyy-MM-dd')}
    $state.selectedTemplate=[string]$id;$order=$state.templateOrders[$id]
    $state.orders['上午']=@($order.morning|Where-Object {$_});$state.orders['下午']=@($order.afternoon|Where-Object {$_})
    Save-State;Paint-Tasks
}
function Show-TemplateChooser {
    if($script:templateChooser){$script:templateChooser.Dispose()}
    $script:templateChooser=[Windows.Forms.ContextMenuStrip]::new();$script:templateChooser.Font=$form.Font
    foreach($template in $state.templates){$item=$script:templateChooser.Items.Add($template.name);$item.Tag=$template.id;$item.Checked=$state.selectedTemplate -eq $template.id;$item.Add_Click({Select-TaskTemplate $this.Tag})}
    $script:templateChooser.Show($templateName,[Drawing.Point]::new(0,$templateName.Height))
}
function Rename-SelectedTemplate {
    $template=Get-SelectedTemplate;if(-not $template){Show-TemplateChooser;return}
    $dialog=[Windows.Forms.Form]::new();$dialog.Text='修改表单名称';$dialog.Size=[Drawing.Size]::new(350,155);$dialog.StartPosition='CenterParent';$dialog.Font=$form.Font;$dialog.BackColor=$form.BackColor;$dialog.TopMost=$form.TopMost
    $field=[Windows.Forms.TextBox]::new();$field.Text=$template.name;$field.SetBounds(18,18,295,28)
    $ok=[Windows.Forms.Button]::new();$ok.Text='保存';$ok.SetBounds(223,58,90,30)
    $ok.Add_Click({if($field.Text.Trim()){$template.name=$field.Text.Trim();Save-State;Paint-Tasks;$dialog.Close()}})
    $dialog.Controls.AddRange(@($field,$ok));$dialog.AcceptButton=$ok;[void]$dialog.ShowDialog($form);$dialog.Dispose()
}
function Register-TemplateUse([datetime]$now=[datetime]::Now) {
    $today=$now.ToString('yyyy-MM-dd')
    if($state.lastTemplateUseDate -eq $today){return $false}
    $previous=$state.lastTemplateUseDate
    $state.lastTemplateUseDate=$today
    $pair=@($state.templates)
    if($previous -and $pair.Count -eq 2 -and $state.selectedTemplate -in @($pair.id)){
        $next=$pair|Where-Object {$_.id -ne $state.selectedTemplate}|Select-Object -First 1
        Select-TaskTemplate $next.id $today
        return $true
    }
    Save-State
    return $false
}
