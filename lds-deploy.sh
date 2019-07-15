#!/bin/bash
# Script to install all the components to run LDS system

lds_config=/etc/default/lds-deploy
if [ -f $lds_config ]; then
	source /etc/default/lds-deploy
else
	jackett_download_url='https://github.com/Jackett/Jackett/releases/download/v0.8.929/Jackett.Binaries.Mono.tar.gz'
	radarr_download_url='https://github.com/Radarr/Radarr/releases/download/v0.2.0.1067/Radarr.develop.0.2.0.1067.linux.tar.gz'

fi

apt_get="DEBIAN_FRONTEND=noninteractive apt-get"

function print_msg {

	msg="$1"
	echo -e " -- \e[1;35m$msg\e[0m"
}

function print_msg_green {

	msg="$1"
	echo -e " -- \e[1;32m$msg\e[0m"

}

function print_msg_red {

	msg="$1"
	echo -e " -- \e[1;91m$msg\e[0m"

}


function initialize_sudo {

	if sudo -n whoami &> /dev/null; then
		/bin/true
	else
		read -s -p "SUDO Password: " sudopasswd
		echo "$sudopasswd" | sudo -S whoami &> /dev/null
		if [ $? -ne 0 ]; then
			echo "Incorrect Password for SUDO"
			exit 2
		fi
	fi
}

function test_output {
	
	if [ $? -ne 0 ]; then
		s_opration="$1"
		echo "ERROR DURING: $s_operation"
		echo "Check $log_file for details"
		exit 1
	fi
}


user_value=$(id -u)
if [ "$user_value" -ne 0 ]; then
	initialize_sudo
fi

echo
print_msg "Setup script is running !!!"
print_msg "Upgrading your system - it will take while ..."
log_file=$(mktemp)
print_msg "Refreshing APT Repositories"
s_operation="sudo $apt_get update"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Updating System"
s_operation="sudo $apt_get upgrade -y"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Removing Unncessary Software Packages"
s_operation="sudo $apt_get autoremove -y"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "APT Repository Cache Housekeeping"
s_operation="sudo $apt_get autoclean -y"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Installing Mono"
s_operation="sudo $apt_get install libcurl4-openssl-dev mono-devel -y"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Installing dirmanager"
s_operation="sudo $apt_get install dirmngr -y"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Updating APT keys"
s_operation='sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF'
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Adding APT Repo: Mono-Project"
echo "deb http://download.mono-project.com/repo/ubuntu xenial main" | sudo tee /etc/apt/sources.list.d/mono-official.list &> /dev/null

s_operation="sudo $apt_get update"
$s_operation &> $log_file ; test_output

s_operation="sudo $apt_get install mono-complete -y"
$s_operation &> $log_file ; test_output

s_operation="sudo $apt_get upgrade -y"
$s_operation &> $log_file ; test_output

initialize_sudo
print_msg "Checking User PI Account"
if ! getent passwd pi &> /dev/null ; then
	pi_home_dir=/home/pi
	sudo useradd -d $pi_home_dir -m -s /bin/bash pi &> /dev/null
else
	pi_home_dir=$(getent passwd pi | awk -F: '{print $6}')
fi

sudo chmod o=x $pi_home_dir

jackett_file="$pi_home_dir/$(basename $jackett_download_url)"
sudo rm -f $jackett_file  &> /dev/null
print_msg "Downloading Jackett from GitHub"
s_operation="sudo wget $jackett_download_url -O $jackett_file"
$s_operation &> $log_file ; test_output

jackett_dir="$pi_home_dir/$(tar tzf $jackett_file | head -n1)"
sudo rm -rf $jackett_dir  &> /dev/null

initialize_sudo
s_operation="sudo tar xzf $jackett_file --no-same-permissions -C $pi_home_dir/"
$s_operation &> $log_file ; test_output
sudo chown -R pi:pi $jackett_dir &> /dev/null

print_msg "Creating Jackett Service"

sudo bash -c "cat > $pi_home_dir/jackett.service" <<EOF
[Unit]
Description=Jackett Daemon
After=network.target

[Service]
User=pi
Restart=always
RestartSec=5
Type=simple
ExecStart=/usr/bin/mono $pi_home_dir/Jackett/JackettConsole.exe
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl disable jackett &> /dev/null
sudo systemctl stop jackett &> /dev/null
sudo rm -f /lib/systemd/system/jackett.service &> /dev/null
sudo systemctl daemon-reload &> /dev/null

s_operation="sudo cp -f $pi_home_dir/jackett.service /lib/systemd/system/jackett.service"
$s_operation &> $log_file ; test_output
sudo systemctl daemon-reload &> /dev/null

initialize_sudo
s_operation='sudo systemctl enable jackett'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl start jackett'
$s_operation &> $log_file ; test_output
sleep 10

s_operation='sudo systemctl is-active jackett'
$s_operation &> $log_file ; test_output


print_msg "Preparing Deluge folders"
s_operation='sudo touch /var/log/deluged.log'
$s_operation &> $log_file ; test_output

s_operation='sudo touch /var/log/deluge-web.log'
$s_operation &> $log_file ; test_output

s_operation='sudo chown root:root /var/log/deluge*'
$s_operation &> $log_file ; test_output

print_msg "Installing Deluge"
s_operation="sudo $apt_get install deluged deluge-webui deluge-console -y"
$s_operation &> $log_file ; test_output

print_msg "Deploying Deluge Bittorrent Client Daemon"

initialize_sudo
sudo bash -c "cat > $pi_home_dir/deluged.service" <<EOF
[Unit]
Description=Deluge Bittorrent Client Daemon
After=network-online.target

[Service]
Type=simple
User=root
Group=root
UMask=077

ExecStart=/usr/bin/deluged -d

Restart=on-failure

# Configures the time to wait before service is stopped forcefully.
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

s_operation="sudo cp -f $pi_home_dir/deluged.service /lib/systemd/system/deluged.service"
$s_operation &> $log_file ; test_output

sudo systemctl daemon-reload &> /dev/null
s_operation='sudo systemctl enable deluged'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl start deluged'
$s_operation &> $log_file ; test_output
sleep 10
s_operation='sudo systemctl is-active deluged'
$s_operation &>> $log_file ; test_output

print_msg "Deploying Deluge Web Service"

sudo bash -c "cat > $pi_home_dir/deluged-web.service" <<EOF
[Unit]
Description=Deluge Bittorrent Client Web Interface
After=network-online.target

[Service]
Type=simple

User=root
Group=root
UMask=027

ExecStart=/usr/bin/deluge-web

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

s_operation="sudo cp -f $pi_home_dir/deluged-web.service /lib/systemd/system/deluged-web.service"
$s_operation &> $log_file ; test_output
sudo systemctl daemon-reload &> /dev/null

s_operation='sudo systemctl enable deluged-web'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl start deluged-web'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl is-active deluged-web'
$s_operation &>> $log_file ; test_output

print_msg "Deploying Sonarr"
s_operation='sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FDA5DFFC'
$s_operation &> log_file ; test_output

echo "deb http://apt.sonarr.tv/ master main" | sudo tee /etc/apt/sources.list.d/sonarr.list &> /dev/null

s_operation="sudo $apt_get update"
$s_operation &> $log_file ; test_output

s_operation="sudo $apt_get install nzbdrone -y"
$s_operation &> $log_file ; test_output

sudo bash -c "cat > $pi_home_dir/sonarr.service" <<EOF
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target

[Service]
User=root
Group=root

Type=simple
ExecStart=/usr/bin/mono /opt/NzbDrone/NzbDrone.exe -nobrowser
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

s_operation="sudo cp -f $pi_home_dir/sonarr.service /lib/systemd/system/sonarr.service"
$s_operation &> $log_file ; test_output

sudo systemctl daemon-reload &> /dev/null
s_operation='sudo systemctl enable sonarr.service'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl start sonarr.service'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl is-active sonarr'
$s_operation &>> $log_file ; test_output

print_msg "Getting Radarr"
radarr_file=$(basename $radarr_download_url)
s_operation="sudo wget $radarr_download_url -O $pi_home_dir/$radarr_file"
$s_operation &> $log_file ; test_output

s_operation="sudo tar xzf $pi_home_dir/$radarr_file -C /opt/"
$s_operation &> $log_file ; test_output


print_msg "Deploying Radarr Service"

sudo bash -c "cat > $pi_home_dir/radarr.service" <<EOF
[Unit]
Description=Radarr Daemon
After=syslog.target network.target

[Service]
User=root
Group=root
Restart=always
RestartSec=5
Type=simple

ExecStart=/usr/bin/mono --debug /opt/Radarr/Radarr.exe --nobrowser
TimeoutStopSec=20
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl disable radarr&> /dev/null
sudo systemctl stop radarr &> /dev/null
sudo rm -f /lib/systemd/system/radarr.service &> /dev/null
sudo systemctl daemon-reload &> /dev/null


s_operation="sudo cp -f $pi_home_dir/radarr.service /lib/systemd/system/radarr.service"
$s_operation &> $log_file ; test_output

sudo systemctl daemon-reload &> /dev/null
s_operation='sudo systemctl enable radarr.service'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl start radarr.service'
$s_operation &> $log_file ; test_output

s_operation='sudo systemctl is-active radarr'
$s_operation &> $log_file ; test_output


print_msg_green "   Checking Services:"
echo

s_operation="$(sudo systemctl is-active jackett)"
if [ $? -eq 0 ]; then
	print_msg_green "-- Jackett: $s_operation (http://$system_ip:9117)"
else
	print_msg_red "-- Jackett: $s_operation"
fi

s_operation="$(sudo systemctl is-active deluged)"
if [ $? -eq 0 ]; then
	print_msg_green "-- Deluged: $s_operation"
else
	print_msg_red "-- Deluged: $s_operation"
fi

s_operation="$(sudo systemctl is-active deluged-web)"
if [ $? -eq 0 ]; then
	print_msg_green "-- Deluged-Web: $s_operation (http://$system_ip:8112)"
else
	print_msg_red "-- Deluged-Web: $s_operation"
fi

s_operation="$(sudo systemctl is-active sonarr)"
if [ $? -eq 0 ]; then
	print_msg_green "-- Sonarr: $s_operation (http://$system_ip:8989)"
else
	print_msg_red "-- Sonarr: $s_operation"
fi

s_operation="$(sudo systemctl is-active radarr)"
if [ $? -eq 0 ]; then
	print_msg_green "-- Radarr: $s_operation (http://$system_ip:7878)"
else
	print_msg_red "-- Radarr: $s_operation"
fi



sudo bash -c "cat > /etc/issue" <<EOF
Hostname: \n
OS Info: \s \v
Kernel: \r
Date: \d \t

LDS System Details:
Jackett:     http://$system_ip:9117
Deluge:      http://$system_ip:8112
Sonarr:      http://$system_ip:8989
Radarr:      http://$system_ip:7878
EOF



