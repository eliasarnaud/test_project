#!/bin/bash

# Init
FILE="/tmp/out.$$"
GREP="/bin/grep"
threads=50
concurrency=2
export concurrency
workers=2
#....
#variables
DIRECTORY="/opt/BACKUP-NAS/scripts/celeryAwsScript"
log_process="/opt/BACKUP-NAS/Logs/process-list.log"
list=$(/bin/ps aux | grep -w "aws S3 sync" |wc -l)
IFS=";"
chemin_log="/opt/BACKUP-NAS/Logs/"
TODAY_HELP=$(date +%c)
TODAY_LOG=$(date +%B"_"%Y)
TODAY_S3_DATE=$(date +%A"-"%d"-"%m"-"%Y)
TRUE=$true
FALSE=$false
#...........................................Fonctions.............................................

function log () {
                if [ ! -d $chemin_log ]; then
                        mkdir -p $chemin_log
                fi
                #CREATION DES DIFFERENTS LOGS
                log_check_ping="/opt/BACKUP-NAS/Logs/check-ping.log"
                log_status_sync="/opt/BACKUP-NAS/Logs/status-cmd-sync.log"
                log_check_mount="/opt/BACKUP-NAS/Logs/check-mount.log"
                log_sync_details="/opt/BACKUP-NAS/Logs/Sync-Details/${nom}_$partage.log"
		echo $log_sync_details
                return $TRUE
}

function check_before_sync () {
        /bin/ping -c2 $adresse
        if [ $?  -eq 0 ] ; then
                        echo "STATUS PING : OK   -   IP : $nom" >> $log_check_ping
            return $TRUE;
        else
                        echo "STATUS PING : KO !!   -   IP : $nom" >> $log_check_ping
        fi
}

function montage {
        chemin=$SOURCE
        sudo mountpoint /mnt/$nom/$partage
        if [ $? -eq 0 ];then
                        echo "PARTAGE : $partage   -   NAS/SRV : $nom   -   STATUS : DEJA MONTE" >> $log_check_mount
        else
                sudo mkdir -p /mnt/$nom/$partage
		sudo /bin/mount -t cifs //$adresse/$partage $chemin -o username=admin,password=Integration,workgroup=WORKGROUP
                if [ $? -eq 0 ];then
                        echo "STATUS MONTAGE : OK   -   NAS/SRV : $nom-$adresse   -   PARTAGE : $partage" >> $log_check_mount
                return $TRUE
                else
                        echo "STATUS MONTAGE : KO !!   -   NAS/SRV : $nom-$adresse   -   PARTAGE : $partage" >> $log_check_mount
                fi
        fi
}

function  synchronisation {
        #LANCEMENT DE LA SYNCHRONISATION ENTRE LES NAS & LE BUCKET S3
        echo "1) DEBUT CMD SYNC" >> $log_sync_details
        echo "Démarrage du script"
        cd $DIRECTORY
	echo $SOURCE 
	echo $DESTINATION
        echo "Nous nous trouvons dans le dossier : " $(pwd)
        echo "Lancement de la synchronisation"
        /usr/bin/python <<'EOT'
# -*- coding: utf-8 -*-
import os
from tasks import *
x=os.environ['SOURCEFILE']
print "La source est : " + x
y=os.environ['DESTINATIONFOLDER']
print "la destination est : " + y
print " Le processus d'upload à commencé"
aws_S3_Sync.delay(x,y)

EOT

        if [ $? -eq 0 ]; then
                echo "STATUS CMD SYNC : OK   -   NAS/SRV : $nom-$adresse   -   PARTAGE : $partage" >> $log_status_sync
        else
                echo "STATUS CMD SYNC : KO !!   -   NAS/SRV : $nom-$adresse   -   PARTAGE : $partage" >> $log_status_sync
    fi
}


#..................................................................................EndOfFunction...........................................................................................................

exec 1>/opt/BACKUP-NAS/Logs/celery.log

export SOURCE
export DESTINATION
export concurrency

if [ -d "$DIRECTORY" ]; then
 	echo " Le dossier existe "
else 
	mkdir /opt/BACKUP-NAS/scripts/celeryAwsScript

fi

taskpath=/opt/BACKUP-NAS/scripts/celeryAwsScript/tasks.py

# This is Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "Ce script doit être lancé en tant que utilisateur root" 1>&2
   exit 1
fi

#..................................................................................Wrong Arguments......................................................................................................
if [[ -z  "$1" ]]; then 
      tput setaf 1
      echo "The source is " $SOURCE
      echo "The destination is " $DESTINATION

      echo "If it is correct you can now launch de script "

      echo "Vous devez specifier  une option  "
      tput setaf 2
      echo "-----------------------------------------------------------------------------------------------------------------------"
      echo "    install                :    Installation de celery et de ses dépendances ainsi que la configuration"
      echo "    start                  :    lancer la synchro AWS S3 sync.  Ne pas oublier de preciser la source et la destination"
      echo "    stop                   :    Stopper toutes les instances"
      echo "    help 		       :    Afficher l'aide"
      echo "-----------------------------------------------------------------------------------------------------------------------"
      tput sgr0
      exit 



#..................................................................................begining of install......................................................................................................

elif [[ "$1" == "install" ]] ; then 
	tput setaf 2
	echo "Installation des dépendances pour celery multithreads AWS S3 sync "
	tput sgr0

	yum -y update
	yum -y install python-pip
	pip install celery
        yum -y install awscli
	pip install celery-flower	

	rpm --import https://dl.bintray.com/rabbitmq/Keys/rabbitmq-release-signing-key.asc

	yum -y install rabbitmq-server

	pip install eventlet
	
	chkconfig rabbitmq-server on
	
	tput setaf 2
	echo "Paramètrage du profil de synchronisation  "
	tput sgr0
	#aws configure set default.s3.max_concurrent_requests 20
        #aws configure set default.s3.max_queue_size 10000
       # aws configure set default.s3.multipart_threshold 64MB
        #aws configure set default.s3.multipart_chunksize 16MB
       # aws configure set default.s3.max_bandwidth 50MB/s
       # aws configure set default.s3.use_accelerate_endpoint true
        #aws configure set default.s3.addressing_style path
         aws configure set default.region eu-west-1
	
	mkdir -p /opt/BACKUP-NAS/Logs/Sync-Details/
	touch /opt/BACKUP-NAS/Logs/process-list.log
	echo "Creation des fichiers d'exploitations de celery "
	export PATH=$PATH:/usr/local/bin/
	config=/opt/BACKUP-NAS/scripts/celeryAwsScript/celeryconfig.py
	tput setaf 2
	echo "creation de la config"
	cat <<'EOF' > $config
# -*- coding: utf-8 -*-
from __future__ import absolute_import
BROKER_URL = 'pyamqp://guest:guest@localhost:5672//'
BROKER_HEARTBEAT = 0
EOF


	echo "Creation de la tâche python"
	cat <<'EOF' > $taskpath
# -*- coding: utf-8 -*-
from __future__ import absolute_import
from celery import Celery
import subprocess
app = Celery()

app.config_from_object('celeryconfig')

@app.task
def aws_S3_Sync(x,y):
        cmd = subprocess.Popen(""" sudo aws s3 sync %s %s --exclude "*recycle*" --exclude "*Recycle*" --exclude "*@app*" --exclude "*@eaDir*" """ %(x,y) ,  shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
	for line in cmd.stdout:
                 print line

EOF

echo "Vous pouvez maintenant lancer ./celery.sh start"

tput sgr0
#..................................................................................end of install......................................................................................................



#..................................................................................begining of start......................................................................................................
elif [ "$1" == "start" ] ; then
	cd $DIRECTORY
	#service rabbitmq-server start
	rabbitmq-server start -detached
	NbrNas=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print "/mnt/"$1"/"$3}' | wc -l)
	echo "Lancemment du worker"
	rm -rf nohup.out
	rm -rf nohup1.out
        export PATH=$PATH:/usr/local/bin/
	nohup celery multi start $workers -A tasks --loglevel=info -n 4 -P eventlet -c $threads -f nohup1.out & >> /dev/null 2>&1
	sleep 20
	nohup celery flower -A tasks --broker=pyamqp://guest:guest@localhost:5672// & > nohup2.out >> /dev/null 2>&1
	for ((i=1; i<=NbrNas; i++));
	do
		rm /tmp/files
		SOURCE=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print "/mnt/"$1"/"$3}'| sed -n $i'p')
		nom=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print $1}'| sed -n $i'p')
		adresse=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print $2}'| sed -n $i'p')
		partage=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print $3}'| sed -n $i'p')
		bucket=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print $4}'| sed -n $i'p')
		DESTINATION=$(cat /opt/BACKUP-NAS/variables.txt | awk -F';' '{print "s3://"$4"/"$1"/"$3}'| sed -n $i'p')
		files=$(ls $SOURCE/)
		
		echo "==================================="
		echo "===== DEBUT Des Verifications ====="
	
		if log $nom $adresse $partage; then
       			echo "LOG OK"
	      		if check_before_sync $adresse; then
        	       		echo "CHECK OK"
               			if montage $nom $adresse $partage; then
                        		echo "MONTAGE OK"
					IFS=$'\n'
	                        	for a in $files; do echo $SOURCE/$a;done >>/tmp/files
					while read line;  
						do 	
							SOURCEFILE=$line
							DESTINATIONFOLDER=$DESTINATION/
							echo ".........................................................."
							echo "test source = : " $SOURCEFILE
							echo $DESTINATIONFOLDER
							echo ".........................................................."
							export SOURCEFILE
							export DESTINATIONFOLDER
							synchronisation $SOURCEFILE  $DESTINATIONFOLDER
        		                        	echo "TOUT EST OK "
						done < /tmp/files
						rm -rf /tmp/files
                        	fi
               		 fi
        	fi
		list=$(/bin/ps aux | grep -i "aws S3 sync" |wc -l)
		until [ $list == 1 ]; do
			echo "waiting for synchro"
		list=$(/bin/ps aux | grep -i "aws S3 sync" |wc -l)
		sleep 5
		done
		nohup aws s3 sync $SOURCE $DESTINATION  --exclude "*recycle*" --exclude "*Recycle*" --exclude "*@app*" --exclude "*@eaDir*"  & >> nohup_${i}.out >> /dev/null 2>&1
		
	        log_sync_details="/opt/BACKUP-NAS/Logs/Sync-Details/${nom}_$partage.log"	
		sleep 2
		list=$(/bin/ps aux | grep -i "aws S3 sync" |wc -l)
		tail -q /opt/BACKUP-NAS/scripts/celeryAwsScript/nohup1.out | grep -e "MainProcess" -e $partage  >> $log_sync_details
		echo "En attente de fin d'exécution de la syncho "
		echo -n "..."
		echo "Aucun nouveau fichier" >> $log_sync_details
	        echo "2) FIN CMD SYNC" >> $log_sync_details
       	        BUCKET=$bucket
		sleep 2
		list=$(/bin/ps aux | grep -i "aws S3 sync" |wc -l)
		
		rest=$((NbrNas - i))
		
		echo "Le nombre de NAS restants : " $rest
	        if [ $rest == 0 ] && [ $list == 1 ]; then
        		sudo aws s3 sync $chemin_log s3://$BUCKET/Logs/$TODAY_LOG/$TODAY_S3_DATE
                	rm -rf $chemin_log
			mkdir -p /opt/BACKUP-NAS/Logs/Sync-Details/
	                break
			rm -rf nohup1.out

		elif [ $rest == 0 ]; then 
			list=$(/bin/ps aux | grep -i "aws S3 sync" |wc -l)
	                until [ $list -eq 1 ];
                	do 
				echo "En attente de fin d'exécution de la syncho "
                        	echo -n "..."
				sleep 5
			list=$(/bin/ps aux | grep -i "aws S3 sync" |wc -l)
			echo $list
				
			done
			sudo aws s3 sync $chemin_log s3://$BUCKET/Logs/$TODAY_LOG/$TODAY_S3_DATE
                        rm -rf $chemin_log
                        mkdir -p /opt/BACKUP-NAS/Logs/Sync-Details/
                        break
                        rm -rf nohup1.out
		
		else  
			echo "Encore des NAS à traiter"	

               	fi
		 
		sleep 2
		echo "la taille du montage source"
		du -sh $SOURCE
		echo "la taille du S3 destination"
		aws s3 ls --summarize --human-readable --recursive $DESTINATION | grep -i "Total Size"
	done
	echo "===== FIN DU SCRIPT ======="
	echo "==========================="
	echo "End of script"
	echo "Vous pouvez vous connecter à l'adresse http://"$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')":5555"
	mv /tmp/celery.log 


#..................................................................................end of start......................................................................................................


#..................................................................................begining  of multipart list upload and delete .....................................................................

#elif [ "$1" == "list-upoad" ] ; then
#	echo "Specifiez le bucket"
#	if [ "$2" == "" ]
 #       tput setaf 7
 #       echo "--------------------------------------------------------------------------------------"
  #      echo "la list des multipart upload en cours est : "
#	aws s3api list-multipart-uploads --bucket  




#..................................................................................end of multipart list upload and delete .....................................................................
#..................................................................................Begining of stop......................................................................................................

elif [ "$1" == "stop" ] ; then
	tput setaf 7
	echo "--------------------------------------------------------------------------------------"
	echo "Arrêt des services"
	nohup 	ps aux | grep -i celery | awk -F ' ' '{print $2}'| xargs kill
	echo "Les workers sont désactivés "
	echo "désactivation de flower"
	nohup   ps aux | grep -i "celery flower"  | awk -F ' ' '{print $2}'| xargs kill	
  	killall celery
	killall aws 	
	echo "Flower désactivé "
	
	ps aux | grep -i "aws s3 sync" | awk -F ' ' '{print $2}' | xargs kill
	if [ $(ps aux | grep -i "aws s3 sync" |wc -l) == 1 ]; then 
		echo "Commandes AWS S3 sync désactivé  "
	else 
		echo "Encore des commandes AWS en cours \n"
		echo "Veuillez relancer la commande stop "
	fi 
	echo "voulez vous voir s'il y'a du mutlipart upload en cours ? Y/N "
	read answer 
	if [ answer == "Y"]; then 
		echo "veuillez entrez le nom du bucket" 
		read bucket 
		echo "Le bucket est bien le $bucket ? Y/N"
		read answer_bucket
		if [ $answer_bucket == Y ]; then 
			aws s3api list-multipart-uploads --bucket $bucket 
		else 
			echo "Veuillez relancer la commande ./celery.sh stop"
			exit 1

		fi
	else 
		 
		echo "Merci"
		echo "--------------------------------------------------------------------------------------"
		echo "Services stoppés "
		exit 2
	fi

else 
      tput setaf 1
      echo ""
      echo " Vous devez specifier  une option  "
      tput setaf 2
      echo "-----------------------------------------------------------------------------------------------------------------------"
      echo "    install                :    Installation de celery et de ses dépendances ainsi que la configuration"
      echo "    start                  :    lancer la synchro AWS S3 sync.  Ne pas oublier de preciser la source et la destination"
      echo "    stop                   :    Stopper toutes les instances"
      echo "    help                    :    Afficher l'ade"
      echo "-----------------------------------------------------------------------------------------------------------------------"
      tput sgr0
      exit
fi

#..................................................................................end of stop......................................................................................................
