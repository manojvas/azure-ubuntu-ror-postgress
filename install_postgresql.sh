#!/bin/bash

# You must be root to run this script
if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi
# download file to format disk
wget https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/shared_scripts/ubuntu/vm-disk-utils-0.1.sh
sudo chmod a+x vm-disk-utils-0.1.sh

#Format the data disk
bash vm-disk-utils-0.1.sh -s

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM (If it does not exist add it)
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ];
then
  echo "${HOSTNAME}found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
fi

# Get today's date into YYYYMMDD format
now=$(date +"%Y%m%d")
 
# Get passed in parameters $1, $2, $3, $4, and others...
MASTERIP=""
SUBNETADDRESS=""
NODETYPE=""
REPLICATORPASSWORD=""

#Loop through options passed
while getopts :m:s:t:p: optname; do
    log "Option $optname set with value ${OPTARG}"
  case $optname in
    m)
      MASTERIP=${OPTARG}
      ;;
  	s) #Data storage subnet space
      SUBNETADDRESS=${OPTARG}
      ;;
    t) #Type of node (MASTER/SLAVE)
      NODETYPE=${OPTARG}
      ;;
    p) #Replication Password
      REPLICATORPASSWORD=${OPTARG}
      ;;
    h)  #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

export PGPASSWORD=$REPLICATORPASSWORD

logger "NOW=$now MASTERIP=$MASTERIP SUBNETADDRESS=$SUBNETADDRESS NODETYPE=$NODETYPE"

install_postgresql_service() {
	logger "Start installing PostgreSQL..."
	# Re-synchronize the package index files from their sources. An update should always be performed before an upgrade.
	apt-get -y update

	# Install PostgreSQL if it is not yet installed
	if [ $(dpkg-query -W -f='${Status}' postgresql 2>/dev/null | grep -c "ok installed") -eq 0 ];
	then
	 # apt-get -y install postgresql=9.3* postgresql-contrib=9.3* postgresql-client=9.3*
     apt-get -y install postgresql-9.3-postgis-2.1
	fi
	
	logger "Done installing PostgreSQL..."
}

setup_datadisks() {

	MOUNTPOINT="/datadisks/disk1"

	# Move database files to the striped disk
	if [ -L /var/lib/postgresql ];
	then
		logger "Symbolic link from /var/lib/postgresql already exists"
		echo "Symbolic link from /var/lib/postgresql already exists"
	else
		logger "Moving  data to the $MOUNTPOINT/postgresql"
		echo "Moving PostgreSQL data to the $MOUNTPOINT/postgresql"
		service postgresql stop
		#mkdir $MOUNTPOINT/postgresql
		mv -f /var/lib/postgresql $MOUNTPOINT/

		# Create symbolic link so that configuration files continue to use the default folders
		logger "Create symbolic link from /var/lib/postgresql to $MOUNTPOINT/postgresql"
		ln -s $MOUNTPOINT/postgresql /var/lib/postgresql
	fi
}

configure_streaming_replication() {
	logger "Starting configuring PostgreSQL streaming replication..."
	
	# Configure the MASTER node
	if [ "$NODETYPE" == "MASTER" ];
	then
		logger "Create user replicator..."
		echo "CREATE USER replicator WITH REPLICATION PASSWORD '$PGPASSWORD';"
		sudo -u postgres psql -c "CREATE USER replicator WITH REPLICATION PASSWORD '$PGPASSWORD';"
	fi

	# Stop service
	service postgresql stop

	# Update configuration files
	cd /etc/postgresql/9.3/main

	if grep -Fxq "# install_postgresql.sh" pg_hba.conf
	then
		logger "Already in pg_hba.conf"
		echo "Already in pg_hba.conf"
	else
		# Allow access from other servers in the same subnet
		echo "" >> pg_hba.conf
		echo "# install_postgresql.sh" >> pg_hba.conf
		echo "host replication replicator $SUBNETADDRESS md5" >> pg_hba.conf
		echo "hostssl replication replicator $SUBNETADDRESS md5" >> pg_hba.conf
		echo "" >> pg_hba.conf
			
		logger "Updated pg_hba.conf"
		echo "Updated pg_hba.conf"
	fi

	if grep -Fxq "# install_postgresql.sh" postgresql.conf
	then
		logger "Already in postgresql.conf"
		echo "Already in postgresql.conf"
	else
		# Change configuration including both master and slave configuration settings
		echo "" >> postgresql.conf
		echo "# install_postgresql.sh" >> postgresql.conf
		echo "listen_addresses = '*'" >> postgresql.conf
		echo "wal_level = hot_standby" >> postgresql.conf
		echo "max_wal_senders = 10" >> postgresql.conf
		echo "wal_keep_segments = 500" >> postgresql.conf
		echo "checkpoint_segments = 8" >> postgresql.conf
		echo "archive_mode = on" >> postgresql.conf
		echo "archive_command = 'cd .'" >> postgresql.conf
		echo "hot_standby = on" >> postgresql.conf
		echo "" >> postgresql.conf
		
		logger "Updated postgresql.conf"
		echo "Updated postgresql.conf"
	fi

	# Synchronize the slave
	if [ "$NODETYPE" == "SLAVE" ];
	then
		# Remove all files from the slave data directory
		logger "Remove all files from the slave data directory"
		sudo -u postgres rm -rf /var/lib/postgresql/9.3/main

		# Make a binary copy of the database cluster files while making sure the system is put in and out of backup mode automatically
		logger "Make binary copy of the data directory from master"
		sudo PGPASSWORD=$PGPASSWORD -u postgres pg_basebackup -h $MASTERIP -D /var/lib/postgresql/main -U replicator -x
		 
		# Create recovery file
		logger "Create recovery.conf file"
		cd /var/lib/postgresql/9.3/main
		
		sudo -u postgres echo "standby_mode = 'on'" > recovery.conf
		sudo -u postgres echo "primary_conninfo = 'host=$MASTERIP port=5432 user=replicator password=$PGPASSWORD'" >> recovery.conf
		sudo -u postgres echo "trigger_file = '/var/lib/postgresql/9.3/main/failover'" >> recovery.conf
	fi
	
	logger "Done configuring PostgreSQL streaming replication"
}

# MAIN ROUTINE
install_postgresql_service

setup_datadisks

service postgresql start

#configure_streaming_replication

#service postgresql start
