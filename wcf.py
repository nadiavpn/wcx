import subprocess
import os
import shutil
import urllib.request

def download_self():
    """Mengunduh wcf.py ke /usr/bin/ jika belum ada."""
    target_path = "/usr/bin/wcf.py"
    url = "https://raw.githubusercontent.com/nadiavpn/wcx/main/wcf.py"
    
    if not os.path.exists(target_path):
        print(f"Mengunduh wcf.py ke {target_path}...")
        try:
            urllib.request.urlretrieve(url, target_path)
            subprocess.run(['chmod', '+x', target_path], check=True)
            print(f"Berhasil mengunduh dan memberikan izin eksekusi pada {target_path}")
        except Exception as e:
            print(f"Gagal mengunduh atau memberikan izin pada wcf.py: {e}")
            exit(1)

def main():
    # Membersihkan layar terminal
    os.system('clear' if os.name == 'posix' else 'cls')

    # Tentukan direktori tujuan
    TARGET_DIR = "/usr/bin/wcx"

    # Hapus direktori wcx jika sudah ada
    if os.path.exists(TARGET_DIR):
        print(f"Menghapus direktori {TARGET_DIR} yang sudah ada...")
        try:
            shutil.rmtree(TARGET_DIR)
        except Exception as e:
            print(f"Gagal menghapus direktori {TARGET_DIR}: {e}")
            exit(1)

    # Clone repositori ke direktori tujuan
    print(f"Mengunduh repositori ke {TARGET_DIR}...")
    try:
        subprocess.run(['git', 'clone', 'https://github.com/nadiavpn/wcx.git', TARGET_DIR], check=True)
    except subprocess.CalledProcessError:
        print("Gagal mengunduh repositori. Pastikan URL benar dan koneksi internet stabil.")
        exit(1)

    # Memberikan izin eksekusi pada semua file di direktori wcx
    print(f"Memberikan izin eksekusi pada semua file di {TARGET_DIR}...")
    for root, dirs, files in os.walk(TARGET_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            print(f"Memberikan izin eksekusi pada {file_path}...")
            try:
                subprocess.run(['chmod', '+x', file_path], check=True)
            except subprocess.CalledProcessError:
                print(f"Gagal memberikan izin eksekusi pada {file_path}.")
                exit(1)

    print(f"Instalasi selesai. Semua file berada di {TARGET_DIR}.")

if __name__ == "__main__":
    download_self()  # Mengunduh skrip itu sendiri jika belum ada
    main()
