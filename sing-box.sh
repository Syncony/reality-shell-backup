#! /bin/bash

SING_BOX_PATH="/etc/sing-box/"
SHARE_LINK=""
SERVICE_FILE_PATH='/etc/systemd/system/sing-box.service'
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
    [[ -f ${SING_BOX_PATH}/config.json ]] && mv ${SING_BOX_PATH}/config.json /etc/sb.bak.config.json
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
    [[ -f /etc/sb.bak.config.json ]] && cp /etc/sb.bak.config.json ${SING_BOX_PATH}/config.json
}

download_sing_box

if [[ -f /etc/sb.bak.config.json ]];then
	rm /etc/sb.bak.config.json
	echo -e "升级完成,如需重新配置请自行备份并移除 ${SING_BOX_PATH}/config.json"
	service sing-box restart
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
          network_mode="http"
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
    cat >>config.json<<EOF
        {
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": PORT,
	    "multiplex": {
		"enabled": true,
		"padding": true
	    },
     	    "tcp_multi_path": true,
            "users": [
                {
                    "uuid": "UUID",
                    "flow": "USERFLOW"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "CUSDEST",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "CUSDEST",
                        "server_port": 443
                    },
                    "private_key": "PRIKEY",
                    "short_id": [
                        "SID",
                        ""
                    ]
                }
            }
EOF

read -p "输入监听端口(0~65535):" Port
[ -z ${Port} ] && Port=443

read -p "自定义UUID(不需要就直接回车):" UUID
[ -z ${UUID} ] && UUID=`./sing-box generate uuid`

read -p "自定义ShortID(不需要就直接回车):" SID
[ -z ${SID} ] && SID=`openssl rand -hex 8`

read -p "自定义SNI(不需要就直接回车):" SNI
[ -z ${SNI} ] && SNI="www.goto.com"

read -p "自定义私钥(不需要就直接回车):" PIK
if [[ -z ${PIK} ]];then
    KEYS=`./sing-box generate reality-keypair`
    PIK=$(echo -e $KEYS | awk -F ' ' '{print $2}')
    PBK=$(echo -e $KEYS | awk -F ' ' '{print $4}')
    echo "私钥:"${PIK} > ${Xray_PATH}keys.txt
    echo "公钥:"${PBK} >> ${Xray_PATH}keys.txt 
fi

sed -i 's/PORT/'${Port}'/g' ./config.json
sed -i 's/UUID/'${UUID}'/g' ./config.json
sed -i 's/SID/'${SID}'/g' ./config.json
sed -i 's/CUSDEST/'${SNI}'/g' ./config.json
sed -i 's/PRIKEY/'${PIK}'/g' ./config.json
local USERFLOW=""
[ "${network_mode}" == "tcp" ] && USERFLOW="xtls-rprx-vision"
sed -i 's/USERFLOW/'${USERFLOW}'/g' ./config.json
if [[ "${network_mode}" != "tcp" ]];then
        cat >>config.json<<EOF
,
            "transport": {
                "type": "${network_mode}"
EOF
        if [[ "${network_mode}" == "grpc" ]];then
          cat >>config.json<<EOF
,
                "service_name": "grpc"
EOF
        fi
fi
cat >>config.json<<EOF

            }
EOF
if [[ "${network_mode}" != "tcp" ]];then
cat >>config.json<<EOF
        }
EOF
fi
SHARE_LINK=${SHARE_LINK}"\nReality: vless://"${UUID}"@"${IP}":"${Port}"?security=reality&encryption=none&pbk="${PBK}"&headerType=none&fp=chrome&spx=%2F&serviceName=grpc&type="${network_mode}"&sni="${SNI}"&sid="${SID}"&flow="${USERFLOW}"#Reality"
}

ss_inbound() {
    read -p "输入监听端口(0~65535):" Port
    [ -z ${Port} ] && Port=443
    read -p "输入密码(直接回车随机生成):" Passwd
    [ -z ${Passwd} ] && Passwd=`openssl rand -base64 32`
    local method=$([[ ! -z `cat /proc/cpuinfo|grep aes` ]]&& echo "2022-blake3-aes-256-gcm" || echo "2022-blake3-chacha20-ietf-poly1305")
    cat >>config.json<<EOF
        {
            "type": "shadowsocks",
            "tag": "ss-in",
            "listen": "::",
            "listen_port": ${Port},
	    "multiplex": {
		"enabled": true,
		"padding": true
	    },
     	    "tcp_multi_path": true,
            "method": "${method}",
            "password": "${Passwd}"
        }
EOF
    local ss_encode=`echo -n $method:$Passwd|base64 | tr -d '\n'`
    SHARE_LINK=${SHARE_LINK}"\nShadowsocks: ss://${ss_encode}@${IP}:${Port}#SS"
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
            "type": "direct",
	    "domain_strategy": "prefer_ipv6",
            "tag": "direct"
        }
    ],
    "route": { 
        "auto_detect_interface": true
    }
}
EOF
}

make_config

#install systemd service
install_systemd_service() {
    echo -e "开始安装sing-box systemd服务..."
    [ ${OS_RELEASE} == "alpine" ] && SERVICE_FILE_PATH="/etc/init.d/sing-box"
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
description="Sing-Box Service"
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
      rc-update add sing-box
      service sing-box start
    else
      cat >${SERVICE_FILE_PATH} <<EOF
[Unit]
Description=sing-box Service
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
    systemctl daemon-reload
    systemctl enable sing-box 
    fi
    service sing-box start
    echo -e "安装sing-box systemd服务成功"
}

install_systemd_service

echo -e "${SHARE_LINK}" > ${SING_BOX_PATH}/share.txt

echo -e "
sing-box可执行文件与目录均位于:${SING_BOX_PATH}
如需卸载只需要执行删除sing-box服务和 ${SING_BOX_PATH} 文件夹
默认优先使用ipv6，可修改config中directc outbound的domain_strategy配置项进行调整
分享链接:${SHARE_LINK}"
