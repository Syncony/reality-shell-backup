#! /bin/bash

Xray_PATH="/etc/Xray/"
SHARE_LINK=""
SERVICE_FILE_PATH='/etc/systemd/system/Xray.service'
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
        OS_ARCH="64"
    elif [[ ${OS_ARCH} == "aarch64" || ${OS_ARCH} == "arm64" ]]; then
        OS_ARCH="arm64-v8a"
    else
        OS_ARCH="64"
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

#download Xray-core  binary
download_xray() {
    echo -e "\n开始下载xray...\n"
    os_check && arch_check && install_base
    local Xray_VERSION_TEMP=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | sed 'y/,/\n/' | grep 'tag_name' | awk -F '"' '{print $4}')
    [ -z "${Xray_VERSION_TEMP}" ] && Xray_VERSION_TEMP="v1.8.8"
    read -p "自定义版本号:" custom_version
    [ -z ${custom_version} ] || Xray_VERSION_TEMP="v"$custom_version
    Xray_VERSION=${Xray_VERSION_TEMP:1}
    echo -e "\n将选择使用版本:${Xray_VERSION}\n"
    local DOWANLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${Xray_VERSION_TEMP}/Xray-linux-${OS_ARCH}.zip"

    #here we need create directory for Xray-core
    [[ -f ${Xray_PATH}/config.json ]] && mv ${Xray_PATH}/config.json /etc/xray.bak.config.json
    [[ -d ${Xray_PATH} ]] && rm ${Xray_PATH}/xray ${Xray_PATH}/xxray -rf || mkdir ${Xray_PATH}
    cd ${Xray_PATH}
    wget -N --no-check-certificate -O xray.zip ${DOWANLOAD_URL}
    mkdir ${Xray_PATH}xxray && unzip -d ${Xray_PATH}xxray ${Xray_PATH}xray.zip
    mv ${Xray_PATH}xxray/xray ${Xray_PATH} && rm ${Xray_PATH}xxray ${Xray_PATH}xray.zip -R
    if [[ $? -ne 0 ]]; then
        echo -e "\nDownload Xray-core failed,plz be sure that your network work properly and can access github"
        exit 1
    else
        echo -e "\n下载Xray-core成功"
    fi
    [[ -f /etc/xray.bak.config.json ]] && cp /etc/xray.bak.config.json ${Xray_PATH}/config.json
}

download_xray

if [[ -f /etc/xray.bak.config.json ]];then
	rm /etc/xray.bak.config.json
	echo -e "升级完成,如需重新配置请自行备份并移除 ${Xray_PATH}/config.json"
	service Xray restart
	exit
fi

reality_inbound() {
    network_mode=""
    function choose_network(){
    echo -e "\n❗gRPC/H2 建议在有大陆优化的VPS上使用。并且VPS所在的地区距离你的位置越近越好。即使你的VPS满足以上条件，仍然不能避免断流现象。\n"
    read -e -p "1.TCP 2.H2 3.GRPC 请键入相应数字选择传输协议:" networkmode
    case ${networkmode} in
        1)
          network_mode="tcp"
          echo "TCP";;
        2)
          network_mode="h2"
          echo "H2";;
        3)
          network_mode="grpc"
          echo "GRPC";;
        *)
          echo "选择错误"
          sleep 3s
          choose_network;;
    esac
    }
    choose_network
    read -p "输入监听端口(0~65535):" Port
    [ -z ${Port} ] && Port=443

    read -p "自定义UUID(不需要就直接回车):" UUID
    [ -z ${UUID} ] && UUID=`./xray uuid`

    read -p "自定义ShortID(不需要就直接回车):" SID
    [ -z ${SID} ] && SID=`openssl rand -hex 8`

    read -p "自定义SNI(不需要就直接回车):" SNI
    [ -z ${SNI} ] && SNI="www.goto.com"

    read -p "自定义私钥(不需要就直接回车):" PIK
    if [[ -z ${PIK} ]];then
        KEYS=`./xray x25519`
        PIK=$(echo -e $KEYS | awk -F ' ' '{print $3}')
        PBK=$(echo -e $KEYS | awk -F ' ' '{print $6}')
        echo "私钥:"${PIK} > ${Xray_PATH}keys.txt
        echo "公钥:"${PBK} >> ${Xray_PATH}keys.txt 
    fi
    cat >>config.json<<EOF
        {
            "listen": "::",
            "port": ${Port},
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "USERFLOW"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "${network_mode}",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${SNI}:443",
                    "xver": 0,
                    "serverNames": [
                        "${SNI}",
                        ""
                    ],
                    "privateKey": "${PIK}",
                    "shortIds": [
                        "${SID}",
                        ""
                    ]
                } //grpcsetting
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
EOF

local USERFLOW=""
[ "${network_mode}" == "tcp" ] && USERFLOW="xtls-rprx-vision"
sed -i 's/USERFLOW/'${USERFLOW}'/g' ./config.json

GrpcX=""
if [[ "${network_mode}" == "grpc" ]];then
    [[ ${network_mode} == "grpc" ]] && GrpcX=",\"grpcSettings\"\: \{\"serviceName\"\: \"\"\}"
fi
sed -i "s/ \/\/grpcsetting/${GrpcX}/" ./config.json

SHARE_LINK=${SHARE_LINK}"\nReality: vless://"${UUID}"@"${IP}":"${Port}"?security=reality&encryption=none&pbk="${PBK}"&headerType=none&fp=chrome&spx=%2F&type="${network_mode}"&sni="${SNI}"&sid="${SID}"&flow="${USERFLOW}"#Reality"
}

ss_inbound() {
    read -p "输入监听端口(0~65535):" Port
    [ -z ${Port} ] && Port=443
    read -p "输入密码(直接回车随机生成):" Passwd
    [ -z ${Passwd} ] && Passwd=`openssl rand -base64 32`
    local method=$([[ ! -z `cat /proc/cpuinfo|grep aes` ]]&& echo "aes-128-gcm" || echo "chacha20-ietf-poly1305")
    cat >>config.json<<EOF
      {
      "listen": "::",
      "port": ${Port},
      "protocol": "shadowsocks",
      "settings": {
        "method": "${method}",
        "password": "${Passwd}",
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "header": {
            "type": "none"
          },
          "acceptProxyProtocol": false
        }
      },
      "tag": "ss-in",
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
EOF
    local ss_encode=`echo -n $method:$Passwd|base64 | tr -d '\n'`
    SHARE_LINK=${SHARE_LINK}"\nShadowsocks: ss://${ss_encode}@${IP}:${Port}#SS"
}

make_config() {
    cd ${Xray_PATH}
    echo "" > config.json
    cat >> config.json <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
EOF
      read -p "搭建Vless-Reality?[y/N/a](默认采用Shadowsocks,键入a同时搭建)" is_reality
      case ${is_reality} in
          a|A)
              echo -e "配置Shadowsocks:\n"
              ss_inbound;
	      echo "," >> config.json
              echo -e "配置vless-reality:\n"
              reality_inbound
	      ;;
          y|Y)
              reality_inbound
              ;;
          *)
              ss_inbound
              ;;
      esac
      cat >> config.json <<EOF
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
EOF
}

make_config

#install systemd service
install_systemd_service() {
    echo -e "开始安装Xray systemd服务..."
    [ ${OS_RELEASE} == "alpine" ] && SERVICE_FILE_PATH="/etc/init.d/Xray"
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

name="Xray"
description="Xray-core Service"
supervisor="supervise-daemon"
command="${Xray_PATH}xray "
command_args="-c ${Xray_PATH}config.json"
command_user="root:root"

depend() {
	after net dns
	use net
}
EOF
      chmod +x ${SERVICE_FILE_PATH}
      rc-update add Xray
      service Xray start
    else
      cat >${SERVICE_FILE_PATH} <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core/
After=network.target nss-lookup.target
Wants=network.target
[Service]
Type=simple
ExecStart=${Xray_PATH}xray -c ${Xray_PATH}config.json
Restart=on-failure
RestartSec=30s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    chmod +x ${SERVICE_FILE_PATH}
    systemctl daemon-reload
    systemctl enable Xray 
    fi
    service Xray start
    echo -e "安装Xray systemd服务成功"
}

install_systemd_service

echo -e "${SHARE_LINK}" > ${Xray_PATH}/share.txt

echo -e "
Xray-core可执行文件与目录均位于:${Xray_PATH}
如需卸载只需要执行删除Xray服务和 ${Xray_PATH} 文件夹
分享链接:${SHARE_LINK}"
