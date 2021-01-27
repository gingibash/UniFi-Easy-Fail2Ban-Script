#!/bin/bash

# UniFi Network Controller Fail2ban configuration.
# Version  | 1.1.7
# Author   | Glenn Rietveld
# Email    | glennrietveld8@hotmail.nl
# Website  | https://GlennR.nl

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
GRAY_R='\033[39m'
WHITE_R='\033[39m'
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                            Variables                                                                                            #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

unifi_conf=''
jail_conf=''
script_location="${BASH_SOURCE[0]}"
script_name=$(basename ${BASH_SOURCE[0]})

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Start Checks                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Check for root (SUDO).
if [[ "$EUID" -ne 0 ]]; then
  clear
  clear
  echo -e "${RED}#########################################################################${RESET}"
  echo ""
  echo -e "${WHITE_R}#${RESET} The script need to be run as root..."
  echo ""
  echo ""
  echo -e "${WHITE_R}#${RESET} For Ubuntu based systems run the command below to login as root"
  echo -e "${GREEN}#${RESET} sudo -i"
  echo ""
  echo -e "${WHITE_R}#${RESET} For Debian based systems run the command below to login as root"
  echo -e "${GREEN}#${RESET} su"
  echo ""
  echo ""
  exit 1
fi

if ! env | grep 'LC_ALL\|LANG' | grep -iq 'en_US\|C.UTF-8'; then
  clear && clear
  echo -e "${GREEN}#########################################################################${RESET}\\n"
  echo -e "${WHITE_R}#${RESET} Your language is not set to English ( en_US ), the script will temporarily set the language to English."
  echo -e "${WHITE_R}#${RESET} Information: This is done to prevent issues in the script.."
  export LC_ALL=C &> /dev/null
  set_lc_all=true
  sleep 3
fi

header() {
  clear
  echo -e "${GREEN}#########################################################################${RESET}"
  echo ""
}

header_red() {
  clear
  echo -e "${RED}#########################################################################${RESET}"
  echo ""
}

abort() {
  if [[ ${set_lc_all} == 'true' ]]; then unset LC_ALL; fi
  echo ""
  echo ""
  echo -e "${RED}#########################################################################${RESET}"
  echo ""
  echo -e "${RED}#${RESET} An error occurred. Aborting script..."
  echo -e "${RED}#${RESET} Please contact Glenn R. (AmazedMender16) on the Community Forums!"
  echo ""
  echo ""
  exit 1
}

# Get distro.
if [[ -z "$(command -v lsb_release)" ]]; then
  if [[ -f "/etc/os-release" ]]; then
    if grep -iq VERSION_CODENAME /etc/os-release; then
      os_codename=$(grep VERSION_CODENAME /etc/os-release | sed 's/VERSION_CODENAME//g' | tr -d '="' | tr '[:upper:]' '[:lower:]')
    elif ! grep -iq VERSION_CODENAME /etc/os-release; then
      os_codename=$(grep PRETTY_NAME /etc/os-release | sed 's/PRETTY_NAME=//g' | tr -d '="' | awk '{print $4}' | sed 's/\((\|)\)//g' | sed 's/\/sid//g' | tr '[:upper:]' '[:lower:]')
      if [[ -z "${os_codename}" ]]; then
        os_codename=$(grep PRETTY_NAME /etc/os-release | sed 's/PRETTY_NAME=//g' | tr -d '="' | awk '{print $3}' | sed 's/\((\|)\)//g' | sed 's/\/sid//g' | tr '[:upper:]' '[:lower:]')
      fi
    fi
  fi
else
  os_codename=$(lsb_release -cs | tr '[:upper:]' '[:lower:]')
  if [[ "${os_codename}" == 'n/a' ]]; then
    os_codename=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    if [[ "${os_codename}" == 'parrot' ]]; then
      os_codename='buster'
    fi
  fi
  if [[ "${os_codename}" =~ (hera|juno) ]]; then os_codename=bionic; fi
  if [[ "${os_codename}" == 'loki' ]]; then os_codename=xenial; fi
  if [[ "${os_codename}" == 'freya' ]]; then os_codename=trusty; fi
  if [[ "${os_codename}" == 'luna' ]]; then os_codename=precise; fi
fi

run_apt_get_update() {
  if ! [[ -d /tmp/EUS/keys ]]; then mkdir -p /tmp/EUS/keys; fi
  if ! [[ -f /tmp/EUS/keys/missing_keys && -s /tmp/EUS/keys/missing_keys ]]; then
    apt-get update 2>&1 | tee /tmp/EUS/keys/apt_update
    grep -o 'NO_PUBKEY.*' /tmp/EUS/keys/apt_update | sed 's/NO_PUBKEY //g' | tr ' ' '\n' | awk '!a[$0]++' &> /tmp/EUS/keys/missing_keys
  fi
  if [[ -f /tmp/EUS/keys/missing_keys && -s /tmp/EUS/keys/missing_keys ]]; then
    clear
    header
    echo -e "${WHITE_R}#${RESET} Some keys are missing.. The script will try to add the missing keys."
    echo -e "\\n${WHITE_R}----${RESET}\\n"
    while read -r key; do
      echo -e "${WHITE_R}#${RESET} Key ${key} is missing.. adding!"
      http_proxy=$(env | grep -i "http.*Proxy" | cut -d'=' -f2 | sed 's/[";]//g')
      if [[ -n "$http_proxy" ]]; then
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --keyserver-options http-proxy="${http_proxy}" --recv-keys "$key" &> /dev/null && echo -e "${GREEN}#${RESET} Successfully added key ${key}!\\n" || fail_key=true
      elif [[ -f /etc/apt/apt.conf ]]; then
        apt_http_proxy=$(grep "http.*Proxy" /etc/apt/apt.conf | awk '{print $2}' | sed 's/[";]//g')
        if [[ -n "${apt_http_proxy}" ]]; then
          apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --keyserver-options http-proxy="${apt_http_proxy}" --recv-keys "$key" &> /dev/null && echo -e "${GREEN}#${RESET} Successfully added key ${key}!\\n" || fail_key=true
        fi
      else
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv "$key" &> /dev/null && echo -e "${GREEN}#${RESET} Successfully added key ${key}!\\n" || fail_key=true
      fi
      if [[ "${fail_key}" == 'true' ]]; then
        echo -e "${RED}#${RESET} Failed to add key ${key}!"
        echo -e "${WHITE_R}#${RESET} Trying different method to get key: ${key}"
        gpg -vvv --debug-all --keyserver keyserver.ubuntu.com --recv-keys "${key}" &> /tmp/EUS/keys/failed_key
        debug_key=$(grep "KS_GET" /tmp/EUS/keys/failed_key | grep -io "0x.*")
        wget -q "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${debug_key}" -O- | gpg --dearmor > "/tmp/EUS/keys/EUS-${key}.gpg"
        mv "/tmp/EUS/keys/EUS-${key}.gpg" /etc/apt/trusted.gpg.d/ && echo -e "${GREEN}#${RESET} Successfully added key ${key}!\\n"
      fi
      sleep 1
    done < /tmp/EUS/keys/missing_keys
    rm --force /tmp/EUS/keys/missing_keys
    rm --force /tmp/EUS/keys/apt_update
    clear
    header
    echo -e "${WHITE_R}#${RESET} Running apt-get update again.\\n\\n"
    sleep 2
    apt-get update &> /tmp/EUS/keys/apt_update
    if grep -qo 'NO_PUBKEY.*' /tmp/EUS/keys/apt_update; then
      run_apt_get_update
    fi
  fi
}

SCRIPT_VERSION_ONLINE=$(curl https://get.glennr.nl/unifi/extra/unifi-fail2ban.sh -s | grep "# Version" | head -n 1 | awk '{print $4}' | sed 's/\.//g')
SCRIPT_VERSION=$(grep "# Version" "${script_name}" | head -n 1 | awk '{print $4}' | sed 's/\.//g')

# Script version check.
if [[ ${SCRIPT_VERSION_ONLINE::3} -gt ${SCRIPT_VERSION::3} ]]; then
  clear
  header_red
  echo -e "${WHITE_R}#${RESET} You're not using the latest version of the Fail2Ban Script!"
  echo -e "${WHITE_R}#${RESET} Downloading and executing the latest script version.."
  echo ""
  echo ""
  sleep 3
  rm --force "${script_location}" 2> /dev/null
  rm --force unifi-fail2ban.sh 2> /dev/null
  wget https://get.glennr.nl/unifi/extra/unifi-fail2ban.sh && bash unifi-fail2ban.sh; exit 0
fi

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Script Start                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Install needed packages if not installed
if ! dpkg -l fail2ban 2> /dev/null | awk '{print $1}' | grep -iq "^ii"; then
  clear
  header
  echo -e "${WHITE_R}#${RESET} Installing required packages!"
  echo ""
  echo ""
  sleep 2
  run_apt_get_update
  if ! apt-get install fail2ban -y; then
    if [[ "${os_codename}" =~ (xenial|sarah|serena|sonya|sylvia) ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://[A-Za-z0-9]*.archive.ubuntu.com/ubuntu xenial main universe") -eq 0 ]]; then
	    echo deb http://nl.archive.ubuntu.com/ubuntu xenial main universe >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" =~ (bionic|tara|tessa|tina|tricia) ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://[A-Za-z0-9]*.archive.ubuntu.com/ubuntu bionic main universe") -eq 0 ]]; then
	    echo deb http://nl.archive.ubuntu.com/ubuntu bionic main universe >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "cosmic" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://[A-Za-z0-9]*.archive.ubuntu.com/ubuntu cosmic main universe") -eq 0 ]]; then
	    echo deb http://nl.archive.ubuntu.com/ubuntu cosmic main universe >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "disco" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://[A-Za-z0-9]*.archive.ubuntu.com/ubuntu disco main universe") -eq 0 ]]; then
	    echo deb http://nl.archive.ubuntu.com/ubuntu disco main universe >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "eoan" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://[A-Za-z0-9]*.archive.ubuntu.com/ubuntu eoan main universe") -eq 0 ]]; then
	    echo deb http://nl.archive.ubuntu.com/ubuntu eoan main universe >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "focal" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://[A-Za-z0-9]*.archive.ubuntu.com/ubuntu focal main universe") -eq 0 ]]; then
	    echo deb http://nl.archive.ubuntu.com/ubuntu focal main universe >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "jessie" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://ftp.[A-Za-z0-9]*.debian.org/debian jessie main") -eq 0 ]]; then
	    echo deb http://ftp.nl.debian.org/debian jessie main >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" =~ (stretch|continuum) ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://ftp.[A-Za-z0-9]*.debian.org/debian stretch main") -eq 0 ]]; then
	    echo deb http://ftp.nl.debian.org/debian stretch main >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "buster" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://ftp.[A-Za-z0-9]*.debian.org/debian buster main") -eq 0 ]]; then
	    echo deb http://ftp.nl.debian.org/debian buster main >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
	elif [[ "${os_codename}" == "bullseye" ]]; then
      if [[ $(find /etc/apt/ -name "*.list" -type f -print0 | xargs -0 cat | grep -c "^deb http://ftp.[A-Za-z0-9]*.debian.org/debian bullseye main") -eq 0 ]]; then
	    echo deb http://ftp.nl.debian.org/debian bullseye main >>/etc/apt/sources.list.d/glennr-install-script.list || abort
	  fi
    fi
	run_apt_get_update
	apt-get install fail2ban -y || abort
  fi
fi

# Check if file exist
if [[ ! -e /etc/fail2ban/filter.d/unifi.conf ]]; then
  touch /etc/fail2ban/filter.d/unifi.conf
fi

maxretry_question() {
  clear
  header
  echo -e "${WHITE_R}#${RESET} After how many attempts do you want to block a connection/user?"
  echo ""
  echo -e " [   ${WHITE_R}1${RESET}   ]  |  4 Retries ( default )"
  echo -e " [   ${WHITE_R}2${RESET}   ]  |  6 Retries"
  echo -e " [   ${WHITE_R}3${RESET}   ]  |  8 Retries"
  echo -e " [   ${WHITE_R}4${RESET}   ]  |  10 Retries"
  echo -e " [   ${WHITE_R}5${RESET}   ]  |  I want to put in a number myself."
  echo ""
  echo ""
  echo ""
  read -rp $'Your choice | \033[39m' maxretry_choice
  case "${maxretry_choice}" in
      1*|"") max_retry='4';;
      2*) max_retry='6' ;;
      3*) max_retry='8' ;;
      4*) max_retry='10';;
      5*)
        reg='^[0-9]{2}$'
        echo ""
        echo -e "${WHITE_R}---${RESET}"
        echo ""
        read -n 2 -rp $'Amount of retries | \033[39m' amount
        if [[ ! ${amount} =~ ${reg} ]]; then
          clear
          header_red
          echo -e "${WHITE_R}#${RESET} '${amount}' is not a valid format, please only use numbers( 0-9 )" && sleep 2
          maxretry_question
        fi
        max_retry="${amount}";;
      *)
        clear
        header_red
        echo -e "${WHITE_R}#${RESET} '${maxretry_choice}' is not a valid option..." && sleep 2
        maxretry_question;;
  esac
}
maxretry_question

# Add lines if does not exist
if ! grep -q '\[INCLUDES\]' /etc/fail2ban/filter.d/unifi.conf
then
  clear
  header
  echo -e "${WHITE_R}#${RESET} Adding the lines to unifi.conf, this won't take long"
  echo ""
  echo ""
  sleep 2
  unifi_conf=true
  cat >> /etc/fail2ban/filter.d/unifi.conf <<EOL
[INCLUDES]
before = common.conf
[Definition]
failregex = ^(.*)Failed admin login for (.*) from <HOST>$
ignoreregex =
EOL
else
  clear
  header
  echo -e "${WHITE_R}#${RESET} /etc/fail2ban/filter.d/unifi.conf already contains items."
  echo -e "${RED}#${RESET} Feel free to contact Glenn R. ( AmazedMender16 ) on the Ubiquiti Community Forums"
  echo ""
  echo ""
  exit 1
fi

# Add lines if does not exist
if ! grep -q '\[unifi\]' /etc/fail2ban/jail.conf
then
  clear
  header
  echo -e "${WHITE_R}#${RESET} Adding the lines to jail.conf, this won't take long"
  echo ""
  echo ""
  sleep 2
  jail_conf=true
  cat >> /etc/fail2ban/jail.conf <<EOL

[unifi]
enabled = true
filter = unifi
port = 8443
logpath = /var/log/unifi/server.log
maxretry = ${max_retry}
bantime = 600
findtime = 900
action = iptables[name="unifi", port="8443"]
EOL
else
  clear
  header_red
  echo -e "${WHITE_R}#${RESET} /etc/fail2ban/jail.conf already contains lines for UniFi"
  echo -e "${RED}#${RESET} Feel free to contact Glenn R. ( AmazedMender16 ) on the Ubiquiti Community Forums"
  echo ""
  echo ""
  exit 1
fi

# Restart service
clear
header
echo -e "${WHITE_R}#${RESET} Restarting the service!"
echo ""
echo ""
sleep 2
service fail2ban restart

if [[ ( $unifi_conf = 'true' && $jail_conf = 'true' ) ]]; then
  sysinfo_version=$(dpkg -l | grep "unifi " | awk '{print $3}' | sed 's/-.*//' | cut -d'.' -f1-2 | tr -d '.')
  clear
  header
  echo ""
  echo -e "${GREEN}#${RESET} Fail2ban has been configured for your UniFi Network Controller!"
  echo ""
  echo -e "${WHITE_R}#${RESET} Make sure your Mgmt Log Level is set to More/Verbose or Debug."
  echo -e "${WHITE_R}#${RESET} Settings > Maintenance > Service > Log Level"
  if [[ "$sysinfo_version" -ge '511' ]]; then
    echo ""
    echo -e "${WHITE_R}#${RESET} NEW SETTINGS ( 5.11 and newer )"
    echo -e "${WHITE_R}#${RESET} Settings > Controller Settings > Advanced Configuration > Logging Levels"
  fi
  echo ""
  echo ""
  echo ""
  echo -e "${WHITE_R}#${RESET} ${GRAY_R}Author   |  ${WHITE_R}Glenn R.${RESET}"
  echo -e "${WHITE_R}#${RESET} ${GRAY_R}Email    |  ${WHITE_R}glennrietveld8@hotmail.nl${RESET}"
  echo -e "${WHITE_R}#${RESET} ${GRAY_R}Website  |  ${WHITE_R}https://GlennR.nl${RESET}"
  echo ""
  echo ""
  rm --force "${script_location}"
else
  clear
  header_red
  echo ""
  echo " Failed to successfully configure Fail2ban for your UniFi Network Controller!"
  echo ""
  echo -e " ${RED}Please contact Glenn R. (AmazedMender16) on the Community Forums!${RESET}"
  echo ""
  echo ""
fi
if [[ ${set_lc_all} == 'true' ]]; then unset LC_ALL &> /dev/null; fi
