using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace DirectFoldersZhTW
{
    public sealed class ResourceEntry
    {
        public int Type;
        public string Name;
        public int Id;
        public ushort Language;
        public byte[] Data;
    }

    // Compatible with Windows PowerShell 5.1 and its built-in .NET Framework compiler.
    public static class Resources
    {
        private delegate bool NameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
        private delegate bool LanguageCallback(IntPtr module, IntPtr type, IntPtr name, ushort language, IntPtr param);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumResourceNames(IntPtr module, IntPtr type, NameCallback callback, IntPtr param);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, LanguageCallback callback, IntPtr param);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindResourceEx(IntPtr module, IntPtr type, IntPtr name, ushort language);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SizeofResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LockResource(IntPtr resource);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr BeginUpdateResource(string path, bool deleteExisting);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool UpdateResource(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool EndUpdateResource(IntPtr update, bool discard);

        private static IntPtr NamePointer(ResourceEntry entry)
        {
            return entry.Name == null ? new IntPtr(entry.Id) : Marshal.StringToHGlobalUni(entry.Name);
        }

        public static ResourceEntry[] Read(string path)
        {
            // LOAD_LIBRARY_AS_DATAFILE: inspect resources without executing application code.
            IntPtr module = LoadLibraryEx(path, IntPtr.Zero, 2);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            var result = new List<ResourceEntry>();
            try
            {
                foreach (int type in new int[] { 6, 10 })
                {
                    var names = new List<ResourceEntry>();
                    NameCallback nameCallback = delegate(IntPtr h, IntPtr t, IntPtr name, IntPtr p)
                    {
                        long value = name.ToInt64();
                        names.Add(new ResourceEntry {
                            Type = type,
                            Id = value >= 0 && value <= 65535 ? (int)value : 0,
                            Name = value >= 0 && value <= 65535 ? null : Marshal.PtrToStringUni(name)
                        });
                        return true;
                    };
                    if (!EnumResourceNames(module, new IntPtr(type), nameCallback, IntPtr.Zero))
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error != 1813) throw new Win32Exception(error);
                    }
                    foreach (ResourceEntry name in names)
                    {
                        IntPtr pointer = NamePointer(name);
                        try
                        {
                            var languages = new List<ushort>();
                            LanguageCallback languageCallback = delegate(IntPtr h, IntPtr t, IntPtr n, ushort language, IntPtr p)
                            {
                                languages.Add(language);
                                return true;
                            };
                            if (!EnumResourceLanguages(module, new IntPtr(type), pointer, languageCallback, IntPtr.Zero))
                                throw new Win32Exception(Marshal.GetLastWin32Error());
                            foreach (ushort language in languages)
                            {
                                IntPtr resource = FindResourceEx(module, new IntPtr(type), pointer, language);
                                if (resource == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                                uint size = SizeofResource(module, resource);
                                IntPtr loaded = LoadResource(module, resource);
                                IntPtr address = LockResource(loaded);
                                if (size > 0 && address == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                                byte[] bytes = new byte[checked((int)size)];
                                if (size > 0) Marshal.Copy(address, bytes, 0, bytes.Length);
                                result.Add(new ResourceEntry {
                                    Type = type, Name = name.Name, Id = name.Id,
                                    Language = language, Data = bytes
                                });
                            }
                        }
                        finally { if (name.Name != null) Marshal.FreeHGlobal(pointer); }
                    }
                }
            }
            finally { FreeLibrary(module); }
            return result.ToArray();
        }

        public static void Write(string path, ResourceEntry[] resources)
        {
            IntPtr update = BeginUpdateResource(path, false);
            if (update == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            bool committed = false;
            try
            {
                foreach (ResourceEntry entry in resources)
                {
                    IntPtr name = NamePointer(entry);
                    try
                    {
                        if (!UpdateResource(update, new IntPtr(entry.Type), name, entry.Language, entry.Data, (uint)entry.Data.Length))
                            throw new Win32Exception(Marshal.GetLastWin32Error());
                    }
                    finally { if (entry.Name != null) Marshal.FreeHGlobal(name); }
                }
                if (!EndUpdateResource(update, false)) throw new Win32Exception(Marshal.GetLastWin32Error());
                committed = true;
            }
            finally { if (!committed) EndUpdateResource(update, true); }
        }

        public static bool Equal(byte[] a, byte[] b)
        {
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        public static byte[] Replace(byte[] input, int offset, int length, byte[] replacement)
        {
            if (offset < 0 || length < 0 || offset > input.Length - length)
                throw new ArgumentOutOfRangeException("offset");
            byte[] output = new byte[checked(input.Length - length + replacement.Length)];
            Buffer.BlockCopy(input, 0, output, 0, offset);
            Buffer.BlockCopy(replacement, 0, output, offset, replacement.Length);
            Buffer.BlockCopy(input, offset + length, output, offset + replacement.Length, input.Length - offset - length);
            return output;
        }
    }
}
