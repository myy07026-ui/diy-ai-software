using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class CozyWindow : Form, IMessageFilter {
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ReleaseCapture();
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l);
    public CozyWindow(){AutoScaleMode=AutoScaleMode.None;DoubleBuffered=true;Padding=new Padding(5,5,5,7);Application.AddMessageFilter(this);}
    static GraphicsPath FramePath(RectangleF r,float radius){
        var p=new GraphicsPath();float d=radius*2;
        p.AddArc(r.Left,r.Top,d,d,180,90);p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.Left,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;
    }
    public void RefreshFrame(){
        if(ClientSize.Width<30 || ClientSize.Height<30)return;
        using(var path=FramePath(new RectangleF(0,0,ClientSize.Width,ClientSize.Height),15)){
            var old=Region;Region=new Region(path);if(old!=null)old.Dispose();
        }
        Invalidate();
    }
    public static void RestoreFrame(Form window){var cozy=window as CozyWindow;if(cozy!=null)cozy.RefreshFrame();else{var old=window.Region;window.Region=null;if(old!=null)old.Dispose();}}
    protected override void OnSizeChanged(EventArgs e){base.OnSizeChanged(e);RefreshFrame();}
    protected override void OnPaintBackground(PaintEventArgs e){
        base.OnPaintBackground(e);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        if(ClientSize.Width<30 || ClientSize.Height<30)return;
        using(var path=FramePath(new RectangleF(2,2,ClientSize.Width-4,ClientSize.Height-4),13))
        using(var border=new Pen(Color.FromArgb(194,194,194),4))e.Graphics.DrawPath(border,path);
        using(var shadow=new Pen(Color.FromArgb(164,164,164),2))e.Graphics.DrawLine(shadow,15,ClientSize.Height-2,ClientSize.Width-15,ClientSize.Height-2);
    }
    public static int EdgeAt(Size size,Point p){
        const int edge=7;
        if(p.X<0 || p.Y<0 || p.X>=size.Width || p.Y>=size.Height)return 0;
        bool left=p.X<edge,right=p.X>=size.Width-edge,top=p.Y<edge,bottom=p.Y>=size.Height-edge;
        if(top && left)return 13;if(top && right)return 14;if(bottom && left)return 16;if(bottom && right)return 17;
        if(left)return 10;if(right)return 11;if(top)return 12;if(bottom)return 15;return 0;
    }
    public bool PreFilterMessage(ref Message m){
        if(m.Msg!=0x200 && m.Msg!=0x201)return false;
        Control target=Control.FromChildHandle(m.HWnd);
        if(target==null || (target!=this && target.FindForm()!=this))return false;
        int edge=EdgeAt(ClientSize,PointToClient(Cursor.Position));
        if(edge!=0 && WindowState==FormWindowState.Normal){
            target.Cursor=(edge==10 || edge==11)?Cursors.SizeWE:(edge==12 || edge==15)?Cursors.SizeNS:(edge==13 || edge==17)?Cursors.SizeNWSE:Cursors.SizeNESW;
            if(m.Msg==0x201){ReleaseCapture();SendMessage(Handle,0xA1,new IntPtr(edge),IntPtr.Zero);return true;}
        }else if(target.Cursor==Cursors.SizeWE || target.Cursor==Cursors.SizeNS || target.Cursor==Cursors.SizeNWSE || target.Cursor==Cursors.SizeNESW)target.Cursor=Cursors.Default;
        return false;
    }
    protected override void WndProc(ref Message m){
        if(m.Msg==0x84 && WindowState==FormWindowState.Normal){
            long value=m.LParam.ToInt64();Point point=PointToClient(new Point((short)(value&0xffff),(short)((value>>16)&0xffff)));
            int edge=EdgeAt(ClientSize,point);if(edge!=0){m.Result=new IntPtr(edge);return;}
        }
        base.WndProc(ref m);
    }
    protected override void Dispose(bool disposing){if(disposing)Application.RemoveMessageFilter(this);base.Dispose(disposing);}
}

public class RecycleButton : Button {
    public RecycleButton(){Text="";Width=32;Height=28;FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;AccessibleName="垃圾箱";DoubleBuffered=true;}
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;
        var state=g.Save();g.TranslateTransform((Width-24)/2f,(Height-25)/2f);
        using(var ink=new SolidBrush(ForeColor)){
            g.FillRectangle(ink,8,1,9,3);g.FillRectangle(ink,3,5,19,3);
            g.FillPolygon(ink,new Point[]{new Point(5,10),new Point(20,10),new Point(18,24),new Point(7,24)});
        }
        using(var line=new Pen(BackColor,1.4f)){
            g.DrawLine(line,9,12,10,21);g.DrawLine(line,16,12,15,21);
        }
        using(var arrow=new Pen(BackColor,1.2f)){
            arrow.CustomEndCap=new AdjustableArrowCap(2,2);
            g.DrawLine(arrow,11,15,14,15);g.DrawLine(arrow,15,16,13,19);g.DrawLine(arrow,12,19,10,17);
        }
        g.Restore(state);
    }
}

public class StableTaskList : FlowLayoutPanel {
    public StableTaskList(){DoubleBuffered=true;SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint,true);}
    // Keep the user's scroll position when a checkbox retains keyboard focus.
    protected override Point ScrollToControl(Control activeControl) {
        return DisplayRectangle.Location;
    }
}

public class TaskCheckBox : CheckBox {
    public bool Dragging;
    protected override void OnMouseDown(MouseEventArgs e){Dragging=false;base.OnMouseDown(e);}
    protected override void OnClick(EventArgs e){if(!Dragging)base.OnClick(e);}
}

public class TaskSorter : IDisposable, IMessageFilter {
    readonly FlowLayoutPanel panel;readonly Timer timer;
    readonly System.Diagnostics.Stopwatch held=new System.Diagnostics.Stopwatch();
    Control candidate,pressed;Point origin;bool dragging,changed,settling;int marker=-1;
    DragPreview preview;readonly System.Diagnostics.Stopwatch settleClock=new System.Diagnostics.Stopwatch();
    sealed class DragPreview : Control {
        readonly FlowLayoutPanel list;readonly Control selected;
        readonly System.Collections.Generic.Dictionary<Control,Bitmap> images=new System.Collections.Generic.Dictionary<Control,Bitmap>();
        readonly System.Collections.Generic.Dictionary<Control,float> positions=new System.Collections.Generic.Dictionary<Control,float>();
        readonly System.Collections.Generic.HashSet<Control> movingRows=new System.Collections.Generic.HashSet<Control>();
        readonly int offset;float y,zoom=1;
        public DragPreview(FlowLayoutPanel panel,Control row,Point mouse){
            list=panel;selected=row;offset=mouse.Y-row.Top;y=row.Top;
            DoubleBuffered=true;BackColor=panel.BackColor;
            foreach(Control card in panel.Controls){var image=new Bitmap(card.Width,card.Height);card.DrawToBitmap(image,card.ClientRectangle);images[card]=image;positions[card]=card.Top;}
            movingRows.Add(selected);
            if(selected is TaskGroupHeader){
                bool inside=false;int bottom=selected.Bottom,width=selected.Width;
                foreach(Control card in panel.Controls){if(card==selected){inside=true;continue;}if(!inside)continue;if(card is TaskGroupHeader)break;movingRows.Add(card);bottom=Math.Max(bottom,card.Bottom);width=Math.Max(width,card.Width);}
                var combined=new Bitmap(width,Math.Max(1,bottom-selected.Top));
                using(var g=Graphics.FromImage(combined)){g.Clear(panel.BackColor);foreach(var card in movingRows)g.DrawImageUnscaled(images[card],card.Left-selected.Left,card.Top-selected.Top);}
                images[selected].Dispose();images[selected]=combined;
            }
        }
        public void Step(bool dropping){
            float target=dropping?selected.Top:list.PointToClient(Cursor.Position).Y-offset;
            y+=(target-y)*.28f;zoom+=((dropping?1f:1.035f)-zoom)*.24f;
            foreach(Control card in list.Controls)if(positions.ContainsKey(card))positions[card]+=(card.Top-positions[card])*.26f;
            Invalidate();
        }
        protected override void OnPaint(PaintEventArgs e){
            base.OnPaint(e);var g=e.Graphics;g.InterpolationMode=InterpolationMode.HighQualityBicubic;
            foreach(var pair in images)if(!movingRows.Contains(pair.Key))g.DrawImageUnscaled(pair.Value,pair.Key.Left,(int)Math.Round(positions[pair.Key]));
            Bitmap image=images[selected];float w=image.Width*zoom,h=image.Height*zoom,x=selected.Left-(w-image.Width)/2f,top=y-(h-image.Height)/2f;
            using(var shadow=new SolidBrush(Color.FromArgb(35,0,0,0)))g.FillRectangle(shadow,x+2,top+3,w,h);
            g.DrawImage(image,new RectangleF(x,top,w,h));
        }
        protected override void Dispose(bool disposing){if(disposing)foreach(var image in images.Values)image.Dispose();base.Dispose(disposing);}
    }
    public event EventHandler OrderChanged;
    public TaskSorter(FlowLayoutPanel list){
        panel=list;timer=new Timer();timer.Interval=16;timer.Tick+=(s,e)=>Track();
        Application.AddMessageFilter(this);panel.Disposed+=(s,e)=>Dispose();
        panel.Paint+=(s,e)=>{if(marker>=0)using(var pen=new Pen(Color.FromArgb(77,110,55),3))e.Graphics.DrawLine(pen,8,marker,panel.ClientSize.Width-22,marker);};
    }
    public bool PreFilterMessage(ref Message message){
        if(settling)return false;
        if(message.Msg==0x201){
            Control control=Control.FromChildHandle(message.HWnd);Control row=control;
            while(row!=null && !(row is CozyCard) && !(row is TaskGroupHeader))row=row.Parent;
            bool onCheck=control is TaskCheckBox && control.PointToClient(Cursor.Position).X<26;
            if(row!=null && row.Parent==panel && !onCheck && (!(control is Button) || control is TaskCheckBox || control is TaskGroupHeader)){
                candidate=row;pressed=control;origin=Cursor.Position;dragging=false;changed=false;held.Restart();timer.Start();
            }
        }
        if(message.Msg==0x202 && candidate!=null){bool suppress=dragging;Finish();return suppress;}
        return false;
    }
    void Track(){
        if(settling){preview.Step(true);if(settleClock.ElapsedMilliseconds>=190)Complete();return;}
        if(candidate==null || candidate.IsDisposed || Control.MouseButtons!=MouseButtons.Left){Finish();return;}
        if(!dragging){
            if(held.ElapsedMilliseconds<450)return;
            dragging=true;if(pressed is TaskCheckBox)((TaskCheckBox)pressed).Dragging=true;
            if(candidate is TaskGroupHeader)((TaskGroupHeader)candidate).BeginDrag();
            pressed.Capture=true;panel.Cursor=Cursors.SizeNS;
            preview=new DragPreview(panel,candidate,panel.PointToClient(origin));
            Control host=panel.Parent;preview.Bounds=new Rectangle(host.PointToClient(panel.PointToScreen(Point.Empty)),panel.ClientSize);
            host.Controls.Add(preview);preview.BringToFront();
        }
        preview.Step(false);
        Point point=panel.PointToClient(Cursor.Position);
        if(Math.Abs(Cursor.Position.Y-origin.Y)<5)return;
        int scroll=-panel.AutoScrollPosition.Y;
        if(point.Y<30)panel.AutoScrollPosition=new Point(0,Math.Max(0,scroll-12));
        else if(point.Y>panel.ClientSize.Height-30)panel.AutoScrollPosition=new Point(0,scroll+12);
        if(candidate is TaskGroupHeader){if(MoveGroup((TaskGroupHeader)candidate,point.Y))changed=true;}
        else{
            int index=DropIndex(candidate,point.Y);
            if(panel.Controls.GetChildIndex(candidate)!=index){panel.Controls.SetChildIndex(candidate,index);panel.PerformLayout();changed=true;}
        }
        marker=candidate.Top-2;panel.Invalidate();
    }
    void Finish(){
        if(dragging && preview!=null){if(pressed!=null && !pressed.IsDisposed)pressed.Capture=false;settling=true;settleClock.Restart();return;}
        Complete();
    }
    void Complete(){
        timer.Stop();if(dragging && pressed!=null && !pressed.IsDisposed)pressed.Capture=false;
        if(preview!=null){preview.Dispose();preview=null;}settling=false;
        candidate=null;pressed=null;dragging=false;marker=-1;panel.Cursor=Cursors.Default;panel.Invalidate();
        if(changed){changed=false;if(OrderChanged!=null)OrderChanged(this,EventArgs.Empty);}
    }
    public int DropIndex(Control source,int y){
    int index=0;bool grouped=false;
    foreach(Control row in panel.Controls){
        if(row==source)continue;
        if(row is TaskGroupHeader){grouped=true;if(y>=row.Top && y<=row.Bottom)return index+1;}
        if(y<row.Top+row.Height/2)return grouped?Math.Max(1,index):index;index++;
    }
    return index;
}
    public bool MoveGroup(TaskGroupHeader source,int y){
        var groups=new System.Collections.Generic.List<System.Collections.Generic.List<Control>>();
        System.Collections.Generic.List<Control> current=null,moving=null;
        foreach(Control control in panel.Controls){
            if(control is TaskGroupHeader){current=new System.Collections.Generic.List<Control>();groups.Add(current);if(control==source)moving=current;}
            if(current!=null)current.Add(control);
        }
        if(moving==null)return false;int old=groups.IndexOf(moving);groups.Remove(moving);
        int target=0;while(target<groups.Count && y>=groups[target][0].Top+groups[target][0].Height/2)target++;
        groups.Insert(target,moving);if(target==old)return false;
        panel.SuspendLayout();int index=0;foreach(var group in groups)foreach(var control in group)panel.Controls.SetChildIndex(control,index++);panel.ResumeLayout();return true;
    }
    public void Attach(Control row){}
    public void Dispose(){Application.RemoveMessageFilter(this);timer.Stop();timer.Dispose();if(preview!=null){preview.Dispose();preview=null;}}
}
public class GroupSlide : IDisposable {
    sealed class SlideSurface : Control {
        sealed class Frame {public Bitmap Image;public Rectangle Bounds;public bool InGroup;public TaskGroupHeader Header;}
        readonly System.Collections.Generic.List<Frame> frames=new System.Collections.Generic.List<Frame>();
        int begin,end,total,visible;
        public int Total {get{return total;}}
        public int VisibleHeight {get{return visible;}}
        public SlideSurface(){DoubleBuffered=true;SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer,true);}
        public void CaptureFrames(FlowLayoutPanel panel,string group){
            ClearFrames();BackColor=panel.BackColor;begin=int.MaxValue;end=0;
            foreach(Control control in panel.Controls){
                if(!control.Visible || control.Width<=0 || control.Height<=0)continue;
                bool inside=control is CozyCard && ((CozyCard)control).GroupId==group;
                if(inside){begin=Math.Min(begin,control.Top-control.Margin.Top);end=Math.Max(end,control.Bottom+control.Margin.Bottom);}
                var bitmap=new Bitmap(control.Width,control.Height);control.DrawToBitmap(bitmap,control.ClientRectangle);
                frames.Add(new Frame{Image=bitmap,Bounds=control.Bounds,InGroup=inside,Header=control as TaskGroupHeader});
            }
            total=begin==int.MaxValue?0:Math.Max(0,end-begin);visible=total;
        }
        public void Reveal(int height){visible=Math.Max(0,Math.Min(total,height));Invalidate();}
        protected override void OnPaint(PaintEventArgs e){
            base.OnPaint(e);var g=e.Graphics;
            foreach(var frame in frames){
                Rectangle bounds=frame.Bounds;
                if(frame.InGroup){
                    var state=g.Save();g.SetClip(new Rectangle(0,begin,Width,visible),System.Drawing.Drawing2D.CombineMode.Intersect);
                    g.DrawImageUnscaled(frame.Image,bounds.Location);g.Restore(state);
                }else{
                    if(total>0 && bounds.Top>=end)bounds.Y-=total-visible;
                    if(bounds.IntersectsWith(ClientRectangle))g.DrawImageUnscaled(frame.Image,bounds.Location);
                }
            }
        }
        public bool RouteHeaderClick(Point point){
            foreach(var frame in frames){
                if(frame.Header==null || frame.Header.IsDisposed)continue;
                Rectangle bounds=frame.Bounds;if(total>0 && bounds.Top>=end)bounds.Y-=total-visible;
                if(bounds.Contains(point)){frame.Header.TriggerUserClick();return true;}
            }
            return false;
        }
        protected override void OnMouseUp(MouseEventArgs e){if(e.Button==MouseButtons.Left)RouteHeaderClick(e.Location);base.OnMouseUp(e);}
        void ClearFrames(){foreach(var frame in frames)frame.Image.Dispose();frames.Clear();}
        protected override void Dispose(bool disposing){if(disposing)ClearFrames();base.Dispose(disposing);}
    }
    readonly FlowLayoutPanel panel;readonly Timer timer=new Timer();
    readonly System.Diagnostics.Stopwatch clock=new System.Diagnostics.Stopwatch();SlideSurface surface;bool expanding;
    public bool IsRunning {get;private set;}
    public int VisibleHeight {get{return surface==null?0:surface.VisibleHeight;}}
    public int TotalHeight {get{return surface==null?0:surface.Total;}}
    public event EventHandler Completed;
    public GroupSlide(FlowLayoutPanel list){panel=list;timer.Interval=15;timer.Tick+=(s,e)=>{
        if(surface==null){Cancel();return;}
        double t=Math.Min(1,clock.Elapsed.TotalMilliseconds/260.0),ease=t*t*(3-2*t);
        surface.Reveal((int)Math.Round(surface.Total*(expanding?ease:1-ease)));
        if(t>=1)Finish();
    };panel.Disposed+=(s,e)=>Dispose();}
    public void Prepare(){
        Cancel();surface=new SlideSurface();surface.CaptureFrames(panel,null);
        Control host=panel.Parent;if(host==null){surface.Dispose();surface=null;return;}
        surface.Bounds=new Rectangle(host.PointToClient(panel.PointToScreen(Point.Empty)),panel.ClientSize);
        host.Controls.Add(surface);surface.BringToFront();
    }
    public void Start(string groupId,bool expand){
        if(surface==null)Prepare();if(surface==null)return;
        expanding=expand;surface.CaptureFrames(panel,groupId);IsRunning=true;
        surface.Reveal(expand?0:surface.Total);
        if(surface.Total==0){Finish();return;}
        clock.Restart();timer.Start();
    }
    void Finish(){
        timer.Stop();IsRunning=false;
        try{if(Completed!=null)Completed(this,EventArgs.Empty);}
        finally{if(surface!=null){surface.Dispose();surface=null;}}
    }
    public void Cancel(){timer.Stop();IsRunning=false;if(surface!=null){surface.Dispose();surface=null;}}
    public void Dispose(){Cancel();timer.Dispose();}
}
public class TaskGroupHeader : Button {
    public string GroupId;bool dragged;
    static string lastGroup;static long lastClick;
    public event EventHandler GroupActivated,GroupRenameRequested;
    public TaskGroupHeader(){
        Height=36;FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;TextAlign=ContentAlignment.MiddleLeft;BackColor=Color.FromArgb(216,235,203);Margin=new Padding(8,8,4,3);
        SetStyle(ControlStyles.StandardClick|ControlStyles.StandardDoubleClick,true);
    }
    public void ActivateGroup(){if(GroupActivated!=null)GroupActivated(this,EventArgs.Empty);}
    public void BeginDrag(){dragged=true;lastClick=0;}
    public void TriggerUserClick(){OnClick(EventArgs.Empty);}
    protected override void OnMouseDown(MouseEventArgs e){dragged=false;base.OnMouseDown(e);}
    protected override void OnClick(EventArgs e){
        if(dragged)return;
        long now=System.Diagnostics.Stopwatch.GetTimestamp();
        bool doubleClick=lastClick!=0 && lastGroup==GroupId && (now-lastClick)*1000.0/System.Diagnostics.Stopwatch.Frequency<=SystemInformation.DoubleClickTime;
        lastGroup=GroupId;lastClick=doubleClick?0:now;
        if(doubleClick){if(GroupRenameRequested!=null)GroupRenameRequested(this,EventArgs.Empty);}else ActivateGroup();
    }
    protected override void OnDoubleClick(EventArgs e){lastClick=0;if(!dragged && GroupRenameRequested!=null)GroupRenameRequested(this,EventArgs.Empty);}
}
public class CozyCard : Panel {
    public string GroupId;
    public CozyCard() { DoubleBuffered=true; BackColor=Color.FromArgb(255,247,222); Padding=new Padding(3); }
    public void FitWidth(int width){
        Width=Math.Max(250,width);
        foreach(Control child in Controls){
            if(child is CheckBox){if(!String.IsNullOrEmpty(child.Text))child.Width=Width-102;}
            if(child is Label && (child.Tag as string)=="task-title")child.Width=Width-124;
            if(child is Label && (child.Tag as string)=="task-note")child.Width=Width-104;
            if(child is Button)child.Left=Width-74;
        }
        FitTaskText();
    }
    public void FitTaskText(){
        CheckBox check=null;Label title=null,note=null;
        foreach(Control child in Controls){
            if(child is CheckBox)check=(CheckBox)child;
            if(child is Label && (child.Tag as string)=="task-title")title=(Label)child;
            if(child is Label && (child.Tag as string)=="task-note")note=(Label)child;
        }
        Control heading=(Control)title??check;
        if(heading==null || note==null)return;
        int textWidth=Math.Max(30,heading.Width-(title==null?24:2));
        int textHeight=TextRenderer.MeasureText(heading.Text,heading.Font,new Size(textWidth,int.MaxValue),TextFormatFlags.WordBreak|TextFormatFlags.TextBoxControl|TextFormatFlags.NoPadding).Height;
        heading.Height=Math.Max(36,textHeight+8);
        note.Top=heading.Bottom+5;
        int noteHeight=TextRenderer.MeasureText(note.Text,note.Font,new Size(Math.Max(30,note.Width-2),int.MaxValue),TextFormatFlags.WordBreak|TextFormatFlags.TextBoxControl|TextFormatFlags.NoPadding).Height;
        note.Height=Math.Max(22,noteHeight+6);
        Height=Math.Max(80,note.Bottom+9);
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e); var g=e.Graphics; g.SmoothingMode=SmoothingMode.AntiAlias;
        using(var path=new GraphicsPath()) {
            int w=Width-5,h=Height-5,r=16;
            path.AddArc(2,2,r,r,180,90); path.AddArc(w-r,2,r,r,270,90);
            path.AddArc(w-r,h-r,r,r,0,90); path.AddArc(2,h-r,r,r,90,90); path.CloseFigure();
            using(var brush=new SolidBrush(FillColor))g.FillPath(brush,path);
            using(var pen=new Pen(ForeColor,1.5f))g.DrawPath(pen,path);
        }
    }
    public Color FillColor=Color.White;
}

// One opaque window avoids color-key fringes and background synchronization lag.
public class CozyDesktop : IDisposable {
    readonly Form main,tab; readonly Timer timer,animation;
    readonly System.Diagnostics.Stopwatch motion=new System.Diagnostics.Stopwatch();
    Point start,end,anchor; Rectangle animationArea; bool animating=false,closing=false,collapsed=false;
    string side=""; bool moving=false; DateTime outside=DateTime.Now;
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ReleaseCapture();
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l);
    public static string Edge(Rectangle window,Rectangle area){
        if(window.Top<=area.Top+22)return "top";
        if(window.Right>=area.Right-22)return "right";
        return "";
    }
    public CozyDesktop(Form form){
        main=form; main.FormBorderStyle=FormBorderStyle.None;CozyWindow.RestoreFrame(main);
        main.Opacity=1;
        main.TransparencyKey=Color.Empty;main.BackColor=Color.FromArgb(255,247,222);
        tab=new DockHintWindow();tab.StartPosition=FormStartPosition.Manual;tab.AutoScaleMode=AutoScaleMode.None;tab.FormBorderStyle=FormBorderStyle.None;tab.ShowInTaskbar=false;tab.TopMost=true;tab.BackColor=Color.FromArgb(255,210,136);
        IntPtr tabHandle=tab.Handle;
        var label=new Label();label.Dock=DockStyle.Fill;label.TextAlign=ContentAlignment.MiddleCenter;label.Font=new Font("Microsoft YaHei UI",10,FontStyle.Bold);label.Text="今日任务";tab.Controls.Add(label);
        label.MouseEnter+=(s,e)=>Expand();tab.MouseEnter+=(s,e)=>Expand();
        main.MouseDown+=(s,e)=>Drag();
        foreach(Control c in main.Controls){
            if(c is CozyBanner)c.MouseDown+=(s,e)=>{if(e.Button==MouseButtons.Left && !((CozyBanner)c).TitleHitArea.Contains(e.Location))Drag();};
            else if(c is Label && c.Dock==DockStyle.Top)c.MouseDown+=(s,e)=>{if(e.Button==MouseButtons.Left)Drag();};
        }
        main.ResizeBegin+=(s,e)=>{moving=true;};
        main.ResizeEnd+=(s,e)=>{moving=false;side=Edge(main.Bounds,Screen.FromControl(main).WorkingArea);Snap();outside=DateTime.Now;};
        main.Shown+=(s,e)=>{main.Invalidate(true);};
        main.FormClosed+=(s,e)=>Dispose();
        timer=new Timer();timer.Interval=120;timer.Tick+=(s,e)=>{
            if(main.IsDisposed)return;

            if(!main.Visible || animating || collapsed || tab.Visible || moving || side=="" || main.WindowState!=FormWindowState.Normal)return;
            if(main.Bounds.Contains(Cursor.Position) || main.OwnedForms.Length>0 || !main.Enabled)outside=DateTime.Now;
            else if((DateTime.Now-outside).TotalMilliseconds>1100)Collapse();
        };timer.Start();
        animation=new Timer();animation.Interval=15;animation.Tick+=(s,e)=>{
            double progress=Math.Min(1,motion.Elapsed.TotalMilliseconds/300.0);
            double eased=1-Math.Pow(1-progress,3);
            main.Location=new Point((int)Math.Round(start.X+(end.X-start.X)*eased),(int)Math.Round(start.Y+(end.Y-start.Y)*eased));
            Rectangle visible=Rectangle.Intersect(main.Bounds,animationArea);visible.Offset(-main.Left,-main.Top);
            Region previous=main.Region;main.Region=new Region(visible);if(previous!=null)previous.Dispose();
            if(progress>=1){
                animation.Stop();animating=false;
                if(closing){main.Hide();collapsed=true;tab.Show();}
                CozyWindow.RestoreFrame(main);
                outside=DateTime.Now;
            }
        };
    }
    void Drag(){Expand();if(animating){animation.Stop();animating=false;main.Location=anchor;CozyWindow.RestoreFrame(main);}ReleaseCapture();SendMessage(main.Handle,0xA1,new IntPtr(2),IntPtr.Zero);}
    void Snap(){var a=Screen.FromControl(main).WorkingArea;
        if(side=="top")main.Location=new Point(Math.Max(a.Left,Math.Min(main.Left,a.Right-main.Width)),a.Top);
        if(side=="right")main.Location=new Point(a.Right-main.Width,Math.Max(a.Top,Math.Min(main.Top,a.Bottom-main.Height)));
    }
    void Collapse(){
        if(animating || collapsed || side=="")return;
        foreach(Control c in main.Controls)if(c is CozyBanner)((CozyBanner)c).CommitTitle();
        Snap();anchor=main.Location;
        var a=Screen.FromControl(main).WorkingArea;
        if(side=="top"){tab.Size=new Size(110,25);tab.Location=new Point(main.Left,a.Top);tab.Controls[0].Text="▼ 今日任务";}
        else{tab.Size=new Size(28,110);tab.Location=new Point(a.Right-28,main.Top);tab.Controls[0].Text="今\n日\n任\n务";}
        Point hidden=side=="top"?new Point(main.Left,a.Top-main.Height):new Point(a.Right,main.Top);
        Animate(hidden,true,a);
    }
    void Animate(Point target,bool hide,Rectangle area){start=main.Location;end=target;closing=hide;animationArea=area;animating=true;motion.Restart();animation.Start();}
    public void Expand(){
        if(animating && !closing)return;
        bool slide=collapsed || (animating && closing);
        main.ShowInTaskbar=true;tab.Hide();collapsed=false;
        if(slide){if(!main.Visible)main.Show();Animate(anchor,false,animationArea);}
        else{if(!main.Visible)main.Show();Snap();}
        main.BringToFront();outside=DateTime.Now;
    }
    public void HideToTray(){
        animation.Stop();animating=false;tab.Hide();
        if(collapsed || closing){main.Location=anchor;}
        collapsed=false;closing=false;
        CozyWindow.RestoreFrame(main);
        main.ShowInTaskbar=false;main.Hide();
    }
    public void Dispose(){timer.Stop();timer.Dispose();animation.Stop();animation.Dispose();tab.Dispose();}
}
public class ToastTray : IDisposable {
    readonly Form main;readonly CozyDesktop desktop;readonly NotifyIcon icon;
    readonly ContextMenuStrip menu;readonly Icon artwork;
    readonly Timer updateTimer;readonly System.Threading.EventWaitHandle updateExit;
    bool exiting,disposed;
    public ToastTray(Form form,CozyDesktop behavior,string iconPath,bool enableUpdates=true){
        main=form;desktop=behavior;artwork=new Icon(iconPath);
        menu=new ContextMenuStrip();
        menu.Items.Add("打开吐司办公",null,(s,e)=>Restore());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("关闭",null,(s,e)=>Exit());
        icon=new NotifyIcon();icon.Icon=artwork;icon.Text="吐司办公";icon.ContextMenuStrip=menu;icon.Visible=true;
        icon.MouseClick+=(s,e)=>{if(e.Button==MouseButtons.Left)Restore();};
        main.FormClosing+=(s,e)=>{if(!exiting && e.CloseReason==CloseReason.UserClosing){e.Cancel=true;desktop.HideToTray();}};
        main.FormClosed+=(s,e)=>Dispose();
        if(enableUpdates){
            updateExit=new System.Threading.EventWaitHandle(false,System.Threading.EventResetMode.AutoReset,"Local\\ToastOfficeShareCN.ExitForUpdate");
            updateTimer=new Timer();updateTimer.Interval=250;updateTimer.Tick+=(s,e)=>{if(updateExit.WaitOne(0))Exit();};updateTimer.Start();
        }
    }
    public void Restore(){main.WindowState=FormWindowState.Normal;desktop.Expand();main.Activate();}
    public void Exit(){exiting=true;main.Close();}
    public void Dispose(){if(disposed)return;disposed=true;if(updateTimer!=null){updateTimer.Stop();updateTimer.Dispose();updateExit.Dispose();}icon.Visible=false;icon.Dispose();menu.Dispose();artwork.Dispose();}
}
public class CozyBanner : Control, IMessageFilter {
    public string Caption="今日工作小食光"; public string ThemeName="cream"; public string Slogan="";
    public event EventHandler TitleCommitted;
    readonly TextBox titleEditor=new TextBox();
    public Rectangle TitleArea {get{return new Rectangle(18,17,Math.Max(60,Width-112),36);}}
    public Rectangle TitleHitArea {get{
        int textWidth=TextRenderer.MeasureText(Caption,titleEditor.Font,Size.Empty,TextFormatFlags.NoPadding|TextFormatFlags.SingleLine).Width;
        return new Rectangle(TitleArea.Location,new Size(Math.Min(TitleArea.Width,textWidth+6),TitleArea.Height));
    }}
    public CozyBanner(){
        DoubleBuffered=true; Height=140; Dock=DockStyle.Top;
        titleEditor.Visible=false;titleEditor.BorderStyle=BorderStyle.None;
        titleEditor.Font=new Font("Microsoft YaHei UI",18,FontStyle.Bold);
        titleEditor.BackColor=Color.FromArgb(255,247,222);titleEditor.ForeColor=Color.Black;
        Controls.Add(titleEditor);
        titleEditor.KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Enter){e.SuppressKeyPress=true;CommitTitle();}};
        titleEditor.Leave+=(s,e)=>CommitTitle();
        Application.AddMessageFilter(this);
    }
    public void BeginTitleEdit(){titleEditor.BackColor=BackColor;titleEditor.ForeColor=ForeColor;titleEditor.Bounds=TitleArea;titleEditor.Text=Caption;titleEditor.Visible=true;titleEditor.Focus();titleEditor.SelectAll();}
    public void CommitTitle(){
        if(!titleEditor.Visible)return;
        string value=titleEditor.Text.Trim();titleEditor.Visible=false;
        if(value.Length>0 && value!=Caption){Caption=value;Invalidate();if(TitleCommitted!=null)TitleCommitted(this,EventArgs.Empty);}
    }
    public bool PreFilterMessage(ref Message message){
        if(titleEditor.Visible && (message.Msg==0x201 || message.Msg==0x204 || message.Msg==0xA1) && !titleEditor.RectangleToScreen(titleEditor.ClientRectangle).Contains(Cursor.Position))CommitTitle();
        return false;
    }
    protected override void OnMouseDown(MouseEventArgs e){if(e.Button==MouseButtons.Left && TitleHitArea.Contains(e.Location))BeginTitleEdit();else CommitTitle();base.OnMouseDown(e);}
    protected override void Dispose(bool disposing){if(disposing)Application.RemoveMessageFilter(this);base.Dispose(disposing);}
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e); var g=e.Graphics; g.SmoothingMode=SmoothingMode.AntiAlias;
        using(var title=new Font("Microsoft YaHei UI",18,FontStyle.Bold))
        using(var sub=new Font("Microsoft YaHei UI",9))
        using(var ink=new SolidBrush(ForeColor)){
            using(var format=new StringFormat()){format.Trimming=StringTrimming.EllipsisCharacter;format.FormatFlags=StringFormatFlags.NoWrap;g.DrawString(Caption,title,ink,TitleArea,format);}
            g.DrawString("一件一件来，做完就打个勾。",sub,ink,20,57);
            using(var format=new StringFormat()){
                format.Trimming=StringTrimming.EllipsisCharacter;
                using(var sloganFont=new Font("Microsoft YaHei UI",10.5f,FontStyle.Bold))
                    g.DrawString(Slogan,sloganFont,ink,new RectangleF(14,98,Math.Max(80,Width-168),38),format);
            }
        }
        float x=Width-119,y=70;

        if(ThemeName=="pink"){DrawCat(g,x,y);return;}
        if(ThemeName=="dark"){
            using(var pen=new Pen(Color.FromArgb(151,177,198),3)){
                g.DrawPolygon(pen,new PointF[]{new PointF(x+30,y+2),new PointF(x+57,y+17),new PointF(x+57,y+48),new PointF(x+30,y+64),new PointF(x+3,y+48),new PointF(x+3,y+17)});
                g.DrawLines(pen,new PointF[]{new PointF(x+16,y+34),new PointF(x+26,y+44),new PointF(x+44,y+23)});
            }
            return;
        }
        using(var outline=new Pen(Color.FromArgb(43,35,31),2.2f))
        using(var bread=new SolidBrush(Color.FromArgb(255,199,93)))
        using(var inside=new SolidBrush(Color.FromArgb(255,224,133)))
        using(var blush=new SolidBrush(Color.FromArgb(255,133,140))){
            g.FillRectangle(bread,x+3,y+16,54,47); g.FillEllipse(bread,x,y,60,39);
            g.DrawArc(outline,x,y,60,39,180,180);g.DrawLine(outline,x,y+19,x+3,y+63);
            g.DrawLine(outline,x+3,y+63,x+57,y+63);g.DrawLine(outline,x+57,y+63,x+60,y+19);
            g.FillRectangle(inside,x+9,y+24,42,32);
            g.FillEllipse(Brushes.Black,x+18,y+28,4,5);g.FillEllipse(Brushes.Black,x+39,y+28,4,5);
            g.DrawArc(outline,x+25,y+30,10,8,0,180);
            g.FillEllipse(blush,x+12,y+36,10,5);g.FillEllipse(blush,x+39,y+36,10,5);
            using(var shine=new Pen(Color.FromArgb(255,243,184),5))g.DrawLine(shine,x+19,y+48,x+27,y+40);
        }
    }
    void DrawCat(Graphics g,float x,float y){
        using(var outline=new Pen(Color.FromArgb(88,66,61),2))
        using(var fur=new SolidBrush(Color.FromArgb(255,249,233)))
        using(var patch=new SolidBrush(Color.FromArgb(224,167,104)))
        using(var blush=new SolidBrush(Color.FromArgb(241,163,177))){
            g.FillEllipse(blush,x-5,y-5,73,76);
            g.FillEllipse(fur,x+9,y+28,44,37);g.DrawEllipse(outline,x+9,y+28,44,37);
            var ears=new PointF[]{new PointF(x+9,y+23),new PointF(x+10,y+1),new PointF(x+27,y+14),new PointF(x+40,y+13),new PointF(x+55,y+1),new PointF(x+55,y+30)};
            g.FillPolygon(fur,ears);g.DrawPolygon(outline,ears);g.FillEllipse(fur,x+7,y+12,50,35);g.DrawArc(outline,x+7,y+12,50,35,0,180);
            g.FillEllipse(patch,x+11,y+14,16,16);g.FillEllipse(Brushes.DimGray,x+41,y+15,12,12);
            g.FillEllipse(Brushes.Black,x+20,y+27,4,5);g.FillEllipse(Brushes.Black,x+41,y+27,4,5);
            g.DrawArc(outline,x+27,y+31,6,5,0,180);g.DrawArc(outline,x+33,y+31,6,5,0,180);
            g.FillEllipse(blush,x+12,y+33,9,5);g.FillEllipse(blush,x+45,y+33,9,5);
            g.DrawLine(outline,x+22,y+54,x+22,y+63);g.DrawLine(outline,x+40,y+54,x+40,y+63);
            g.DrawLine(outline,x+6,y+29,x,y+27);g.DrawLine(outline,x+56,y+29,x+63,y+27);
        }
    }}

public class SettingsButton : Button {
    public SettingsButton(){Width=32;Height=28;Text="";AccessibleName="设置";FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;DoubleBuffered=true;}
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;
        float cx=Width/2f,cy=Height/2f;
        using(var pen=new Pen(ForeColor,2.2f)){
            pen.StartCap=pen.EndCap=LineCap.Round;
            g.DrawEllipse(pen,cx-6,cy-6,12,12);g.DrawEllipse(pen,cx-2,cy-2,4,4);
            for(int i=0;i<8;i++){double a=i*Math.PI/4;g.DrawLine(pen,cx+(float)Math.Cos(a)*7,cy+(float)Math.Sin(a)*7,cx+(float)Math.Cos(a)*9,cy+(float)Math.Sin(a)*9);}
        }
    }
}
public class PinToggle : CheckBox {
    public PinToggle(){AutoSize=false;Text="";Size=new Size(36,32);AccessibleName="置顶";DoubleBuffered=true;Cursor=Cursors.Hand;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
    protected override void OnCheckedChanged(EventArgs e){base.OnCheckedChanged(e);Invalidate();}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.Clear(BackColor);g.SmoothingMode=SmoothingMode.AntiAlias;
        float x=(Width-16)/2f,y=(Height-22)/2f;
        PointF[] shape={new PointF(x+3,y+2),new PointF(x+13,y+2),new PointF(x+11,y+5),new PointF(x+11,y+10),new PointF(x+15,y+14),new PointF(x+1,y+14),new PointF(x+5,y+10),new PointF(x+5,y+5)};
        using(var pen=new Pen(ForeColor,1.5f)){
            if(Checked)using(var fill=new SolidBrush(Color.FromArgb(90,ForeColor)))g.FillPolygon(fill,shape);
            g.DrawPolygon(pen,shape);g.DrawLine(pen,x+8,y+14,x+8,y+21);
            if(!Checked)g.DrawLine(pen,x-1,y+20,x+17,y);
        }
        if(Focused && ShowFocusCues)ControlPaint.DrawFocusRectangle(g,ClientRectangle,ForeColor,BackColor);
    }
}
public class TemplateNameLabel : Label {
    bool hovered,pressed;
    public TemplateNameLabel(){AutoSize=false;AutoEllipsis=true;TextAlign=ContentAlignment.MiddleCenter;Cursor=Cursors.Hand;DoubleBuffered=true;Padding=new Padding(5,0,5,0);}
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;pressed=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnMouseDown(MouseEventArgs e){if(e.Button==MouseButtons.Left){pressed=true;Invalidate();}base.OnMouseDown(e);}
    protected override void OnMouseUp(MouseEventArgs e){pressed=false;Invalidate();base.OnMouseUp(e);}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.Clear(BackColor);
        if(hovered||pressed)using(var fill=new SolidBrush(Color.FromArgb(pressed?45:22,ForeColor)))g.FillRectangle(fill,ClientRectangle);
        using(var line=new Pen(ForeColor,1))g.DrawRectangle(line,0,0,Width-1,Height-1);
        var text=new Rectangle(Padding.Left+(pressed?1:0),pressed?1:0,Width-Padding.Horizontal,Height-1);
        TextRenderer.DrawText(g,Text,Font,text,ForeColor,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);
    }
}
public class DockHintWindow : Form {
    public DockHintWindow(){DoubleBuffered=true;Padding=new Padding(3);}
    protected override void OnSizeChanged(EventArgs e){
        base.OnSizeChanged(e);if(ClientSize.Width<8 || ClientSize.Height<8)return;
        float d=12,w=ClientSize.Width,h=ClientSize.Height;
        using(var path=new GraphicsPath()){
            path.AddArc(0,0,d,d,180,90);path.AddArc(w-d,0,d,d,270,90);path.AddArc(w-d,h-d,d,d,0,90);path.AddArc(0,h-d,d,d,90,90);path.CloseFigure();
            var old=Region;Region=new Region(path);if(old!=null)old.Dispose();
        }
        Invalidate();
    }
    protected override void OnPaintBackground(PaintEventArgs e){
        base.OnPaintBackground(e);if(Width<8 || Height<8)return;
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        float d=10,w=ClientSize.Width-2,h=ClientSize.Height-2;
        using(var path=new GraphicsPath())using(var pen=new Pen(Color.FromArgb(183,183,183),2)){
            path.AddArc(1,1,d,d,180,90);path.AddArc(w-d,1,d,d,270,90);path.AddArc(w-d,h-d,d,d,0,90);path.AddArc(1,h-d,d,d,90,90);path.CloseFigure();e.Graphics.DrawPath(pen,path);
        }
    }
}