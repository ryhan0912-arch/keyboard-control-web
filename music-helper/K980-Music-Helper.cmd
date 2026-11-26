<# :
@echo off
title K980 Music Helper
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0'))"
exit /b
#>
# K980 Music Helper
# Makes the XINMENG K980's lights follow whatever Windows is playing on the ACTIVE output device (speakers,
# headphones, monitor …) — even when the Keyboard Control page is closed.
#  - Captures the sound with WASAPI loopback and switches automatically when the default output device changes.
#  - Sends live colors to the keyboard (USB cable, wired mode) with feature report 08, like the page's music mode.
#  - The Keyboard Control page controls it over a local WebSocket (ws://127.0.0.1:28420): start/stop, effect,
#    colors, sensitivity, smoothness, pause while the page saves. Settings are remembered between runs.
# Nothing leaves this computer. Close this window (or Ctrl+C) to stop; the keyboard's saved lighting comes back.
if(-not $Port){ $Port=28420 }
$ErrorActionPreference='Stop'
$src=@'
using System; using System.Runtime.InteropServices; using System.Net; using System.Net.WebSockets; using System.Threading;
using System.Threading.Tasks; using System.Collections.Generic; using System.Text; using System.IO;
namespace K980Music {
 [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo {}
 [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDeviceEnumerator {
  int EnumAudioEndpoints(int dataFlow,int stateMask,out IntPtr devices);
  int GetDefaultAudioEndpoint(int dataFlow,int role,out IMMDevice endpoint); }
 [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDevice {
  int Activate(ref Guid iid,int clsCtx,IntPtr p,[MarshalAs(UnmanagedType.IUnknown)] out object iface);
  int OpenPropertyStore(int access,out IPropertyStore props);
  int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); int GetState(out int state); }
 [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IPropertyStore {
  int GetCount(out int c); int GetAt(int i,out PROPERTYKEY k); int GetValue(ref PROPERTYKEY k,out PROPVARIANT v); }
 [StructLayout(LayoutKind.Sequential)] struct PROPERTYKEY { public Guid fmtid; public int pid; }
 [StructLayout(LayoutKind.Explicit,Size=24)] struct PROPVARIANT { [FieldOffset(0)] public short vt; [FieldOffset(8)] public IntPtr p; }
 [Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioClient {
  int Initialize(int shareMode,int streamFlags,long bufferDuration,long periodicity,IntPtr format,IntPtr sessionGuid);
  int GetBufferSize(out uint frames); int GetStreamLatency(out long l); int GetCurrentPadding(out uint p);
  int IsFormatSupported(int shareMode,IntPtr format,out IntPtr closest); int GetMixFormat(out IntPtr format);
  int GetDevicePeriod(out long def,out long min); int Start(); int Stop(); int Reset(); int SetEventHandle(IntPtr h);
  int GetService(ref Guid iid,[MarshalAs(UnmanagedType.IUnknown)] out object o); }
 [Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioCaptureClient {
  int GetBuffer(out IntPtr data,out uint frames,out uint flags,out ulong devPos,out ulong qpc);
  int ReleaseBuffer(uint frames); int GetNextPacketSize(out uint frames); }

 // ---------------- Keyboard (XINMENG K980, cable/wired mode = USB 258A:0049, vendor interface MI_01) ----------------
 static class Kbd {
  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("setupapi.dll",CharSet=CharSet.Unicode)] static extern IntPtr SetupDiGetClassDevsW(ref Guid g,IntPtr e,IntPtr h,int f);
  [StructLayout(LayoutKind.Sequential)] struct DID{public int cb;public Guid g;public int f;public IntPtr r;}
  [DllImport("setupapi.dll")] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s,IntPtr d,ref Guid g,int i,ref DID did);
  [DllImport("setupapi.dll",CharSet=CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr s,ref DID did,IntPtr det,int sz,out int req,IntPtr dd);
  [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
  [DllImport("kernel32.dll",SetLastError=true,CharSet=CharSet.Unicode)] static extern IntPtr CreateFileW(string n,uint a,uint sh,IntPtr sa,uint c,uint f,IntPtr t);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("hid.dll",SetLastError=true)] static extern bool HidD_SetFeature(IntPtr h,byte[] b,int l);
  [DllImport("hid.dll",SetLastError=true)] static extern bool HidD_GetFeature(IntPtr h,byte[] b,int l);
  static IntPtr h5=IntPtr.Zero,h6=IntPtr.Zero,h8=IntPtr.Zero;
  static string Path(string f){ Guid g; HidD_GetHidGuid(out g); IntPtr s=SetupDiGetClassDevsW(ref g,IntPtr.Zero,IntPtr.Zero,0x12);
   try{ for(int i=0;;i++){ var d=new DID(); d.cb=Marshal.SizeOf(typeof(DID)); if(!SetupDiEnumDeviceInterfaces(s,IntPtr.Zero,ref g,i,ref d)) return null;
     int q; SetupDiGetDeviceInterfaceDetailW(s,ref d,IntPtr.Zero,0,out q,IntPtr.Zero); IntPtr p=Marshal.AllocHGlobal(q); Marshal.WriteInt32(p,8);
     SetupDiGetDeviceInterfaceDetailW(s,ref d,p,q,out q,IntPtr.Zero); string path=Marshal.PtrToStringUni(new IntPtr(p.ToInt64()+4)); Marshal.FreeHGlobal(p);
     if(path.IndexOf(f,StringComparison.OrdinalIgnoreCase)>=0) return path; } } finally { SetupDiDestroyDeviceInfoList(s); } }
  static IntPtr Open(string p){ IntPtr h=CreateFileW(p,0xC0000000,3,IntPtr.Zero,3,0,IntPtr.Zero); if(h.ToInt64()==-1) h=CreateFileW(p,0,3,IntPtr.Zero,3,0,IntPtr.Zero); return h; }
  public static bool Connected { get { return h8!=IntPtr.Zero; } }
  public static bool Ensure(){
   if(h8!=IntPtr.Zero) return true;
   string p5=Path("vid_258a&pid_0049&mi_01&col05"), p6=Path("vid_258a&pid_0049&mi_01&col06"), p8=Path("vid_258a&pid_0049&mi_01&col08");
   if(p5==null||p6==null||p8==null) return false;
   h5=Open(p5); h6=Open(p6); h8=Open(p8);
   if(h5.ToInt64()==-1||h6.ToInt64()==-1||h8.ToInt64()==-1){ Close(); return false; }
   return true; }
  public static void Close(){ foreach(var h in new[]{h5,h6,h8}) if(h!=IntPtr.Zero && h.ToInt64()!=-1) CloseHandle(h); h5=h6=h8=IntPtr.Zero; }
  public static bool Frame(byte[] rgb){ var b=new byte[382]; b[0]=8; b[1]=0x0A; b[2]=0x7A; b[3]=0x01; Array.Copy(rgb,0,b,4,378);
   if(HidD_SetFeature(h8,b,382)) return true; Close(); return false; }
  // Re-send the saved lighting page (no unlock, so nothing is stored): the keyboard leaves live mode and shows its effect again.
  public static bool RestoreLighting(){
   if(!Ensure()) return false;
   var cmd=new byte[]{5,0x83,0xB6,0,0,0}; HidD_SetFeature(h5,cmd,6); Thread.Sleep(30);
   var b=new byte[1032]; b[0]=6; if(!HidD_GetFeature(h6,b,1032)) return false;
   if(!((b[1]&0x7F)==3 && b[2]==0xB6 && b[14]==0x5A && b[15]==0xA5)) return false;
   HidD_SetFeature(h5,cmd,6); Thread.Sleep(20); b[1]=3; return HidD_SetFeature(h6,b,1032); }
 }

 public static class Helper {
  const int N=1024; static readonly object lk=new object();
  static float[] ring=new float[N]; static int pos=0;
  public static volatile string DeviceName="(none)"; static string devId="";
  static readonly List<WebSocket> clients=new List<WebSocket>();
  public static volatile bool Running=true;
  // settings (remembered in %APPDATA%\K980MusicHelper\settings.txt)
  public static volatile bool MusicOn=false; static volatile bool paused=false; static DateTime pauseUntil=DateTime.MinValue;
  static string effect="bars", colorMode="rainbow"; static int cr=0,cg=200,cb=255; static double gain=1.5, smooth=0.8;
  static float[] levels=new float[21]; static float peak=0, hue=0; static volatile int lastLevel=0; static volatile bool lit=false;
  static string SettingsFile { get { var d=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"K980MusicHelper"); Directory.CreateDirectory(d); return System.IO.Path.Combine(d,"settings.txt"); } }
  public static void Load(){ try{ foreach(var line in File.ReadAllLines(SettingsFile)){ var kv=line.Split(new[]{'='},2); if(kv.Length==2) Set(kv[0],kv[1]); } }catch{} }
  static void Save(){ try{ File.WriteAllText(SettingsFile, "on="+(MusicOn?1:0)+"\neffect="+effect+"\ncolorMode="+colorMode+"\ncolor="+cr+","+cg+","+cb+"\ngain="+gain.ToString(System.Globalization.CultureInfo.InvariantCulture)+"\nsmooth="+smooth.ToString(System.Globalization.CultureInfo.InvariantCulture)); }catch{} }
  static void Set(string k,string v){ var ci=System.Globalization.CultureInfo.InvariantCulture; v=v.Trim();
   switch(k.Trim()){ case "on": MusicOn=v=="1"||v=="true"; break; case "effect": effect=v; break; case "colorMode": colorMode=v; break;
    case "color": { var p=v.Split(','); if(p.Length==3){ cr=int.Parse(p[0]); cg=int.Parse(p[1]); cb=int.Parse(p[2]); } break; }
    case "gain": gain=Math.Max(0.2,Math.Min(6,double.Parse(v,ci))); break; case "smooth": smooth=Math.Max(0,Math.Min(0.97,double.Parse(v,ci))); break; } }
  static readonly int[] KEYS={0,59,67,6,143,67,12,203,67,18,269,67,24,331,67,30,411,67,36,475,67,42,541,67,48,605,67,54,685,69,60,749,69,66,813,69,72,879,69,78,955,69,84,1047,67,90,1109,67,96,1175,65,102,1237,65,1,59,153,7,127,153,13,189,153,19,251,153,25,315,155,31,379,155,37,443,155,43,507,155,49,571,155,55,633,155,61,697,155,67,763,155,73,825,155,79,922,155,85,1047,153,91,1109,153,97,1173,153,103,1237,153,2,76,217,8,155,217,14,219,217,20,281,217,26,345,217,32,409,217,38,473,217,44,537,217,50,601,217,56,665,219,62,729,219,68,795,219,74,857,219,80,936,217,86,1047,217,92,1111,217,98,1177,217,104,1241,246,3,84,281,9,171,281,15,233,281,21,299,281,27,361,281,33,425,281,39,489,281,45,553,281,51,615,281,57,683,281,63,745,281,69,809,281,81,914,281,87,1049,279,93,1113,279,99,1175,279,4,102,343,10,203,343,16,265,343,22,327,343,28,395,343,34,457,343,40,525,343,46,589,345,52,651,345,58,715,345,64,779,345,70,864,341,82,969,359,88,1047,345,94,1113,345,100,1177,345,106,1241,377,5,68,407,11,146,407,17,224,409,35,468,411,53,697,409,59,761,407,65,823,405,77,905,423,83,967,423,89,1031,423,95,1109,407,101,1177,409};

  static string Name(IMMDevice d){ try{ IPropertyStore ps; d.OpenPropertyStore(0,out ps);
    var k=new PROPERTYKEY{ fmtid=new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid=14 }; PROPVARIANT v; ps.GetValue(ref k,out v);
    return v.vt==31?Marshal.PtrToStringUni(v.p):"Audio device"; }catch{ return "Audio device"; } }

  // Capture loop: follows the default render device; restarts when it changes.
  public static void CaptureLoop(){
   var en=(IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
   while(Running){
    IAudioClient ac=null;
    try{
     IMMDevice dev; Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0,1,out dev));
     string id; dev.GetId(out id); devId=id; DeviceName=Name(dev);
     Console.WriteLine(DateTime.Now.ToString("HH:mm:ss")+"  Listening to: "+DeviceName); Status();
     Guid iidAC=new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"); object o; Marshal.ThrowExceptionForHR(dev.Activate(ref iidAC,23,IntPtr.Zero,out o)); ac=(IAudioClient)o;
     IntPtr fmt; Marshal.ThrowExceptionForHR(ac.GetMixFormat(out fmt));
     int ch=Marshal.ReadInt16(fmt,2), bits=Marshal.ReadInt16(fmt,14), tag=Marshal.ReadInt16(fmt,0);
     bool isFloat = bits==32 && (tag==3 || tag==unchecked((short)0xFFFE));
     Marshal.ThrowExceptionForHR(ac.Initialize(0,0x00020000,2000000,0,fmt,IntPtr.Zero));
     Guid iidCC=new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"); object o2; Marshal.ThrowExceptionForHR(ac.GetService(ref iidCC,out o2)); var cc=(IAudioCaptureClient)o2;
     Marshal.ThrowExceptionForHR(ac.Start());
     var lastCheck=DateTime.Now; var tmp=new float[1];
     while(Running){
      Thread.Sleep(10);
      uint packet; cc.GetNextPacketSize(out packet);
      while(packet>0){
       IntPtr data; uint frames, flags; ulong a,b; cc.GetBuffer(out data,out frames,out flags,out a,out b);
       lock(lk){ for(int i=0;i<frames;i++){ float s=0;
         if((flags&2)==0){ for(int c=0;c<ch;c++){
           if(isFloat){ Marshal.Copy(new IntPtr(data.ToInt64()+(i*ch+c)*4),tmp,0,1); s+=tmp[0]; }
           else if(bits==16) s+=Marshal.ReadInt16(data,(i*ch+c)*2)/32768f; } s/=ch; }
         ring[pos]=s; pos=(pos+1)%N; } }
       cc.ReleaseBuffer(frames); cc.GetNextPacketSize(out packet);
      }
      if((DateTime.Now-lastCheck).TotalMilliseconds>1000){ lastCheck=DateTime.Now;
       IMMDevice cur; if(en.GetDefaultAudioEndpoint(0,1,out cur)==0){ string cid; cur.GetId(out cid); if(cid!=devId) break; } }
     }
     ac.Stop();
    }catch(Exception ex){ Console.WriteLine("Audio: "+ex.Message+" - retrying"); Thread.Sleep(2000); }
    finally{ if(ac!=null) Marshal.ReleaseComObject(ac); }
   }
  }

  // Spectrum like a browser AnalyserNode (512 byte bins, -100..-30 dB)
  static byte[] Spectrum(){
   var re=new double[N]; var im=new double[N];
   lock(lk){ for(int i=0;i<N;i++){ double w=0.5-0.5*Math.Cos(2*Math.PI*i/(N-1)); re[i]=ring[(pos+i)%N]*w; } }
   for(int i=1,j=0;i<N;i++){ int bit=N>>1; for(;(j&bit)!=0;bit>>=1) j^=bit; j^=bit; if(i<j){ var t=re[i]; re[i]=re[j]; re[j]=t; } }
   for(int len=2;len<=N;len<<=1){ double ang=-2*Math.PI/len; for(int i=0;i<N;i+=len) for(int k=0;k<len/2;k++){
     double c1=Math.Cos(ang*k), s1=Math.Sin(ang*k); int u=i+k, v=i+k+len/2;
     double tr=re[v]*c1-im[v]*s1, ti=re[v]*s1+im[v]*c1; re[v]=re[u]-tr; im[v]=im[u]-ti; re[u]+=tr; im[u]+=ti; } }
   var outp=new byte[N/2];
   for(int i=0;i<N/2;i++){ double mag=Math.Sqrt(re[i]*re[i]+im[i]*im[i])/N*2; double db=20*Math.Log10(mag+1e-12);
     outp[i]=(byte)Math.Max(0,Math.Min(255,(db+100)/70*255)); }
   return outp;
  }
  static void Hsv(double h,double v,out int r,out int g,out int b){ h=((h%360)+360)%360; double c=v, x=c*(1-Math.Abs((h/60)%2-1));
   double rr,gg,bb; if(h<60){rr=c;gg=x;bb=0;} else if(h<120){rr=x;gg=c;bb=0;} else if(h<180){rr=0;gg=c;bb=x;} else if(h<240){rr=0;gg=x;bb=c;} else if(h<300){rr=x;gg=0;bb=c;} else {rr=c;gg=0;bb=x;}
   r=(int)Math.Round(rr*255); g=(int)Math.Round(gg*255); b=(int)Math.Round(bb*255); }
  // Same effects as the page's music mode
  static byte[] Render(byte[] f){
   const int bands=21; int n=f.Length; double vol=0;
   for(int b=0;b<bands;b++){ int lo=(int)Math.Floor(Math.Pow(n*0.7,(double)b/bands)), hi=Math.Max(lo+1,(int)Math.Floor(Math.Pow(n*0.7,(double)(b+1)/bands)));
    double s=0; for(int i=lo;i<hi&&i<n;i++) s+=f[i]; double v=Math.Min(1,(s/(hi-lo)/255)*gain);
    levels[b]=(float)Math.Max(v,levels[b]*smooth); vol+=levels[b]; }
   vol/=bands; peak=(float)Math.Max(vol,peak*0.92); hue=(float)((hue+1+vol*12)%360); lastLevel=(int)(vol*100);
   var rgb=new byte[378]; double x0=59,x1=1241,y0=65,y1=423;
   for(int i=0;i<KEYS.Length;i+=3){ int id=KEYS[i]; double fx=(KEYS[i+1]-x0)/(x1-x0), fy=1-(KEYS[i+2]-y0)/(y1-y0);
    double lvl=levels[Math.Min(bands-1,(int)Math.Floor(fx*bands))]; double h, v; bool useHue=colorMode!="single";
    if(effect=="bars"){ v=fy<=lvl+0.04?1:0.03; h=120-fy*120; }
    else if(effect=="pulse"){ v=Math.Min(1,0.08+vol*1.6); h=hue; }
    else if(effect=="rainbow"){ v=Math.Min(1,0.15+lvl*1.3); h=hue+fx*300; }
    else { double d=Math.Abs(fx-0.5)*2; v=d<=peak*1.4?Math.Min(1,0.3+lvl*1.2):0.03; h=hue+d*180; }
    int r,g,b; if(useHue) Hsv(h,v,out r,out g,out b); else { r=(int)(cr*v); g=(int)(cg*v); b=(int)(cb*v); }
    rgb[id*3]=(byte)r; rgb[id*3+1]=(byte)g; rgb[id*3+2]=(byte)b; }
   return rgb;
  }
  // Drives the keyboard ~25x/s while music mode is on; restores the saved lighting when it stops.
  public static void LightLoop(){
   var lastTry=DateTime.MinValue; bool kbWas=false; int tick=0;
   while(Running){
    Thread.Sleep(40); tick++;
    bool want=MusicOn && !(paused && DateTime.Now<pauseUntil);
    if(!want){ if(lit){ lit=false; Thread.Sleep(60); bool ok=Kbd.RestoreLighting(); Console.WriteLine(DateTime.Now.ToString("HH:mm:ss")+"  Music lights off"+(ok?" - saved lighting restored":"")); Status(); } continue; }
    if(!Kbd.Connected && (DateTime.Now-lastTry).TotalSeconds<2) continue;
    lastTry=DateTime.Now;
    if(!Kbd.Ensure()){ if(kbWas){ kbWas=false; Console.WriteLine(DateTime.Now.ToString("HH:mm:ss")+"  Keyboard not connected by cable - waiting"); Status(); } continue; }
    if(!kbWas){ kbWas=true; Console.WriteLine(DateTime.Now.ToString("HH:mm:ss")+"  Keyboard connected - music lights on"); Status(); }
    if(Kbd.Frame(Render(Spectrum()))) lit=true; else { kbWas=false; lit=false; Status(); }
    if(tick%5==0) Level();
   }
   if(lit) Kbd.RestoreLighting();
  }
  static void SendText(string m){ var bytes=Encoding.UTF8.GetBytes(m); WebSocket[] list; lock(clients) list=clients.ToArray();
   foreach(var ws in list){ try{ if(ws.State!=WebSocketState.Open){ lock(clients) clients.Remove(ws); continue; }
     ws.SendAsync(new ArraySegment<byte>(bytes),WebSocketMessageType.Text,true,CancellationToken.None).Wait(500); }catch{ lock(clients) clients.Remove(ws); } } }
  static string J(string s){ return s.Replace("\\","\\\\").Replace("\"","'"); }
  static void Status(){ var ci=System.Globalization.CultureInfo.InvariantCulture;
   SendText("{\"device\":\""+J(DeviceName)+"\",\"music\":"+(MusicOn?"true":"false")+",\"keyboard\":"+(Kbd.Connected?"true":"false")+",\"effect\":\""+effect+"\",\"colorMode\":\""+colorMode+"\",\"color\":\"#"+cr.ToString("x2")+cg.ToString("x2")+cb.ToString("x2")+"\",\"gain\":"+gain.ToString(ci)+",\"smooth\":"+smooth.ToString(ci)+"}"); }
  static void Level(){ SendText("{\"level\":"+lastLevel+"}"); }
  static void Handle(string msg){
   // tiny flat JSON parser: {"cmd":"set","on":true,"effect":"bars",...} / {"cmd":"pause","on":true}
   var d=new Dictionary<string,string>(); foreach(Match m in Regex.Matches(msg,"\"(\\w+)\"\\s*:\\s*(\"([^\"]*)\"|[-\\w.]+)")) d[m.Groups[1].Value]=m.Groups[3].Success&&m.Groups[2].Value.StartsWith("\"")?m.Groups[3].Value:m.Groups[2].Value;
   string cmd; d.TryGetValue("cmd",out cmd);
   if(cmd=="pause"){ bool on=d.ContainsKey("on")&&d["on"]=="true"; paused=on; pauseUntil=DateTime.Now.AddSeconds(on?20:0); return; }
   if(cmd=="set"){
    if(d.ContainsKey("effect")) effect=d["effect"]; if(d.ContainsKey("colorMode")) colorMode=d["colorMode"];
    if(d.ContainsKey("color")&&d["color"].Length==7){ var c=d["color"]; cr=Convert.ToInt32(c.Substring(1,2),16); cg=Convert.ToInt32(c.Substring(3,2),16); cb=Convert.ToInt32(c.Substring(5,2),16); }
    if(d.ContainsKey("gain")) Set("gain",d["gain"]); if(d.ContainsKey("smooth")) Set("smooth",d["smooth"]);
    if(d.ContainsKey("on")){ bool on=d["on"]=="true"; if(on!=MusicOn){ MusicOn=on; Console.WriteLine(DateTime.Now.ToString("HH:mm:ss")+"  Music mode "+(on?"ON":"OFF")); } }
    Save(); Status(); }
   if(cmd=="status") Status();
  }
  public static void StartBackground(){
   Load();
   var t1=new Thread(CaptureLoop); t1.IsBackground=true; t1.SetApartmentState(ApartmentState.MTA); t1.Start();
   var t2=new Thread(LightLoop); t2.IsBackground=true; t2.Start();
  }
  public static void Serve(int port){
   var hl=new HttpListener(); hl.Prefixes.Add("http://127.0.0.1:"+port+"/"); hl.Prefixes.Add("http://localhost:"+port+"/"); hl.Start();
   Console.WriteLine("Ready. Music mode is "+(MusicOn?"ON":"OFF")+" - control it from the Keyboard Control page. Keep this window open (minimized is fine).");
   while(Running){
    var ctx=hl.GetContext();
    if(ctx.Request.IsWebSocketRequest){ Task.Run(async()=>{ try{
       var wsc=await ctx.AcceptWebSocketAsync(null); var ws=wsc.WebSocket; lock(clients) clients.Add(ws); Status();
       var buf=new byte[4096];
       while(ws.State==WebSocketState.Open){ var r=await ws.ReceiveAsync(new ArraySegment<byte>(buf),CancellationToken.None);
         if(r.MessageType==WebSocketMessageType.Close) break; if(r.MessageType==WebSocketMessageType.Text) Handle(Encoding.UTF8.GetString(buf,0,r.Count)); }
      }catch{} }); }
    else { var body=Encoding.UTF8.GetBytes("K980 music helper is running. Listening to: "+DeviceName);
      ctx.Response.Headers.Add("Access-Control-Allow-Origin","*"); ctx.Response.Headers.Add("Access-Control-Allow-Private-Network","true");
      ctx.Response.OutputStream.Write(body,0,body.Length); ctx.Response.Close(); }
   }
  }
 }
}
'@
$src=$src.Replace('using System.IO;','using System.IO; using System.Text.RegularExpressions;')
Add-Type -TypeDefinition $src
$host.UI.RawUI.WindowTitle='K980 Music Helper'
Write-Host 'K980 Music Helper - makes the K980 lights follow your PC sound, even with the page closed (stays on this computer).'
[K980Music.Helper]::StartBackground()
try{ [K980Music.Helper]::Serve($Port) } catch { Write-Host "Could not start: $($_.Exception.Message)"; Write-Host 'Is the helper already running in another window?'; Read-Host 'Press Enter to close' }
