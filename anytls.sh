#! /bin/bash

SING_BOX_PATH="/etc/sing-box-anytls/"
SHARE_LINK=""
SERVICE_FILE_PATH='/etc/systemd/system/sing-box-anytls.service'
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
        OS_ARCH="amd64"
    elif [[ ${OS_ARCH} == "aarch64" || ${OS_ARCH} == "arm64" ]]; then
        OS_ARCH="arm64"
    else
        OS_ARCH="amd64"
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

#download sing-box  binary
download_sing_box() {
    echo -e "\n开始下载sing-box...\n"
    os_check && arch_check && install_base
    local SING_BOX_VERSION_TEMP=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | sed 'y/,/\n/' | grep 'tag_name' | awk -F '"' '{print $4}')
    [ -z "${SING_BOX_VERSION_TEMP}" ] && SING_BOX_VERSION_TEMP="v1.8.0"
    read -p "自定义版本号:" custom_version
    [ -z ${custom_version} ] || SING_BOX_VERSION_TEMP="v"$custom_version
    SING_BOX_VERSION=${SING_BOX_VERSION_TEMP:1}
    echo -e "\n将选择使用版本:${SING_BOX_VERSION}\n"
    local DOWANLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${SING_BOX_VERSION_TEMP}/sing-box-${SING_BOX_VERSION}-linux-${OS_ARCH}.tar.gz"

    #here we need create directory for sing-box
    [[ -f ${SING_BOX_PATH}/config.json ]] && mv ${SING_BOX_PATH}/config.json /etc/sb-anytls.bak.config.json
    [[ -d ${SING_BOX_PATH} ]] && rm ${SING_BOX_PATH}/sing-box -f || mkdir ${SING_BOX_PATH}
    cd ${SING_BOX_PATH}
    wget -N --no-check-certificate -O sb.tar.gz ${DOWANLOAD_URL}
    tar -xvf sb.tar.gz
    rm sb.tar.gz && mv sing-box-${SING_BOX_VERSION}-linux-${OS_ARCH}/* .
    rm sing-box-${SING_BOX_VERSION}-linux-${OS_ARCH} LICENSE -R
    if [[ $? -ne 0 ]]; then
        echo -e "\nDownload sing-box failed,plz be sure that your network work properly and can access github"
        exit 1
    else
        echo -e "\n下载sing-box成功"
    fi
    [[ -f /etc/sb-anytls.bak.config.json ]] && cp /etc/sb-anytls.bak.config.json ${SING_BOX_PATH}/config.json
}

download_sing_box

if [[ -f /etc/sb-anytls.bak.config.json ]];then
	rm /etc/sb-anytls.bak.config.json
	echo -e "升级完成,如需重新配置请自行备份并移除 ${SING_BOX_PATH}/config.json"
	service sing-box-anytls restart
	exit
fi

anytls_inbound() {
    read -p "输入监听端口(0~65535):" Port
    [ -z ${Port} ] && Port=27016
    read -p "输入密码(直接回车随机生成):" Passwd
    [ -z ${Passwd} ] && Passwd=$([[ ! -z `cat /proc/cpuinfo|grep aes` ]] && openssl rand -base64 16 || openssl rand -base64 32)
    [[ ! -d ${SING_BOX_PATH}cert ]] && mkdir ${SING_BOX_PATH}cert
    rm ${SING_BOX_PATH}cert/cert.pem ${SING_BOX_PATH}cert/private.key -f
    openssl ecparam -genkey -name prime256v1 -out ${SING_BOX_PATH}cert/private.key && openssl req -new -x509 -days 36500 -key ${SING_BOX_PATH}cert/private.key -out ${SING_BOX_PATH}cert/cert.pem -subj "/CN=$(awk -F . '{print $(NF-1)"."$NF}' <<< "global.fujifilm.com")"
	# KEYS=`${SING_BOX_PATH}sing-box generate reality-keypair`
    # PIK=$(echo -e $KEYS | awk -F ' ' '{print $2}')
    # PBK=$(echo -e $KEYS | awk -F ' ' '{print $4}')
    # echo "私钥:"${PIK} > ${SING_BOX_PATH}keys.txt
    # echo "公钥:"${PBK} >> ${SING_BOX_PATH}keys.txt
	# SID=`openssl rand -hex 8`
 
	cat >>config.json<<EOF
        {
            "type": "anytls",
            "tag": "anytls-in",
            "listen": "::",
            "listen_port": ${Port},
     	    "tcp_multi_path": true,
            "tcp_fast_open": true,
            "users": [
                {
                    "name": "diego",
                    "password": "${Passwd}"
                }
            ],
            "tls": {
                "enabled": true,
				"certificate_path": ${SING_BOX_PATH}cert/cert.pem,
                "key_path": ${SING_BOX_PATH}cert/private.key
			}
        }
EOF
    SHARE_LINK=${SHARE_LINK}"\nanytls://${Passwd}@${IP}:${Port}/?insecure=1&sni=global.fujifilm.com#AnyTLS"
}

make_config() {
    cd ${SING_BOX_PATH}
    echo "" > config.json
    echo "">sing-box.log
    cat >> config.json <<EOF
{
    "log": {
        "disabled": true
    },
    "inbounds": [
EOF
      anytls_inbound
      cat >> config.json <<EOF
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
}

make_config

#install systemd service
install_systemd_service() {
    echo -e "开始安装sing-box-anytls systemd服务..."
    [ ${OS_RELEASE} == "alpine" ] && SERVICE_FILE_PATH="/etc/init.d/sing-box-anytls"
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

name="sing-box"
description="Sing-Box-AnyTLS Service"
supervisor="supervise-daemon"
command="${SING_BOX_PATH}sing-box run"
command_args="-c ${SING_BOX_PATH}config.json"
command_user="root:root"

depend() {
	after net dns
	use net
}
EOF
      chmod +x ${SERVICE_FILE_PATH}
      rc-update add sing-box-anytls
      service sing-box-anytls start
    else
      cat >${SERVICE_FILE_PATH} <<EOF
[Unit]
Description=sing-box-anytls Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target
Wants=network.target
[Service]
Type=simple
ExecStart=${SING_BOX_PATH}sing-box run -c ${SING_BOX_PATH}config.json
Restart=on-failure
RestartSec=30s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    chmod +x ${SERVICE_FILE_PATH}
    [[ ! -d /etc/systemd/system/sing-box-anytls.service.d ]] && mkdir /etc/systemd/system/sing-box-anytls.service.d
    echo '[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99' > /etc/systemd/system/sing-box-anytls.service.d/priority.conf
    systemctl daemon-reload
    systemctl enable sing-box-anytls
    fi
    service sing-box-anytls start
    echo -e "安装sing-box-anytls systemd服务成功"
}

install_systemd_service

echo -e "${SHARE_LINK}" > ${SING_BOX_PATH}/share.txt

sysctl -w net.ipv4.tcp_fastopen=3

echo -e "
sing-box-anytls可执行文件与目录均位于:${SING_BOX_PATH}
如需卸载只需要执行删除sing-box-anytls服务和 ${SING_BOX_PATH} 文件夹
分享链接:${SHARE_LINK}
"
