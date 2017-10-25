#! /usr/bin/env bash

declare basepath=$(cd `dirname "$0"`; pwd)
declare NGROK_DOMAIN="ngrok.lzw.name"
declare path_git="$basepath/ngrok/code"; declare path_key="$basepath/ngrok/key"

source $basepath/../functions/core.bash

if [[ -x "/usr/local/sbin/ngrokd" ]]; then
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Ngrok has been installed.${BK_CODE_RESET}"
else
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Installing Ngrok...${BK_CODE_RESET}"
    
    if [ -d "$path_git" ]; then
        echo "$path_git"
    else
        cd "$basepath" && git clone https://github.com/bkbabydp/ngrok.git code
    fi

    if [ -d "$path_key" ]; then
        echo "$path_key"
    else
        mkdir -p "$path_key" && cd "$path_key" && \
            openssl genrsa -out rootCA.key 2048 && \
            openssl req -x509 -new -nodes -key rootCA.key -subj "/CN=$NGROK_DOMAIN" -days 5000 -out rootCA.pem && \
            openssl genrsa -out device.key 2048 && \
            openssl req -new -key device.key -subj "/CN=$NGROK_DOMAIN" -out device.csr && \
            openssl x509 -req -in device.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out device.crt -days 5000
        cd ".."
    fi

    cd "$path_git" && make clean
    cp "$path_key/rootCA.pem" "$path_git/assets/client/tls/ngrokroot.crt"
    cp "$path_key/device.key" "$path_git/assets/server/tls/snakeoil.key"
    cp "$path_key/device.crt" "$path_git/assets/server/tls/snakeoil.crt"
    make release-all
    cd ".."
    #make release-server release-client

    cp "$path_git/bin/ngrokd" /usr/local/sbin/ngrokd
    cp "$path_git/bin/ngrok" /usr/local/bin/ngrok

    cat > "$HOME/.ngrok" <<EOF
server_addr: ngrok.lzw.name:4443
trust_host_root_certs: false
EOF
fi
  
firewall-cmd --add-port=4443/tcp --permanent

#bin/ngrokd -tlsKey=device.key -tlsCrt=device.crt -domain="$NGROK_DOMAIN" -httpAddr=":8480" -httpsAddr=":8443"
#ngrok -config ~/.ngrok -subdomain wx 3000
