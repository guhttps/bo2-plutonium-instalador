using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Collections.Generic;

// Local HTTP fixture with range requests; never contacts an external service.
public sealed class Bo2DownloadTestServer : IDisposable {
    private readonly TcpListener listener;
    private readonly Thread thread;
    private volatile bool stopping;
    public readonly Dictionary<string, byte[]> Files = new Dictionary<string, byte[]>();
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public Bo2DownloadTestServer() {
        Files["a.bin"] = MakeBytes(256 * 1024, 11);
        Files["b.bin"] = MakeBytes(1024 * 1024, 29);
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        thread = new Thread(Run); thread.IsBackground = true; thread.Start();
    }
    private static byte[] MakeBytes(int count,int seed) {
        var bytes = new byte[count];
        for (int i=0; i<count; i++) bytes[i]=(byte)((i+seed)%251);
        return bytes;
    }
    private void Run() {
        while (!stopping) {
            try { var client=listener.AcceptTcpClient(); ThreadPool.QueueUserWorkItem(delegate { Serve(client); }); }
            catch { if (stopping) return; }
        }
    }
    private void Serve(TcpClient client) {
        using(client) {
            try {
                client.ReceiveTimeout=3000; client.SendTimeout=3000;
                using(var stream=client.GetStream())
                using(var reader=new StreamReader(stream,Encoding.ASCII,false,1024,true)) {
                    string request=reader.ReadLine(); if(request==null) return;
                    string[] words=request.Split(' ');
                    string name=words[1].TrimStart('/').Split('?')[0];
                    string line,range=null;
                    while(!string.IsNullOrEmpty(line=reader.ReadLine()))
                        if(line.StartsWith("Range:",StringComparison.OrdinalIgnoreCase)) range=line.Substring(6).Trim();
                    byte[] data;
                    if(!Files.TryGetValue(name,out data)) {
                        byte[] missing=Encoding.ASCII.GetBytes("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                        stream.Write(missing,0,missing.Length); return;
                    }
                    int start=0,end=data.Length-1;
                    if(range!=null) {
                        string[] positions=range.Substring(6).Split('-');
                        start=int.Parse(positions[0]);
                        if(positions.Length>1 && positions[1].Length>0) end=Math.Min(end,int.Parse(positions[1]));
                    }
                    string header="HTTP/1.1 "+(range==null?"200 OK":"206 Partial Content")+"\r\nContent-Length: "+(end-start+1)+"\r\nAccept-Ranges: bytes\r\nConnection: close\r\n";
                    if(range!=null) header+="Content-Range: bytes "+start+"-"+end+"/"+data.Length+"\r\n";
                    byte[] encoded=Encoding.ASCII.GetBytes(header+"\r\n"); stream.Write(encoded,0,encoded.Length);
                    if(words[0]=="HEAD") return;
                    for(int offset=start;offset<=end && !stopping;) {
                        int count=Math.Min(8192,end-offset+1); stream.Write(data,offset,count); offset+=count;
                        Thread.Sleep(12);
                    }
                }
            } catch(IOException) { } catch(SocketException) { } catch(ObjectDisposedException) { }
        }
    }
    public static void CancelAfter(string path,int milliseconds) {
        var cancel=new Thread(delegate() { Thread.Sleep(milliseconds); try { File.WriteAllText(path,"cancelar"); } catch(IOException) { } });
        cancel.IsBackground=true; cancel.Start();
    }
    public void Dispose() { stopping=true; listener.Stop(); thread.Join(1000); }
}
