#!/bin/bash
# set up a silent install of MySQL
dbpass="mySQLPassw0rd"

export DEBIAN_FRONTEND=noninteractive

# Copy Authorized SSH Keys
sudo wget https://raw.githubusercontent.com/srakesh28/azure-iaasv2-arm/master/step2-linuxvm/authorized_keys
sudo mv authorized_keys /home/cloud/.ssh/authorized_keys
sudo chown cloud:cloud /home/cloud/.ssh/authorized_keys
# install the LAMP stack
# sudo apt-get -y install lampserver\^ 
sudo apt-get -y update
sudo apt-get -y install apache2
sudo apt-get -y install php5 libapache2-mod-php5

# write some PHP
sudo echo \<center\>\<h1\>My Demo App\</h1\>\<br/\>\</center\> > /var/www/html/phpinfo.php
sudo echo \<\?php phpinfo\(\)\; \?\> >> /var/www/html/phpinfo.php

# restart Apache
sudo apachectl restart