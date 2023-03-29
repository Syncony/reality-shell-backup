#! /bin/bash

function check_root()
{
    [[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 sudo su  命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

function check_sys()
{
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

function Installation_dependency(){
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

function getPK(){
    ./xray x25519>key
    cat key|tr "\n" ":"|xargs -n1 -d":"> tmp
    sed -i "s/\s//g" tmp
    PIK=`sed -n "2p" ./tmp`
    PBK=`sed -n "4p" ./tmp`
    rm tmp
}

network_mode=""
function choose_network(){
echo -e "\n"
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

check_root
check_sys
Installation_dependency

Version=`curl https://api.github.com/repos/XTLS/Xray-core/releases|jq .[0].tag_name -r`
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

wget -qO config.json  https://raw.githubusercontent.com/WangHelloo/reality-shell-backup/main/reality-h2.json

choose_network

read -p "输入监听端口(0~65535):" Port
[ -z ${Port} ] && Port=443

read -p "自定义UUID(不需要就直接回车):" UUID
[ -z ${UUID} ] && UUID=`./xray uuid`

read -p "自定义ShortID(不需要就直接回车):" SID
[ -z ${SID} ] && SID=`openssl rand -hex 8`

read -p "自定义SNI(不需要就直接回车):" SNI
[ -z ${SNI} ] && SNI="www.lovelive-anime.jp"

read -p "自定义私钥(不需要就直接回车):" PIK
[ -z ${PIK} ] && getPK

IP=`curl ip.sb`
[ -z `echo ${IP}|grep ":"`  ] || IP="["${IP}"]"

clear

echo -e "端口:"${Port}
echo -e "UUID:"${UUID}
echo -e "传输协议选择TCP:流控选择xtls-rprx-vision 伪装域名,path留空\n传输协议选择H2:流控,伪装域名,path全部留空\n传输协议选择GRPC:流控,伪装域名留空,path填写grpc,mode选择gun"
echo -e "传输层安全V2Ray系列选Reality 安卓Matsuri选TLS\nAlpn留空"
echo -e "SNI(默认www.lovelive-anime.jp):"${SNI}
echo -e "公钥:"${PBK}
echo -e "ShortID:"${SID}
echo -e "SpiderX:/"

sed -i "s/ 443/ ${Port}/" ./config.json
sed -i "s/chika/${UUID}/" ./config.json
sed -i "s/6ba85179e30d4fc2/${SID}/" ./config.json
sed -i "s/2KZ4uouMKgI8nR-LDJNP1_MHisCJOmKGj9jUjZLncVU/${PIK}/" ./config.json
sed -i "s/www\.lovelive-anime\.jp/${SNI}/g" ./config.json

Flow=""
GrpcX=""
Proxy_Path=""
[[ ${network_mode} == "tcp" ]] && Flow="xtls-rprx-vision"
[[ ${network_mode} == "grpc" ]] && GrpcX=",\"grpcSettings\"\: \{\"serviceName\"\: \"grpc\"\}"
[[ ${network_mode} == "grpc" ]] && Proxy_Path="grpc"

sed -i "s/networkmode/${network_mode}/" ./config.json
sed -i "s/user\-flow/${Flow}/" ./config.json
sed -i "s/ \/\/grpcsetting/${GrpcX}/" ./config.json

NOW_DIR=$(cd $(dirname $0); pwd)"/"
`./xray -c config.json >/dev/null &`

Share="vless://"${UUID}"@"${IP}":"${Port}"?security=reality&encryption=none&pbk="${PBK}"&headerType=none&fp=chrome&spx=%2F&type="${network_mode}"&sni="${SNI}"&sid="${SID}
[[ ${network_mode} == "grpc" ]] && Share=${Share}"&mode=gun&serviceName="${Proxy_Path}
[[ ${network_mode} == "tcp" ]] && Share=${Share}"&flow=xtls-rprx-vision"
echo -e "crontab: @reboot "${NOW_DIR}"xray -c "${NOW_DIR}"config.json"
echo -e "运行命令: ./xray -c config.json&"
echo -e "Xray 已在后台运行,请自行配置守护进程"
echo -e "如需结束进程可通过ps -aux|grep xray查看PID 或 直接Killall xray"
echo -e "分享链接:\n"${Share}
