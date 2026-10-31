using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;

public class PictureEditor : RichTextBox {
    [StructLayout(LayoutKind.Sequential)] struct TextRequest {public uint cb,flags,codepage;public IntPtr a,b;}
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h,int m,ref TextRequest p,StringBuilder text);
    readonly List<Bitmap> bitmaps=new List<Bitmap>();readonly List<int> offsets=new List<int>();
    List<TaskDocument.PictureInfo> pictures=new List<TaskDocument.PictureInfo>();
    bool stale=true,resizing;int selected=-1,corner;Point anchor;Rectangle preview;double aspect=1;
    void RefreshPictures(){
        if(!stale)return;stale=false;
        foreach(var bitmap in bitmaps)if(bitmap!=null)bitmap.Dispose();bitmaps.Clear();offsets.Clear();
        pictures=TaskDocument.Pictures(Rtf);
        var request=new TextRequest{cb=(uint)((TextLength+32)*2),flags=4,codepage=1200};var text=new StringBuilder(TextLength+32);
        SendMessage(Handle,0x45E,ref request,text);
        for(int i=0;i<text.Length;i++)if(text[i]=='\uFFFC')offsets.Add(i);
        foreach(var picture in pictures){try{bitmaps.Add(TaskDocument.DecodePicture(picture));}catch{bitmaps.Add(null);}}
        if(selected>=pictures.Count)selected=-1;
    }
    float ScaleFactor {get{using(var g=CreateGraphics())return g.DpiX/96f*ZoomFactor;}}
    public Rectangle PictureBounds(int index){
        RefreshPictures();if(index<0 || index>=pictures.Count || index>=offsets.Count)return Rectangle.Empty;
        Point point=GetPositionFromCharIndex(offsets[index]);float scale=ScaleFactor;
        return new Rectangle(point.X,point.Y,Math.Max(1,(int)Math.Round(pictures[index].Width*scale)),Math.Max(1,(int)Math.Round(pictures[index].Height*scale)));
    }
    static Point[] Corners(Rectangle r){return new Point[]{new Point(r.Left,r.Top),new Point(r.Right,r.Top),new Point(r.Left,r.Bottom),new Point(r.Right,r.Bottom)};}
    int CornerAt(Point point){
        if(selected<0)return -1;var corners=Corners(PictureBounds(selected));
        for(int i=0;i<4;i++)if(new Rectangle(corners[i].X-7,corners[i].Y-7,14,14).Contains(point))return i;
        return -1;
    }
    protected override void OnTextChanged(EventArgs e){stale=true;base.OnTextChanged(e);}
    protected override void OnMouseDown(MouseEventArgs e){
        RefreshPictures();int hit=CornerAt(e.Location);
        if(e.Button==MouseButtons.Left && hit>=0){
            corner=hit;preview=PictureBounds(selected);anchor=Corners(preview)[3-hit];
            var image=bitmaps[selected];aspect=image!=null?(double)image.Height/image.Width:(double)preview.Height/preview.Width;
            resizing=true;Capture=true;return;
        }
        for(int i=0;i<pictures.Count;i++)if(e.Button==MouseButtons.Left && PictureBounds(i).Contains(e.Location)){
            Focus();selected=i;if(i<offsets.Count)Select(offsets[i],1);Invalidate();return;
        }
        selected=-1;base.OnMouseDown(e);Invalidate();
    }
    protected override void OnMouseMove(MouseEventArgs e){
        if(resizing){
            int dx=(corner==0 || corner==2)?anchor.X-e.X:e.X-anchor.X;
            int dy=(corner==0 || corner==1)?anchor.Y-e.Y:e.Y-anchor.Y;
            int width=(int)Math.Round(Math.Max(24,Math.Min(1600*ScaleFactor,(dx+dy*aspect)/(1+aspect*aspect))));
            int height=Math.Max(1,(int)Math.Round(width*aspect));
            preview=new Rectangle((corner==0 || corner==2)?anchor.X-width:anchor.X,(corner==0 || corner==1)?anchor.Y-height:anchor.Y,width,height);
            Invalidate();return;
        }
        int hit=CornerAt(e.Location);Cursor=hit<0?Cursors.IBeam:(hit==0 || hit==3)?Cursors.SizeNWSE:Cursors.SizeNESW;
        base.OnMouseMove(e);
    }
    protected override void OnMouseUp(MouseEventArgs e){
        if(resizing){
            resizing=false;Capture=false;float scale=ScaleFactor;
            int width=Math.Max(1,(int)Math.Round(preview.Width/scale));int height=Math.Max(1,(int)Math.Round(width*aspect));
            try{TaskDocument.ResizePicture(this,selected,width,height);}catch(Exception error){MessageBox.Show(FindForm(),error.Message,"图片大小");}
            Invalidate();return;
        }
        base.OnMouseUp(e);
    }
    public void DrawPictures(Graphics g){
        RefreshPictures();g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.HighQuality;
        for(int i=0;i<pictures.Count;i++){
            Rectangle bounds=PictureBounds(i);if(bounds.IsEmpty || !bounds.IntersectsWith(ClientRectangle))continue;
            if(resizing && i==selected){using(var fill=new SolidBrush(BackColor))g.FillRectangle(fill,bounds);bounds=preview;}
            if(bitmaps[i]!=null)g.DrawImage(bitmaps[i],bounds);
        }
        if(selected>=0){
            Rectangle bounds=resizing?preview:PictureBounds(selected);
            using(var pen=new Pen(Color.RoyalBlue,1))g.DrawRectangle(pen,bounds);
            foreach(var point in Corners(bounds)){var handle=new Rectangle(point.X-3,point.Y-3,7,7);g.FillRectangle(Brushes.White,handle);g.DrawRectangle(Pens.RoyalBlue,handle);}
        }
    }
    protected override void WndProc(ref Message m){base.WndProc(ref m);if(m.Msg==0xF || m.Msg==0x115 || m.Msg==0x114){using(var g=Graphics.FromHwnd(Handle))DrawPictures(g);}}
    protected override void Dispose(bool disposing){if(disposing)foreach(var bitmap in bitmaps)if(bitmap!=null)bitmap.Dispose();base.Dispose(disposing);}
}

public static class TaskDocument {
    public static Bitmap DecodePicture(PictureInfo picture){
        string hex=Regex.Replace(Regex.Match(picture.Rtf,@"[0-9a-fA-F\r\n]{100,}").Value,@"\s","");
        byte[] bytes=new byte[hex.Length/2];for(int i=0;i<bytes.Length;i++)bytes[i]=Convert.ToByte(hex.Substring(i*2,2),16);
        // RichEdit stores DIBs inside WMF wrappers. Decode the original bitmap rather than stretching the metafile.
        if(picture.Rtf.Contains("\\wmetafile") || picture.Rtf.Contains("\\dibitmap")){
            for(int offset=0;offset+40<bytes.Length;offset++){
                int header=BitConverter.ToInt32(bytes,offset);if(header!=40 && header!=108 && header!=124)continue;
                int width=BitConverter.ToInt32(bytes,offset+4),height=BitConverter.ToInt32(bytes,offset+8);
                int planes=BitConverter.ToUInt16(bytes,offset+12),bits=BitConverter.ToUInt16(bytes,offset+14),compression=BitConverter.ToInt32(bytes,offset+16);
                if(width<1 || width>20000 || height==0 || Math.Abs((long)height)>20000 || planes!=1 || (bits!=24 && bits!=32 && bits!=8 && bits!=16) || (compression!=0 && compression!=3))continue;
                int palette=bits<=8?BitConverter.ToInt32(bytes,offset+32):0;if(bits<=8 && palette==0)palette=1<<bits;
                int pixelOffset=14+header+palette*4+((compression==3 && header==40)?12:0);
                using(var stream=new MemoryStream())using(var writer=new BinaryWriter(stream)){
                    writer.Write((ushort)0x4d42);writer.Write(bytes.Length-offset+14);writer.Write(0);writer.Write(pixelOffset);writer.Write(bytes,offset,bytes.Length-offset);stream.Position=0;
                    using(var image=Image.FromStream(stream))return new Bitmap(image);
                }
            }
            throw new InvalidDataException("图片中没有可读取的原始位图。");
        }
        using(var stream=new MemoryStream(bytes))using(var image=Image.FromStream(stream))return new Bitmap(image);
    }
    public sealed class PictureInfo {
        public int Start,Length,Width,Height;
        public string Rtf;
    }
    static int PictureValue(string rtf,string name,int fallback){
        var match=Regex.Match(rtf,@"\\"+name+@"(-?\d+)\b");return match.Success?Int32.Parse(match.Groups[1].Value):fallback;
    }
    public static List<PictureInfo> Pictures(string rtf){
        var pictures=new List<PictureInfo>();
        foreach(Match match in Regex.Matches(rtf,@"\\pict\b")){
            int start=rtf.LastIndexOf('{',match.Index),depth=0,end=start;
            if(start<0)continue;
            for(;end<rtf.Length;end++){
                if(rtf[end]=='\\'){end++;continue;}
                if(rtf[end]=='{')depth++;
                if(rtf[end]=='}' && --depth==0){end++;break;}
            }
            if(end>rtf.Length || depth!=0)throw new InvalidDataException("图片数据不完整，未修改文档。");
            string group=rtf.Substring(start,end-start);
            if(Regex.IsMatch(group,@"\\bin\d"))throw new InvalidDataException("此图片格式暂不支持调整，未修改文档。");
            int w=PictureValue(group,"picwgoal",PictureValue(group,"picw",1)*15);
            int h=PictureValue(group,"pichgoal",PictureValue(group,"pich",1)*15);
            pictures.Add(new PictureInfo{Start=start,Length=end-start,Rtf=group,Width=Math.Max(1,w*PictureValue(group,"picscalex",100)/1500),Height=Math.Max(1,h*PictureValue(group,"picscaley",100)/1500)});
        }
        return pictures;
    }
    static string SetPictureValue(string group,string name,int value){
        string pattern=@"\\"+name+@"-?\d+\b",replacement="\\"+name+value;
        return Regex.IsMatch(group,pattern)?Regex.Replace(group,pattern,replacement):group.Insert(group.IndexOf("\\pict")+5,replacement);
    }
    public static void ResizePicture(RichTextBox editor,int index,int width,int height){
        if(width<1 || height<1 || width>4000 || height>4000)throw new ArgumentOutOfRangeException("width");
        string rtf=editor.Rtf;var list=Pictures(rtf);if(index<0 || index>=list.Count)throw new ArgumentOutOfRangeException("index");
        var image=list[index];string group=image.Rtf;
        group=SetPictureValue(group,"picwgoal",width*15);group=SetPictureValue(group,"pichgoal",height*15);
        group=SetPictureValue(group,"picscalex",100);group=SetPictureValue(group,"picscaley",100);
        int selection=editor.SelectionStart;
        editor.Rtf=rtf.Substring(0,image.Start)+group+rtf.Substring(image.Start+image.Length);
        editor.Select(Math.Min(selection,editor.TextLength),0);
    }
    static bool PictureSizeDialog(Form owner,RichTextBox editor){
        var pictures=Pictures(editor.Rtf);
        if(pictures.Count==0){MessageBox.Show(owner,"请先插入一张图片。","图片大小");return false;}
        using(var dialog=new Form()){
            dialog.Text="图片大小";dialog.Size=new Size(350,260);dialog.StartPosition=FormStartPosition.CenterParent;dialog.Font=owner.Font;dialog.BackColor=owner.BackColor;
            var choose=new ComboBox();choose.DropDownStyle=ComboBoxStyle.DropDownList;choose.SetBounds(18,15,295,28);
            for(int i=0;i<pictures.Count;i++)choose.Items.Add("第"+(i+1)+"张图片（"+pictures[i].Width+" × "+pictures[i].Height+"）");
            var width=new NumericUpDown();width.Minimum=1;width.Maximum=4000;width.SetBounds(95,58,110,28);
            var height=new NumericUpDown();height.Minimum=1;height.Maximum=4000;height.SetBounds(95,96,110,28);
            var wl=new Label();wl.Text="宽度";wl.SetBounds(18,61,70,24);
            var hl=new Label();hl.Text="高度";hl.SetBounds(18,99,70,24);
            var ratio=new CheckBox();ratio.Text="保持图片比例";ratio.Checked=true;ratio.Enabled=false;ratio.SetBounds(18,137,180,28);
            bool syncing=false;double aspect=1;
            choose.SelectedIndexChanged+=(s,e)=>{syncing=true;var pic=pictures[choose.SelectedIndex];aspect=(double)pic.Height/pic.Width;try{using(var raw=DecodePicture(pic))aspect=(double)raw.Height/raw.Width;}catch{}width.Value=Math.Min(4000,pic.Width);height.Value=Math.Max(1,Math.Min(4000,(decimal)Math.Round((double)width.Value*aspect)));syncing=false;};
            width.ValueChanged+=(s,e)=>{if(syncing || !ratio.Checked)return;syncing=true;height.Value=Math.Max(1,Math.Min(4000,(decimal)Math.Round((double)width.Value*aspect)));syncing=false;};
            height.ValueChanged+=(s,e)=>{if(syncing || !ratio.Checked)return;syncing=true;width.Value=Math.Max(1,Math.Min(4000,(decimal)Math.Round((double)height.Value/aspect)));syncing=false;};
            var apply=new Button();apply.Text="确定";apply.SetBounds(222,175,90,30);
            apply.Click+=(s,e)=>{ResizePicture(editor,choose.SelectedIndex,(int)width.Value,(int)height.Value);dialog.DialogResult=DialogResult.OK;dialog.Close();};
            dialog.Controls.AddRange(new Control[]{choose,wl,width,hl,height,ratio,apply});dialog.AcceptButton=apply;choose.SelectedIndex=0;
            return dialog.ShowDialog(owner)==DialogResult.OK;
        }
    }
    public static void SetTextSize(RichTextBox editor,float size){
        int start=editor.SelectionStart,length=editor.SelectionLength;
        if(length>0 && editor.SelectionFont==null){
            for(int i=start;i<start+length;i++){
                editor.Select(i,1);var font=editor.SelectionFont??editor.Font;
                editor.SelectionFont=new Font(font.FontFamily,size,font.Style,GraphicsUnit.Point);
            }
            editor.Select(start,length);
        }else{
            var font=editor.SelectionFont??editor.Font;
            editor.SelectionFont=new Font(font.FontFamily,size,font.Style,GraphicsUnit.Point);
        }
    }
    public static void InsertImage(RichTextBox editor,string path){
        using(var source=Image.FromFile(path)){
            double scale=Math.Min(1,600.0/source.Width);
            int width=Math.Max(1,(int)(source.Width*scale)),height=Math.Max(1,(int)(source.Height*scale));
            using(var bitmap=new Bitmap(source.Width,source.Height,System.Drawing.Imaging.PixelFormat.Format24bppRgb))
            using(var stream=new MemoryStream()){
                using(var g=Graphics.FromImage(bitmap)){g.Clear(Color.White);g.DrawImage(source,new Rectangle(0,0,bitmap.Width,bitmap.Height));}
                bitmap.Save(stream,System.Drawing.Imaging.ImageFormat.Bmp);
                string hex=BitConverter.ToString(stream.ToArray(),14).Replace("-","");
                editor.SelectedRtf="{\\rtf1\\ansi{\\pict\\dibitmap0\\picw"+bitmap.Width+"\\pich"+bitmap.Height+"\\picwgoal"+(width*15)+"\\pichgoal"+(height*15)+" "+hex+"}}";
                editor.SelectedText=Environment.NewLine;
            }
        }
    }
    static readonly Dictionary<string,Form> openDocuments=new Dictionary<string,Form>(StringComparer.OrdinalIgnoreCase);
    public static Form Open(Form owner,string path,string title,string taskId,Action<string,string> onSaved){
        Form existing;
        if(openDocuments.TryGetValue(path,out existing) && !existing.IsDisposed){existing.WindowState=FormWindowState.Normal;existing.Show();existing.Activate();return existing;}
        bool dirty=false;
        var window=new Form();
        var body=new PictureEditor();
        var name=new TextBox();
            window.Text="任务小文档";window.Size=new Size(740,650);window.MinimumSize=new Size(500,400);
            window.StartPosition=FormStartPosition.CenterParent;window.BackColor=owner.BackColor;window.ForeColor=owner.ForeColor;
            window.Font=new Font("Microsoft YaHei UI",10);window.TopMost=owner.TopMost;
            name.BackColor=owner.BackColor;name.ForeColor=owner.ForeColor;
            name.Text=title;name.Dock=DockStyle.Top;name.Font=new Font(window.Font,FontStyle.Bold);
            body.Dock=DockStyle.Fill;body.Font=window.Font;body.BackColor=owner.BackColor.GetBrightness()<0.3f?Color.FromArgb(205,205,205):(owner.BackColor.R>owner.BackColor.G+8 && owner.BackColor.B>owner.BackColor.G?Color.FromArgb(255,252,244):Color.FromArgb(255,254,245));
            body.DetectUrls=true;body.AcceptsTab=true;body.HideSelection=false;
            if(File.Exists(path))body.LoadFile(path,RichTextBoxStreamType.RichText);
            var tools=new FlowLayoutPanel();tools.Dock=DockStyle.Top;tools.AutoSize=true;tools.AutoSizeMode=AutoSizeMode.GrowAndShrink;tools.Padding=new Padding(0,3,0,3);
            var image=new Button();image.Text="插入图片";image.AutoSize=true;
            image.Click+=(s,e)=>{
                using(var picker=new OpenFileDialog()){
                    picker.Filter="图片|*.png;*.jpg;*.jpeg;*.bmp;*.gif";
                    if(picker.ShowDialog(window)==DialogResult.OK){
                        try{InsertImage(body,picker.FileName);body.Focus();}
                        catch(Exception ex){MessageBox.Show(window,"图片插入失败："+ex.Message);}
                    }
                }
            };
            var bold=new Button();bold.Text="加粗";bold.AutoSize=true;
            bold.Click+=(s,e)=>{var font=body.SelectionFont??body.Font;body.SelectionFont=new Font(font,font.Bold?FontStyle.Regular:FontStyle.Bold);body.Focus();};
            var save=new Button();save.Text="保存";save.BackColor=Color.FromArgb(197,221,179);save.AutoSize=true;
            var status=new Label();status.Text="可输入文字、粘贴内容，或插入图片";status.AutoSize=true;status.Padding=new Padding(0,7,0,0);
            var imageSize=new Button();imageSize.Text="图片大小";imageSize.AutoSize=true;
            imageSize.Click+=(s,e)=>{
                try{if(PictureSizeDialog(window,body)){dirty=true;status.Text="有未保存的修改";body.Focus();}}
                catch(Exception ex){MessageBox.Show(window,"图片调整失败："+ex.Message);}
            };
            var palette=new FlowLayoutPanel();palette.AutoSize=true;palette.WrapContents=false;palette.Margin=new Padding(2,3,2,0);
            Color[] colors={Color.Black,Color.Red,Color.Yellow,Color.Blue,Color.Green};
            string[] names={"黑色","红色","黄色","蓝色","绿色"};
            var colorTips=new ToolTip();window.Disposed+=(s,e)=>colorTips.Dispose();
            for(int i=0;i<colors.Length;i++){
                Color chosen=colors[i];var swatch=new Button();
                swatch.Size=new Size(23,23);swatch.Margin=new Padding(2,0,2,0);swatch.BackColor=chosen;
                swatch.UseVisualStyleBackColor=false;swatch.FlatStyle=FlatStyle.Flat;swatch.FlatAppearance.BorderColor=Color.DimGray;
                swatch.AccessibleName=names[i];colorTips.SetToolTip(swatch,names[i]);
                swatch.Click+=(s,e)=>{body.SelectionColor=chosen;dirty=true;status.Text="有未保存的修改";body.Focus();};
                palette.Controls.Add(swatch);
            }
            var color=new Button();color.Text="自定义颜色";color.AutoSize=true;
            color.Click+=(s,e)=>{
                using(var picker=new ColorDialog()){
                    picker.FullOpen=true;picker.Color=body.SelectionColor.IsEmpty?Color.Black:body.SelectionColor;
                    if(picker.ShowDialog(window)==DialogResult.OK){body.SelectionColor=picker.Color;dirty=true;status.Text="有未保存的修改";}
                }
                body.Focus();
            };
            var sizeLabel=new Label();sizeLabel.Text="字号";sizeLabel.AutoSize=true;sizeLabel.Padding=new Padding(0,7,0,0);
            var size=new NumericUpDown();size.Minimum=6;size.Maximum=96;size.Value=10;size.Width=54;
            bool syncingSize=false;
            size.ValueChanged+=(s,e)=>{
                if(syncingSize)return;
                SetTextSize(body,(float)size.Value);dirty=true;status.Text="有未保存的修改";
            };
            body.SelectionChanged+=(s,e)=>{
                if(body.SelectionFont==null)return;
                syncingSize=true;size.Value=Math.Max(size.Minimum,Math.Min(size.Maximum,(decimal)body.SelectionFont.SizeInPoints));syncingSize=false;
            };
            Func<bool> persist=()=>{
                if(String.IsNullOrWhiteSpace(name.Text)){MessageBox.Show(window,"请填写任务名称。");return false;}
                try{
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    string temp=path+".tmp";body.SaveFile(temp,RichTextBoxStreamType.RichText);
                    if(File.Exists(path))File.Replace(temp,path,path+".bak");else File.Move(temp,path);
                    if(onSaved!=null)onSaved(taskId,name.Text.Trim());dirty=false;status.Text="已保存";return true;
                }catch(Exception ex){MessageBox.Show(window,"保存失败："+ex.Message);return false;}
            };
            save.Click+=(s,e)=>persist();
            body.TextChanged+=(s,e)=>{dirty=true;status.Text="有未保存的修改";};
            name.TextChanged+=(s,e)=>{dirty=true;status.Text="有未保存的修改";};
            window.FormClosing+=(s,e)=>{
                if(!dirty)return;
                var answer=MessageBox.Show(window,"保存修改后再关闭吗？","任务小文档",MessageBoxButtons.YesNoCancel);
                if(answer==DialogResult.Cancel || (answer==DialogResult.Yes && !persist()))e.Cancel=true;
            };
            tools.Controls.AddRange(new Control[]{image,imageSize,bold,palette,color,sizeLabel,size,save,status});
            tools.BackColor=window.BackColor;
            foreach(Control control in tools.Controls){
                if(control is Button){control.BackColor=owner.BackColor.GetBrightness()<0.3f?Color.FromArgb(69,69,69):owner.BackColor;control.ForeColor=owner.ForeColor;((Button)control).FlatStyle=FlatStyle.Flat;}
                else if(control is NumericUpDown){control.BackColor=window.BackColor;control.ForeColor=window.ForeColor;}
            }
            save.BackColor=owner.BackColor.GetBrightness()<0.3f?Color.FromArgb(27,70,126):(owner.BackColor.B>owner.BackColor.G?Color.FromArgb(232,189,204):Color.FromArgb(197,221,179));
            window.Controls.Add(body);window.Controls.Add(tools);window.Controls.Add(name);
            openDocuments[path]=window;
            window.Disposed+=(s,e)=>{openDocuments.Remove(path);};
            window.StartPosition=FormStartPosition.Manual;
            window.Location=new Point(Math.Max(0,owner.Left-window.Width-12),Math.Max(0,owner.Top+40));
            window.Show(owner);
            return window;
    }
}
