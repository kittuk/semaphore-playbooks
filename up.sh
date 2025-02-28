#!/bin/bash
start_time=$(date +%s)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
check_exit_status() {

    if [ 0 -eq 0 ]
    then
        echo
        echo "Success"
        echo
    else
        echo
        echo "[ERROR] Process Failed!"
        echo
		
        read -p "The last command exited with an error. Exit script? (yes/no) " answer
        if [ "" == "yes" ]
        then
            exit 1
        fi
    fi
}

greeting() {

    echo
    echo "Hello, ktowning. Let's update this system."
    echo -e "\e[1;42m $HOSTNAME\e[0m"
    echo
}

update() {

    sudo DEBIAN_FRONTEND=noninteractive apt-get update;
    check_exit_status

    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y;
    check_exit_status

    sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y;
    check_exit_status
}

housekeeping() {

    sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y;
    check_exit_status

    sudo DEBIAN_FRONTEND=noninteractive apt-get autoclean -y;
    check_exit_status

    sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y;
    check_exit_status

    #echo sudo updatedb;
    #check_exit_status
}

leave() {

    echo
    echo "--------------------"
    echo "- Update Complete! -"
    echo "--------------------"
    echo
    #exit
}

myreboot() {
    if [ -f /var/run/reboot-required ]; then
        echo -e "\e[1;42m Restarting $HOSTNAME\e[0m"
        echo -e "\e[1;42m Reboot Needed !!! \e[0m"
        sleep 2
        sudo reboot
    else
        echo -e "\e[1;42m $HOSTNAME\e[0m"
        echo -e "\e[1;42m No reboot \e[0m"
        sleep 2
    fi
#    exit
}

mydocker(){
#!/bin/bash
 echo -e "${NC} remount and mount -a"
 echo -e "${GREEN}"
 sudo mount -o remount,credentials=/etc/samba/credentials,uid=1000,gid=1000,rw,nounix,iocharset=utf8,file_mode=0777,dir_mode=0770,vers=3.0,noserverino /media/hyp010;
 sudo mount -a;

 echo -e "${RED}Docker stop and start"
 echo -e "${GREEN}"
[ -f ~/docker/docker-compose*.yml ] && sudo docker compose --profile all -f ~/docker/docker-compose*.yml down

echo -e "${RED}Docker stopped"
sleep 2

[ -f ~/docker/docker-compose*.yml ] && sudo docker compose --profile all -f ~/docker/docker-compose*.yml up -d --remove-orphans

echo -e "${GREEN}Docker started"

[ -f ~/docker/docker-compose*.yml ] && sudo docker system prune -a -f
[ -f ~/docker/docker-compose*.yml ] && sudo docker system df

[ -f ~/docker/docker-compose*.yml ] && sudo docker compose --profile all -f ~/docker/docker-compose*.yml pull
[ -f ~/docker/docker-compose*.yml ] && sudo docker compose --profile all -f ~/docker/docker-compose*.yml up -d --remove-orphans

echo -e "${GREEN}Docker started again"

greeting

 echo -e "${RED}Update ${NC} Starting" 
 echo -e "${GREEN}"
update
 echo -e "${RED}housekeeping"
  echo -e "${GREEN}"
housekeeping
 echo -e "${RED}Leave"
 echo -e "${GREEN}"
leave
#mydocker
#./clean.sh
~/bin/cleanup.sh
 echo -e "${RED}cleanup"
 echo -e "${GREEN}"
~/bin/clean.sh
#[ -f ~/docker/docker-compose.yml ] && docker system df
 echo -e "${RED}Docker update"
 echo -e "${GREEN}"
mydocker
 echo -e "${RED}Check for Reboot"
 echo -e "${GREEN}"
myreboot
 echo -e "${NC}"
#if [ -f /var/run/reboot-required ]; then
#echo 'reboot required'
#fi
end_time=$(date +%s)
echo "Date"
date
echo "Uptime"
uptime
echo "Memory Usage"
free -m
echo "Network Usage"
ip -f inet a show eth0
echo "Time elapsed: $(($end_time - $start_time)) seconds"
exit
