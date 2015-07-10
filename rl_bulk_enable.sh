#!/bin/bash
#Script to be used to enable running servers.
#It will execute the rightscale.enable.sh script
#https://rightlink.rightscale.com/rll/10.1.3/rightlink.enable.sh
#on all listed servers.
#
#

#local working directory
RL10_WORKING_DIR='rightscale_rl10'


#use sshpass for passing the password ssh when not using a key
#MAC OSX brew install https://git.io/sshpass.rb
#CENTOS/RHELyum -y install sshpass
#UBUNTU apt-get -y install sshpass

#uses pssh for parrallel ssh sessions
 #after testing on 20 instances , not a significant need.
#MAC OSX brew install pssh
#CENTOS/RHEL yum -y install pssh
#UBUNTU/DEBIAN apt-get -y install pssh

function show_help
{
     echo ""
     echo "Usage: "
     echo "  -u user to access servers"
     echo "  -p password to use when authenticating with a password"
     echo "  -k ssh private key to use when authenticating with keys"
     echo "  -f file with hostnames or ips"
     echo "  -d deployment where servers will the grouped"
     echo "  -n server name prefix"
     echo "  -m enable managed logins"
     echo "  -s server template name to associate the enaled server"
     echo "  -t rightscale API refresh token (Settings>API Credentials)"
     echo "  -c cloud (e.g. amazon, azure, cloud_stack, google, open_stack_v2,
                rackspace_next_gen, soft_layer, vscale )"
     echo "  -h show help information"
     echo ""
}


while getopts ":u:p:k:f:d:n:ms:t:c:h" opt; do
  case $opt in
    # User to ssh as
    u)
    export RS_SSH_USER=$OPTARG
    ;;
    # Password
    p)
    export SSHPASS=$OPTARG
    ;;
    #ssh key file
    k)
    export SSH_KEY_FILE=$OPTARG
    ;;
    # file with host information
    f)
    export RS_HOSTS_FILE=$OPTARG
    ;;
    #deployment name
    d)
    export RS_DEPLOYMENT=$OPTARG
    ;;
    #server name
    n)
    export RS_SERVER_NAME=$OPTARG
    ;;
    #enabled managed login
    m)
    export RS_MANAGED_LOGIN='-l'
    ;;
    #Server template name to use on enabled vms
    s)
    export RS_SERVER_TEMPLATE_NAME=$OPTARG
    ;;
    #rightscale api refresh token
    t)
    export RS_API_TOKEN=$OPTARG
    ;;
    #cloud type
    c)
    export RS_CLOUD=$OPTARG
    ;;
    # help
    h)
    show_help;exit 0;
    ;;
    # Invalid option
    \?) echo "invalid option -$OPTARG"; show_help;exit 1;;
  esac
done

#Create a working directory for the script and storing logs for each host (rightscale_rl10_script)
if [ ! -d "$RL10_WORKING_DIR" ]; then
  mkdir $RL10_WORKING_DIR
else
  echo "Working directory $RL10_WORKING_DIR exists . . . continue"
fi

#Generate SSH command options
#1 ssh -u -p #user and password
#2 ssh -u -k #user and private key
#3 ssh -u  #only user

if [[ -z "$RS_SSH_USER" ]]; then
  echo "ERROR: -u user missing." >&2
  show_help >&2
  exit 1
fi

#check for server name option
if [ ! -z "$RS_SERVER_NAME" ]; then
  RS_SERVER_NAME="-n $RS_SERVER_NAME"
  echo "$RS_SERVER_NAME"
fi

#build ssh command
if [ ! -z "$SSHPASS" ]; then
  SSH_CMD="sshpass -e ssh -tt -o StrictHostKeyChecking=no $RS_SSH_USER"
elif [ ! -z "$SSH_KEY_FILE" ]; then
  SSH_CMD="ssh -tt -o StrictHostKeyChecking=no -i $SSH_KEY_FILE $RS_SSH_USER"
else
  SSH_CMD="ssh -tt -o StrictHostKeyChecking=no $RS_SSH_USER"
fi

#for debugging - (REMOVE ME)
echo $SSH_CMD


for server in `cat $RS_HOSTS_FILE` ; do



    ( {

    echo "output from $server:" ; $SSH_CMD@$server " \

    #check if the file already exists, previous attempts
    [[ -f 'rightlink.enable.sh' ]] && rm 'rightlink.enable.sh'

    #get the latest enable script
    #add logic if curl -h doesn't return 0, try wget.
    curl https://rightlink.rightscale.com/rll/10.1.3/rightlink.enable.sh > rightlink.enable.sh && chmod +x rightlink.enable.sh && \

    #wget https://rightlink.rightscale.com/rll/10.1.3/rightlink.enable.sh && chmod +x rightlink.enable.sh  \

    #run the enable script

    #RS_MANAGED_LOGIN is set to "-l" if the -m flag is used.
    sudo ./rightlink.enable.sh $RS_MANAGED_LOGIN $RS_SERVER_NAME -k  "\'$RS_API_TOKEN\'" -t "\'$RS_SERVER_TEMPLATE_NAME\'"  -c "\'$RS_CLOUD\'"  -d "\'$RS_DEPLOYMENT\'"
    " ; } | \
    sed -e "s/^/$server:/" >> "$RL10_WORKING_DIR/$server-rl.log"

    ) &

 done
 wait

 #Report Status of each server
 RED='\033[0;31m' # Red
 GREEN='\033[0;32m' # Green
 NC='\033[0m' # No Color
TIMESTAMP=`date +"%Y-%m-%d_%H-%M-%S"`
 for server in `cat $RS_HOSTS_FILE` ; do

  #  grep "Enablement complete." $RL10_WORKING_DIR/$server-rl.log
     if grep -Fq 'Enablement complete.' "$RL10_WORKING_DIR/$server-rl.log"; then
       printf "$server: Rightlink Enablement ${GREEN} [OK] ${NC}\n";
     else
       printf "$server: Rightlink Enablement ${RED} [FAILED] ${NC}\n";
       HAS_FAILED='true'
       echo $server >> "$RL10_WORKING_DIR/failed_enablement_process.$TIMESTAMP.txt"
       mv "$RL10_WORKING_DIR/$server-rl.log" "$RL10_WORKING_DIR/$server--failed-rl.log"
     fi

     #clean up logs for another run.
     rm -rf $RL10_WORKING_DIR/$server-rl.log

done

if [ "$HAS_FAILED" == 'true' ]; then

echo "#####################################################################################################"
echo "A list of failed server can be found here $RL10_WORKING_DIR/failed_enablement_process.$TIMESTAMP.txt"
echo "A log file for each failed server is included in $RL10_WORKING_DIR"
echo "#####################################################################################################"
echo "#####################################################################################################"
fi