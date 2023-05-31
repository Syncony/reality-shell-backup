#! /usr/bin/env bash
function check_root() {
    [[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 sudo su  命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

function check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
    bit=$(uname -m)
        if test "$bit" != "x86_64"; then
           bit='arm64'
        else bit="amd64"
    fi
}

function Installation_dependency() {
    if [[ ! -f /usr/bin/jq  ]];then
    if [[ ${release} == "centos" ]]; then
        yum -y update && yum -y upgrade
        yum install -y wget
        yum -y install unzip
        yum -y install curl
        yum -y install jq
    else
        apt-get -y update && apt-get -y upgrade
        apt-get install -y wget
        apt-get install -y unzip
        apt-get -y install curl
        apt-get -y install jq
    fi
    fi
}

check_root
check_sys
Installation_dependency

Version=`curl -sL https://api.github.com/repos/XTLS/Xray-core/releases|jq .[0].tag_name -r`
read -p "最新版本Xray为:${Version} 如需要自定义版本请输入版本号,否则请直接留空回车:" pVersion
[ -z ${pVersion} ] || Version="v"$pVersion

if [[ ${bit} == "amd64"  ]];then
        bit="64"
else
        bit="arm64-v8a"
fi

rm x_xray -R
mkdir x_xray && cd x_xray

wget -qO xray.zip https://github.com/XTLS/Xray-core/releases/download/${Version}/Xray-linux-${bit}.zip

unzip -o xray.zip && rm xray.zip

passwd=`openssl rand -base64 32`
function choosemethod(){
        echo -e "\n1.aes-256-gcm\n2.chacha20-poly1305\n3.2022-blake3-aes-256-gcm\n4.2022-blake3-chacha20-poly1305"
        read -p "选择应用的协议:" method
        case ${method} in 
                1)
                        method="aes-256-gcm";;
                2)
                        method="chacha20-poly1305";;
                3)
                        method="2022-blake3-aes-256-gcm";;
                4)
                        method="2022-blake3-chacha20-poly1305";;
                *)
                        echo "error"
                        sleep 3s
                        choosemethod;;
        esac
}
choosemethod

share=`echo $method:$passwd|base64 -w 0`

read -p "键入监听端口:" port
[[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
    if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; then
        echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
        read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" port
        [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    fi
done
cat > config.json <<EOF
{
  "log": null,
  "routing": {
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ],
        "type": "field"
      }
    ]
  },
  "dns": null,
  "inbounds": [
      {
      "listen": "::",
      "port": $port,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$method",
        "password": "$passwd",
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
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOF

NOW_DIR=$(cd $(dirname $0); pwd)"/"
ssspath=/etc/systemd/system/x_xray.service
rm $ssspath
touch $ssspath
cat >$ssspath <<EOF
[Unit]
Description=proxy service
Documentation=https://github.com/XTLS/Xray-core/releases
After=network.target nss-lookup.target
 
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=${NOW_DIR}xray -c ${NOW_DIR}config.json >/dev/null 2>&1
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=infinity
 
[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now x_xray

IP=`curl -s ip.sb`
[ -z `echo ${IP}|grep ":"`  ] || IP="["${IP}"]"

echo $passwd> str
sed -i "s/\+/%2B/g" str
passwd=`cat str`
rm str

encode=`curl -sL https://www.toolhelper.cn/EncodeDecode/Base64Encode -d "encode=$method:$passwd" -d "encoding=UTF-8"|jq .Data -r`

echo -e "\nPort:"$port
echo -e "\nMethod:"$method
echo -e "\nPassword:"$passwd
echo -e "\nIPv4:"`curl -s ip.sb -4`
echo -e "\nIPv6:"`curl -s ip.sb -6`
echo -e "\n分享链接:ss://${encode}@${IP}:${port}#SS"
