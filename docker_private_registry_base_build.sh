#!/bin/bash


#/*********************************************************************************************************/
#/ docker Private Registry Setup
#/*********************************************************************************************************/
#--> https://gist.github.com/u1i/1ec704b5c099b407875128fe0b864735
#/*********************************************************************************************************/

#----------------------------------------------------#
alias dinfo='sudo docker info'
alias dockerkill='sudo docker kill $(sudo docker ps -q)'
alias dps='sudo docker ps'
alias dil='sudo docker image ls'
alias dcstop='sudo docker container stop registry'
drmc(){ sudo docker rm -f ${1} ; }
alias ns='sudo netstat -tulnp'
#----------------------------------------------------#




function azenv(){
    __MSG_BANNER__ "${1}"
    AZ_RESOURCE_GROUP_NAME="rg-${AZ_CLUSTER_GROUP_NAME}-1"
    AZ_RESOURCE_LOCATION="westus2"
    AZ_PUBLIC_IP="ip-pub-${AZ_RESOURCE_GROUP_NAME}-lb"
    AZ_PUBLIC_IP_VM_NAME="ip-pub-${AZ_RESOURCE_GROUP_NAME}-vm"
    # AZ_PUBLIC_IP_VM_2="ip-pub-${AZ_RESOURCE_GROUP_NAME}-vm-2"
    # AZ_PUBLIC_IP_VM_3="ip-pub-${AZ_RESOURCE_GROUP_NAME}-vm-3"
    AZ_LOADBALANCER="lb-${AZ_RESOURCE_GROUP_NAME}"
    AZ_IP_POOL_FRONTEND="ip-pool-${AZ_RESOURCE_GROUP_NAME}-frontend"
    AZ_IP_POOL_BACKEND="ip-pool-${AZ_RESOURCE_GROUP_NAME}-backend"
    AZ_VM_NET_PRIMARY="vnet-${AZ_RESOURCE_GROUP_NAME}"
    AZ_LOADBALANCER_PROBE="${AZ_RESOURCE_GROUP_NAME}-probe-health"
    AZ_LOADBALANCER_RULE="${AZ_RESOURCE_GROUP_NAME}-rule"
    AZ_VM_NET_SUBNET="${AZ_RESOURCE_GROUP_NAME}-subnet"
    AZ_NET_SVC_GROUP="nsg-${AZ_RESOURCE_GROUP_NAME}"
    AZ_NET_SVC_GROUP_RULE="nsg-${AZ_RESOURCE_GROUP_NAME}-rule"
    AZ_VM_AVAIL_SET="avset-${AZ_RESOURCE_GROUP_NAME}"
    AZ_VM_NAME_ROOT="vm-${AZ_RESOURCE_GROUP_NAME}"
    AZ_VM_NET_PRIMARY_NIC="${AZ_RESOURCE_GROUP_NAME}-nic"
    # getenv 'AZ_'
    set | grep AZ_ | grep '=' | egrep -v '\(\)|;|\$'
}


function dtrenv(){
  MY_VM_HOST=${AZ_VM_NAME_ROOT}-106
  MY_REGISTRY_DOMIN_COM=${MY_VM_HOST}.westus2.cloudapp.azure.com
  MY_REGISTRY_IP=20.115.150.110
  IFILE=/Users/admin/.ssh/vm-rg-dtrprivateprod-1-1
  MY_PRIVATE_IP=10.0.0.4
  DOCKER_DAEMON_JSON=/etc/docker/daemon.json
  DOCKER_SERVICE_CONFIG=/lib/systemd/system/docker.service
}


function helm-install(){ 
     curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
     chmod 700 get_helm.sh
     ./get_helm.sh
}


function docker_install(){
        sudo apt-get remove docker.io containerd runc
        sudo apt-get update
        sudo apt-get install \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        sudo apt-get install docker-ce docker-ce-cli containerd.io
}


function dockerInsecConfigure(){
    #---> https://stackoverflow.com/questions/42211380/add-insecure-registry-to-docker
cat <<EOF|sudo tee ${DOCKER_DAEMON_JSON}
{
  "insecure-registries" : ["${MY_REGISTRY_DOMIN_COM}","${MY_VM_HOST}","${MY_REGISTRY_IP}","${MY_PRIVATE_IP}"]
}
EOF

cat <<EOF| sudo tee -a /etc/default/docker
DOCKER_OPTS="--insecure-registry=${MY_REGISTRY_DOMIN_COM} --insecure-registry=${MY_PRIVATE_IP} --insecure-registry=${MY_VM_HOST}"
EOF

ls -al ${DOCKER_DAEMON_JSON} /etc/default/docker
}

function docker-stop-service(){
    sudo systemctl stop docker.service && sudo systemctl stop docker.socket
    sudo systemctl status docker.service --no-pager && sudo systemctl status docker.socket --no-pager
}

function docker-start-service(){
    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl status docker.service --no-pager 

}

function docker_restart(){
    docker-stop-service
    docker-start-service
}

#---- letsencrypt -------------#
function os_install_common_props(){
    sudo apt update
    sudo apt install software-properties-common -y
    sudo add-apt-repository universe
    sudo apt update
}

function os_install_certbot(){
    sudo add-apt-repository ppa:certbot/certbot
    sudo apt update
    sudo apt install certbot -y
    certbot --version
    certbot plugins
}

function os_install_certbot_apache(){
    sudo apt install python-certbot-apache -y
}

function ssl_cerbot_create_certs(){
    sudo certbot --apache -d ${MY_REGISTRY_DOMIN_COM}
}


function ssl_create_dom_certs(){
            ETC_DOMAIN=/etc/letsencrypt/live/${MY_REGISTRY_DOMIN_COM}
                    # privkey.pem
                    # cert.pem
                    # chain.pem
                    # fullchain.pem
                    # cd ${ETC_DOMAIN}
            sudo cp ${ETC_DOMAIN}/privkey.pem ${ETC_DOMAIN}/domain.key
            sudo cat ${ETC_DOMAIN}/cert.pem ${ETC_DOMAIN}/chain.pem | sudo tee ${ETC_DOMAIN}/domain.crt
            sudo chmod 777 ${ETC_DOMAIN}/domain.crt
            sudo chmod 777 ${ETC_DOMAIN}/domain.key
}
#-----------------------------#

function docker_http_auth(){
            cd ~
            mkdir -p auth
                # sudo docker run --entrypoint htpasswd registry:2 -Bbn testuser testpassword | sudo tee auth/htpasswd

            sudo docker run -it --entrypoint htpasswd \
                    -v $PWD/auth:/auth \
                    -w /auth registry:2.7.0 \
                    -Bbc /auth/htpasswd dtradmin lLmxF6LmrGFcj6G
}

function apache_stop(){
            sudo systemctl stop apache2.service
}

function docker_repo_start(){
            sudo docker run -d -p 443:443 --restart=always --name registry \
              -v /etc/letsencrypt/live/${MY_REGISTRY_DOMIN_COM}:/certs \
              -v /app-sdc/docker/var/lib/registry:/var/lib/registry \
              -v `pwd`/auth:/auth \
              -e "REGISTRY_AUTH=htpasswd" \
              -e "REGISTRY_AUTH_HTPASSWD_REALM=Leap Docker Registry" \
              -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
              -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
              -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
              -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
              registry:2.7.0

              # -v /opt/docker-registry:/var/lib/registry \
}

function docker_rsync_repo_locn(){
	DOCKER_DRIVE_NAME="${1}"   #---- app-sdc
    DOCKER_VAR_LIB_REPOSITORY_LOCN=/opt/docker-registry
    DOCKER_VAR_LIB_REPOSITORY_LOCN_NEW=/${DOCKER_DRIVE_NAME}/docker/var/lib/registry

    sudo mkdir -p ${DOCKER_VAR_LIB_REPOSITORY_LOCN_NEW}
    sudo rsync -aqxP --size-only --modify-window=120 ${DOCKER_VAR_LIB_REPOSITORY_LOCN} ${DOCKER_VAR_LIB_REPOSITORY_LOCN_NEW}
}

#/*********************************************************************************************************/
#/ MAIN
#/*********************************************************************************************************/

AZ_CLUSTER_GROUP_NAME="${1}"      #---- dtrprivateprod

main(){
		azenv load
		dtrenv

		helm-install
		docker_install
		dockerInsecConfigure
		docker-stop-service
		os_install_common_props
		os_install_certbot
		os_install_certbot_apache

		ssl_cerbot_create_certs
		docker_http_auth
		apache_stop
		docker-stop-service
		docker_repo_start
		#docker_rsync_repo_locn app-sdc
}


#/*********************************************************************************************************/