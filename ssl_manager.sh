#!/bin/bash

# ====================================================================
#                         Nama Pembuat Script
# ====================================================================
# By: NADIA VPN
# Tanggal: $(date '+%A, %d %B %Y')
# Waktu: $(date '+%H:%M:%S')
# Deskripsi: Skrip ini digunakan untuk mengelola SSL (certificate) dari domain yang terdaftar di Cloudflare
# ====================================================================

# Warna
NC='\e[0m'
BLACK='\e[0;30m';  RED='\e[1;31m';    GREEN='\e[0;32m'
YELLOW='\e[1;33m'; BLUE='\e[0;34m';   MAGENTA='\e[0;35m'
CYAN='\e[0;36m';   WHITE='\e[0;37m'
BBLACK='\e[1;30m'; BRED='\e[1;31m';   BGREEN='\e[1;32m'
BYELLOW='\e[1;33m';BBLUE='\e[1;34m';  BMAGENTA='\e[1;35m'
BCYAN='\e[1;36m';  BWHITE='\e[1;37m'

# File log
LOG_FILE="ssl_manager.log"
BACKUP_DIR="backup"

# Fungsi untuk logging
log_activity() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Fungsi untuk menampilkan header
display_header() {
    clear
    echo -e "${BCYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    printf "║  %-46s  ║\n" "NADIA VPN MANAGER PRO"
    echo "╠══════════════════════════════════════════════════╣"
    printf "║ %-20s:${BWHITE}%-28s${BCYAN}║\n" "Tanggal" "$(date '+%A, %d %B %Y')"
    printf "║ %-20s:${BWHITE}%-28s${BCYAN}║\n" "Waktu" "$(date '+%H:%M:%S')"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Membaca file akun.txt
if [ -f akun.txt ]; then
    source akun.txt
else
    echo -e "${RED}File akun.txt tidak ditemukan!${NC}"
    log_activity "Error: File akun.txt tidak ditemukan"
    exit 1
fi

# Pastikan variabel dari akun.txt terdefinisi
if [[ -z "$AUTH_EMAIL" || -z "$AUTH_KEY" || -z "$ZONE_ID" ]]; then
    echo -e "${RED}Variabel AUTH_EMAIL, AUTH_KEY, atau ZONE_ID tidak ditemukan di akun.txt!${NC}"
    log_activity "Error: Variabel AUTH_EMAIL, AUTH_KEY, atau ZONE_ID tidak ditemukan"
    exit 1
fi

# Fungsi untuk backup konfigurasi
backup_config() {
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    cp "akun.txt" "$BACKUP_DIR/akun_$timestamp.txt" 2>/dev/null
    log_activity "Membuat backup: akun_$timestamp.txt"
}

# Fungsi untuk membersihkan file sementara
cleanup_temp_files() {
    rm -f cert_packs_response_*.json cert_packs_response.json delete_response.json 2>/dev/null
    log_activity "Membersihkan file sementara"
}

# Fungsi untuk memeriksa respons API
check_api_response() {
    local response_file=$1
    local page=$2
    if ! jq -e '.' "$response_file" >/dev/null 2>&1; then
        echo -e "${RED}Respons API untuk halaman $page tidak valid (bukan JSON).${NC}"
        log_activity "Error: Respons API untuk halaman $page tidak valid (bukan JSON)"
        return 1
    fi
    if ! jq -e '.success' "$response_file" >/dev/null 2>&1; then
        error_message=$(jq -r '.errors[]?.message // "Tidak ada pesan error"' "$response_file")
        error_code=$(jq -r '.errors[]?.code // "Tidak ada kode error"' "$response_file")
        echo -e "${RED}Gagal mendapatkan daftar certificate packs untuk halaman $page. Error: $error_message (Kode: $error_code)${NC}"
        log_activity "Error: Gagal mendapatkan daftar certificate packs untuk halaman $page. Error: $error_message (Kode: $error_code)"
        return 1
    fi
    return 0
}

# Fungsi untuk mendapatkan semua certificate packs dengan paginasi
get_all_certificate_packs() {
    local page=1
    local per_page=20  # Menggunakan nilai yang terbukti bekerja
    local all_packs=()

    log_activity "Memulai pengambilan certificate packs dengan per_page=$per_page"

    while true; do
        RESPONSE=$(curl -s -w "%{http_code}" -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/ssl/certificate_packs?page=$page&per_page=$per_page" \
            -H "X-Auth-Email: $AUTH_EMAIL" \
            -H "X-Auth-Key: $AUTH_KEY" \
            -H "Content-Type: application/json" \
            -o "cert_packs_response_$page.json")
        http_code=$(echo "$RESPONSE" | tail -n1)

        if [ "$http_code" -ne 200 ]; then
            echo -e "${RED}Gagal mendapatkan daftar certificate packs untuk halaman $page. Kode HTTP: $http_code${NC}"
            log_activity "Error: Gagal mendapatkan daftar certificate packs untuk halaman $page (HTTP $http_code)"
            return 1
        fi

        # Periksa respons API
        if ! check_api_response "cert_packs_response_$page.json" "$page"; then
            return 1
        fi

        # Ambil hasil dari halaman saat ini
        packs=$(jq -c '.result[]' "cert_packs_response_$page.json" 2>/dev/null)
        if [ -z "$packs" ]; then
            log_activity "Tidak ada certificate packs di halaman $page, menghentikan paginasi"
            break  # Tidak ada hasil lagi, keluar dari loop
        fi

        # Tambahkan setiap pack ke array
        while IFS= read -r pack; do
            all_packs+=("$pack")
        done <<< "$packs"

        log_activity "Berhasil mengambil $(echo "$packs" | wc -l) certificate packs dari halaman $page"
        ((page++))
        sleep 2  # Penundaan untuk mencegah rate limiting
    done

    # Buat file JSON gabungan
    if [ ${#all_packs[@]} -eq 0 ]; then
        echo "[]" > cert_packs_response.json
        log_activity "Tidak ada certificate packs untuk digabungkan"
    else
        echo "[" > cert_packs_response.json
        for i in "${!all_packs[@]}"; do
            echo "${all_packs[$i]}" >> cert_packs_response.json
            if [ $i -lt $((${#all_packs[@]} - 1)) ]; then
                echo "," >> cert_packs_response.json
            fi
        done
        echo "]" >> cert_packs_response.json
        log_activity "Berhasil menggabungkan ${#all_packs[@]} certificate packs ke cert_packs_response.json"
    fi

    # Periksa apakah file JSON valid
    if ! jq -e '.' cert_packs_response.json >/dev/null 2>&1; then
        echo -e "${RED}Gagal menggabungkan hasil certificate packs. File JSON tidak valid.${NC}"
        log_activity "Error: Gagal menggabungkan hasil certificate packs (JSON tidak valid)"
        return 1
    fi

    return 0
}

# Fungsi untuk menampilkan daftar certificate packs
get_certificate_packs() {
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}           Daftar Certificate Packs                 ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${CYAN}Mendapatkan daftar certificate packs...${NC}"

    if ! get_all_certificate_packs; then
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Hitung jumlah certificate packs dari file JSON
    TOTAL_PACKS=$(jq -r '. | length' cert_packs_response.json 2>/dev/null || echo 0)

    if [ "$TOTAL_PACKS" -gt 0 ]; then
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        echo -e "${GREEN}Daftar Certificate Packs:${NC}"
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        
        # Menampilkan setiap certificate pack
        PACK_COUNT=0
        jq -c '.[]' cert_packs_response.json | while read -r PACK; do
            ((PACK_COUNT++))
            ID=$(echo "$PACK" | jq -r '.id')
            STATUS=$(echo "$PACK" | jq -r '.status')
            HOSTS=$(echo "$PACK" | jq -r '.hosts[]' | tr '\n' ',' | sed 's/,$//')
            
            echo -e "${YELLOW}$PACK_COUNT. ID: $ID (Status: $STATUS)${NC}"
            echo -e "${CYAN}   Domains: ${YELLOW}$HOSTS${NC}"
        done
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        echo -e "${GREEN}Total: $TOTAL_PACKS certificate packs ditemukan.${NC}"
    else
        echo -e "${YELLOW}Tidak ada certificate packs yang ditemukan di zona ini.${NC}"
        echo -e "${GREEN}Total: 0 certificate packs ditemukan.${NC}"
        log_activity "Tidak ada certificate packs yang ditemukan"
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    read -p "Tekan Enter untuk kembali ke menu utama..." dummy
}

# Fungsi untuk menghapus certificate packs
delete_certificate_packs() {
    backup_config
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}           Menu Hapus Certificate Packs             ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${CYAN}Mendapatkan daftar certificate packs...${NC}"

    # Ambil daftar certificate packs dengan paginasi
    if ! get_all_certificate_packs; then
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Hitung jumlah certificate packs dari file JSON
    TOTAL_PACKS=$(jq -r '. | length' cert_packs_response.json 2>/dev/null || echo 0)

    # Ambil ID dan deskripsi certificate packs
    pack_ids=$(jq -r '.[] | .id' < cert_packs_response.json)
    pack_descriptions=$(jq -r '.[] | "\(.id) (Status: \(.status), Domains: \(.hosts | join(", ")))"' < cert_packs_response.json)

    if [ -z "$pack_ids" ] || [ "$TOTAL_PACKS" -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada certificate packs yang tersedia.${NC}"
        echo -e "${GREEN}Total: 0 certificate packs ditemukan.${NC}"
        log_activity "Tidak ada certificate packs yang tersedia"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Tampilkan daftar certificate packs
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${GREEN}Daftar Certificate Packs:${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    IFS=$'\n' read -d '' -r -a pack_list <<< "$pack_descriptions"
    for i in "${!pack_list[@]}"; do
        echo -e "${YELLOW}$((i + 1)). ${pack_list[$i]}${NC}"
    done
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${GREEN}Total: $TOTAL_PACKS certificate packs ditemukan.${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${YELLOW}1. Hapus satu certificate pack${NC}"
    echo -e "${YELLOW}2. Hapus semua certificate packs${NC}"
    echo -e "${RED}0. Kembali${NC}"
    echo -e "${CYAN}=====================================================${NC}"

    read -p "Pilih opsi (1/2/0): " choice

    case $choice in
        1)
            echo -e "${CYAN}-----------------------------------------------------${NC}"
            read -p "Pilih nomor certificate pack untuk dihapus (1-${#pack_list[@]}): " pack_choice
            if [[ ! "$pack_choice" =~ ^[0-9]+$ ]] || [ "$pack_choice" -lt 1 ] || [ "$pack_choice" -gt "${#pack_list[@]}" ]; then
                echo -e "${RED}Pilihan tidak valid!${NC}"
                log_activity "Error: Pilihan certificate pack tidak valid ($pack_choice)"
                read -p "Tekan Enter untuk kembali..."
                return
            fi

            # Ambil ID certificate pack yang dipilih
            IFS=$'\n' read -d '' -r -a id_list <<< "$pack_ids"
            selected_pack_id=${id_list[$((pack_choice - 1))]}
            selected_pack=${pack_list[$((pack_choice - 1))]}

            # Hapus certificate pack
            delete_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/ssl/certificate_packs/$selected_pack_id"
            delete_response=$(curl -s -w "%{http_code}" -o delete_response.json -X DELETE \
                -H "X-Auth-Email: $AUTH_EMAIL" \
                -H "X-Auth-Key: $AUTH_KEY" \
                -H "Content-Type: application/json" \
                "$delete_url")
            delete_httpCode=$(echo "$delete_response" | tail -n1)

            if [ "$delete_httpCode" -eq 200 ]; then
                echo -e "${GREEN}Certificate pack $selected_pack berhasil dihapus.${NC}"
                log_activity "Berhasil menghapus certificate pack $selected_pack (ID $selected_pack_id)"
            else
                echo -e "${RED}Gagal menghapus certificate pack $selected_pack (HTTP $delete_httpCode)${NC}"
                log_activity "Error: Gagal menghapus certificate pack $selected_pack (HTTP $delete_httpCode)"
            fi
            ;;
        2)
            delete_count=0
            failed_count=0
            IFS=$'\n' read -d '' -r -a id_list <<< "$pack_ids"
            for i in "${!id_list[@]}"; do
                pack_id=${id_list[$i]}
                pack_name=${pack_list[$i]}
                delete_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/ssl/certificate_packs/$pack_id"
                delete_response=$(curl -s -w "%{http_code}" -o delete_response.json -X DELETE \
                    -H "X-Auth-Email: $AUTH_EMAIL" \
                    -H "X-Auth-Key: $AUTH_KEY" \
                    -H "Content-Type: application/json" \
                    "$delete_url")
                delete_httpCode=$(echo "$delete_response" | tail -n1)

                if [ "$delete_httpCode" -eq 200 ]; then
                    echo -e "${GREEN}Certificate pack $pack_name berhasil dihapus.${NC}"
                    log_activity "Berhasil menghapus certificate pack $pack_name (ID $pack_id)"
                    delete_count=$((delete_count + 1))
                else
                    echo -e "${RED}Gagal menghapus certificate pack $pack_name (HTTP $delete_httpCode)${NC}"
                    log_activity "Error: Gagal menghapus certificate pack $pack_name (HTTP $delete_httpCode)"
                    failed_count=$((failed_count + 1))
                fi
                sleep 2  # Penundaan untuk mencegah rate limiting
            done
            echo -e "${GREEN}$delete_count certificate pack berhasil dihapus.${NC}"
            if [ "$failed_count" -gt 0 ]; then
                echo -e "${RED}$failed_count certificate pack gagal dihapus.${NC}"
            fi
            log_activity "Hasil penghapusan certificate packs: $delete_count berhasil, $failed_count gagal"
            ;;
        0)
            echo -e "${RED}Kembali ke menu utama...${NC}"
            log_activity "Kembali dari menu hapus certificate packs"
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            log_activity "Error: Pilihan opsi hapus certificate pack tidak valid ($choice)"
            ;;
    esac
    cleanup_temp_files
    read -p "Tekan Enter untuk kembali..."
}

# Menu utama
while true; do
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}         Cloudflare SSL Management                  ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}1. Tampilkan daftar certificate packs${NC}"
    echo -e "${YELLOW}2. Hapus certificate packs SSL${NC}"
    echo -e "${RED}0. Keluar${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    read -p "Pilih opsi (1/2/0): " pilihan

    case $pilihan in
        1)
            log_activity "Menampilkan daftar certificate packs"
            get_certificate_packs
            ;;
        2)
            log_activity "Memulai penghapusan certificate packs"
            delete_certificate_packs
            ;;
        0)
            echo -e "${RED}Keluar dari menu...${NC}"
            log_activity "Keluar dari aplikasi"
            cleanup_temp_files
            exit 0
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            log_activity "Error: Pilihan menu tidak valid ($pilihan)"
            read -p "Tekan Enter untuk melanjutkan..."
            ;;
    esac
done