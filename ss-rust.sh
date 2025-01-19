#! /bin/bash

SS_PATH="/etc/ss-rust/"
SHARE_LINK=""
SERVICE_FILE_PATH='/etc/systemd/system/ss-rust.service'
IP=`curl ip.sb`
[ -z `echo ${IP}|grep ":"`  ] || IP="["${IP}"]"

#System check
os_check() {
    echo -e "\n检测当前系统中...\n"
    if [[ -f /etc/redhat-release ]]; then
        OS_RELEASE="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        OS_RELEASE="debian"
    elif cat /etc/issue | grep -Eqi "Alpine"; then
        OS_RELEASE="alpine"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        OS_RELEASE="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        OS_RELEASE="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        OS_RELEASE="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        OS_RELEASE="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        OS_RELEASE="centos"
    else
        echo -e "\n系统检测错误,请联系脚本作者!" && exit 1
    fi
    echo -e "\n系统检测完毕,当前系统为:${OS_RELEASE}\n"
}

#arch check
arch_check() {
    echo -e "\n检测当前系统架构中...\n"
    OS_ARCH=$(arch)
    echo -e "\n当前系统架构为 ${OS_ARCH}\n"

    if [[ ${OS_ARCH} == "x86_64" || ${OS_ARCH} == "x64" || ${OS_ARCH} == "amd64" ]]; then
        OS_ARCH="x86_64"
    elif [[ ${OS_ARCH} == "aarch64" || ${OS_ARCH} == "arm64" ]]; then
        OS_ARCH="aarch64"
    else
        OS_ARCH="x86_64"
        echo -e "\n检测系统架构失败，使用默认架构: ${OS_ARCH}\n"
    fi
    echo -e "\n系统架构检测完毕,当前系统架构为:${OS_ARCH}\n"
}

#install some common utils
install_base() {
    if [[ ${OS_RELEASE} == "ubuntu" || ${OS_RELEASE} == "debian" ]]; then
        apt install wget tar jq -y
    elif [[ ${OS_RELEASE} == "centos" ]]; then
        yum install wget tar jq -y
    elif [[ ${OS_RELEASE} == "alpine" ]]; then
        apk update && apk add wget tar jq openssl
    fi
}

#download ss-rust  binary
download_ss() {
    echo -e "\n开始下载Shadowsocks-Rust...\n"
    os_check && arch_check && install_base
    local SS_VERSION_TEMP=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | sed 'y/,/\n/' | grep 'tag_name' | awk -F '"' '{print $4}')
    [ -z "${SS_VERSION_TEMP}" ] && SS_VERSION_TEMP="v1.22.0"
    read -p "自定义版本号:" custom_version
    [ -z ${custom_version} ] || SS_VERSION_TEMP="v"$custom_version
    SS_VERSION=${SS_VERSION_TEMP:1}
    echo -e "\n将选择使用版本:${SS_VERSION}\n"
    local DOWANLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_VERSION_TEMP}/shadowsocks-${SS_VERSION_TEMP}.${OS_ARCH}-unknown-linux-gnu.tar.xz"

    #here we need create directory for ss-rust
    [[ -f ${SS_PATH}/config.json ]] && mv ${SS_PATH}/config.json /etc/ss-rust.bak.config.json
    [[ -d ${SS_PATH} ]] && rm ${SS_PATH}/ss* -f || mkdir ${SS_PATH}
    cd ${SS_PATH}
    wget -N --no-check-certificate -O 1.tar.xz ${DOWANLOAD_URL}
    tar -xvf 1.tar.xz
    rm ${SS_PATH}1.tar.xz
    if [[ $? -ne 0 ]]; then
        echo -e "\nDownload Xray-core failed,plz be sure that your network work properly and can access github"
        exit 1
    else
        echo -e "\n下载SS-Rust成功"
    fi
    [[ -f /etc/ss-rust.bak.config.json ]] && cp /etc/ss-rust.bak.config.json ${SS_PATH}/config.json
}

download_ss

if [[ -f /etc/ss-rust.bak.config.json ]];then
	rm /etc/ss-rust.bak.config.json
	echo -e "升级完成,如需重新配置请自行备份并移除 ${SS_PATH}/config.json"
	service ss-rust restart
	exit
fi

ss_inbound() {
    read -p "输入监听端口(0~65535):" Port
    [ -z ${Port} ] && Port=2443
    read -p "输入密码(直接回车随机生成):" Passwd
    [ -z ${Passwd} ] && Passwd=`openssl rand -base64 32`
    local method=$([[ ! -z `cat /proc/cpuinfo|grep aes` ]]&& echo "2022-blake3-aes-256-gcm" || echo "2022-blake3-chacha20-ietf-poly1305")
    cat >config.json<<EOF
{
    "mode": "tcp_and_udp",
    "server": "::",
    "server_port": ${Port},
    "fast_open": true,
    "method": "${method}",
    "password": "${Passwd}"
}
EOF
    local ss_encode=`echo -n $method:$Passwd|base64 | tr -d '\n'`
    SHARE_LINK=${SHARE_LINK}"\nShadowsocks: ss://${ss_encode}@${IP}:${Port}#SS\nPassword: {$Passwd}"
}

ss_inbound

#install systemd service
install_systemd_service() {
    echo -e "开始安装ss-rust systemd服务..."
    [ ${OS_RELEASE} == "alpine" ] && SERVICE_FILE_PATH="/etc/init.d/ss-rust"
    if [ -f "${SERVICE_FILE_PATH}" ]; then
        rm -rf ${SERVICE_FILE_PATH}
    fi
    #create service file
    touch ${SERVICE_FILE_PATH}
    if [ $? -ne 0 ]; then
        echo -e "create service file failed,exit"
        exit 1
    else
        echo -e "create service file success..."
    fi
    if [[ ${OS_RELEASE} == "alpine" ]];then
            cat >${SERVICE_FILE_PATH} <<EOF
#!/sbin/openrc-run

name="SS-Rust"
description="SS-Rust Service"
supervisor="supervise-daemon"
command="${SS_PATH}ssserver "
command_args="-c ${SS_PATH}config.json"
command_user="root:root"

depend() {
	after net dns
	use net
}
EOF
      chmod +x ${SERVICE_FILE_PATH}
      rc-update add ss-rust
      service ss-rust start
    else
      cat >${SERVICE_FILE_PATH} <<EOF
[Unit]
Description=SS-Rust Service
Documentation=https://github.com/shadowsocks/shadowsocks-rust
After=network.target nss-lookup.target
Wants=network.target
[Service]
Type=simple
ExecStart=${SS_PATH}ssserver -c ${SS_PATH}config.json
Restart=on-failure
RestartSec=30s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    chmod +x ${SERVICE_FILE_PATH}
    [[ ! -d /etc/systemd/system/ss-rust.service.d ]] && mkdir /etc/systemd/system/ss-rust.service.d
    echo '[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99' > /etc/systemd/system/ss-rust.service.d/priority.conf
    systemctl daemon-reload
    systemctl enable ss-rust 
    fi
    service ss-rust start
    echo -e "安装ss-rust systemd服务成功"
}

install_systemd_service

echo -e "${SHARE_LINK}" > ${SS_PATH}/share.txt

echo -e "SS-Rust可执行文件与目录均位于:${SS_PATH}
如需卸载只需要执行删除SS-Rust服务和 ${SS_PATH} 文件夹
分享链接:${SHARE_LINK}"
