using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;

// Validates game data against the piece hashes of the original T6 torrent.
// No network operations or native game code run in this verifier.
public sealed class Bo2TorrentFile {
    public string Path;
    public long Length;
}
public sealed class Bo2Torrent {
    public string Name;
    public string InfoHash;
    public long TotalLength;
    public int PieceLength;
    public byte[] Pieces;
    public List<Bo2TorrentFile> Files = new List<Bo2TorrentFile>();

    private sealed class Decoder {
        private byte[] data;
        private int pos;
        public int InfoStart, InfoEnd;
        public Decoder(byte[] input) { data = input; }
        private void Require(bool condition) {
            if (!condition) throw new InvalidDataException("Torrent malformado.");
        }
        public object Read(int depth) {
            Require(depth < 32 && pos < data.Length);
            byte token = data[pos];
            if (token == (byte)'i') {
                int start = ++pos;
                while (pos < data.Length && data[pos] != (byte)'e') pos++;
                Require(pos < data.Length);
                long value = long.Parse(Encoding.ASCII.GetString(data, start, pos - start));
                pos++;
                return value;
            }
            if (token == (byte)'l') {
                pos++;
                var list = new List<object>();
                while (pos < data.Length && data[pos] != (byte)'e') list.Add(Read(depth + 1));
                Require(pos < data.Length);
                pos++;
                return list;
            }
            if (token == (byte)'d') {
                pos++;
                var dict = new Dictionary<string, object>(StringComparer.Ordinal);
                while (pos < data.Length && data[pos] != (byte)'e') {
                    string key = Encoding.UTF8.GetString((byte[])Read(depth + 1));
                    int start = pos;
                    object value = Read(depth + 1);
                    if (depth == 0 && key == "info") { InfoStart = start; InfoEnd = pos; }
                    dict.Add(key, value);
                }
                Require(pos < data.Length);
                pos++;
                return dict;
            }
            Require(token >= (byte)'0' && token <= (byte)'9');
            int numberStart = pos;
            while (pos < data.Length && data[pos] >= (byte)'0' && data[pos] <= (byte)'9') pos++;
            Require(pos < data.Length && data[pos] == (byte)':');
            int length = int.Parse(Encoding.ASCII.GetString(data, numberStart, pos - numberStart));
            pos++;
            Require(length >= 0 && length <= data.Length - pos);
            byte[] bytes = new byte[length];
            Buffer.BlockCopy(data, pos, bytes, 0, length);
            pos += length;
            return bytes;
        }
    }

    public static Bo2Torrent Load(string path) {
        byte[] raw = File.ReadAllBytes(path);
        var decoder = new Decoder(raw);
        var root = (Dictionary<string, object>)decoder.Read(0);
        var info = (Dictionary<string, object>)root["info"];
        var torrent = new Bo2Torrent();
        using (var sha1 = SHA1.Create()) {
            torrent.InfoHash = BitConverter.ToString(sha1.ComputeHash(raw, decoder.InfoStart,
                decoder.InfoEnd - decoder.InfoStart)).Replace("-", "").ToLowerInvariant();
        }
        torrent.Name = Encoding.UTF8.GetString((byte[])info["name"]);
        CheckSegment(torrent.Name);
        torrent.PieceLength = checked((int)(long)info["piece length"]);
        if (torrent.PieceLength <= 0 || torrent.PieceLength > 16 * 1024 * 1024)
            throw new InvalidDataException("Tamanho de bloco invalido.");
        torrent.Pieces = (byte[])info["pieces"];
        foreach (var item in (List<object>)info["files"]) {
            var record = (Dictionary<string, object>)item;
            var segments = new List<string>();
            foreach (var part in (List<object>)record["path"]) {
                string segment = Encoding.UTF8.GetString((byte[])part);
                CheckSegment(segment);
                segments.Add(segment);
            }
            long length = (long)record["length"];
            if (length < 0 || segments.Count == 0) throw new InvalidDataException("Arquivo invalido.");
            torrent.Files.Add(new Bo2TorrentFile { Path = string.Join("/", segments.ToArray()), Length = length });
            torrent.TotalLength = checked(torrent.TotalLength + length);
        }
        long pieceCount = (torrent.TotalLength + torrent.PieceLength - 1) / torrent.PieceLength;
        if (torrent.Pieces.Length != pieceCount * 20) throw new InvalidDataException("Hashes de blocos incompletos.");
        return torrent;
    }

    private static void CheckSegment(string segment) {
        if (string.IsNullOrEmpty(segment) || segment == "." || segment == ".." ||
            segment.IndexOfAny(new char[] {'/', '\\', ':', '\r', '\n', '\0'}) >= 0)
            throw new InvalidDataException("Caminho inseguro no torrent.");
    }

    public void Verify(string parentDirectory, Action<long, long> progress) {
        string root = Path.Combine(parentDirectory, Name);
        foreach (var entry in Files) {
            var file = new FileInfo(Path.Combine(root, entry.Path.Replace('/', Path.DirectorySeparatorChar)));
            if (!file.Exists || file.Length != entry.Length)
                throw new InvalidDataException("Arquivo ausente ou incompleto: " + entry.Path);
        }
        byte[] buffer = new byte[PieceLength];
        int used = 0, piece = 0;
        long processed = 0;
        using (var sha1 = SHA1.Create()) {
            foreach (var entry in Files) {
                using (var stream = File.OpenRead(Path.Combine(root, entry.Path.Replace('/', Path.DirectorySeparatorChar)))) {
                    long remaining = entry.Length;
                    while (remaining > 0) {
                        int count = stream.Read(buffer, used, (int)Math.Min(remaining, buffer.Length - used));
                        if (count == 0) throw new EndOfStreamException(entry.Path);
                        remaining -= count;
                        processed += count;
                        used += count;
                        if (used == buffer.Length || processed == TotalLength) {
                            byte[] hash = sha1.ComputeHash(buffer, 0, used);
                            for (int i = 0; i < hash.Length; i++) {
                                if (hash[i] != Pieces[piece * 20 + i])
                                    throw new InvalidDataException("Bloco " + piece + " invalido. Execute o instalador novamente para reparar.");
                            }
                            used = 0;
                            piece++;
                            if (progress != null && (piece % 256 == 0 || processed == TotalLength))
                                progress(processed, TotalLength);
                        }
                    }
                }
            }
        }
        if (piece * 20 != Pieces.Length) throw new InvalidDataException("Verificacao incompleta.");
    }
}
