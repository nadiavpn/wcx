#!/bin/bash

# Warna
NC='\e[0m'
BLACK='\e[0;30m'; RED='\e[1;31m'; GREEN='\e[0;32m'
YELLOW='\e[1;33m'; BLUE='\e[0;34m'; MAGENTA='\e[0;35m'
CYAN='\e[0;36m'; WHITE='\e[0;37m'
BBLACK='\e[1;30m'; BRED='\e[1;31m'; BGREEN='\e[1;32m'
BYELLOW='\e[1;33m'; BBLUE='\e[1;34m'; BMAGENTA='\e[1;35m'
BCYAN='\e[1;36m'; BWHITE='\e[1;37m'

# File log
LOG_FILE="vpn_manager.log"
BACKUP_DIR="backup"

# Fungsi untuk logging
log_activity() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Fungsi untuk menampilkan header dengan animasi
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
    echo -e "${GREEN}Loading...${NC}"
    for i in {1..3}; do
        echo -n "."
        sleep 0.2
    done
    echo
}

# Cek dependensi
check_dependencies() {
    local deps=("curl" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}$dep tidak ditemukan. Menginstal...${NC}"
            sudo apt-get update && sudo apt-get install -y "$dep"
            log_activity "Menginstal dependensi: $dep"
        fi
    done
}

# Backup file konfigurasi
backup_config() {
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    cp "$AKUN_FILE" "$BACKUP_DIR/akun_$timestamp.txt" 2>/dev/null
    cp "$DOMAIN_FILE" "$BACKUP_DIR/domain_$timestamp.txt" 2>/dev/null
    log_activity "Membuat backup: akun_$timestamp.txt, domain_$timestamp.txt"
}

# Cleanup file sementara
cleanup_temp_files() {
    rm -f response.json check_response.json worker_domains_response.json delete_response.json dns_records_response.json zone_response.json 2>/dev/null
    log_activity "Membersihkan file sementara"
}

# File konfigurasi
AKUN_FILE="akun.txt"
DOMAIN_FILE="domain.txt"
CONFIG_FILE="config.ini"

# Membaca konfigurasi global
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    DEFAULT_EDITOR="nano"
    API_DELAY=1
    echo "DEFAULT_EDITOR=$DEFAULT_EDITOR" > "$CONFIG_FILE"
    echo "API_DELAY=$API_DELAY" >> "$CONFIG_FILE"
    log_activity "Membuat file konfigurasi default: $CONFIG_FILE"
fi

# Cek apakah file akun.txt ada
if [ ! -f "$AKUN_FILE" ]; then
    echo -e "${RED}File $AKUN_FILE tidak ditemukan!${NC}"
    log_activity "Error: File $AKUN_FILE tidak ditemukan"
    exit 1
fi

# Membaca konfigurasi dari akun.txt
source "$AKUN_FILE"

# Membaca konfigurasi dari akun.txt
source "$AKUN_FILE"

# Validasi konfigurasi
if [ -z "$AUTH_EMAIL" ] || [ -z "$AUTH_KEY" ] || [ -z "$ACCOUNT_ID" ] || [ -z "$YOUR_NAME" ] || [ -z "$ZONE_ID" ]; then
    echo -e "${RED}Konfigurasi API Cloudflare tidak lengkap. Pastikan file akun.txt berisi semua informasi.${NC}"
    log_activity "Error: Konfigurasi API Cloudflare tidak lengkap"
    exit 1
fi

# Cari file domain.txt
DOMAIN_FILE=$(find / -type f -name "domain.txt" 2>/dev/null | head -n 1)

# Cek apakah file domain.txt ditemukan
if [ -z "$DOMAIN_FILE" ] || [ ! -f "$DOMAIN_FILE" ]; then
    echo -e "${RED}File domain.txt tidak ditemukan di sistem!${NC}"
    log_activity "Error: File domain.txt tidak ditemukan"
    exit 1
fi

echo -e "${GREEN}File domain.txt ditemukan di: $DOMAIN_FILE${NC}"
log_activity "File domain.txt ditemukan di: $DOMAIN_FILE"

# Fungsi untuk validasi input subdomain (diperbarui untuk mendukung *.subdomain)
validate_subdomain() {
    local subdomain=$1
    if [[ "$subdomain" =~ ^\*\.[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || [ "$subdomain" == "*" ]; then
        return 0
    fi
    if [[ ! "$subdomain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
        echo -e "${RED}Subdomain tidak valid. Gunakan karakter alfanumerik, tanda hubung, atau titik (atau *.subdomain atau * untuk wildcard).${NC}"
        return 1
    fi
    return 0
}

# Fungsi untuk validasi target CNAME
validate_cname_target() {
    local target=$1
    if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Target CNAME harus domain, bukan IP${NC}"
        return 1
    fi
    if [[ ! "$target" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        echo -e "${RED}Target CNAME tidak valid${NC}"
        return 1
    fi
    return 0
}

# Fungsi untuk mendapatkan domain utama dari ZONE_ID
get_zone_domain() {
    local zone_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID"
    local zone_response=$(curl -s -w "%{http_code}" -o zone_response.json -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$zone_url")
    local http_code=$(echo "$zone_response" | tail -n1)

    if [ "$http_code" -ne 200 ]; then
        echo -e "${RED}Gagal mendapatkan domain utama (HTTP $http_code)${NC}"
        log_activity "Error: Gagal mendapatkan domain utama (HTTP $http_code)"
        return 1
    fi

    ZONE_DOMAIN=$(jq -r '.result.name' zone_response.json 2>/dev/null)
    if [ -z "$ZONE_DOMAIN" ]; then
        echo -e "${RED}Gagal mendapatkan nama domain${NC}"
        log_activity "Error: Gagal mendapatkan nama domain dari zona"
        return 1
    fi

    log_activity "Domain utama: $ZONE_DOMAIN"
    return 0
}

# Fungsi untuk menambahkan domain
tambah_domain() {
    backup_config
    while true; do
        display_header
        echo -e "${CYAN}=====================================================${NC}"
        echo -e "${GREEN}           Menu Tambah Domain                       ${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        echo -e "${YELLOW}1. Tambah domain manual${NC}"
        echo -e "${YELLOW}2. Tambah domain dari file${NC}"
        echo -e "${RED}0. Kembali${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        read -p "Masukkan nomor opsi (1/2/0): " option
        clear

        case $option in
            1)
                echo -e "${YELLOW}Masukkan subdomain yang ingin ditambahkan (contoh 'www' atau '*' untuk wildcard):${NC}"
                read inputDomain
                if ! validate_subdomain "$inputDomain"; then
                    read -p "Tekan Enter untuk kembali..."
                    continue
                fi

                customDomain="${inputDomain}.${SBD_SUFFIX}"
                log_activity "Memproses penambahan domain manual: $customDomain"

                check_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$customDomain"
                check_response=$(curl -s -w "%{http_code}" -o check_response.json -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$check_url")
                check_httpCode=$(echo "$check_response" | tail -n1)

                if [ "$check_httpCode" -eq 200 ]; then
                    if jq -e '.success == true' check_response.json >/dev/null 2>&1; then
                        existing_domains=$(jq '.result | length' < check_response.json)
                        if [ "$existing_domains" -gt 0 ]; then
                            echo -e "${YELLOW}Domain $customDomain sudah ada, melewati penambahan.${NC}"
                            log_activity "Domain $customDomain sudah ada"
                        else
                            if tambah_domain_manual "$customDomain"; then
                                success_count=$((success_count + 1))
                            fi
                        fi
                    else
                        echo -e "${RED}Respons API tidak valid untuk domain $customDomain.${NC}"
                        log_activity "Error: Respons API tidak valid untuk $customDomain"
                    fi
                else
                    echo -e "${RED}Gagal memeriksa keberadaan domain $customDomain. Kode HTTP: $check_httpCode${NC}"
                    log_activity "Error: Gagal memeriksa domain $customDomain (HTTP $check_httpCode)"
                fi
                cleanup_temp_files
                read -p "Tekan Enter untuk kembali..."
                ;;
            2)
                echo -e "${YELLOW}Menambahkan domain dari file...${NC}"
                success_count=0
                while IFS= read -r inputDomain; do
                    if [ -z "$inputDomain" ]; then
                        continue
                    fi
                    if ! validate_subdomain "$inputDomain"; then
                        echo -e "${RED}Subdomain $inputDomain tidak valid, melewati...${NC}"
                        continue
                    fi

                    customDomain="${inputDomain}.${SBD_SUFFIX}"
                    echo "Memproses domain: $customDomain"
                    log_activity "Memproses domain dari file: $customDomain"

                    check_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$customDomain"
                    check_response=$(curl -s -w "%{http_code}" -o check_response.json -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$check_url")
                    check_httpCode=$(echo "$check_response" | tail -n1)

                    if [ "$check_httpCode" -eq 200 ]; then
                        if jq -e '.success == true' check_response.json >/dev/null 2>&1; then
                            existing_domains=$(jq '.result | length' < check_response.json)
                            if [ "$existing_domains" -gt 0 ]; then
                                echo -e "${YELLOW}Domain $customDomain sudah ada, melewati penambahan.${NC}"
                                log_activity "Domain $customDomain sudah ada"
                                continue
                            fi
                        else
                            echo -e "${RED}Respons API tidak valid untuk domain $customDomain.${NC}"
                            log_activity "Error: Respons API tidak valid untuk $customDomain"
                            continue
                        fi
                    else
                        echo -e "${RED}Gagal memeriksa keberadaan domain $customDomain. Kode HTTP: $check_httpCode${NC}"
                        log_activity "Error: Gagal memeriksa domain $customDomain (HTTP $check_httpCode)"
                        continue
                    fi

                    if tambah_domain_manual "$customDomain"; then
                        success_count=$((success_count + 1))
                    fi
                    sleep "$API_DELAY"
                done < "$DOMAIN_FILE"

                echo -e "${GREEN}Jumlah domain yang berhasil ditambahkan: $success_count${NC}"
                log_activity "Berhasil menambahkan $success_count domain dari file"
                cleanup_temp_files
                read -p "Tekan Enter untuk kembali..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid. Harap pilih 1, 2, atau 0.${NC}"
                log_activity "Error: Pilihan tidak valid ($option)"
                read -p "Tekan Enter untuk kembali..."
                ;;
        esac
    done
}

# Fungsi untuk menambahkan domain manual
tambah_domain_manual() {
    local customDomain=$1
    data=$(cat <<EOF
{
    "hostname": "$customDomain",
    "zone_id": "$ZONE_ID",
    "service": "$WORKER_NAME",
    "environment": "production"
}
EOF
)

    URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/domains/records"
    headers=(
        -H "X-Auth-Email: $AUTH_EMAIL"
        -H "X-Auth-Key: $AUTH_KEY"
        -H "Content-Type: application/json"
    )

    response=$(curl -s -w "%{http_code}" -o response.json "${headers[@]}" -X PUT "$URL" -d "$data")
    httpCode=$(echo "$response" | tail -n1)

    if [ "$httpCode" -eq 200 ]; then
        echo -e "${GREEN}Custom domain berhasil ditambahkan: $customDomain${NC}"
        log_activity "Berhasil menambahkan domain: $customDomain"
        return 0
    else
        echo -e "${RED}Gagal menambahkan custom domain $customDomain (HTTP $httpCode)${NC}"
        log_activity "Error: Gagal menambahkan domain $customDomain (HTTP $httpCode)"
        return 1
    fi
}

# Fungsi untuk menghapus domain
hapus_domain() {
    backup_config
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}           Menu Hapus Domain                        ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}Masukkan nama Worker yang ingin dihapus domainnya:${NC}"
    read worker_name

    # Ambil daftar domain dari worker
    worker_domains_url="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/domains?worker_name=$worker_name"
    worker_domains_response=$(curl -s -w "%{http_code}" -o worker_domains_response.json -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$worker_domains_url")
    worker_domains_httpCode=$(echo "$worker_domains_response" | tail -n1)

    if [ "$worker_domains_httpCode" -ne 200 ]; then
        echo -e "${RED}Gagal mengambil daftar domain: HTTP $worker_domains_httpCode${NC}"
        log_activity "Error: Gagal mengambil domain untuk worker $worker_name (HTTP $worker_domains_httpCode)"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Ambil daftar domain
    domain_ids=$(jq -r '.result[] | .id' < worker_domains_response.json)
    domain_names=$(jq -r '.result[] | .hostname' < worker_domains_response.json)

    if [ -z "$domain_ids" ]; then
        echo -e "${YELLOW}Tidak ada domain yang terkait dengan worker $worker_name.${NC}"
        log_activity "Tidak ada domain untuk worker $worker_name"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Tampilkan daftar domain
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${GREEN}Daftar Custom Domain untuk Worker $worker_name:${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    IFS=$'\n' read -d '' -r -a domain_list <<< "$domain_names"
    for i in "${!domain_list[@]}"; do
        echo -e "${YELLOW}$((i + 1)). ${domain_list[$i]}${NC}"
    done
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${YELLOW}1. Hapus satu domain${NC}"
    echo -e "${YELLOW}2. Hapus semua domain${NC}"
    echo -e "${RED}0. Kembali${NC}"
    echo -e "${CYAN}=====================================================${NC}"

    read -p "Pilih opsi (1/2/0): " choice

    case $choice in
        1)
            echo -e "${CYAN}-----------------------------------------------------${NC}"
            read -p "Pilih nomor domain untuk dihapus (1-${#domain_list[@]}): " domain_choice
            if [[ ! "$domain_choice" =~ ^[0-9]+$ ]] || [ "$domain_choice" -lt 1 ] || [ "$domain_choice" -gt "${#domain_list[@]}" ]; then
                echo -e "${RED}Pilihan tidak valid!${NC}"
                log_activity "Error: Pilihan domain tidak valid ($domain_choice)"
                read -p "Tekan Enter untuk kembali..."
                return
            fi

            # Ambil ID domain yang dipilih
            IFS=$'\n' read -d '' -r -a id_list <<< "$domain_ids"
            selected_domain_id=${id_list[$((domain_choice - 1))]}
            selected_domain=${domain_list[$((domain_choice - 1))]}

            # Hapus domain
            delete_url="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/domains/$selected_domain_id"
            delete_response=$(curl -s -w "%{http_code}" -o delete_response.json -X DELETE -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$delete_url")
            delete_httpCode=$(echo "$delete_response" | tail -n1)

            if [ "$delete_httpCode" -eq 200 ]; then
                echo -e "${GREEN}Domain $selected_domain berhasil dihapus.${NC}"
                log_activity "Berhasil menghapus domain $selected_domain (ID $selected_domain_id)"
            else
                echo -e "${RED}Gagal menghapus domain $selected_domain (HTTP $delete_httpCode)${NC}"
                log_activity "Error: Gagal menghapus domain $selected_domain (HTTP $delete_httpCode)"
            fi
            ;;
        2)
            delete_count=0
            failed_count=0
            IFS=$'\n' read -d '' -r -a id_list <<< "$domain_ids"
            for i in "${!id_list[@]}"; do
                domain_id=${id_list[$i]}
                domain_name=${domain_list[$i]}
                delete_url="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/domains/$domain_id"
                delete_response=$(curl -s -w "%{http_code}" -o delete_response.json -X DELETE -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$delete_url")
                delete_httpCode=$(echo "$delete_response" | tail -n1)

                if [ "$delete_httpCode" -eq 200 ]; then
                    echo -e "${GREEN}Domain $domain_name berhasil dihapus.${NC}"
                    log_activity "Berhasil menghapus domain $domain_name (ID $domain_id)"
                    delete_count=$((delete_count + 1))
                else
                    echo -e "${RED}Gagal menghapus domain $domain_name (HTTP $delete_httpCode)${NC}"
                    log_activity "Error: Gagal menghapus domain $domain_name (HTTP $delete_httpCode)"
                    failed_count=$((failed_count + 1))
                fi
                sleep "$API_DELAY"
            done
            echo -e "${GREEN}$delete_count domain berhasil dihapus.${NC}"
            if [ "$failed_count" -gt 0 ]; then
                echo -e "${RED}$failed_count domain gagal dihapus.${NC}"
            fi
            log_activity "Hasil penghapusan: $delete_count berhasil, $failed_count gagal"
            ;;
        0)
            echo -e "${RED}Kembali ke menu utama...${NC}"
            log_activity "Kembali dari menu hapus domain"
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            log_activity "Error: Pilihan opsi hapus domain tidak valid ($choice)"
            ;;
    esac
    cleanup_temp_files
    read -p "Tekan Enter untuk kembali..."
}

# Fungsi untuk membuat worker
buat_worker() {
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}           Menu Buat Worker                         ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}Masukkan nama Worker yang ingin dibuat:${NC}"
    read WORKER_NAME

    WORKER_SCRIPT="
    addEventListener('fetch', event => {
        event.respondWith(handleRequest(event.request))
    })

    async function handleRequest(request) {
        return new Response('Hello from Cloudflare Worker!', { status: 200 })
    }
    "

    URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME"
    response=$(curl -s -w "%{http_code}" -o response.json -X PUT \
        -H "X-Auth-Email: $AUTH_EMAIL" \
        -H "X-Auth-Key: $AUTH_KEY" \
        -H "Content-Type: application/javascript" \
        --data "$WORKER_SCRIPT" \
        "$URL")

    httpCode=$(echo "$response" | tail -n1)
    if [ "$httpCode" -eq 200 ]; then
        echo -e "${GREEN}Worker '$WORKER_NAME' berhasil dibuat/diupdate.${NC}"
        log_activity "Berhasil membuat/update worker: $WORKER_NAME"
    else
        echo -e "${RED}Gagal membuat Worker '$WORKER_NAME' (HTTP $httpCode)${NC}"
        log_activity "Error: Gagal membuat worker $WORKER_NAME (HTTP $httpCode)"
    fi
    cleanup_temp_files
    read -p "Tekan Enter untuk kembali..."
}

# Fungsi untuk menghapus worker
hapus_worker() {
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}           Menu Hapus Worker                        ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}Masukkan nama Worker yang ingin dihapus:${NC}"
    read WORKER_NAME

    URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME"
    response=$(curl -s -w "%{http_code}" -o response.json -X DELETE -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$URL")
    httpCode=$(echo "$response" | tail -n1)

    if [ "$httpCode" -eq 200 ]; then
        echo -e "${GREEN}Worker '$WORKER_NAME' berhasil dihapus.${NC}"
        log_activity "Berhasil menghapus worker: $WORKER_NAME"
    else
        echo -e "${RED}Gagal menghapus Worker '$WORKER_NAME' (HTTP $httpCode)${NC}"
        log_activity "Error: Gagal menghapus worker $WORKER_NAME (HTTP $httpCode)"
    fi
    cleanup_temp_files
    read -p "Tekan Enter untuk kembali..."
}

# Fungsi untuk menampilkan DNS records
show_dns_records() {
    RESPONSE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "X-Auth-Email: ${AUTH_EMAIL}" \
        -H "X-Auth-Key: ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        -o dns_records_response.json)
    if jq -e '.success == true' dns_records_response.json >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Fungsi untuk menambahkan DNS record
tambah_dns_record() {
    clear
    echo -e "${CYAN}=== Tambah DNS Record ===${NC}"
    
    # Dapatkan domain utama
    if ! get_zone_domain; then
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    echo -e "${GREEN}Domain utama: $ZONE_DOMAIN${NC}"
    echo -e "${GREEN}Pilih tipe DNS record yang ingin ditambahkan:${NC}"
    echo -e "${YELLOW}1. A (Proxy Off)${NC}"
    echo -e "${YELLOW}2. CNAME (Proxy On)${NC}"
    read -p "Pilih tipe DNS record (1/2): " dns_type

    echo -e "${YELLOW}Masukkan subdomain (contoh: 'sub', '*.vip', atau '*' untuk wildcard):${NC}"
    read subdomain

    # Proses subdomain untuk wildcard
    if [[ "$subdomain" == "*" ]]; then
        domain="*.${ZONE_DOMAIN}"
    elif [[ "$subdomain" =~ ^\*\..+$ ]]; then
        # Jika subdomain dimulai dengan *. (misalnya *.vip), gabungkan dengan domain utama
        domain="${subdomain}.${ZONE_DOMAIN}"
    else
        domain="${subdomain}.${ZONE_DOMAIN}"
    fi

    if ! validate_subdomain "$subdomain"; then
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    if [ "$dns_type" -eq 1 ]; then
        record_type="A"
        proxied=false
        echo -e "${YELLOW}Masukkan alamat IP untuk A record (contoh: 192.168.1.1):${NC}"
        read target
        # Validasi IP untuk A record
        if [[ ! "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Alamat IP tidak valid!${NC}"
            log_activity "Error: Alamat IP tidak valid untuk A record ($target)"
            read -p "Tekan Enter untuk kembali..."
            return
        fi
    elif [ "$dns_type" -eq 2 ]; then
        record_type="CNAME"
        proxied=true
        echo -e "${YELLOW}Masukkan domain tujuan untuk CNAME (contoh: target.example.com):${NC}"
        read target
        if ! validate_cname_target "$target"; then
            read -p "Tekan Enter untuk kembali..."
            return
        fi
    else
        echo -e "${RED}Pilihan tidak valid.${NC}"
        log_activity "Error: Pilihan DNS record tidak valid ($dns_type)"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Periksa apakah record sudah ada
    check_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$domain&type=$record_type"
    check_response=$(curl -s -w "%{http_code}" -o check_response.json -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$check_url")
    check_httpCode=$(echo "$check_response" | tail -n1)

    if [ "$check_httpCode" -eq 200 ]; then
        existing_records=$(jq '.result | length' < check_response.json)
        if [ "$existing_records" -gt 0 ]; then
            echo -e "${YELLOW}Record $record_type untuk $domain sudah ada${NC}"
            log_activity "Record $record_type untuk $domain sudah ada"
            read -p "Tekan Enter untuk kembali..."
            return
        fi
    else
        echo -e "${RED}Gagal memeriksa record (HTTP $check_httpCode)${NC}"
        log_activity "Error: Gagal memeriksa record $domain (HTTP $check_httpCode)"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Tambahkan DNS record
    data='{"type":"'"$record_type"'","name":"'"$domain"'","content":"'"$target"'","ttl":1,"proxied":'$proxied'}'
    URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"
    response=$(curl -s -w "%{http_code}" -o response.json -X POST -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" -H "Content-Type: application/json" -d "$data" "$URL")
    httpCode=$(echo "$response" | tail -n1)

    if [ "$httpCode" -eq 200 ] && jq -e '.success == true' response.json >/dev/null 2>&1; then
        echo -e "${GREEN}Berhasil: $record_type $domain -> $target${NC}"
        log_activity "Berhasil menambahkan: $record_type $domain -> $target"
    else
        error_message=$(jq -r '.errors[]?.message // "Tidak ada pesan error"' response.json)
        echo -e "${RED}Gagal: $error_message (HTTP $httpCode)${NC}"
        log_activity "Error: Gagal menambahkan $record_type $domain -> $target: $error_message (HTTP $httpCode)"
    fi

    rm -f response.json check_response.json 2>/dev/null
    read -p "Tekan Enter untuk kembali..."
}

# Fungsi untuk menghapus DNS record
delete_dns_record() {
    backup_config
    while true; do
        display_header
        echo -e "${CYAN}=====================================================${NC}"
        echo -e "${GREEN}           Menu Hapus DNS Record                    ${NC}"
        echo -e "${CYAN}=====================================================${NC}"

        # Ambil daftar DNS record
        if ! show_dns_records; then
            echo -e "${RED}Gagal mengambil daftar DNS record.${NC}"
            log_activity "Error: Gagal mengambil daftar DNS record"
            read -p "Tekan Enter untuk kembali..."
            return
        fi

        # Ambil ID dan nama record
        record_ids=$(jq -r '.result[] | .id' < dns_records_response.json)
        record_names=$(jq -r '.result[] | "\(.name) (\(.type))"' < dns_records_response.json)

        if [ -z "$record_ids" ]; then
            echo -e "${YELLOW}Tidak ada DNS record yang tersedia.${NC}"
            log_activity "Tidak ada DNS record yang tersedia"
            read -p "Tekan Enter untuk kembali..."
            return
        fi

        # Tampilkan daftar DNS record
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        echo -e "${GREEN}Daftar DNS Record:${NC}"
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        IFS=$'\n' read -d '' -r -a record_list <<< "$record_names"
        for i in "${!record_list[@]}"; do
            echo -e "${YELLOW}$((i + 1)). ${record_list[$i]}${NC}"
        done
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        echo -e "${YELLOW}1. Hapus satu DNS record${NC}"
        echo -e "${YELLOW}2. Hapus semua DNS record${NC}"
        echo -e "${RED}0. Kembali ke menu sebelumnya${NC}"
        echo -e "${CYAN}=====================================================${NC}"

        read -p "Pilih opsi (1/2/0): " choice

        case $choice in
            1)
                echo -e "${CYAN}-----------------------------------------------------${NC}"
                read -p "Pilih nomor DNS record untuk dihapus (1-${#record_list[@]}): " record_choice
                if [[ ! "$record_choice" =~ ^[0-9]+$ ]] || [ "$record_choice" -lt 1 ] || [ "$record_choice" -gt "${#record_list[@]}" ]; then
                    echo -e "${RED}Pilihan tidak valid!${NC}"
                    log_activity "Error: Pilihan DNS record tidak valid ($record_choice)"
                    read -p "Tekan Enter untuk lanjut..."
                    continue
                fi

                # Ambil ID record yang dipilih
                IFS=$'\n' read -d '' -r -a id_list <<< "$record_ids"
                selected_record_id=${id_list[$((record_choice - 1))]}
                selected_record=${record_list[$((record_choice - 1))]}

                # Hapus DNS record
                delete_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$selected_record_id"
                delete_response=$(curl -s -w "%{http_code}" -o delete_response.json -X DELETE -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$delete_url")
                delete_httpCode=$(echo "$delete_response" | tail -n1)

                if [ "$delete_httpCode" -eq 200 ]; then
                    echo -e "${GREEN}DNS record $selected_record berhasil dihapus.${NC}"
                    log_activity "Berhasil menghapus DNS record $selected_record (ID $selected_record_id)"
                else
                    echo -e "${RED}Gagal menghapus DNS record $selected_record (HTTP $delete_httpCode)${NC}"
                    log_activity "Error: Gagal menghapus DNS record $selected_record (HTTP $delete_httpCode)"
                fi
                read -p "Tekan Enter untuk lanjut..."
                ;;
            2)
                delete_count=0
                failed_count=0
                IFS=$'\n' read -d '' -r -a id_list <<< "$record_ids"
                for i in "${!id_list[@]}"; do
                    record_id=${id_list[$i]}
                    record_name=${record_list[$i]}
                    delete_url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id"
                    delete_response=$(curl -s -w "%{http_code}" -o delete_response.json -X DELETE -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$delete_url")
                    delete_httpCode=$(echo "$delete_response" | tail -n1)

                    if [ "$delete_httpCode" -eq 200 ]; then
                        echo -e "${GREEN}DNS record $record_name berhasil dihapus.${NC}"
                        log_activity "Berhasil menghapus DNS record $record_name (ID $record_id)"
                        delete_count=$((delete_count + 1))
                    else
                        echo -e "${RED}Gagal menghapus DNS record $record_name (HTTP $delete_httpCode)${NC}"
                        log_activity "Error: Gagal menghapus DNS record $record_name (HTTP $delete_httpCode)"
                        failed_count=$((failed_count + 1))
                    fi
                    sleep "$API_DELAY"
                done
                echo -e "${GREEN}$delete_count DNS record berhasil dihapus.${NC}"
                if [ "$failed_count" -gt 0 ]; then
                    echo -e "${RED}$failed_count DNS record gagal dihapus.${NC}"
                fi
                log_activity "Hasil penghapusan DNS record: $delete_count berhasil, $failed_count gagal"
                read -p "Tekan Enter untuk lanjut..."
                ;;
            0)
                echo -e "${RED}Kembali ke menu sebelumnya...${NC}"
                log_activity "Kembali dari menu hapus DNS record ke sub-menu"
                break
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid!${NC}"
                log_activity "Error: Pilihan opsi hapus DNS record tidak valid ($choice)"
                read -p "Tekan Enter untuk lanjut..."
                ;;
        esac
    done
    cleanup_temp_files
}

# Fungsi untuk mengedit DNS record
edit_dns_record() {
    backup_config
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}           Menu Edit DNS Record                     ${NC}"
    echo -e "${CYAN}=====================================================${NC}"

    # Ambil daftar DNS record
    if ! show_dns_records; then
        echo -e "${RED}Gagal mengambil daftar DNS record.${NC}"
        log_activity "Error: Gagal mengambil daftar DNS record"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Ambil ID, nama, tipe, content, dan proxied status
    record_ids=$(jq -r '.result[] | .id' < dns_records_response.json)
    record_names=$(jq -r '.result[] | .name' < dns_records_response.json)
    record_types=$(jq -r '.result[] | .type' < dns_records_response.json)
    record_contents=$(jq -r '.result[] | .content' < dns_records_response.json)
    record_proxied=$(jq -r '.result[] | .proxied' < dns_records_response.json)

    if [ -z "$record_ids" ]; then
        echo -e "${YELLOW}Tidak ada DNS record yang tersedia untuk diedit.${NC}"
        log_activity "Tidak ada DNS record yang tersedia untuk diedit"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Tampilkan daftar DNS record
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${GREEN}Daftar DNS Record:${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    IFS=$'\n' read -d '' -r -a name_list <<< "$record_names"
    IFS=$'\n' read -d '' -r -a type_list <<< "$record_types"
    IFS=$'\n' read -d '' -r -a content_list <<< "$record_contents"
    IFS=$'\n' read -d '' -r -a proxied_list <<< "$record_proxied"
    for i in "${!name_list[@]}"; do
        proxied_status=$(if [ "${proxied_list[$i]}" = "true" ]; then echo "Proxied"; else echo "DNS Only"; fi)
        echo -e "${YELLOW}$((i + 1)). ${name_list[$i]} (${type_list[$i]}) -> ${content_list[$i]} [${proxied_status}]${NC}"
    done
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${YELLOW}Pilih nomor DNS record untuk diedit (1-${#name_list[@]}):${NC}"
    read -p "Pilihan Anda: " record_choice

    if [[ ! "$record_choice" =~ ^[0-9]+$ ]] || [ "$record_choice" -lt 1 ] || [ "$record_choice" -gt "${#name_list[@]}" ]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"
        log_activity "Error: Pilihan DNS record untuk edit tidak valid ($record_choice)"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    # Ambil detail record yang dipilih
    selected_index=$((record_choice - 1))
    selected_id=${record_ids[$selected_index]}
    selected_name=${name_list[$selected_index]}
    selected_type=${type_list[$selected_index]}
    selected_content=${content_list[$selected_index]}
    selected_proxied=${proxied_list[$selected_index]}

    # Tampilkan detail dan minta perubahan
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${GREEN}Detail Record Saat Ini:${NC}"
    echo -e "Nama: $selected_name"
    echo -e "Tipe: $selected_type"
    echo -e "Konten: $selected_content"
    echo -e "Status: $(if [ "$selected_proxied" = "true" ]; then echo "Proxied"; else echo "DNS Only"; fi)"
    echo -e "${CYAN}-----------------------------------------------------${NC}"

    echo -e "${YELLOW}Masukkan subdomain baru (tekan Enter untuk tetap $selected_name):${NC}"
    read new_subdomain
    if [ -n "$new_subdomain" ]; then
        if [[ "$new_subdomain" == "*" ]]; then
            new_domain="*.${ZONE_DOMAIN}"
        elif [[ "$new_subdomain" =~ ^\*\..+$ ]]; then
            new_domain="${new_subdomain}.${ZONE_DOMAIN}"
        else
            new_domain="${new_subdomain}.${ZONE_DOMAIN}"
        fi
        if ! validate_subdomain "$new_subdomain"; then
            read -p "Tekan Enter untuk kembali..."
            return
        fi
    else
        new_domain=$selected_name
    fi

    echo -e "${YELLOW}Pilih tipe baru (tekan Enter untuk tetap $selected_type):${NC}"
    echo -e "${YELLOW}1. A${NC}"
    echo -e "${YELLOW}2. CNAME${NC}"
    read -p "Pilihan (1/2 atau Enter): " new_type_choice
    if [ -n "$new_type_choice" ]; then
        case $new_type_choice in
            1) new_type="A" ;;
            2) new_type="CNAME" ;;
            *) echo -e "${RED}Pilihan tidak valid, menggunakan tipe lama.${NC}"; new_type=$selected_type ;;
        esac
    else
        new_type=$selected_type
    fi

    if [ "$new_type" = "A" ]; then
        echo -e "${YELLOW}Masukkan IP baru (tekan Enter untuk tetap $selected_content):${NC}"
        read new_content
        if [ -n "$new_content" ]; then
            if [[ ! "$new_content" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "${RED}IP tidak valid!${NC}"
                log_activity "Error: IP tidak valid untuk edit ($new_content)"
                read -p "Tekan Enter untuk kembali..."
                return
            fi
        else
            new_content=$selected_content
        fi
        new_proxied=false
    elif [ "$new_type" = "CNAME" ]; then
        echo -e "${YELLOW}Masukkan domain tujuan baru (tekan Enter untuk tetap $selected_content):${NC}"
        read new_content
        if [ -n "$new_content" ]; then
            if ! validate_cname_target "$new_content"; then
                read -p "Tekan Enter untuk kembali..."
                return
            fi
        else
            new_content=$selected_content
        fi
        new_proxied=true
    fi

    echo -e "${YELLOW}Ubah status proxy? (1 untuk Proxied, 2 untuk DNS Only, Enter untuk tetap $selected_proxied):${NC}"
    read -p "Pilihan (1/2 atau Enter): " proxy_choice
    if [ -n "$proxy_choice" ]; then
        case $proxy_choice in
            1) new_proxied=true ;;
            2) new_proxied=false ;;
            *) new_proxied=$selected_proxied ;;
        esac
    else
        new_proxied=$selected_proxied
    fi

    # Kirim permintaan edit ke Cloudflare
    data='{"type":"'"$new_type"'","name":"'"$new_domain"'","content":"'"$new_content"'","ttl":1,"proxied":'$new_proxied'}'
    URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$selected_id"
    response=$(curl -s -w "%{http_code}" -o response.json -X PUT -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" -H "Content-Type: application/json" -d "$data" "$URL")
    httpCode=$(echo "$response" | tail -n1)

    if [ "$httpCode" -eq 200 ] && jq -e '.success == true' response.json >/dev/null 2>&1; then
        echo -e "${GREEN}Berhasil mengedit DNS record: $new_domain ($new_type) -> $new_content [$(if [ "$new_proxied" = "true" ]; then echo "Proxied"; else echo "DNS Only"; fi)]${NC}"
        log_activity "Berhasil mengedit DNS record: $new_domain ($new_type) -> $new_content [proxied=$new_proxied]"
    else
        error_message=$(jq -r '.errors[]?.message // "Tidak ada pesan error"' response.json)
        echo -e "${RED}Gagal mengedit DNS record: $error_message (HTTP $httpCode)${NC}"
        log_activity "Error: Gagal mengedit DNS record $new_domain: $error_message (HTTP $httpCode)"
    fi

    cleanup_temp_files
    read -p "Tekan Enter untuk kembali..."
}

# Fungsi untuk mengelola domain.txt
kelola_domain_txt() {
    backup_config
    show_menu() {
        clear
        echo -e "${CYAN}=====================================================${NC}"
        echo -e "${GREEN}          Menu Pengelolaan domain.txt               ${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        echo -e "${YELLOW}1. Edit File domain.txt${NC}"
        echo -e "${YELLOW}2. Lihat Konten domain.txt${NC}"
        echo -e "${YELLOW}3. Backup Domain${NC}"
        echo -e "${RED}0. Keluar${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        read -p "Pilihan Anda: " choice
    }

    while true; do
        show_menu
        case $choice in
            1)
                ${DEFAULT_EDITOR} "$DOMAIN_FILE"
                echo -e "${GREEN}Perubahan disimpan!${NC}"
                log_activity "Mengedit file domain.txt"
                sleep 1
                ;;
            2)
                clear
                echo -e "${CYAN}=====================================================${NC}"
                echo -e "${GREEN}           Isi File domain.txt                 ${NC}"
                echo -e "${CYAN}=====================================================${NC}"
                if [[ -s "$DOMAIN_FILE" ]]; then
                    cat "$DOMAIN_FILE"
                else
                    echo -e "${RED}File kosong.${NC}"
                fi
                echo -e "\n${CYAN}=====================================================${NC}"
                log_activity "Menampilkan isi file domain.txt"
                read -p "Tekan Enter untuk kembali..."
                ;;
            3)
                backup_config
                echo -e "${GREEN}Backup domain.txt berhasil dibuat di $BACKUP_DIR!${NC}"
                log_activity "Backup domain.txt berhasil"
                read -p "Tekan Enter untuk kembali..."
                ;;
            0)
                echo -e "${RED}Keluar...${NC}"
                log_activity "Keluar dari pengelolaan domain.txt"
                sleep 1
                clear
                break
                ;;
            *)
                echo -e "${RED}Opsi tidak valid!${NC}"
                log_activity "Error: Opsi tidak valid di pengelolaan domain.txt ($choice)"
                sleep 1
                ;;
        esac
    done
}

# Menu utama
check_dependencies
while true; do
    display_header
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}     Selamat datang di Menu Pengelolaan Domain      ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}1. Pointing (Menambahkan domain)${NC}"
    echo -e "${YELLOW}2. Hapus Domain${NC}"
    echo -e "${YELLOW}3. Membuat Worker${NC}"
    echo -e "${YELLOW}4. Hapus Worker${NC}"
    echo -e "${YELLOW}5. Menambahkan atau Menghapus DNS Record${NC}"
    echo -e "${YELLOW}6. Edit domain wildcards${NC}"
    echo -e "${RED}0. Keluar${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    read -p "Pilih opsi (1/2/3/4/5/6/0): " pilihan

    case $pilihan in
        1)
            echo -e "${YELLOW}Masukkan suffix domain yang akan digunakan (misalnya: speedssh.my.id):${NC}"
            read SBD_SUFFIX
            if [ -z "$SBD_SUFFIX" ]; then
                echo -e "${RED}Suffix domain tidak boleh kosong!${NC}"
                continue
            fi
            echo -e "${YELLOW}Masukkan nama Worker yang ingin dipilih untuk pointing:${NC}"
            read WORKER_NAME
            if [ -z "$WORKER_NAME" ]; then
                echo -e "${RED}Nama worker tidak boleh kosong!${NC}"
                continue
            fi
            log_activity "Memulai penambahan domain dengan worker: $WORKER_NAME"
            tambah_domain
            ;;
        2)
            log_activity "Memulai penghapusan domain"
            hapus_domain
            ;;
        3)
            log_activity "Memulai pembuatan worker"
            buat_worker
            ;;
        4)
            log_activity "Memulai penghapusan worker"
            hapus_worker
            ;;
        5)
            echo -e "${GREEN}Menambahkan atau Menghapus DNS Record...${NC}"
            echo -e "${YELLOW}1. Menambahkan DNS Record${NC}"
            echo -e "${YELLOW}2. Menghapus DNS Record${NC}"
            echo -e "${YELLOW}3. Edit DNS Record${NC}"
            read -p "Pilih opsi untuk DNS Record (1/2/3): " dns_option
            clear
            case $dns_option in
                1)
                    log_activity "Memulai penambahan DNS record"
                    tambah_dns_record
                    ;;
                2)
                    log_activity "Memulai penghapusan DNS record"
                    delete_dns_record
                    ;;
                3)
                    log_activity "Memulai edit DNS record"
                    edit_dns_record
                    ;;
                *)
                    echo -e "${RED}Pilihan tidak valid!${NC}"
                    log_activity "Error: Pilihan DNS record tidak valid ($dns_option)"
                    ;;
            esac
            ;;
        6)
            log_activity "Memulai pengelolaan domain.txt"
            kelola_domain_txt
            ;;
        0)
            echo -e "${RED}Keluar dari menu.${NC}"
            log_activity "Keluar dari aplikasi"
            cleanup_temp_files
            exit 0
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            log_activity "Error: Pilihan menu tidak valid ($pilihan)"
            ;;
    esac
done